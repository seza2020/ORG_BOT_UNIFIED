param()
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PY = "C:\alpaca-bot\ORG_BOT_UNIFIED\code\.venv\Scripts\python.exe"
$SCRIPT = "C:\alpaca-bot\ORG_BOT_UNIFIED\ops\analytics\expectancy_engine\expectancy_engine_v2.py"

if (!(Test-Path $PY)) { throw "PYTHON_NOT_FOUND=$PY" }
if (!(Test-Path $SCRIPT)) { throw "SCRIPT_NOT_FOUND=$SCRIPT" }

& $PY $SCRIPT
