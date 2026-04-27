# Plan: Fixture — No DoD Artifacts section

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: This is a self-test fixture for the DoD artifact gate; not a real plan.

## Goal

Synthetic plan used by `pre-stop-verifier.sh --self-test` to exercise Check 5 / A2.
Exit ALLOW is expected because there is no `## DoD Artifacts` section — A2 must be a
no-op when the section is absent. The base M1 check still passes since all DoD
checkboxes are checked.

## Scope

- IN: validate that A2 is a no-op when `## DoD Artifacts` is missing.
- OUT: anything else.

## Tasks

- [x] A.1 Self-test placeholder task

## Files to Modify/Create

- N/A

## Assumptions

- The fixture has no `## DoD Artifacts` section.

## Edge Cases

- A plan that doesn't opt into A2 must still complete cleanly.

## Acceptance Scenarios

n/a — self-test fixture.

## Out-of-scope scenarios

None.

## Testing Strategy

Run `pre-stop-verifier.sh --self-test`.

## Decisions Log

None.

## Definition of Done

- [x] All planned work done
- [x] Tests all green

## Evidence Log

EVIDENCE BLOCK
Task ID: A.1
Verified at: 2026-04-26T00:00:00Z
Verdict: PASS
Notes: Synthetic — fixture only.
