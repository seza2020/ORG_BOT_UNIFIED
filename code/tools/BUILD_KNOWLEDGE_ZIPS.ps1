param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$Days = 5,
  [int]$MakeSuperZip = 1
)

$ErrorActionPreference = "Stop"

function New-Dir([string]$p){
  if(!(Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Safe-CopyDir([string]$src, [string]$dst){
  New-Dir (Split-Path $dst)
  Copy-Item -Path $src -Destination $dst -Recurse -Force
}

function Should-Exclude([string]$path){
  $p = $path.ToLower()
  if($p -match "\\secrets\\"){ return $true }
  if($p -match "alpaca_env\.ps1"){ return $true }
  if($p -match "\.env(\.|$)"){ return $true }
  if($p -match "secret|token|apikey|api_key|private|pem|pfx|key"){ return $true }
  return $false
}

function Add-OpsScripts([string]$root, [string]$outDir){
  $tools = Join-Path $root "tools"
  if(!(Test-Path $tools)){ return }

  New-Dir $outDir

  Get-ChildItem -Path $tools -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      ($_.Extension -in @(".ps1",".py",".txt",".md",".json")) -and
      -not (Should-Exclude $_.FullName)
    } |
    ForEach-Object {
      $rel = $_.FullName.Substring($tools.Length).TrimStart("\")
      $dst = Join-Path $outDir $rel
      New-Dir (Split-Path $dst)
      Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
    }
}

function Select-LatestFreezeByDay([string]$rootOps){
  $dirs = Get-ChildItem -Path $rootOps -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue
  if(!$dirs){ return @() }

  $items = foreach($d in $dirs){
    $name = $d.Name
    if($name -match "^FREEZE_BACKUP_(\d{8})_"){
      [pscustomobject]@{
        Day = $Matches[1]
        FullName = $d.FullName
        LastWriteTime = $d.LastWriteTime
      }
    }
  }

  if(!$items){ return @() }

  # pick latest per day
  $latest = $items |
    Group-Object Day |
    ForEach-Object { $_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1 } |
    Sort-Object Day -Descending

  # take last N days
  return $latest | Select-Object -First $Days
}

function Zip-Dir([string]$srcDir, [string]$zipPath){
  if(Test-Path $zipPath){ Remove-Item $zipPath -Force }
  Compress-Archive -Path (Join-Path $srcDir "*") -DestinationPath $zipPath -Force
}

# --- Output base ---
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$ops = Join-Path $Root "logs\ops"
New-Dir $ops

$outBase = Join-Path $ops ("KNOWLEDGE_BUNDLE_{0}" -f $ts)
$stage  = Join-Path $outBase "stage"
$zips   = Join-Path $outBase "zips"
New-Dir $stage
New-Dir $zips

# --- 1) Rolling Freeze Backups ---
$rollingStage = Join-Path $stage ("LAST{0}_ROLLING" -f $Days)
New-Dir $rollingStage

$freezeList = Select-LatestFreezeByDay -rootOps $ops
if($freezeList.Count -eq 0){
  Write-Host "WARN: No FREEZE_BACKUP_* folders found in logs\ops."
}else{
  foreach($f in $freezeList){
    $dst = Join-Path $rollingStage (Split-Path $f.FullName -Leaf)
    Safe-CopyDir -src $f.FullName -dst $dst
  }
}

# --- 2) OPS scripts bundle ---
$opsStage = Join-Path $stage "OPS_SCRIPTS"
Add-OpsScripts -root $Root -outDir $opsStage

# --- Manifest ---
$manifest = Join-Path $outBase "MANIFEST.txt"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("ROOT=$Root") | Out-Null
$lines.Add("DAYS=$Days") | Out-Null
$lines.Add("CREATED_UTC=" + (Get-Date).ToUniversalTime().ToString("o")) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("ROLLING_FOLDERS:") | Out-Null
foreach($f in $freezeList){ $lines.Add(("  {0}  {1}" -f $f.Day, (Split-Path $f.FullName -Leaf))) | Out-Null }
$lines.Add("") | Out-Null
$lines.Add("NOTES: secrets/keys/env are excluded by filter.") | Out-Null
$lines | Set-Content -Encoding UTF8 -Path $manifest

# --- Zip outputs ---
$zipRolling = Join-Path $zips ("ORG_BOT_LAST{0}_ROLLING.zip" -f $Days)
$zipOps     = Join-Path $zips "ORG_BOT_OPS_SCRIPTS.zip"

Zip-Dir -srcDir $rollingStage -zipPath $zipRolling
Zip-Dir -srcDir $opsStage     -zipPath $zipOps

$superZip = ""
if($MakeSuperZip -eq 1){
  $superDir = Join-Path $stage "SUPER"
  New-Dir $superDir
  Copy-Item $zipRolling -Destination (Join-Path $superDir (Split-Path $zipRolling -Leaf)) -Force
  Copy-Item $zipOps     -Destination (Join-Path $superDir (Split-Path $zipOps -Leaf)) -Force
  Copy-Item $manifest   -Destination (Join-Path $superDir "MANIFEST.txt") -Force

  $superZip = Join-Path $zips "ORG_BOT_KNOWLEDGE_SUPER.zip"
  Zip-Dir -srcDir $superDir -zipPath $superZip
}

Write-Host ("FOLDER_READY=" + $outBase)
Write-Host ("ZIP_ROLLING=" + $zipRolling)
Write-Host ("ZIP_OPS=" + $zipOps)
if($superZip){ Write-Host ("ZIP_SUPER=" + $superZip) }
Write-Host ("MANIFEST=" + $manifest)
