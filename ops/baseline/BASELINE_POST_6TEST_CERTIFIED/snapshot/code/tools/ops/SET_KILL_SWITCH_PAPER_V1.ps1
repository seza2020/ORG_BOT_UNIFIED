param([string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",[string]$Reason="manual")
$ErrorActionPreference="Stop"
$p = Join-Path $RunRoot "KILL_SWITCH"
("ts={0} reason={1}" -f (Get-Date -Format s), $Reason) | Set-Content -Encoding UTF8 -Path $p
"SET: $p"
