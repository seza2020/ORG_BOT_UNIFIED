from __future__ import annotations

from dataclasses import asdict, dataclass
import os
from typing import Any, Dict


@dataclass(slots=True)
class PortfolioRiskDecision:
    decision: str
    reason: str
    total_open_risk_r: float
    proposed_risk_r: float
    max_total_risk_r: float
    max_new_risk_r: float
    daily_budget_remaining_r: float
    weekly_budget_remaining_r: float
    extra: Dict[str, Any] | None = None

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class PortfolioRiskEngine:
    """
    Phase-1 portfolio risk engine.
    Conservative, deterministic, audit-friendly.
    """

    def __init__(
        self,
        *,
        max_total_risk_r: float = 3.0,
        max_new_risk_r: float = 1.0,
        daily_budget_r: float = 5.0,
        weekly_budget_r: float = 10.0,
    ) -> None:
        self.max_total_risk_r = float(max_total_risk_r)
        self.max_new_risk_r = float(max_new_risk_r)
        self.daily_budget_r = float(daily_budget_r)
        self.weekly_budget_r = float(weekly_budget_r)

    @classmethod
    def from_env(cls) -> "PortfolioRiskEngine":
        return cls(
            max_total_risk_r=float(os.getenv("TBOT_PORT_MAX_TOTAL_RISK_R", "3.0") or "3.0"),
            max_new_risk_r=float(os.getenv("TBOT_PORT_MAX_NEW_RISK_R", "1.0") or "1.0"),
            daily_budget_r=float(os.getenv("TBOT_PORT_DAILY_BUDGET_R", "5.0") or "5.0"),
            weekly_budget_r=float(os.getenv("TBOT_PORT_WEEKLY_BUDGET_R", "10.0") or "10.0"),
        )

    def decide(
        self,
        *,
        total_open_risk_r: float,
        proposed_risk_r: float,
        daily_budget_remaining_r: float,
        weekly_budget_remaining_r: float,
    ) -> PortfolioRiskDecision:
        total_open_risk_r = float(total_open_risk_r or 0.0)
        proposed_risk_r = float(proposed_risk_r or 0.0)
        daily_budget_remaining_r = float(daily_budget_remaining_r or 0.0)
        weekly_budget_remaining_r = float(weekly_budget_remaining_r or 0.0)

        if daily_budget_remaining_r <= 0:
            return PortfolioRiskDecision(
                decision="BLOCK",
                reason="daily_budget_exhausted",
                total_open_risk_r=total_open_risk_r,
                proposed_risk_r=proposed_risk_r,
                max_total_risk_r=self.max_total_risk_r,
                max_new_risk_r=self.max_new_risk_r,
                daily_budget_remaining_r=daily_budget_remaining_r,
                weekly_budget_remaining_r=weekly_budget_remaining_r,
                extra={},
            )

        if weekly_budget_remaining_r <= 0:
            return PortfolioRiskDecision(
                decision="BLOCK",
                reason="weekly_budget_exhausted",
                total_open_risk_r=total_open_risk_r,
                proposed_risk_r=proposed_risk_r,
                max_total_risk_r=self.max_total_risk_r,
                max_new_risk_r=self.max_new_risk_r,
                daily_budget_remaining_r=daily_budget_remaining_r,
                weekly_budget_remaining_r=weekly_budget_remaining_r,
                extra={},
            )

        if total_open_risk_r >= self.max_total_risk_r:
            return PortfolioRiskDecision(
                decision="BLOCK",
                reason="total_risk_cap",
                total_open_risk_r=total_open_risk_r,
                proposed_risk_r=proposed_risk_r,
                max_total_risk_r=self.max_total_risk_r,
                max_new_risk_r=self.max_new_risk_r,
                daily_budget_remaining_r=daily_budget_remaining_r,
                weekly_budget_remaining_r=weekly_budget_remaining_r,
                extra={},
            )

        if proposed_risk_r > self.max_new_risk_r:
            return PortfolioRiskDecision(
                decision="BLOCK",
                reason="risk_per_trade_too_large",
                total_open_risk_r=total_open_risk_r,
                proposed_risk_r=proposed_risk_r,
                max_total_risk_r=self.max_total_risk_r,
                max_new_risk_r=self.max_new_risk_r,
                daily_budget_remaining_r=daily_budget_remaining_r,
                weekly_budget_remaining_r=weekly_budget_remaining_r,
                extra={},
            )

        if (total_open_risk_r + proposed_risk_r) > self.max_total_risk_r:
            return PortfolioRiskDecision(
                decision="BLOCK",
                reason="post_trade_total_risk_cap",
                total_open_risk_r=total_open_risk_r,
                proposed_risk_r=proposed_risk_r,
                max_total_risk_r=self.max_total_risk_r,
                max_new_risk_r=self.max_new_risk_r,
                daily_budget_remaining_r=daily_budget_remaining_r,
                weekly_budget_remaining_r=weekly_budget_remaining_r,
                extra={},
            )

        return PortfolioRiskDecision(
            decision="ALLOW",
            reason="ok",
            total_open_risk_r=total_open_risk_r,
            proposed_risk_r=proposed_risk_r,
            max_total_risk_r=self.max_total_risk_r,
            max_new_risk_r=self.max_new_risk_r,
            daily_budget_remaining_r=daily_budget_remaining_r,
            weekly_budget_remaining_r=weekly_budget_remaining_r,
            extra={},
        )
