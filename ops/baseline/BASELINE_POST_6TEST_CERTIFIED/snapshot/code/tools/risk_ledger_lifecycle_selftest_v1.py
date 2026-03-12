from pathlib import Path
from datetime import datetime
import os

# Import RiskLedger from your project
from tbot.runtime.risk_ledger import RiskLedger

runroot = os.environ.get("TBOT_RUNROOT", r"C:\alpaca-bot\org_bot_runtime\shadow")
logs = Path(runroot) / "logs"
logs.mkdir(parents=True, exist_ok=True)

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
test_path = logs / f"risk_ledger_SELFTEST_{stamp}.jsonl"

# Construct RiskLedger in best-effort way.
# We do not assume constructor signature, so we instantiate and then set ledger_path if present.
rl = RiskLedger()

# Set ledger path attribute if available
if hasattr(rl, "ledger_path"):
    rl.ledger_path = str(test_path)
elif hasattr(rl, "_ledger_path"):
    rl._ledger_path = str(test_path)
else:
    # fallback: just pass path via emit_event(fields)
    pass

# Emit lifecycle events
ok = []
ok.append(("run_start", rl.on_run_start(run_id="SELFTEST", scope="SHADOW", day=datetime.now().strftime("%Y%m%d"), path=str(test_path))))
ok.append(("session_start", rl.on_session_start(session="RTH", scope="SHADOW")))
ok.append(("gate_snapshot", rl.on_gate_snapshot(scope="SHADOW", cap_usd=50.0, risk_used_usd=25.0, risk_left_usd=25.0, plans_used=1, plans_left=1, cooldown_left_sec=0, cap_hit=False)))
ok.append(("session_end", rl.on_session_end(session="RTH", scope="SHADOW")))
ok.append(("run_end", rl.on_run_end(run_id="SELFTEST", exit_code=0, scope="SHADOW")))

print("TEST_LEDGER_PATH=", test_path)
print("EVENT_RESULTS=", ok)

# Show tail
if test_path.exists():
    lines = test_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    print("TAIL(20):")
    for x in lines[-20:]:
        print(x)
else:
    print("ERROR: test ledger file not created")
    raise SystemExit(2)
