# tools\PATCH_SHADOW_SOFT_NEGEXP_V1.ps1
[CmdletBinding()]
param(
  # Thresholds for "do not hard-off shadow because of negative_expectancy"
  [int]$MinAcceptedBeforeHardOff = 120,
  [string]$SoftUntilPT = "10:30",   # HH:mm PT
  [double]$SoftCapRatio = 0.10,
  [int]$SoftCooldownSec = 180
)

$ErrorActionPreference = "Stop"
$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot" }

$OPS = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force -Path $OPS | Out-Null
$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$BAK = Join-Path $OPS ("PATCH_SHADOW_SOFT_NEGEXP_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

$orch  = Join-Path $ROOT "tbot\runtime\orchestrator.py"
$canon = Join-Path $ROOT "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
if(-not (Test-Path $orch )){ throw "Missing: $orch"  }
if(-not (Test-Path $canon)){ throw "Missing: $canon" }

Copy-Item -Force $orch  (Join-Path $BAK "orchestrator.py.bak")
Copy-Item -Force $canon (Join-Path $BAK "RUN_LIVE_SHADOW_CANON_V2.ps1.bak")

# --------- 1) Ensure canon runner has env block for soft-negative-expectancy ----------
$canonTxt = Get-Content -Raw -Encoding UTF8 $canon

$envBegin = "# --- TBOT_SHADOW_SOFT_NEGEXP_ENV_V1 BEGIN ---"
$envEnd   = "# --- TBOT_SHADOW_SOFT_NEGEXP_ENV_V1 END ---"

if(($canonTxt -notmatch [regex]::Escape($envBegin)) -or ($canonTxt -notmatch [regex]::Escape($envEnd))){
  $envBlock = @"
$envBegin
`$env:TBOT_SHADOW_SOFT_NEGEXP = "1"
`$env:TBOT_SHADOW_SOFT_NEGEXP_MIN_ACCEPTS = "$MinAcceptedBeforeHardOff"
`$env:TBOT_SHADOW_SOFT_NEGEXP_SOFT_UNTIL_PT = "$SoftUntilPT"
`$env:TBOT_SHADOW_SOFT_NEGEXP_CAP_RATIO = "$SoftCapRatio"
`$env:TBOT_SHADOW_SOFT_NEGEXP_COOLDOWN_SEC = "$SoftCooldownSec"
$envEnd

"@

  # Insert at very top (before anything else)
  $canonTxt = $envBlock + $canonTxt
  Set-Content -Encoding UTF8 -Path $canon -Value $canonTxt
}

# --------- 2) Verify orchestrator has the code marker (we DO NOT auto-edit logic here) ----------
$orchTxt = Get-Content -Raw -Encoding UTF8 $orch
$mkBegin = "# --- TBOT_SHADOW_SOFT_NEGEXP_V1 BEGIN ---"
$mkEnd   = "# --- TBOT_SHADOW_SOFT_NEGEXP_V1 END ---"

if(($orchTxt -notmatch [regex]::Escape($mkBegin)) -or ($orchTxt -notmatch [regex]::Escape($mkEnd))){
  Write-Host ""
  Write-Host "DIAGNOSTIC: Could not find TBOT_SHADOW_SOFT_NEGEXP_V1 markers in orchestrator.py"
  Write-Host "Search hints:"
  Select-String -Path $orch -Pattern "negative_expectancy|decide_alpha|alpha_admission|signal_skip" -Context 0,2 | Select-Object -First 30 | ForEach-Object { $_.Line }
  throw "Patch not applied to orchestrator.py yet. Markers missing."
}

Write-Host "OK: patch script ran safely."
Write-Host "Backup dir => $BAK"
Write-Host ""

Write-Host "VERIFY (canon env):"
Select-String -Path $canon -Pattern "TBOT_SHADOW_SOFT_NEGEXP_ENV_V1|TBOT_SHADOW_SOFT_NEGEXP_MIN_ACCEPTS|TBOT_SHADOW_SOFT_NEGEXP_SOFT_UNTIL_PT|TBOT_SHADOW_SOFT_NEGEXP_CAP_RATIO|TBOT_SHADOW_SOFT_NEGEXP_COOLDOWN_SEC" |
  ForEach-Object { $_.Line }

Write-Host ""
Write-Host "VERIFY (orchestrator markers):"
Select-String -Path $orch -Pattern "TBOT_SHADOW_SOFT_NEGEXP_V1" | Select-Object -First 2 | ForEach-Object { $_.Line }

