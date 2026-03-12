param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$ProfilePath="C:\alpaca-bot\org_bot\tools\profiles\paper.profile.json",
  [int]$Force=1
)

$env:TBOT_LOCAL_DECISION_URL="http://127.0.0.1:8899/decision"
$env:TBOT_ALLOW_OUT_OF_SESSION="1"

Write-Host ("[WRAP] TBOT_LOCAL_DECISION_URL=" + $env:TBOT_LOCAL_DECISION_URL)
Write-Host ("[WRAP] TBOT_ALLOW_OUT_OF_SESSION=" + $env:TBOT_ALLOW_OUT_OF_SESSION)

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass `
  -File (Join-Path $ProjectRoot "tools\RUN_PAPER_SHADOW_CANON_V1.ps1") `
  -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -Force $Force
exit $LASTEXITCODE
