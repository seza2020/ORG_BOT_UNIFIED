from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
txt = P.read_text(encoding="utf-8", errors="replace")

#   return run_loop(...)
#   _rc = run_loop(...)
#   return 0
#

pat = r"(?m)^(?P<indent>\s*)return\s+run_loop\s*\("
m = re.search(pat, txt)
if not m:
    raise SystemExit("NO_CHANGES: couldn't find 'return run_loop(' in tbot/main.py. Paste 30 lines around where run_loop is called.")

indent = m.group("indent")

txt2 = re.sub(
    pat,
    indent + "_rc = run_loop(",
    txt,
    count=1
)

lines = txt2.splitlines(True)

start_idx = None
for i, ln in enumerate(lines):
    if re.match(r"^\s*_rc\s*=\s*run_loop\s*\(", ln):
        start_idx = i
        break
if start_idx is None:
    raise SystemExit("NO_CHANGES: internal error locating patched run_loop call.")

bal = 0
found_open = False
end_idx = None
for i in range(start_idx, len(lines)):
    ln = lines[i]
    for ch in ln:
        if ch == "(":
            bal += 1
            found_open = True
        elif ch == ")":
            bal -= 1
    if found_open and bal == 0:
        end_idx = i
        break

if end_idx is None:
    raise SystemExit("NO_CHANGES: could not find end of run_loop(...) call; main.py formatting unexpected.")

window = "".join(lines[end_idx+1:end_idx+6])
if re.search(r"(?m)^\s*return\s+0\s*$", window):
    out = "".join(lines)
else:
    insert = indent + "return 0\n"
    lines.insert(end_idx+1, insert)
    out = "".join(lines)

if out == txt:
    raise SystemExit("NO_CHANGES: patch produced no diff.")

P.write_text(out, encoding="utf-8")
print("PATCHED:", str(P))
print("NOTE: main() now returns 0 after run_loop() (unless an exception occurs).")
