param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$RollingDays = 10,
  [int]$UpdateCurrent = 1,
  [int]$UpdateWeekLatest = 1
)

$ErrorActionPreference="Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem

$Cur      = Join-Path $Root "logs\ops\knowledge_current"
$ZipDir   = Join-Path $Cur  "zips"
$Manifest = Join-Path $Cur  "MANIFEST.txt"
$DocsDir  = Join-Path $Cur  "docs"

if(!(Test-Path $ZipDir)){ throw "Missing zip dir: $ZipDir" }
New-Item -ItemType Directory -Force -Path $DocsDir | Out-Null

function Write-Log([string]$m){
  $ts = (Get-Date).ToString("HH:mm:ss")
  Write-Host "[$ts] $m"
}

function Get-QCForDay([string]$day){
  $ops = Join-Path $Root "logs\ops"
  $qc  = Get-ChildItem $ops -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
         ForEach-Object {
           $p = Join-Path $_.FullName ("QC_{0}.txt" -f $day)
           if(Test-Path $p){
             [pscustomobject]@{ Path=$p; Backup=$_.FullName; LastWrite=(Get-Item $p).LastWriteTime }
           }
         } |
         Sort-Object LastWrite -Descending |
         Select-Object -First 1

  if(!$qc){
    return [pscustomobject]@{
      qc_found=0; qc_path=""; qc_backup=""; qc_result=""; live_out_count=""; warn=""; fail=""
    }
  }

  $map = @{}
  Get-Content $qc.Path | ForEach-Object {
    if($_ -match '^\s*([A-Z0-9_]+)=(.*)\s*$'){
      $k=$matches[1]; $v=$matches[2]
      $map[$k]=$v
    }
  }

  [pscustomobject]@{
    qc_found=1
    qc_path=$qc.Path
    qc_backup=$qc.Backup
    qc_result=([string]$map["QC_RESULT"])
    live_out_count=([string]$map["LIVE_OUT_COUNT"])
    warn=([string]$map["WARN"])
    fail=([string]$map["FAIL"])
  }
}

function Get-FromMetaStats([string]$path){
  if(!(Test-Path $path)){
    return [pscustomobject]@{ exists=0; lines=0; first_ts=""; last_ts="" }
  }

  $lines = (Get-Content $path | Measure-Object -Line).Lines
  if($lines -le 0){
    return [pscustomobject]@{ exists=1; lines=0; first_ts=""; last_ts="" }
  }

  $firstLine = Get-Content $path -TotalCount 1
  $lastLine  = Get-Content $path -Tail 1

  $firstTs=""; $lastTs=""
  try { $o1 = $firstLine | ConvertFrom-Json; $firstTs = [string]$o1.ts } catch {}
  try { $o2 = $lastLine  | ConvertFrom-Json; $lastTs  = [string]$o2.ts } catch {}

  [pscustomobject]@{ exists=1; lines=$lines; first_ts=$firstTs; last_ts=$lastTs }
}

# -------------------------
# 1) Build DAILY_ROLLUP.csv
# -------------------------
$ShadowDaily = Join-Path $Root "logs\shadow_daily"
$fromMetaFiles = Get-ChildItem $ShadowDaily -File -Filter "shadow_plans_*_FROM_META.jsonl" -ErrorAction SilentlyContinue

$days = $fromMetaFiles |
  ForEach-Object {
    if($_.Name -match '^shadow_plans_(\d{8})_FROM_META\.jsonl$'){ $matches[1] }
  } |
  Where-Object { $_ } |
  Sort-Object -Unique -Descending |
  Select-Object -First $RollingDays

$days = $days | Sort-Object

$rollup = New-Object System.Collections.Generic.List[string]
$rollup.Add("day,from_meta_lines,from_meta_first_utc,from_meta_last_utc,qc_result,live_out_count,warn,fail") | Out-Null

foreach($d in $days){
  $p = Join-Path $ShadowDaily ("shadow_plans_{0}_FROM_META.jsonl" -f $d)
  $st = Get-FromMetaStats $p
  $qc = Get-QCForDay $d

  $line = "{0},{1},{2},{3},{4},{5},{6},{7}" -f `
    $d, $st.lines, $st.first_ts, $st.last_ts, `
    ($qc.qc_result -replace ',',';'), ($qc.live_out_count -replace ',',';'), `
    (($qc.warn) -replace ',',';'), (($qc.fail) -replace ',',';')

  $rollup.Add($line) | Out-Null
}

$RollupPath = Join-Path $DocsDir "ORG_BOT_DAILY_ROLLUP.csv"
Set-Content -Encoding UTF8 -Path $RollupPath -Value $rollup
Write-Log ("WROTE " + $RollupPath)

# -------------------------
# 2) Build RUNBOOK.md
# -------------------------
$RunbookPath = Join-Path $DocsDir "ORG_BOT_RUNBOOK.md"

$runbook = @()
$runbook += "# ORG_BOT RUNBOOK (Ops + QA)"
$runbook += ""
$runbook += "## Canonical paths"
$runbook += "- ROOT: C:\alpaca-bot\org_bot"
$runbook += "- LOCK: C:\alpaca-bot\org_bot\logs\locks\RUN_SHADOW.lock"
$runbook += "- META: C:\alpaca-bot\org_bot\logs\meta.jsonl"
$runbook += "- ANNOUNCE: C:\alpaca-bot\org_bot\logs\announce.log"
$runbook += "- SHADOW_PLANS (legacy): C:\alpaca-bot\org_bot\logs\shadow_plans.jsonl"
$runbook += "- SHADOW_DAILY: C:\alpaca-bot\org_bot\logs\shadow_daily\shadow_plans_YYYYMMDD_FROM_META.jsonl"
$runbook += ""
$runbook += "## Start shadow (safe)"
$runbook += 'pwsh -NoProfile -ExecutionPolicy Bypass -File C:\alpaca-bot\org_bot\tools\RUN_LIVE_SHADOW_CANON_V2.ps1'
$runbook += ""
$runbook += "## Stop + End of day (safe)"
$runbook += 'pwsh -NoProfile -ExecutionPolicy Bypass -File C:\alpaca-bot\org_bot\tools\OPS_END_OF_DAY_V2.ps1 -Root C:\alpaca-bot\org_bot -Day (Get-Date -Format yyyyMMdd) -StopBot 1'
$runbook += ""
$runbook += "## Recover daily shadow plans from meta"
$runbook += 'pwsh -NoProfile -ExecutionPolicy Bypass -File C:\alpaca-bot\org_bot\tools\recover_shadow_plans_from_meta.ps1 -Root C:\alpaca-bot\org_bot -Day YYYYMMDD'
$runbook += ""
$runbook += "## Knowledge pack output location"
$runbook += "- CURRENT: C:\alpaca-bot\org_bot\logs\ops\knowledge_current"
$runbook += "- ZIPS:    C:\alpaca-bot\org_bot\logs\ops\knowledge_current\zips"
$runbook += ""
$runbook += "## Upload policy (recommended)"
$runbook += "- Daily replace: ORG_BOT_KNOWLEDGE_SUPER.zip OR ORG_BOT_ROLLING_LAST{N}.zip"
$runbook += "- Replace when changed: ORG_BOT_STATIC_CODE.zip, ORG_BOT_STATIC_OPS.zip"
$runbook += "- Always include: MANIFEST.txt, docs/ORG_BOT_RUNBOOK.md, docs/ORG_BOT_DAILY_ROLLUP.csv"
$runbook += ""

Set-Content -Encoding UTF8 -Path $RunbookPath -Value $runbook
Write-Log ("WROTE " + $RunbookPath)

# -------------------------
# 3) Update ZIP(s) with docs + manifest
# -------------------------
function Update-Zip([string]$ZipPath){
  if(!(Test-Path $ZipPath)){ return }

  Write-Log ("UPDATING ZIP " + $ZipPath)

  $fs = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
  try{
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Update)
    try{
      function Replace-Entry([string]$src, [string]$dst){
        $e = $zip.GetEntry($dst)
        if($e){ $e.Delete() }
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
          $zip, $src, $dst, [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
      }

      if(Test-Path $Manifest){ Replace-Entry $Manifest "MANIFEST.txt" }
      Replace-Entry $RunbookPath "docs/ORG_BOT_RUNBOOK.md"
      Replace-Entry $RollupPath  "docs/ORG_BOT_DAILY_ROLLUP.csv"
    } finally {
      $zip.Dispose()
    }
  } finally {
    $fs.Dispose()
  }
}

if($UpdateCurrent -eq 1){
  Get-ChildItem $ZipDir -File -Filter "*.zip" | ForEach-Object {
    Update-Zip $_.FullName
  }
}

if($UpdateWeekLatest -eq 1){
  $ops = Join-Path $Root "logs\ops"
  $week = Get-ChildItem $ops -File -Filter "ORG_BOT_WEEK_*_KNOWLEDGE.zip" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1
  if($week){
    Update-Zip $week.FullName
    Write-Log ("UPDATED_WEEK_ZIP=" + $week.FullName)
  } else {
    Write-Log "NO_WEEK_ZIP_FOUND"
  }
}

Write-Log ("DONE. DOCS=" + $DocsDir)
Write-Log ("CURRENT_ZIPS=" + $ZipDir)

# show quick inventory
Get-ChildItem $ZipDir -File -Filter "*.zip" |
  Sort-Object Name |
  Select-Object Name,Length,LastWriteTime |
  Format-Table -Auto
