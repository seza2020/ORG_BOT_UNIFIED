import shutil, re
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"shadow_gate.py"
if not path.exists():
    raise SystemExit(f"ERROR: not found: {path}")

lines = path.read_text(encoding="utf-8", errors="ignore").splitlines(True)

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"SHADOW_GATE_INDENTFIX_B_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"shadow_gate.py")

def indent_len(s: str) -> int:
    return len(s) - len(s.lstrip(" "))

changed = 0

# Find first non-empty, non-shebang line that starts an indented triple-quote docstring
i = 0
while i < len(lines) and lines[i].strip() == "":
    i += 1

# allow shebang/encoding lines
while i < len(lines) and (lines[i].startswith("#!") or re.match(r"^#\s*coding[:=]\s*[-\w.]+", lines[i])):
    i += 1

# skip blank lines after headers
while i < len(lines) and lines[i].strip() == "":
    i += 1

if i < len(lines):
    s = lines[i]
    ind = indent_len(s)
    if ind > 0 and re.match(r'^\s*("""|\'\'\')', s):
        q = '"""' if '"""' in s else "'''"
        base = ind

        # Unindent this line and subsequent lines until closing triple-quote is found
        k = i
        closed = False
        while k < len(lines):
            lk = lines[k]
            # remove exactly base leading spaces if present
            if lk.startswith(" " * base):
                lines[k] = lk[base:]
            else:
                # defensive: if tabs or mixed indent, just lstrip
                if lk.strip() != "":
                    lines[k] = lk.lstrip(" ")

            # detect closing quote (but avoid counting the opening line as closing if it's same-line only)
            if k > i and q in lines[k]:
                closed = True
                k += 1
                break
            k += 1

        if closed:
            changed = 1

path.write_text("".join(lines), encoding="utf-8")
print("PATCHED:", path)
print("BACKUP_DIR:", bak)
print("CHANGED_DOCSTRING_BLOCK:", changed)

# print first 40 lines to verify indentation visually
L = "".join(lines).splitlines()
print("---- HEAD_40 ----")
for j in range(0, min(40, len(L))):
    print(f"{j+1:>4} | {L[j]}")
