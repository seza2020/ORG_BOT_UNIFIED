param([string]\C:\alpaca-bot\org_bot_runtime\paper="C:\alpaca-bot\org_bot_runtime\paper")
\Stop="Stop"
function AgeSec([string]\){
  if(!(Test-Path -LiteralPath \)){ return \ }
  return [int](([DateTime]::UtcNow-(Get-Item -LiteralPath \).LastWriteTimeUtc).TotalSeconds)
}
\ = Join-Path \C:\alpaca-bot\org_bot_runtime\paper "state"
\    = Join-Path \ "heartbeat.json"
\ = Join-Path \ "hb_touch.txt"
\   = Join-Path \ "heartbeat_err.txt"
\  = Join-Path \ "pid.txt"
\  = Join-Path \C:\alpaca-bot\org_bot_runtime\paper "logs\meta.jsonl"

"RUNROOT=\C:\alpaca-bot\org_bot_runtime\paper"
"HB_EXISTS=" + (Test-Path \)
"TOUCH_EXISTS=" + (Test-Path \)
"ERR_EXISTS=" + (Test-Path \)
"PID_EXISTS=" + (Test-Path \)
"META_EXISTS=" + (Test-Path \)

"HB_AGE="    + (AgeSec \ ?? -1)
"TOUCH_AGE=" + (AgeSec \ ?? -1)
"ERR_AGE="   + (AgeSec \ ?? -1)
"META_AGE="  + (AgeSec \ ?? -1)

if(Test-Path \){ "PID=" + (Get-Content -Raw -LiteralPath \).Trim() }
if(Test-Path \){ "
--- heartbeat_err.txt ---"; Get-Content -LiteralPath \ -Tail 50 }
if(Test-Path \){ "
--- heartbeat.json ---"; Get-Content -LiteralPath \ -Tail 5 }
