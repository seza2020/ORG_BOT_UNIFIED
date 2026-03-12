from __future__ import annotations
from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\policy\scorecard_policy.py")
s = P.read_text(encoding="utf-8")

TAG = "ALPHA_WARMUP_AUTO_V1"
if TAG in s:
    print("PATCH_SKIP: ALPHA_WARMUP_AUTO_V1 already present.")
    raise SystemExit(0)

# Must find the negative_expectancy branch or literal
m = re.search(r"negative_expectancy", s)
if not m:
    print("PATCH_FAIL: cannot find 'negative_expectancy' in scorecard_policy.py")
    raise SystemExit(2)

lines = s.splitlines(True)

# Find a good insertion point: a line that contains negative_expectancy in a return/decision
hit = None
for i,l in enumerate(lines):
    if "negative_expectancy" in l:
        hit = i
        break

if hit is None:
    print("PATCH_FAIL: negative_expectancy not found in lines")
    raise SystemExit(3)

# Walk up to find the indentation scope (inside a function)
# We insert a few lines BEFORE the negative_expectancy logic line.
# Determine indentation from current line.
ind = re.match(r"^(\s*)", lines[hit]).group(1)

inject = (
    f"{ind}# {TAG}: warmup gate when realized sample is insufficient\n"
    f"{ind}try:\n"
    f"{ind}    import os\n"
    f"{ind}    _min_fires = int((os.getenv('TBOT_ALPHA_MIN_FIRES','30') or '30').strip())\n"
    f"{ind}    _min_accs  = int((os.getenv('TBOT_ALPHA_MIN_ACCEPTS','10') or '10').strip())\n"
    f"{ind}except Exception:\n"
    f"{ind}    _min_fires = 30\n"
    f"{ind}    _min_accs  = 10\n"
    f"{ind}\n"
    f"{ind}try:\n"
    f"{ind}    _fires = int(getattr(sc, 'fires', 0))\n"
    f"{ind}    _accs  = int(getattr(sc, 'accepts', 0))\n"
    f"{ind}except Exception:\n"
    f"{ind}    _fires = 0\n"
    f"{ind}    _accs  = 0\n"
    f"{ind}\n"
    f"{ind}if (_fires < _min_fires) or (_accs < _min_accs):\n"
    f"{ind}    # Allow but cap while warming up\n"
    f"{ind}    return type('AlphaDecision',(object,),{{'mode':'CAP50','cap_ratio':0.5,'reason':'warmup_insufficient_sample','allow':True}})()\n"
    f"{ind}\n"
)

# Don't inject if already near the location
window = "".join(lines[max(0, hit-80):hit+20])
if TAG in window:
    print("PATCH_SKIP: warmup already near negative_expectancy")
    raise SystemExit(0)

lines.insert(hit, inject)
P.write_text("".join(lines), encoding="utf-8")
print("PATCH_OK: injected ALPHA_WARMUP_AUTO_V1 before negative_expectancy branch")
