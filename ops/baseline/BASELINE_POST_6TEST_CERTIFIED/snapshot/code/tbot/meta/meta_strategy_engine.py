from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, Optional, List, Tuple

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
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)

def _append_jsonl(path: str, obj: Dict[str, Any]) -> None:
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except Exception:
        pass

def _default_cfg() -> Dict[str, Any]:
    return {
        "enabled": True,
        "min_trades": 30,
        "min_pf": 1.10,
        "min_expectancy": 0.0,
        "max_dd_pl": 250.0,
        "max_corr_mean_abs": 0.65,
        "fallback_enabled_sids": ["S01"],
        "sources": {
            "strategy_perf": "strategy_perf_summary.json",
            "strategy_kills": "strategy_kills.json",
            "regime_allowlist": "regime_allowlist.json",
            "capital_alloc": "capital_allocations.json"
        }
    }

def _load_sources(ana_dir: str, cfg: Dict[str, Any]) -> Dict[str, Any]:
    src = cfg.get("sources") if isinstance(cfg.get("sources"), dict) else {}
    out = {}
    for k, fn in src.items():
        if not isinstance(fn, str) or not fn:
            out[k] = None
            continue
        out[k] = _read_json(os.path.join(ana_dir, fn))
    return out

def _sid_set_from_list(x: Any) -> List[str]:
    if isinstance(x, list):
        out = []
        for v in x:
            if isinstance(v, str) and v.strip():
                out.append(v.strip())
        return out
    return []

def _extract_perf_map(perf: Optional[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    # expected shape:
    # { "by_sid": { "S01": {"trades":..,"pf":..,"expectancy":..,"dd_pl":..,"corr_mean_abs":..}, ... } }
    if not isinstance(perf, dict):
        return {}
    by = perf.get("by_sid")
    if not isinstance(by, dict):
        return {}
    out = {}
    for sid, row in by.items():
        if not isinstance(sid, str) or not isinstance(row, dict):
            continue
        out[sid.strip()] = row
    return out

def _apply_filters(
    perf_map: Dict[str, Dict[str, Any]],
    cfg: Dict[str, Any]
) -> Tuple[List[str], Dict[str, List[str]]]:
    min_tr = int(cfg.get("min_trades") or 0)
    min_pf = float(cfg.get("min_pf") or 0.0)
    min_ex = float(cfg.get("min_expectancy") or 0.0)
    max_dd = float(cfg.get("max_dd_pl") or 0.0)
    max_corr = float(cfg.get("max_corr_mean_abs") or 1.0)

    keep = []
    reasons: Dict[str, List[str]] = {}

    for sid, row in perf_map.items():
        rs = []
        tr = row.get("trades")
        pf = row.get("pf")
        ex = row.get("expectancy")
        dd = row.get("dd_pl")
        co = row.get("corr_mean_abs")

        try: trf = int(tr)
        except Exception: trf = 0
        try: pff = float(pf)
        except Exception: pff = 0.0
        try: exf = float(ex)
        except Exception: exf = -999.0
        try: ddf = float(dd)
        except Exception: ddf = 0.0
        try: cof = float(co)
        except Exception: cof = 0.0

        if min_tr > 0 and trf < min_tr:
            rs.append("MIN_TRADES")
        if min_pf > 0 and pff < min_pf:
            rs.append("PF_BELOW")
        if exf < min_ex:
            rs.append("EXPECTANCY_BELOW")
        if max_dd > 0 and ddf > max_dd:
            rs.append("DD_ABOVE")
        if max_corr > 0 and abs(cof) > max_corr:
            rs.append("CORR_ABOVE")

        if len(rs) == 0:
            keep.append(sid)
        else:
            reasons[sid] = rs

    return keep, reasons

def decide_enabled_sids(cfg: Dict[str, Any]) -> Dict[str, Any]:
    rr = _runroot()
    ana = os.path.join(rr, "analytics")
    os.makedirs(ana, exist_ok=True)

    cfg = cfg or _default_cfg()
    src = _load_sources(ana, cfg)

    perf_map = _extract_perf_map(src.get("strategy_perf"))

    # 1) start from regime allowlist if exists
    regime = src.get("regime_allowlist") or {}
    regime_sids = _sid_set_from_list(regime.get("enabled_sids"))

    # 2) remove killed sids
    kills = src.get("strategy_kills") or {}
    killed = set(_sid_set_from_list((kills.get("kill_sids") or kills.get("killed") or [])))

    base = regime_sids if regime_sids else sorted(list(perf_map.keys()))
    base = [s for s in base if s not in killed]

    # 3) perf filters
    perf_subset = {s: perf_map.get(s, {}) for s in base}
    keep, reject_reasons = _apply_filters(perf_subset, cfg)

    # 4) capital allocator (optional weight hint)
    alloc = src.get("capital_alloc") or {}
    weights = alloc.get("weights") if isinstance(alloc.get("weights"), dict) else {}

    # fallback
    if not keep:
        keep = _sid_set_from_list(cfg.get("fallback_enabled_sids")) or ["S01"]

    out = {
        "ts": _now(),
        "ok": True,
        "enabled_sids": keep,
        "killed_sids": sorted(list(killed)),
        "regime_enabled_sids": regime_sids,
        "reject_reasons": reject_reasons,
        "weights_hint": weights,
        "cfg": cfg,
    }
    return out

def apply(meta=None) -> Dict[str, Any]:
    rr = _runroot()
    ana = os.path.join(rr, "analytics")
    os.makedirs(ana, exist_ok=True)

    cfg_path = os.path.join(ana, "meta_strategy_config.json")
    cfg = _read_json(cfg_path) or _default_cfg()
    if not os.path.exists(cfg_path):
        try:
            _write_json(cfg_path, cfg)
        except Exception:
            pass

    rep = decide_enabled_sids(cfg)

    rep_path = os.path.join(ana, "meta_strategy_report.json")
    _write_json(rep_path, rep)

    hist = os.path.join(ana, "meta_strategy_history.jsonl")
    _append_jsonl(hist, rep)

    allow_path = os.path.join(ana, "meta_enabled_sids.json")
    _write_json(allow_path, {"ts": rep.get("ts"), "enabled_sids": rep.get("enabled_sids", [])})

    try:
        if meta is not None:
            meta.write("meta_strategy", rep)
    except Exception:
        pass

    return {
        "ok": True,
        "runroot": rr,
        "cfg": cfg_path,
        "report": rep_path,
        "history": hist,
        "allow": allow_path,
    }

def main():
    out = apply(meta=None)
    print("OK")
    for k,v in out.items():
        print(f"{k}={v}")

if __name__ == "__main__":
    main()
