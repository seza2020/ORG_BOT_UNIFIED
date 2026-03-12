param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [int]$WarmupSec=10
)
$ErrorActionPreference="Stop"
function AgeSec($p){
  if(!(Test-Path -LiteralPath $p)){ return $null }
  [int](([DateTime]::UtcNow-(Get-Item $p).LastWriteTimeUtc).TotalSeconds)
}

$runner = Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
$verify = Join-Path $Root "tools\ops\VERIFY_PAPER_V2.ps1"

"=== CLEAN_START_V3 BEGIN ==="
"ROOT=$Root"
"RUNROOT=$RunRoot"

# clear state
Remove-Item -Force -ErrorAction SilentlyContinue `
  (Join-Path $RunRoot "state\locks\RUN_PAPER_PROFILE.lock"),
  (Join-Path $RunRoot "state\pid.txt"),
  (Join-Path $RunRoot "state\heartbeat.json"),
  (Join-Path $RunRoot "state\heartbeat_err.txt")

"STATE_CLEARED"

# run runner
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $runner -Force 1
"RUNNER_EXIT=$LASTEXITCODE"

Start-Sleep -Seconds $WarmupSec

# verify
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $verify -Root $Root -RunRoot $RunRoot -MetaSlaSec 10 -HbSlaSec 10

"=== CLEAN_START_V3 END ==="
