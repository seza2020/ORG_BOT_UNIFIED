$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE="$ROOT\code"
$PY="$ROOT\.venv\Scripts\python.exe"
$RUNROOT="$ROOT\runtime\paper"

Set-Location $CODE
$env:PYTHONPATH=$CODE
$env:TBOT_ROOT=$ROOT
$env:TBOT_RUNROOT=$RUNROOT

& $PY "$ROOT\ops\tools\weekly_gates.py"
