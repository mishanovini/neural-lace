# Decision 005: 40-character rationale threshold for "no mechanism" answer form

**Date:** 2026-04-23
**Status:** Implemented
**Tier:** 2
**Stakeholders:** Misha (maintainer)

## Context

The "c) No mechanism — accepted residual risk" answer form is the escape hatch that keeps the capture-codify discipline from blocking legitimate exception cases (rollbacks, single-character prose typos, hotfixes where the mechanism analysis lives on the PR being rolled back, etc.). Without a substantive-length floor, the escape hatch becomes a vaporware bypass: writers type "N/A" or "none" and the validator passes. A floor that's too high produces false rejections on genuine one-sentence rationales.

## Decision

Require ≥40 characters of non-whitespace content after the `### c)` sub-heading when the (c) answer form is selected. Threshold lives in a single constant `PR_TEMPLATE_RATIONALE_MIN_CHARS` in `.github/scripts/validate-pr-template.sh`, tunable later if the false-positive rate proves wrong.

## Alternatives Considered

- **80 characters** — rejected because tight legitimate one-sentence rationales fall in the 40-70 range. Example: "Single-char prose typo; no rule catches that cheaply." is 51 chars, meaningful, but would fail an 80-char gate. Forcing writers to pad legitimate answers produces noise without quality gains.
- **20 characters** — rejected because terse brush-offs slip through. Examples: "N/A — see prior PR" is 18 chars; "Rollback only" is 13 chars; "Doc fix only" is 12 chars. All pass at 20.
- **No floor (regex match only)** — rejected because the failure mode is exactly "bypass by typing nothing." A floor is the entire point of the structural enforcement.

40 sits at the inflection point where most genuine one-sentence rationales succeed and most cop-outs fail.

## Consequences

- **Enables:** the (c) answer form is a real escape hatch, not a vaporware loophole. Writers who genuinely have no mechanism analysis to give can still merge by writing one substantive sentence.
- **Costs:** occasional false rejection on a 39-char legitimate rationale. Mitigation: writer extends to 40+ chars (typically a 1-2 word addition).
- **Tunable:** the threshold is a single constant in the validator library. If post-rollout telemetry shows a high false-positive rate, raise to 50 or 60 in one line of code without touching the workflow or template.

## Implementation reference

`.github/scripts/validate-pr-template.sh` constant `PR_TEMPLATE_RATIONALE_MIN_CHARS=40` and function `validate_rationale_length()`. Plan section 10, Decision 2.
