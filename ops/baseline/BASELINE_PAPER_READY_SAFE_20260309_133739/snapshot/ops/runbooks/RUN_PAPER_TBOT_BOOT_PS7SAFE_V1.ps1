# RUN_PAPER_TBOT_BOOT_PS7SAFE_V1.ps1  (REWRITE V5 - deterministic, PS7 safe)
# Goal: start TBOT paper loop with strict, stable paths + runbook mutex.
$ErrorActionPreference="Stop"

# --- MUTEX GUARD (runbook-level single instance) ---
try {
  $mName = "Local\TBOT_RUNBOOK_ORG_UNIFIED_PAPER"
  $global:__tbot_mutex = [System.Threading.Mutex]::new($false, $mName)
  $acq = $global:__tbot_mutex.WaitOne([TimeSpan]::FromSeconds(0))
  if(-not $acq){
    Write-Host ("[RUNBOOK_MUTEX] BUSY name=" + $mName + " -> exit 92")
    exit 92
  }
  Write-Host ("[RUNBOOK_MUTEX] ACQUIRED name=" + $mName)
} catch {
  Write-Host ("[RUNBOOK_MUTEX] EXCEPTION -> fail-open " + $_.Exception.Message)
}

# --- ROOT/CODE/RUNROOT deterministic ---
$ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"
if(-not (Test-Path $ROOT)){ throw "ROOT_NOT_FOUND=$ROOT" }

$CODE   = Join-Path $ROOT "code"
$RUNROOT= Join-Path $ROOT "runtime\paper"
$LOGDIR = Join-Path $RUNROOT "logs"
$LOCKDIR= Join-Path $RUNROOT "state\locks"

foreach($p in @($CODE,$RUNROOT,$LOGDIR,$LOCKDIR)){
  if(-not (Test-Path $p)){ New-Item -ItemType Directory -Force $p | Out-Null }
}

Write-Host ("ROOT=" + $ROOT)
Write-Host ("CODE=" + $CODE)
Write-Host ("RUNROOT=" + $RUNROOT)
Write-Host ("LOGDIR=" + $LOGDIR)

# --- pick python ---
$PY = Join-Path $CODE ".venv\Scripts\python.exe"
if(!(Test-Path $PY)){ $PY = Join-Path $ROOT ".venv\Scripts\python.exe" }
if(!(Test-Path $PY)){ throw "MISSING_PYTHON_VENV (expected $CODE\.venv or $ROOT\.venv)" }
Write-Host ("PY=" + $PY)

# --- env bind (hard) ---
Set-Location $CODE
$env:PYTHONPATH     = $CODE
$env:TBOT_ROOT      = $ROOT
$env:TBOT_CODE      = $CODE
$env:TBOT_RUNROOT   = $RUNROOT
$env:TBOT_LOG_ROOT  = $LOGDIR
$env:TBOT_OPS_LOG   = (Join-Path $LOGDIR "ops")

# --- kill stale TBOT (safe) ---
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match "tbot\.main" -and $_.CommandLine -match "ORG_BOT_UNIFIED" } |
  ForEach-Object { try{ Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }

Start-Sleep -Seconds 1

# --- audit files ---
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ADIR  = Join-Path $ROOT ("ops\audit\PAPER_TBOT_BOOT_" + $stamp)
New-Item -ItemType Directory -Force $ADIR | Out-Null
$out = Join-Path $ADIR "tbot_stdout.txt"
$err = Join-Path $ADIR "tbot_stderr.txt"

# --- start TBOT (paper loop) ---
$args = @("-m","tbot.main","--run","--iters","999999","--sleep","0.5")
$p = Start-Process -FilePath $PY -ArgumentList $args -PassThru -NoNewWindow `
      -RedirectStandardOutput $out -RedirectStandardError $err

Start-Sleep -Seconds 6

# --- verify ---
$py = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
      Where-Object { $_.CommandLine -match "tbot\.main" -and $_.CommandLine -match "ORG_BOT_UNIFIED" } |
      Select-Object ProcessId,ParentProcessId,CreationDate,CommandLine

Write-Host ("AUDITDIR=" + $ADIR)
Write-Host ("STARTED_PID=" + $p.Id)
Write-Host ("TBOT_PY_COUNT_NOW=" + $py.Count)
if(Test-Path $err){ Write-Host ("STDERR_SIZE_BYTES=" + (Get-Item $err).Length) }

if($py){
  $py | Format-List
  Write-Host "OK_TBOT_RUNNING"
} else {
  Write-Host "TBOT_NOT_RUNNING"
  if(Test-Path $err){ Get-Content $err -Tail 200 }
  exit 2
}
