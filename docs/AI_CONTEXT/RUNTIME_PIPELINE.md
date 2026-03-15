# RUNTIME PIPELINE

This document describes the logical execution flow of ORG_BOT_UNIFIED.

## Stage 1: Market Data

market_provider retrieves:

- latest trade
- bars
- VWAP
- EMA

Outputs a market snapshot.

## Stage 2: Regime Detection

System evaluates macro state:

- trending
- chop
- volatility regime

## Stage 3: Core Context

Core indicators are evaluated:

- EMA relationships
- VWAP positioning
- volatility filters

## Stage 4: Alpha Layer

Alpha strategies produce candidate signals.

Examples:

S11 gap day + ORB filter.

## Stage 5: Signal Evaluation

Signals are evaluated for:

- confidence
- minimum RR
- context validity

## Stage 6: Risk Gate

Risk system validates:

- max risk per trade
- cooldown
- daily limits
- portfolio exposure

## Stage 7: Plan Creation

Valid signals produce trading plans.

## Stage 8: Execution

Orders are sent to Alpaca.

## Stage 9: Observability

All decisions are logged to:

meta_events.jsonl  
meta_engine.jsonl  
shadow_plans.jsonl
