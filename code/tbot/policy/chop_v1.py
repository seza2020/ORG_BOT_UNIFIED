from __future__ import annotations

from dataclasses import dataclass
from typing import Optional
import os


STRATEGY_ID = "CHOP_V1_VWAP_RECLAIM_LIGHT"


@dataclass(frozen=True)
class ChopDecision:
    eligible: bool
    side: str
    entry: Optional[float]
    stop: Optional[float]
    tp: Optional[float]
    rr: Optional[float]
    reason: str
    displacement_pct: float
    ema_spread_pct: float
    price_vs_vwap_pct: float


def decide_chop_v1(
    *,
    last: float,
    vwap: float,
    ema_fast: float,
    ema_slow: float,
    bias: str,
    displacement_min: float = float(os.getenv("TBOT_CHOP_DISPLACEMENT_MIN", "0.0015")),
    chop_ema_spread_max: float = 0.0008,
    stop_pct_fallback: float = 0.0025,
    tp_pct_base: float = 0.0040,
    min_rr: float = 1.5,
) -> ChopDecision:
    """
    CHOP_V1_VWAP_RECLAIM_LIGHT
    Minimal V1 logic based on last/vwap/ema_fast/ema_slow/bias only.
    """

    try:
        last = float(last)
        vwap = float(vwap)
        ema_fast = float(ema_fast)
        ema_slow = float(ema_slow)
    except Exception:
        return ChopDecision(
            eligible=False,
            side="NONE",
            entry=None,
            stop=None,
            tp=None,
            rr=None,
            reason="invalid_numeric_inputs",
            displacement_pct=0.0,
            ema_spread_pct=0.0,
            price_vs_vwap_pct=0.0,
        )

    if last <= 0:
        return ChopDecision(
            eligible=False,
            side="NONE",
            entry=None,
            stop=None,
            tp=None,
            rr=None,
            reason="last_nonpositive",
            displacement_pct=0.0,
            ema_spread_pct=0.0,
            price_vs_vwap_pct=0.0,
        )

    b = str(bias or "FLAT").upper()
    if b not in {"LONG", "SHORT"}:
        return ChopDecision(
            eligible=False,
            side="NONE",
            entry=None,
            stop=None,
            tp=None,
            rr=None,
            reason="flat_or_unknown_bias",
            displacement_pct=0.0,
            ema_spread_pct=0.0,
            price_vs_vwap_pct=0.0,
        )

    displacement_pct = abs(last - vwap) / max(1e-9, last)
    ema_spread_pct = abs(ema_fast - ema_slow) / max(1e-9, last)
    price_vs_vwap_pct = (last - vwap) / max(1e-9, last)

    if ema_spread_pct > chop_ema_spread_max:
        return ChopDecision(
            eligible=False,
            side="NONE",
            entry=None,
            stop=None,
            tp=None,
            rr=None,
            reason=f"ema_spread_too_wide({ema_spread_pct:.6f})",
            displacement_pct=displacement_pct,
            ema_spread_pct=ema_spread_pct,
            price_vs_vwap_pct=price_vs_vwap_pct,
        )

    _disp_mult = float(os.getenv('TBOT_CHOP_DISPLACEMENT_MULT', '1.0') or '1.0')
    if _disp_mult <= 0:
        _disp_mult = 1.0
    displacement_min_default = float(displacement_min)
    _disp_override_raw = os.getenv('TBOT_CHOP_DISPLACEMENT_MIN_OVERRIDE', '').strip()
    try:
        displacement_min = float(_disp_override_raw) if _disp_override_raw else displacement_min_default
    except Exception:
        displacement_min = displacement_min_default
    displacement_min = max(0.0003, min(displacement_min, displacement_min_default))
    # TBOT_CHOP_DISPLACEMENT_MIN_OVERRIDE
    if displacement_pct < displacement_min:
        return ChopDecision(
            eligible=False,
            side="NONE",
            entry=None,
            stop=None,
            tp=None,
            rr=None,
            reason=f"displacement_too_small({displacement_pct:.6f})",
            displacement_pct=displacement_pct,
            ema_spread_pct=ema_spread_pct,
            price_vs_vwap_pct=price_vs_vwap_pct,
        )

    side = "NONE"
    if b == "LONG" and last >= vwap:
        side = "BUY"
    elif b == "SHORT" and last <= vwap:
        side = "SELL"
    else:
        return ChopDecision(
            eligible=False,
            side="NONE",
            entry=None,
            stop=None,
            tp=None,
            rr=None,
            reason="reclaim_not_confirmed",
            displacement_pct=displacement_pct,
            ema_spread_pct=ema_spread_pct,
            price_vs_vwap_pct=price_vs_vwap_pct,
        )

    entry = last

    if side == "BUY":
        stop = min(vwap, last * (1.0 - stop_pct_fallback))
        tp   = last * (1.0 + tp_pct_base)
        risk = entry - stop
        reward = tp - entry
    else:
        stop = max(vwap, last * (1.0 + stop_pct_fallback))
        tp   = last * (1.0 - tp_pct_base)
        risk = stop - entry
        reward = entry - tp

    if risk <= 0 or reward <= 0:
        return ChopDecision(
            eligible=False,
            side="NONE",
            entry=None,
            stop=None,
            tp=None,
            rr=None,
            reason="nonpositive_risk_or_reward",
            displacement_pct=displacement_pct,
            ema_spread_pct=ema_spread_pct,
            price_vs_vwap_pct=price_vs_vwap_pct,
        )

    rr = reward / risk
    if rr < min_rr:
        return ChopDecision(
            eligible=False,
            side="NONE",
            entry=None,
            stop=None,
            tp=None,
            rr=rr,
            reason=f"rr_below_min({rr:.3f})",
            displacement_pct=displacement_pct,
            ema_spread_pct=ema_spread_pct,
            price_vs_vwap_pct=price_vs_vwap_pct,
        )

    return ChopDecision(
        eligible=True,
        side=side,
        entry=round(entry, 6),
        stop=round(stop, 6),
        tp=round(tp, 6),
        rr=round(rr, 6),
        reason="chop_v1_candidate_ok",
        displacement_pct=round(displacement_pct, 6),
        ema_spread_pct=round(ema_spread_pct, 6),
        price_vs_vwap_pct=round(price_vs_vwap_pct, 6),
    )

