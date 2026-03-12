# File: tbot/runtime/ledger.py
from __future__ import annotations

import csv
import json
import os
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any


@dataclass(frozen=True)
class TradeRecord:
    ts: str
    event: str        # OPEN/CLOSE
    env: str
    symbol: str
    sid: str
    side: str         # LONG/SHORT
    qty: int
    entry: float
    stop: float
    tp: float
    exit: float | None
    r: float | None
    reason: str


class TradeLedger:
    def __init__(self, *, base_dir: str) -> None:
        self.base_dir = base_dir
        os.makedirs(self.base_dir, exist_ok=True)

    def _day_tag(self) -> str:
        return datetime.now().strftime("%Y%m%d")

    def _csv_path(self) -> str:
        return os.path.join(self.base_dir, f"trades_{self._day_tag()}.csv")

    def _jsonl_path(self) -> str:
        return os.path.join(self.base_dir, f"trades_{self._day_tag()}.jsonl")

    def append(self, tr: TradeRecord) -> None:
        self._append_csv(tr)
        self._append_jsonl(tr)

    def _expected_header(self) -> list[str]:
        return [
            "ts","event","env","symbol","sid","side","qty",
            "entry","stop","tp","exit","r","reason"
        ]

    def _ensure_csv_schema(self, path: str) -> None:
        # If file exists but header mismatches, rename it and start fresh.
        if not os.path.exists(path):
            return

        try:
            with open(path, "r", encoding="utf-8") as f:
                first = f.readline().strip()
        except Exception:
            first = ""

        expected = ",".join(self._expected_header())
        if first != expected:
            legacy = path.replace(".csv", f"_legacy_{self._day_tag()}.csv")
            try:
                os.replace(path, legacy)
            except Exception:
                # fallback: leave as-is if rename fails
                return

    def _append_csv(self, tr: TradeRecord) -> None:
        path = self._csv_path()
        self._ensure_csv_schema(path)

        header = self._expected_header()
        file_exists = os.path.exists(path)

        with open(path, "a", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=header)
            if not file_exists:
                w.writeheader()
            row = asdict(tr)
            w.writerow({k: row.get(k, "") for k in header})

    def _append_jsonl(self, tr: TradeRecord) -> None:
        path = self._jsonl_path()
        line = json.dumps(asdict(tr), ensure_ascii=False)
        with open(path, "a", encoding="utf-8") as f:
            f.write(line + "\n")


def make_trade_record(**kwargs: Any) -> TradeRecord:
    kwargs = dict(kwargs)
    kwargs.setdefault("ts", datetime.now().isoformat(timespec="seconds"))
    return TradeRecord(**kwargs)
