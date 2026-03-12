$ErrorActionPreference="Stop"
function WL($s){ Write-Host $s }

$BASE="C:\alpaca-bot"
$UNIFIED_ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$UNIFIED_OPS=Join-Path $UNIFIED_ROOT "ops\audit"

$U_OPSLOG=Join-Path $UNIFIED_ROOT "runtime\paper\logs\ops"
$L_OPSLOG="C:\alpaca-bot\org_bot_runtime\paper\logs\ops"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$ADIR=Join-Path $UNIFIED_OPS ("TRACE_PAPER_LOGS_" + $stamp)
New-Item -ItemType Directory -Force $ADIR | Out-Null

function Summ($path,[string]$tag){
  $o=@()
  $o += "TAG=$tag"
  $o += "PATH=$path"
  if(!(Test-Path -LiteralPath $path)){
    $o += "EXISTS=FALSE"
    return $o
  }
  $o += "EXISTS=TRUE"
  $all = Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue
  $o += ("FILES_TOTAL=" + ($all.Count))
  $hits = $all | Where-Object { $_.Name -match "PAPER_.*_(OUT|ERR)_" -or $_.Name -match "PAPER_.*_(OUT|ERR)\.txt" }
  $o += ("PAPER_OUTERR_COUNT=" + ($hits.Count))
  $newest = $all | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($newest){
    $o += ("NEWEST_FILE=" + $newest.FullName)
    $o += ("NEWEST_LASTWRITE=" + $newest.LastWriteTime)
    $o += ("NEWEST_SIZE=" + $newest.Length)
  } else {
    $o += "NEWEST_FILE="
  }
  return $o
}

$u = Summ $U_OPSLOG "UNIFIED"
$l = Summ $L_OPSLOG "LEGACY"

($u + "" + $l) | Set-Content (Join-Path $ADIR "trace.txt") -Encoding utf8

WL ("AUDIT_DIR=" + $ADIR)
WL "NEXT=After you run paper live (when market open), run this trace again and compare LEGACY vs UNIFIED."
