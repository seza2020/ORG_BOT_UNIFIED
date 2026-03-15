# ORG_BOT_UNIFIED — Decision Tree

## Objective

This document explains how a trading opportunity moves through the decision system
and where it can be vetoed.

---

# Decision Flow

Market Data
    ↓
Regime Check
    ↓
Core Context Check
    ↓
Alpha Mode Check
    ↓
Signal Evaluation
    ↓
Gate Rules
    ↓
Risk Approval
    ↓
Plan Creation
    ↓
Execution

---

# Stage 1 — Market Data

Questions:

- Was latest trade retrieved?
- Were bars retrieved?
- Are timestamps fresh?
- Is source_stale false?

Failure examples:

- trade_age_exceeded
- bar_age_exceeded
- source_stale = true

Decision:

If market data is stale, downstream decisions are not trustworthy.

---

# Stage 2 — Regime Check

Questions:

- Did the system classify regime as TREND or CHOP?
- Is regime compatible with strategy family?

Failure examples:

- regime = CHOP
- weak trend strength

Decision:

If regime rejects opportunity, alpha layer will often stay OFF.

---

# Stage 3 — Core Context Check

Questions:

- Are EMA relationships valid?
- Is VWAP state aligned?
- Is trend_strength sufficient?
- Is bias valid?

Failure examples:

- trend_strength_low
- invalid core context
- collapsed context

Decision:

Weak or degraded context reduces signal eligibility.

---

# Stage 4 — Alpha Mode Check

Questions:

- Is alpha mode ON?
- Did alpha_mode reason allow entry?

Failure examples:

- alpha_mode = OFF
- alpha_off_chop
- alpha_off_trend_weak

Decision:

If alpha mode is OFF, no alpha strategy can proceed.

---

# Stage 5 — Signal Evaluation

Questions:

- Did strategy generate a candidate?
- Is confidence above threshold?
- Is RR above threshold?

Failure examples:

- no_candidate
- state_confidence_low
- rr_too_low

Decision:

No valid candidate means no plan.

---

# Stage 6 — Gate Rules

Questions:

- Did gate accept the signal?
- Are cooldown and max plans respected?

Failure examples:

- cooldown_active
- gate_reject
- max_plans_per_day reached

Decision:

Gate rejection blocks plan creation.

---

# Stage 7 — Risk Approval

Questions:

- Is trade risk within allowed limits?
- Is daily/weekly kill switch inactive?
- Is portfolio risk allowed?

Failure examples:

- max_risk_exceeded
- daily_loss_limit
- weekly_kill_switch
- portfolio governor rejection

Decision:

Risk rejection blocks plan creation.

---

# Stage 8 — Plan Creation

Questions:

- Was a plan actually created?
- Was it written to shadow_plans?

Failure examples:

- plan_created = 0
- shadow write missing

Decision:

If no plan exists, execution never starts.

---

# Stage 9 — Execution

Questions:

- Was order submitted?
- Did broker accept the order?

Failure examples:

- API rejection
- invalid order
- execution disabled

Decision:

Execution failure occurs only after all prior stages passed.

---

# Primary Forensic Rule

Always diagnose in this order:

1. Market Data
2. Regime
3. Core Context
4. Alpha Mode
5. Signal Evaluation
6. Gate
7. Risk
8. Plan Creation
9. Execution

Never start from execution if plan_created = 0.

---

# Current Project Relevance

Known project patterns include:

- alpha_off_chop
- state_confidence_low
- plan_created = 0
- source_stale / age-driven suppression

This file should be read together with:

- SYSTEM_MAP.md
- FORENSIC_PLAYBOOK.md
- CURRENT_ISSUE.md
- LATEST_RUNTIME_SUMMARY.md
