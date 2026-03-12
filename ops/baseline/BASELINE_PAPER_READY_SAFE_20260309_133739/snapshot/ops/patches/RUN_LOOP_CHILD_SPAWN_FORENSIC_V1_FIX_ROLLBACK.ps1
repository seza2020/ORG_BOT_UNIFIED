$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U    = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS  = Join-Path $U "ops"
$EVID = Join-Path $OPS "evidence"
$MAIN = Join-Path $U "code\tbot\main.py"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "RUN_LOOP_CHILD_SPAWN_FORENSIC_V1_FIX_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_FORENSIC_BUNDLE_FOUND" }

$bak = Join-Path $latest.FullName "source_backup\main.py.bak"
if (!(Test-Path -LiteralPath $bak)) { throw "BACKUP_NOT_FOUND=$bak" }

Copy-Item -LiteralPath $bak -Destination $MAIN -Force

"ROLLBACK_OK"
("RESTORED_FROM=" + $bak)
