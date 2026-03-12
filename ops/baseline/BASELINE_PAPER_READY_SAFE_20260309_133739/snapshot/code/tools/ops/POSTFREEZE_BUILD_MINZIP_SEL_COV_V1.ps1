param(
  [string]$ProjectRoot,
  [string]$RunRoot,
  [string]$OutPath,
  [string]$ErrPath,
  [string]$IsoDayOverride=""
)
$ErrorActionPreference="Stop"

function LogOut([string]$s){
  if($OutPath){ Add-Content -Encoding UTF8 -Path $OutPath -Value $s } else { Write-Host $s }
}
function LogErr([string]$s){
  if($ErrPath){ Add-Content -Encoding UTF8 -Path $ErrPath -Value $s } else { Write-Host $s }
}

try{
  # 1) find bk2
  $bk2=$null
  if($OutPath -and (Test-Path $OutPath)){
    $m = Select-String -Path $OutPath -Pattern '^RUNROOT_BACKUP_DIR=' -ErrorAction SilentlyContinue | Select-Object -First 1
    if($m){ $bk2 = $m.Line.Split("=",2)[1].Trim() }
  }
  if([string]::IsNullOrWhiteSpace($bk2)){
    $opsRoot = Join-Path $RunRoot "logs\ops"
    $bk2 = (Get-ChildItem $opsRoot -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1).FullName
  }
  if([string]::IsNullOrWhiteSpace($bk2) -or !(Test-Path $bk2)){
    LogErr "POSTFREEZE_MINZIP2_FAIL=BK_NOT_FOUND"
    exit 0
  }

  # 2) ymd
  $ymd2 = ($bk2 -replace '^.*FREEZE_BACKUP_(\d{8}).*','$1')
  if($ymd2 -notmatch '^\d{8}$'){
    if($IsoDayOverride -match '^\d{4}-\d{2}-\d{2}$'){ $ymd2 = $IsoDayOverride.Replace("-","") }
    else { $ymd2 = (Get-Date).ToString("yyyyMMdd") }
  }

  LogOut ("POSTFREEZE_MINZIP2_BK=" + $bk2 + " ymd=" + $ymd2)

  # 3) ensure SELECTION_COVERAGE exists (rerun writer if needed)
  $scj = Join-Path $bk2 ("SELECTION_COVERAGE_{0}.json" -f $ymd2)
  $scm = Join-Path $bk2 ("SELECTION_COVERAGE_{0}.md" -f $ymd2)
  if(!(Test-Path $scj) -or !(Test-Path $scm)){
    $writer = Join-Path $ProjectRoot "tools\ops\SELECTION_COVERAGE_FROM_OPP_V1.ps1"
    if(Test-Path $writer){
      & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass `
        -File $writer -ProjectRoot $ProjectRoot -RunRoot $RunRoot -BackupDir $bk2 -IsoDayOverride $IsoDayOverride `
        1>> $OutPath 2>> $ErrPath
      LogOut "SELECTION_COVERAGE_RERUN=1"
    } else {
      LogErr "SELECTION_COVERAGE_WRITER_MISSING=1"
    }
  }

  # 4) build curated file list
  $names=@(
    ("QC_{0}.txt" -f $ymd2),
    ("CONFIG_GATES_{0}.txt" -f $ymd2),
    ("CONFIG_GATES_{0}.json" -f $ymd2),
    ("QC_OBS_{0}.txt" -f $ymd2),
    ("EXPECTANCY_GUARD_{0}.txt" -f $ymd2),
    ("EXPECTANCY_GUARD_{0}.json" -f $ymd2),
    ("KPI_{0}.json" -f $ymd2),
    ("KPI_{0}.md" -f $ymd2),
    ("REALIZED_KPI_{0}.json" -f $ymd2),
    ("REALIZED_KPI_{0}.md" -f $ymd2),
    ("POLICY_SNAPSHOT_{0}.md" -f $ymd2),
    ("POLICY_SNAPSHOT_{0}.json" -f $ymd2),
    ("DAILY_BRIEF_{0}.md" -f $ymd2),
    ("FUNNEL_{0}.json" -f $ymd2), ("FUNNEL_{0}.md" -f $ymd2),
    ("SKIP_REASONS_{0}.json" -f $ymd2), ("SKIP_REASONS_{0}.md" -f $ymd2),
    ("EXEC_HEALTH_{0}.json" -f $ymd2), ("EXEC_HEALTH_{0}.md" -f $ymd2),
    ("ALPHA_HEALTH_{0}.json" -f $ymd2), ("ALPHA_HEALTH_{0}.md" -f $ymd2),
    ("MISSED_OPPS_{0}.json" -f $ymd2),
    ("ANOMALY_{0}.json" -f $ymd2), ("ANOMALY_{0}.md" -f $ymd2),
    ("OPP_QUEUE_{0}.json" -f $ymd2),
    ("SELECTION_EFF_{0}.json" -f $ymd2),
    ("TOP1P_{0}.md" -f $ymd2),
    ("SELECTION_COVERAGE_{0}.json" -f $ymd2),
    ("SELECTION_COVERAGE_{0}.md" -f $ymd2),
    ("LATENCY_SLO_{0}.json" -f $ymd2),
    ("LATENCY_SLO_{0}.md" -f $ymd2),
    # LATENCY_SLO_NEED_V4    ("LATENCY_SLO_{0}.json" -f $ymd2),
    ("LATENCY_SLO_{0}.md" -f $ymd2),
    # LATENCY_SLO_NEED_V2    ("LATENCY_SLO_{0}.json" -f $ymd2),
    ("LATENCY_SLO_{0}.md" -f $ymd2),
    # LATENCY_SLO_NEED_V1    ("meta_{0}.jsonl" -f $ymd2),
    ("shadow_plans_{0}_FROM_META.jsonl" -f $ymd2),
    ("shadow_plans_{0}.jsonl" -f $ymd2),
    ("shadow_plans_FULL_{0}.jsonl" -f $ymd2),
    ("LIVE_OUT_{0}_LATEST.txt" -f $ymd2),
    ("LIVE_ERR_{0}_LATEST.txt" -f $ymd2)
  )

  $paths=@()
  foreach($n in $names){
    $p = Join-Path $bk2 $n
    if(Test-Path $p){ $paths += $p } else { LogOut ("ZIP_MISSING_FILE=" + $n) }
  }

  if($paths.Count -lt 5){
    LogErr ("POSTFREEZE_MINZIP2_FAIL=TOO_FEW_FILES count=" + $paths.Count)
    exit 0
  }

  # 5) create zip INSIDE bk2
  $ts = Get-Date -Format "yyyyMMdd_HHmmss"
  $zipNew = Join-Path $bk2 ("FREEZE_TODAY_{0}_{1}_RUNROOT.zip" -f $ymd2,$ts)
  if(Test-Path $zipNew){ Remove-Item $zipNew -Force -ErrorAction SilentlyContinue }
  Compress-Archive -Path $paths -DestinationPath $zipNew -Force

  # 6) verify zip contains selection coverage (no extraction)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [System.IO.Compression.ZipFile]::OpenRead($zipNew)
  $has=$false
  foreach($e in $z.Entries){
    if($e.FullName -match ("SELECTION_COVERAGE_{0}\." -f $ymd2)){ $has=$true; break }
  }
  $z.Dispose()

  LogOut ("MINZIP2_OK=1 files=" + $paths.Count + " zip=" + $zipNew)
  if($has){ LogOut ("ZIP_SEL_COV_OK=1 zip=" + $zipNew) } else { LogErr ("ZIP_SEL_COV_OK=0 zip=" + $zipNew) }

} catch {
  LogErr ("POSTFREEZE_MINZIP2_EXC=" + $_.Exception.Message)
  exit 0
}



