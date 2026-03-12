from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]  # .../org_bot
STRATS = ROOT / "tbot" / "strategies"

SID_RE = re.compile(r'^\s*sid\s*=\s*["\']([A-Za-z0-9_]+)["\']\s*$', re.M)

KEYWORDS = re.compile(r"(Trend-Continuation|trend[_ -]?cont|bar_count|VWAP|vwap|ema_fast|ema_slow)", re.I)

def main() -> int:
    if not STRATS.exists():
        print(f"ERROR: missing strategies folder: {STRATS}")
        return 2

    rows: list[tuple[str, str]] = []
    kw_hits: list[tuple[str, int, str]] = []

    for p in sorted(STRATS.rglob("*.py")):
        text = p.read_text(encoding="utf-8", errors="replace")

        for m in SID_RE.finditer(text):
            sid = m.group(1)
            rows.append((sid, str(p.relative_to(ROOT))))

        for i, line in enumerate(text.splitlines(), start=1):
            if KEYWORDS.search(line):
                kw_hits.append((str(p.relative_to(ROOT)), i, line.strip()[:200]))

    rows.sort(key=lambda x: (x[0], x[1]))

    print("=== FOUND_SIDS ===")
    if not rows:
        print("NO_SIDS_FOUND")
    else:
        for sid, rel in rows:
            print(f"{sid}\t{rel}")

    # duplicates
    seen: dict[str, list[str]] = {}
    for sid, rel in rows:
        seen.setdefault(sid, []).append(rel)

    dups = {k: v for k, v in seen.items() if len(v) > 1}
    print("\n=== DUPLICATE_SIDS ===")
    if not dups:
        print("NONE")
    else:
        for sid, files in sorted(dups.items()):
            print(sid)
            for f in files:
                print(f"  - {f}")

    print("\n=== KEYWORD_HITS (core-related) ===")
    if not kw_hits:
        print("NONE")
    else:
        for rel, ln, preview in kw_hits[:120]:
            print(f"{rel}:{ln}: {preview}")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
