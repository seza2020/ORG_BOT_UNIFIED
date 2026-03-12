$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE=Join-Path $ROOT "code"
$RUNROOT=Join-Path $ROOT "runtime\paper"
$PY=Join-Path $CODE ".venv\Scripts\python.exe"

if(!(Test-Path -LiteralPath $PY)){ throw "PY_NOT_FOUND=$PY" }
if(!(Test-Path -LiteralPath $RUNROOT)){ throw "RUNROOT_NOT_FOUND=$RUNROOT" }

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$ADIR=Join-Path $ROOT ("ops\audit\PAPER_DIAG_DRYRUN_" + $stamp)
New-Item -ItemType Directory -Force $ADIR | Out-Null

function Read-Ledger([string]$rr){
  $lp=Join-Path $rr "state\risk\risk_ledger.json"
  if(!(Test-Path -LiteralPath $lp)){ return $null }
  try { return (Get-Content -LiteralPath $lp -Raw -Encoding utf8 | ConvertFrom-Json) } catch { return $null }
}

# 1) Baseline snapshot
$L0 = Read-Ledger $RUNROOT
if($L0){
  ("BASELINE used=$($L0.used_risk) reserved=$($L0.reserved_risk) nres=$(($L0.reservations.PSObject.Properties.Name|Measure-Object).Count)") | Out-Host
} else {
  "BASELINE ledger missing/unreadable (ok for first run)" | Out-Host
}

# 2) Run a managed paper pipeline in dry-run mode (best effort)
# Try the most likely runner; if it doesn't exist we fail with clear evidence.
$RUNNER = Join-Path $CODE "tools\ops\RUN_PAPER_MANAGED_V1.ps1"
if(!(Test-Path -LiteralPath $RUNNER)){
  throw "RUNNER_NOT_FOUND=$RUNNER"
}

# Ensure env for python modules
$env:PYTHONPATH = $CODE
$env:RUNROOT = $RUNROOT

# Dry-run flags (EXECUTE_PLAN_SELECTION_PAPER_V2 supports -DryRun)
$env:TBOT_PAPER_DRYRUN = "1"

# Run and capture output
$out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $RUNNER 2>&1 | Out-String
$out | Set-Content (Join-Path $ADIR "runner_out.txt") -Encoding utf8

# 3) Post snapshot
Start-Sleep -Seconds 1
$L1 = Read-Ledger $RUNROOT
if($L1){
  ("POST used=$($L1.used_risk) reserved=$($L1.reserved_risk) nres=$(($L1.reservations.PSObject.Properties.Name|Measure-Object).Count)") | Out-Host
  ($L1 | ConvertTo-Json -Depth 12) | Set-Content (Join-Path $ADIR "ledger_post.json") -Encoding utf8

  if([double]$L1.reserved_risk -ne 0){
    "FAIL: RESERVED_RISK_NOT_ZERO" | Out-Host
    ("AUDIT_DIR=" + $ADIR) | Out-Host
    "NEXT=PASTE audit runner_out.txt + ledger_post.json" | Out-Host
    exit 2
  }
} else {
  "WARN: ledger missing/unreadable after run" | Out-Host
}

"DRYRUN_DIAG=PASS" | Out-Host
("AUDIT_DIR=" + $ADIR) | Out-Host
"NEXT=IF YOU WANT: run real paper for 5-10 min with executor+poller" | Out-Host
