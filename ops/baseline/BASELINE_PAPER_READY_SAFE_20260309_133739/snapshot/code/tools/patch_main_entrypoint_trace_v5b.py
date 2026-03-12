from __future__ import annotations
from pathlib import Path
from datetime import datetime
import re

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT / "tbot" / "main.py"
s = path.read_text(encoding="utf-8")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bakdir = ROOT / "logs" / "ops" / "patches" / f"MAIN_ENTRYPOINT_TRACE_V5B_{stamp}"
bakdir.mkdir(parents=True, exist_ok=True)
(bakdir / "main.py").write_text(s, encoding="utf-8")

# Find entrypoint() block boundaries (best-effort):
m_def = re.search(r"(?m)^def\s+entrypoint\s*\(\)\s*:\s*$", s)
if not m_def:
    raise SystemExit("ANCHOR_NOT_FOUND: def entrypoint()")

# entrypoint ends at next top-level def or if __name__ guard
m_end = re.search(r"(?m)^(def\s+|\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:)", s[m_def.end():])
end_idx = (m_def.end() + m_end.start()) if m_end else len(s)

blk = s[m_def.start():end_idx]

# Replace "except Exception: <...> return 1" where the return 1 is directly under that except
pat = re.compile(r"(?m)^(?P<ind>\s*)except\s+Exception\s*:\s*\n(?P=ind)\s*return\s+1\s*$")
m = pat.search(blk)
if not m:
    raise SystemExit("ANCHOR_NOT_FOUND: except Exception: return 1 inside entrypoint()")

ind = m.group("ind")
replacement = (
    f"{ind}except Exception as e:\n"
    f"{ind}    # Optional deep trace for unexpected exceptions\n"
    f"{ind}    try:\n"
    f"{ind}        import os as _os\n"
    f"{ind}        if _os.getenv('TBOT_TRACE_ENTRYPOINT','0') == '1':\n"
    f"{ind}            import traceback as _tb\n"
    f"{ind}            import sys as _sys\n"
    f"{ind}            print('[ENTRYPOINT_EXCEPTION]', repr(e), file=_sys.stderr)\n"
    f"{ind}            _tb.print_exc()\n"
    f"{ind}    except Exception:\n"
    f"{ind}        pass\n"
    f"{ind}    return 1"
)

blk2 = blk[:m.start()] + replacement + blk[m.end():]
s2 = s[:m_def.start()] + blk2 + s[end_idx:]

path.write_text(s2, encoding="utf-8")
print("PATCH_OK:", str(path))
print("BACKUP_DIR:", str(bakdir))
