# Plan: Cross-machine work-coordination + Workstreams aggregation
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-infrastructure work (coordination scripts + Workstreams UI internals); the acceptance bar is the scripts' --self-tests + the GUI functional verification described in Testing Strategy, not a contractor-facing runtime scenario.
tier: 3
rung: 2
architecture: orchestration
frozen: false

## Goal
Give Misha a shared, cross-machine task list so work running on Office_PC + BOOK-JDM547N8BO can be coordinated: detect redundant/overlapping efforts, dedupe them, decide which machine handles which work, and render both machines' Workstreams trees in one view. Full design + locked decisions in the approved plan `~/.claude/plans/golden-percolating-flamingo.md`.

## User-facing Outcome
Open the Workstreams UI on either machine and see: the merged tree of BOTH machines' work, a shared task list with overlap/redundancy flags, and per-task machine assignment — instead of today's empty "nothing in flight."

## Scope
- IN: the private coordination repo `<personal-account>/workstreams-coordination` (DONE — scaffolded); push/pull scripts; reconciler wiring to shared claims; overlap detection; GUI merge + shared-task-list panel; the single-machine items-pipeline fix + reducer dedup; harness propagation to BOOK.
- OUT: full auto-claiming (assisted-first v1 only); changing the public neural-lace's data exposure; anything requiring a BOOK session (BOOK self-heals on its next run).

## Tasks
- [ ] 1. (DONE) Create private repo `<personal-account>/workstreams-coordination` + scaffold schema (tasks/claims/tree-state + SCHEMA.md). — Verification: mechanical
- [ ] 2. `coord-push.sh` + `coord-pull.sh` (local-clone + git+SSH; NOT gh Contents API → avoids account-switching) + self-tests; live-mirror sync. — Verification: full
- [ ] 3. Author ADR (cross-machine coordination + why a separate private repo). — Verification: mechanical
- [ ] 4. Wire reconciler claim-read/lease to the shared `claims.json`; respect `machine_assigned`. — Verification: full
- [ ] 5. Overlap/redundancy detection over `tasks/*.json` `target` fields. — Verification: full
- [ ] 6. GUI: `safeRead()` merge of local + peers' tree-states (origin-tagged) + shared-task-list panel + assignment control. — Verification: full
- [ ] 7. Single-machine fix: decision-context path resolver → workstreams-ui (items populate); reducer upsert-by-node_id dedup; open-branch in-flight fallback. — Verification: full
- [ ] 8. Propagate to NL master; reconcile the 5 drift files; BOOK self-heals next session. — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/scripts/coord-push.sh`, `coord-pull.sh` — new (Task 2)
- `adapters/claude-code/scripts/coord-overlap-detect.sh` — new (Task 5)
- `adapters/claude-code/settings.json.template` — SessionStart wiring for coord-push (Task 2)
- `neural-lace/workstreams-ui/state/reconciler.js` — shared-claims read/lease (Task 4)
- `neural-lace/workstreams-ui/state/reducer.js` — upsert-by-node_id on branch-opened (Task 7)
- `neural-lace/workstreams-ui/state/merge-peers.js` — new, peer event/snapshot union (Task 6)
- `neural-lace/workstreams-ui/server/server.js` — safeRead() merge injection (Task 6)
- `neural-lace/workstreams-ui/web/app.js` — origin badge + open-branch fallback (Tasks 6/7)
- `adapters/claude-code/hooks/decision-context-gate.sh`, `decision-context-reply-emit.sh` — path resolver → workstreams-ui (Task 7)
- `docs/decisions/051-cross-machine-coordination.md` (+ DECISIONS.md row) — ADR (Task 3)
- (external, DONE) `<personal-account>/workstreams-coordination` repo scaffold

## In-flight scope updates
- 2026-06-04: `neural-lace/workstreams-ui/server/server.js` already received the `Cache-Control: no-cache` static-asset fix this session (root cause of the GUI showing stale code); committed with the build.

## Assumptions
- The personal github.com SSH key has write access to `<personal-account>/workstreams-coordination` (PROVEN — scaffold pushed via SSH).
- The reconciler's existing claim/lease/dedup-skip logic (reconciler.js ~224-260) works unchanged once pointed at a shared `claims.json` (the shape matches).
- BOOK reaches origin/master + runs `session-start-auto-install` on its next session (the propagation mechanism).

## Edge Cases
- Two machines push `tasks/`/`claims.json` near-simultaneously → non-fast-forward; coord-push pull-rebases (last-writer-wins on the blob; assisted-mode tolerates the rare manual dedup).
- Coordination repo unreachable → GUI falls back to local-only tree (non-blocking).
- Expired claims (`now > claimed_at + lease_ttl_min`) are ignored so a crashed machine doesn't hold work hostage.
- Personal vs work gh account: git+SSH avoids account-switching for the coord repo.

## Acceptance Scenarios
n/a — acceptance-exempt (harness-infra; self-tests + the functional GUI verification in Testing Strategy are the bar).

## Out-of-scope scenarios
- Full autonomous claiming (deferred to a later iteration; v1 is assisted).

## Testing Strategy
- coord-push/pull: `--self-test` against a temp git repo (push writes tree-state; pull gets peers; non-ff rebase).
- reconciler: node unit test that a remote unexpired claim suppresses local spawn.
- GUI: restart server, push a peer tree-state, confirm the GUI renders both machines' nodes with origin badges + falls back to local when the repo is unreachable; emit a decision-context fence and confirm an "Awaiting me" item appears (the single-machine functional bar).

## Walking Skeleton
DONE: the private repo + schema + a pushed scaffold is the thinnest end-to-end slice (the shared store exists + is writable). Next thinnest slice: coord-push writes this machine's tree-state to the repo and coord-pull reads it back — proving the round-trip before the GUI/reconciler consume it.

## Pre-Submission Audit
- S1–S5: n/a — Mode: code (build-harness-infrastructure work-shape; the design-mode pre-submission audit applies to Mode: design plans).

## Definition of Done
- [ ] All tasks task-verified
- [ ] coord-push/pull self-tests green; reconciler test green
- [ ] GUI renders merged two-machine view (or local-fallback) + a populated item appears from a fence
- [ ] Fixes on NL master; ADR landed; SCRATCHPAD updated
