# File: tbot/runtime/state.py
from __future__ import annotations
from dataclasses import dataclass

@dataclass
class RunState:
    in_session: bool = False
    pre_close: bool = False

    alpha_kill: bool = False
    portfolio_kill: bool = False

    pending: bool = False
    active: str | None = None

    daily_r: float = 0.0
    week_r: float = 0.0
