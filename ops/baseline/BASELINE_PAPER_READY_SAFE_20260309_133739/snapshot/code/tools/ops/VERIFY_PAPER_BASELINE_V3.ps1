param(
  [int]$MetaSlaSec = 10,
  [int]$HbSlaSec   = 10
)

$ErrorActionPreference = "Continue"

# Load paths helper
. "C:\alpaca-bot\org_bot\tools\ops\PATHS.ps1"
$P = Get-Paths

function AgeSec([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return $null }
  if(!(Test-Path -LiteralPath $p)){ return $null }
  [int](([DateTime]::UtcNow - (Get-Item -LiteralPath $p).LastWriteTimeUtc).TotalSeconds)
}

"=== VERIFY_PAPER_BASELINE_V3 ==="
"TS={0}" -f (Get-Date)
"RUNROOT={0}" -f $P.RunRootPaper

$pidf = Join-Path $P.RunRootPaper "state\pid.txt"
$meta = $P.PaperMeta
$hb   = $P.PaperHb
$hbErr= Join-Path $P.RunRootPaper "state\heartbeat_err.txt"

$botPid = $null
if(Test-Path -LiteralPath $pidf){
  $botPid = (Get-Content -Raw -LiteralPath $pidf).Trim()
}
"PIDFILE={0}" -f ($botPid ?? "-")

$alive = $false
if($botPid -and ($botPid -match '^\d+$') -and ([int]$botPid -gt 0)){
  try{ Get-Process -Id ([int]$botPid) -ErrorAction Stop | Out-Null; $alive=$true }catch{ $alive=$false }
}
"ALIVE={0}" -f $alive

$ma = AgeSec $meta
$ha = AgeSec $hb
"#$meta"
"#$hb"
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
  "HB_ERR_TAIL(20):"
  if(Test-Path -LiteralPath $hbErr){ Get-Content -LiteralPath $hbErr -Tail 20 }
}

"=== END VERIFY ==="
