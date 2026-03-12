from __future__ import annotations
from pathlib import Path
import re, shutil
from datetime import datetime

path = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
s = path.read_text(encoding="utf-8")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bakdir = Path(r"C:\alpaca-bot\org_bot\logs\ops\patches") / f"ORCH_TOUCH_SHADOWPATH_{stamp}"
bakdir.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bakdir / "orchestrator.py")

# anchor: inside run_loop signature area, after shadow_enabled/shadow_path args exist, before loop starts.
# We'll insert near where forced_remaining is computed (common stable anchor).
m = re.search(r"\n\s*forced_remaining\s*=\s*int\(force_signal_repeat\)\s*if\s*force_signal_sid\s*else\s*0\s*\n", s)
if not m:
    raise SystemExit("ANCHOR_NOT_FOUND: forced_remaining block not found")

insert = """
    # --- SHADOW_TOUCH_PATH_V1 (observability) ---
    try:
        if shadow_enabled and shadow_path:
            import os as _os
            _os.makedirs(_os.path.dirname(shadow_path) or ".", exist_ok=True)
            with open(shadow_path, "a", encoding="utf-8") as _f:
                _f.write("")  # touch file even if no accepts
    except Exception:
        pass
    # --- /SHADOW_TOUCH_PATH_V1 ---
"""

s2 = s[:m.end()] + insert + s[m.end():]
path.write_text(s2, encoding="utf-8")

print("PATCH_OK:", str(path))
print("BACKUP_DIR:", str(bakdir))
