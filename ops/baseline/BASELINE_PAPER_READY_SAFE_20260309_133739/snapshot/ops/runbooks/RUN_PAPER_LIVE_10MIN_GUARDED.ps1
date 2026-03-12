$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE=Join-Path $ROOT "code"
$RUNROOT=Join-Path $ROOT "runtime\paper"
$PAPER=Join-Path $CODE "tools\paper"
$OPS=Join-Path $CODE "tools\ops"

$EXEC_TASK = Join-Path $PAPER "RUN_PAPER_EXECUTOR_TASK_V1.ps1"
$POLL_TASK = Join-Path $PAPER "RUN_PAPER_ORDER_POLL_TASK_V1.ps1"
$RECON     = Join-Path $PAPER "RECON_PAPER_V1.ps1"

if(!(Test-Path -LiteralPath $EXEC_TASK)){ throw "EXEC_TASK_NOT_FOUND=$EXEC_TASK" }
if(!(Test-Path -LiteralPath $POLL_TASK)){ throw "POLL_TASK_NOT_FOUND=$POLL_TASK" }
if(!(Test-Path -LiteralPath $RECON)){ throw "RECON_NOT_FOUND=$RECON" }
if(!(Test-Path -LiteralPath $RUNROOT)){ throw "RUNROOT_NOT_FOUND=$RUNROOT" }

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$ADIR=Join-Path $ROOT ("ops\audit\PAPER_LIVE_10MIN_" + $stamp)
New-Item -ItemType Directory -Force $ADIR | Out-Null

function WL([string]$s){ $s | Out-Host; Add-Content -LiteralPath (Join-Path $ADIR "run.log") -Value $s -Encoding utf8 }

function Read-Ledger([string]$rr){
  $lp=Join-Path $rr "state\risk\risk_ledger.json"
  if(!(Test-Path -LiteralPath $lp)){ return $null }
  try { return (Get-Content -LiteralPath $lp -Raw -Encoding utf8 | ConvertFrom-Json) } catch { return $null }
}

# ---- Pre: kill any stray python that might be holding files (best-effort) ----
try {
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.CommandLine -match "ORG_BOT_UNIFIED" -and $_.CommandLine -match "tbot\.main" } |
    ForEach-Object {
      WL ("KILL python pid=" + $_.ProcessId)
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
} catch {}

# ---- Env ----
$env:PYTHONPATH = $CODE
$env:RUNROOT = $RUNROOT

# Optional: safety caps (leave your existing gate config as-is)
# $env:TBOT_MAX_PLANS_PER_DAY="3"

# ---- Baseline ledger ----
$L0 = Read-Ledger $RUNROOT
if($L0){
  WL ("BASELINE used=$($L0.used_risk) reserved=$($L0.reserved_risk) nres=$(($L0.reservations.PSObject.Properties.Name|Measure-Object).Count)")
} else {
  WL "BASELINE ledger missing/unreadable"
}

# ---- Run executor once ----
WL "RUN_EXECUTOR_ONCE..."
$execOut = & pwsh -NoProfile -ExecutionPolicy Bypass -File $EXEC_TASK 2>&1 | Out-String
$execOut | Set-Content (Join-Path $ADIR "executor_out.txt") -Encoding utf8
WL "EXECUTOR_DONE"

# ---- Poll loop for 10 minutes ----
WL "POLL_LOOP_10MIN_START..."
$t0 = Get-Date
while(((Get-Date) - $t0).TotalSeconds -lt 600){
  $pollOut = & pwsh -NoProfile -ExecutionPolicy Bypass -File $POLL_TASK 2>&1 | Out-String
  Add-Content -LiteralPath (Join-Path $ADIR "poll_out.txt") -Value ("
--- " + (Get-Date).ToString("s") + " ---
" + $pollOut) -Encoding utf8
  Start-Sleep -Seconds 10
}
WL "POLL_LOOP_10MIN_END"

# ---- Recon once ----
WL "RUN_RECON..."
$reconOut = & pwsh -NoProfile -ExecutionPolicy Bypass -File $RECON 2>&1 | Out-String
$reconOut | Set-Content (Join-Path $ADIR "recon_out.txt") -Encoding utf8
WL "RECON_DONE"

# ---- Post ledger check ----
$L1 = Read-Ledger $RUNROOT
if($L1){
  ($L1 | ConvertTo-Json -Depth 12) | Set-Content (Join-Path $ADIR "ledger_post.json") -Encoding utf8
  WL ("POST used=$($L1.used_risk) reserved=$($L1.reserved_risk) nres=$(($L1.reservations.PSObject.Properties.Name|Measure-Object).Count)")

  if([double]$L1.reserved_risk -ne 0){
    WL "FAIL: RESERVED_RISK_NOT_ZERO"
    WL ("AUDIT_DIR=" + $ADIR)
    WL "NEXT=PASTE executor_out.txt + poll_out.txt tail + recon_out.txt + ledger_post.json"
    exit 2
  }
} else {
  WL "WARN: ledger missing/unreadable after run"
}

WL "PAPER_LIVE_10MIN=PASS"
WL ("AUDIT_DIR=" + $ADIR)
WL "NEXT=If orders/fills look sane, run 30-60 min session; else paste audit files."
