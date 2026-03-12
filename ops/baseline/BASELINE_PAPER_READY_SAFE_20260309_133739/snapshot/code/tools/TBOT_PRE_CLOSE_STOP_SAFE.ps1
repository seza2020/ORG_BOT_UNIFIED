param([string]$Root = "C:\alpaca-bot\org_bot")

$ErrorActionPreference = "Continue"

$PY = Join-Path $Root ".venv\Scripts\python.exe"
Write-Host ("[PRE_CLOSE_STOP] Root=" + $Root)
Write-Host ("[PRE_CLOSE_STOP] TargetPY=" + $PY)

$alive = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ExecutablePath -eq $PY -and $_.CommandLine -match "tbot\.main" }

if (-not $alive) {
  Write-Host "[PRE_CLOSE_STOP] No matching bot processes found."
  exit 0
}

foreach($p in $alive){
  try {
    Write-Host ("[PRE_CLOSE_STOP] KILL_PID=" + $p.ProcessId)
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  } catch {
    Write-Host ("[PRE_CLOSE_STOP] WARN kill failed pid=" + $p.ProcessId + " :: " + $_.Exception.Message)
  }
}

Write-Host "[PRE_CLOSE_STOP] DONE."
