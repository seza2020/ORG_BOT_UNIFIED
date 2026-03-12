$ErrorActionPreference = "Stop"
$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$WRAP    = Join-Path $OPS "task_wrappers"
$CODE    = Join-Path $U "code"
$EVID    = Join-Path $OPS "evidence"

$MANAGER = Join-Path $WRAP "ORG_UNIFIED_RUNTIME_MANAGER.ps1"
$SITE    = Join-Path $CODE "sitecustomize.py"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "V6_REAPPLY_WITH_PRESENCE_VERIFY_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_V6_REAPPLY_BUNDLE_FOUND" }

$mgrBak  = Join-Path $latest.FullName "source_backup\ORG_UNIFIED_RUNTIME_MANAGER.ps1.bak"
$siteBak = Join-Path $latest.FullName "source_backup\sitecustomize.py.bak"

if (!(Test-Path $mgrBak))  { throw "MANAGER_BACKUP_NOT_FOUND=$mgrBak" }
if (!(Test-Path $siteBak)) { throw "SITECUSTOMIZE_BACKUP_NOT_FOUND=$siteBak" }

Copy-Item -LiteralPath $mgrBak  -Destination $MANAGER -Force
Copy-Item -LiteralPath $siteBak -Destination $SITE -Force

"ROLLBACK_OK"
("RESTORED_MANAGER=" + $mgrBak)
("RESTORED_SITECUSTOMIZE=" + $siteBak)
