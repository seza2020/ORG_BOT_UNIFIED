param([string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper")
$flag = Join-Path $RunRoot 'state\LLM_GATE_DISABLED.flag'
if(Test-Path $flag){
  Remove-Item $flag -Force
  "RESET_OK: removed $flag"
} else {
  "RESET_OK: flag not present"
}
