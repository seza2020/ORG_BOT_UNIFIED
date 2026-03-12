# File: tbot/policy/alpha_mode.py
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

AlphaMode = Literal["ON", "CAP50", "OFF"]


@dataclass(frozen=True)
class AlphaDecision:
    mode: AlphaMode
    cap_ratio: float  # 1.0 / 0.5 / 0.0
    reason: str


def decide_alpha_mode(*, regime: str, bias: str, trend_strength: float) -> AlphaDecision:
    import os

    r = str(regime).upper()
    b = str(bias).upper()
    ts = float(trend_strength or 0.0)

    # Thresholds (defaults preserve current behavior)
    TREND_ON_TH  = float(os.getenv("TBOT_ALPHA_TREND_ON_TH",  "0.60"))
    TREND_CAP_TH = float(os.getenv("TBOT_ALPHA_TREND_CAP_TH", "0.35"))
    CHOP_CAP_TH  = float(os.getenv("TBOT_ALPHA_CHOP_CAP_TH",  "0.75"))

    # Hard blocks
    if r == "HIGH_VOL":
        return AlphaDecision(mode="OFF", cap_ratio=0.0, reason=f"alpha_off_high_vol(ts={ts:.3f})")

    # Chop
    if r == "CHOP":
        if ts >= CHOP_CAP_TH:
            return AlphaDecision(mode="CAP50", cap_ratio=0.5, reason=f"alpha_cap_chop_strong(ts={ts:.3f},th={CHOP_CAP_TH:.2f})")
        return AlphaDecision(mode="OFF", cap_ratio=0.0, reason=f"alpha_off_chop(ts={ts:.3f})")

    # Trend: scale by strength
    if r == "TREND":
        if ts >= TREND_ON_TH:
            return AlphaDecision(mode="ON", cap_ratio=1.0, reason=f"alpha_on_trend(ts={ts:.3f},th={TREND_ON_TH:.2f})")
        if ts >= TREND_CAP_TH:
            return AlphaDecision(mode="CAP50", cap_ratio=0.5, reason=f"alpha_cap_trend(ts={ts:.3f},th={TREND_CAP_TH:.2f})")
        return AlphaDecision(mode="OFF", cap_ratio=0.0, reason=f"alpha_off_trend_weak(ts={ts:.3f},th={TREND_CAP_TH:.2f})")

    # Default safe
    return AlphaDecision(mode="OFF", cap_ratio=0.0, reason=f"alpha_off_unknown_regime(ts={ts:.3f},r={r})")

