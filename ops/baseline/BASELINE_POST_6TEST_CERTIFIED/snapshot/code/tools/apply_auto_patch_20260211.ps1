param(
  [string]$Root = "C:\alpaca-bot\org_bot"
)

$ErrorActionPreference="Stop"

function WriteFile([string]$Path,[string]$Text){
  New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
  $Text | Set-Content -Path $Path -Encoding UTF8
}

$Tools = Join-Path $Root "tools"
$Logs  = Join-Path $Root "logs"
$Ops   = Join-Path $Logs "ops"
$Arch  = Join-Path $Logs "archive"
New-Item -ItemType Directory -Force -Path $Tools,$Logs,$Ops,$Arch | Out-Null

# ---------- Python QC: scan ALL LIVE_OUT/ERR for the day ----------
$qcPy = @"
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
"@
WriteFile (Join-Path $Tools "qc_ops_all.py") $qcPy

# ---------- PowerShell: rotate shadow_plans.jsonl at start ----------
$rotatePs = @"
param(
  [string]`$Root = "C:\alpaca-bot\org_bot"
)
`$ErrorActionPreference="Stop"
`$Logs = Join-Path `$Root "logs"
`$Arch = Join-Path `$Logs "archive"
New-Item -ItemType Directory -Force -Path `$Arch | Out-Null

`$sp = Join-Path `$Logs "shadow_plans.jsonl"
if (Test-Path `$sp) {
  `$len = (Get-Item `$sp).Length
  if (`$len -gt 0) {
    `$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    `$dst = Join-Path `$Arch ("shadow_plans_{0}.jsonl" -f `$stamp)
    Move-Item -Force `$sp `$dst
  } else {
    Remove-Item -Force `$sp
  }
}
# create fresh file
New-Item -ItemType File -Force -Path `$sp | Out-Null
"@
WriteFile (Join-Path $Tools "rotate_shadow_plans.ps1") $rotatePs

# ---------- PowerShell: run shadow with hard preflight + post QC ----------
$runAuto = @"
param(
  [string]`$Root = "C:\alpaca-bot\org_bot",
  [int]`$GateCooldownSec = 30,
  [int]`$GateMaxPlansPerDay = 150,
  [int]`$GateMaxRiskUsd = 500,
  [double]`$GateMinRR = 1.0,
  [double]`$GateMinConf = 0.0
)

`$ErrorActionPreference="Stop"

# paths
`$Py = Join-Path `$Root ".venv\Scripts\python.exe"
`$Logs = Join-Path `$Root "logs"
`$Ops  = Join-Path `$Logs "ops"
New-Item -ItemType Directory -Force -Path `$Ops | Out-Null

# 0) kill stale python
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 1) cd + env
Set-Location `$Root
`$env:PYTHONPATH = `$Root

# 2) secrets
. "C:\alpaca-bot\secrets\alpaca_env.ps1"

# 3) shadow env
`$env:TBOT_MVP="1"
`$env:TBOT_ENABLE_S01_LOGIC="1"
`$env:TBOT_S11_ENABLE="1"
`$env:TBOT_SHADOW_PRICE_MODE="last"
`$env:TBOT_SHADOW_RR="2.0"
`$env:TBOT_SHADOW_STOP_PCT="0.003"

# 4) rotate shadow plans (fresh day file)
pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path `$Root "tools\rotate_shadow_plans.ps1") -Root `$Root

# 5) preflight: enforce venv python + import tbot
if (-not (Test-Path `$Py)) { throw "Venv python not found: `$Py" }
`$exe = & `$Py -c "import sys; print(sys.executable)"
if (`$exe -notmatch "\\\.venv\\\Scripts\\\python\.exe$") {
  throw "Preflight failed: not using venv python. exe=`$exe"
}
& `$Py -c "import tbot; import tbot.main; print('preflight_ok')"

# 6) run
`$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
`$out = Join-Path `$Ops ("LIVE_OUT_{0}.txt" -f `$stamp)
`$err = Join-Path `$Ops ("LIVE_ERR_{0}.txt" -f `$stamp)

`$args = @(
  "-m","tbot.main",
  "--shadow",
  "--gate_min_rr", [string]`$GateMinRR,
  "--gate_min_conf", [string]`$GateMinConf,
  "--gate_cooldown_sec", [string]`$GateCooldownSec,
  "--gate_max_plans_per_day", [string]`$GateMaxPlansPerDay,
  "--gate_max_risk_usd", [string]`$GateMaxRiskUsd
)

Write-Host "RUN_SHADOW_AUTO..."
Write-Host ("PY=" + `$exe)
Write-Host ("OUT=" + `$out)
Write-Host ("ERR=" + `$err)

& `$Py @args 1> `$out 2> `$err

# 7) post QC: scan ALL outs/errs for today
`$date = Get-Date -Format "yyyyMMdd"
`$qc = & `$Py (Join-Path `$Root "tools\qc_ops_all.py") --root `$Root --date `$date
exit `$LASTEXITCODE
"@
WriteFile (Join-Path $Tools "RUN_SHADOW_AUTO.ps1") $runAuto

# ---------- PowerShell: audit scheduled tasks that call system python / tbot ----------
$audit = @"
param()
`$ErrorActionPreference="SilentlyContinue"
`$hits = @()
Get-ScheduledTask | ForEach-Object {
  `$_task = `$_
  try {
    `$xml = Export-ScheduledTask -TaskName `$_task.TaskName -TaskPath `$_task.TaskPath
    if (`$xml -match "C:\\\\Python313\\\\python\.exe" -or `$xml -match "tbot\.main" -or `$xml -match "alpaca-bot\\\\org_bot") {
      `$hits += [pscustomobject]@{
        TaskName = `$_task.TaskName
        TaskPath = `$_task.TaskPath
      }
    }
  } catch {}
}
if (`$hits.Count -eq 0) {
  "NO_MATCHING_TASKS"
} else {
  `$hits | Format-Table -Auto
  "TIP: For any old task that runs system python, point it to tools\\RUN_SHADOW_AUTO.ps1 instead."
}
"@
WriteFile (Join-Path $Tools "audit_scheduled_tasks.ps1") $audit

"PATCH_INSTALLED=OK"
"Created:"
Join-Path $Tools "RUN_SHADOW_AUTO.ps1"
Join-Path $Tools "rotate_shadow_plans.ps1"
Join-Path $Tools "qc_ops_all.py"
Join-Path $Tools "audit_scheduled_tasks.ps1"
