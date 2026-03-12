param(
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$state = Join-Path $RunRoot "state"
$ops   = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $ops | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$bk = Join-Path $ops ("BOOT_GUARD_RESET_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $bk | Out-Null

"=== RESET_BOOT_GUARD_PAPER_V1 ==="
"RunRoot=$RunRoot"
"BackupDir=$bk"

# 1) Kill any python from our venv that might be stuck
$venvPy = "C:\alpaca-bot\org_bot\.venv\Scripts\python.exe"
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like "*$venvPy*" } |
  ForEach-Object {
    "KILL pid=$($_.ProcessId) cmd=$($_.CommandLine)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }

# 2) Backup + remove volatile state files (lock/pid/hb)
$volatile = @(
  (Join-Path $state "locks\RUN_PAPER_PROFILE.lock"),
  (Join-Path $state "pid.txt"),
  (Join-Path $state "heartbeat.json"),
  (Join-Path $state "heartbeat_err.txt")
)
foreach($p in $volatile){
  if(Test-Path -LiteralPath $p){
    Copy-Item -LiteralPath $p -Destination $bk -Force
    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    "CLEARED_VOLATILE=$p"
  }
}

# 3) Find & reset boot/gate counters in state directory (backup then delete)
if(!(Test-Path -LiteralPath $state)){
  "STATE_DIR_MISSING=$state"
  exit 0
}

$hits = Get-ChildItem -LiteralPath $state -Recurse -Force -File |
  Where-Object {
    $_.Name -match "boot|guard|gate|counter|state" -or $_.FullName -match "boot|guard|gate|counter|state"
  }

"STATE_CANDIDATES={0}" -f @($hits).Count
foreach($f in $hits){
  # backup
  $rel = $f.FullName.Substring($state.Length).TrimStart("\")
  $dstDir = Join-Path $bk (Split-Path $rel -Parent)
  New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
  Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dstDir $f.Name) -Force

  # delete to force fresh state tomorrow
  Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
  "RESET_STATE_FILE={0}" -f $f.FullName
}

"=== RESET DONE ==="

