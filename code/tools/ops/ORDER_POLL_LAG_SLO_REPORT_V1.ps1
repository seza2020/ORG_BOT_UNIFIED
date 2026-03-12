param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$BackupDir="",
  [string]$IsoDayOverride="",
  [int]$WarnGapSec=240,
  [int]$FailGapSec=600,
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

if([string]::IsNullOrWhiteSpace($OutPath)){ $OutPath = Join-Path $opsRoot ("POLL_LAG_SLO_OUT_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss")) }
if([string]::IsNullOrWhiteSpace($ErrPath)){ $ErrPath = Join-Path $opsRoot ("POLL_LAG_SLO_ERR_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss")) }
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

$pollFiles = Get-ChildItem $opsRoot -File -Filter ("ORDER_POLL_OUT_{0}_*.txt" -f $ymd) -ErrorAction SilentlyContinue
if(!$pollFiles -or $pollFiles.Count -eq 0){
  $rep=@{ ymd=$ymd; isoday=$IsoDayOverride; status="WARN"; reason="no_poll_files"; warn_gap_sec=$WarnGapSec; fail_gap_sec=$FailGapSec }
  $j=Join-Path $bk ("ORDER_POLL_LAG_SLO_{0}.json" -f $ymd)
  $m=Join-Path $bk ("ORDER_POLL_LAG_SLO_{0}.md" -f $ymd)
  ($rep | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 -Path $j
  @("# ORDER POLL LAG SLO $ymd","", "WARN: no poll files found.") | Set-Content -Encoding UTF8 -Path $m
  Copy-Item $j (Join-Path $anaRoot ("ORDER_POLL_LAG_SLO_{0}.json" -f $ymd)) -Force
  Copy-Item $m (Join-Path $anaRoot ("ORDER_POLL_LAG_SLO_{0}.md" -f $ymd)) -Force
  "ORDER_POLL_LAG_SLO_STATUS=WARN reason=no_poll_files" | Add-Content -Encoding UTF8 -Path $OutPath
  exit 0
}

$stamps=@()
foreach($f in $pollFiles){
  $mm=[regex]::Match($f.Name,'ORDER_POLL_OUT_(\d{8})_(\d{6})')
  if($mm.Success){
    $dt=[datetime]::ParseExact(($mm.Groups[1].Value+$mm.Groups[2].Value),"yyyyMMddHHmmss",$null)
    $stamps += $dt
  } else {
    $stamps += $f.LastWriteTime
  }
}
$stamps = $stamps | Sort-Object
$maxGap=0
for($i=1;$i -lt $stamps.Count;$i++){
  $gap = ($stamps[$i] - $stamps[$i-1]).TotalSeconds
  if($gap -gt $maxGap){ $maxGap=[int]$gap }
}
$status="PASS"
if($maxGap -ge $FailGapSec){ $status="FAIL" } elseif($maxGap -ge $WarnGapSec){ $status="WARN" }

$rep=@{
  ymd=$ymd; isoday=$IsoDayOverride; status=$status;
  poll_files=$pollFiles.Count;
  max_gap_sec=$maxGap;
  warn_gap_sec=$WarnGapSec;
  fail_gap_sec=$FailGapSec;
  notes="Computed from ORDER_POLL_OUT_* timestamps; large gaps imply missed sync."
}

$j=Join-Path $bk ("ORDER_POLL_LAG_SLO_{0}.json" -f $ymd)
$m=Join-Path $bk ("ORDER_POLL_LAG_SLO_{0}.md" -f $ymd)
($rep | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 -Path $j
@(
  "# ORDER POLL LAG SLO $ymd","",
  "- status: $status",
  "- poll_files: $($rep.poll_files)",
  "- max_gap_sec: $maxGap",
  "- warn_gap_sec: $WarnGapSec",
  "- fail_gap_sec: $FailGapSec"
) | Set-Content -Encoding UTF8 -Path $m
Copy-Item $j (Join-Path $anaRoot ("ORDER_POLL_LAG_SLO_{0}.json" -f $ymd)) -Force
Copy-Item $m (Join-Path $anaRoot ("ORDER_POLL_LAG_SLO_{0}.md" -f $ymd)) -Force
("ORDER_POLL_LAG_SLO_STATUS=" + $status + " max_gap_sec=" + $maxGap) | Add-Content -Encoding UTF8 -Path $OutPath
exit 0
