import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
GATE = ROOT / "tbot" / "runtime" / "shadow_gate.py"
txt = GATE.read_text(encoding="utf-8")

# 1) Find & remove our injected block (if present anywhere)
block_pat = re.compile(
    r"\n?# --- Gate reason taxonomy \(enterprise-grade\) ---\n"
    r"_ALLOWED_REASONS\s*=\s*\{.*?\}\n\n"
    r"def _normalize_reasons\(reasons\):.*?\n\s*return\s+sorted\(uniq\)\n",
    re.S
)
m = block_pat.search(txt)
block = None
if m:
    block = m.group(0)
    txt = txt[:m.start()] + "\n" + txt[m.end():]

# 2) Ensure future import exists and is at top area
future_pat = re.compile(r"(?m)^\s*from __future__ import annotations\s*$")
fm = future_pat.search(txt)
if not fm:
    raise SystemExit("shadow_gate.py: missing 'from __future__ import annotations'")

# 3) Insert the block immediately AFTER the last contiguous future-import line(s)
#    (keeps docstring/comments intact, keeps future import rule valid)
lines = txt.splitlines(True)

# find index of first future import line
idxs = [i for i,l in enumerate(lines) if l.strip() == "from __future__ import annotations"]
first_idx = idxs[0]

# advance through contiguous future-import lines (if there are multiple)
j = first_idx
while j + 1 < len(lines) and lines[j+1].lstrip().startswith("from __future__ import "):
    j += 1

# prepare canonical block if it was missing (should not happen if patch ran, but safe)
if not block:
    block = (
        "\n# --- Gate reason taxonomy (enterprise-grade) ---\n"
        "_ALLOWED_REASONS = {\n"
        '    "rr_below_min",\n'
        '    "confidence_below_min",\n'
        '    "risk_above_max",\n'
        '    "daily_plan_cap_reached",\n'
        '    "cooldown_active",\n'
        '    "alpha_kill_active",\n'
        '    "portfolio_kill_active",\n'
        '    "out_of_session",\n'
        '    "pre_close_active",\n'
        '    "unknown_reject",\n'
        "}\n\n"
        "def _normalize_reasons(reasons):\n"
        '    """\n'
        "    Return deterministic, unique, sorted list of reasons.\n"
        "    Guarantees at least one reason for rejects.\n"
        '    """\n'
        "    if not reasons:\n"
        '        return ["unknown_reject"]\n'
        "    uniq = []\n"
        "    seen = set()\n"
        "    for r in reasons:\n"
        "        r = str(r).strip()\n"
        "        if not r:\n"
        "            continue\n"
        "        if r not in seen:\n"
        "            uniq.append(r)\n"
        "            seen.add(r)\n"
        "    if not uniq:\n"
        '        uniq = ["unknown_reject"]\n'
        '        seen = {"unknown_reject"}\n\n'
        "    if any(r not in _ALLOWED_REASONS for r in uniq):\n"
        '        if "unknown_reject" not in seen:\n'
        '            uniq.append("unknown_reject")\n\n'
        "    return sorted(uniq)\n"
    )

# insert after line j
insert_at = j + 1
lines.insert(insert_at, block + "\n")
new_txt = "".join(lines)

GATE.write_text(new_txt, encoding="utf-8")
print("FIXED FUTURE IMPORT ORDER:", GATE)
