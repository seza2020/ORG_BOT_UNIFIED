import re
from pathlib import Path

P = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
s = P.read_text(encoding="utf-8")

if "SAFE_GUARD_ENTRY_EFF_V3" in s:
    print("PATCH_SKIP: SAFE_GUARD_ENTRY_EFF_V3 already present.")
    raise SystemExit(0)

lines = s.splitlines(True)

# Find "plan = build_shadow_plan(" blocks
indices = [i for i,l in enumerate(lines) if re.match(r'^\s*\w+\s*=\s*build_shadow_plan\(\s*$', l)]
if not indices:
    # fallback: any line containing build_shadow_plan(
    indices = [i for i,l in enumerate(lines) if "build_shadow_plan(" in l]

if not indices:
    print("PATCH_FAIL: cannot find build_shadow_plan(...)")
    raise SystemExit(2)

patched = False
for call_start in indices:
    # look ahead 120 lines for default_entry=float(_entry_eff)
    look = "".join(lines[call_start:call_start+120])
    if "default_entry=float(_entry_eff)" not in look:
        continue

    # check previous 40 lines inside same area for _entry_eff assignment
    prev = "".join(lines[max(0,call_start-40):call_start])
    if re.search(r'(?m)^\s*_entry_eff\s*=\s*', prev):
        continue

    # determine indentation of call_start
    ind = re.match(r'^(\s*)', lines[call_start]).group(1)
    inject = (
        f"{ind}# SAFE_GUARD_ENTRY_EFF_V3: define effective entry/stop/tp defaults (prevents UnboundLocalError)\n"
        f"{ind}_entry_eff = float(shadow_entry)\n"
        f"{ind}_stop_eff  = float(shadow_stop)\n"
        f"{ind}_tp_eff    = float(shadow_tp)\n"
    )
    lines.insert(call_start, inject)
    patched = True
    break

if not patched:
    print("PATCH_FAIL: did not find a target call needing _entry_eff guard")
    raise SystemExit(3)

P.write_text("".join(lines), encoding="utf-8")
print("PATCH_OK: inserted SAFE_GUARD_ENTRY_EFF_V3 before build_shadow_plan(...)")
