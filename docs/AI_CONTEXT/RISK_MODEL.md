# RISK MODEL

Project: ORG_BOT_UNIFIED

## 1. Risk Philosophy

The system follows a strict risk-first architecture.

Primary objectives:

capital preservation  
controlled exposure  
systematic position sizing  
portfolio protection  

The system prefers **no trade** over **excessive risk exposure**.

---

## 2. Position Risk Limits

Maximum risk per plan:

gate_max_risk_usd = 500

This represents the maximum dollar loss allowed for a single plan.

Position size must be calculated so that stop-loss exposure does not exceed this value.

---

## 3. Trade Quality Filters

Trade plans must satisfy minimum quality requirements.

Minimum risk-reward:

min_rr = 1.5

Minimum confidence:

min_conf = 0.55

Plans failing these thresholds are rejected.

---

## 4. Trade Frequency Limits

The system enforces limits on the number of plans generated per day.

Maximum plans per day:

max_plans_per_day = 15

This prevents excessive trading during volatile sessions.

---

## 5. Cooldown Enforcement

A cooldown period prevents rapid consecutive trade generation.

cooldown_sec = 300

This ensures signals are spaced in time.

---

## 6. Portfolio Kill Switches

The system includes global kill switches.

Daily alpha kill:

daily_alpha_kill_r = -2

Weekly kill switch:

weekly_kill_r = -5

If these limits are breached, trading activity should stop.

---

## 7. Risk Ledger

The system includes a developing component:

Atomic Risk Ledger

This module is intended to track:

daily exposure  
strategy exposure  
portfolio risk accumulation  

The goal is to ensure restart-safe risk accounting.

---

## 8. Risk Gate Position In Pipeline

Risk validation occurs in the Gate system.

Decision pipeline:

Market Data  
↓  
Regime  
↓  
Core Context  
↓  
Alpha Strategy  
↓  
Candidate Generation  
↓  
Gate (risk / confidence / regime checks)  
↓  
Plan Builder  

Any failure inside the Gate stage vetoes plan creation.

---

## 9. Current Risk-Related Observations

Given the current system state:

plan_created = 0

One possible explanation is that risk gates may be rejecting candidates before plan creation.

However this has not yet been confirmed as the dominant cause.

---

## 10. Canonical Documentation Priority

The following files define system governance:

SYSTEM_ARCHITECTURE.md  
TRADING_MODEL.md  
RISK_MODEL.md  
CURRENT_SYSTEM_STATE.md  
CURRENT_ISSUE.md  

These files should be treated as authoritative.

