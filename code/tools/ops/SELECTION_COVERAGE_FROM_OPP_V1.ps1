param(
  [string]$ProjectRoot,
  [string]$RunRoot,
  [string]$BackupDir,
  [string]$IsoDayOverride=""
)
$ErrorActionPreference="Stop"

function Read-Json([string]$p){
  if(!(Test-Path $p)){ return $null }
  try { Get-Content -Raw -Encoding UTF8 $p | ConvertFrom-Json } catch { return $null }
}

# ymd
$ymd=""
if($BackupDir -match 'FREEZE_BACKUP_(\d{8})'){ $ymd=$matches[1] }
elseif($IsoDayOverride -match '^\d{4}-\d{2}-\d{2}$'){ $ymd=$IsoDayOverride.Replace("-","") }
else{ $ymd=(Get-Date).ToString("yyyyMMdd") }

$ana = Join-Path $RunRoot "logs\analytics"
New-Item -ItemType Directory -Force -Path $ana | Out-Null

# OPP_QUEUE
$opp = Join-Path $BackupDir ("OPP_QUEUE_{0}.json" -f $ymd)
$oppObj = Read-Json $opp
if(-not $oppObj){
  $opp = Join-Path $ana ("OPP_QUEUE_{0}.json" -f $ymd)
  $oppObj = Read-Json $opp
}

$candidates=0; $top=@()
if($oppObj){
  try{ $candidates=[int]$oppObj.candidates } catch { $candidates=0 }
  try{ $top=@($oppObj.top200) } catch { $top=@() }
}
if($candidates -le 0){ $candidates=$top.Count }

$top1=0; $top5=0
if($candidates -gt 0){
  $top1=[int][math]::Ceiling($candidates*0.01); if($top1 -lt 1){ $top1=1 }
  $top5=[int][math]::Ceiling($candidates*0.05); if($top5 -lt 1){ $top5=1 }
}

$top1Sid = New-Object "System.Collections.Generic.HashSet[string]"
$top5Sid = New-Object "System.Collections.Generic.HashSet[string]"
for($i=0;$i -lt $top.Count;$i++){
  $sid=""
  try{ $sid=[string]$top[$i].sid } catch { $sid="" }
  if([string]::IsNullOrWhiteSpace($sid)){ continue }
  if($i -lt $top1){ $top1Sid.Add($sid) | Out-Null }
  if($i -lt $top5){ $top5Sid.Add($sid) | Out-Null }
}

# meta shadow_accept
$meta = Join-Path $BackupDir ("meta_{0}.jsonl" -f $ymd)
if(!(Test-Path $meta)){ $meta = Join-Path (Join-Path $RunRoot "logs") "meta.jsonl" }

$selected = New-Object "System.Collections.Generic.HashSet[string]"
if(Test-Path $meta){
  foreach($ln in Get-Content -Encoding UTF8 $meta){
    if($ln -notmatch '"kind"\s*:\s*"shadow_accept"'){ continue }
    try{
      $ev = $ln | ConvertFrom-Json
      $sid2 = [string]$ev.payload.sid
      if(-not [string]::IsNullOrWhiteSpace($sid2)){ $selected.Add($sid2) | Out-Null }
    } catch {}
  }
}

function IntersectCount($a,$b){ $c=0; foreach($x in $a){ if($b.Contains($x)){ $c++ } }; return $c }
$top1Sel = IntersectCount $top1Sid $selected
$top5Sel = IntersectCount $top5Sid $selected

$rep=[ordered]@{
  ymd=$ymd
  inputs=[ordered]@{
    opp_queue=$(if(Test-Path $opp){$opp}else{$null})
    meta=$(if(Test-Path $meta){$meta}else{$null})
  }
  candidates=$candidates
  top1_sid_seen_in_opp=$top1Sid.Count
  top5_sid_seen_in_opp=$top5Sid.Count
  selected_total_sid=$selected.Count
  top1_selected_sid=$top1Sel
  top5_selected_sid=$top5Sel
  top1_coverage_sid=$(if($top1Sid.Count -gt 0){ [double]$top1Sel/[double]$top1Sid.Count } else { $null })
  top5_coverage_sid=$(if($top5Sid.Count -gt 0){ [double]$top5Sel/[double]$top5Sid.Count } else { $null })
}

$jsonName=("SELECTION_COVERAGE_{0}.json" -f $ymd)
$mdName  =("SELECTION_COVERAGE_{0}.md" -f $ymd)
$outJsonBk=Join-Path $BackupDir $jsonName
$outMdBk  =Join-Path $BackupDir $mdName
$outJsonAn=Join-Path $ana $jsonName
$outMdAn  =Join-Path $ana $mdName

($rep | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 -Path $outJsonBk
($rep | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 -Path $outJsonAn

@(
  "# SELECTION COVERAGE (from OPP_QUEUE) $ymd",
  "",
  "- candidates: $candidates",
  "- selected_total_sid: $($rep.selected_total_sid)",
  "- top1_sid_seen_in_opp: $($rep.top1_sid_seen_in_opp)",
  "- top1_selected_sid: $($rep.top1_selected_sid)",
  "- top1_coverage_sid: $($rep.top1_coverage_sid)",
  "- top5_sid_seen_in_opp: $($rep.top5_sid_seen_in_opp)",
  "- top5_selected_sid: $($rep.top5_selected_sid)",
  "- top5_coverage_sid: $($rep.top5_coverage_sid)"
) | Set-Content -Encoding UTF8 -Path $outMdBk
Copy-Item $outMdBk $outMdAn -Force

Write-Host ("OK=SELECTION_COVERAGE_WRITTEN ymd={0} bk={1}" -f $ymd,$BackupDir)
