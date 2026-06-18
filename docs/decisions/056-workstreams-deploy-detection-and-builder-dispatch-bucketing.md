# 056 — Workstreams deploy-detection + builder-dispatch bucketing fix

**Date:** 2026-06-17
**Status:** Active
**Stakeholders:** Misha (operator of the :7733 GUI), harness maintainers
**Relates to:** ADR-031/032 (conv-tree/workstreams architecture + schema), ADR-054
(builder-dispatch work-item emission), Workstreams Phase R7 (`work-in-motion-sweep.js`).

## Context

The :7733 Workstreams GUI did not reflect the orchestrator's real status
(diagnosis: `docs/discoveries/2026-06-17-workstreams-no-deploy-signal-no-ask-resolution.md`).
Confirmed against the live 462-item canonical state file:

- **Deployed = 0** despite real Vercel production deploys today. Root cause:
  `isDeployed(it)` keys off `it.deployed === true` (`web/app.js:394`), which is
  only set by `item-deployed` / `item-shipped{deployed:true}`
  (`state/reducer.js:458,476`). **NO hook anywhere emits `item-deployed`** —
  `work-in-motion-sweep.js` (the ground-truth reconciler) explicitly deferred
  deploy detection to "the operator's / deploy tooling's transition" that never
  existed. Only the GUI's manual per-item button set it; the orchestrator never
  clicks it. → structurally always 0.
- **Shipped·not-deployed = 211.** Of these, **93 were builder-dispatch items**
  (ADR-054 `--on-builder-complete` → `action-done` → checked → `itemState`
  'shipped'). A builder dispatch is AI-internal completed work, NOT deployable
  code; it should never sit in a "merged code awaiting production" backlog.

## Decision

Two additive, ground-truth-derived fixes — NO schema bump (ADR-032 §1
additive-within-major), NO new hook, NO hand-edit of state:

1. **Deploy detection in `work-in-motion-sweep.js`.** A new `collectDeploys(repo)`
   collector reads production-deploy ground truth from the operator's
   **authenticated Vercel CLI** (no API key in the harness): a repo with a
   linked `.vercel/project.json` runs `vercel ls --prod` and finds the latest
   READY Production deploy's age → an approximate "production live as of"
   timestamp. The sweep then emits `item-deployed` for any shipped `wim-pr-*` /
   `wim-br-*` node whose `shipped_ts` predates that deploy. Conservative by
   construction:
   - Only `pr`/`br` wim categories (merged code), never `plan` (a plan going
     non-ACTIVE means it closed, not that code deployed).
   - A ship with NO subsequent Ready deploy stays shipped-not-deployed (never a
     false deploy).
   - Deploy SKIP (no `.vercel` link / CLI absent / unauth / parse failure) →
     NO `item-deployed` (per-category failure isolation, mirroring the existing
     plans/branches/PR collectors — a missing signal never falsely deploys).
   - Idempotent (checks `it.deployed` locally).

   The Vercel "Age/Status/Environment" table renders to **stderr** (stdout is
   URL-only), and on Windows the CLI is a `.cmd` shim — both handled by the
   `runVercelLs` helper (shell invocation, combined stderr+stdout parse,
   `VERCEL_BIN` override).

2. **builder-dispatch excluded from shipped-not-deployed (`web/app.js`).**
   `isShippedNotDeployed` now also requires `!isBuilderDispatch(it)`
   (`details._category === 'builder-dispatch'`). Completed builder dispatches
   are accomplishments → they fall through to Recently-shipped, not the
   deploy-pending backlog. (211 → 118 immediately, before any deploy sweep.)

## Alternatives Considered

- **Vercel API + token in the harness.** Rejected: couples the harness to a
  credential and an org; the operator's CLI is already authenticated and is the
  decoupled ground truth.
- **Exact per-PR commit-SHA reachability against the deployed SHA.** Rejected:
  `vercel ls --json` is unsupported and `vercel inspect` omits the SHA in plain
  output — fragile CLI archaeology. For an auto-deploy-on-master setup, "a
  successful prod deploy completed after this merged" is the truthful answer to
  "did it reach production," at minute resolution.
- **Auto-resolve stale "awaiting-me" asks (mark them answered).** Rejected on
  honesty grounds (Rule 0): a free-text decision has no ground-truth link, so
  marking it `answered`/`action-done` would fabricate a resolution. Surfaced as
  an operator-controlled UI proposal instead (see the PR body), not auto-applied.
- **Hand-edit the state file to set deployed/clear stale.** Rejected per the
  "reconciler over hand-editing" discipline (`rules/workstreams-state.md`): the
  semantically-true tree is written via the event-sourced facade, never spliced.

## Consequences

- **Enables:** Deployed bucket reflects reality once the deploy-aware sweep runs
  with a per-machine `wim-repos.json`; the shipped-not-deployed backlog stops
  counting AI-internal dispatch noise; the operator sees real "shipped→deployed"
  transitions as ground truth advances.
- **Costs:** deploy detection is age-resolution (minute), not commit-exact — a
  truthful approximation for auto-deploy-on-master, documented as such. Requires
  a per-machine `wim-repos.json` listing Vercel-linked repos (the existing
  Phase-R7 config; the kit ships only the example).
- **Blocks nothing.** Pure addition; existing gates/hooks/self-tests unaffected
  (wim-sweep self-test 49/49). The stale-awaiting-me clearing remains an open
  proposal for the operator to sign off on (not auto-applied).
