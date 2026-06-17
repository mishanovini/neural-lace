# Plan: Workstreams UI reflect real status (deploy-detection + builder-dispatch bucketing)
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work on the workstreams-ui status surface; self-tests + live /api/state verification are the acceptance artifact (no contractor-facing product surface).
tier: 2
rung: 1
architecture: orchestration
frozen: true
prd-ref: n/a — harness-development

## Goal

The :7733 Workstreams GUI did not reflect the orchestrator's real status:
`Deployed 0` (despite real Vercel production deploys), a 211-item
`shipped·not-deployed` backlog, and uncleared `awaiting-me` asks. Make the
status buckets reflect reality, via the existing ground-truth reconciler
(`work-in-motion-sweep.js`), additively and within the ADR-032 event schema.

## User-facing Outcome

The operator (the GUI's user) sees a `Deployed` bucket that reflects real
production deploys, a `shipped·not-deployed` bucket scoped to genuinely
merged-but-undeployed code (not AI-internal dispatch noise), and a
deploy-detection reconciler that advances shipped→deployed from observable
ground truth on each run.

## Scope
- IN: deploy-detection collector + emission in `work-in-motion-sweep.js`; its
  self-test; the `isShippedNotDeployed` builder-dispatch exclusion in
  `web/app.js`; the ADR + discovery + DECISIONS index row.
- OUT: auto-resolving stale awaiting-me asks (rejected on honesty grounds —
  surfaced as an operator proposal in the PR, not built); any redesign of the
  GUI view (proposed, not built); a scheduled-task wiring change.

## Tasks
- [x] 1. Diagnose the bucket-computation root causes (Deployed=0, 211 stale, awaiting-me uncleared) with file:line evidence — Verification: mechanical
- [x] 2. Add Vercel deploy-detection (collectDeploys + item-deployed emission) to the wim-sweep, with conservative guards + cross-platform CLI resolution — Verification: mechanical
- [x] 3. Extend the wim-sweep self-test with deploy-detection scenarios (T11-T14) — Verification: mechanical
- [x] 4. Exclude builder-dispatch items from the shipped-not-deployed bucket in app.js — Verification: mechanical
- [x] 5. ADR 056 + discovery + DECISIONS index — Verification: mechanical

## Files to Modify/Create
- `neural-lace/workstreams-ui/scripts/work-in-motion-sweep.js` — deploy-detection collector + emission
- `neural-lace/workstreams-ui/scripts/work-in-motion-sweep.selftest.js` — T11-T14 deploy scenarios
- `neural-lace/workstreams-ui/web/app.js` — isShippedNotDeployed excludes builder-dispatch
- `docs/decisions/056-workstreams-deploy-detection-and-builder-dispatch-bucketing.md` — ADR
- `docs/discoveries/2026-06-17-workstreams-no-deploy-signal-no-ask-resolution.md` — diagnosis
- `docs/DECISIONS.md` — index row for ADR 056

## In-flight scope updates
(no in-flight changes)

## Assumptions
- The wim-sweep is the right place to add deploy detection (it already owns
  ground-truth ingestion + gone-detection for the same wim nodes).
- The operator's Vercel CLI is authenticated (it is — verified). Repos without a
  `.vercel` link / CLI / auth degrade to deploy-SKIP (no false deploy).
- `item-deployed` is an existing schema event (it is — schema.js:213); no bump.

## Edge Cases
- Deploy ground truth unavailable (no `.vercel`, CLI missing, unauth) → SKIP, no
  item-deployed (per-category failure isolation, verified by self-test T13).
- A prod deploy OLDER than a ship → not this work's deploy (verified by T14).
- Legacy checked item with no shipped_ts → conservatively not auto-deployed.
- Builder-dispatch item completing → excluded from shipped-not-deployed (app.js).

## Acceptance Scenarios
- n/a — acceptance-exempt (harness-internal; self-tests + /api/state are the artifact)

## Out-of-scope scenarios
- Auto-resolving stale awaiting-me asks — rejected on honesty grounds; operator proposal only.

## Testing Strategy
- wim-sweep self-test 49/49 (12 new for deploy detection); state 21/21; reconciler 33/33.
- Live verification: dry-run plans 35 item-deployed for proj-circuit; applied →
  Deployed 0→35, shipped-not-deployed 211→83 (confirmed via GUI /api/state).

## Walking Skeleton
N/A — extends an existing reconciler; the thinnest slice (collectDeploys → one
item-deployed event) was built and verified first against real ground truth.

## Decisions Log
### Decision: deploy ground truth = Vercel CLI, age-resolution, not commit-exact
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** read `vercel ls --prod` from the operator's authenticated CLI; a
  shipped wim node whose ship predates the latest Ready prod deploy is deployed.
- **Alternatives:** Vercel API + token (rejected: couples harness to a credential);
  exact per-PR commit-SHA reachability (rejected: `vercel ls --json` unsupported,
  `vercel inspect` omits SHA — fragile).
- **Reasoning:** for auto-deploy-on-master, "a prod deploy completed after this
  merged" is the truthful answer to "did it reach production" at minute resolution.
- **Decision record:** docs/decisions/056-workstreams-deploy-detection-and-builder-dispatch-bucketing.md

### Decision: do NOT auto-resolve stale awaiting-me asks
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** leave ask-resolution to the operator; surface as a UI proposal.
- **Reasoning:** Rule 0 — a free-text decision has no ground-truth link; marking
  it answered would fabricate a resolution.
- **Decision record:** same ADR (Alternatives Considered).

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — Mode: code harness work, no Systems Engineering Analysis sections.
- S2 (Existing-Code-Claim Verification): all file:line claims re-verified against the files at diagnosis time.
- S3 (Cross-Section Consistency): swept, 0 contradictions.
- S4 (Numeric-Parameter Sweep): no new numeric parameters introduced (age units derived in parseVercelAgeToMs).
- S5 (Scope-vs-Analysis Check): swept, every "add/modify" verb checked against Scope OUT; ask-aging correctly OUT.

## Definition of Done
- [x] All tasks checked off
- [x] All tests pass (wim-sweep 49/49, state 21/21, reconciler 33/33)
- [x] Live verification: Deployed 0→35, shipped-not-deployed 211→83 via /api/state
- [x] ADR + discovery + index landed
- [x] Completion report appended below

## Completion Report

### 1. Implementation Summary
Tasks 1-5 built as planned. Deploy detection added to the wim-sweep reconciler
(ground-truth-derived, conservative, idempotent); builder-dispatch excluded from
shipped-not-deployed in app.js. ADR 056 + discovery + index row landed.
Backlog items absorbed: none.

### 2. Design Decisions & Plan Deviations
Two Tier-2 decisions (deploy-via-CLI; no auto-ask-aging) recorded in ADR 056.
No deviations from the approved scope; ask-aging deliberately left OUT (honesty).

### 3. Known Issues & Gotchas
- Deploy detection is age-resolution (minute), not commit-exact — documented in ADR.
- The deploy-aware sweep requires a per-machine `wim-repos.json` listing
  Vercel-linked repos (existing Phase-R7 config; the kit ships only the example).
- The live GUI's `fs.watch` can cause transient EPERM on the canonical state file's
  atomic rename when applying mid-session; the facade is append-only/atomic per
  event so a mid-batch failure is non-corrupting (retry completes the batch).

### 4. Manual Steps Required
- For deploy detection to run on a machine, create `wim-repos.json` (or
  `~/.claude/local/wim-sweep-repos.json`) listing the Vercel-linked repos, then
  run `node scripts/work-in-motion-sweep.js --apply` (or wire the reconciler
  scheduled task to include deploy detection).

### 5. Testing Performed & Recommended
- Self-tests: wim-sweep 49/49 (12 new), state 21/21, reconciler 33/33.
- Live: dry-run + apply against the canonical state; Deployed 0→35,
  shipped-not-deployed 211→83 confirmed via the GUI `/api/state`.
- Recommended: a forward-facing check that every GUI status bucket has ≥1 emitter
  that can move an item into it (the failure class this fix exposed).

### 6. Cost Estimates
Zero recurring cost — uses the operator's existing authenticated Vercel CLI;
no API key, no new service.
