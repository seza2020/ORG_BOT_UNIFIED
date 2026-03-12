param(
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

$ops = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $ops | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$bak = Join-Path $ops ("BOOT_GUARD_RESET_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $bak | Out-Null

"=== RESET_BOOT_GUARD_PAPER_V2 ==="
"RunRoot=$RunRoot"
"BackupDir=$bak"

# Targets (ONLY inside RunRoot\state)
$bg = Join-Path $RunRoot "state\boot_guard.json"
$wd = Join-Path $RunRoot "state\watchdog"
$pidFile = Join-Path $RunRoot "state\pid.txt"
$hb  = Join-Path $RunRoot "state\heartbeat.json"
$herr= Join-Path $RunRoot "state\heartbeat_err.txt"

# 1) Backup existing files (if exist)
$targets = @($bg, $pidFile, $hb, $herr)
foreach($t in $targets){
  if(Test-Path -LiteralPath $t){
    Copy-Item -Force -LiteralPath $t -Destination (Join-Path $bak (Split-Path $t -Leaf))
    "BACKUP=" + $t
  }
}

# Backup watchdog restart counters (if any)
if(Test-Path -LiteralPath $wd){
  $wdFiles = Get-ChildItem -Path $wd -File -Force -ErrorAction SilentlyContinue
  foreach($f in $wdFiles){
    Copy-Item -Force -LiteralPath $f.FullName -Destination (Join-Path $bak ("watchdog_" + $f.Name))
    "BACKUP_WD=" + $f.FullName
  }
}

# 2) Hard reset boot_guard.json to today boots=0
# Use UTC date because gate_state uses UTC for audit/reset
$todayUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$payload = @{ day = $todayUtc; boots = 0 } | ConvertTo-Json -Compress
New-Item -ItemType Directory -Force -Path (Join-Path $RunRoot "state") | Out-Null
Set-Content -Encoding UTF8 -LiteralPath $bg -Value $payload
"RESET_BG=" + $bg
"BG_NOW=" + (Get-Content -Raw -LiteralPath $bg).Trim()

# 3) Optional: clear watchdog restart file for today (prevents re-increment loop)
if(Test-Path -LiteralPath $wd){
  $todayTag = (Get-Date).ToString("yyyyMMdd")
  $rst = Join-Path $wd ("restarts_{0}.txt" -f $todayTag)
  if(Test-Path -LiteralPath $rst){
    Copy-Item -Force -LiteralPath $rst -Destination (Join-Path $bak ("watchdog_" + (Split-Path $rst -Leaf)))
    Clear-Content -LiteralPath $rst
    "CLEARED_WD_RESTARTS=" + $rst
  } else {
    "WD_RESTARTS_NOT_FOUND=" + $rst
  }
} else {
  "WD_DIR_NOT_FOUND=" + $wd
}

"=== RESET DONE ==="

