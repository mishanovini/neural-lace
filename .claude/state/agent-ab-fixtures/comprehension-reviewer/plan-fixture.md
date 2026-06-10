# Plan: Per-org outbound notification rate-limiting (FIXTURE)
Status: ACTIVE-FIXTURE (synthetic — not a real plan; do not archive)
rung: 2
Mode: code

## Goal
Cap each org at 100 outbound notifications per rolling 60-second window, enforced
at the notifier level before queue handoff. Excess returns a structured rejection
(not a silent drop). The cap applies to ALL notification types, including system
alerts.

## Tasks
- [ ] T1. Add per-org rolling-window rate-limiter and wire into sendNotification —
  Verification: full

## Evidence Log

### T1 evidence

## Comprehension Articulation

### Spec meaning
The spec asks me to add per-org rate-limiting capped at 100 notifications per
rolling 60-second window for marketing notifications, enforced in the notifier
before queue handoff, returning a structured rejection when over the cap.

### Edge cases covered
- Window rollover: events outside the rolling 60s window are pruned before the
  cap check (`src/lib/rate-limiter.ts:31-38`).
- 100th accepted, 101st rejected: comparison is `>= 100` (`src/lib/rate-limiter.ts:13`).

### Edge cases NOT covered
- Cross-process limiter state (single-process in-memory map). Out of scope per plan.

### Assumptions
- Callers always pass a non-empty orgId.
