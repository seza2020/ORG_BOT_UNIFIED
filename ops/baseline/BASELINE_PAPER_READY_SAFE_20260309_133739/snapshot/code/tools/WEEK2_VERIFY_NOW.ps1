param(
  [switch]$KillRunning,
  [int]$TimeoutSec = 120,
  [int]$SleepSec = 5,
  [string]$Symbols = "SPY,QQQ,NVDA",
  [int]$MinPlans = 2
)

$ErrorActionPreference = "Stop"
$ROOT = "C:\alpaca-bot\org_bot"
$PY   = Join-Path $ROOT ".venv\Scripts\python.exe"
$OPS  = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force $OPS | Out-Null

# --- helpers ---
function Now-PT {
  try {
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")
    return [System.TimeZoneInfo]::ConvertTime([DateTime]::UtcNow, $tz)
  } catch {
    return (Get-Date) # fallback: assume local is PT
  }
}

function In-Session($dt){
  if($dt.DayOfWeek -in @("Saturday","Sunday")){ return $false }
  $t = $dt.TimeOfDay
  $open = [TimeSpan]::FromHours(6.5)      # 06:30
  $close = [TimeSpan]::FromHours(13.0)    # 13:00
  return ($t -ge $open -and $t -le $close)
}

function Alpaca-Headers {
  $kid = ($env:APCA_API_KEY_ID,$env:APCA_API_KEY | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1)
  $sec = ($env:APCA_API_SECRET_KEY,$env:APCA_API_SECRET | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1)
  if(-not $kid -or -not $sec){ throw "APCA_KEYS_MISSING in env" }
  return @{
    "Accept"="application/json"
    "User-Agent"="week2-verify/1.0"
    "APCA-API-KEY-ID"=$kid
    "APCA-API-SECRET-KEY"=$sec
  }
}

function Invoke-Alpaca([string]$Url, $Headers, [int]$Tries=6){
  for($i=0; $i -lt $Tries; $i++){
    try {
      return Invoke-RestMethod $Url -Headers $Headers -TimeoutSec 10
    } catch {
      $is429 = $false
      try {
        if($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 429){ $is429=$true }
      } catch {}
      if(-not $is429 -and $_.Exception.Message -match "429|too many requests"){ $is429=$true }
      if($is429 -and $i -lt ($Tries-1)){
        Start-Sleep -Seconds ([Math]::Min(10, 2 + $i))
        continue
      }
      throw
    }
  }
}

function Kill-Tbot([string]$PyPath){
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.ExecutablePath -eq $PyPath -and $_.CommandLine -match " -m tbot\.main\b" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Count-MetaShadowPlan([string]$MetaPath){
  if(!(Test-Path $MetaPath)){ return 0 }
  return (Get-Content $MetaPath -ErrorAction SilentlyContinue | Select-String '"kind"\s*:\s*"shadow_plan"' | Measure-Object).Count
}

function Has-Error([string]$MetaPath){
  if(!(Test-Path $MetaPath)){ return $false }
  return [bool](Get-Content $MetaPath -ErrorAction SilentlyContinue | Select-String '"kind"\s*:\s*"error"' -Quiet)
}

function Find-FakeTriples([string]$ShadowPath){
  if(!(Test-Path $ShadowPath)){ return @() }
  $out = @()
  foreach($ln in Get-Content $ShadowPath -ErrorAction SilentlyContinue){
    try { $j = $ln | ConvertFrom-Json } catch { continue }
    if($j.entry -eq 100 -and $j.stop -eq 99 -and $j.tp -eq 102){ $out += $j }
  }
  return $out
}

# --- begin ---
$now = Now-PT
$inSession = In-Session $now
Write-Host ("[VERIFY] NOW_PT={0}  inSession={1}" -f $now,$inSession)

$env:TBOT_DATA_FEED="iex"
$env:TBOT_MARKET_DEBUG="1"

$syms = $Symbols.Split(",") | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }
$h = Alpaca-Headers

# PhaseA: direct API sanity
$endUtc = (Get-Date).ToUniversalTime()
$startUtc = $endUtc.AddHours(-3)
$startIso = $startUtc.ToString("o").Replace("+00:00","Z")
$endIso   = $endUtc.ToString("o").Replace("+00:00","Z")

Write-Host "[VERIFY] PhaseA: Alpaca data sanity (trade.latest + bars)"
foreach($s in $syms){
  $uTrade = "https://data.alpaca.markets/v2/stocks/$s/trades/latest?feed=$($env:TBOT_DATA_FEED)"
  $uBars  = "https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Min&limit=120&feed=$($env:TBOT_DATA_FEED)&start=$startIso&end=$endIso"

  $t = (Invoke-Alpaca $uTrade $h).trade
  $b = (Invoke-Alpaca $uBars  $h).bars

  $tp = [double]$t.p
  $bc = ($b | Measure-Object).Count
  Write-Host ("[DATA] {0} trade.p={1}  bars.count={2}" -f $s,$tp,$bc)

  if($tp -le 0 -or $bc -lt 80){ throw "PhaseA FAIL for $s (bad trade/bars)" }
}

# PhaseB: python snapshot loop (no exception)
Write-Host "[VERIFY] PhaseB: build_market_snapshot loop x6 (no throw)"
$pyCode = @"
import time, os
from tbot.market.market_provider import build_market_snapshot
syms = tuple([s.strip().upper() for s in os.getenv('W2_SYMS','SPY,QQQ,NVDA').split(',') if s.strip()])
print('DEBUG',os.getenv('TBOT_MARKET_DEBUG'),'FEED',os.getenv('TBOT_DATA_FEED'),'SYMS',syms)
for i in range(6):
  t0=time.time()
  build_market_snapshot(symbols=syms)
  print('ITER',i,'ok ms',int((time.time()-t0)*1000))
  time.sleep(3)
"@
$env:W2_SYMS = ($syms -join ",")
& $PY -c $pyCode
if($LASTEXITCODE -ne 0){ throw "PhaseB FAIL (python exited $LASTEXITCODE)" }

# PhaseC: only meaningful in-session (real pricing)
Write-Host ("[VERIFY] PhaseC: bot-run {0}s (only if inSession=True)" -f $TimeoutSec)
if(-not $inSession){
  Write-Host "SKIP PhaseC: خارج سشن هستی؛ تست قیمت واقعی داخل سشن معنی‌دار است."
  exit 0
}

if($KillRunning){ Kill-Tbot $PY }

$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$out   = Join-Path $OPS ("VERIFY_OUT_{0}.txt" -f $stamp)
$err   = Join-Path $OPS ("VERIFY_ERR_{0}.txt" -f $stamp)
$meta  = Join-Path $OPS ("meta_verify_{0}.jsonl" -f $stamp)
$shadow= Join-Path $OPS ("shadow_verify_{0}.jsonl" -f $stamp)

$args = @(
  "-u","-m","tbot.main",
  "--run","--iters","999999","--sleep",$SleepSec,
  "--meta",$meta,
  "--shadow","--shadow_path",$shadow,
  "--shadow_risk_usd","250","--shadow_max_qty","5000",
  "--gate_min_rr","0","--gate_min_conf","0",
  "--gate_cooldown_sec","90",
  "--gate_max_plans_per_day","10",
  "--gate_max_risk_usd","999999"
)

Write-Host "[VERIFY] CMDLINE:"; Write-Host ('"{0}" {1}' -f $PY, ($args -join " "))
$p = Start-Process -FilePath $PY -ArgumentList $args -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while((Get-Date) -lt $deadline){
  Start-Sleep -Seconds 2
  if((Count-MetaShadowPlan $meta) -ge $MinPlans){ break }
}

try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}

$metaPlans = Count-MetaShadowPlan $meta
$fake = Find-FakeTriples $shadow
$hasErr = Has-Error $meta

Write-Host ("[VERIFY] PhaseC results: meta_shadow_plan={0}  fake_triples={1}  error={2}" -f $metaPlans, $fake.Count, $hasErr)
Write-Host ("[ARTIFACTS] OUT={0}`n[ARTIFACTS] ERR={1}`n[ARTIFACTS] META={2}`n[ARTIFACTS] SHADOW={3}" -f $out,$err,$meta,$shadow)

if($hasErr){ throw "FAIL: error events detected in meta" }
if($metaPlans -lt $MinPlans){ throw "FAIL: insufficient shadow_plan count" }
if($fake.Count -gt 0){ throw "FAIL: FAKE 100/99/102 detected داخل سشن => ریشه‌ای حل نشده" }

Write-Host "PASS: داخل سشن، پلن‌ها واقعی‌اند و fake-triple نداریم."

