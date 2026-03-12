# File: tbot/regime/overlay.py
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict

from tbot.regime.engine import Regime


@dataclass(frozen=True)
class RegimeOverlay:
    alpha_mode: str  # "OFF" | "ON" | "CAP50"
    weight_mult: Dict[str, float]


def overlay_for_regime(regime: Regime) -> RegimeOverlay:
    """
    Maps regime -> alpha behavior.

    SAFE DEFAULT:
    - Always ON (no changes) to preserve behavior.
    """
    if regime == "CHOP":
        # Example: alpha limited in chop (can tune later)
        return RegimeOverlay(alpha_mode="CAP50", weight_mult={})
    if regime == "HIGH_VOL":
        # Example: alpha off in high vol (can tune later)
        return RegimeOverlay(alpha_mode="OFF", weight_mult={})
    return RegimeOverlay(alpha_mode="ON", weight_mult={})
