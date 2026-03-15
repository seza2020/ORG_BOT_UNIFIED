# ORG_BOT_UNIFIED — System Map

## System Objective

Systematic trading engine designed for:

- capital preservation
- systematic execution
- risk-first architecture
- observability
- audit-ready runtime

---

# Trading Pipeline

Market Data
    ↓
Market Provider
    ↓
Regime Engine
    ↓
Core Context Engine
    ↓
Alpha Engine
    ↓
Execution Gate
    ↓
Risk Engine
    ↓
Execution Plan
    ↓
Runtime Logs

---

# Engine Components

## Market Layer
Responsible for fetching market data.

Modules:

- market_provider.py
- replay_provider.py

---

## Regime Layer

Detects market environment.

Modules:

- regime_engine.py
- regime overlay

---

## Core Context Layer

Builds internal trading context.

Modules:

- core_context.py
- core_trend.py

---

## Alpha Layer

Strategy signal generation.

Modules:

- s01_core
- s11_alpha
- s12_alpha

---

## Gate Layer

Filters trades using rules:

- risk limits
- cooldown
- confidence
- RR validation

Modules:

- policy/
- enforce.py

---

## Risk Engine

Portfolio and strategy risk.

Modules:

- atomic_risk_ledger
- portfolio_governor
- correlation_risk_engine

---

## Runtime Engine

Responsible for orchestration.

Modules:

- orchestrator.py
- runtime engine
- session manager

---

# Observability

Runtime logs:

- meta_events.jsonl
- meta_engine.jsonl
- shadow_plans.jsonl
- risk_ledger.json

---

# Decision Veto Points

Trades can be rejected at:

- regime filter
- core context
- alpha filter
- gate rules
- risk engine

---

# Execution Modes

Supported modes:

- shadow
- paper
- live

---

# System Philosophy

This system follows:

Risk First  
Signal Second  
Execution Third
