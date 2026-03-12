# tools\FIX_CANON_GATE_KNOBS_V5.ps1
# Restore canonical runner from latest PATCH_CANON_GATE backup, then patch safely (no $1/$3 ambiguity).
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

$canon = Join-Path $ROOT "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
if(-not (Test-Path $canon)){ throw "Missing: $canon" }

$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$BAK = Join-Path $OPS ("FIX_CANON_GATE_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

# Backup current (even if corrupted)
Copy-Item -Force $canon (Join-Path $BAK "RUN_LIVE_SHADOW_CANON_V2.ps1.before_fix.bak")

# Restore from latest PATCH_CANON_GATE_* backup (your earlier patch created one)
$latestPatchDir = Get-ChildItem $OPS -Directory -Filter "PATCH_CANON_GATE_*" |
  Sort-Object Name -Descending | Select-Object -First 1

if($latestPatchDir){
  $restoreSrc = Join-Path $latestPatchDir.FullName "RUN_LIVE_SHADOW_CANON_V2.ps1.bak"
  if(Test-Path $restoreSrc){
    Copy-Item -Force $restoreSrc $canon
    Write-Host "OK: restored canon from => $restoreSrc"
  } else {
    Write-Host "WARN: latest PATCH_CANON_GATE_* found but .bak missing; continuing without restore."
  }
} else {
  Write-Host "WARN: no PATCH_CANON_GATE_* backup dir found; continuing without restore."
}

# Patch safely using MatchEvaluator (no $1/$3)
$txt = Get-Content -Raw -Encoding UTF8 $canon

$rxCooldown = '(?m)("[-–—]{2}gate_cooldown_sec"\s*,\s*")(\d+)(")'
$rxMaxPlans = '(?m)("[-–—]{2}gate_max_plans_per_day"\s*,\s*")(\d+)(")'

$changed1 = 0
$changed2 = 0

$txt = [regex]::Replace($txt, $rxCooldown, {
  param($m)
  $script:changed1++
  return $m.Groups[1].Value + $CooldownSec + $m.Groups[3].Value
})

$txt = [regex]::Replace($txt, $rxMaxPlans, {
  param($m)
  $script:changed2++
  return $m.Groups[1].Value + $MaxPlansPerDay + $m.Groups[3].Value
})

if($changed1 -eq 0 -or $changed2 -eq 0){
  Write-Host "FAIL: did not patch expected patterns (changed cooldown=$changed1 maxplans=$changed2)"
  Write-Host "DIAG:"
  Select-String -Path $canon -Pattern "gate_cooldown_sec|gate_max_plans_per_day" -Context 0,2 | ForEach-Object { $_.Line }
  throw "Patch failed."
}

Set-Content -Encoding UTF8 -Path $canon -Value $txt
Write-Host "OK: patched => $canon"
Write-Host "Backup dir => $BAK"

Write-Host ""
Write-Host "VERIFY (must show 45 and 150):"
Select-String -Path $canon -Pattern "gate_cooldown_sec|gate_max_plans_per_day" -Context 0,0 | ForEach-Object { $_.Line.Trim() }

# Extra sanity: ensure script still contains tbot.main invocation
Write-Host ""
Write-Host "SANITY:"
Select-String -Path $canon -Pattern "tbot\.main|--shadow" -Context 0,0 | Select-Object -First 5 | ForEach-Object { $_.Line.Trim() }
