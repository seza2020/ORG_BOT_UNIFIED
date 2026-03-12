from __future__ import annotations
from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\policy\scorecard_policy.py")
s = P.read_text(encoding="utf-8")

TAG1 = "ALPHA_WARMUP_AUTO_V1"
TAG2 = "ALPHA_WARMUP_AUTO_V2"

if TAG2 in s:
    print("PATCH_SKIP: ALPHA_WARMUP_AUTO_V2 already present.")
    raise SystemExit(0)

if TAG1 not in s:
    print("PATCH_FAIL: ALPHA_WARMUP_AUTO_V1 not found; expected to upgrade V1->V2")
    raise SystemExit(2)

lines = s.splitlines(True)

# Find the V1 tag line
start = None
for i, l in enumerate(lines):
    if TAG1 in l:
        start = i
        break
if start is None:
    print("PATCH_FAIL: cannot locate V1 tag line")
    raise SystemExit(3)

# Remove V1 injected block until blank line after its return
end = None
for j in range(start, min(len(lines), start + 120)):
    if "return type('AlphaDecision'" in lines[j]:
        for k in range(j, min(len(lines), j + 40)):
            if lines[k].strip() == "":
                end = k + 1
                break
        break

if end is None:
    print("PATCH_FAIL: cannot locate end of V1 warmup block")
    raise SystemExit(4)

ind = re.match(r"^(\s*)", lines[start]).group(1)

inject = (
    f"{ind}# {TAG2}: warmup gate with cap ramp; exits to normal policy after sample is sufficient\n"
    f"{ind}try:\n"
    f"{ind}    import os\n"
    f"{ind}    _min_fires = int((os.getenv('TBOT_ALPHA_MIN_FIRES','200') or '200').strip())\n"
    f"{ind}    _min_accs  = int((os.getenv('TBOT_ALPHA_MIN_ACCEPTS','80') or '80').strip())\n"
    f"{ind}except Exception:\n"
    f"{ind}    _min_fires = 200\n"
    f"{ind}    _min_accs  = 80\n"
    f"{ind}\n"
    f"{ind}try:\n"
    f"{ind}    _fires = int(getattr(sc, 'fires', 0))\n"
    f"{ind}    _accs  = int(getattr(sc, 'accepts', 0))\n"
    f"{ind}except Exception:\n"
    f"{ind}    _fires = 0\n"
    f"{ind}    _accs  = 0\n"
    f"{ind}\n"
    f"{ind}if (_fires < _min_fires) or (_accs < _min_accs):\n"
    f"{ind}    # Ramp cap while warming up; do NOT override normal policy after thresholds are met\n"
    f"{ind}    if _fires < max(1, int(_min_fires * 0.5)):\n"
    f"{ind}        _cap_ratio = 0.10\n"
    f"{ind}        _mode = 'CAP10'\n"
    f"{ind}    else:\n"
    f"{ind}        _cap_ratio = 0.25\n"
    f"{ind}        _mode = 'CAP25'\n"
    f"{ind}    return type('AlphaDecision',(object,),{{'mode':_mode,'cap_ratio':_cap_ratio,'reason':'warmup_insufficient_sample','allow':True}})()\n"
    f"{ind}\n"
)

new_lines = lines[:start] + [inject] + lines[end:]
P.write_text("".join(new_lines), encoding="utf-8")
print("PATCH_OK: upgraded warmup to ALPHA_WARMUP_AUTO_V2 (cap ramp + exit)")
