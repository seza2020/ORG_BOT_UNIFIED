from __future__ import annotations
from pathlib import Path
import re
from datetime import datetime

ROOT = r"C:\alpaca-bot\org_bot"
path = Path(ROOT) / "tbot" / "runtime" / "orchestrator.py"
s = path.read_text(encoding="utf-8", errors="ignore")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bakdir = Path(ROOT) / "logs" / "ops" / "patches" / f"ORCH_FIX_KILLSWITCH_STRAY_OBS_NONE_{stamp}"
bakdir.mkdir(parents=True, exist_ok=True)
(pathlib := bakdir / "orchestrator.py").write_text(s, encoding="utf-8")

# Narrow scope: find the KILL_SWITCH_V1 block first to avoid accidental global edits
kill_idx = s.find("# KILL_SWITCH_V1")
if kill_idx < 0:
    raise SystemExit("ANCHOR_NOT_FOUND: # KILL_SWITCH_V1")

# Work in a window around it
win_start = max(0, kill_idx - 2000)
win_end   = min(len(s), kill_idx + 6000)
w = s[win_start:win_end]

# Find the stray OBS block inside kill-switch region
m = re.search(r"(?ms)^[ \t]+# --- OBS_REASON_NONE_V4 .*?^[ \t]+# --- /OBS_REASON_NONE_V4 ---\s*\n\s*\n\s*^[ \t]+meta\.emit\(ev\);\s*announce\.emit\(ev\)\s*$", w)
if not m:
    raise SystemExit("BLOCK_NOT_FOUND: OBS_REASON_NONE_V4 + meta.emit in kill-switch window")

block = w[m.start():m.end()]

# Determine correct indent from the nearest 'ev = make_event(' above the block
evm = list(re.finditer(r"(?m)^([ \t]+)ev\s*=\s*make_event\(", w[:m.start()]))
if not evm:
    raise SystemExit("EV_ANCHOR_NOT_FOUND: could not find ev = make_event(...) above stray block")
indent = evm[-1].group(1)

replacement = indent + "meta.emit(ev); announce.emit(ev)\n"

w2 = w[:m.start()] + replacement + w[m.end():]
s2 = s[:win_start] + w2 + s[win_end:]

path.write_text(s2, encoding="utf-8")
print("PATCH_OK:", str(path))
print("BACKUP_DIR:", str(bakdir))
print("USED_INDENT_REPR:", repr(indent))
