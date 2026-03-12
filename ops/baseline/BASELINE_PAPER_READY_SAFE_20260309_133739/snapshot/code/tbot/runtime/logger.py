# File: tbot/runtime/logger.py
from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime

@dataclass
class Log:
    name: str = "TBOT"

    def info(self, msg: str) -> None:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{self.name}][INFO] {ts} | {msg}")

    def warn(self, msg: str) -> None:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{self.name}][WARN] {ts} | {msg}")

    def error(self, msg: str) -> None:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{self.name}][ERROR] {ts} | {msg}")
