param(
  [Parameter(Mandatory=$true)][string]$ProjectPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Log([string]$m){ Write-Host ("[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $m) }
function Ensure-Dir([string]$p){ if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-File([string]$p, [string]$content){
  Ensure-Dir (Split-Path $p -Parent)
  Set-Content -LiteralPath $p -Encoding UTF8 -Value $content
}

if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "ProjectPath not found" }

# --- Create baseline knowledge docs ---
$DocsRoot = Join-Path $ProjectPath "docs"
$MGPT = Join-Path $DocsRoot "mgpt"
Ensure-Dir $DocsRoot
Ensure-Dir $MGPT
Ensure-Dir (Join-Path $DocsRoot "stage_gates")
Ensure-Dir (Join-Path $DocsRoot "tasks")
Ensure-Dir (Join-Path $ProjectPath "dailies")
Ensure-Dir (Join-Path $ProjectPath "latest_daily\freeze")
Ensure-Dir (Join-Path $ProjectPath "latest_daily\live")

Log "WRITE_BASELINE_DOCS"

Write-File (Join-Path $ProjectPath "MYGPT_BOOTSTRAP.md") @"
# MYGPT_BOOTSTRAP — ORG_BOT

## Mission
Operate an auditable trading bot pipeline with strict safety boundaries and staged promotion:
SHADOW -> PAPER -> LIVE.

## Hard Safety Rules
- Never upload or store secrets (alpaca_env.ps1, .env, API keys, tokens, private keys).
- Scope is limited to: C:\alpaca-bot\org_bot
- Shadow mode: no live orders.

## Operating Model (Artifacts)
- STATIC_CODE / STATIC_DOCS / STATIC_OPS: upload only when changed.
- ROLLING_LAST10 + DAILY_LATEST: upload daily (replace previous).

## What MyGPT should do by default
- Treat reliability, risk controls, and auditability as first-class requirements.
- Prefer deterministic, measurable changes over “clever” changes.
- Always propose changes as copy/paste-ready PowerShell + file diffs when possible.

## Key Paths
- Root: C:\alpaca-bot\org_bot
- Upload output: C:\alpaca-bot\org_bot\_MYGPT_UPLOAD\LATEST
"@

Write-File (Join-Path $ProjectPath "PROJECT_SNAPSHOT.md") @"
# PROJECT_SNAPSHOT — ORG_BOT

Date: $(Get-Date -Format "yyyy-MM-dd")
Timezone: America/Los_Angeles (PT)

## Current Mode
SHADOW

## Current Objective
Stabilize daily runs and artifacts, then pass stage gate to PAPER.

## What is working
- Daily packaging tool produces 5 upload artifacts under size limits.

## Open Items
- Fill in exact run commands and real operational runbooks.
- Confirm stage gates and evidence requirements.

## Next Actions (ordered)
1) Run Shadow session
2) Produce Daily artifacts
3) Upload ROLLING + DAILY
4) Review QC and error tags
"@

Write-File (Join-Path $MGPT "INDEX.md") @"
# MyGPT Knowledge Index (ORG_BOT)

## Core
- MYGPT_BOOTSTRAP.md (root)
- PROJECT_SNAPSHOT.md (root)

## Runbooks
- OPS_RUNBOOK_DAILY.md
- OPS_RUNBOOK_SHADOW.md
- OPS_RUNBOOK_PAPER.md
- OPS_RUNBOOK_LIVE.md

## Risk & Controls
- RISK_POLICY.md
- KILL_SWITCH_RULES.md
- ERROR_TAGS.md
- METRICS_SPEC.md

## Architecture
- ARCHITECTURE_OVERVIEW.md
- DIRECTORY_MAP.md
- DATA_DICTIONARY.md

## Stage Gates
- docs/stage_gates/STAGE_GATE_SHADOW_TO_PAPER.md
- docs/stage_gates/STAGE_GATE_PAPER_TO_LIVE.md
"@

Write-File (Join-Path $MGPT "OPS_RUNBOOK_DAILY.md") @"
# OPS_RUNBOOK_DAILY

## Daily sequence
1) Run Shadow session (no orders).
2) Collect outputs into latest_daily/ and logs/.
3) Build upload artifacts (5 files).
4) Upload:
   - Always replace: MYGPT_ROLLING_LAST10.zip, MYGPT_DAILY_LATEST.zip
   - Replace static only if changed.

## Minimum checks
- No SECRET_HIT in packaging
- QC summary present (or explain missing)
- Rolling and Daily ZIP sizes within cap
"@

Write-File (Join-Path $MGPT "RISK_POLICY.md") @"
# RISK_POLICY (High Level)

## Primary objective
Capital preservation and bounded drawdown.

## Controls
- Define max daily loss and max weekly loss in R-units.
- Use kill-switch rules when errors, slippage, or unexpected behavior occurs.
- Promote stages only after evidence thresholds are met.

## Evidence-based gating
All promotions require logs + QC artifacts demonstrating stability.
"@

Write-File (Join-Path $MGPT "KILL_SWITCH_RULES.md") @"
# KILL_SWITCH_RULES

Trigger immediate stand-down if any occurs:
- Any suspected secret exposure risk
- Repeated runtime crashes or reconnect loops
- Order-routing behavior observed in SHADOW (should be none)
- Data integrity failure (missing core fields, corrupted JSONL)

Stand-down actions:
- Stop bot
- Preserve logs
- Produce a DAILY artifact bundle for audit
- Diagnose before resuming
"@

Write-File (Join-Path $MGPT "ERROR_TAGS.md") @"
# ERROR_TAGS

Use consistent tags for post-run classification:
- DATA_MISSING
- OUT_OF_SESSION
- ALPHA_OFF
- REGIME_BLOCK
- RISK_BLOCK
- EXEC_FAIL
- RECONNECT
- DUPLICATE_GUARD
- TIME_SYNC
- UNKNOWN
"@

Write-File (Join-Path $MGPT "METRICS_SPEC.md") @"
# METRICS_SPEC

Operational metrics:
- Uptime %
- Crash count / day
- Reconnect count / day
- Artifact compliance % (did we produce and upload daily?)
- QC pass streak

Trading metrics (when in PAPER/LIVE):
- R-multiples
- Win rate
- Expectancy
- Profit factor
- Max drawdown (R)
- Rule compliance %
"@

Write-File (Join-Path $MGPT "ARCHITECTURE_OVERVIEW.md") @"
# ARCHITECTURE_OVERVIEW (Placeholder)

Describe:
- Orchestrator / runner entrypoints
- Strategy layers (core/alpha/risk/regime/execution)
- Shadow vs Paper vs Live differences
- Where logs and artifacts are written
"@

Write-File (Join-Path $MGPT "DIRECTORY_MAP.md") @"
# DIRECTORY_MAP

High-level map (edit to match reality):

- docs/
  - mgpt/
  - stage_gates/
  - tasks/
- tools/
- logs/
- dailies/
- latest_daily/
  - freeze/
  - live/
- _MYGPT_UPLOAD/
  - LATEST/
  - HISTORY/
"@

Write-File (Join-Path $MGPT "DATA_DICTIONARY.md") @"
# DATA_DICTIONARY (Placeholder)

Define key JSONL schemas:
- meta.jsonl records
- shadow_plans.jsonl records
- QC output format
"@

# --- Stage gates (overwrite with full templates) ---
Write-File (Join-Path $DocsRoot "stage_gates\STAGE_GATE_SHADOW_TO_PAPER.md") @"
# STAGE GATE: SHADOW -> PAPER

## Goal
Promote only after operational stability is proven.

## Required evidence (minimum)
- 10+ market sessions in Shadow with consistent artifacts.
- Zero secret exposure incidents.
- No unintended order placement in Shadow.
- QC pass streak and documented issues list.
- Rolling + Daily artifacts produced every session.

## Promotion checklist
- [ ] Daily artifacts present (ROLLING + DAILY)
- [ ] QC summaries present and reviewed
- [ ] No repeated crash loops
- [ ] Known issues documented with mitigation
- [ ] Paper config reviewed (no secrets uploaded)

## Rejection conditions
- Any unexplained crash / data corruption
- Missing required logs or schemas
- Any sign of order routing in Shadow
"@

Write-File (Join-Path $DocsRoot "stage_gates\STAGE_GATE_PAPER_TO_LIVE.md") @"
# STAGE GATE: PAPER -> LIVE

## Goal
Promote only after bounded drawdown and rule compliance are proven.

## Required evidence (minimum)
- 30+ paper trades following the exact live ruleset.
- Bounded drawdown in R (define threshold).
- High compliance % (define threshold).
- Stable operations (artifacts, QC, no crashes).
- Kill-switch tested and documented.

## Promotion checklist
- [ ] 30+ trades logged with R-multiples
- [ ] Expectancy and PF within targets
- [ ] Max drawdown within cap
- [ ] Compliance % above threshold
- [ ] Kill-switch rules validated
"@

# --- docs/tasks must contain at least one file ---
Write-File (Join-Path $DocsRoot "tasks\TASKS_INDEX.md") @"
# TASKS_INDEX

Operational tasks:
- Daily run + QA + pack + upload
- Weekly review: stability, error tags, improvements
- Stage gate reviews: evidence collection and decision log
"@

# --- Ensure manifests exist (lightweight) ---
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath "MANIFEST.txt"))) {
  Write-File (Join-Path $ProjectPath "MANIFEST.txt") "MANIFEST`nCreated=$(Get-Date -Format o)"
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath "latest_daily\MANIFEST.txt"))) {
  Write-File (Join-Path $ProjectPath "latest_daily\MANIFEST.txt") "LATEST_DAILY_MANIFEST`nCreated=$(Get-Date -Format o)"
}

# --- Run the daily packer to produce the 5 upload files ---
$DailyTool = Join-Path $ProjectPath "tools\BUILD_MYGPT_DAILY.ps1"
if (-not (Test-Path -LiteralPath $DailyTool)) { throw "Missing daily tool: tools\BUILD_MYGPT_DAILY.ps1" }

Log "RUN_DAILY_PACKER"
& pwsh -NoProfile -ExecutionPolicy Bypass -File $DailyTool -ProjectPath $ProjectPath -RollingDays 10 -KeepHistory 7 -MaxZipMB 490 | Out-Host

Log "BASELINE_DONE"
$Latest = Join-Path $ProjectPath "_MYGPT_UPLOAD\LATEST"
Get-ChildItem -LiteralPath $Latest -File | Sort-Object Name | Format-Table Name,Length,LastWriteTime -Auto
