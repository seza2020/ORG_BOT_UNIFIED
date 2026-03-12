#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import re
import shutil
import sys
from pathlib import Path

TS = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
BACKUP_DIR = Path("logs") / "ops" / "patches" / f"P0_2_1_{TS}"
MARK = "P0_2_1_DEDUP_AND_FALLBACK"

def die(msg: str, code: int = 1) -> None:
    print(f"[P0-2.1] ERROR: {msg}", file=sys.stderr)
    sys.exit(code)

def info(msg: str) -> None:
    print(f"[P0-2.1] {msg}")

def backup(path: Path) -> None:
    dst = BACKUP_DIR / path
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dst)

def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")

def write(path: Path, txt: str) -> None:
    path.write_text(txt, encoding="utf-8")

def patch_main_dedup() -> bool:
    path = Path("tbot") / "main.py"
    if not path.exists():
        die("Missing tbot/main.py")

    txt = read(path)
    if MARK in txt:
        info("tbot/main.py already patched (dedup).")
        return False

    # remove duplicate add_argument blocks for these two flags (keep first occurrence)
    flags = [
        '--gate_max_risk_per_trade_usd',
        '--gate_max_risk_per_day_usd',
    ]

    lines = txt.splitlines(True)

    # track first-seen per flag
    seen = {f: False for f in flags}
    out = []
    removed = 0

    i = 0
    while i < len(lines):
        ln = lines[i]

        # detect an add_argument line for one of the flags
        hit_flag = None
        for f in flags:
            if f'add_argument("{f}"' in ln:
                hit_flag = f
                break

        if not hit_flag:
            out.append(ln)
            i += 1
            continue

        # capture this add_argument block (line + possible continuation lines until we hit a line that ends with ')'
        block = [ln]
        j = i + 1
        while j < len(lines) and ")" not in lines[j]:
            block.append(lines[j])
            j += 1
        if j < len(lines):
            block.append(lines[j])
            j += 1

        if seen[hit_flag]:
            removed += 1
            # drop duplicate block
        else:
            seen[hit_flag] = True
            out.extend(block)

        i = j

    if removed == 0:
        info("No duplicate add_argument blocks detected (nothing to dedup).")
        return False

    out_txt = "".join(out)
    out_txt = out_txt.replace("# P0_2_RISK_BUDGET_SPLIT_V3", "# P0_2_RISK_BUDGET_SPLIT_V3\n    # " + MARK)

    backup(path)
    write(path, out_txt)
    info(f"Deduped main.py (removed duplicate blocks: {removed})")
    return True

def patch_orchestrator_day_fallback() -> bool:
    path = Path("tbot") / "runtime" / "orchestrator.py"
    if not path.exists():
        die("Missing tbot/runtime/orchestrator.py")

    txt = read(path)
    if MARK in txt:
        info("orchestrator.py already patched (fallback).")
        return False

    # Replace the dict field line for max_risk_per_day_usd to include fallback to gate_max_risk_usd when None.
    # We target the exact pattern shown in your rg output.
    pat = re.compile(r'(?m)^\s*"max_risk_per_day_usd"\s*:\s*gate_max_risk_per_day_usd\s*,\s*$')
    if not pat.search(txt):
        die('Could not locate `"max_risk_per_day_usd": gate_max_risk_per_day_usd,` in orchestrator.py (pattern mismatch).')

    repl = '                "max_risk_per_day_usd": (gate_max_risk_usd if gate_max_risk_per_day_usd is None else gate_max_risk_per_day_usd),  # ' + MARK + '\n'
    new = pat.sub(repl.rstrip("\n"), txt, count=1)

    backup(path)
    write(path, new)
    info("Patched orchestrator.py (day-budget fallback)")
    return True

def main() -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    changed = False
    changed |= patch_main_dedup()
    changed |= patch_orchestrator_day_fallback()
    if not changed:
        info("No edits applied.")
    info(f"Backups: {BACKUP_DIR.as_posix()}")
    info('Verify:')
    info('  rg -n "P0_2_1_DEDUP_AND_FALLBACK|max_risk_per_day_usd\\\": \\(gate_max_risk_usd|gate_max_risk_per_day_usd" -S tbot')

if __name__ == "__main__":
    main()
