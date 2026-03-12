from __future__ import annotations
import re
from pathlib import Path
from datetime import datetime

path = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
s = path.read_text(encoding="utf-8")

# Anchor: the "except Exception:" block inside entrypoint()
# We will inject traceback printing before "return 1" in that block.
anchor = r"(except Exception:\s*\n)(\s*return 1\s*)"
if not re.search(anchor, s, flags=re.M):
    raise SystemExit("PATCH_FAIL: could not find entrypoint except Exception: return 1 anchor")

bakdir = Path(r"C:\alpaca-bot\org_bot\logs\ops\patches") / ("MAIN_ENTRYPOINT_TRACE_" + datetime.now().strftime("%Y%m%d_%H%M%S"))
bakdir.mkdir(parents=True, exist_ok=True)
(bakdir / "main.py").write_text(s, encoding="utf-8")

replacement = (
    r"\1"
    "        try:\n"
    "            import traceback as _tb\n"
    "            print('[ENTRYPOINT] UNHANDLED_EXCEPTION', file=sys.stderr)\n"
    "            _tb.print_exc()\n"
    "        except Exception:\n"
    "            pass\n"
    r"\2"
)

s2 = re.sub(anchor, replacement, s, flags=re.M)
path.write_text(s2, encoding="utf-8")

print("PATCH_OK:", str(path))
print("BACKUP_DIR:", str(bakdir))
