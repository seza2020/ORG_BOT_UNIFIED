# OPERATING MODEL

Project: ORG_BOT_UNIFIED

## 1. System Operating Philosophy

The system follows a controlled institutional operating model.

Primary principles:

risk-first deployment  
evidence-driven validation  
strict promotion rules  
fast rollback capability  

The system must always prioritize capital protection over trade frequency.

---

## 2. System Lifecycle

The system operates across three runtime stages.

Stage 1

Shadow Mode

Purpose:

validate signals without real execution.

Outputs:

shadow_plans.jsonl  
meta_events.jsonl  
meta_engine.jsonl

---

Stage 2

Paper Mode

Purpose:

validate trade execution logic using simulated capital.

Outputs:

paper execution logs  
risk ledger updates  
plan execution records

---

Stage 3

Controlled Live Mode

Purpose:

deploy validated strategies to real capital under strict risk limits.

---

## 3. Promotion Rules

A strategy or system version may be promoted only if:

minimum trade sample size achieved  
risk metrics remain within acceptable limits  
observability logs confirm stability  
no major runtime failures occur

Typical requirement:

minimum 30 validated trades.

---

## 4. Deployment Rules

New code or configuration changes must follow this order:

development environment  
shadow validation  
paper validation  
controlled promotion

Direct deployment to live trading is not allowed.

---

## 5. Rollback Policy

If unexpected behavior occurs the system must revert to a previously validated baseline.

Rollback triggers include:

runtime instability  
unexpected drawdown  
observability failure  
data integrity issues

---

## 6. Evidence and Observability

Operational decisions must rely on structured evidence.

Primary observability sources:

meta_events.jsonl  
meta_engine.jsonl  
shadow_plans.jsonl  
risk ledger records  

These logs allow reconstruction of system decisions.

---

## 7. Governance Rules

System modifications must follow controlled change procedures.

Recommended governance:

define change objective  
capture baseline snapshot  
apply controlled modification  
collect evidence  
evaluate impact  

Uncontrolled system changes are discouraged.

---

## 8. Relationship With AI Analysis

The AI analysis layer relies on canonical documentation.

Key files include:

AI_CONTEXT_INDEX.md  
CURRENT_SYSTEM_STATE.md  
CURRENT_ISSUE.md  
SYSTEM_ARCHITECTURE.md  
TRADING_MODEL.md  
RISK_MODEL.md  
OPERATING_MODEL.md  

These files allow analysts or AI models to understand system structure and current state quickly.

---

## 9. Current Operational Focus

Current operational focus:

stabilization of paper / shadow pipeline  
diagnosis of plan generation issues  
improvement of signal validation flow

