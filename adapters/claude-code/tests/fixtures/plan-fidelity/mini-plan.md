# Plan: Dashboard Friction Freshness (FIXTURE — plan-fidelity-reviewer golden case)
Status: FIXTURE
Execution Mode: n/a — fixture, never dispatched
Mode: code

design-ref: adapters/claude-code/tests/fixtures/plan-fidelity/mini-design.md@<computed at fixture-load time via `git hash-object`>
<!-- FIXTURE NOTE: this file is never committed as an ACTIVE plan and never dispatched — it exists
     solely as the "plan" half of plan-fidelity-reviewer's golden-case pair. The reviewer, when
     replaying this fixture, computes the design blob itself (git hash-object mini-design.md) rather
     than trusting a hardcoded value here, so the fixture stays valid across any future edit to
     mini-design.md. -->

## Goal

Implement `adapters/claude-code/tests/fixtures/plan-fidelity/mini-design.md` (REQ-D1, REQ-D2):
keep the dashboard's friction pane current with the underlying event log.

## Scope

- IN: the friction pane's freshness mechanism (REQ-D1).
- OUT: everything else in the mini-design's Non-goals.

## Tasks

- [ ] 1. Friction pane freshness: `friction-pane.js` polls the ledger file every 60 seconds via a
  TTL cache — on each poll, if the TTL has expired, re-read `~/.claude/state/gate-friction/
  ledger.jsonl` from disk, recompute the friction counts, and re-render the pane with the fresh
  values; between polls the pane serves the cached counts. This bounds staleness to at most one poll
  interval (60s) while avoiding a re-read on every pane render — Verification: mechanical —
  Implements: REQ-D1 — Docs impact: pane help text notes the 60s refresh interval

## Files to Modify/Create

Modify:
- `friction-pane.js` — TTL-cache poll loop (T1)

## Assumptions

- A 60-second staleness window is acceptable for this pane; if the operator needs tighter freshness
  later, the poll interval can simply be shortened.

## Testing Strategy

`friction-pane.js`'s self-test primes the ledger, waits one TTL cycle, and asserts the pane's
rendered counts match the ledger's post-write state.

<!-- THIS IS THE GOLDEN-CASE DEFECT, LEFT INTENTIONALLY IN THE FIXTURE:
     REQ-D1 requires push-materialization ("the same write... directly updates... in the same
     operation — never re-derived on a timer, never served from a cache with a fixed TTL that
     re-polls the source on expiry"). Task 1's text does exactly the forbidden thing: a 60-second
     TTL cache that re-polls the source on expiry. The task cites `Implements: REQ-D1` and even
     sounds reasonable in isolation ("bounds staleness," "avoids a re-read on every render") — a
     naive id-match reviewer marks this FULL. plan-fidelity-reviewer's Step 1 (read both texts,
     compare MECHANISM not topic) must mark this mapping CONTRADICTORY and, because REQ-D1 is MUST,
     rate it Critical severity, producing verdict REFORMULATE at minimum. See the agent file's
     GOLDEN CASE section for the required eval output. -->
