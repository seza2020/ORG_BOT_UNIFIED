# File: tbot/strategies/base.py
from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime
from typing import Literal, Protocol, Any

SignalSide = Literal["LONG", "SHORT"]

@dataclass(frozen=True)
class Signal:
    sid: str
    symbol: str
    side: SignalSide
    confidence: float  # 0..1
    reason: str

@dataclass(frozen=True)
class SignalContext:
    now: datetime
    in_session: bool
    pre_close: bool
    alpha_kill: bool
    portfolio_kill: bool
    symbols: tuple[str, ...]
    market: Any | None = None   # market snapshot provider (read-only)
    # --- policy/runtime attachments (set by orchestrator) ---
    core_context: object | None = None
    alpha_mode: str | None = None
    alpha_cap_ratio: float | None = None



class MarketSnapshot:
    """
    Lightweight snapshot container used by market_provider.

    Intentionally permissive: accepts arbitrary fields via kwargs so that
    market_provider can evolve without breaking imports/tests.
    """
    def __init__(self, *args, **kwargs):
        if args:
            self.args = args
        for k, v in kwargs.items():
            setattr(self, k, v)

    def __repr__(self) -> str:
        keys = sorted([k for k in self.__dict__.keys() if k != "args"])
        return f"MarketSnapshot(keys={keys}, has_args={'args' in self.__dict__})"

class Strategy(Protocol):
    sid: str
    is_alpha: bool

    def evaluate(self, ctx: SignalContext) -> Signal | None:
        ...
