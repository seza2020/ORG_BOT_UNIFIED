#!/usr/bin/env python3
from __future__ import annotations
import datetime as dt
import shutil
from pathlib import Path

ROOT = Path.cwd()
MAIN = ROOT / "tbot" / "main.py"

def die(msg: str, code: int = 1) -> None:
    raise SystemExit(f"[FIX-MAIN-INDENT] ERROR: {msg}")

def main() -> None:
    if not MAIN.exists():
        die("tbot/main.py not found. Run from repo root.")

    txt = MAIN.read_text(encoding="utf-8", errors="ignore").splitlines(True)

    # lines we expect (may already be indented)
    L1 = "from tbot.runtime._shadow_observability import patch_logging_emit  # P0-1"
    L2 = "patch_logging_emit()  # P0-1"

    changed = 0
    out: list[str] = []

    for line in txt:
        s = line.rstrip("\r\n")
        if s == L1:
            # already indented? keep, else indent to be inside main()
            if line.startswith("    "):
                out.append(line)
            else:
                out.append("    " + line)
                changed += 1
            continue
        if s == L2:
            if line.startswith("    "):
                out.append(line)
            else:
                out.append("    " + line)
                changed += 1
            continue
        out.append(line)

    if changed == 0:
        print("[FIX-MAIN-INDENT] No changes needed (already indented).")
        return

    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = ROOT / "logs" / "ops" / "patches" / f"FIX_MAIN_INDENT_{ts}"
    backup_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(MAIN, backup_dir / "main.py")

    MAIN.write_text("".join(out), encoding="utf-8")
    print(f"[FIX-MAIN-INDENT] Applied. Changed lines: {changed}")
    print(f"[FIX-MAIN-INDENT] Backup: {backup_dir}")

if __name__ == "__main__":
    main()
