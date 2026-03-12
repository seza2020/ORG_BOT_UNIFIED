import json, csv
from pathlib import Path
from collections import Counter

ROOT = Path(r"C:\alpaca-bot\org_bot")
RUNROOT_PAPER = Path(r"C:\alpaca-bot\org_bot_runtime\paper")
RUNROOT_SHADOW = Path(r"C:\alpaca-bot\org_bot_runtime\shadow")

def newest(p: Path, pattern: str):
    files = list(p.glob(pattern))
    if not files:
        return None
    files.sort(key=lambda x: x.stat().st_mtime, reverse=True)
    return files[0]

paper = newest(RUNROOT_PAPER / "logs", "risk_ledger_PAPER_*.jsonl")
shadow = newest(RUNROOT_SHADOW / "logs", "risk_ledger_SHADOW_*.jsonl")
src = paper or shadow
if not src:
    raise SystemExit("ERROR: No risk_ledger_*.jsonl found in paper/shadow runroots.")

out_dir = ROOT / "_MYGPT_UPLOAD"
out_dir.mkdir(parents=True, exist_ok=True)

out_csv = out_dir / (src.name.replace(".jsonl", "_EXPORT.csv"))
out_kinds = out_dir / (src.name.replace(".jsonl", "_KINDS.txt"))

rows = []
kinds = Counter()

with src.open("r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        kinds[obj.get("kind","<NONE>")] += 1
        rows.append(obj)

fieldnames = []
seen = set()
for r in rows:
    for k in r.keys():
        if k not in seen:
            seen.add(k)
            fieldnames.append(k)

with out_csv.open("w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in rows:
        w.writerow(r)

with out_kinds.open("w", encoding="utf-8") as f:
    f.write(f"SRC={src}\n")
    for k,v in kinds.most_common():
        f.write(f"{k}\t{v}\n")

print("SRC=", str(src))
print("CSV=", str(out_csv))
print("KINDS=", str(out_kinds))
print("KINDS_SUMMARY=", dict(kinds))
print("ROWS=", len(rows))
