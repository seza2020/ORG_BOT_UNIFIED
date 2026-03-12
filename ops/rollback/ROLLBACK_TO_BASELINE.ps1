$ErrorActionPreference="Stop"

$U="C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE=Join-Path $U "code"
$RUNTIME=Join-Path $U "runtime"

$SNAP="C:\alpaca-bot\ORG_BOT_UNIFIED\ops\snapshots\BASELINE_STABLE_20260304_210004"
$SNAP_CODE=Join-Path $SNAP "code"
$SNAP_RUNTIME=Join-Path $SNAP "runtime"

Write-Host "ROLLBACK START"

robocopy $SNAP_CODE $CODE /MIR /R:2 /W:1 | Out-Null
robocopy $SNAP_RUNTIME $RUNTIME /MIR /R:2 /W:1 | Out-Null

Write-Host "ROLLBACK COMPLETE"
