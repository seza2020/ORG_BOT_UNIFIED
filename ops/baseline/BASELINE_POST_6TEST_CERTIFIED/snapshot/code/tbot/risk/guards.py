# File: tbot/risk/guards.py
from __future__ import annotations
from dataclasses import dataclass

@dataclass
class RiskState:
    daily_r: float = 0.0
    week_r: float = 0.0

    alpha_kill: bool = False   # alpha OFF (but core can continue)
    portfolio_kill: bool = False  # full kill / lock state (policy decides behavior later)

def apply_kill_rules(rs: RiskState, *, daily_alpha_kill_r: float, weekly_kill_r: float) -> RiskState:
    rs.alpha_kill = (rs.daily_r <= daily_alpha_kill_r)
    rs.portfolio_kill = (rs.week_r <= weekly_kill_r)
    return rs
