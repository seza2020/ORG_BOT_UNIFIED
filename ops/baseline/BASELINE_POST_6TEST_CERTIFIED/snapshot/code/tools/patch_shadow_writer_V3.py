import pathlib, re, json, shutil, sys
from datetime import datetime

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
TBOT = ROOT / "tbot"

STAMP="TBOT_SHADOW_WRITER_V3"

def ts(): return datetime.now().strftime("%Y%m%d_%H%M%S")

def backup(p):
    b=p.with_suffix(p.suffix+".bak_"+ts())
    shutil.copy2(p,b)
    return b

def patch_file(p):
    t=p.read_text(encoding="utf-8",errors="ignore")
    if STAMP in t: return False,"already"

    if "shadow_plans.jsonl" not in t:
        return False,"no_shadow_ref"

    lines=t.splitlines()
    out=[]
    injected=False

    helper=f'''
# {STAMP}
def _apply_shadow_prices(rec):
    try:
        if not isinstance(rec,dict): return rec
        if "entry" not in rec: return rec
        from tbot.market.market_provider import build_market_snapshot
        from tbot.runtime.shadow_pricing import compute_shadow_prices
        sym=rec.get("symbol"); side=rec.get("side")
        if not sym or not side: return rec
        m=build_market_snapshot(symbols=(sym,))
        p=compute_shadow_prices(
            sig_payload={{"symbol":sym,"side":side}},
            market=m,
            default_entry=float(rec["entry"]),
            default_stop=float(rec["stop"]),
            default_tp=float(rec["tp"])
        )
        rec["entry"]=float(p.entry)
        rec["stop"]=float(p.stop)
        rec["tp"]=float(p.tp)
        return rec
    except Exception:
        return rec
'''

    inserted=False
    for ln in lines:
        if not inserted and (ln.startswith("import ") or ln.startswith("from ")):
            out.append(ln)
            continue
        if not inserted:
            out.append(helper)
            inserted=True
        out.append(ln)

    final=[]
    for ln in out:
        if ("write(" in ln or "print(" in ln) and "shadow_plans.jsonl" in ln:
            indent=re.match(r"\s*",ln).group(0)
            final.append(indent+"try: rec=_apply_shadow_prices(rec)\n"+indent+"except: pass")
        final.append(ln)

    backup(p)
    p.write_text("\n".join(final),encoding="utf-8")
    return True,"patched"

def main():
    hits=[]
    for p in TBOT.rglob("*.py"):
        if "shadow_plans.jsonl" in p.read_text(encoding="utf-8",errors="ignore"):
            hits.append(p)

    print("[V3] candidates=",len(hits))
    for p in hits:
        ok,msg=patch_file(p)
        print("[V3]",p,ok,msg)
        if ok:
            print("[V3] SUCCESS")
            sys.exit(0)

    print("[V3] no file patched")
    sys.exit(3)

if __name__=="__main__":
    main()
