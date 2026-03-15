# FORENSIC PLAYBOOK

This document describes the standard forensic process for diagnosing
why ORG_BOT_UNIFIED did not produce trades.

--------------------------------------------------

STAGE 1 — MARKET DATA

Check market_provider.

Verify:

- latest trade retrieval
- bars retrieval
- VWAP
- EMA

Primary file:

code\tbot\market\market_provider.py

Evidence:

meta_events.jsonl

Typical failures:

- stale market data
- HTTP errors
- timestamp age exceeded

--------------------------------------------------

STAGE 2 — REGIME FILTER

Check whether system entered a valid regime.

Evidence:

meta_events.jsonl

Look for events:

regime_eval  
regime_result

Typical failures:

- regime = chop
- volatility filter blocked signals

--------------------------------------------------

STAGE 3 — CORE CONTEXT

Core indicators must align.

Examples:

- EMA fast vs slow
- VWAP position
- trend strength

Evidence:

meta_events.jsonl

Typical failures:

core_context_invalid  
trend_strength_low

--------------------------------------------------

STAGE 4 — ALPHA LAYER

Strategies attempt to produce candidate signals.

Examples:

S11 gap + ORB

Evidence:

meta_events.jsonl

Look for:

alpha_mode  
signal_eval

Typical failures:

alpha_mode OFF  
no_candidate

--------------------------------------------------

STAGE 5 — SIGNAL EVALUATION

Signals are validated.

Checks include:

- minimum RR
- confidence threshold

Typical failures:

state_confidence_low  
rr_too_low

--------------------------------------------------

STAGE 6 — RISK GATE

Risk system may block plans.

Evidence:

meta_events.jsonl  
risk_ledger.json

Typical failures:

max_risk_exceeded  
cooldown_active  
daily_loss_limit

--------------------------------------------------

STAGE 7 — PLAN CREATION

If signal passes risk gate, a plan should be created.

Evidence:

shadow_plans.jsonl

Typical failure:

plan_created = 0

--------------------------------------------------

STAGE 8 — EXECUTION

If plan exists, order should be sent.

Evidence:

execution logs  
Alpaca API responses

Typical failures:

API rejection  
order validation error

--------------------------------------------------

FORENSIC RULE

Always debug pipeline in this order:

Market Data  
→ Regime  
→ Core Context  
→ Alpha  
→ Signal Evaluation  
→ Risk Gate  
→ Plan Creation  
→ Execution

Never skip stages.

--------------------------------------------------

PRIMARY EVIDENCE FILES

meta_events.jsonl  
meta_engine.jsonl  
shadow_plans.jsonl  
risk_ledger.json
