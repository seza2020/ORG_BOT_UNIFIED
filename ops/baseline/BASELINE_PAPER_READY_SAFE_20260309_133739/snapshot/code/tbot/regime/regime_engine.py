from __future__ import annotations

import json
import os
import time
from urllib.request import Request, urlopen
from typing import Any, Dict, Optional, Tuple, List

def _now() -> float:
    return time.time()

def _headers() -> Optional[Dict[str, str]]:
    kid = (os.environ.get("APCA_API_KEY_ID") or os.environ.get("ALPACA_API_KEY") or "").strip()
    sec = (os.environ.get("APCA_API_SECRET_KEY") or os.environ.get("ALPACA_API_SECRET_KEY") or "").strip()
    if not kid or not sec:
        return None
    return {
        "APCA-API-KEY-ID": kid,
        "APCA-API-SECRET-KEY": sec,
        "Accept": "application/json",
        "User-Agent": "tbot-regime-engine/1.0",
    }

def _data_base(profile: str) -> str:
    b = (os.environ.get("TBOT_ALPACA_DATA_BASE") or "").strip()
    if b:
        return b.rstrip("/")
    # Alpaca market data base (v2)
    return "https://data.alpaca.markets"

def _get_json(url: str, headers: Dict[str, str], timeout: float = 4.0) -> Any:
    req = Request(url, headers=headers, method="GET")
    with urlopen(req, timeout=timeout) as r:
        raw = r.read().decode("utf-8", errors="replace")
    return json.loads(raw)

def _safe_float(x: Any) -> Optional[float]:
    try:
        if x is None:
            return None
        return float(x)
    except Exception:
        return None

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
        "symbol": (os.environ.get("TBOT_REGIME_SYMBOL") or "SPY").strip().upper(),
        "timeframe": "15Min",          # 1Min, 5Min, 15Min, 1Hour, 1Day
        "lookback_bars": 200,          # must be >= 80 for stable stats
        "atr_period": 14,
        "trend_period": 80,            # slope window
        "range_band_atr": 1.2,         # range threshold band
        "vol_hi_atr_pct": 0.016,       # ATR/price high vol threshold
        "vol_lo_atr_pct": 0.008,       # ATR/price low vol threshold
        "trend_slope_hi": 0.00035,     # normalized slope high
        "trend_slope_lo": 0.00015,     # normalized slope low
        "profile": (os.environ.get("TBOT_PROFILE") or "paper").strip().lower(),
        "write_allowlist": True,
        # mapping: which strategy families allowed per regime
        "regime_allowlist": {
            "TREND_HI_VOL": ["S01","S11","S12"],
            "TREND_LO_VOL": ["S01","S12"],
            "RANGE_HI_VOL": ["S08","S12"],
            "RANGE_LO_VOL": ["S08"],
            "UNCERTAIN":    ["S01"]
        }
    }

def _fetch_bars(symbol: str, timeframe: str, limit: int, headers: Dict[str, str]) -> List[Dict[str, Any]]:
    base = _data_base(os.environ.get("TBOT_PROFILE") or "paper")
    # Alpaca v2 bars endpoint
    # https://data.alpaca.markets/v2/stocks/{symbol}/bars?timeframe=15Min&limit=200
    url = f"{base}/v2/stocks/{symbol}/bars?timeframe={timeframe}&limit={int(limit)}"
    js = _get_json(url, headers, timeout=6.0)
    bars = js.get("bars") if isinstance(js, dict) else None
    return bars if isinstance(bars, list) else []

def _ema(values: List[float], period: int) -> Optional[float]:
    if period <= 1 or len(values) < period:
        return None
    k = 2.0 / (period + 1.0)
    ema = values[0]
    for v in values[1:]:
        ema = (v * k) + (ema * (1.0 - k))
    return ema

def _atr(bars: List[Dict[str, Any]], period: int) -> Optional[float]:
    if len(bars) < period + 2:
        return None
    trs = []
    prev_c = None
    for b in bars:
        h = _safe_float(b.get("h"))
        l = _safe_float(b.get("l"))
        c = _safe_float(b.get("c"))
        if h is None or l is None or c is None:
            continue
        if prev_c is None:
            tr = h - l
        else:
            tr = max(h - l, abs(h - prev_c), abs(l - prev_c))
        trs.append(tr)
        prev_c = c
    if len(trs) < period:
        return None
    # EMA ATR
    return _ema(trs[-period:], period)

def _slope_norm(values: List[float], period: int) -> Optional[float]:
    # normalized slope: (last - first) / (period * last)
    if len(values) < period + 1 or period <= 1:
        return None
    seg = values[-(period+1):]
    a = seg[0]
    b = seg[-1]
    if b == 0:
        return None
    return (b - a) / (float(period) * b)

def _classify(atr_pct: float, slope: float, cfg: Dict[str, Any]) -> str:
    vol_hi = float(cfg.get("vol_hi_atr_pct", 0.016))
    vol_lo = float(cfg.get("vol_lo_atr_pct", 0.008))
    s_hi = float(cfg.get("trend_slope_hi", 0.00035))
    s_lo = float(cfg.get("trend_slope_lo", 0.00015))

    vol = "HI_VOL" if atr_pct >= vol_hi else "LO_VOL" if atr_pct <= vol_lo else "MID_VOL"
    trend = "TREND" if abs(slope) >= s_hi else "RANGE" if abs(slope) <= s_lo else "UNCERTAIN"

    if trend == "TREND" and vol == "HI_VOL":
        return "TREND_HI_VOL"
    if trend == "TREND" and vol != "HI_VOL":
        return "TREND_LO_VOL"
    if trend == "RANGE" and vol == "HI_VOL":
        return "RANGE_HI_VOL"
    if trend == "RANGE" and vol != "HI_VOL":
        return "RANGE_LO_VOL"
    return "UNCERTAIN"

def compute_regime(cfg: Dict[str, Any]) -> Dict[str, Any]:
    h = _headers()
    if h is None:
        return {"ts": _now(), "ok": False, "reason": "NO_API_KEYS", "regime": "UNCERTAIN", "metrics": None, "cfg": cfg}

    sym = (cfg.get("symbol") or "SPY").strip().upper()
    tf = (cfg.get("timeframe") or "15Min").strip()
    n = int(cfg.get("lookback_bars") or 200)

    bars = _fetch_bars(sym, tf, n, h)
    closes = []
    for b in bars:
        c = _safe_float(b.get("c"))
        if c is not None:
            closes.append(c)

    if len(closes) < max(int(cfg.get("trend_period", 80))+5, int(cfg.get("atr_period", 14))+5):
        return {"ts": _now(), "ok": False, "reason": "INSUFFICIENT_BARS", "regime": "UNCERTAIN", "metrics": {"bars": len(closes)}, "cfg": cfg}

    atr = _atr(bars, int(cfg.get("atr_period", 14)))
    last = closes[-1]
    if atr is None or last <= 0:
        return {"ts": _now(), "ok": False, "reason": "ATR_FAIL", "regime": "UNCERTAIN", "metrics": None, "cfg": cfg}

    atr_pct = float(atr) / float(last)
    slope = _slope_norm(closes, int(cfg.get("trend_period", 80)))
    if slope is None:
        return {"ts": _now(), "ok": False, "reason": "SLOPE_FAIL", "regime": "UNCERTAIN", "metrics": None, "cfg": cfg}

    regime = _classify(atr_pct, slope, cfg)

    return {
        "ts": _now(),
        "ok": True,
        "reason": "OK",
        "regime": regime,
        "metrics": {
            "symbol": sym,
            "timeframe": tf,
            "bars": len(closes),
            "last_price": last,
            "atr": atr,
            "atr_pct": atr_pct,
            "slope_norm": slope,
        },
        "cfg": cfg,
    }

def apply(meta=None) -> Dict[str, Any]:
    rr = _runroot()
    ana = os.path.join(rr, "analytics")
    os.makedirs(ana, exist_ok=True)

    cfg_path = os.path.join(ana, "regime_config.json")
    cfg = _read_json(cfg_path) or _default_cfg()
    if not os.path.exists(cfg_path):
        try:
            _write_json(cfg_path, cfg)
        except Exception:
            pass

    rep = compute_regime(cfg)

    rep_path = os.path.join(ana, "regime_report.json")
    _write_json(rep_path, rep)

    hist = os.path.join(ana, "regime_history.jsonl")
    _append_jsonl(hist, rep)

    # write allowlist for gate usage
    allow_path = os.path.join(ana, "regime_allowlist.json")
    if cfg.get("write_allowlist", True):
        amap = cfg.get("regime_allowlist") if isinstance(cfg.get("regime_allowlist"), dict) else {}
        enabled = amap.get(rep.get("regime")) if isinstance(amap, dict) else None
        if not isinstance(enabled, list):
            enabled = ["S01"]
        allow = {
            "ts": rep.get("ts"),
            "regime": rep.get("regime"),
            "enabled_sids": enabled
        }
        _write_json(allow_path, allow)

    # meta event best-effort
    try:
        if meta is not None:
            meta.write("regime", rep)
    except Exception:
        pass

    return {
        "ok": True,
        "runroot": rr,
        "cfg": cfg_path,
        "report": rep_path,
        "history": hist,
        "allowlist": allow_path,
    }

def main():
    out = apply(meta=None)
    print("OK")
    for k,v in out.items():
        print(f"{k}={v}")

if __name__ == "__main__":
    main()
