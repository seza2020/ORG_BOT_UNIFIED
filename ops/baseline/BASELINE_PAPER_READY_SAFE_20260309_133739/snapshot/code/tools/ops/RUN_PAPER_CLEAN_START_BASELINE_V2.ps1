param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [int]$WarmupSec=10,
  [int]$AllowBootOverrun=0
)
$ErrorActionPreference="Stop"

$state = Join-Path $RunRoot "state"
$lock  = Join-Path $state "locks\RUN_PAPER_PROFILE.lock"
$pidf  = Join-Path $state "pid.txt"
$hb    = Join-Path $state "heartbeat.json"
$herr  = Join-Path $state "heartbeat_err.txt"

"=== CLEAN_START_BASELINE_V2 ==="
"Root=$Root"
"RunRoot=$RunRoot"
"AllowBootOverrun=$AllowBootOverrun"

Remove-Item -Force -ErrorAction SilentlyContinue $lock,$pidf,$hb,$herr
"STATE_CLEARED"

$run = Join-Path $Root "tools\ops\RUN_PAPER_MANAGED_BASELINE_V2.ps1"
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $run -Root $Root -RunRoot $RunRoot -AllowBootOverrun $AllowBootOverrun
"MANAGED_EXIT=$LASTEXITCODE"

Start-Sleep -Seconds $WarmupSec

$verify = Join-Path $Root "tools\ops\VERIFY_PAPER_BASELINE_V2.ps1"
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $verify -RunRoot $RunRoot -MetaSlaSec 10 -HbSlaSec 10
