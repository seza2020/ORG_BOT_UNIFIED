#!/usr/bin/env python3
"""
P0-2 patch (v1): Split risk caps (per-trade vs per-day) + fix restart semantics.

Edits:
  - tbot/main.py: add args --gate_max_risk_per_trade_usd, --gate_max_risk_per_day_usd (backward compatible)
  - tbot/runtime/gate_state.py: on restart, apply remaining-day ONLY to per-day cap, never to per-trade
  - tbot/runtime/shadow_gate.py: enforce both caps with clear reasons

Creates backups under: logs/ops/patches/P0_2_<ts>/
"""
from __future__ import annotations

import datetime as dt
import re
import shutil
import sys
from pathlib import Path

TS = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
MARK = "P0_2_RISK_BUDGET_SPLIT_V1"
BACKUP_DIR = Path("logs") / "ops" / "patches" / f"P0_2_{TS}"

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

def patch_main_py() -> bool:
    path = Path("tbot") / "main.py"
    if not path.exists():
        die("Missing tbot/main.py")

    txt = read(path)
    if MARK in txt:
        info("tbot/main.py already patched.")
        return False

    # 1) add argparse args near existing gate_max_risk_usd
    # find the line that defines gate_max_risk_usd
    pat = re.compile(r'(?m)^\s*ap\.add_argument\("--gate_max_risk_usd".*$')
    m = pat.search(txt)
    if not m:
        die("Could not find --gate_max_risk_usd in tbot/main.py")

    insert_at = m.end()
    insert_block = f"""

    # {MARK}
    # Split risk caps:
    # - gate_max_risk_per_trade_usd: per-plan risk ceiling
    # - gate_max_risk_per_day_usd: cumulative daily budget
    # Backward compatible: if only --gate_max_risk_usd is provided, it applies to both.
    ap.add_argument("--gate_max_risk_per_trade_usd", type=float, default=None,
                    help="per-plan max risk_usd (overrides --gate_max_risk_usd for per-trade)")
    ap.add_argument("--gate_max_risk_per_day_usd", type=float, default=None,
                    help="daily total risk budget (if omitted, defaults to --gate_max_risk_usd)")
"""
    txt2 = txt[:insert_at] + insert_block + txt[insert_at:]

    # 2) ensure after args parsed, we normalize defaults.
    # We look for a place after args=ap.parse_args() or similar.
    # Common pattern: args = ap.parse_args()
    pat2 = re.compile(r'(?m)^\s*args\s*=\s*ap\.parse_args\(\)\s*$')
    m2 = pat2.search(txt2)
    if not m2:
        # fallback: parse_args without assignment? very unlikely
        die("Could not find 'args = ap.parse_args()' in tbot/main.py")

    normalize_block = f"""

    # {MARK}
    # Normalize risk caps (backward compatible):
    # - If per-trade/day flags not set, fall back to gate_max_risk_usd.
    if getattr(args, "gate_max_risk_per_trade_usd", None) is None:
        args.gate_max_risk_per_trade_usd = float(getattr(args, "gate_max_risk_usd"))
    if getattr(args, "gate_max_risk_per_day_usd", None) is None:
        args.gate_max_risk_per_day_usd = float(getattr(args, "gate_max_risk_usd"))
"""
    insert_at2 = m2.end()
    txt3 = txt2[:insert_at2] + normalize_block + txt2[insert_at2:]

    backup(path)
    write(path, txt3)
    info("Patched tbot/main.py")
    return True

def patch_gate_state_py() -> bool:
    path = Path("tbot") / "runtime" / "gate_state.py"
    if not path.exists():
        die("Missing tbot/runtime/gate_state.py")

    txt = read(path)
    if MARK in txt:
        info("gate_state.py already patched.")
        return False

    # Replace the block that mutates args.gate_max_risk_usd based on accepted_risk_usd
    # We target the exact lines around:
    # if hasattr(args, "gate_max_risk_usd") and st.accepted_risk_usd > 0:
    #   orig_r = ...
    #   rem_r = ...
    #   setattr(args,"gate_max_risk_usd", rem_r)
    block_pat = re.compile(
        r'(?s)^\s*if\s+hasattr\(args,\s*"gate_max_risk_usd"\)\s+and\s+st\.accepted_risk_usd\s*>\s*0\s*:\s*'
        r'.*?setattr\(args,\s*"gate_max_risk_usd",\s*rem_r\)\s*'
        r'.*?^\s*print\(f"\[PERSIST_CAP\].*?effective_risk_cap=.*?\)\s*',
        re.M
    )
    m = block_pat.search(txt)
    if not m:
        die("Could not locate restart risk-cap mutation block in gate_state.py (pattern mismatch).")

    replacement = f"""    # {MARK}
    # IMPORTANT: Do NOT mutate per-trade cap on restart.
    # Apply remaining-day ONLY to per-day budget.
    if hasattr(args, "gate_max_risk_per_day_usd") and st.accepted_risk_usd > 0:
        try:
            orig_day = float(getattr(args, "gate_max_risk_per_day_usd"))
            rem_day = max(0.0, orig_day - float(st.accepted_risk_usd))
            setattr(args, "gate_max_risk_per_day_usd", rem_day)
            print(f"[PERSIST_CAP] day={st.day} risk_used={st.accepted_risk_usd:.2f} orig_day_budget={orig_day:.2f} remaining_day_budget={rem_day:.2f}")
        except Exception:
            pass
"""
    txt2 = txt[:m.start()] + replacement + txt[m.end():]

    backup(path)
    write(path, txt2)
    info("Patched tbot/runtime/gate_state.py")
    return True

def patch_shadow_gate_py() -> bool:
    path = Path("tbot") / "runtime" / "shadow_gate.py"
    if not path.exists():
        die("Missing tbot/runtime/shadow_gate.py")

    txt = read(path)
    if MARK in txt:
        info("shadow_gate.py already patched.")
        return False

    # 1) Ensure reason list includes our new reason (optional; safe if absent)
    # file has a list near top including "risk_above_max", "daily_plan_cap_reached"
    txt1 = txt
    if '"daily_risk_budget_reached"' not in txt1:
        txt1 = re.sub(
            r'(?s)(\[\s*".*?"\s*,\s*)("risk_above_max"\s*,\s*"daily_plan_cap_reached")',
            r'\1"daily_risk_budget_reached", \2',
            txt1,
            count=1
        )
    if '"risk_above_max_trade"' not in txt1:
        txt1 = re.sub(
            r'(?s)(\[\s*".*?"\s*,\s*)("risk_above_max"\s*,)',
            r'\1"risk_above_max_trade", \2',
            txt1,
            count=1
        )

    # 2) Add config fields. There's a cfg class with max_risk_usd: float = ...
    # We keep legacy max_risk_usd but add two new ones.
    cfg_pat = re.compile(r'(?m)^\s*max_risk_usd\s*:\s*float\s*=\s*([0-9.]+)\s*$')
    m = cfg_pat.search(txt1)
    if not m:
        die("Could not find max_risk_usd field in shadow_gate.py")

    default_val = m.group(1)
    insert_cfg = f"""    # {MARK}
    # Split caps:
    max_risk_per_trade_usd: float = {default_val}
    max_risk_per_day_usd: float = {default_val}
    # Legacy (kept for backward compat / debugging):
    max_risk_usd: float = {default_val}
"""
    # Replace the single legacy line with our block
    txt2 = cfg_pat.sub(insert_cfg.rstrip("\n"), txt1, count=1)

    # 3) Patch logic where risk_above_max and daily_plan_cap_reached are appended.
    # We find the block:
    # risk = ...
    # if risk is not None and risk > float(self.cfg.max_risk_usd): reasons.append("risk_above_max")
    # ... daily_plan_cap_reached ...
    logic_pat = re.compile(
        r'(?s)(risk\s*=\s*_safe_float\(getattr\(plan,\s*"risk_usd".*?\)\s*,\s*None\)\s*.*?\n)'
        r'(.*?if\s+risk\s+is\s+not\s+None\s+and\s+risk\s*>\s*float\(self\.cfg\.max_risk_usd\)\s*:\s*\n\s*reasons\.append\("risk_above_max"\)\s*\n)'
        ,
        re.M
    )
    m2 = logic_pat.search(txt2)
    if not m2:
        die("Could not locate risk_above_max check block in shadow_gate.py (pattern mismatch).")

    new_logic = m2.group(1) + f"""        # {MARK}
        # Enforce per-trade cap:
        per_trade_cap = float(getattr(self.cfg, "max_risk_per_trade_usd", getattr(self.cfg, "max_risk_usd", 9e9)))
        if risk is not None and risk > per_trade_cap:
            reasons.append("risk_above_max_trade")

        # Enforce per-day budget:
        per_day_budget = float(getattr(self.cfg, "max_risk_per_day_usd", getattr(self.cfg, "max_risk_usd", 9e9)))
        risk_today = float(getattr(self, "_risk_today", 0.0))
        if risk is not None and (risk_today + float(risk)) > per_day_budget:
            reasons.append("daily_risk_budget_reached")
"""
    # Remove old block and inject new one
    txt3 = txt2[:m2.start()] + new_logic + txt2[m2.end():]

    backup(path)
    write(path, txt3)
    info("Patched tbot/runtime/shadow_gate.py")
    return True

def main() -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    changed = False
    changed |= patch_main_py()
    changed |= patch_gate_state_py()
    changed |= patch_shadow_gate_py()

    if not changed:
        info("No edits were needed (already patched).")
    info(f"Backups at: {BACKUP_DIR.as_posix()}")
    info("Next verify:")
    info('  rg -n "P0_2_RISK_BUDGET_SPLIT_V1|gate_max_risk_per_trade_usd|gate_max_risk_per_day_usd|daily_risk_budget_reached|risk_above_max_trade" -S tbot')
    info("Runtime sanity (no market needed):")
    info('  python -c "from tbot.runtime import gate_state; import json,glob; print(sorted(glob.glob(\'logs/ops/gate_state_*.json\'))[-1])"')

if __name__ == "__main__":
    main()
