from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, List, Optional, Tuple

_last_ts = 0.0

def _now() -> float:
    return time.time()

def _tick_sec() -> float:
    try:
        v = float((os.environ.get("TBOT_PERF_TICK_SEC") or "10").strip())
        return 10.0 if v <= 0 else v
    except Exception:
        return 10.0

def _safe_mkdir(p: str) -> None:
    try:
        os.makedirs(p, exist_ok=True)
    except Exception:
        pass

def _read_tail_lines(path: str, max_lines: int) -> List[str]:
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            block = 8192
            data = b""
            while size > 0 and data.count(b"\n") <= max_lines + 5:
                step = block if size >= block else size
                size -= step
                f.seek(size)
                data = f.read(step) + data
            lines = data.splitlines()[-max_lines:]
        return [ln.decode("utf-8", errors="replace") for ln in lines if ln.strip()]
    except Exception:
        return []

def _read_last_jsonl_obj(path: str) -> Optional[Dict[str, Any]]:
    lines = _read_tail_lines(path, 1)
    if not lines:
        return None
    try:
        return json.loads(lines[0])
    except Exception:
        return None

def _append_jsonl(path: str, obj: Dict[str, Any]) -> None:
    try:
        _safe_mkdir(os.path.dirname(path))
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except Exception:
        pass

def _write_json(path: str, obj: Dict[str, Any]) -> None:
    try:
        _safe_mkdir(os.path.dirname(path))
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except Exception:
        pass

def _to_float(x: Any) -> Optional[float]:
    try:
        if x is None:
            return None
        return float(x)
    except Exception:
        return None

def _equity_series_from_pnl_ticks(pnl_path: str, max_pts: int = 5000) -> List[Tuple[float, float]]:
    out: List[Tuple[float, float]] = []
    for ln in _read_tail_lines(pnl_path, max_pts):
        try:
            o = json.loads(ln)
            ts = _to_float(o.get("ts"))
            eq = _to_float((o.get("account") or {}).get("equity"))
            if ts is None or eq is None:
                continue
            out.append((ts, eq))
        except Exception:
            continue
    out.sort(key=lambda t: t[0])
    return out

def _max_drawdown(series: List[Tuple[float, float]]) -> Dict[str, Any]:
    if not series:
        return {"max_dd_abs": None, "max_dd_pct": None, "peak": None, "trough": None}
    peak = series[0][1]
    peak_ts = series[0][0]
    max_dd = 0.0
    max_dd_pct = 0.0
    trough = series[0][1]
    trough_ts = series[0][0]

    for ts, eq in series:
        if eq > peak:
            peak = eq
            peak_ts = ts
        dd = peak - eq
        dd_pct = (dd / peak) if peak > 0 else 0.0
        if dd > max_dd:
            max_dd = dd
            max_dd_pct = dd_pct
            trough = eq
            trough_ts = ts

    return {
        "max_dd_abs": max_dd,
        "max_dd_pct": max_dd_pct,
        "peak": {"ts": peak_ts, "equity": peak},
        "trough": {"ts": trough_ts, "equity": trough},
    }

def _day_key(ts: float) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(ts))

def _session_pnl(series: List[Tuple[float, float]]) -> Dict[str, Any]:
    if len(series) < 2:
        return {"pnl_abs": None, "pnl_pct": None, "from": None, "to": None}
    e0 = series[0][1]
    e1 = series[-1][1]
    pnl = e1 - e0
    pnl_pct = (pnl / e0) if e0 else None
    return {"pnl_abs": pnl, "pnl_pct": pnl_pct, "from": {"ts": series[0][0], "equity": e0}, "to": {"ts": series[-1][0], "equity": e1}}

def _day_pnl(series: List[Tuple[float, float]]) -> Dict[str, Any]:
    if len(series) < 2:
        return {"day": None, "pnl_abs": None, "pnl_pct": None}
    last_ts = series[-1][0]
    dk = _day_key(last_ts)
    day_pts = [(ts,eq) for ts,eq in series if _day_key(ts) == dk]
    if len(day_pts) < 2:
        return {"day": dk, "pnl_abs": None, "pnl_pct": None}
    e0 = day_pts[0][1]
    e1 = day_pts[-1][1]
    pnl = e1 - e0
    pnl_pct = (pnl / e0) if e0 else None
    return {"day": dk, "pnl_abs": pnl, "pnl_pct": pnl_pct}

def _gate_reject_counts_from_meta(meta_path: str, max_lines: int = 20000) -> Dict[str, int]:
    # best-effort string scan (no schema assumptions)
    lines = _read_tail_lines(meta_path, max_lines)
    s = "\n".join(lines).lower()

    def cnt(pat: str) -> int:
        try:
            return s.count(pat.lower())
        except Exception:
            return 0

    # core buckets requested
    out = {
        "min_rr": cnt("min_rr"),
        "min_conf": cnt("min_conf"),
        "cooldown": cnt("cooldown"),
        "budget": cnt("budget") + cnt("budget_exceeded") + cnt("b udget_exceeded") + cnt("bUdget_exceeded"),
    }

    # helpful extras (kept minimal)
    out["budget_exceeded"] = cnt("budget_exceeded")
    out["lock_timeout"] = cnt("lock_timeout")
    out["io_fail"] = cnt("io_fail")
    out["gate_reject"] = cnt("gate_reject")
    out["rejected"] = cnt("reject")
    return out

def perf_tick(meta, runroot: str, profile: str) -> None:
    """
    هر TBOT_PERF_TICK_SEC ثانیه:
      - equity curve از pnl_ticks.jsonl
      - max drawdown
      - session/day pnl
      - شمارنده gate_reject_reason از meta_events.jsonl
      - ثبت در runtime\<profile>\analytics\performance.json
      - ثبت journal در runtime\<profile>\analytics\trade_journal.jsonl (snapshot-based)
    """
    global _last_ts
    try:
        t = _now()
        if (t - float(_last_ts or 0.0)) < _tick_sec():
            return
        _last_ts = t

        rr = (runroot or "").strip() or (os.environ.get("TBOT_RUNROOT") or "").strip()
        if not rr:
            return

        prof = (profile or "").strip().lower() or (os.environ.get("TBOT_PROFILE") or "paper").strip().lower()

        logs = os.path.join(rr, "logs")
        pnl_path = os.path.join(logs, "pnl_ticks.jsonl")
        meta_path = os.path.join(logs, "meta_events.jsonl")

        series = _equity_series_from_pnl_ticks(pnl_path) if os.path.exists(pnl_path) else []
        dd = _max_drawdown(series)
        sess = _session_pnl(series)
        day = _day_pnl(series)

        gate_counts = _gate_reject_counts_from_meta(meta_path) if os.path.exists(meta_path) else {
            "min_rr": 0, "min_conf": 0, "cooldown": 0, "budget": 0,
            "budget_exceeded": 0, "lock_timeout": 0, "io_fail": 0, "gate_reject": 0, "rejected": 0
        }

        last_tick = _read_last_jsonl_obj(pnl_path) if os.path.exists(pnl_path) else None
        pos_count = None
        if isinstance(last_tick, dict):
            ps = last_tick.get("positions")
            if isinstance(ps, list):
                pos_count = len(ps)

        perf = {
            "ts": t,
            "profile": prof,
            "equity_curve_points": len(series),
            "session": sess,
            "day": day,
            "max_drawdown": dd,
            "open_positions_count": pos_count,
            "gate_reject_reason_counts": gate_counts,
            # These require realized trade ledger; keep placeholders until you wire fills->journal:
            "trade_metrics": {
                "r_multiple": None,
                "win_rate": None,
                "profit_factor": None,
                "expectancy": None,
                "notes": "Requires realized trade journal (fills/closed-trade PnL + planned risk)."
            }
        }

        # write performance.json (authoritative)
        out_dir = os.path.join(rr, "analytics")
        _safe_mkdir(out_dir)
        _write_json(os.path.join(out_dir, "performance.json"), perf)

        # append journal snapshot
        _append_jsonl(os.path.join(out_dir, "trade_journal.jsonl"), perf)

        # optional meta event
        try:
            if meta is not None:
                meta.write("gate_reject_counts", {"ts": t, "counts": gate_counts})
        except Exception:
            pass

    except Exception:
        return
