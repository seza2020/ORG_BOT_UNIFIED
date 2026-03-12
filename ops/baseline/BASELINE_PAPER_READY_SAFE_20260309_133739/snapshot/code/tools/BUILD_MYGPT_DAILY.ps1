param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [int]$RollingDays = 10,
  [int]$KeepHistory = 7,
  [int]$MaxZipMB = 490,
  [int]$RollingBudgetMB = 320,   # raw staging budget (pre-zip), keep below MaxZipMB to avoid oversize
  [int]$TailLines = 20000,
  [int]$MaxRollingFiles = 350,
  [int]$MaxSingleFileMB = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Log([string]$m){ Write-Host ("[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $m) }
function Ensure-Dir([string]$p){ if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function BytesToMB([long]$b){ [math]::Round($b/1MB,2) }

# --- Secrets safety (path/name based; skip vendor dirs) ---
$SecretPatterns = @(
  "\secrets\",
  "alpaca_env.ps1",
  "\.env",
  "api_key",
  "private_key",
  "secret_key"
)

function Assert-NoSecretPaths([string]$root){
  $SkipDirs = @("\.venv\","\__pycache__\","\.git\","\node_modules\","\dist\","\build\","_MYGPT_UPLOAD")

  $hits = Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object {
      $p = $_.FullName.ToLowerInvariant()

      foreach($sd in $SkipDirs){
        if ($p -like ("*" + $sd.ToLowerInvariant() + "*")) { return $false }
      }

      foreach($pat in $SecretPatterns){
        if ($p -like ("*" + $pat.ToLowerInvariant() + "*")) { return $true }
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

function New-Zip([string]$zipPath, [string]$baseDir, [string[]]$items, [string[]]$excludeGlobs){
  if (Test-Path -LiteralPath $zipPath){ Remove-Item -LiteralPath $zipPath -Force }
  if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)){ throw "tar.exe not found" }

  $clean = @()
  foreach($it in $items){
    if ([string]::IsNullOrWhiteSpace($it)) { continue }
    if (Test-Path -LiteralPath (Join-Path $baseDir $it)) { $clean += $it }
  }

  if ($clean.Count -eq 0){
    # create a tiny zip with a note
    $tmp = Join-Path $baseDir "_empty_zip_note.txt"
    Set-Content -LiteralPath $tmp -Encoding UTF8 -Value "EMPTY_ZIP: no valid items found"
    $args = @("-a","-c","-f",$zipPath,"-C",$baseDir,(Split-Path $tmp -Leaf))
    & tar.exe @args | Out-Null
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return
  }

  $args = @("-a","-c","-f",$zipPath,"-C",$baseDir)
  foreach($ex in $excludeGlobs){ $args += @("--exclude",$ex) }
  foreach($it in $clean){ $args += $it }

  & tar.exe @args | Out-Null
}

function Write-TailFile([string]$src, [string]$dst, [int]$tailLines){
  if (-not (Test-Path -LiteralPath $src)) { return }
  Ensure-Dir (Split-Path $dst -Parent)
  Get-Content -LiteralPath $src -Tail $tailLines -ErrorAction SilentlyContinue |
    Set-Content -LiteralPath $dst -Encoding UTF8
}

function Copy-WithBudget(
  [System.IO.FileInfo[]]$files,
  [string]$projectRoot,
  [string]$destRoot,
  [int]$budgetMB,
  [int]$maxFiles,
  [int]$maxSingleMB
){
  $budgetBytes = [int64]$budgetMB * 1MB
  $total = [int64]0
  $count = 0

  foreach($f in $files){
    if ($count -ge $maxFiles) { break }
    if (-not $f) { continue }
    if ($f.Length -le 0) { continue }
    if (($f.Length/1MB) -gt $maxSingleMB) { continue }

    $next = $total + $f.Length
    if ($next -gt $budgetBytes) { break }

    $rel = $f.FullName.Substring($projectRoot.Length).TrimStart('\')
    $dst = Join-Path $destRoot $rel
    Ensure-Dir (Split-Path $dst -Parent)
    Copy-Item -LiteralPath $f.FullName -Destination $dst -Force

    $total = $next
    $count++
  }

  Log ("BUDGET_COPY files={0} totalMB={1} budgetMB={2}" -f $count, ([math]::Round($total/1MB,2)), $budgetMB)
}

if (-not (Test-Path -LiteralPath $ProjectPath)){ throw "ProjectPath not found" }

$OutRoot = Join-Path $ProjectPath "_MYGPT_UPLOAD"
$Latest  = Join-Path $OutRoot "LATEST"
$History = Join-Path $OutRoot "HISTORY"
Ensure-Dir $Latest
Ensure-Dir $History

$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$runDir = Join-Path $History $stamp
Ensure-Dir $runDir

Log "SAFETY_SCAN_PATHS"
Assert-NoSecretPaths -root $ProjectPath

$Exclude = @(
  ".venv","__pycache__",".git",".mypy_cache",".pytest_cache",
  "node_modules","dist","build",".idea",".vscode",
  "secrets","alpaca_env.ps1",".env","*api_key*","*private_key*","*secret_key*",
  "*.pyc","*.pyo","*.tmp"
)

# STATIC (auto-filter to existing)
$StaticCodeItems = @("tbot","src","tools","configs","pyproject.toml","requirements.txt","requirements-dev.txt","README.md")
$StaticDocsItems = @("docs")
$StaticOpsItems = @("ops","runbooks","scripts","tasks","PROJECT_SNAPSHOT.md","MYGPT_BOOTSTRAP.md","docs\tasks","tools")

# Stage
$Stage = Join-Path $runDir "STAGE"
Ensure-Dir $Stage
Ensure-Dir (Join-Path $Stage "tails")
Ensure-Dir (Join-Path $Stage "rolling_files")
Ensure-Dir (Join-Path $Stage "daily_files")

# Tails (small but high-signal)
Write-TailFile -src (Join-Path $ProjectPath "logs\meta.jsonl") -dst (Join-Path $Stage "tails\meta_tail.jsonl") -tailLines $TailLines
Write-TailFile -src (Join-Path $ProjectPath "logs\shadow_plans.jsonl") -dst (Join-Path $Stage "tails\shadow_plans_tail.jsonl") -tailLines $TailLines

# Rolling candidates (bounded)
$since = (Get-Date).AddDays(-1 * [math]::Abs($RollingDays))
$logRoot = Join-Path $ProjectPath "logs"

if (Test-Path -LiteralPath $logRoot){
  $cands = Get-ChildItem -LiteralPath $logRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $since } |
    Sort-Object LastWriteTime -Descending
  Copy-WithBudget -files $cands -projectRoot $ProjectPath -destRoot (Join-Path $Stage "rolling_files") -budgetMB $RollingBudgetMB -maxFiles $MaxRollingFiles -maxSingleMB $MaxSingleFileMB
} else {
  Log "ROLLING: logs/ not found (skip)"
}

# Daily candidates (latest_daily + last few ops logs)
$dailyDirs = @(
  (Join-Path $ProjectPath "latest_daily"),
  (Join-Path $ProjectPath "latest_daily\freeze"),
  (Join-Path $ProjectPath "latest_daily\live"),
  (Join-Path $ProjectPath "dailies"),
  (Join-Path $ProjectPath "logs\ops")
)

$dailyFiles = @()
foreach($d in $dailyDirs){
  if (-not (Test-Path -LiteralPath $d)) { continue }
  $dailyFiles += Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 120
}

if ($dailyFiles.Count -gt 0){
  Copy-WithBudget -files $dailyFiles -projectRoot $ProjectPath -destRoot (Join-Path $Stage "daily_files") -budgetMB 220 -maxFiles 200 -maxSingleMB 40
}

# Build ZIPs
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

Log "BUILD_ROLLING_LAST10"
New-Zip -zipPath $z4 -baseDir $Stage -items @("tails","rolling_files") -excludeGlobs $Exclude
Assert-ZipSize -zipPath $z4 -maxMB $MaxZipMB

Log "BUILD_DAILY_LATEST"
New-Zip -zipPath $z5 -baseDir $Stage -items @("daily_files") -excludeGlobs $Exclude
Assert-ZipSize -zipPath $z5 -maxMB $MaxZipMB

# Manifest
$man = Join-Path $runDir "MANIFEST.txt"
@(
  "PROJECT_PATH=$ProjectPath"
  "STAMP=$stamp"
  "ROLLING_DAYS=$RollingDays"
  "ROLLING_BUDGET_MB=$RollingBudgetMB"
  "MAX_ZIP_MB=$MaxZipMB"
  "FILES:"
  (Split-Path $z1 -Leaf)
  (Split-Path $z2 -Leaf)
  (Split-Path $z3 -Leaf)
  (Split-Path $z4 -Leaf)
  (Split-Path $z5 -Leaf)
) | Set-Content -LiteralPath $man -Encoding UTF8

# Publish LATEST
Log "PUBLISH_LATEST"
Get-ChildItem -LiteralPath $Latest -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath $z1,$z2,$z3,$z4,$z5,$man -Destination $Latest -Force

# Cleanup history
Log "CLEANUP_HISTORY"
$dirs = Get-ChildItem -LiteralPath $History -Directory | Sort-Object Name -Descending
$drop = $dirs | Select-Object -Skip $KeepHistory
foreach($d in $drop){ Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }

Log "DONE"
Log ("LATEST_DIR={0}" -f $Latest)

