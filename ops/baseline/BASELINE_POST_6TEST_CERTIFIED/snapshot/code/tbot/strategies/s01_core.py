from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Optional, Any

from tbot.strategies.base import Signal, SignalContext

_LAST_DBG_TS = 0.0

def _cc_get(cc: Any, key: str, default: Any = None) -> Any:
    """Read core_context fields whether cc is a dict or an object."""
    if isinstance(cc, dict):
        return cc.get(key, default)
    return getattr(cc, key, default)

def _dbg(line: str) -> None:
    global _LAST_DBG_TS
    now = time.time()
    # throttle to once per 10 seconds
    if now - _LAST_DBG_TS < 10.0:
        return
    _LAST_DBG_TS = now
    try:
        print(line, flush=True)
    except Exception:
        pass

_S01DBG_N = 0

class S01CoreTrend:
    sid: str = "S01"
    is_alpha: bool = False

    def evaluate(self, ctx: SignalContext) -> Optional[Signal]:
        enable = str(os.getenv("TBOT_ENABLE_S01_LOGIC", "0")).strip()
        try:
            min_strength = float(os.getenv("TBOT_S01_MIN_STRENGTH", "0.45"))
        except Exception:
            min_strength = 0.45

        cc = getattr(ctx, "core_context", None)

        # lightweight runtime introspection (safe)
        cc_type = type(cc).__name__
        has_keys = hasattr(cc, "keys")
        try:
            cc_keys = list(cc.keys())[:12] if has_keys else None
        except Exception:
            cc_keys = ["<keys_error>"]

        ts_raw = None
        try:
            ts_raw = _cc_get(cc, "trend_strength", None) if cc is not None else None
        except Exception:
            ts_raw = "<ts_get_error>"
            try:
                _ts = getattr(core_context, "trend_strength", None)
                _bias = getattr(core_context, "bias", None)
                _vwap = getattr(core_context, "vwap_state", None)
                _ema  = getattr(core_context, "ema_sep", None)
                print(f"[S01DBG] enable={enable} min={min_strength} ts={_ts} bias={_bias} vwap={_vwap} ema_sep={_ema}")
            except Exception:
                pass

        if enable != "1":
            return None

        if cc is None:
            return None
        ts = float(_cc_get(cc, "trend_strength", 0.5) or 0.5)
        bias = str(_cc_get(cc, "bias", "NEUTRAL") or "NEUTRAL").upper()
        if bias not in ("LONG","SHORT"):
            return None
        side = bias
        symbol = ctx.symbols[0] if ctx.symbols else "SPY"
        conf_side = ts if side == "LONG" else (1.0 - ts)
        conf = max(0.01, min(0.99, conf_side))
        strength = conf
        if strength < min_strength:
            return None
        try:
            dbg = str(os.getenv("TBOT_S01_DEBUG_SHORT", "0")).strip()
            global _S01DBG_N
            if dbg == "1" and side == "SHORT" and _S01DBG_N < 10:
                _S01DBG_N += 1
                print(f"[S01DBG] symbol={symbol} bias={bias} ts={ts} strength={strength} conf={conf}", flush=True)
        except Exception:
            pass
        return Signal(
            sid=self.sid,
            symbol=str(symbol),
            side=str(side),
            confidence=float(conf),
            reason="s01_corectx_strength",
        )






