from __future__ import annotations
from pathlib import Path
import re, datetime as dt

def main():
    path = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
    s = path.read_text(encoding="utf-8")

    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    bakdir = Path(r"C:\alpaca-bot\org_bot\logs\ops\patches") / f"MAIN_ENTRYPOINT_TRACE_V4_{stamp}"
    bakdir.mkdir(parents=True, exist_ok=True)
    (bakdir / "main.py").write_text(s, encoding="utf-8")

    # We patch the entrypoint() SystemExit handler to ALWAYS print diagnostics even if str(e) is empty.
    # Anchor around: except SystemExit as e:
    m = re.search(r"(?m)^\s*except\s+SystemExit\s+as\s+e\s*:\s*\n", s)
    if not m:
        raise SystemExit("ANCHOR_NOT_FOUND: except SystemExit as e")

    # Find the block lines until next 'except ' at same indent.
    start = m.start()
    # Determine indent
    line_start = s.rfind("\n", 0, m.start()) + 1
    indent = re.match(r"[ \t]*", s[line_start:m.end()]).group(0)

    # Replace the whole SystemExit block with a deterministic one (keep semantics: return int(code) else 1)
    # We'll locate the next "except KeyboardInterrupt" to bound replacement.
    m2 = re.search(r"(?m)^\s*except\s+KeyboardInterrupt\s*:\s*\n", s[m.end():])
    if not m2:
        raise SystemExit("ANCHOR_NOT_FOUND: except KeyboardInterrupt")
    block_end = m.end() + m2.start()

    replacement = (
f"{indent}except SystemExit as e:\n"
f"{indent}    import sys, os, traceback\n"
f"{indent}    # Always print, even if message is empty\n"
f"{indent}    try:\n"
f"{indent}        code = getattr(e, 'code', None)\n"
f"{indent}        print(f\"[ENTRYPOINT_SYSTEMEXIT] repr={{repr(e)}} code={{repr(code)}} str={{str(e)}}\", file=sys.stderr)\n"
f"{indent}        if os.getenv('TBOT_TRACE_SYSTEMEXIT','0') == '1':\n"
f"{indent}            traceback.print_exc()\n"
f"{indent}    except Exception:\n"
f"{indent}        pass\n"
f"{indent}    # Normalize exit code\n"
f"{indent}    code = getattr(e, 'code', 1)\n"
f"{indent}    try:\n"
f"{indent}        return int(code)\n"
f"{indent}    except Exception:\n"
f"{indent}        return 1\n"
    )

    s2 = s[:start] + replacement + s[block_end:]
    path.write_text(s2, encoding="utf-8")
    print("PATCH_OK:", str(path))
    print("BACKUP_DIR:", str(bakdir))

if __name__ == "__main__":
    main()
