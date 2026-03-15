# ORG_BOT_UNIFIED — AI System Context

## Purpose

This file gives AI systems and engineers a concise system-level understanding of ORG_BOT_UNIFIED.

It should be read together with:

- AI_STARTUP_PROMPT.md
- AI_CONTEXT_INDEX.md
- CURRENT_SYSTEM_STATE.md
- CURRENT_ISSUE.md
- SYSTEM_MAP.md
- DECISION_TREE.md
- PROJECT_MASTER_INDEX.md

---

## System Identity

ORG_BOT_UNIFIED is an institutional-style algorithmic trading system.

Primary goals:

- capital preservation
- systematic execution
- risk-first operation
- auditability
- observability
- controlled scaling

Income targets are phase-based:

- Phase 1: \/year
- Phase 2: \/year
- Phase 3: \/year

The system is designed to scale only after stable validation.

---

## Core Philosophy

The system is not designed around prediction-first discretionary trading.

It is designed around:

- repeatable execution
- gating
- veto logic
- measurable risk
- evidence-based diagnostics

The project prioritizes:

1. capital protection
2. runtime integrity
3. observability
4. validation discipline
5. scalability after proof

---

## Architecture Layers

The high-level decision pipeline is:

Market Data
→ Regime
→ Core Context
→ Alpha Mode
→ Strategy Evaluation
→ Gate / Risk Checks
→ Plan Creation
→ Execution / Shadow / Paper Logging

Important interpretation rule:

If no plan is created, diagnosis must locate the exact veto stage rather than guessing.

---

## Core Runtime Concepts

### Regime
Determines whether market conditions are supportive, weak, trend-like, or chop-like.

### Core Context
Builds the immediate context used for downstream evaluation, such as:

- trend strength
- bias
- VWAP state
- EMA relation
- freshness fields

### Alpha Mode
Determines whether alpha strategies are active or blocked.

Typical reasons for alpha-off include:

- chop classification
- weak trend
- stale source state
- policy gating

### Strategy Evaluation
Strategies are evaluated only after context and mode are available.

### Gate
Gate logic decides whether a signal becomes a plan.

Typical veto families include:

- regime veto
- alpha veto
- confidence veto
- RR veto
- daily risk veto
- max plans veto
- cooldown veto

---

## Current Diagnostic Theme

A recurring project theme has been:

plan_created = 0

The institutional interpretation is:

- do not assume broken execution first
- first identify which stage vetoed the pipeline
- validate that using logs and structured evidence

---

## Runtime Evidence Sources

Primary evidence sources include:

- runtime\paper\logs\meta_events.jsonl
- runtime\paper\logs\meta_engine.jsonl
- runtime\paper\logs\shadow_plans.jsonl
- risk ledger outputs
- structured audits under docs\AI_RUNTIME_CONTEXT

Important rule:

Evidence is authoritative for runtime facts.
Narrative summaries are secondary.

---

## AI Reading Order

Recommended order for any new AI session:

1. AI_STARTUP_PROMPT.md
2. AI_CONTEXT_INDEX.md
3. CURRENT_SYSTEM_STATE.md
4. CURRENT_ISSUE.md
5. SYSTEM_MAP.md
6. DECISION_TREE.md
7. LATEST_RUNTIME_SUMMARY.md
8. ACTIVE_INVESTIGATION.md
9. NEXT_ACTION.md
10. PROJECT_MASTER_INDEX.md

---

## Governance Rule

Authority priority:

1. CURRENT_SYSTEM_STATE.md
2. CURRENT_ISSUE.md
3. ACTIVE_INVESTIGATION.md
4. NEXT_ACTION.md
5. runtime evidence

Conversation history is support context, not top-level authority.

---

## Practical AI Instruction

When diagnosing this project:

- do not guess root cause
- do not generalize from one log line
- isolate the exact veto stage
- compare local symptoms against architecture intent
- prefer structured evidence over intuition

The system should be treated as a professional trading operations platform, not as a casual trading script.
