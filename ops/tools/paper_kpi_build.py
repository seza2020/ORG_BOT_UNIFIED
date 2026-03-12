import os, json, time, csv
from collections import Counter, defaultdict

def read_json(path):
    with open(path,"r",encoding="utf-8") as f:
        return json.load(f)

def read_jsonl(path, max_lines=200000):
    out=[]
    if not os.path.exists(path):
        return out
    with open(path,"r",encoding="utf-8",errors="ignore") as f:
        for i,ln in enumerate(f):
            if i>=max_lines: break
            ln=ln.strip()
            if not ln: continue
            try:
                out.append(json.loads(ln))
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
    state_kpi=os.path.join(runroot,"state","kpi")
    os.makedirs(state_kpi, exist_ok=True)

    led=read_json(ledger_path)
    events=read_jsonl(events_path)

    commits=led.get("commits",[])
    used=float(led.get("used_risk",0.0))
    max_day=float(led.get("max_day_risk",0.0))

    # Build trades dataset from commits
    trades=[]
    for c in commits:
        trades.append({
            "ts": c.get("ts"),
            "rid": c.get("id"),
            "sid": c.get("sid"),
            "symbol": c.get("symbol"),
            "risk_usd": c.get("risk_usd"),
        })

    # Validator
    errs=[]
    if len(trades)!=len(commits):
        errs.append("TRADES_LEN_MISMATCH")
    for t in trades:
        if not t.get("rid"): errs.append("MISSING_RID")
        if not t.get("sid"): errs.append("MISSING_SID")
        if not t.get("symbol"): errs.append("MISSING_SYMBOL")
        if t.get("risk_usd") is None: errs.append("MISSING_RISK_USD")

    # Event counts
    def cnt(kind):
        return sum(1 for e in events if e.get("kind")==kind)

    by_sid=Counter([t.get("sid") for t in trades if t.get("sid")])
    by_symbol=Counter([t.get("symbol") for t in trades if t.get("symbol")])

    kpi={
        "date": str(led.get("date")),
        "max_day_risk": max_day,
        "used_risk": used,
        "commit_count": len(commits),
        "events": {
            "strategy_result": cnt("strategy_result"),
            "risk_reserve_ok": cnt("risk_reserve_ok"),
            "risk_reserve_reject": cnt("risk_reserve_reject"),
            "risk_reserve_error": cnt("risk_reserve_error"),
        },
        "by_sid_top": by_sid.most_common(10),
        "by_symbol_top": by_symbol.most_common(10),
        "validator": {
            "ok": (len(errs)==0),
            "errors": sorted(set(errs)),
        }
    }

    stamp=time.strftime("%Y%m%d_%H%M%S")
    audit=os.path.join(root,"ops","audit",f"KPI_BUILD_{stamp}")
    os.makedirs(audit, exist_ok=True)

    # write outputs
    out_json=os.path.join(state_kpi,"paper_kpi_latest.json")
    with open(out_json,"w",encoding="utf-8") as f:
        json.dump(kpi,f,ensure_ascii=False,indent=2)

    out_csv=os.path.join(state_kpi,"trades_latest.csv")
    with open(out_csv,"w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f, fieldnames=["ts","rid","sid","symbol","risk_usd"])
        w.writeheader()
        for t in trades:
            w.writerow(t)

    # audit copies
    try:
        import shutil
        shutil.copy2(ledger_path, os.path.join(audit,"risk_ledger.json"))
        shutil.copy2(events_path, os.path.join(audit,"meta_events.jsonl"))
        shutil.copy2(out_json, os.path.join(audit,"paper_kpi_latest.json"))
        shutil.copy2(out_csv, os.path.join(audit,"trades_latest.csv"))
    except Exception:
        pass

    print("KPI_OUT=", out_json)
    print("TRADES_OUT=", out_csv)
    print("AUDIT_DIR=", audit)
    print("VALIDATOR_OK=", kpi["validator"]["ok"])
    if not kpi["validator"]["ok"]:
        print("VALIDATOR_ERRORS=", kpi["validator"]["errors"])

if __name__=="__main__":
    main()
