param(
  [switch]$KillRunning,
  [int]$SanityLoops = 6,
  [int]$SanityDelaySec = 2,
  [int]$BotSleepSec = 20,
  [int]$TimeoutSec = 180,
  [string]$Feed = "iex"
)

$ErrorActionPreference = "Stop"

$ROOT = "C:\alpaca-bot\org_bot"
$PY   = Join-Path $ROOT ".venv\Scripts\python.exe"
$OPS  = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force $OPS | Out-Null

function Kill-TbotMain {
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.ExecutablePath -eq $PY -and $_.CommandLine -match " -m tbot\.main\b" } |
    ForEach-Object {
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Get-Headers {
  $kid = $env:APCA_API_KEY_ID
  if(-not $kid){ $kid = $env:APCA_API_KEY }
  $sec = $env:APCA_API_SECRET_KEY
  if(-not $sec){ $sec = $env:APCA_API_SECRET }
  if(-not $kid -or -not $sec){ throw "APCA KEYS missing in env" }

  return @{
    "Accept"="application/json"
    "User-Agent"="tbot-precheck/1.0"
    "APCA-API-KEY-ID"=$kid
    "APCA-API-SECRET-KEY"=$sec
  }
}

function Invoke-JsonRetry([string]$Url, $Headers, [int]$Tries=6){
  for($i=0;$i -lt $Tries;$i++){
    try{
      $r = Invoke-RestMethod -Uri $Url -Headers $Headers -TimeoutSec 10
      if($r -and $r.PSObject.Properties.Name -contains "message"){
        if(($r.message -as [string]) -match "too many requests"){
          throw "429_MESSAGE"
        }
      }
      return $r
    } catch {
      $msg = $_.Exception.Message
      $sleep = [Math]::Min(12, (2 + $i*2))
      if($msg -match "429|too many requests|429_MESSAGE"){
        Start-Sleep -Seconds $sleep
        continue
      }
      # سایر خطاها هم یکبار با backoff
      if($i -lt ($Tries-1)){
        Start-Sleep -Seconds $sleep
        continue
      }
      throw
    }
  }
  throw "Invoke-JsonRetry exhausted"
}

function Find-SuspectSymbolConfig {
  $hits = @()
  $patterns = @("TBOT_.*SYMBOL","SYMBOLS_FILE","UNIVERSE","watchlist","symbols.txt","symbols.json")
  foreach($p in $patterns){
    $m = Get-ChildItem $ROOT -Recurse -File -Include *.py,*.ps1,*.json,*.txt,*.yml,*.yaml -ErrorAction SilentlyContinue |
      Select-String -Pattern $p -List -ErrorAction SilentlyContinue
    if($m){ $hits += $m }
  }
  $hits | Select-Object -Unique Path,LineNumber,Line | Select-Object -First 25
}

if($KillRunning){
  Write-Host "[NIGHT] Killing running tbot.main..." -ForegroundColor Yellow
  Kill-TbotMain
}

Write-Host "[NIGHT] NOW_PT=$(Get-Date)  FEED=$Feed" -ForegroundColor Cyan

# PhaseA: Sanity loops (trade.latest + bars)
$H = Get-Headers
$syms = @("SPY","QQQ","NVDA")

$end = (Get-Date).ToUniversalTime()
$start = $end.AddDays(-5)
$startIso = $start.ToString("yyyy-MM-ddTHH:mm:ssZ")
$endIso   = $end.ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "[NIGHT] PhaseA: Alpaca sanity loops x$SanityLoops (trade+bars, retry/backoff)" -ForegroundColor Cyan

for($k=0;$k -lt $SanityLoops;$k++){
  foreach($s in $syms){
    $uTrade = "https://data.alpaca.markets/v2/stocks/$s/trades/latest?feed=$Feed"
    $uBars  = "https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Min&limit=120&feed=$Feed&start=$startIso&end=$endIso"

    $tr = Invoke-JsonRetry $uTrade $H
    $br = Invoke-JsonRetry $uBars  $H

    $p = [double]($tr.trade.p)
    $bc = @($br.bars).Count
    if($p -le 0 -or $bc -lt 80){
      throw "PhaseA FAIL: $s bad trade/bars (p=$p bars=$bc)"
    }
    Write-Host ("[DATA] {0} p={1} bars={2}" -f $s,$p,$bc)
    Start-Sleep -Seconds $SanityDelaySec
  }
}

# PhaseB: Bot run (low pressure) and detect fake
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$out    = Join-Path $OPS "NIGHT_PRECHECK_OUT_$ts.txt"
$err    = Join-Path $OPS "NIGHT_PRECHECK_ERR_$ts.txt"
$meta   = Join-Path $OPS "meta_night_precheck_$ts.jsonl"
$shadow = Join-Path $OPS "shadow_night_precheck_$ts.jsonl"

# env for process
$env:TBOT_DATA_FEED    = $Feed
$env:TBOT_MARKET_DEBUG = "1"
$env:TBOT_ENABLE_S11_MVP   = "1"
$env:TBOT_S11_MIN_STRENGTH = "0"
$env:TBOT_S11_MIN_CONF     = "0.55"
$env:TBOT_ALPHA_TREND_ON_TH  = "0"
$env:TBOT_ALPHA_TREND_CAP_TH = "0"

Write-Host "[NIGHT] PhaseB: start bot (sleep=$BotSleepSec) until 2 shadow_plans or timeout=$TimeoutSec" -ForegroundColor Cyan

# برای کم‌کردن فشار: فقط 2 پلن می‌گیریم و بعد می‌کشیم
$args = @(
  "-u","-m","tbot.main",
  "--run",
  "--iters","999999",
  "--sleep","$BotSleepSec",
  "--meta",$meta,
  "--shadow",
  "--shadow_path",$shadow,
  "--shadow_risk_usd","250",
  "--shadow_max_qty","5000",
  "--gate_min_rr","0",
  "--gate_min_conf","0",
  "--gate_cooldown_sec","0",
  "--gate_max_plans_per_day","2",
  "--gate_max_risk_usd","999999",
  "--sim_in_session","1"
)

$p = Start-Process -FilePath $PY -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err

$deadline = (Get-Date).AddSeconds($TimeoutSec)
do {
  Start-Sleep -Seconds 2
  $count = 0
  if(Test-Path $meta){
    $count = (Get-Content $meta -Tail 50000 | Select-String '"kind"\s*:\s*"shadow_plan"' | Measure-Object).Count
  }
} while($count -lt 2 -and (Get-Date) -lt $deadline)

try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}

if(-not (Test-Path $meta)){ throw "PhaseB FAIL: meta not created" }
if(-not (Test-Path $shadow)){ throw "PhaseB FAIL: shadow not created" }

$metaPlans = (Get-Content $meta -Tail 50000 | Select-String '"kind"\s*:\s*"shadow_plan"' | Measure-Object).Count
$shadowLines = (Get-Content $shadow | Measure-Object).Count

# fake triple detector
$fake = @()
Get-Content $shadow | ForEach-Object {
  try {
    $j = $_ | ConvertFrom-Json
    if($j.entry -eq 100 -and $j.stop -eq 99 -and $j.tp -eq 102){
      $fake += $j
    }
  } catch {}
}

# also scan out/err for 429 or debug fails
$rateHits = @()
$patterns = "429","too many requests","DEBUG_BARS_NULL","DEBUG_LAST_HTTPERR","DEBUG_LAST_FAIL","URLError","Timeout"
foreach($patt in $patterns){
  $rateHits += (Select-String -Path $out,$err -Pattern $patt -ErrorAction SilentlyContinue)
}

Write-Host "[NIGHT] PhaseB meta_plans=$metaPlans shadow_lines=$shadowLines fake_count=$($fake.Count) rate_hits=$($rateHits.Count)" -ForegroundColor Cyan
Write-Host "[ARTIFACTS] OUT=$out"
Write-Host "[ARTIFACTS] ERR=$err"
Write-Host "[ARTIFACTS] META=$meta"
Write-Host "[ARTIFACTS] SHADOW=$shadow"

if($metaPlans -lt 2){ throw "FAIL: insufficient shadow_plan count (meta_plans=$metaPlans)" }
if($fake.Count -gt 0){
  Write-Host "FAIL: FAKE 100/99/102 detected => root issue NOT safe for tomorrow under this pacing." -ForegroundColor Red
  $fake | Select-Object sid,symbol,entry,stop,tp,rr,confidence,reason | Format-Table -AutoSize
  Write-Host "`n[HINT] This is almost always market-data failure or rate-limit. Keep BotSleepSec higher and ensure only one bot instance. Also avoid running external bars/trade loops while bot is running."
  Write-Host "`n[HINT] Candidate symbol/universe config hints:"
  Find-SuspectSymbolConfig | Format-Table -AutoSize
  exit 1
}
if($rateHits.Count -gt 0){
  Write-Host "WARN: rate/debug hints found in OUT/ERR (check artifacts). Consider BotSleepSec=30 for tomorrow baseline." -ForegroundColor Yellow
}

Write-Host "PASS: No fake triple under low-pressure run. Tomorrow with same pacing (sleep>=20) should be safe from fake-pricing." -ForegroundColor Green

