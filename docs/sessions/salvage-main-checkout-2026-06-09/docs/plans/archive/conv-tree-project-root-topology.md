# Plan: Conversation Tree — project-root topology + wire auto-extract hook + path-fallback fix
Status: COMPLETED
<!-- Closed 2026-06-04 by stale-ACTIVE-plan cleanup. Verified on master HEAD: migrate-topology-to-project-roots.js + backfill-from-sessions.js + emit path-fallback (CONV_TREE_MAIN_CHECKOUT) + extract-pending wiring (scripts moved to workstreams-ui/ in the conv-tree→workstreams rename). Shipped PR #20 (4e64e6e). Dispatch never ran task-verifier. -->
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: existing
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal conversation-tree tooling; no product end-user. Acceptance = state-lib self-tests pass, migration replays cleanly, and the GUI renders projects-at-top (verified manually against the live :7733 server).
Backlog items absorbed: none

## Goal
Misha's directive: the Conversation Tree must not use dates as root nodes. Dispatch is single-threaded, so per-project chronological order is implicit and date grouping is unnecessary. Projects/repos become the top-level (root) nodes; sessions render directly under their project; subagents under sessions. Also fix two latent bugs surfaced by the auto-update diagnosis: (a) the `conversation-tree-extract-pending.sh` Stop hook was authored but never wired into settings — the reason the tree stopped auto-updating for ordinary sessions; (b) `conversation-tree-emit.sh` has a hardcoded, wrong fallback path (`~/claude-projects/neural-lace/neural-lace/...`; real checkout is `~/dev/Pocket Technician/neural-lace`).

## Scope
- IN:
  - Migrate the existing append-only `tree-state.json` log to project-root topology via appended `re-parented` (proj→null) + `archived` (date-node) events — log preserved, not blown away.
  - Fix `backfill-from-sessions.js` so project nodes are emitted as roots (`parent_id: null`); remove `today-*` date-node creation.
  - Wire `conversation-tree-extract-pending.sh` into the Stop chain AFTER `conversation-tree-emit.sh --on-stop`, in both the live `~/.claude/settings.json` and the committed `settings.json.template`.
  - Make `conversation-tree-emit.sh`'s hardcoded fallback path config-driven (`CONV_TREE_MAIN_CHECKOUT` env var) with a de-doubled generic default; set the env var to the real checkout in live settings.
  - Re-run backfill and verify the GUI renders projects-at-top.
- OUT:
  - No change to the reducer/schema event contract (topology is purely a `parent_id` concern the reducer already handles generically).
  - No GUI `web/app.js` code change UNLESS verification shows incorrect rendering (the renderer already builds a `parent_id` forest and filters archived nodes; expected to be correct post-migration).
  - No change to emit.sh `--on-spawn` / `--on-stop` topology (already emits project-as-root, no date nodes).

## Tasks
- [ ] 1. Write `scripts/migrate-topology-to-project-roots.js` — backs up tree-state.json, appends re-parented(proj→null)+archived(date) events via state.js appendEvent; idempotent; `--dry-run` supported. Verification: mechanical
- [ ] 2. Fix `backfill-from-sessions.js` to emit project nodes as roots (no date node). Verification: mechanical
- [ ] 3. Wire `conversation-tree-extract-pending.sh` into `settings.json.template` Stop chain after `--on-stop`. Verification: mechanical
- [ ] 4. Make emit.sh fallback path config-driven (CONV_TREE_MAIN_CHECKOUT). Verification: mechanical

## Files to Modify/Create
- `neural-lace/conversation-tree-ui/scripts/migrate-topology-to-project-roots.js` — NEW migration script (log-preserving).
- `neural-lace/conversation-tree-ui/scripts/backfill-from-sessions.js` — project nodes become roots; remove date-node creation.
- `adapters/claude-code/hooks/conversation-tree-emit.sh` — config-driven fallback path (lines ~108, ~141).
- `adapters/claude-code/settings.json.template` — wire extract-pending into Stop chain.
- `docs/plans/conv-tree-project-root-topology.md` — this plan.

## In-flight scope updates

## Assumptions
- The reducer (`reducer.js`) already builds topology purely from `branch-opened`/`re-parented` `parent_id` values; no special date-node handling exists, so `re-parented`→null + `archived` of date nodes fully migrates topology. (Verified by reading reducer.js + deriving the snapshot.)
- The GUI (`web/app.js`) already builds a forest from `parent_id` and filters `state==='archived'` nodes when `showArchived` is unchecked (verified at lines 696–708), so projects-as-roots render correctly once data is migrated, with no GUI code change.
- `tree-state.json` is gitignored runtime state (verified via `git check-ignore`); migration + backfill run against the main-checkout's live file, independent of git/worktree.
- The 4 duplicate `proj-*` `branch-opened` events from 2026-05-27 are already rejected by the reducer ("node_id already exists") and stay harmlessly rejected after migration.

## Edge Cases
- Re-running the migration: idempotent via deterministic event_ids (state.js dedups by event_id); a second run appends nothing new.
- A `re-parented` of a proj node whose parent is already null: reducer sets parent_id=null (no-op effect), no rejection.
- Archiving a date node that has no children (after re-parent): reducer sets state=archived; GUI hides it.
- Backfill run with `--since` before/after migration: project `branch-opened parent_id:null` is idempotent (node already exists → rejected harmlessly); new sessions attach under existing project roots.
- emit.sh fallback: only reached when `git rev-parse` fails (cwd outside a repo). Primary git-based resolver continues to work for the real checkout.

## Testing Strategy
- Migration: run `--dry-run` first (shows planned events, no write); then real run against a COPY of tree-state.json; derive snapshot and assert all `proj-*` nodes have `parent_id:null` and date nodes are `archived`; assert zero new rejections beyond the pre-existing 4.
- backfill: `--dry-run` against the migrated state; assert no `today-*` branch-opened emitted and project branches carry `parent_id: null`.
- emit.sh: `bash conversation-tree-emit.sh --self-test` passes; CONV_TREE_MAIN_CHECKOUT override resolves correctly.
- settings template: `node -e` JSON-parse the template; assert extract-pending command present immediately after `--on-stop` in the Stop chain.
- GUI: start server at :7733, load page, confirm roots are the project nodes (Circuit, foresight, neural-lace, etc.), sessions nested under them, no "Today —" roots.
- Auto-update: confirm `~/.claude/logs/conversation-tree-extract-pending.log` records a real (non-self-test) session entry after this session ends.

## Walking Skeleton
The thinnest end-to-end slice: append two `re-parented` events (one proj node → null) + one `archived` (one date node) to a COPY of tree-state.json via state.js, derive the snapshot, and confirm that proj node is now a root and the date node is archived. That proves the migration mechanism end-to-end before scaling to all 6 proj nodes + 2 date nodes.

## Decisions Log

## Definition of Done
- [ ] Migration script written + run against live tree-state.json (backup taken).
- [ ] backfill emits project roots; re-run populates the migrated tree.
- [ ] extract-pending wired in live settings.json + template.
- [ ] emit.sh path fallback config-driven; CONV_TREE_MAIN_CHECKOUT set live.
- [ ] PR merged to master; main checkout synced.
- [ ] GUI verified rendering projects-at-top at :7733.
- [ ] Auto-update confirmed via extract-pending log on next session end.
