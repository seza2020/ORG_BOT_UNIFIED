from pathlib import Path

p = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
s = p.read_text(encoding="utf-8", errors="ignore")

print("FILE=", str(p))
print("MARKER_GATE_SNAPSHOT_HOOK=", ("ORCH_RISK_LEDGER_GATE_SNAPSHOT_B1" in s))

needle = 'ev = make_event(level="INFO", kind="heartbeat", payload=heartbeat)'
i = s.find(needle)
print("HB_IDX=", i)
print("\nHB_CONTEXT:\n")

if i != -1:
    lo = max(0, i-300)
    hi = min(len(s), i+600)
    print(s[lo:hi])
else:
    print("HB_NOT_FOUND")
