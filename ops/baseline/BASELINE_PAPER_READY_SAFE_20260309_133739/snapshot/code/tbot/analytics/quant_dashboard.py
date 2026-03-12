from __future__ import annotations
import os,json,time,statistics
from typing import Dict,Any,List

def _runroot():
    rr=os.environ.get("TBOT_RUNROOT")
    if rr: return rr
    root=os.environ.get("TBOT_UNIFIED_ROOT","C:\\alpaca-bot\\ORG_BOT_UNIFIED")
    prof=os.environ.get("TBOT_PROFILE","paper")
    return os.path.join(root,"runtime",prof)

def _read_json(p):
    try:
        with open(p,"r",encoding="utf-8") as f:
            return json.load(f)
    except:
        return None

def _read_jsonl(p):
    out=[]
    try:
        with open(p,"r",encoding="utf-8") as f:
            for l in f:
                try: out.append(json.loads(l))
                except: pass
    except: pass
    return out

def _write_json(p,o):
    os.makedirs(os.path.dirname(p),exist_ok=True)
    with open(p,"w",encoding="utf-8") as f:
        json.dump(o,f,indent=2)

def _calc_expectancy(trades:List[float]):
    if not trades: return 0
    wins=[t for t in trades if t>0]
    losses=[t for t in trades if t<=0]
    winrate=len(wins)/len(trades)
    avgw=sum(wins)/len(wins) if wins else 0
    avgl=sum(losses)/len(losses) if losses else 0
    return (winrate*avgw)+((1-winrate)*avgl)

def build_dashboard():
    rr=_runroot()
    ana=os.path.join(rr,"analytics")
    os.makedirs(ana,exist_ok=True)

    ledger=_read_jsonl(os.path.join(ana,"ledger_history.jsonl"))
    pnl=_read_jsonl(os.path.join(rr,"logs","pnl_ticks.jsonl"))
    regime=_read_json(os.path.join(ana,"regime_report.json")) or {}
    meta=_read_json(os.path.join(ana,"meta_strategy_report.json")) or {}

    trades=[x.get("r",0) for x in ledger if isinstance(x,dict)]
    equity=[x.get("account",{}).get("equity") for x in pnl if isinstance(x,dict)]

    winrate=0
    pf=0
    expectancy=0
    dd=0

    if trades:
        wins=[t for t in trades if t>0]
        losses=[abs(t) for t in trades if t<=0]

        if trades:
            winrate=len(wins)/len(trades)

        if losses:
            pf=sum(wins)/sum(losses) if sum(losses)!=0 else 0

        expectancy=_calc_expectancy(trades)

    if equity:
        peak=equity[0]
        ddv=0
        for e in equity:
            if e>peak: peak=e
            d=peak-e
            if d>ddv: ddv=d
        dd=ddv

    dash={
        "ts":time.time(),
        "trade_count":len(trades),
        "win_rate":winrate,
        "profit_factor":pf,
        "expectancy":expectancy,
        "max_drawdown":dd,
        "regime":regime.get("regime"),
        "enabled_strategies":meta.get("enabled_sids"),
    }

    out=os.path.join(ana,"quant_dashboard.json")
    _write_json(out,dash)

    return {"dashboard":out,"metrics":dash}

def main():
    r=build_dashboard()
    print("OK")
    print("dashboard=",r["dashboard"])
    print("metrics=",json.dumps(r["metrics"],indent=2))

if __name__=="__main__":
    main()
