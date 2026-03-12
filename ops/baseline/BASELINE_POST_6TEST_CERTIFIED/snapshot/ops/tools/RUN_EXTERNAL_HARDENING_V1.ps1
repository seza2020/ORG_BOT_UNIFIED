param()

$ErrorActionPreference = "Stop"

$U      = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE   = Join-Path $U "code"
$PY     = Join-Path $CODE ".venv\Scripts\python.exe"
$RUNROOT= Join-Path $U "runtime\paper"
$HELPER = Join-Path $CODE "tbot\runtime\shadow_hardening_helper.py"

if(!(Test-Path $PY)){ throw "PY_NOT_FOUND=$PY" }
if(!(Test-Path $HELPER)){ throw "HELPER_NOT_FOUND=$HELPER" }

Push-Location $CODE
try {
  $env:PYTHONPATH = $CODE
  $env:TBOT_RUNROOT = $RUNROOT
  & $PY $HELPER
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
