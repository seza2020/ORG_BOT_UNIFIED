param(
  [string]$Tag = "BASELINE_QA_GREEN_20260204",
  [switch]$IncludeLogs
)

$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\org_bot"
Set-Location $ROOT

$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$OUTDIR = Join-Path $ROOT ("_BACKUPS")
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null

$work = Join-Path $OUTDIR ("work_" + $ts)
New-Item -ItemType Directory -Force -Path $work | Out-Null

# 1) Export tracked source from git tag (clean baseline)
$zip1 = Join-Path $work ("repo_" + $Tag + ".zip")
git archive --format=zip --output $zip1 $Tag

# 2) Collect extras (untracked but useful scripts)
$extras = Join-Path $work "extras"
New-Item -ItemType Directory -Force -Path $extras | Out-Null

# tools ps1 you created (and any other ps1 helpers)
if(Test-Path (Join-Path $ROOT "tools")){
  New-Item -ItemType Directory -Force -Path (Join-Path $extras "tools") | Out-Null
  Get-ChildItem (Join-Path $ROOT "tools") -File -Filter "*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { Copy-Item -Force $_.FullName (Join-Path $extras "tools") }
}

# optionally include recent QA runlogs (not secrets)
if($IncludeLogs -and (Test-Path (Join-Path $ROOT "logs"))){
  $logsDst = Join-Path $extras "logs"
  New-Item -ItemType Directory -Force -Path $logsDst | Out-Null
  Get-ChildItem (Join-Path $ROOT "logs") -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(qa_|ann_|meta_)' } |
    Sort-Object LastWriteTime |
    Select-Object -Last 50 |
    ForEach-Object { Copy-Item -Force $_.FullName $logsDst }
}

# 3) Write manifest (hashes)
$manifest = Join-Path $extras ("MANIFEST_" + $ts + ".txt")
@(
  "ROOT=$ROOT",
  "TAG=$Tag",
  "TS=$ts",
  "INCLUDE_LOGS=$IncludeLogs",
  ""
) | Set-Content -LiteralPath $manifest -Encoding UTF8

$filesToHash = @(
  "tbot\main.py",
  "tbot\runtime\orchestrator.py",
  "tools\QA_PREMARKET.ps1",
  "tools\QA_PIPELINE_ACCEPT.ps1",
  "tools\RUN_SHADOW_LIVE_NOW.ps1"
) | ForEach-Object { Join-Path $ROOT $_ } | Where-Object { Test-Path $_ }

foreach($f in $filesToHash){
  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $f
  Add-Content -LiteralPath $manifest -Value ($h.Hash + "  " + $f)
}

# 4) Final bundle zip (repo zip + extras)
$final = Join-Path $OUTDIR ("ORG_BOT_BACKUP_" + $Tag + "_" + $ts + ".zip")
Compress-Archive -Path $zip1, $extras -DestinationPath $final -Force

Write-Host ("[OK] backup zip=" + $final)
Write-Host ("[OK] repo archive=" + $zip1)
Write-Host ("[OK] extras dir=" + $extras)
