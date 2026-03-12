$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$RECON_RUN="C:\alpaca-bot\ORG_BOT_UNIFIED\ops\tools\RUN_DAILY_RECONCILE.ps1"

Write-Host "=== PAPER_DAY_END ==="
Write-Host "ROOT=$ROOT"
Write-Host "RECON=$RECON_RUN"

# 1) Daily reconcile + audit bundle
& $RECON_RUN
if($LASTEXITCODE -ne 0){ throw "DAILY_RECON_FAILED_EXITCODE=$LASTEXITCODE" }

Write-Host "DAY_END=OK"
