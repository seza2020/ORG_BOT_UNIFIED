$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$RUNBOOKS=Join-Path $ROOT "ops\runbooks"
$TOOLS=Join-Path $ROOT "code\tools\paper"

$PREFLIGHT = Join-Path $RUNBOOKS "PAPER_PREFLIGHT_HARDENED_AND_PACK.ps1"
$EXECUTOR  = Join-Path $TOOLS "RUN_PAPER_EXECUTOR_TASK_V1.ps1"
$POLL      = Join-Path $TOOLS "RUN_PAPER_ORDER_POLL_TASK_V1.ps1"
$TRACE     = Join-Path $RUNBOOKS "TRACE_PAPER_LOG_DESTINATIONS.ps1"
$RECON     = Join-Path $TOOLS "RECON_PAPER_V1.ps1"

if(!(Test-Path -LiteralPath $PREFLIGHT)){ throw "MISSING_PREFLIGHT=$PREFLIGHT" }
if(!(Test-Path -LiteralPath $EXECUTOR)){ throw "MISSING_EXECUTOR=$EXECUTOR" }
if(!(Test-Path -LiteralPath $POLL)){ throw "MISSING_POLL=$POLL" }
if(!(Test-Path -LiteralPath $TRACE)){ throw "MISSING_TRACE=$TRACE" }
if(!(Test-Path -LiteralPath $RECON)){ throw "MISSING_RECON=$RECON" }

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$ADIR=Join-Path $ROOT ("ops\audit\RUN_PAPER_MANUAL_" + $stamp)
New-Item -ItemType Directory -Force -Path $ADIR | Out-Null

function RunStep([string]$name,[string]$cmd,[string]$out){
  $ts=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  ("== {0} @ {1} ==" -f $name,$ts) | Add-Content -LiteralPath $out -Encoding utf8
  $r = & pwsh -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1 | Out-String
  $r | Add-Content -LiteralPath $out -Encoding utf8
}

$log = Join-Path $ADIR "manual_run_log.txt"

RunStep "PREFLIGHT" ("& `"$PREFLIGHT`"") $log

# Start window: 06:30 local
$start=[datetime]::Today.AddHours(6).AddMinutes(30)
$end  =[datetime]::Today.AddHours(13)

if([datetime]::Now -lt $start){
  $wait = [int]([math]::Ceiling(($start-[datetime]::Now).TotalSeconds))
  ("WAITING_UNTIL_START seconds=" + $wait) | Add-Content -LiteralPath $log -Encoding utf8
  Start-Sleep -Seconds $wait
}

RunStep "TRACE_BEFORE" ("& `"$TRACE`"") $log

# Loop: run executor every 60s, poll every 10s
$nextExec = [datetime]::Now
while([datetime]::Now -lt $end){
  if([datetime]::Now -ge $nextExec){
    RunStep "EXECUTOR_ONCE" ("& `"$EXECUTOR`"") $log
    $nextExec = [datetime]::Now.AddSeconds(60)
  }

  RunStep "POLL_ONCE" ("& `"$POLL`"") $log
  Start-Sleep -Seconds 10
}

RunStep "RECON" ("& `"$RECON`"") $log
RunStep "TRACE_AFTER" ("& `"$TRACE`"") $log

Write-Host "RUN_DONE=OK"
Write-Host ("AUDIT_DIR=" + $ADIR)
Write-Host "NEXT=CHECK log destinations + risk ledger + orders/fills summary"
