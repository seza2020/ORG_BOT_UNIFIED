# File: tbot/strategies/s12_alpha2.py
from __future__ import annotations

from tbot.strategies.base import Signal, SignalContext


class S12AlphaSecondary:
    sid = "S12"
    is_alpha = True

    def evaluate(self, ctx: SignalContext) -> Signal | None:
        """
        Secondary Alpha (S12) - SAFE MODE scaffold.

        Contract:
        - Must be treated as alpha (is_alpha=True)
        - Must not change behavior until explicitly enabled + logic implemented.

        SAFE MODE:
        - Always returns None.
        """
        _ = ctx
        return None
