param()

$ErrorActionPreference="Stop"

# --- Canonical roots ---
$ROOT    = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE    = Join-Path $ROOT "code"
$RUNROOT = Join-Path $ROOT "runtime\paper"
$LOGDIR  = Join-Path $RUNROOT "logs"
$OPSLOG  = Join-Path $LOGDIR "ops"

New-Item -ItemType Directory -Force -Path $OPSLOG | Out-Null

# --- Env hard bind ---
Set-Location $CODE
$env:PYTHONPATH    = $CODE
$env:TBOT_ROOT     = $ROOT
$env:TBOT_CODE     = $CODE
$env:TBOT_RUNROOT  = $RUNROOT
$env:TBOT_LOG_ROOT = $LOGDIR
$env:TBOT_OPS_LOG  = $OPSLOG

# --- Daily logs ---
$day = Get-Date -Format "yyyyMMdd"
$OUT = Join-Path $OPSLOG ("PAPER_EXEC_OUT_{0}.txt" -f $day)
$ERR = Join-Path $OPSLOG ("PAPER_EXEC_ERR_{0}.txt" -f $day)

New-Item -ItemType File -Force -Path $OUT | Out-Null
New-Item -ItemType File -Force -Path $ERR | Out-Null

function WL([string]$s){
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  ("[{0}] {1}" -f $ts, $s) | Add-Content -LiteralPath $OUT -Encoding utf8
}
function WLE([string]$s){
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  ("[{0}] {1}" -f $ts, $s) | Add-Content -LiteralPath $ERR -Encoding utf8
}

WL "EXECUTOR_TASK_START"
WL ("CWD=" + (Get-Location))
WL ("RUNROOT=" + $RUNROOT)

# --- Target exec selection ---
$target = Join-Path $CODE "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"
if(!(Test-Path -LiteralPath $target)){
  WLE ("MISSING_EXECSEL_TARGET=" + $target)
  exit 2
}

# --- Per-run temp redirect (avoid handle conflicts) ---
$tmpDir = Join-Path $OPSLOG ("_exec_tmp_" + (Get-Date -Format "yyyyMMdd"))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$ts2 = Get-Date -Format "yyyyMMdd_HHmmss"
$tmpOut = Join-Path $tmpDir ("execsel_out_{0}.txt" -f $ts2)
$tmpErr = Join-Path $tmpDir ("execsel_err_{0}.txt" -f $ts2)

$timeoutSec = 30
WL ("LAUNCH execsel timeoutSec=" + $timeoutSec)
WL ("TMP_OUT=" + $tmpOut)
WL ("TMP_ERR=" + $tmpErr)

$args = @(
  "-NoProfile","-ExecutionPolicy","Bypass",
  "-File",$target,
  "-ProjectRoot",$ROOT,
  "-RunRoot",$RUNROOT,
  "-DryRun","1"
)

$p = Start-Process -FilePath "C:\Program Files\PowerShell\7\pwsh.exe" `
      -ArgumentList $args `
      -NoNewWindow `
      -PassThru `
      -RedirectStandardOutput $tmpOut `
      -RedirectStandardError  $tmpErr

$ok = $p.WaitForExit($timeoutSec * 1000)

if(-not $ok){
  WL "EXECSEL_TIMEOUT -> terminating child"
  try{ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
  WLE ("EXECSEL_TIMEOUT pid=" + $p.Id + " timeoutSec=" + $timeoutSec)
  if(Test-Path $tmpErr){ Get-Content $tmpErr -ErrorAction SilentlyContinue | Add-Content -LiteralPath $ERR -Encoding utf8 }
  exit 124
}

WL ("CHILD_EXITCODE=" + $p.ExitCode)

# Append child outputs into daily logs
if(Test-Path $tmpOut){
  WL "---- CHILD_STDOUT_BEGIN ----"
  Get-Content $tmpOut -ErrorAction SilentlyContinue | Add-Content -LiteralPath $OUT -Encoding utf8
  WL "---- CHILD_STDOUT_END ----"
}
if(Test-Path $tmpErr){
  WLE "---- CHILD_STDERR_BEGIN ----"
  Get-Content $tmpErr -ErrorAction SilentlyContinue | Add-Content -LiteralPath $ERR -Encoding utf8
  WLE "---- CHILD_STDERR_END ----"
}

exit $p.ExitCode
