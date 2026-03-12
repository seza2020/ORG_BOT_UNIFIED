#!/usr/bin/env python3
"""
P0-2.3 v2.5 - Fix budget consumption hook:
- previous hook required local var 'allow' which may not exist
- new hook consumes when len(reasons)==0 (accepted) and max_risk_per_day_usd is set

Edits tbot/runtime/shadow_gate.py (expects P0_2_3_V2_4_DAILY_BUDGET_ENFORCE exists).

Backups: logs/ops/patches/P0_2_3_V2_5_<ts>/
"""

from __future__ import annotations

import datetime as dt
import shutil
import sys
import re
from pathlib import Path

MARK_OLD = "P0_2_3_V2_4_DAILY_BUDGET_ENFORCE"
MARK = "P0_2_3_V2_5_DAILY_BUDGET_CONSUME_FIX"

def die(msg: str) -> None:
    print(f"[P0-2.3v2.5] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def info(msg: str) -> None:
    print(f"[P0-2.3v2.5] {msg}")

def repo_root() -> Path:
    p = Path.cwd().resolve()
    if (p / "tbot").is_dir():
        return p
    for parent in p.parents:
        if (parent / "tbot").is_dir():
            return parent
    die("Run from repo root (contains ./tbot).")

def backup(root: Path, f: Path) -> Path:
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = root / "logs" / "ops" / "patches" / f"P0_2_3_V2_5_{ts}" / f.relative_to(root)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, out)
    return out

def main() -> None:
    root = repo_root()
    f = root / "tbot" / "runtime" / "shadow_gate.py"
    if not f.exists():
        die("Missing tbot/runtime/shadow_gate.py")

    txt = f.read_text(encoding="utf-8", errors="ignore")

    if MARK_OLD not in txt:
        die(f"Expected {MARK_OLD} to exist in file (apply v2.4 first).")

    if MARK in txt:
        info("Already applied.")
        return

    b = backup(root, f)
    info(f"Backup: {b.relative_to(root)}")

    # Replace the v2.4 return-guard block to use len(reasons)==0 instead of local 'allow'
    # We match the block by its comment text. Keep indentation as-is.
    pattern = re.compile(
        r"(?ms)"
        r"(^[ \t]*# " + re.escape(MARK_OLD) + r"\n"
        r"^[ \t]*# Consume budget on allow=True \(best-effort\)\n"
        r"^[ \t]*try:\n"
        r"(?:^[ \t].*\n)*?"
        r"^[ \t]*except Exception:\n"
        r"^[ \t]*    pass\n)",
    )

    m = pattern.search(txt)
    if not m:
        die("Could not locate the v2.4 consume block. Paste ShadowGate.evaluate tail and I will tailor the matcher.")

    block = m.group(1)
    # Determine indentation from first line
    indent = re.match(r"^([ \t]*)#", block).group(1)

    new_block = (
        f"{indent}# {MARK_OLD}\n"
        f"{indent}# {MARK}\n"
        f"{indent}# Consume budget on ACCEPT (len(reasons)==0), regardless of local 'allow'\n"
        f"{indent}try:\n"
        f"{indent}    _day_cap2 = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
        f"{indent}    if _day_cap2 is not None:\n"
        f"{indent}        if len(reasons) == 0:\n"
        f"{indent}            self._risk_today = float(getattr(self, '_risk_today', 0.0)) + float(getattr(plan, 'risk_usd', 0.0))\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )

    txt2 = txt[:m.start()] + new_block + txt[m.end():]
    f.write_text(txt2, encoding="utf-8")
    info("Applied P0-2.3 v2.5 successfully.")
    info("Now run: python .\\tools\\p0_2_2_gate_selftest.py")

if __name__ == "__main__":
    main()
