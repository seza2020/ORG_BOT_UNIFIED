import json, os, datetime
p=r"C:\alpaca-bot\org_bot_runtime\paper\logs\meta.jsonl"
evt={
  "ts": datetime.datetime.utcnow().replace(microsecond=0).isoformat()+"Z",
  "level":"INFO",
  "kind":"llm_gate_probe",
  "payload":{"note":"probe_append_v1","why":"verify meta write path"},
  "run_id":"probe_manual"
}
with open(p,"a",encoding="utf-8",newline="\n") as f:
  f.write(json.dumps(evt, ensure_ascii=False) + "\n")
print("OK appended to", p)
