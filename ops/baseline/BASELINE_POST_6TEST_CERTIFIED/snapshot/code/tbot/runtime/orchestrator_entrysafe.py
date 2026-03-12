from __future__ import annotations

import json
import os
import time
import traceback

def _runroot() -> str:
    rr = (os.environ.get("TBOT_RUNROOT") or "").strip()
    if rr:
        return rr
    return r"C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper"

def _meta_path() -> str:
    return os.path.join(_runroot(), "logs", "meta_events.jsonl")

def _emit(kind: str, payload: dict | None = None, level: str = "INFO", run_id = None) -> None:
    try:
        p = _meta_path()
        os.makedirs(os.path.dirname(p), exist_ok=True)
        row = {
            "ts": time.strftime("%Y-%m-%d %H:%M:%S"),
            "level": level,
            "kind": kind,
            "run_id": run_id,
            "payload": payload or {},
        }
        with open(p, "a", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    except Exception:
        pass

def _shadow_path() -> str:
    return os.path.join(_runroot(), "logs", "shadow_plans.jsonl")

def _safe_import_and_call():
    # intentional no-op functional core for Dual PID closure phase
    # strategy reattachment happens only after entry surface is stable
    return {
        "regime": "SIDE_CAR",
        "confidence": 0.0,
        "alpha_mode": "OFF",
        "reason": "entrysafe_dualpid_closure_phase",
    }

def run_loop(profile: str = "PAPER", iters: int = 999999, sleep: float = 0.5) -> int:
    boot_payload = {
        "profile": profile,
        "iters": int(iters),
        "sleep": float(sleep),
        "entry": "tbot.entrysafe",
    }
    print("boot", boot_payload, flush=True)
    _emit("boot", boot_payload)

    for i in range(int(iters)):
        hb = {"i": i, "has_snapshot": False, "entry": "tbot.entrysafe"}
        print("heartbeat", hb, flush=True)
        _emit("heartbeat", hb)

        try:
            state = _safe_import_and_call()
            _emit("strategy_result", state)
        except BaseException as e:
            _emit(
                "entrysafe_logic_fail",
                {
                    "error_type": type(e).__name__,
                    "error": str(e),
                    "traceback": traceback.format_exc(limit=8),
                },
                level="ERROR",
            )

        if sleep and float(sleep) > 0:
            time.sleep(float(sleep))

    shut = {"rc": 0, "iters": int(iters), "entry": "tbot.entrysafe"}
    print("shutdown", shut, flush=True)
    _emit("shutdown", shut)
    return 0
