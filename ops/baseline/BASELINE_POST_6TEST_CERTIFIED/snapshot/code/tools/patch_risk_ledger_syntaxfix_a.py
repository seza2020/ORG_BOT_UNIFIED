import shutil
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"risk_ledger.py"
txt = path.read_text(encoding="utf-8", errors="ignore")

# backup
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"RISK_LEDGER_SYNTAXFIX_A_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"risk_ledger.py")

# fix the broken annotation
bad = "    remaining_usd:\n"
good = "    remaining_usd: float\n"

if bad not in txt:
    print("FAIL: did not find exact 'remaining_usd:' line")
    raise SystemExit(2)

txt = txt.replace(bad, good, 1)
path.write_text(txt, encoding="utf-8")
print("PATCHED:", path)
print("BACKUP_DIR:", bak)
