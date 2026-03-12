import argparse, json, os
from datetime import datetime

def safe_float(x):
    try: return float(x)
    except Exception: return None

def load_jsonl(path):
    out=[]
    with open(path,"r",encoding="utf-8",errors="ignore") as f:
        for line in f:
            line=line.strip()
            if not line: continue
            try: out.append(json.loads(line))
            except Exception: pass
    return out

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--runroot", required=True)
    ap.add_argument("--isoday", required=True)  # YYYY-MM-DD
    args=ap.parse_args()

    iso=args.isoday
    ymd=iso.replace("-","")
    runroot=args.runroot

    led_dir=os.path.join(runroot,"logs","ledger")
    ana_dir=os.path.join(runroot,"logs","analytics")
    ops_dir=os.path.join(runroot,"logs","ops")
    os.makedirs(ana_dir, exist_ok=True)
    os.makedirs(ops_dir, exist_ok=True)

    ledger_real=os.path.join(led_dir,f"LEDGER_REAL_{ymd}.jsonl")

    report={
        "isoday": iso,
        "status": "WARN",
        "reason": None,
        "ledger_real_path": ledger_real,
        "counts": {},
        "orders": {
            "unique_client_ids": 0,
            "submitted": 0,
            "errors": 0,
            "dryrun_skips": 0,
            "state_updates": 0,
            "filled": 0,
            "partially_filled": 0,
            "canceled": 0,
            "rejected": 0,
        },
        "fills": {
            "filled_qty_sum": 0.0,
            "avg_fill_price_weighted": None,
        },
        "notes": "Realized KPI from LEDGER_REAL + order_state. PnL not computed unless you add exit/position ledger later."
    }

    if not os.path.exists(ledger_real):
        report["reason"]="no_ledger_real"
        write(runroot, ymd, report)
        return

    evs = load_jsonl(ledger_real)
    kinds={}
    by_cid={}
    submitted=0; errors=0; dry=0; state_updates=0

    for ev in evs:
        k=ev.get("kind","unknown")
        kinds[k]=kinds.get(k,0)+1

        cid=ev.get("client_order_id")
        if cid:
            by_cid.setdefault(cid, {"client_order_id":cid, "order_id":None, "last_status":None, "filled_qty":None, "filled_avg_price":None})
            if ev.get("order_id"): by_cid[cid]["order_id"]=ev.get("order_id")

        if k=="order_submitted":
            submitted += 1
        elif k=="order_error":
            errors += 1
        elif k=="dryrun_skip_submit":
            dry += 1
        elif k=="order_state":
            state_updates += 1
            if cid:
                by_cid[cid]["last_status"]=ev.get("status")
                by_cid[cid]["filled_qty"]=ev.get("filled_qty")
                by_cid[cid]["filled_avg_price"]=ev.get("filled_avg_price")
                if ev.get("order_id"): by_cid[cid]["order_id"]=ev.get("order_id")

    # summarize statuses
    filled=0; partial=0; canceled=0; rejected=0
    qty_sum=0.0; px_qty_sum=0.0

    for cid, row in by_cid.items():
        st=(row.get("last_status") or "").lower()
        if st=="filled": filled += 1
        elif st=="partially_filled": partial += 1
        elif st=="canceled": canceled += 1
        elif st=="rejected": rejected += 1

        q = safe_float(row.get("filled_qty"))
        p = safe_float(row.get("filled_avg_price"))
        if q is not None and q>0:
            qty_sum += q
            if p is not None:
                px_qty_sum += p*q

    report["status"]="PASS"
    report["reason"]=None
    report["counts"]=kinds
    report["orders"]["unique_client_ids"]=len(by_cid)
    report["orders"]["submitted"]=submitted
    report["orders"]["errors"]=errors
    report["orders"]["dryrun_skips"]=dry
    report["orders"]["state_updates"]=state_updates
    report["orders"]["filled"]=filled
    report["orders"]["partially_filled"]=partial
    report["orders"]["canceled"]=canceled
    report["orders"]["rejected"]=rejected
    report["fills"]["filled_qty_sum"]=qty_sum
    report["fills"]["avg_fill_price_weighted"]= (px_qty_sum/qty_sum) if qty_sum>0 else None

    write(runroot, ymd, report)

def write(runroot, ymd, report):
    ana_dir=os.path.join(runroot,"logs","analytics")
    ops_dir=os.path.join(runroot,"logs","ops")
    os.makedirs(ana_dir, exist_ok=True)
    os.makedirs(ops_dir, exist_ok=True)

    j = os.path.join(ana_dir, f"REALIZED_KPI_{ymd}.json")
    m = os.path.join(ana_dir, f"REALIZED_KPI_{ymd}.md")
    t = os.path.join(ops_dir, f"REALIZED_KPI_{ymd}.txt")

    with open(j,"w",encoding="utf-8") as f:
        json.dump(report,f,ensure_ascii=False,indent=2)

    with open(m,"w",encoding="utf-8") as f:
        f.write(f"# REALIZED KPI {report.get('isoday')}\n\n")
        f.write(f"- status: {report.get('status')}\n")
        if report.get("reason"): f.write(f"- reason: {report.get('reason')}\n")
        o=report.get("orders",{})
        f.write(f"- submitted: {o.get('submitted')}\n")
        f.write(f"- errors: {o.get('errors')}\n")
        f.write(f"- dryrun_skips: {o.get('dryrun_skips')}\n")
        f.write(f"- state_updates: {o.get('state_updates')}\n")
        f.write(f"- filled_qty_sum: {report.get('fills',{}).get('filled_qty_sum')}\n")
        f.write(f"- avg_fill_price_weighted: {report.get('fills',{}).get('avg_fill_price_weighted')}\n")

    with open(t,"w",encoding="utf-8") as f:
        f.write(f"REALIZED_KPI_STATUS={report.get('status')}\n")
        f.write(f"isoday={report.get('isoday')}\n")
        if report.get("reason"): f.write(f"reason={report.get('reason')}\n")
        o=report.get("orders",{})
        f.write(f"submitted={o.get('submitted')}\n")
        f.write(f"errors={o.get('errors')}\n")
        f.write(f"dryrun_skips={o.get('dryrun_skips')}\n")
        f.write(f"state_updates={o.get('state_updates')}\n")

if __name__=="__main__":
    main()
