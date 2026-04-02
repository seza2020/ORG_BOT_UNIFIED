from __future__ import annotations

from typing import Any, Dict, Optional


from tbot.policy.chop_v1 import STRATEGY_ID, decide_chop_v1

_LAST_CHOP_V1_REJECT: Dict[str, Any] = {}

def _set_last_chop_v1_reject(reason: str, **extra):
    global _LAST_CHOP_V1_REJECT
    payload = {"reason": str(reason or "unknown")}
    payload.update(extra)
    _LAST_CHOP_V1_REJECT = payload

def get_last_chop_v1_reject() -> Dict[str, Any]:
    try:
        return dict(_LAST_CHOP_V1_REJECT)
    except Exception:
        return {"reason": "reject_state_unavailable"}


def _get_snap_obj(snapshot, symbol: str = "SPY"):
    try:
        return getattr(snapshot, symbol, None)
    except Exception as e:
        _set_last_chop_v1_reject(f"exception:{type(e).__name__}", err=str(e), symbol=symbol)
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
            _set_last_chop_v1_reject("not_chop_regime", regime=str((regime or {}).get("regime") or ""), path_line=46)
            return None

        snap = _get_snap_obj(snapshot, symbol)
        if snap is None:
            _set_last_chop_v1_reject("snapshot_symbol_missing", symbol=symbol, path_line=51)
            return None

        last = getattr(snap, "last", None)
        vwap = getattr(snap, "vwap", None)
        ema_fast = getattr(snap, "ema_fast", None)
        ema_slow = getattr(snap, "ema_slow", None)
        bias = str((core_ctx or {}).get("bias") or "FLAT").upper()

        if last is None or vwap is None or ema_fast is None or ema_slow is None:
            _set_last_chop_v1_reject(
                "snapshot_fields_missing",
                symbol=symbol,
                has_last=(last is not None),
                has_vwap=(vwap is not None),
                has_ema_fast=(ema_fast is not None),
                has_ema_slow=(ema_slow is not None),
                path_line=68,
            )
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
            _set_last_chop_v1_reject(
                str(getattr(d, "reason", None) or "policy_ineligible"),
                symbol=symbol,
                bias=bias,
                displacement_pct=getattr(d, "displacement_pct", None),
                ema_spread_pct=getattr(d, "ema_spread_pct", None),
                price_vs_vwap_pct=getattr(d, "price_vs_vwap_pct", None),
            )
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




