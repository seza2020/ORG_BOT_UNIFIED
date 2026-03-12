param(
  [string]$Mode = "paper"
)

$ErrorActionPreference = "Stop"

$U    = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE = Join-Path $U "code"
$RTP  = Join-Path $U "runtime\paper"
$PY   = Join-Path $CODE ".venv\Scripts\python.exe"
$LOCK = Join-Path $RTP "locks\tbot_main.lock"

$env:PYTHONPATH = $CODE
$env:TBOT_RUNROOT = $RTP
$env:TBOT_RUNTIME_MANAGER = "0"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fams = & (Join-Path $here "Get-TbotFamilies.ps1")

if (@($fams).Count -gt 0) {
  "START_BLOCKED_EXISTING_FAMILY"
  $fams | Format-Table -AutoSize | Out-Host
  exit 0
}

if (Test-Path $LOCK) {
  try { Remove-Item $LOCK -Force -ErrorAction Stop } catch {}
}

$p = Start-Process -FilePath $PY `
  -ArgumentList @("-m","tbot.main","--run") `
  -WorkingDirectory $CODE `
  -PassThru `
  -WindowStyle Hidden

Start-Sleep 8

$fams2 = & (Join-Path $here "Get-TbotFamilies.ps1")
"START_PID=$($p.Id)"
"FAMILY_COUNT=$(@($fams2).Count)"
$fams2 | Format-Table -AutoSize | Out-Host

if (@($fams2).Count -gt 1) {
  "START_FAIL_DUPLICATE_FAMILY"
  exit 2
}

"START_OK_SINGLE_FAMILY"
exit 0
