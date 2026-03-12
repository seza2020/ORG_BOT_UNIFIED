import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
MAIN = ROOT / "tbot" / "main.py"
ORCH = ROOT / "tbot" / "runtime" / "orchestrator.py"

m = MAIN.read_text(encoding="utf-8")
o = ORCH.read_text(encoding="utf-8")

# ---------------------------
# A) main.py: add argparse flag (if missing)
# ---------------------------
if "--force_signal_ignore_pre_close" not in m:
    needle = '    ap.add_argument("--force_signal_ignore_session", type=int, default=0, help="allow --force_signal to run even when out of session")\n'
    if needle not in m:
        raise SystemExit("main.py: could not find force_signal_ignore_session add_argument line")
    m = m.replace(
        needle,
        needle + '    ap.add_argument("--force_signal_ignore_pre_close", type=int, default=0, help="allow --force_signal to run even during pre_close (test-only)")\n'
    )

# main.py: pass kwarg into run_loop (if missing)
if "force_signal_ignore_pre_close=" not in m:
    # robust: find the existing ignore_session kwarg line (single or double quotes)
    pat = re.compile(r"^(\s*force_signal_ignore_session\s*=\s*bool\(int\(getattr\(args,\s*['\"]force_signal_ignore_session['\"],0\)\)\)\s*,\s*)$",
                     re.M)
    mm = pat.search(m)
    if not mm:
        raise SystemExit("main.py: could not find force_signal_ignore_session kwarg in run_loop call")
    line = mm.group(1)
    indent = re.match(r"^\s*", line).group(0)
    insert = line + "\n" + indent + "force_signal_ignore_pre_close=bool(int(getattr(args,'force_signal_ignore_pre_close',0))),"
    m = pat.sub(insert, m, count=1)

MAIN.write_text(m, encoding="utf-8")

# ---------------------------
# B) orchestrator.py: ensure signature param exists
# ---------------------------
if "force_signal_ignore_pre_close" not in o:
    sig_pat = re.compile(r"(\n[ \t]*force_signal_ignore_session\s*:\s*int\s*=\s*0\s*,)")
    sm = sig_pat.search(o)
    if not sm:
        raise SystemExit("orchestrator.py: could not locate force_signal_ignore_session: int = 0, in run_loop signature")
    indent = re.search(r"\n([ \t]*)force_signal_ignore_session", sm.group(1)).group(1)
    o = sig_pat.sub(sm.group(1) + f"\n{indent}force_signal_ignore_pre_close: int = 0,", o, count=1)

# ---------------------------
# C) orchestrator.py: make pre_close gating ignore-able when forcing
#    We patch common patterns safely.
# ---------------------------
ov_expr = r"bool(force_signal_sid and int(force_signal_ignore_pre_close))"

# 1) if st.pre_close:
o = re.sub(
    r"(?m)^([ \t]*)if\s+st\.pre_close\s*:\s*$",
    r"\1if st.pre_close and (not " + ov_expr + r"):",
    o
)

# 2) if pre_close:
o = re.sub(
    r"(?m)^([ \t]*)if\s+pre_close\s*:\s*$",
    r"\1if pre_close and (not " + ov_expr + r"):",
    o
)

# 3) if not st.in_session or st.pre_close:
o = re.sub(
    r"(?m)^([ \t]*)if\s+not\s+st\.in_session\s+or\s+st\.pre_close\s*:\s*$",
    r"\1if (not st.in_session) or (st.pre_close and (not " + ov_expr + r")):",
    o
)

# 4) if (not st.in_session) or st.pre_close:
o = re.sub(
    r"(?m)^([ \t]*)if\s*\(\s*not\s+st\.in_session\s*\)\s+or\s+st\.pre_close\s*:\s*$",
    r"\1if (not st.in_session) or (st.pre_close and (not " + ov_expr + r")):",
    o
)

ORCH.write_text(o, encoding="utf-8")
print("PATCHED:", MAIN)
print("PATCHED:", ORCH)
