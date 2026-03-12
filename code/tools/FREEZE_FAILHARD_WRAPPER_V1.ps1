param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [Parameter(Mandatory=$true)][string]$InnerFreezeScript,
  [int]$TimeoutSec = 180
)

$ErrorActionPreference="Stop"

function LatestBackupDir([string]$runRoot){
  $ops = Join-Path $runRoot "logs\ops"
  if(!(Test-Path $ops)){ throw "ops dir missing: $ops" }
  $d = Get-ChildItem $ops -Directory -Filter "FREEZE_BACKUP_*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
  if(!$d){ throw "No FREEZE_BACKUP_* found under: $ops" }
  return $d.FullName
}

# 1) Run the inner freeze
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass `
  -File $InnerFreezeScript -ProjectRoot $ProjectRoot -RunRoot $RunRoot -TimeoutSec $TimeoutSec

$innerExit = $LASTEXITCODE

# 2) Locate latest backup dir
$bk = LatestBackupDir $RunRoot

# 3) Enforce required artifacts (Fail-Hard)
$required = @(
  "QC_*.txt",
  "CONFIG_GATES_*.txt",
  "POLICY_SNAPSHOT_*.md",
  "KPI_*.json",
  "REALIZED_KPI_*.json",
  "DAILY_BRIEF_*.md"
)

$missing = @()
foreach($pat in $required){
  $hit = Get-ChildItem $bk -File -Filter $pat -ErrorAction SilentlyContinue | Select-Object -First 1
  if(!$hit){ $missing += $pat }
}

if($missing.Count -gt 0){
  "FAIL_HARD_MISSING=" + ($missing -join ",")
  "BACKUP_DIR=$bk"
  exit 1
}

# If inner freeze already failed, preserve that failure
if($innerExit -ne 0){
  "INNER_FREEZE_EXIT=$innerExit"
  exit $innerExit
}

"OK_FAILHARD_ALL_REQUIRED_PRESENT"
"BACKUP_DIR=$bk"
exit 0
