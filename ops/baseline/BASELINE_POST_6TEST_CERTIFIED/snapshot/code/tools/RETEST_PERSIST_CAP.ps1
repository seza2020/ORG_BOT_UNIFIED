# tools\RETEST_PERSIST_CAP.ps1
[CmdletBinding()]
param()

$ErrorActionPreference="Stop"
$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot" }

$PY = Join-Path $ROOT ".venv\Scripts\python.exe"
if(-not (Test-Path $PY)){ throw "Missing venv python: $PY" }

Write-Host "TEST A: marker in main.py"
Select-String -Path ".\tbot\main.py" -Pattern "TBOT_PERSIST_CAP_V1" -ErrorAction Stop | Out-Null
Write-Host "OK marker found"

Write-Host ""
Write-Host "TEST B: import gate_state"
& $PY -c "import tbot.runtime.gate_state as gs; print('import_ok')"
if($LASTEXITCODE -ne 0){ throw "TEST B failed" }

Write-Host ""
Write-Host "TEST C: meta_stats(today)"
& $PY -c "import os; from tbot.runtime.gate_state import meta_stats; print(meta_stats(os.path.join(os.getcwd(),'logs','meta.jsonl')))"
if($LASTEXITCODE -ne 0){ throw "TEST C failed" }

Write-Host ""
Write-Host "TEST D: synthetic remaining-cap (FIXED newline)"
& $PY -c "import os, json, tempfile; from argparse import Namespace; from datetime import date; from tbot.runtime.gate_state import apply_persistent_gate_limits; tmp=tempfile.mkdtemp(); os.makedirs(os.path.join(tmp,'logs'),exist_ok=True); mp=os.path.join(tmp,'logs','meta.jsonl'); day=date(2030,1,1); lines=[json.dumps({'ts':'2030-01-01T07:00:00-08:00','kind':'shadow_accept','payload':{'entry':10,'stop':9,'tp':12,'reason':'ok','risk_usd':25,'symbol':'SPY'}}) for _ in range(3)]; open(mp,'w',encoding='utf-8').write('\n'.join(lines)+'\n'); args=Namespace(gate_max_plans_per_day=5, gate_max_risk_usd=200.0); apply_persistent_gate_limits(args, root_dir=tmp, allow_fake_start=True, day_pt=day); print('effective_cap', args.gate_max_plans_per_day); assert args.gate_max_plans_per_day==2; print('synth_ok')"
if($LASTEXITCODE -ne 0){ throw "TEST D failed" }

Write-Host ""
Write-Host "ALL_TESTS_PASS"
