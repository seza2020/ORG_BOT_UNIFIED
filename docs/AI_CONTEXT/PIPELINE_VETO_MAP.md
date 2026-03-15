# PIPELINE VETO MAP

Project: ORG_BOT_UNIFIED

Purpose:

Identify where signals are rejected before plan creation.

Current investigation focuses on:

plan_created = 0

---

# 1. Decision Pipeline

Market Data  
↓  
Regime Detection  
↓  
Core Context Validation  
↓  
Alpha Strategy Evaluation  
↓  
Candidate Generation  
↓  
Gate System  
↓  
Plan Builder  

Trade plans are created only if all stages approve.

---

# 2. Regime Filter

Purpose:

Determine if market conditions allow strategy activation.

Possible veto reasons:

regime_inactive  
trend_strength_low  
out_of_session  

Evidence source:

meta_events.jsonl

---

# 3. Core Context

Purpose:

Validate overall market structure before enabling strategies.

Possible veto reasons:

core_context_invalid  
insufficient_signal_quality  
state_confidence_low  

Evidence source:

meta_events.jsonl

---

# 4. Alpha Engine

Purpose:

Generate candidate signals.

Possible veto reasons:

alpha_mode OFF  
no_candidate  

Evidence source:

meta_events.jsonl

---

# 5. Candidate Generation

Purpose:

Produce trade candidate objects.

Possible veto reasons:

strategy_conditions_not_met  

Evidence source:

meta_events.jsonl

---

# 6. Gate System

Purpose:

Validate trade candidate quality.

Possible veto reasons:

confidence_threshold  
risk_limits  
regime_incompatibility  
cooldown_active  

Evidence source:

meta_events.jsonl

---

# 7. Plan Builder

Purpose:

Convert valid candidate into executable trade plan.

Possible veto reasons:

plan_builder_error  
invalid_trade_parameters  

Evidence source:

shadow_plans.jsonl

---

# 8. Observability Sources

Key diagnostic logs:

meta_events.jsonl  
meta_engine.jsonl  
shadow_plans.jsonl  

These logs allow reconstruction of the full decision path.

---

# 9. Current Hypothesis

Current dominant hypothesis:

Signals are vetoed before or at the Plan Builder stage.

Most likely causes include:

alpha_mode OFF  
core_context invalidation  
confidence threshold veto  

Further evidence is required.

---

# 10. Investigation Goal

The goal of this investigation is to identify the exact stage where:

plan_created becomes zero.

Once the stage is identified, targeted debugging can begin.

