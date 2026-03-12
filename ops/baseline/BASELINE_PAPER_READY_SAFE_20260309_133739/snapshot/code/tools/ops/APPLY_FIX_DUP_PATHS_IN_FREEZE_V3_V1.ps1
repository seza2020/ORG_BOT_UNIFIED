param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

function ParseFileOk([string]$p){
  $tokens=$null; $errs=$null
  [System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errs) | Out-Null
  if($errs -and $errs.Count -gt 0){
    $e=$errs[0]
    throw ("PARSE_FAIL: " + $e.Message + " line=" + $e.Extent.StartLineNumber + " col=" + $e.Extent.StartColumnNumber)
  }
}

$v3 = Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V3.ps1"
if(!(Test-Path $v3)){ throw "MISSING_V3=$v3" }

# stop scheduled freeze if running
$task="ORG_BOT_PAPER_FREEZE"
try{
  $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  if($t -and $t.State -eq "Running"){
    Stop-ScheduledTask -TaskName $task
    Start-Sleep -Seconds 2
  }
}catch{}

$lines = Get-Content -Encoding UTF8 $v3
$markerBase = "DEDUP_BEFORE_COMPRESS_V4"
$patched=0

# track here-strings so we DON'T patch inside them
$inHere=$false
$hereQuote=""

function IsHereStart([string]$ln){
  return ($ln -match '^\s*@["'']\s*$')
}
function IsHereEnd([string]$ln,[string]$q){
  if($q -eq "'"){ return ($ln -match '^\s*''@\s*$') }
  if($q -eq '"'){ return ($ln -match '^\s*"\@\s*$') }
  return $false
}

for($i=0; $i -lt $lines.Count; $i++){

  $ln = $lines[$i]

  if(-not $inHere -and (IsHereStart $ln)){
    $inHere=$true
    $hereQuote = $ln.Trim().Substring(1,1) # ' or "
    continue
  }
  if($inHere){
    if(IsHereEnd $ln $hereQuote){
      $inHere=$false
      $hereQuote=""
    }
    continue
  }

  if($ln -notmatch '(?i)\bCompress-Archive\b'){ continue }

  # Find the variable used in -Path / -LiteralPath in this line or next few lines
  $varRef=$null
  for($j=$i; $j -lt [Math]::Min($i+15,$lines.Count); $j++){
    $m=[regex]::Match($lines[$j],'(?i)\-(?:Path|LiteralPath)\s+(\$\w+)')
    if($m.Success){ $varRef=$m.Groups[1].Value; break }
  }
  if(-not $varRef){ continue }

  $vn = $varRef.TrimStart('$')
  $mkr = "$markerBase`_$vn"

  # skip if we already inserted a dedup block nearby
  $already=$false
  for($k=[Math]::Max(0,$i-8); $k -lt $i; $k++){
    if($lines[$k] -match [regex]::Escape($mkr)){ $already=$true; break }
  }
  if($already){ continue }

  $indent = ([regex]::Match($ln,'^\s*')).Value

  $block=@(
    "${indent}# $mkr (avoid duplicate paths crashing Compress-Archive)",
    "${indent}try {",
    "${indent}  `$tmp = Get-Variable -Name '$vn' -ValueOnly -ErrorAction SilentlyContinue",
    "${indent}  if(`$null -ne `$tmp){",
    "${indent}    `$arr = @(`$tmp) | Where-Object { `$_ } | Sort-Object -Unique",
    "${indent}    Set-Variable -Name '$vn' -Value `$arr -Force",
    "${indent}  }",
    "${indent}} catch { }",
    ""
  )

  # insert block BEFORE the Compress-Archive line
  $new = New-Object System.Collections.Generic.List[string]
  for($x=0; $x -lt $lines.Count; $x++){
    if($x -eq $i){
      foreach($b in $block){ $new.Add($b) | Out-Null }
    }
    $new.Add($lines[$x]) | Out-Null
  }
  $lines = $new.ToArray()
  $patched += 1

  # jump forward to avoid re-processing
  $i += ($block.Count + 1)
}

if($patched -gt 0){
  Copy-Item $v3 ($v3 + ".bak_dedupfix_" + (Get-Date -Format "yyyyMMdd_HHmmss")) -Force
  Set-Content -Encoding UTF8 -Path $v3 -Value $lines
  "PATCHED_COMPRESS_CALLS=$patched" | Out-Host
} else {
  "PATCHED_COMPRESS_CALLS=0 (no eligible Compress-Archive found)" | Out-Host
}

# Parse verify
ParseFileOk $v3
"V3_PARSE_OK=1" | Out-Host

# Run freeze v3 once (direct)
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass `
  -File $v3 -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

# Verify: latest err should NOT contain MIN_ZIP_EXC duplicate path
$ops = Join-Path $RunRoot "logs\ops"
$fo = Get-ChildItem $ops -File -Filter "FREEZE_OUT_*.txt" | Sort LastWriteTime -Desc | Select -First 1
$fe = Get-ChildItem $ops -File -Filter "FREEZE_ERR_*.txt" | Sort LastWriteTime -Desc | Select -First 1

"LAST_OUT=$($fo.FullName)" | Out-Host
Select-String -Path $fo.FullName -Pattern "MINZIP2_OK=|ZIP_SEL_COV_OK=" -ErrorAction SilentlyContinue |
  ForEach-Object { $_.Line } | Out-Host

"LAST_ERR=$($fe.FullName)" | Out-Host
$hit = Select-String -Path $fe.FullName -Pattern "MIN_ZIP_EXC=|duplicate path" -ErrorAction SilentlyContinue
if($hit){
  $hit | ForEach-Object { $_.Line } | Out-Host
  "DEDUP_RESULT=FAIL" | Out-Host
} else {
  "DEDUP_RESULT=PASS" | Out-Host
}
