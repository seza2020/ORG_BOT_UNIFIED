param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [int]$RollingDays = 10,
  [int]$KeepHistory = 5,
  [int]$MaxZipMB = 490
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Log([string]$m){ Write-Host ("[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $m) }

function Ensure-Dir([string]$p){
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function BytesToMB([long]$b){ [math]::Round($b/1MB,2) }

# --- Safety: detect secret-like paths (name/path based, fast) ---
$SecretPatterns = @("secrets","alpaca_env.ps1",".env","token","api_key","private_key")

function Assert-NoSecretPaths([string]$root){
  $hits = Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object {
      $p = $_.FullName.ToLowerInvariant()
      foreach($pat in $SecretPatterns){
        if ($p -like ("*" + $pat + "*")) { return $true }
      }
      return $false
    } | Select-Object -First 50

  if ($hits){
    foreach($h in $hits){ Write-Host ("SECRET_HIT:{0}" -f $h.FullName) }
    throw "SECRET_HIT: aborting packaging"
  }
}

function Assert-ZipSize([string]$zipPath, [int]$maxMB){
  $len = (Get-Item -LiteralPath $zipPath).Length
  $mb = BytesToMB $len
  Log ("ZIP_SIZE_MB {0} = {1}" -f (Split-Path $zipPath -Leaf), $mb)
  if ($mb -gt $maxMB){ throw ("ZIP_TOO_LARGE: {0}MB > {1}MB ({2})" -f $mb,$maxMB,$zipPath) }
}

function Write-TailFile([string]$src, [string]$dst, [int]$tailLines){
  if (-not (Test-Path -LiteralPath $src)) { return }
  $dir = Split-Path $dst -Parent
  Ensure-Dir $dir
  Get-Content -LiteralPath $src -Tail $tailLines -ErrorAction SilentlyContinue |
    Set-Content -LiteralPath $dst -Encoding UTF8
}

function New-Zip([string]$zipPath, [string]$baseDir, [string[]]$items, [string[]]$excludeGlobs){
  if (Test-Path -LiteralPath $zipPath){ Remove-Item -LiteralPath $zipPath -Force }
  $tar = (Get-Command tar.exe -ErrorAction SilentlyContinue)
  if (-not $tar){ throw "tar.exe not found (Windows tar is required)" }

  $args = @("-a","-c","-f",$zipPath,"-C",$baseDir)
  foreach($ex in $excludeGlobs){ $args += @("--exclude",$ex) }
  foreach($it in $items){ $args += $it }

  & tar.exe @args | Out-Null
}

# --- Paths ---
if (-not (Test-Path -LiteralPath $ProjectPath)){ throw "ProjectPath not found" }

$OutRoot = Join-Path $ProjectPath "_MYGPT_UPLOAD"
$Latest  = Join-Path $OutRoot "LATEST"
$History = Join-Path $OutRoot "HISTORY"
Ensure-Dir $Latest
Ensure-Dir $History

$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$runDir = Join-Path $History $stamp
Ensure-Dir $runDir

# --- Safety scan ---
Log "SAFETY_SCAN_PATHS"
Assert-NoSecretPaths -root $ProjectPath

# --- Excludes (global) ---
$Exclude = @(
  ".venv","__pycache__",".git",".mypy_cache",".pytest_cache",
  "node_modules","dist","build",".idea",".vscode",
  "secrets","alpaca_env.ps1",".env","*token*","*api_key*","*private_key*",
  "*.pyc","*.pyo","*.log.old","*.tmp"
)

# --- Package definitions (edit the include lists to match your repo) ---
$StaticCodeItems = @(
  "tbot","src","tools","configs",
  "pyproject.toml","requirements.txt","requirements-dev.txt","README.md"
)

$StaticDocsItems = @(
  "docs"
)

$StaticOpsItems = @(
  "ops","runbooks","scripts","tasks",
  "PROJECT_SNAPSHOT.md","MYGPT_BOOTSTRAP.md"
)

# Rolling and Daily: build a small staging folder with tails + selected recent files
$Stage = Join-Path $runDir "STAGE"
Ensure-Dir $Stage

# Tail big files into stage (reduce size)
Write-TailFile -src (Join-Path $ProjectPath "logs\meta.jsonl") -dst (Join-Path $Stage "tails\meta_tail.jsonl") -tailLines 20000
Write-TailFile -src (Join-Path $ProjectPath "logs\shadow_plans.jsonl") -dst (Join-Path $Stage "tails\shadow_plans_tail.jsonl") -tailLines 20000

# Copy recent logs (by date window)
$since = (Get-Date).AddDays(-1 * [math]::Abs($RollingDays))
$Recent = @()
$logRoot = Join-Path $ProjectPath "logs"
if (Test-Path -LiteralPath $logRoot){
  $Recent += Get-ChildItem -LiteralPath $logRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $since } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 400
}

foreach($f in $Recent){
  $rel = $f.FullName.Substring($ProjectPath.Length).TrimStart('\')
  $dst = Join-Path $Stage "rolling_files\$rel"
  Ensure-Dir (Split-Path $dst -Parent)
  Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
}

# Daily: latest run artifacts (pick latest by pattern if exist)
$DailyStage = Join-Path $Stage "daily_files"
Ensure-Dir $DailyStage

$pick = @(
  "logs\ops\SHADOW_OUT_*.txt",
  "logs\ops\SHADOW_ERR_*.txt",
  "logs\ops\QC_*.txt",
  "logs\freeze\*.zip",
  "logs\live\LIVE_OUT_*.txt",
  "logs\live\LIVE_ERR_*.txt",
  "dailies\*.zip"
)

foreach($pat in $pick){
  $full = Join-Path $ProjectPath $pat
  $dir  = Split-Path $full -Parent
  $leaf = Split-Path $full -Leaf
  if (Test-Path -LiteralPath $dir){
    $last = Get-ChildItem -LiteralPath $dir -File -Filter $leaf -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 3
    foreach($lf in $last){
      $rel = $lf.FullName.Substring($ProjectPath.Length).TrimStart('\')
      $dst = Join-Path $DailyStage $rel
      Ensure-Dir (Split-Path $dst -Parent)
      Copy-Item -LiteralPath $lf.FullName -Destination $dst -Force
    }
  }
}

# --- Build zips ---
$z1 = Join-Path $runDir "MYGPT_STATIC_CODE.zip"
$z2 = Join-Path $runDir "MYGPT_STATIC_DOCS.zip"
$z3 = Join-Path $runDir "MYGPT_STATIC_OPS.zip"
$z4 = Join-Path $runDir "MYGPT_ROLLING_LAST10.zip"
$z5 = Join-Path $runDir "MYGPT_DAILY_LATEST.zip"

Log "BUILD_STATIC_CODE"
New-Zip -zipPath $z1 -baseDir $ProjectPath -items $StaticCodeItems -excludeGlobs $Exclude
Assert-ZipSize -zipPath $z1 -maxMB $MaxZipMB

Log "BUILD_STATIC_DOCS"
New-Zip -zipPath $z2 -baseDir $ProjectPath -items $StaticDocsItems -excludeGlobs $Exclude
Assert-ZipSize -zipPath $z2 -maxMB $MaxZipMB

Log "BUILD_STATIC_OPS"
New-Zip -zipPath $z3 -baseDir $ProjectPath -items $StaticOpsItems -excludeGlobs $Exclude
Assert-ZipSize -zipPath $z3 -maxMB $MaxZipMB

Log "BUILD_ROLLING_LAST10 (from stage)"
New-Zip -zipPath $z4 -baseDir $Stage -items @("tails","rolling_files") -excludeGlobs $Exclude
Assert-ZipSize -zipPath $z4 -maxMB $MaxZipMB

Log "BUILD_DAILY_LATEST (from stage)"
New-Zip -zipPath $z5 -baseDir $Stage -items @("daily_files") -excludeGlobs $Exclude
Assert-ZipSize -zipPath $z5 -maxMB $MaxZipMB

# --- Manifest ---
$man = Join-Path $runDir "MANIFEST.txt"
@(
  "PROJECT_PATH=$ProjectPath"
  "STAMP=$stamp"
  "ROLLING_DAYS=$RollingDays"
  "MAX_ZIP_MB=$MaxZipMB"
  "FILES:"
  (Split-Path $z1 -Leaf)
  (Split-Path $z2 -Leaf)
  (Split-Path $z3 -Leaf)
  (Split-Path $z4 -Leaf)
  (Split-Path $z5 -Leaf)
) | Set-Content -LiteralPath $man -Encoding UTF8

# --- Publish to LATEST (overwrite) ---
Log "PUBLISH_LATEST"
Get-ChildItem -LiteralPath $Latest -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath $z1,$z2,$z3,$z4,$z5,$man -Destination $Latest -Force

# --- Cleanup old history ---
Log "CLEANUP_HISTORY"
$dirs = Get-ChildItem -LiteralPath $History -Directory | Sort-Object Name -Descending
$keep = $dirs | Select-Object -First $KeepHistory
$drop = $dirs | Select-Object -Skip $KeepHistory
foreach($d in $drop){ Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }

Log "DONE: LATEST ready for upload"
Log ("LATEST_DIR={0}" -f $Latest)
