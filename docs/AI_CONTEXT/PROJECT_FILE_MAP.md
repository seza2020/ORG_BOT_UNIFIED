# PROJECT FILE MAP

Project: ORG_BOT_UNIFIED

This document maps the critical file structure of the system so that analysts and AI models can locate key components quickly.

---

# 1. Root Directory

Root:

C:\alpaca-bot\ORG_BOT_UNIFIED

Major folders:

code
runtime
ops
docs

---

# 2. Core Trading Engine

Primary trading engine:

code\tbot

Key runtime entry:

tbot.main

Core orchestration:

code\tbot\runtime\orchestrator.py

Responsibilities:

signal orchestration
strategy evaluation
gate checks
plan creation

---

# 3. Strategy Layer

Strategy logic typically resides inside:

code\tbot\strategies

Examples include:

trend strategies
gap strategies
VWAP strategies
ORB strategies

These modules produce candidate signals.

---

# 4. Gate System

Trade validation occurs inside:

code\tbot\gate

Responsibilities:

risk validation
confidence filtering
regime compatibility
exposure control

The gate system is one of the most common veto locations.

---

# 5. Runtime Logs

Primary observability logs:

runtime\paper\logs

Important files include:

meta_events.jsonl
meta_engine.jsonl
shadow_plans.jsonl

These logs allow reconstruction of system decisions.

---

# 6. Runtime Modes

Runtime folders include:

runtime\paper
runtime\shadow

These directories store session logs and runtime artifacts.

---

# 7. Operations Tooling

Operational scripts reside in:

ops

Key subfolders include:

ops\tasks
ops\patches
ops\audit
ops\evidence

These tools are used for:

runtime supervision
diagnostics
forensics
system maintenance

---

# 8. Documentation Layer

Canonical AI context documentation resides in:

docs\AI_CONTEXT

Important files:

AI_CONTEXT_INDEX.md
CURRENT_SYSTEM_STATE.md
CURRENT_ISSUE.md
SYSTEM_ARCHITECTURE.md
TRADING_MODEL.md
RISK_MODEL.md
OPERATING_MODEL.md
PROJECT_FILE_MAP.md

These files define the official description of the system.

---

# 9. Most Important Files For Debugging

When diagnosing trading failures the most important files are:

orchestrator.py
gate logic modules
strategy engines
meta_events.jsonl
meta_engine.jsonl
shadow_plans.jsonl

These components define the decision pipeline.

---

# 10. Current Investigation Focus

Current investigation focuses on:

plan_created = 0

The goal is to identify which stage of the pipeline vetoes signal generation before plan creation.

