# ORG_BOT_UNIFIED — Repository Map

## Purpose

This file explains the repository structure and clarifies what belongs in GitHub versus what must remain local-only.

---

## Canonical Repository Role

The GitHub repository is the canonical home for:

- controlled source code
- architecture documentation
- AI onboarding documents
- operational scripts that are part of the maintained system

The repository must not become a runtime dump.

---

## High-Level Structure

Expected primary structure:

- code/
- docs/
- ops/
- configs/
- .gitignore

---

## code/

This is the main source-code zone.

Primary canonical subtree:

- code/tbot/

Expected important domains under code/tbot:

- market/
- runtime/
- policy/
- strategies/
- risk/
- analytics/
- core/
- portfolio/
- tools/
- tests/

Guidance:

Only maintained source code belongs here.
Backups, temporary snapshots, runtime state, and logs should not remain here long-term.

---

## docs/

This is the controlled documentation layer.

Important subtrees:

- docs/AI_CONTEXT/
- docs/AI_RUNTIME_CONTEXT/
- docs/AI_INVESTIGATION/
- docs/architecture/

Important anchor files:

- docs/PROJECT_MASTER_INDEX.md
- docs/AI_CONTEXT/AI_STARTUP_PROMPT.md
- docs/architecture/SYSTEM_MAP.md
- docs/architecture/DECISION_TREE.md

Purpose of docs layer:

- make the system understandable
- reduce onboarding friction
- provide architecture truth
- support AI and engineering audits

---

## ops/

This is the operational tooling layer.

Typical content includes:

- scripts
- wrappers
- controlled automation support
- selected diagnostics
- selected migration tools

Important rule:

Canonical operational scripts may live here.
Massive evidence dumps and forensic archives should not.

---

## configs/

This contains controlled configuration artifacts.

Examples:

- profile definitions
- environment-independent config files
- canonical runtime mode settings

Secrets must never be committed.

---

## Local-Only Zones

The following are local-only by default and should not be treated as canonical repo content:

- runtime/
- logs/
- archive/
- archives/
- freeze_backups/
- evidence bundles
- uploaded zip packs
- transfer bundles
- local audit dumps
- temporary backup folders

These belong on the machine, not in GitHub.

---

## AI Context Role in the Repo

The repo now includes an AI-facing documentation layer.

This serves three purposes:

1. help ChatGPT or other AI systems understand the project
2. reduce repeated explanation overhead
3. make architecture and investigation status explicit

Key files:

- AI_CONTEXT_INDEX.md
- AI_STARTUP_PROMPT.md
- CURRENT_SYSTEM_STATE.md
- CURRENT_ISSUE.md
- PROJECT_MASTER_INDEX.md
- SYSTEM_MAP.md
- DECISION_TREE.md

---

## Repo Hygiene Rules

The repository should remain:

- readable
- auditable
- source-oriented
- stable

Avoid committing:

- runtime outputs
- lock files
- generated bundles
- large evidence packs
- archives
- exploratory local dumps
- redundant backup chains

---

## Institutional Usage Model

Recommended model:

- main = canonical branch
- local working branches = development / migration / preservation branches
- GitHub = official source of truth
- local machine = runtime + evidence + experimentation

---

## Practical Rule for Engineers and AI

When reading this repo:

- treat docs as navigation and architecture truth
- treat code as implementation truth
- treat runtime evidence as local operational truth
- do not assume that local machine artifacts belong in GitHub

This repository is intended to function as an institutional-grade trading system codebase, not as a general storage location.
