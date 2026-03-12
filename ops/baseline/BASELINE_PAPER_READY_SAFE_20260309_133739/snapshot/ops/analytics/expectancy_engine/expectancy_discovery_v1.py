from __future__ import annotations

import csv
import json
from collections import Counter
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

ROOT = Path(r"C:\alpaca-bot\ORG_BOT_UNIFIED")
SEARCH_DIRS = [
    ROOT / "runtime" / "paper" / "logs",
    ROOT / "runtime" / "paper" / "validation_v2",
    ROOT / "ops" / "evidence",
]
OUTPUT_DIR = ROOT / "ops" / "analytics" / "expectancy_engine" / "discovery_out"

JSON_EXTS = {".json", ".jsonl"}
CSV_EXTS = {".csv"}

TARGET_FIELDS = ["strategy", "symbol", "regime", "r_value", "pnl", "risk", "entry", "exit", "timestamp"]
ALIASES = {
    "strategy": ["strategy", "strategy_id", "sid", "setup", "strategy_name"],
    "symbol": ["symbol", "ticker", "asset", "instrument"],
    "regime": ["regime", "market_regime", "session_regime", "alpha_mode"],
    "r_value": ["pnl_r", "realized_r", "r_multiple", "r", "trade_r", "net_r", "gross_r", "result_r"],
    "pnl": ["pnl", "net_pnl", "realized_pnl", "profit", "net_profit"],
    "risk": ["risk_usd", "risk", "initial_risk_usd", "planned_risk_usd"],
    "entry": ["entry", "entry_price"],
    "exit": ["exit", "exit_price"],
    "timestamp": ["ts", "timestamp", "time", "entry_time", "exit_time", "closed_at", "created_at"],
}

def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)

def iter_json_records(path: Path):
    text = path.read_text(encoding="utf-8", errors="ignore")
    if path.suffix.lower() == ".jsonl":
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if isinstance(obj, dict):
                    yield obj
            except Exception:
                continue
    else:
        try:
            obj = json.loads(text)
            if isinstance(obj, dict):
                yield obj
            elif isinstance(obj, list):
                for item in obj:
                    if isinstance(item, dict):
                        yield item
        except Exception:
            return

def iter_csv_records(path: Path):
    try:
        with path.open("r", encoding="utf-8", errors="ignore", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                yield dict(row)
    except Exception:
        return

def collect_files() -> List[Path]:
    found: List[Path] = []
    for base in SEARCH_DIRS:
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if not p.is_file():
                continue
            ext = p.suffix.lower()
            if ext in JSON_EXTS or ext in CSV_EXTS:
                found.append(p)
    found = sorted({str(p).lower(): p for p in found}.values(), key=lambda x: str(x).lower())
    return found

def score_keys(keys: List[str]) -> Tuple[int, Dict[str, str], Dict[str, int]]:
    lowered = {k.lower(): k for k in keys}
    matched: Dict[str, str] = {}
    scores: Dict[str, int] = {}
    total = 0
    for tf in TARGET_FIELDS:
        hit = None
        for alias in ALIASES[tf]:
          if alias.lower() in lowered:
            hit = lowered[alias.lower()]
            break
        if hit:
            matched[tf] = hit
            scores[tf] = 1
            total += 1
        else:
            scores[tf] = 0
    return total, matched, scores

def source_kind(path: Path) -> str:
    return path.suffix.lower().lstrip(".")

def main() -> int:
    ensure_dir(OUTPUT_DIR)

    files = collect_files()
    inventory_rows: List[Dict[str, Any]] = []
    candidate_rows: List[Dict[str, Any]] = []
    missing_rows: List[Dict[str, Any]] = []
    sample_records: List[Dict[str, Any]] = []

    for path in files:
        ext = path.suffix.lower()
        records = iter_json_records(path) if ext in JSON_EXTS else iter_csv_records(path)

        count = 0
        key_counter: Counter[str] = Counter()
        first_record = None

        for rec in records:
            count += 1
            if first_record is None:
                first_record = rec
            for k in rec.keys():
                key_counter[str(k)] += 1
            if count >= 25:
                break

        keys = sorted(key_counter.keys())
        score, matched, scores = score_keys(keys)

        inventory_rows.append({
            "file": str(path),
            "source_kind": source_kind(path),
            "records_sampled": count,
            "field_count": len(keys),
            "score": score,
            "matched_fields": ",".join(sorted(matched.keys())),
        })

        if count > 0:
            candidate_rows.append({
                "file": str(path),
                "source_kind": source_kind(path),
                "records_sampled": count,
                "score": score,
                "strategy_field": matched.get("strategy"),
                "symbol_field": matched.get("symbol"),
                "regime_field": matched.get("regime"),
                "r_value_field": matched.get("r_value"),
                "pnl_field": matched.get("pnl"),
                "risk_field": matched.get("risk"),
                "entry_field": matched.get("entry"),
                "exit_field": matched.get("exit"),
                "timestamp_field": matched.get("timestamp"),
            })

            for tf in TARGET_FIELDS:
                missing_rows.append({
                    "file": str(path),
                    "target_field": tf,
                    "present": scores[tf],
                })

            sample_records.append({
                "file": str(path),
                "source_kind": source_kind(path),
                "score": score,
                "keys": keys[:80],
                "sample_record": first_record,
            })

    candidate_rows = sorted(candidate_rows, key=lambda x: (-x["score"], x["file"]))

    def write_csv(path: Path, rows: List[Dict[str, Any]]) -> None:
        ensure_dir(path.parent)
        if not rows:
            path.write_text("", encoding="utf-8")
            return
        with path.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)

    write_csv(OUTPUT_DIR / "candidate_schema_inventory.csv", inventory_rows)
    write_csv(OUTPUT_DIR / "best_outcome_candidates.csv", candidate_rows[:50])
    write_csv(OUTPUT_DIR / "missing_field_matrix.csv", missing_rows)

    (OUTPUT_DIR / "sample_records.json").write_text(
        json.dumps(sample_records[:50], indent=2, ensure_ascii=False),
        encoding="utf-8"
    )

    summary = {
        "tool_version": "EXPECTANCY_DISCOVERY_V1",
        "files_scanned": len(files),
        "files_with_sampled_records": sum(1 for x in candidate_rows if x["records_sampled"] > 0),
        "top_candidates": candidate_rows[:10],
    }
    (OUTPUT_DIR / "discovery_summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False),
        encoding="utf-8"
    )

    (OUTPUT_DIR / "README_DISCOVERY.txt").write_text(
        "Use best_outcome_candidates.csv and sample_records.json to identify the real closed-trade schema for Expectancy Engine V2.",
        encoding="utf-8"
    )

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
