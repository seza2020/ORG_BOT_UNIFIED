from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, List, Optional

def _now() -> float:
    return time.time()

def _runroot() -> str:
    rr = (os.environ.get("TBOT_RUNROOT") or "").strip()
    if rr:
        return rr
    root = (os.environ.get("TBOT_UNIFIED_ROOT") or "").strip()
    prof = (os.environ.get("TBOT_PROFILE") or "paper").strip().lower()
    if root:
        return os.path.join(root, "runtime", prof)
    return os.path.join(r"C:\alpaca-bot\ORG_BOT_UNIFIED", "runtime", prof)

def _read_json(path: str) -> Optional[Dict[str, Any]]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            o = json.load(f)
        return o if isinstance(o, dict) else None
    except Exception:
        return None

def _safe_float(x: Any) -> Optional[float]:
    try:
        if x is None:
            return None
        return float(x)
    except Exception:
        return None

def _norm01(x: float, lo: float, hi: float) -> float:
    if hi <= lo:
        return 0.0
    if x <= lo:
        return 0.0
    if x >= hi:
        return 1.0
    return (x - lo) / (hi - lo)

def _clamp(x: float, lo: float, hi: float) -> float:
    return lo if x < lo else hi if x > hi else x

def allocate(strategy_perf: Dict[str, Any], cfg: Dict[str, Any]) -> Dict[str, Any]:
    """
    Uses strategy_performance.json:
      rep["by_sid"][i]["metrics"] = {n, win_rate, pf, expectancy, sum_pl}
    Produces weights with constraints:
      - sample size gate (n>=min_trades)
      - pf gate (>=min_pf)
      - expectancy gate (>=min_expectancy)
      - max_weight_per_sid cap
      - optional floor weight for approved strategies
    """
    by_sid = strategy_perf.get("by_sid") or []
    if not isinstance(by_sid, list):
        by_sid = []

    min_trades = int(cfg.get("min_trades", 30))
    min_pf = float(cfg.get("min_pf", 1.1))
    min_expect = float(cfg.get("min_expectancy", 0.0))
    max_w = float(cfg.get("max_weight_per_sid", 0.5))
    floor_w = float(cfg.get("floor_weight_per_sid", 0.0))
    use_score = bool(cfg.get("use_score", True))

    # scoring ranges (auditable)
    exp_lo = float(cfg.get("expectancy_lo", -10.0))
    exp_hi = float(cfg.get("expectancy_hi",  10.0))
    pf_lo  = float(cfg.get("pf_lo", 1.0))
    pf_hi  = float(cfg.get("pf_hi", 2.0))
    wr_lo  = float(cfg.get("wr_lo", 0.45))
    wr_hi  = float(cfg.get("wr_hi", 0.60))

    approved = []
    rejected = []

    for row in by_sid:
        sid = row.get("sid") or "UNKNOWN"
        m = row.get("metrics") or {}
        n = int(m.get("n") or 0)
        pf = _safe_float(m.get("pf"))
        exp = _safe_float(m.get("expectancy"))
        wr = _safe_float(m.get("win_rate"))

        reasons = []
        if n < min_trades:
            reasons.append("MIN_TRADES")
        if pf is None or pf < min_pf:
            reasons.append("MIN_PF")
        if exp is None or exp < min_expect:
            reasons.append("MIN_EXPECTANCY")

        if reasons:
            rejected.append({"sid": sid, "metrics": m, "reasons": reasons})
            continue

        # build weight score (bounded positive)
        if use_score and isinstance(row.get("score"), (int, float)):
            raw = float(row.get("score"))
            # shift into positive domain
            s = max(0.0, raw)
        else:
            # composite in [0,3] roughly
            s = 0.0
            if exp is not None:
                s += _norm01(exp, exp_lo, exp_hi) * 1.4
            if pf is not None:
                s += _norm01(pf, pf_lo, pf_hi) * 1.0
            if wr is not None:
                s += _norm01(wr, wr_lo, wr_hi) * 0.6

        approved.append({"sid": sid, "metrics": m, "raw_score": s})

    # normalize
    total = sum(x["raw_score"] for x in approved) if approved else 0.0
    weights = []

    if total <= 0.0:
        # fail-safe: equal weights among approved (or empty)
        k = len(approved)
        for x in approved:
            w = (1.0 / k) if k else 0.0
            weights.append({"sid": x["sid"], "weight": w, "metrics": x["metrics"], "raw_score": x["raw_score"]})
    else:
        for x in approved:
            w = x["raw_score"] / total
            weights.append({"sid": x["sid"], "weight": w, "metrics": x["metrics"], "raw_score": x["raw_score"]})

    # apply floor + cap, then renormalize
    if weights:
        # cap
        for w in weights:
            w["weight"] = _clamp(float(w["weight"]), 0.0, max_w)

        # floor
        if floor_w > 0.0:
            for w in weights:
                w["weight"] = max(float(w["weight"]), floor_w)

        s2 = sum(float(w["weight"]) for w in weights)
        if s2 > 0:
            for w in weights:
                w["weight"] = float(w["weight"]) / s2

    # final ordering
    weights.sort(key=lambda x: x["weight"], reverse=True)

    return {
        "ts": _now(),
        "config": cfg,
        "approved_count": len(weights),
        "rejected_count": len(rejected),
        "weights": weights,
        "rejected": rejected[:200],
        "notes": {
            "fail_safe": "if no approved strategies -> weights empty; allocator never raises",
            "scale_policy": "do not increase max_w or floor_w until >=30 trades per sid and bounded drawdown",
        }
    }

def main():
    rr = _runroot()
    ana = os.path.join(rr, "analytics")
    rep_path = os.path.join(ana, "strategy_performance.json")
    cfg_path = os.path.join(ana, "capital_allocator_config.json")
    out_path = os.path.join(ana, "capital_allocation.json")
    hist_path = os.path.join(ana, "capital_allocation_history.jsonl")
    os.makedirs(ana, exist_ok=True)

    rep = _read_json(rep_path) or {}
    cfg = _read_json(cfg_path) or {}

    # defaults (auditable)
    cfg.setdefault("min_trades", 30)
    cfg.setdefault("min_pf", 1.1)
    cfg.setdefault("min_expectancy", 0.0)
    cfg.setdefault("max_weight_per_sid", 0.50)
    cfg.setdefault("floor_weight_per_sid", 0.00)
    cfg.setdefault("use_score", True)

    cfg.setdefault("expectancy_lo", -10.0)
    cfg.setdefault("expectancy_hi",  10.0)
    cfg.setdefault("pf_lo", 1.0)
    cfg.setdefault("pf_hi", 2.0)
    cfg.setdefault("wr_lo", 0.45)
    cfg.setdefault("wr_hi", 0.60)

    # persist cfg if missing
    if not os.path.exists(cfg_path):
        try:
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(cfg, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    out = allocate(rep, cfg)

    tmp = out_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    os.replace(tmp, out_path)

    try:
        with open(hist_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(out, ensure_ascii=False) + "\n")
    except Exception:
        pass

    print("OK")
    print("RUNROOT=", rr)
    print("REP=", rep_path)
    print("CFG=", cfg_path)
    print("OUT=", out_path)
    print("HIST=", hist_path)

if __name__ == "__main__":
    main()
