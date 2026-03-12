$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$TASKDIR = Join-Path $OPS "tasks"
$EVID    = Join-Path $OPS "evidence"

$TASKNAME = "\ORG_UNIFIED_PAPER_CANONICAL_V1"
$XMLPATH  = Join-Path $TASKDIR "ORG_UNIFIED_PAPER_CANONICAL_V1.xml"

if (!(Test-Path -LiteralPath $EVID)) {
  New-Item -ItemType Directory -Force -Path $EVID | Out-Null
}
if (!(Test-Path -LiteralPath $XMLPATH)) {
  throw "TASK_XML_NOT_FOUND=$XMLPATH"
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $EVID ("CANONICAL_TASK_XML_REGISTER_RUN_" + $ts)
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$deleteOut = Join-Path $outDir "schtasks_delete_stdout.txt"
$deleteErr = Join-Path $outDir "schtasks_delete_stderr.txt"
$createOut = Join-Path $outDir "schtasks_create_stdout.txt"
$createErr = Join-Path $outDir "schtasks_create_stderr.txt"

try {
  Start-Process -FilePath "schtasks.exe" `
    -ArgumentList @("/delete","/tn",$TASKNAME,"/f") `
    -NoNewWindow `
    -RedirectStandardOutput $deleteOut `
    -RedirectStandardError $deleteErr `
    -Wait | Out-Null
} catch {}

$createProc = Start-Process -FilePath "schtasks.exe" `
  -ArgumentList @("/create","/tn",$TASKNAME,"/xml",$XMLPATH,"/f") `
  -NoNewWindow `
  -RedirectStandardOutput $createOut `
  -RedirectStandardError $createErr `
  -PassThru `
  -Wait

$exitCode = $createProc.ExitCode

"CANONICAL_TASK_XML_REBUILD_V1_REGISTER_DONE"
("TASKNAME=" + $TASKNAME)
("XMLPATH=" + $XMLPATH)
("OUTDIR=" + $outDir)
("CREATE_EXIT_CODE=" + $exitCode)
("CREATE_STDOUT=" + $createOut)
("CREATE_STDERR=" + $createErr)

if ($exitCode -ne 0) {
  throw ("TASK_REGISTER_FAILED_EXITCODE=" + $exitCode)
}
