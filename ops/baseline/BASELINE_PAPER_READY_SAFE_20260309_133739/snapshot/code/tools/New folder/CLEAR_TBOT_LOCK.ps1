$LOCK="C:\alpaca-bot\org_bot\logs\locks\RUN_SHADOW.lock"
if(Test-Path $LOCK){
  Remove-Item $LOCK -Force
  "LOCK_CLEARED"
}else{
  "NO_LOCK"
}
