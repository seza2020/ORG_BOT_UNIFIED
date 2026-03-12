param()
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PY = "C:\alpaca-bot\ORG_BOT_UNIFIED\code\.venv\Scripts\python.exe"
$SCRIPT = "C:\alpaca-bot\ORG_BOT_UNIFIED\ops\analytics\outcome_enrichment\outcome_enrichment_v1.py"

if (!(Test-Path $PY)) { throw "PYTHON_NOT_FOUND=$PY" }
if (!(Test-Path $SCRIPT)) { throw "SCRIPT_NOT_FOUND=$SCRIPT" }

& $PY $SCRIPT
