# -*- coding: utf-8 -*-
"""
Engine-native Observability (Production-grade, minimal deps)

Outputs (under runroot):
- logs/meta_engine.jsonl                      (events)
- logs/engine_daily_metrics_YYYYMMDD.json     (daily counters)

Design goals:
- Never crash the engine; failures are swallowed.
- Structured JSONL events; fast append.
- Works even if runroot is missing (falls back to TBOT_RUNROOT/TBOT_RUNTIME).
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass, field
from typing import Any, Dict, Optional

def _utc_ts() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def _ymd() -> str:
    return time.strftime("%Y%m%d", time.localtime())

def _safe_mkdir(p: str) -> None:
    os.makedirs(p, exist_ok=True)

def _resolve_runroot(ctx: Any = None) -> Optional[str]:
    rr = None
    try:
        if ctx is not None:
            rr = getattr(ctx, "runroot", None)
    except Exception:
        rr = None
    if not rr:
        rr = os.environ.get("TBOT_RUNROOT") or os.environ.get("TBOT_RUNTIME")
    return rr

def _log_dir(runroot: str) -> str:
    return os.path.join(runroot, "logs")

def _event_path(runroot: str) -> str:
    return os.path.join(_log_dir(runroot), "meta_engine.jsonl")

def _daily_path(runroot: str, ymd: str) -> str:
    return os.path.join(_log_dir(runroot), f"engine_daily_metrics_{ymd}.json")

def _append_jsonl(path: str, obj: Dict[str, Any]) -> None:
    _safe_mkdir(os.path.dirname(path))
    line = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    with open(path, "a", encoding="utf-8") as f:
        f.write(line + "\n")

def _atomic_write(path: str, obj: Dict[str, Any]) -> None:
    _safe_mkdir(os.path.dirname(path))
    tmp = f"{path}.tmp.{int(time.time()*1000)}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)

@dataclass
class Counters:
    fires: int = 0
    accepts: int = 0
    rejects: int = 0
    orders_submit: int = 0
    orders_err: int = 0
    atomic_ok: int = 0
    atomic_fail: int = 0
    hb: int = 0
    reject_reasons: Dict[str, int] = field(default_factory=dict)

    def inc_reason(self, reason: str) -> None:
        if not reason:
            reason = "unknown"
        self.reject_reasons[reason] = self.reject_reasons.get(reason, 0) + 1

class Telemetry:
    """
    One instance per process recommended.
    """
    def __init__(self, runroot: Optional[str] = None):
        self.runroot = runroot
        self._c = Counters()
        self._last_flush = 0.0

    def set_runroot(self, runroot: Optional[str]) -> None:
        if runroot:
            self.runroot = runroot

    def event(self, *, name: str, ctx: Any = None, **fields: Any) -> None:
        try:
            rr = self.runroot or _resolve_runroot(ctx)
            if not rr:
                return
            obj: Dict[str, Any] = {"ts": _utc_ts(), "name": name}
            # common fields (best-effort)
            try:
                if ctx is not None:
                    obj["env"] = getattr(ctx, "env", None)
                    obj["sid"] = getattr(ctx, "sid", None)
                    obj["symbol"] = getattr(ctx, "symbol", None)
            except Exception:
                pass
            obj.update(fields)
            _append_jsonl(_event_path(rr), obj)
        except Exception:
            # never let telemetry kill the bot
            return

    def count(self, *, kind: str, reason: Optional[str] = None) -> None:
        try:
            if kind == "fire":
                self._c.fires += 1
            elif kind == "accept":
                self._c.accepts += 1
            elif kind == "reject":
                self._c.rejects += 1
                if reason:
                    self._c.inc_reason(reason)
            elif kind == "order_submit":
                self._c.orders_submit += 1
            elif kind == "order_err":
                self._c.orders_err += 1
            elif kind == "atomic_ok":
                self._c.atomic_ok += 1
            elif kind == "atomic_fail":
                self._c.atomic_fail += 1
            elif kind == "hb":
                self._c.hb += 1
        except Exception:
            return

    def flush_daily(self, *, ctx: Any = None, force: bool = False) -> None:
        try:
            now = time.time()
            if not force and (now - self._last_flush) < 30.0:
                return
            rr = self.runroot or _resolve_runroot(ctx)
            if not rr:
                return
            y = _ymd()
            obj = {
                "ts": _utc_ts(),
                "ymd": y,
                "fires": self._c.fires,
                "accepts": self._c.accepts,
                "rejects": self._c.rejects,
                "orders_submit": self._c.orders_submit,
                "orders_err": self._c.orders_err,
                "atomic_ok": self._c.atomic_ok,
                "atomic_fail": self._c.atomic_fail,
                "hb": self._c.hb,
                "reject_reasons": dict(self._c.reject_reasons),
            }
            _atomic_write(_daily_path(rr, y), obj)
            self._last_flush = now
        except Exception:
            return

# global singleton (safe)
TELEM = Telemetry()