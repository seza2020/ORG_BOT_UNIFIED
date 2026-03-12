param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [switch]$RotateAfter
)

# --- GUARD: DO NOT ROTATE/FREEZE DURING SESSION (PT) ---
$now = Get-Date
$h = $now.Hour
$m = $now.Minute

$inBlock =
  ($h -gt 6 -and $h -lt 13) -or
  ($h -eq 6 -and $m -ge 25) -or
  ($h -eq 13 -and $m -lt 5)

if ($inBlock) {
  throw "GUARD: Freeze/Rotate blocked during 06:25-13:05 PT window."
}

if ($RotateAfter) {
  throw "RotateAfter is disabled. Use FROM_META recovery + shadow_daily instead."
}


$ErrorActionPreference = "Stop"
Set-Location $Root

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$FreezeDir = Join-Path $Root ("logs\freeze\FREEZE_{0}" -f $Stamp)
New-Item -ItemType Directory -Force $FreezeDir | Out-Null

# Copy core logs
$FilesToCopy = @(
  (Join-Path $Root "logs\shadow_plans.jsonl"),
  (Join-Path $Root "logs\meta.jsonl"),
  (Join-Path $Root "logs\announce.log")
)

foreach ($f in $FilesToCopy) {
  if (Test-Path $f) { Copy-Item -Force $f $FreezeDir }
}

# Copy ALL ops logs from today (local)
$OpsDir = Join-Path $Root "logs\ops"
if (Test-Path $OpsDir) {
  $today = (Get-Date).Date
  Get-ChildItem $OpsDir -Filter "LIVE_OUT_*.txt" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime.Date -eq $today } |
    Copy-Item -Force -Destination $FreezeDir
}

# Env snapshot (no secrets)
$envSnap = Join-Path $FreezeDir "env_snapshot.txt"
@(
  "timestamp=$Stamp",
  ("python=" + (python -V 2>&1)),
  ("python_exe=" + (python -c "import sys; print(sys.executable)" 2>&1)),
  ""
  "TBOT_*:"
) | Set-Content -LiteralPath $envSnap -Encoding UTF8

Get-ChildItem Env:TBOT_* -ErrorAction SilentlyContinue |
  Sort-Object Name |
  ForEach-Object { "{0}={1}" -f $_.Name, $_.Value } |
  Add-Content -LiteralPath $envSnap -Encoding UTF8

# Zip
$ZipPath = Join-Path $Root ("logs\freeze\FREEZE_PACKAGE_{0}.zip" -f $Stamp)
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Compress-Archive -Path (Join-Path $FreezeDir "*") -DestinationPath $ZipPath -Force

Write-Host ("FROZEN_DIR={0}" -f $FreezeDir) -ForegroundColor Green
Write-Host ("ZIP={0}" -f $ZipPath) -ForegroundColor Green

# if ($RotateAfter) {
#   $plans = Join-Path $Root "logs\shadow_plans.jsonl"
#   if (Test-Path $plans) {
#     $arch = Join-Path $Root ("logs\shadow_plans_{0}.jsonl" -f $Stamp)
#     Move-Item -Force $plans $arch
#     New-Item -ItemType File -Force $plans | Out-Null
#     Write-Host ("ROTATED shadow_plans to {0}" -f $arch) -ForegroundColor Yellow
#   }
}

