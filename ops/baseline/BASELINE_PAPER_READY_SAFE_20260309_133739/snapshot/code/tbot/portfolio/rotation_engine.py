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
    root = (os.environ.get("TBOT_UNIFIED_ROOT") or r"C:\alpaca-bot\ORG_BOT_UNIFIED").strip()
    prof = (os.environ.get("TBOT_PROFILE") or "paper").strip().lower()
    return os.path.join(root, "runtime", prof)

def _read_json(p: str) -> Optional[Dict[str, Any]]:
    try:
        with open(p, "r", encoding="utf-8") as f:
            o = json.load(f)
        return o if isinstance(o, dict) else None
    except Exception:
        return None

def _read_jsonl(p: str, limit: int = 50000) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    try:
        with open(p, "r", encoding="utf-8") as f:
            for line in f:
                if len(out) >= limit:
                    break
                try:
                    o = json.loads(line)
                    if isinstance(o, dict):
                        out.append(o)
                except Exception:
                    pass
    except Exception:
        pass
    return out

def _write_json(p: str, o: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(o, f, ensure_ascii=False, indent=2)
    os.replace(tmp, p)

def _append_jsonl(p: str, o: Dict[str, Any]) -> None:
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "a", encoding="utf-8") as f:
            f.write(json.dumps(o, ensure_ascii=False) + "\n")
    except Exception:
        pass

def _default_cfg() -> Dict[str, Any]:
    return {
        "enabled": True,
        "min_trades": 30,
        "rotation_period_sec": 3600,      # don't rotate too often (1h)
        "cooldown_after_rotation_sec": 900,
        "max_enabled_sids": 3,
        "rank_weights": {
            "expectancy": 0.50,
            "pf": 0.30,
            "dd_r": -0.20
        },
        "min_requirements": {
            "min_pf": 1.10,
            "min_expectancy": 0.0,
            "max_dd_r": 6.0
        },
        "fallback_enabled_sids": ["S01"],
        "sources": {
            "strategy_perf": "strategy_perf_summary.json",
            "strategy_kills": "strategy_kills.json",
            "regime_allowlist": "regime_allowlist.json",
            "meta_enabled": "meta_enabled_sids.json"
        }
    }

def _load_sources(ana: str, cfg: Dict[str, Any]) -> Dict[str, Any]:
    src = cfg.get("sources") if isinstance(cfg.get("sources"), dict) else {}
    out = {}
    for k, fn in src.items():
        if not isinstance(fn, str) or not fn:
            out[k] = None
            continue
        out[k] = _read_json(os.path.join(ana, fn))
    return out

def _sid_list(x: Any) -> List[str]:
    if isinstance(x, list):
        out = []
        for v in x:
            if isinstance(v, str) and v.strip():
                out.append(v.strip())
        return out
    return []

def _perf_map(perf: Optional[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    if not isinstance(perf, dict):
        return {}
    by = perf.get("by_sid")
    if not isinstance(by, dict):
        return {}
    out = {}
    for sid, row in by.items():
        if isinstance(sid, str) and isinstance(row, dict):
            out[sid.strip()] = row
    return out

def _float(v: Any, d: float = 0.0) -> float:
    try:
        return float(v)
    except Exception:
        return d

def _passes_min(row: Dict[str, Any], cfg: Dict[str, Any]) -> Tuple[bool, List[str]]:
    req = cfg.get("min_requirements") if isinstance(cfg.get("min_requirements"), dict) else {}
    rs = []
    pf = _float(row.get("pf"), 0.0)
    ex = _float(row.get("expectancy"), -999.0)
    dd = _float(row.get("dd_r"), 0.0)

    if pf < _float(req.get("min_pf"), 0.0):
        rs.append("PF_BELOW")
    if ex < _float(req.get("min_expectancy"), -999.0):
        rs.append("EXPECTANCY_BELOW")
    if dd > _float(req.get("max_dd_r"), 1e18):
        rs.append("DD_ABOVE")
    return (len(rs) == 0), rs

def _rank_score(row: Dict[str, Any], cfg: Dict[str, Any]) -> float:
    w = cfg.get("rank_weights") if isinstance(cfg.get("rank_weights"), dict) else {}
    exw = _float(w.get("expectancy"), 0.0)
    pfw = _float(w.get("pf"), 0.0)
    ddw = _float(w.get("dd_r"), 0.0)

    ex = _float(row.get("expectancy"), 0.0)
    pf = _float(row.get("pf"), 0.0)
    dd = _float(row.get("dd_r"), 0.0)

    return (exw * ex) + (pfw * pf) + (ddw * dd)

def _rotation_state_path(ana: str) -> str:
    return os.path.join(ana, "rotation_state.json")

def _load_state(ana: str) -> Dict[str, Any]:
    p = _rotation_state_path(ana)
    s = _read_json(p)
    if isinstance(s, dict):
        return s
    return {"last_ts": 0.0, "last_enabled_sids": []}

def _save_state(ana: str, s: Dict[str, Any]) -> None:
    _write_json(_rotation_state_path(ana), s)

def decide(cfg: Dict[str, Any]) -> Dict[str, Any]:
    rr = _runroot()
    ana = os.path.join(rr, "analytics")
    os.makedirs(ana, exist_ok=True)

    cfg = cfg or _default_cfg()
    src = _load_sources(ana, cfg)

    # base candidates: meta_enabled if exists, else regime allowlist, else perf keys
    meta = src.get("meta_enabled") or {}
    base = _sid_list(meta.get("enabled_sids"))

    if not base:
        reg = src.get("regime_allowlist") or {}
        base = _sid_list(reg.get("enabled_sids"))

    perf_map = _perf_map(src.get("strategy_perf"))
    if not base:
        base = sorted(list(perf_map.keys()))

    kills = src.get("strategy_kills") or {}
    killed = set(_sid_list(kills.get("kill_sids") or kills.get("killed") or []))
    base = [s for s in base if s not in killed]

    min_tr = int(cfg.get("min_trades") or 0)
    max_n = int(cfg.get("max_enabled_sids") or 1)
    max_n = max(1, max_n)

    scored = []
    reject = {}
    for sid in base:
        row = perf_map.get(sid, {})
        tr = int(_float(row.get("trades"), 0.0))
        if min_tr and tr < min_tr:
            reject[sid] = ["MIN_TRADES"]
            continue

        ok, rs = _passes_min(row, cfg)
        if not ok:
            reject[sid] = rs
            continue

        scored.append((sid, _rank_score(row, cfg), row))

    scored.sort(key=lambda x: float(x[1]), reverse=True)
    enabled = [x[0] for x in scored[:max_n]]

    if not enabled:
        enabled = _sid_list(cfg.get("fallback_enabled_sids")) or ["S01"]

    return {
        "ts": _now(),
        "ok": True,
        "enabled_sids": enabled,
        "candidates": base,
        "killed_sids": sorted(list(killed)),
        "rejected": reject,
        "top": [{"sid": s, "score": sc} for (s, sc, _) in scored[:10]],
        "cfg": cfg,
    }

def apply(meta=None) -> Dict[str, Any]:
    rr = _runroot()
    ana = os.path.join(rr, "analytics")
    os.makedirs(ana, exist_ok=True)

    cfg_path = os.path.join(ana, "rotation_config.json")
    cfg = _read_json(cfg_path) or _default_cfg()
    if not os.path.exists(cfg_path):
        try:
            _write_json(cfg_path, cfg)
        except Exception:
            pass

    st = _load_state(ana)
    now = _now()
    period = float(cfg.get("rotation_period_sec") or 3600.0)
    if (now - float(st.get("last_ts") or 0.0)) < period:
        rep = {
            "ts": now,
            "ok": True,
            "reason": "RATE_LIMITED",
            "next_allowed_in_sec": max(0.0, period - (now - float(st.get("last_ts") or 0.0))),
            "last_enabled_sids": st.get("last_enabled_sids", []),
        }
        rep_path = os.path.join(ana, "rotation_report.json")
        _write_json(rep_path, rep)
        _append_jsonl(os.path.join(ana, "rotation_history.jsonl"), rep)
        try:
            if meta is not None:
                meta.write("rotation", rep)
        except Exception:
            pass
        return {"ok": True, "runroot": rr, "cfg": cfg_path, "report": rep_path}

    rep = decide(cfg)
    rep["reason"] = "OK"

    rep_path = os.path.join(ana, "rotation_report.json")
    _write_json(rep_path, rep)
    _append_jsonl(os.path.join(ana, "rotation_history.jsonl"), rep)

    # authoritative output: rotation_enabled_sids.json
    out_path = os.path.join(ana, "rotation_enabled_sids.json")
    _write_json(out_path, {"ts": rep.get("ts"), "enabled_sids": rep.get("enabled_sids", []), "source": "rotation_engine"})

    # update state
    st = {"last_ts": now, "last_enabled_sids": rep.get("enabled_sids", [])}
    _save_state(ana, st)

    try:
        if meta is not None:
            meta.write("rotation", rep)
    except Exception:
        pass

    return {
        "ok": True,
        "runroot": rr,
        "cfg": cfg_path,
        "report": rep_path,
        "enabled": out_path,
        "state": _rotation_state_path(ana),
        "history": os.path.join(ana, "rotation_history.jsonl"),
    }

def main():
    out = apply(meta=None)
    print("OK")
    for k,v in out.items():
        print(f"{k}={v}")

if __name__ == "__main__":
    main()
