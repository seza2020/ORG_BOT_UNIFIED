param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$BackupDir="",
  [string]$IsoDayOverride="",
  [int]$WarnSec=180,
  [int]$FailSec=600,
  [string]$OutPath="",
  [string]$ErrPath=""
)
$ErrorActionPreference="Stop"

function FindLatestBackup([string]$opsRoot){
  Get-ChildItem $opsRoot -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
    Sort LastWriteTime -Desc | Select -First 1
}
function GetYmdFromName([string]$name){
  $m=[regex]::Match($name,'FREEZE_BACKUP_(\d{8})')
  if($m.Success){ return $m.Groups[1].Value }
  return ""
}
function EnsureFile([string]$p){ if(!(Test-Path $p)){ "" | Set-Content -Encoding UTF8 -Path $p } }

$opsRoot = Join-Path $RunRoot "logs\ops"
$anaRoot = Join-Path $RunRoot "logs\analytics"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $anaRoot | Out-Null

if([string]::IsNullOrWhiteSpace($OutPath)){ $OutPath = Join-Path $opsRoot ("D2O_SLO_OUT_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss")) }
if([string]::IsNullOrWhiteSpace($ErrPath)){ $ErrPath = Join-Path $opsRoot ("D2O_SLO_ERR_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss")) }
EnsureFile $ErrPath

$bkObj=$null
if(-not [string]::IsNullOrWhiteSpace($BackupDir) -and (Test-Path $BackupDir)){ $bkObj=Get-Item $BackupDir } else { $bkObj=FindLatestBackup $opsRoot }
if(!$bkObj){ throw "NO_BACKUP_DIR_FOUND" }
$bk=$bkObj.FullName
$ymd=GetYmdFromName $bkObj.Name
if([string]::IsNullOrWhiteSpace($ymd)){ throw "CANNOT_PARSE_YMD" }

if([string]::IsNullOrWhiteSpace($IsoDayOverride)){
  $IsoDayOverride = "{0}-{1}-{2}" -f $ymd.Substring(0,4),$ymd.Substring(4,2),$ymd.Substring(6,2)
}

$meta = Join-Path $bk ("meta_{0}.jsonl" -f $ymd)
if(!(Test-Path $meta)){ $meta = Join-Path $RunRoot "logs\meta.jsonl" }

$firstDecision=$null; $firstOrder=$null
$ordersCount=0; $decisionsCount=0

if(Test-Path $meta){
  foreach($ln in Get-Content -Encoding UTF8 $meta){
    if([string]::IsNullOrWhiteSpace($ln)){ continue }
    $ev=$null
    try{ $ev = $ln | ConvertFrom-Json } catch { continue }
    $kind=[string]$ev.kind
    $ts=[string]$ev.ts
    if([string]::IsNullOrWhiteSpace($ts)){ continue }
    $dt=$null
    try{ $dt=[datetime]::Parse($ts) } catch { continue }

    if($kind -eq "shadow_accept"){
      $decisionsCount++
      if($null -eq $firstDecision){ $firstDecision=$dt }
    }
    if($kind -match 'order' -or $kind -match 'submit' -or $kind -match 'fill'){
      $ordersCount++
      if($null -eq $firstOrder){ $firstOrder=$dt }
    }
  }
}

$status="WARN"; $latSec=$null; $reason="no_orders_detected"
if($firstDecision -and $firstOrder){
  $latSec=[int](($firstOrder - $firstDecision).TotalSeconds)
  $reason="ok"
  $status="PASS"
  if($latSec -ge $FailSec){ $status="FAIL" } elseif($latSec -ge $WarnSec){ $status="WARN" }
} elseif(!$firstDecision) {
  $reason="no_decisions_detected"
}

$rep=@{
  ymd=$ymd; isoday=$IsoDayOverride; status=$status; reason=$reason;
  decision_to_order_sec=$latSec;
  warn_sec=$WarnSec; fail_sec=$FailSec;
  counts=@{ shadow_accept=$decisionsCount; order_like=$ordersCount };
  notes="Best-effort from meta.jsonl. Once PAPER execution is enabled, order_like should appear."
}

$j=Join-Path $bk ("DECISION_TO_ORDER_SLO_{0}.json" -f $ymd)
$m=Join-Path $bk ("DECISION_TO_ORDER_SLO_{0}.md" -f $ymd)
($rep | ConvertTo-Json -Depth 30) | Set-Content -Encoding UTF8 -Path $j
@(
  "# DECISION → ORDER SLO $ymd","",
  "- status: $status",
  "- reason: $reason",
  "- decision_to_order_sec: $latSec",
  "- warn_sec: $WarnSec",
  "- fail_sec: $FailSec",
  "- shadow_accept: $decisionsCount",
  "- order_like: $ordersCount"
) | Set-Content -Encoding UTF8 -Path $m
Copy-Item $j (Join-Path $anaRoot ("DECISION_TO_ORDER_SLO_{0}.json" -f $ymd)) -Force
Copy-Item $m (Join-Path $anaRoot ("DECISION_TO_ORDER_SLO_{0}.md" -f $ymd)) -Force
("DECISION_TO_ORDER_SLO_STATUS=" + $status + " sec=" + $latSec + " reason=" + $reason) | Add-Content -Encoding UTF8 -Path $OutPath
exit 0
