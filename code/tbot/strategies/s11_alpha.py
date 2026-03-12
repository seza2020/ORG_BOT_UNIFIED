# File: tbot/strategies/s11_alpha.py
from __future__ import annotations

import os
from tbot.strategies.base import Signal, SignalContext
from tbot.runtime.events import make_event


def _env_bool(name: str, default: str = "0") -> bool:
    return os.getenv(name, default).strip().lower() in ("1", "true", "yes", "on")


def _env_float(name: str, default: str) -> float:
    try:
        return float(os.getenv(name, default))
    except Exception:
        return float(default)


class S11GapDay:
    sid = "S11"
    is_alpha = True

    def evaluate(self, ctx: SignalContext) -> Signal | None:
        """
        S11 Alpha (MVP, feature-flagged + tunable)

        Gates:
        - TBOT_ENABLE_S11_MVP=1 enables MVP
        - TBOT_S11_MIN_STRENGTH controls trend_strength threshold (default 0.60)
        - TBOT_S11_MIN_CONF sets confidence (default 0.55)
        """
        if not _env_bool("TBOT_ENABLE_S11_MVP", "0"):
            return None

        min_strength = _env_float("TBOT_S11_MIN_STRENGTH", "0.60")
        conf = _env_float("TBOT_S11_MIN_CONF", "0.55")

        # If orchestrator attached alpha_mode, OFF blocks alpha
        try:
            if str(getattr(ctx, "alpha_mode", "ON")).upper() == "OFF":
                return None
        except Exception:
            pass

        core_ctx = getattr(ctx, "core_context", None)
        if core_ctx is None:
            return None

        try:
            bias = str(getattr(core_ctx, "bias", "NEUTRAL")).upper()
            ts = float(getattr(core_ctx, "trend_strength", 0.0))
        except Exception:
            return None

        if bias != "LONG":
            return None
        if ts < float(min_strength):
            return None

        sym = ctx.symbols[0] if ctx.symbols else "SPY"

        return Signal(
            sid=self.sid,
            symbol=str(sym),
            side="LONG",
            confidence=float(conf),
            reason=f"s11_mvp_corectx_long_ts>={min_strength}",
        )

