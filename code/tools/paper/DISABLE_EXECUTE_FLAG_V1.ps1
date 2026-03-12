param([string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper")
Remove-Item -Force -ErrorAction SilentlyContinue -Path (Join-Path $RunRoot 'EXECUTE_ENABLED')
'OK=EXECUTE_ENABLED_REMOVED'
