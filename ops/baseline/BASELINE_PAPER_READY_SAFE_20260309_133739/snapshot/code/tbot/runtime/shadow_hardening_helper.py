from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                continue
    return rows


def _append_jsonl(path: Path, row: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def _now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def _latest_for_run(rows: list[dict[str, Any]], run_id: str, kind: str) -> dict[str, Any] | None:
    matches = [r for r in rows if r.get("run_id") == run_id and r.get("kind") == kind]
    return matches[-1] if matches else None


def _latest_plan_for_run(rows: list[dict[str, Any]], run_id: str) -> dict[str, Any] | None:
    matches = [r for r in rows if r.get("run_id") == run_id]
    return matches[-1] if matches else None


def _emit_event(events_path: Path, run_id: str, kind: str, payload: dict[str, Any], level: str = "INFO") -> None:
    _append_jsonl(events_path, {
        "ts": _now(),
        "level": level,
        "kind": kind,
        "run_id": run_id,
        "payload": payload,
    })


def _price_fallback_for_symbol(symbol: str) -> float:
    base = {
        "SPY": 600.0,
        "QQQ": 520.0,
        "IWM": 220.0,
        "NVDA": 140.0,
        "AAPL": 220.0,
        "TSLA": 240.0,
    }
    return float(base.get(str(symbol).upper(), 100.0))


def _extract_realistic_entry(raw: dict[str, Any], regime: dict[str, Any], core: dict[str, Any]) -> float:
    for key in ("entry", "last", "price", "mark", "close"):
        val = raw.get(key)
        if val is not None:
            try:
                v = float(val)
                if v > 0:
                    return v
            except Exception:
                pass

    symbol = str(raw.get("symbol") or "SPY").upper()
    return _price_fallback_for_symbol(symbol)

def _build_hardened_plan(run_id: str, regime_row: dict[str, Any], core_row: dict[str, Any], plan_row: dict[str, Any]) -> dict[str, Any] | None:
    regime = regime_row.get("payload", {}) if regime_row else {}
    core = core_row.get("payload", {}) if core_row else {}
    raw  = plan_row if plan_row else {}

    bias = str(core.get("bias", "FLAT")).upper()
    conf = float(regime.get("confidence", 0.0) or 0.0)

    symbol = str(raw.get("symbol") or "SPY").upper()
    side = "BUY" if bias == "LONG" else "SELL" if bias == "SHORT" else None
    if side is None:
        return None

    entry = _extract_realistic_entry(raw, regime, core)

    raw_stop = raw.get("stop")
    raw_tp = raw.get("tp")
    raw_rr = raw.get("rr")

    if raw_stop is not None and raw_tp is not None and raw_rr is not None:
        try:
            stop = float(raw_stop)
            tp = float(raw_tp)
            rr = float(raw_rr)
        except Exception:
            raw_stop = raw_tp = raw_rr = None

    if raw_stop is None or raw_tp is None or raw_rr is None:
        if side == "BUY":
            stop = round(entry * 0.995, 6)
            tp = round(entry * 1.008, 6)
        else:
            stop = round(entry * 1.005, 6)
            tp = round(entry * 0.992, 6)

        risk = abs(entry - stop)
        rr = 0.0 if risk <= 0 else round(abs(tp - entry) / risk, 4)

    return {
        "ts": _now(),
        "source_run_id": run_id,
        "sid": "EXT_HARDEN_V2",
        "symbol": symbol,
        "side": side,
        "entry": round(float(entry), 6),
        "stop": round(float(stop), 6),
        "tp": round(float(tp), 6),
        "rr": round(float(rr), 4),
        "confidence": round(conf, 4),
        "bias": bias,
        "reason": "external_hardening_pricing_realism_v2",
    }


def harden_latest(runroot: str, gate_min_conf: float = 0.55, gate_min_rr: float = 1.5) -> dict[str, Any]:
    runroot_p = Path(runroot)
    logs = runroot_p / "logs"

    meta_path = logs / "meta_events.jsonl"
    shadow_path = logs / "shadow_plans.jsonl"
    hard_path = logs / "hardened_shadow_plans.jsonl"
    events_path = logs / "hardening_events.jsonl"

    meta_rows = _read_jsonl(meta_path)
    shadow_rows = _read_jsonl(shadow_path)

    plan_events = [r for r in meta_rows if r.get("kind") == "plan_created" and r.get("run_id")]
    if not plan_events:
        _emit_event(events_path, "NA", "hardening_gate_decision", {
            "allow": False,
            "reasons": ["no_plan_created_event"]
        }, level="WARNING")
        return {"ok": False, "reason": "no_plan_created_event"}

    run_id = str(plan_events[-1]["run_id"])

    regime_row = _latest_for_run(meta_rows, run_id, "regime")
    core_row = _latest_for_run(meta_rows, run_id, "core_context")
    alpha_row = _latest_for_run(meta_rows, run_id, "alpha_mode")
    plan_event = _latest_for_run(meta_rows, run_id, "plan_created")
    raw_plan = plan_event.get("payload", {}) if plan_event else (_latest_plan_for_run(shadow_rows, run_id) or {})

    _emit_event(events_path, run_id, "hardening_input", {
        "has_regime": regime_row is not None,
        "has_core": core_row is not None,
        "has_alpha": alpha_row is not None,
        "has_raw_plan": bool(raw_plan),
    })

    alpha_payload = alpha_row.get("payload", {}) if alpha_row else {}
    alpha_mode = str(alpha_payload.get("mode", "OFF")).upper()

    candidate = _build_hardened_plan(run_id, regime_row or {}, core_row or {}, raw_plan or {})
    _emit_event(events_path, run_id, "hardening_candidate", {
        "candidate_exists": bool(candidate),
        "alpha_mode": alpha_mode,
    })

    reasons: list[str] = []
    allow = True

    if alpha_mode != "ON":
        allow = False
        reasons.append("alpha_off")

    if candidate is None:
        allow = False
        reasons.append("no_candidate")
        conf = 0.0
        rr = 0.0
    else:
        conf = float(candidate.get("confidence", 0.0) or 0.0)
        rr = float(candidate.get("rr", 0.0) or 0.0)

        if conf < gate_min_conf:
            allow = False
            reasons.append(f"conf_below_min({conf:.3f}<{gate_min_conf:.3f})")

        if rr < gate_min_rr:
            allow = False
            reasons.append(f"rr_below_min({rr:.3f}<{gate_min_rr:.3f})")

    _emit_event(events_path, run_id, "hardening_risk_check", {
        "allow": allow,
        "confidence": conf,
        "rr": rr,
        "gate_min_conf": gate_min_conf,
        "gate_min_rr": gate_min_rr,
    })

    _emit_event(events_path, run_id, "hardening_gate_decision", {
        "allow": allow,
        "reasons": reasons if reasons else ["pass"],
    })

    if allow and candidate is not None:
        _append_jsonl(hard_path, candidate)
        _emit_event(events_path, run_id, "hardened_plan_written", {
            "symbol": candidate["symbol"],
            "sid": candidate["sid"],
            "side": candidate["side"],
        })
        return {"ok": True, "run_id": run_id, "candidate": candidate}

    return {"ok": False, "run_id": run_id, "reason": reasons}


if __name__ == "__main__":
    rr = os.environ.get("TBOT_RUNROOT", r"C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper")
    result = harden_latest(rr)
    print(json.dumps(result, ensure_ascii=False))
