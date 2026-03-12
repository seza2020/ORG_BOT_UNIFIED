param(
  [string]$Root="C:\alpaca-bot\org_bot"
)
$ErrorActionPreference="Stop"
$orch = Join-Path $Root "tbot\runtime\orchestrator.py"
if(!(Test-Path -LiteralPath $orch)){ throw "ORCH_NOT_FOUND=$orch" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$bkpDir = Join-Path $Root ("logs\ops\patches\OS_SHADOW_PATCH_" + $stamp)
New-Item -ItemType Directory -Force -Path $bkpDir | Out-Null
Copy-Item -Force -LiteralPath $orch -Destination (Join-Path $bkpDir "orchestrator.py")

$txt = Get-Content -LiteralPath $orch -Raw

# Replace ONLY the known failure pattern: os.getenv("TBOT_DEBUG_TIME")
if($txt -match 'os\.getenv\("TBOT_DEBUG_TIME"\)'){
  $txt = $txt -replace 'os\.getenv\("TBOT_DEBUG_TIME"\)', '__import__("os").getenv("TBOT_DEBUG_TIME")'
  Set-Content -Encoding UTF8 -LiteralPath $orch -Value $txt
  "OK: PATCHED os.getenv(TBOT_DEBUG_TIME) => __import__('os').getenv"
  "BKP_DIR=$bkpDir"
} else {
  "NO_MATCH: os.getenv(TBOT_DEBUG_TIME) not found (maybe already patched or moved)."
  "BKP_DIR=$bkpDir"
}
