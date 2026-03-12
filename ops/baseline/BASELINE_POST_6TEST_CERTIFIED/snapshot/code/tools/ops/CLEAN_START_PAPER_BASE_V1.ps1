param(
  [string]$Root="C:\alpaca-bot\ORG_BOT_UNIFIED\code",
  [string]$RunRoot="C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper",
  [int]$WarmupSec=10
)
$ErrorActionPreference="Stop"

$state = Join-Path $RunRoot "state"
$lock  = Join-Path $state "locks\RUN_PAPER_PROFILE.lock"
$pidf  = Join-Path $state "pid.txt"
$hb    = Join-Path $state "heartbeat.json"
$herr  = Join-Path $state "heartbeat_err.txt"

"=== CLEAN_START_BASE ==="
"Root=$Root"
"RunRoot=$RunRoot"

Remove-Item -Force -ErrorAction SilentlyContinue $lock,$pidf,$hb,$herr
"STATE_CLEARED"

$run    = Join-Path $Root "tools\ops\RUN_PAPER_MANAGED_BASE_V1.ps1"
$verify = Join-Path $Root "tools\ops\VERIFY_PAPER_BASE_V1.ps1"

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $run -Root $Root -RunRoot $RunRoot
"RUN_EXIT=$LASTEXITCODE"

Start-Sleep -Seconds $WarmupSec
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $verify -RunRoot $RunRoot -MetaSlaSec 10 -HbSlaSec 10

