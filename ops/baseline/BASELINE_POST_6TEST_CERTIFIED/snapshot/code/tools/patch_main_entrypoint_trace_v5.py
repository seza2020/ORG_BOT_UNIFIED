from __future__ import annotations
from pathlib import Path
from datetime import datetime
import re, os

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT / "tbot" / "main.py"
s = path.read_text(encoding="utf-8")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bakdir = ROOT / "logs" / "ops" / "patches" / f"MAIN_ENTRYPOINT_TRACE_V5_{stamp}"
bakdir.mkdir(parents=True, exist_ok=True)
(bakdir / "main.py").write_text(s, encoding="utf-8")

# We patch entrypoint() except Exception block to print traceback when TBOT_TRACE_ENTRYPOINT=1
# Find the `except Exception:` block inside entrypoint() and replace its body.
pat = re.compile(r"(def\s+entrypoint\s*\(\)\s*:\s*[\s\S]*?)(\n\s*except\s+Exception\s*:\s*\n\s*return\s+1)", re.M)

m = pat.search(s)
if not m:
    raise SystemExit("ANCHOR_NOT_FOUND: could not locate entrypoint() except Exception: return 1")

head = m.group(1)
tail = s[m.end(2):]

replacement = r"""
    except Exception as e:
        # Optional deep trace for unexpected exceptions
        try:
            import os as _os
            if _os.getenv("TBOT_TRACE_ENTRYPOINT","0") == "1":
                import traceback as _tb
                import sys as _sys
                print("[ENTRYPOINT_EXCEPTION]", repr(e), file=_sys.stderr)
                _tb.print_exc()
        except Exception:
            pass
        return 1
"""

s2 = head + "\n" + replacement + tail
path.write_text(s2, encoding="utf-8")
print("PATCH_OK:", str(path))
print("BACKUP_DIR:", str(bakdir))
