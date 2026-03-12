#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path
import datetime as dt

MARK = "P0_2_GATE_STATE_NO_MUTATE_PER_TRADE"

def die(msg: str, code: int = 1):
    print(f"[P0-2-FIX] ERROR: {msg}", file=sys.stderr)
    sys.exit(code)

def info(msg: str):
    print(f"[P0-2-FIX] {msg}")

def main():
    root = Path.cwd().resolve()
    target = root / "tbot" / "runtime" / "gate_state.py"
    if not target.exists():
        die(f"Missing file: {target}")

    txt = target.read_text(encoding="utf-8", errors="ignore")

    if MARK in txt:
        info("Already patched.")
        return

    # Remove ONLY the block that mutates gate_max_risk_usd based on accepted_risk_usd.
    # We keep the per-day budget mutation (gate_max_risk_per_day_usd).
    pat = re.compile(
        r"""
(?P<block>
^[ \t]*orig_r[ \t]*=[ \t]*float\(getattr\(args,[ \t]*["']gate_max_risk_usd["']\)\)[ \t]*\r?\n
^[ \t]*rem_r[ \t]*=[ \t]*max\(0\.0,[ \t]*orig_r[ \t]*-[ \t]*float\(st\.accepted_risk_usd\)\)[ \t]*\r?\n
^[ \t]*setattr\(args,[ \t]*["']gate_max_risk_usd["'],[ \t]*rem_r\)[ \t]*\r?\n
^[ \t]*print\(f?\["']\[PERSIST_CAP\].*orig_risk_cap=.*effective_risk_cap=.*["']\)[ \t]*\r?\n
)
""",
        re.MULTILINE | re.VERBOSE,
    )

    m = pat.search(txt)
    if not m:
        # fallback: looser pattern in case formatting differs
        pat2 = re.compile(
            r"""
(?P<block>
^[ \t]*orig_r[ \t]*=[^\r\n]*gate_max_risk_usd[^\r\n]*\r?\n
^[ \t]*rem_r[ \t]*=[^\r\n]*accepted_risk_usd[^\r\n]*\r?\n
^[ \t]*setattr\([^\r\n]*gate_max_risk_usd[^\r\n]*\r?\n
^[ \t]*print\([^\r\n]*orig_risk_cap[^\r\n]*effective_risk_cap[^\r\n]*\r?\n
)
""",
            re.MULTILINE | re.VERBOSE,
        )
        m = pat2.search(txt)
        if not m:
            die("Could not locate the gate_max_risk_usd mutation block to remove (pattern mismatch).")

        txt2 = txt[:m.start("block")] + f"    # {MARK} removed per-trade cap mutation across restarts (legacy gate_max_risk_usd)\n" + txt[m.end("block"):]
    else:
        txt2 = txt[:m.start("block")] + f"    # {MARK} removed per-trade cap mutation across restarts (legacy gate_max_risk_usd)\n" + txt[m.end("block"):]

    # backup
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = root / "logs" / "ops" / "patches" / f"P0_2_FIX_{ts}"
    backup_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(target, backup_dir / "gate_state.py")

    target.write_text(txt2, encoding="utf-8")
    info(f"Backup: {backup_dir.relative_to(root)}\\gate_state.py")
    info("Applied.")
    info('Verify:')
    info('  rg -n -- "orig_risk_cap|effective_risk_cap|setattr\\(args, \\"gate_max_risk_usd\\"" tbot\\runtime\\gate_state.py')

if __name__ == "__main__":
    main()
