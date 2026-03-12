from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
txt = P.read_text(encoding="utf-8", errors="replace")

orig = txt

txt = re.sub(
    r'make_event\(\s*level\s*=\s*["\'](INFO|WARN|ERROR)["\']\s*,\s*kind\s*=\s*["\']alpha_kill_change["\']',
    'make_event(level="INFO", kind="alpha_kill_change"',
    txt,
    flags=re.IGNORECASE
)

txt = re.sub(
    r'make_event\(\s*level\s*=\s*["\'](INFO|WARN|ERROR)["\']\s*,\s*kind\s*=\s*["\']portfolio_kill_change["\']',
    'make_event(level="INFO", kind="portfolio_kill_change"',
    txt,
    flags=re.IGNORECASE
)

if txt == orig:
    raise SystemExit("NO_CHANGES: pattern not found (paste the exact two lines around make_event for kill_change).")

P.write_text(txt, encoding="utf-8")
print("PATCHED:", str(P))
