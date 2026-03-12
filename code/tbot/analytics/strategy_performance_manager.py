from __future__ import annotations

import csv
import json
import os
import threading
from datetime import datetime
from typing import Dict, Iterable, Optional, Tuple

from .strategy_perf_models import StrategyPerfEvent, StrategyPerfSnapshot


class StrategyPerformanceManager:
    """
    Safe analytics layer for strategy-level event tracking.

    Design goals:
    - No side effects on trading decisions
    - Append-only event logging
    - Best-effort snapshot generation
    - Graceful failure
    """

    def __init__(self, runroot: str) -> None:
        self.runroot = runroot
        self.logs_dir = os.path.join(runroot, "logs")
        self.events_path = os.path.join(self.logs_dir, "strategy_perf_events.jsonl")
        self.snapshot_path = os.path.join(self.logs_dir, "strategy_perf_snapshot.json")
        self.daily_csv_path = os.path.join(self.logs_dir, "strategy_perf_daily.csv")

        self._lock = threading.Lock()
        self._snapshots: Dict[Tuple[str, str, str], StrategyPerfSnapshot] = {}

        os.makedirs(self.logs_dir, exist_ok=True)

    @classmethod
    def from_env(cls) -> "StrategyPerformanceManager":
        runroot = os.getenv("TBOT_RUNROOT") or os.path.join(os.getcwd(), "runtime", "paper")
        return cls(runroot=runroot)

    def emit(self, event: StrategyPerfEvent) -> None:
        """
        Best-effort append and in-memory aggregation.
        Must never raise into the caller.
        """
        try:
            with self._lock:
                self._append_event(event)
                self._update_snapshot(event)
                self._flush_snapshot()
                self._append_daily_row(event)
        except Exception:
            return

    def emit_simple(
        self,
        *,
        ts: Optional[str],
        strategy_id: str,
        symbol: str,
        event_type: str,
        market_state: str = "UNKNOWN",
        regime: str = "UNKNOWN",
        alpha_mode: str = "OFF",
        reason: str = "",
        confidence: Optional[float] = None,
        rr: Optional[float] = None,
        compliance_ok: bool = True,
        run_id: Optional[str] = None,
        side: Optional[str] = None,
        realized_r: Optional[float] = None,
        hold_minutes: Optional[float] = None,
        extra: Optional[dict] = None,
    ) -> None:
        event = StrategyPerfEvent(
            ts=ts or self._now_str(),
            strategy_id=strategy_id,
            symbol=symbol,
            event_type=event_type,
            market_state=market_state,
            regime=regime,
            alpha_mode=alpha_mode,
            reason=reason,
            confidence=confidence,
            rr=rr,
            compliance_ok=compliance_ok,
            run_id=run_id,
            side=side,
            realized_r=realized_r,
            hold_minutes=hold_minutes,
            extra=extra or {},
        )
        self.emit(event)

    def rebuild_snapshot_from_events(self) -> None:
        try:
            if not os.path.exists(self.events_path):
                return

            fresh: Dict[Tuple[str, str, str], StrategyPerfSnapshot] = {}
            with open(self.events_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    row = json.loads(line)

                    event = StrategyPerfEvent(
                        ts=row.get("ts", self._now_str()),
                        strategy_id=row.get("strategy_id", "UNKNOWN"),
                        symbol=row.get("symbol", "UNKNOWN"),
                        event_type=row.get("event_type", "unknown"),
                        market_state=row.get("market_state", "UNKNOWN"),
                        regime=row.get("regime", "UNKNOWN"),
                        alpha_mode=row.get("alpha_mode", "OFF"),
                        reason=row.get("reason", ""),
                        confidence=row.get("confidence"),
                        rr=row.get("rr"),
                        compliance_ok=bool(row.get("compliance_ok", True)),
                        run_id=row.get("run_id"),
                        side=row.get("side"),
                        realized_r=row.get("realized_r"),
                        hold_minutes=row.get("hold_minutes"),
                        extra=row.get("extra") or {},
                    )

                    key = (event.strategy_id, event.market_state, event.regime)
                    snap = fresh.get(key)
                    if snap is None:
                        snap = StrategyPerfSnapshot(
                            strategy_id=event.strategy_id,
                            market_state=event.market_state,
                            regime=event.regime,
                        )
                        fresh[key] = snap
                    snap.register_event(event)

            with self._lock:
                self._snapshots = fresh
                self._flush_snapshot()
        except Exception:
            return

    def get_snapshot_rows(self) -> Iterable[dict]:
        with self._lock:
            return [snap.to_dict() for snap in self._snapshots.values()]

    def _append_event(self, event: StrategyPerfEvent) -> None:
        with open(self.events_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(event.to_dict(), ensure_ascii=False) + "\n")

    def _update_snapshot(self, event: StrategyPerfEvent) -> None:
        key = (event.strategy_id, event.market_state, event.regime)
        snap = self._snapshots.get(key)
        if snap is None:
            snap = StrategyPerfSnapshot(
                strategy_id=event.strategy_id,
                market_state=event.market_state,
                regime=event.regime,
            )
            self._snapshots[key] = snap
        snap.register_event(event)

    def _flush_snapshot(self) -> None:
        rows = [snap.to_dict() for snap in self._snapshots.values()]
        payload = {
            "ts": self._now_str(),
            "snapshot_count": len(rows),
            "rows": rows,
        }
        with open(self.snapshot_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)

    def _append_daily_row(self, event: StrategyPerfEvent) -> None:
        file_exists = os.path.exists(self.daily_csv_path)
        with open(self.daily_csv_path, "a", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(
                f,
                fieldnames=[
                    "ts",
                    "strategy_id",
                    "symbol",
                    "event_type",
                    "market_state",
                    "regime",
                    "alpha_mode",
                    "reason",
                    "confidence",
                    "rr",
                    "compliance_ok",
                    "run_id",
                    "side",
                    "realized_r",
                    "hold_minutes",
                ],
            )
            if not file_exists:
                writer.writeheader()
            writer.writerow(
                {
                    "ts": event.ts,
                    "strategy_id": event.strategy_id,
                    "symbol": event.symbol,
                    "event_type": event.event_type,
                    "market_state": event.market_state,
                    "regime": event.regime,
                    "alpha_mode": event.alpha_mode,
                    "reason": event.reason,
                    "confidence": event.confidence,
                    "rr": event.rr,
                    "compliance_ok": event.compliance_ok,
                    "run_id": event.run_id,
                    "side": event.side,
                    "realized_r": event.realized_r,
                    "hold_minutes": event.hold_minutes,
                }
            )

    @staticmethod
    def _now_str() -> str:
        return datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
