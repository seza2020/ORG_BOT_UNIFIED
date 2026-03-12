$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U        = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS      = Join-Path $U "ops"
$EVID     = Join-Path $OPS "evidence"
$WRAPDIR  = Join-Path $OPS "task_wrappers"
$LAUNCHER = Join-Path $WRAPDIR "CANONICAL_TASK_XML_LAUNCHER_V1.ps1"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "MANAGER_CHAIN_REENTRY_FIX_V1_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_MANAGER_CHAIN_REENTRY_BUNDLE_FOUND" }

$bak = Join-Path $latest.FullName "source_backup\CANONICAL_TASK_XML_LAUNCHER_V1.ps1.bak"
if (!(Test-Path -LiteralPath $bak)) { throw "LAUNCHER_BACKUP_NOT_FOUND=$bak" }

Copy-Item -LiteralPath $bak -Destination $LAUNCHER -Force

"ROLLBACK_OK"
("RESTORED_FROM=" + $bak)
