param(
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [switch]$ShadowEnabled
)

$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\org_bot"
$PY="$ROOT\.venv\Scripts\python.exe"
if(!(Test-Path $PY)){ throw "MISSING_PY=$PY" }

# --- single instance lock (RunRoot scoped) ---
$lockDir=Join-Path $RunRoot "state\locks"
New-Item -ItemType Directory -Force $lockDir | Out-Null
$lock=Join-Path $lockDir "RUN_CANON_AUDITED_V2.lock"

if(Test-Path $lock){
  $age=(Get-Date)-(Get-Item $lock).LastWriteTime
  if($age.TotalMinutes -lt 240){
    throw "LOCK_EXISTS=$lock age_min=$([int]$age.TotalMinutes)"
  } else {
    Remove-Item $lock -Force -ErrorAction SilentlyContinue
  }
}
"pid=$PID`nts=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())" | Set-Content -Encoding utf8 $lock

try {
  $ops=Join-Path $RunRoot "logs\ops"
  New-Item -ItemType Directory -Force $ops | Out-Null
  $stamp=Get-Date -Format "yyyyMMdd_HHmmss"

  $out=Join-Path $ops "CANON_OUT_$stamp.txt"
  $err=Join-Path $ops "CANON_ERR_$stamp.txt"
  $audit=Join-Path $ops "EXIT_AUDIT_$stamp.txt"

  $bg=Join-Path $RunRoot "state\boot_guard.json"
  if(Test-Path $bg){
    Copy-Item $bg (Join-Path $ops "boot_guard_before_$stamp.json") -Force
  }

  $env:TBOT_RUNROOT=$RunRoot

  # --- Trace flags (root-cause capture) ---
  $env:TBOT_TRACE_SYSTEMEXIT="1"
  $env:TBOT_TRACE_ENTRYPOINT="1"
  $env:TBOT_TRACE_EXCEPTIONS="1"
  $env:PYTHONFAULTHANDLER="1"

  $args=@("-u","-m","tbot.main","--run")
  if($ShadowEnabled){ $args += "--shadow" }

  # Run and capture
  & $PY @args 1> $out 2> $err
  $rc=$LASTEXITCODE

  if(Test-Path $bg){
    Copy-Item $bg (Join-Path $ops "boot_guard_after_$stamp.json") -Force
  }

  @"
ts=$stamp
runroot=$RunRoot
argv=$($args -join ' ')
rc=$rc
out=$out
err=$err
trace=TBOT_TRACE_SYSTEMEXIT=1 TBOT_TRACE_ENTRYPOINT=1 TBOT_TRACE_EXCEPTIONS=1 PYTHONFAULTHANDLER=1
"@ | Set-Content -Encoding utf8 $audit

  "AUDIT=$audit"
  "RC=$rc"
  exit $rc
}
finally {
  Remove-Item $lock -Force -ErrorAction SilentlyContinue
}
