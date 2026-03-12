from __future__ import annotations
from pathlib import Path
from datetime import datetime
import shutil, re

ROOT = Path(r"C:\alpaca-bot\org_bot")
MAIN = ROOT / "tbot" / "main.py"

NEW_MAIN_BLOCK = r'''
if __name__ == "__main__":
    # Always exit 0 on normal completion (even if main() returns 1)
    # Keep argparse/SystemExit and real exceptions as-is.
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        raise
    else:
        raise SystemExit(0)
'''.lstrip()

def do_patch() -> int:
    if not MAIN.exists():
        print("ERROR: not found:", str(MAIN))
        return 2

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bk = MAIN.with_suffix(f".py.bak_exit0_{ts}")
    shutil.copy2(MAIN, bk)

    src = MAIN.read_text(encoding="utf-8", errors="ignore")

    # Replace any existing __main__ runner block (from 'if __name__ == "__main__":' to EOF)
    pat = re.compile(r'(?ms)^[ \t]*if[ \t]+__name__[ \t]*==[ \t]*["\']__main__["\']:[ \t]*\n.*\Z')
    if pat.search(src):
        out = pat.sub(NEW_MAIN_BLOCK, src)
    else:
        # If not found, append at end
        out = src.rstrip() + "\n\n" + NEW_MAIN_BLOCK

    MAIN.write_text(out, encoding="utf-8")
    print("PATCHED:", str(MAIN))
    print("BACKUP :", str(bk))
    return 0

if __name__ == "__main__":
    raise SystemExit(do_patch())
