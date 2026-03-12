# File: tbot/strategies/s08_alpha_secondary.py
from __future__ import annotations

from tbot.strategies.base import Signal, SignalContext


class S08AlphaSecondary:
    sid = "S08"
    is_alpha = True

    def evaluate(self, ctx: SignalContext) -> Signal | None:
        """
        Secondary Alpha (S08) - SAFE MODE scaffold.

        SAFE MODE:
        - Always returns None (no behavioral change).
        """
        _ = ctx
        return None
