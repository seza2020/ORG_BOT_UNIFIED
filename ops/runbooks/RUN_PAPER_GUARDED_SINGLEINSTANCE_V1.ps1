# === DUALPID_GUARD_V4 (Institutional) ===
$ErrorActionPreference="Stop"
Add-Type -AssemblyName System.Threading

function New-Or-BlockMutex([string]$name){
  $createdNew = $false
  $m = New-Object System.Threading.Mutex($true, $name, [ref]$createdNew)
  if(-not $createdNew){
    Write-Host ("DUALPID_GUARD: BLOCK_MUTEX_EXISTS name=" + $name)
    exit 0
  }
  return $m
}

function New-AtomicLockfile([string]$path){
  New-Item -ItemType Directory -Force (Split-Path $path -Parent) | Out-Null
  try {
    $fs = [System.IO.File]::Open($path,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
    $sw = New-Object System.IO.StreamWriter($fs)
    $sw.WriteLine("TS=20260305_113140")
    $sw.WriteLine("PWSH_PID=19820")
    $sw.Flush(); $sw.Dispose(); $fs.Dispose()
    return $true
  } catch {
    Write-Host ("DUALPID_GUARD: BLOCK_LOCK_EXISTS path=" + $path + " err=" + $_.Exception.Message)
    return $false
  }
}

$__mutex = New-Or-BlockMutex "Global\ORG_BOT_UNIFIED_PAPER_SINGLEINSTANCE_V4"
if(-not (New-AtomicLockfile "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\state\locks\PAPER_RUNTIME_SINGLEINSTANCE_V4.lock")){ try{ $__mutex.ReleaseMutex() }catch{}; try{ $__mutex.Dispose() }catch{}; exit 0 }

try {
  # Continue original runbook...
} finally {
  try { if(Test-Path "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\state\locks\PAPER_RUNTIME_SINGLEINSTANCE_V4.lock"){ Remove-Item -LiteralPath "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\state\locks\PAPER_RUNTIME_SINGLEINSTANCE_V4.lock" -Force } } catch {}
  try { $__mutex.ReleaseMutex() } catch {}
  try { $__mutex.Dispose() } catch {}
}
# === /DUALPID_GUARD_V4 ===

param()

$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE="$ROOT\code"
$PY="$CODE\.venv\Scripts\python.exe"

$LOG="$ROOT\runtime\paper\logs\process_guard.jsonl"
$LOCKFILE="$ROOT\runtime\paper\tbot_runtime.lock"

function log([string]$msg, [hashtable]$kv){
  $o=[pscustomobject]@{
    ts=(Get-Date).ToString("o")
    msg=$msg
    kv=$kv
  }
  $o | ConvertTo-Json -Compress | Add-Content -LiteralPath $LOG -Encoding UTF8
}

# -------- GLOBAL MUTEX --------
$mutexName="Global\ORG_BOT_UNIFIED_PAPER_RUNTIME"
$created=$false
$mutex=New-Object System.Threading.Mutex($true,$mutexName,[ref]$created)

if(-not $created){
  log "mutex_exists_exit" @{ mutex=$mutexName; pwshPid=$PID }
  Write-Host "GUARD_LOCK_DENIED (MUTEX) -> EXIT"
  exit 0
}

try {
  # -------- FILE LOCK (PID+TS) --------
  if(Test-Path $LOCKFILE){
    log "lockfile_exists_exit" @{ lockfile=$LOCKFILE; pwshPid=$PID }
    Write-Host "GUARD_LOCK_DENIED (LOCKFILE) -> EXIT"
    exit 0
  }

  $content = "ts=$((Get-Date).ToString('o'))`nlauncher_pwsh_pid=$PID"
  Set-Content -LiteralPath $LOCKFILE -Value $content -Encoding UTF8

  Set-Location -LiteralPath $CODE
  $env:PYTHONPATH=$CODE

  # Precheck
  $smoke = & $PY -m tbot.main --smoke 2>&1
  log "smoke" @{ out=$smoke }

  log "runtime_start" @{ py=$PY; cwd=$CODE; pythonpath=$env:PYTHONPATH }

  & $PY -m tbot.main --run

  $exit=$LASTEXITCODE
  log "runtime_exit" @{ exitcode=$exit }
  exit $exit
}
finally{
  try { if(Test-Path $LOCKFILE){ Remove-Item -LiteralPath $LOCKFILE -Force } } catch {}
  try { $mutex.ReleaseMutex() } catch {}
  try { $mutex.Dispose() } catch {}
}

