# File: tbot/config.py
from dataclasses import dataclass
import os

def _parse_hhmm(s: str, default: tuple[int,int]) -> tuple[int,int]:
    try:
        parts = s.strip().split(":")
        if len(parts) != 2:
            return default
        h = int(parts[0]); m = int(parts[1])
        if h < 0 or h > 23 or m < 0 or m > 59:
            return default
        return (h, m)
    except Exception:
        return default

def _parse_symbols(s: str, default: tuple[str, ...]) -> tuple[str, ...]:
    try:
        raw = (s or "").strip()
        if not raw:
            return default
        items = []
        for part in raw.replace(";", ",").split(","):
            t = part.strip().upper()
            if t:
                items.append(t)
        return tuple(items) if items else default
    except Exception:
        return default

@dataclass(frozen=True)
class AppConfig:
    env: str = "PAPER"   # PAPER/SHADOW/LIVE
    timezone: str = "America/Los_Angeles"
    symbols: tuple[str, ...] = ("SPY","QQQ","IWM","NVDA","AAPL")

    # Session
    session_start: tuple[int,int] = (9, 30)
    session_end: tuple[int,int] = (16, 0)        # end exclusive
    pre_close_minutes: int = 2                   # minutes before end (inside session)

    # Risk (R units)
    daily_alpha_kill_r: float = -2.0             # if daily_r <= this => alpha off
    weekly_kill_r: float = -5.0                  # if week_r <= this => portfolio lock/kill

def load_config() -> AppConfig:
    env = os.getenv("TBOT_ENV", "PAPER").upper()

    start = _parse_hhmm(os.getenv("TBOT_SESSION_START", "09:30"), (9,30))
    end   = _parse_hhmm(os.getenv("TBOT_SESSION_END", "16:00"), (16,0))

    symbols = _parse_symbols(os.getenv("TBOT_SYMBOLS", ""), ("SPY","QQQ","IWM","NVDA","AAPL"))

    try:
        pre_close = int(os.getenv("TBOT_PRE_CLOSE_MINUTES") or os.getenv("TBOT_PRE_CLOSE_MIN") or "2")
    except Exception:
        pre_close = 2

    try:
        daily_kill = float(os.getenv("TBOT_DAILY_ALPHA_KILL_R", "-2.0"))
    except Exception:
        daily_kill = -2.0

    try:
        weekly_kill = float(os.getenv("TBOT_WEEKLY_KILL_R", "-5.0"))
    except Exception:
        weekly_kill = -5.0

    return AppConfig(
        env=env,
        symbols=symbols,
        session_start=start,
        session_end=end,
        pre_close_minutes=pre_close,
        daily_alpha_kill_r=daily_kill,
        weekly_kill_r=weekly_kill,
    )
# --- TBOT_CFG_EXPORT_V1 ---
# Backwards-compatible "CFG" export for tooling/scripts (non-breaking).
from dataclasses import dataclass
import os
from typing import Tuple

def _parse_hhmm(s: str, default: Tuple[int,int]) -> Tuple[int,int]:
    try:
        s = (s or "").strip()
        if not s:
            return default
        s = s.replace(".", ":")
        parts = s.split(":")
        if len(parts) != 2:
            return default
        h = int(parts[0]); m = int(parts[1])
        if h < 0 or h > 23 or m < 0 or m > 59:
            return default
        return (h, m)
    except Exception:
        return default

def _parse_symbols(s: str, default: Tuple[str,...]) -> Tuple[str,...]:
    try:
        s = (s or "").strip()
        if not s:
            return default
        items = [x.strip().upper() for x in s.split(",") if x.strip()]
        return tuple(items) if items else default
    except Exception:
        return default

@dataclass(frozen=True)
class _Cfg:
    env: str
    symbols: Tuple[str, ...]
    session_start: Tuple[int, int]
    session_end: Tuple[int, int]
    pre_close_min: int
    daily_alpha_kill_r: float
    weekly_kill_r: float

def load_cfg() -> _Cfg:
    env = (os.getenv("TBOT_ENV") or os.getenv("TBOT_MODE") or "PAPER").strip().upper()
    symbols = _parse_symbols(os.getenv("TBOT_SYMBOLS"), ("SPY","QQQ","IWM","NVDA","AAPL"))
    session_start = _parse_hhmm(os.getenv("TBOT_SESSION_START"), (9, 30))
    session_end   = _parse_hhmm(os.getenv("TBOT_SESSION_END"), (16, 0))
    try:
        pre_close_min = int((os.getenv("TBOT_PRE_CLOSE_MINUTES") or os.getenv("TBOT_PRE_CLOSE_MIN") or "2").strip())
    except Exception:
        pre_close_min = 2
    try:
        daily_alpha_kill_r = float((os.getenv("TBOT_DAILY_ALPHA_KILL_R") or "-2.0").strip())
    except Exception:
        daily_alpha_kill_r = -2.0
    try:
        weekly_kill_r = float((os.getenv("TBOT_WEEKLY_KILL_R") or "-5.0").strip())
    except Exception:
        weekly_kill_r = -5.0

    return _Cfg(
        env=env,
        symbols=symbols,
        session_start=session_start,
        session_end=session_end,
        pre_close_min=pre_close_min,
        daily_alpha_kill_r=daily_alpha_kill_r,
        weekly_kill_r=weekly_kill_r,
    )

# Exported singleton
CFG = load_cfg()

def reload_cfg() -> _Cfg:
    global CFG
    CFG = load_cfg()
    return CFG
# --- end TBOT_CFG_EXPORT_V1 ---



