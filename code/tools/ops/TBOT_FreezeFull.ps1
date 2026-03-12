param(
  [string]$Root = "C:\alpaca-bot\org_bot"
)

$ErrorActionPreference = "Stop"
Set-Location $Root

$FreezeBase = Join-Path $Root "logs\freeze"
$null = New-Item -ItemType Directory -Force -Path $FreezeBase

$stamp = Get-Date -Format yyyyMMdd_HHmmss
$dir = Join-Path $FreezeBase ("FREEZE_{0}" -f $stamp)
$null = New-Item -ItemType Directory -Force -Path $dir

function Copy-IfExists([string]$p, [string]$dstDir) {
  if (Test-Path $p) { Copy-Item $p -Destination $dstDir -Force }
}

# 1) Latest LIVE_OUT
$opsDir = Join-Path $Root "logs\ops"
$latestOut = $null
if (Test-Path $opsDir) {
  $latestOut = Get-ChildItem $opsDir -Filter "LIVE_OUT_*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if ($latestOut) { Copy-Item $latestOut.FullName $dir -Force }

# 2) Core logs
Copy-IfExists (Join-Path $Root "logs\shadow_plans.jsonl") $dir
Copy-IfExists (Join-Path $Root "logs\meta.jsonl")         $dir
Copy-IfExists (Join-Path $Root "logs\announce.log")       $dir

# 3) Code snapshot (optional but useful for audits)
Copy-IfExists (Join-Path $Root "tbot\runtime\shadow_pricing.py") $dir
Copy-IfExists (Join-Path $Root "tbot\runtime\orchestrator.py")   $dir

# 4) Env snapshot (no secrets; only presence flags)
$envOut = Join-Path $dir "env_snapshot.txt"
$vars = @(
  "PYTHONSAFEPATH","PYTHONIOENCODING","PYTHONNOUSERSITE",
  "TBOT_SHADOW_PRICE_MODE","TBOT_SHADOW_STOP_PCT","TBOT_SHADOW_RR",
  "TBOT_ENABLE_S01_LOGIC","TBOT_S01_MIN_STRENGTH",
  "TBOT_FILELOG_PATH"
)

$lines = New-Object System.Collections.Generic.List[string]
foreach ($v in $vars) {
  $val = (Get-Item "Env:$v" -ErrorAction SilentlyContinue).Value
  $lines.Add("$v=$val")
}

$k1 = [bool]((Get-Item Env:APCA_API_KEY_ID -ErrorAction SilentlyContinue).Value)
$k2 = [bool]((Get-Item Env:APCA_API_SECRET_KEY -ErrorAction SilentlyContinue).Value)
$lines.Add("APCA_API_KEY_ID_PRESENT=$k1")
$lines.Add("APCA_API_SECRET_KEY_PRESENT=$k2")

Set-Content -LiteralPath $envOut -Value $lines -Encoding UTF8

# 5) Zip it
$zip = Join-Path $FreezeBase ("FREEZE_PACKAGE_{0}.zip" -f $stamp)
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $dir "*") -DestinationPath $zip -Force

"FROZEN_DIR=$dir"
"ZIP=$zip"
