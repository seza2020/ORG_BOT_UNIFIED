import pathlib, re

P = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\shadow_gate.py")
s = P.read_text(encoding="utf-8")

# Find the GateConfig class block and ensure it includes max_qty
# We insert max_qty right after max_risk_usd (or after max_plans_per_day if max_risk_usd not found)
if "class GateConfig" not in s:
    raise SystemExit("shadow_gate.py: GateConfig class not found")

# Case A: has max_risk_usd line -> append max_qty after it
if re.search(r"^\s*max_risk_usd\s*:\s*float\s*=\s*.*$", s, flags=re.M):
    if not re.search(r"^\s*max_qty\s*:\s*int\s*=", s, flags=re.M):
        s = re.sub(
            r"(?m)^(\s*max_risk_usd\s*:\s*float\s*=\s*[0-9.]+(?:\s*)$)",
            r"\1\n    # backward-compatible (some callers pass it; gate may ignore)\n    max_qty: int = 0",
            s,
            count=1
        )
else:
    # Case B: fallback insert after max_plans_per_day
    if re.search(r"^\s*max_plans_per_day\s*:\s*int\s*=\s*.*$", s, flags=re.M) and not re.search(r"^\s*max_qty\s*:\s*int\s*=", s, flags=re.M):
        s = re.sub(
            r"(?m)^(\s*max_plans_per_day\s*:\s*int\s*=\s*\d+(?:\s*)$)",
            r"\1\n    # backward-compatible (some callers pass it; gate may ignore)\n    max_qty: int = 0",
            s,
            count=1
        )

P.write_text(s, encoding="utf-8")
print("PATCHED:", P)
