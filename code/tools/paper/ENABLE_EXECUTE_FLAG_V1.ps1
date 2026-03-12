param([string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper")
New-Item -ItemType File -Force -Path (Join-Path $RunRoot 'EXECUTE_ENABLED') | Out-Null
'OK=EXECUTE_ENABLED_CREATED'
