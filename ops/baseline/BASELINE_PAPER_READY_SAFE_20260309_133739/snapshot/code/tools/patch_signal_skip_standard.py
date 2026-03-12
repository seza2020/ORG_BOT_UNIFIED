import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
ORCH = ROOT / "tbot" / "runtime" / "orchestrator.py"
o = ORCH.read_text(encoding="utf-8")

# We patch the gate that wraps strategy eval loop:
# if ctx.in_session and (not ctx.pre_close) and (not ctx.portfolio_kill):
#     for strat in strategies:
#
# We replace it with explicit skip reasons + single gate.

needle = r"if ctx\.in_session and \(not ctx\.pre_close\) and \(not ctx\.portfolio_kill\):\n\s+for strat in strategies:"
m = re.search(needle, o)
if not m:
    raise SystemExit("Could not find the ctx.in_session/pre_close/portfolio_kill gate block to patch.")

# Keep indentation
line_start = o.rfind("\n", 0, m.start()) + 1
indent = re.match(r"\s*", o[line_start:m.start()]).group(0)

replacement = (
    f"{indent}# Standardized signal_skip reasons (enterprise QA)\n"
    f"{indent}if (not ctx.in_session) or ctx.pre_close or ctx.portfolio_kill:\n"
    f"{indent}    if not ctx.in_session:\n"
    f"{indent}        _rsn = 'out_of_session'\n"
    f"{indent}    elif ctx.portfolio_kill:\n"
    f"{indent}        _rsn = 'portfolio_kill_active'\n"
    f"{indent}    else:\n"
    f"{indent}        _rsn = 'pre_close_active'\n"
    f"{indent}    ev = make_event(level='INFO', kind='signal_skip', payload={{'reason': _rsn}})\n"
    f"{indent}    meta.emit(ev); announce.emit(ev)\n"
    f"{indent}else:\n"
    f"{indent}    for strat in strategies:"
)

o2 = re.sub(needle, replacement, o, count=1)

ORCH.write_text(o2, encoding="utf-8")
print("PATCHED:", ORCH)
