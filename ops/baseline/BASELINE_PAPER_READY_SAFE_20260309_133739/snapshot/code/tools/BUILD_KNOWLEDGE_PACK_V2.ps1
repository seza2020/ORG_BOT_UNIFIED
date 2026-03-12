param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$Day = "",                 # yyyyMMdd; empty -> today
  [int]$RollingDays = 10,
  [int]$MakeSuperZip = 1,
  [int]$RebuildStatic = 0,
  [int]$SkipFreeze = 0,
  [int]$AllowNoPlans = 1             # 1 -> do not fail on weekends/no plans
)

$ErrorActionPreference="Stop"

function Log([string]$m){
  $ts=(Get-Date -Format "HH:mm:ss")
  Write-Host "[$ts] $m"
}
function Ensure-Dir([string]$p){ New-Item -ItemType Directory -Force -Path $p | Out-Null }
function Sha256([string]$p){
  if(!(Test-Path $p)){ return "" }
  return (Get-FileHash -Algorithm SHA256 -Path $p).Hash
}

# Resolve day
if([string]::IsNullOrWhiteSpace($Day)){
  $Day = (Get-Date).ToString("yyyyMMdd")
}
function DayIso([string]$d){ "{0}-{1}-{2}" -f $d.Substring(0,4),$d.Substring(4,2),$d.Substring(6,2) }

$Logs = Join-Path $Root "logs"
$Ops  = Join-Path $Logs "ops"
$FreezeDir = Join-Path $Logs "freeze"
$ShadowDaily = Join-Path $Logs "shadow_daily"
$Archive = Join-Path $Ops "knowledge_archive"
$DailyArchive = Join-Path $Archive "daily_zips"
$StaticCache  = Join-Path $Ops "knowledge_static"
$CurrentOut   = Join-Path $Ops "knowledge_current"

Ensure-Dir $Ops
Ensure-Dir $FreezeDir
Ensure-Dir $ShadowDaily
Ensure-Dir $Archive
Ensure-Dir $DailyArchive
Ensure-Dir $StaticCache
Ensure-Dir $CurrentOut

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$BundleRoot = Join-Path $Ops ("KNOWLEDGE_BUNDLE_{0}" -f $ts)
$ZipDir = Join-Path $BundleRoot "zips"
Ensure-Dir $BundleRoot
Ensure-Dir $ZipDir

# Tools
$Recover = Join-Path $Root "tools\recover_shadow_plans_from_meta.ps1"
$FreezeSafe = Join-Path $Root "tools\freeze_today_enterprise_SAFE.ps1"

# ---- FROM_META (authoritative daily plan source) ----
$FromMeta = Join-Path $ShadowDaily ("shadow_plans_{0}_FROM_META.jsonl" -f $Day)
Ensure-Dir (Split-Path $FromMeta)

Log ("RECOVER_FROM_META Day=" + $Day)
if(!(Test-Path $Recover)){ throw "Missing tool: recover_shadow_plans_from_meta.ps1" }

# Force OutPath so we know exactly where it should be written
$rcOut = & pwsh -NoProfile -ExecutionPolicy Bypass -File $Recover -Root $Root -Day $Day -OutPath $FromMeta 2>&1
$rc = $LASTEXITCODE

if($rc -ne 0){
  Log ("WARN: recover returned exitcode=" + $rc)
  $rcOut | Select-Object -First 5 | ForEach-Object { Log ("  " + $_) }
}

# If still missing, fallback to most recent available FROM_META
if(!(Test-Path $FromMeta)){
  $cand = Get-ChildItem $ShadowDaily -File -Filter "shadow_plans_*_FROM_META.jsonl" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Desc | Select-Object -First 1

  if($cand){
    Log ("WARN: FROM_META missing for requested Day. Fallback=" + $cand.FullName)
    $FromMeta = $cand.FullName
    if($cand.Name -match 'shadow_plans_(\d{8})_FROM_META\.jsonl'){
      $Day = $matches[1]
      Log ("WARN: Day adjusted to " + $Day)
    }
  } else {
    if($AllowNoPlans -eq 1){
      Log "WARN: No FROM_META files exist at all. Creating empty placeholder."
      New-Item -ItemType File -Force -Path $FromMeta | Out-Null
    } else {
      throw "FROM_META missing and no fallback exists."
    }
  }
}

$fromMetaCount = (Get-Content $FromMeta -ErrorAction SilentlyContinue | Measure-Object).Count
Log ("FROM_META_PATH=" + $FromMeta)
Log ("FROM_META_COUNT=" + $fromMetaCount)

# ---- FREEZE (optional) ----
if($SkipFreeze -eq 0){
  Log "FREEZE_SAFE..."
  if(Test-Path $FreezeSafe){
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $FreezeSafe -Root $Root -Day $Day 2>&1 | Out-Null
  } else {
    Log "WARN: freeze_today_enterprise_SAFE.ps1 missing; skipping freeze."
  }
}else{
  Log "SKIP_FREEZE (SkipFreeze=1)"
}

# Find latest FREEZE_BACKUP for this Day (fallback to latest any-day)
$Bk = Get-ChildItem $Ops -Directory -Filter "FREEZE_BACKUP_${Day}_*" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Desc | Select-Object -First 1
if(!$Bk){
  $Bk = Get-ChildItem $Ops -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Desc | Select-Object -First 1
}
if($Bk){ Log ("FREEZE_BACKUP=" + $Bk.FullName) } else { Log "WARN: No FREEZE_BACKUP_* found." }

# ---- STATIC zips (cache) ----
$StaticOpsZipCache  = Join-Path $StaticCache "ORG_BOT_STATIC_OPS.zip"
$StaticCodeZipCache = Join-Path $StaticCache "ORG_BOT_STATIC_CODE.zip"

if($RebuildStatic -eq 1){
  Log "REBUILD_STATIC_OPS..."
  $tmp = Join-Path $BundleRoot "STATIC_OPS_STAGE"
  Ensure-Dir $tmp

  $include = @(
    (Join-Path $Root "tools\*.ps1"),
    (Join-Path $Root "tools\*.py"),
    (Join-Path $Root "tools\ops\*.ps1")
  )
  foreach($g in $include){
    Get-ChildItem -Path $g -File -ErrorAction SilentlyContinue | ForEach-Object {
      Copy-Item -Force -Path $_.FullName -Destination (Join-Path $tmp $_.Name)
    }
  }
  if(Test-Path $StaticOpsZipCache){ Remove-Item $StaticOpsZipCache -Force }
  Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $StaticOpsZipCache -Force
  Log ("STATIC_OPS_CACHE=" + $StaticOpsZipCache)

  Log "REBUILD_STATIC_CODE..."
  $tmp2 = Join-Path $BundleRoot "STATIC_CODE_STAGE"
  Ensure-Dir $tmp2

  $src = Join-Path $Root "tbot"
  if(Test-Path $src){
    Copy-Item -Recurse -Force -Path $src -Destination (Join-Path $tmp2 "tbot")
  }
  $opt = @("pyproject.toml","requirements.txt","requirements-dev.txt","README.md")
  foreach($f in $opt){
    $p = Join-Path $Root $f
    if(Test-Path $p){ Copy-Item -Force -Path $p -Destination (Join-Path $tmp2 $f) }
  }

  if(Test-Path $StaticCodeZipCache){ Remove-Item $StaticCodeZipCache -Force }
  Compress-Archive -Path (Join-Path $tmp2 "*") -DestinationPath $StaticCodeZipCache -Force
  Log ("STATIC_CODE_CACHE=" + $StaticCodeZipCache)
}else{
  Log "SKIP_REBUILD_STATIC (RebuildStatic=0)"
}

# Always copy static cache into today's ZipDir (if exists)
$StaticOpsZip  = Join-Path $ZipDir "ORG_BOT_STATIC_OPS.zip"
$StaticCodeZip = Join-Path $ZipDir "ORG_BOT_STATIC_CODE.zip"
if(Test-Path $StaticOpsZipCache){ Copy-Item -Force $StaticOpsZipCache $StaticOpsZip } else { Log "WARN: STATIC_OPS cache missing." }
if(Test-Path $StaticCodeZipCache){ Copy-Item -Force $StaticCodeZipCache $StaticCodeZip } else { Log "WARN: STATIC_CODE cache missing." }

# ---- DAILY zip (only if meaningful) ----
$DailyZip = $null
if($fromMetaCount -eq 0 -and $AllowNoPlans -eq 1){
  Log "WARN: No plans for this day (COUNT=0). Skipping DAILY zip build."
}else{
  if($Bk){
    $DailyStage = Join-Path $BundleRoot ("DAILY_{0}" -f $Day)
    Ensure-Dir $DailyStage

    Copy-Item -Recurse -Force -Path (Join-Path $Bk.FullName "*") -Destination $DailyStage -ErrorAction SilentlyContinue
    Copy-Item -Force -Path $FromMeta -Destination (Join-Path $DailyStage ("shadow_plans_{0}_FROM_META.jsonl" -f $Day)) -ErrorAction SilentlyContinue

    $DailyZip = Join-Path $ZipDir ("ORG_BOT_DAILY_{0}.zip" -f $Day)
    if(Test-Path $DailyZip){ Remove-Item $DailyZip -Force }
    Compress-Archive -Path (Join-Path $DailyStage "*") -DestinationPath $DailyZip -Force
    Log ("ZIP_DAILY=" + $DailyZip)

    # store in archive
    Copy-Item -Force -Path $DailyZip -Destination (Join-Path $DailyArchive (Split-Path $DailyZip -Leaf))
  } else {
    Log "WARN: No FREEZE_BACKUP found. Skipping DAILY zip."
  }
}

# ---- ROLLING zip ----
$allDaily = Get-ChildItem $DailyArchive -File -Filter "ORG_BOT_DAILY_*.zip" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Desc

$keep = $allDaily | Select-Object -First $RollingDays
$drop = $allDaily | Select-Object -Skip $RollingDays
foreach($d in $drop){ Remove-Item $d.FullName -Force -ErrorAction SilentlyContinue }

$RollingZip = Join-Path $ZipDir ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays)
if(Test-Path $RollingZip){ Remove-Item $RollingZip -Force }
if($keep.Count -gt 0){
  Compress-Archive -Path ($keep.FullName) -DestinationPath $RollingZip -Force
  Log ("ZIP_ROLLING=" + $RollingZip)
}else{
  Log "WARN: No DAILY zips in archive; rolling zip not created."
}

# ---- SUPER zip (optional) ----
$SuperZip = Join-Path $ZipDir "ORG_BOT_KNOWLEDGE_SUPER.zip"
if($MakeSuperZip -eq 1){
  if(Test-Path $SuperZip){ Remove-Item $SuperZip -Force }
  Compress-Archive -Path (Join-Path $ZipDir "*.zip") -DestinationPath $SuperZip -Force
  Log ("ZIP_SUPER=" + $SuperZip)
}else{
  Log "SKIP_SUPER (MakeSuperZip=0)"
}

# ---- Copy to stable "current" output (so you always upload from one fixed path) ----
$CurZipDir = Join-Path $CurrentOut "zips"
Ensure-Dir $CurZipDir
Get-ChildItem $ZipDir -File -Filter "*.zip" | ForEach-Object { Copy-Item -Force $_.FullName (Join-Path $CurZipDir $_.Name) }

$manifest = Join-Path $CurrentOut "MANIFEST.txt"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add(("DAY={0} ISO={1}" -f $Day,(DayIso $Day))) | Out-Null
$lines.Add(("ROLLING_DAYS={0}" -f $RollingDays)) | Out-Null
$lines.Add(("FROM_META={0}" -f $FromMeta)) | Out-Null
$lines.Add(("FROM_META_COUNT={0}" -f $fromMetaCount)) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("UPLOAD_POLICY:") | Out-Null
$lines.Add(("  - Always replace: ORG_BOT_ROLLING_LAST{0}.zip (daily)" -f $RollingDays)) | Out-Null
$lines.Add("  - Replace when changed: ORG_BOT_STATIC_OPS.zip, ORG_BOT_STATIC_CODE.zip") | Out-Null
$lines.Add("  - Optional: ORG_BOT_KNOWLEDGE_SUPER.zip (daily replace)") | Out-Null
$lines.Add("") | Out-Null

$z = Get-ChildItem $CurZipDir -File -Filter "*.zip" | Sort-Object Name
foreach($f in $z){
  $lines.Add(("{0}  bytes={1}  sha256={2}" -f $f.Name,$f.Length,(Sha256 $f.FullName))) | Out-Null
}
Set-Content -Encoding UTF8 -Path $manifest -Value $lines

"CURRENT_ZIP_DIR=$CurZipDir"
"MANIFEST=$manifest"
