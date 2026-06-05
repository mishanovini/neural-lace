---
title: Workstreams UI "empty" root cause is no-fences-emitted, NOT a path-resolver bug
date: 2026-06-05
type: failure-mode
status: decided
auto_applied: true
originating_context: orchestrator-prime spawned a builder to "get the Workstreams UI working again as a frame of reference"
decision_needed: n/a — root-caused diagnostic-first; corrects the assumption in the 2026-06-04 cross-machine plan Task 7
predicted_downstream:
  - docs/plans/cross-machine-workstreams-coordination-2026-06-04.md (Task 7 premise)
  - neural-lace/workstreams-ui/scripts/surface-pending-asks.js (the manual surface added this session)
---

## What was discovered

The Workstreams GUI rendered "Nothing is waiting on you / Nothing in flight" even
though the server was up and serving **617 nodes**. Diagnostic-first evidence
(audit-log event histogram, not inference):

- `tree-state.json.audit.log`: **617 `branch-opened` + 617 `concluded` events, and
  ZERO `decision-raised` / `question-raised` / `action-added` events.**
- `/api/state`: 617 nodes, **0 work-items** across all nodes.
- The GUI is **item-centric**: `allWorkItems()` collects decision/question/action
  *items* on non-session nodes; the awaiting-me / in-flight / blocked tabs all
  filter *items*. Session/progress nodes (`ss-*`, `sp-*`) are deliberately hidden
  as provenance. So with 0 items, every actionable tab is legitimately empty.

The two assumptions going in were both **wrong**:

1. **"The decision-context emit path resolver points at the old `conversation-tree-ui`
   dir."** FALSE. `decision-context-gate.sh`, `decision-context-reply-emit.sh`, and
   `workstreams-emit.sh` all already resolve to `workstreams-ui` — verified in BOTH
   the canonical `adapters/claude-code/hooks/` and the live `~/.claude/hooks/`. The
   rename was already propagated.
2. **"The emit pipeline / reducer is broken."** FALSE. `decision-context-gate.sh
   --self-test` is **29/29 PASS**, including "item lands in snapshot.nodes[].items[]".
   The gate attaches items to the `proj-<slug>` project root (a non-session node) via
   the `state.js` facade, which renders cleanly. The GUI regression e2e is **10/10**.

**The real cause:** no decision-context *fence* had ever been emitted to this state.
orchestrator-prime authors its asks as fences, but `decision-context-gate.sh` is a
**Stop hook** and orchestrator-prime is a long-running loop whose Stop rarely fires —
so its asks never flushed into the state the GUI reads. The pipeline was healthy and
*starved of input*, not broken.

## Why it matters

The 2026-06-04 cross-machine plan Task 7 is scoped as "decision-context path resolver
→ workstreams-ui (items populate); reducer upsert dedup; open-branch fallback." Two of
those three premises are already satisfied:
- Path resolver: already correct (no change needed).
- Reducer dedup: the 81 dup person-session / 53 dup repo-session nodes are real
  but **do NOT pollute the rendered view** — sessions are hidden as provenance, so the
  tree renders the project roots cleanly (the harness repo plus the operator's other
  projects) without dedup. The dedup remains a nice-to-have for state-file size, not a
  render blocker.
- Open-branch fallback: not needed for the awaiting-me/in-flight frame of reference once
  real items exist.

The actionable gap is **input**: orchestrator-prime's asks must reach the GUI's state.

## Decision

- **Surface the asks manually NOW (reversible, auto-applied).** Added
  `scripts/surface-pending-asks.js` — emits the named pending asks via the SAME facade +
  node target the gate uses (`state.js appendEvent` → `proj-neural-lace`), idempotent on
  deterministic event_ids. Ran it; the GUI now shows 3 awaiting / 3 in-flight under
  neural-lace. Verified via headless screenshot + GUI regression 10/10.
- **Durable flow is orchestrator-prime's job (deferred to that loop).** As orchestrator-prime's
  own fences flush via the (verified-healthy) Stop-hook gate, they enrich these seeds in
  place (same item_ids → item-details-set). A follow-up worth considering: orchestrator-prime
  flushing its fences mid-loop rather than only at Stop, so the GUI stays live without the
  manual surface.

## Implementation log

- `neural-lace/workstreams-ui/scripts/surface-pending-asks.js` — new (this session)
- `neural-lace/workstreams-ui/server/server.js` — `/favicon.ico` → 204 (kills the only console 404)
- `neural-lace/workstreams-ui/package.json` — stale name `conversation-tree-ui` → `workstreams-ui`
- `neural-lace/workstreams-ui/docs/workstreams-render-2026-06-05.png` — render evidence
