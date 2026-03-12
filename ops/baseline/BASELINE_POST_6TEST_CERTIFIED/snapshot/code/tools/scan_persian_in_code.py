from __future__ import annotations
from pathlib import Path
import re

ROOTS = [Path("tbot"), Path("tools")]
PY_RE = re.compile(r".*\.py$", re.IGNORECASE)

# Persian/Arabic Unicode blocks (covers Persian + Arabic letters and presentation forms)
FA_RE = re.compile(r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]")

def scan_file(p: Path):
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        print(f"[READ_FAIL] {p} :: {e}")
        return

    for i, line in enumerate(text.splitlines(), start=1):
        if FA_RE.search(line):
            # Print a compact preview
            preview = line.strip()
            if len(preview) > 220:
                preview = preview[:220] + "..."
            print(f"{p}:{i}: {preview}")

def main():
    any_hit = False
    for root in ROOTS:
        if not root.exists():
            continue
        for p in root.rglob("*.py"):
            # quick skip for venv-like folders if they exist under tools
            parts = {x.lower() for x in p.parts}
            if ".venv" in parts or "venv" in parts or "__pycache__" in parts:
                continue
            # scan
            before = any_hit
            scan_file(p)
            # If anything printed, we consider it a hit (approx)
            # (We can't easily detect prints without buffering; keep it simple.)
            any_hit = True if any_hit or before else any_hit

    print("DONE")

if __name__ == "__main__":
    main()
