import json, inspect, sys
from tbot.market.market_provider import build_market_snapshot

m = build_market_snapshot(symbols=("SPY",))

print("TYPE:", type(m))
print("REPR:", m)

d = None
if hasattr(m, "to_dict"):
    try:
        d = m.to_dict()
        print("to_dict: OK")
    except Exception as e:
        print("to_dict: ERR", repr(e))

if d is None and hasattr(m, "__dict__"):
    try:
        d = dict(m.__dict__)
        print("__dict__: OK")
    except Exception as e:
        print("__dict__: ERR", repr(e))

if isinstance(d, dict):
    top_keys = sorted(list(d.keys()))
    print("DICT_KEYS_TOP_COUNT:", len(top_keys))
    print("DICT_KEYS_TOP_SAMPLE:", top_keys[:80])

    # If SPY nested dict exists
    for k in ("SPY", "spy"):
        if k in d and isinstance(d[k], dict):
            spy_keys = sorted(list(d[k].keys()))
            print("SPY_KEYS_COUNT:", len(spy_keys))
            print("SPY_KEYS_SAMPLE:", spy_keys[:120])
            break

def scan(obj, path=""):
    hits=[]
    if isinstance(obj, dict):
        for kk,v in obj.items():
            kls = str(kk).lower()
            p = f"{path}.{kk}" if path else str(kk)
            if any(x in kls for x in ["bar","bars","close","open","high","low","last","price","ts","time","timestamp","vwap","ema","atr","vol","volume"]):
                hits.append(p)
            hits += scan(v, p)
    elif isinstance(obj, (list,tuple)):
        if len(obj) <= 5:
            for i,v in enumerate(obj):
                hits += scan(v, f"{path}[{i}]")
    return hits

if isinstance(d, dict):
    hits = scan(d)
    print("HEURISTIC_HITS_COUNT:", len(hits))
    print("HEURISTIC_HITS_SAMPLE:", hits[:120])

import tbot.market.market_provider as mp
print("MARKET_PROVIDER_FILE:", inspect.getsourcefile(mp))

print("SYS_EXECUTABLE:", sys.executable)
print("SYS_PATH0_12:", sys.path[:12])
