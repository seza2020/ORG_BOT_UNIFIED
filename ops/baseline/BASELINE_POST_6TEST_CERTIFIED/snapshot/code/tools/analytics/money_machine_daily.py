import argparse, json, os, hashlib
from datetime import datetime

def parse_ts(s: str):
    try: return datetime.fromisoformat(s.replace("Z",""))
    except Exception: return None

def load_jsonl(path):
    out=[]
    if not os.path.exists(path): return out
    with open(path,"r",encoding="utf-8",errors="ignore") as f:
        for line in f:
            line=line.strip()
            if not line: continue
            try: out.append(json.loads(line))
            except Exception: pass
    return out

def sha256_file(path: str):
    if not os.path.exists(path): return None
    h=hashlib.sha256()
    with open(path,"rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--runroot", required=True)
    ap.add_argument("--isoday", required=True, help="YYYY-MM-DD")
    ap.add_argument("--max_plans", type=int, default=30)
    ap.add_argument("--slippage_bps", type=float, default=5.0)
    ap.add_argument("--strategy_contract", default=r"C:\alpaca-bot\org_bot\strategies\S11\strategy.yaml")
    args=ap.parse_args()

    runroot=args.runroot
    iso=args.isoday
    ymd=iso.replace("-","")
    out_dir=os.path.join(runroot,"logs","analytics")
    os.makedirs(out_dir, exist_ok=True)

    meta_path=os.path.join(runroot,"logs","meta.jsonl")
    shadow_path=os.path.join(runroot,"logs","shadow_plans.jsonl")

    meta=load_jsonl(meta_path)

    day=[]
    for ev in meta:
        ts=parse_ts(ev.get("ts",""))
        if ts and ts.date().isoformat()==iso:
            day.append(ev)

    kinds={}
    for ev in day:
        k=ev.get("kind","unknown")
        kinds[k]=kinds.get(k,0)+1

    # candidates from accept-like events (best-effort)
    cand=[]
    for ev in day:
        if ev.get("kind") in ("shadow_accept","plan_accept","accept"):
            p=ev.get("payload") or {}
            sym=p.get("sym") or p.get("symbol") or p.get("ticker")
            if not sym: 
                continue
            rr=float(p.get("rr") or p.get("RR") or 1.0)
            conf=float(p.get("conf") or p.get("confidence") or 0.0)
            risk=float(p.get("risk_usd") or p.get("risk") or 0.0)
            side=p.get("side") or p.get("dir") or "UNK"
            score=(conf*rr*100.0) - (risk/10.0)
            cand.append({"sym":sym,"side":side,"rr":rr,"conf":conf,"risk_usd":risk,"score":score})

    cand.sort(key=lambda x: x["score"], reverse=True)
    selected=cand[:max(1,args.max_plans)]

    exposure={}
    for c in selected:
        k=f'{c["sym"]}:{c["side"]}'
        exposure[k]=exposure.get(k,0.0)+float(c["risk_usd"])

    # sim-exec MVP: expectancy from conf+rr (placeholder until real fills exist)
    exp_gross=0.0
    win=0.0
    loss=0.0
    for c in selected:
        p=max(0.0,min(1.0,float(c["conf"])))
        rr=float(c["rr"])
        r=float(c["risk_usd"])
        exp_gross += r*(p*rr - (1-p)*1.0)
        win += r*p*rr
        loss += r*(1-p)*1.0
    slip = (args.slippage_bps/10000.0) * sum(float(c["risk_usd"]) for c in selected)
    exp_net = exp_gross - slip
    pf = (win/loss) if loss>0 else None

    shadow_lines=0
    if os.path.exists(shadow_path):
        with open(shadow_path,"r",encoding="utf-8",errors="ignore") as f:
            shadow_lines=sum(1 for _ in f)

    def dump(name,obj):
        with open(os.path.join(out_dir,f"{name}_{ymd}.json"),"w",encoding="utf-8") as f:
            json.dump(obj,f,ensure_ascii=False,indent=2)

    dump("PLAN_SELECTION", {"isoday":iso,"selected":selected})
    dump("EXPOSURE", {"isoday":iso,"exposure_risk_usd":exposure})
    dump("SIM_EXEC_REPORT", {"isoday":iso,"selected_n":len(selected),"slippage_bps":args.slippage_bps,"expected_pnl_net":exp_net,"expected_profit_factor":pf})
    dump("SCALING_SUGGEST", {"isoday":iso,"policy":"increase only if PF>1 and QC not FAIL","suggested_risk_multiplier":(1.1 if (pf and pf>1.1 and exp_net>0) else 1.0)})

    kpi={
        "isoday": iso,
        "strategy_contract_sha256": sha256_file(args.strategy_contract),
        "meta_events_today": len(day),
        "event_counts_today": kinds,
        "shadow_lines_total": shadow_lines,
        "selected_n": len(selected),
        "expected_profit_factor": pf,
        "expected_pnl_net": exp_net,
        "notes":"MVP KPI; next step: real fills/fees/reconciliation ledger"
    }

    with open(os.path.join(out_dir,f"KPI_{ymd}.json"),"w",encoding="utf-8") as f:
        json.dump(kpi,f,ensure_ascii=False,indent=2)
    with open(os.path.join(out_dir,f"KPI_{ymd}.md"),"w",encoding="utf-8") as f:
        f.write(f"# KPI {iso}\n\n")
        f.write(f"- Selected: {len(selected)}\n")
        f.write(f"- Expected PF: {pf}\n")
        f.write(f"- Expected PnL net: {exp_net:.2f}\n")
        f.write(f"- shadow_lines_total: {shadow_lines}\n")

if __name__=="__main__":
    main()
