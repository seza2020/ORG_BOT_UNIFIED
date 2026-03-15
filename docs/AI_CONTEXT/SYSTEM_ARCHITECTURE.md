# SYSTEM ARCHITECTURE

Project: ORG_BOT_UNIFIED

## 1. System Philosophy

This system is designed as an institutional-grade systematic trading engine.

Primary priorities:

capital preservation  
risk-first execution  
observability  
audit-ready runtime behavior  

The system is intentionally designed to reject trades unless strict criteria are met.

---

## 2. Decision Pipeline

High-level decision flow:

Market Data  
↓  
Regime Detection  
↓  
Core Context Evaluation  
↓  
Alpha Engine  
↓  
Candidate Generation  
↓  
Gate System (risk / confidence / regime filters)  
↓  
Plan Builder  
↓  
Execution Layer  

---

## 3. Veto Locations

Trade candidates can be rejected at multiple layers:

Regime Filter  
Core Context Validation  
Alpha Mode Disable  
Confidence Threshold  
Gate Risk Rules  

The most critical veto point in current investigations appears to occur:

BEFORE OR AT PLAN BUILDER

---

## 4. Observability System

Runtime observability is based on structured logs:

meta_events.jsonl  
meta_engine.jsonl  
shadow_plans.jsonl  

These logs allow reconstruction of the full decision path.

---

## 5. Runtime Modes

The system operates in three major modes:

Shadow  
Paper  
Live

Current operational focus:

Paper / Shadow validation.

---

## 6. Key Architectural Components

orchestrator.py  
strategy engines  
gate system  
risk ledger  
observability layer  

---

## 7. Current Architectural Weak Point

Current evidence suggests the decision pipeline vetoes signals before plan creation.

This indicates a likely issue in:

Alpha layer  
Core context  
Gate system  

---

## 8. Canonical Documentation Priority

The following files define the authoritative system description:

AI_CONTEXT_INDEX.md  
CURRENT_SYSTEM_STATE.md  
CURRENT_ISSUE.md  
SYSTEM_ARCHITECTURE.md  

Conversation history is secondary context.

