# File: tbot/policy/limits.py
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Dict, Optional

from tbot.policy.strategy_policy import StrategyPolicy, load_policy


@dataclass
class _SidCounters:
    fires: int = 0
    accepts: int = 0
    last_fire_ts: float | None = None


@dataclass
class PolicyLimiter:
    _day: date | None = None
    _counters: Dict[str, _SidCounters] = field(default_factory=dict)

    def _roll_day_if_needed(self, now: datetime) -> None:
        d = now.date()
        if self._day is None or d != self._day:
            self._day = d
            self._counters = {}

    def _get(self, sid: str) -> _SidCounters:
        c = self._counters.get(sid)
        if c is None:
            c = _SidCounters()
            self._counters[sid] = c
        return c

    def can_fire(self, sid: str, now: datetime) -> tuple[bool, str | None]:
        self._roll_day_if_needed(now)
        pol = load_policy().get(sid)
        if pol is None:
            return True, None

        c = self._get(sid)

        if c.fires >= int(pol.max_fires_per_day):
            return False, "policy_fire_cap"

        if int(pol.cooldown_sec) > 0 and c.last_fire_ts is not None:
            dt = now.timestamp() - float(c.last_fire_ts)
            if dt < int(pol.cooldown_sec):
                return False, "policy_cooldown"

        return True, None

    def record_fire(self, sid: str, now: datetime) -> None:
        self._roll_day_if_needed(now)
        c = self._get(sid)
        c.fires += 1
        c.last_fire_ts = now.timestamp()

    def can_accept(self, sid: str, now: datetime) -> tuple[bool, str | None]:
        self._roll_day_if_needed(now)
        pol = load_policy().get(sid)
        if pol is None:
            return True, None
        c = self._get(sid)
        if c.accepts >= int(pol.max_accepts_per_day):
            return False, "policy_accept_cap"
        return True, None

    def record_accept(self, sid: str, now: datetime) -> None:
        self._roll_day_if_needed(now)
        c = self._get(sid)
        c.accepts += 1
