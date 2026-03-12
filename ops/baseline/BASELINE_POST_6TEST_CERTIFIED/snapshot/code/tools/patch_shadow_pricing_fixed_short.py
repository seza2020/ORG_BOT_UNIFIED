# File: tools/patch_shadow_pricing_fixed_short.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\shadow_pricing.py")
s = P.read_text(encoding="utf-8")

TAG = "FIXED_MODE_SHORT_NORMALIZE_V1"
if TAG in s:
    print("PATCH_SKIP: already present.")
    raise SystemExit(0)

# We will inject normalization right before:
# if mode != "last":
#     return ShadowPrices(...)
pat = r'(?m)^\s*if mode != "last":\s*\n\s*return ShadowPrices\(entry=entry, stop=stop, tp=tp\)\s*$'
m = re.search(pat, s)
if not m:
    print("PATCH_FAIL: cannot find fixed-mode return block.")
    raise SystemExit(2)

block = m.group(0)
indent = re.match(r'^(\s*)', block).group(1)

inject = (
    f"{indent}# {TAG}: if mode=fixed, ensure stop/tp align with side\n"
    f"{indent}try:\n"
    f"{indent}    side0 = str(sig_payload.get('side', 'LONG')).upper()\n"
    f"{indent}    if side0 == 'SHORT':\n"
    f"{indent}        # Interpret defaults as LONG-template distances, then flip for SHORT\n"
    f"{indent}        # Ensure stop > entry and tp < entry\n"
    f"{indent}        if not (stop > entry and tp < entry):\n"
    f"{indent}            _stop_dist = abs(entry - stop)\n"
    f"{indent}            _tp_dist = abs(tp - entry)\n"
    f"{indent}            stop = entry + _stop_dist\n"
    f"{indent}            tp = entry - _tp_dist\n"
    f"{indent}    else:\n"
    f"{indent}        # LONG: ensure stop < entry and tp > entry (best-effort)\n"
    f"{indent}        if not (stop < entry and tp > entry):\n"
    f"{indent}            _stop_dist = abs(entry - stop)\n"
    f"{indent}            _tp_dist = abs(tp - entry)\n"
    f"{indent}            stop = entry - _stop_dist\n"
    f"{indent}            tp = entry + _tp_dist\n"
    f"{indent}except Exception:\n"
    f"{indent}    pass\n"
    f"\n"
)

s2 = s[:m.start()] + inject + s[m.start():]
P.write_text(s2, encoding="utf-8")
print("PATCH_OK: injected fixed-mode SHORT/LONG normalization in shadow_pricing.py")
