# CURRENT ISSUE

Problem Title:
System does not reliably generate executable trade plans.

## 1. Problem Statement

Observed operational issue:
The system reaches evaluation flow but does not consistently produce executable plans for trading sessions.

High-level symptom:
plan_created = 0 in affected sessions.

## 2. Observed Evidence

Current known evidence suggests:
- plan creation is absent or near-zero in affected sessions
- veto appears to occur before plan-builder completion, or at the plan-builder boundary
- non-trading state is not explained by a single confirmed root cause yet

## 3. Current Most Likely Cause Cluster

Highest-probability active cause cluster:
- alpha_mode OFF
- core_context invalidation
- confidence threshold veto
- data freshness / market snapshot weakness
- regime / gate-level filtering

## 4. Rejected or Previously Addressed Areas

The following areas have already been materially investigated or hardened:
- dual PID / duplicate process contamination
- legacy path contamination
- working directory / PYTHONPATH binding
- single-instance enforcement
- observability separation between meta_events and meta_engine
- cooldown hard-stop anomalies
- major logging integrity issues

These areas should not be treated as the dominant blocker unless new evidence re-opens them.

## 5. Still-Open Questions

Open technical questions:
- Is alpha_mode OFF the primary veto source in current runs?
- Is core_context being invalidated too aggressively?
- Is confidence gating blocking otherwise valid candidates?
- Is data freshness degrading signal eligibility?
- Is regime filtering over-restrictive relative to current market conditions?

## 6. Required Evidence For Next Decision

Required next evidence:
- direct evidence chain from signal evaluation to veto reason
- explicit counts of alpha_off / confidence_low / no_candidate / freshness-related outcomes
- evidence linking current runtime state to the exact pre-plan veto point

## 7. Approved Next Investigation Step

Approved next step:
Create a formal evidence-driven veto map that traces the decision path from signal generation to plan rejection.

## 8. Do Not Retest Blindly

Do not blindly retest these without new evidence:
- generic path fixes
- generic process cleanup
- already-resolved duplicate PID theories
- non-specific logging rewrites
- broad environment guesses without fresh proof

## 9. Update Rule

This file must be updated whenever:
- the dominant blocker changes
- a major hypothesis is rejected
- a root cause is confirmed
- the approved next step changes

