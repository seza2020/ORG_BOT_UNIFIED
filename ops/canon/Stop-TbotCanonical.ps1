$ErrorActionPreference = "Stop"

$U    = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$RTP  = Join-Path $U "runtime\paper"
$LOCK = Join-Path $RTP "locks\tbot_main.lock"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fams = & (Join-Path $here "Get-TbotFamilies.ps1")

foreach ($fam in @($fams)) {
  $pids = @()
  if ($fam.MemberPids) {
    $pids = $fam.MemberPids -split "," | ForEach-Object { [int]$_ } | Sort-Object -Descending
  }
  foreach ($id in $pids) {
    try { Stop-Process -Id $id -Force -ErrorAction Stop } catch {}
  }
}

Start-Sleep 3

$fams2 = & (Join-Path $here "Get-TbotFamilies.ps1")
"FAMILY_COUNT_AFTER_STOP=$(@($fams2).Count)"

if (@($fams2).Count -eq 0 -and (Test-Path $LOCK)) {
  try { Remove-Item $LOCK -Force -ErrorAction Stop } catch {}
}

"LOCK_EXISTS=$([bool](Test-Path $LOCK))"

if (@($fams2).Count -eq 0) {
  "STOP_OK_CLEAN_STATE"
  exit 0
}

"STOP_FAIL_FAMILY_REMAINS"
$fams2 | Format-Table -AutoSize | Out-Host
exit 2
