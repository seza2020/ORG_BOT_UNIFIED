import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
MAIN = ROOT / "tbot" / "main.py"
ORCH = ROOT / "tbot" / "runtime" / "orchestrator.py"

# ---------------------------
# Patch tbot/main.py
# ---------------------------
m_txt = MAIN.read_text(encoding="utf-8")

# 1) add argparse option --force_signal_ignore_pre_close
if "--force_signal_ignore_pre_close" not in m_txt:
    needle = '    ap.add_argument("--force_signal_ignore_session", type=int, default=0, help="allow --force_signal to run even when out of session")\n'
    if needle not in m_txt:
        raise SystemExit("Could not find force_signal_ignore_session add_argument line in main.py")
    m_txt = m_txt.replace(
        needle,
        needle + '    ap.add_argument("--force_signal_ignore_pre_close", type=int, default=0, help="allow --force_signal to run even during pre_close")\n'
    )

# 2) pass force_signal_ignore_pre_close into run_loop call
if "force_signal_ignore_pre_close" not in m_txt:
    pass_line = "            force_signal_ignore_session=bool(int(getattr(args,'force_signal_ignore_session',0))),\n"
    if pass_line not in m_txt:
        raise SystemExit("Could not find force_signal_ignore_session=... line in run_loop call (main.py)")
    m_txt = m_txt.replace(
        pass_line,
        pass_line + "            force_signal_ignore_pre_close=bool(int(getattr(args,'force_signal_ignore_pre_close',0))),\n"
    )

MAIN.write_text(m_txt, encoding="utf-8")
print("PATCHED:", MAIN)

# ---------------------------
# Patch tbot/runtime/orchestrator.py
# ---------------------------
o_txt = ORCH.read_text(encoding="utf-8")

# A) ensure signature has force_signal_ignore_pre_close right after ignore_session
if "force_signal_ignore_pre_close" not in o_txt:
    sig_pat = re.compile(r"(\n[ \t]*force_signal_ignore_session\s*:\s*int\s*=\s*0\s*,)")
    m = sig_pat.search(o_txt)
    if not m:
        raise SystemExit("Could not locate force_signal_ignore_session: int = 0, in run_loop signature (orchestrator.py)")
    line = m.group(1)
    indent = re.search(r"\n([ \t]*)force_signal_ignore_session", line).group(1)
    insert = line + f"\n{indent}force_signal_ignore_pre_close: int = 0,"
    o_txt = sig_pat.sub(insert, o_txt, count=1)

# B) patch the block that computes force_override/in_session/pre_close
block_pat = re.compile(
    r"""
(?P<indent>^[ \t]*)
force_override\s*=\s*bool\(\s*force_signal_sid\s*and\s*force_signal_ignore_session\s*\)\s*\n
(?P=indent)in_session\s*=\s*bool\(\s*st\.in_session\s*or\s*force_override\s*\)\s*\n
(?P=indent)pre_close\s*=\s*bool\(\s*st\.pre_close\s*\)\s*
""",
    re.M | re.X
)

m2 = block_pat.search(o_txt)
if not m2:
    raise SystemExit("Could not find expected force_override/in_session/pre_close block to patch (orchestrator.py).")

ind = m2.group("indent")
replacement = (
    f"{ind}force_override_session = bool(force_signal_sid and force_signal_ignore_session)\n"
    f"{ind}force_override_pre_close = bool(force_signal_sid and force_signal_ignore_pre_close)\n"
    f"{ind}in_session = bool(st.in_session or force_override_session)\n"
    f"{ind}pre_close = bool(st.pre_close and (not force_override_pre_close))\n"
)

o_txt = block_pat.sub(replacement, o_txt, count=1)

ORCH.write_text(o_txt, encoding="utf-8")
print("PATCHED:", ORCH)
