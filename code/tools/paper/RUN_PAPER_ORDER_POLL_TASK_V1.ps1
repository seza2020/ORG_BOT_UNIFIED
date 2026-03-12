$ErrorActionPreference="Stop"

function _ts(){ Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
function WL([string]$path,[string]$msg){
  ("[{0}] {1}" -f (_ts),$msg) | Add-Content -LiteralPath $path -Encoding UTF8
}

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

# --- Daily append targets ---
$day = Get-Date -Format "yyyyMMdd"
$OUT = Join-Path $OPSLOG ("ORDER_POLL_OUT_{0}.txt" -f $day)
$ERR = Join-Path $OPSLOG ("ORDER_POLL_ERR_{0}.txt" -f $day)
New-Item -ItemType File -Force -Path $OUT | Out-Null
New-Item -ItemType File -Force -Path $ERR | Out-Null

WL $OUT "ORDER_POLL_TASK_START"
WL $OUT ("CWD=" + (Get-Location).Path)
WL $OUT ("RUNROOT=" + $RUNROOT)

# --- Resolve poll target script (priority order) ---
$paperDir = Join-Path $CODE "tools\paper"
$names = @(
  "POLL_PAPER_ORDERS_V1.ps1",
  "ORDER_POLL_PAPER_V1.ps1",
  "POLL_ORDERS_PAPER_V1.ps1",
  "ORDER_POLL_TASK_IMPL_V1.ps1",
  "ORDER_POLL_V1.ps1"
)

$target = $null
foreach($n in $names){
  $p = Join-Path $paperDir $n
  if(Test-Path -LiteralPath $p){ $target = $p; break }
}

if(-not $target){
  WL $ERR "MISSING_POLL_TARGET (none of known candidates found)"
  WL $ERR ("CANDIDATES=" + ($names -join ";"))
  exit 2
}

WL $OUT ("POLL_TARGET=" + $target)

# --- Per-run temp redirect (avoid handle conflicts) ---
$tmpDir = Join-Path $OPSLOG ("_poll_tmp_" + (Get-Date -Format "yyyyMMdd"))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$tmpOut = Join-Path $tmpDir ("poll_out_{0}.txt" -f $ts)
$tmpErr = Join-Path $tmpDir ("poll_err_{0}.txt" -f $ts)

$timeoutSec = 25
WL $OUT ("LAUNCH poll timeoutSec=" + $timeoutSec)
WL $OUT ("TMP_OUT=" + $tmpOut)
WL $OUT ("TMP_ERR=" + $tmpErr)

# Args for implementation script (best-effort compatible)
$args = @(
  "-NoProfile","-ExecutionPolicy","Bypass",
  "-File",$target,
  "-ProjectRoot",$ROOT,
  "-RunRoot",$RUNROOT
)

$p = Start-Process -FilePath "C:\Program Files\PowerShell\7\pwsh.exe" `
      -ArgumentList $args `
      -WorkingDirectory $CODE `
      -NoNewWindow `
      -PassThru `
      -RedirectStandardOutput $tmpOut `
      -RedirectStandardError  $tmpErr

$ok = $p.WaitForExit($timeoutSec * 1000)
if(-not $ok){
  WL $OUT "POLL_TIMEOUT -> terminating child"
  try{ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
  WL $ERR ("POLL_TIMEOUT pid=" + $p.Id + " timeoutSec=" + $timeoutSec)
  if(Test-Path $tmpErr){ Get-Content $tmpErr -ErrorAction SilentlyContinue | Add-Content -LiteralPath $ERR -Encoding UTF8 }
  exit 124
}

WL $OUT ("CHILD_EXITCODE=" + $p.ExitCode)

# Append child outputs into daily logs
if(Test-Path $tmpOut){ Get-Content $tmpOut -ErrorAction SilentlyContinue | Add-Content -LiteralPath $OUT -Encoding UTF8 }
if(Test-Path $tmpErr){ Get-Content $tmpErr -ErrorAction SilentlyContinue | Add-Content -LiteralPath $ERR -Encoding UTF8 }

exit $p.ExitCode
