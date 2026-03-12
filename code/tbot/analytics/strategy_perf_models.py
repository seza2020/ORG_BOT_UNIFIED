from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Dict, Optional


@dataclass(slots=True)
class StrategyPerfEvent:
    ts: str
    strategy_id: str
    symbol: str
    event_type: str

    market_state: str = "UNKNOWN"
    regime: str = "UNKNOWN"
    alpha_mode: str = "OFF"
    reason: str = ""
    confidence: Optional[float] = None
    rr: Optional[float] = None
    compliance_ok: bool = True

    run_id: Optional[str] = None
    side: Optional[str] = None
    realized_r: Optional[float] = None
    hold_minutes: Optional[float] = None

    extra: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(slots=True)
class StrategyPerfSnapshot:
    strategy_id: str
    market_state: str
    regime: str

    event_count: int = 0
    plan_created_count: int = 0
    plan_skipped_count: int = 0
    rejection_count: int = 0
    alpha_off_count: int = 0

    confidence_sum: float = 0.0
    confidence_count: int = 0

    rr_sum: float = 0.0
    rr_count: int = 0

    realized_r_sum: float = 0.0
    realized_r_count: int = 0
    win_count: int = 0
    loss_count: int = 0

    def register_event(self, event: StrategyPerfEvent) -> None:
        self.event_count += 1

        if event.event_type == "plan_created":
            self.plan_created_count += 1
        elif event.event_type == "plan_skipped":
            self.plan_skipped_count += 1
        elif event.event_type == "rejection_reason":
            self.rejection_count += 1

        if event.reason == "alpha_mode_off":
            self.alpha_off_count += 1

        if event.confidence is not None:
            self.confidence_sum += float(event.confidence)
            self.confidence_count += 1

        if event.rr is not None:
            self.rr_sum += float(event.rr)
            self.rr_count += 1

        if event.realized_r is not None:
            rr = float(event.realized_r)
            self.realized_r_sum += rr
            self.realized_r_count += 1
            if rr > 0:
                self.win_count += 1
            elif rr < 0:
                self.loss_count += 1

    @property
    def avg_confidence(self) -> Optional[float]:
        if self.confidence_count <= 0:
            return None
        return self.confidence_sum / self.confidence_count

    @property
    def avg_rr(self) -> Optional[float]:
        if self.rr_count <= 0:
            return None
        return self.rr_sum / self.rr_count

    @property
    def expectancy_r(self) -> Optional[float]:
        if self.realized_r_count <= 0:
            return None
        return self.realized_r_sum / self.realized_r_count

    @property
    def win_rate(self) -> Optional[float]:
        closed = self.win_count + self.loss_count
        if closed <= 0:
            return None
        return self.win_count / closed

    def to_dict(self) -> Dict[str, Any]:
        return {
            "strategy_id": self.strategy_id,
            "market_state": self.market_state,
            "regime": self.regime,
            "event_count": self.event_count,
            "plan_created_count": self.plan_created_count,
            "plan_skipped_count": self.plan_skipped_count,
            "rejection_count": self.rejection_count,
            "alpha_off_count": self.alpha_off_count,
            "avg_confidence": self.avg_confidence,
            "avg_rr": self.avg_rr,
            "expectancy_r": self.expectancy_r,
            "win_rate": self.win_rate,
            "realized_r_count": self.realized_r_count,
            "win_count": self.win_count,
            "loss_count": self.loss_count,
        }
