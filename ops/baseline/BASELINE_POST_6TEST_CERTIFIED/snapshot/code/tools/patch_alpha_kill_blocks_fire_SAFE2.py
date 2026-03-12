import pathlib, re

P = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
txt = P.read_text(encoding="utf-8")

if "kind=\"signal_skip\"" in txt and "alpha_kill_active" in txt:
    print("ALREADY_PATCHED:", P)
    raise SystemExit(0)

# --- Forced signal block ---
forced_if_pat = re.compile(
    r"(?m)^(?P<indent>[ \t]*)if\s+force_signal_sid\s+and\s+\(forced_remaining\s*>\s*0\)\s+and\s+strat\.sid\.upper\(\)\s*==\s*force_signal_sid\s*:\s*$"
)
m = forced_if_pat.search(txt)
if not m:
    raise SystemExit("Could not find forced signal if-line to patch")

indent = m.group("indent")
in1 = indent + "    "  # inside the if-block

guard1 = (
    f"{in1}# guard: alpha kill blocks alpha signals (forced)\n"
    f"{in1}if is_alpha and bool(ctx.alpha_kill):\n"
    f"{in1}    forced_remaining -= 1\n"
    f"{in1}    ev = make_event(level=\"WARN\", kind=\"signal_skip\", payload={{\"sid\": strat.sid, \"reason\": \"alpha_kill_active\"}})\n"
    f"{in1}    meta.emit(ev); announce.emit(ev)\n"
    f"{in1}    continue\n"
)

txt = forced_if_pat.sub(lambda mm: mm.group(0) + "\n" + guard1, txt, count=1)

# --- Real signal block ---
real_if_pat = re.compile(r"(?m)^(?P<indent>[ \t]*)if\s+sig\s+is\s+not\s+None\s*:\s*$")
mr = real_if_pat.search(txt)
if not mr:
    raise SystemExit("Could not find real signal 'if sig is not None:' line to patch")

indent2 = mr.group("indent")
in2 = indent2 + "    "

guard2 = (
    f"{in2}# guard: alpha kill blocks alpha signals (real)\n"
    f"{in2}if is_alpha and bool(ctx.alpha_kill):\n"
    f"{in2}    ev = make_event(level=\"WARN\", kind=\"signal_skip\", payload={{\"sid\": strat.sid, \"reason\": \"alpha_kill_active\"}})\n"
    f"{in2}    meta.emit(ev); announce.emit(ev)\n"
    f"{in2}    continue\n"
)

txt = real_if_pat.sub(lambda mm: mm.group(0) + "\n" + guard2, txt, count=1)

P.write_text(txt, encoding="utf-8")
print("PATCHED:", P)
