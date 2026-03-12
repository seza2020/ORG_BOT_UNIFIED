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
$bakDir = Join-Path $Root ("logs\ops\patches\SESSION_GUARD_RTH_V2_" + $stamp)
New-Item -ItemType Directory -Force $bakDir | Out-Null

$BEGIN = "# --- SESSION_GUARD_RTH_V1 (RTH only) ---"
$END   = "# --- SESSION_GUARD_RTH_V1 END ---"

$patched=0
$skipped=0

function Remove-DuplicateBlocks([string]$s){
  $idx = 0
  $firstKept = $false
  $out = New-Object System.Text.StringBuilder

  while($true){
    $b = $s.IndexOf($BEGIN, $idx, [System.StringComparison]::Ordinal)
    if($b -lt 0){
      # no more blocks; append rest
      [void]$out.Append($s.Substring($idx))
      break
    }

    # append text before this block
    [void]$out.Append($s.Substring($idx, $b-$idx))

    $e = $s.IndexOf($END, $b, [System.StringComparison]::Ordinal)
    if($e -lt 0){
      # malformed: can't find END; append rest and stop (fail-open)
      [void]$out.Append($s.Substring($b))
      break
    }
    $e2 = $e + $END.Length

    $block = $s.Substring($b, $e2-$b)

    if(-not $firstKept){
      # keep first block
      [void]$out.Append($block)
      # ensure newline after block
      if(-not $block.EndsWith("`r`n")){ [void]$out.Append("`r`n") }
      $firstKept = $true
    } else {
      # drop duplicates, but keep a clean newline
      [void]$out.Append("`r`n")
    }

    $idx = $e2
  }

  return $out.ToString()
}

foreach($t in $targets){
  if(-not (Test-Path $t)){
    Write-Host "SKIP_NOT_FOUND: $t"
    $skipped += 1
    continue
  }

  $s = Get-Content -Raw -Encoding UTF8 $t
  $count = ([regex]::Matches($s, [regex]::Escape($BEGIN))).Count

  if($count -le 1){
    Write-Host "SKIP_OK_MARKERS=$count : $t"
    $skipped += 1
    continue
  }

  Copy-Item -Force $t (Join-Path $bakDir ([IO.Path]::GetFileName($t) + ".bak"))
  $s2 = Remove-DuplicateBlocks $s
  Set-Content -Path $t -Value $s2 -Encoding UTF8
  Write-Host "PATCH_OK_DEDUP markers=$count -> 1 : $t"
  $patched += 1
}

Write-Host "BACKUP_DIR: $bakDir"
Write-Host "PATCHED: $patched  SKIPPED: $skipped"

# Quick syntax check for patched PS files
foreach($t in $targets){
  try {
    $null = [System.Management.Automation.Language.Parser]::ParseFile($t, [ref]$null, [ref]$null)
    Write-Host "PS_PARSE_OK: $t"
  } catch {
    Write-Host "PS_PARSE_FAIL: $t :: $($_.Exception.Message)"
    throw
  }
}
