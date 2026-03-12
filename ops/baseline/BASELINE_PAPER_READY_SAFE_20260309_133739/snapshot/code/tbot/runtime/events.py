# File: tbot/runtime/events.py
from __future__ import annotations


# === ENSURE_NONE_REASON_V1 ===
def _ensure_none_reason(kind, payload):
    try:
        if kind == "strategy_result" and isinstance(payload, dict):
            if payload.get("returned") == "NONE":
                r = payload.get("reason")
                if r is None or str(r).strip() == "":
                    payload["reason"] = "NONE_NO_REASON"
    except Exception:
        pass
    return payload
# === END ENSURE_NONE_REASON_V1 ===

import os
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Literal




# === META_EVENTS_SINK_V1 ===
import os as _me_os, json as _me_json, time as _me_time

def _me_append_strategy_result(payload):
    try:
        logdir = (_me_os.getenv("TBOT_LOGDIR") or "").strip()
        if not logdir:
            rr = (_me_os.getenv("TBOT_RUNROOT") or _me_os.getenv("TBOT_RUNTIME") or "").strip()
            if rr:
                logdir = _me_os.path.join(rr, "logs")
        if not logdir:
            return

        _me_os.makedirs(logdir, exist_ok=True)
        outp = _me_os.path.join(logdir, "meta_events.jsonl")

        rec = {
            "ts": _me_time.time(),
            "kind": "strategy_result",
            "payload": payload,
        }

        with open(outp, "a", encoding="utf-8", newline="\n") as w:
            w.write(_me_json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass


EventLevel = Literal["INFO", "WARN", "ERROR"]

# NOTE:
# Keep this list aligned with actual emits in orchestrator/runtime.
EventKind = Literal[
    "boot",
    "heartbeat",
    "shutdown",
    "alpha_kill_change",
    "portfolio_kill_change",
    "trade_open",
    "trade_close",
    "signal_eval",
    "signal_fire",
    "signal_skip",
    "strategy_result",
    "regime",
    "core_context",
    "alpha_mode",
    "alpha_admission",
    "shadow_plan",
    "shadow_accept",
    "shadow_reject",
    "shadow_build_error",
    "metrics",
    "qa_summary",
]

@dataclass(frozen=True)
class Event:
    ts: str
    level: EventLevel
    kind: str
    payload: dict[str, Any]
    run_id: str

def _default_run_id() -> str:
    # Prefer user-provided run id; else generate stable id per process
    rid = (os.getenv("TBOT_RUN_ID") or "").strip()
    if rid:
        return rid
    # Create one and pin it into env so all events in this process share the same run_id
    rid = "run_" + datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:8]
    os.environ["TBOT_RUN_ID"] = rid
    return rid

def make_event(*, level: EventLevel, kind: str, payload: dict[str, Any], run_id: str | None = None) -> Event:
    rid = (run_id or "").strip() or _default_run_id()
    payload = _ensure_none_reason(kind, payload)
    # META_EVENTS_SINK
    try:
        if kind == "strategy_result":
            _me_append_strategy_result(payload)
    except Exception:
        pass


    return Event(
        ts=datetime.now().isoformat(timespec="seconds"),
        level=level,
        kind=kind,
        payload=payload,
        run_id=rid,
    )

