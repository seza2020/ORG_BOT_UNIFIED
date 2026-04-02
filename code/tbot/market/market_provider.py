from __future__ import annotations

# --- TBOT_PATCH_BAR_SCHEMA_BEGIN ---
def _bar_get(bar, key, fallback_key):
    # Supports dict-like bars from REST: {'c','vw','t',...} or {'close','vwap','timestamp',...}
    if isinstance(bar, dict):
        if key in bar:
            return bar.get(key)
        return bar.get(fallback_key)
    # Supports object-like bars (SDK)
    if hasattr(bar, key):
        return getattr(bar, key)
    return getattr(bar, fallback_key, None)

def _bar_close(bar):
    return _bar_get(bar, "c", "close")

def _bar_vwap(bar):
    return _bar_get(bar, "vw", "vwap")

def _bar_time(bar):
    return _bar_get(bar, "t", "timestamp")

def _ts_parse_utc(v):
    if v is None:
        return None
    try:
        s = str(v).strip()
        if not s:
            return None
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        return None

def _age_sec(v, now_utc=None):
    dt = _ts_parse_utc(v)
    if dt is None:
        return None
    try:
        now = now_utc or datetime.now(timezone.utc)
        return round(float((now - dt).total_seconds()), 6)
    except Exception:
        return None

# --- TBOT_PATCH_BAR_SCHEMA_END ---


import os
import json
import urllib.request
import urllib.error
from urllib.parse import urlencode
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
from typing import Dict, Tuple, Any, Optional


# NOTE: MarketSnapshot container is permissive and is the expected shape for getattr(snap, "SPY")
from tbot.strategies.base import MarketSnapshot as SnapshotContainer


@dataclass(frozen=True)
class MarketSnap:

    def to_quote(self) -> dict:
        # Standardized quote payload consumed by pricing/strategies.
        # 'mid' falls back to 'last' when bid/ask are not present.
        last = float(getattr(self, "last", 0.0) or 0.0)
        bid = getattr(self, "bid", None)
        ask = getattr(self, "ask", None)
        try:
            bid_f = float(bid) if bid is not None else None
        except Exception:
            bid_f = None
        try:
            ask_f = float(ask) if ask is not None else None
        except Exception:
            ask_f = None
        mid = None
        if bid_f is not None and ask_f is not None and bid_f > 0 and ask_f > 0:
            mid = (bid_f + ask_f) / 2.0
        else:
            mid = last if last > 0 else None

        ts = getattr(self, "ts", None)
        out = {
            "symbol": getattr(self, "symbol", None),
            "last": last if last > 0 else None,
            "bid": bid_f,
            "ask": ask_f,
            "mid": mid,
            "vwap": float(getattr(self, "vwap", 0.0) or 0.0) if getattr(self, "vwap", None) is not None else None,
            "ema_fast": float(getattr(self, "ema_fast", 0.0) or 0.0) if getattr(self, "ema_fast", None) is not None else None,
            "ema_slow": float(getattr(self, "ema_slow", 0.0) or 0.0) if getattr(self, "ema_slow", None) is not None else None,
            "bar_index": getattr(self, "bar_index", None),
            "ts": ts,
        }
        return out

    def to_dict(self) -> dict:
        return self.to_quote()
    symbol: str
    last: Optional[float] = None
    vwap: Optional[float] = None
    ema_fast: Optional[float] = None
    ema_slow: Optional[float] = None
    bar_index: Optional[int] = None
    provider_name: Optional[str] = None
    input_trade_ts: Optional[str] = None
    input_bar_ts: Optional[str] = None
    latest_trade_ts: Optional[str] = None
    latest_bar_ts: Optional[str] = None
    trade_age_sec: Optional[float] = None
    bar_age_sec: Optional[float] = None
    source_stale: Optional[bool] = None
    stale_reason: Optional[str] = None
    trade_fetch_ok: Optional[bool] = None
    bars_fetch_ok: Optional[bool] = None
    @property
    def ef(self) -> Optional[float]:
        # Engine legacy alias: ef == ema_fast
        return self.ema_fast

    @property
    def es(self) -> Optional[float]:
        # Engine legacy alias: es == ema_slow
        return self.ema_slow


def _env(name: str) -> str:
    return (os.environ.get(name) or "").strip()


def _make_headers() -> Dict[str, str]:
    kid = _env("APCA_API_KEY_ID") or _env("APCA_API_KEY")
    sec = _env("APCA_API_SECRET_KEY") or _env("APCA_API_SECRET")

    if "PUT_YOUR" in kid or "PUT_YOUR" in sec:
        raise RuntimeError("APCA_KEYS_ARE_PLACEHOLDER")
    if not kid or not sec:
        raise RuntimeError("APCA_KEYS_MISSING")

    return {
        "Accept": "application/json",
        "User-Agent": "tbot-market/1.0",
        "APCA-API-KEY-ID": kid,
        "APCA-API-SECRET-KEY": sec,
    }


# TBOT_HTTP_CACHE_THROTTLE (V3)
_HTTP_CACHE = {}   # url -> (ts, body)
_LAST_HTTP_TS = 0.0
def _http_get(url: str, headers: Dict[str, str], timeout_sec: float = 10.0) -> str:
    import time, os
    import urllib.request
    import urllib.error
    global _LAST_HTTP_TS, _HTTP_CACHE

    # Throttle: minimum interval between ANY HTTP calls (ms)
    try:
        min_ms = float(os.getenv("TBOT_HTTP_MIN_INTERVAL_MS", "300") or 0.0)
    except Exception:
        min_ms = 300.0

    if min_ms and min_ms > 0:
        now = time.time()
        wait = (min_ms / 1000.0) - (now - float(_LAST_HTTP_TS or 0.0))
        if wait > 0:
            time.sleep(wait)
        _LAST_HTTP_TS = time.time()

    def _fenv(name: str, d: str) -> float:
        try:
            return float(os.getenv(name, d))
        except Exception:
            return float(d)

    # Cache TTLs (seconds)
    ttl_trade = _fenv("TBOT_HTTP_CACHE_TRADE_SEC", "15")
    ttl_bars  = _fenv("TBOT_HTTP_CACHE_BARS_SEC",  "60")

    ttl = 0.0
    if "/trades/latest" in url or "/quotes/latest" in url:
        ttl = ttl_trade
    elif "/bars?" in url:
        ttl = ttl_bars

    # Fresh cache hit
    if ttl and ttl > 0:
        v = _HTTP_CACHE.get(url)
        if v:
            ts, body = v
            if (time.time() - float(ts)) < ttl:
                return body

    # Retry/backoff on 429/5xx, fallback to cached body if exists
    try:
        retries = int(os.getenv("TBOT_HTTP_RETRIES", "4"))
    except Exception:
        retries = 4
    base = _fenv("TBOT_HTTP_RETRY_BASE_SEC", "1.0")

    last_err = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(url, headers=headers, method="GET")
            with urllib.request.urlopen(req, timeout=timeout_sec) as r:
                body = r.read().decode("utf-8", "replace")
            if ttl and ttl > 0:
                _HTTP_CACHE[url] = (time.time(), body)
            return body

        except urllib.error.HTTPError as e:
            last_err = e
            code = getattr(e, "code", None)

            # If we have any cached body (even stale), prefer returning it over triggering fallback pricing
            v = _HTTP_CACHE.get(url)
            if v and code in (429,) or (isinstance(code, int) and code >= 500):
                return v[1]

            if code == 429 or (isinstance(code, int) and code >= 500):
                ra = None
                try:
                    ra = e.headers.get("Retry-After")
                except Exception:
                    ra = None
                try:
                    sleep_s = float(ra) if ra else (base * (2 ** attempt))
                except Exception:
                    sleep_s = base * (2 ** attempt)
                time.sleep(min(30.0, sleep_s))
                continue
            raise

        except Exception as e:
            last_err = e
            v = _HTTP_CACHE.get(url)
            if v:
                return v[1]
            time.sleep(min(10.0, base * (2 ** attempt)))
            continue

    raise last_err

def _http_json(url: str, headers: Dict[str, str], timeout_sec: float = 10.0) -> Any:
    return json.loads(_http_get(url, headers=headers, timeout_sec=timeout_sec))


def _ema(series, span: int) -> Optional[float]:
    if not series:
        return None
    alpha = 2.0 / (span + 1.0)
    e = series[0]
    for x in series[1:]:
        e = alpha * x + (1.0 - alpha) * e
    return float(e)


def _bars_url(sym: str, feed: str, start: datetime, end: datetime, limit: int) -> str:
    params = {
        "timeframe": "1Min",
        "limit": int(limit),
        "feed": feed,
        "start": start.isoformat().replace("+00:00", "Z"),
        "end": end.isoformat().replace("+00:00", "Z"),
        "adjustment": "raw",
        "sort": "asc",
    }
    return f"https://data.alpaca.markets/v2/stocks/{sym}/bars?{urlencode(params)}"


def _sleep(sec: float) -> None:
    import time
    time.sleep(sec)


def _http_json_retry(url: str, headers: dict, tries: int = 5, base_sleep: float = 0.5):
    import urllib.error
    for i in range(tries):
        try:
            return _http_json(url, headers)
        except urllib.error.HTTPError as e:
            code = getattr(e, "code", None)
            # Retry on rate-limit + transient server errors
            if code == 429 or (code is not None and 500 <= code < 600):
                if i < tries - 1:
                    ra = None
                    try:
                        ra = e.headers.get("Retry-After")
                    except Exception:
                        ra = None
                    if ra:
                        try:
                            _sleep(float(ra))
                        except Exception:
                            _sleep(base_sleep * (i + 1) * 2.0)
                    else:
                        _sleep(base_sleep * (i + 1) * 2.0)
                    continue
            raise
        except (urllib.error.URLError, TimeoutError):
            if i < tries - 1:
                _sleep(base_sleep * (i + 1))
                continue
            raise

def _http_get_retry(url: str, headers: dict, timeout_sec: float = 10.0, tries: int = 5, base_sleep: float = 0.5) -> str:
    import urllib.error
    for i in range(tries):
        try:
            return _http_get(url, headers=headers, timeout_sec=timeout_sec)
        except urllib.error.HTTPError as e:
            code = getattr(e, "code", None)
            if code == 429 or (code is not None and 500 <= code < 600):
                if i < tries - 1:
                    ra = None
                    try:
                        ra = e.headers.get("Retry-After")
                    except Exception:
                        ra = None
                    if ra:
                        try:
                            _sleep(float(ra))
                        except Exception:
                            _sleep(base_sleep * (i + 1) * 2.0)
                    else:
                        _sleep(base_sleep * (i + 1) * 2.0)
                    continue
            raise
        except (urllib.error.URLError, TimeoutError):
            if i < tries - 1:
                _sleep(base_sleep * (i + 1))
                continue
            raise

def build_market_snapshot(symbols: Tuple[str, ...], **_kw) -> SnapshotContainer:
    feed = _env("TBOT_DATA_FEED") or "iex"
    bars_feed = _env("TBOT_BARS_FEED") or feed
    debug = (_env("TBOT_MARKET_DEBUG") == "1")

    headers = _make_headers()

    # Narrow recent window for bars to reduce stale historical slices
    end = datetime.now(timezone.utc)
    start = end - timedelta(hours=2)

    out: Dict[str, MarketSnap] = {}

    for sym in symbols:
        last = None
        vwap = None
        ef = None
        es = None
        bar_index = None

        provider_name = f"alpaca:trade={feed},bars={bars_feed}"
        input_trade_ts = None
        input_bar_ts = None
        latest_trade_ts = None
        latest_bar_ts = None
        trade_age_sec = None
        bar_age_sec = None
        source_stale = None
        stale_reason = None
        trade_fetch_ok = False
        bars_fetch_ok = False
        now_utc = datetime.now(timezone.utc)

        # 1) latest trade -> last
        try:
            u = f"https://data.alpaca.markets/v2/stocks/{sym}/trades/latest?feed={feed}"
            j = _http_json_retry(u, headers)
            t = (j.get("trade") or {})
            p = t.get("p")

            input_trade_ts = t.get("t")
            latest_trade_ts = t.get("t")
            trade_fetch_ok = True
            if p is not None:
                last = float(p)
        except urllib.error.HTTPError as e:
            if debug:
                try:
                    body = e.read(200).decode("utf-8", "ignore")
                except Exception:
                    body = ""
                print(f"DEBUG_LAST_HTTPERR {sym} code={e.code} body={body[:120]}")
        except Exception as e:
            if debug:
                print(f"DEBUG_LAST_FAIL {sym} {type(e).__name__}")

        # 2) bars -> vwap + ema
        try:
            u = _bars_url(sym, bars_feed, start, end, limit=240)
            raw = _http_get_retry(u, headers=headers, timeout_sec=10.0)
            j = json.loads(raw)
            bars = j.get("bars", None)
            bars_fetch_ok = True

            # Alpaca bars endpoint may return:
            #   {"bars": {"SPY": [ ... ]}}
            # or a direct list.
            if isinstance(bars, dict):
                bars = bars.get(sym) or bars.get(str(sym).upper()) or bars.get(str(sym).lower())

            if bars is None:
                try:
                    from urllib.parse import urlencode as _urlencode_fallback
                    fallback_url = "https://data.alpaca.markets/v2/stocks/bars?" + _urlencode_fallback({
                        "symbols": sym,
                        "timeframe": "1Min",
                        "limit": 240,
                        "feed": bars_feed,
                    })
                    fallback_raw = _http_get_retry(fallback_url, headers=headers, timeout_sec=10.0)
                    fallback_j = json.loads(fallback_raw)
                    fallback_bars = fallback_j.get("bars", None) if isinstance(fallback_j, dict) else None

                    if isinstance(fallback_bars, dict):
                        fallback_bars = fallback_bars.get(sym) or fallback_bars.get(str(sym).upper()) or fallback_bars.get(str(sym).lower())

                    if isinstance(fallback_bars, list) and fallback_bars:
                        bars = fallback_bars
                        if debug:
                            print(f"DEBUG_BARS_GENERAL_FALLBACK_OK {sym} count={len(bars)}")
                except Exception as _fallback_e:
                    if debug:
                        print(f"DEBUG_BARS_GENERAL_FALLBACK_FAIL {sym} {type(_fallback_e).__name__}")

            if bars is None:
                if debug:
                    print(f"DEBUG_BARS_NULL {sym} feed={feed} raw={raw[:220]}")
            elif isinstance(bars, list) and bars:
                input_bar_ts = _bar_time(bars[-1])
                latest_bar_ts = _bar_time(bars[-1])
                closes = []
                vwaps = []
                for b in bars:
                    c = _bar_close(b)
                    if c is not None:
                        closes.append(float(c))
                    vw = _bar_vwap(b)
                    if vw is not None:
                        vwaps.append(float(vw))

                if vwaps:
                    vwap = float(vwaps[-1])
                elif closes:
                    vwap = float(closes[-1])

                if closes:
                    ef = _ema(closes, span=9)
                    es = _ema(closes, span=20)
                    bar_index = len(closes) - 1

        except urllib.error.HTTPError as e:
            if debug:
                try:
                    body = e.read(220).decode("utf-8", "ignore")
                except Exception:
                    body = ""
                print(f"DEBUG_BARS_HTTPERR {sym} code={e.code} body={body[:160]}")
        except Exception as e:
            if debug:
                print(f"DEBUG_BARS_FAIL {sym} {type(e).__name__}")

        # TBOT_REALPRICE_FALLBACK: avoid fake 100/99/102 when latest trade fails but bars produced values

        if last is None:

            try:

                if vwap is not None:

                    last = float(vwap)

                elif ef is not None:

                    last = float(ef)

                elif es is not None:

                    last = float(es)

            except Exception:

                pass
        trade_age_sec = _age_sec(latest_trade_ts, now_utc=now_utc)
        bar_age_sec = _bar_age_sec_from_bar_open(latest_bar_ts, now_utc=now_utc, bar_seconds=60.0)
        stale_parts = []
        if trade_age_sec is None:
            stale_parts.append("trade_ts_missing")
        elif trade_age_sec > 30.0:
            stale_parts.append("trade_age_exceeded")

        if bar_age_sec is None:
            stale_parts.append("bar_ts_missing")
        elif bar_age_sec > 120.0:
            stale_parts.append("bar_age_exceeded")

        source_stale = True if len(stale_parts) > 0 else False
        stale_reason = "|".join(stale_parts) if len(stale_parts) > 0 else None



        out[sym] = MarketSnap(
            symbol=sym,
            last=last,
            vwap=vwap,
            ema_fast=ef,
            ema_slow=es,
            bar_index=bar_index,
            provider_name=provider_name,
            input_trade_ts=input_trade_ts,
            input_bar_ts=input_bar_ts,
            latest_trade_ts=latest_trade_ts,
            latest_bar_ts=latest_bar_ts,
            trade_age_sec=trade_age_sec,
            bar_age_sec=bar_age_sec,
            source_stale=source_stale,
            stale_reason=stale_reason,
            trade_fetch_ok=trade_fetch_ok,
            bars_fetch_ok=bars_fetch_ok,
        )

    # Return container so callers can do getattr(snap, "SPY") like before
    return SnapshotContainer(**out)


def _marketsnapshot_get_quote(market, symbol: str) -> dict:
    # Works for MarketSnapshot storing MarketSnap objects under dict keys.
    if market is None or not hasattr(market, "__dict__"):
        return {}
    d = dict(market.__dict__)
    v = d.get(symbol) or d.get(symbol.upper()) or d.get(symbol.lower())
    if v is None:
        return {}
    if isinstance(v, dict):
        return v
    if hasattr(v, "to_quote"):
        try:
            return v.to_quote()
        except Exception:
            return {}
    if hasattr(v, "__dict__"):
        try:
            return dict(v.__dict__)
        except Exception:
            return {}
    return {}

def _bar_age_sec_from_bar_open(v, now_utc=None, bar_seconds=60.0):
    dt = _ts_parse_utc(v)
    if dt is None:
        return None
    try:
        now = now_utc or datetime.now(timezone.utc)
        close_dt = dt + timedelta(seconds=float(bar_seconds or 60.0))
        effective_dt = close_dt if close_dt <= now else now
        return round(float((now - effective_dt).total_seconds()), 6)
    except Exception:
        return None
