from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass

def _now() -> float:
    return time.time()

def _read_jsonl_tail(path: str, max_lines: int = 5000) -> list[dict]:
    if not path or (not os.path.exists(path)):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        out: list[dict] = []
        for l in lines[-max_lines:]:
            l = (l or "").strip()
            if not l:
                continue
            try:
                obj = json.loads(l)
                if isinstance(obj, dict):
                    out.append(obj)
            except Exception:
                continue
        return out
    except Exception:
        return []

def _append_jsonl(path: str, obj: dict) -> None:
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except Exception:
        pass

def _env_int(name: str, default: int) -> int:
    try:
        v = int((os.environ.get(name) or str(default)).strip())
        return default if v <= 0 else v
    except Exception:
        return default

def _env_float(name: str, default: float) -> float:
    try:
        v = float((os.environ.get(name) or str(default)).strip())
        return default if v <= 0 else v
    except Exception:
        return default

@dataclass
class FailurePolicy:
    lookback_trades: int = 30
    loss_streak_k: int = 5
    dd_limit_r: float = -3.0
    exp_limit_r: float = -0.10
    min_trades_for_exp: int = 15

def policy_from_env() -> FailurePolicy:
    return FailurePolicy(
        lookback_trades=_env_int("TBOT_FAIL_LB_TRADES", 30),
        loss_streak_k=_env_int("TBOT_FAIL_LOSS_STREAK", 5),
        dd_limit_r=_env_float("TBOT_FAIL_DD_LIMIT_R", -3.0),
        exp_limit_r=_env_float("TBOT_FAIL_EXP_LIMIT_R", -0.10),
        min_trades_for_exp=_env_int("TBOT_FAIL_MIN_TRADES_FOR_EXP", 15),
    )

def _extract_strategy_id(ev: dict) -> str:
    sid = ""
    for k in ("strategy_id","sid","strategy","strategy_name"):
        v = ev.get(k)
        if isinstance(v, str) and v.strip():
            sid = v.strip()
            break
    if not sid:
        p = ev.get("plan")
        if isinstance(p, dict):
            v = p.get("strategy_id") or p.get("sid")
            if isinstance(v, str) and v.strip():
                sid = v.strip()
    return sid or "UNKNOWN"

def _extract_trade_r(ev: dict) -> float | None:
    for k in ("r","R","trade_r","realized_r"):
        v = ev.get(k)
        if isinstance(v, (int,float)):
            return float(v)
    p = ev.get("result") or ev.get("trade") or ev.get("metrics")
    if isinstance(p, dict):
        for k in ("r","trade_r","realized_r"):
            v = p.get(k)
            if isinstance(v, (int,float)):
                return float(v)
    return None

def _is_trade_event(ev: dict) -> bool:
    k = (ev.get("kind") or ev.get("name") or ev.get("event") or "")
    return str(k).lower() in ("strategy_result","trade_result","execution_result","fill_result")

def evaluate(meta, runroot: str, profile: str) -> None:
    try:
        rr = (runroot or "").strip() or (os.environ.get("TBOT_RUNROOT") or "").strip()
        if not rr:
            return
        logdir = os.path.join(rr, "logs")
        meta_path = os.path.join(logdir, "meta_events.jsonl")
        events = _read_jsonl_tail(meta_path, max_lines=7000)
        if not events:
            return

        pol = policy_from_env()

        trades_by_sid: dict[str, list[float]] = {}
        for ev in events:
            if not isinstance(ev, dict):
                continue
            if not _is_trade_event(ev):
                continue
            r = _extract_trade_r(ev)
            if r is None:
                continue
            sid = _extract_strategy_id(ev)
            trades_by_sid.setdefault(sid, []).append(float(r))

        if not trades_by_sid:
            return

        out_path = os.path.join(logdir, "strategy_failure.jsonl")

        for sid, rs in trades_by_sid.items():
            if not rs:
                continue
            lb = rs[-pol.lookback_trades:]
            sum_r = float(sum(lb))
            n = len(lb)

            streak = 0
            for x in reversed(lb):
                if x < 0:
                    streak += 1
                else:
                    break

            exp = float(sum_r / n) if n > 0 else 0.0

            triggers: list[str] = []
            if streak >= pol.loss_streak_k:
                triggers.append("LOSS_STREAK")
            if sum_r <= pol.dd_limit_r:
                triggers.append("DRAWDOWN_LOOKBACK")
            if n >= pol.min_trades_for_exp and exp <= pol.exp_limit_r:
                triggers.append("EXPECTANCY_DRIFT")

            if not triggers:
                continue

            payload = {
                "ts": _now(),
                "profile": (profile or "").strip().lower(),
                "strategy_id": sid,
                "triggers": triggers,
                "metrics": {
                    "lookback_trades": n,
                    "sum_r": sum_r,
                    "expectancy_r": exp,
                    "loss_streak": streak,
                    "policy": {
                        "lookback_trades": pol.lookback_trades,
                        "loss_streak_k": pol.loss_streak_k,
                        "dd_limit_r": pol.dd_limit_r,
                        "exp_limit_r": pol.exp_limit_r,
                        "min_trades_for_exp": pol.min_trades_for_exp,
                    }
                }
            }

            try:
                if meta is not None:
                    meta.write("strategy_failure", payload)
            except Exception:
                pass

            _append_jsonl(out_path, payload)

    except Exception:
        return
