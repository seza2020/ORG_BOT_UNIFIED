param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper",
  [int]$Force = 1
)

$ErrorActionPreference="Stop"

$py = Join-Path $Root ".venv\Scripts\python.exe"
$target = Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
$lock = Join-Path $RunRoot "state\locks\RUN_PAPER_PROFILE.lock"
$hb   = Join-Path $RunRoot "state\heartbeat.json"
$pidf = Join-Path $RunRoot "state\pid.txt"

if(!(Test-Path $py)){ throw "MISSING_PY=$py" }
if(!(Test-Path $target)){ throw "MISSING_TARGET=$target" }

"=== MANAGED_RUN START ==="
("ROOT={0}" -f $Root)
("RUNROOT={0}" -f $RunRoot)
("PY={0}" -f $py)
("TARGET={0}" -f $target)

# 0) Ensure pip usable + install deps (idempotent)
& $py -m pip --version | Out-Null
& $py -m pip install -U pip setuptools wheel | Out-Null

# Prefer official SDK if you later migrate, but keep current test using alpaca-trade-api
& $py -m pip install -U alpaca-trade-api requests urllib3 | Out-Null

# 1) Kill any stray paper bots (safe filter)
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like "*-m tbot.main*" -and $_.CommandLine -like "*org_bot_runtime\paper*" } |
  ForEach-Object { "KILL_PAPER_BOT PID=$($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2) Clear lock
Remove-Item $lock -Force -ErrorAction SilentlyContinue

# 3) Import + market-data probe (Alpaca latest trade)
$code = @"
import os, sys
import alpaca_trade_api as tradeapi

key=os.environ.get('APCA_API_KEY_ID')
sec=os.environ.get('APCA_API_SECRET_KEY')
url=os.environ.get('APCA_API_BASE_URL')
print('ENV_OK', bool(key), bool(sec), bool(url), 'BASE_URL=', url)

api = tradeapi.REST(key, sec, url, api_version='v2')

symbols = os.environ.get('TBOT_SYMBOLS') or os.environ.get('SYMBOLS') or 'SPY,QQQ'
syms=[s.strip() for s in symbols.split(',') if s.strip()]
print('SYMBOLS', syms)

ok=0
for s in syms[:6]:
    try:
        t = api.get_latest_trade(s)
        px = getattr(t, 'price', None)
        ts = getattr(t, 'timestamp', None)
        print('LATEST_TRADE', s, 'price=', px, 'ts=', ts)
        if px is not None:
            ok += 1
    except Exception as e:
        print('LATEST_TRADE_FAIL', s, repr(e))
print('LATEST_TRADE_OK_COUNT', ok)
if ok == 0:
    sys.exit(12)
"@

& $py -c $code
$probeEc = $LASTEXITCODE
("PROBE_EXITCODE={0}" -f $probeEc)
if($probeEc -ne 0){
  "FATAL: market data probe failed. NOT starting runner."
  Read-Host "Press Enter to close"
  exit $probeEc
}

# 4) Run runner (keep console open)
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $target -Force $Force
$ec=$LASTEXITCODE
"RUNNER_EXITCODE=$ec"

# 5) Show heartbeat/pidfile status
if(Test-Path $hb){
  $age = [int](([DateTime]::UtcNow-(Get-Item $hb).LastWriteTimeUtc).TotalSeconds)
  "HEARTBEAT_AGE_SEC=$age"
  "HEARTBEAT_TAIL="; Get-Content -LiteralPath $hb -Tail 3
} else {
  "HEARTBEAT_MISSING=1"
}
if(Test-Path $pidf){
  "PIDFILE=" + (Get-Content -Raw $pidf).Trim()
} else {
  "PIDFILE_MISSING=1"
}

Read-Host "Press Enter to close"
exit $ec
