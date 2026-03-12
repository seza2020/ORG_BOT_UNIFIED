import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
ORCH = ROOT / "tbot" / "runtime" / "orchestrator.py"
txt = ORCH.read_text(encoding="utf-8")

# A) Ensure we have force_override_pre_close variable somewhere near the existing override block.
# If it already exists, we don't add another one.
if "force_override_pre_close" not in txt:
    # Try to insert right after a common force_override line.
    pat_force = re.compile(r"(?m)^(?P<ind>[ \t]*)force_override\s*=\s*bool\(\s*force_signal_sid\s*and\s*int\(\s*force_signal_ignore_session\s*\)\s*\)\s*$")
    m = pat_force.search(txt)
    if not m:
        raise SystemExit("Could not find force_override line to anchor insertion.")
    ind = m.group("ind")
    ins = m.group(0) + "\n" + ind + "force_override_pre_close = bool(force_signal_sid and int(force_signal_ignore_pre_close))"
    txt = pat_force.sub(ins, txt, count=1)

# B) Fix the effective pre_close calculation (this is the line you still have wrong).
# Replace: pre_close = bool(st.pre_close and (not force_override))
# With:    pre_close = bool(st.pre_close and (not force_override_pre_close))
txt2, n = re.subn(
    r"(?m)^(?P<ind>[ \t]*)pre_close\s*=\s*bool\(\s*st\.pre_close\s*and\s*\(not\s*force_override\)\s*\)\s*$",
    r"\g<ind>pre_close = bool(st.pre_close and (not force_override_pre_close))",
    txt
)

if n == 0:
    # If code is slightly different, try a broader pattern:
    txt2, n2 = re.subn(
        r"(?m)^(?P<ind>[ \t]*)pre_close\s*=\s*bool\(\s*st\.pre_close\s*and\s*\(not\s*[^)]+\)\s*\)\s*$",
        r"\g<ind>pre_close = bool(st.pre_close and (not force_override_pre_close))",
        txt
    )
    if n2 == 0:
        raise SystemExit("Could not find a pre_close assignment line to patch.")
    txt = txt2
else:
    txt = txt2

# C) Ensure st.pre_close reflects the effective pre_close right after it's computed
# so any downstream checks using st.pre_close also respect ignore_pre_close.
# We insert 'st.pre_close = pre_close' right after the pre_close assignment if not present nearby.
anchor_pat = re.compile(r"(?m)^(?P<ind>[ \t]*)pre_close\s*=\s*bool\(st\.pre_close\s*and\s*\(not\s*force_override_pre_close\)\)\s*$")
m = anchor_pat.search(txt)
if not m:
    raise SystemExit("Patched pre_close line not found (unexpected).")

ind = m.group("ind")
# Look ahead a few lines to see if st.pre_close already assigned
start = m.start()
snippet = txt[start: start + 400]
if "st.pre_close = pre_close" not in snippet:
    txt = txt[:m.end()] + "\n" + ind + "st.pre_close = pre_close" + txt[m.end():]

ORCH.write_text(txt, encoding="utf-8")
print("PATCHED:", ORCH)
