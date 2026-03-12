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
