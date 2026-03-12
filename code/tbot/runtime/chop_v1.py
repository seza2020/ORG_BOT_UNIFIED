from __future__ import annotations

from typing import Any, Dict, Optional

from tbot.policy.chop_v1 import STRATEGY_ID, decide_chop_v1


def _get_snap_obj(snapshot, symbol: str = "SPY"):
    try:
        return getattr(snapshot, symbol, None)
    except Exception:
        return None


def build_chop_v1_plan(
    snapshot,
    core_ctx: Dict[str, Any],
    regime: Dict[str, Any],
    run_id: Optional[str] = None,
    symbol: str = "SPY",
) -> Optional[Dict[str, Any]]:
    """
    Build a CHOP_V1 candidate plan from snapshot + core context.
    Returns None if not eligible.
    """

    try:
        if str((regime or {}).get("regime") or "").upper() != "CHOP":
            return None

        snap = _get_snap_obj(snapshot, symbol)
        if snap is None:
            return None

        last = getattr(snap, "last", None)
        vwap = getattr(snap, "vwap", None)
        ema_fast = getattr(snap, "ema_fast", None)
        ema_slow = getattr(snap, "ema_slow", None)
        bias = str((core_ctx or {}).get("bias") or "FLAT").upper()

        if last is None or vwap is None or ema_fast is None or ema_slow is None:
            return None

        d = decide_chop_v1(
            last=float(last),
            vwap=float(vwap),
            ema_fast=float(ema_fast),
            ema_slow=float(ema_slow),
            bias=bias,
            min_rr=1.5,
        )

        if not d.eligible:
            return None

        return {
            "sid": STRATEGY_ID,
            "symbol": symbol,
            "side": d.side,
            "entry": d.entry,
            "stop": d.stop,
            "tp": d.tp,
            "rr": d.rr,
            "reason": d.reason,
            "regime": "CHOP",
            "alpha_mode": "CAP50",
            "confidence": float((regime or {}).get("confidence") or 0.30),
            "extra": {
                "source": "runtime.chop_v1",
                "displacement_pct": d.displacement_pct,
                "ema_spread_pct": d.ema_spread_pct,
                "price_vs_vwap_pct": d.price_vs_vwap_pct,
                "run_id": run_id,
            },
        }
    except Exception:
        return None
