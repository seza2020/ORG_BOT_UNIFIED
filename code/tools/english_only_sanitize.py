from __future__ import annotations
from pathlib import Path
import re

ROOTS = [Path("tbot"), Path("tools")]

# Arabic + Persian unicode ranges (broad)
FA_RE = re.compile(r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]")

# Known message -> English replacement
KNOWN_REPL = {
    "Use --smoke, --run, or --emit_test_trade to run tests.": "Use --smoke, --run, or --emit_test_trade to run tests.",
}

def sanitize_line(line: str) -> str | None:
    if not FA_RE.search(line):
        return line

    # Remove pure comment lines that contain Persian
    if line.lstrip().startswith("#"):
        return None

    # Replace known exact messages
    for k, v in KNOWN_REPL.items():
        if k in line:
            return line.replace(k, v)

    # If inside quotes, replace only the Persian substring with marker
    # (keep code structure safe)
    return FA_RE.sub("", line).replace("  ", " ").rstrip() + "\n"

def process_file(p: Path) -> int:
    try:
        src = p.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
    except Exception:
        return 0

    out = []
    hits = 0
    for ln in src:
        if FA_RE.search(ln):
            hits += 1
        new_ln = sanitize_line(ln)
        if new_ln is None:
            continue
        out.append(new_ln)

    if hits > 0:
        p.write_text("".join(out), encoding="utf-8", newline="\n")
    return hits

def main():
    total_hits = 0
    for root in ROOTS:
        if not root.exists():
            continue
        for p in root.rglob("*.py"):
            parts = {x.lower() for x in p.parts}
            if "__pycache__" in parts or ".venv" in parts or "venv" in parts:
                continue
            total_hits += process_file(p)

    print("DONE total_hits=", total_hits)

if __name__ == "__main__":
    main()
