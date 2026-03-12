import pathlib, re

ORCH = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
txt = ORCH.read_text(encoding="utf-8")

# --- 1) ensure run_loop signature contains force_signal_ignore_pre_close (best-effort)
m = re.search(r"def\s+run_loop\((?P<sig>.*?)\)\s*->", txt, flags=re.S)
if not m:
    raise SystemExit("Could not find def run_loop(...) signature.")

sig = m.group("sig")
if "force_signal_ignore_pre_close" not in sig:
    # insert right after force_signal_ignore_session if possible
    if "force_signal_ignore_session" not in sig:
        raise SystemExit("Signature missing force_signal_ignore_session marker; cannot insert ignore_pre_close safely.")
    txt = txt.replace(
        "force_signal_ignore_session",
        "force_signal_ignore_session, force_signal_ignore_pre_close: bool = False",
        1
    )

# --- 2) replace force_override/in_session/pre_close block with correct logic
pattern = re.compile(
    r"""
(?P<indent>^[ \t]*)
force_override[^\n]*\n
(?P=indent)in_session[^\n]*\n
(?P=indent)pre_close[^\n]*\n
""",
    re.M | re.X
)

m2 = pattern.search(txt)
if not m2:
    raise SystemExit("Could not find force_override/in_session/pre_close block to patch.")

indent = m2.group("indent")
replacement = (
    f"{indent}force_override_session = bool(force_signal_sid and force_signal_ignore_session)\n"
    f"{indent}force_override_pre_close = bool(force_signal_sid and force_signal_ignore_pre_close)\n"
    f"{indent}in_session = bool(st.in_session or force_override_session)\n"
    f"{indent}pre_close = bool(st.pre_close and (not force_override_pre_close))\n"
)

txt2 = pattern.sub(replacement, txt, count=1)
ORCH.write_text(txt2, encoding="utf-8")
print("PATCHED:", ORCH)
