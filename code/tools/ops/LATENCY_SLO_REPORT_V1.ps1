param(
  [string]$ProjectRoot,
  [string]$RunRoot,
  [string]$BackupDir,
  [string]$IsoDayOverride="",
  [string]$OutPath="",
  [string]$ErrPath=""
)
$ErrorActionPreference="Stop"
function LOut([string]$s){ if($OutPath){ Add-Content -Encoding UTF8 -Path $OutPath -Value $s } else { Write-Host $s } }
function LErr([string]$s){ if($ErrPath){ Add-Content -Encoding UTF8 -Path $ErrPath -Value $s } else { Write-Host $s } }
function ReadJsonl([string]$p){
  $arr=@(); if(!(Test-Path $p)){ return $arr }
  foreach($ln in (Get-Content -Encoding UTF8 $p)){
    $t=$ln.Trim(); if(!$t){ continue }
    try { $arr += ($t | ConvertFrom-Json) } catch {}
  }
  return $arr
}
try{
  if([string]::IsNullOrWhiteSpace($BackupDir) -or !(Test-Path $BackupDir)){
    $opsRoot = Join-Path $RunRoot "logs\ops"
    $BackupDir = (Get-ChildItem $opsRoot -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1).FullName
  }
  if([string]::IsNullOrWhiteSpace($BackupDir) -or !(Test-Path $BackupDir)){ LErr "LATENCY_SLO_FAIL=BK_NOT_FOUND"; exit 0 }
  $ymd = ($BackupDir -replace "^.*FREEZE_BACKUP_(\d{8}).*","$1")
  if($ymd -notmatch "^\d{8}$"){
    if($IsoDayOverride -match "^\d{4}-\d{2}-\d{2}$"){ $ymd = $IsoDayOverride.Replace("-","") }
    else { $ymd = (Get-Date).ToString("yyyyMMdd") }
  }
  $ana = Join-Path $RunRoot "logs\analytics"; New-Item -ItemType Directory -Force -Path $ana | Out-Null
  $meta = Join-Path $BackupDir ("meta_{0}.jsonl" -f $ymd)
  if(!(Test-Path $meta)){ $meta = Join-Path $RunRoot "logs\meta.jsonl" }
  $ev = ReadJsonl $meta
  $hb = @($ev | Where-Object { $_.kind -eq "heartbeat" -and $_.ts })
  $tsList=@()
  foreach($h in $hb){ try { $tsList += [datetimeoffset]::Parse([string]$h.ts).UtcDateTime } catch {} }
  $tsList = @($tsList | Sort-Object)
  $gaps=@()
  for($i=1;$i -lt $tsList.Count;$i++){ $gaps += ([int](([datetime]$tsList[$i]-[datetime]$tsList[$i-1]).TotalSeconds)) }
  $maxGap = if($gaps.Count){ ($gaps | Measure-Object -Maximum).Maximum } else { 0 }
  $gapOver120 = @($gaps | Where-Object { $_ -ge 120 }).Count
  $gapOver300 = @($gaps | Where-Object { $_ -ge 300 }).Count
  $inTrue=0; $inTot=0
  foreach($h in $hb){
    try { $p=$h.payload } catch { $p=$null }
    if($null -ne $p){ $inTot++; if([bool]$p.in_session){ $inTrue++ } }
  }
  $inRatio = if($inTot -gt 0){ [math]::Round(($inTrue/$inTot),4) } else { $null }
  $sk = @($ev | Where-Object { $_.kind -eq "signal_skip" })
  $reasonCounts=@{}
  foreach($s in $sk){
    $r=""; try { $r=[string]$s.payload.reason } catch {}
    if([string]::IsNullOrWhiteSpace($r)){ $r="(unknown)" }
    if(!$reasonCounts.ContainsKey($r)){ $reasonCounts[$r]=0 }
    $reasonCounts[$r]++
  }
  $top = @($reasonCounts.GetEnumerator() | Sort-Object Value -Desc | Select -First 8 | ForEach-Object { @{reason=$_.Key; count=$_.Value} })
  $status="PASS"; if($maxGap -ge 300 -or $gapOver300 -gt 0){ $status="FAIL" } elseif($maxGap -ge 180 -or $gapOver120 -gt 0){ $status="WARN" }
  $rep=@{
    ymd=$ymd; meta_path=$meta; heartbeat_count=$hb.Count;
    max_heartbeat_gap_sec=$maxGap; gaps_over_120=$gapOver120; gaps_over_300=$gapOver300;
    in_session_ratio=$inRatio; signal_skip_total=$sk.Count; top_skip_reasons=$top;
    slo_status=$status;
    notes=@("هدف: کشف stall/کندی loop و علت از دست رفتن فرصت‌ها.")
  }
  $outJ_bk = Join-Path $BackupDir ("LATENCY_SLO_{0}.json" -f $ymd)
  $outM_bk = Join-Path $BackupDir ("LATENCY_SLO_{0}.md" -f $ymd)
  $outJ_an = Join-Path $ana ("LATENCY_SLO_{0}.json" -f $ymd)
  $outM_an = Join-Path $ana ("LATENCY_SLO_{0}.md" -f $ymd)
  ($rep | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 -Path $outJ_bk
  Copy-Item $outJ_bk $outJ_an -Force
  @(
    ("# LATENCY SLO {0}" -f $ymd),
    "",
    ("- slo_status: {0}" -f $status),
    ("- heartbeat_count: {0}" -f $rep.heartbeat_count),
    ("- max_heartbeat_gap_sec: {0}" -f $maxGap),
    ("- gaps_over_120: {0}" -f $gapOver120),
    ("- gaps_over_300: {0}" -f $gapOver300),
    ("- in_session_ratio: {0}" -f $inRatio),
    ("- signal_skip_total: {0}" -f $rep.signal_skip_total),
    "",
    "## Top skip reasons"
  ) + ($top | ForEach-Object { "- $($_.reason): $($_.count)" }) | Set-Content -Encoding UTF8 -Path $outM_bk
  Copy-Item $outM_bk $outM_an -Force
  LOut ("LATENCY_SLO_STATUS=" + $status + " ymd=" + $ymd)
} catch { LErr ("LATENCY_SLO_EXC=" + $_.Exception.Message) }
