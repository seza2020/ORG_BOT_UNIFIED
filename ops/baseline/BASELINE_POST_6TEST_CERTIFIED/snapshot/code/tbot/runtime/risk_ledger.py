# File: tbot/runtime/risk_ledger.py
from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, Tuple

from pathlib import Path
try:
    from zoneinfo import ZoneInfo
except Exception:  # pragma: no cover
    ZoneInfo = None  # type: ignore

_TZ_NAME = "America/Los_Angeles"

def _tz():
    if ZoneInfo is None:
        return None
    return ZoneInfo(_TZ_NAME)

def _today_pt_yyyymmdd() -> str:
    tz = _tz()
    if tz is None:
        return datetime.now().strftime("%Y%m%d")
    now_utc = datetime.utcnow().replace(tzinfo=ZoneInfo("UTC"))
    return now_utc.astimezone(tz).strftime("%Y%m%d")

def _atomic_write_json(path: str, obj: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
    os.replace(tmp, path)

def _append_jsonl(path: str, obj: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    line = json.dumps(obj, ensure_ascii=False)
    with open(path, "a", encoding="utf-8") as f:
        f.write(line + "\n")

class _FileLock:
    """
    Cross-platform-ish lock using atomic lockfile create (O_EXCL).
    Works well on Windows for single host/process coordination.
    """
    def __init__(self, lock_path: str, timeout_ms: int = 5000, sleep_ms: int = 25) -> None:
        self.lock_path = lock_path
        self.timeout_ms = int(timeout_ms)
        self.sleep_ms = int(sleep_ms)
        self._fd: int | None = None

    def acquire(self) -> None:
        deadline = time.time() + (self.timeout_ms / 1000.0)
        while True:
            try:
                self._fd = os.open(self.lock_path, os.O_CREAT | os.O_EXCL | os.O_RDWR)
                return
            except FileExistsError:
                if time.time() >= deadline:
                    raise TimeoutError(f"RiskLedger lock timeout: {self.lock_path}")
                time.sleep(self.sleep_ms / 1000.0)

    def release(self) -> None:
        try:
            if self._fd is not None:
                os.close(self._fd)
        finally:
            self._fd = None
            try:
                os.remove(self.lock_path)
            except Exception:
                pass

    def __enter__(self):
        self.acquire()
        return self

    def __exit__(self, exc_type, exc, tb):
        self.release()
        return False

@dataclass(frozen=True)
class RiskState:
    day: str
    scope: str
    cap_usd: float
    used_usd: float
    remaining_usd: float
    last_ts: str

class RiskLedger:
    """
    Atomic daily risk budget ledger.
    - Stores state in:   {RUNROOT}/state/risk_ledger_{scope}_{day}.json
    - Appends events to: {RUNROOT}/logs/risk_ledger_{scope}_{day}.jsonl
    """
    def __init__(self, *, runroot: str, scope: str = "GLOBAL") -> None:
        self.runroot = (runroot or "").strip() or "."
        self.scope = (scope or "").strip().upper() or "GLOBAL"

    def _day(self) -> str:
        return _today_pt_yyyymmdd()

    def _state_path(self, day: str) -> str:
        return os.path.join(self.runroot, "state", f"risk_ledger_{self.scope}_{day}.json")

    def _events_path(self, day: str) -> str:
        return os.path.join(self.runroot, "logs", f"risk_ledger_{self.scope}_{day}.jsonl")

    def _lock_path(self, day: str) -> str:
        return self._state_path(day) + ".lock"

    def _load_state(self, day: str) -> Dict[str, Any]:
        p = self._state_path(day)
        if not os.path.exists(p):
            return {
                "day": day,
                "scope": self.scope,
                "cap_usd": None,
                "used_usd": 0.0,
                "last_ts": None,
            }
        try:
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f) or {}
        except Exception:
            # If corrupted, fail closed (force stop)
            raise SystemExit(f"[RISK_LEDGER] HARD_STOP: corrupted state file: {p}")

    def try_consume_day_budget(
        self,
        *,
        ts: str,
        sid: str,
        symbol: str,
        risk_usd: float,
        cap_usd: float,
        run_id: str = "",
    ) -> Tuple[bool, RiskState]:
        day = self._day()
        lock_timeout_ms = int((os.getenv("TBOT_RISK_LEDGER_LOCK_TIMEOUT_MS","5000") or "5000").strip())
        allow_budget_change = (os.getenv("TBOT_ALLOW_BUDGET_CHANGE","0") == "1")

        with _FileLock(self._lock_path(day), timeout_ms=lock_timeout_ms):
            st = self._load_state(day)

            prev_cap = st.get("cap_usd", None)
            if prev_cap is None:
                st["cap_usd"] = float(cap_usd)
            else:
                # Cap drift is a compliance break unless explicitly allowed
                if float(prev_cap) != float(cap_usd) and not allow_budget_change:
                    raise SystemExit(
                        f"[RISK_LEDGER] HARD_STOP: cap changed mid-day: prev={prev_cap} new={cap_usd} "
                        f"(set TBOT_ALLOW_BUDGET_CHANGE=1 only for controlled experiments)"
                    )
                st["cap_usd"] = float(cap_usd)

            used = float(st.get("used_usd", 0.0) or 0.0)
            cap = float(st.get("cap_usd", cap_usd) or cap_usd)
            risk = float(risk_usd or 0.0)

            remaining = cap - used
            ok = (risk <= remaining + 1e-9)

            ev = {
                "ts": ts,
                "day": day,
                "scope": self.scope,
                "kind": "risk_consume_attempt",
                "ok": bool(ok),
                "sid": str(sid or ""),
                "symbol": str(symbol or ""),
                "risk_usd": round(risk, 6),
                "cap_usd": round(cap, 6),
                "used_before_usd": round(used, 6),
                "remaining_before_usd": round(remaining, 6),
                "run_id": str(run_id or ""),
            }

            if ok:
                used2 = used + risk
                st["used_usd"] = float(used2)
                st["last_ts"] = ts
                _atomic_write_json(self._state_path(day), st)
                ev["used_after_usd"] = round(used2, 6)
                ev["remaining_after_usd"] = round(cap - used2, 6)
                _append_jsonl(self._events_path(day), ev)
                return True, RiskState(day, self.scope, cap, used2, cap - used2, ts)

            # Not ok -> do NOT mutate used
            st["last_ts"] = ts
            _atomic_write_json(self._state_path(day), st)
            _append_jsonl(self._events_path(day), ev)
            return False, RiskState(day, self.scope, cap, used, cap - used, ts)

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

