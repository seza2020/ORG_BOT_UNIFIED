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

def _sid_list(x: Any) -> List[str]:
    if isinstance(x, list):
        out = []
        for v in x:
            if isinstance(v, str) and v.strip():
                out.append(v.strip())
        return out
    return []

def _default_cfg() -> Dict[str, Any]:
    return {
        "enabled": True,
        "lookback_events": 2000,              # how many recent meta_events to scan
        "window_sec": 3 * 24 * 3600,          # ignore events older than this window
        "max_same_symbol_enabled": 1,         # allow at most N strategies to be enabled per symbol concurrently
        "max_same_side_on_symbol": 1,         # allow at most N strategies with same side (LONG/SHORT) per symbol
        "block_if_cooccur_rate_ge": 0.70,     # block pairs that co-occur too often (proxy correlation)
        "min_pair_samples": 20,               # minimum samples for pair rate to be considered
        "sources": {
            "rotation_enabled": "rotation_enabled_sids.json",
            "meta_enabled": "meta_enabled_sids.json"
        },
        "outputs": {
            "correlation_blocklist": "correlation_blocklist.json",
            "correlation_report": "correlation_report.json",
            "correlation_history": "correlation_history.jsonl"
        }
    }

def _load_cfg(ana: str) -> Dict[str, Any]:
    p = os.path.join(ana, "correlation_config.json")
    cfg = _read_json(p)
    if not isinstance(cfg, dict):
        cfg = _default_cfg()
        try:
            _write_json(p, cfg)
        except Exception:
            pass
    else:
        # ensure required keys exist
        d = _default_cfg()
        for k,v in d.items():
            cfg.setdefault(k, v)
    return cfg

def _meta_events_path(runroot: str) -> str:
    # prefer meta_events.jsonl (per snapshot)
    p = os.path.join(runroot, "logs", "meta_events.jsonl")
    return p

def _read_last_jsonl(path: str, limit: int) -> List[Dict[str, Any]]:
    # tail-like without huge RAM: read all if small; else read last N lines by byte window
    out: List[Dict[str, Any]] = []
    try:
        if not os.path.exists(path):
            return out
        sz = os.path.getsize(path)
        # heuristic: read last up to 8MB for large files
        max_bytes = 8 * 1024 * 1024
        with open(path, "rb") as f:
            if sz > max_bytes:
                f.seek(-max_bytes, os.SEEK_END)
            raw = f.read().decode("utf-8", errors="replace")
        lines = [ln for ln in raw.splitlines() if ln.strip()]
        lines = lines[-limit:] if limit > 0 else lines
        for ln in lines:
            try:
                o = json.loads(ln)
                if isinstance(o, dict):
                    out.append(o)
            except Exception:
                pass
    except Exception:
        return out
    return out

def _extract_observations(ev: Dict[str, Any]) -> Optional[Tuple[float, str, str, str]]:
    """
    Return (ts, sid, symbol, side) from event if present.
    We accept multiple schemas:
      - event.kind/name = 'strategy_result' OR 'signal_eval'
      - payload includes sid/strategy_id + symbol + side/direction
    """
    try:
        ts = float(ev.get("ts") or ev.get("time") or 0.0)
    except Exception:
        ts = 0.0

    kind = (ev.get("kind") or ev.get("name") or ev.get("event") or "").strip()
    payload = ev.get("payload") if isinstance(ev.get("payload"), dict) else ev

    sid = (payload.get("sid") or payload.get("strategy_id") or payload.get("strategy") or "").strip()
    symbol = (payload.get("symbol") or payload.get("sym") or "").strip().upper()
    side = (payload.get("side") or payload.get("direction") or payload.get("dir") or "").strip().upper()

    if not sid or not symbol:
        return None

    if side not in ("LONG","SHORT","BUY","SELL"):
        # map common
        if side in ("B","L"): side = "LONG"
        elif side in ("S"): side = "SHORT"
        else: side = "UNKNOWN"
    else:
        if side == "BUY": side = "LONG"
        if side == "SELL": side = "SHORT"

    # accept only useful kinds, but allow unknown if fields exist
    if kind and ("strategy_result" in kind or "signal_eval" in kind or "plan" in kind or "order" in kind):
        return (ts, sid, symbol, side)
    # fallback if enough fields exist
    return (ts, sid, symbol, side)

def _pair(a: str, b: str) -> Tuple[str, str]:
    return (a, b) if a <= b else (b, a)

def analyze() -> Dict[str, Any]:
    rr = _runroot()
    ana = os.path.join(rr, "analytics")
    os.makedirs(ana, exist_ok=True)

    cfg = _load_cfg(ana)
    if not cfg.get("enabled", True):
        rep = {"ts": _now(), "ok": True, "reason": "DISABLED"}
        _write_json(os.path.join(ana, cfg["outputs"]["correlation_report"]), rep)
        _append_jsonl(os.path.join(ana, cfg["outputs"]["correlation_history"]), rep)
        return {"ok": True, "reason": "DISABLED"}

    src = cfg.get("sources") if isinstance(cfg.get("sources"), dict) else {}
    rotation = _read_json(os.path.join(ana, str(src.get("rotation_enabled") or "rotation_enabled_sids.json"))) or {}
    meta = _read_json(os.path.join(ana, str(src.get("meta_enabled") or "meta_enabled_sids.json"))) or {}

    enabled = _sid_list(rotation.get("enabled_sids")) or _sid_list(meta.get("enabled_sids"))
    enabled = [s for s in enabled if isinstance(s, str) and s.strip()]

    ev_path = _meta_events_path(rr)
    lookback = int(cfg.get("lookback_events") or 2000)
    events = _read_last_jsonl(ev_path, lookback)

    # build observations in window
    now = _now()
    window = float(cfg.get("window_sec") or (3*24*3600))
    obs: List[Tuple[float,str,str,str]] = []
    for e in events:
        o = _extract_observations(e)
        if not o:
            continue
        ts,sid,symbol,side = o
        if ts and window and (now - ts) > window:
            continue
        if enabled and sid not in enabled:
            continue
        obs.append((ts,sid,symbol,side))

    # symbol concentration checks at "latest snapshot" (use most recent obs per sid)
    last_by_sid: Dict[str, Tuple[float,str,str]] = {}
    for ts,sid,symbol,side in obs:
        cur = last_by_sid.get(sid)
        if cur is None or ts >= cur[0]:
            last_by_sid[sid] = (ts, symbol, side)

    by_symbol: Dict[str, List[Tuple[str,str]]] = {}
    for sid,(ts,symbol,side) in last_by_sid.items():
        by_symbol.setdefault(symbol, []).append((sid, side))

    max_same_symbol = int(cfg.get("max_same_symbol_enabled") or 1)
    max_same_side = int(cfg.get("max_same_side_on_symbol") or 1)

    blocked_sids = set()
    violations = []

    for sym, items in by_symbol.items():
        if len(items) > max_same_symbol:
            # keep first by stable sort (sid) for determinism
            keep = sorted(items, key=lambda x: x[0])[:max_same_symbol]
            keep_sids = set([k[0] for k in keep])
            for sid,_ in items:
                if sid not in keep_sids:
                    blocked_sids.add(sid)
            violations.append({"type":"MAX_SAME_SYMBOL", "symbol":sym, "count":len(items), "max":max_same_symbol, "items":items, "kept":list(keep_sids)})

        # same-side limit
        side_map: Dict[str, List[str]] = {}
        for sid,side in items:
            side_map.setdefault(side, []).append(sid)
        for side, sids in side_map.items():
            if side in ("LONG","SHORT") and len(sids) > max_same_side:
                keep = sorted(sids)[:max_same_side]
                for sid in sids:
                    if sid not in keep:
                        blocked_sids.add(sid)
                violations.append({"type":"MAX_SAME_SIDE", "symbol":sym, "side":side, "count":len(sids), "max":max_same_side, "sids":sids, "kept":keep})

    # pair co-occur proxy correlation: count co-occur on same symbol (regardless side)
    # sample unit: per symbol snapshot at each event timestamp bucket (rounded)
    # build buckets by (symbol, t_bucket)
    buckets: Dict[Tuple[str,int], set] = {}
    for ts,sid,symbol,side in obs:
        tb = int(ts // 60)  # 1-minute buckets
        buckets.setdefault((symbol,tb), set()).add(sid)

    pair_cnt: Dict[Tuple[str,str], int] = {}
    sid_cnt: Dict[str,int] = {}
    for _, sset in buckets.items():
        sids = sorted(list(sset))
        for s in sids:
            sid_cnt[s] = sid_cnt.get(s, 0) + 1
        for i in range(len(sids)):
            for j in range(i+1, len(sids)):
                p = (sids[i], sids[j])
                pair_cnt[p] = pair_cnt.get(p, 0) + 1

    min_samples = int(cfg.get("min_pair_samples") or 20)
    thr = float(cfg.get("block_if_cooccur_rate_ge") or 0.70)

    blocked_pairs = []
    for (a,b), c in pair_cnt.items():
        denom = min(sid_cnt.get(a,0), sid_cnt.get(b,0))
        if denom < min_samples:
            continue
        rate = float(c) / float(denom) if denom else 0.0
        if rate >= thr:
            blocked_pairs.append({"a":a,"b":b,"cooccur":c,"denom":denom,"rate":rate})

    # If a blocked pair exists and both enabled, block the lexicographically later one for determinism
    enabled_set = set(enabled)
    for bp in blocked_pairs:
        a,b = bp["a"], bp["b"]
        if a in enabled_set and b in enabled_set:
            loser = b if a < b else a
            blocked_sids.add(loser)

    final_enabled = [s for s in enabled if s not in blocked_sids]
    if not final_enabled:
        # fail-closed but keep at least one
        final_enabled = [enabled[0]] if enabled else []

    rep = {
        "ts": now,
        "ok": True,
        "reason": "OK",
        "runroot": rr,
        "enabled_in": enabled,
        "enabled_out": final_enabled,
        "blocked_sids": sorted(list(blocked_sids)),
        "violations": violations,
        "blocked_pairs_top": sorted(blocked_pairs, key=lambda x: float(x.get("rate",0.0)), reverse=True)[:25],
        "inputs": {
            "meta_events_path": ev_path,
            "events_scanned": len(events),
            "observations_used": len(obs),
            "window_sec": window,
            "lookback_events": lookback
        },
        "cfg": cfg
    }

    out_block = os.path.join(ana, cfg["outputs"]["correlation_blocklist"])
    out_rep = os.path.join(ana, cfg["outputs"]["correlation_report"])
    out_hist = os.path.join(ana, cfg["outputs"]["correlation_history"])

    _write_json(out_block, {"ts": now, "blocked_sids": rep["blocked_sids"], "blocked_pairs": rep["blocked_pairs_top"], "source":"correlation_risk_engine"})
    _write_json(out_rep, rep)
    _append_jsonl(out_hist, rep)

    # authoritative output to be consumed by higher layer: correlation_enabled_sids.json
    _write_json(os.path.join(ana, "correlation_enabled_sids.json"), {"ts": now, "enabled_sids": final_enabled, "source":"correlation_risk_engine"})

    return {"ok": True, "runroot": rr, "report": out_rep, "blocklist": out_block, "enabled": os.path.join(ana, "correlation_enabled_sids.json")}

def main():
    out = analyze()
    print("OK")
    for k,v in out.items():
        print(f"{k}={v}")

if __name__ == "__main__":
    main()
