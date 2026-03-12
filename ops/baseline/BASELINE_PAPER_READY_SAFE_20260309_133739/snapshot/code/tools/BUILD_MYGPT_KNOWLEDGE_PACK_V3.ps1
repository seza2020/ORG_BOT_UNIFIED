param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$RollingDays = 10,
  [int]$KeepDailyZips = 10
)

$ErrorActionPreference="Stop"

function Ensure-Dir([string]$p){ if(!(Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }

# Output dir (ONLY zips live here)
$OutDir = Join-Path $Root "logs\mygpt_pack"
Ensure-Dir $OutDir

# Stage root OUTSIDE logs to prevent recursion
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$StageRoot = Join-Path $env:TEMP ("org_bot_pack_stage_{0}" -f $ts)
Ensure-Dir $StageRoot

# deny (secrets)
$denyPatterns = @(
  "*\secrets\*",
  "*alpaca_env.ps1",
  "*.env",
  "*token*",
  "*api_key*",
  "*private_key*"
)

function Is-DeniedPath([string]$path){
  foreach($pat in $denyPatterns){ if($path -like $pat){ return $true } }
  return $false
}

# exclude staging/knowledge areas from any log copy
$excludeRelRegex = '^(?i)logs\\mygpt_pack\\|^(?i)logs\\gpt_pack\\|^(?i)logs\\ops\\knowledge_current\\|^(?i)logs\\archive\\'

function Add-ToStage([string]$stageDir, [string]$src){
  if(!(Test-Path -LiteralPath $src)){ return }
  $items = Get-ChildItem -LiteralPath $src -Recurse -Force -File -ErrorAction SilentlyContinue
  foreach($it in $items){
    $full = $it.FullName
    if(Is-DeniedPath $full){ continue }
    $rel = $full.Substring($Root.Length).TrimStart("\")
    if($rel -match $excludeRelRegex){ continue }
    $dst = Join-Path $stageDir $rel
    Ensure-Dir (Split-Path $dst -Parent)
    Copy-Item -LiteralPath $full -Destination $dst -Force
  }
}

function New-ZipFromStage([string]$stageDir, [string]$zipPath){
  if(Test-Path -LiteralPath $zipPath){ Remove-Item -LiteralPath $zipPath -Force }
  Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath -Force
}

# --- 1) STATIC_CODE ---
$stageCode = Join-Path $StageRoot "_stage_code"
if(Test-Path -LiteralPath $stageCode){ Remove-Item -LiteralPath $stageCode -Recurse -Force }
Ensure-Dir $stageCode
Add-ToStage $stageCode (Join-Path $Root "tbot")
Add-ToStage $stageCode (Join-Path $Root "tools")
if(Test-Path -LiteralPath (Join-Path $Root "configs")){ Add-ToStage $stageCode (Join-Path $Root "configs") }

$zipCode = Join-Path $OutDir "ORG_BOT_STATIC_CODE.zip"
New-ZipFromStage $stageCode $zipCode

# --- 2) STATIC_OPS ---
$stageOps = Join-Path $StageRoot "_stage_ops"
if(Test-Path -LiteralPath $stageOps){ Remove-Item -LiteralPath $stageOps -Recurse -Force }
Ensure-Dir $stageOps
Add-ToStage $stageOps (Join-Path $Root "docs")
Add-ToStage $stageOps (Join-Path $Root "tools")

$zipOps = Join-Path $OutDir "ORG_BOT_STATIC_OPS.zip"
New-ZipFromStage $stageOps $zipOps

# --- 3) ROLLING_LASTN (logs, last RollingDays) ---
$stageRoll = Join-Path $StageRoot "_stage_roll"
if(Test-Path -LiteralPath $stageRoll){ Remove-Item -LiteralPath $stageRoll -Recurse -Force }
Ensure-Dir $stageRoll

$cutoff = (Get-Date).Date.AddDays(-1 * $RollingDays)
$logsRoot = Join-Path $Root "logs"
if(Test-Path -LiteralPath $logsRoot){
  $files = Get-ChildItem -LiteralPath $logsRoot -Recurse -Force -File |
    Where-Object {
      $_.LastWriteTime -ge $cutoff -and
      -not (Is-DeniedPath $_.FullName)
    }

  foreach($f in $files){
    $rel = $f.FullName.Substring($Root.Length).TrimStart("\")
    if($rel -match $excludeRelRegex){ continue }
    $dst = Join-Path $stageRoll $rel
    Ensure-Dir (Split-Path $dst -Parent)
    Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
  }
}

$zipRoll = Join-Path $OutDir ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays)
New-ZipFromStage $stageRoll $zipRoll

# --- 4) DAILY (today only) ---
$stageDaily = Join-Path $StageRoot "_stage_daily"
if(Test-Path -LiteralPath $stageDaily){ Remove-Item -LiteralPath $stageDaily -Recurse -Force }
Ensure-Dir $stageDaily

$today = Get-Date -Format "yyyyMMdd"
if(Test-Path -LiteralPath $logsRoot){
  $dailyFiles = Get-ChildItem -LiteralPath $logsRoot -Recurse -Force -File |
    Where-Object {
      $_.LastWriteTime.Date -eq (Get-Date).Date -and
      -not (Is-DeniedPath $_.FullName)
    }

  foreach($f in $dailyFiles){
    $rel = $f.FullName.Substring($Root.Length).TrimStart("\")
    if($rel -match $excludeRelRegex){ continue }
    $dst = Join-Path $stageDaily $rel
    Ensure-Dir (Split-Path $dst -Parent)
    Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
  }
}

$zipDaily = Join-Path $OutDir ("ORG_BOT_DAILY_{0}.zip" -f $today)
New-ZipFromStage $stageDaily $zipDaily

# --- 5) SUPER ---
$stageSuper = Join-Path $StageRoot "_stage_super"
if(Test-Path -LiteralPath $stageSuper){ Remove-Item -LiteralPath $stageSuper -Recurse -Force }
Ensure-Dir $stageSuper

Copy-Item -LiteralPath $zipOps  -Destination (Join-Path $stageSuper (Split-Path $zipOps -Leaf))  -Force
Copy-Item -LiteralPath $zipCode -Destination (Join-Path $stageSuper (Split-Path $zipCode -Leaf)) -Force
Copy-Item -LiteralPath $zipRoll -Destination (Join-Path $stageSuper (Split-Path $zipRoll -Leaf)) -Force
Copy-Item -LiteralPath $zipDaily -Destination (Join-Path $stageSuper (Split-Path $zipDaily -Leaf)) -Force

$manifest = @"
MANIFEST_VERSION=1
CREATED_LOCAL=$((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
ROOT=$Root
FILES:
- ORG_BOT_STATIC_OPS.zip
- ORG_BOT_STATIC_CODE.zip
- $(Split-Path $zipRoll -Leaf)
- ORG_BOT_DAILY_$today.zip
"@
Set-Content -Encoding UTF8 -LiteralPath (Join-Path $stageSuper "MANIFEST.txt") -Value $manifest

$zipSuper = Join-Path $OutDir "UPLOAD_SUPER.zip"
New-ZipFromStage $stageSuper $zipSuper

# housekeeping: keep only last N daily zips
Get-ChildItem -LiteralPath $OutDir -Filter "ORG_BOT_DAILY_*.zip" |
  Sort-Object LastWriteTime -Desc |
  Select-Object -Skip $KeepDailyZips |
  Remove-Item -Force -ErrorAction SilentlyContinue

# cleanup stage
Remove-Item -LiteralPath $StageRoot -Recurse -Force -ErrorAction SilentlyContinue

"OK: CREATED"
" - $zipSuper"
" - $zipOps"
" - $zipCode"
" - $zipRoll"
" - $zipDaily"
