# File: tbot/runtime/scorecard_runtime.py
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict


@dataclass
class _SidAgg:
    fires: int = 0
    accepts: int = 0
    sum_r: float = 0.0
    sum_pos: float = 0.0
    sum_neg: float = 0.0
    max_dd: float = 0.0  # placeholder


class RuntimeScorecard:
    """
    MVP runtime scorecard cache (in-memory).
    For shadow readiness, we only need a consistent interface.
    """

    def __init__(self) -> None:
        self._d: Dict[str, _SidAgg] = {}

    def _get(self, sid: str) -> _SidAgg:
        sid = str(sid).upper()
        if sid not in self._d:
            self._d[sid] = _SidAgg()
        return self._d[sid]

    def record_fire(self, sid: str) -> None:
        self._get(sid).fires += 1

    def record_accept(self, sid: str) -> None:
        self._get(sid).accepts += 1

    def record_r(self, sid: str, r: float) -> None:
        a = self._get(sid)
        a.sum_r += float(r)
        if r >= 0:
            a.sum_pos += float(r)
        else:
            a.sum_neg += abs(float(r))

    def get_fires(self, sid: str) -> int:
        return self._get(sid).fires

    def get_accepts(self, sid: str) -> int:
        return self._get(sid).accepts

    def get_avg_r(self, sid: str) -> float:
        a = self._get(sid)
        n = max(1, a.accepts)
        return float(a.sum_r) / float(n)

    def get_pf(self, sid: str) -> float:
        a = self._get(sid)
        if a.sum_neg <= 0:
            return 1.5  # optimistic placeholder when no losses recorded
        return float(a.sum_pos) / float(a.sum_neg)

    def get_dd(self, sid: str) -> float:
        # placeholder DD (requires trade-level R series)
        return float(self._get(sid).max_dd)
