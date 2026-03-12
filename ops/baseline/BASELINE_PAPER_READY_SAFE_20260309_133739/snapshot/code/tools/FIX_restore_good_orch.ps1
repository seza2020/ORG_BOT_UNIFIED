$ErrorActionPreference = "Stop"

$orch = "C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py"
$tmp  = "$orch.__tmp__.py"

$baks = Get-ChildItem -Path ($orch + ".bak_*") -ErrorAction Stop |
  Sort-Object LastWriteTime -Descending

if (-not $baks) { throw "No backups found for orchestrator.py" }

$good = $null

foreach ($b in $baks) {
  Copy-Item -LiteralPath $b.FullName -Destination $tmp -Force
  python -m py_compile $tmp *> $null 2>&1
  if ($LASTEXITCODE -eq 0) {
    $good = $b.FullName
    break
  }
}

Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

if (-not $good) {
  throw "No compilable backup found. All backups fail py_compile."
}

# restore good
$bak2 = "$orch.bak_restore_" + (Get-Date).ToString("yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $orch -Destination $bak2 -Force
Copy-Item -LiteralPath $good -Destination $orch -Force

Write-Host "RESTORED_FROM=$good"
Write-Host "BACKUP_BEFORE_RESTORE=$bak2"

python -m py_compile $orch
if ($LASTEXITCODE -ne 0) { throw "Restore selected but still fails py_compile (unexpected)" }

Write-Host "COMPILE_OK=YES"
