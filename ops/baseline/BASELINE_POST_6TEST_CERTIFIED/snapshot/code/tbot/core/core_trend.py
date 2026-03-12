# File: tbot/strategies/core_trend.py
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal


CoreSide = Literal["LONG", "SHORT", "FLAT"]


@dataclass(frozen=True)
class CoreSignal:
    side: CoreSide  # "LONG" / "SHORT" / "FLAT"
    reason: str
    confidence: float = 0.5  # 0..1


def compute_core_signal(*args, **kwargs) -> CoreSignal:
    """
    Helper module for Core Trend logic.

    Important:
    - This file is NOT a Strategy and must NOT be registered as a standalone strategy.
    - It intentionally returns FLAT by default (scaffolding only).
    """
    return CoreSignal(side="FLAT", reason="TODO(core)", confidence=0.0)
