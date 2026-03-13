from __future__ import annotations
from pathlib import Path
import json
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\ORG_BOT_UNIFIED")
LOGS = ROOT / "runtime" / "paper" / "logs"
OUT  = ROOT / "runtime_reports"

META_EVENTS = LOGS / "meta_events.jsonl"
META_ENGINE = LOGS / "meta_engine.jsonl"
STRAT_PERF  = LOGS / "strategy_perf_events.jsonl"
SHADOW      = LOGS / "shadow_plans.jsonl"
RISK        = LOGS / "risk_ledger_v1.json"

def count_lines(path: Path) -> int:
    if not path.exists():
        return 0
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        return sum(1 for _ in f)

def file_info(path: Path) -> dict:
    if not path.exists():
        return {"exists": False, "bytes": 0, "last_write_time": None}
    st = path.stat()
    return {
        "exists": True,
        "bytes": st.st_size,
        "last_write_time": datetime.fromtimestamp(st.st_mtime).isoformat(timespec="seconds")
    }

def count_contains(path: Path, needles: list[str]) -> dict:
    counts = {n: 0 for n in needles}
    if not path.exists():
        return counts
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            for n in needles:
                if n in line:
                    counts[n] += 1
    return counts

def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    meta_events_lines = count_lines(META_EVENTS)
    meta_engine_lines = count_lines(META_ENGINE)
    strategy_perf_lines = count_lines(STRAT_PERF)
    shadow_lines = count_lines(SHADOW)
    risk_lines = count_lines(RISK)

    strategy_tokens = [
        "chop_v1_eval",
        "chop_v1_rejected",
        "chop_v1_plan_created",
        '"kind": "plan_created"',
        '"kind": "gate_decision"'
    ]
    strategy_counts = count_contains(META_EVENTS, strategy_tokens)

    rejection_tokens = [
        "alpha_mode_off",
        "trend_weak",
        "out_of_session",
        "state_confidence_low",
        "gate_reject",
        "no_candidate",
        "cooldown",
        "risk_budget"
    ]
    rejection_counts = count_contains(META_EVENTS, rejection_tokens)

    runtime_summary = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "runtime_status": "alive" if META_EVENTS.exists() or META_ENGINE.exists() else "unknown",
        "files": {
            "meta_events": {"lines": meta_events_lines, "info": file_info(META_EVENTS)},
            "meta_engine": {"lines": meta_engine_lines, "info": file_info(META_ENGINE)},
            "strategy_perf_events": {"lines": strategy_perf_lines, "info": file_info(STRAT_PERF)},
            "shadow_plans": {"lines": shadow_lines, "info": file_info(SHADOW)},
            "risk_ledger_v1": {"lines": risk_lines, "info": file_info(RISK)}
        }
    }

    strategy_summary = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "counts": strategy_counts
    }

    rejection_summary = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "counts": rejection_counts
    }

    risk_status = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "risk_ledger_exists": RISK.exists(),
        "risk_ledger_lines": risk_lines,
        "risk_ledger_info": file_info(RISK)
    }

    (OUT / "latest_runtime_summary.json").write_text(
        json.dumps(runtime_summary, indent=2), encoding="utf-8"
    )
    (OUT / "latest_strategy_counts.json").write_text(
        json.dumps(strategy_summary, indent=2), encoding="utf-8"
    )
    (OUT / "latest_gate_rejections.json").write_text(
        json.dumps(rejection_summary, indent=2), encoding="utf-8"
    )
    (OUT / "latest_risk_status.json").write_text(
        json.dumps(risk_status, indent=2), encoding="utf-8"
    )

    print("RUNTIME_REPORTS_EXPORT_DONE")
    print(str(OUT / "latest_runtime_summary.json"))
    print(str(OUT / "latest_strategy_counts.json"))
    print(str(OUT / "latest_gate_rejections.json"))
    print(str(OUT / "latest_risk_status.json"))

if __name__ == "__main__":
    main()
