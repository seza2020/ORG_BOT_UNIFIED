import pathlib, subprocess, sys, os

root = pathlib.Path(r"C:\alpaca-bot\org_bot")
orch_dir = root / "tbot" / "runtime"
cur = orch_dir / "orchestrator.py"

cands = []
# backups
cands += sorted(orch_dir.glob("orchestrator.py.bak*"), key=lambda p: p.stat().st_mtime, reverse=True)
# also try a couple known names if exist
for name in ["orchestrator.py.bak_before_ignore_preclose_fix_v3",
             "orchestrator.py.bak_before_ignore_preclose_fix_v2",
             "orchestrator.py.bak_before_ignore_preclose_fix",
             "orchestrator.py.bak_before_alpha_kill_blocks_fire",
             "orchestrator.py.bak_alpha_kill_blocks_fire"]:
    p = orch_dir / name
    if p.exists() and p not in cands:
        cands.insert(0, p)

def compiles(path: pathlib.Path) -> bool:
    try:
        r = subprocess.run([sys.executable, "-m", "py_compile", str(path)], capture_output=True, text=True)
        return r.returncode == 0
    except Exception:
        return False

ok = None
for p in cands:
    if compiles(p):
        ok = p
        break

if ok is None:
    print("NO_COMPILE_OK_BACKUP_FOUND")
    print("Tried:", [str(x) for x in cands[:10]])
    sys.exit(2)

cur.write_text(ok.read_text(encoding="utf-8"), encoding="utf-8")
print("RESTORED_FROM:", ok)
sys.exit(0)
