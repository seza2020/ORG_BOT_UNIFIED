import json, time, os, datetime
from tbot.runtime.local_decision_client import request_decision

RUNROOT = r"C:\alpaca-bot\org_bot_runtime\paper"
META = os.path.join(RUNROOT, "logs", "meta.jsonl")

features = {"diag": True, "ts": datetime.datetime.utcnow().isoformat()+"Z"}
meta = {"run_id":"diag_llm_gate_runonce","symbol":"DIAG","sid":"DIAG"}

t0 = time.time()
try:
    r = request_decision(features=features, meta=meta, timeout_sec=2.0)
    lat = round(time.time()-t0, 4)
    decision = (r or {}).get("decision","NO_DECISION")
    evt = {"ts": datetime.datetime.utcnow().replace(microsecond=0).isoformat()+"Z",
           "level":"INFO","kind":"llm_gate","payload":{"ok": decision=="ALLOW",
           "decision":decision,"latency":lat,"raw":r},"run_id":"diag_llm_gate_runonce"}
except Exception as e:
    lat = round(time.time()-t0, 4)
    evt = {"ts": datetime.datetime.utcnow().replace(microsecond=0).isoformat()+"Z",
           "level":"ERROR","kind":"llm_gate","payload":{"ok": False,"decision":"ERROR",
           "latency":lat,"err":repr(e)},"run_id":"diag_llm_gate_runonce"}

os.makedirs(os.path.dirname(META), exist_ok=True)
with open(META,"a",encoding="utf-8",newline="\n") as f:
    f.write(json.dumps(evt, ensure_ascii=False) + "\n")

print("WROTE", evt["kind"], "to", META)
print("DECISION=", evt["payload"].get("decision"), "LAT=", evt["payload"].get("latency"))
