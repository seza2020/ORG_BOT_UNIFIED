import os, shutil, glob, sys
from pathlib import Path
from datetime import datetime
import py_compile

ROOT = Path(r"C:\alpaca-bot\org_bot")
cur = ROOT/"tbot"/"runtime"/"shadow_gate.py"
patches = ROOT/"logs"/"ops"/"patches"

if not cur.exists():
    raise SystemExit(f"ERROR: current file missing: {cur}")
if not patches.exists():
    raise SystemExit(f"ERROR: patches dir missing: {patches}")

# Find all backup shadow_gate.py files
cands = []
for p in patches.glob("**/shadow_gate.py"):
    try:
        st = p.stat()
        cands.append((st.st_mtime, p))
    except Exception:
        pass

cands.sort(reverse=True)  # newest first
print("FOUND_BACKUPS=", len(cands))

best = None
tested = 0
for mtime, p in cands:
    tested += 1
    try:
        py_compile.compile(str(p), doraise=True)
        best = p
        print("BEST_OK_BACKUP=", p)
        break
    except Exception as e:
        # syntax/indent failed
        continue

print("TESTED=", tested)
if best is None:
    print("FAIL: no compilable backup found under logs/ops/patches")
    raise SystemExit(2)

# Backup current file before replacing
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak_dir = patches/f"SHADOW_GATE_RESTORE_AUTO_{stamp}"
bak_dir.mkdir(parents=True, exist_ok=True)
shutil.copy2(cur, bak_dir/"shadow_gate.py.CURRENT_BEFORE_RESTORE")

# Restore
shutil.copy2(best, cur)
print("RESTORED_FROM=", best)
print("BACKUP_CURRENT_DIR=", bak_dir)

# Quick HEAD preview
L = cur.read_text(encoding="utf-8", errors="ignore").splitlines()
print("---- RESTORED_HEAD_40 ----")
for i in range(0, min(40, len(L))):
    print(f"{i+1:>4} | {L[i]}")
