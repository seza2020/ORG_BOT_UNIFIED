$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$WRAPDIR = Join-Path $OPS "task_wrappers"
$MANAGER = Join-Path $WRAPDIR "ORG_UNIFIED_RUNTIME_MANAGER.ps1"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "GUARD_BYPASS_CANONICAL_FIX_V1_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_GUARD_BYPASS_BUNDLE_FOUND" }

$bak = Join-Path $latest.FullName "source_backup\ORG_UNIFIED_RUNTIME_MANAGER.ps1.bak"
if (!(Test-Path -LiteralPath $bak)) { throw "MANAGER_BACKUP_NOT_FOUND=$bak" }

Copy-Item -LiteralPath $bak -Destination $MANAGER -Force

"ROLLBACK_OK"
("RESTORED_FROM=" + $bak)
