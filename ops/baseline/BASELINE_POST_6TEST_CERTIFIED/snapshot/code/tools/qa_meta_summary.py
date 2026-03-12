import os, json
from datetime import datetime, date
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

TZ = ZoneInfo("America/Los_Angeles") if ZoneInfo else None

def to_pt(ts: str):
    ts = ts.strip()
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    dt = datetime.fromisoformat(ts)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=TZ) if TZ else dt
    return dt.astimezone(TZ) if TZ else dt

def today_pt():
    if TZ:
        return datetime.utcnow().replace(tzinfo=ZoneInfo("UTC")).astimezone(TZ).date()
    return datetime.now().date()

def is_fake(p):
    if not p: return False
    r = str(p.get("reason","") or "")
    if "forced_signal_test" in r: return True
    try:
        e=float(p.get("entry")); s=float(p.get("stop")); t=float(p.get("tp"))
        return abs(e-100.0)<1e-6 and abs(s-99.0)<1e-6 and abs(t-102.0)<1e-6
    except Exception:
        return False

day = os.environ.get("TBOT_QA_DAY","").strip()
day_pt = date.fromisoformat(day) if day else today_pt()

meta_path = os.path.join(os.getcwd(),"logs","meta.jsonl")
counts = dict(boot=0, shadow_plan=0, shadow_accept=0, shadow_reject=0, fake_plans=0, valid_accepts=0)
by_sid = {}
by_side = {}
reject_reasons = {}

with open(meta_path,"r",encoding="utf-8") as f:
    for line in f:
        line=line.strip()
        if not line: continue
        try: j=json.loads(line)
        except Exception: continue
        kind=j.get("kind"); ts=j.get("ts")
        if not kind or not ts: continue
        try: tpt=to_pt(str(ts))
        except Exception: continue
        if tpt.date() != day_pt: continue

        if kind in counts: counts[kind]+=1
        p=j.get("payload") or {}

        if kind=="shadow_plan" and is_fake(p):
            counts["fake_plans"] += 1

        if kind=="shadow_accept":
            if is_fake(p):
                continue
            counts["valid_accepts"] += 1
            sid = p.get("sid") or p.get("strategy") or p.get("signal_id") or p.get("name") or "UNKNOWN"
            side = p.get("side") or "UNKNOWN"
            by_sid[sid] = by_sid.get(sid,0)+1
            by_side[side] = by_side.get(side,0)+1

        if kind=="shadow_reject":
            rs = p.get("reasons") or []
            if isinstance(rs,str): rs=[rs]
            for r in rs:
                reject_reasons[r]=reject_reasons.get(r,0)+1

max_boots = int(os.environ.get("TBOT_QA_MAX_BOOTS","3"))
cap = int(os.environ.get("TBOT_QA_CAP","150"))
audit_ok = True
notes=[]
if counts["boot"] > max_boots:
    audit_ok=False; notes.append(f"boots_gt_{max_boots}")
if counts["fake_plans"] > 0:
    audit_ok=False; notes.append("fake_plans_present")
if counts["valid_accepts"] > cap:
    audit_ok=False; notes.append("valid_accepts_gt_cap")

print(f"QA_DAY={day_pt} AUDIT_OK={audit_ok} NOTES={';'.join(notes) if notes else '(none)'}")
print("META_COUNTS", counts)
print("BY_STRATEGY", dict(sorted(by_sid.items(), key=lambda kv: -kv[1])))
print("BY_SIDE", dict(sorted(by_side.items(), key=lambda kv: -kv[1])))
print("REJECT_REASONS", dict(sorted(reject_reasons.items(), key=lambda kv: -kv[1])))
