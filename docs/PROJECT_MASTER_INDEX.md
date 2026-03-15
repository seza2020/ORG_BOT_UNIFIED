# ORG_BOT_UNIFIED — Project Master Index

## Purpose

This file is the master navigation index for the entire project.

It defines:

- canonical authority files
- architecture files
- runtime context files
- investigation files
- conversation history
- code root
- bundle root

---

# 1. Primary Authority Files

These files define current truth and must be read first.

## Current State
docs\AI_CONTEXT\CURRENT_SYSTEM_STATE.md

## Current Issue
docs\AI_CONTEXT\CURRENT_ISSUE.md

## AI Startup Prompt
docs\AI_CONTEXT\AI_STARTUP_PROMPT.md

## AI Context Index
docs\AI_CONTEXT\AI_CONTEXT_INDEX.md

---

# 2. Architecture Layer

## System Map
docs\architecture\SYSTEM_MAP.md

## Decision Tree
docs\architecture\DECISION_TREE.md

## System Architecture
docs\AI_CONTEXT\SYSTEM_ARCHITECTURE.md

## Code Index
docs\AI_CONTEXT\CODE_INDEX.md

## Runtime Pipeline
docs\AI_CONTEXT\RUNTIME_PIPELINE.md

## Data Flow Map
docs\AI_CONTEXT\DATA_FLOW_MAP.md

## Forensic Playbook
docs\AI_CONTEXT\FORENSIC_PLAYBOOK.md

---

# 3. Trading / Risk / Operating Model

## Trading Model
docs\AI_CONTEXT\TRADING_MODEL.md

## Risk Model
docs\AI_CONTEXT\RISK_MODEL.md

## Operating Model
docs\AI_CONTEXT\OPERATING_MODEL.md

## Pipeline Veto Map
docs\AI_CONTEXT\PIPELINE_VETO_MAP.md

## Project File Map
docs\AI_CONTEXT\PROJECT_FILE_MAP.md

---

# 4. Runtime Context Layer

## Runtime Index
docs\AI_RUNTIME_CONTEXT\AI_RUNTIME_INDEX.md

## Latest Runtime Summary
docs\AI_RUNTIME_CONTEXT\LATEST_RUNTIME_SUMMARY.md

## Blocker Counts
docs\AI_RUNTIME_CONTEXT\BLOCKER_COUNTS.md

## Project Context Map
docs\AI_RUNTIME_CONTEXT\PROJECT_CONTEXT_MAP.md

## Runtime Samples
docs\AI_RUNTIME_CONTEXT\SAMPLES\meta_events_sample.jsonl
docs\AI_RUNTIME_CONTEXT\SAMPLES\meta_engine_sample.jsonl
docs\AI_RUNTIME_CONTEXT\SAMPLES\shadow_plans_sample.jsonl
docs\AI_RUNTIME_CONTEXT\SAMPLES\risk_ledger_sample.json

---

# 5. Investigation Layer

## Investigation Index
docs\AI_INVESTIGATION\AI_INVESTIGATION_INDEX.md

## Active Investigation
docs\AI_INVESTIGATION\ACTIVE_INVESTIGATION.md

## Active Ticket
docs\AI_INVESTIGATION\ACTIVE_TICKET.md

## Acceptance Criteria
docs\AI_INVESTIGATION\ACCEPTANCE_CRITERIA.md

## Next Action
docs\AI_INVESTIGATION\NEXT_ACTION.md

---

# 6. Conversation History

Conversation snapshots are stored here:

docs\AI_CONTEXT\CONVERSATION\

Current known files:

- P1.md
- P2.md
- P3.md
- P4.md
- P5.md

Future files should continue as:

- P6.md
- P7.md
- P8.md
- ...

These are history files, not authority files.

---

# 7. Code Root

Canonical code root:

code\tbot\

Important code zones:

- code\tbot\market
- code\tbot\runtime
- code\tbot\policy
- code\tbot\strategies
- code\tbot\risk
- code\tbot\analytics
- code\tbot\portfolio
- code\tbot\core
- code\tbot\tools
- code\tbot\tests

---

# 8. Local Runtime Root

Local runtime stays outside GitHub truth.

Primary runtime root:

runtime\paper\

Important runtime logs:

- runtime\paper\logs\meta_events.jsonl
- runtime\paper\logs\meta_engine.jsonl
- runtime\paper\logs\shadow_plans.jsonl
- runtime\paper\logs\risk_ledger_v1.json

---

# 9. AI Bundle Root

Canonical AI bundle:

AI_CONTEXT_BUNDLE.zip

Bundle contents:

- AI_CONTEXT
- AI_ARCHITECTURE
- AI_RUNTIME_CONTEXT
- AI_INVESTIGATION
- README_CONTEXT_BOOTSTRAP.md

---

# 10. GitHub Source of Truth

GitHub repository:

https://github.com/seza2020/ORG_BOT_UNIFIED

Use GitHub for:

- canonical code
- controlled docs
- institutional repo structure

Do not use GitHub as runtime storage.

---

# 11. Reading Order for New AI Sessions

Recommended order:

1. docs\AI_CONTEXT\AI_STARTUP_PROMPT.md
2. docs\AI_CONTEXT\CURRENT_SYSTEM_STATE.md
3. docs\AI_CONTEXT\CURRENT_ISSUE.md
4. docs\architecture\SYSTEM_MAP.md
5. docs\architecture\DECISION_TREE.md
6. docs\AI_RUNTIME_CONTEXT\LATEST_RUNTIME_SUMMARY.md
7. docs\AI_INVESTIGATION\ACTIVE_INVESTIGATION.md
8. docs\AI_INVESTIGATION\NEXT_ACTION.md

---

# 12. Governance Rule

Authority priority:

1. CURRENT_SYSTEM_STATE.md
2. CURRENT_ISSUE.md
3. ACTIVE_INVESTIGATION.md
4. NEXT_ACTION.md

Conversation files are support history only.

Runtime logs are evidence, not narrative authority.

---
