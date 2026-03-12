# tools\QA_META_SUMMARY_V1.ps1
[CmdletBinding()]
param(
  [string]$Day = "",   # YYYY-MM-DD PT (optional)
  [int]$MaxBoots = 3,
  [int]$Cap = 150
)

$ErrorActionPreference="Stop"
$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot" }

$PY  = Join-Path $ROOT ".venv\Scripts\python.exe"
if(-not (Test-Path $PY)){ throw "Missing venv python: $PY" }

$OPS = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force -Path $OPS | Out-Null

$meta = Join-Path $ROOT "logs\meta.jsonl"
if(-not (Test-Path $meta)){ throw "Missing: $meta" }

if($Day){ $env:TBOT_QA_DAY = $Day } else { Remove-Item Env:TBOT_QA_DAY -ErrorAction SilentlyContinue }
$env:TBOT_QA_MAX_BOOTS = "$MaxBoots"
$env:TBOT_QA_CAP       = "$Cap"

$py = Join-Path $ROOT "tools\qa_meta_summary.py"
if(-not (Test-Path $py)){ throw "Missing: $py" }

$out = & $PY $py
$stamp = if($Day){ $Day.Replace("-","") } else { (Get-Date).ToString("yyyyMMdd") }
$path  = Join-Path $OPS ("QA_META_SUMMARY_{0}.txt" -f $stamp)

$out | Out-File -Encoding UTF8 -FilePath $path
$out
Write-Host ("WROTE => " + $path)
