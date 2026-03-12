# File: C:\alpaca-bot\org_bot\tbot\runtime\market_provider.py
from __future__ import annotations

from datetime import datetime
from typing import Iterable

from tbot.strategies.base import MarketSnapshot


def build_market_snapshot(*, now: datetime, symbols: Iterable[str]) -> dict[str, MarketSnapshot]:
    """
    Minimal, safe provider (scaffolding).
    Later you can plug real bars/VWAP/EMA computation here without touching orchestrator/strategies plumbing.
    """
    out: dict[str, MarketSnapshot] = {}
    for sym in symbols:
        out[str(sym)] = MarketSnapshot(symbol=str(sym), ts=now)
    return out
