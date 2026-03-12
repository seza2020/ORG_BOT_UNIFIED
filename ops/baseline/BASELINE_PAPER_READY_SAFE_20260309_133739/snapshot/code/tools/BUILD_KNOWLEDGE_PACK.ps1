param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$Day = "",                 # yyyyMMdd; if empty -> today (local)
  [int]$RollingDays = 10,
  [int]$MakeSuperZip = 1,
  [int]$RebuildStatic = 1
)

$ErrorActionPreference="Stop"

function Log([string]$m){
  $ts=(Get-Date -Format "HH:mm:ss")
  Write-Host "[$ts] $m"
}

function Ensure-Dir([string]$p){
  New-Item -ItemType Directory -Force -Path $p | Out-Null
}

function Sha256([string]$p){
  if(!(Test-Path $p)){ return "" }
  return (Get-FileHash -Algorithm SHA256 -Path $p).Hash
}

# Resolve day
if([string]::IsNullOrWhiteSpace($Day)){
  $Day = (Get-Date).ToString("yyyyMMdd")
}
$DayISO = "{0}-{1}-{2}" -f $Day.Substring(0,4),$Day.Substring(4,2),$Day.Substring(6,2)

$Logs = Join-Path $Root "logs"
$Ops  = Join-Path $Logs "ops"
$FreezeDir = Join-Path $Logs "freeze"
$ShadowDaily = Join-Path $Logs "shadow_daily"
$Archive = Join-Path $Ops "knowledge_archive"
$DailyArchive = Join-Path $Archive "daily_zips"

Ensure-Dir $Ops
Ensure-Dir $FreezeDir
Ensure-Dir $ShadowDaily
Ensure-Dir $Archive
Ensure-Dir $DailyArchive

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$BundleRoot = Join-Path $Ops ("KNOWLEDGE_BUNDLE_{0}" -f $ts)
$ZipDir = Join-Path $BundleRoot "zips"
Ensure-Dir $BundleRoot
Ensure-Dir $ZipDir

# Tools
$Recover = Join-Path $Root "tools\recover_shadow_plans_from_meta.ps1"
$FreezeSafe = Join-Path $Root "tools\freeze_today_enterprise_SAFE.ps1"

# 1) Ensure FROM_META exists (source of truth for daily plans)
Log ("RECOVER_FROM_META Day=" + $Day)
if(!(Test-Path $Recover)){ throw "Missing tool: recover_shadow_plans_from_meta.ps1" }
& pwsh -NoProfile -ExecutionPolicy Bypass -File $Recover -Root $Root -Day $Day | Out-Null

$FromMeta = Join-Path $ShadowDaily ("shadow_plans_{0}_FROM_META.jsonl" -f $Day)
if(!(Test-Path $FromMeta)){
  throw "FROM_META missing: $FromMeta"
}
$fromMetaCount = (Get-Content $FromMeta | Measure-Object).Count
Log ("FROM_META_COUNT=" + $fromMetaCount)

# 2) Run Freeze SAFE (creates a new FREEZE_BACKUP_* folder + zip)
Log "FREEZE_SAFE..."
if(!(Test-Path $FreezeSafe)){ throw "Missing tool: freeze_today_enterprise_SAFE.ps1" }
& pwsh -NoProfile -ExecutionPolicy Bypass -File $FreezeSafe -Root $Root -Day $Day | Out-Null

# 3) Find latest FREEZE_BACKUP for this Day
$Bk = Get-ChildItem $Ops -Directory -Filter "FREEZE_BACKUP_${Day}_*" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Desc | Select-Object -First 1

if(!$Bk){
  # fallback: use latest any-day
  $Bk = Get-ChildItem $Ops -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Desc | Select-Object -First 1
}
if(!$Bk){ throw "No FREEZE_BACKUP_* folder found under logs\ops" }

Log ("FREEZE_BACKUP=" + $Bk.FullName)

# 4) Build DAILY zip (copy backup folder + ensure FROM_META is included)
$DailyStage = Join-Path $BundleRoot ("DAILY_{0}" -f $Day)
Ensure-Dir $DailyStage

# copy backup folder content
Copy-Item -Recurse -Force -Path (Join-Path $Bk.FullName "*") -Destination $DailyStage

# copy FROM_META
Copy-Item -Force -Path $FromMeta -Destination (Join-Path $DailyStage ("shadow_plans_{0}_FROM_META.jsonl" -f $Day))

$DailyZip = Join-Path $ZipDir ("ORG_BOT_DAILY_{0}.zip" -f $Day)
if(Test-Path $DailyZip){ Remove-Item $DailyZip -Force }
Compress-Archive -Path (Join-Path $DailyStage "*") -DestinationPath $DailyZip -Force
Log ("ZIP_DAILY=" + $DailyZip)

# 5) Build STATIC_OPS zip (scripts/tools only, exclude secrets/logs/venv)
$StaticOpsZip = Join-Path $ZipDir "ORG_BOT_STATIC_OPS.zip"
if($RebuildStatic -eq 1){
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

  if(Test-Path $StaticOpsZip){ Remove-Item $StaticOpsZip -Force }
  Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $StaticOpsZip -Force
  Log ("ZIP_STATIC_OPS=" + $StaticOpsZip)
}else{
  Log "SKIP_STATIC_OPS (RebuildStatic=0)"
}

# 6) Build STATIC_CODE zip (tbot code only, exclude secrets/logs/venv)
$StaticCodeZip = Join-Path $ZipDir "ORG_BOT_STATIC_CODE.zip"
if($RebuildStatic -eq 1){
  $tmp = Join-Path $BundleRoot "STATIC_CODE_STAGE"
  Ensure-Dir $tmp

  $src = Join-Path $Root "tbot"
  if(!(Test-Path $src)){ throw "Missing folder: $src" }

  Copy-Item -Recurse -Force -Path $src -Destination (Join-Path $tmp "tbot")

  # optional common project files
  $opt = @("pyproject.toml","requirements.txt","requirements-dev.txt","README.md")
  foreach($f in $opt){
    $p = Join-Path $Root $f
    if(Test-Path $p){ Copy-Item -Force -Path $p -Destination (Join-Path $tmp $f) }
  }

  if(Test-Path $StaticCodeZip){ Remove-Item $StaticCodeZip -Force }
  Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $StaticCodeZip -Force
  Log ("ZIP_STATIC_CODE=" + $StaticCodeZip)
}else{
  Log "SKIP_STATIC_CODE (RebuildStatic=0)"
}

# 7) Rolling: keep last N daily zips in archive, then build rolling zip
Copy-Item -Force -Path $DailyZip -Destination (Join-Path $DailyArchive (Split-Path $DailyZip -Leaf))

$allDaily = Get-ChildItem $DailyArchive -File -Filter "ORG_BOT_DAILY_*.zip" |
  Sort-Object LastWriteTime -Desc

# delete older than RollingDays
$keep = $allDaily | Select-Object -First $RollingDays
$drop = $allDaily | Select-Object -Skip $RollingDays
foreach($d in $drop){
  Remove-Item $d.FullName -Force -ErrorAction SilentlyContinue
}

$RollingZip = Join-Path $ZipDir ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays)
if(Test-Path $RollingZip){ Remove-Item $RollingZip -Force }
Compress-Archive -Path ($keep.FullName) -DestinationPath $RollingZip -Force
Log ("ZIP_ROLLING=" + $RollingZip)

# 8) Super zip (optional)
$SuperZip = Join-Path $ZipDir "ORG_BOT_KNOWLEDGE_SUPER.zip"
if($MakeSuperZip -eq 1){
  if(Test-Path $SuperZip){ Remove-Item $SuperZip -Force }
  Compress-Archive -Path (Join-Path $ZipDir "*.zip") -DestinationPath $SuperZip -Force
  Log ("ZIP_SUPER=" + $SuperZip)
}else{
  Log "SKIP_SUPER (MakeSuperZip=0)"
}

# 9) Manifest
$manifest = Join-Path $BundleRoot "MANIFEST.txt"
$lines = New-Object System.Collections.Generic.List[string]

$lines.Add("DAY=$Day ($DayISO)") | Out-Null
$lines.Add("ROLLING_DAYS=$RollingDays") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("UPLOAD_POLICY:") | Out-Null
$lines.Add("  - Always replace: ORG_BOT_ROLLING_LAST{N}.zip (daily)") | Out-Null
$lines.Add("  - Replace when changed: ORG_BOT_STATIC_OPS.zip, ORG_BOT_STATIC_CODE.zip") | Out-Null
$lines.Add("  - Optional: ORG_BOT_KNOWLEDGE_SUPER.zip (daily replace)") | Out-Null
$lines.Add("") | Out-Null

$z = Get-ChildItem $ZipDir -File -Filter "*.zip" | Sort-Object Name
foreach($f in $z){
  $lines.Add(("{0}  bytes={1}  sha256={2}" -f $f.Name,$f.Length,(Sha256 $f.FullName))) | Out-Null
}
Set-Content -Encoding UTF8 -Path $manifest -Value $lines

"FOLDER_READY=$BundleRoot"
"ZIP_DIR=$ZipDir"
"MANIFEST=$manifest"
