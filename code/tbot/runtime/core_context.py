from __future__ import annotations

def _get_snap_obj(snapshot, symbol: str = "SPY"):
    try:
        return getattr(snapshot, symbol, None)
    except Exception:
        return None

def build_core_context(snapshot, regime):
    snap = _get_snap_obj(snapshot, "SPY")
    if snap is None:
        return {"bias": "FLAT", "trend_strength": 0.0, "reason": "core_context_no_spy"}

    last = getattr(snap, "last", None)
    vwap = getattr(snap, "vwap", None)
    ef   = getattr(snap, "ema_fast", None)
    es   = getattr(snap, "ema_slow", None)

    if last is None or ef is None or es is None:
        return {"bias": "FLAT", "trend_strength": 0.0, "reason": "core_context_missing_fields"}

    try:
        last = float(last)
        ef   = float(ef)
        es   = float(es)
        vwap_f = float(vwap) if vwap is not None else None

        ema_sep = abs(ef - es) / max(1e-9, last)

        if ef > es:
            bias = "LONG"
        elif ef < es:
            bias = "SHORT"
        else:
            bias = "FLAT"

        if vwap_f is None:
            vwap_state = "NEAR"
        else:
            dv = (last - vwap_f) / max(1e-9, last)
            if dv > 0.001:
                vwap_state = "ABOVE"
            elif dv < -0.001:
                vwap_state = "BELOW"
            else:
                vwap_state = "NEAR"

        trend_strength = min(1.0, ema_sep * 240.0)

        if bias == "FLAT":
            trend_strength = 0.0

        return {
"bias": bias,
            "trend_strength": round(float(trend_strength), 4),
            "vwap_state": vwap_state,
            "ema_sep": round(float(ema_sep), 6),
            "symbol": getattr(snap, "symbol", "SPY"),
            "provider_name": getattr(snap, "provider_name", None),
            "input_trade_ts": getattr(snap, "input_trade_ts", getattr(snap, "source_trade_ts", None)),
            "input_bar_ts": getattr(snap, "input_bar_ts", getattr(snap, "source_bar_ts", None)),
            "latest_trade_ts": getattr(snap, "latest_trade_ts", getattr(snap, "source_trade_ts", None)),
            "latest_bar_ts": getattr(snap, "latest_bar_ts", getattr(snap, "source_bar_ts", None)),
            "trade_age_sec": getattr(snap, "trade_age_sec", None),
            "bar_age_sec": getattr(snap, "bar_age_sec", None),
            "source_stale": getattr(snap, "source_stale", None),
            "stale_reason": getattr(snap, "stale_reason", None),
            "trade_fetch_ok": getattr(snap, "trade_fetch_ok", None),
            "bars_fetch_ok": getattr(snap, "bars_fetch_ok", None),
            "reason": "core_context_from_snapshot_v1",
        }
    except Exception as e:
        return {"bias": "FLAT", "trend_strength": 0.0, "reason": f"core_context_exception:{type(e).__name__}"}


