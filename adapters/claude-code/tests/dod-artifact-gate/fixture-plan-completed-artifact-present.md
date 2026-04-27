# Plan: Fixture — DoD artifact present

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: This is a self-test fixture for the DoD artifact gate; not a real plan.

## Goal

Synthetic plan used by `pre-stop-verifier.sh --self-test` to exercise Check 5 / A2.
Exit ALLOW is expected because the declared DoD artifacts exist with the required content.

## Scope

- IN: validate that present artifacts allow COMPLETED.
- OUT: anything else.

## Tasks

- [x] A.1 Self-test placeholder task

## Files to Modify/Create

- N/A

## Assumptions

- The fixture's `## DoD Artifacts` section is parsed by Check 5.
- Sibling files under `present-fixtures-runs/<runId>/` exist on disk.

## Edge Cases

- Artifact path resolves via `<runId>` glob expansion.

## Acceptance Scenarios

n/a — self-test fixture.

## Out-of-scope scenarios

None.

## Testing Strategy

Run `pre-stop-verifier.sh --self-test`.

## Decisions Log

None.

## Definition of Done

- [x] Loop converges on current master
- [x] Human sign-off recorded

## DoD Artifacts

### bullet: Loop converges on current master
- artifact: present-fixtures-runs/<runId>/CONVERGENCE.json
- requires_field: verdict
- requires_value: CONVERGED

### bullet: Human sign-off recorded
- artifact: present-fixtures-runs/<runId>/SIGNOFF.md
- requires_pattern: approved
- requires_min_length: 10

## Evidence Log

EVIDENCE BLOCK
Task ID: A.1
Verified at: 2026-04-26T00:00:00Z
Verdict: PASS
Notes: Synthetic — fixture only.
