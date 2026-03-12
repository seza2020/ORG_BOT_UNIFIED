import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
MAIN = ROOT / "tbot" / "main.py"
ORCH = ROOT / "tbot" / "runtime" / "orchestrator.py"

def die(msg): raise SystemExit(msg)

# ----------------------------
# Patch main.py (ensure int pass)
# ----------------------------
mtxt = MAIN.read_text(encoding="utf-8")

# ensure argparse exists (should already exist; keep safe)
if "--force_signal_ignore_pre_close" not in mtxt:
    needle = '    ap.add_argument("--force_signal_ignore_session", type=int, default=0, help="allow --force_signal to run even when out of session")\n'
    if needle not in mtxt:
        die("main.py: could not find force_signal_ignore_session argparse line")
    mtxt = mtxt.replace(
        needle,
        needle + '    ap.add_argument("--force_signal_ignore_pre_close", type=int, default=0, help="allow --force_signal to run even during pre_close")\n'
    )

# run_loop call: ensure we pass int(...)
# first remove any old bool(...) line if present
mtxt = re.sub(
    r"(?m)^\s*force_signal_ignore_pre_close\s*=\s*bool\(int\(getattr\(args,\s*'force_signal_ignore_pre_close'\s*,\s*0\)\)\)\s*,\s*$",
    "            force_signal_ignore_pre_close=int(getattr(args,'force_signal_ignore_pre_close',0)),",
    mtxt
)

# if still not present at all, add after ignore_session line
if "force_signal_ignore_pre_close" not in mtxt:
    needle = "            force_signal_ignore_session=bool(int(getattr(args,'force_signal_ignore_session',0))),\n"
    if needle not in mtxt:
        die("main.py: could not find run_loop force_signal_ignore_session line")
    mtxt = mtxt.replace(
        needle,
        needle + "            force_signal_ignore_pre_close=int(getattr(args,'force_signal_ignore_pre_close',0)),\n"
    )

MAIN.write_text(mtxt, encoding="utf-8")

# ----------------------------
# Patch orchestrator.py (override st fields)
# ----------------------------
otxt = ORCH.read_text(encoding="utf-8")

# ensure signature param exists
if "force_signal_ignore_pre_close" not in otxt:
    sig_pat = re.compile(r"(force_signal_ignore_session\s*:\s*(?:int|bool)\s*=\s*(?:0|False)\s*,)")
    m = sig_pat.search(otxt)
    if not m:
        die("orchestrator.py: could not find force_signal_ignore_session param in signature")
    line_start = otxt.rfind("\n", 0, m.start()) + 1
    line_end = otxt.find("\n", m.start())
    indent = re.match(r"^\s*", otxt[line_start:line_end]).group(0)
    insertion = m.group(1) + f"\n{indent}force_signal_ignore_pre_close: int = 0,"
    otxt = sig_pat.sub(insertion, otxt, count=1)

# insert override block after st.pre_close assignment (first occurrence)
if "st.pre_close = False  # forced: ignore pre_close" not in otxt:
    assign_pat = re.compile(r"(?m)^(?P<ind>[ \t]*)st\.pre_close\s*=\s*.*\r?\n")
    m2 = assign_pat.search(otxt)
    if not m2:
        die("orchestrator.py: could not find st.pre_close assignment to patch")
    ind = m2.group("ind")
    insert = (
        m2.group(0) +
        f"{ind}# forced overrides for testing forced signals\n"
        f"{ind}if force_signal_sid:\n"
        f"{ind}    if int(force_signal_ignore_session):\n"
        f"{ind}        st.in_session = True\n"
        f"{ind}    if int(force_signal_ignore_pre_close):\n"
        f"{ind}        st.pre_close = False  # forced: ignore pre_close\n"
    )
    otxt = otxt[:m2.start()] + insert + otxt[m2.end():]

ORCH.write_text(otxt, encoding="utf-8")

print("PATCHED:", MAIN)
print("PATCHED:", ORCH)
