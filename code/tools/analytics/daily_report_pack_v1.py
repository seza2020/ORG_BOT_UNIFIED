import argparse, os, json, re, glob
from datetime import datetime
from collections import Counter, defaultdict
import ast

def _read_text(path):
    try:
        with open(path,"r",encoding="utf-8",errors="replace") as f:
            return f.read()
    except Exception:
        return ""

def _read_lines(path):
    try:
        with open(path,"r",encoding="utf-8",errors="replace") as f:
            return f.readlines()
    except Exception:
        return []

def _safe_json_load(path):
    try:
        with open(path,"r",encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def _ymd_from_iso(iso):
    return iso.replace("-","")

def _find_first(paths):
    for p in paths:
        if p and os.path.exists(p):
            return p
    return None

def _meta_candidates(runroot, ymd, backupdir):
    # Prefer imported core meta inside backupdir
    cand = []
    if backupdir:
        cand.append(os.path.join(backupdir, f"meta_{ymd}.jsonl"))
    cand.append(os.path.join(runroot,"logs","ops",f"meta_{ymd}.jsonl"))
    cand.append(os.path.join(runroot,"logs","meta.jsonl"))
    return cand

def _parse_meta(meta_path, iso):
    # Filter by date prefix in "ts" if present
    rows=[]
    if not meta_path: return rows
    for ln in _read_lines(meta_path):
        ln=ln.strip()
        if not ln: 
            continue
        try:
            o=json.loads(ln)
        except Exception:
            continue
        ts=str(o.get("ts",""))
        if ts.startswith(iso):
            rows.append(o)
        else:
            # also accept payload.now date match
            p=o.get("payload") or {}
            now=str(p.get("now",""))
            if now.startswith(iso):
                rows.append(o)
    return rows

def _parse_signal_skip_from_liveout(liveout_path):
    c=Counter()
    neg=0
    if not liveout_path: 
        return c,neg
    rx=re.compile(r"\bsignal_skip\b\s+(?P<obj>\{.*\})")
    for ln in _read_lines(liveout_path):
        if "signal_skip" not in ln:
            continue
        m=rx.search(ln)
        if not m:
            continue
        obj=m.group("obj")
        reason=None
        try:
            d=json.loads(obj)
            reason=d.get("reason")
        except Exception:
            try:
                d=ast.literal_eval(obj)
                if isinstance(d, dict):
                    reason=d.get("reason")
            except Exception:
                reason=None
        if reason:
            c[str(reason)] += 1
            if str(reason) == "negative_expectancy":
                neg += 1
    return c,neg

def _funnel_from_meta(meta_rows):
    kinds=Counter([str(r.get("kind","")) for r in meta_rows])
    skip_reason=Counter()
    neg_count=0
    for r in meta_rows:
        if str(r.get("kind","")) == "signal_skip":
            p=r.get("payload") or {}
            reason=p.get("reason")
            if reason:
                skip_reason[str(reason)] += 1
                if str(reason)=="negative_expectancy":
                    neg_count += 1
    # best-effort plan counts
    plan_created = sum(v for k,v in kinds.items() if "plan" in k and "select" not in k and "accept" not in k)
    plan_accept  = sum(v for k,v in kinds.items() if "accept" in k and "plan" in k) + kinds.get("plan_accept",0)
    return {
        "kinds": dict(kinds),
        "signal_skip_by_reason": dict(skip_reason),
        "plan_created_est": int(plan_created),
        "plan_accept_est": int(plan_accept),
        "negative_expectancy_skip_meta": int(neg_count),
    }

def _load_selection(runroot, ymd, backupdir):
    cands=[]
    if backupdir:
        cands += [
            os.path.join(backupdir, f"PLAN_SELECTION_{ymd}.json"),
            os.path.join(backupdir, f"PLAN_SELECTION_{ymd}.json".lower()),
        ]
    cands += [
        os.path.join(runroot,"logs","analytics",f"PLAN_SELECTION_{ymd}.json"),
        os.path.join(runroot,"logs","ops",f"PLAN_SELECTION_{ymd}.json"),
    ]
    p=_find_first(cands)
    j=_safe_json_load(p) if p else None
    if not j:
        return {"path": p, "selected_count": 0, "selected_ids": [], "missing": True}
    ids=[]
    for k in ("selected_ids","selected","ids"):
        if isinstance(j.get(k), list):
            ids=[str(x) for x in j.get(k)]
            break
    return {"path": p, "selected_count": len(ids), "selected_ids": ids, "missing": False}

def _load_kpi(runroot, ymd, backupdir, name):
    cands=[]
    if backupdir:
        cands.append(os.path.join(backupdir, f"{name}_{ymd}.json"))
    cands.append(os.path.join(runroot,"logs","analytics",f"{name}_{ymd}.json"))
    p=_find_first(cands)
    j=_safe_json_load(p) if p else None
    return {"path": p, "data": j, "missing": (j is None)}

def _exec_health(runroot, ymd, backupdir):
    # Prefer REAL ledger if exists, else SIM
    led_dir=os.path.join(runroot,"logs","ledger")
    real=os.path.join(led_dir,f"LEDGER_REAL_{ymd}.jsonl")
    sim =os.path.join(led_dir,f"LEDGER_SIM_{ymd}.jsonl")
    path = real if os.path.exists(real) else (sim if os.path.exists(sim) else None)
    out={"ledger_path": path, "orders": 0, "fills": 0, "rejects": 0, "missing": (path is None)}
    if not path: 
        return out
    for ln in _read_lines(path):
        ln=ln.strip()
        if not ln: 
            continue
        try:
            o=json.loads(ln)
        except Exception:
            continue
        out["orders"] += 1
        st=str(o.get("status","")).lower()
        if "fill" in st:
            out["fills"] += 1
        if "reject" in st or "canceled" in st:
            out["rejects"] += 1
    out["fill_rate"] = (out["fills"]/out["orders"]) if out["orders"] else 0.0
    out["reject_rate"] = (out["rejects"]/out["orders"]) if out["orders"] else 0.0
    return out

def _qc_extract(backupdir, ymd):
    qc_path = os.path.join(backupdir, f"QC_{ymd}.txt") if backupdir else None
    obs_path = os.path.join(backupdir, f"QC_OBS_{ymd}.txt") if backupdir else None
    return {"qc_path": qc_path if qc_path and os.path.exists(qc_path) else None,
            "qc_text": _read_text(qc_path) if qc_path and os.path.exists(qc_path) else "",
            "qc_obs_path": obs_path if obs_path and os.path.exists(obs_path) else None,
            "qc_obs_text": _read_text(obs_path) if obs_path and os.path.exists(obs_path) else ""}

def _anomaly(runroot, ymd, outdir):
    # Compare today's funnel/exec vs last few days (if exist)
    an={"ymd": ymd, "signals": {}, "notes": []}
    hist=sorted(glob.glob(os.path.join(outdir,"FUNNEL_*.json")))[-7:] if outdir and os.path.isdir(outdir) else []
    if len(hist) < 2:
        an["notes"].append("no_history_for_anomaly")
        return an
    vals=[]
    for p in hist:
        j=_safe_json_load(p) or {}
        vals.append(j.get("skip_total",0))
    if vals:
        med=sorted(vals)[len(vals)//2]
        an["signals"]["skip_total_median_7d"]=med
    return an

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
    ap.add_argument("--runroot", required=True)
    ap.add_argument("--isoday", required=True)
    ap.add_argument("--backupdir", required=True)
    ap.add_argument("--outdir", required=True)
    args=ap.parse_args()

    iso=args.isoday
    ymd=_ymd_from_iso(iso)
    runroot=args.runroot
    backupdir=args.backupdir
    outdir=args.outdir

    # Inputs
    meta_path=_find_first(_meta_candidates(runroot, ymd, backupdir))
    meta_rows=_parse_meta(meta_path, iso)
    funnel_meta=_funnel_from_meta(meta_rows)

    liveout=os.path.join(backupdir, f"LIVE_OUT_{ymd}_LATEST.txt")
    skip_live, neg_live=_parse_signal_skip_from_liveout(liveout)
    skip_total = sum(skip_live.values()) + sum(funnel_meta.get("signal_skip_by_reason",{}).values())

    selection=_load_selection(runroot, ymd, backupdir)
    kpi=_load_kpi(runroot, ymd, backupdir, "KPI")
    rkpi=_load_kpi(runroot, ymd, backupdir, "REALIZED_KPI")
    exec_h=_exec_health(runroot, ymd, backupdir)
    qc=_qc_extract(backupdir, ymd)

    # Funnel
    funnel={
      "isoday": iso,
      "ymd": ymd,
      "inputs": {"meta_path": meta_path, "liveout_path": liveout},
      "skip_total": int(skip_total),
      "skip_reasons_liveout": dict(skip_live),
      "meta": funnel_meta,
      "selection": selection,
      "exec_health": exec_h,
    }

    # Skip reasons top
    top = Counter(skip_live)
    for k,v in (funnel_meta.get("signal_skip_by_reason") or {}).items():
        top[k]+=int(v)
    top10=top.most_common(10)
    skip_rep={"isoday": iso, "ymd": ymd, "top10": top10, "all": dict(top)}

    # Alpha health
    alpha={
      "isoday": iso,
      "ymd": ymd,
      "negative_expectancy_skip_liveout": int(neg_live),
      "negative_expectancy_skip_meta": int(funnel_meta.get("negative_expectancy_skip_meta",0)),
      "expectancy_guard_present": os.path.exists(os.path.join(backupdir,f"EXPECTANCY_GUARD_{ymd}.json")),
    }

    # Missed opps (best-effort): if we have shadow_plans_FULL, pick near-threshold
    missed={"isoday": iso, "ymd": ymd, "items": [], "notes": []}
    sp = os.path.join(backupdir, f"shadow_plans_FULL_{ymd}.jsonl")
    if os.path.exists(sp):
        items=[]
        for ln in _read_lines(sp):
            try:
                o=json.loads(ln)
            except Exception:
                continue
            conf=o.get("conf") or o.get("confidence")
            rr=o.get("rr") or o.get("risk_reward") or o.get("RR")
            sym=o.get("symbol") or o.get("sym")
            if conf is None or rr is None: 
                continue
            try:
                conf=float(conf); rr=float(rr)
            except Exception:
                continue
            score=conf*rr
            items.append({"symbol": sym, "conf": conf, "rr": rr, "score": score})
        items=sorted(items,key=lambda x:x["score"], reverse=True)[:20]
        missed["items"]=items
    else:
        missed["notes"].append("shadow_plans_FULL_missing")

    # Exec health report
    exec_rep={"isoday": iso, "ymd": ymd, **exec_h}

    # Anomaly
    an=_anomaly(runroot, ymd, outdir)

    # Daily brief (1 page)
    brief=[]
    brief.append(f"# Daily Brief {iso} (ymd={ymd})")
    brief.append("")
    brief.append("## Health")
    brief.append(f"- QC file: {qc['qc_path'] or 'MISSING'}")
    brief.append(f"- OBS QC file: {qc['qc_obs_path'] or 'MISSING'}")
    if qc["qc_obs_text"]:
        m=re.search(r"OBS_QC_RESULT=(\w+)", qc["qc_obs_text"])
        if m: brief.append(f"- OBS_QC_RESULT: **{m.group(1)}**")
    brief.append("")
    brief.append("## Opportunity Funnel")
    brief.append(f"- skip_total (meta+liveout): {funnel['skip_total']}")
    brief.append(f"- selected_count: {selection['selected_count']}")
    brief.append(f"- orders: {exec_h.get('orders',0)} fills: {exec_h.get('fills',0)} rejects: {exec_h.get('rejects',0)}")
    brief.append("")
    brief.append("## Top Skip Reasons")
    for r,c in top10:
        brief.append(f"- {r}: {c}")
    brief.append("")
    brief.append("## Alpha Health")
    brief.append(f"- negative_expectancy (liveout): {alpha['negative_expectancy_skip_liveout']}")
    brief.append(f"- negative_expectancy (meta): {alpha['negative_expectancy_skip_meta']}")
    brief.append("")
    brief.append("## Actions (suggested)")
    actions=[]
    if alpha["negative_expectancy_skip_liveout"] + alpha["negative_expectancy_skip_meta"] >= 200:
        actions.append("EXPECTANCY flood: بررسی رژیم/دیتا؛ در صورت تداوم، کاهش ریسک/توقف طبق KillSwitch.")
    if exec_h.get("reject_rate",0) > 0.05:
        actions.append("RejectRate بالا: پارامترها/سایز/سشن/اتصال API را بررسی کن.")
    if not actions:
        actions.append("اگر KPI/Realized واگراست: execution/slippage/fill را بررسی کن.")
    for a in actions[:3]:
        brief.append(f"- {a}")

    # Write outputs into BOTH backupdir + outdir
    out_files = {
      f"FUNNEL_{ymd}.json": funnel,
      f"SKIP_REASONS_{ymd}.json": skip_rep,
      f"EXEC_HEALTH_{ymd}.json": exec_rep,
      f"ALPHA_HEALTH_{ymd}.json": alpha,
      f"MISSED_OPPS_{ymd}.json": missed,
      f"ANOMALY_{ymd}.json": an,
    }

    for name,obj in out_files.items():
        write_json(os.path.join(backupdir,name), obj)
        write_json(os.path.join(outdir,name), obj)

    write_md(os.path.join(backupdir,f"FUNNEL_{ymd}.md"), [f"# FUNNEL {iso}", "", f"skip_total={funnel['skip_total']}", f"selected={selection['selected_count']}", f"orders={exec_h.get('orders',0)}"])
    write_md(os.path.join(outdir,f"FUNNEL_{ymd}.md"), [f"# FUNNEL {iso}", "", f"skip_total={funnel['skip_total']}", f"selected={selection['selected_count']}", f"orders={exec_h.get('orders',0)}"])

    write_md(os.path.join(backupdir,f"SKIP_REASONS_{ymd}.md"), [f"# SKIP REASONS {iso}", ""] + [f"- {r}: {c}" for r,c in top10])
    write_md(os.path.join(outdir,f"SKIP_REASONS_{ymd}.md"), [f"# SKIP REASONS {iso}", ""] + [f"- {r}: {c}" for r,c in top10])

    write_md(os.path.join(backupdir,f"EXEC_HEALTH_{ymd}.md"), [f"# EXEC HEALTH {iso}", "", json.dumps(exec_rep, ensure_ascii=False, indent=2)])
    write_md(os.path.join(outdir,f"EXEC_HEALTH_{ymd}.md"), [f"# EXEC HEALTH {iso}", "", json.dumps(exec_rep, ensure_ascii=False, indent=2)])

    write_md(os.path.join(backupdir,f"ALPHA_HEALTH_{ymd}.md"), [f"# ALPHA HEALTH {iso}", "", json.dumps(alpha, ensure_ascii=False, indent=2)])
    write_md(os.path.join(outdir,f"ALPHA_HEALTH_{ymd}.md"), [f"# ALPHA HEALTH {iso}", "", json.dumps(alpha, ensure_ascii=False, indent=2)])

    write_md(os.path.join(backupdir,f"ANOMALY_{ymd}.md"), [f"# ANOMALY {iso}", "", json.dumps(an, ensure_ascii=False, indent=2)])
    write_md(os.path.join(outdir,f"ANOMALY_{ymd}.md"), [f"# ANOMALY {iso}", "", json.dumps(an, ensure_ascii=False, indent=2)])

    write_md(os.path.join(backupdir,f"DAILY_BRIEF_{ymd}.md"), brief)
    write_md(os.path.join(outdir,f"DAILY_BRIEF_{ymd}.md"), brief)

    print(os.path.join(backupdir,f"DAILY_BRIEF_{ymd}.md"))

if __name__=="__main__":
    main()
