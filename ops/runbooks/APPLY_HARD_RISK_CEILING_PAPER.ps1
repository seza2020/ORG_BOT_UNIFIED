& {
  $ErrorActionPreference="Stop"

  $ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
  $CODE=Join-Path $ROOT "code"
  $RUNROOT=Join-Path $ROOT "runtime\paper"
  $EXE=Join-Path $CODE "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"

  if(!(Test-Path -LiteralPath $EXE)){ throw "EXEC_NOT_FOUND=$EXE" }
  if(!(Test-Path -LiteralPath $RUNROOT)){ throw "RUNROOT_NOT_FOUND=$RUNROOT" }

  $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
  $PDIR=Join-Path $ROOT ("ops\patches\HARD_RISK_CEILING_" + $stamp)
  $ADIR=Join-Path $ROOT ("ops\audit\HARD_RISK_CEILING_" + $stamp)
  New-Item -ItemType Directory -Force -Path $PDIR | Out-Null
  New-Item -ItemType Directory -Force -Path $ADIR | Out-Null
  Copy-Item $EXE (Join-Path $PDIR "EXECUTE_PLAN_SELECTION_PAPER_V2.ps1.bak") -Force

  $raw = Get-Content -LiteralPath $EXE -Raw -Encoding utf8
  if([string]::IsNullOrWhiteSpace($raw)){ throw "EXEC_EMPTY=$EXE" }

  if($raw -match "HARD_RISK_CEILING_BEGIN"){
    Write-Host "ALREADY_PATCHED=TRUE"
    Write-Host "EXE=$EXE"
    Write-Host "PATCH_DIR=$PDIR"
    Write-Host "AUDIT_DIR=$ADIR"
    exit 0
  }

  function Insert-AfterFirstMatch([string[]]$arr,[string]$pattern,[string[]]$block){
    $o=@(); $done=$false
    for($i=0;$i -lt $arr.Count;$i++){
      $o += $arr[$i]
      if(-not $done -and $arr[$i] -match $pattern){
        $o += $block
        $done=$true
      }
    }
    return ,@($o)
  }

  $guardBlock = @(
    "# ================================",
    "# HARD_RISK_CEILING_BEGIN",
    "# ================================",
    "",
    '$HRC_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"',
    '$HRC_CODE = Join-Path $HRC_ROOT "code"',
    '$HRC_RUNROOT = Join-Path $HRC_ROOT "runtime\paper"',
    '$env:PYTHONPATH = $HRC_CODE',
    "",
    "function HRC-ReadLedger {",
    "  param([string]$RunRoot)",
    '  $lp = Join-Path $RunRoot "state\risk\risk_ledger.json"',
    "  if(!(Test-Path -LiteralPath $lp)){ return $null }",
    "  try { return (Get-Content -LiteralPath $lp -Raw -Encoding utf8 | ConvertFrom-Json) } catch { return $null }",
    "}",
    "",
    "function HRC-Reconcile {",
    "  param([string]$RunRoot)",
    "  try {",
    '    $py = Join-Path $HRC_CODE ".venv\Scripts\python.exe"',
    "    if(!(Test-Path -LiteralPath $py)){ return }",
    "    $env:RUNROOT = $RunRoot",
    "    $code = @(",
    '      "import os",',
    '      "from tbot.runtime.risk_ledger_atomic import reconcile_ttl",',
    '      "rr=os.environ.get(""RUNROOT"") or """"",',
    '      "reconcile_ttl(rr, ttl_sec=1)",',
    '    ) -join "`n"',
    '    & $py @("-c", $code) 2>&1 | Out-Null',
    "  } catch {}",
    "}",
    "",
    "function HRC-Emit {",
    "  param([hashtable]$Obj)",
    "  try {",
    '    $ops = Join-Path $HRC_RUNROOT "logs\ops"',
    "    New-Item -ItemType Directory -Force -Path $ops | Out-Null",
    '    $p = Join-Path $ops "hard_risk_ceiling.jsonl"',
    "    ($Obj | ConvertTo-Json -Compress) | Out-File -FilePath $p -Encoding utf8 -Append",
    "  } catch {}",
    "}",
    "",
    "function HRC-Check {",
    "  param([double]$ThisRiskUsd,[string]$Rid,[double]$MaxRiskUsd)",
    "  try {",
    "    HRC-Reconcile -RunRoot $HRC_RUNROOT",
    "    $j = HRC-ReadLedger -RunRoot $HRC_RUNROOT",
    "    if($null -eq $j){ return @{ ok=$true; reason=""LEDGER_MISSING_SKIP""; used=0; reserved=0 } }",
    "    $used = 0.0; $res=0.0",
    "    try { $used=[double]$j.used_risk } catch {}",
    "    try { $res =[double]$j.reserved_risk } catch {}",
    "    $after = $used + $res + $ThisRiskUsd",
    "    if($after -gt $MaxRiskUsd){",
    "      HRC-Emit @{ ts=(Get-Date).ToString(""o""); kind=""hard_ceiling_block""; rid=$Rid; this_risk=$ThisRiskUsd; used=$used; reserved=$res; max=$MaxRiskUsd; after=$after }",
    "      return @{ ok=$false; reason=""HARD_CEILING_BLOCK""; used=$used; reserved=$res; after=$after; max=$MaxRiskUsd }",
    "    }",
    "    return @{ ok=$true; reason=""OK""; used=$used; reserved=$res; after=$after; max=$MaxRiskUsd }",
    "  } catch {",
    "    return @{ ok=$true; reason=""CHECK_ERROR_SKIP""; used=0; reserved=0 }",
    "  }",
    "}",
    "",
    "# ================================",
    "# HARD_RISK_CEILING_END",
    "# ================================"
  )

  $hook = @(
    "# === HARD_RISK_CEILING_PRE_SUBMIT_HOOK BEGIN ===",
    "try {",
    "  $rid = $null; $riskUsd = 0.0",
    "  try { if($planObj -and ($planObj.PSObject.Properties.Name -contains 'risk_rid')){ $rid = [string]$planObj.risk_rid } } catch {}",
    "  try { if($planObj -and ($planObj.PSObject.Properties.Name -contains 'risk_usd')){ $riskUsd = [double]$planObj.risk_usd } } catch {}",
    "  if([string]::IsNullOrWhiteSpace($rid)){ $rid = 'RID:MISSING' }",
    "  $max = 500.0",
    "  try { $v=[string]$env:TBOT_MAX_DAILY_RISK_USD; if(-not [string]::IsNullOrWhiteSpace($v)){ $max=[double]$v } } catch {}",
    "  $chk = HRC-Check -ThisRiskUsd $riskUsd -Rid $rid -MaxRiskUsd $max",
    "  if(-not $chk.ok){",
    "    Write-Host ('HARD_CEILING_BLOCKED rid=' + $rid + ' riskUsd=' + $riskUsd + ' used=' + $chk.used + ' reserved=' + $chk.reserved + ' max=' + $chk.max)",
    "    exit 91",
    "  }",
    "} catch {}",
    "# === HARD_RISK_CEILING_PRE_SUBMIT_HOOK END ==="
  )

  $lines = $raw -split "`r?`n"
  $out=@()
  $out += $guardBlock
  $out += ""
  $out += $lines

  $out = Insert-AfterFirstMatch $out 'kind\s*=\s*"order_intent"' $hook

  Set-Content -LiteralPath $EXE -Value ($out -join "`r`n") -Encoding utf8
  Unblock-File -LiteralPath $EXE -ErrorAction SilentlyContinue

  ($out | Select-Object -First 220) | Set-Content (Join-Path $ADIR "patched_head_220.txt") -Encoding utf8

  Write-Host "HARD_RISK_CEILING_APPLY=OK"
  Write-Host "EXE=$EXE"
  Write-Host "PATCH_DIR=$PDIR"
  Write-Host "AUDIT_DIR=$ADIR"
  Write-Host "NEXT=RUN_PAPER_PREFLIGHT_GUARDED"
}
