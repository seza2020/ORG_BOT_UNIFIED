param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$OpsTail = 3
)

$ErrorActionPreference = "Stop"
Set-Location $Root

$Stamp = Get-Date -Format yyyyMMdd_HHmmss
$FreezeBase = Join-Path $Root "logs\freeze"
New-Item -ItemType Directory -Force -Path $FreezeBase | Out-Null

$F = Join-Path $FreezeBase ("FREEZE_{0}" -f $Stamp)
New-Item -ItemType Directory -Force -Path $F | Out-Null

$manifest = Join-Path $F "manifest.txt"
"FREEZE_TS=$Stamp" | Set-Content -LiteralPath $manifest -Encoding UTF8
"ROOT=$Root"       | Add-Content -LiteralPath $manifest -Encoding UTF8
""                  | Add-Content -LiteralPath $manifest -Encoding UTF8

function Add-File([string]$Src, [string]$DstName) {
  if (Test-Path $Src) {
    $dst = Join-Path $F $DstName
    Copy-Item -LiteralPath $Src -Destination $dst -Force
    $fi = Get-Item $dst
    ("OK  {0}  {1} bytes  {2}" -f $DstName, $fi.Length, $fi.LastWriteTime) | Add-Content -LiteralPath $manifest -Encoding UTF8
  } else {
    ("MISS {0}  (src not found: {1})" -f $DstName, $Src) | Add-Content -LiteralPath $manifest -Encoding UTF8
  }
}

function Add-LatestOps([int]$N) {
  $opsDir = Join-Path $Root "logs\ops"
  if (-not (Test-Path $opsDir)) {
    ("MISS logs_ops_dir (not found: {0})" -f $opsDir) | Add-Content -LiteralPath $manifest -Encoding UTF8
    return
  }
  $files = Get-ChildItem -LiteralPath $opsDir -Filter "LIVE_OUT_*.txt" -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending |
           Select-Object -First $N
  if (-not $files) {
    "MISS LIVE_OUT_*.txt (no files in logs\ops)" | Add-Content -LiteralPath $manifest -Encoding UTF8
    return
  }
  foreach ($x in $files) { Add-File $x.FullName ("ops_{0}" -f $x.Name) }
}

# --- Core artifacts
Add-File (Join-Path $Root "logs\shadow_plans.jsonl") "shadow_plans.jsonl"
Add-File (Join-Path $Root "logs\meta.jsonl")        "meta.jsonl"
Add-File (Join-Path $Root "logs\announce.log")      "announce.log"

# --- Code snapshots
Add-File (Join-Path $Root "tbot\runtime\orchestrator.py")   "orchestrator.py"
Add-File (Join-Path $Root "tbot\runtime\shadow_pricing.py") "shadow_pricing.py"
Add-File (Join-Path $Root "tbot\main.py")                   "main.py"

# --- Python info (safe)
$pyInfo = Join-Path $F "python_info.txt"
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if ($py) {
  & $py -c "import sys; print(sys.version); print(sys.executable)" | Set-Content -LiteralPath $pyInfo -Encoding UTF8
  ("OK  python_info.txt  {0} bytes" -f (Get-Item $pyInfo).Length) | Add-Content -LiteralPath $manifest -Encoding UTF8
} else {
  "MISS python_info.txt (python not found on PATH)" | Add-Content -LiteralPath $manifest -Encoding UTF8
}

# --- Env snapshot (mask secrets)
$envOut = Join-Path $F "env_snapshot.txt"
$keys = @(
  "TBOT_SHADOW_PRICE_MODE","TBOT_SHADOW_STOP_PCT","TBOT_SHADOW_RR",
  "TBOT_ENABLE_S01_LOGIC","TBOT_S01_MIN_STRENGTH",
  "APCA_API_KEY_ID","APCA_API_SECRET_KEY"
)
$rows = foreach ($k in $keys) {
  $v = (Get-Item "Env:$k" -ErrorAction SilentlyContinue).Value
  if ($k -like "APCA_*") { $v = ("SET=" + [string]([bool]$v)) }
  "{0}={1}" -f $k, $v
}
$rows | Set-Content -LiteralPath $envOut -Encoding UTF8
("OK  env_snapshot.txt  {0} bytes" -f (Get-Item $envOut).Length) | Add-Content -LiteralPath $manifest -Encoding UTF8

# --- Latest ops logs (tail)
Add-LatestOps $OpsTail

# --- Zip it
$Zip = Join-Path $FreezeBase ("FREEZE_PACKAGE_{0}.zip" -f (Split-Path $F -Leaf))
if (Test-Path $Zip) { Remove-Item $Zip -Force }
Compress-Archive -Path (Join-Path $F "*") -DestinationPath $Zip -Force

Write-Host ("FROZEN_DIR={0}" -f $F)
Write-Host ("ZIP={0}" -f $Zip)
