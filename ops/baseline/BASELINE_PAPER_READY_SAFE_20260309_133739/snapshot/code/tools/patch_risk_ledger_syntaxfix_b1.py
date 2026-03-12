import shutil, re
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"risk_ledger.py"
if not path.exists():
    raise SystemExit(f"ERROR: not found: {path}")

txt = path.read_text(encoding="utf-8", errors="ignore")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"RISK_LEDGER_SYNTAXFIX_B1_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"risk_ledger.py")

# Replace the whole RiskState block up to class RiskLedger with a clean canonical block.
pat = re.compile(r"@dataclass\(frozen=True\)\s*\nclass RiskState:\n.*?\nclass RiskLedger:\n", re.DOTALL)
m = pat.search(txt)
if not m:
    print("FAIL: could not locate RiskState -> RiskLedger block")
    raise SystemExit(2)

canonical = """@dataclass(frozen=True)
class RiskState:
    day: str
    scope: str
    cap_usd: float
    used_usd: float
    remaining_usd: float
    last_ts: str

class RiskLedger:
"""
txt2 = txt[:m.start()] + canonical + txt[m.end():]

path.write_text(txt2, encoding="utf-8")
print("PATCHED:", path)
print("BACKUP_DIR:", bak)

# quick sanity: print lines around the repaired area
L = txt2.splitlines()
for i in range(110, min(175, len(L))):
    print(f"{i+1:>5} | {L[i]}")
