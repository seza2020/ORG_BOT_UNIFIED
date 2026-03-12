$ErrorActionPreference="Stop"

function WL([string]$s){
  $ts = Get-Date -Format "HH:mm:ss"
  Write-Host ("[{0}] {1}" -f $ts, $s)
}

$ROOT    = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE    = Join-Path $ROOT "code"
$RUNROOT = Join-Path $ROOT "runtime\paper"
$LOGDIR  = Join-Path $RUNROOT "logs"
$OPS     = Join-Path $ROOT "ops"
$AUDIT   = Join-Path $OPS "audit"
$STAMP   = Get-Date -Format "yyyyMMdd_HHmmss"
$ADIR    = Join-Path $AUDIT ("PAPER_QUICK_10MIN_" + $STAMP)
$EVDIR   = Join-Path $ADIR "EVIDENCE"
New-Item -ItemType Directory -Force -Path $EVDIR | Out-Null

$stdout = Join-Path $EVDIR "stdout.txt"
$stderr = Join-Path $EVDIR "stderr.txt"
$qlog   = Join-Path $EVDIR "quick_run_log.txt"

WL "START QUICK_10MIN"
WL "AUDITDIR=$ADIR"
WL "CWD=$(Get-Location)"
WL "RUNROOT=$RUNROOT"
WL "LOGDIR=$LOGDIR"

# Hard bind environment
Set-Location $CODE
$env:PYTHONPATH    = $CODE
$env:TBOT_ROOT     = $ROOT
$env:TBOT_CODE     = $CODE
$env:TBOT_RUNROOT  = $RUNROOT
$env:TBOT_LOG_ROOT = $LOGDIR
$env:TBOT_OPS_LOG  = (Join-Path $LOGDIR "ops")

# Required scripts
$RUNBOOKS = Join-Path $ROOT "ops\runbooks"
$PREFLIGHT = Join-Path $RUNBOOKS "PAPER_PREFLIGHT_HARDENED_AND_PACK.ps1"
$TRACE     = Join-Path $RUNBOOKS "TRACE_PAPER_LOG_DESTINATIONS.ps1"
$EXECUTOR  = Join-Path $ROOT "code\tools\paper\RUN_PAPER_EXECUTOR_TASK_V1.ps1"
$POLL      = Join-Path $ROOT "code\tools\paper\RUN_PAPER_ORDER_POLL_TASK_V1.ps1"
$RECON     = Join-Path $ROOT "code\tools\paper\RECON_PAPER_V1.ps1"

foreach($p in @($PREFLIGHT,$TRACE,$EXECUTOR,$POLL,$RECON)){
  if(!(Test-Path -LiteralPath $p)){ throw "MISSING_REQUIRED=$p" }
}

function RunStepFile([string]$name,[string]$file,[hashtable]$params){
  $ts=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  ("== {0} @ {1} ==" -f $name,$ts) | Add-Content -LiteralPath $qlog -Encoding utf8
  try{
    $args=@()
    if($params){
      foreach($k in $params.Keys){
        $args += @("-$k", [string]$params[$k])
      }
    }
    $out = & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $file @args 2>&1 | Out-String
    $out | Add-Content -LiteralPath $qlog -Encoding utf8
  } catch {
    ("EXCEPTION=" + $_.Exception.Message) | Add-Content -LiteralPath $qlog -Encoding utf8
    throw
  }
}

$childExit=0
try{
  RunStepFile "PREFLIGHT"   $PREFLIGHT @{}
  RunStepFile "TRACE_BEFORE" $TRACE    @{}

  $end = (Get-Date).AddMinutes(10)
  $nextExec = Get-Date

  while((Get-Date) -lt $end){
    if((Get-Date) -ge $nextExec){
      RunStepFile "EXECUTOR_ONCE" $EXECUTOR @{}
      $nextExec = (Get-Date).AddSeconds(60)
    }
    RunStepFile "POLL_ONCE" $POLL @{}
    Start-Sleep -Seconds 10
  }

  RunStepFile "RECON"      $RECON  @{}
  RunStepFile "TRACE_AFTER" $TRACE @{}

} catch {
  $childExit = 1
  ("CHILD_EXCEPTION=" + $_.ToString()) | Set-Content -LiteralPath $stderr -Encoding utf8
}

# Health snapshot
$py = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match "tbot\.main" -and $_.CommandLine -match "ORG_BOT_UNIFIED" }
"TBOT_PY_COUNT=$($py.Count)" | Add-Content -LiteralPath $qlog -Encoding utf8

$pollCount = (Get-ChildItem $LOGDIR -Filter "ORDER_POLL_*.txt" -ErrorAction SilentlyContinue | Measure-Object).Count
"ORDER_POLL_FILES_COUNT=$pollCount" | Add-Content -LiteralPath $qlog -Encoding utf8

# Write evidence stdout with tail
"---- QUICK_RUN_LOG_TAIL_120 ----" | Set-Content -LiteralPath $stdout -Encoding utf8
if(Test-Path $qlog){ Get-Content $qlog -Tail 120 | Add-Content -LiteralPath $stdout -Encoding utf8 }
if(Test-Path $stderr){
  "" | Add-Content -LiteralPath $stdout -Encoding utf8
  "---- STDERR_TAIL_120 ----" | Add-Content -LiteralPath $stdout -Encoding utf8
  Get-Content $stderr -Tail 120 | Add-Content -LiteralPath $stdout -Encoding utf8
}

$zip = Join-Path $ADIR ("PAPER_QUICK_10MIN_" + $STAMP + ".zip")
Compress-Archive -Path "$EVDIR\*" -DestinationPath $zip -Force

WL ("CHILD_EXITCODE=" + $childExit)
WL ("EVIDENCE_ZIP=" + $zip)
