param([string]$Root="C:\alpaca-bot\org_bot")

$ErrorActionPreference="Stop"

$Py   = Join-Path $Root ".venv\Scripts\python.exe"
$Canon= Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
$Lock = Join-Path $Root "logs\locks\RUN_SHADOW.lock"

function Log([string]$m){
  $ts=(Get-Date -Format "HH:mm:ss")
  Write-Host "[$ts] $m"
}

if(!(Test-Path $Py)){ throw "Missing PY: $Py" }
if(!(Test-Path $Canon)){ throw "Missing CANON: $Canon" }

Log "KILL: all org_bot venv python (project-only)"
Get-Process python -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -eq $Py } |
  ForEach-Object {
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    Log ("KILLED_PID=" + $_.Id)
  }

Start-Sleep 2

Log "CLEAR LOCK (if any)"
if(Test-Path $Lock){
  Remove-Item $Lock -Force -ErrorAction SilentlyContinue
  Log "LOCK_CLEARED"
}else{
  Log "NO_LOCK"
}

Log "START CANON (one instance)"
pwsh -NoProfile -ExecutionPolicy Bypass -File $Canon
Log ("CANON_EXITCODE=" + $LASTEXITCODE)

Start-Sleep 3

Log "VERIFY: count of project python"
$procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ExecutablePath -eq $Py } |
  Select-Object ProcessId,CommandLine

$procs | Format-Table -Auto | Out-String | Write-Host
Log ("COUNT=" + ($procs | Measure-Object).Count)

Log "VERIFY: lock"
Log ("LOCK_EXISTS=" + (Test-Path $Lock))
if(Test-Path $Lock){
  "LOCK_CONTENT:" | Write-Host
  Get-Content $Lock | Write-Host
}
