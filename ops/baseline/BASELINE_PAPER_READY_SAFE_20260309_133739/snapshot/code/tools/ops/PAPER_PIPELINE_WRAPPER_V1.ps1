param(
  [string]$Root = "C:\alpaca-bot\ORG_BOT_UNIFIED\code",
  [string]$RunRoot = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper"
)
$ErrorActionPreference="Stop"
$PW = "C:\Program Files\PowerShell\7\pwsh.exe"
$PRE = "C:\alpaca-bot\ORG_BOT_UNIFIED\code\tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1"
$RUN = "C:\alpaca-bot\ORG_BOT_UNIFIED\code\tools\RUN_PAPER_SHADOW_CANON_V1.ps1"

Write-Host "[PIPELINE] PRECHECK..."
& $PW -NoProfile -ExecutionPolicy Bypass -File $PRE -Root $Root -RunRoot $RunRoot
$preExit = $LASTEXITCODE
Write-Host "[PIPELINE] PRECHECK_EXIT=$preExit"
if($preExit -ne 0){
  Write-Host "[PIPELINE] NO_GO: preflight failed -> runner blocked"
  exit 99
}

Write-Host "[PIPELINE] GO: launching runner..."
& $PW -NoProfile -ExecutionPolicy Bypass -File $RUN
$runExit = $LASTEXITCODE
Write-Host "[PIPELINE] RUNNER_EXIT=$runExit"
exit $runExit

