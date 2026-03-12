param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$false)][string]$RunRoot,
  [Parameter(Mandatory=$true)][string]$ProfilePath,
  [Parameter(Mandatory=$true)][string]$InnerScriptPath
)
$ErrorActionPreference="Stop"

# RUN_SHADOW_PROFILE_CANON_V1

if(!(Test-Path $ProfilePath)){ throw ("MISSING_PROFILEPATH=" + $ProfilePath) }
$prof = Get-Content -Raw -Encoding UTF8 $ProfilePath | ConvertFrom-Json

# Resolve RunRoot from profile if not provided
if([string]::IsNullOrWhiteSpace($RunRoot)){
  if($prof.runroot){ $RunRoot=[string]$prof.runroot }
  elseif($prof.runtime){ $RunRoot=[string]$prof.runtime }
}
if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "RUNROOT_EMPTY" }

# Hard enforce shadow identity
if(([string]$RunRoot).ToLower() -notlike "*\shadow*"){ throw ("RUNROOT_NOT_SHADOW=" + $RunRoot) }

# Load secrets for SHADOW (no key printing except masked fingerprint from loader)
$ldr = Join-Path $ProjectRoot "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
if(!(Test-Path $ldr)){ throw ("MISSING_LOADER=" + $ldr) }
. $ldr -Profile "SHADOW" -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

# Enforce TBOT_PROFILE correct
$act = ([string]$env:TBOT_PROFILE).Trim().ToUpper()
if($act -ne "SHADOW"){ throw ("TBOT_PROFILE_MISMATCH expected=SHADOW actual=" + $act) }

if(!(Test-Path $InnerScriptPath)){ throw ("INNER_SCRIPT_NOT_FOUND=" + $InnerScriptPath) }

# Pass through any extra args passed to wrapper
$rest = $args

# Run inner in child pwsh
$pwsh="C:\Program Files\PowerShell\7\pwsh.exe"
if(!(Test-Path $pwsh)){ $pwsh=(Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
if([string]::IsNullOrWhiteSpace($pwsh)){ $pwsh=(Get-Command powershell.exe).Source }

& $pwsh -NoProfile -ExecutionPolicy Bypass -File $InnerScriptPath -ProjectRoot $ProjectRoot -RunRoot $RunRoot @rest
exit $LASTEXITCODE
