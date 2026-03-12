param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)

$ErrorActionPreference="Stop"

# Canonical env for PAPER
$env:TBOT_ENV="PAPER"
$env:TBOT_RUNROOT=$RunRoot

# Optional: run id for traceability
if([string]::IsNullOrWhiteSpace($env:TBOT_RUN_ID)){
  $env:TBOT_RUN_ID = ("PAPER_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
}

# Delegate to existing runner (already validated exists)
& (Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1")
$ec=$LASTEXITCODE
Write-Host "RUNNER_EXIT_CODE=$ec"
exit $ec
