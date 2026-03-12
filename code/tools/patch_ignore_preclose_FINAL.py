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
    pat = re.compile(
        r"^(\s*force_signal_ignore_session\s*=\s*bool\(int\(getattr\(args,\s*['\"]force_signal_ignore_session['\"],0\)\)\)\s*,\s*)$",
        re.M
    )
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
# C) orchestrator.py: compute override flag (insert after force_override/force_sid if possible)
# ---------------------------
if "force_override_pre_close" not in o:
    # try insert after a force_override assignment that references ignore_session
    p1 = re.compile(r"(?m)^([ \t]*)force_override\s*=\s*.*force_signal_ignore_session.*$")
    m1 = p1.search(o)
    if m1:
        ind = m1.group(1)
        line = f"{ind}force_override_pre_close = bool(force_signal_sid and int(force_signal_ignore_pre_close))"
        o = o[:m1.end()] + "\n" + line + o[m1.end():]
    else:
        # fallback: insert near first usage of force_signal_sid inside function body
        p2 = re.compile(r"(?m)^([ \t]*).*(force_signal_sid).*$")
        m2 = p2.search(o)
        if not m2:
            raise SystemExit("orchestrator.py: could not find a place to insert force_override_pre_close")
        ind = re.match(r"^\s*", m2.group(0)).group(0)
        line = f"{ind}force_override_pre_close = bool(force_signal_sid and int(force_signal_ignore_pre_close))"
        o = o[:m2.start()] + line + "\n" + o[m2.start():]

# ---------------------------
# D) orchestrator.py: make pre_close override-able
#    1) pre_close derived from session.is_pre_close(...)
#    2) pre_close derived from st.pre_close
# ---------------------------

# 1) pre_close = session.is_pre_close(X)
o = re.sub(
    r"(?m)^([ \t]*pre_close\s*=\s*)(session\.is_pre_close\([^\)]*\))\s*$",
    r"\1(\2 and (not force_override_pre_close))",
    o
)

# 2) pre_close = st.pre_close   OR  pre_close = bool(st.pre_close)
o = re.sub(
    r"(?m)^([ \t]*pre_close\s*=\s*)(bool\()?\s*(st\.pre_close)\s*\)?\s*$",
    r"\1bool(\3 and (not force_override_pre_close))",
    o
)

ORCH.write_text(o, encoding="utf-8")
print("PATCHED:", MAIN)
print("PATCHED:", ORCH)
