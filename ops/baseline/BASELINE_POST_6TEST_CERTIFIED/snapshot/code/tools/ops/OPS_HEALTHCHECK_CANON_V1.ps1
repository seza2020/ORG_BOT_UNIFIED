param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$BackupDir = "C:\alpaca-bot\org_bot\logs\ops\backups\OPS_SAFE_BACKUP_V2_20260223_171730",
  [switch]$NoRestore,
  [switch]$VerboseLog
)

$ErrorActionPreference="Stop"

function _ts { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
function _log($m){ Write-Host ("[{0}] {1}" -f (_ts),$m) }

try{
  $verify  = Join-Path $BackupDir "VERIFY.ps1"
  $restore = Join-Path $BackupDir "RESTORE.ps1"

  if(!(Test-Path $verify)){ _log "FAIL VERIFY_NOT_FOUND"; exit 3 }
  if(!(Test-Path $restore)){ _log "FAIL RESTORE_NOT_FOUND"; exit 3 }

  _log "STEP1 VERIFY"
  pwsh -NoProfile -ExecutionPolicy Bypass -File $verify
  $rc1=$LASTEXITCODE

  if($rc1 -eq 0){ _log "PASS VERIFY_OK"; exit 0 }

  if($NoRestore){ _log "FAIL VERIFY_ONLY"; exit 2 }

  _log "STEP2 RESTORE"
  pwsh -NoProfile -ExecutionPolicy Bypass -File $restore
  $rcR=$LASTEXITCODE
  if($rcR -ne 0){ _log "FAIL RESTORE"; exit 4 }

  _log "STEP3 VERIFY_AGAIN"
  pwsh -NoProfile -ExecutionPolicy Bypass -File $verify
  $rc2=$LASTEXITCODE

  if($rc2 -eq 0){ _log "PASS AFTER_RESTORE"; exit 0 }

  _log "FAIL POST_RESTORE"
  exit 2
}
catch{
  _log ("UNEXPECTED " + $_.Exception.Message)
  exit 5
}
