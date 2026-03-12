$ErrorActionPreference = "Stop"

$orch = "C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py"

function Backup-File($p) {
  $bak = "$p.bak_" + (Get-Date).ToString("yyyyMMdd_HHmmss")
  Copy-Item -LiteralPath $p -Destination $bak -Force
  return $bak
}

$bak = Backup-File $orch
Write-Host "BACKUP_ORCH=$bak"

$text = Get-Content -LiteralPath $orch -Raw

# 1) stats.bump_reason(_rsn) -> getattr(stats,"bump_reason",lambda *_:None)(_rsn)
$text2 = $text -replace "stats\.bump_reason\(\s*([^)]+?)\s*\)", "getattr(stats,'bump_reason',(lambda *_: None))($1)"

# 2) stats.bump_reason() -> getattr(stats,"bump_reason",lambda *_:None)()
$text2 = $text2 -replace "stats\.bump_reason\(\s*\)", "getattr(stats,'bump_reason',(lambda *_: None))()"

Set-Content -LiteralPath $orch -Value $text2 -Encoding UTF8

# Compile check
python -m py_compile $orch
if ($LASTEXITCODE -ne 0) { throw "py_compile failed for orchestrator.py" }

Write-Host "COMPILE_OK=YES"

# Show occurrences (sanity)
Select-String -Path $orch -Pattern "bump_reason\(" | Select-Object -First 20
