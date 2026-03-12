from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, List, Optional, Tuple

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

def _read_jsonl(path: str, max_lines: int = 200000) -> List[Dict[str, Any]]:
    try:
        with open(path, "rb") as f:
            data = f.read()
        lines = data.splitlines()[-max_lines:]
        out = []
        for b in lines:
            if not b.strip():
                continue
            try:
                out.append(json.loads(b.decode("utf-8", errors="replace")))
            except Exception:
                continue
        return out
    except Exception:
        return []

def _safe_float(x: Any) -> Optional[float]:
    try:
        if x is None:
            return None
        return float(x)
    except Exception:
        return None

def _sid_from_trade(t: Dict[str, Any]) -> str:
    # Heuristic: accept multiple common keys
    for k in ("sid","strategy_id","strategy","strategy_name","signal_sid","plan_sid"):
        v = t.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    # allow nested
    for k in ("meta","ctx","context","plan","signal"):
        o = t.get(k)
        if isinstance(o, dict):
            for kk in ("sid","strategy_id","strategy","strategy_name","signal_sid","plan_sid"):
                v = o.get(kk)
                if isinstance(v, str) and v.strip():
                    return v.strip()
    return "UNKNOWN"

def _symbol_from_trade(t: Dict[str, Any]) -> str:
    for k in ("symbol","sym","ticker"):
        v = t.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip().upper()
    o = t.get("fill")
    if isinstance(o, dict):
        v = o.get("symbol")
        if isinstance(v, str) and v.strip():
            return v.strip().upper()
    return "UNKNOWN"

def _realized_pl_from_trade(t: Dict[str, Any]) -> Optional[float]:
    for k in ("realized_pl","pnl","pl","realized_pnl","net_pl"):
        v = _safe_float(t.get(k))
        if v is not None:
            return v
    # fallback: Alpaca activity may include net_amount (string)
    v = _safe_float(t.get("net_amount"))
    return v

def _metrics(pl: List[float]) -> Dict[str, Any]:
    n = len(pl)
    if n == 0:
        return {"n": 0, "win_rate": None, "avg_win": None, "avg_loss": None, "pf": None, "expectancy": None, "sum_pl": None}
    wins = [x for x in pl if x > 0]
    losses = [x for x in pl if x < 0]
    win_rate = len(wins) / n if n else None
    avg_win = sum(wins)/len(wins) if wins else 0.0
    avg_loss = sum(losses)/len(losses) if losses else 0.0
    gross_profit = sum(wins) if wins else 0.0
    gross_loss = -sum(losses) if losses else 0.0
    pf = (gross_profit / gross_loss) if gross_loss > 0 else None
    expectancy = sum(pl)/n if n else None
    return {
        "n": n,
        "win_rate": win_rate,
        "avg_win": avg_win,
        "avg_loss": avg_loss,
        "pf": pf,
        "expectancy": expectancy,
        "sum_pl": sum(pl),
    }

def _score(m: Dict[str, Any]) -> float:
    # Institutional-style composite score (simple, auditable)
    n = float(m.get("n") or 0.0)
    exp = float(m.get("expectancy") or 0.0)
    pf = m.get("pf")
    pfv = float(pf) if pf is not None else 0.0
    wr = float(m.get("win_rate") or 0.0)

    # Penalties for low sample size
    size_mult = min(1.0, n / 30.0)  # scale only after 30+
    # Reward positive expectancy, PF>1
    base = (exp * 1.0) + ((pfv - 1.0) * 10.0) + ((wr - 0.5) * 5.0)
    return base * size_mult

def analyze(trades_path: str) -> Dict[str, Any]:
    rows = _read_jsonl(trades_path, max_lines=200000)
    # Keep only rows with realized_pl
    by_sid: Dict[str, List[float]] = {}
    by_sid_sym: Dict[Tuple[str,str], List[float]] = {}

    for r in rows:
        if not isinstance(r, dict):
            continue
        pl = _realized_pl_from_trade(r)
        if pl is None:
            continue
        sid = _sid_from_trade(r)
        sym = _symbol_from_trade(r)
        by_sid.setdefault(sid, []).append(float(pl))
        by_sid_sym.setdefault((sid, sym), []).append(float(pl))

    sid_out = []
    for sid, pls in by_sid.items():
        m = _metrics(pls)
        sid_out.append({
            "sid": sid,
            "metrics": m,
            "score": _score(m),
        })
    sid_out.sort(key=lambda x: x["score"], reverse=True)

    sid_sym_out = []
    for (sid, sym), pls in by_sid_sym.items():
        m = _metrics(pls)
        sid_sym_out.append({
            "sid": sid,
            "symbol": sym,
            "metrics": m,
            "score": _score(m),
        })
    sid_sym_out.sort(key=lambda x: x["score"], reverse=True)

    return {
        "ts": _now(),
        "source_trades_path": trades_path,
        "n_rows_total": len(rows),
        "n_rows_with_pl": sum(len(v) for v in by_sid.values()),
        "by_sid": sid_out,
        "by_sid_symbol": sid_sym_out[:200],  # cap
        "notes": {
            "sid_extraction": "heuristic: sid/strategy_id/strategy/... or nested meta/ctx/plan/signal",
            "requires": "trades.jsonl with realized_pl (or net_amount) and ideally sid tagging",
            "score": "composite of expectancy + PF + winrate with n/30 sample-size multiplier"
        }
    }

def main():
    rr = _runroot()
    trades = os.path.join(rr, "analytics", "trades.jsonl")
    out_dir = os.path.join(rr, "analytics")
    os.makedirs(out_dir, exist_ok=True)

    rep = analyze(trades)
    out = os.path.join(out_dir, "strategy_performance.json")
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(rep, f, ensure_ascii=False, indent=2)
    os.replace(tmp, out)

    hist = os.path.join(out_dir, "strategy_performance_history.jsonl")
    try:
        with open(hist, "a", encoding="utf-8") as f:
            f.write(json.dumps(rep, ensure_ascii=False) + "\n")
    except Exception:
        pass

    print("OK")
    print("RUNROOT=", rr)
    print("OUT=", out)
    print("HIST=", hist)

if __name__ == "__main__":
    main()
