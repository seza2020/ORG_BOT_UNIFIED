import os, re, json, shutil
from datetime import datetime
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot")
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak_dir = ROOT / "logs" / "ops" / "patches" / f"ATOMIC_RISK_LEDGER_GATEHOOK_V1_{stamp}"
bak_dir.mkdir(parents=True, exist_ok=True)

candidates = [
  ROOT / "tbot" / "runtime" / "shadow_gate.py",
  ROOT / "tbot" / "runtime" / "paper_gate.py",
  ROOT / "tbot" / "runtime" / "gate.py",
]
# also: search any *gate*.py under tbot/runtime
for p in (ROOT / "tbot" / "runtime").glob("*gate*.py"):
  if p not in candidates:
    candidates.append(p)

targets = [p for p in candidates if p.exists()]
if not targets:
  raise SystemExit("ERROR: no gate candidates found under tbot/runtime")

hook_import = "from tbot.runtime.risk_ledger import RiskLedger\n"
hook_block = r"""
        # --- ATOMIC_RISK_LEDGER_GATEHOOK_V1 ---
        try:
            rl = RiskLedger(runroot=os.getenv("TBOT_RUNROOT","").strip() or ".", scope=(os.getenv("TBOT_ENV","GLOBAL") or "GLOBAL").strip())
            ok_ledger, st_ledger = rl.try_consume_day_budget(
                ts=ts,
                sid=sid,
                symbol=symbol,
                risk_usd=float(risk_usd),
                cap_usd=float(max_risk_usd),
                run_id=run_id,
            )
            if not ok_ledger:
                return self._reject(reason="risk_above_max_atomic", meta={"ledger": st_ledger})
        except Exception as e:
            return self._reject(reason="risk_ledger_error", meta={"err": str(e)})
        # --- /ATOMIC_RISK_LEDGER_GATEHOOK_V1 ---
"""

def patch_one(path: Path):
  txt = path.read_text(encoding="utf-8", errors="ignore")
  if "ATOMIC_RISK_LEDGER_GATEHOOK_V1" in txt:
    return f"SKIP(already): {path}"

  # ensure import exists near top
  if "from tbot.runtime.risk_ledger import RiskLedger" not in txt:
    # insert after other imports
    m = re.search(r"^(import .+?\n)+", txt, flags=re.M)
    if m:
      ins = m.end()
      txt = txt[:ins] + hook_import + txt[ins:]
    else:
      txt = hook_import + txt

  # heuristic: find the place where accept happens or where max_risk_usd checked
  # we anchor on a line mentioning max_risk_usd and risk_usd in evaluate
  anchor = re.search(r"(max_risk_usd.*\n.*risk_usd.*\n)|(\brisk_usd\b.*\n.*max_risk_usd.*\n)", txt)
  if not anchor:
    # fallback anchor: just before "return self._accept" if exists
    anchor = re.search(r"^\s*return\s+self\._accept\(", txt, flags=re.M)
  if not anchor:
    return f"FAIL(no anchor): {path}"

  # insert hook_block right before anchor.start (or before accept)
  ins_at = anchor.start()
  # figure indentation from nearby line
  before = txt[:ins_at].splitlines()[-1]
  indent = re.match(r"^(\s*)", before).group(1)
  block = "\n".join([indent + line if line.strip() else line for line in hook_block.splitlines()]) + "\n"
  txt2 = txt[:ins_at] + block + txt[ins_at:]

  # backup & write
  shutil.copy2(path, bak_dir / path.name)
  path.write_text(txt2, encoding="utf-8")
  return f"PATCHED: {path}"

results=[]
for t in targets:
  results.append(patch_one(t))

print("BACKUP_DIR:", bak_dir)
for r in results:
  print(r)
