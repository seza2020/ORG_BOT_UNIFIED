import inspect, sys, os
from tbot.market.market_provider import build_market_snapshot

m = build_market_snapshot(symbols=("SPY",))
print("TYPE:", type(m))
print("REPR:", m)

d = dict(getattr(m, "__dict__", {}))
print("TOP_KEYS:", sorted(d.keys()))

v = d.get("SPY", None)
print("SPY_VALUE_TYPE:", type(v))
print("SPY_VALUE_REPR:", repr(v))

# If v is dict-like, print keys
try:
    if isinstance(v, dict):
        print("SPY_DICT_KEYS_COUNT:", len(v))
        print("SPY_DICT_KEYS_SAMPLE:", sorted(list(v.keys()))[:120])
    elif hasattr(v, "__dict__"):
        vd = dict(v.__dict__)
        print("SPY_OBJ_DICT_KEYS_COUNT:", len(vd))
        print("SPY_OBJ_DICT_KEYS_SAMPLE:", sorted(list(vd.keys()))[:120])
except Exception as e:
    print("SPY_INTROSPECT_ERR:", repr(e))

import tbot.market.market_provider as mp
print("MARKET_PROVIDER_FILE:", inspect.getsourcefile(mp))
print("ENV_TBOT_RUNROOT:", os.getenv("TBOT_RUNROOT"))
print("ENV_TBOT_LOGDIR:", os.getenv("TBOT_LOGDIR"))
print("SYS_EXECUTABLE:", sys.executable)
print("SYS_PATH0_12:", sys.path[:12])
