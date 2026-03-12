$ErrorActionPreference = "Stop"

$orch = "C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py"

$bak = "$orch.bak_patch_" + (Get-Date).ToString("yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $orch -Destination $bak -Force
Write-Host "BACKUP=$bak"

$t = Get-Content -LiteralPath $orch -Raw

# جایگزینی‌های دقیق و کم‌ریسک
$t2 = $t.Replace("stats.bump_reason(_rsn)", "getattr(stats,'bump_reason',(lambda *_: None))(_rsn)")
$t2 = $t2.Replace("stats.bump_reason()",     "getattr(stats,'bump_reason',(lambda *_: None))()")

Set-Content -LiteralPath $orch -Value $t2 -Encoding UTF8

python -m py_compile $orch
if ($LASTEXITCODE -ne 0) { throw "py_compile failed after bump_reason patch" }

Write-Host "COMPILE_OK=YES"
Select-String -Path $orch -Pattern "bump_reason" | Select-Object -First 20
