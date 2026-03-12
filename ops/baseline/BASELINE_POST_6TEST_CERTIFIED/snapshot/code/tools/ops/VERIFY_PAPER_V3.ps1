param(
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [int]$MetaSlaSec=20,
  [int]$HbSlaSec=20
)
$ErrorActionPreference="Continue"

function AgeSec([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return $null }
  if(!(Test-Path -LiteralPath $p)){ return $null }
  [int](([DateTime]::UtcNow-(Get-Item $p).LastWriteTimeUtc).TotalSeconds)
}

$meta = Join-Path $RunRoot "logs\meta.jsonl"
$hb   = Join-Path $RunRoot "state\heartbeat.json"
$pidf = Join-Path $RunRoot "state\pid.txt"

"=== VERIFY_PAPER_V3 ==="
"TS={0}" -f (Get-Date)
"RUNROOT={0}" -f $RunRoot

$botPidStr = $null
if(Test-Path -LiteralPath $pidf){ $botPidStr = (Get-Content -Raw -LiteralPath $pidf).Trim() }
"PIDFILE={0}" -f ($botPidStr ?? "-")

$alive = $false
if($botPidStr -and ($botPidStr -match '^\d+$') -and ([int]$botPidStr -gt 0)){
  try { Get-Process -Id ([int]$botPidStr) -ErrorAction Stop | Out-Null; $alive=$true } catch { $alive=$false }
}
"ALIVE={0}" -f $alive

$ma = AgeSec $meta
$ha = AgeSec $hb
"META_AGE_SEC={0}" -f ($ma ?? -1)
"HB_AGE_SEC={0}"   -f ($ha ?? -1)

$metaOk = ($ma -ne $null) -and ($ma -le $MetaSlaSec)
$hbOk   = ($ha -ne $null) -and ($ha -le $HbSlaSec)
"META_OK={0}" -f ([int]$metaOk)
"HB_OK={0}"   -f ([int]$hbOk)

if(-not $metaOk){
  "META_TAIL(10):"
  if(Test-Path -LiteralPath $meta){ Get-Content -LiteralPath $meta -Tail 10 }
}
if(-not $hbOk){
  "HB_TAIL(3):"
  if(Test-Path -LiteralPath $hb){ Get-Content -LiteralPath $hb -Tail 3 }
}
"=== END VERIFY ==="
