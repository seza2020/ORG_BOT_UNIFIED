# File: tbot/runtime/ansi.py
from __future__ import annotations

import os
import sys
import shutil

CSI = "\x1b["

def supports_color() -> bool:
    # TBOT_USE_COLOR=0 => force off
    v = os.getenv("TBOT_USE_COLOR", "").strip()
    if v == "0":
        return False
    # basic TTY check
    if not hasattr(sys.stdout, "isatty") or not sys.stdout.isatty():
        return False
    # Windows Terminal / modern consoles generally OK. If broken, user can set TBOT_USE_COLOR=0
    return True

def term_width(default: int = 100) -> int:
    try:
        return shutil.get_terminal_size((default, 20)).columns
    except Exception:
        return default

def wrap(s: str, *codes: str) -> str:
    if not codes:
        return s
    return f"{CSI}{';'.join(codes)}m{s}{CSI}0m"

def dim(s: str) -> str:
    return wrap(s, "2")

def bold(s: str) -> str:
    return wrap(s, "1")

def fg(code: int, s: str) -> str:
    # 30-37 normal, 90-97 bright
    return wrap(s, str(code))

def level_color(level: str) -> int:
    # INFO=bright cyan, WARN=bright yellow, ERROR=bright red
    if level == "ERROR":
        return 91
    if level == "WARN":
        return 93
    return 96

def center_stamp(stamp: str, width: int, fill: str = "─") -> str:
    # e.g. ───────── 2026-01-30T07:41:11 ─────────
    core = f" {stamp} "
    if width < len(core) + 2:
        return core
    left = (width - len(core)) // 2
    right = width - len(core) - left
    return (fill * left) + core + (fill * right)
