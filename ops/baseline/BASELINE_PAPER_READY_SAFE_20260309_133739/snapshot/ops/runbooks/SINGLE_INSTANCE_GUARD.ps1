$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$RUNROOT=Join-Path $ROOT "runtime\paper"
$LOCKDIR=Join-Path $RUNROOT "state\locks"
$LOG=Join-Path $RUNROOT "logs\single_instance_guard.log"

if(!(Test-Path $LOCKDIR)){ New-Item -ItemType Directory -Force $LOCKDIR | Out-Null }
if(!(Test-Path (Split-Path $LOG))){ New-Item -ItemType Directory -Force (Split-Path $LOG) | Out-Null }

function WL([string]$t){
  Add-Content -LiteralPath $LOG -Value ("{0} {1}" -f (Get-Date -Format s), $t)
}

$procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match "tbot\.main" } |
  Select-Object ProcessId,CreationDate,CommandLine

if(@($procs).Count -le 1){
  WL "OK_SINGLE_INSTANCE"
  return
}

WL ("MULTI_INSTANCE_DETECTED count=" + (@($procs).Count))

# Keep oldest; kill the rest
$keep = $procs | Sort-Object CreationDate | Select-Object -First 1
$kill = $procs | Where-Object { $_.ProcessId -ne $keep.ProcessId }

WL ("KEEP_PID=" + $keep.ProcessId)

foreach($p in @($kill)){
  try{
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    WL ("KILLED_PID=" + $p.ProcessId)
  } catch {
    WL ("KILL_FAILED_PID=" + $p.ProcessId + " ERR=" + $_.Exception.Message)
  }
}
