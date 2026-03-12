import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
ORCH = ROOT / "tbot" / "runtime" / "orchestrator.py"

txt = ORCH.read_text(encoding="utf-8")

# 1) ensure signature has force_signal_ignore_pre_close (only if missing)
if "force_signal_ignore_pre_close" not in txt:
    sig_pat = re.compile(r"(\n[ \t]*force_signal_ignore_session\s*:\s*int\s*=\s*0\s*,)")
    m = sig_pat.search(txt)
    if not m:
        raise SystemExit("Could not find force_signal_ignore_session in run_loop signature")
    indent = re.search(r"\n([ \t]*)force_signal_ignore_session", m.group(1)).group(1)
    txt = sig_pat.sub(m.group(1) + f"\n{indent}force_signal_ignore_pre_close: int = 0,", txt, count=1)

# 2) patch the current override block (your file uses pre_close with (not force_override))
block_pat = re.compile(
    r"(?m)^(?P<ind>[ \t]*)force_override\s*=\s*bool\(\s*force_signal_sid\s*and\s*force_signal_ignore_session\s*\)\s*\n"
    r"(?P=ind)in_session\s*=\s*bool\(\s*st\.in_session\s*or\s*force_override\s*\)\s*\n"
    r"(?P=ind)pre_close\s*=\s*bool\(\s*st\.pre_close\s*and\s*\(not\s*force_override\)\s*\)\s*\n"
)
m2 = block_pat.search(txt)
if not m2:
    raise SystemExit("Could not find force_override/in_session/pre_close block (expected current form).")

ind = m2.group("ind")
replacement = (
    f"{ind}force_override_session = bool(force_signal_sid and force_signal_ignore_session)\n"
    f"{ind}force_override_pre_close = bool(force_signal_sid and force_signal_ignore_pre_close)\n"
    f"{ind}in_session = bool(st.in_session or force_override_session)\n"
    f"{ind}pre_close = bool(st.pre_close and (not force_override_pre_close))\n"
)

txt = block_pat.sub(replacement, txt, count=1)
ORCH.write_text(txt, encoding="utf-8")
print("PATCHED:", ORCH)
