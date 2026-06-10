# Plan: Workstreams R2 — land live UI deltas, harvest stranded branches, fix stale-tab modal class
Status: SUPERSEDED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal Workstreams UI infrastructure; self-tests + DOM-mechanical verification on a test port are the acceptance artifact
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Phase R2 of the Workstreams rebuild: reconcile the live 7733 server checkout
into the tracked tree (verified delta: package-lock.json name field only),
audit the six stranded conv-tree/workstreams branches for unharvested content,
and fix the root cause of "item detail fills the right panel instead of opening
a modal" (stale long-lived browser tab running pre-Phase-D JS; SSE keeps data
fresh while code stays frozen at tab-load time).

## User-facing Outcome
The operator's Workstreams GUI tab auto-reloads within 30s whenever the served
UI files change, so a long-lived tab can never again show pre-fix behavior
(panel-filling detail) while the server already serves the modal code.

## Scope
- IN: neural-lace/workstreams-ui/** (web/app.js, web/index.html, web/app.css,
  server/server.js, package-lock.json, selftests); this plan file.
- OUT: the live 7733 server process and the real canonical state file (test
  verification uses port 7734 + a state-file copy); workstreams-coordination
  single-source state design (no tree-state/canonical-path changes); merging
  to master (orchestrator's job).

## Tasks

- [ ] 1. Sync live-checkout delta (package-lock name field) into tracked tree — Verification: mechanical
- [ ] 2. Audit stranded branches (accordion-panels, vertical-redesign, toast-stacking, project-root-topology, workstreams-ui-render, v1.1.2-polish, deterministic-turn-emit) vs master; harvest anything missing — Verification: mechanical
- [ ] 3. Fix stale-tab class: server /api/health exposes ui_build stamp (max mtime of web assets); client pollHealth auto-reloads when stamp changes — Verification: mechanical
- [ ] 4. Run UI selftests + verify modal chain DOM-mechanically against a 7734 test server with a copied state file — Verification: mechanical

## Files to Modify/Create
- `neural-lace/workstreams-ui/package-lock.json` — name-field sync from live checkout
- `neural-lace/workstreams-ui/server/server.js` — /api/health ui_build stamp
- `neural-lace/workstreams-ui/web/app.js` — pollHealth auto-reload on ui_build change
- `neural-lace/workstreams-ui/web/responsive.selftest.js` — selftest coverage for the auto-reload wiring (if needed)
- `docs/plans/workstreams-r2-harvest-2026-06-09.md` — this plan

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The live 7733 checkout (ws-ui-server-stable @ 850277f) stays byte-identical
  to master's tracked tree except package-lock.json (verified by diff -rq at
  plan time).
- server.js serves static files per-request via fs.readFile (verified at
  server/server.js:76-86), so a reload always fetches current code; the only
  staleness vector is the never-reloading open tab.

## Edge Cases
- ui_build stamp missing from an old server's /api/health response: client
  skips the comparison (no reload loop against the old live server).
- Editor saves touching web assets while a tab is open: tab reloads once per
  change within 30s — acceptable, only fires on real mtime change.
- stat failure on a web asset: server omits/nulls the stamp; client skips.

## Acceptance Scenarios
- n/a — acceptance-exempt (harness-internal; selftests + DOM-mechanical check on test port 7734 are the artifact)

## Out-of-scope scenarios
- Live-browser click-through on the operator's real 7733 tab (requires the operator's browser; covered by the auto-reload mechanism itself once the live server restarts)

## Testing Strategy
- state/selftest.js + web/responsive.selftest.js + state/reconciler.selftest.js must pass in the worktree.
- Test server on port 7734 with CONV_TREE_STATE_PATH pointing at a COPY of the canonical state file; curl / and /api/health; grep-verify the click-handler chain (list item click -> openDetailModal -> #detailModal + #detailScrim unhidden).

## Walking Skeleton
n/a — single-purpose harness-infrastructure change per build-harness-infrastructure work-shape.

## Decisions Log
- Auto-reload over cache-busting query strings: the failure class is a tab that
  never re-requests assets at all; only a server-pushed/polled build stamp
  reaches an already-open tab. Reversible (one client + one server hunk).

## Pre-Submission Audit
n/a — Mode: code, single-purpose harness-infrastructure plan.

## Definition of Done
- [ ] All tasks checked off
- [ ] Selftests pass
- [ ] Branch pushed; orchestrator merges

## Superseded note (2026-06-10)
Phase plan of the Workstreams consolidation. Its entire scope shipped to master (R2: cbee009+c4a2d55; R7: 433f164) and was verified under docs/plans/archive/workstreams-consolidation-2026-06-08.md — task-verifier 6/6 + end-user-advocate runtime 4/4 PASS (r8 artifact). Closed as SUPERSEDED by that plan's closure rather than duplicating its evidence.
