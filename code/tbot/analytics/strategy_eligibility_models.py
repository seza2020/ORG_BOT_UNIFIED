from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Dict, Optional


@dataclass(slots=True)
class StrategyEligibilityDecision:
    strategy_id: str
    market_state: str
    eligible: bool
    reason: str

    event_count: int = 0
    expectancy_r: Optional[float] = None
    win_rate: Optional[float] = None
    regime: Optional[str] = None
    extra: Dict[str, Any] | None = None

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
