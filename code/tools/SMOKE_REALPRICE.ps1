param(
  [switch]$KillRunning,
  [int]$TimeoutSec = 120,
  [int]$SleepSec = 5
)

$ErrorActionPreference="Stop"
$ROOT   = "C:\alpaca-bot\org_bot"
$PY     = Join-Path $ROOT ".venv\Scripts\python.exe"
$OPS    = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force -Path $OPS | Out-Null
Set-Location $ROOT

function Kill-Tbot {
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.ExecutablePath -eq $PY -and $_.CommandLine -match " -m tbot\.main\b" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

if($KillRunning){ Kill-Tbot; Start-Sleep 3 }

# --- Env: make S11 fire + enable debug ---
$env:TBOT_ENABLE_S11_MVP     = "1"
$env:TBOT_S11_MIN_STRENGTH   = "0"
$env:TBOT_S11_MIN_CONF       = "0.55"
$env:TBOT_ALPHA_TREND_ON_TH  = "0"
$env:TBOT_ALPHA_TREND_CAP_TH = "0"
$env:TBOT_DATA_FEED          = "iex"
$env:TBOT_MARKET_DEBUG       = "1"

# IMPORTANT: clear any accidental env overrides (if you ever created them)
"TBOT_SHADOW_ENTRY","TBOT_SHADOW_STOP","TBOT_SHADOW_TP" | ForEach-Object {
  if(Test-Path "env:$_"){ Remove-Item "env:$_" -ErrorAction SilentlyContinue }
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out    = Join-Path $OPS "SMOKE_OUT_$ts.txt"
$err    = Join-Path $OPS "SMOKE_ERR_$ts.txt"
$meta   = Join-Path $OPS "meta_smoke_$ts.jsonl"
$shadow = Join-Path $OPS "shadow_smoke_$ts.jsonl"

Write-Host "[SMOKE] Start bot (NO force, NO shadow_entry override) sleep=$SleepSec timeout=$TimeoutSec"
Write-Host "[SMOKE] META=$meta"
Write-Host "[SMOKE] SHADOW=$shadow"

# Start bot
$p = Start-Process -FilePath $PY -ArgumentList @(
  "-u","-m","tbot.main",
  "--run",
  "--iters","999999",
  "--sleep",("$SleepSec"),
  "--meta",$meta,
  "--shadow",
  "--shadow_path",$shadow,
  "--shadow_risk_usd","250",
  "--shadow_max_qty","5000",
  "--gate_min_rr","0",
  "--gate_min_conf","0",
  "--gate_cooldown_sec","0",
  "--gate_max_plans_per_day","10",
  "--gate_max_risk_usd","999999",
  "--sim_in_session","1"
) -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru

# Capture command line (to detect overrides like --shadow_entry)
$cmd = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction SilentlyContinue).CommandLine
Write-Host "`n[SMOKE] CMDLINE:`n$cmd`n"

# Wait until at least 2 shadow_plans appear (or timeout)
$deadline = (Get-Date).AddSeconds($TimeoutSec)
do {
  Start-Sleep 2
  $count = 0
  if(Test-Path $meta){
    $count = (Get-Content $meta -ErrorAction SilentlyContinue |
      Select-String '"kind"\s*:\s*"shadow_plan"' | Measure-Object).Count
  }
} while($count -lt 2 -and (Get-Date) -lt $deadline)

# Stop bot
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue

if(-not (Test-Path $meta)){
  Write-Host "FAIL: meta file not created => bot didn't start or crashed." -ForegroundColor Red
  exit 1
}

# Parse shadow_plans from meta
$plans = Get-Content $meta |
  Select-String '"kind"\s*:\s*"shadow_plan"' |
  ForEach-Object { ($_.Line | ConvertFrom-Json).payload }

$fake = @($plans | Where-Object { [double]$_.entry -eq 100 -and [double]$_.stop -eq 99 -and [double]$_.tp -eq 102 })

# Look for evidence of 429 / http errors in out/err
$netWarn = Select-String -Path $out,$err -Pattern "429|too many|HTTPError|URLError|Timeout|DEBUG_BARS|DEBUG_LAST" -SimpleMatch -ErrorAction SilentlyContinue

Write-Host "[SMOKE] shadow_plans=$($plans.Count) fake_triples=$($fake.Count)"
if($netWarn){
  Write-Host "[SMOKE] NET/DEBUG WARNINGS found (tail):" -ForegroundColor Yellow
  $netWarn | Select-Object -Last 20 | ForEach-Object { $_.Line }
}

if($plans.Count -lt 2){
  Write-Host "FAIL: Did not get >=2 shadow_plans in time. (Maybe S11 didn't fire; increase TimeoutSec.)" -ForegroundColor Red
  Write-Host "Artifacts: OUT=$out ERR=$err META=$meta SHADOW=$shadow"
  exit 2
}

if($fake.Count -gt 0){
  Write-Host "FAIL: FAKE 100/99/102 detected in NON-forced run." -ForegroundColor Red
  Write-Host "Artifacts: OUT=$out ERR=$err META=$meta SHADOW=$shadow"
  Write-Host "Next step: check CMDLINE above for --shadow_entry/--shadow_stop/--shadow_tp. If present, remove those from your wrapper/canary scripts."
  exit 3
}

Write-Host "PASS: No fake triple in NON-forced run. Root fake-pricing issue is NOT happening under this config." -ForegroundColor Green
Write-Host "Artifacts: OUT=$out ERR=$err META=$meta SHADOW=$shadow"
