import io, os, re

ROOT = r"C:\alpaca-bot\org_bot"
F = os.path.join(ROOT, r"tbot\runtime\orchestrator.py")

with io.open(F, "r", encoding="utf-8") as f:
    s = f.read()

orig = s

s = re.sub(
    r'kind\s*=\s*["\']alpha_kill_change["\'][^)]*?level\s*=\s*["\']INFO["\']\s*if\s*st\.alpha_kill\s*else\s*["\']INFO["\']',
    'kind="alpha_kill_change", level="WARN" if st.alpha_kill else "INFO"',
    s,
    flags=re.DOTALL
)

s = re.sub(
    r'level\s*=\s*["\']INFO["\']\s*if\s*st\.alpha_kill\s*else\s*["\']INFO["\'][^)]*?kind\s*=\s*["\']alpha_kill_change["\']',
    'level="WARN" if st.alpha_kill else "INFO", kind="alpha_kill_change"',
    s,
    flags=re.DOTALL
)

s = re.sub(
    r'kind\s*=\s*["\']portfolio_kill_change["\'][^)]*?level\s*=\s*["\']INFO["\']\s*if\s*st\.portfolio_kill\s*else\s*["\']INFO["\']',
    'kind="portfolio_kill_change", level="ERROR" if st.portfolio_kill else "INFO"',
    s,
    flags=re.DOTALL
)

s = re.sub(
    r'level\s*=\s*["\']INFO["\']\s*if\s*st\.portfolio_kill\s*else\s*["\']INFO["\'][^)]*?kind\s*=\s*["\']portfolio_kill_change["\']',
    'level="ERROR" if st.portfolio_kill else "INFO", kind="portfolio_kill_change"',
    s,
    flags=re.DOTALL
)

if s == orig:
    raise SystemExit("FIX FAILED: patterns not found (file already correct or format changed)")

with io.open(F, "w", encoding="utf-8", newline="\n") as f:
    f.write(s)

print("FIXED LEVELS:", F)
