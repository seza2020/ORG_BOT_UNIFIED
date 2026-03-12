import shutil, re
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"shadow_gate.py"
if not path.exists():
    raise SystemExit(f"ERROR: not found: {path}")

txt = path.read_text(encoding="utf-8", errors="ignore").splitlines(True)

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"SHADOW_GATE_INDENTFIX_A_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"shadow_gate.py")

changed = 0
out = []
for line in txt:
    # Fix common "dangling bullet line" that was indented at top-level and breaks import.
    # Example: "    - ok=False => reject with normalized reasons list"
    if re.match(r'^\s+-\s*ok\s*=\s*(true|false)\b.*=>', line, flags=re.IGNORECASE):
        # Comment it out at column 0 (safe; keeps file importable)
        out.append("# " + line.lstrip())
        changed += 1
    else:
        out.append(line)

path.write_text("".join(out), encoding="utf-8")
print("PATCHED:", path)
print("BACKUP_DIR:", bak)
print("CHANGED_LINES:", changed)
