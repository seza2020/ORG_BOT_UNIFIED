from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Dict, Optional


@dataclass(slots=True)
class MetaStrategyDecision:
    decision: str
    reason: str
    market_state: str
    state_confidence: float
    active_family: str
    size_mode: str
    extra: Dict[str, Any] | None = None

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
