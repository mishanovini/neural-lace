# Mini Design — Dashboard Friction Freshness (FIXTURE — plan-fidelity-reviewer golden case)

**Status:** FIXTURE — not a real design. Built for `plan-fidelity-reviewer`'s admission test
(`adapters/claude-code/agents/plan-fidelity-reviewer.md`, GOLDEN CASE section). Replays the P-32 /
2026-08-02e defect class (a binding directive present in the source document, absent in substance
from the artifact a builder reads) as a design→plan pair, in miniature, so the agent's protocol can
be exercised end to end instead of just described.

**Supersedes:** a prior "refreshes on a timer" reading of the same dashboard pane (the exact class
`docs/designs/gated-pipeline-master-2026-08-03.md`'s P-42 discussion documents for the real system:
`derive-cache.js:7-11`'s timer-pull was superseded by push-materialize).

## 1. Problem statement

The dashboard's friction pane has gone stale between real events and pane refresh more than once,
because the pane re-derives its counts on a fixed interval instead of the moment the underlying
event is written. A push-materialized update — fired by the same write that mutates the event log —
closes that staleness window to zero by construction; a timer-based poll cannot, no matter how short
the interval, because it always trades a bounded staleness window for simplicity.

## 2. Binding constraints

- **Hard stop:** no new read store for friction counts may be introduced without a push writer;
  a timer-refreshed cache is the exact defect this design exists to retire.

## 3. Decisions

| # | Decision | Rationale | Reversal cost |
|---|---|---|---|
| DEC-F1 | Friction counts are push-materialized, not polled | A poll interval is always a staleness window; push has none | One writer hook to remove |

## 4. Requirements

| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-D1 | MUST | Dashboard friction counts MUST be **push-materialized**: the same write that mutates the underlying friction/event log directly updates the pane's read store, in the same operation — **never re-derived on a timer, never served from a cache with a fixed TTL that re-polls the source on expiry**. Rationale: a timer/TTL-refreshed read store drifts by construction between ticks (the defect this design retires — see Problem statement). Verify: a fixture write to the event log is followed, with zero intervening timer tick, by the pane read store reflecting it. |
| REQ-D2 | SHOULD | The pane renders an explicit stale/unknown state (never a confident zero) when the push writer has not run since the store was created. |

## 5. Non-goals

- A general-purpose polling framework for panes that do not need push freshness — out of scope for
  this fixture design.

## 6. Directives-honored

- DEC-F1 (push-materialize, not poll) is the single binding directive this design carries. Any plan
  implementing REQ-D1 must carry DEC-F1's substance in its task text, not merely cite REQ-D1's id —
  per the P-32 lesson this fixture replays: a directive present in the design and absent from the
  task text a builder reads is functionally dropped.
