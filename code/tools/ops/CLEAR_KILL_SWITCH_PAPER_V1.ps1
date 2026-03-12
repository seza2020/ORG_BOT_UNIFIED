param([string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper")
$ErrorActionPreference="Stop"
$p = Join-Path $RunRoot "KILL_SWITCH"
if(Test-Path $p){ Remove-Item $p -Force }
"CLEARED: $p"
