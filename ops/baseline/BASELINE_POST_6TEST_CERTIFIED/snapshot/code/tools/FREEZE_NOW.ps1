param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$OutDir
)
$ErrorActionPreference="Stop"
if(-not $OutDir){ $OutDir = Join-Path $Root "logs\ops" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $OutDir ("FREEZE_{0}.zip" -f $ts)

$items = @(
  (Join-Path $Root "tbot"),
  (Join-Path $Root "tools"),
  (Join-Path $Root "configs"),
  (Join-Path $Root ".env"),
  (Join-Path $Root "requirements.txt"),
  (Join-Path $Root "pyproject.toml")
) | Where-Object { Test-Path $_ }

if(-not $items -or $items.Count -eq 0){
  throw "Nothing to freeze (paths not found). Root=$Root"
}

Compress-Archive -Path $items -DestinationPath $out -Force
Write-Host ("FREEZE_OK {0}" -f $out) -ForegroundColor Green
