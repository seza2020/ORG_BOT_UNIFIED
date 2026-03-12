$ErrorActionPreference = "Stop"

$Root = "C:\alpaca-bot\org_bot"
$Snap = Join-Path $Root "logs\backups\SNAPSHOT_20260206_081746"

if (-not (Test-Path $Snap)) {
  throw "Snapshot not found: $Snap"
}

# --- backup current state before rollback
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BK = Join-Path $Root ("logs\backups\ROLLBACK_PRE_{0}" -f $Stamp)
New-Item -ItemType Directory -Force -Path $BK | Out-Null

Write-Host "BACKUP (pre-rollback) => $BK"
Write-Host "RESTORE FROM SNAPSHOT  => $Snap"

# Stop any running python early
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force

# Files we care about
$targets = @(
  @{ Rel = "tbot\runtime\orchestrator.py";   Flat = "orchestrator.py" },
  @{ Rel = "tbot\runtime\shadow_pricing.py"; Flat = "shadow_pricing.py" },
  @{ Rel = "tools\run_shadow_final.ps1";     Flat = "run_shadow_final.ps1" }
)

# Backup current versions (if exist)
foreach ($t in $targets) {
  $cur = Join-Path $Root $t.Rel
  if (Test-Path $cur) {
    Copy-Item -LiteralPath $cur -Destination (Join-Path $BK $t.Flat) -Force
  }
}

function Restore-File {
  param(
    [Parameter(Mandatory=$true)][string]$Rel,
    [Parameter(Mandatory=$true)][string]$Flat
  )

  $cur = Join-Path $Root $Rel
  $snapExact = Join-Path $Snap $Rel
  $snapFlat  = Join-Path $Snap $Flat

  # Ensure destination directory exists
  $dstDir = Split-Path -Parent $cur
  if (-not (Test-Path $dstDir)) {
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
  }

  if (Test-Path $snapExact) {
    Copy-Item -LiteralPath $snapExact -Destination $cur -Force
    Write-Host "RESTORED: $Rel (snapshot exact)"
    return
  }

  if (Test-Path $snapFlat) {
    Copy-Item -LiteralPath $snapFlat -Destination $cur -Force
    Write-Host "RESTORED: $Rel (snapshot flat)"
    return
  }

  Write-Host "SKIP (not found in snapshot): $Rel"
}

# Restore
foreach ($t in $targets) {
  Restore-File -Rel $t.Rel -Flat $t.Flat
}

# Compile check
$P1 = Join-Path $Root "tbot\runtime\orchestrator.py"
$P2 = Join-Path $Root "tbot\runtime\shadow_pricing.py"

python -m py_compile $P1
python -m py_compile $P2

Write-Host "COMPILE OK"
Write-Host "NEXT RUN:"
Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$Root\tools\run_shadow_final.ps1`""
