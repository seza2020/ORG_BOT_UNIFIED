param()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fams = & (Join-Path $here "Get-TbotFamilies.ps1")

if (-not $fams) {
  "FAMILY_COUNT=0"
  exit 0
}

$fcount = @($fams).Count
"FAMILY_COUNT=$fcount"
$fams | Format-Table -AutoSize | Out-Host

if ($fcount -gt 1) {
  exit 2
}

exit 0
