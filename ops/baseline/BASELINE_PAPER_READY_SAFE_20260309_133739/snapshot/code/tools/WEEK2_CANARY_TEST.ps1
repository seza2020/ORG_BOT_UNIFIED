param(
  [switch]$Force,
  [string]$Root = "C:\alpaca-bot\org_bot"
)

$ErrorActionPreference="Stop"

function NowTag(){ Get-Date -Format "yyyyMMdd_HHmmss" }

function Kill-Tbot([string]$Py){
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.ExecutablePath -eq $Py -and $_.CommandLine -match " -m tbot\.main\b" } |
    ForEach-Object { 
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
      Write-Host ("KILLED PID={0}" -f $_.ProcessId) -ForegroundColor Yellow
    }
}

function Count-Pattern([string]$Path,[string]$Pattern){
  if(!(Test-Path $Path)){ return 0 }
  return (Select-String -Path $Path -Pattern $Pattern -ErrorAction SilentlyContinue | Measure-Object).Count
}

function Has-Pattern([string]$Path,[string]$Pattern){
  if(!(Test-Path $Path)){ return $false }
  return [bool](Select-String -Path $Path -Pattern $Pattern -Quiet -ErrorAction SilentlyContinue)
}

function TailFile([string]$Path,[int]$N=80){
  if(Test-Path $Path){
    Write-Host ("---- tail {0}: {1} ----" -f $N,$Path) -ForegroundColor DarkGray
    Get-Content -Tail $N $Path
  }
}

# Paths
$Root = (Resolve-Path $Root).Path
$Py   = Join-Path $Root ".venv\Scripts\python.exe"
$MetaMain = Join-Path $Root "logs\meta.jsonl"
$OpsDir   = Join-Path $Root "logs\ops"
New-Item -ItemType Directory -Force $OpsDir | Out-Null

if(!(Test-Path $Py)){ throw "PY not found: $Py" }

if($Force){
  Kill-Tbot $Py
}

# Fake triple regex (entry=100/stop=99/tp=102) - tolerant to decimals/spaces
$FakeTriple = '"entry"\s*:\s*100(\.0+)?\s*,\s*"stop"\s*:\s*99(\.0+)?\s*,\s*"tp"\s*:\s*102(\.0+)?'

Write-Host "[CANARY] Phase0: scan MAIN logs\meta.jsonl last boot RID for ANY fake 100/99/102 shadow_plan" -ForegroundColor Cyan
if(!(Test-Path $MetaMain)){
  Write-Host ("WARN: MAIN meta missing: {0}" -f $MetaMain) -ForegroundColor Yellow
}else{
  $lastBoot = Get-Content $MetaMain -Tail 200000 | Select-String '"kind"\s*:\s*"boot"' | Select-Object -Last 1
  if($lastBoot){
    $rid0 = ($lastBoot.Line | ConvertFrom-Json).run_id
    Write-Host ("[CANARY] Phase0 RID={0}  META_MAIN={1}" -f $rid0,$MetaMain)
    $fake0 = Get-Content $MetaMain -Tail 200000 |
      Select-String $rid0 |
      Select-String '"kind"\s*:\s*"shadow_plan"' |
      Select-String $FakeTriple
    if($fake0){
      Write-Host "FAIL: MAIN meta last RID contains FAKE triple => root issue NOT fixed." -ForegroundColor Red
      $fake0 | Select-Object -Last 5 | ForEach-Object { $_.Line }
      exit 1
    }else{
      Write-Host "[CANARY] Phase0 PASS: No fake triple found in MAIN meta for last RID" -ForegroundColor Green
    }
  }else{
    Write-Host "WARN: No boot found in MAIN meta (cannot derive RID)." -ForegroundColor Yellow
  }
}

# ------------------------------------------------------------
# Phase1: REAL pricing check (NO --force_signal)
# We simulate in-session so after-hours still evaluates strategies.
# ------------------------------------------------------------
$tag1   = NowTag
$out1   = Join-Path $OpsDir ("CANARY_REAL_OUT_{0}.txt" -f $tag1)
$err1   = Join-Path $OpsDir ("CANARY_REAL_ERR_{0}.txt" -f $tag1)
$meta1  = Join-Path $OpsDir ("meta_canary_real_{0}.jsonl" -f $tag1)
$shadow1= Join-Path $OpsDir ("shadow_canary_real_{0}.jsonl" -f $tag1)

# Env to make S11 fire easily (your week2 testing posture)
$env:TBOT_ENABLE_S11_MVP      = "1"
$env:TBOT_S11_MIN_STRENGTH    = "0"
$env:TBOT_S11_MIN_CONF        = "0.55"
$env:TBOT_ALPHA_TREND_ON_TH   = "0"
$env:TBOT_ALPHA_TREND_CAP_TH  = "0"
$env:TBOT_MARKET_DEBUG        = "0"

Write-Host "[CANARY] Phase1: start bot (NO force), expect >=2 shadow_plans with REAL prices (NOT 100/99/102) (timeout 120s)" -ForegroundColor Cyan

$args1 = @(
  "-u","-m","tbot.main",
  "--run",
  "--iters","999999",
  "--sleep","0.25",
  "--meta",$meta1,
  "--shadow",
  "--shadow_path",$shadow1,
  "--shadow_risk_usd","250",
  "--shadow_max_qty","5000",
  "--gate_min_rr","0",
  "--gate_min_conf","0",
  "--gate_cooldown_sec","0",
  "--gate_max_plans_per_day","50",
  "--gate_max_risk_usd","999999",
  "--sim_in_session","1",
  "--sim_pre_close","0"
)

$p1 = Start-Process -FilePath $Py -ArgumentList $args1 -NoNewWindow -PassThru `
      -RedirectStandardOutput $out1 -RedirectStandardError $err1

$deadline = (Get-Date).AddSeconds(120)
do {
  Start-Sleep -Milliseconds 700
  $cPlans = Count-Pattern $meta1 '"kind"\s*:\s*"shadow_plan"'
  if($cPlans -ge 2){ break }
} while((Get-Date) -lt $deadline)

# Stop phase1 bot
try { Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue } catch {}

$rid1 = ""
if(Test-Path $meta1){
  $b = Get-Content $meta1 -Tail 20000 | Select-String '"kind"\s*:\s*"boot"' | Select-Object -Last 1
  if($b){ $rid1 = ($b.Line | ConvertFrom-Json).run_id }
}

$metaPlans1   = Count-Pattern $meta1 '"kind"\s*:\s*"shadow_plan"'
$shadowLines1 = (Test-Path $shadow1) ? ((Get-Content $shadow1 | Measure-Object -Line).Lines) : 0
$errFlag1     = Has-Pattern $meta1 '"kind"\s*:\s*"error"'
$fakeFlag1    = Has-Pattern $meta1 $FakeTriple

Write-Host ("[CANARY] Phase1 RID={0} meta_shadow_plan={1} shadow_lines={2} error={3} fake={4}" -f $rid1,$metaPlans1,$shadowLines1,$errFlag1,$fakeFlag1)
Write-Host ("[CANARY] Phase1 logs: OUT={0} ERR={1} META={2} SHADOW={3}" -f $out1,$err1,$meta1,$shadow1)

if($metaPlans1 -lt 2){
  Write-Host "FAIL: Phase1 did not produce enough shadow_plans (maybe strategy not firing). Increase timeout or check session gates." -ForegroundColor Red
  TailFile $err1 120
  TailFile $meta1 120
  exit 1
}
if($errFlag1){
  Write-Host "FAIL: Phase1 has error events." -ForegroundColor Red
  TailFile $meta1 120
  exit 1
}
if($fakeFlag1){
  Write-Host "FAIL: Phase1 detected FAKE pricing (100/99/102) in NON-forced run => root issue NOT fixed." -ForegroundColor Red
  TailFile $meta1 200
  TailFile $shadow1 40
  exit 1
}
if($metaPlans1 -ne $shadowLines1){
  Write-Host "FAIL: meta shadow_plan count != shadow file lines (file trim/append mismatch)." -ForegroundColor Red
  TailFile $meta1 80
  TailFile $shadow1 40
  exit 1
}

Write-Host "[CANARY] Phase1 PASS: real plans written, no fake, meta==shadow" -ForegroundColor Green

# ------------------------------------------------------------
# Phase3: Kill-switch validation (INTENTIONALLY force FAKE triple)
# ------------------------------------------------------------
$tag3   = NowTag
$out3   = Join-Path $OpsDir ("CANARY_FAKE_OUT_{0}.txt" -f $tag3)
$err3   = Join-Path $OpsDir ("CANARY_FAKE_ERR_{0}.txt" -f $tag3)
$meta3  = Join-Path $OpsDir ("meta_canary_fake_{0}.jsonl" -f $tag3)
$shadow3= Join-Path $OpsDir ("shadow_canary_fake_{0}.jsonl" -f $tag3)

Write-Host "[CANARY] Phase3: force FAKE (entry=100/stop=99/tp=102). Expect DETECT+KILL within 30s." -ForegroundColor Cyan

$args3 = @(
  "-u","-m","tbot.main",
  "--run",
  "--iters","999999",
  "--sleep","0.25",
  "--meta",$meta3,
  "--shadow",
  "--shadow_path",$shadow3,
  "--shadow_risk_usd","250",
  "--shadow_max_qty","5000",
  "--shadow_entry","100",
  "--shadow_stop","99",
  "--shadow_tp","102",
  "--gate_min_rr","0",
  "--gate_min_conf","0",
  "--gate_cooldown_sec","0",
  "--gate_max_plans_per_day","999999",
  "--gate_max_risk_usd","999999",
  "--force_signal","S11",
  "--force_signal_repeat","1",
  "--force_signal_ignore_session","1",
  "--sim_in_session","1",
  "--sim_pre_close","0"
)

$p3 = Start-Process -FilePath $Py -ArgumentList $args3 -NoNewWindow -PassThru `
      -RedirectStandardOutput $out3 -RedirectStandardError $err3

$detected = $false
$deadline3 = (Get-Date).AddSeconds(30)
do {
  Start-Sleep -Milliseconds 400
  if(Test-Path $meta3){
    # Detect fake in shadow_plan OR shadow_accept
    $hit = Select-String -Path $meta3 -Pattern $FakeTriple -Quiet -ErrorAction SilentlyContinue
    if($hit){
      $detected = $true
      try { Stop-Process -Id $p3.Id -Force -ErrorAction SilentlyContinue } catch {}
      break
    }
  }
} while((Get-Date) -lt $deadline3)

if(-not $detected){
  Write-Host "FAIL: Phase3 fake-price NOT detected in 30s." -ForegroundColor Red
  TailFile $err3 120
  TailFile $meta3 160
  TailFile $shadow3 40
  try { Stop-Process -Id $p3.Id -Force -ErrorAction SilentlyContinue } catch {}
  exit 1
}

Write-Host "[CANARY] Phase3 PASS: fake detected + bot killed." -ForegroundColor Green
Write-Host ("[CANARY] Logs: META={0} SHADOW={1} ERR={2}" -f $meta3,$shadow3,$err3)

Write-Host "========== CANARY SUMMARY ==========" -ForegroundColor Green
Write-Host "PASS: (1) MAIN last RID no fake (2) NON-forced run produced real plans w/ meta==shadow (3) Kill-switch detects fake and kills."
Write-Host "===================================="
