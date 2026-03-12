$ErrorActionPreference="Continue"

$PWSH="C:\Program Files\PowerShell\7\pwsh.exe"
$SUP ="C:\alpaca-bot\ORG_BOT_UNIFIED\ops\tasks\TBOT_SUPERVISOR_PAPER_V3.ps1"
$EV  ="C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\supervisor_events.v3.jsonl"
$DLOG="C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\supervisor_daemon.log"

function _now { (Get-Date).ToString("s") }

function _append($p,$s){
 New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
 Add-Content -Encoding UTF8 -Path $p -Value $s
}

_append $DLOG ("==== DAEMON_START " + (_now) + " ====")

$j=@{ts=_now;kind="daemon_start";sup=$SUP} | ConvertTo-Json -Compress
_append $EV $j

while($true){

 try{

  & $PWSH -NoProfile -ExecutionPolicy Bypass -File $SUP 2>&1 |
   ForEach-Object{ _append $DLOG $_ }

  $j=@{ts=_now;kind="daemon_cycle_ok"} | ConvertTo-Json -Compress
  _append $EV $j

  Start-Sleep 30

 }catch{

  $j=@{ts=_now;kind="daemon_cycle_err";err=$_.Exception.Message} | ConvertTo-Json -Compress
  _append $EV $j

  Start-Sleep 15

 }

}
