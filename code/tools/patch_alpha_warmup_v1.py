from __future__ import annotations
from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\policy\scorecard_policy.py")
s = P.read_text(encoding="utf-8")

TAG = "ALPHA_WARMUP_V1"
if TAG in s:
    print("PATCH_SKIP: ALPHA_WARMUP_V1 already present.")
    raise SystemExit(0)

# We inject warmup logic inside decide_alpha(sc) before negative_expectancy checks.
# This assumes decide_alpha exists and uses AlphaScore fields fires/accepts/avg_r/pf/dd.
pat = r"def\s+decide_alpha\s*\(\s*sc\s*\)\s*:\s*[\s\S]*?\n"
m = re.search(r"def\s+decide_alpha\s*\(\s*sc\s*\)\s*:\s*\n", s)
if not m:
    print("PATCH_FAIL: cannot find decide_alpha(sc) function header.")
    raise SystemExit(2)

# Insert after function header line
lines = s.splitlines(True)
idx = None
for i, l in enumerate(lines):
    if re.match(r"^\s*def\s+decide_alpha\s*\(\s*sc\s*\)\s*:\s*$", l):
        idx = i
        break
if idx is None:
    print("PATCH_FAIL: cannot locate decide_alpha(sc) line.")
    raise SystemExit(3)

# Determine indentation inside function
indent = re.match(r"^(\s*)", lines[idx]).group(1) + "    "

inject = f"""{indent}# {TAG}: warmup gate for alpha when scorecard has insufficient realized sample
{indent}try:
{indent}    min_fires = int((__import__("os").getenv("TBOT_ALPHA_MIN_FIRES", "30") or "30").strip())
{indent}    min_accepts = int((__import__("os").getenv("TBOT_ALPHA_MIN_ACCEPTS", "10") or "10").strip())
{indent}except Exception:
{indent}    min_fires = 30
{indent}    min_accepts = 10

{indent}# If we don't have enough sample yet, allow but cap risk (exploration phase)
{indent}if int(getattr(sc, "fires", 0)) < min_fires or int(getattr(sc, "accepts", 0)) < min_accepts:
{indent}    return type("AlphaDecision",(object,),{{"mode":"CAP50","cap_ratio":0.5,"reason":"warmup_insufficient_sample","allow":True}})()

"""

# Prevent double insert inside decide_alpha
# Insert only if next ~120 lines don't already contain TAG
window = "".join(lines[idx:idx+120])
if TAG in window:
    print("PATCH_SKIP: warmup tag already inside decide_alpha.")
    raise SystemExit(0)

lines.insert(idx+1, inject)
P.write_text("".join(lines), encoding="utf-8")
print("PATCH_OK: injected ALPHA_WARMUP_V1 into scorecard_policy.py")
