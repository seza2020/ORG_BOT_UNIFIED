import argparse, os, json, math
from collections import Counter

def read_jsonl(p):
    out=[]
    if not p or not os.path.exists(p): return out
    with open(p,"r",encoding="utf-8",errors="replace") as f:
        for ln in f:
            ln=ln.strip()
            if not ln: continue
            try: out.append(json.loads(ln))
            except: pass
    return out

def safe_load(p):
    try:
        with open(p,"r",encoding="utf-8") as f: return json.load(f)
    except: return None

def write_json(p,obj):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p,"w",encoding="utf-8") as f: json.dump(obj,f,ensure_ascii=False,indent=2)

def write_md(p,lines):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p,"w",encoding="utf-8") as f: f.write("\n".join(lines).rstrip()+"\n")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--backupdir", required=True)
    ap.add_argument("--runroot", required=True)
    ap.add_argument("--ymd", required=True)
    args=ap.parse_args()

    ymd=args.ymd
    bk=args.backupdir
    ana=os.path.join(args.runroot,"logs","analytics")
    os.makedirs(ana, exist_ok=True)

    # Prefer shadow_plans_FULL from backup (best-effort scoring rr*conf)
    sp = os.path.join(bk, f"shadow_plans_FULL_{ymd}.jsonl")
    items=[]
    for o in read_jsonl(sp):
        sym=o.get("symbol") or o.get("sym")
        rr=o.get("rr") or o.get("RR")
        conf=o.get("conf") or o.get("confidence")
        try: rr=float(rr); conf=float(conf)
        except: continue
        score=rr*conf
        items.append({"symbol":sym,"rr":rr,"conf":conf,"score":score})

    items.sort(key=lambda x:x["score"], reverse=True)

    # selection file (if present)
    selp=os.path.join(bk, f"PLAN_SELECTION_{ymd}.json")
    sel=safe_load(selp) or {}
    sel_ids=set()
    for k in ("selected_ids","selected","ids"):
        if isinstance(sel.get(k), list):
            sel_ids=set(str(x) for x in sel[k])
            break

    # Top-1% / Top-5%
    n=len(items)
    top1=max(1, math.ceil(n*0.01)) if n else 0
    top5=max(1, math.ceil(n*0.05)) if n else 0
    top1_list=items[:top1]
    top5_list=items[:top5]

    # Note: without plan IDs, we measure coverage on count only (upgrade once telemetry adds IDs)
    rep={
        "ymd": ymd,
        "source_shadow_plans_full": sp if os.path.exists(sp) else None,
        "candidates": n,
        "top1_count": len(top1_list),
        "top5_count": len(top5_list),
        "notes":[
          "For exact 'selected coverage', add plan telemetry with stable plan_id into selection + shadow_plans_FULL."
        ],
        "top1": top1_list[:50],
        "top5": top5_list[:50],
    }

    # queue: top 200
    queue={"ymd":ymd,"top200":items[:200],"candidates":n}

    # write into backup + analytics
    for outdir in (bk, ana):
        write_json(os.path.join(outdir, f"OPP_QUEUE_{ymd}.json"), queue)
        write_json(os.path.join(outdir, f"SELECTION_EFF_{ymd}.json"), rep)
        write_md(os.path.join(outdir, f"TOP1P_{ymd}.md"), [
            f"# TOP 1% REPORT {ymd}",
            "",
            f"- candidates: {n}",
            f"- top1_count: {len(top1_list)}",
            f"- top5_count: {len(top5_list)}",
            "",
            "## Top 20 by score (rr*conf)",
            *[f"- {x['symbol']} rr={x['rr']:.2f} conf={x['conf']:.2f} score={x['score']:.3f}" for x in top1_list[:20]] or ["- none"]
        ])

if __name__=="__main__":
    main()
