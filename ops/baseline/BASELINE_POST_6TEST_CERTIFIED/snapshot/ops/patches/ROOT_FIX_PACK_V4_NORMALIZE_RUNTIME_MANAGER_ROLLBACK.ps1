$ErrorActionPreference = "Stop"

$U        = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS      = Join-Path $U "ops"
$WRAP     = Join-Path $OPS "task_wrappers"
$EVID     = Join-Path $OPS "evidence"
$MANAGER  = Join-Path $WRAP "ORG_UNIFIED_RUNTIME_MANAGER.ps1"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "ROOT_FIX_PACK_V4_NORMALIZE_RUNTIME_MANAGER_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_V4_BUNDLE_FOUND" }

$bak = Join-Path $latest.FullName "source_backup\ORG_UNIFIED_RUNTIME_MANAGER.ps1.bak"
if (!(Test-Path $bak)) { throw "MANAGER_BACKUP_NOT_FOUND=$bak" }

Copy-Item -LiteralPath $bak -Destination $MANAGER -Force

"ROLLBACK_OK"
("RESTORED_MANAGER=" + $bak)
