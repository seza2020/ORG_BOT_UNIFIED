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

def _write_json(path: str, obj: Dict[str, Any]) -> None:
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except Exception:
        pass

def _append_jsonl(path: str, obj: Dict[str, Any]) -> None:
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except Exception:
        pass

def _safe_float(x: Any) -> Optional[float]:
    try:
        if x is None:
            return None
        return float(x)
    except Exception:
        return None

def _rolling_dd(pl: List[float]) -> float:
    # max drawdown on cumulative PL
    eq = 0.0
    peak = 0.0
    max_dd = 0.0
    for x in pl:
        eq += x
        if eq > peak:
            peak = eq
        dd = eq - peak
        if dd < max_dd:
            max_dd = dd
    return float(max_dd)  # negative or 0

def _extract_sids(rep: Dict[str, Any]) -> List[Dict[str, Any]]:
    by_sid = rep.get("by_sid") or []
    return by_sid if isinstance(by_sid, list) else []

def decide_kills(strategy_perf: Dict[str, Any], cfg: Dict[str, Any]) -> Dict[str, Any]:
    """
    Policy:
      - do not kill if n < min_trades (insufficient evidence) unless hard_dd exceeded
      - kill if:
          PF < kill_pf  AND n>=min_trades
          or expectancy < kill_expectancy AND n>=min_trades
          or max_drawdown_pl <= -kill_dd_pl (always)
    Output:
      - kill_list with reasons
      - write kill file: analytics/strategy_kills.json
      - optional "enabled_sids.json" allowlist (fail-safe)
    """
    min_trades = int(cfg.get("min_trades", 30))
    kill_pf = float(cfg.get("kill_pf", 1.0))
    kill_expect = float(cfg.get("kill_expectancy", 0.0))
    kill_dd_pl = float(cfg.get("kill_dd_pl", 200.0))  # dollars unless you switch to R

    # optional: if you later produce per-sid PL series, you can tighten
    # for now we approximate dd from sum_pl history if available
    sids = _extract_sids(strategy_perf)

    kill = []
    keep = []

    for row in sids:
        sid = row.get("sid") or "UNKNOWN"
        m = row.get("metrics") or {}
        n = int(m.get("n") or 0)
        pf = _safe_float(m.get("pf"))
        exp = _safe_float(m.get("expectancy"))
        sum_pl = _safe_float(m.get("sum_pl"))

        reasons = []

        # Hard drawdown proxy (best-effort): if sum_pl very negative
        if sum_pl is not None and sum_pl <= -abs(kill_dd_pl):
            reasons.append("HARD_DD_PL_PROXY")

        if n >= min_trades:
            if pf is not None and pf < kill_pf:
                reasons.append("PF_BELOW_KILL")
            if exp is not None and exp < kill_expect:
                reasons.append("EXPECTANCY_BELOW_KILL")

        if reasons:
            kill.append({"sid": sid, "metrics": m, "reasons": reasons})
        else:
            keep.append({"sid": sid, "metrics": m})

    kill.sort(key=lambda x: (len(x["reasons"]), x["sid"]), reverse=True)
    keep.sort(key=lambda x: x["sid"])

    return {
        "ts": _now(),
        "config": cfg,
        "kill_count": len(kill),
        "keep_count": len(keep),
        "kill": kill,
        "keep": keep,
        "notes": {
            "proxy_warning": "HARD_DD_PL_PROXY uses sum_pl (not true dd). For institutional DD: log per-trade pnl series per sid.",
            "safe_default": "no kill for n<min_trades unless hard proxy triggers",
        }
    }

def main():
    rr = _runroot()
    ana = os.path.join(rr, "analytics")
    rep_path = os.path.join(ana, "strategy_performance.json")
    cfg_path = os.path.join(ana, "strategy_kill_config.json")
    out_path = os.path.join(ana, "strategy_kills.json")
    hist_path = os.path.join(ana, "strategy_kills_history.jsonl")
    allow_path = os.path.join(ana, "enabled_sids.json")

    os.makedirs(ana, exist_ok=True)

    rep = _read_json(rep_path) or {}
    cfg = _read_json(cfg_path) or {}

    cfg.setdefault("min_trades", 30)
    cfg.setdefault("kill_pf", 1.0)
    cfg.setdefault("kill_expectancy", 0.0)
    cfg.setdefault("kill_dd_pl", 200.0)

    if not os.path.exists(cfg_path):
        _write_json(cfg_path, cfg)

    out = decide_kills(rep, cfg)

    _write_json(out_path, out)
    _append_jsonl(hist_path, out)

    # create allowlist as fail-safe (keep only)
    try:
        enabled = {"ts": _now(), "enabled_sids": [k["sid"] for k in out.get("keep", []) if k.get("sid")]}
        _write_json(allow_path, enabled)
    except Exception:
        pass

    print("OK")
    print("RUNROOT=", rr)
    print("REP=", rep_path)
    print("CFG=", cfg_path)
    print("OUT=", out_path)
    print("ALLOWLIST=", allow_path)
    print("HIST=", hist_path)

if __name__ == "__main__":
    main()
