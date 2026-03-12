# tools\PATCH_HARD_BLOCK_FAKE_PRICE_V1.ps1
# Hard-block fake shadow pricing (forced_signal_test and 100/99/102 template)
# - Prevents any fake plan from being accepted
# - Optionally hard-stops bot immediately (default ON)
# Safe: project-only edits, creates backups.

[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference="Stop"
$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot (current: $ROOT)" }

$PY = Join-Path $ROOT ".venv\Scripts\python.exe"
if(-not (Test-Path $PY)){ throw "Missing venv python: $PY" }

$OPS = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force -Path $OPS | Out-Null
$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$BAK = Join-Path $OPS ("PATCH_FAKEPRICE_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

function Backup-File($p){
  if(Test-Path $p){
    Copy-Item -Force $p (Join-Path $BAK ([IO.Path]::GetFileName($p) + ".bak"))
  }
}

# -------------------------
# Patch 1: tbot/runtime/shadow_gate.py
#  - add allowed reason: fake_price_blocked
#  - add early check in evaluate(): forced/template => reject
# -------------------------
$gatePath = Join-Path $ROOT "tbot\runtime\shadow_gate.py"
if(-not (Test-Path $gatePath)){ throw "Missing: $gatePath" }

$gate = Get-Content -Encoding UTF8 $gatePath
$marker = "TBOT_HARD_BLOCK_FAKE_PRICE_V1"

if(($gate -join "`n") -match $marker){
  Write-Host "shadow_gate.py already patched => skip"
} else {
  Backup-File $gatePath

  # 1) ensure allowed reason exists
  $out = New-Object System.Collections.Generic.List[string]
  $insertedReason = $false
  for($i=0; $i -lt $gate.Count; $i++){
    $line = $gate[$i]
    $out.Add($line)
    if(-not $insertedReason -and $line -match '^\s*"unknown_reason",\s*$'){
      $out.Add('    "fake_price_blocked",')
      $insertedReason = $true
    }
  }
  if(-not $insertedReason -and (($out -join "`n") -notmatch '"fake_price_blocked"')){
    throw "Could not insert fake_price_blocked into _ALLOWED_REASONS (pattern not found)."
  }

  # 2) insert evaluate() guard after reasons init
  $out2 = New-Object System.Collections.Generic.List[string]
  $insertedGuard = $false
  for($i=0; $i -lt $out.Count; $i++){
    $line = $out[$i]
    $out2.Add($line)

    if(-not $insertedGuard -and $line -match '^(\s*)reasons:\s*List\[str\]\s*=\s*\[\]\s*$'){
      $ind = $matches[1]
      $out2.Add("")
      $out2.Add("${ind}# --- ${marker} BEGIN ---")
      $out2.Add("${ind}try:")
      $out2.Add("${ind}    from tbot.runtime.gate_state import is_fake_payload as _tbot_is_fake")
      $out2.Add("${ind}    _p = {")
      $out2.Add("${ind}        'reason': getattr(plan, 'reason', None),")
      $out2.Add("${ind}        'entry':  getattr(plan, 'entry',  None),")
      $out2.Add("${ind}        'stop':   getattr(plan, 'stop',   None),")
      $out2.Add("${ind}        'tp':     getattr(plan, 'tp',     None),")
      $out2.Add("${ind}    }")
      $out2.Add("${ind}    if plan is not None and _tbot_is_fake(_p):")
      $out2.Add("${ind}        reasons.append('fake_price_blocked')")
      $out2.Add("${ind}except Exception:")
      $out2.Add("${ind}    pass")
      $out2.Add("${ind}# --- ${marker} END ---")
      $out2.Add("")
      $insertedGuard = $true
    }
  }
  if(-not $insertedGuard){
    throw "Could not insert evaluate() guard (reasons line not found)."
  }

  Set-Content -Encoding UTF8 -Path $gatePath -Value $out2
  Write-Host "OK: patched => $gatePath"
}

# -------------------------
# Patch 2: tbot/runtime/orchestrator.py
#  - if fake detected AND TBOT_HARD_STOP_ON_FAKE_PRICE=1 (default), emit reject + exit
# -------------------------
$orcPath = Join-Path $ROOT "tbot\runtime\orchestrator.py"
if(-not (Test-Path $orcPath)){ throw "Missing: $orcPath" }

$orc = Get-Content -Encoding UTF8 $orcPath
if(($orc -join "`n") -match $marker){
  Write-Host "orchestrator.py already patched => skip"
} else {
  Backup-File $orcPath

  $out = New-Object System.Collections.Generic.List[string]
  $done = $false

  for($i=0; $i -lt $orc.Count; $i++){
    $line = $orc[$i]

    # insert right before gate.evaluate(...)
    if(-not $done -and $line -match '^(\s*)ok,\s*reasons\s*=\s*gate\.evaluate\(\s*$'){
      $ind = $matches[1]
      $out.Add("${ind}# --- ${marker} BEGIN ---")
      $out.Add("${ind}try:")
      $out.Add("${ind}    import os as _tbot_os")
      $out.Add("${ind}    from tbot.runtime.gate_state import is_fake_payload as _tbot_is_fake")
      $out.Add("${ind}    _p = {")
      $out.Add("${ind}        'reason': getattr(plan, 'reason', None),")
      $out.Add("${ind}        'entry':  getattr(plan, 'entry',  None),")
      $out.Add("${ind}        'stop':   getattr(plan, 'stop',   None),")
      $out.Add("${ind}        'tp':     getattr(plan, 'tp',     None),")
      $out.Add("${ind}    }")
      $out.Add("${ind}    if plan is not None and _tbot_is_fake(_p) and (_tbot_os.getenv('TBOT_HARD_STOP_ON_FAKE_PRICE','1') == '1'):")
      $out.Add("${ind}        try:")
      $out.Add("${ind}            ev = make_event(level='ERROR', kind='shadow_reject', payload={")
      $out.Add("${ind}                'sid': getattr(plan,'sid',None),")
      $out.Add("${ind}                'symbol': getattr(plan,'symbol',None),")
      $out.Add("${ind}                'side': getattr(plan,'side',None),")
      $out.Add("${ind}                'qty': getattr(plan,'qty',None),")
      $out.Add("${ind}                'entry': getattr(plan,'entry',None),")
      $out.Add("${ind}                'stop': getattr(plan,'stop',None),")
      $out.Add("${ind}                'tp': getattr(plan,'tp',None),")
      $out.Add("${ind}                'risk_usd': getattr(plan,'risk_usd',None),")
      $out.Add("${ind}                'rr': getattr(plan,'rr',None),")
      $out.Add("${ind}                'confidence': getattr(plan,'confidence',None),")
      $out.Add("${ind}                'reason': getattr(plan,'reason',None),")
      $out.Add("${ind}                'reasons': ['fake_price_blocked'],")
      $out.Add("${ind}            })")
      $out.Add("${ind}            meta.emit(ev); announce.emit(ev)")
      $out.Add("${ind}        except Exception:")
      $out.Add("${ind}            pass")
      $out.Add("${ind}        raise SystemExit('[FAKE_PRICE] hard-stop: forced/template pricing detected; refusing to accept any plan.')")
      $out.Add("${ind}except SystemExit:")
      $out.Add("${ind}    raise")
      $out.Add("${ind}except Exception:")
      $out.Add("${ind}    pass")
      $out.Add("${ind}# --- ${marker} END ---")
      $out.Add("")
      $done = $true
    }

    $out.Add($line)
  }

  if(-not $done){
    throw "Could not find insertion point (ok, reasons = gate.evaluate(...)) in orchestrator.py"
  }

  Set-Content -Encoding UTF8 -Path $orcPath -Value $out
  Write-Host "OK: patched => $orcPath"
}

# -------------------------
# Tests
# -------------------------
Write-Host ""
Write-Host "TEST 1: py_compile patched files"
& $PY -m py_compile "tbot\runtime\shadow_gate.py" "tbot\runtime\orchestrator.py"
if($LASTEXITCODE -ne 0){ throw "py_compile failed" }

Write-Host ""
Write-Host "TEST 2: gate rejects fake plan"
& $PY -c "from datetime import datetime; from types import SimpleNamespace; from tbot.runtime.shadow_gate import ShadowGate, GateConfig; g=ShadowGate(GateConfig(min_rr=1.0,min_confidence=0.0,cooldown_sec=0,max_plans_per_day=999,max_risk_usd=999999.0)); p=SimpleNamespace(entry=100.0,stop=99.0,tp=102.0,confidence=0.99,risk_usd=25.0,reason='forced_signal_test',rr=2.0); ok,reasons=g.evaluate(now=datetime.now(),plan=p,alpha_kill=False,portfolio_kill=False,in_session=True,pre_close=False); print(ok,reasons); assert (ok is False) and ('fake_price_blocked' in reasons)"
if($LASTEXITCODE -ne 0){ throw "gate fake-reject test failed" }

Write-Host ""
Write-Host "PATCH_OK. Backup dir:"
Write-Host $BAK
Write-Host ""
Write-Host "Behavior:"
Write-Host "- Any plan with reason=forced_signal_test OR exact 100/99/102 template => reject reason fake_price_blocked."
Write-Host "- If TBOT_HARD_STOP_ON_FAKE_PRICE=1 (default), orchestrator exits immediately on detection."
Write-Host "- To allow run to continue (still reject), set: `$env:TBOT_HARD_STOP_ON_FAKE_PRICE='0'"
