from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
s = P.read_text(encoding="utf-8")

TAG = "ALPHA_ADMISSION_EVENT_V1"
if TAG in s:
    print("PATCH_SKIP: already present")
    raise SystemExit(0)

# We expect a block like:
# sc = AlphaScore(...)
# dec = decide_alpha(sc)
# if not dec.allow: ... signal_skip ... continue
#
# Inject an event right after "dec = decide_alpha(sc)"

pat = r"(dec\s*=\s*decide_alpha\s*\(\s*sc\s*\)\s*\n)"
m = re.search(pat, s)
if not m:
    print("PATCH_FAIL: cannot find 'dec = decide_alpha(sc)'")
    raise SystemExit(2)

# Find indentation of that line
start = m.start(1)
line_start = s.rfind("\n", 0, start) + 1
ind = re.match(r"^(\s*)", s[line_start:]).group(1)

inject = (
    f"{ind}# {TAG}: emit alpha admission decision (debug/visibility)\n"
    f"{ind}try:\n"
    f"{ind}    ev = make_event(level=\"INFO\", kind=\"alpha_admission\", payload={{\n"
    f"{ind}        \"sid\": str(sig_payload.get(\"sid\")),\n"
    f"{ind}        \"fires\": int(getattr(sc, \"fires\", 0)),\n"
    f"{ind}        \"accepts\": int(getattr(sc, \"accepts\", 0)),\n"
    f"{ind}        \"avg_r\": float(getattr(sc, \"avg_r\", 0.0)),\n"
    f"{ind}        \"pf\": float(getattr(sc, \"pf\", 0.0)),\n"
    f"{ind}        \"dd\": float(getattr(sc, \"dd\", 0.0)),\n"
    f"{ind}        \"allow\": bool(getattr(dec, \"allow\", False)),\n"
    f"{ind}        \"cap_ratio\": float(getattr(dec, \"cap_ratio\", 0.0)),\n"
    f"{ind}        \"reason\": str(getattr(dec, \"reason\", \"\")),\n"
    f"{ind}    }})\n"
    f"{ind}    meta.emit(ev); announce.emit(ev)\n"
    f"{ind}except Exception:\n"
    f"{ind}    pass\n"
)

s = s[:m.end(1)] + inject + s[m.end(1):]
P.write_text(s, encoding="utf-8")
print("PATCH_OK: added alpha_admission event after decide_alpha(sc)")
