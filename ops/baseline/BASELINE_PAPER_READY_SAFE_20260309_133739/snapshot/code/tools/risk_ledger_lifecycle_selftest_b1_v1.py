import os, json
from pathlib import Path
from datetime import datetime

from tbot.runtime.risk_ledger import RiskLedger

RUNROOT = Path(r"C:\alpaca-bot\org_bot_runtime\shadow")
RUNROOT.mkdir(parents=True, exist_ok=True)

# Create ledger and force a known day via normal API behavior (it uses PT date internally).
led = RiskLedger(runroot=str(RUNROOT), scope="SHADOW")

# Emit lifecycle events (observability-only)
run_id = "SELFTEST_B1"
ts = datetime.utcnow().replace(microsecond=0).isoformat()

# These methods should exist after B1 lifecycle patch
led.on_run_start(run_id=run_id, ts=ts, scope="SHADOW", note="selftest")
led.on_session_start(session="RTH", ts=ts, scope="SHADOW", note="selftest")
led.on_gate_snapshot(ts=ts, scope="SHADOW", plans_used=1, plans_left=24, risk_used_usd=25.0, risk_left_usd=75.0, cooldown_left_sec=0, cap_hit=False, cap_usd=100.0)
led.on_session_end(session="RTH", ts=ts, scope="SHADOW", note="selftest")
led.on_run_end(run_id=run_id, ts=ts, scope="SHADOW", exit_code=0, note="selftest")

# Locate latest ledger jsonl and verify events exist
logs_dir = RUNROOT / "logs"
cands = sorted(logs_dir.glob("risk_ledger_*_*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)

print("RUNROOT=", str(RUNROOT))
print("LOGS_DIR=", str(logs_dir))
print("LATEST_LEDGER_JSONL=", str(cands[0]) if cands else None)

if not cands:
    raise SystemExit("FAIL: no risk_ledger_*.jsonl found")

p = cands[0]
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines()[-50:]
kinds = []
for ln in lines:
    try:
        obj = json.loads(ln)
        kinds.append(obj.get("kind"))
    except Exception:
        pass

need = {"run_start","session_start","gate_snapshot","session_end","run_end"}
have = set([k for k in kinds if k])

print("HAVE_KINDS=", sorted(list(have)))
missing = sorted(list(need - have))
print("MISSING_KINDS=", missing)

if missing:
    raise SystemExit("FAIL: missing lifecycle kinds: " + ", ".join(missing))

print("PASS: lifecycle events written to JSONL")
