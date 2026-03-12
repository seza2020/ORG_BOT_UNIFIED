param([string]$Root="C:\alpaca-bot\org_bot",[int]$Force=0)
$ErrorActionPreference="Stop"
$canon = Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File $canon -Force $Force
