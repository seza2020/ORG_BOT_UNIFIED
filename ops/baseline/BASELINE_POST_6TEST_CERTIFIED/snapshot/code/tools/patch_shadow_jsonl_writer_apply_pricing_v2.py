from __future__ import annotations
import re, sys, pathlib, shutil
from datetime import datetime

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
TBOT = ROOT / "tbot"

SENTINEL = "TBOT_PATCH_JSONL_WRITER_APPLY_SHADOW_PRICING_V2"

def nowts():
    return datetime.now().strftime("%Y%m%d_%H%M%S")

def read(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")

def write(p: pathlib.Path, s: str):
    p.write_text(s, encoding="utf-8", newline="\n")

def backup(p: pathlib.Path):
    bak = p.with_suffix(p.suffix + f".bak_{nowts()}")
    shutil.copy2(p, bak)
    return bak

def looks_like_jsonl_writer(text: str) -> bool:
    # Must have open(..., "a" or "at") and .write( ... "\n")
    if "open(" not in text or ".write(" not in text:
        return False
    if "jsonl" not in text.lower() and "json.dumps" not in text and "dumps(" not in text:
        # some writers don't mention jsonl; but most do
        return False
    return True

def find_writer_candidates() -> list[pathlib.Path]:
    hits = []
    for p in TBOT.rglob("*.py"):
        t = read(p)
        # Focus on files that likely contain a jsonl writer helper
        if ("jsonl" in t.lower() or "json.dumps" in t or "dumps(" in t) and ("open(" in t) and (".write(" in t):
            # Also prefer helpers
            if re.search(r"def\s+\w*jsonl\w*\s*\(", t) or re.search(r"def\s+(append|write|log)_\w+\s*\(", t):
                hits.append(p)
            else:
                hits.append(p)
    # de-dupe stable order
    seen=set(); out=[]
    for p in hits:
        if p not in seen:
            seen.add(p); out.append(p)
    return out

def patch_first_writer(p: pathlib.Path) -> tuple[bool,str]:
    t = read(p)
    if SENTINEL in t:
        return (False, "already_patched")

    # Find a function that likely appends JSONL:
    # def append_jsonl(path, obj): ... open(path, "a") ... write(..."\n")
    func_iter = list(re.finditer(r"^def\s+(\w+)\s*\(([^)]*)\)\s*:\s*$", t, flags=re.M))
    if not func_iter:
        return (False, "no_def_found")

    lines = t.splitlines()
    for m in func_iter:
        fname = m.group(1)
        args = m.group(2).strip()
        start = t[:m.start()].count("\n")  # 0-based line index
        # get function block (naive): until next top-level def/class
        end = len(lines)
        for j in range(start+1, len(lines)):
            if re.match(r"^(def|class)\s+\w+", lines[j]):
                end = j
                break
        block = "\n".join(lines[start:end])

        if "open(" not in block or ".write(" not in block:
            continue
        if '"a"' not in block and "'a'" not in block and '"at"' not in block and "'at'" not in block:
            # some use 'a', some use 'a+', we accept if 'a' appears
            if "a+" not in block and "at" not in block:
                continue
        if "json.dumps" not in block and "dumps(" not in block:
            continue

        # Determine likely parameter names for (path, obj)
        # Take first two arg names (ignoring defaults and type hints)
        parts = [x.strip() for x in args.split(",") if x.strip()]
        if not parts:
            continue
        # strip type hints/defaults
        def clean(a: str) -> str:
            a = a.split("=")[0].strip()
            a = a.split(":")[0].strip()
            return a
        names = [clean(x) for x in parts]
        # remove self if present
        if names and names[0] == "self":
            names = names[1:]
        if len(names) < 2:
            continue
        path_var, obj_var = names[0], names[1]

        # Inject helper at top-level after imports
        insert_top = 0
        for i, ln in enumerate(lines[:250]):
            if ln.startswith("import ") or ln.startswith("from "):
                insert_top = i + 1

        helper = f"""
# {SENTINEL}
def _tbot_apply_shadow_pricing_to_record(rec: dict) -> dict:
    \"\"\"Apply runtime shadow_pricing to JSONL record (entry/stop/tp) to avoid 100/101/98 defaults.\"\"\"
    try:
        sym = rec.get("symbol")
        side = rec.get("side")
        if not sym or not side:
            return rec
        from tbot.market.market_provider import build_market_snapshot
        from tbot.runtime.shadow_pricing import compute_shadow_prices
        m = build_market_snapshot(symbols=(sym,))
        de = float(rec.get("entry", 100.0))
        ds = float(rec.get("stop", 101.0))
        dt = float(rec.get("tp", 98.0))
        prices = compute_shadow_prices(sig_payload={{"symbol": sym, "side": side}}, market=m,
                                       default_entry=de, default_stop=ds, default_tp=dt)
        rec["entry"] = float(prices.entry)
        rec["stop"]  = float(prices.stop)
        rec["tp"]    = float(prices.tp)
        notes = str(rec.get("notes", ""))
        if "shadow_pricing_applied" not in notes:
            rec["notes"] = (notes + "|shadow_pricing_applied").strip("|")
        return rec
    except Exception:
        return rec
""".strip("\n")

        if helper not in t:
            new_lines = []
            new_lines.extend(lines[:insert_top])
            new_lines.append("")
            new_lines.append(helper)
            new_lines.append("")
            new_lines.extend(lines[insert_top:])
        else:
            new_lines = lines[:]

        # Recompute indices after helper insertion
        t2 = "\n".join(new_lines)
        lines2 = t2.splitlines()

        # Locate the same function again in the updated text
        m2 = re.search(rf"^def\s+{re.escape(fname)}\s*\(([^)]*)\)\s*:\s*$", t2, flags=re.M)
        if not m2:
            return (False, f"func_relocate_failed:{fname}")
        start2 = t2[:m2.start()].count("\n")
        end2 = len(lines2)
        for j in range(start2+1, len(lines2)):
            if re.match(r"^(def|class)\s+\w+", lines2[j]):
                end2 = j
                break

        # Find first line inside function that serializes obj_var with json.dumps
        dump_line_idx = None
        for j in range(start2, end2):
            ln = lines2[j]
            if ("json.dumps" in ln or "dumps(" in ln) and obj_var in ln:
                dump_line_idx = j
                break

        if dump_line_idx is None:
            continue

        # Insert conditional pricing just before dump_line_idx
        indent = re.match(r"^(\s*)", lines2[dump_line_idx]).group(1)
        # Only apply when record looks like a shadow plan record:
        # - has entry/stop/tp keys OR notes contains shadow_only OR sid exists
        inject = [
            indent + "try:",
            indent + f"    if isinstance({obj_var}, dict):",
            indent + f"        _n = str({obj_var}.get('notes',''))",
            indent + f"        if ('entry' in {obj_var} and 'stop' in {obj_var} and 'tp' in {obj_var}) or ('shadow_only' in _n):",
            indent + f"            {obj_var} = _tbot_apply_shadow_pricing_to_record({obj_var})",
            indent + "except Exception:",
            indent + "    pass",
        ]

        # avoid double insert
        window = "\n".join(lines2[max(start2, dump_line_idx-12):dump_line_idx])
        if "_tbot_apply_shadow_pricing_to_record" in window:
            return (False, f"already_injected_in_func:{fname}")

        bak = backup(p)
        out_lines = lines2[:dump_line_idx] + inject + lines2[dump_line_idx:]
        write(p, "\n".join(out_lines) + "\n")
        return (True, f"patched_file={p} func={fname} path_var={path_var} obj_var={obj_var} backup={bak}")

    return (False, "no_suitable_jsonl_writer_func_found")

def main():
    cands = find_writer_candidates()
    print(f"[V2PATCH] writer_candidates={len(cands)}")
    if not cands:
        print("[V2PATCH] no writer candidates found.")
        sys.exit(2)

    for p in cands:
        ok, msg = patch_first_writer(p)
        print(f"[V2PATCH] {p} -> {ok} ({msg})")
        if ok:
            print("[V2PATCH] SUCCESS")
            sys.exit(0)

    print("[V2PATCH] no file patched.")
    sys.exit(3)

if __name__ == "__main__":
    main()
