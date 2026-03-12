from __future__ import annotations

from pathlib import Path
import re
import datetime as dt

def main():
    path = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
    s = path.read_text(encoding="utf-8")

    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    bakdir = Path(r"C:\alpaca-bot\org_bot\logs\ops\patches") / f"MAIN_ENTRYPOINT_TRACE_V3_{stamp}"
    bakdir.mkdir(parents=True, exist_ok=True)
    (bakdir / "main.py").write_text(s, encoding="utf-8")

    # Find entrypoint() function block and patch the generic Exception handler.
    # We replace:
    #   except Exception:
    #       return 1
    # with:
    #   except Exception as e:
    #       import traceback
    #       print("[ENTRYPOINT_EXCEPTION]", repr(e), file=sys.stderr)
    #       traceback.print_exc()
    #       return 1

    # Anchor on "def entrypoint():" and then the "except Exception:" near it.
    m = re.search(r"def\s+entrypoint\s*\(\)\s*:\s*\n", s)
    if not m:
        raise SystemExit("ANCHOR_NOT_FOUND: entrypoint()")

    # Patch only inside entrypoint() by searching after its start
    tail = s[m.start():]
    m2 = re.search(r"\n(\s*)except\s+Exception\s*:\s*\n\1\s*return\s+1\s*\n", tail)
    if not m2:
        raise SystemExit("ANCHOR_NOT_FOUND: entrypoint except Exception: return 1")

    indent = m2.group(1)
    replacement = (
        f"\n{indent}except Exception as e:\n"
        f"{indent}    import traceback\n"
        f"{indent}    print(\"[ENTRYPOINT_EXCEPTION]\", repr(e), file=sys.stderr)\n"
        f"{indent}    traceback.print_exc()\n"
        f"{indent}    return 1\n"
    )

    tail2 = tail[:m2.start()] + replacement + tail[m2.end():]
    s2 = s[:m.start()] + tail2
    path.write_text(s2, encoding="utf-8")

    print("PATCH_OK:", str(path))
    print("BACKUP_DIR:", str(bakdir))

if __name__ == "__main__":
    main()
