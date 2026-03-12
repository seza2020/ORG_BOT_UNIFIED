# File: tbot/core/context.py
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

Bias = Literal["LONG", "SHORT", "NEUTRAL"]
VwapState = Literal["ABOVE", "BELOW", "NEAR"]


@dataclass(frozen=True)
class CoreContext:
    bias: Bias
    trend_strength: float  # 0..1
    vwap_state: VwapState
    ema_sep: float
    reason: str
