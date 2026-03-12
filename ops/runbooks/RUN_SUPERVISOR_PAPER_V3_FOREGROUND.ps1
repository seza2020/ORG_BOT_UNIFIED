$ErrorActionPreference='Continue'
$SUP='C:\alpaca-bot\ORG_BOT_UNIFIED\ops\tasks\TBOT_SUPERVISOR_PAPER_V3.ps1'
$EV='C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\supervisor_events.jsonl'

function _now(){ (Get-Date).ToString('s') }
function _append([string]$p,[string]$s){ try{ Add-Content -Encoding UTF8 -Path $p -Value $s }catch{} }

_append $EV ((@{ts=_now(); kind='supervisor_daemon_start'; mode='foreground'} | ConvertTo-Json -Compress))

while($true){
  try{
    & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $SUP | Out-Null
    Start-Sleep -Seconds 60
  } catch {
    _append $EV ((@{ts=_now(); kind='supervisor_daemon_error'; err=$_.Exception.Message} | ConvertTo-Json -Compress))
    Start-Sleep -Seconds 15
  }
}
