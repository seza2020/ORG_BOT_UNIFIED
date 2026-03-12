$ErrorActionPreference = "Stop"

$U    = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$BASE = "C:\alpaca-bot\ORG_BOT_UNIFIED\ops\baseline\BASELINE_PAPER_READY_SAFE_20260309_133739"
$SNAP = Join-Path $BASE "snapshot"
$CODE = Join-Path $U "code"
$OPS  = Join-Path $U "ops"
$RTP  = Join-Path $U "runtime\paper"

function Copy-DirSafe {
  param([string]$Source,[string]$Dest,[string[]]$ExcludeDirs=@())
  if (!(Test-Path $Source)) { throw "MISSING_SOURCE=$Source" }
  New-Item -ItemType Directory -Force $Dest | Out-Null
  $args = @($Source,$Dest,"/E","/PURGE","/R:1","/W:1","/NFL","/NDL","/NJH","/NJS","/NP","/XF","*.pyc")
  if ($ExcludeDirs.Count -gt 0) {
    $args += "/XD"
    $args += $ExcludeDirs
  }
  & robocopy @args | Out-Null
  $rc = $LASTEXITCODE
  if ($rc -ge 8) { throw "ROBOCOPY_RESTORE_FAIL Source=$Source Dest=$Dest ExitCode=$rc" }
}

Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match "tbot\.main" } |
  ForEach-Object {
    try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {}
  }

Start-Sleep 2

Copy-DirSafe -Source (Join-Path $SNAP "code") -Dest $CODE
Copy-DirSafe -Source (Join-Path $SNAP "ops") -Dest $OPS -ExcludeDirs @((Join-Path $OPS "baseline"),(Join-Path $OPS "evidence"))
Copy-DirSafe -Source (Join-Path $SNAP "runtime_paper") -Dest $RTP

"RESTORE_BASELINE_OK"
"BASELINE=C:\alpaca-bot\ORG_BOT_UNIFIED\ops\baseline\BASELINE_PAPER_READY_SAFE_20260309_133739"
