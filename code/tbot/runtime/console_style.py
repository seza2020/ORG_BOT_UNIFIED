# File: tbot/runtime/console_style.py
from __future__ import annotations

import os
import sys
from dataclasses import dataclass

ESC = "\x1b["

@dataclass(frozen=True)
class Style:
    bold: str = ESC + "1m"
    dim: str = ESC + "2m"
    reset: str = ESC + "0m"

    # basic colors (good contrast on dark terminals)
    red: str = ESC + "31m"
    green: str = ESC + "32m"
    yellow: str = ESC + "33m"
    blue: str = ESC + "34m"
    magenta: str = ESC + "35m"
    cyan: str = ESC + "36m"
    gray: str = ESC + "90m"

def supports_ansi() -> bool:
    # Hard off switch
    v = os.getenv("TBOT_USE_COLOR", "1").strip().lower()
    if v in ("0", "false", "no", "off"):
        return False

    # If output is redirected, avoid ANSI by default
    if not sys.stdout.isatty():
        return False

    # Windows Terminal / modern consoles typically support ANSI.
    # We'll assume yes when TTY unless user disables with TBOT_USE_COLOR=0.
    return True

def color_for_level(level: str, s: Style) -> str:
    level = (level or "").upper()
    if level == "ERROR":
        return s.red
    if level == "WARN":
        return s.yellow
    return s.green

def fmt_kv(key: str, val: str, *, s: Style, use_color: bool) -> str:
    # key dim, value bold
    if not use_color:
        return f"{key}={val}"
    return f"{s.dim}{key}={s.reset}{s.bold}{val}{s.reset}"

def center(text: str, width: int) -> str:
    if len(text) >= width:
        return text[:width]
    pad = width - len(text)
    left = pad // 2
    right = pad - left
    return (" " * left) + text + (" " * right)
