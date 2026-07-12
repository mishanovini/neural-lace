---
title: Deep-audit scope gap — page-route integrity + analytics-metric correctness uncovered
date: 2026-06-17
type: process
status: decided
auto_applied: true
originating_context: orchestrator-prime <product> session; the operator found 3 customer-facing bugs (Alert-detail 404; Analytics Contact Rate >100% + wrong Overall-Conversion stage; Communications Response Rate measuring a dead field) that the deep functional audit (Workflow wwykddsfl) did NOT surface
decision_needed: n/a — auto-applied (widen audit scope; a schema-vs-SELECT lint is a candidate mechanical follow-up)
predicted_downstream:
  - the audit prompt / a future "page-route integrity + metric-sanity" audit dimension
  - candidate: a SELECT-column-exists lint (the recurring column-mismatch class)
---

## What was discovered

The deep functional audit covered the conversation engine, scheduling/booking, persistence,
state machine, and messaging — and found 8 real must-fixes. But the operator, clicking
around the live app, immediately found THREE customer-facing bugs the audit missed:

1. **Alert-detail 404** — `/alerts/[id]/page.tsx`'s `alert_events` SELECT names columns the
   list page doesn't; a non-existent column makes PostgREST reject the query → `notFound()`
   → 404 on every alert. The audit never exercised the route's RENDER (only the route's
   existence), so it passed.
2. **Analytics Contact Rate >100%** — the conversion funnel is cohort-inconsistent (each
   stage filters an independent population), so "Contacted" can exceed "New Leads." A
   metric-sanity check (rates ≤ 100%, funnel monotonic) would have caught it.
3. **Communications Response Rate ~0%** — measures `(outbound with replied_at) / sent`, but
   `replied_at` is essentially never populated, so it reads ~0.2% despite 395 real replies.
   A metric-vs-reality cross-check would have caught it.

## Why it matters

"Should have been caught in your audit" is correct. The audit's coverage was
engine/data/messaging-shaped; it had NO dimension for (a) **page-route render integrity**
(does every `<Link>` target actually RENDER, not just resolve?) or (b) **analytics-metric
correctness** (do rates stay ≤100%, do funnels stay monotonic, does each metric measure
what its label claims, does it match observable reality?). Those are exactly the surfaces a
human operator hits first.

Also notable: the Alert-detail 404 is the THIRD column-mismatch bug today (the other two:
`messages.template_variant_id` in send-email + the Resend webhook, PR #557). A SELECT naming
a column that doesn't exist is a recurring CLASS — a schema-vs-SELECT lint (assert every
selected column ⊆ the table's columns) would catch all of them mechanically.

## Options

A. Behavioral: add two dimensions to the audit prompt — "page-route render integrity" (load every Link/route target, assert it renders, not 404/500) and "analytics-metric sanity" (rates ≤100%, funnels monotonic, label-vs-formula match, value-vs-reality cross-check).
B. Mechanical: a SELECT-column-exists lint / test that parses Supabase `.select(...)` strings and asserts each column exists in the migration-defined schema (catches the column-mismatch class — 3 instances today).
C. Both.

## Recommendation

C. A is the immediate widen-the-net (auto-applied: the next audit includes route-render +
metric-sanity dimensions). B is the higher-leverage mechanical follow-up for the
column-mismatch class specifically — surfaced for the operator as a harness candidate
(not built this session).

## Decision

A auto-applied (audit scope widened going forward). B surfaced as a candidate mechanical
gate. The 3 specific <product> bugs are being fixed via PR fix/analytics-alerts-correctness
(plan docs/plans/analytics-alerts-correctness-2026-06-17.md in the <product> repo).

## Implementation log

- This discovery (durable capture of the audit-scope gap). B not yet built.
- <product> fixes dispatched (separate PR). 
