from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Dict


@dataclass(slots=True)
class StrategyHealthDecision:
    strategy_id: str
    health_state: str
    reason: str
    health_score: float
    recent_trade_count: int
    recent_expectancy_r: float
    recent_win_rate: float
    loss_streak: int
    compliance_rate: float
    extra: Dict[str, Any] | None = None

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
