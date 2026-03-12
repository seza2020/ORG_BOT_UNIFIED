# -*- coding: utf-8 -*-
"""
Atomic Risk Ledger (Production-grade)

Goal:
- Prevent risk double-spend across restarts / concurrent processes.
- Provide atomic reserve/commit/release using a lock file + atomic replace.

Design:
- One JSON file per day under: <runroot>/state/risk_atomic_<YYYYMMDD>.json
- Records:
  - reserved_usd
  - used_usd
  - reservations map: {rid: {usd, ts, meta}}
- Reserve must happen BEFORE any order/execution is allowed.
- On failure after reserve, caller must release reservation.

This module is intentionally dependency-free.
"""

from __future__ import annotations

import json
import os
import time
import uuid
from dataclasses import dataclass
from typing import Any, Dict, Optional

@dataclass
class AtomicResult:
    ok: bool
    rid: Optional[str] = None
    reason: Optional[str] = None
    path: Optional[str] = None
    reserved_usd: float = 0.0
    used_usd: float = 0.0
    remaining_usd: float = 0.0

def _utc_ts() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def _ensure_dir(p: str) -> None:
    os.makedirs(p, exist_ok=True)

def _atomic_write_json(path: str, obj: Dict[str, Any]) -> None:
    tmp = f"{path}.tmp.{uuid.uuid4().hex}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        f.flush()
        os.fsync(f.fileno())
    # atomic replace on Windows is supported by os.replace
    os.replace(tmp, path)

def _default_state() -> Dict[str, Any]:
    return {
        "version": 1,
        "ts": _utc_ts(),
        "reserved_usd": 0.0,
        "used_usd": 0.0,
        "reservations": {},  # rid -> {usd, ts, meta}
    }

def _load_state(path: str) -> Dict[str, Any]:
    if not os.path.exists(path):
        return _default_state()
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def _lock_path(state_path: str) -> str:
    return state_path + ".lock"

class FileLock:
    """
    Minimal file lock using exclusive create.
    """
    def __init__(self, path: str, timeout_sec: float = 5.0, poll_sec: float = 0.05):
        self.path = path
        self.timeout_sec = timeout_sec
        self.poll_sec = poll_sec
        self._fd = None

    def __enter__(self):
        t0 = time.time()
        while True:
            try:
                # exclusive create
                self._fd = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_RDWR)
                os.write(self._fd, _utc_ts().encode("utf-8"))
                return self
            except FileExistsError:
                if time.time() - t0 > self.timeout_sec:
                    raise TimeoutError(f"LOCK_TIMEOUT: {self.path}")
                time.sleep(self.poll_sec)

    def __exit__(self, exc_type, exc, tb):
        try:
            if self._fd is not None:
                os.close(self._fd)
        finally:
            try:
                if os.path.exists(self.path):
                    os.remove(self.path)
            except Exception:
                # never raise on unlock
                pass

def _state_file(runroot: str, ymd: str) -> str:
    state_dir = os.path.join(runroot, "state")
    _ensure_dir(state_dir)
    return os.path.join(state_dir, f"risk_atomic_{ymd}.json")

def reserve_risk_atomic(
    *,
    runroot: str,
    ymd: str,
    reserve_usd: float,
    max_risk_per_day_usd: float,
    meta: Optional[Dict[str, Any]] = None,
) -> AtomicResult:
    if not runroot:
        return AtomicResult(ok=False, reason="RUNROOT_MISSING")
    if reserve_usd <= 0:
        return AtomicResult(ok=False, reason="RESERVE_NONPOSITIVE")
    if max_risk_per_day_usd <= 0:
        return AtomicResult(ok=False, reason="MAXDAY_NONPOSITIVE")

    path = _state_file(runroot, ymd)
    lock = _lock_path(path)

    try:
        with FileLock(lock, timeout_sec=8.0):
            st = _load_state(path)
            reserved = float(st.get("reserved_usd", 0.0))
            used = float(st.get("used_usd", 0.0))
            remaining = max_risk_per_day_usd - (reserved + used)
            if reserve_usd > remaining + 1e-9:
                return AtomicResult(
                    ok=False,
                    reason="RISK_ABOVE_MAXDAY",
                    path=path,
                    reserved_usd=reserved,
                    used_usd=used,
                    remaining_usd=remaining,
                )

            rid = uuid.uuid4().hex
            st["ts"] = _utc_ts()
            st["reserved_usd"] = reserved + reserve_usd
            st.setdefault("reservations", {})[rid] = {
                "usd": reserve_usd,
                "ts": _utc_ts(),
                "meta": meta or {},
            }
            _atomic_write_json(path, st)

            remaining2 = max_risk_per_day_usd - (float(st["reserved_usd"]) + float(st.get("used_usd", 0.0)))
            return AtomicResult(
                ok=True,
                rid=rid,
                path=path,
                reserved_usd=float(st["reserved_usd"]),
                used_usd=float(st.get("used_usd", 0.0)),
                remaining_usd=remaining2,
            )
    except TimeoutError:
        return AtomicResult(ok=False, reason="LOCK_TIMEOUT", path=path)
    except Exception as e:
        return AtomicResult(ok=False, reason=f"EX:{type(e).__name__}", path=path)

def commit_risk_atomic(*, runroot: str, ymd: str, rid: str) -> AtomicResult:
    if not runroot:
        return AtomicResult(ok=False, reason="RUNROOT_MISSING")
    if not rid:
        return AtomicResult(ok=False, reason="RID_MISSING")
    path = _state_file(runroot, ymd)
    lock = _lock_path(path)

    try:
        with FileLock(lock, timeout_sec=8.0):
            st = _load_state(path)
            reservations = st.get("reservations", {})
            if rid not in reservations:
                return AtomicResult(ok=False, reason="RID_NOT_FOUND", path=path)

            usd = float(reservations[rid].get("usd", 0.0))
            st["ts"] = _utc_ts()
            st["reserved_usd"] = float(st.get("reserved_usd", 0.0)) - usd
            st["used_usd"] = float(st.get("used_usd", 0.0)) + usd
            reservations.pop(rid, None)
            st["reservations"] = reservations
            _atomic_write_json(path, st)
            return AtomicResult(ok=True, rid=rid, path=path, reserved_usd=float(st["reserved_usd"]), used_usd=float(st["used_usd"]))
    except TimeoutError:
        return AtomicResult(ok=False, reason="LOCK_TIMEOUT", path=path)
    except Exception as e:
        return AtomicResult(ok=False, reason=f"EX:{type(e).__name__}", path=path)

def release_risk_atomic(*, runroot: str, ymd: str, rid: str) -> AtomicResult:
    if not runroot:
        return AtomicResult(ok=False, reason="RUNROOT_MISSING")
    if not rid:
        return AtomicResult(ok=False, reason="RID_MISSING")
    path = _state_file(runroot, ymd)
    lock = _lock_path(path)

    try:
        with FileLock(lock, timeout_sec=8.0):
            st = _load_state(path)
            reservations = st.get("reservations", {})
            if rid not in reservations:
                return AtomicResult(ok=False, reason="RID_NOT_FOUND", path=path)

            usd = float(reservations[rid].get("usd", 0.0))
            st["ts"] = _utc_ts()
            st["reserved_usd"] = float(st.get("reserved_usd", 0.0)) - usd
            reservations.pop(rid, None)
            st["reservations"] = reservations
            _atomic_write_json(path, st)
            return AtomicResult(ok=True, rid=rid, path=path, reserved_usd=float(st["reserved_usd"]), used_usd=float(st.get("used_usd", 0.0)))
    except TimeoutError:
        return AtomicResult(ok=False, reason="LOCK_TIMEOUT", path=path)
    except Exception as e:
        return AtomicResult(ok=False, reason=f"EX:{type(e).__name__}", path=path)