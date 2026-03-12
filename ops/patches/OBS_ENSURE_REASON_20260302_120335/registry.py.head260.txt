# File: tbot/strategies/registry.py
from __future__ import annotations

from tbot.strategies.base import Strategy
from tbot.strategies.s01_core import S01CoreTrend
from tbot.strategies.s11_alpha import S11GapDay
from tbot.strategies.s12_alpha2 import S12AlphaSecondary
from tbot.strategies.s08_alpha_secondary import S08AlphaSecondary
from tbot.policy.strategy_policy import load_policy


def load_strategies() -> list[Strategy]:
    pol = load_policy()

    strategies: list[Strategy] = [
        S01CoreTrend(),
        S11GapDay(),
        S12AlphaSecondary(),
        S08AlphaSecondary(),
    ]

    out: list[Strategy] = []
    for s in strategies:
        p = pol.get(getattr(s, "sid", ""), None)
        if p is None:
            out.append(s)
            continue
        if p.enabled:
            out.append(s)

    return out


