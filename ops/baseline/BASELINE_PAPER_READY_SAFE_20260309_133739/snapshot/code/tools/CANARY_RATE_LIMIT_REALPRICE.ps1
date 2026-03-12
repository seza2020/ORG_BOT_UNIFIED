param(
  [switch]$KillRunning,
  [int]$SleepSec = 3,
  [int]$NeedPlans = 2
)

$ErrorActionPreference="Stop"
$ROOT   = "C:\alpaca-bot\org_bot"
$PY     = Join-Path $ROOT ".venv\Scripts\python.exe"
$OPS    = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force $OPS | Out-Null

function Find-TbotProcs {
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.CommandLine -match " -m tbot\.main\b" }
}

if($KillRunning){
  $procs = Find-TbotProcs
  if($procs){
    "Killing running tbot.main procs..."
    $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
  }
}

# ---- Alpaca REST headers ----
$h=@{
  "Accept"="application/json"
  "User-Agent"="tbot-market/1.0"
  "APCA-API-KEY-ID"=$env:APCA_API_KEY_ID
  "APCA-API-SECRET-KEY"=$env:APCA_API_SECRET_KEY
}

$feed = $env:TBOT_DATA_FEED; if(-not $feed){ $feed="iex" }
"FEED=$feed"

function Get-Trade($sym){
  $u="https://data.alpaca.markets/v2/stocks/$sym/trades/latest?feed=$feed"
  (Invoke-RestMethod $u -Headers $h -TimeoutSec 10).trade
}

function Try-Bars($sym){
  $end=(Get-Date).ToUniversalTime()
  $start=$end.AddMinutes(-20)
  $startIso=($start.ToString("o") -replace "\+00:00$","Z")
  $endIso=($end.ToString("o") -replace "\+00:00$","Z")
  $u="https://data.alpaca.markets/v2/stocks/$sym/bars?timeframe=1Min&limit=30&feed=$feed&start=$startIso&end=$endIso"
  Invoke-RestMethod $u -Headers $h -TimeoutSec 10
}

# ---- Phase A: rate-limit probe on bars ----
$symProbe="SPY"
$backoff = @(1,2,3,5,8,13,21)
$okBars=$false
for($i=0; $i -lt 30; $i++){
  try{
    $r = Try-Bars $symProbe
    $n = @($r.bars).Count
    "BARS_OK count=$n"
    if($n -gt 0){ $okBars=$true; break }
    "WARN: bars returned 0 (no 1Min bars in window)."
    $okBars=$true  # HTTP ok; but may be after-hours behavior
    break
  } catch {
    $msg = $_.Exception.Message
    if($msg -match "too many requests|429"){
      $s = $backoff[[Math]::Min($i, $backoff.Count-1)]
      "BARS_429 -> backoff ${s}s"
      Start-Sleep -Seconds $s
      continue
    }
    throw
  }
}

if(-not $okBars){
  Write-Host "FAIL: bars probe never succeeded (still rate-limited)." -ForegroundColor Red
  exit 1
}

# ---- Phase B: start bot with low pressure + debug ----
$env:TBOT_MARKET_DEBUG="1"
$env:TBOT_ENABLE_S11_MVP="1"
$env:TBOT_S11_MIN_STRENGTH="0"
$env:TBOT_S11_MIN_CONF="0.55"
$env:TBOT_ALPHA_TREND_ON_TH="0"
$env:TBOT_ALPHA_TREND_CAP_TH="0"

$ts=Get-Date -Format "yyyyMMdd_HHmmss"
$out   = Join-Path $OPS "CANARY429_OUT_$ts.txt"
$err   = Join-Path $OPS "CANARY429_ERR_$ts.txt"
$meta  = Join-Path $OPS "meta_canary429_$ts.jsonl"
$shadow= Join-Path $OPS "shadow_canary429_$ts.jsonl"

$p = Start-Process -FilePath $PY -ArgumentList @(
  "-u","-m","tbot.main",
  "--run",
  "--shadow",
  "--meta",$meta,
  "--shadow_path",$shadow,
  "--iters","999999",
  "--sleep","$SleepSec",
  "--gate_min_rr","0",
  "--gate_min_conf","0",
  "--gate_cooldown_sec","0",
  "--gate_max_plans_per_day","10",
  "--gate_max_risk_usd","999999",
  "--sim_in_session","1"
) -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru

"BOT_PID=$($p.Id)"
"OUT=$out"
"ERR=$err"
"META=$meta"
"SHADOW=$shadow"

# wait for shadow_plans
$deadline=(Get-Date).AddSeconds(180)
$plans=@()
while((Get-Date) -lt $deadline){
  if(Test-Path $meta){
    $hits = Get-Content $meta -Tail 2000 |
      Select-String '"kind"\s*:\s*"shadow_plan"' |
      Select-Object -ExpandProperty Line
    if($hits){
      $plans = $hits | ForEach-Object { ($_ | ConvertFrom-Json).payload }
      if($plans.Count -ge $NeedPlans){ break }
    }
  }
  Start-Sleep -Milliseconds 500
}

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue

if(-not $plans -or $plans.Count -lt $NeedPlans){
  Write-Host "FAIL: did not collect enough shadow_plans." -ForegroundColor Red
  exit 1
}

# validate: no fake triple + entry close to trade
$fake = $plans | Where-Object { ([double]$_.entry -eq 100) -and ([double]$_.stop -eq 99) -and ([double]$_.tp -eq 102) }
if($fake){
  Write-Host "FAIL: FAKE triple detected in shadow_plan => still hitting fallback (likely bars 429 during bot run)." -ForegroundColor Red
  $plans | Select-Object sid,symbol,entry,stop,tp,rr,confidence,reason | Format-Table -AutoSize
  Write-Host "Hint: increase --sleep to 5 and ensure no other bot is running." -ForegroundColor Yellow
  exit 1
}

# closeness check vs latest trade (per symbol in collected plans)
$bad=@()
foreach($pl in $plans){
  try{
    $t = Get-Trade $pl.symbol
    $px = [double]$t.p
    $en = [double]$pl.entry
    $diff = [Math]::Abs($en-$px)/$px
    if($diff -gt 0.05){  # 5%
      $bad += [pscustomobject]@{symbol=$pl.symbol; entry=$en; trade=$px; rel_diff=$diff}
    }
  } catch {}
}

if($bad.Count -gt 0){
  Write-Host "WARN: entry not close to trade for some symbols (>5%). Check market snapshot health." -ForegroundColor Yellow
  $bad | Format-Table -AutoSize
} else {
  Write-Host "PASS: No fake triple + entries roughly match latest trades." -ForegroundColor Green
}

Write-Host "Search debug for 429:" -ForegroundColor Cyan
if(Test-Path $out){ Get-Content $out -Tail 400 | Select-String -Pattern "429|too many|HTTPERR|DEBUG_" | ForEach-Object {$_.Line} }
if(Test-Path $err){ Get-Content $err -Tail 400 | Select-String -Pattern "429|too many|HTTPERR|DEBUG_" | ForEach-Object {$_.Line} }

