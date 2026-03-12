param(
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper",
  [string]$ProjectRoot = "C:\alpaca-bot\org_bot"
)

$ErrorActionPreference="Stop"
$L = Join-Path $RunRoot "logs"
$meta = Join-Path $L "meta.jsonl"
$PY = Join-Path $ProjectRoot ".venv\Scripts\python.exe"

if(!(Test-Path $L)){ New-Item -ItemType Directory -Force -Path $L | Out-Null }

if(!(Test-Path $meta)){
  New-Item -ItemType File -Force -Path $meta | Out-Null
  Write-Host "[META_GUARD] meta.jsonl missing -> created"
  exit 0
}

# verify JSONL quickly
$code=@"
import json, sys
p=r'''$meta'''
bad=0
with open(p,'r',encoding='utf-8', errors='replace') as f:
    for i,line in enumerate(f, start=1):
        if not line.strip():
            bad+=1; break
        try:
            json.loads(line)
        except Exception:
            bad+=1; break
print("BAD=", bad)
sys.exit(0 if bad==0 else 2)
"@

& $PY -u -c $code
if($LASTEXITCODE -eq 0){
  Write-Host "[META_GUARD] OK"
  exit 0
}

# rotate if bad
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$bakDir = Join-Path $L ("meta_guard_rotate_" + $ts)
New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
Copy-Item -Force -LiteralPath $meta -Destination (Join-Path $bakDir "meta.jsonl.BEFORE")
Move-Item -Force -LiteralPath $meta -Destination (Join-Path $L ("meta.guard_corrupt_" + $ts + ".jsonl"))
New-Item -ItemType File -Force -Path $meta | Out-Null

Write-Host "[META_GUARD] ROTATED_BAD_META -> fresh meta.jsonl"
Write-Host ("[META_GUARD] BKP_DIR=" + $bakDir)
exit 0
