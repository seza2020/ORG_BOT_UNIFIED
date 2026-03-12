import pathlib, re, shutil, sys
from datetime import datetime

ROOT=pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime")
STAMP="TBOT_SHADOW_PIPELINE_V4"

def ts(): return datetime.now().strftime("%Y%m%d_%H%M%S")

def backup(p):
    b=p.with_suffix(p.suffix+".bak_"+ts())
    shutil.copy2(p,b)

def patch(p):
    t=p.read_text(encoding="utf-8",errors="ignore")
    if STAMP in t:
        return False,"already"

    if '"entry": 100.0' not in t and '"stop": 101.0' not in t:
        return False,"no_dummy"

    hook = '''
# TBOT_SHADOW_PIPELINE_V4
from tbot.market.market_provider import build_market_snapshot
from tbot.runtime.shadow_pricing import compute_shadow_prices

def _apply_shadow(rec):
    try:
        sym = rec.get("symbol")
        side = rec.get("side")
        m = build_market_snapshot(symbols=(sym,))
        p = compute_shadow_prices(
            sig_payload={"symbol": sym, "side": side},
            market=m,
            default_entry=rec["entry"],
            default_stop=rec["stop"],
            default_tp=rec["tp"],
        )
        rec["entry"] = float(p.entry)
        rec["stop"]  = float(p.stop)
        rec["tp"]    = float(p.tp)
    except Exception:
        pass
    return rec
'''

    t = hook + t
    t = re.sub(r'(rec\s*=\s*\{)', r'\1\n    "_patched": True,', t)
    t = re.sub(r'(rec\s*=\s*\{[^}]*\})', r'_apply_shadow(\1)', t, flags=re.S)

    backup(p)
    p.write_text(t, encoding="utf-8")
    return True,"patched"

def main():
    files=list(ROOT.rglob("*.py"))
    print("[V4] scanning",len(files))

    for p in files:
        ok,msg=patch(p)
        print("[V4]",p,ok,msg)
        if ok:
            print("[V4] SUCCESS",p)
            sys.exit(0)

    print("[V4] no patch applied")
    sys.exit(3)

if __name__=="__main__":
    main()
