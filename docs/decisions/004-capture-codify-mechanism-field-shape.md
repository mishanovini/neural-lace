# Decision 004: Capture-codify mechanism field shape

**Date:** 2026-04-23
**Status:** Implemented
**Tier:** 2
**Stakeholders:** Misha (maintainer)

## Context

The capture-codify-pr-template plan (`docs/plans/capture-codify-pr-template.md`) introduces a structural requirement that every PR answer the question **"what mechanism would have caught this?"**. The CI workflow needs to detect both empty submissions and trivially-filled ones. The shape of the field — single freeform paragraph vs. structured sub-headings vs. external Issue Forms — drives both writer cognitive load and validator regex complexity.

## Decision

A single Markdown section `## What mechanism would have caught this?` with three explicit answer-form sub-headings:
- `### a) Existing catalog entry` — cite an existing FM-NNN ID from `docs/failure-modes.md`
- `### b) New catalog entry proposed` — name the gap and propose adding it to the catalog
- `### c) No mechanism — accepted residual risk` — explain why no mechanism is appropriate (≥40 chars rationale required)

The validator looks for the section heading, the placeholder text (`<mechanism answer — replace this bracketed text>`), and selection of one of the three sub-headings.

## Alternatives Considered

- **GitHub Issue Forms for structured input** — rejected because Issue Forms only work for issues, not PR bodies. PRs are the level where mechanism analysis belongs (one PR = one logical fix unit), so PR-body templates are the only structural option.
- **HTML comment instructions only (no visible structure)** — rejected because the workflow needs to detect placeholder vs. filled state, which requires distinct text patterns the validator can match. Hidden HTML comments leave nothing to anchor on.
- **Single freeform paragraph (no answer-form sub-headings)** — rejected because it makes auditing harder: reviewers and the audit script can't tell at a glance whether the writer cited an existing entry, proposed a new one, or selected residual risk. Sub-headings make the choice explicit and machine-readable.

## Consequences

- **Enables:** clear auditing of the (a)/(b)/(c) distribution over time (telemetry backlog item filed). Easy regex match for both placeholder detection and answer-form selection. Writers have a clear template to fill rather than staring at a blank box.
- **Costs:** writers must choose an answer form, a small cognitive cost. The template is slightly more verbose than a single freeform field would be.
- **Blocks:** none.

## Implementation reference

`.github/PULL_REQUEST_TEMPLATE.md` (template body), `.github/scripts/validate-pr-template.sh` (regex), `docs/plans/capture-codify-pr-template.md` Section 3 (Interface Contracts).
