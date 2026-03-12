$ErrorActionPreference = "Stop"

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$WRAP    = Join-Path $OPS "task_wrappers"
$EVID    = Join-Path $OPS "evidence"

$WRAPPER = Join-Path $WRAP "ORG_UNIFIED_PAPER_RUN.ps1"
$MANAGER = Join-Path $WRAP "ORG_UNIFIED_RUNTIME_MANAGER.ps1"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "ROOT_FIX_PACK_V3_TARGET_SECOND_LAUNCH_SOURCE_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_V3_BUNDLE_FOUND" }

$wrapBak = Join-Path $latest.FullName "source_backup\ORG_UNIFIED_PAPER_RUN.ps1.bak"
$mgrBak  = Join-Path $latest.FullName "source_backup\ORG_UNIFIED_RUNTIME_MANAGER.ps1.bak"

if (!(Test-Path $wrapBak)) { throw "WRAPPER_BACKUP_NOT_FOUND=$wrapBak" }
if (!(Test-Path $mgrBak))  { throw "MANAGER_BACKUP_NOT_FOUND=$mgrBak" }

Copy-Item -LiteralPath $wrapBak -Destination $WRAPPER -Force
Copy-Item -LiteralPath $mgrBak  -Destination $MANAGER -Force

"ROLLBACK_OK"
("RESTORED_WRAPPER=" + $wrapBak)
("RESTORED_MANAGER=" + $mgrBak)
