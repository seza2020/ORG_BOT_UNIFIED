from __future__ import annotations
import os

def _get_snap_obj(snapshot, symbol: str = "SPY"):
    try:
        return getattr(snapshot, symbol, None)
    except Exception:
        return None

def compute_regime(snapshot):
    snap = _get_snap_obj(snapshot, "SPY")
    if snap is None:
        return {"regime": "CHOP", "confidence": 0.0, "alpha_mode": "OFF", "reason": "regime_no_spy"}

    last = getattr(snap, "last", None)
    vwap = getattr(snap, "vwap", None)
    ef   = getattr(snap, "ema_fast", None)
    es   = getattr(snap, "ema_slow", None)

    if last is None or ef is None or es is None:
        return {"regime": "CHOP", "confidence": 0.0, "alpha_mode": "OFF", "reason": "regime_missing_fields"}

    try:
        spread = abs(float(ef) - float(es)) / max(1e-9, float(last))
        direction = 1 if float(ef) >= float(es) else -1
        price_vs_vwap = 0.0
        if vwap is not None:
            price_vs_vwap = (float(last) - float(vwap)) / max(1e-9, float(last))

        if spread >= 0.0025:
            regime = "TREND"
            conf = min(1.0, 0.55 + spread * 40.0)
            reason = f"trend_spread({spread:.4f})"
        elif spread <= 0.0008:
            regime = "CHOP"
            conf = max(0.0, 0.35 - spread * 50.0)
            reason = f"chop_spread({spread:.4f})"
        else:
            regime = "CHOP"
            conf = 0.40
            reason = f"mid_spread({spread:.4f})"

        high_vol_th = float(os.getenv("TBOT_REGIME_HIGH_VOL_PVWAP_TH","0.01") or "0.01")
        if abs(price_vs_vwap) >= high_vol_th:
            regime = "HIGH_VOL"
            conf = min(1.0, max(conf, 0.65))
            reason = f"high_vol_pvwap({price_vs_vwap:.4f})"

        return {
            "regime": regime,
            "confidence": round(float(conf), 4),
            "alpha_mode": "OFF",
            "reason": reason,
            "direction": direction,
            "metrics": {
                "last": last,
                "vwap": vwap,
                "ema_fast": ef,
                "ema_slow": es,
                "ema_spread_pct": round(float(spread), 6),
                "price_vs_vwap_pct": round(float(price_vs_vwap), 6),
            },
        }
    except Exception as e:
        return {"regime": "CHOP", "confidence": 0.0, "alpha_mode": "OFF", "reason": f"regime_exception:{type(e).__name__}"}
