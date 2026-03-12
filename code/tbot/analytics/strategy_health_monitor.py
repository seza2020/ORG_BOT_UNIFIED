from __future__ import annotations

import os

from .strategy_health_models import StrategyHealthDecision


class StrategyHealthMonitor:
    """
    Phase-1 rule-based health monitor.
    Conservative, audit-friendly, no hard disable.
    """

    def __init__(
        self,
        *,
        min_sample: int = 10,
        cooldown_expectancy_r: float = -0.3,
        max_loss_streak: int = 4,
        min_compliance_rate: float = 0.80,
    ) -> None:
        self.min_sample = int(min_sample)
        self.cooldown_expectancy_r = float(cooldown_expectancy_r)
        self.max_loss_streak = int(max_loss_streak)
        self.min_compliance_rate = float(min_compliance_rate)

    @classmethod
    def from_env(cls) -> "StrategyHealthMonitor":
        return cls(
            min_sample=int(os.getenv("TBOT_HEALTH_MIN_SAMPLE", "10") or "10"),
            cooldown_expectancy_r=float(os.getenv("TBOT_HEALTH_COOLDOWN_EXP_R", "-0.3") or "-0.3"),
            max_loss_streak=int(os.getenv("TBOT_HEALTH_MAX_LOSS_STREAK", "4") or "4"),
            min_compliance_rate=float(os.getenv("TBOT_HEALTH_MIN_COMPLIANCE", "0.80") or "0.80"),
        )

    def decide(
        self,
        *,
        strategy_id: str,
        recent_trade_count: int,
        recent_expectancy_r: float,
        recent_win_rate: float,
        loss_streak: int,
        compliance_rate: float,
    ) -> StrategyHealthDecision:
        try:
            sid = str(strategy_id or "UNKNOWN")
            n = int(recent_trade_count or 0)
            exp_r = float(recent_expectancy_r or 0.0)
            win_r = float(recent_win_rate or 0.0)
            ls = int(loss_streak or 0)
            comp = float(compliance_rate or 0.0)

            score = self._health_score(
                recent_trade_count=n,
                recent_expectancy_r=exp_r,
                recent_win_rate=win_r,
                compliance_rate=comp,
            )

            if n < self.min_sample:
                return StrategyHealthDecision(
                    strategy_id=sid,
                    health_state="WATCHLIST",
                    reason="insufficient_sample",
                    health_score=score,
                    recent_trade_count=n,
                    recent_expectancy_r=exp_r,
                    recent_win_rate=win_r,
                    loss_streak=ls,
                    compliance_rate=comp,
                    extra={"min_sample": self.min_sample},
                )

            if exp_r < self.cooldown_expectancy_r:
                return StrategyHealthDecision(
                    strategy_id=sid,
                    health_state="COOLDOWN",
                    reason="negative_expectancy_recent",
                    health_score=score,
                    recent_trade_count=n,
                    recent_expectancy_r=exp_r,
                    recent_win_rate=win_r,
                    loss_streak=ls,
                    compliance_rate=comp,
                    extra={"cooldown_expectancy_r": self.cooldown_expectancy_r},
                )

            if ls >= self.max_loss_streak and comp < self.min_compliance_rate:
                return StrategyHealthDecision(
                    strategy_id=sid,
                    health_state="COOLDOWN",
                    reason="loss_streak_with_low_compliance",
                    health_score=score,
                    recent_trade_count=n,
                    recent_expectancy_r=exp_r,
                    recent_win_rate=win_r,
                    loss_streak=ls,
                    compliance_rate=comp,
                    extra={
                        "max_loss_streak": self.max_loss_streak,
                        "min_compliance_rate": self.min_compliance_rate,
                    },
                )

            return StrategyHealthDecision(
                strategy_id=sid,
                health_state="ACTIVE",
                reason="health_ok",
                health_score=score,
                recent_trade_count=n,
                recent_expectancy_r=exp_r,
                recent_win_rate=win_r,
                loss_streak=ls,
                compliance_rate=comp,
                extra={},
            )

        except Exception as e:
            return StrategyHealthDecision(
                strategy_id=str(strategy_id or "UNKNOWN"),
                health_state="WATCHLIST",
                reason=f"health_monitor_error:{type(e).__name__}",
                health_score=0.0,
                recent_trade_count=int(recent_trade_count or 0),
                recent_expectancy_r=float(recent_expectancy_r or 0.0),
                recent_win_rate=float(recent_win_rate or 0.0),
                loss_streak=int(loss_streak or 0),
                compliance_rate=float(compliance_rate or 0.0),
                extra={},
            )

    @staticmethod
    def _health_score(
        *,
        recent_trade_count: int,
        recent_expectancy_r: float,
        recent_win_rate: float,
        compliance_rate: float,
    ) -> float:
        sample_component = min(1.0, max(0.0, recent_trade_count / 20.0))
        expectancy_component = min(1.0, max(0.0, (recent_expectancy_r + 1.0) / 1.5))
        win_component = min(1.0, max(0.0, recent_win_rate))
        compliance_component = min(1.0, max(0.0, compliance_rate))

        score = (
            0.40 * expectancy_component +
            0.30 * compliance_component +
            0.20 * win_component +
            0.10 * sample_component
        )
        return round(float(score), 4)
