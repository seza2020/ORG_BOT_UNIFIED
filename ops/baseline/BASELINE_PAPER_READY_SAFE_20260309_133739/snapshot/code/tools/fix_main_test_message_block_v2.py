from __future__ import annotations

from pathlib import Path
import re
import shutil
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
MAIN = ROOT / "tbot" / "main.py"

ANCHORS = (
    "--emit_test_trade",
    "For testing use --smoke",
  " ",
)

def _leading_ws(s: str) -> str:
    return s[: len(s) - len(s.lstrip(" \t"))]

def ensure_sys_import(src: str) -> str:
    if re.search(r"(?m)^\s*import\s+sys\s*$", src):
        return src

    lines = src.splitlines(True)
    insert_at = 0

    while insert_at < len(lines):
        ln = lines[insert_at]
        if ln.startswith("#!") or "coding" in ln or ln.lstrip().startswith("#") or ln.strip() == "":
            insert_at += 1
            continue
        break

    i = insert_at
    while i < len(lines) and re.match(r"^\s*from\s+__future__\s+import\s+", lines[i]):
        i += 1
    insert_at = i

    lines.insert(insert_at, "import sys\n")
    return "".join(lines)

def main() -> int:
    if not MAIN.exists():
        print("ERROR: not found:", str(MAIN))
        return 2

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bk = MAIN.with_suffix(f".py.bak_{ts}")
    shutil.copy2(MAIN, bk)

    src = MAIN.read_text(encoding="utf-8", errors="ignore")
    src = ensure_sys_import(src)
    lines = src.splitlines(True)

    idx = None
    for i, ln in enumerate(lines):
        if any(a in ln for a in ANCHORS) and "print" in ln:
            idx = i
            break

    if idx is None:
        for i, ln in enumerate(lines):
            if ln.strip() == "try:":
                window = "".join(lines[i:i+25])
                if any(a in window for a in ANCHORS):
                    idx = i
                    break

    if idx is None:
        print("NO_CHANGES: could not locate the test-message print/try block in main.py")
        return 2

    base_ind = _leading_ws(lines[idx])

    start = idx
    if start > 0 and lines[start-1].strip() == "try:" and _leading_ws(lines[start-1]) == base_ind:
        start -= 1
        base_ind = _leading_ws(lines[start])

    end = start + 1

    except_line = None
    for j in range(start, min(len(lines), start + 60)):
        if re.match(r"^\s*except\s+UnicodeEncodeError\s*:\s*$", lines[j]) and _leading_ws(lines[j]) == base_ind:
            except_line = j
            break

    if except_line is not None:
        end = except_line + 1
        while end < len(lines):
            ln = lines[end]
            if ln.strip() == "":
                end += 1
                continue
            ind = _leading_ws(ln)
            if len(ind) > len(base_ind):
                end += 1
                continue
            break
    else:
        end = min(len(lines), start + 8)

    msg = "For testing use --smoke or --run or --emit_test_trade."
    new_block = [
        f"{base_ind}try:\n",
        f"{base_ind}    print({msg!r})\n",
        f"{base_ind}except UnicodeEncodeError:\n",
        f"{base_ind}    sys.stdout.buffer.write({(msg + chr(10)).encode('ascii')!r})\n",
    ]

    lines[start:end] = new_block
    out = "".join(lines)
    MAIN.write_text(out, encoding="utf-8")

    print("PATCHED:", str(MAIN))
    print("BACKUP :", str(bk))
    print("REPLACED_LINES:", start, "to", end-1)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
