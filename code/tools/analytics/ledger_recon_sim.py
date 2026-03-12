import argparse, json, os
from datetime import datetime

def load_json(path):
    if not os.path.exists(path): return None
    with open(path,"r",encoding="utf-8",errors="ignore") as f:
        return json.load(f)

def safe_float(x, d=0.0):
    try: return float(x)
    except Exception: return d

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--runroot", required=True)
    ap.add_argument("--isoday", required=True, help="YYYY-MM-DD")
    ap.add_argument("--slippage_bps_default", type=float, default=5.0)
    args=ap.parse_args()

    iso=args.isoday
    ymd=iso.replace("-","")
    runroot=args.runroot

    ana_dir=os.path.join(runroot,"logs","analytics")
    led_dir=os.path.join(runroot,"logs","ledger")
    os.makedirs(led_dir, exist_ok=True)

    sel_path=os.path.join(ana_dir,f"PLAN_SELECTION_{ymd}.json")
    sim_path=os.path.join(ana_dir,f"SIM_EXEC_REPORT_{ymd}.json")
    kpi_path=os.path.join(ana_dir,f"KPI_{ymd}.json")

    sel=load_json(sel_path) or {}
    sim=load_json(sim_path) or {}
    kpi=load_json(kpi_path) or {}

    selected = sel.get("selected") or []
    selected_n = int(len(selected))

    slippage_bps = safe_float(sim.get("slippage_bps"), args.slippage_bps_default)
    exp_pf = sim.get("expected_profit_factor", None)
    exp_pnl = safe_float(sim.get("expected_pnl_net"), 0.0)

    # Build ledger (SIM)
    ledger_path=os.path.join(led_dir,f"LEDGER_SIM_{ymd}.jsonl")
    ts0=datetime.utcnow().isoformat(timespec="seconds")

    lines=[]
    lines.append({"ts":ts0,"kind":"ledger_header","isoday":iso,"mode":"SIM","slippage_bps":slippage_bps})
    for i,c in enumerate(selected):
        sym=c.get("sym")
        side=c.get("side","UNK")
        rr=safe_float(c.get("rr"), 1.0)
        conf=safe_float(c.get("conf"), 0.0)
        risk=safe_float(c.get("risk_usd"), 0.0)
        score=safe_float(c.get("score"), 0.0)
        # Expected pnl per trade (very rough)
        p=max(0.0,min(1.0,conf))
        exp = risk*(p*rr - (1-p)*1.0)
        lines.append({
            "ts":ts0,
            "kind":"sim_trade",
            "isoday":iso,
            "idx":i,
            "sym":sym,
            "side":side,
            "rr":rr,
            "conf":conf,
            "risk_usd":risk,
            "score":score,
            "expected_pnl_gross":exp
        })

    with open(ledger_path,"w",encoding="utf-8") as f:
        for x in lines:
            f.write(json.dumps(x,ensure_ascii=False)+"\n")

    # Recon (SIM)
    recon_path=os.path.join(led_dir,f"RECON_SIM_{ymd}.json")
    meta_events_today = int(kpi.get("meta_events_today", 0) or 0)

    status="PASS"
    notes=[]
    if selected_n==0:
        status="WARN"
        notes.append("No selected plans (likely out_of_session or no accept events).")
    if meta_events_today==0:
        status="WARN" if status!="FAIL" else status
        notes.append("meta_events_today=0 (check meta ingestion).")

    # Hard fail if required inputs missing entirely
    missing=[]
    if not os.path.exists(kpi_path): missing.append(f"MISSING:{kpi_path}")
    if not os.path.exists(sim_path): missing.append(f"MISSING:{sim_path}")
    if not os.path.exists(sel_path): missing.append(f"MISSING:{sel_path}")
    if missing:
        status="FAIL"
        notes.extend(missing)

    recon={
        "isoday": iso,
        "status": status,
        "selected_n": selected_n,
        "meta_events_today": meta_events_today,
        "expected_pf": exp_pf,
        "expected_pnl_net": exp_pnl,
        "ledger_path": ledger_path,
        "notes": notes
    }
    with open(recon_path,"w",encoding="utf-8") as f:
        json.dump(recon,f,ensure_ascii=False,indent=2)

    print(recon_path)

if __name__=="__main__":
    main()
