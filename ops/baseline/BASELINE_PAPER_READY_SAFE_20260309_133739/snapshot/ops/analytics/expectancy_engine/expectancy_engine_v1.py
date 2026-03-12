from __future__ import annotations

import csv
import json
import math
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

ROOT = Path(r"C:\alpaca-bot\ORG_BOT_UNIFIED")
SEARCH_DIRS = [
    ROOT / "runtime" / "paper" / "logs",
    ROOT / "runtime" / "paper" / "validation_v2",
    ROOT / "ops" / "evidence",
]
OUTPUT_DIR = ROOT / "ops" / "analytics" / "expectancy_engine" / "out"

JSON_EXTS = {".json", ".jsonl"}
CSV_EXTS = {".csv"}

TS_KEYS = ["ts", "timestamp", "time", "entry_time", "exit_time", "closed_at", "created_at"]
SYMBOL_KEYS = ["symbol", "ticker", "asset", "instrument"]
STRATEGY_KEYS = ["strategy", "strategy_id", "sid", "setup", "strategy_name"]
REGIME_KEYS = ["regime", "market_regime", "session_regime", "alpha_mode"]
R_KEYS = [
    "pnl_r", "realized_r", "r_multiple", "r", "trade_r", "net_r", "gross_r", "result_r"
]
WIN_KEYS = ["win", "is_win", "winner"]
POLLUTION_NAMES = {"meta_events", "meta_engine", "hardening_events", "evidence_manifest", "paper_runtime_metrics"}

def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)

def safe_float(v: Any) -> Optional[float]:
    if v is None:
        return None
    if isinstance(v, (int, float)):
        if math.isnan(float(v)) or math.isinf(float(v)):
            return None
        return float(v)
    s = str(v).strip()
    if not s:
        return None
    s = s.replace(",", "")
    try:
        f = float(s)
        if math.isnan(f) or math.isinf(f):
            return None
        return f
    except Exception:
        return None

def safe_str(v: Any) -> Optional[str]:
    if v is None:
        return None
    s = str(v).strip()
    return s or None

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

def find_first(d: Dict[str, Any], keys: Iterable[str]) -> Any:
    lowered = {str(k).lower(): v for k, v in d.items()}
    for k in keys:
        if k.lower() in lowered:
            return lowered[k.lower()]
    return None

def looks_like_outcome_path(p: Path) -> bool:
    s = str(p).lower()
    return any(tok in s for tok in [
        "trade", "outcome", "closed", "fill", "execution", "validation", "shadow_plans", "paper", "result"
    ])

def path_polluted(p: Path) -> bool:
    name = p.stem.lower()
    return any(name.startswith(x) for x in POLLUTION_NAMES)

@dataclass
class NormalizedTrade:
    source_file: str
    source_kind: str
    timestamp: Optional[str]
    hour: Optional[int]
    strategy: str
    symbol: str
    regime: str
    r_value: float
    win_flag: int

def infer_r_value(d: Dict[str, Any]) -> Optional[float]:
    direct = find_first(d, R_KEYS)
    rv = safe_float(direct)
    if rv is not None:
        return rv

    pnl = safe_float(find_first(d, ["pnl", "net_pnl", "realized_pnl", "profit", "net_profit"]))
    risk = safe_float(find_first(d, ["risk_usd", "risk", "initial_risk_usd", "planned_risk_usd"]))
    if pnl is not None and risk not in (None, 0.0):
        return pnl / risk

    entry = safe_float(find_first(d, ["entry", "entry_price"]))
    exit_ = safe_float(find_first(d, ["exit", "exit_price"]))
    stop = safe_float(find_first(d, ["stop", "stop_price", "initial_stop"]))
    side = safe_str(find_first(d, ["side", "direction"]))
    if None not in (entry, exit_, stop) and entry != stop:
        if side and side.lower().startswith("short"):
            return (entry - exit_) / abs(entry - stop)
        return (exit_ - entry) / abs(entry - stop)

    return None

def infer_win_flag(d: Dict[str, Any], r_value: float) -> int:
    w = find_first(d, WIN_KEYS)
    if isinstance(w, bool):
        return 1 if w else 0
    sw = safe_str(w)
    if sw:
        if sw.lower() in {"1", "true", "yes", "win", "winner"}:
            return 1
        if sw.lower() in {"0", "false", "no", "loss", "loser"}:
            return 0
    return 1 if r_value > 0 else 0

def normalize_record(d: Dict[str, Any], source_file: Path, source_kind: str) -> Tuple[Optional[NormalizedTrade], Optional[str]]:
    r_value = infer_r_value(d)
    if r_value is None:
        return None, "missing_r_value"

    ts_raw = find_first(d, TS_KEYS)
    dt = parse_ts(ts_raw)
    ts_str = dt.isoformat(timespec="seconds") if dt else safe_str(ts_raw)
    hour = dt.hour if dt else None

    strategy = safe_str(find_first(d, STRATEGY_KEYS)) or "UNKNOWN"
    symbol = safe_str(find_first(d, SYMBOL_KEYS)) or "UNKNOWN"
    regime = safe_str(find_first(d, REGIME_KEYS)) or "UNKNOWN"
    win_flag = infer_win_flag(d, r_value)

    trade = NormalizedTrade(
        source_file=str(source_file),
        source_kind=source_kind,
        timestamp=ts_str,
        hour=hour,
        strategy=strategy,
        symbol=symbol,
        regime=regime,
        r_value=float(r_value),
        win_flag=int(win_flag),
    )
    return trade, None

def iter_json_records(path: Path) -> Iterable[Dict[str, Any]]:
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

def iter_csv_records(path: Path) -> Iterable[Dict[str, Any]]:
    try:
        with path.open("r", encoding="utf-8", errors="ignore", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                yield dict(row)
    except Exception:
        return

def collect_candidate_files() -> List[Path]:
    found: List[Path] = []
    for base in SEARCH_DIRS:
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if not p.is_file():
                continue
            ext = p.suffix.lower()
            if ext not in JSON_EXTS and ext not in CSV_EXTS:
                continue
            if path_polluted(p):
                continue
            if not looks_like_outcome_path(p):
                continue
            found.append(p)
    uniq = []
    seen = set()
    for p in found:
        s = str(p).lower()
        if s not in seen:
            seen.add(s)
            uniq.append(p)
    return sorted(uniq, key=lambda x: str(x).lower())

def aggregate(rows: List[NormalizedTrade], key_fn) -> List[Dict[str, Any]]:
    groups: Dict[str, List[NormalizedTrade]] = defaultdict(list)
    for r in rows:
        groups[key_fn(r)].append(r)

    out: List[Dict[str, Any]] = []
    for key, items in sorted(groups.items(), key=lambda kv: kv[0]):
        n = len(items)
        wins = [x.r_value for x in items if x.r_value > 0]
        losses = [x.r_value for x in items if x.r_value <= 0]
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

def write_csv(path: Path, rows: List[Dict[str, Any]]) -> None:
    ensure_dir(path.parent)
    if not rows:
        with path.open("w", encoding="utf-8", newline="") as f:
            f.write("")
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

def main() -> int:
    ensure_dir(OUTPUT_DIR)

    candidates = collect_candidate_files()
    inventory_rows = [{"file": str(p), "size_bytes": p.stat().st_size} for p in candidates]
    write_csv(OUTPUT_DIR / "candidate_file_inventory.csv", inventory_rows)

    normalized: List[NormalizedTrade] = []
    quality_rows: List[Dict[str, Any]] = []
    file_stats: List[Dict[str, Any]] = []

    for path in candidates:
        source_kind = path.suffix.lower().lstrip(".")
        total = 0
        accepted = 0
        rejected = 0
        reasons: Dict[str, int] = defaultdict(int)

        records = iter_json_records(path) if path.suffix.lower() in JSON_EXTS else iter_csv_records(path)
        for rec in records:
            total += 1
            trade, reason = normalize_record(rec, path, source_kind)
            if trade is not None:
                normalized.append(trade)
                accepted += 1
            else:
                rejected += 1
                reasons[reason or "unknown_reject"] += 1

        row = {
            "file": str(path),
            "records_total": total,
            "records_accepted": accepted,
            "records_rejected": rejected,
            "top_reject_reason": (sorted(reasons.items(), key=lambda kv: kv[1], reverse=True)[0][0] if reasons else None),
        }
        file_stats.append(row)

        for k, v in sorted(reasons.items()):
            quality_rows.append({
                "file": str(path),
                "issue": k,
                "count": v,
            })

    normalized_rows = [{
        "source_file": x.source_file,
        "source_kind": x.source_kind,
        "timestamp": x.timestamp,
        "hour": x.hour,
        "strategy": x.strategy,
        "symbol": x.symbol,
        "regime": x.regime,
        "r_value": round(x.r_value, 6),
        "win_flag": x.win_flag,
    } for x in normalized]

    write_csv(OUTPUT_DIR / "normalized_trades.csv", normalized_rows)
    write_csv(OUTPUT_DIR / "source_file_stats.csv", file_stats)
    write_csv(OUTPUT_DIR / "data_quality_report.csv", quality_rows)

    by_strategy = aggregate(normalized, lambda x: x.strategy)
    by_symbol = aggregate(normalized, lambda x: x.symbol)
    by_regime = aggregate(normalized, lambda x: x.regime)
    by_hour = aggregate(normalized, lambda x: ("UNKNOWN" if x.hour is None else f"{x.hour:02d}:00"))

    write_csv(OUTPUT_DIR / "expectancy_by_strategy.csv", by_strategy)
    write_csv(OUTPUT_DIR / "expectancy_by_symbol.csv", by_symbol)
    write_csv(OUTPUT_DIR / "expectancy_by_regime.csv", by_regime)
    write_csv(OUTPUT_DIR / "expectancy_by_hour.csv", by_hour)

    total = len(normalized)
    wins = [x.r_value for x in normalized if x.r_value > 0]
    losses = [x.r_value for x in normalized if x.r_value <= 0]
    summary = {
        "engine_version": "EXPECTANCY_ENGINE_V1",
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "candidate_files": len(candidates),
        "normalized_trades": total,
        "wins": len(wins),
        "losses": len(losses),
        "overall_win_rate": (round(len(wins) / total, 6) if total else None),
        "overall_avg_win_r": (round(sum(wins) / len(wins), 6) if wins else None),
        "overall_avg_loss_r_abs": (round(abs(sum(losses) / len(losses)), 6) if losses else None),
    }

    if total and wins and losses:
        wr = len(wins) / total
        lr = len(losses) / total
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

    (OUTPUT_DIR / "expectancy_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    lines = []
    lines.append("EXPECTANCY ENGINE V1 RESULTS")
    lines.append("")
    lines.append(f"Candidate files scanned: {len(candidates)}")
    lines.append(f"Normalized trades: {total}")
    lines.append(f"Overall expectancy (R): {summary['overall_expectancy_r']}")
    lines.append(f"Overall profit factor: {summary['overall_profit_factor']}")
    lines.append("")
    if total == 0:
        lines.append("No normalized trade outcomes were found.")
        lines.append("Review candidate_file_inventory.csv and data_quality_report.csv.")
    else:
        lines.append("Primary outputs:")
        lines.append("- expectancy_by_strategy.csv")
        lines.append("- expectancy_by_symbol.csv")
        lines.append("- expectancy_by_regime.csv")
        lines.append("- expectancy_by_hour.csv")
        lines.append("- normalized_trades.csv")
        lines.append("- data_quality_report.csv")

    (OUTPUT_DIR / "README_RESULTS.txt").write_text("\n".join(lines), encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
