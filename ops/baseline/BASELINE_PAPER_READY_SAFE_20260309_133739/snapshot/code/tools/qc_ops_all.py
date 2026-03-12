import argparse, glob, json, os, re, sys
from datetime import datetime

CRIT_PATTERNS = {
  "traceback": r"Traceback \(most recent call last\)",
  "module_not_found": r"ModuleNotFoundError:",
  "import_error": r"ImportError:",
  "syntax_error": r"SyntaxError:",
  "type_error": r"TypeError:",
  "apca_keys_missing": r"APCA_KEYS_MISSING",
  "rate_429": r"\b429\b|Too Many Requests",
  "timeout": r"timeout|timed out|ReadTimeout|ConnectTimeout",
  "exception": r"\bException\b",
}

def scan_file(path, patterns):
  counts = {k: 0 for k in patterns}
  try:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
      txt = f.read()
  except Exception:
    return counts
  for k, pat in patterns.items():
    counts[k] = len(re.findall(pat, txt))
  return counts

def add_counts(a, b):
  for k, v in b.items():
    a[k] = a.get(k, 0) + v
  return a

def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--root", required=True)
  ap.add_argument("--date", required=True)  # YYYYMMDD
  args = ap.parse_args()

  ops = os.path.join(args.root, "logs", "ops")
  out_glob = os.path.join(ops, f"LIVE_OUT_{args.date}_*.txt")
  err_glob = os.path.join(ops, f"LIVE_ERR_{args.date}_*.txt")

  outs = sorted(glob.glob(out_glob))
  errs = sorted(glob.glob(err_glob))

  total = {k: 0 for k in CRIT_PATTERNS}
  per_file = []

  for p in outs + errs:
    c = scan_file(p, CRIT_PATTERNS)
    add_counts(total, c)
    per_file.append({"file": os.path.basename(p), "counts": c})

  qc = {
    "qc_date": args.date,
    "qc_ts": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
    "live_out_count": len(outs),
    "live_err_count": len(errs),
    "errors_total": total,
    "files": per_file,
  }

  out_txt = os.path.join(ops, f"QC_ALL_{args.date}.txt")
  out_json = os.path.join(ops, f"QC_ALL_{args.date}.json")

  # Write text summary
  lines = []
  lines.append(f"QC_DATE={args.date}")
  lines.append(f"LIVE_OUT_COUNT={len(outs)}")
  lines.append(f"LIVE_ERR_COUNT={len(errs)}")
  lines.append("ERRORS_TOTAL=" + json.dumps(total))
  crit_sum = sum(total.values())
  lines.append(f"CRIT_SUM={crit_sum}")
  if crit_sum == 0:
    lines.append("QC_RESULT=PASS")
  else:
    lines.append("QC_RESULT=WARN")
  lines.append("")
  lines.append("FILES_WITH_ANY_ERRORS:")
  any_err_files = [x for x in per_file if sum(x["counts"].values()) > 0]
  if not any_err_files:
    lines.append("(none)")
  else:
    for x in any_err_files:
      lines.append(f"- {x['file']} :: {json.dumps(x['counts'])}")
  with open(out_txt, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

  with open(out_json, "w", encoding="utf-8") as f:
    json.dump(qc, f, indent=2)

  # Exit code: 0 for PASS, 2 for WARN (lets scheduler/monitor notice)
  sys.exit(0 if crit_sum == 0 else 2)

if __name__ == "__main__":
  main()
