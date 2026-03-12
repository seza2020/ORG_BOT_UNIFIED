import json
from pathlib import Path
from typing import Dict, Any, Iterable, List, Tuple

def iter_jsonl(p: Path) -> Iterable[Dict[str, Any]]:
    if not p.exists():
        return
    with p.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line=line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except Exception:
                # keep forensic: skip bad line but continue
                continue

def load_meta_events(runroot: Path) -> List[Dict[str, Any]]:
    p = runroot / "logs" / "meta_events.jsonl"
    return list(iter_jsonl(p))

def kcount(events: List[Dict[str, Any]]) -> Dict[str, int]:
    out={}
    for e in events:
        k = e.get("kind") or e.get("name") or e.get("type") or "UNKNOWN"
        out[k]=out.get(k,0)+1
    return out

def by_sid_none(events: List[Dict[str, Any]]) -> Dict[str, Dict[str, int]]:
    # expects strategy_result events
    out={}
    for e in events:
        if (e.get("kind") or e.get("name")) != "strategy_result":
            continue
        payload = e.get("payload") if isinstance(e.get("payload"), dict) else e
        sid = str(payload.get("sid","UNKNOWN"))
        ret = str(payload.get("returned","UNKNOWN"))
        reason = str(payload.get("reason","UNKNOWN"))
        d = out.setdefault(sid, {"TOTAL":0, "NONE":0})
        d["TOTAL"] += 1
        if ret == "NONE":
            d["NONE"] += 1
        # keep top reasons count
        rk = f"REASON::{reason}"
        d[rk] = d.get(rk,0)+1
    return out

def alpha_off_reasons(events: List[Dict[str, Any]]) -> Dict[str, int]:
    out={}
    for e in events:
        if (e.get("kind") or e.get("name")) != "alpha_mode":
            continue
        payload = e.get("payload") if isinstance(e.get("payload"), dict) else e
        mode = str(payload.get("mode",""))
        reason = str(payload.get("reason","UNKNOWN"))
        if mode.upper() == "OFF":
            out[reason]=out.get(reason,0)+1
    return out
