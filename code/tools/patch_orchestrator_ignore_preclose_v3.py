import pathlib, re

ORCH = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
txt = ORCH.read_text(encoding="utf-8")

# ---------------------------
# 1) Ensure signature param exists (int = 0)
# ---------------------------
if "force_signal_ignore_pre_close" not in txt:
    # look for: force_signal_ignore_session: int = 0,
    sig_pat = re.compile(r"(force_signal_ignore_session\s*:\s*int\s*=\s*0\s*,)")
    m = sig_pat.search(txt)
    if not m:
        raise SystemExit("Could not find force_signal_ignore_session: int = 0, in orchestrator.py signature")

    # keep indentation based on the matched line
    line_start = txt.rfind("\n", 0, m.start()) + 1
    line_end = txt.find("\n", m.start())
    line = txt[line_start:line_end]
    indent = re.match(r"^\s*", line).group(0)

    insertion = m.group(1) + f"\n{indent}force_signal_ignore_pre_close: int = 0,"
    txt = sig_pat.sub(insertion, txt, count=1)

# ---------------------------
# 2) Replace force_override block with session + pre_close overrides
# ---------------------------
block_pat = re.compile(
    r"""(?m)^(?P<indent>[ \t]*)force_override\s*=\s*bool\(force_signal_sid\s*and\s*force_signal_ignore_session\)\s*\r?\n
(?P=indent)in_session\s*=\s*bool\(st\.in_session\s*or\s*force_override\)\s*\r?\n
(?P=indent)pre_close\s*=\s*bool\(st\.pre_close\s*and\s*\(not\s*force_override\)\)\s*\r?\n
""",
)

m2 = block_pat.search(txt)
if not m2:
    raise SystemExit("Could not find force_override/in_session/pre_close block to patch (orchestrator.py)")

ind = m2.group("indent")
replacement = (
    f"{ind}force_override_session = bool(force_signal_sid and force_signal_ignore_session)\n"
    f"{ind}force_override_pre_close = bool(force_signal_sid and force_signal_ignore_pre_close)\n"
    f"{ind}in_session = bool(st.in_session or force_override_session)\n"
    f"{ind}pre_close = bool(st.pre_close and (not force_override_pre_close))\n"
)

txt = block_pat.sub(replacement, txt, count=1)

ORCH.write_text(txt, encoding="utf-8")
print("PATCHED:", ORCH)
