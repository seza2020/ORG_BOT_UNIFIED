param()

$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE=Join-Path $ROOT "code"
$RUNROOT=Join-Path $ROOT "runtime\paper"
$LOGDIR=Join-Path $RUNROOT "logs"
$PY=Join-Path $CODE ".venv\Scripts\python.exe"
$ADIR="C:\alpaca-bot\ORG_BOT_UNIFIED\ops\audit\PAPER_TBOT_FOREGROUND_CAPTURE_20260303_115343"

New-Item -ItemType Directory -Force $LOGDIR | Out-Null
New-Item -ItemType Directory -Force (Join-Path $RUNROOT "state\locks") | Out-Null
New-Item -ItemType Directory -Force $ADIR | Out-Null

# Deterministic env
$env:TBOT_ROOT=$ROOT
$env:TBOT_CODE=$CODE
$env:TBOT_RUNROOT=$RUNROOT
$env:TBOT_LOG_ROOT=$LOGDIR

# Force traceback visibility
$env:PYTHONFAULTHANDLER="1"
$env:PYTHONUNBUFFERED="1"

Write-Host "ROOT=$ROOT"
Write-Host "CODE=$CODE"
Write-Host "RUNROOT=$RUNROOT"
Write-Host "LOGDIR=$LOGDIR"
Write-Host "PY=$PY"
Write-Host "AUDITDIR=$ADIR"

if(!(Test-Path $PY)){ throw "MISSING_PYTHON=$PY" }

# Best-effort stale lock cleanup (only if pid dead)
$lock = Join-Path (Join-Path $RUNROOT "state\locks") "TBOT_SINGLE_INSTANCE_PAPER.lock"
if(Test-Path $lock){
  Write-Host "LOCK_EXISTS_BEFORE=$lock"
  try{
    $j = Get-Content $lock -Raw | ConvertFrom-Json
    $oldPid = [int]$j.pid
    $alive = $false
    try{ $alive = (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) -ne $null } catch {}
    if(-not $alive){
      Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
      Write-Host "LOCK_REMOVED_STALE_PID=$oldPid"
    } else {
      Write-Host "LOCK_HELD_BY_LIVE_PID=$oldPid (expect exit 86)"
    }
  } catch {
    Write-Host "LOCK_PARSE_FAIL (leave it)"
  }
}

Set-Location $CODE

$outAll = Join-Path $ADIR "tbot_all_console.txt"
$outStd = Join-Path $ADIR "tbot_stdout.txt"
$outErr = Join-Path $ADIR "tbot_stderr.txt"

# Run TBOT with SAFE argv (no cmd.exe, no string quoting traps)
$args = @(
  "-X","faulthandler",
  "-u",
  "-m","tbot.main",
  "--run",
  "--iters","999999",
  "--sleep","0.5"
)

Write-Host ("ARGV=" + ($args -join " "))

# Execute + capture
& $PY @args 1> $outStd 2> $outErr
$ec = $LASTEXITCODE

# Build combined file
"
=== STDOUT ===
" | Set-Content -LiteralPath $outAll -Encoding UTF8
if(Test-Path $outStd){ Get-Content $outStd -ErrorAction SilentlyContinue | Add-Content -LiteralPath $outAll -Encoding UTF8 }
"
=== STDERR ===
" | Add-Content -LiteralPath $outAll -Encoding UTF8
if(Test-Path $outErr){ Get-Content $outErr -ErrorAction SilentlyContinue | Add-Content -LiteralPath $outAll -Encoding UTF8 }

Write-Host ("TBOT_EXITCODE=" + $ec)
Write-Host "OUT_STD=$outStd"
Write-Host "OUT_ERR=$outErr"
Write-Host "OUT_ALL=$outAll"

Write-Host "---- STDERR_TAIL_200 ----"
if(Test-Path $outErr){ Get-Content $outErr -Tail 200 -ErrorAction SilentlyContinue }
Write-Host "---- STDOUT_TAIL_200 ----"
if(Test-Path $outStd){ Get-Content $outStd -Tail 200 -ErrorAction SilentlyContinue }

exit $ec

