# ORG_BOT_UNIFIED — AI Context Index

This document is the primary entry point for any AI or engineer attempting to understand the ORG_BOT_UNIFIED trading system.

The purpose of this file is to allow a new reader to understand the system in less than one minute without scanning the entire repository or runtime logs.

---

# System Overview

ORG_BOT_UNIFIED is an institutional-style systematic trading engine designed for:

- capital preservation
- deterministic execution
- risk-first architecture
- full observability
- audit-ready runtime diagnostics

Primary runtime mode:

Paper Trading Validation

Architecture style:

Multi-layer decision pipeline with strict gating and observability.

---

# Core Decision Pipeline

The trading system executes the following pipeline:

Market Data  
→ Regime Engine  
→ Core Context  
→ Alpha Mode  
→ Strategy Evaluation  
→ Gate Filtering  
→ Risk Engine  
→ Plan Builder  
→ Execution Layer

Each stage produces structured runtime telemetry.

Primary observability files:

runtime/paper/logs/meta_events.jsonl  
runtime/paper/logs/meta_engine.jsonl  
runtime/paper/logs/strategy_perf_events.jsonl  
runtime/paper/logs/shadow_plans.jsonl  

---

# Current System State

The authoritative system state description is stored in:

CURRENT_SYSTEM_STATE.md

This file describes:

- current runtime condition
- system readiness level
- known limitations
- engineering maturity

---

# Current Blocker

The authoritative description of the active blocker is stored in:

CURRENT_ISSUE.md

This file explains:

- why the system currently does not produce reliable trades
- which layer is responsible
- what evidence supports the diagnosis
- what should be investigated next

---

# Conversation History

Engineering conversation snapshots are stored in:

CONVERSATION/

Files follow this naming format:

P<number>.md

Examples:

CONVERSATION/P1.md  
CONVERSATION/P2.md  
CONVERSATION/P3.md  
CONVERSATION/P4.md  
CONVERSATION/P5.md  
CONVERSATION/P6.md  
...

Rule:

- snapshots are append-only
- older snapshots should not be rewritten unless correcting a factual error
- the highest numbered P-file is the latest historical engineering snapshot

Recommended read order for a new investigation:

1. CURRENT_ISSUE.md
2. CONVERSATION/P5.md or the highest available P-file
3. CURRENT_SYSTEM_STATE.md
4. supporting conversation snapshots as needed


# System Documentation

Core architecture and model definitions are stored in:

SYSTEM_ARCHITECTURE.md  
TRADING_MODEL.md  
RISK_MODEL.md  
OPERATING_MODEL.md  

These files explain how the trading engine is designed to operate.

---

# Project Structure Reference

The full project structure map is documented in:

PROJECT_FILE_MAP.md

This document explains where code, runtime artifacts, and operational scripts are located.

---

# Diagnostic Map

The pipeline veto and suppression map is documented in:

PIPELINE_VETO_MAP.md

This file explains where the system can reject or suppress trade plans before execution.

---

# Key Diagnostic Concept

The system frequently appears to "run but not trade".

This typically occurs when:

alpha_mode = OFF

However, alpha_mode_off may be either:

1. a real regime classification result
2. a downstream symptom of stale or missing market data

Recent investigation suggests the dominant chain may be:

stale core context  
→ alpha_mode_off  
→ suppressed trading

The next investigation step is to verify whether the data freshness path is functioning correctly during live market sessions.

---

# Engineering Operating Rule

The system is now operated under institutional change discipline:

- one active engineering ticket at a time
- one hypothesis per ticket
- one change type per ticket
- evidence-first decision making

No threshold tuning or strategy modifications should occur before fresh runtime evidence is collected.

---

# Where a New Investigation Should Start

If a new engineer or AI needs to continue the investigation:

1. Read CURRENT_ISSUE.md
2. Read CONVERSATION/P5.md
3. Review latest meta_events.jsonl runtime evidence
4. Verify provider → core_context → event contract
5. Confirm whether market data freshness is valid during active session

Only after these checks should decision-layer tuning begin.

