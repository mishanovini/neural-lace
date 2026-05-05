# Decisions Index

Permanent record of Tier 2+ architectural and product decisions for the Neural
Lace harness. Every entry below points at a standalone record in
`docs/decisions/NNN-*.md` with full Context, Decision, Alternatives, and
Consequences. Adding a new record requires updating this index in the same
commit (enforced by `adapters/claude-code/hooks/decisions-index-gate.sh`).

| # | Title | Date | Status |
|---|-------|------|--------|
| 001 | [Fresh orphan-commit for public release](decisions/001-public-release-strategy.md) | 2026-04-18 | Active |
| 002 | [Attribution-only anonymization policy](decisions/002-attribution-only-anonymization.md) | 2026-04-18 | Active |
| 003 | [`review-before-deploy` as automation-mode default](decisions/003-review-before-deploy-default.md) | 2026-04-18 | Active |
| 004 | [Capture-codify mechanism field shape](decisions/004-capture-codify-mechanism-field-shape.md) | 2026-04-23 | Implemented |
| 005 | [40-character rationale threshold for "no mechanism" answer form](decisions/005-capture-codify-rationale-threshold.md) | 2026-04-23 | Implemented |
| 006 | [CI workflow + local pre-push hook (both layers)](decisions/006-capture-codify-ci-and-local-hook.md) | 2026-04-23 | Implemented |
| 007 | [Per-repo opt-in for the pre-push PR template hook](decisions/007-capture-codify-per-repo-hook-optin.md) | 2026-04-23 | Implemented |
| 008 | [Failure-modes file as a stub created by capture-codify plan](decisions/008-capture-codify-failure-modes-stub.md) | 2026-04-23 | Implemented |
| 009 | [Do not change repo squash-merge commit-message setting](decisions/009-capture-codify-squash-merge-body.md) | 2026-04-23 | Implemented |
| 010 | [Validator library lives at `.github/scripts/` (not `adapters/claude-code/`)](decisions/010-capture-codify-validator-library-location.md) | 2026-04-23 | Implemented |
| 011 | [Claude `--remote` harness portability — Approach A (commit harness into project) + Routines + DevContainers, Dispatch out of scope](decisions/011-claude-remote-harness-approach.md) | 2026-04-23 | Implemented |
| 012 | [Agent Teams integration — six design decisions](decisions/012-agent-teams-integration.md) | 2026-04-27 | Active |
| 013 | [Default git push policy — auto-push (safe methods); customer-tier branching for real-user projects](decisions/013-default-push-policy.md) | 2026-05-03 | Active |
| 014 | [Calibration mimicry design — RL-shaped via prompt conditioning (G-1 through G-4)](decisions/014-calibration-mimicry-design.md) | 2026-05-03 | Active |
| 015 | [PRD-validity gate (C1): single `docs/prd.md` per project + 7 required sections + harness-development carve-out](decisions/015-prd-validity-gate-c1.md) | 2026-05-04 | Active |
| 016 | [Spec-freeze gate (C2): `frozen: true|false` semantics, freeze-by-commit-SHA, freeze-thaw protocol](decisions/016-spec-freeze-gate-c2.md) | 2026-05-04 | Active |
| 017 | [Plan-header schema locked: 5 required fields, no defaults, gated on `Status: ACTIVE`](decisions/017-plan-header-schema-locked.md) | 2026-05-04 | Active |
| 018 | [Spec-section divergence from SCRATCHPAD: Build Doctrine §6 chosen as authoritative; `## Provides`/`## Consumes`/`## Dependencies` deferred](decisions/018-spec-section-divergence-from-scratchpad.md) | 2026-05-04 | Open |
| 019 | [Findings-ledger format (C9): 6-field schema, single `docs/findings.md` per project, dispositioning lifecycle](decisions/019-findings-ledger-format.md) | 2026-05-04 | Active |
| 020 | [Comprehension-gate semantics (C15): rung-2 cutoff, four articulation fields, FAIL/INCOMPLETE blocks task-verifier](decisions/020-comprehension-gate-semantics.md) | 2026-05-04 | Active |
| 021 | [DRIFT-02 resolution: SessionStart account-switching hook is config-driven](decisions/021-drift-02-account-switch-config-driven.md) | 2026-05-04 | Active |
| 022 | [`pipeline-agents.md` deleted from global rules](decisions/022-pipeline-agents-md-deletion.md) | 2026-05-04 | Implemented |
| 023 | [Definition-on-first-use enforcement: acronym regex + stopword allowlist + scope-prefix + glossary/in-diff semantics](decisions/023-definition-on-first-use-enforcement.md) | 2026-05-04 | Active |
