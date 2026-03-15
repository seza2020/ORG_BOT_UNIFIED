# CURRENT SYSTEM STATE

Project: ORG_BOT_UNIFIED

## 1. System Identity

Institutional-grade systematic trading engine focused on:
- capital preservation
- risk-first execution
- observability
- audit-ready runtime behavior

## 2. Current Operating Mode

Primary working mode:
PAPER / SHADOW VALIDATION

Current phase:
stabilization + validation before controlled scaling

## 3. Latest Known Baseline

Known validated baseline:
post-dual-PID stabilization baseline

Key known stable areas:
- single-instance enforcement
- path binding
- observability event flow
- meta logging separation
- cooldown hard-stop enforcement

## 4. Current Dominant Problem

System is not reliably generating executable trade plans.

Observed high-level state:
- plan_created = 0 in affected sessions
- pipeline appears to veto before or at plan-builder stage

## 5. Highest-Probability Active Causes

Most likely active causes:
- alpha_mode OFF
- core_context invalidation
- confidence threshold veto
- data freshness / market snapshot quality
- regime / gate-level filtering

## 6. What Has Already Been Investigated

Previously investigated areas include:
- dual PID / multi-process contamination
- environment contamination from legacy paths
- path binding / working directory issues
- meta_events vs meta_engine observability separation
- cooldown enforcement anomalies
- risk-ledger / gate-hook hardening
- shadow / paper runtime evidence collection

## 7. What Should Be Treated As Canonical Truth

Canonical truth priority:
1. CURRENT_SYSTEM_STATE.md
2. CURRENT_ISSUE.md
3. AI_CONTEXT_INDEX.md
4. validated project snapshots
5. conversation snapshots P1..P5

Conversation files are history, not final authority.

## 8. Approved Next Step

Next approved step:
Create CURRENT_ISSUE.md as the formal incident file for the active non-trading problem.

## 9. Last Update Policy

This file must be updated whenever one of the following changes:
- baseline changes
- dominant blocker changes
- approved next step changes
- system operating mode changes

