import argparse, os, json, math

def read_jsonl(path):
    out=[]
    if not path or not os.path.exists(path):
        return out
    with open(path,"r",encoding="utf-8",errors="replace") as f:
        for ln in f:
            ln=ln.strip()
            if not ln:
                continue
            try:
                out.append(json.loads(ln))
            except Exception:
                continue
    return out

def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path,"w",encoding="utf-8") as f:
        json.dump(obj,f,ensure_ascii=False,indent=2)

def write_md(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path,"w",encoding="utf-8") as f:
        f.write("\n".join(lines).rstrip()+"\n")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--backupdir", required=True)
    ap.add_argument("--runroot", required=True)
    ap.add_argument("--ymd", required=True)
    args=ap.parse_args()

    ymd=args.ymd
    bk=args.backupdir
    runroot=args.runroot
    ana=os.path.join(runroot,"logs","analytics")
    os.makedirs(ana, exist_ok=True)

    sp=os.path.join(bk, f"shadow_plans_FULL_{ymd}.jsonl")

    items=[]
    for o in read_jsonl(sp):
        sym=o.get("symbol") or o.get("sym")
        rr=o.get("rr") or o.get("RR") or o.get("risk_reward")
        conf=o.get("conf") or o.get("confidence")
        try:
            rr=float(rr); conf=float(conf)
        except Exception:
            continue
        items.append({"symbol":sym,"rr":rr,"conf":conf,"score":rr*conf})

    items.sort(key=lambda x:x["score"], reverse=True)
    n=len(items)
    top1 = max(1, math.ceil(n*0.01)) if n else 0
    top5 = max(1, math.ceil(n*0.05)) if n else 0

    queue = {
        "ymd": ymd,
        "candidates": n,
        "source_shadow_plans_full": sp if os.path.exists(sp) else None,
        "top200": items[:200],
        "notes": ["Top200 by score=rr*conf. Exact selection coverage needs stable plan_id telemetry."]
    }

    eff = {
        "ymd": ymd,
        "candidates": n,
        "top1_count": top1,
        "top5_count": top5,
        "top1": items[:min(50,top1)] if top1 else [],
        "top5": items[:min(50,top5)] if top5 else [],
        "notes": ["Upgrade to ID-based coverage after plan_id telemetry is added."]
    }

    md = [
        f"# TOP 1% REPORT {ymd}",
        "",
        f"- candidates: {n}",
        f"- top1_count: {top1}",
        f"- top5_count: {top5}",
        "",
        "## Top 20 by score (rr*conf)"
    ]
    if n:
        md += [f"- {x['symbol']} rr={x['rr']:.2f} conf={x['conf']:.2f} score={x['score']:.3f}" for x in items[:20]]
    else:
        md += ["- none (shadow_plans_FULL missing or no parsable rr/conf)"]

    for outdir in (bk, ana):
        write_json(os.path.join(outdir, f"OPP_QUEUE_{ymd}.json"), queue)
        write_json(os.path.join(outdir, f"SELECTION_EFF_{ymd}.json"), eff)
        write_md(os.path.join(outdir, f"TOP1P_{ymd}.md"), md)

if __name__=="__main__":
    main()
