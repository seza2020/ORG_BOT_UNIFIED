$ErrorActionPreference = "Stop"

# === ROOT BINDING (deterministic) ===
$U    = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE = Join-Path $U "code"
$PY   = Join-Path $CODE ".venv\Scripts\python.exe"
$RUN  = "tbot.main"

Set-Location -LiteralPath $CODE
$env:PYTHONPATH = $CODE

# === LOCK FILE (user-space single instance) ===
$lockDir = Join-Path $U "locks"
New-Item -ItemType Directory -Force $lockDir | Out-Null
$lock = Join-Path $lockDir "PAPER_SINGLEINSTANCE.lock"

# Acquire lock by exclusive open; if locked, exit safely.
try {
  $fs = [System.IO.File]::Open($lock, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
} catch {
  Write-Host "LOCK_HELD -> EXIT (another instance running)"
  exit 0
}

# === PRE-KILL (safety) ===
$procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match "tbot\.main" -and $_.CommandLine -match "ORG_BOT_UNIFIED" }
if(($procs | Measure-Object).Count -gt 0){
  foreach($p in $procs){
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch {}
  }
}

# === RUN PAPER ===
Write-Host "RUN_GUARDED: $PY -m $RUN --run"
& $PY -m $RUN --run