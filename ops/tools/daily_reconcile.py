import os, json, time

def read_json(path):
    with open(path,"r",encoding="utf-8") as f:
        return json.load(f)

def safe_tail_jsonl(path, max_lines=20000):
    # read last N lines best-effort
    if not os.path.exists(path):
        return []
    with open(path,"rb") as f:
        f.seek(0,2)
        size=f.tell()
        step=4096
        buf=b""
        pos=size
        lines=[]
        while pos>0 and len(lines)<max_lines:
            pos=max(0,pos-step)
            f.seek(pos)
            buf=f.read(size-pos)+buf
            lines=buf.splitlines()
            size=pos
        # parse
    out=[]
    for ln in lines[-max_lines:]:
        try:
            obj=json.loads(ln.decode("utf-8","ignore"))
            out.append(obj)
        except Exception:
            pass
    return out

def main():
    root=os.environ.get("TBOT_ROOT","")
    runroot=os.environ.get("TBOT_RUNROOT","")
    if not root or not runroot:
        raise SystemExit("MISSING_ENV: TBOT_ROOT/TBOT_RUNROOT")

    ledger_path=os.path.join(runroot,"state","risk","risk_ledger.json")
    events_path=os.path.join(runroot,"logs","meta_events.jsonl")

    led=read_json(ledger_path)
    events=safe_tail_jsonl(events_path, max_lines=50000)

    day=str(led.get("date"))
    used=float(led.get("used_risk",0.0))
    reserved=float(led.get("reserved_risk",0.0))
    max_day=float(led.get("max_day_risk",0.0))
    commits=len(led.get("commits",[]))
    res_count=len(led.get("reservations",{}))

    # event counts
    def cnt(kind):
        return sum(1 for e in events if e.get("kind")==kind)

    summary={
        "date": day,
        "max_day_risk": max_day,
        "used_risk": used,
        "reserved_risk": reserved,
        "commit_count": commits,
        "open_reservations": res_count,
        "events": {
            "strategy_result": cnt("strategy_result"),
            "signal_eval": cnt("signal_eval"),
            "risk_reserve_ok": cnt("risk_reserve_ok"),
            "risk_reserve_reject": cnt("risk_reserve_reject"),
            "risk_reserve_error": cnt("risk_reserve_error"),
            "risk_charge_error": cnt("risk_charge_error"),
            "shutdown": cnt("shutdown"),
            "boot": cnt("boot"),
        },
        "checks": {
            "no_open_reservations": (res_count==0),
            "risk_not_exceeded": (used<=max_day+1e-9),
        }
    }

    out_dir=os.path.join(runroot,"state","risk")
    os.makedirs(out_dir, exist_ok=True)
    out_path=os.path.join(out_dir, f"daily_summary_{day}.json")
    with open(out_path,"w",encoding="utf-8") as f:
        json.dump(summary,f,ensure_ascii=False,indent=2)

    # audit bundle
    stamp=time.strftime("%Y%m%d_%H%M%S")
    audit=os.path.join(root,"ops","audit",f"DAILY_RECON_{stamp}")
    os.makedirs(audit, exist_ok=True)
    # copy ledger/events snapshots
    try:
        import shutil
        shutil.copy2(ledger_path, os.path.join(audit,"risk_ledger.json"))
    except Exception:
        pass
    try:
        import shutil
        shutil.copy2(events_path, os.path.join(audit,"meta_events.jsonl"))
    except Exception:
        pass
    with open(os.path.join(audit,"daily_summary.json"),"w",encoding="utf-8") as f:
        json.dump(summary,f,ensure_ascii=False,indent=2)

    print("DAILY_SUMMARY_OUT=", out_path)
    print("AUDIT_DIR=", audit)
    print("CHECK_no_open_reservations=", summary["checks"]["no_open_reservations"])
    print("CHECK_risk_not_exceeded=", summary["checks"]["risk_not_exceeded"])

if __name__=="__main__":
    main()
