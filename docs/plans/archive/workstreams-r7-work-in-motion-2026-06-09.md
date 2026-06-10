# Plan: Workstreams R7 — work-in-motion ingestion sweeper
Status: SUPERSEDED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal Workstreams UI infrastructure; the sweeper selftest (temp state file, 34 scenarios) is the acceptance artifact
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Phase R7 of the Workstreams rebuild: close the R4 scenario-4 gap — the tracker
showed NONE of the actually-in-flight work. Build a deterministic, idempotent
sweeper that reads ground truth (ACTIVE plans, unmerged-unique branches, open
PRs across the configured repos), maps each effort to a deterministic wim-*
node under its project root, and emits — via the state.js facade only —
exactly the events the GUI's lifecycle filters consume (in-flight via
unchecked+stateless items; gone efforts via item-shipped → shipped-not-deployed
+ annotated + concluded).

## User-facing Outcome
After the orchestrator runs the sweeper against the canonical state file, the
Workstreams GUI's In-flight chip lists every ACTIVE plan, unmerged-unique
branch, and open PR across both repos; efforts that leave ground truth (merged
branch, closed plan, merged PR) move to Shipped-not-deployed and their nodes
conclude with an explanatory note.

## Scope
- IN: `neural-lace/workstreams-ui/scripts/work-in-motion-sweep.js` (new),
  `neural-lace/workstreams-ui/scripts/work-in-motion-sweep.selftest.js` (new),
  `neural-lace/workstreams-ui/config/wim-repos.example.json` (new — two-layer
  config: the per-machine repo map ships as a generic example only),
  `neural-lace/workstreams-ui/config/.gitignore` (add wim-repos.json);
  this plan file.
- OUT: running the sweeper against the real canonical state file (the
  orchestrator does that after merge); deploy-signal detection (`item-deployed`
  stays an operator/deploy-tooling transition); merging to master
  (orchestrator's job); any change to state/, web/, or server/ code.

## Tasks

- [ ] 1. Build scripts/work-in-motion-sweep.js — ground-truth collectors (ACTIVE plans, git-cherry unmerged-unique branches, gh open PRs with auth-switch fallback), deterministic wim-* node mapping, idempotent facade emit, gone-effort conclude, dry-run-default CLI — Verification: mechanical
- [ ] 2. Build scripts/work-in-motion-sweep.selftest.js against a temp state file (CONV_TREE_STATE_PATH override): ingest shape, double-run zero-event idempotency, gone→concluded, reactivation, failed-category suppression, root discovery, collector fixtures — Verification: mechanical
- [ ] 3. Confirm all existing workstreams-ui selftests stay green — Verification: mechanical

## Files to Modify/Create
- `neural-lace/workstreams-ui/scripts/work-in-motion-sweep.js` — the sweeper (new)
- `neural-lace/workstreams-ui/scripts/work-in-motion-sweep.selftest.js` — the selftest (new)
- `neural-lace/workstreams-ui/config/wim-repos.example.json` — generic per-machine repo-map example (new; harness-hygiene two-layer config — the real wim-repos.json is gitignored)
- `neural-lace/workstreams-ui/config/.gitignore` — ignore the per-machine wim-repos.json
- `docs/plans/workstreams-r7-work-in-motion-2026-06-09.md` — this plan

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The store dedupes appended events by event_id (verified: state/store.js:327-329),
  so deterministic event_ids are a safe second idempotency layer.
- The GUI derives in-flight from an unchecked item with no explicit `state`
  (verified: web/app.js itemState() lines 175-181, applyFilter line 263), and
  shipped-not-deployed from `state==='shipped' && deployed!==true` (lines 232-235).
- Ground truth has no deploy signal, so the sweeper never emits item-deployed.

## Edge Cases
- gh auth failure for a repo's PRs: PR ingestion AND gone-detection for that
  repo's PR category are skipped (a fetch failure must never conclude live work).
- Same branch name in both repos: node id hashes `repoKey|branchName` so the
  ids cannot collide across repos.
- A concluded wim effort reappearing in ground truth: re-opened +
  item-unchecked + item-committed (no item-in-flight event exists in the schema).
- Conclude on a node with an unchecked item is reducer-rejected (FR-7): the
  gone sequence ships the item first, then concludes.

## Acceptance Scenarios
- n/a — acceptance-exempt harness-internal work; the 34-scenario selftest is
  the acceptance artifact.

## Out-of-scope scenarios
- Live-GUI rendering verification of ingested nodes — deferred to the
  orchestrator's post-merge canonical run.

## Testing Strategy
- scripts/work-in-motion-sweep.selftest.js: 34 assertions against a temp state
  file (env-override per state/resolve-state-path.js), including a real temp
  git repo for the branch collector.
- Existing selftests re-run: state/selftest.js (19), state/reconciler.selftest.js
  (33), state/resolve-state-path.js --self-test (6).
- Dry-run of the sweeper against real ground truth with a temp sink confirms
  collectors work end-to-end and that dry-run writes nothing.

## Walking Skeleton
The selftest's T1+T2 pair is the skeleton: one fixture repo through the full
collect→map→emit→re-run path, proving the end-to-end slice (ground truth →
facade events → snapshot shape the UI filters consume → zero-event re-run).

## Decisions Log
### Decision: branch node ids hash repoKey|branchName (not branch name alone)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** `wim-br-<sha1(repoKey + '|' + branchName)[0..11]>`
- **Alternatives:** sha1 of branch name alone (spec'd in the dispatch prompt) —
  collides when the same branch name exists in both repos.
- **Reasoning:** determinism is preserved; cross-repo collision is a real
  hazard (e.g. wip/* conventions shared across repos).
- **Checkpoint:** N/A
- **To reverse:** revert to hashing the bare name; existing nodes would be
  re-ingested under new ids and old ones concluded as gone.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — single-purpose two-file harness plan; behaviors cited in Tasks + Files.
- S2 (Existing-Code-Claim Verification): app.js/store.js line claims verified in-session against the worktree.
- S3 (Cross-Section Consistency): swept — Scope OUT (no canonical run) consistent with Testing Strategy (temp sink only).
- S4 (Numeric-Parameter Sweep): n/a — no numeric parameters.
- S5 (Scope-vs-Analysis Check): swept — all Add/Build verbs target the two IN-scope files.

## Definition of Done
- [ ] All tasks checked off
- [ ] Selftest 34/34 + existing selftests green
- [ ] Branch pushed; orchestrator merges + runs the canonical sweep

## Superseded note (2026-06-10)
Phase plan of the Workstreams consolidation. Its entire scope shipped to master (R2: cbee009+c4a2d55; R7: 433f164) and was verified under docs/plans/archive/workstreams-consolidation-2026-06-08.md — task-verifier 6/6 + end-user-advocate runtime 4/4 PASS (r8 artifact). Closed as SUPERSEDED by that plan's closure rather than duplicating its evidence.
