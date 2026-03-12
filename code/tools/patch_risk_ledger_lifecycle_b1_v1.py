import shutil
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"risk_ledger.py"
if not path.exists():
    raise SystemExit(f"ERROR: not found: {path}")

txt = path.read_text(encoding="utf-8", errors="ignore")

# Idempotency
if "RISK_LEDGER_LIFECYCLE_B1_V1" in txt:
    print("SKIP: already patched (RISK_LEDGER_LIFECYCLE_B1_V1)")
    raise SystemExit(0)

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"RISK_LEDGER_LIFECYCLE_B1_V1_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"risk_ledger.py")

# We will insert methods at the end of class RiskLedger, right before EOF.
# Anchor: the class RiskLedger docstring exists; and try_consume_day_budget exists.
if "class RiskLedger" not in txt or "def try_consume_day_budget" not in txt:
    print("FAIL: RiskLedger anchors not found")
    raise SystemExit(2)

insert_block = r'''

    # --- RISK_LEDGER_LIFECYCLE_B1_V1 (observability/ledger only) ---
    def _append_event(self, day: str, evt: dict) -> bool:
        """
        Append a JSONL event to the daily ledger file.
        Observability-only: must not affect trading decisions.
        """
        try:
            p = Path(self._events_path(day))
            p.parent.mkdir(parents=True, exist_ok=True)
            with p.open("a", encoding="utf-8") as f:
                import json
                f.write(json.dumps(evt, ensure_ascii=False) + "\n")
            return True
        except Exception:
            return False

    def emit_event(self, kind: str, *, ts: str = None, run_id: str = "", day: str = None, **fields) -> bool:
        """
        Emit a lifecycle/telemetry event into the risk ledger JSONL.
        """
        try:
            _day = day or self._day()
            _ts = ts or datetime.utcnow().replace(microsecond=0).isoformat()
            evt = {
                "ts": _ts,
                "day": _day,
                "scope": self.scope,
                "kind": kind,
            }
            if run_id:
                evt["run_id"] = str(run_id)
            # merge extra fields
            for k, v in fields.items():
                if v is not None:
                    evt[k] = v
            return self._append_event(_day, evt)
        except Exception:
            return False

    def on_run_start(self, *, run_id: str, ts: str = None, **fields) -> bool:
        return self.emit_event("run_start", ts=ts, run_id=run_id, **fields)

    def on_run_end(self, *, run_id: str, exit_code: int = None, ts: str = None, **fields) -> bool:
        return self.emit_event("run_end", ts=ts, run_id=run_id, exit_code=exit_code, **fields)

    def on_session_start(self, *, session: str = "", run_id: str = "", ts: str = None, **fields) -> bool:
        return self.emit_event("session_start", ts=ts, run_id=run_id, session=session, **fields)

    def on_session_end(self, *, session: str = "", run_id: str = "", ts: str = None, **fields) -> bool:
        return self.emit_event("session_end", ts=ts, run_id=run_id, session=session, **fields)

    def on_gate_snapshot(self, *, run_id: str = "", ts: str = None, **fields) -> bool:
        # fields example: plans_used, plans_left, risk_used_usd, risk_left_usd, cooldown_left_sec, cap_hit, cap_usd
        return self.emit_event("gate_snapshot", ts=ts, run_id=run_id, **fields)
    # --- /RISK_LEDGER_LIFECYCLE_B1_V1 ---
'''

# Insert near end of class RiskLedger:
# We'll add the block right before the last line of file, but only if indentation suggests we're still in class.
# Simple approach: append at EOF (safe if file ends at class scope).
txt2 = txt.rstrip() + insert_block + "\n"

path.write_text(txt2, encoding="utf-8")
print("PATCHED:", path)
print("BACKUP_DIR:", bak)
