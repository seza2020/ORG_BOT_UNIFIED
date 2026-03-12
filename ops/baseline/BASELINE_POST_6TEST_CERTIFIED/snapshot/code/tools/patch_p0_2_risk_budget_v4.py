#!/usr/bin/env python3
"""
P0-2 patch (Risk budget split + fix restart semantics)

- Adds CLI args:
    --gate_max_risk_per_trade_usd  (per-plan cap)
    --gate_max_risk_per_day_usd    (daily budget)
  Keeps --gate_max_risk_usd as backward-compatible alias (mapped to per-trade).

- Fixes gate_state.py: previously subtracted accepted_risk_usd from gate_max_risk_usd.
  Now it subtracts from gate_max_risk_per_day_usd (daily), and never mutates per-trade cap.

- Extends shadow_gate.py config & checks:
    risk_above_max_trade
    daily_risk_budget_reached

- Wires orchestrator -> shadow_gate config.

Backups stored under logs/ops/patches/P0_2_<ts>/...
"""
from __future__ import annotations

import datetime as dt
import re
import shutil
import sys
from pathlib import Path

MARK = "P0_2_RISK_BUDGET_SPLIT_V1"

def die(msg: str, code: int = 1) -> None:
    print(f"[P0-2] ERROR: {msg}", file=sys.stderr)
    sys.exit(code)

def info(msg: str) -> None:
    print(f"[P0-2] {msg}")

def root_from_cwd() -> Path:
    p = Path.cwd().resolve()
    for q in [p, *p.parents]:
        if (q / "tbot").is_dir() and (q / "tools").is_dir():
            return q
    die("Run from repo root (must contain ./tbot and ./tools).")

def backup(root: Path, f: Path, bdir: Path) -> None:
    rel = f.relative_to(root)
    dest = bdir / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, dest)

def read(f: Path) -> str:
    return f.read_text(encoding="utf-8", errors="ignore")

def write(f: Path, s: str) -> None:
    f.write_text(s, encoding="utf-8")

def patch_main_py(root: Path, bdir: Path) -> bool:
    f = root / "tbot" / "main.py"
    if not f.exists():
        die("Missing tbot/main.py")

    txt = read(f)
    if MARK in txt:
        info("tbot/main.py already patched.")
        return False

    # 1) Insert new add_argument lines near existing --gate_max_risk_usd
    pat_arg = r'(ap\.add_argument\("--gate_max_risk_usd"[^\n]*\)\s*\n)'
    m = re.search(pat_arg, txt)
    if not m:
        die("Could not find ap.add_argument(\"--gate_max_risk_usd\"...) in tbot/main.py")

    insert = (
        m.group(1) +
        f'    # {MARK}\n'
        '    ap.add_argument("--gate_max_risk_per_trade_usd", type=float, default=None,\n'
        '                    help="Per-trade (per shadow plan) risk cap in USD. If omitted, falls back to --gate_max_risk_usd.")\n'
        '    ap.add_argument("--gate_max_risk_per_day_usd", type=float, default=None,\n'
        '                    help="Daily cumulative risk budget in USD (sum of accepted plan risk_usd). If omitted, no daily budget is enforced.")\n'
    )
    txt2 = re.sub(pat_arg, insert, txt, count=1)

    # 2) After parse_args(raw_argv): map legacy arg -> per_trade if per_trade is None
    pat_parse = r'(args\s*=\s*ap\.parse_args\(\s*raw_argv\s*\)\s*\n)'
    m2 = re.search(pat_parse, txt2)
    if not m2:
        die("Could not find args = ap.parse_args(raw_argv) in tbot/main.py (pattern mismatch).")

    inject = (
        m2.group(1) +
        f'    # {MARK}\n'
        '    # Back-compat: --gate_max_risk_usd historically existed; treat it as per-trade cap.\n'
        '    if getattr(args, "gate_max_risk_per_trade_usd", None) is None:\n'
        '        args.gate_max_risk_per_trade_usd = float(getattr(args, "gate_max_risk_usd", 0.0))\n'
        '    # If daily budget not provided, leave as None (no daily enforcement).\n'
    )
    txt3 = re.sub(pat_parse, inject, txt2, count=1)

    # 3) Wire args into orchestrator call: replace gate_max_risk_usd=... with two params
    # We will keep existing param for compatibility if orchestrator still expects it, but add new ones.
    # Find the kwarg line "gate_max_risk_usd=float(args.gate_max_risk_usd),"
    pat_kw = r'(\s*gate_max_risk_usd\s*=\s*float\(args\.gate_max_risk_usd\)\s*,\s*\n)'
    if not re.search(pat_kw, txt3):
        die("Could not find gate_max_risk_usd=float(args.gate_max_risk_usd), in tbot/main.py")

    repl = (
        f'        # {MARK}\n'
        '        gate_max_risk_usd=float(args.gate_max_risk_usd),  # legacy alias\n'
        '        gate_max_risk_per_trade_usd=float(args.gate_max_risk_per_trade_usd),\n'
        '        gate_max_risk_per_day_usd=(None if args.gate_max_risk_per_day_usd is None else float(args.gate_max_risk_per_day_usd)),\n'
    )
    txt4 = re.sub(pat_kw, repl, txt3, count=1)

    backup(root, f, bdir)
    write(f, txt4)
    info("Patched tbot/main.py")
    return True

def patch_gate_state_py(root: Path, bdir: Path) -> bool:
    f = root / "tbot" / "runtime" / "gate_state.py"
    if not f.exists():
        die("Missing tbot/runtime/gate_state.py")

    txt = read(f)
    if MARK in txt:
        info("gate_state.py already patched.")
        return False

    # Replace the block that mutates args.gate_max_risk_usd based on accepted_risk_usd.
    # Current lines (from your rg):
    # if hasattr(args, "gate_max_risk_usd") and st.accepted_risk_usd > 0:
    #   orig_r = float(getattr(args, "gate_max_risk_usd"))
    #   rem_r = max(0.0, orig_r - float(st.accepted_risk_usd))
    #   setattr(args, "gate_max_risk_usd", rem_r)
    #   print(...)
    pat = (
        r'(\n\s*if\s+hasattr\(args,\s*"gate_max_risk_usd"\)\s+and\s+st\.accepted_risk_usd\s*>\s*0\s*:\s*\n'
        r'(?:\s+.*\n){1,10}?)'
    )
    m = re.search(pat, txt)
    if not m:
        die("Could not locate the persisted risk adjustment block in gate_state.py (pattern mismatch).")

    new_block = (
        f'\n    # {MARK}\n'
        '    # IMPORTANT: gate_max_risk_usd is a per-trade cap (legacy). Do NOT mutate it across restarts.\n'
        '    # If a daily budget is configured, we may compute an effective remaining daily budget.\n'
        '    if hasattr(args, "gate_max_risk_per_day_usd") and getattr(args, "gate_max_risk_per_day_usd") is not None and st.accepted_risk_usd > 0:\n'
        '        try:\n'
        '            orig_day = float(getattr(args, "gate_max_risk_per_day_usd"))\n'
        '            rem_day = max(0.0, orig_day - float(st.accepted_risk_usd))\n'
        '            setattr(args, "gate_max_risk_per_day_usd", rem_day)\n'
        '            print(f"[PERSIST_CAP] risk_used={st.accepted_risk_usd:.2f} orig_day_budget={orig_day:.2f} effective_day_budget={rem_day:.2f}")\n'
        '        except Exception:\n'
        '            pass\n'
    )

    txt2 = re.sub(pat, new_block, txt, count=1)

    backup(root, f, bdir)
    write(f, txt2)
    info("Patched tbot/runtime/gate_state.py")
    return True

def patch_shadow_gate_py(root: Path, bdir: Path) -> bool:
    f = root / "tbot" / "runtime" / "shadow_gate.py"
    if not f.exists():
        die("Missing tbot/runtime/shadow_gate.py")

    txt = read(f)
    if MARK in txt:
        info("shadow_gate.py already patched.")
        return False

    # 1) Extend reasons list constants at top: add new reason keys near existing
    # existing:
    # "risk_above_max",
    # "daily_plan_cap_reached",
    if '"risk_above_max_trade"' not in txt:
        txt = txt.replace('"risk_above_max",', '"risk_above_max",\n    "risk_above_max_trade",\n    "daily_risk_budget_reached",')

    # 2) Config: add fields to cfg class/struct. We look for "max_risk_usd: float"
    txt2, n1 = re.subn(
        r'(max_risk_usd\s*:\s*float\s*=\s*[0-9\.]+\s*\n)',
        r'\1    # ' + MARK + r'\n    max_risk_per_trade_usd: float = 999999.0\n    max_risk_per_day_usd: float | None = None\n',
        txt,
        count=1
    )
    if n1 == 0:
        die("Could not find max_risk_usd field to extend in shadow_gate.py (pattern mismatch).")

    # 3) Enforce checks: locate existing per-trade check:
    # if risk is not None and risk > float(self.cfg.max_risk_usd): reasons.append("risk_above_max")
    # We'll replace with 2 checks.
    pat_check = r'(\s*if\s+risk\s+is\s+not\s+None\s+and\s+risk\s*>\s*float\(self\.cfg\.max_risk_usd\)\s*:\s*\n\s*reasons\.append\("risk_above_max"\)\s*\n)'
    m = re.search(pat_check, txt2)
    if not m:
        die("Could not locate per-trade risk check in shadow_gate.py to replace (pattern mismatch).")

    repl = (
        f'        # {MARK}\n'
        '        # Per-trade cap (legacy max_risk_usd still supported, but prefer max_risk_per_trade_usd)\n'
        '        max_trade = float(getattr(self.cfg, "max_risk_per_trade_usd", None) or getattr(self.cfg, "max_risk_usd", 0.0))\n'
        '        if risk is not None and risk > max_trade:\n'
        '            reasons.append("risk_above_max_trade")\n'
        '            # Keep legacy reason too for compatibility with existing dashboards\n'
        '            reasons.append("risk_above_max")\n'
        '        # Daily budget (cumulative)\n'
        '        max_day = getattr(self.cfg, "max_risk_per_day_usd", None)\n'
        '        if (risk is not None) and (max_day is not None):\n'
        '            try:\n'
        '                used = float(getattr(self, "_risk_today", 0.0))\n'
        '                if used + float(risk) > float(max_day):\n'
        '                    reasons.append("daily_risk_budget_reached")\n'
        '            except Exception:\n'
        '                pass\n'
    )

    txt3 = re.sub(pat_check, repl, txt2, count=1)

    backup(root, f, bdir)
    write(f, txt3)
    info("Patched tbot/runtime/shadow_gate.py")
    return True

def patch_orchestrator_py(root: Path, bdir: Path) -> bool:
    f = root / "tbot" / "runtime" / "orchestrator.py"
    if not f.exists():
        die("Missing tbot/runtime/orchestrator.py")

    txt = read(f)
    if MARK in txt:
        info("orchestrator.py already patched.")
        return False

    # 1) Extend function signature that includes gate_max_risk_usd: float = 500.0,
    # Add two new kwargs right after it.
    sig_pat = r'(gate_max_risk_usd\s*:\s*float\s*=\s*[0-9\.]+\s*,\s*\n)'
    if not re.search(sig_pat, txt):
        die("Could not find gate_max_risk_usd: float = ... in orchestrator.py signature (pattern mismatch).")

    txt2 = re.sub(
        sig_pat,
        r'\1    # ' + MARK + r'\n    gate_max_risk_per_trade_usd: float | None = None,\n    gate_max_risk_per_day_usd: float | None = None,\n',
        txt,
        count=1
    )

    # 2) Wherever it sets config "max_risk_usd": gate_max_risk_usd, add new keys
    # Example from your grep: "max_risk_usd": gate_max_risk_usd,
    cfg_pat = r'("max_risk_usd"\s*:\s*gate_max_risk_usd\s*,\s*\n)'
    if not re.search(cfg_pat, txt2):
        die('Could not find config entry "max_risk_usd": gate_max_risk_usd, in orchestrator.py (pattern mismatch).')

    repl = (
        '"max_risk_usd": gate_max_risk_usd,\n'
        f'                # {MARK}\n'
        '                "max_risk_per_trade_usd": (gate_max_risk_per_trade_usd if gate_max_risk_per_trade_usd is not None else gate_max_risk_usd),\n'
        '                "max_risk_per_day_usd": gate_max_risk_per_day_usd,\n'
    )
    txt3 = re.sub(cfg_pat, repl, txt2, count=1)

    backup(root, f, bdir)
    write(f, txt3)
    info("Patched tbot/runtime/orchestrator.py")
    return True

def main() -> None:
    root = root_from_cwd()
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    bdir = root / "logs" / "ops" / "patches" / f"P0_2_{ts}"
    bdir.mkdir(parents=True, exist_ok=True)

    changed = 0
    if patch_main_py(root, bdir): changed += 1
    if patch_gate_state_py(root, bdir): changed += 1
    if patch_shadow_gate_py(root, bdir): changed += 1
    if patch_orchestrator_py(root, bdir): changed += 1

    if changed == 0:
        die("No changes applied (everything already patched or patterns mismatched).")

    info(f"Done. Backups in: {bdir.relative_to(root)}")
    info("Verify with:")
    info('  rg -n "' + MARK + '|gate_max_risk_per_trade_usd|gate_max_risk_per_day_usd|daily_risk_budget_reached|risk_above_max_trade" -S tbot')
    info("Paper-test run example:")
    info("  python -m tbot.main --paper --gate_max_risk_per_trade_usd 250 --gate_max_risk_per_day_usd 1000")

if __name__ == "__main__":
    main()
