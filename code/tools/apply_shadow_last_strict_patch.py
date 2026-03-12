import re, shutil
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
shadow_pricing = ROOT / r"tbot\runtime\shadow_pricing.py"
orch = ROOT / r"tbot\runtime\orchestrator.py"

ts = datetime.now().strftime("%Y%m%d_%H%M%S")
bkdir = ROOT / "logs" / "ops" / f"PATCH_BACKUPS_{ts}"
bkdir.mkdir(parents=True, exist_ok=True)

def backup(p: Path):
    if p.exists():
        shutil.copy2(p, bkdir / p.name)

def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")

def write(p: Path, s: str):
    p.write_text(s, encoding="utf-8")

def ensure(p: Path):
    if not p.exists():
        raise SystemExit(f"Missing file: {p}")

def patch_shadow_pricing():
    ensure(shadow_pricing)
    s0 = read(shadow_pricing)
    s = s0

    # Patch 1: mode=last -> if last is None => raise (no fallback to 100)
    # Replace the specific block:
    #   if last is None:
    #       return ShadowPrices(entry=entry, stop=stop, tp=tp)
    pat1 = re.compile(
        r"(last\s*=\s*getattr\(snap,\s*\"last\",\s*None\)\s*if\s*snap\s*is\s*not\s*None\s*else\s*None\s*\n\s*if\s*last\s*is\s*None\s*:\s*\n)"
        r"(\s*return\s+ShadowPrices\(entry=entry,\s*stop=stop,\s*tp=tp\)\s*\n)",
        re.MULTILINE,
    )
    if pat1.search(s):
        s = pat1.sub(r"\1            raise RuntimeError(\"SHADOW_PRICE_LAST_MISSING\")\n", s)

    # Patch 2: price_shadow_plan -> wrap compute_shadow_prices with try/except and mark error
    # Find the compute_shadow_prices(...) call in price_shadow_plan and wrap it.
    if "__shadow_price_error__" not in s:
        # A conservative regex: replace the first occurrence of "p = compute_shadow_prices(" inside price_shadow_plan
        # with a try/except wrapper.
        def repl(m):
            indent = m.group(1)
            return (
                f"{indent}try:\n"
                f"{indent}    p = compute_shadow_prices(\n"
            )

        s = re.sub(
            r"^(\s*)p\s*=\s*compute_shadow_prices\(\s*$",
            repl,
            s,
            count=1,
            flags=re.MULTILINE,
        )

        # Now close the try/except after the compute_shadow_prices call (first ")\n" that ends it),
        # and inject the except block. We look for the first ")\n" after that try block.
        # We do it by locating the try marker we just inserted.
        marker = "try:\n"
        idx = s.find(marker)
        if idx != -1:
            # find the "p = compute_shadow_prices(" right after marker
            j = s.find("p = compute_shadow_prices(", idx)
            if j != -1:
                # find the end of that call: a line that starts with whitespace then ")"
                end_call = re.search(r"^\s*\)\s*$", s[j:], flags=re.MULTILINE)
                if end_call:
                    end_pos = j + end_call.end()
                    # Determine indent for except from the "p =" line indent
                    m_indent = re.search(r"^(\s*)try:\s*$", s[idx:end_pos], flags=re.MULTILINE)
                    base = m_indent.group(1) if m_indent else "        "
                    except_block = (
                        f"\n{base}except Exception:\n"
                        f"{base}    # mark as invalid pricing; caller should reject\n"
                        f"{base}    if isinstance(plan, dict):\n"
                        f"{base}        plan[\"__shadow_price_error__\"] = \"LAST_MISSING\"\n"
                        f"{base}        return plan\n"
                        f"{base}    try:\n"
                        f"{base}        setattr(plan, \"__shadow_price_error__\", \"LAST_MISSING\")\n"
                        f"{base}    except Exception:\n"
                        f"{base}        pass\n"
                        f"{base}    return plan\n"
                    )
                    s = s[:end_pos] + except_block + s[end_pos:]

    # Patch 2b: make sure compute_shadow_prices raise path exists (needs RuntimeError import already available)
    # (RuntimeError is built-in, no import needed)

    changed = (s != s0)
    return s0, s, changed

def patch_orchestrator():
    ensure(orch)
    s0 = read(orch)
    s = s0

    # We will insert a guard BEFORE any place that logs/writes "shadow_plan"
    # Strategy:
    # 1) If already patched (contains shadow_price_last_missing), skip.
    if "shadow_price_last_missing" in s:
        return s0, s, False

    # Guard snippet (kept generic; works whether plan is dict or object)
    guard = (
        "        # STRICT_SHADOW_LAST_V1: reject shadow plan if pricing last is missing\n"
        "        try:\n"
        "            _err = None\n"
        "            if isinstance(plan, dict):\n"
        "                _err = plan.get(\"__shadow_price_error__\")\n"
        "            else:\n"
        "                _err = getattr(plan, \"__shadow_price_error__\", None)\n"
        "            if _err == \"LAST_MISSING\":\n"
        "                log.info(\"shadow_reject %s\", {\"reason\": \"shadow_price_last_missing\"})\n"
        "                return\n"
        "        except Exception:\n"
        "            pass\n"
    )

    # Insert before the first occurrence of a shadow_plan log/event emission.
    # Try patterns in order.
    patterns = [
        r"^\s*log\.info\(\s*\"shadow_plan\b",               # log.info("shadow_plan ...
        r"^\s*logger\.info\(\s*\"shadow_plan\b",            # logger.info("shadow_plan ...
        r"^\s*log\.info\(\s*'shadow_plan\b",                # single quotes
        r"^\s*logger\.info\(\s*'shadow_plan\b",
    ]

    inserted = False
    for pat in patterns:
        m = re.search(pat, s, flags=re.MULTILINE)
        if m:
            # Find the line start of the match and insert guard right before it.
            line_start = s.rfind("\n", 0, m.start()) + 1
            # Determine indentation of that log line, then adapt guard indentation to match surrounding block.
            line = s[line_start:s.find("\n", line_start)]
            indent = re.match(r"^(\s*)", line).group(1)
            # Our guard is written with 8 spaces (typical inside a function). Re-indent it.
            g = "\n".join((indent + x if x.strip() else x) for x in guard.splitlines()) + "\n"
            s = s[:line_start] + g + s[line_start:]
            inserted = True
            break

    # If we didn't find log emission, try to insert before JSONL write to shadow_plans.jsonl (best effort)
    if not inserted:
        m = re.search(r"shadow_plans\.jsonl", s)
        if m:
            # Insert near the first mention (best effort)
            line_start = s.rfind("\n", 0, m.start()) + 1
            line = s[line_start:s.find("\n", line_start)]
            indent = re.match(r"^(\s*)", line).group(1)
            g = "\n".join((indent + x if x.strip() else x) for x in guard.splitlines()) + "\n"
            s = s[:line_start] + g + s[line_start:]
            inserted = True

    changed = (s != s0)
    return s0, s, changed

def main():
    # backups
    backup(shadow_pricing)
    backup(orch)

    # patch files
    sp0, sp1, sp_changed = patch_shadow_pricing()
    if sp_changed:
        write(shadow_pricing, sp1)

    o0, o1, o_changed = patch_orchestrator()
    if o_changed:
        write(orch, o1)

    print("PATCH_RESULTS:")
    print(f"  backup_dir = {bkdir}")
    print(f"  shadow_pricing.py changed = {sp_changed}")
    print(f"  orchestrator.py  changed = {o_changed}")

if __name__ == "__main__":
    main()
