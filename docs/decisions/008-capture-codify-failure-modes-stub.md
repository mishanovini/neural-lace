# Decision 008: Failure-modes file as a stub created by capture-codify plan

**Date:** 2026-04-23
**Status:** Implemented
**Tier:** 2
**Stakeholders:** Misha (maintainer)

## Context

The PR template's (a) answer form references catalog entries by ID (`FM-NNN`) in `docs/failure-modes.md`. The catalog itself is a separate scope owned by the companion `failure-mode-catalog` plan. The two plans were initially planned to ship in unspecified order, raising the question: does the capture-codify plan create the catalog file, or wait for the catalog plan?

## Decision

The capture-codify plan creates a one-paragraph stub at `docs/failure-modes.md` that forward-links to the companion catalog plan. The stub is overwriteable: the catalog plan, when it ships, replaces the stub with real catalog content (FM-001..FM-NNN entries). This decouples the two plans' shipping order — neither blocks the other.

## Alternatives Considered

- **Wait for the catalog plan to ship first** — rejected because plan sequencing is not enforced; the catalog plan could be deferred for weeks while the PR template's references dangle. A stub is a 5-minute task that unblocks the references regardless of catalog-plan timing.
- **Embed catalog content in the capture-codify plan** — rejected because catalog authoring is its own discipline (curation, ID assignment, cross-references) and bloats the capture-codify plan beyond its scope.
- **Skip the stub entirely; let references 404** — rejected because dangling links degrade reviewer trust ("the template tells me to cite FM-NNN but the file doesn't exist?") and produce a poor first impression.

In actual sequencing, the catalog plan shipped first (FM-001..FM-006 already in `docs/failure-modes.md` as of plan #2's completion), so the stub-creation step was no-op by the time this plan built — the forward-link addition still applies but the file already had real content.

## Consequences

- **Enables:** the capture-codify plan ships independently of the catalog plan; references resolve from day one.
- **Costs:** small risk of the stub being committed and never replaced if the catalog plan never ships. Mitigated by the stub being a single paragraph with an explicit "stub — replaced by catalog plan" marker.
- **Blocks:** none.

## Implementation reference

`docs/failure-modes.md` (the file — now containing both the forward-link and FM-001..FM-006 from plan #2). Plan section 10, Decision 5.
