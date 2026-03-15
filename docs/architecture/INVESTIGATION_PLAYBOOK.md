# ORG_BOT_UNIFIED — Investigation Playbook

## Purpose

This document defines the canonical investigation workflow for diagnosing trading system behavior.

It is designed for:

- engineers
- AI diagnostic systems
- operations teams
- auditors

This playbook ensures investigations follow evidence rather than assumptions.

---

# Golden Rule

Never start investigation with broker or execution explanations.

Always locate the stage in the decision pipeline where the system stopped.

---

# Investigation Workflow

## Step 1 — Confirm Engine Activity

Evidence source:

meta_engine.jsonl

Questions:

- Is the engine producing iteration events?
- Is the run loop active?

Typical signals:

run_loop_enter  
heartbeat  

If no events appear, the engine itself may be stalled.

---

## Step 2 — Inspect Decision Pipeline

Evidence source:

meta_events.jsonl

Key event families:

boot  
regime  
core_context  
alpha_mode  
signal_eval  
strategy_result  

Questions:

- Which stages appear?
- Where do events stop?

This reveals where the pipeline stopped.

---

## Step 3 — Inspect Alpha Mode

Key diagnostic question:

Is alpha mode enabled?

Common event patterns:

alpha_mode_off  
alpha_off_chop  

Interpretation:

The system intentionally disabled alpha strategies.

This is often correct behavior under chop conditions.

---

## Step 4 — Inspect Strategy Results

Evidence source:

strategy_result events

Possible outcomes:

candidate accepted  
candidate rejected  
NONE  

Interpretation:

NONE does not necessarily mean a bug.

It may mean that no strategy candidate passed evaluation rules.

---

## Step 5 — Inspect Gate Decisions

Evidence sources:

gate reports  
runtime_reports  

Typical veto classes:

confidence veto  
RR veto  
cooldown veto  
daily plan cap  
weekly risk kill  
portfolio protection  

If a candidate exists but fails here, the system intentionally blocked the trade.

---

## Step 6 — Inspect Plan Creation

Evidence source:

shadow_plans.jsonl

Critical metric:

plan_created

Interpretation:

plan_created = 0

means:

The pipeline never authorized a trade plan.

This is usually caused by upstream veto stages.

---

## Step 7 — Inspect Execution Path

Only perform this step if a plan exists.

Evidence sources:

shadow_plans.jsonl  
execution logs  
broker responses  

Execution failure occurs only if:

1. a plan exists
2. execution routing fails afterward

If no plan exists, execution is not the problem.

---

# Typical Diagnostic Scenarios

## Scenario 1 — Engine Not Running

Symptoms:

meta_engine.jsonl inactive

Cause:

engine crash  
scheduler failure  
runtime stall  

---

## Scenario 2 — Alpha Mode Disabled

Symptoms:

alpha_mode_off  
alpha_off_chop  

Cause:

market chop classification  
weak trend regime  

Interpretation:

system intentionally suppresses trading.

---

## Scenario 3 — No Strategy Candidate

Symptoms:

strategy_result NONE  

Cause:

market conditions do not produce valid signals.

---

## Scenario 4 — Gate Rejection

Symptoms:

candidate exists  
gate rejection occurs  

Cause:

risk protection or confidence filtering.

---

## Scenario 5 — Plan Exists But Execution Failed

Symptoms:

shadow_plans.jsonl contains plan  

but

execution logs show failure.

Cause:

execution layer issue.

---

# Investigation Order Summary

Always follow this order:

1 engine activity  
2 decision pipeline  
3 alpha mode  
4 strategy evaluation  
5 gate decisions  
6 plan creation  
7 execution routing  

Skipping steps leads to incorrect conclusions.

---

# Institutional Principle

ORG_BOT_UNIFIED is designed to trade only when conditions are acceptable.

A no-trade outcome is not automatically a failure.

Often it means the system correctly rejected a trade.

Investigations must distinguish between:

intentional veto  
unintended failure.

---

# Relationship to Other Architecture Documents

This playbook should be used together with:

SYSTEM_MAP.md  
TRADING_ENGINE_FLOW.md  
RUNTIME_EVIDENCE_MAP.md  
DECISION_TREE.md  

Together these documents describe:

system architecture  
decision pipeline  
runtime evidence  
investigation methodology.
