# File: tbot/market/replay_provider.py
from __future__ import annotations

import csv
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional


@dataclass(frozen=True)
class ReplayBar:
    symbol: str
    last: float
    vwap: float | None
    ema_fast: float | None
    ema_slow: float | None


class ReplayFeed:
    """
    Deterministic replay feed from CSV.
    CSV columns (required): symbol,last
    Optional: vwap,ema_fast,ema_slow
    """

    def __init__(self, csv_path: str):
        self.csv_path = str(csv_path)
        self._rows: List[ReplayBar] = []
        self._i = 0
        self._load()

    def _load(self) -> None:
        p = Path(self.csv_path)
        if not p.exists():
            raise FileNotFoundError(self.csv_path)

        rows: List[ReplayBar] = []
        with p.open("r", encoding="utf-8", newline="") as f:
            r = csv.DictReader(f)
            for row in r:
                sym = str(row.get("symbol", "")).strip().upper()
                if not sym:
                    continue

                def _f(k: str) -> float | None:
                    v = row.get(k, None)
                    if v is None:
                        return None
                    s = str(v).strip()
                    if s == "":
                        return None
                    try:
                        return float(s)
                    except Exception:
                        return None

                last = _f("last")
                if last is None:
                    continue

                rows.append(
                    ReplayBar(
                        symbol=sym,
                        last=float(last),
                        vwap=_f("vwap"),
                        ema_fast=_f("ema_fast"),
                        ema_slow=_f("ema_slow"),
                    )
                )

        if not rows:
            raise ValueError("replay CSV has no valid rows")

        self._rows = rows
        self._i = 0

    def next_snapshot(self, symbols: tuple[str, ...]) -> Dict[str, dict]:
        """
        Returns dict: symbol -> snapshot fields
        Advances one step per call.
        If file has multiple symbols interleaved, we take the current row
        and only update that symbol.
        """
        if not self._rows:
            return {}

        row = self._rows[self._i % len(self._rows)]
        self._i += 1

        out: Dict[str, dict] = {}
        for s in symbols:
            out[str(s).upper()] = {"symbol": str(s).upper()}

        # Update current row symbol
        out[row.symbol] = {
            "symbol": row.symbol,
            "last": row.last,
            "vwap": row.vwap,
            "ema_fast": row.ema_fast,
            "ema_slow": row.ema_slow,
            "bar_index": self._i,
        }
        return out


_GLOBAL_FEED: ReplayFeed | None = None


def get_replay_snapshot(symbols: tuple[str, ...]) -> Dict[str, dict]:
    global _GLOBAL_FEED
    csv_path = os.getenv("TBOT_REPLAY_CSV", r".\replay\replay.csv")
    if _GLOBAL_FEED is None or _GLOBAL_FEED.csv_path != str(csv_path):
        _GLOBAL_FEED = ReplayFeed(str(csv_path))
    return _GLOBAL_FEED.next_snapshot(symbols)
