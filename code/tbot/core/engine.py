# File: tbot/core/engine.py
from __future__ import annotations

import os
from tbot.core.context import CoreContext

# ORCH_OBS_REASON_v1 (observability only): explain which inputs are missing/invalid
import math

def _missing_reason(*, last, vwap, ef, es) -> str:
    missing = []
    def ok(x) -> bool:
        try:
            if x is None:
                return False
            f = float(x)
            return math.isfinite(f)
        except Exception:
            return False

    if not ok(last): missing.append("last")
    if not ok(vwap): missing.append("vwap")
    if not ok(ef):   missing.append("ef")
    if not ok(es):   missing.append("es")

    if missing:
        return "no_data:" + ",".join(missing)
    return "ok"



def detect_core_context(*, symbol: str, snap) -> CoreContext:
    """
    Core context detector (calibrated).
    Uses market snapshot fields:
      last, vwap, ema_fast, ema_slow
    Returns a stable context for policy layer.

    TBOT_CORE_STRENGTH_SCALE:
      - Scales trend_strength sensitivity for different providers (replay vs live).
    """
    # TBOT_EFES_COMPAT_V3
    # MarketSnap uses ema_fast/ema_slow; engine historically expects ef/es.
    def _get_field(obj, *names):
        for n in names:
            try:
                v = getattr(obj, n, None)
            except Exception:
                v = None
            if v is not None:
                return v
        return None

    last = getattr(snap, "last", None)
    vwap = getattr(snap, "vwap", None)
    ef = getattr(snap, "ema_fast", None)
    es = getattr(snap, "ema_slow", None)

    if last is None or vwap is None or ef is None or es is None:
        return CoreContext(
            bias="NEUTRAL",
            trend_strength=0.0,
            vwap_state="NEAR",
            ema_sep=0.0,
            reason=_missing_reason(last=last, vwap=vwap, ef=ef, es=es),
        )

    last = float(last)
    vwap = float(vwap)
    ef = float(ef)
    es = float(es)

    ema_sep = abs(ef - es)
    denom = max(1e-9, abs(es))

    # Base separation normalization
    sep_norm = (ema_sep / denom)

    # Provider calibration scale
    try:
        scale = float(os.getenv("TBOT_CORE_STRENGTH_SCALE", "1.0"))
    except Exception:
        scale = 1.0
    if scale <= 0:
        scale = 1.0

    # Bound to 0..1 after scaling
    sep_scaled = min(1.0, sep_norm * float(scale))

    # Bias from EMA ordering
    if ef > es:
        bias = "LONG"
    elif ef < es:
        bias = "SHORT"
    else:
        bias = "NEUTRAL"

    # VWAP state
    dv = last - vwap
    if abs(dv) < max(0.02, abs(vwap) * 0.0001):
        vwap_state = "NEAR"
    elif dv > 0:
        vwap_state = "ABOVE"
    else:
        vwap_state = "BELOW"

    # Alignment bonus
    align = 0.0
    if bias == "LONG" and vwap_state == "ABOVE":
        align = 0.5
    elif bias == "SHORT" and vwap_state == "BELOW":
        align = 0.5

    strength = min(1.0, 0.5 * sep_scaled + align)

    return CoreContext(
        bias=bias,
        trend_strength=float(strength),
        vwap_state=vwap_state,
        ema_sep=float(ema_sep),
        reason="core_ctx_v2_scaled",
    )

