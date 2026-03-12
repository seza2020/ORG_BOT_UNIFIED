param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

function Stamp { (Get-Date -Format "yyyyMMdd_HHmmss") }

$PY = Join-Path $Root ".venv\Scripts\python.exe"
if(!(Test-Path $PY)){ throw "PY_NOT_FOUND: $PY" }

$L = Join-Path $RunRoot "logs"
$F = Join-Path $L "freeze"
$X = Join-Path $L "freeze_extracted"
$AUD = Join-Path $Root "logs\ops\audit"
New-Item -ItemType Directory -Force -Path $AUD | Out-Null
$NOTE = Join-Path $AUD ("PAPER_FREEZE_GO_NOGO_" + (Stamp) + ".txt")

"NOTE=$NOTE" | Set-Content -Encoding UTF8 $NOTE
"TS_LOCAL=$([DateTime]::Now.ToString('MM/dd/yyyy HH:mm:ss'))" | Add-Content -Encoding UTF8 $NOTE
"RUNROOT=$RunRoot" | Add-Content -Encoding UTF8 $NOTE
"LOGS=$L" | Add-Content -Encoding UTF8 $NOTE
"FREEZE_ROOT=$F" | Add-Content -Encoding UTF8 $NOTE
"" | Add-Content -Encoding UTF8 $NOTE

if(!(Test-Path $F)){
  New-Item -ItemType Directory -Force -Path $F | Out-Null
  "[INFO] CREATED_FREEZE_ROOT" | Tee-Object -FilePath $NOTE -Append | Out-Host
}

# 1) Find latest FREEZE zip
$zip = Get-ChildItem $F -File -Filter "FREEZE_TODAY_*.zip" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if($null -eq $zip){
  "[NO_GO] NO_FREEZE_ZIP_FOUND in $F" | Tee-Object -FilePath $NOTE -Append | Out-Host
  exit 2
}

"LATEST_FREEZE_ZIP=$($zip.FullName)" | Tee-Object -FilePath $NOTE -Append | Out-Host
"ZIP_SIZE_BYTES=$($zip.Length)" | Add-Content -Encoding UTF8 $NOTE
"" | Add-Content -Encoding UTF8 $NOTE

# 2) List zip entries + required prefixes
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead($zip.FullName)
$names = @($z.Entries | ForEach-Object { $_.FullName })

$required = @("meta_","announce_","env_TBOT_SAFE_","QC_","run_index_")
$missing = @()
foreach($r in $required){
  if(-not ($names | Where-Object { $_ -like "$r*" })){
    $missing += $r
  }
}

"--- ZIP_ENTRY_COUNT=$($z.Entries.Count) ---" | Add-Content -Encoding UTF8 $NOTE
($z.Entries | Sort-Object FullName | Select-Object FullName,Length,LastWriteTime | Out-String) | Add-Content -Encoding UTF8 $NOTE
$z.Dispose()

if($missing.Count -gt 0){
  "[NO_GO] FREEZE_ZIP_MISSING_REQUIRED_PREFIXES: $($missing -join ', ')" | Tee-Object -FilePath $NOTE -Append | Out-Host
  exit 2
}

"[OK] ZIP_HAS_REQUIRED_FILES" | Tee-Object -FilePath $NOTE -Append | Out-Host

# 3) Extract latest zip
New-Item -ItemType Directory -Force -Path $X | Out-Null
$dst = Join-Path $X $zip.BaseName
if(Test-Path $dst){ Remove-Item -Recurse -Force $dst }
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dst -Force
"EXTRACT_DST=$dst" | Tee-Object -FilePath $NOTE -Append | Out-Host

# 4) Verify extracted meta parses
$meta = Get-ChildItem $dst -File -Filter "meta_*.jsonl" | Select-Object -First 1
if($null -eq $meta){
  "[NO_GO] EXTRACTED_META_NOT_FOUND" | Tee-Object -FilePath $NOTE -Append | Out-Host
  exit 2
}

$code=@"
import json, sys, collections
p=r'''$($meta.FullName)'''
bad=0; n=0
kinds=collections.Counter()
with open(p,'r',encoding='utf-8') as f:
    for i,line in enumerate(f, start=1):
        if not line.strip():
            bad=1; print('BAD blank at', i); break
        try:
            o=json.loads(line)
        except Exception as e:
            bad=1; print('BAD', i, type(e).__name__, str(e)); print('LINE_PREFIX:', line[:200]); break
        kinds[o.get('kind','__NO_KIND__')] += 1
        n+=1
print('PARSED_OK_LINES=', n, 'BAD=', bad)
for k,v in kinds.most_common(12):
    print(f'{v:8d}  {k}')
sys.exit(0 if bad==0 else 2)
"@

& $PY -u -c $code | Tee-Object -FilePath $NOTE -Append | Out-Host
if($LASTEXITCODE -ne 0){
  "[NO_GO] EXTRACTED_META_INVALID_JSONL" | Tee-Object -FilePath $NOTE -Append | Out-Host
  exit 2
}

# 5) Check current live meta.jsonl (warn only)
$liveMeta = Join-Path $L "meta.jsonl"
if(!(Test-Path $liveMeta)){
  New-Item -ItemType File -Force -Path $liveMeta | Out-Null
  "[INFO] live meta.jsonl missing -> created" | Tee-Object -FilePath $NOTE -Append | Out-Host
}

$code2=@"
import json, sys
p=r'''$liveMeta'''
bad=0; n=0
with open(p,'r',encoding='utf-8', errors='replace') as f:
    for i,line in enumerate(f, start=1):
        if not line.strip():
            bad=1; print('BAD blank at', i); break
        try:
            json.loads(line)
        except Exception as e:
            bad=1; print('BAD', i, type(e).__name__, str(e)); print('LINE_PREFIX:', line[:200]); break
        n+=1
print('LIVE_META_OK_LINES=', n, 'BAD=', bad)
sys.exit(0 if bad==0 else 2)
"@

& $PY -u -c $code2 | Tee-Object -FilePath $NOTE -Append | Out-Host
if($LASTEXITCODE -ne 0){
  "[WARN] LIVE_META_CURRENTLY_BAD (guard should rotate at start)" | Tee-Object -FilePath $NOTE -Append | Out-Host
} else {
  "[OK] LIVE_META_CURRENTLY_VALID" | Tee-Object -FilePath $NOTE -Append | Out-Host
}

"" | Add-Content -Encoding UTF8 $NOTE
"====================" | Add-Content -Encoding UTF8 $NOTE
"GO: READY_FOR_TOMORROW" | Add-Content -Encoding UTF8 $NOTE
"====================" | Add-Content -Encoding UTF8 $NOTE

Write-Host ""
Write-Host "===================="
Write-Host "GO: READY_FOR_TOMORROW"
Write-Host "NOTE_WRITTEN=$NOTE"
Write-Host "===================="
exit 0
