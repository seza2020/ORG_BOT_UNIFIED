param(
  [string]$Root = "C:\alpaca-bot\org_bot"
)

$ErrorActionPreference="Stop"

$targets=@(
  (Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"),
  (Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"),
  (Join-Path $Root "tools\shadow_run.ps1")
)

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$bakDir = Join-Path $Root ("logs\ops\patches\SESSION_GUARD_RTH_V3_" + $stamp)
New-Item -ItemType Directory -Force $bakDir | Out-Null

$BEGIN = "# --- SESSION_GUARD_RTH_V1 (RTH only) ---"
$END   = "# --- SESSION_GUARD_RTH_V1 END ---"

$patched=0
$skipped=0

foreach($t in $targets){
  if(-not (Test-Path $t)){
    Write-Host "SKIP_NOT_FOUND: $t"
    $skipped += 1
    continue
  }

  $s = Get-Content -Raw -Encoding UTF8 $t

  $b = $s.IndexOf($BEGIN, [System.StringComparison]::Ordinal)
  $e = $s.IndexOf($END,   [System.StringComparison]::Ordinal)

  if($b -lt 0 -or $e -lt 0 -or $e -le $b){
    Write-Host "SKIP_NO_GUARD_BLOCK: $t"
    $skipped += 1
    continue
  }

  $e2 = $e + $END.Length
  $pre  = $s.Substring(0, $b)
  $blk  = $s.Substring($b, $e2-$b)
  $post = $s.Substring($e2)

  # Only fix inside the guard block:
  # replace `$
  $blk2 = $blk -replace '`\$','$$'

  if($blk2 -eq $blk){
    Write-Host "SKIP_NO_BACKTICKS_IN_GUARD: $t"
    $skipped += 1
    continue
  }

  Copy-Item -Force $t (Join-Path $bakDir ([IO.Path]::GetFileName($t) + ".bak"))
  $s2 = $pre + $blk2 + $post
  Set-Content -Path $t -Value $s2 -Encoding UTF8
  Write-Host "PATCH_OK_FIX_BACKTICKS: $t"
  $patched += 1
}

Write-Host "BACKUP_DIR: $bakDir"
Write-Host "PATCHED: $patched  SKIPPED: $skipped"

# Syntax check
foreach($t in $targets){
  try {
    $null = [System.Management.Automation.Language.Parser]::ParseFile($t, [ref]$null, [ref]$null)
    Write-Host "PS_PARSE_OK: $t"
  } catch {
    Write-Host "PS_PARSE_FAIL: $t :: $($_.Exception.Message)"
    throw
  }
}
