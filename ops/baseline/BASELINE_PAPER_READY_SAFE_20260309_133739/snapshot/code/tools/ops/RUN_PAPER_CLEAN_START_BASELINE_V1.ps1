param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [int]$WarmupSec=10
)
$ErrorActionPreference="Stop"

$runner = Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
$verify = Join-Path $Root "tools\ops\VERIFY_PAPER_V3.ps1"

# Ensure deterministic runroot env (for BOOT_GUARD state)
$env:TBOT_RUNROOT = $RunRoot
$env:TBOT_RUNTIME = $RunRoot

"=== CLEAN_START_BASELINE_V1 ==="
"Root=$Root"
"RunRoot=$RunRoot"

# Clear volatile state only (DO NOT delete logs/meta)
Remove-Item -Force -ErrorAction SilentlyContinue `
  (Join-Path $RunRoot "state\locks\RUN_PAPER_PROFILE.lock"),
  (Join-Path $RunRoot "state\pid.txt"),
  (Join-Path $RunRoot "state\heartbeat.json"),
  (Join-Path $RunRoot "state\heartbeat_err.txt")

"STATE_CLEARED"

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $runner -Force 1
"RUNNER_EXIT=$LASTEXITCODE"

Start-Sleep -Seconds $WarmupSec

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $verify -RunRoot $RunRoot -MetaSlaSec 20 -HbSlaSec 20
"=== END CLEAN ==="
