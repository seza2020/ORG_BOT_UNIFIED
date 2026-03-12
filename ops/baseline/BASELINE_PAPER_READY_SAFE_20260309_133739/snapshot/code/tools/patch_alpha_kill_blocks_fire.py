import pathlib, re

P = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
txt = P.read_text(encoding="utf-8")

# --- Patch 1: Forced signal block (insert alpha_kill guard + optional skip log) ---
marker_forced = '                # Forced signal (test)\n'
if marker_forced not in txt:
    raise SystemExit("Could not find Forced signal marker")

# We'll inject guard right after marker line, before 'if force_signal_sid ...'
pat_forced_if = re.compile(r"(\n\s*# Forced signal \(test\)\n)(\s*if\s+force_signal_sid\s+and\s+\(forced_remaining\s*>\s*0\)\s+and\s+strat\.sid\.upper\(\)\s*==\s*force_signal_sid\s*:\s*\n)", re.M)
m = pat_forced_if.search(txt)
if not m:
    raise SystemExit("Could not locate forced signal if-block to patch")

indent = re.match(r"\s*", m.group(2)).group(0)
guard = (
    f"{indent}# Alpha kill: do not emit signal_fire for alpha strategies\n"
    f"{indent}if is_alpha and bool(ctx.alpha_kill):\n"
    f"{indent}    # keep evaluation logs, but skip firing signals\n"
    f"{indent}    if force_signal_sid and (forced_remaining > 0) and strat.sid.upper() == force_signal_sid:\n"
    f"{indent}        forced_remaining -= 1\n"
    f"{indent}        ev = make_event(level=\"WARN\", kind=\"signal_skip\", payload={{\"sid\": strat.sid, \"reason\": \"alpha_kill_active\"}})\n"
    f"{indent}        meta.emit(ev); announce.emit(ev)\n"
    f"{indent}    # also skip real evaluate fire below\n"
    f"{indent}    continue\n\n"
)

txt = pat_forced_if.sub(r"\1" + guard + r"\2", txt, count=1)

# --- Patch 2: Real strategy signal block (avoid signal_fire when alpha_kill for alpha) ---
# Replace:
# sig = strat.evaluate(ctx)
# if sig is not None:
#   ... emit signal_fire
# with:
# sig = strat.evaluate(ctx)
# if sig is not None:
#   if is_alpha and ctx.alpha_kill: emit signal_skip else emit signal_fire

pat_real = re.compile(
    r"(\n\s*# Real strategy signal \(if strategy returns one\)\n\s*sig\s*=\s*strat\.evaluate\(ctx\)\n\s*if\s+sig\s+is\s+not\s+None\s*:\n)(\s*sig_payload\s*=\s*\{\n)",
    re.M
)
mr = pat_real.search(txt)
if not mr:
    raise SystemExit("Could not locate real signal block to patch")

indent2 = re.match(r"\s*", mr.group(2)).group(0)
insert2 = (
    f"{mr.group(1)}"
    f"{indent2}# Alpha kill: suppress signal_fire for alpha strategies\n"
    f"{indent2}if is_alpha and bool(ctx.alpha_kill):\n"
    f"{indent2}    ev = make_event(level=\"WARN\", kind=\"signal_skip\", payload={{\"sid\": strat.sid, \"reason\": \"alpha_kill_active\"}})\n"
    f"{indent2}    meta.emit(ev); announce.emit(ev)\n"
    f"{indent2}else:\n"
    f"{indent2}    "
    + "{\n"  # placeholder; we'll keep the existing payload block but shift indent by 4
)

# We can't easily re-indent the existing payload block with regex safely;
# so instead, we patch by inserting a guard BEFORE the existing 'sig_payload = {' line.
# Simpler: find the exact line 'sig_payload = {' right after 'if sig is not None:' and add guard above it.

pat_guard_before_payload = re.compile(
    r"(\n\s*# Real strategy signal \(if strategy returns one\)\n\s*sig\s*=\s*strat\.evaluate\(ctx\)\n\s*if\s+sig\s+is\s+not\s+None\s*:\n)(\s*sig_payload\s*=\s*\{\n)",
    re.M
)

guard2 = (
    r"\1"
    + indent2 + "if is_alpha and bool(ctx.alpha_kill):\n"
    + indent2 + "    ev = make_event(level=\"WARN\", kind=\"signal_skip\", payload={\"sid\": strat.sid, \"reason\": \"alpha_kill_active\"})\n"
    + indent2 + "    meta.emit(ev); announce.emit(ev)\n"
    + indent2 + "else:\n"
    + indent2 + "    "
    + r"\2"
)

txt2 = pat_guard_before_payload.sub(guard2, txt, count=1)

# Also need to indent the entire existing block under else by 4 spaces.
# We'll indent until the next blank line after emitting 'signal_fire' for real signal.
# Find the block that starts with 'sig_payload = {' and ends right after meta.emit(ev); announce.emit(ev) for real signal.
block_pat = re.compile(
    r"(?ms)(\n\s*# Real strategy signal \(if strategy returns one\)\n\s*sig\s*=\s*strat\.evaluate\(ctx\)\n\s*if\s+sig\s+is\s+not\s+None\s*:\n\s*if is_alpha.*?else:\n\s*)(sig_payload\s*=\s*\{.*?meta\.emit\(ev\);\s*announce\.emit\(ev\)\n)",
)
mb = block_pat.search(txt2)
if not mb:
    raise SystemExit("Could not locate real-signal payload block for indentation")

prefix = mb.group(1)
block = mb.group(2)

indented_block = "\n".join(("    " + line) if line.strip() else line for line in block.splitlines())
# Ensure we keep trailing newline
if not indented_block.endswith("\n"):
    indented_block += "\n"

txt2 = block_pat.sub(prefix + indented_block, txt2, count=1)

P.write_text(txt2, encoding="utf-8")
print("PATCHED:", P)
