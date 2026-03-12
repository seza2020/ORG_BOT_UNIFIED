param(
  [string]$Profile = "PAPER",
  [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Gov = "C:\alpaca-bot\ORG_BOT_UNIFIED\ops\task_wrappers\ORG_UNIFIED_PAPER_CANONICAL_GOVERNOR.ps1"
if (!(Test-Path $Gov)) { throw "CANONICAL_GOVERNOR_NOT_FOUND=$Gov" }

if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Join-Path "C:\alpaca-bot\ORG_BOT_UNIFIED\ops\evidence" ("TASK_LAUNCH_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
  New-Item -ItemType Directory -Force $OutDir | Out-Null
}

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $Gov -Profile $Profile -OutDir $OutDir -CertSeconds 20
