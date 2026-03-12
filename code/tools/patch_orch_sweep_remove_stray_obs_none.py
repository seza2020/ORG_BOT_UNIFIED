from __future__ import annotations
from pathlib import Path
from datetime import datetime
import re

ROOT = r"C:\alpaca-bot\org_bot"
path = Path(ROOT) / "tbot" / "runtime" / "orchestrator.py"
s = path.read_text(encoding="utf-8", errors="ignore")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bakdir = Path(ROOT) / "logs" / "ops" / "patches" / f"ORCH_SWEEP_REMOVE_STRAY_OBS_NONE_{stamp}"
bakdir.mkdir(parents=True, exist_ok=True)
(bakdir / "orchestrator.py").write_text(s, encoding="utf-8")

# 1) Remove ALL OBS_REASON_NONE_V4 blocks (observability-only) anywhere in file
rx_block = re.compile(r"(?ms)^[ \t]*# --- OBS_REASON_NONE_V4 .*?^[ \t]*# --- /OBS_REASON_NONE_V4 ---\s*\n", re.MULTILINE)
s2, n_blocks = rx_block.subn("", s)

# 2) Remove dangling meta.emit(ev); announce.emit(ev) lines that are excessively indented
# (These are typically remnants from the broken insertions; keep only those at normal indent levels.)
lines = s2.splitlines(True)
out = []
n_dangling = 0

for ln in lines:
    if "meta.emit(ev); announce.emit(ev)" in ln:
        # Count leading whitespace
        leading = len(ln) - len(ln.lstrip(" \t"))
        # Heuristic: if indent >= 16 and line stands alone, treat as dangling and remove
        if leading >= 16:
            n_dangling += 1
            continue
    out.append(ln)

s3 = "".join(out)
path.write_text(s3, encoding="utf-8")

print("PATCH_OK:", str(path))
print("BACKUP_DIR:", str(bakdir))
print("REMOVED_BLOCKS:", n_blocks)
print("REMOVED_DANGLING_EMIT_LINES:", n_dangling)
