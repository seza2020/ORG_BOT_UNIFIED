import json, time, datetime
from tbot.runtime.local_decision_client import request_decision

features={"diag":True,"case":"echo","ts":datetime.datetime.utcnow().isoformat()+"Z"}
meta={"run_id":"diag_echo","symbol":"DIAG","sid":"DIAG"}

t0=time.time()
r=None
err=None
try:
    r=request_decision(features=features, meta=meta, timeout_sec=3.0)
except Exception as e:
    err=repr(e)
lat=round(time.time()-t0,4)

print("LAT=",lat)
print("RESP=",json.dumps(r, ensure_ascii=False))
print("ERR=",err)
