import pathlib, re

P = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
txt = P.read_text(encoding="utf-8")

# ---------- Forced block: inject guard right after the forced if-line ----------
forced_if_pat = re.compile(
    r"(?m)^(?P<indent>\s*)if\s+force_signal_sid\s+and\s+\(forced_remaining\s*>\s*0\)\s+and\s+strat\.sid\.upper\(\)\s*==\s*force_signal_sid\s*:\s*$"
)
m = forced_if_pat.search(txt)
if not m:
    raise SystemExit("Could not find forced signal if-line to patch")

indent = m.group("indent")
guard = (
    f"{indent}if is_alpha and bool(ctx.alpha_kill):\n"
    f"{indent}    forced_remaining -= 1\n"
    f"{indent}    ev = make_event(level=\"WARN\", kind=\"signal_skip\", payload={{\"sid\": strat.sid, \"reason\": \"alpha_kill_active\"}})\n"
    f"{indent}    meta.emit(ev); announce.emit(ev)\n"
    f"{indent}    continue\n"
)

# Insert guard as the first statements inside the forced if-block,
# by replacing the if-line with itself + guard (indented one level deeper)
txt = forced_if_pat.sub(lambda mm: mm.group(0) + "\n" + guard, txt, count=1)

# ---------- Real block: inject guard right after 'if sig is not None:' ----------
real_if_pat = re.compile(r"(?m)^(?P<indent>\s*)if\s+sig\s+is\s+not\s+None\s*:\s*$")
mr = real_if_pat.search(txt)
if not mr:
    raise SystemExit("Could not find real signal 'if sig is not None:' line to patch")

indent2 = mr.group("indent")
guard2 = (
    f"{indent2}if is_alpha and bool(ctx.alpha_kill):\n"
    f"{indent2}    ev = make_event(level=\"WARN\", kind=\"signal_skip\", payload={{\"sid\": strat.sid, \"reason\": \"alpha_kill_active\"}})\n"
    f"{indent2}    meta.emit(ev); announce.emit(ev)\n"
    f"{indent2}    continue\n"
)

txt = real_if_pat.sub(lambda mm: mm.group(0) + "\n" + guard2, txt, count=1)

P.write_text(txt, encoding="utf-8")
print("PATCHED:", P)
