$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U      = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPSRT  = Join-Path $U "ops"
$EVID   = Join-Path $OPSRT "evidence"
$OPS_PY = Join-Path $U "code\tbot\runtime\ops.py"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "OPS_RUNTIME_OWNER_GUARD_FIX_V1_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_FIX_BUNDLE_FOUND" }

$bak = Join-Path $latest.FullName "source_backup\ops.py.bak"
if (!(Test-Path -LiteralPath $bak)) { throw "BACKUP_NOT_FOUND=$bak" }

Copy-Item -LiteralPath $bak -Destination $OPS_PY -Force

"ROLLBACK_OK"
("RESTORED_FROM=" + $bak)
