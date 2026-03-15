# ORG_BOT_UNIFIED — Trading Engine Flow

## Purpose

This document explains the operational flow of the trading engine.

It is intended for:

- AI systems
- engineers
- auditors
- trading operations review

It should be read together with:

- SYSTEM_MAP.md
- DECISION_TREE.md
- AI_SYSTEM_CONTEXT.md
- CURRENT_SYSTEM_STATE.md
- CURRENT_ISSUE.md

---

## High-Level Flow

The trading engine should be understood as a gated decision pipeline rather than a simple signal generator.

The canonical high-level flow is:

Market Data
→ Regime Classification
→ Core Context Construction
→ Alpha Mode Determination
→ Strategy Evaluation
→ Gate / Risk Screening
→ Plan Creation
→ Execution / Shadow / Paper handling
→ Runtime Logging / Evidence

Important rule:

A missing trade is not automatically an execution failure.
A missing trade may simply mean the pipeline vetoed the trade before plan creation.

---

## Stage 1 — Market Data

The engine first obtains market state from its data provider.

This typically includes:

- last price
- VWAP
- EMA fast
- EMA slow
- bar timing
- source freshness
- source timestamps

Key risks at this layer:

- stale provider state
- age calculation defects
- timestamp mapping defects
- fallback-derived values
- cache contamination

If this layer is wrong, downstream regime and context may also be wrong.

---

## Stage 2 — Regime Classification

Regime determines broad market character.

Examples of regime interpretations:

- trend-supportive
- weak trend
- neutral
- chop-like
- blocked / risk-hostile

Regime is not the final trade decision.

Its role is to control whether the engine should even consider trading under the current environment.

Typical veto class here:

- regime veto
- chop veto
- insufficient trend regime

---

## Stage 3 — Core Context Construction

Core Context builds the structured state used by downstream logic.

Typical fields include:

- trend_strength
- bias
- vwap_state
- ema separation
- current price relation
- freshness fields
- bar age
- trade age

This stage is critical because downstream alpha and strategy logic depend on it.

If Core Context is malformed, stale, partial, or inconsistent, the system may correctly veto without ever creating a plan.

Typical veto class here:

- invalid context
- stale context
- low strength context
- incomplete context

---

## Stage 4 — Alpha Mode Determination

Alpha Mode decides whether alpha strategies are allowed to operate.

It is not the same thing as strategy fire.

Alpha Mode is a gating layer.

Typical reasons for alpha-off:

- chop classification
- weak trend
- stale source state
- confidence protection
- policy gating
- mode threshold not met

A common pattern in project diagnostics has been:

alpha_off_chop

This means the system is intentionally suppressing alpha participation under chop-like conditions.

---

## Stage 5 — Strategy Evaluation

Only after regime and context are in acceptable state does the system evaluate strategies.

Strategy evaluation may include:

- core strategies
- alpha strategies
- symbol-specific filters
- signal validity rules
- internal admission tests

At this stage a strategy may still return:

- no candidate
- weak candidate
- blocked candidate
- accepted candidate

Important interpretation:

A strategy producing NONE is not necessarily a bug.
It may be correct behavior under the current pipeline conditions.

---

## Stage 6 — Gate / Risk Screening

This is one of the most important institutional layers.

A candidate signal is not yet a trade.

It must pass gate and risk filters such as:

- minimum confidence
- minimum RR
- daily risk budget
- weekly loss protection
- cooldown
- max plans per day
- kill switches
- portfolio protection
- execution eligibility

Typical veto families here:

- confidence veto
- RR veto
- cooldown veto
- daily cap veto
- weekly kill veto
- portfolio kill veto
- max-plans veto

This stage exists to protect capital and system integrity.

---

## Stage 7 — Plan Creation

Only after all upstream logic passes does the engine create a plan.

This is the important transition point:

candidate
→ plan

If a plan is not created, execution should not happen.

This is why the metric below matters so much:

plan_created = 0

Institutional interpretation of plan_created = 0:

Do not start with execution debugging.
First identify the upstream veto stage.

---

## Stage 8 — Execution / Shadow / Paper Handling

After a plan exists, the engine may:

- log it in shadow mode
- prepare it for paper flow
- route it to controlled execution logic
- attach downstream observability

Execution handling must be separated from upstream diagnosis.

If no plan exists, execution is not the primary problem.

If a plan exists but nothing is logged or routed, then execution-path diagnosis becomes relevant.

---

## Stage 9 — Runtime Logging and Evidence

The runtime emits evidence into logs and structured summaries.

Important evidence sources include:

- meta_events.jsonl
- meta_engine.jsonl
- shadow_plans.jsonl
- risk ledger outputs
- AI_RUNTIME_CONTEXT audit artifacts

These logs should be treated as operational evidence.

Narrative summaries should be checked against these sources.

---

## Canonical Diagnostic Rule

When investigating missing trades, the correct order is:

1. confirm whether market data was valid
2. confirm regime state
3. confirm core context quality
4. confirm alpha mode state
5. confirm strategy output
6. confirm gate / risk result
7. confirm whether a plan was created
8. only then inspect execution path

This order prevents false diagnosis.

---

## Meaning of plan_created = 0

This project has repeatedly encountered situations where:

plan_created = 0

This should be interpreted as:

the system did not authorize a trade plan under current conditions

Possible causes include:

- alpha-off due to chop
- low confidence
- no valid candidate
- stale context
- risk gating
- cooldown
- daily budget block
- policy veto

Incorrect interpretation:

- assuming broker failure first
- assuming execution bug first
- assuming engine crash first

Correct interpretation:

- locate the exact veto stage first

---

## Veto Taxonomy

A simplified veto taxonomy:

### Market / Provider veto
Input data is stale, malformed, delayed, or untrusted.

### Regime veto
Environment is not suitable.

### Core Context veto
Context quality is incomplete or weak.

### Alpha Mode veto
Alpha participation is intentionally disabled.

### Strategy veto
No valid candidate survives evaluation.

### Gate / Risk veto
Candidate exists but is intentionally blocked.

### Execution-path failure
A valid plan exists but downstream handling fails.

Only the last case is an execution-path issue.

---

## Practical Reading Rule for AI and Engineers

When reading logs or investigating behavior:

- do not jump directly to broker or execution explanations
- do not assume every no-trade event is a defect
- first identify where the pipeline stopped
- distinguish between intended veto and unintended failure
- prefer structured evidence to intuition

---

## Institutional Interpretation

ORG_BOT_UNIFIED should be treated as a risk-governed trading decision system.

Its job is not to force trades.
Its job is to authorize only acceptable trades.

Therefore, many no-trade outcomes are healthy if they are correctly caused and correctly observable.

The real question is not:

Why did the system not trade?

The real question is:

At which stage did the system intentionally or unintentionally stop the trading pipeline?
