import pathlib
import re

ORCH = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
txt = ORCH.read_text(encoding="utf-8")

pattern = re.compile(
    r"""
(?P<indent>^[ \t]*)force_override\s*=\s*bool\([^\n]*\)\s*\n
(?P=indent)in_session\s*=\s*bool\([^\n]*\)\s*\n
(?P=indent)pre_close\s*=\s*bool\([^\n]*\)\s*$
""",
    re.M | re.X
)

m = pattern.search(txt)
if not m:
    raise SystemExit("Could not find force_override/in_session/pre_close block to patch.")

indent = m.group("indent")
replacement = (
    f"{indent}force_override_session = bool(force_signal_sid and force_signal_ignore_session)\n"
    f"{indent}force_override_pre_close = bool(force_signal_sid and force_signal_ignore_pre_close)\n"
    f"{indent}in_session = bool(st.in_session or force_override_session)\n"
    f"{indent}pre_close = bool(st.pre_close and (not force_override_pre_close))\n"
)

txt2 = pattern.sub(replacement, txt, count=1)
ORCH.write_text(txt2, encoding="utf-8")
print("PATCHED:", ORCH)
