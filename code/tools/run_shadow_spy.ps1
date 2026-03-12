Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# 0) move to project root
Set-Location "C:\alpaca-bot\org_bot"

# 1) secrets (keys)
. "C:\alpaca-bot\secrets\alpaca_env.ps1"

# 2) symbols
$env:TBOT_SYMBOLS = ($env:TBOT_SYMBOLS -and $env:TBOT_SYMBOLS.Trim().Length -gt 0) ? $env:TBOT_SYMBOLS : "SPY"

# 3) ensure tbot import works from cwd
python -c "import os,sys; import tbot; print('TBOT_OK', tbot.__file__); print('CWD', os.getcwd())" | Out-Null

# 4) preflight data (hard gate)
$py = Join-Path $env:LOCALAPPDATA "Temp\tbot_preflight_data.py"
if (-not (Test-Path $py)) { throw "PREFLIGHT_SCRIPT_MISSING: $py" }

python $py
if ($LASTEXITCODE -ne 0) { throw "PREFLIGHT_FAILED exit=$LASTEXITCODE" }

# 5) run main -> tee to file
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "C:\alpaca-bot\org_bot\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$out = Join-Path $logDir ("console_shadow_" + ($env:TBOT_SYMBOLS.ToLower()) + "_live_" + $ts + "_out.txt")

"RUNNER_OK OUT=$out" | Tee-Object -FilePath $out -Append

python -m tbot.main --run --shadow | Tee-Object -FilePath $out -Append

"RUNNER_DONE EXITCODE=$LASTEXITCODE" | Tee-Object -FilePath $out -Append
exit $LASTEXITCODE
