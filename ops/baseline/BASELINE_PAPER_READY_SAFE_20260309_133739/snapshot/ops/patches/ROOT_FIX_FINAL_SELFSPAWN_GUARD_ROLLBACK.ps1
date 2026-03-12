$ErrorActionPreference = "Stop"

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$CODE    = Join-Path $U "code"
$MAIN    = Join-Path $CODE "tbot\main.py"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "ROOT_FIX_FINAL_SELFSPAWN_GUARD_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_FINAL_GUARD_BUNDLE_FOUND" }

$bak = Join-Path $latest.FullName "source_backup\main.py.bak"
if (!(Test-Path $bak)) { throw "MAIN_BACKUP_NOT_FOUND=$bak" }

Copy-Item -LiteralPath $bak -Destination $MAIN -Force

"ROLLBACK_OK"
("RESTORED_MAIN=" + $bak)
