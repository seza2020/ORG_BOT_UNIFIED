from __future__ import annotations
from pathlib import Path
import re
import datetime as dt

def main():
    path = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
    s = path.read_text(encoding="utf-8")

    bakdir = Path(r"C:\alpaca-bot\org_bot\logs\ops\patches") / ("MAIN_ENTRYPOINT_TRACE_EXCEPTIONS_V1_" + dt.datetime.now().strftime("%Y%m%d_%H%M%S"))
    bakdir.mkdir(parents=True, exist_ok=True)
    (bakdir / "main.py").write_text(s, encoding="utf-8")

    # Replace the silent except Exception block inside entrypoint()
    # Target snippet:
    #   except Exception:
    #       return 1
    pat = re.compile(r"(def\s+entrypoint\s*\(\)\s*:\s*[\s\S]*?)(\n\s*except\s+Exception\s*:\s*\n\s*return\s+1\s*)", re.M)
    m = pat.search(s)
    if not m:
        raise SystemExit("ANCHOR_NOT_FOUND: could not locate silent except Exception: return 1 in entrypoint()")

    repl = """
    except Exception as e:
        try:
            import os as _os, traceback as _tb, sys as _sys
            if (_os.getenv("TBOT_TRACE_EXCEPTIONS","0") == "1"):
                print("[ENTRYPOINT_EXCEPTION] " + repr(e), file=_sys.stderr)
                _tb.print_exc()
        except Exception:
            pass
        return 1
"""
    s2 = s[:m.start(2)] + "\n" + (" " * 4) + repl.strip("\n") + "\n" + s[m.end(2):]
    path.write_text(s2, encoding="utf-8")

    print("PATCH_OK:", str(path))
    print("BACKUP_DIR:", str(bakdir))

if __name__ == "__main__":
    main()
