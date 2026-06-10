# Plan: Revert mirror Action workflow (keep sync.sh; switch to harness-internal drift detection)

Status: COMPLETED
<!-- Closed 2026-06-04 by stale-ACTIVE-plan cleanup. Deliverable was REMOVAL: .github/workflows/mirror-to-sister.yml is GONE from HEAD; ADR-044 status flipped to "Reverted (2026-05-28)" with matching DECISIONS row; sync.sh correctly kept per OUT scope. The absence IS the success signal. Dispatch never ran task-verifier. -->
Execution Mode: orchestrator
Mode: code
frozen: true
tier: 1
rung: 0
architecture: harness-infrastructure
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal revert; verification is the workflow file no longer existing on PT master + ADR-044 status flipped to Reverted; the URL-based sync.sh stays.
Backlog items absorbed: none

## Goal

Remove the cross-repo mirror Action (PRs #30/#31/#32) per the 2026-05-28 pivot. The PAT
cross-account operational burden was disproportionate to the edge-case coverage it
provided; every NL push happens through Claude Code with the harness loaded, so the
URL-based `sync.sh` wrapper covers the steady-state need. Drift coverage moves to a
3-component harness-internal mechanism in subsequent PRs.

## Scope
- IN: delete `.github/workflows/mirror-to-sister.yml`; mark ADR-044 Reverted in both
  the ADR file and the DECISIONS.md index row.
- OUT: deleting `sync.sh` (it stays — right primitive); deleting ADR-044 or the
  archived plan (both preserved as historical record); revoking `MIRROR_PAT` secrets
  (manual operator action — surfaced to Misha); the drift-detection components (separate
  PRs).

## Tasks
- [ ] 1. Delete the workflow file + mark ADR-044 Reverted + update DECISIONS.md row — Verification: mechanical

## Files to Modify/Create
- `.github/workflows/mirror-to-sister.yml` — DELETE
- `docs/decisions/044-neural-lace-mirror-automation.md` — mark Reverted
- `docs/DECISIONS.md` — flip row 044 status to Reverted

## Testing Strategy
- Mechanical: post-merge, `gh workflow list --repo Pocket-Technician/neural-lace` no
  longer shows "Mirror master to sister repo"; `ls .github/workflows/` doesn't include
  `mirror-to-sister.yml`.

## Walking Skeleton

n/a — single mechanical deletion + status flip.

## Acceptance Scenarios

n/a — acceptance-exempt (harness-internal revert; downstream verification is the
absence of the workflow file).
