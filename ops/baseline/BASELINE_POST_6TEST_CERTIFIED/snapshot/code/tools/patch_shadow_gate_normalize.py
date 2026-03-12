import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
GATE = ROOT / "tbot" / "runtime" / "shadow_gate.py"

txt = GATE.read_text(encoding="utf-8")

# ---- 1) ensure allowed reason set + normalizer exists (idempotent)
if "_normalize_reasons" not in txt:
    insert = r'''
# --- Gate reason taxonomy (enterprise-grade) ---
_ALLOWED_REASONS = {
    "rr_below_min",
    "confidence_below_min",
    "risk_above_max",
    "daily_plan_cap_reached",
    "cooldown_active",
    "alpha_kill_active",
    "portfolio_kill_active",
    "out_of_session",
    "pre_close_active",
    "unknown_reject",
}

def _normalize_reasons(reasons):
    """
    Return deterministic, unique, sorted list of reasons.
    Guarantees at least one reason for rejects.
    """
    if not reasons:
        return ["unknown_reject"]
    uniq = []
    seen = set()
    for r in reasons:
        r = str(r).strip()
        if not r:
            continue
        if r not in seen:
            uniq.append(r)
            seen.add(r)
    if not uniq:
        uniq = ["unknown_reject"]
        seen = {"unknown_reject"}

    # if any reason is not in allowlist, tag unknown_reject (but keep originals for debugging)
    if any(r not in _ALLOWED_REASONS for r in uniq):
        if "unknown_reject" not in seen:
            uniq.append("unknown_reject")

    return sorted(uniq)
'''
    # place right after imports if possible
    m = re.search(r"(?m)^(from __future__ import .*?\n)?(import .*?\n)+", txt)
    if not m:
        # fallback: prepend
        txt = insert + "\n" + txt
    else:
        pos = m.end()
        txt = txt[:pos] + insert + "\n" + txt[pos:]

# ---- 2) normalize return False, reasons patterns
# a) return False, reasons
txt = re.sub(
    r"(?m)^\s*return\s+False\s*,\s*reasons\s*$",
    "    return False, _normalize_reasons(reasons)",
    txt
)

# b) return False, \[...\]
txt = re.sub(
    r"(?m)^\s*return\s+False\s*,\s*(\[[^\]]*\])\s*$",
    r"    return False, _normalize_reasons(\1)",
    txt
)

# ---- 3) normalize success too (optional but stable)
# If file uses `return True, []` keep as is. No need.

GATE.write_text(txt, encoding="utf-8")
print("PATCHED:", GATE)
