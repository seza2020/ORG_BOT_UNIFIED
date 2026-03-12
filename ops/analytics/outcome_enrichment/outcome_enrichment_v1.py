from __future__ import annotations

import csv
import json
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(r"C:\alpaca-bot\ORG_BOT_UNIFIED")
SOURCE = ROOT / "runtime" / "paper" / "validation_v2" / "outcome_ledger.jsonl"
RECON = ROOT / "runtime" / "paper" / "validation_v2" / "outcome_reconciliation.csv"

OUTPUT_DIR = ROOT / "ops" / "analytics" / "outcome_enrichment" / "out"
ENRICHED = OUTPUT_DIR / "outcome_ledger_enriched.jsonl"
AUDIT = OUTPUT_DIR / "outcome_enrichment_audit.jsonl"
SUMMARY = OUTPUT_DIR / "outcome_enrichment_summary.json"
UNRESOLVED = OUTPUT_DIR / "unresolved_outcomes.csv"

def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)

def safe_str(v: Any) -> str | None:
    if v is None:
        return None
    s = str(v).strip()
    return s or None

def safe_float(v: Any) -> float | None:
    if v is None:
        return None
    try:
        return float(str(v).strip())
    except Exception:
        return None

def read_jsonl(path: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    if not path.exists():
        return rows
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if isinstance(obj, dict):
                    rows.append(obj)
            except Exception:
                continue
    return rows

def read_reconciliation(path: Path) -> Tuple[Dict[str, Dict[str, Any]], List[Dict[str, Any]]]:
    mapping: Dict[str, Dict[str, Any]] = {}
    conflicts: List[Dict[str, Any]] = []

    if not path.exists():
        return mapping, conflicts

    with path.open("r", encoding="utf-8", errors="ignore", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            plan_key = safe_str(row.get("plan_key"))
            if not plan_key:
                conflicts.append({
                    "kind": "reconciliation_conflict",
                    "reason": "missing_plan_key",
                    "row": row,
                })
                continue
            if plan_key in mapping:
                conflicts.append({
                    "kind": "reconciliation_conflict",
                    "reason": "duplicate_plan_key",
                    "plan_key": plan_key,
                    "row": row,
                })
                continue
            mapping[plan_key] = dict(row)
    return mapping, conflicts

def validate_resolution(row: Dict[str, Any]) -> Tuple[bool, str | None]:
    status = safe_str(row.get("resolved_status"))
    realized_r = safe_float(row.get("resolved_r"))

    if not status:
        return False, "missing_resolved_status"

    if status not in {"CLOSED_WIN", "CLOSED_LOSS", "OPEN", "UNRESOLVED"}:
        return False, "invalid_resolved_status"

    if status == "CLOSED_WIN":
        if realized_r is None:
            return False, "missing_resolved_r_for_win"
        if realized_r <= 0:
            return False, "non_positive_r_for_win"

    if status == "CLOSED_LOSS":
        if realized_r is None:
            return False, "missing_resolved_r_for_loss"
        if realized_r >= 0:
            return False, "non_negative_r_for_loss"

    return True, None

def main() -> int:
    ensure_dir(OUTPUT_DIR)

    source_rows = read_jsonl(SOURCE)
    recon_map, recon_conflicts = read_reconciliation(RECON)

    enriched_rows: List[Dict[str, Any]] = []
    audit_rows: List[Dict[str, Any]] = []
    unresolved_rows: List[Dict[str, Any]] = []

    stats = Counter()
    stats["source_records_total"] = len(source_rows)
    stats["reconciliation_rows"] = len(recon_map)
    stats["reconciliation_conflicts"] = len(recon_conflicts)

    for item in source_rows:
        plan_key = safe_str(item.get("plan_key"))
        status = safe_str(item.get("status"))
        realized_r = item.get("realized_r")

        is_open = (status == "OPEN") and (realized_r is None)

        out = dict(item)
        out["enrichment_version"] = "OUTCOME_ENRICHMENT_V1"
        out["enriched_at"] = datetime.now().isoformat(timespec="seconds")

        if not is_open:
            stats["already_closed_or_non_open"] += 1
            enriched_rows.append(out)
            continue

        stats["open_records_total"] += 1

        if not plan_key:
            stats["unresolved_records"] += 1
            unresolved_rows.append({
                "plan_key": "",
                "reason": "missing_plan_key_in_source",
                "source_status": status,
            })
            out["outcome_source"] = "unresolved"
            out["notes"] = "missing plan_key in source"
            enriched_rows.append(out)
            audit_rows.append({
                "ts": datetime.now().isoformat(timespec="seconds"),
                "kind": "outcome_enrichment_unresolved",
                "reason": "missing_plan_key_in_source",
                "plan_key": "",
            })
            continue

        recon = recon_map.get(plan_key)
        if recon is None:
            stats["unresolved_records"] += 1
            unresolved_rows.append({
                "plan_key": plan_key,
                "reason": "no_reconciliation_row",
                "source_status": status,
            })
            out["outcome_source"] = "unresolved"
            out["notes"] = "no reconciliation row found"
            enriched_rows.append(out)
            audit_rows.append({
                "ts": datetime.now().isoformat(timespec="seconds"),
                "kind": "outcome_enrichment_unresolved",
                "reason": "no_reconciliation_row",
                "plan_key": plan_key,
            })
            continue

        ok, reason = validate_resolution(recon)
        if not ok:
            stats["conflict_records"] += 1
            unresolved_rows.append({
                "plan_key": plan_key,
                "reason": reason,
                "source_status": status,
            })
            out["outcome_source"] = "unresolved"
            out["notes"] = f"reconciliation invalid: {reason}"
            enriched_rows.append(out)
            audit_rows.append({
                "ts": datetime.now().isoformat(timespec="seconds"),
                "kind": "outcome_enrichment_conflict",
                "reason": reason,
                "plan_key": plan_key,
            })
            continue

        resolved_status = safe_str(recon.get("resolved_status"))
        resolved_r = safe_float(recon.get("resolved_r"))
        exit_px = safe_float(recon.get("exit"))
        exit_ts = safe_str(recon.get("exit_ts"))
        outcome_source = safe_str(recon.get("outcome_source")) or "manual_reconciliation"
        notes = safe_str(recon.get("notes")) or ""

        if resolved_status in {"CLOSED_WIN", "CLOSED_LOSS"}:
            out["status"] = resolved_status
            out["realized_r"] = resolved_r
            out["exit"] = exit_px
            out["exit_ts"] = exit_ts
            out["outcome_source"] = outcome_source
            out["notes"] = notes
            stats["resolved_records"] += 1
            if resolved_status == "CLOSED_WIN":
                stats["win_records"] += 1
            if resolved_status == "CLOSED_LOSS":
                stats["loss_records"] += 1

            audit_rows.append({
                "ts": datetime.now().isoformat(timespec="seconds"),
                "kind": "outcome_enrichment_resolved",
                "plan_key": plan_key,
                "resolved_status": resolved_status,
                "realized_r": resolved_r,
                "outcome_source": outcome_source,
            })
        else:
            stats["unresolved_records"] += 1
            out["outcome_source"] = outcome_source
            out["notes"] = notes or "resolution remained open/unresolved"
            unresolved_rows.append({
                "plan_key": plan_key,
                "reason": "resolved_status_not_closed",
                "source_status": status,
            })
            audit_rows.append({
                "ts": datetime.now().isoformat(timespec="seconds"),
                "kind": "outcome_enrichment_unresolved",
                "reason": "resolved_status_not_closed",
                "plan_key": plan_key,
            })

        enriched_rows.append(out)

    for c in recon_conflicts:
        audit_rows.append({
            "ts": datetime.now().isoformat(timespec="seconds"),
            **c,
        })

    with ENRICHED.open("w", encoding="utf-8") as f:
        for row in enriched_rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    with AUDIT.open("w", encoding="utf-8") as f:
        for row in audit_rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    with UNRESOLVED.open("w", encoding="utf-8", newline="") as f:
        fieldnames = ["plan_key", "reason", "source_status"]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in unresolved_rows:
            writer.writerow(row)

    resolution_rate = 0.0
    if stats["open_records_total"] > 0:
        resolution_rate = stats["resolved_records"] / stats["open_records_total"]

    summary = {
        "system_version": "OUTCOME_ENRICHMENT_V1",
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "source_file": str(SOURCE),
        "reconciliation_file": str(RECON),
        "source_exists": SOURCE.exists(),
        "reconciliation_exists": RECON.exists(),
        "source_records_total": stats["source_records_total"],
        "open_records_total": stats["open_records_total"],
        "resolved_records": stats["resolved_records"],
        "unresolved_records": stats["unresolved_records"],
        "conflict_records": stats["conflict_records"],
        "win_records": stats["win_records"],
        "loss_records": stats["loss_records"],
        "reconciliation_conflicts": stats["reconciliation_conflicts"],
        "resolution_rate": round(resolution_rate, 6),
        "outputs": {
            "enriched_ledger": str(ENRICHED),
            "audit_log": str(AUDIT),
            "summary_json": str(SUMMARY),
            "unresolved_csv": str(UNRESOLVED),
        },
    }

    SUMMARY.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
