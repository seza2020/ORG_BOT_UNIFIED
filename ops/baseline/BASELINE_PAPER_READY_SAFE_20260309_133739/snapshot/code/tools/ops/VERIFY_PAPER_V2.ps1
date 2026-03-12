param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [int]$MetaSlaSec=10,
  [int]$HbSlaSec=10
)
$ErrorActionPreference="Continue"
function AgeSec($p){
  if(!(Test-Path -LiteralPath $p)){ return $null }
  [int](([DateTime]::UtcNow-(Get-Item $p).LastWriteTimeUtc).TotalSeconds)
}
$meta = Join-Path $RunRoot "logs\meta.jsonl"
$hb   = Join-Path $RunRoot "state\heartbeat.json"
$pidf = Join-Path $RunRoot "state\pid.txt"

"=== VERIFY_PAPER_V2 ==="
"TS={0}" -f (Get-Date)
"RUNROOT={0}" -f $RunRoot

$botPid = $null
if(Test-Path $pidf){ $botPid = (Get-Content -Raw $pidf).Trim() }
"PIDFILE={0}" -f ($botPid ?? "-")

$alive = $false
if($botPid -and ($botPid -match '^\d+$') -and ([int]$botPid -gt 0)){
  try { $p = Get-Process -Id ([int]$botPid) -ErrorAction Stop; $alive=$true } catch { $alive=$false }
}
"ALIVE={0}" -f $alive

$ma = AgeSec $meta
$ha = AgeSec $hb
"META_AGE_SEC={0}" -f ($ma ?? -1)
"HB_AGE_SEC={0}" -f ($ha ?? -1)

$metaOk = ($ma -ne $null) -and ($ma -le $MetaSlaSec)
$hbOk   = ($ha -ne $null) -and ($ha -le $HbSlaSec)

"META_OK={0}" -f ([int]$metaOk)
"HB_OK={0}"   -f ([int]$hbOk)

if(-not $metaOk){
  "META_TAIL(20):"
  if(Test-Path $meta){ Get-Content $meta -Tail 20 }
}
if(-not $hbOk){
  "HB_TAIL(5):"
  if(Test-Path $hb){ Get-Content $hb -Tail 5 }
}
"=== END VERIFY ==="
