from __future__ import annotations

import csv
import json
import math
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(r"C:\alpaca-bot\ORG_BOT_UNIFIED")
SOURCE = ROOT / "runtime" / "paper" / "validation_v2" / "outcome_ledger.jsonl"
OUTPUT_DIR = ROOT / "ops" / "analytics" / "expectancy_engine" / "out_v2"

def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)

def safe_str(v: Any) -> Optional[str]:
    if v is None:
        return None
    s = str(v).strip()
    return s or None

def safe_float(v: Any) -> Optional[float]:
    if v is None:
        return None
    if isinstance(v, (int, float)):
        f = float(v)
        if math.isnan(f) or math.isinf(f):
            return None
        return f
    s = str(v).strip().replace(",", "")
    if not s:
        return None
    try:
        f = float(s)
        if math.isnan(f) or math.isinf(f):
            return None
        return f
    except Exception:
        return None

def parse_ts(v: Any) -> Optional[datetime]:
    s = safe_str(v)
    if not s:
        return None
    candidates = [s]
    if s.endswith("Z"):
        candidates.append(s[:-1])
    for c in candidates:
        for fmt in (
            "%Y-%m-%dT%H:%M:%S",
            "%Y-%m-%d %H:%M:%S",
            "%Y-%m-%dT%H:%M:%S.%f",
            "%Y-%m-%d %H:%M:%S.%f",
        ):
            try:
                return datetime.strptime(c, fmt)
            except Exception:
                pass
        try:
            return datetime.fromisoformat(c)
        except Exception:
            pass
    return None

@dataclass
class Outcome:
    ts: Optional[str]
    hour: Optional[int]
    strategy: str
    symbol: str
    regime: str
    realized_r: float
    source_file: str

def iter_jsonl(path: Path):
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if isinstance(obj, dict):
                    yield obj
            except Exception:
                continue

def normalize_record(d: Dict[str, Any], source_file: Path):
    strategy = safe_str(d.get("sid")) or safe_str(d.get("strategy")) or "UNKNOWN"
    symbol = safe_str(d.get("symbol")) or "UNKNOWN"
    regime = safe_str(d.get("regime")) or "UNKNOWN"
    realized_r = safe_float(d.get("realized_r"))
    ts_raw = d.get("ts")

    if realized_r is None:
        return None, "missing_realized_r"

    dt = parse_ts(ts_raw)
    ts = dt.isoformat(timespec="seconds") if dt else safe_str(ts_raw)
    hour = dt.hour if dt else None

    return Outcome(
        ts=ts,
        hour=hour,
        strategy=strategy,
        symbol=symbol,
        regime=regime,
        realized_r=float(realized_r),
        source_file=str(source_file),
    ), None

def aggregate(rows: List[Outcome], key_fn):
    groups = defaultdict(list)
    for r in rows:
        groups[key_fn(r)].append(r)

    out = []
    for key, items in sorted(groups.items(), key=lambda kv: kv[0]):
        n = len(items)
        wins = [x.realized_r for x in items if x.realized_r > 0]
        losses = [x.realized_r for x in items if x.realized_r <= 0]

        avg_win = sum(wins) / len(wins) if wins else 0.0
        avg_loss_abs = abs(sum(losses) / len(losses)) if losses else 0.0
        win_rate = len(wins) / n if n else 0.0
        loss_rate = len(losses) / n if n else 0.0
        expectancy = (win_rate * avg_win) - (loss_rate * avg_loss_abs)
        gross_profit = sum(wins) if wins else 0.0
        gross_loss_abs = abs(sum(losses)) if losses else 0.0
        pf = (gross_profit / gross_loss_abs) if gross_loss_abs > 0 else None

        out.append({
            "group_key": key,
            "trades": n,
            "wins": len(wins),
            "losses": len(losses),
            "win_rate": round(win_rate, 6),
            "avg_win_r": round(avg_win, 6),
            "avg_loss_r_abs": round(avg_loss_abs, 6),
            "expectancy_r": round(expectancy, 6),
            "gross_profit_r": round(gross_profit, 6),
            "gross_loss_r_abs": round(gross_loss_abs, 6),
            "profit_factor": (round(pf, 6) if pf is not None else None),
        })
    return out

def write_csv(path: Path, rows: List[Dict[str, Any]]):
    ensure_dir(path.parent)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

def main():
    ensure_dir(OUTPUT_DIR)

    quality_rows = []
    normalized: List[Outcome] = []

    if not SOURCE.exists():
        summary = {
            "engine_version": "EXPECTANCY_ENGINE_V2",
            "generated_at": datetime.now().isoformat(timespec="seconds"),
            "source_file": str(SOURCE),
            "source_exists": False,
            "normalized_trades": 0,
            "overall_expectancy_r": None,
            "overall_profit_factor": None,
        }
        (OUTPUT_DIR / "expectancy_v2_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        (OUTPUT_DIR / "README_RESULTS_V2.txt").write_text("Canonical outcome_ledger.jsonl not found.", encoding="utf-8")
        return 0

    total = 0
    rejected = 0
    reasons = defaultdict(int)

    for rec in iter_jsonl(SOURCE):
        total += 1
        outcome, reason = normalize_record(rec, SOURCE)
        if outcome is not None:
            normalized.append(outcome)
        else:
            rejected += 1
            reasons[reason or "unknown_reject"] += 1

    for k, v in sorted(reasons.items()):
        quality_rows.append({
            "file": str(SOURCE),
            "issue": k,
            "count": v,
        })

    normalized_rows = [{
        "ts": x.ts,
        "hour": x.hour,
        "strategy": x.strategy,
        "symbol": x.symbol,
        "regime": x.regime,
        "realized_r": round(x.realized_r, 6),
        "source_file": x.source_file,
    } for x in normalized]

    by_strategy = aggregate(normalized, lambda x: x.strategy)
    by_symbol = aggregate(normalized, lambda x: x.symbol)
    by_regime = aggregate(normalized, lambda x: x.regime)
    by_hour = aggregate(normalized, lambda x: ("UNKNOWN" if x.hour is None else f"{x.hour:02d}:00"))

    write_csv(OUTPUT_DIR / "normalized_outcomes_v2.csv", normalized_rows)
    write_csv(OUTPUT_DIR / "data_quality_v2.csv", quality_rows)
    write_csv(OUTPUT_DIR / "expectancy_v2_by_strategy.csv", by_strategy)
    write_csv(OUTPUT_DIR / "expectancy_v2_by_symbol.csv", by_symbol)
    write_csv(OUTPUT_DIR / "expectancy_v2_by_regime.csv", by_regime)
    write_csv(OUTPUT_DIR / "expectancy_v2_by_hour.csv", by_hour)

    wins = [x.realized_r for x in normalized if x.realized_r > 0]
    losses = [x.realized_r for x in normalized if x.realized_r <= 0]

    summary = {
        "engine_version": "EXPECTANCY_ENGINE_V2",
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "source_file": str(SOURCE),
        "source_exists": True,
        "records_total": total,
        "records_rejected": rejected,
        "normalized_trades": len(normalized),
        "wins": len(wins),
        "losses": len(losses),
        "overall_win_rate": (round(len(wins) / len(normalized), 6) if normalized else None),
        "overall_avg_win_r": (round(sum(wins) / len(wins), 6) if wins else None),
        "overall_avg_loss_r_abs": (round(abs(sum(losses) / len(losses)), 6) if losses else None),
    }

    if normalized and wins and losses:
        wr = len(wins) / len(normalized)
        lr = len(losses) / len(normalized)
        aw = sum(wins) / len(wins)
        al = abs(sum(losses) / len(losses))
        expectancy = (wr * aw) - (lr * al)
        gp = sum(wins)
        gl = abs(sum(losses))
        summary["overall_expectancy_r"] = round(expectancy, 6)
        summary["overall_profit_factor"] = round(gp / gl, 6) if gl > 0 else None
    else:
        summary["overall_expectancy_r"] = None
        summary["overall_profit_factor"] = None

    (OUTPUT_DIR / "expectancy_v2_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    lines = []
    lines.append("EXPECTANCY ENGINE V2 RESULTS")
    lines.append("")
    lines.append(f"Source file: {SOURCE}")
    lines.append(f"Records total: {total}")
    lines.append(f"Records rejected: {rejected}")
    lines.append(f"Normalized trades: {len(normalized)}")
    lines.append(f"Overall expectancy (R): {summary['overall_expectancy_r']}")
    lines.append(f"Overall profit factor: {summary['overall_profit_factor']}")
    lines.append("")
    lines.append("Outputs:")
    lines.append("- expectancy_v2_by_strategy.csv")
    lines.append("- expectancy_v2_by_symbol.csv")
    lines.append("- expectancy_v2_by_regime.csv")
    lines.append("- expectancy_v2_by_hour.csv")
    lines.append("- normalized_outcomes_v2.csv")
    lines.append("- data_quality_v2.csv")
    (OUTPUT_DIR / "README_RESULTS_V2.txt").write_text("\n".join(lines), encoding="utf-8")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
