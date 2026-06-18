---
title: Workstreams GUI cannot show deployed/accomplishments — no deploy emitter, no ask resolution
date: 2026-06-17
type: failure-mode
status: decided
auto_applied: true
originating_context: docs/plans/workstreams-ui-reflect-real-status (fix/workstreams-ui-reflect-real-status)
decision_needed: n/a — auto-applied (additive reconciler extension, reversible)
predicted_downstream:
  - neural-lace/workstreams-ui/scripts/work-in-motion-sweep.js
  - docs/decisions/056-workstreams-deploy-detection-and-builder-dispatch-bucketing.md
---

## What was discovered

The :7733 Workstreams GUI does not reflect the orchestrator's real status. Confirmed
numerically against the live canonical state file (resolved via
`~/.claude/workstreams-state-path.txt` → `~/.../workstreams-coordination/state/tree-state.json`,
462 items): `Deployed 0`, `Shipped·not-deployed 211`, `Awaiting-me 63`.

Root causes (file:line):

1. **Deployed = 0 (PROVEN).** `isDeployed(it)` = `it.deployed === true`
   (`web/app.js:394`). `it.deployed` is only ever set by `item-deployed` or
   `item-shipped{deployed:true}` (`state/reducer.js:458,476`). NO hook anywhere
   emits `item-deployed` — `grep -rln item-deployed adapters/claude-code/hooks/`
   and `~/.claude/hooks/` both return nothing. `work-in-motion-sweep.js:386-387`
   explicitly comments "Deployed → NOT emitted by this sweeper … the operator's /
   deploy tooling's transition" — that transition does not exist. Only the GUI's
   manual per-item "mark deployed" button (`app.js:2645`) sets it, which the
   orchestrator never clicks. Result: structurally always 0 despite real Vercel
   prod deploys (a downstream product repo's prod = Ready, 4 deploys in the last hour today).

2. **Shipped·not-deployed = 211 (PROVEN).** `isShippedNotDeployed` = shipped &&
   !deployed (`app.js:395-397`). 87 items have explicit `state:shipped`; 124 are
   legacy `checked` items that `itemState()` maps to `shipped` (`app.js:280`).
   Every one lacks a deploy signal (root cause 1), so all 211 pile into this
   bucket. Completed builder-dispatch work-items (165 `builder-dispatch` items
   from ADR-054 `--on-builder-complete` → `action-done` → checked) feed this.

3. **Awaiting-me = 63 never clears (PROVEN).** `isAwaitingMe` = open Misha-ask
   (decision/question/action_item_for_user) && !responded (`app.js:314-316`).
   A fence emits `decision-raised`/`action-added`; resolution only fires via the
   GUI resolve button or `decision-context-reply-emit.sh` (UserPromptSubmit — only
   in the originating session). A decision actioned in a later/Dispatch session
   (e.g. `DEC-2026-06-16-conv-deploy go/no-go`, deployed days ago) is never marked
   answered/done → persists as a stale ask. No reconciler ages these out.

4. **Orchestrator work IS emitted but mis-bucketed (PROVEN).** ADR-054
   `--on-builder-dispatch` IS wired (`settings.json.template:284`) and firing
   (165 builder-dispatch items). But merges/deploys are NOT emitted as
   accomplishments — there is no "PR merged → deployed" feed; merged PRs only
   show as shipped-not-deployed via the wim-sweep's gone-detection.

The system tracks Dispatch branches + builder dispatches + repo-observable
in-flight effort (wim-sweep), but has NO deploy emitter and NO ask-resolution
reconciler, so it structurally cannot show "what shipped to production" or clear
resolved asks.

## Why it matters

The operator runs the GUI to know what the orchestrator is doing. With Deployed
permanently 0, a 211-item stale shipped backlog, and 63 uncleared asks (some
resolved days ago), the GUI is actively misleading — it trains the operator to
ignore it.

## Decision

Extend the existing ground-truth reconciler (`work-in-motion-sweep.js`) rather
than build parallel machinery or hand-edit state (per the prompt + the
"reconciler over hand-editing" discipline). Additive, within the ADR-032 event
schema (no schema bump). Reversible (one revert). Auto-applied because it is a
reversible reconciler extension, not an irreversible op.

## Implementation log

- `neural-lace/workstreams-ui/scripts/work-in-motion-sweep.js` — `collectDeploys`
  collector (Vercel CLI ground truth, stderr-parsed, Windows `.cmd`-aware) +
  deploy-emission in `sweep()`: emits `item-deployed` for shipped `wim-pr-*`/
  `wim-br-*` nodes whose ship predates the latest Ready prod deploy. Conservative
  (merged-code categories only; no-deploy → stays shipped-not-deployed; SKIP on
  unavailable signal → never a false deploy; idempotent). Self-test 49/49.
- `neural-lace/workstreams-ui/web/app.js` — `isShippedNotDeployed` now excludes
  `details._category==='builder-dispatch'` (211→118 immediately; 93 AI-internal
  completed dispatches fall through to Recently-shipped, not the deploy-pending
  backlog).
- Applied against live state: Deployed 0→35, shipped-not-deployed 211→83 (verified
  via the GUI `/api/state`).
- `docs/decisions/056-workstreams-deploy-detection-and-builder-dispatch-bucketing.md`
  — ADR.
- NOT done (honesty / Rule 0): auto-resolving stale "awaiting-me" asks. A free-text
  decision has no ground-truth link; marking it `answered`/`action-done` would
  fabricate a resolution. Surfaced as an operator-controlled UI proposal in the PR
  body instead.
