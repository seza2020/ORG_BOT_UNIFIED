from __future__ import annotations
import json
from collections import Counter
from pathlib import Path

SRC = Path(r"C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\validation_v2\outcome_ledger.jsonl")
OUT = Path(r"C:\alpaca-bot\ORG_BOT_UNIFIED\ops\analytics\expectancy_engine\schema_probe_out")

OUT.mkdir(parents=True, exist_ok=True)

samples = []
key_counter = Counter()
nested_counter = Counter()
line_count = 0

with SRC.open("r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        line_count += 1
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if isinstance(obj, dict):
            for k, v in obj.items():
                key_counter[str(k)] += 1
                if isinstance(v, dict):
                    for nk in v.keys():
                        nested_counter[f"{k}.{nk}"] += 1
            if len(samples) < 10:
                samples.append(obj)

summary = {
    "source": str(SRC),
    "records_seen": line_count,
    "top_level_keys": dict(key_counter.most_common()),
    "nested_keys": dict(nested_counter.most_common()),
}

(OUT / "outcome_schema_summary.json").write_text(
    json.dumps(summary, indent=2, ensure_ascii=False),
    encoding="utf-8"
)
(OUT / "outcome_schema_samples.json").write_text(
    json.dumps(samples, indent=2, ensure_ascii=False),
    encoding="utf-8"
)

print("OUTCOME_SCHEMA_PROBE=OK")
print("SUMMARY_JSON=" + str(OUT / "outcome_schema_summary.json"))
print("SAMPLES_JSON=" + str(OUT / "outcome_schema_samples.json"))
