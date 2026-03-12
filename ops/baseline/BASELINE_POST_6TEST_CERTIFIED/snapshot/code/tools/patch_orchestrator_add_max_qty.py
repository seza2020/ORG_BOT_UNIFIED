import pathlib, re

P = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
s = P.read_text(encoding="utf-8")
orig = s

# make shadow condition explicit (robust)
s = s.replace(
    "if shadow_enabled and shadow_writer and gate and sig_payload is not None:",
    "if shadow_enabled and (shadow_writer is not None) and (gate is not None) and (sig_payload is not None):"
)

# find build_shadow_plan call and inject max_qty if missing
needle = "plan = build_shadow_plan("
idx = s.find(needle)
if idx == -1:
    raise SystemExit("PATCH FAIL: build_shadow_plan call not found")

win = s[idx: idx + 2500]
if "max_qty=" in win:
    print("SKIP: max_qty already present in build_shadow_plan call")
else:
    # insert after confidence=... line inside call
    m = re.search(r"(?m)^(?P<indent>[ \t]*)confidence\s*=\s*.*,\s*$", win)
    if not m:
        raise SystemExit("PATCH FAIL: could not find confidence= line near build_shadow_plan call")

    indent = m.group("indent")
    insert = f"{indent}max_qty=int(shadow_max_qty),\n"
    pos = idx + m.end()
    s = s[:pos] + insert + s[pos:]
    P.write_text(s, encoding="utf-8")
    print("PATCHED:", P)

if s == orig:
    print("NO_CHANGE")
