import os, json, time, glob

def read_json(path):
    with open(path,"r",encoding="utf-8") as f:
        return json.load(f)

def main():
    root=os.environ.get("TBOT_ROOT","")
    runroot=os.environ.get("TBOT_RUNROOT","")
    if not root or not runroot:
        raise SystemExit("MISSING_ENV: TBOT_ROOT/TBOT_RUNROOT")

    risk_state=os.path.join(runroot,"state","risk")
    kpi_state=os.path.join(runroot,"state","kpi")

    sums=sorted(glob.glob(os.path.join(risk_state,"daily_summary_*.json")))
    if not sums:
        raise SystemExit("NO_DAILY_SUMMARIES")

    # take last 14
    sums=sums[-14:]

    kpi_path=os.path.join(kpi_state,"paper_kpi_latest.json")
    kpi=read_json(kpi_path) if os.path.exists(kpi_path) else {"validator":{"ok":False,"errors":["KPI_MISSING"]}}

    hard_fail=False
    reasons=[]
    fail_days=[]
    max_used=0.0
    reserve_error_days=0

    for p in sums:
        s=read_json(p)
        d=str(s.get("date"))
        used=float(s.get("used_risk",0.0))
        max_used=max(max_used, used)

        checks=s.get("checks",{})
        if not checks.get("no_open_reservations", False):
            hard_fail=True
            fail_days.append(d)
            reasons.append("OPEN_RESERVATIONS_DAY="+d)
        if not checks.get("risk_not_exceeded", False):
            hard_fail=True
            fail_days.append(d)
            reasons.append("RISK_EXCEEDED_DAY="+d)

        ev=s.get("events",{})
        if int(ev.get("risk_reserve_error",0))>0:
            reserve_error_days += 1
            hard_fail=True
            fail_days.append(d)
            reasons.append("RISK_RESERVE_ERROR_DAY="+d)

    if not kpi.get("validator",{}).get("ok", False):
        hard_fail=True
        reasons.append("KPI_VALIDATOR_FAIL")
        reasons.extend(["KPI_ERR="+e for e in kpi.get("validator",{}).get("errors",[])])

    out={
        "stamp": time.strftime("%Y%m%d_%H%M%S"),
        "days_analyzed": len(sums),
        "hard_fail": hard_fail,
        "reasons": sorted(set(reasons)),
        "fail_days": sorted(set(fail_days)),
        "max_used_risk": max_used,
        "reserve_error_days": reserve_error_days,
        "commit_count_latest": int(kpi.get("commit_count",0)),
        "events_latest": kpi.get("events",{})
    }

    audit=os.path.join(root,"ops","audit",f"WEEKLY_GATES_{out['stamp']}")
    os.makedirs(audit, exist_ok=True)

    out_json=os.path.join(audit,"weekly_gates.json")
    with open(out_json,"w",encoding="utf-8") as f:
        json.dump(out,f,ensure_ascii=False,indent=2)

    out_txt=os.path.join(audit,"weekly_gates.txt")
    with open(out_txt,"w",encoding="utf-8") as f:
        f.write("HARD_FAIL=" + str(out["hard_fail"]) + "\n")
        for r in out["reasons"]:
            f.write(r + "\n")

    print("AUDIT_DIR=", audit)
    print("HARD_FAIL=", out["hard_fail"])
    print("REASONS_COUNT=", len(out["reasons"]))
    if out["hard_fail"]:
        print("REASONS=", out["reasons"])

if __name__=="__main__":
    main()
