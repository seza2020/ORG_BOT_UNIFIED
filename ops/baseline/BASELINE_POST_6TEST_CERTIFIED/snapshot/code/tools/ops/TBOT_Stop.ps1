param([string]$Root = "C:\alpaca-bot\org_bot")
$ErrorActionPreference = "Continue"
Set-Location $Root

Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "STOPPED python processes." -ForegroundColor Green
