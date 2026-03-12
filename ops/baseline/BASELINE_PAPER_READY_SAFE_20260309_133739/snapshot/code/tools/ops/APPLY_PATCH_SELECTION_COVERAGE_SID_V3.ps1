param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

function BackupFile([string]$p,[string]$tag){
  if(Test-Path $p){
    Copy-Item $p ($p + ".bak_" + $tag + "_" + (Get-Date -Format "yyyyMMdd_HHmmss")) -Force
  }
}
function InsertAfterMarker([string]$text,[string]$marker,[string]$block){
  $i = $text.IndexOf($marker)
  if($i -lt 0){ throw "MARKER_NOT_FOUND:$marker" }
  $nl = $text.IndexOf("`n",$i); if($nl -lt 0){ $nl=$text.Length-1 }
  return $text.Insert($nl+1, $block + "`r`n")
}
function InsertBeforeMarkerLine([string]$text,[string]$marker,[string]$block){
  $i = $text.IndexOf($marker)
  if($i -lt 0){ throw "MARKER_NOT_FOUND:$marker" }
  $ls = $text.LastIndexOf("`n",$i); if($ls -lt 0){ $ls=0 } else { $ls=$ls+1 }
  return $text.Insert($ls, $block + "`r`n")
}

# 0) Stop freeze task if running
$task="ORG_BOT_PAPER_FREEZE"
$t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
if($t -and $t.State -eq "Running"){
  "STOPPING_FREEZE_TASK=1" | Out-Host
  Stop-ScheduledTask -TaskName $task
  Start-Sleep -Seconds 3
}

# 1) Write python (from base64; no quoting issues)
$anaDir = Join-Path $ProjectRoot "tools\analytics"
New-Item -ItemType Directory -Force -Path $anaDir | Out-Null
$pyPath = Join-Path $anaDir "selection_coverage_shadow_sid_v1.py"

$pyB64 = 'aW1wb3J0IGFyZ3BhcnNlLCBvcywganNvbiwgbWF0aAoKZGVmIHJlYWRfanNvbmwocGF0aCk6CiAgICBvdXQ9W10KICAgIGlmIG5vdCBwYXRoIG9yIG5vdCBvcy5wYXRoLmV4aXN0cyhwYXRoKToKICAgICAgICByZXR1cm4gb3V0CiAgICB3aXRoIG9wZW4ocGF0aCwicjIsZW5jb2Rpbmc9InV0Zi04IixlcnJvcnM9InJlcGxhY2UiKSBhcyBmOgogICAgICAgIGZvciBsbiBpbiBmOgogICAgICAgICAgICBsbj1sbi5zdHJpcCgpCiAgICAgICAgICAgIGlmIG5vdCBsbjoKICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgIHRyeToKICAgICAgICAgICAgICAgIG91dC5hcHBlbmQoanNvbi5sb2FkcyhsbikpCiAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgICAgICAgICBwYXNzCiAgICByZXR1cm4gb3V0CgpkZWYgandyaXRlKHBhdGgsb2JqKToKICAgIG9zLm1ha2VkaXJzKG9zLnBhdGguZGlybmFtZShwYXRoKSwgZXhpc3Rfb2s9VHJ1ZSkKICAgIHdpdGggb3BlbihwYXRoLCJ3IixlbmNvZGluZz0idXRmLTgiKSBhcyBmOgogICAgICAgIGpzb24uZHVtcChvYmo\,ZixlbnN1cmVfYXNjaWk9RmFsc2UsaW5kZW50PTIpCgpkZWYgbXdyaXRlKHBhdGgsbGluZXMpOgogICAgb3MubWFrZWRpcnMob3MucGF0aC5kaXJuYW1lKHBhdGgpLCBleGlzdF9vaz1UcnVlKQogICAgd2l0aCBvcGVuKHBhdGgsInciLGVuY29kaW5nPSJ1dGYtOCIpIGFzIGY6CiAgICAgICAgZi53cml0ZSgiXG4iLmpvaW4obGluZXMpLnJzdHJpcCgpKyJcbiIpCgpkZWYgbWFpbigpOgogICAgYXA9YXJnYXJzZS5Bcmd1bWVudFBhcnNlcigpCiAgICBhcC5hZGRfYXJndW1lbnQoIi0tYmFja3VwZGlyIiwgcmVxdWlyZWQ9VHJ1ZSkKICAgIGFwLmFkZF9hcmd1bWVudCgiLS1ydW5yb290IiwgcmVxdWlyZWQ9VHJ1ZSkKICAgIGFwLmFkZF9hcmd1bWVudCgiLS15bWQiLCByZXF1aXJlZD1UcnVlKQogICAgYXJncz1hcC5wYXJzZV9hcmdzKCkKCiAgICB5bWQ9YXJncy55bWQKICAgIGJrPWFyZ3MuYmFja3VwZGlyCiAgICBydW5yb290PWFyZ3MucnVucm9vdAogICAgYW5hPW9zLnBhdGguam9pbihydW5yb290LCJsb2dzIiwiYW5hbHl0aWNzIikKICAgIG9zLm1ha2VkaXJzKGFuYSwgZXhpc3Rfb2s9VHJ1ZSkKCiAgICBzcD1vcy5wYXRoLmpvaW4oYmssIGYi c2hhZG93X3BsYW5zX0ZVTExfe3ltZH0uanNvbmwiKQogICAgcm93cz1yZWFkX2pzb25sKHNwKQoKICAgIGl0ZW1zPVtdCiAgICBmb3IgbyBpbiByb3dzOgogICAgICAgIHNpZD1vLmdldCgic2lkIikgb3IgKG8uZ2V0KCJwbGFuIikgb3Ige30pLmdldCgic2lkIikKICAgICAgICBycj1vLmdldCgicnIiKSBvciBvLmdldCgiUlIiKSBvciAoby5nZXQoInBsYW4iKSBvciB7fSk uZ2V0KCJyciIpCiAgICAgICAgY29uZj1vLmdldCgiY29uZiIpIG9yIG8uZ2V0KCJjb25maWRlbmNlIikgb3IgKG8uZ2V0KCJwbGFuIikgb3Ige30pLmdldCg iY29uZmlkZW5jZSIpCiAgICAgICAgc3ltPW8uZ2V0KCJzeW1ib2wiKSBvciBvLmdldCgic3ltIikgb3IgKG8uZ2V0KCJwbGFuIikgb3Ige30pLmdldCgic3ltYm9sIikKICAgICAgICBpZiBzaWQgaXMgTm9uZToKICAgICAgICAgICAgY29udGludWUKICAgICAgICB0cnk6CiAgICAgICAgICAgIHJyPWZsb2F0KHJyKTsgY29uZj1mbG9hdChjb25mKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgaXRlbXMuYXBwZW5kKHsic2lkIjogc3RyKHNpZCksICJzeW1ib2wiOiBzeW0sICJyciI6IHJyLCAiY29uZiI6IGNvbmYsICJzY29yZSI6IHJyKmNvbmZ9KQoKICAgIGl0ZW1zLnNvcnQoa2V5PWxhbWJkYSB4OnhbInNjb3JlIl0sIHJldmVyc2U9VHJ1ZSkKICAgIGNhbmRpZGF0ZXM9bGVuKGl0ZW1zKQogICAgdG9wMT1tYXgoMSwgbWF0aC5jZWlsKGNhbmRpZGF0ZXMqMC4wMSkpIGlmIGNhbmRpZGF0ZXMgZWxzZSAwCiAgICB0b3A1PW1heCgxLCBtYXRoLmNlaWwoY2FuZGlkYXRlcyowLjA1KSkgaWYgY2FuZGlkYXRlcyBlbHNlIDA KCiAgICB0b3AxX3NpZD1zZXQoW3hbInNpZCJdIGZvciB4IGluIGl0ZW1zWzp0b3AxXV0pIGlmIHRvcDEgZWxzZSBzZXQoKQogICAgdG9wNV9zaWQ9c2V0KFt4WyJzaWQiXSBmb3IgeCBpbiBpdGVtc1s6dG9wNV1dKSBpZiB0b3A1IGVsc2Ugc2V0KCkKCiAgICBtZXRhPW9zLnBhdGguam9pbihiaywgZiJtZXRhX3t5bWR9Lmpzb25sIikKICAgIGlmIG5vdCBvcy5wYXRoLmV4aXN0cyhtZXRhKToKICAgICAgICBtZXRhPW9zLnBhdGguam9pbihydW5yb290LCJsb2dzIiwibWV0YS5qc29ubCIpCgogICAgc2VsZWN0ZWQ9c2V0KCkKICAgIGZvciBldiBpbiByZWFkX2pzb25sKG1ldGEpOgogICAgICAgIGlmIHN0cihldi5nZXQoImtpbmQiLCIiKSkgIT0gInNoYWRvd19hY2NlcHQiOgogICAgICAgICAgICBjb250aW51ZQogICAgICAgIHA9ZXYuZ2V0KCJwYXlsb2FkIikgb3Ige30KICAgICAgICBzaWQ9cC5nZXQoInNpZCIpCiAgICAgICAgaWYgc2lkOgogICAgICAgICAgICBzZWxlY3RlZC5hZGQoc3RyKHNpZCkpCgogICAgcmVwPXsKICAgICAgInltZCI6IHltZCwKICAgICAgImlucHV0cyI6IHsic2hhZG93X3BsYW5zX2Z1bGwiOiBzcCBpZiBvcy5wYXRoLmV4aXN0cyhzcCkgZWxzZSBOb25lLCAibWV0YSI6IG1ldGEgaWYgb3MucGF0aC5leGlzdHMobWV0YSkgZWxzZSBOb25lfSwKICAgICAgImNhbmRpZGF0ZXMiOiBjYW5kaWRhdGVzLAogICAgICAidG9wMV90b3RhbF9zaWQiOiBsZW4odG9wMV9zaWQpLAogICAgICAidG9wNV90b3RhbF9zaWQiOiBsZW4odG9wNV9zaWQpLAogICAgICAic2VsZWN0ZWRfdG90YWxfc2lkIjogbGVuKHNlbGVjdGVkKSwKICAgICAgInRvcDFfc2VsZWN0ZWRfc2lkIjogbGVuKHRvcDFfc2lkICYgc2VsZWN0ZWQpLAogICAgICAidG9wNV9zZWxlY3RlZF9zaWQiOiBsZW4odG9wNV9zaWQgJiBzZWxlY3RlZCksCiAgICAgICJ0b3AxX2NvdmVyYWdlX3NpZCI6IChsZW4odG9wMV9zaWQgJiBzZWxlY3RlZCkvbGVuKHRvcDFfc2lkKSkgaWYgbGVuKHRvcDFfc2lkKSBlbHNlIE5vbmUsCiAgICAgICJ0b3A1X2NvdmVyYWdlX3NpZCI6IChsZW4odG9wNV9zaWQgJiBzZWxlY3RlZCkvbGVuKHRvcDVfc2lkKSkgaWYgbGVuKHRvcDVfc2lkKSBlbHNlIE5vbmUsCiAgICAgICJub3RlcyI6IFsiU0lELWJhc2VkOiB1c2VzIHNoYWRvd19hY2NlcHQgbWV0YSBldmVudHMuIE1lYW5pbmdmdWwgb25jZSBQYXBlciBydW5zIGluLXNlc3Npb24uIiwgIkxhdGVyIHVwZ3JhZGU6IGVuZC10by1lbmQgcGxhbl9pZCAoc2VsZWN0aW9uK29yZGVycykgZm9yIHBlcmZlY3QgY2FwdHVyZSBhY2NvdW50aW5nLiJdCiAgICB9CgogICAgZm9yIG91dGRpciBpbiAoYmssIGFuYSk6CiAgICAgICAgandyaXRlKG9zLnBhdGguam9pbihvdXRkaXIsIGYiU0VMRUNUSU9OX0NPVkVSQUdFX3t5bWR9Lmpzb24iKSwgcmVwKQogICAgICAgIG13cml0ZShvcy5wYXRoLmpvaW4ob3V0ZGlyLCBmIlNFTEVDVElPTl9DT1ZFUkFHRV97eW1kfS5tZCIpLCBbCiAgICAgICAgICBmIiMgU0VMRUNUSU9OIENPVkVSQUdFIChTSUQpIHt5bWR9IiwKICAgICAgICAgICIiLAogICAgICAgICAgZiItIGNhbmRpZGF0ZXM6IHtjYW5kaWRhdGVzfSIsCiAgICAgICAgICBmIi0gdG9wMV90b3RhbF9zaWQ6IHtyZXBbXCJ0b3AxX3RvdGFsX3NpZFwiXX0iLAogICAgICAgICAgZiItIHRvcDFfc2VsZWN0ZWRfc2lkOiB7cmVwW1widG9wMV9zZWxlY3RlZF9zaWRcIl19IiwKICAgICAgICAgIGYiLSB0b3AxX2NvdmVyYWdlX3NpZDoge3JlcFtcInRvcDFfY292ZXJhZ2Vfc2lkXCJdfSIsCiAgICAgICAgICBmIi0gdG9wNV90b3RhbF9zaWQ6IHtyZXBbXCJ0b3A1X3RvdGFsX3NpZFwiXX0iLAogICAgICAgICAgZiItIHRvcDVfc2VsZWN0ZWRfc2lkOiB7cmVwW1widG9wNV9zZWxlY3RlZF9zaWRcIl19IiwKICAgICAgICAgIGYiLSB0b3A1X2NvdmVyYWdlX3NpZDoge3JlcFtcInRvcDVfY292ZXJhZ2Vfc2lkXCJdfSIsCiAgICAgICAgICBmIi0gc2VsZWN0ZWRfdG90YWxfc2lkOiB7cmVwW1wic2VsZWN0ZWRfdG90YWxfc2lkXCJdfSIsCiAgICAgICAgXSkKCmlmIF9fbmFtZV9fPT0iX19tYWluX18iOgogICAgbWFpbigpCg=='
[System.IO.File]::WriteAllBytes($pyPath, [Convert]::FromBase64String($pyB64))
"OK=WROTE_SELECTION_COVERAGE_PY=$pyPath" | Out-Host

# 2) Compile python
$pyExe = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if(!(Test-Path $pyExe)){ $pyExe="python" }
& $pyExe -m py_compile $pyPath 2>$null
if($LASTEXITCODE -ne 0){ throw "PY_COMPILE_FAIL:selection_coverage_shadow_sid_v1.py" }
"PY_COMPILE_OK=1" | Out-Host

# 3) Patch FREEZE V3 by markers (idempotent)
$v3 = Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V3.ps1"
if(!(Test-Path $v3)){ throw "MISSING_V3=$v3" }
$fv = Get-Content -Raw -Encoding UTF8 $v3

# NEED injection after OPP_QUEUE_NEED_V2
if($fv -notmatch "SELECTION_COVERAGE_NEED_SHADOWSID_V3"){
  $fv = InsertAfterMarker $fv "OPP_QUEUE_NEED_V2" @"
# SELECTION_COVERAGE_NEED_SHADOWSID_V3
`$need += @(
  ("SELECTION_COVERAGE_{0}.json" -f `$ymd),
  ("SELECTION_COVERAGE_{0}.md" -f `$ymd)
)

"@
  "PATCHED_NEED=1" | Out-Host
} else { "PATCHED_NEED=0 (already)" | Out-Host }

# CALL injection before OPP_QUEUE_GUARANTEE_V1
if($fv -notmatch "SELECTION_COVERAGE_CALL_SHADOWSID_V3"){
  $fv = InsertBeforeMarkerLine $fv "OPP_QUEUE_GUARANTEE_V1" @"
# SELECTION_COVERAGE_CALL_SHADOWSID_V3
try{
  `$pyExe2 = Join-Path `$ProjectRoot ".venv\Scripts\python.exe"
  if(!(Test-Path `$pyExe2)){ `$pyExe2="python" }
  `$sc = Join-Path `$ProjectRoot "tools\analytics\selection_coverage_shadow_sid_v1.py"
  if(Test-Path `$sc){
    & `$pyExe2 `$sc --backupdir `$bkLocal --runroot `$RunRoot --ymd `$ymd 1>> `$out 2>> `$err
    "SELECTION_COVERAGE_OK=1" | Add-Content -Encoding UTF8 -Path `$out
  } else {
    "SELECTION_COVERAGE_MISSING=1" | Add-Content -Encoding UTF8 -Path `$err
  }
}catch{
  ("SELECTION_COVERAGE_EXC=" + `$_.Exception.Message) | Add-Content -Encoding UTF8 -Path `$err
}

"@
  "PATCHED_CALL=1" | Out-Host
} else { "PATCHED_CALL=0 (already)" | Out-Host }

BackupFile $v3 "selcov_sid_v3"
Set-Content -Encoding UTF8 -Path $v3 -Value $fv
try { [ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 $v3)) | Out-Null; "V3_PARSE_OK=1" | Out-Host } catch { throw "V3_PARSE_OK=0" }

# 4) Trigger Freeze + verify
Start-ScheduledTask -TaskName $task
Start-Sleep -Seconds 25

$ops = Join-Path $RunRoot "logs\ops"
$fo = Get-ChildItem $ops -File -Filter "FREEZE_OUT_*.txt" | Sort LastWriteTime -Desc | Select -First 1
"LAST_OUT=$($fo.FullName)" | Out-Host
Select-String -Path $fo.FullName -Pattern "RUNROOT_BACKUP_DIR=|SELECTION_COVERAGE_OK=|SELECTION_COVERAGE_EXC=" -ErrorAction SilentlyContinue |
  ForEach-Object { $_.Line } | Out-Host

$bk = (Select-String -Path $fo.FullName -Pattern '^RUNROOT_BACKUP_DIR=' | Select -First 1).Line.Split("=",2)[1].Trim()
$ymd = ($bk -replace '^.*FREEZE_BACKUP_(\d{8}).*','$1')
"BK=$bk ymd=$ymd" | Out-Host

Get-ChildItem $bk -File -Filter ("SELECTION_COVERAGE_{0}.*" -f $ymd) -ErrorAction SilentlyContinue |
  Format-Table Name,Length,LastWriteTime

"OK=SELECTION_COVERAGE_SID_V3_INSTALLED_AND_VERIFIED" | Out-Host
