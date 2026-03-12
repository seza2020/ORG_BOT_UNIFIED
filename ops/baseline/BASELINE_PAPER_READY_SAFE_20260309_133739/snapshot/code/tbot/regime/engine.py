# File: tbot/regime/engine.py
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Literal, Any
from datetime import datetime

Regime = Literal["TREND", "CHOP", "HIGH_VOL"]


@dataclass(frozen=True)
class RegimeResult:
    regime: Regime
    confidence: float  # 0..1
    detail: dict[str, Any]


def detect_regime(*, now: datetime, market: Any | None) -> RegimeResult:
    """
    Regime detection scaffold.

    Env override (for deterministic tests):
      TBOT_REGIME_FORCE = TREND|CHOP|HIGH_VOL

    SAFE DEFAULT:
    - Returns TREND with low confidence and empty detail.
    """
    _ = (now, market)

    forced = os.getenv("TBOT_REGIME_FORCE", "").strip().upper()
    if forced in ("TREND", "CHOP", "HIGH_VOL"):
        return RegimeResult(regime=forced, confidence=1.0, detail={"forced": True})

    return RegimeResult(regime="TREND", confidence=0.0, detail={})
