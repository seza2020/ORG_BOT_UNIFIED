# File: tbot/runtime/meta.py
from __future__ import annotations

import json
import os
from dataclasses import asdict

from tbot.runtime.events import Event


class MetaWriter:
    def __init__(self, path: str) -> None:
        self.path = path
        os.makedirs(os.path.dirname(path), exist_ok=True)

    def emit(self, ev: Event) -> None:
        # Keep UTF-8 and preserve non-ascii payloads
        line = json.dumps(asdict(ev), ensure_ascii=False)
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
