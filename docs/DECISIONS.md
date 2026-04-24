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
