import argparse, json, os, glob
from statistics import mean

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--runroot", required=True)
    ap.add_argument("--weeksuffix", required=True)
    args=ap.parse_args()

    out_dir=os.path.join(args.runroot,"logs","analytics")
    files=sorted(glob.glob(os.path.join(out_dir,"KPI_*.json")))[-20:]
    kpis=[]
    for p in files:
        try:
            with open(p,"r",encoding="utf-8") as f: kpis.append(json.load(f))
        except Exception: pass

    md=os.path.join(out_dir,f"WEEKLY_REVIEW_{args.weeksuffix}.md")
    with open(md,"w",encoding="utf-8") as f:
        f.write(f"# Weekly Review {args.weeksuffix}\n\n")
        f.write(f"- KPI files considered: {len(kpis)}\n\n")
        if not kpis:
            f.write("No KPI data.\n"); return
        pf=[k.get("expected_profit_factor") for k in kpis if k.get("expected_profit_factor") is not None]
        pnl=[k.get("expected_pnl_net",0.0) for k in kpis]
        f.write(f"- Avg expected PF: {mean(pf) if pf else None}\n")
        f.write(f"- Sum expected pnl net: {sum(pnl):.2f}\n")
        f.write("\n## Actions\n")
        f.write("- If PF<1 => reduce risk/pause\n")
        f.write("- If QC FAIL days exist => investigate ops/data\n")

if __name__=="__main__":
    main()
