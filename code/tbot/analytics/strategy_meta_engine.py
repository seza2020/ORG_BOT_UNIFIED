from __future__ import annotations

import os
from typing import Optional

from .strategy_meta_models import MetaStrategyDecision


class SimpleMetaStrategyEngine:
    """
    Phase-1 meta strategy engine.
    Deterministic, state-aware, audit-friendly.
    """

    def __init__(
        self,
        *,
        min_state_confidence: float = 0.30,
        high_vol_size_mode: str = "REDUCED",
        diag_force_enable: bool = False,
    ) -> None:
        self.min_state_confidence = float(min_state_confidence)
        self.high_vol_size_mode = str(high_vol_size_mode or "REDUCED").upper()
        self.diag_force_enable = bool(diag_force_enable)

    @classmethod
    def from_env(cls) -> "SimpleMetaStrategyEngine":
        min_state_confidence = float(os.getenv("TBOT_META_MIN_STATE_CONF", "0.30") or "0.30")
        high_vol_size_mode = str(os.getenv("TBOT_META_HIGH_VOL_SIZE_MODE", "REDUCED") or "REDUCED")
        diag_force_enable = str(os.getenv("TBOT_META_DIAG_FORCE_ENABLE", "0") or "0").strip().lower() in ("1", "true", "yes", "on")
        return cls(
            min_state_confidence=min_state_confidence,
            high_vol_size_mode=high_vol_size_mode,
            diag_force_enable=diag_force_enable,
        )

    def decide(
        self,
        *,
        market_state: str,
        state_confidence: Optional[float],
    ) -> MetaStrategyDecision:
        try:
            state = str(market_state or "UNKNOWN").upper()
            conf = float(state_confidence or 0.0)

            if conf < self.min_state_confidence:
                if self.diag_force_enable and state == "CHOP":
                    return MetaStrategyDecision(
                        decision="ENABLE",
                        reason="diag_force_enable_after_state_confidence_low",
                        market_state=state,
                        state_confidence=conf,
                        active_family="CHOP",
                        size_mode="FULL",
                        extra={
                            "min_state_confidence": self.min_state_confidence,
                            "diag_force_enable": True,
                            "diag_delta": round(self.min_state_confidence - conf, 6),
                        },
                    )
                return MetaStrategyDecision(
                    decision="STAND_DOWN",
                    reason="state_confidence_low",
                    market_state=state,
                    state_confidence=conf,
                    active_family="NONE",
                    size_mode="OFF",
                    extra={
                        "min_state_confidence": self.min_state_confidence,
                        "diag_force_enable": self.diag_force_enable,
                        "diag_delta": round(self.min_state_confidence - conf, 6),
                    },
                )

            if state == "TREND":
                return MetaStrategyDecision(
                    decision="ENABLE",
                    reason="trend_state_confirmed",
                    market_state=state,
                    state_confidence=conf,
                    active_family="TREND",
                    size_mode="FULL",
                    extra={},
                )

            if state == "CHOP":
                return MetaStrategyDecision(
                    decision="ENABLE",
                    reason="chop_state_confirmed",
                    market_state=state,
                    state_confidence=conf,
                    active_family="CHOP",
                    size_mode="FULL",
                    extra={},
                )

            if state == "HIGH_VOL":
                return MetaStrategyDecision(
                    decision="ENABLE",
                    reason="high_vol_trend_reduced",
                    market_state=state,
                    state_confidence=conf,
                    active_family="TREND",
                    size_mode=self.high_vol_size_mode,
                    extra={},
                )

            if state == "ULTRA_CHOP":
                return MetaStrategyDecision(
                    decision="STAND_DOWN",
                    reason="ultra_chop_no_trade",
                    market_state=state,
                    state_confidence=conf,
                    active_family="NONE",
                    size_mode="OFF",
                    extra={},
                )

            return MetaStrategyDecision(
                decision="STAND_DOWN",
                reason="unknown_market_state",
                market_state=state,
                state_confidence=conf,
                active_family="NONE",
                size_mode="OFF",
                extra={},
            )

        except Exception as e:
            return MetaStrategyDecision(
                decision="STAND_DOWN",
                reason=f"meta_engine_error:{type(e).__name__}",
                market_state=str(market_state or "UNKNOWN").upper(),
                state_confidence=float(state_confidence or 0.0),
                active_family="NONE",
                size_mode="OFF",
                extra={},
            )
