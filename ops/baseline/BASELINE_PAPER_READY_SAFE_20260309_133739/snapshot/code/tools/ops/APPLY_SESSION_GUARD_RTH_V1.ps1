$ErrorActionPreference = "Stop"

$ROOT = "C:\alpaca-bot\org_bot"

$targets = @(
  (Join-Path $ROOT "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"),
  (Join-Path $ROOT "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"),
  (Join-Path $ROOT "tools\shadow_run.ps1")
) | Where-Object { Test-Path $_ }

if(-not $targets -or $targets.Count -eq 0){
  throw "No target runner scripts found under tools\. Add your runner path(s) to targets and re-run."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$bakDir = Join-Path $ROOT ("logs\ops\patches\SESSION_GUARD_RTH_V1_" + $stamp)
New-Item -ItemType Directory -Force -Path $bakDir | Out-Null

$marker = "SESSION_GUARD_RTH_V1"

$guard = @'
# --- SESSION_GUARD_RTH_V1 (RTH only) ---
try {
  `$nowLocal = Get-Date
  `$tzET = [TimeZoneInfo]::FindSystemTimeZoneById("Eastern Standard Time")
  `$nowET = [TimeZoneInfo]::ConvertTime(`$nowLocal, `$tzET)

  # RTH window in ET: 09:30 - 16:00
  `$startET = Get-Date -Date `$nowET.Date.AddHours(9).AddMinutes(30)
  `$endET   = Get-Date -Date `$nowET.Date.AddHours(16).AddMinutes(0)

  if(`$nowET -lt `$startET -or `$nowET -gt `$endET){
    `$msg = ("[SESSION_GUARD] OUT_OF_SESSION: nowET={0} window=09:30-16:00 ET. Exiting 0." -f $nowET.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-Host `$msg
    exit 0
  }
} catch {
  # Fail-open: do not block run if timezone conversion fails
}
# --- SESSION_GUARD_RTH_V1 END ---
'@.TrimEnd() + "

"

function Insert-AfterFirstMatch {
  param(
    [string]$Text,
    [string]$Regex,
    [string]$InsertBlock
  )
  $m = [regex]::Match($Text, $Regex, [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if(-not $m.Success){ return $null }
  $idx = $m.Index + $m.Length
  return $Text.Substring(0,$idx) + "`r`n" + $InsertBlock + $Text.Substring($idx)
}

$patched = 0
$skipped = 0

foreach($t in $targets){
  $s = Get-Content -Raw -Encoding UTF8 $t

  if($s -match $marker){
    Write-Host "SKIP_ALREADY_PRESENT: $t"
    $skipped += 1
    continue
  }

  Copy-Item $t (Join-Path $bakDir ([IO.Path]::GetFileName($t) + ".bak")) -Force

  $s2 = Insert-AfterFirstMatch -Text $s -Regex "^\s*\$ErrorActionPreference\s*=\s*`"Stop`"\s*$" -InsertBlock $guard

  if(-not $s2){
    $s2 = Insert-AfterFirstMatch -Text $s -Regex "^\s*param\s*\([\s\S]*?\)\s*$" -InsertBlock $guard
  }

  if(-not $s2){
    $s2 = $guard + $s
  }

  Set-Content -Path $t -Value $s2 -Encoding UTF8
  Write-Host "PATCH_OK: $t"
  $patched += 1
}

Write-Host "BACKUP_DIR: $bakDir"
Write-Host "PATCHED: $patched  SKIPPED: $skipped"

foreach($t in $targets){
  try {
    $null = [System.Management.Automation.Language.Parser]::ParseFile($t, [ref]$null, [ref]$null)
    Write-Host "PS_PARSE_OK: $t"
  } catch {
    Write-Host "PS_PARSE_FAIL: $t :: $($_.Exception.Message)"
    throw
  }
}

