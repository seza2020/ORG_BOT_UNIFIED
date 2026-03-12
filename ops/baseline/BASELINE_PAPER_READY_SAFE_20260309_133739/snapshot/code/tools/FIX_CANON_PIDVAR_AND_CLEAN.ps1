param([string]$Root="C:\alpaca-bot\org_bot")

$ErrorActionPreference="Stop"

$Canon = Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
if(!(Test-Path $Canon)){ throw "Missing: $Canon" }

$py   = Join-Path $Root ".venv\Scripts\python.exe"
$lock = Join-Path $Root "logs\locks\RUN_SHADOW.lock"

function Log([string]$m){ $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" }

Log "STEP1: Kill ONLY project venv python..."
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ExecutablePath -eq $py } |
  ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    Log ("KILLED_PID=" + $_.ProcessId)
  }

Log "STEP2: Clear project lock (if any)..."
if(Test-Path $lock){
  Remove-Item $lock -Force -ErrorAction SilentlyContinue
  Log "LOCK_CLEARED"
}else{
  Log "NO_LOCK"
}

Log "STEP3: Backup + patch Canon (replace $pid/$PID tokens)..."
$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$bak = "$Canon.bak_fix_pidvar_$ts"
Copy-Item -Force $Canon $bak
Log ("BACKUP=" + $bak)

$txt = Get-Content -Raw -LiteralPath $Canon

# IMPORTANT: PowerShell is case-insensitive; $pid == $PID (read-only). Replace token "$pid" safely.
$txt2 = [regex]::Replace($txt, '(?i)\$pid\b', '$livePid')

Set-Content -Encoding UTF8 -LiteralPath $Canon -Value $txt2

# Verify: no remaining $pid token
$left = Select-String -LiteralPath $Canon -Pattern '(?i)\$pid\b' -AllMatches -ErrorAction SilentlyContinue
if($left){
  throw "PATCH_FAILED: still found `$pid token(s)."
}

Log "VERIFY: showing first hits for LIVE_PID / HEALTHCHECK markers..."
Select-String -LiteralPath $Canon -Pattern "LIVE_PID=|HEALTHCHECK_OK|FAIL_START:|BLOCK:" -ErrorAction SilentlyContinue |
  Select-Object -First 15 | ForEach-Object { Log $_.Line }

Log "DONE_OK"
