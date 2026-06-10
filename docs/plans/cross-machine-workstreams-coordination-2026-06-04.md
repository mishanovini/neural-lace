# Plan: Cross-machine work-coordination + Workstreams aggregation
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
prd-ref: n/a — harness-development
acceptance-exempt: false
acceptance-exempt-reason: (removed 2026-06-09 — this plan declares Workstreams UI files, a user-facing surface the operator looks at; UI plans may not be exempt per acceptance-scenarios.md. The "GUI functional verification" it promised is exactly what the end-user-advocate runtime gate enforces.)
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
- 2026-06-04: `<personal-account>/workstreams-coordination` (external repo) — added `tasks/task-2026-06-04-*.json`, `claims.json`, and `MACHINE-BOOTSTRAP.md` (proposed Office_PC↔BOOK division + machine bootstrap/safety doc + BOOK startup prompt). Coordination-substrate scope of this plan.
- 2026-06-04 (Task 2): `adapters/claude-code/skills/orchestrator-prime.md` (+ `~/.claude/` mirror) — loop-wired coord-pull (cycle step 0 + cold-spawn hydrate) and coord-push (cycle step 8). This is the correct hook point per the task prompt ("the loop is skill-driven"): coordination sync belongs to the orchestrator-prime cadence, NOT to every code session. Consequently `settings.json.template` (originally listed for SessionStart coord-push wiring) was deliberately NOT modified — every-session coord-pull would wrongly sync coordination state from non-orchestrator sessions.
- 2026-06-04 (Task 2): `docs/harness-architecture.md` — added the coord-push.sh + coord-pull.sh rows to the scripts inventory (build-harness-infrastructure docs-freshness requirement).
- 2026-06-05 (Task 7, single-machine "GUI shows real work"): diagnostic-first investigation found the Task-7 path-resolver premise ALREADY satisfied (gate self-test 29/29; resolvers point at workstreams-ui in canonical + live). The GUI was empty because ZERO decision fences had ever been emitted (audit log: only branch-opened + concluded). Reducer dedup is NOT a render blocker (sessions hidden as provenance → tree renders clean without it). Files touched in this Task-7 slice:
- `neural-lace/workstreams-ui/scripts/surface-pending-asks.js` — new idempotent utility surfacing the orchestrator's pending asks via the same facade+node the gate uses (GUI now shows 3 awaiting / 3 in-flight)
- `neural-lace/workstreams-ui/package.json` — stale name `conversation-tree-ui` → `workstreams-ui`
- `docs/discoveries/2026-06-05-workstreams-ui-empty-was-no-fences-not-path-bug.md` — root-cause write-up
- `docs/plans/cross-machine-workstreams-coordination-2026-06-04.md` — this in-flight scope update entry

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

## Orchestration — wave dispatch (run from a neural-lace-rooted session)
**Why a NL-rooted session:** worktree isolation roots off the launching session's cwd; an org-folder-rooted session (e.g. cwd in a sibling org dir) can't create neural-lace worktrees. Run the orchestrator with `cwd = ~/claude-projects/neural-lace`.

**Discipline (per the orchestrator pattern):** each builder is a worktree-isolated `general-purpose` agent (the `plan-phase-builder` type is not always registered — use `general-purpose` with `isolation: "worktree"`). Builders build + self-test + commit IN THEIR WORKTREE, return a concise verdict + commit SHAs, and **do NOT invoke task-verifier or edit this plan**. After each wave, the orchestrator cherry-picks each builder's commits onto master in task-ID order, runs `task-verifier` per task, then tears the worktree down. Parallelism ceiling ~5.

**Wave 1 — 4 parallel (disjoint files):**
- **Task 2** — `coord-push.sh` + `coord-pull.sh` (`adapters/claude-code/scripts/`) + SessionStart wiring in `settings.json.template`. Design: git-over-SSH + local clone (NOT gh Contents API; NO `gh auth switch`). **Hygiene: never hardcode the personal repo URL in the committed script** — read `COORD_REPO_URL` env → `~/.claude/local/coord-repo-url.txt` → WARN+exit0; clone dir `COORD_CLONE_DIR` → `~/claude-projects/workstreams-coordination`. coord-pull = fetch+reset --hard origin/main; coord-push = write `tree-state/<host>.json` from `…/workstreams-ui/state/tree-state.json` snapshot, commit, push with pull-rebase-on-non-ff (cap 2), throttle 600s. Reuse broadcast-active-session.sh helper patterns. `--self-test` against a TEMP bare repo (never the live one). Sync to `~/.claude/scripts/`.
- **Task 3** — ADR (next free number from `docs/DECISIONS.md`, NOT assumed) + index row. Capture: shared-store coordination; **why a separate PRIVATE repo on the personal account** (NL is public; task/claim/machine data is personal); peer-to-peer; assisted-first. **Hygiene: generic only — no personal username/repo path** ("a private repo on the operator's personal account").
- **Task 4** — `workstreams-ui/state/reconciler.js`: read SHARED claims (configurable path that coord-pull populates; default `~/claude-projects/workstreams-coordination/claims.json`) in addition to local; respect `machine_assigned`; existing lease-expiry + dedup-skip applies (a remote unexpired claim suppresses local spawn). Node test: remote-unexpired-claim suppresses; expired does not.
- **Task 7** — single-machine "GUI shows real work" (see `docs/discoveries/2026-06-03-workstreams-ui-empty-gui-rootcause.md`): (a) `hooks/decision-context-gate.sh` + `decision-context-reply-emit.sh` path resolver → live `workstreams-ui` (so item events land where the GUI reads) + sync to `~/.claude/hooks/`; (b) `state/reducer.js` `branch-opened` → upsert-by-node_id (kills 28+ dup nodes; use `findNode()`); (c) `web/app.js` open-branch in-flight fallback. Extend the reducer test + hook `--self-test`.

**Wave 2 — after Wave 1 cherry-picked (Task 6 shares `app.js` with Task 7):**
- **Task 5** — `adapters/claude-code/scripts/coord-overlap-detect.sh`: flag `tasks/*.json` whose `target` (paths/feature/plan/repo) intersect an in-flight task on another machine. `--self-test`.
- **Task 6** — GUI aggregation: `state/merge-peers.js` (new — union peers' tree-state snapshots by event_id/node_id, origin-tag by hostname); `server/server.js` `safeRead()` merges local + `tree-state/*.json` peers (fallback to local on failure); `web/app.js` origin badge + shared-task-list panel + assignment control.

**Wave 3 — orchestrator-direct (not a builder):**
- **Task 8** — push fixes to NL master; author `~/.claude/local/coord-repo-url.txt` on each machine; reconcile the 5 drift files; SCRATCHPAD update. BOOK inherits via `session-start-auto-install` + then publishes its own tree/claims on its next session.

**Live integration (orchestrator, after the build):** write `~/.claude/local/coord-repo-url.txt` = the real private repo URL; run `coord-push.sh` for real once; confirm the GUI renders + (after BOOK runs) shows both machines.
