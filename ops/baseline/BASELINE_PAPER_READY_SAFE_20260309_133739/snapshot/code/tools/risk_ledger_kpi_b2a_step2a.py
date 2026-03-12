import json
from pathlib import Path
from collections import Counter, defaultdict
from statistics import mean

ROOT = Path(r"C:\alpaca-bot\org_bot")
RUNROOT_SHADOW = Path(r"C:\alpaca-bot\org_bot_runtime\shadow")
RUNROOT_PAPER  = Path(r"C:\alpaca-bot\org_bot_runtime\paper")
OUTDIR = ROOT / "_MYGPT_UPLOAD"
OUTDIR.mkdir(parents=True, exist_ok=True)

def newest(p: Path, pattern: str):
    files = list(p.glob(pattern))
    if not files:
        return None
    files.sort(key=lambda x: x.stat().st_mtime, reverse=True)
    return files[0]

src = newest(RUNROOT_PAPER / "logs", "risk_ledger_PAPER_*.jsonl") or newest(RUNROOT_SHADOW / "logs", "risk_ledger_SHADOW_*.jsonl")
if not src:
    raise SystemExit("ERROR: No risk_ledger_*.jsonl found.")

rows = []
with src.open("r", encoding="utf-8") as f:
    for line in f:
        line=line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except Exception:
            pass

kinds = Counter(r.get("kind","<NONE>") for r in rows)

# Extract scope/day from rows (fallback: filename)
scope = None
day = None
for r in rows:
    if r.get("scope") and not scope:
        scope = r["scope"]
    if r.get("day") and not day:
        day = r["day"]
scope = scope or ("PAPER" if "PAPER" in src.name else "SHADOW")
day = day or "UNKNOWN"

# KPI: risk consume attempts
attempts = [r for r in rows if r.get("kind") == "risk_consume_attempt"]
ok_attempts = [r for r in attempts if bool(r.get("ok"))]
rej_attempts = [r for r in attempts if not bool(r.get("ok"))]

ok_rate = (len(ok_attempts) / len(attempts)) if attempts else None

cap_usd_vals = [float(r.get("cap_usd")) for r in attempts if r.get("cap_usd") is not None]
risk_vals = [float(r.get("risk_usd")) for r in attempts if r.get("risk_usd") is not None]
used_before_vals = [float(r.get("used_before_usd")) for r in attempts if r.get("used_before_usd") is not None]
rem_before_vals  = [float(r.get("remaining_before_usd")) for r in attempts if r.get("remaining_before_usd") is not None]
used_after_vals  = [float(r.get("used_after_usd")) for r in attempts if r.get("used_after_usd") is not None]
rem_after_vals   = [float(r.get("remaining_after_usd")) for r in attempts if r.get("remaining_after_usd") is not None]

# Gate snapshots
snaps = [r for r in rows if r.get("kind") == "gate_snapshot"]
cap_hit_cnt = sum(1 for r in snaps if bool(r.get("cap_hit")))
cap_hit_rate = (cap_hit_cnt / len(snaps)) if snaps else None

# Consistency checks (best-effort):
# - remaining_after = cap - used_after (within epsilon)
eps = 1e-6
consistency = {"attempt_remaining_after_matches": None}
if attempts:
    good = 0
    total = 0
    for r in attempts:
        cap = r.get("cap_usd")
        ua  = r.get("used_after_usd")
        ra  = r.get("remaining_after_usd")
        if cap is None or ua is None or ra is None:
            continue
        total += 1
        if abs((float(cap) - float(ua)) - float(ra)) <= 1e-4:
            good += 1
    consistency["attempt_remaining_after_matches"] = (good, total)

kpi = {
    "src": str(src),
    "scope": scope,
    "day": day,
    "rows": len(rows),
    "kinds_summary": dict(kinds),

    "risk_consume_attempt": {
        "count": len(attempts),
        "ok_count": len(ok_attempts),
        "reject_count": len(rej_attempts),
        "ok_rate": ok_rate,
        "cap_usd_avg": (mean(cap_usd_vals) if cap_usd_vals else None),
        "risk_usd_avg": (mean(risk_vals) if risk_vals else None),
        "used_before_avg": (mean(used_before_vals) if used_before_vals else None),
        "remaining_before_avg": (mean(rem_before_vals) if rem_before_vals else None),
        "used_after_avg": (mean(used_after_vals) if used_after_vals else None),
        "remaining_after_avg": (mean(rem_after_vals) if rem_after_vals else None),
    },

    "gate_snapshot": {
        "count": len(snaps),
        "cap_hit_count": cap_hit_cnt,
        "cap_hit_rate": cap_hit_rate,
    },

    "consistency": consistency,
}

out_txt = OUTDIR / f"RISK_LEDGER_KPI_{scope}_{day}.txt"
out_json = OUTDIR / f"RISK_LEDGER_KPI_{scope}_{day}.json"

# Write TXT
lines = []
lines.append(f"SRC={kpi['src']}")
lines.append(f"SCOPE={scope} DAY={day} ROWS={kpi['rows']}")
lines.append(f"KINDS={kpi['kinds_summary']}")
lines.append("")
lines.append("[RISK_CONSUME_ATTEMPT]")
for kk,v in kpi["risk_consume_attempt"].items():
    lines.append(f"{kk}={v}")
lines.append("")
lines.append("[GATE_SNAPSHOT]")
for kk,v in kpi["gate_snapshot"].items():
    lines.append(f"{kk}={v}")
lines.append("")
lines.append("[CONSISTENCY]")
for kk,v in kpi["consistency"].items():
    lines.append(f"{kk}={v}")

out_txt.write_text("\n".join(lines), encoding="utf-8")
out_json.write_text(json.dumps(kpi, ensure_ascii=False, indent=2), encoding="utf-8")

print("OK: KPI_TXT=", str(out_txt))
print("OK: KPI_JSON=", str(out_json))
print("OK: SCOPE=", scope, "DAY=", day, "ROWS=", len(rows))
