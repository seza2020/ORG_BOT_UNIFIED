import re
from pathlib import Path

P = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
s = P.read_text(encoding="utf-8")

TAG = "SAFE_GUARD_ENTRY_EFF_V4"
if TAG in s:
    print("PATCH_SKIP: SAFE_GUARD_ENTRY_EFF_V4 already present.")
    raise SystemExit(0)

lines = s.splitlines(True)

# Find the first usage of default_entry=float(_entry_eff)
hit = None
for i, l in enumerate(lines):
    if "default_entry=float(_entry_eff)" in l:
        hit = i
        break

if hit is None:
    print("PATCH_FAIL: could not find default_entry=float(_entry_eff)")
    raise SystemExit(2)

# Find start of compute_shadow_prices block
call_start = None
for j in range(hit, max(-1, hit-80), -1):
    if re.search(r'^\s*prices\s*=\s*compute_shadow_prices\(\s*$', lines[j]):
        call_start = j
        break

if call_start is None:
    call_start = hit

# Skip if already defined
prev = "".join(lines[max(0, call_start-120):call_start])
if re.search(r'(?m)^\s*_entry_eff\s*=\s*', prev):
    print("PATCH_SKIP: _entry_eff assignment already exists before compute_shadow_prices.")
    raise SystemExit(0)

ind = re.match(r'^(\s*)', lines[call_start]).group(1)

inject = (
    f"{ind}# SAFE_GUARD_ENTRY_EFF_V4: define effective entry/stop/tp defaults (prevents UnboundLocalError)\n"
    f"{ind}_entry_eff = float(shadow_entry)\n"
    f"{ind}_stop_eff  = float(shadow_stop)\n"
    f"{ind}_tp_eff    = float(shadow_tp)\n"
)

lines.insert(call_start, inject)
P.write_text("".join(lines), encoding="utf-8")
print("PATCH_OK: inserted SAFE_GUARD_ENTRY_EFF_V4 before compute_shadow_prices(...)")
