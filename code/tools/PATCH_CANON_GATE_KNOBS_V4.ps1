# tools\PATCH_CANON_GATE_KNOBS_V4.ps1
[CmdletBinding()]
param(
  [int]$CooldownSec = 45,
  [int]$MaxPlansPerDay = 150
)

$ErrorActionPreference="Stop"
$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot" }

$OPS = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force -Path $OPS | Out-Null
$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$BAK = Join-Path $OPS ("PATCH_CANON_GATE_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

$canon = Join-Path $ROOT "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
if(-not (Test-Path $canon)){ throw "Missing: $canon" }

Copy-Item -Force $canon (Join-Path $BAK "RUN_LIVE_SHADOW_CANON_V2.ps1.bak")

$txt = Get-Content -Raw -Encoding UTF8 $canon
$before = $txt

# Handles quoted args: "--gate_cooldown_sec","0"
$rxCooldown = '(?m)("[-–—]{2}gate_cooldown_sec"\s*,\s*")(\d+)(")'
$rxMaxPlans = '(?m)("[-–—]{2}gate_max_plans_per_day"\s*,\s*")(\d+)(")'

$txt = [regex]::Replace($txt, $rxCooldown, ('$1' + $CooldownSec + '$3'))
$txt = [regex]::Replace($txt, $rxMaxPlans, ('$1' + $MaxPlansPerDay + '$3'))

if($txt -eq $before){
  Write-Host "NO_CHANGE: patterns not matched. Diagnostics:"
  Select-String -Path $canon -Pattern "gate_cooldown_sec|gate_max_plans_per_day" -Context 0,2 | ForEach-Object { $_.Line }
  throw "Patch failed: no changes made."
}

Set-Content -Encoding UTF8 -Path $canon -Value $txt

Write-Host "OK: patched => $canon"
Write-Host "Backup => $BAK"
Write-Host ""
Write-Host "VERIFY:"
Select-String -Path $canon -Pattern "gate_cooldown_sec|gate_max_plans_per_day" | ForEach-Object { $_.Line }
