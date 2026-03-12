from __future__ import annotations

import json
import os
import time
from urllib.request import Request, urlopen

_last_ts = 0.0

def _now() -> float:
    return time.time()

def _tick_sec() -> float:
    try:
        v = float((os.environ.get("TBOT_PNL_TICK_SEC") or "10").strip())
        return 10.0 if v <= 0 else v
    except Exception:
        return 10.0

def _trade_base(profile: str) -> str:
    b = (os.environ.get("TBOT_ALPACA_TRADE_BASE") or "").strip()
    if b:
        return b.rstrip("/")
    b = (os.environ.get("APCA_API_BASE_URL") or "").strip()
    if b:
        return b.rstrip("/")
    p = (profile or "").strip().lower()
    if p in ("shadow","paper"):
        return "https://paper-api.alpaca.markets"
    return "https://api.alpaca.markets"

def _headers():
    kid = (os.environ.get("APCA_API_KEY_ID") or os.environ.get("ALPACA_API_KEY") or "").strip()
    sec = (os.environ.get("APCA_API_SECRET_KEY") or os.environ.get("ALPACA_API_SECRET_KEY") or "").strip()
    if not kid or not sec:
        return None
    return {
        "APCA-API-KEY-ID": kid,
        "APCA-API-SECRET-KEY": sec,
        "Accept": "application/json",
        "User-Agent": "tbot-pnl-tick/1.0",
    }

def _get_json(url: str, headers: dict, timeout: float = 3.0):
    req = Request(url, headers=headers, method="GET")
    with urlopen(req, timeout=timeout) as r:
        raw = r.read().decode("utf-8", errors="replace")
    return json.loads(raw)

def _append_jsonl(path: str, obj: dict):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except Exception:
        pass

def pnl_tick(meta, runroot: str, profile: str):
    """
    هر TBOT_PNL_TICK_SEC ثانیه:
      - /v2/account
      - /v2/positions
      - meta.write(kind='pnl_tick', payload)
      - append: <RUNROOT>\\logs\\pnl_ticks.jsonl
    Fail-safe: هیچ exceptionی بالا نمی‌اندازد.
    """
    global _last_ts
    try:
        t = _now()
        if (t - float(_last_ts or 0.0)) < _tick_sec():
            return
        _last_ts = t

        h = _headers()
        if h is None:
            return

        rr = (runroot or "").strip() or (os.environ.get("TBOT_RUNROOT") or "").strip()
        if not rr:
            return

        prof = (profile or "").strip().lower() or (os.environ.get("TBOT_PROFILE") or "paper").strip().lower()
        base = _trade_base(prof)

        acct = _get_json(f"{base}/v2/account", h, timeout=3.0)
        pos  = _get_json(f"{base}/v2/positions", h, timeout=3.0)

        payload = {
            "ts": t,
            "profile": prof,
            "base": base,
            "account": {
                "equity": acct.get("equity"),
                "last_equity": acct.get("last_equity"),
                "cash": acct.get("cash"),
                "portfolio_value": acct.get("portfolio_value"),
                "buying_power": acct.get("buying_power"),
                "daytrade_count": acct.get("daytrade_count"),
            },
            "positions": [],
        }

        if isinstance(pos, list):
            for p in pos:
                if not isinstance(p, dict):
                    continue
                payload["positions"].append({
                    "symbol": p.get("symbol"),
                    "qty": p.get("qty"),
                    "side": p.get("side"),
                    "avg_entry_price": p.get("avg_entry_price"),
                    "current_price": p.get("current_price"),
                    "market_value": p.get("market_value"),
                    "unrealized_pl": p.get("unrealized_pl"),
                    "unrealized_plpc": p.get("unrealized_plpc"),
                    "unrealized_intraday_pl": p.get("unrealized_intraday_pl"),
                    "unrealized_intraday_plpc": p.get("unrealized_intraday_plpc"),
                    "cost_basis": p.get("cost_basis"),
                })

        try:
            if meta is not None:
                meta.write("pnl_tick", payload)
        except Exception:
            pass

        out = os.path.join(rr, "logs", "pnl_ticks.jsonl")
        _append_jsonl(out, payload)

    except Exception:
        return
