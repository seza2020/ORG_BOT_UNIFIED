# TRADING MODEL

Project: ORG_BOT_UNIFIED

## 1. Trading Philosophy

The system is designed as a systematic trading engine.

Primary priorities:

capital preservation  
controlled risk  
repeatable execution  
strict signal filtering  

The system intentionally prefers **no trade** over **low-quality trade**.

---

## 2. Strategy Families

The system currently includes multiple strategy families.

### Core Strategy

S01 — Core Trend Strategy

Purpose:
capture directional continuation when market structure aligns with higher timeframe trend.

Typical signals include:

trend continuation  
pullback entries  
trendline or moving-average confluence

---

### Alpha Strategies

S11 — Gap Day + ORB Filter

Purpose:

exploit early-session momentum following significant overnight gaps.

Key components:

gap detection  
opening range breakout filtering  
volume confirmation

---

S12 — Trend + VWAP Confluence

Purpose:

capture intraday continuation when price aligns with:

trend structure  
VWAP positioning  
volume confirmation

---

### Additional Structural Elements

AVWAP reclaim logic  
ORB breakout structures  
trend confirmation filters

---

## 3. Signal Pipeline

Signal flow inside the system:

Market Data  
↓  
Regime Detection  
↓  
Core Context  
↓  
Alpha Strategy Evaluation  
↓  
Candidate Generation  
↓  
Gate Filtering  
↓  
Plan Builder  

If all layers approve, a trade plan is created.

---

## 4. Candidate Rejection Points

Trade candidates can be rejected at multiple stages:

regime filter  
core context validation  
alpha mode disable  
confidence threshold  
risk gate rules  

A rejection at any of these stages prevents plan creation.

---

## 5. Current Operational Observation

In current sessions the system frequently produces:

plan_created = 0

This indicates that signals are likely vetoed before or at the plan builder stage.

---

## 6. Relationship With Risk System

All generated plans must pass the gate system.

Gate checks include:

risk allocation  
confidence thresholds  
regime compatibility  
portfolio exposure limits

Only plans passing all gates can reach execution.

---

## 7. Intended Behavior

The system is intentionally conservative.

Valid behavior includes:

low trade frequency  
many rejected signals  
strict filtering

However persistent plan_created = 0 across sessions may indicate excessive filtering.

---

## 8. Documentation Priority

The following files define the trading system:

SYSTEM_ARCHITECTURE.md  
TRADING_MODEL.md  
RISK_MODEL.md  
CURRENT_SYSTEM_STATE.md  

These files should be treated as canonical references.

