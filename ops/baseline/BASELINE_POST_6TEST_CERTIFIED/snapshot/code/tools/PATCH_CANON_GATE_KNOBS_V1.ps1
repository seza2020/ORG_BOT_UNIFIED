# tools\PATCH_CANON_GATE_KNOBS_V1.ps1
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

function ReplaceFlag([string]$t, [string]$flag, [string]$val){
  $before = $t

  # pattern A: "--flag 180"
  $t = [regex]::Replace($t, "(?m)(\Q$flag\E\s+)(\d+)", "`$1$val")

  # pattern B: "--flag","180"  or '--flag','180'
  $t = [regex]::Replace($t, "(?m)(['""]\Q$flag\E['""]\s*,\s*['""])(\d+)(['""])", "`$1$val`$3")

  if($t -eq $before){
    throw "Did not find flag in file: $flag"
  }
  return $t
}

$txt = ReplaceFlag $txt "--gate_cooldown_sec" "$CooldownSec"
$txt = ReplaceFlag $txt "--gate_max_plans_per_day" "$MaxPlansPerDay"

Set-Content -Encoding UTF8 -Path $canon -Value $txt
Write-Host "OK: patched => $canon"
Write-Host "Backup => $BAK"

Write-Host ""
Write-Host "VERIFY:"
Select-String -Path $canon -Pattern "gate_cooldown_sec|gate_max_plans_per_day" | ForEach-Object { $_.Line }
