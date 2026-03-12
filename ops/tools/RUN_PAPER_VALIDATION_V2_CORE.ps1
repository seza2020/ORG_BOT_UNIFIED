param()

$ErrorActionPreference = "Stop"

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE    = Join-Path $U "code"
$PY      = Join-Path $CODE ".venv\Scripts\python.exe"
$CORE    = Join-Path $CODE "tbot\runtime\paper_validation_v2_core.py"
$RUNROOT = Join-Path $U "runtime\paper"

if(!(Test-Path $PY)){ throw "PY_NOT_FOUND=$PY" }
if(!(Test-Path $CORE)){ throw "CORE_NOT_FOUND=$CORE" }

Push-Location $CODE
try {
  $env:PYTHONPATH = $CODE
  $env:TBOT_RUNROOT = $RUNROOT
  & $PY $CORE
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
