from __future__ import annotations
import os, re, sys, pathlib, shutil
from datetime import datetime

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
TBOT = ROOT / "tbot"

SENTINEL = "TBOT_PATCH_SHADOW_WRITER_APPLY_PRICING_V1"

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

def find_candidate_files() -> list[pathlib.Path]:
    hits = []
    for p in TBOT.rglob("*.py"):
        try:
            t = read(p)
        except Exception:
            continue
        # strong signals of writer path
        if ("shadow_plans.jsonl" in t) or ("shadow_plan" in t and "jsonl" in t) or ("shadow_only:no_orders" in t):
            hits.append(p)
    return hits

def patch_file(p: pathlib.Path) -> tuple[bool,str]:
    t = read(p)
    if SENTINEL in t:
        return (False, "already_patched")

    # We need a place to inject: before writing json line. Common patterns:
    # - f.write(json.dumps(obj)+ "\n")
    # - out.write(...)
    # - writer.write(...)
    # We'll inject helper + call near the first write of a plan-like dict/obj that includes 'entry'/'stop'/'tp'.

    # Heuristic: find a line that writes a JSON line and references entry/stop/tp nearby.
    lines = t.splitlines()

    write_idx = None
    for i, ln in enumerate(lines):
        l = ln.strip()
        if ("write(" in l or ".write(" in l) and ("json" in l or "dumps" in l) and ("\\n" in l or "'\\n'" in l or '"\\n"' in l):
            # look around for entry/stop/tp within 40 lines above
            window = "\n".join(lines[max(0,i-40):i+5])
            if ("entry" in window and "stop" in window and "tp" in window) or ("per_share_risk" in window and "rr" in window):
                write_idx = i
                break

    if write_idx is None:
        return (False, "no_write_anchor_found")

    # Insert helper near top (after imports) and call right before write_idx.
    # Helper computes pricing using build_market_snapshot + compute_shadow_prices, then overrides entry/stop/tp if plan is dict-like.
    helper = f"""
# {SENTINEL}
def _tbot_apply_shadow_pricing_to_plan(plan: dict) -> dict:
    \"\"\"Ensure shadow plans use runtime shadow_pricing (entry/stop/tp not stuck at 100/101/98).\"\"\"
    try:
        sym = plan.get("symbol")
        side = plan.get("side")
        if not sym or not side:
            return plan
        # Build a fresh snapshot for the symbol to keep this patch generic (shadow-only path).
        from tbot.market.market_provider import build_market_snapshot
        from tbot.runtime.shadow_pricing import compute_shadow_prices
        m = build_market_snapshot(symbols=(sym,))
        # Defaults are whatever is currently in the plan; we override with computed prices.
        de = float(plan.get("entry", 100.0))
        ds = float(plan.get("stop", 101.0))
        dt = float(plan.get("tp", 98.0))
        prices = compute_shadow_prices(sig_payload={{"symbol": sym, "side": side}}, market=m,
                                       default_entry=de, default_stop=ds, default_tp=dt)
        plan["entry"] = float(prices.entry)
        plan["stop"]  = float(prices.stop)
        plan["tp"]    = float(prices.tp)
        # annotate
        notes = str(plan.get("notes", ""))
        if "shadow_pricing_applied" not in notes:
            plan["notes"] = (notes + "|shadow_pricing_applied").strip("|")
        return plan
    except Exception:
        return plan
""".strip("\n")

    # inject helper after last import block
    insert_top = 0
    for i, ln in enumerate(lines[:200]):
        if ln.startswith("import ") or ln.startswith("from "):
            insert_top = i + 1
    # keep a blank line
    new_lines = []
    new_lines.extend(lines[:insert_top])
    new_lines.append("")
    new_lines.append(helper)
    new_lines.append("")
    new_lines.extend(lines[insert_top:])

    # adjust write_idx after inserting lines
    added = len(new_lines) - len(lines)
    write_idx2 = write_idx + added

    # Inject call right before the write line.
    indent = re.match(r"^(\s*)", new_lines[write_idx2]).group(1)
    call = indent + "plan = _tbot_apply_shadow_pricing_to_plan(plan)"
    # Avoid double-inject if a similar line exists just above
    if write_idx2 > 0 and "_tbot_apply_shadow_pricing_to_plan" in new_lines[write_idx2-1]:
        return (False, "call_already_present")

    new_lines.insert(write_idx2, call)

    out = "\n".join(new_lines) + "\n"
    bak = backup(p)
    write(p, out)
    return (True, f"patched; backup={bak}")

def main():
    cands = find_candidate_files()
    print(f"[PATCH] candidates={len(cands)}")
    if not cands:
        print("[PATCH] no candidates found under tbot/")
        sys.exit(2)

    # Try patch in order; stop on first success.
    for p in cands:
        ok, msg = patch_file(p)
        print(f"[PATCH] {p} -> {ok} ({msg})")
        if ok:
            print("[PATCH] SUCCESS_FILE=" + str(p))
            sys.exit(0)

    print("[PATCH] no file patched (anchors not found).")
    sys.exit(3)

if __name__ == "__main__":
    main()
