# File: tbot/runtime/orch_bridge.py
from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Optional


@dataclass
class OrchBridgeWriter:
    """
    Minimal bridge writer to stabilize orchestrator import:
      from tbot.runtime.orch_bridge import OrchBridgeWriter

    Safe behavior:
      - If env flags disable orch/jsonl, it is a no-op.
      - Never raises exceptions into the trading loop.
    """
    enabled: bool = False
    path: str = ""

    @classmethod
    def from_env(cls) -> "OrchBridgeWriter":
        enabled = (os.environ.get("TBOT_ENABLE_ORCH", "0") == "1") and (os.environ.get("TBOT_ORCH_JSONL", "0") == "1")
        path = os.environ.get("TBOT_ORCH_JSONL_PATH", "") or os.environ.get("TBOT_ORCH_META_PATH", "")
        return cls(enabled=enabled, path=path)

    def write(self, kind: str, payload: Any, ts: Optional[datetime] = None) -> None:
        if not self.enabled:
            return
        try:
            import json
            rec = {
                "ts": (ts or datetime.utcnow()).isoformat(),
                "kind": kind,
                "payload": payload,
            }
            if not self.path:
                return
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        except Exception:
            return

    def close(self) -> None:
        return
