from __future__ import annotations

import json
import os
import tempfile
from datetime import datetime
from typing import Optional

from .risk_ledger_models import RiskLedgerState


class RiskLedger:
    """
    Phase-1 file-based risk ledger with atomic write and restart-safe load.
    """

    def __init__(self, path: str) -> None:
        self.path = path

    @classmethod
    def from_env(cls) -> "RiskLedger":
        runroot = os.getenv("TBOT_RUNROOT") or os.path.join(os.getcwd(), "runtime", "paper")
        path = os.path.join(runroot, "logs", "risk_ledger_v1.json")
        return cls(path=path)

    @staticmethod
    def _now_ts() -> str:
        return datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    @staticmethod
    def _day_key(dt: Optional[datetime] = None) -> str:
        dt = dt or datetime.utcnow()
        return dt.strftime("%Y-%m-%d")

    @staticmethod
    def _week_key(dt: Optional[datetime] = None) -> str:
        dt = dt or datetime.utcnow()
        year, week, _ = dt.isocalendar()
        return f"{year}-W{week:02d}"

    def _default_state(self, run_id: str = "") -> RiskLedgerState:
        now = datetime.utcnow()
        return RiskLedgerState(
            ledger_version=1,
            run_id=str(run_id or ""),
            last_update_ts=self._now_ts(),
            day_key=self._day_key(now),
            week_key=self._week_key(now),
            daily_budget_used_r=0.0,
            weekly_budget_used_r=0.0,
            open_risk_r=0.0,
            open_positions_count=0,
            last_reason="initialized",
            load_error="",
        )

    def load_or_create(self, run_id: str = "") -> RiskLedgerState:
        if not os.path.exists(self.path):
            state = self._default_state(run_id=run_id)
            self.save_atomic(state)
            return state

        try:
            with open(self.path, "r", encoding="utf-8") as f:
                raw = json.load(f)

            state = RiskLedgerState(
                ledger_version=int(raw.get("ledger_version", 1) or 1),
                run_id=str(raw.get("run_id", run_id or "") or ""),
                last_update_ts=str(raw.get("last_update_ts", self._now_ts()) or self._now_ts()),
                day_key=str(raw.get("day_key", self._day_key()) or self._day_key()),
                week_key=str(raw.get("week_key", self._week_key()) or self._week_key()),
                daily_budget_used_r=float(raw.get("daily_budget_used_r", 0.0) or 0.0),
                weekly_budget_used_r=float(raw.get("weekly_budget_used_r", 0.0) or 0.0),
                open_risk_r=max(0.0, float(raw.get("open_risk_r", 0.0) or 0.0)),
                open_positions_count=max(0, int(raw.get("open_positions_count", 0) or 0)),
                last_reason=str(raw.get("last_reason", "loaded") or "loaded"),
                load_error="",
            )
            state = self.reset_daily_if_needed(state)
            state = self.reset_weekly_if_needed(state)
            self.save_atomic(state)
            return state

        except Exception as e:
            state = self._default_state(run_id=run_id)
            state.load_error = f"load_error:{type(e).__name__}"
            state.last_reason = "recovered_from_load_error"
            self.save_atomic(state)
            return state

    def save_atomic(self, state: RiskLedgerState) -> None:
        os.makedirs(os.path.dirname(self.path), exist_ok=True)

        payload = state.to_dict()
        fd, tmp = tempfile.mkstemp(prefix="risk_ledger_", suffix=".tmp", dir=os.path.dirname(self.path))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, self.path)
        finally:
            if os.path.exists(tmp):
                try:
                    os.remove(tmp)
                except Exception:
                    pass

    def reset_daily_if_needed(self, state: RiskLedgerState) -> RiskLedgerState:
        current_day = self._day_key()
        if state.day_key != current_day:
            state.day_key = current_day
            state.daily_budget_used_r = 0.0
            state.last_update_ts = self._now_ts()
            state.last_reason = "daily_reset"
        return state

    def reset_weekly_if_needed(self, state: RiskLedgerState) -> RiskLedgerState:
        current_week = self._week_key()
        if state.week_key != current_week:
            state.week_key = current_week
            state.weekly_budget_used_r = 0.0
            state.last_update_ts = self._now_ts()
            state.last_reason = "weekly_reset"
        return state

    def reserve_risk(self, state: RiskLedgerState, risk_r: float, reason: str = "reserve_risk") -> RiskLedgerState:
        r = max(0.0, float(risk_r or 0.0))
        state = self.reset_daily_if_needed(state)
        state = self.reset_weekly_if_needed(state)

        state.daily_budget_used_r += r
        state.weekly_budget_used_r += r
        state.open_risk_r += r
        state.open_positions_count += 1 if r > 0 else 0
        state.last_update_ts = self._now_ts()
        state.last_reason = reason
        return state

    def release_risk(self, state: RiskLedgerState, risk_r: float, reason: str = "release_risk") -> RiskLedgerState:
        r = max(0.0, float(risk_r or 0.0))

        state.open_risk_r = max(0.0, state.open_risk_r - r)
        if state.open_positions_count > 0 and r > 0:
            state.open_positions_count -= 1

        state.last_update_ts = self._now_ts()
        state.last_reason = reason
        return state

    def snapshot(self, state: RiskLedgerState) -> dict:
        return state.to_dict()
