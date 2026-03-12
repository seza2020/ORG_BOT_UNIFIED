# tools\TEST_STRICT_LAST_AND_FAKE_BLOCK.ps1
[CmdletBinding()]
param()

$ErrorActionPreference="Stop"
$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot" }

$PY = Join-Path $ROOT ".venv\Scripts\python.exe"
if(-not (Test-Path $PY)){ throw "Missing venv python: $PY" }

Write-Host "TEST 1: main marker (persist cap) + enforce marker"
Select-String -Path ".\tbot\main.py" -Pattern "TBOT_PERSIST_CAP_V1" -ErrorAction Stop | Out-Null
Select-String -Path ".\tbot\main.py" -Pattern "TBOT_ENFORCE_SHADOW_LAST_V1" -ErrorAction Stop | Out-Null
Write-Host "OK markers present"

Write-Host ""
Write-Host "TEST 2: strict-last raises no_market_last"
& $PY -c "import os; os.environ['TBOT_SHADOW_PRICE_MODE']='last'; os.environ['TBOT_SHADOW_LAST_STRICT']='1'; from tbot.runtime.shadow_pricing import compute_shadow_prices; 
class S: pass
class M: pass
m=M(); m.SPY=S()
try:
    compute_shadow_prices(sig_payload={'symbol':'SPY','side':'LONG'}, market=m, default_entry=100.0, default_stop=99.0, default_tp=102.0)
    raise SystemExit('FAIL expected RuntimeError(no_market_last)')
except RuntimeError as e:
    print('OK', str(e))"

Write-Host ""
Write-Host "TEST 3: gate blocks fake template"
& $PY -c "from datetime import datetime; from types import SimpleNamespace; from tbot.runtime.shadow_gate import ShadowGate, GateConfig; g=ShadowGate(GateConfig(min_rr=1.0,min_confidence=0.0,cooldown_sec=0,max_plans_per_day=999,max_risk_usd=999999.0)); 
p=SimpleNamespace(entry=100.0,stop=99.0,tp=102.0,confidence=0.99,risk_usd=25.0,reason='forced_signal_test',rr=2.0);
ok,reasons=g.evaluate(now=datetime.now(),plan=p,alpha_kill=False,portfolio_kill=False,in_session=True,pre_close=False);
print(ok,reasons); assert (ok is False) and ('fake_price_blocked' in reasons)"

Write-Host ""
Write-Host "ALL_TESTS_PASS"
