$ErrorActionPreference = "Stop"
$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$CODE    = Join-Path $U "code"
$WRAP    = Join-Path $OPS "task_wrappers"
$MAIN    = Join-Path $CODE "tbot\main.py"
$WRAPPER = Join-Path $WRAP "ORG_UNIFIED_PAPER_RUN.ps1"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "ROOT_FIX_PACK_V2_TARGETED_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_V2_TARGETED_BUNDLE_FOUND" }

$mainBak = Join-Path $latest.FullName "source_backup\main.py.bak"
$wrapBak = Join-Path $latest.FullName "source_backup\ORG_UNIFIED_PAPER_RUN.ps1.bak"

if (!(Test-Path $mainBak)) { throw "MAIN_BACKUP_NOT_FOUND=$mainBak" }
if (!(Test-Path $wrapBak)) { throw "WRAPPER_BACKUP_NOT_FOUND=$wrapBak" }

Copy-Item -LiteralPath $mainBak -Destination $MAIN -Force
Copy-Item -LiteralPath $wrapBak -Destination $WRAPPER -Force

"ROLLBACK_OK"
("RESTORED_MAIN=" + $mainBak)
("RESTORED_WRAPPER=" + $wrapBak)
