#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import re
import shutil
import sys
from pathlib import Path

TS = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
MARK = "P0_2_RISK_BUDGET_SPLIT_V3"
BACKUP_DIR = Path("logs") / "ops" / "patches" / f"P0_2_V3_{TS}"

def die(msg: str, code: int = 1) -> None:
    print(f"[P0-2] ERROR: {msg}", file=sys.stderr)
    sys.exit(code)

def info(msg: str) -> None:
    print(f"[P0-2] {msg}")

def backup(path: Path) -> None:
    dst = BACKUP_DIR / path
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dst)

def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")

def write(path: Path, txt: str) -> None:
    path.write_text(txt, encoding="utf-8")

def patch_main_add_args() -> bool:
    path = Path("tbot") / "main.py"
    if not path.exists():
        die("Missing tbot/main.py")

    txt = read(path)
    if MARK in txt:
        info("tbot/main.py already patched (args).")
        return False

    # find legacy arg line
    legacy = re.compile(r'(?m)^\s*ap\.add_argument\("--gate_max_risk_usd".*$')
    m = legacy.search(txt)
    if not m:
        die("Could not find --gate_max_risk_usd in tbot/main.py")

    insert_at = m.end()
    insert = f"""

    # {MARK}
    # Split risk caps:
    # - gate_max_risk_per_trade_usd: per-plan ceiling
    # - gate_max_risk_per_day_usd: daily cumulative budget
    # Backward compatible: if unset, both fall back to --gate_max_risk_usd.
    ap.add_argument("--gate_max_risk_per_trade_usd", type=float, default=None,
                    help="per-plan max risk_usd (defaults to --gate_max_risk_usd)")
    ap.add_argument("--gate_max_risk_per_day_usd", type=float, default=None,
                    help="daily total risk budget (defaults to --gate_max_risk_usd)")
"""
    new = txt[:insert_at] + insert + txt[insert_at:]
    backup(path)
    write(path, new)
    info("Patched tbot/main.py (added split-risk args)")
    return True

def patch_orchestrator_cfg() -> bool:
    path = Path("tbot") / "runtime" / "orchestrator.py"
    if not path.exists():
        die("Missing tbot/runtime/orchestrator.py")

    txt = read(path)
    if MARK in txt:
        info("orchestrator.py already patched.")
        return False

    # We inject a normalization helper near top-level imports (simple + safe).
    # Then patch the ShadowGateCfg(...) call-site to pass per-trade/day.
    helper = f"""

# {MARK}
def _risk_caps_from_args(args):
    \"\"\"Backward-compatible cap split.
    Returns: (per_trade_cap, per_day_budget)
    \"\"\"
    legacy = float(getattr(args, "gate_max_risk_usd", 0.0) or 0.0)
    per_trade = getattr(args, "gate_max_risk_per_trade_usd", None)
    per_day   = getattr(args, "gate_max_risk_per_day_usd", None)
    if per_trade is None:
        per_trade = legacy
    if per_day is None:
        per_day = legacy
    return float(per_trade), float(per_day)
"""

    # insert helper after last import/from in first ~250 lines
    lines = txt.splitlines(True)
    insert_at = 0
    for i, ln in enumerate(lines[:250]):
        if ln.startswith("import ") or ln.startswith("from "):
            insert_at = i + 1
    lines.insert(insert_at, helper)
    txt1 = "".join(lines)

    # Patch ShadowGateCfg(...) callsite:
    # We look for "ShadowGateCfg(" and within next ~60 lines for "max_risk_usd="
    # and inject max_risk_per_trade_usd / max_risk_per_day_usd.
    pat = re.compile(r"ShadowGateCfg\s*\(", re.M)
    m = pat.search(txt1)
    if not m:
        die("Could not find ShadowGateCfg( in orchestrator.py")

    # Find first occurrence of max_risk_usd= within 80 lines after the first ShadowGateCfg(
    start = m.start()
    after = txt1[start:]
    chunk_lines = after.splitlines(True)
    window = "".join(chunk_lines[:120])

    if "max_risk_usd" not in window:
        die("Found ShadowGateCfg( but could not find max_risk_usd= near it (pattern mismatch).")

    # We inject right before "max_risk_usd="
    inj = "        max_risk_per_trade_usd=_risk_caps_from_args(args)[0],\n        max_risk_per_day_usd=_risk_caps_from_args(args)[1],\n"
    window2 = re.sub(r"(?m)^\s*(max_risk_usd\s*=)", inj + r"\1", window, count=1)

    if window2 == window:
        die("Failed to inject per-trade/day caps into ShadowGateCfg block.")

    txt2 = txt1[:start] + window2 + after[len(window):]

    backup(path)
    write(path, txt2)
    info("Patched tbot/runtime/orchestrator.py (cfg caps split)")
    return True

def patch_shadow_gate_enforce() -> bool:
    path = Path("tbot") / "runtime" / "shadow_gate.py"
    if not path.exists():
        die("Missing tbot/runtime/shadow_gate.py")

    txt = read(path)
    if MARK in txt:
        info("shadow_gate.py already patched.")
        return False

    # Replace the legacy cfg field max_risk_usd with split fields (keeping legacy too)
    cfg_pat = re.compile(r'(?m)^\s*max_risk_usd\s*:\s*float\s*=\s*(?P<dflt>[0-9.]+)\s*$')
    m = cfg_pat.search(txt)
    if not m:
        die("Could not find max_risk_usd field in shadow_gate.py")
    dflt = m.group("dflt")
    cfg_block = f"""    # {MARK}
    max_risk_per_trade_usd: float = {dflt}
    max_risk_per_day_usd: float = {dflt}
    # Legacy:
    max_risk_usd: float = {dflt}
"""
    txt1 = cfg_pat.sub(cfg_block.rstrip("\n"), txt, count=1)

    # Replace risk_above_max check block (must exist)
    legacy_check = re.compile(
        r'(?m)^\s*if\s+risk\s+is\s+not\s+None\s+and\s+risk\s*>\s*float\(self\.cfg\.max_risk_usd\)\s*:\s*\n'
        r'^\s*reasons\.append\("risk_above_max"\)\s*$'
    )
    if not legacy_check.search(txt1):
        die("Could not locate legacy risk_above_max check to replace.")

    repl = f"""        # {MARK}
        per_trade_cap = float(getattr(self.cfg, "max_risk_per_trade_usd", getattr(self.cfg, "max_risk_usd", 9e9)))
        per_day_budget = float(getattr(self.cfg, "max_risk_per_day_usd", getattr(self.cfg, "max_risk_usd", 9e9)))
        risk_today = float(getattr(self, "_risk_today", 0.0))

        if risk is not None and float(risk) > per_trade_cap:
            reasons.append("risk_above_max_trade")

        if risk is not None and (risk_today + float(risk)) > per_day_budget:
            reasons.append("daily_risk_budget_reached")
"""
    txt2 = legacy_check.sub(repl.rstrip("\n"), txt1, count=1)

    backup(path)
    write(path, txt2)
    info("Patched tbot/runtime/shadow_gate.py (dual enforce reasons)")
    return True

def main() -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    changed = False
    changed |= patch_main_add_args()
    changed |= patch_orchestrator_cfg()
    changed |= patch_shadow_gate_enforce()
    if not changed:
        info("No edits applied (already patched).")
    info(f"Backups: {BACKUP_DIR.as_posix()}")
    info("Verify:")
    info('  rg -n "P0_2_RISK_BUDGET_SPLIT_V3|gate_max_risk_per_trade_usd|gate_max_risk_per_day_usd|daily_risk_budget_reached|risk_above_max_trade" -S tbot')

if __name__ == "__main__":
    main()
