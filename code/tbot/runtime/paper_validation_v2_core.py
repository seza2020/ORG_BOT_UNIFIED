from __future__ import annotations

import json
import os
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


def _now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    out: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except Exception:
                continue
    return out


def _append_jsonl(path: Path, row: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def _latest_for_run(rows: list[dict[str, Any]], run_id: str, kind: str) -> dict[str, Any] | None:
    matches = [r for r in rows if r.get("run_id") == run_id and r.get("kind") == kind]
    return matches[-1] if matches else None


def _load_logs(logs: Path) -> dict[str, list[dict[str, Any]]]:
    return {
        "meta": _read_jsonl(logs / "meta_events.jsonl"),
        "shadow": _read_jsonl(logs / "shadow_plans.jsonl"),
        "hardened": _read_jsonl(logs / "hardened_shadow_plans.jsonl"),
        "hardening_events": _read_jsonl(logs / "hardening_events.jsonl"),
    }


def _config_id_from_plan(plan: dict[str, Any]) -> str:
    sid = str(plan.get("sid", "NA"))
    sym = str(plan.get("symbol", "NA"))
    bias = str(plan.get("bias", "NA"))
    side = str(plan.get("side", "NA"))
    return f"{sid}|{sym}|{bias}|{side}"


def _regime_tag(meta_rows: list[dict[str, Any]], run_id: str) -> dict[str, Any]:
    regime_row = _latest_for_run(meta_rows, run_id, "regime")
    core_row = _latest_for_run(meta_rows, run_id, "core_context")
    alpha_row = _latest_for_run(meta_rows, run_id, "alpha_mode")

    regime_payload = regime_row.get("payload", {}) if regime_row else {}
    core_payload = core_row.get("payload", {}) if core_row else {}
    alpha_payload = alpha_row.get("payload", {}) if alpha_row else {}

    return {
        "regime": regime_payload.get("regime", "UNKNOWN"),
        "confidence": float(regime_payload.get("confidence", 0.0) or 0.0),
        "bias": core_payload.get("bias", "FLAT"),
        "trend_strength": float(core_payload.get("trend_strength", 0.0) or 0.0),
        "alpha_mode": alpha_payload.get("mode", "OFF"),
    }


def _existing_open_keys(outcome_rows: list[dict[str, Any]]) -> set[str]:
    keys = set()
    for r in outcome_rows:
        if str(r.get("status", "OPEN")).upper() == "OPEN":
            keys.add(str(r.get("plan_key", "")))
    return keys


def _build_outcome_entries(logs: dict[str, list[dict[str, Any]]], valroot: Path) -> list[dict[str, Any]]:
    meta = logs["meta"]
    hardened = logs["hardened"]
    outcome_path = valroot / "outcome_ledger.jsonl"
    existing = _read_jsonl(outcome_path)
    existing_open = _existing_open_keys(existing)

    new_rows: list[dict[str, Any]] = []
    for plan in hardened:
        run_id = str(plan.get("source_run_id") or plan.get("run_id") or "NA")
        config_id = _config_id_from_plan(plan)
        plan_key = f"{run_id}|{config_id}|{plan.get('ts','NA')}"
        if plan_key in existing_open:
            continue

        reg = _regime_tag(meta, run_id)
        row = {
            "ts": _now(),
            "plan_key": plan_key,
            "source_run_id": run_id,
            "config_id": config_id,
            "sid": plan.get("sid"),
            "symbol": plan.get("symbol"),
            "side": plan.get("side"),
            "bias": plan.get("bias"),
            "entry": plan.get("entry"),
            "stop": plan.get("stop"),
            "tp": plan.get("tp"),
            "rr_planned": plan.get("rr"),
            "confidence": plan.get("confidence"),
            "regime": reg["regime"],
            "alpha_mode": reg["alpha_mode"],
            "trend_strength": reg["trend_strength"],
            "status": "OPEN",
            "realized_r": None,
            "outcome_source": "pending",
            "notes": "Awaiting outcome enrichment",
        }
        new_rows.append(row)
    return new_rows


def _build_config_registry(outcome_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in outcome_rows:
        grouped[str(row.get("config_id"))].append(row)

    out: list[dict[str, Any]] = []
    for config_id, rows in grouped.items():
        sample = rows[-1]
        out.append({
            "ts": _now(),
            "config_id": config_id,
            "sid": sample.get("sid"),
            "symbol": sample.get("symbol"),
            "bias": sample.get("bias"),
            "side": sample.get("side"),
            "profile_version": "validation_v2_core",
            "gate_version": "ext_harden_v2",
            "sample_size": len(rows),
            "regimes_seen": sorted(list({str(r.get("regime")) for r in rows})),
        })
    return out


def _safe_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return default
        return float(v)
    except Exception:
        return default


def _kpi_snapshot(outcome_rows: list[dict[str, Any]], hardening_events: list[dict[str, Any]]) -> dict[str, Any]:
    closed = [r for r in outcome_rows if r.get("realized_r") is not None]
    open_rows = [r for r in outcome_rows if r.get("realized_r") is None]

    realized = [_safe_float(r.get("realized_r")) for r in closed]
    confs = [_safe_float(r.get("confidence")) for r in outcome_rows]
    planned_rr = [_safe_float(r.get("rr_planned")) for r in outcome_rows]

    pass_events = 0
    block_events = 0
    for e in hardening_events:
        if e.get("kind") == "hardening_gate_decision":
            allow = bool((e.get("payload") or {}).get("allow"))
            if allow:
                pass_events += 1
            else:
                block_events += 1

    avg_realized = sum(realized) / len(realized) if realized else 0.0
    avg_conf = sum(confs) / len(confs) if confs else 0.0
    avg_planned_rr = sum(planned_rr) / len(planned_rr) if planned_rr else 0.0

    symbols = Counter([str(r.get("symbol")) for r in outcome_rows])
    biases = Counter([str(r.get("bias")) for r in outcome_rows])
    regimes = Counter([str(r.get("regime")) for r in outcome_rows])

    positive_realized = [r for r in realized if r > 0]
    negative_realized = [r for r in realized if r < 0]
    expectancy_r = avg_realized
    avg_win = sum(positive_realized) / len(positive_realized) if positive_realized else 0.0
    avg_loss = sum(negative_realized) / len(negative_realized) if negative_realized else 0.0
    payoff_ratio = abs(avg_win / avg_loss) if avg_loss != 0 else None
    profit_factor = (sum(positive_realized) / abs(sum(negative_realized))) if negative_realized else None

    return {
        "ts": _now(),
        "plans_total": len(outcome_rows),
        "plans_open": len(open_rows),
        "plans_closed": len(closed),
        "gate_pass": pass_events,
        "gate_block": block_events,
        "gate_pass_rate": (pass_events / (pass_events + block_events)) if (pass_events + block_events) > 0 else 0.0,
        "avg_planned_rr": round(avg_planned_rr, 4),
        "avg_confidence": round(avg_conf, 4),
        "realized_r_mean": round(avg_realized, 4),
        "expectancy_r": round(expectancy_r, 4),
        "average_win_r": round(avg_win, 4),
        "average_loss_r": round(avg_loss, 4),
        "payoff_ratio": None if payoff_ratio is None else round(payoff_ratio, 4),
        "profit_factor": None if profit_factor is None else round(profit_factor, 4),
        "symbol_distribution": dict(symbols),
        "bias_distribution": dict(biases),
        "regime_distribution": dict(regimes),
    }


def _governance_rows(outcome_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in outcome_rows:
        grouped[str(row.get("config_id"))].append(row)

    out: list[dict[str, Any]] = []
    for config_id, rows in grouped.items():
        sample_size = len(rows)
        closed = [r for r in rows if r.get("realized_r") is not None]
        realized = [_safe_float(r.get("realized_r")) for r in closed]
        expectancy = (sum(realized) / len(realized)) if realized else None

        compliance = 100.0
        major_integrity_issue = False

        if sample_size < 30:
            bucket = "incubating"
            reason = "sample_lt_30"
        elif expectancy is None:
            bucket = "active_test"
            reason = "no_realized_r_yet"
        elif expectancy <= 0:
            bucket = "killed"
            reason = "expectancy_non_positive"
        elif compliance < 95.0 or major_integrity_issue:
            bucket = "review"
            reason = "compliance_or_integrity_issue"
        elif expectancy > 0.15:
            bucket = "candidate"
            reason = "meets_expectancy_threshold"
        else:
            bucket = "active_test"
            reason = "needs_more_quality"
        out.append({
            "ts": _now(),
            "config_id": config_id,
            "sample_size": sample_size,
            "closed_count": len(closed),
            "expectancy_r": None if expectancy is None else round(expectancy, 4),
            "bucket": bucket,
            "reason": reason,
        })
    return out


def run_v2_core(runroot: str) -> dict[str, Any]:
    runroot_p = Path(runroot)
    logs = runroot_p / "logs"
    valroot = runroot_p / "validation_v2"
    valroot.mkdir(parents=True, exist_ok=True)

    logs_data = _load_logs(logs)

    outcome_path = valroot / "outcome_ledger.jsonl"
    registry_path = valroot / "config_registry.jsonl"
    kpi_path = valroot / "kpi_snapshots.jsonl"
    gov_path = valroot / "governance_status.jsonl"

    new_outcomes = _build_outcome_entries(logs_data, valroot)
    for row in new_outcomes:
        _append_jsonl(outcome_path, row)

    outcome_rows = _read_jsonl(outcome_path)

    config_rows = _build_config_registry(outcome_rows)
    _append_jsonl(registry_path, {
        "ts": _now(),
        "kind": "config_registry_snapshot",
        "rows": config_rows,
    })

    kpi = _kpi_snapshot(outcome_rows, logs_data["hardening_events"])
    _append_jsonl(kpi_path, kpi)

    gov_rows = _governance_rows(outcome_rows)
    _append_jsonl(gov_path, {
        "ts": _now(),
        "kind": "governance_snapshot",
        "rows": gov_rows,
    })

    return {
        "ok": True,
        "new_outcomes_written": len(new_outcomes),
        "outcome_ledger_total": len(outcome_rows),
        "config_count": len({r.get("config_id") for r in outcome_rows}),
        "governance_rows": len(gov_rows),
        "kpi_plans_total": kpi["plans_total"],
    }


if __name__ == "__main__":
    rr = os.environ.get("TBOT_RUNROOT", r"C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper")
    result = run_v2_core(rr)
    print(json.dumps(result, ensure_ascii=False))
