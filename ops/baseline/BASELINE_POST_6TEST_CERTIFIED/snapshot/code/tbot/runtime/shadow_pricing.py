# File: tbot/runtime/shadow_pricing.py
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ShadowPrices:
    entry: float
    stop: float
    tp: float


def _market_get_snap(market: Any | None, sym: str) -> Any | None:
    """
    Supports:
      - dict-like: market.get(sym)
      - MarketSnapshot object that stores symbols as attributes: market.SPY
      - fallback to __dict__[sym]
    """
    if market is None or not sym:
        return None

    # dict-like
    try:
        get_fn = getattr(market, "get", None)
        if callable(get_fn):
            return get_fn(sym)
    except Exception:
        pass

    # attribute-based (MarketSnapshot)
    try:
        if hasattr(market, sym):
            return getattr(market, sym)
    except Exception:
        pass

    # __dict__ fallback
    try:
        d = getattr(market, "__dict__", None)
        if isinstance(d, dict):
            return d.get(sym)
    except Exception:
        pass

    return None


def compute_shadow_prices(
    *,
    sig_payload: dict,
    market: Any | None,
    default_entry: float,
    default_stop: float,
    default_tp: float,
) -> ShadowPrices:
    """
    Computes entry/stop/tp for shadow plans.

    Default behavior (mode=fixed):
      returns the provided defaults (backward-compatible).

    If TBOT_SHADOW_PRICE_MODE=last:
      - entry is set to market last price (if available)
      - stop distance is TBOT_SHADOW_STOP_PCT of entry (bounded)
      - tp is set using TBOT_SHADOW_RR multiple of stop distance
    """
    # --- TBOT_SHADOW_LAST_GUARD_V3 BEGIN ---
    import os as _os
    mode = (_os.getenv('TBOT_SHADOW_PRICE_MODE','fixed') or 'fixed').strip().lower()
    strict = (_os.getenv('TBOT_SHADOW_LAST_STRICT','1') or '1').strip() != '0'
    if strict and mode == 'last':
        _sym = None
        try:
            _sym = sig_payload.get('symbol') if isinstance(sig_payload, dict) else getattr(sig_payload, 'symbol', None)
        except Exception:
            _sym = None
        if _sym:
            try:
                _snap = getattr(market, _sym, None)
                _last = getattr(_snap, 'last', None)
            except Exception:
                _last = None
            if _last is None:
                raise RuntimeError('no_market_last')
    # --- TBOT_SHADOW_LAST_GUARD_V3 END ---

    mode = (os.getenv("TBOT_SHADOW_PRICE_MODE", "fixed") or "fixed").strip().lower()
    rr = float(os.getenv("TBOT_SHADOW_RR", "2.0") or 2.0)
    stop_pct = float(os.getenv("TBOT_SHADOW_STOP_PCT", "0.003") or 0.003)

    entry = float(default_entry)
    stop = float(default_stop)
    tp = float(default_tp)

    # FIXED_MODE_SHORT_NORMALIZE_V1: if mode=fixed, ensure stop/tp align with side
    try:
        side0 = str(sig_payload.get("side", "LONG")).upper()

        if side0 == "SHORT":
            # Interpret defaults as LONG-template distances, then flip for SHORT
            # Ensure stop > entry and tp < entry
            if not (stop > entry and tp < entry):
                _stop_dist = abs(entry - stop)
                _tp_dist = abs(tp - entry)
                stop = entry + _stop_dist
                tp = entry - _tp_dist
        else:
            # LONG: ensure stop < entry and tp > entry (best-effort)
            if not (stop < entry and tp > entry):
                _stop_dist = abs(entry - stop)
                _tp_dist = abs(tp - entry)
                stop = entry - _stop_dist
                tp = entry + _tp_dist
    except Exception:
        pass

    if mode != "last":
        return ShadowPrices(entry=entry, stop=stop, tp=tp)

    try:
        sym = str(sig_payload.get("symbol", "") or "").strip().upper()
        snap = _market_get_snap(market, sym)
        last = getattr(snap, "last", None) if snap is not None else None
        if last is None:
            # --- TBOT_SHADOW_LAST_STRICT_V1 BEGIN ---
            strict = (os.getenv('TBOT_SHADOW_LAST_STRICT','1') or '1').strip() != '0'
            if strict:
                raise RuntimeError('no_market_last')
            # --- TBOT_SHADOW_LAST_STRICT_V1 END ---
            return ShadowPrices(entry=entry, stop=stop, tp=tp)

        entry = float(last)
        dist = max(0.01, abs(entry) * stop_pct)

        side = str(sig_payload.get("side", "LONG")).upper()
        if side == "SHORT":
            stop = entry + dist
            tp = entry - (rr * dist)
        else:
            stop = entry - dist
            tp = entry + (rr * dist)

        return ShadowPrices(entry=entry, stop=stop, tp=tp)
    except Exception:
        return ShadowPrices(entry=entry, stop=stop, tp=tp)

def price_shadow_plan(plan):
    """
    Apply shadow pricing to a ShadowPlan-like object.

    Works with dataclasses (frozen or not) and plain objects/dicts.
    Uses TBOT_SHADOW_PRICE_MODE, TBOT_SHADOW_RR, TBOT_SHADOW_STOP_PCT.
    """
    try:
        import dataclasses
        from tbot.market.market_provider import build_market_snapshot
        from tbot.runtime.shadow_pricing import compute_shadow_prices  # self module, safe
    except Exception:
        return plan

    try:
        symbol = getattr(plan, "symbol", None) or (plan.get("symbol") if isinstance(plan, dict) else None)
        side = getattr(plan, "side", None) or (plan.get("side") if isinstance(plan, dict) else None)
        entry0 = getattr(plan, "entry", None) if not isinstance(plan, dict) else plan.get("entry")
        stop0  = getattr(plan, "stop", None)  if not isinstance(plan, dict) else plan.get("stop")
        tp0    = getattr(plan, "tp", None)    if not isinstance(plan, dict) else plan.get("tp")
        if not symbol or not side:
            return plan
        # build market snapshot for this symbol
        m = build_market_snapshot(symbols=(symbol,))
        p = compute_shadow_prices(
            sig_payload={"symbol": symbol, "side": side},
            market=m,
            default_entry=float(entry0) if entry0 is not None else 100.0,
            default_stop=float(stop0) if stop0 is not None else 101.0,
            default_tp=float(tp0) if tp0 is not None else 98.0,
        )
        # Update plan (dataclass or object or dict)
        if isinstance(plan, dict):
            plan["entry"], plan["stop"], plan["tp"] = float(p.entry), float(p.stop), float(p.tp)
            return plan

        if dataclasses.is_dataclass(plan):
            try:
                return dataclasses.replace(plan, entry=float(p.entry), stop=float(p.stop), tp=float(p.tp))
            except Exception:
                pass

        try:
            setattr(plan, "entry", float(p.entry))
            setattr(plan, "stop",  float(p.stop))
            setattr(plan, "tp",    float(p.tp))
        except Exception:
            pass
        return plan
    except Exception:
        return plan
