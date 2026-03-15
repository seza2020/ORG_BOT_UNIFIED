# CODE INDEX

This file maps the main code modules of ORG_BOT_UNIFIED.

## Core Engine

code\tbot\main.py  
Entry point of the trading engine.

code\tbot\orchestrator.py  
Main pipeline controller that coordinates regime, signal, and execution flow.

## Market Layer

code\tbot\market\market_provider.py  
Responsible for:

- retrieving latest trade
- retrieving bars
- computing VWAP
- computing EMA
- generating market snapshot

## Strategy Layer

code\tbot\strategies\*

Contains strategy modules including:

S01 core trend  
S11 alpha gap/ORB  
Other experimental strategies

## Risk Layer

code\tbot\risk\*

Responsible for:

- position sizing
- risk gating
- max risk per trade
- kill switches

## Execution Layer

code\tbot\execution\*

Responsible for:

- order construction
- Alpaca API interaction
- order submission

## Runtime Integration

runtime\paper
runtime\shadow

Contain:

logs  
risk ledgers  
runtime artifacts

## Operational Scripts

ops\scripts

Contains operational utilities including:

- evidence tools
- build scripts
- context bundle generation
