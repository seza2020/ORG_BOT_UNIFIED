$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

# Always run from project root so python can import tbot
Push-Location "C:\alpaca-bot\org_bot"
try {
  $ts  = Get-Date -Format "yyyyMMdd_HHmmss"
  $out = "C:\alpaca-bot\org_bot\logs\console_shadow_spy_live_${ts}_out.txt"
  New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null

  "RUNNER_START ts=$ts" | Tee-Object -FilePath $out -Append | Out-Null
  "CWD=$((Get-Location).Path)" | Tee-Object -FilePath $out -Append | Out-Null
  "PY=$((Get-Command python).Source)" | Tee-Object -FilePath $out -Append | Out-Null

  # Preflight (inside project cwd)
  "PREFLIGHT_START" | Tee-Object -FilePath $out -Append | Out-Null
  python "$env:LOCALAPPDATA\Temp\tbot_preflight_data.py" 2>&1 | Tee-Object -FilePath $out -Append | Out-Null
  $pre = $LASTEXITCODE
  "PREFLIGHT_DONE exit=$pre" | Tee-Object -FilePath $out -Append | Out-Null
  if ($pre -ne 0) { throw "PREFLIGHT_FAILED exit=$pre (see $out)" }

  # Run bot
  "BOT_START" | Tee-Object -FilePath $out -Append | Out-Null
  python -m tbot.main --run --shadow 2>&1 | Tee-Object -FilePath $out -Append
  $bot = $LASTEXITCODE
  "BOT_DONE exit=$bot" | Tee-Object -FilePath $out -Append | Out-Null

  "OUT=$out"
  exit $bot
}
finally {
  Pop-Location
}
