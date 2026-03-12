# tools\PATCH_CANON_GATE_KNOBS_V3.ps1
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

function Replace-Key([string]$t, [string[]]$keys, [string]$val){
  $totalChanged = 0

  foreach($key in $keys){
    $k = [regex]::Escape($key)
    $dash = "[–—-]{1,2}"   # supports -, en-dash, em-dash (and double)

    $patterns = @(
      # --key 180   OR  –key 180
      "(?mi)(?<p>$dash$k)(\s+)(?<n>\d+)",
      # --key=180
      "(?mi)(?<p>$dash$k)=(?<n>\d+)",
      # "--key","180"   or  '–key','180'
      "(?mi)(?<p>['""]$dash$k['""]\s*,\s*['""])(?<n>\d+)(?<s>['""])",
      # "--key",180   (number unquoted)
      "(?mi)(?<p>['""]$dash$k['""]\s*,\s*)(?<n>\d+)"
    )

    foreach($pat in $patterns){
      $changedHere = 0
      $t2 = [regex]::Replace($t, $pat, {
        param($m)
        $script:changedHere++
        if($m.Groups["s"].Success){
          return $m.Groups["p"].Value + $val + $m.Groups["s"].Value
        } else {
          # preserve exact spacing when group 2 is whitespace
          if($m.Groups[2].Success){
            return $m.Groups["p"].Value + $m.Groups[2].Value + $val
          }
          return $m.Groups["p"].Value + $val
        }
      })
      if($changedHere -gt 0){
        $t = $t2
        $totalChanged += $changedHere
      }
    }
  }

  return @{ text=$t; changed=$totalChanged }
}

# Try common key variants
$c1 = Replace-Key $txt @("gate_cooldown_sec","gate-cooldown-sec") "$CooldownSec"
$txt = $c1.text
$c2 = Replace-Key $txt @("gate_max_plans_per_day","gate-max-plans-per-day") "$MaxPlansPerDay"
$txt = $c2.text

if($c1.changed -eq 0 -or $c2.changed -eq 0){
  Write-Host "WARNING: could not patch one or more keys."
  Write-Host ("cooldown_changed=" + $c1.changed + "  maxplans_changed=" + $c2.changed)
  Write-Host ""
  Write-Host "DIAGNOSTIC (show any gate-related lines):"
  Select-String -Path $canon -Pattern "gate_|gate-|cooldown|plans_per_day|max_plans" -Context 0,2 | ForEach-Object {
    $_.Line
    if($_.Context.PostContext){ $_.Context.PostContext | ForEach-Object { "  " + $_ } }
  }
  throw "Patch failed: gate keys not found in canonical runner with expected naming."
}

Set-Content -Encoding UTF8 -Path $canon -Value $txt

Write-Host "OK: patched => $canon"
Write-Host "Backup => $BAK"
Write-Host ""
Write-Host "VERIFY:"
Select-String -Path $canon -Pattern "gate_cooldown|cooldown_sec|gate_max_plans|max_plans_per_day|plans_per_day" | ForEach-Object { $_.Line }
