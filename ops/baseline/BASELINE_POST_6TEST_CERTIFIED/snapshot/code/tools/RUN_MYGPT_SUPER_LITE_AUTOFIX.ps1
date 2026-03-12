# RUN_MYGPT_SUPER_LITE_AUTOFIX.ps1
# Creates uploadable SUPER_LITE by replacing huge DAILY/ROLLING with tail-based lite packs.
# English-only comments/strings.

param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$TailMetaLines = 200000,
  [int]$TailPlansLines = 8000,
  [int]$TailOutLines = 3000,
  [int]$RollingRuns = 12,
  [int]$MaxTextFileMB = 8,
  [int]$KeepArchives = 5
)

$ErrorActionPreference = "Stop"

function Ensure-Dir($p) {
  if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

function Write-TailFile($src, $dst, $tailLines, $denyRegex) {
  if (!(Test-Path $src)) { return }
  if ($src -match $denyRegex) { return }
  Ensure-Dir (Split-Path $dst -Parent)
  Get-Content -LiteralPath $src -Tail $tailLines -ErrorAction SilentlyContinue |
    Set-Content -Encoding UTF8 -LiteralPath $dst
}

function Copy-TextIfSmall($src, $dst, $maxMB, $denyRegex) {
  if (!(Test-Path $src)) { return }
  if ($src -match $denyRegex) { return }
  $len = (Get-Item -LiteralPath $src).Length
  if ($len -gt ($maxMB * 1MB)) { return }
  Ensure-Dir (Split-Path $dst -Parent)
  Copy-Item -LiteralPath $src -Destination $dst -Force
}

function New-ZipFromStage($stageDir, $zipPath) {
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath -Force
}

function Zip-SecretScan($zipPath) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  $hits = @()
  foreach ($e in $z.Entries) {
    $n = $e.FullName
    if ($n -match '(?i)secrets|alpaca_env\.ps1|\.env|token|api_key|private_key') { $hits += $n }
  }
  $z.Dispose()
  return $hits
}

function Zip-Top($zipPath, $topN = 12) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  $rows = $z.Entries |
    Where-Object { $_.FullName -and $_.FullName -notmatch '/$' } |
    Sort-Object CompressedLength -Desc |
    Select-Object -First $topN FullName,
      @{n="CompressedMB";e={[math]::Round($_.CompressedLength/1MB,2)}},
      @{n="UncompressedMB";e={[math]::Round($_.Length/1MB,2)}}
  $z.Dispose()
  return $rows
}

# ---- setup ----
$PackDir = Join-Path $Root "logs\mygpt_pack"
Ensure-Dir $PackDir

$TodayTag = Get-Date -Format "yyyyMMdd"
$NowTag = Get-Date -Format "yyyyMMdd_HHmmss"

$ArchiveDir = Join-Path $PackDir ("_archive\{0}" -f $NowTag)
Ensure-Dir $ArchiveDir

$denyRegex = '(?i)\\secrets\\|alpaca_env\.ps1|\.env($|\\)|token|api_key|private_key'

# ---- 0) discover current big zips safely ----
$SuperZipPath = Join-Path $PackDir "UPLOAD_SUPER.zip"
$RollingZipPath = Join-Path $PackDir "ORG_BOT_ROLLING_LAST10.zip"

$LatestDailyZip = $null
$dailyZips = Get-ChildItem -LiteralPath $PackDir -Filter "ORG_BOT_DAILY_*.zip" -ErrorAction SilentlyContinue
if ($dailyZips) {
  $LatestDailyZip = ($dailyZips | Sort-Object LastWriteTime -Desc | Select-Object -First 1).FullName
}

$bigCandidates = @()
if (Test-Path $SuperZipPath)   { $bigCandidates += $SuperZipPath }
if ($LatestDailyZip -and (Test-Path $LatestDailyZip)) { $bigCandidates += $LatestDailyZip }
if (Test-Path $RollingZipPath) { $bigCandidates += $RollingZipPath }

# ---- archive (move) big zips ----
foreach ($p in $bigCandidates) {
  $dst = Join-Path $ArchiveDir (Split-Path $p -Leaf)
  Move-Item -LiteralPath $p -Destination $dst -Force
}

# Keep only last N archive folders
$archRoot = Join-Path $PackDir "_archive"
if (Test-Path $archRoot) {
  Get-ChildItem -LiteralPath $archRoot -Directory |
    Sort-Object LastWriteTime -Desc |
    Select-Object -Skip $KeepArchives |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 1) DAILY_LITE ----
$StageDaily = Join-Path $PackDir "_stage_daily_lite"
if (Test-Path $StageDaily) { Remove-Item $StageDaily -Recurse -Force }
Ensure-Dir $StageDaily

$Logs = Join-Path $Root "logs"
$Ops  = Join-Path $Logs "ops"

Write-TailFile (Join-Path $Logs "meta.jsonl")         (Join-Path $StageDaily "latest_daily\meta_tail.jsonl") $TailMetaLines $denyRegex
Write-TailFile (Join-Path $Logs "shadow_plans.jsonl") (Join-Path $StageDaily "latest_daily\shadow_plans_tail.jsonl") $TailPlansLines $denyRegex

if (Test-Path $Ops) {
  $out = Get-ChildItem $Ops -Filter "SHADOW_OUT_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
  $err = Get-ChildItem $Ops -Filter "SHADOW_ERR_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
  if ($out) { Write-TailFile $out.FullName (Join-Path $StageDaily "latest_daily\SHADOW_OUT_TAIL.txt") $TailOutLines $denyRegex }
  if ($err) { Write-TailFile $err.FullName (Join-Path $StageDaily "latest_daily\SHADOW_ERR_TAIL.txt") $TailOutLines $denyRegex }
}

# include only SMALL text files from today
$today = (Get-Date).Date
if (Test-Path $Logs) {
  Get-ChildItem $Logs -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime.Date -eq $today -and $_.FullName -notmatch $denyRegex } |
    Where-Object { $_.Extension -in ".txt",".md",".csv" } |
    ForEach-Object {
      $rel = $_.FullName.Substring($Root.Length).TrimStart("\")
      Copy-TextIfSmall $_.FullName (Join-Path $StageDaily $rel) $MaxTextFileMB $denyRegex
    }
}

$ZipDailyLite = Join-Path $PackDir ("ORG_BOT_DAILY_LITE_{0}.zip" -f $TodayTag)
New-ZipFromStage $StageDaily $ZipDailyLite

# ---- 2) ROLLING_LITE ----
$StageRoll = Join-Path $PackDir "_stage_roll_lite"
if (Test-Path $StageRoll) { Remove-Item $StageRoll -Recurse -Force }
Ensure-Dir $StageRoll

Write-TailFile (Join-Path $Logs "meta.jsonl")         (Join-Path $StageRoll "rolling\meta_tail.jsonl") $TailMetaLines $denyRegex
Write-TailFile (Join-Path $Logs "shadow_plans.jsonl") (Join-Path $StageRoll "rolling\shadow_plans_tail.jsonl") $TailPlansLines $denyRegex

if (Test-Path $Ops) {
  $outs = Get-ChildItem $Ops -Filter "SHADOW_OUT_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First $RollingRuns
  $errs = Get-ChildItem $Ops -Filter "SHADOW_ERR_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First $RollingRuns

  $i=0
  foreach ($f in $outs) {
    $i++
    Write-TailFile $f.FullName (Join-Path $StageRoll ("rolling\ops\OUT_{0:00}.txt" -f $i)) $TailOutLines $denyRegex
  }
  $i=0
  foreach ($f in $errs) {
    $i++
    Write-TailFile $f.FullName (Join-Path $StageRoll ("rolling\ops\ERR_{0:00}.txt" -f $i)) $TailOutLines $denyRegex
  }
}

$ZipRollLite = Join-Path $PackDir "ORG_BOT_ROLLING_LITE.zip"
New-ZipFromStage $StageRoll $ZipRollLite

# ---- 3) SUPER_LITE ----
$StageSuper = Join-Path $PackDir "_stage_super_lite"
if (Test-Path $StageSuper) { Remove-Item $StageSuper -Recurse -Force }
Ensure-Dir $StageSuper

# copy docs directly (size-capped per file)
$Docs = Join-Path $Root "docs"
if (Test-Path $Docs) {
  Get-ChildItem $Docs -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $denyRegex } |
    ForEach-Object {
      $rel = $_.FullName.Substring($Root.Length).TrimStart("\")
      Copy-TextIfSmall $_.FullName (Join-Path $StageSuper $rel) 50 $denyRegex
    }
}

# include tiny static zips if present
$StaticOps  = Join-Path $PackDir "ORG_BOT_STATIC_OPS.zip"
$StaticCode = Join-Path $PackDir "ORG_BOT_STATIC_CODE.zip"
if (Test-Path $StaticOps)  { Copy-Item -LiteralPath $StaticOps  -Destination (Join-Path $StageSuper "ORG_BOT_STATIC_OPS.zip")  -Force }
if (Test-Path $StaticCode) { Copy-Item -LiteralPath $StaticCode -Destination (Join-Path $StageSuper "ORG_BOT_STATIC_CODE.zip") -Force }

# include lite zips
Copy-Item -LiteralPath $ZipDailyLite -Destination (Join-Path $StageSuper (Split-Path $ZipDailyLite -Leaf)) -Force
Copy-Item -LiteralPath $ZipRollLite  -Destination (Join-Path $StageSuper (Split-Path $ZipRollLite -Leaf))  -Force

$manifest = @"
MANIFEST_VERSION=3
CREATED_LOCAL=$((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
ROOT=$Root
SUPER_LITE=docs/ + STATIC zips + DAILY_LITE + ROLLING_LITE (uploadable)
FILES:
- ORG_BOT_STATIC_OPS.zip
- ORG_BOT_STATIC_CODE.zip
- ORG_BOT_DAILY_LITE_$TodayTag.zip
- ORG_BOT_ROLLING_LITE.zip
"@
Set-Content -Encoding UTF8 -LiteralPath (Join-Path $StageSuper "MANIFEST.txt") -Value $manifest

$ZipSuperLite = Join-Path $PackDir "UPLOAD_SUPER_LITE.zip"
New-ZipFromStage $StageSuper $ZipSuperLite

# ---- 4) sizes ----
"=== SIZES (MB) ==="
Get-ChildItem -LiteralPath $PackDir -Filter "*.zip" |
  Select-Object Name, @{n="MB";e={[math]::Round($_.Length/1MB,2)}}, LastWriteTime |
  Sort-Object MB -Desc |
  Format-Table -Auto

# ---- 5) secret scan ----
"=== SECRET SCAN ==="
$targets = @($ZipSuperLite, $ZipDailyLite, $ZipRollLite) | Where-Object { $_ -and (Test-Path $_) }
$anyHit = $false
foreach ($t in $targets) {
  $hits = Zip-SecretScan $t
  if ($hits.Count -gt 0) {
    $anyHit = $true
    foreach ($h in $hits) { "SECRET_HIT:$h (in $(Split-Path $t -Leaf))" }
  }
}
if ($anyHit) {
  "FAIL: SECRET_HIT found. Do NOT upload."
  exit 2
}
"PASS: No secret hits."

"=== UPLOAD THIS ==="
$ZipSuperLite

# ---- 6) show top offenders from archived big zips (forensics) ----
"=== ARCHIVED BIG ZIP TOP (if any) ==="
Get-ChildItem -LiteralPath $ArchiveDir -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
  "---- TOP in $($_.Name) ----"
  Zip-Top $_.FullName 12 | Format-Table -Auto
}
