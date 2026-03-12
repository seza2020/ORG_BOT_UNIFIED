#!/usr/bin/env python3
"""
P0-2 patch (v2): Robust parse_args detection + split risk caps per-trade vs per-day.

Edits:
  - tbot/main.py:
      * add --gate_max_risk_per_trade_usd, --gate_max_risk_per_day_usd (backward compatible)
      * normalize caps right after parse_args(), regardless of variable name
  - tbot/runtime/gate_state.py:
      * on restart, apply remaining-day ONLY to per-day budget (never per-trade)
  - tbot/runtime/shadow_gate.py:
      * enforce per-trade and per-day budgets with explicit reasons
Backups: logs/ops/patches/P0_2_<ts>/
"""
from __future__ import annotations

import datetime as dt
import re
import shutil
import sys
from pathlib import Path

TS = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
MARK = "P0_2_RISK_BUDGET_SPLIT_V2"
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

    # 1) add argparse args near existing legacy gate_max_risk_usd
    legacy_pat = re.compile(r'(?m)^\s*ap\.add_argument\("--gate_max_risk_usd".*$')
    m = legacy_pat.search(txt)
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

    # 2) find parse_args line (robust). We prefer assignment form to capture var name.
    lines = txt2.splitlines(True)

    parse_idx = None
    var_name = None

    assign_pats = [
        re.compile(r'^\s*(?P<var>\w+)\s*=\s*ap\.parse_args\(\)\s*(#.*)?$', re.M),
        re.compile(r'^\s*(?P<var>\w+)\s*=\s*\w+\.parse_args\(\)\s*(#.*)?$', re.M),
        re.compile(r'^\s*(?P<var>\w+)\s*=\s*parser\.parse_args\(\)\s*(#.*)?$', re.M),
    ]
    # First pass: assignment parse_args
    for i, ln in enumerate(lines):
        for pat in assign_pats:
            m2 = pat.match(ln)
            if m2:
                parse_idx = i
                var_name = m2.group("var")
                break
        if parse_idx is not None:
            break

    # Second pass: any parse_args() call (no assignment)
    if parse_idx is None:
        any_pat = re.compile(r'\.parse_args\(\)\s*(#.*)?$')
        for i, ln in enumerate(lines):
            if any_pat.search(ln):
                parse_idx = i
                var_name = "args"  # fallback
                break

    if parse_idx is None:
        die("Could not find any '.parse_args()' call in tbot/main.py")

    normalize_block = f"""

    # {MARK}
    # Normalize risk caps (backward compatible):
    # - If per-trade/day flags not set, fall back to gate_max_risk_usd.
    # NOTE: This runs immediately after parse_args().
    if getattr({var_name}, "gate_max_risk_per_trade_usd", None) is None:
        {var_name}.gate_max_risk_per_trade_usd = float(getattr({var_name}, "gate_max_risk_usd"))
    if getattr({var_name}, "gate_max_risk_per_day_usd", None) is None:
        {var_name}.gate_max_risk_per_day_usd = float(getattr({var_name}, "gate_max_risk_usd"))
"""
    # insert right after parse_args line
    lines.insert(parse_idx + 1, normalize_block)
    txt3 = "".join(lines)

    backup(path)
    write(path, txt3)
    info(f"Patched tbot/main.py (parse var='{var_name}')")
    return True

def patch_gate_state_py() -> bool:
    path = Path("tbot") / "runtime" / "gate_state.py"
    if not path.exists():
        die("Missing tbot/runtime/gate_state.py")

    txt = read(path)
    if MARK in txt:
        info("gate_state.py already patched.")
        return False

    # locate the old restart mutation block that touches args.gate_max_risk_usd
    # We'll replace from: if hasattr(args,"gate_max_risk_usd") and st.accepted_risk_usd > 0:
    # until the print of effective_risk_cap line (or end of try block).
    block_start = re.compile(r'(?m)^\s*if\s+hasattr\(args,\s*"gate_max_risk_usd"\)\s+and\s+st\.accepted_risk_usd\s*>\s*0\s*:\s*$')
    m = block_start.search(txt)
    if not m:
        die("Could not locate legacy restart risk-cap block in gate_state.py")

    # Find a reasonable end: next blank line after that block or next 'if hasattr(args,' after it
    start = m.start()
    # heuristic: cut until a line that starts at same indent and begins with 'if ' but not inside try
    # simplest: cut until first line that matches r'^\s*if\s+' AFTER start+1 that is not indented deeper than start indent
    start_line = txt[:start].splitlines()[-1] if txt[:start].splitlines() else ""
    indent = re.match(r'^(\s*)', txt[m.start():].splitlines()[0]).group(1)
    # scan forward line-by-line
    lines = txt.splitlines(True)
    # map position->line index
    pos = 0
    start_i = None
    for i, ln in enumerate(lines):
        if pos == start:
            start_i = i
            break
        pos += len(ln)
    if start_i is None:
        # fallback: compute via cumulative search
        # if mismatch, just hard fail
        die("Internal mapping error while patching gate_state.py")

    end_i = None
    for j in range(start_i + 1, len(lines)):
        ln = lines[j]
        if re.match(rf'^{re.escape(indent)}\S', ln) and re.match(rf'^{re.escape(indent)}(if|def|class)\b', ln):
            end_i = j
            break
    if end_i is None:
        end_i = len(lines)

    replacement = f"""{indent}# {MARK}
{indent}# IMPORTANT: Do NOT mutate per-trade cap on restart.
{indent}# Apply remaining-day ONLY to per-day budget.
{indent}if hasattr(args, "gate_max_risk_per_day_usd") and st.accepted_risk_usd > 0:
{indent}    try:
{indent}        orig_day = float(getattr(args, "gate_max_risk_per_day_usd"))
{indent}        rem_day = max(0.0, orig_day - float(st.accepted_risk_usd))
{indent}        setattr(args, "gate_max_risk_per_day_usd", rem_day)
{indent}        print(f"[PERSIST_CAP] day={st.day} risk_used={st.accepted_risk_usd:.2f} orig_day_budget={orig_day:.2f} remaining_day_budget={rem_day:.2f}")
{indent}    except Exception:
{indent}        pass

"""

    new_lines = lines[:start_i] + [replacement] + lines[end_i:]
    txt2 = "".join(new_lines)

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

    # add new cfg fields by replacing the single max_risk_usd line
    cfg_pat = re.compile(r'(?m)^\s*max_risk_usd\s*:\s*float\s*=\s*(?P<dflt>[0-9.]+)\s*$')
    m = cfg_pat.search(txt)
    if not m:
        die("Could not find max_risk_usd field in shadow_gate.py")

    dflt = m.group("dflt")
    cfg_block = f"""    # {MARK}
    # Split caps:
    max_risk_per_trade_usd: float = {dflt}
    max_risk_per_day_usd: float = {dflt}
    # Legacy:
    max_risk_usd: float = {dflt}
"""
    txt1 = cfg_pat.sub(cfg_block.rstrip("\n"), txt, count=1)

    # replace legacy risk_above_max check with dual checks
    legacy_check = re.compile(
        r'(?m)^\s*if\s+risk\s+is\s+not\s+None\s+and\s+risk\s*>\s*float\(self\.cfg\.max_risk_usd\)\s*:\s*\n'
        r'^\s*reasons\.append\("risk_above_max"\)\s*$',
        re.M
    )
    m2 = legacy_check.search(txt1)
    if not m2:
        die("Could not locate legacy risk_above_max check in shadow_gate.py (pattern mismatch).")

    new_check = f"""        # {MARK}
        # Enforce per-trade cap:
        per_trade_cap = float(getattr(self.cfg, "max_risk_per_trade_usd", getattr(self.cfg, "max_risk_usd", 9e9)))
        if risk is not None and float(risk) > per_trade_cap:
            reasons.append("risk_above_max_trade")

        # Enforce per-day budget:
        per_day_budget = float(getattr(self.cfg, "max_risk_per_day_usd", getattr(self.cfg, "max_risk_usd", 9e9)))
        risk_today = float(getattr(self, "_risk_today", 0.0))
        if risk is not None and (risk_today + float(risk)) > per_day_budget:
            reasons.append("daily_risk_budget_reached")
"""
    txt2 = legacy_check.sub(new_check.rstrip("\n"), txt1, count=1)

    backup(path)
    write(path, txt2)
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
    info("Verify:")
    info('  rg -n "P0_2_RISK_BUDGET_SPLIT_V2|gate_max_risk_per_trade_usd|gate_max_risk_per_day_usd|daily_risk_budget_reached|risk_above_max_trade" -S tbot')

if __name__ == "__main__":
    main()
