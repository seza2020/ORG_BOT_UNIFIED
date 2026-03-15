# DATA FLOW MAP

High-level data movement inside ORG_BOT_UNIFIED.

Market Data
    ↓
market_provider
    ↓
Market Snapshot
    ↓
Regime Detection
    ↓
Core Context
    ↓
Alpha Strategies
    ↓
Signal Evaluation
    ↓
Risk Gate
    ↓
Trading Plan
    ↓
Execution Engine
    ↓
Alpaca Broker
    ↓
Logs / Evidence

Logs include:

meta_events.jsonl  
meta_engine.jsonl  
shadow_plans.jsonl  
risk_ledger.json
