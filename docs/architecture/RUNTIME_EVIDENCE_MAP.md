# ORG_BOT_UNIFIED — Runtime Evidence Map

## Purpose

This document explains how runtime evidence is produced and how it should be used to diagnose trading system behavior.

The goal is to make the system observable, auditable, and diagnosable.

This file should be used when answering questions such as:

- Why did the system not trade?
- Why was a candidate rejected?
- Did the pipeline veto the trade intentionally?
- Did execution fail after a plan was created?

---

# Evidence Philosophy

ORG_BOT_UNIFIED is designed as an observability-heavy system.

Behavior should not be diagnosed through intuition or narrative explanations.

Instead, diagnosis should be based on runtime evidence emitted by the system.

Key rule:

Logs are evidence.
Interpretations must follow the logs.

---

# Evidence Sources

The runtime produces several categories of evidence.

Each serves a different diagnostic role.

---

# 1 — meta_events.jsonl

Location example:

runtime/paper/logs/meta_events.jsonl

Purpose:

Event stream describing the decision pipeline.

Typical event families include:

- boot
- regime
- core_context
- alpha_mode
- signal_eval
- strategy_result
- heartbeat
- shutdown

These events allow reconstruction of the decision pipeline.

Important diagnostic value:

They show where the pipeline stopped.

Example interpretation:

If strategy_result never appears, the veto occurred upstream.

---

# 2 — meta_engine.jsonl

Location example:

runtime/paper/logs/meta_engine.jsonl

Purpose:

Engine telemetry and iteration reporting.

Typical fields include:

- iteration
- run_loop_enter
- runtime state markers
- loop cadence

Diagnostic value:

Shows that the engine is alive and iterating.

If meta_engine events stop appearing, the engine itself may be stalled.

---

# 3 — shadow_plans.jsonl

Location example:

runtime/paper/logs/shadow_plans.jsonl

Purpose:

Records plans that were authorized by the pipeline.

Critical meaning:

A plan exists only after:

candidate
→ gate passed
→ risk accepted
→ plan constructed

If this file remains empty:

plan_created = 0

Interpretation:

The pipeline never authorized a trade plan.

This does NOT automatically mean execution failed.

It usually means a veto occurred earlier.

---

# 4 — runtime_reports

Location example:

runtime_reports/

Examples:

latest_runtime_summary.json
latest_strategy_counts.json
latest_gate_rejections.json
latest_validation_snapshot.json

Purpose:

Human-readable summaries derived from runtime activity.

Diagnostic value:

Quick overview of system health and activity.

These summaries should always be cross-checked with raw logs.

---

# 5 — Risk Ledger

Examples:

risk_ledger_daily.json
risk_ledger_weekly.json

Purpose:

Tracks risk consumption and protection mechanisms.

Typical fields include:

- daily risk used
- weekly risk used
- kill switch activation
- budget remaining

If risk budget is exhausted, gate logic may veto new plans.

---

# Understanding plan_created = 0

One of the most common diagnostics in this project is:

plan_created = 0

Institutional interpretation:

The pipeline did not authorize any trade plans.

Possible causes include:

- alpha mode disabled
- chop classification
- no strategy candidate
- candidate rejected by gate
- cooldown active
- daily plan cap reached
- risk budget exhausted

Incorrect interpretation:

Assuming broker or execution failure without verifying pipeline stages.

---

# Correct Diagnostic Order

When investigating missing trades, follow this order:

1. Verify engine iteration using meta_engine.jsonl
2. Inspect decision pipeline in meta_events.jsonl
3. Check alpha_mode state
4. Inspect strategy_result events
5. Inspect gate rejection reports
6. Confirm whether shadow_plans.jsonl contains plans
7. Only then investigate execution routing

Skipping steps leads to incorrect conclusions.

---

# Execution Path Failures

An execution-path problem occurs only if:

1. a plan exists
2. the plan is logged
3. execution fails afterward

Evidence sources for this case include:

- shadow_plans.jsonl
- execution logs
- broker response logs

If no plan exists, the issue is not execution.

---

# Observability Principle

The system is intentionally designed to produce more evidence than a minimal trading engine.

Benefits:

- faster root cause analysis
- easier AI reasoning
- safer system evolution
- clearer audit trails

Observability is a core design feature, not an afterthought.

---

# Canonical Investigation Rule

Never start investigation with broker or execution explanations.

Always locate the pipeline stage where the system stopped.

Only after the correct stage is identified should deeper debugging begin.

This rule prevents misdiagnosis.

---

# Relationship to Other Architecture Documents

This file should be read together with:

SYSTEM_MAP.md  
DECISION_TREE.md  
TRADING_ENGINE_FLOW.md  
AI_SYSTEM_CONTEXT.md  

Together these documents describe:

- system structure
- decision pipeline
- runtime evidence
- investigation methodology

They form the core architectural documentation of ORG_BOT_UNIFIED.
