from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
txt = P.read_text(encoding="utf-8", errors="replace").splitlines(True)

# 1) remove ANY existing force_signal_sid lines (no matter where/indent)
out = []
removed = 0
for ln in txt:
    if "--force_signal_sid" in ln:
        removed += 1
        continue
    out.append(ln)
txt2 = "".join(out)

# 2) find the --force_signal add_argument block and insert alias right after it
# We locate the line containing ap.add_argument("--force_signal"
lines = txt2.splitlines(True)
i_force = None
for i, ln in enumerate(lines):
    if 'ap.add_argument("--force_signal"' in ln or "ap.add_argument('--force_signal'" in ln:
        i_force = i
        break

if i_force is None:
    print("REPAIR_FAIL: could not find ap.add_argument(--force_signal) in main.py")
    raise SystemExit(1)

# Determine indentation of that ap.add_argument line
m = re.match(r"^(\s*)ap\.add_argument\(", lines[i_force])
indent = m.group(1) if m else ""

alias_line = indent + 'ap.add_argument("--force_signal_sid", dest="force_signal", default="", help="DEPRECATED alias for --force_signal")\n'

# Insert alias line AFTER the force_signal argument line/block.
# In your file, add_argument usually is one-line; but we safely insert after the first closing paren if it spans multiple lines.
insert_at = i_force + 1

# If the add_argument spans multiple lines, advance until a line that contains ')'
if "(" in lines[i_force] and ")" not in lines[i_force]:
    j = i_force
    while j < len(lines) and ")" not in lines[j]:
        j += 1
    insert_at = j + 1

lines.insert(insert_at, alias_line)

P.write_text("".join(lines), encoding="utf-8")
print("REPAIRED:", P, "removed_force_signal_sid_lines=", removed, "inserted_alias=1")
