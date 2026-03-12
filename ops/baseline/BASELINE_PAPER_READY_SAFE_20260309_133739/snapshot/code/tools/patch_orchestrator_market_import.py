import io, os, re

ROOT = r"C:\alpaca-bot\org_bot"
F = os.path.join(ROOT, r"tbot\runtime\orchestrator.py")

with io.open(F, "r", encoding="utf-8") as f:
    s = f.read()

old = "from tbot.runtime.market_provider import build_market_snapshot"
new = "from tbot.market.market_provider import build_market_snapshot"

if old not in s and new not in s:
    raise SystemExit("PATCH FAILED: target import line not found (already different?)")

s2 = s.replace(old, new)

with io.open(F, "w", encoding="utf-8", newline="\n") as f:
    f.write(s2)

print("PATCHED:", F)
