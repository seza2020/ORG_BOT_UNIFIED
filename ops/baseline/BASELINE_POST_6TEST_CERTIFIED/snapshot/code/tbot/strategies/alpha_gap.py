# File: tbot/strategies/alpha_gap.py
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

AlphaSide = Literal["LONG", "SHORT", "FLAT"]

@dataclass(frozen=True)
class AlphaSignal:
    side: AlphaSide  # 'LONG'/'SHORT'/'FLAT'
    reason: str
    confidence: float = 0.5  # 0..1


def compute_alpha_signal(*args, **kwargs) -> AlphaSignal:
    """
    Placeholder for Alpha Gap Day / ORB logic.

    NOTE:
    SignalContext currently does not include market data, so default is FLAT.
    """
    return AlphaSignal(side="FLAT", reason="TODO(alpha)", confidence=0.0)
