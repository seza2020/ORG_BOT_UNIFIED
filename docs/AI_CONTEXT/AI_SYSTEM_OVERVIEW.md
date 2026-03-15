# ORG_BOT_UNIFIED — AI System Overview

## Purpose

This document is the canonical entry point for AI systems and engineers.

It explains how to understand the ORG_BOT_UNIFIED trading system.

AI systems should start with this document before reading the rest of the repository.

---

# System Identity

ORG_BOT_UNIFIED is an institutional-grade algorithmic trading engine.

Core design principles:

- capital preservation
- risk-first architecture
- observability-heavy runtime
- systematic decision pipeline
- audit-ready diagnostics

The system is designed to authorize trades only when conditions meet strict criteria.

A no-trade outcome is often correct behavior.

---

# Decision Pipeline

The trading engine follows a gated pipeline.

Market Data  
→ Regime Classification  
→ Core Context Construction  
→ Alpha Mode Determination  
→ Strategy Evaluation  
→ Risk / Gate Screening  
→ Plan Creation  
→ Execution Handling  

A trade occurs only if a candidate survives every stage.

---

# Core Principle

ORG_BOT_UNIFIED is not a signal generator.

It is a risk-governed decision system.

The engine's job is to reject unacceptable trades.

Therefore many cycles may produce no trade.

This is expected behavior.

---

# Repository Structure

Important repository layers:

## Source Code

code/

Contains the trading engine.

Key modules:

tbot/  
strategies/  
market/  
runtime/  
policy/  

---

## Architecture Documentation

docs/architecture/

These documents explain how the system works.

Key files:

SYSTEM_MAP.md  
REPO_MAP.md  
DECISION_TREE.md  
TRADING_ENGINE_FLOW.md  
RUNTIME_EVIDENCE_MAP.md  
INVESTIGATION_PLAYBOOK.md  

These documents together define the system architecture.

---

## AI Context Layer

docs/AI_CONTEXT/

These documents help AI systems understand the repository.

Important files include:

AI_SYSTEM_CONTEXT.md  
AI_STARTUP_PROMPT.md  
AI_CONTEXT_INDEX.md  

---

# Runtime Evidence

The system produces structured logs that serve as diagnostic evidence.

Important evidence sources:

meta_events.jsonl  
meta_engine.jsonl  
shadow_plans.jsonl  
runtime_reports  

These logs allow reconstruction of the decision pipeline.

---

# Diagnosing Missing Trades

When the system does not trade, follow this order:

1 confirm engine activity  
2 inspect decision pipeline  
3 inspect alpha mode  
4 inspect strategy evaluation  
5 inspect gate decisions  
6 inspect plan creation  
7 inspect execution path  

This investigation order is defined in:

INVESTIGATION_PLAYBOOK.md

---

# Meaning of plan_created = 0

plan_created = 0 means the pipeline never authorized a trade plan.

Typical causes include:

alpha mode disabled  
no strategy candidate  
gate rejection  
risk protection  
cooldown rules  

This does not automatically indicate an execution failure.

---

# Observability Philosophy

ORG_BOT_UNIFIED is intentionally observability-heavy.

The system produces extensive runtime evidence so behavior can be explained through logs.

Diagnosis should always be evidence-driven.

---

# Reading Order for AI Systems

AI systems should read documents in this order:

1 PROJECT_MASTER_INDEX.md  
2 AI_SYSTEM_OVERVIEW.md  
3 SYSTEM_MAP.md  
4 TRADING_ENGINE_FLOW.md  
5 RUNTIME_EVIDENCE_MAP.md  
6 INVESTIGATION_PLAYBOOK.md  

Following this order allows rapid understanding of the system.

---

# Summary

ORG_BOT_UNIFIED is designed as a professional systematic trading engine.

Its behavior should be understood through:

architecture  
decision pipeline  
runtime evidence  
structured investigation

AI systems should treat these documents as the canonical explanation of the project.
