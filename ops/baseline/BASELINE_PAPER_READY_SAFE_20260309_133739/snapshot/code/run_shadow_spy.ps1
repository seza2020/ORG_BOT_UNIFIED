$ErrorActionPreference = "Stop"

Set-Location "C:\alpaca-bot\org_bot"
"PWD=$((Get-Location).Path)"

# --- 1) Load secrets if present (recommended)
$secrets = @(
  "C:\alpaca-bot\secrets\alpaca_env.ps1",
  "C:\alpaca-bot\secrets\env_alpaca.ps1",
  "C:\alpaca-bot\secrets\secrets.ps1"
)

$loaded = $false
foreach ($p in $secrets) {
  if (Test-Path $p) {
    . $p
    "SECRETS_LOADED=$p"
    $loaded = $true
    break
  }
}
if (-not $loaded) { "SECRETS_LOADED=NO_FILE_FOUND" }

# --- 2) Ensure required env vars
$need = @("APCA_API_KEY_ID","APCA_API_SECRET_KEY")
$missing = @()

foreach ($k in $need) {
  $item = Get-Item -Path ("Env:\" + $k) -ErrorAction SilentlyContinue
  $val  = if ($null -ne $item) { $item.Value } else { "" }
  if ([string]::IsNullOrWhiteSpace($val)) { $missing += $k }
}

# optional base url default
$itemBase = Get-Item -Path "Env:\APCA_API_BASE_URL" -ErrorAction SilentlyContinue
if ($null -eq $itemBase -or [string]::IsNullOrWhiteSpace($itemBase.Value)) {
  $env:APCA_API_BASE_URL = "https://paper-api.alpaca.markets"
}

$env:TBOT_SYMBOLS = "SPY"

"TBOT_SYMBOLS=$env:TBOT_SYMBOLS"
"APCA_API_BASE_URL=$env:APCA_API_BASE_URL"
"KEY_SET=" + ($(if([string]::IsNullOrWhiteSpace((Get-Item Env:\APCA_API_KEY_ID -ErrorAction SilentlyContinue).Value)){"NO"}else{"YES"}))
"SECRET_SET=" + ($(if([string]::IsNullOrWhiteSpace((Get-Item Env:\APCA_API_SECRET_KEY -ErrorAction SilentlyContinue).Value)){"NO"}else{"YES"}))

if ($missing.Count -gt 0) {
  "FATAL_MISSING_ENV=" + ($missing -join ",")
  throw "APCA_KEYS_MISSING"
}

# --- 3) Short smoke run (fast)
python -m tbot.main --run --iters 3 --sleep 1 --shadow --sim_in_session 1 --sim_pre_close 0
"SMOKE_EXITCODE=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { throw "Smoke run failed" }

# --- 4) Start long run with separate out/err
$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$out = "C:\alpaca-bot\org_bot\logs\console_shadow_spy_live_${ts}_out.txt"
$err = "C:\alpaca-bot\org_bot\logs\console_shadow_spy_live_${ts}_err.txt"

"OUT=$out"
"ERR=$err"

$py = (Get-Command python).Source

Start-Process -FilePath $py `
  -WorkingDirectory "C:\alpaca-bot\org_bot" `
  -ArgumentList @("-m","tbot.main","--run","--shadow","--sleep","15") `
  -RedirectStandardOutput $out `
  -RedirectStandardError  $err `
  -WindowStyle Hidden

"STARTED=YES"
