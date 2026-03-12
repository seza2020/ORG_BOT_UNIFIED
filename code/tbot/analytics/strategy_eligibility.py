from __future__ import annotations

import json
import os
from typing import Any, Dict, Optional

from .strategy_eligibility_models import StrategyEligibilityDecision


class StrategyEligibilityEngine:
    """
    Phase-1 eligibility engine.

    Design goals:
    - State-aware
    - Snapshot-driven
    - Fail-safe
    - No runtime side effects
    """

    def __init__(
        self,
        *,
        runroot: str,
        min_events: int = 20,
        min_expectancy_r: float = -0.2,
        min_win_rate: float = 0.35,
    ) -> None:
        self.runroot = runroot
        self.logs_dir = os.path.join(runroot, "logs")
        self.snapshot_path = os.path.join(self.logs_dir, "strategy_perf_snapshot.json")

        self.min_events = int(min_events)
        self.min_expectancy_r = float(min_expectancy_r)
        self.min_win_rate = float(min_win_rate)

    @classmethod
    def from_env(cls) -> "StrategyEligibilityEngine":
        runroot = os.getenv("TBOT_RUNROOT") or os.path.join(os.getcwd(), "runtime", "paper")
        min_events = int(os.getenv("TBOT_ELIG_MIN_EVENTS", "20") or "20")
        min_expectancy_r = float(os.getenv("TBOT_ELIG_MIN_EXP_R", "-0.2") or "-0.2")
        min_win_rate = float(os.getenv("TBOT_ELIG_MIN_WIN_RATE", "0.35") or "0.35")
        return cls(
            runroot=runroot,
            min_events=min_events,
            min_expectancy_r=min_expectancy_r,
            min_win_rate=min_win_rate,
        )

    def decide(
        self,
        *,
        strategy_id: str,
        market_state: str,
        regime: Optional[str] = None,
        strategy_family: Optional[str] = None,
    ) -> StrategyEligibilityDecision:
        try:
            state = str(market_state or "UNKNOWN").upper()
            strat = str(strategy_id or "UNKNOWN")
            fam = str(strategy_family or self._infer_family(strat)).upper()

            if state == "ULTRA_CHOP":
                return StrategyEligibilityDecision(
                    strategy_id=strat,
                    market_state=state,
                    eligible=False,
                    reason="ultra_chop_no_trade",
                    regime=regime,
                    extra={"strategy_family": fam},
                )

            if not self._state_family_match(state=state, family=fam):
                return StrategyEligibilityDecision(
                    strategy_id=strat,
                    market_state=state,
                    eligible=False,
                    reason="state_mismatch",
                    regime=regime,
                    extra={"strategy_family": fam},
                )

            row = self._find_snapshot_row(strategy_id=strat, market_state=state, regime=regime)

            if row is None:
                return StrategyEligibilityDecision(
                    strategy_id=strat,
                    market_state=state,
                    eligible=True,
                    reason="eligibility_snapshot_missing_fail_open",
                    regime=regime,
                    extra={"strategy_family": fam},
                )

            event_count = int(row.get("event_count", 0) or 0)
            expectancy_r = self._maybe_float(row.get("expectancy_r"))
            win_rate = self._maybe_float(row.get("win_rate"))

            if event_count < self.min_events:
                return StrategyEligibilityDecision(
                    strategy_id=strat,
                    market_state=state,
                    eligible=False,
                    reason="insufficient_evidence",
                    event_count=event_count,
                    expectancy_r=expectancy_r,
                    win_rate=win_rate,
                    regime=regime,
                    extra={"strategy_family": fam},
                )

            if expectancy_r is not None and expectancy_r < self.min_expectancy_r:
                return StrategyEligibilityDecision(
                    strategy_id=strat,
                    market_state=state,
                    eligible=False,
                    reason="negative_expectancy",
                    event_count=event_count,
                    expectancy_r=expectancy_r,
                    win_rate=win_rate,
                    regime=regime,
                    extra={"strategy_family": fam},
                )

            if win_rate is not None and win_rate < self.min_win_rate:
                return StrategyEligibilityDecision(
                    strategy_id=strat,
                    market_state=state,
                    eligible=False,
                    reason="low_win_rate",
                    event_count=event_count,
                    expectancy_r=expectancy_r,
                    win_rate=win_rate,
                    regime=regime,
                    extra={"strategy_family": fam},
                )

            return StrategyEligibilityDecision(
                strategy_id=strat,
                market_state=state,
                eligible=True,
                reason="eligible",
                event_count=event_count,
                expectancy_r=expectancy_r,
                win_rate=win_rate,
                regime=regime,
                extra={"strategy_family": fam},
            )

        except Exception as e:
            return StrategyEligibilityDecision(
                strategy_id=str(strategy_id or "UNKNOWN"),
                market_state=str(market_state or "UNKNOWN").upper(),
                eligible=True,
                reason=f"eligibility_error_fail_open:{type(e).__name__}",
                regime=regime,
                extra={"strategy_family": str(strategy_family or "")},
            )

    def _load_snapshot_rows(self) -> list[dict]:
        if not os.path.exists(self.snapshot_path):
            return []
        with open(self.snapshot_path, "r", encoding="utf-8") as f:
            payload = json.load(f)
        rows = payload.get("rows", [])
        return rows if isinstance(rows, list) else []

    def _find_snapshot_row(
        self,
        *,
        strategy_id: str,
        market_state: str,
        regime: Optional[str],
    ) -> Optional[Dict[str, Any]]:
        rows = self._load_snapshot_rows()

        exact = None
        state_only = None
        any_row = None

        for row in rows:
            sid = str(row.get("strategy_id") or "UNKNOWN")
            st = str(row.get("market_state") or "UNKNOWN").upper()
            rg = str(row.get("regime") or "UNKNOWN").upper()

            if sid != strategy_id:
                continue

            if any_row is None:
                any_row = row

            if st == market_state and (regime is None or rg == str(regime).upper()):
                exact = row
                break

            if st == market_state and state_only is None:
                state_only = row

        return exact or state_only or any_row

    @staticmethod
    def _maybe_float(x: Any) -> Optional[float]:
        try:
            if x is None:
                return None
            return float(x)
        except Exception:
            return None

    @staticmethod
    def _infer_family(strategy_id: str) -> str:
        sid = str(strategy_id or "").upper()

        # phase-1 conservative mapping
        if sid.startswith("S01") or sid.startswith("S11") or sid.startswith("S12") or sid.startswith("A_"):
            return "TREND"

        if sid.startswith("C_") or sid.startswith("MR_") or sid.startswith("S21") or sid.startswith("S31"):
            return "CHOP"

        return "TREND"

    @staticmethod
    def _state_family_match(*, state: str, family: str) -> bool:
        if state == "TREND":
            return family == "TREND"

        if state == "CHOP":
            return family == "CHOP"

        if state == "HIGH_VOL":
            return family == "TREND"

        if state == "ULTRA_CHOP":
            return False

        return True
