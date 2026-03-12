$ErrorActionPreference = "Stop"
$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$WRAP    = Join-Path $OPS "task_wrappers"
$TARGET  = Join-Path $WRAP "ORG_UNIFIED_PAPER_RUN.ps1"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "ROOT_FIX_PACK_V1_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_ROOT_FIX_PACK_FOUND" }

$bak = Join-Path $latest.FullName "source_backup\ORG_UNIFIED_PAPER_RUN.ps1.bak"
if (!(Test-Path $bak)) { throw "BACKUP_NOT_FOUND=$bak" }

Copy-Item -LiteralPath $bak -Destination $TARGET -Force
"ROLLBACK_OK"
("RESTORED_FROM=" + $bak)
("TARGET=" + $TARGET)
