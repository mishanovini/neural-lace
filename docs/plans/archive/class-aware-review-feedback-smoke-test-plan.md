# Plan: Smoke Test Fixture for Class-Aware Reviewer Feedback (THROWAWAY)

Status: ABANDONED
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Throwaway smoke-test fixture with four intentional defect-class instances. Purpose was to validate Plan #7's class-aware reviewer format. Evidence captured; fixture's job is done.

> **NOTE:** This file is a deliberately-flawed throwaway used to smoke-test the systems-designer agent's class-aware feedback contract (Task A.10 of `class-aware-review-feedback.md`). It is NOT a real plan and is not committed for any production purpose. The four flaws below are intentional examples of a single defect class.

## Goal

Throwaway smoke-test fixture. Should not be used to plan or build anything.

## Scope

- IN: throwaway fixture
- OUT: everything

## Tasks

- [ ] T.1 Do something
- [ ] T.2 Do something else

## Files to Modify/Create

- `none` — fixture

## Assumptions

- Reviewer reads this fixture and identifies the defect class

## Edge Cases

- Reviewer doesn't identify the class

## Testing Strategy

- Manual review

## Decisions Log

*Throwaway.*

## Definition of Done

- [ ] Reviewer outputs class-aware feedback per the new contract

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)

The system works.

### 2. End-to-end trace with a concrete example

The user does a thing, and then the system does another thing. Then it succeeds.

### 3. Interface contracts between components

Components pass data between each other using standard formats.

### 4. Environment & execution context

Runs on a GitHub Actions runner with the standard setup.

### 5. Authentication & authorization map

Uses the GitHub token for GH actions and the Claude token for Claude.

### 6. Observability plan (built before the feature)

Standard GitHub Actions logs.

### 7. Failure-mode analysis per step

If something fails we retry.

### 8. Idempotency & restart semantics

The pipeline is idempotent.

### 9. Load / capacity model

Uses parallel builds.

### 10. Decision records & runbook

We chose squash merge. Debug by checking the logs.
