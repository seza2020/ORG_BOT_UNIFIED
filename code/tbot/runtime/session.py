# File: tbot/runtime/session.py
from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo


NY = ZoneInfo("America/New_York")


def _to_ny(now: datetime) -> datetime:
    """
    Convert input datetime to America/New_York.

    - If naive, assume UTC (safe default for bots).
    - If aware, convert from its timezone.
    """
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    return now.astimezone(NY)


@dataclass(frozen=True)
class SessionWindow:
    # US equities regular session: 09:30-16:00 ET (end exclusive)
    start_hhmm: tuple[int, int] = (9, 30)
    end_hhmm: tuple[int, int] = (16, 0)
    pre_close_minutes: int = 2

    def in_session(self, now: datetime) -> bool:
        now_et = _to_ny(now)

        # Weekend guard (holidays handled later via market calendar if desired)
        if now_et.weekday() >= 5:
            return False

        s = time(self.start_hhmm[0], self.start_hhmm[1])
        e = time(self.end_hhmm[0], self.end_hhmm[1])
        t = now_et.time()
        return (t >= s) and (t < e)

    def is_pre_close(self, now: datetime) -> bool:
        now_et = _to_ny(now)

        if not self.in_session(now_et):
            return False

        end_dt = now_et.replace(
            hour=self.end_hhmm[0],
            minute=self.end_hhmm[1],
            second=0,
            microsecond=0,
        )
        pre_dt = end_dt - timedelta(minutes=max(0, self.pre_close_minutes))
        return now_et >= pre_dt
