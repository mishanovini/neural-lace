# Plan: Harness gate fixes — broadcast SSH-alias, decision-context schema-path, acceptance over-scoping, skills-sync
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: harness-internal
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work; self-tests are the acceptance artifact (no user-observable runtime — the "user" is the maintainer running the gates)
Backlog items absorbed: none

## Goal
Fix four harness defects surfaced during the 2026-06-02/03 Office_PC bootstrap, all of which over-fire or misbehave in the real multi-machine / parent-of-projects environment and create the gate friction documented in `docs/backlog.md` (two HARNESS-GAP entries dated 2026-06-02). Net effect: cross-machine broadcast works on SSH-alias-routed remotes; the decision-context gate can validate fences again; the product-acceptance gate stops over-scoping when run from a parent-of-projects cwd; canonical skills auto-sync like hooks/scripts.

## Scope
- IN: the four named fixes, each with a `--self-test` extension proving the fix; sync of canonical → live `~/.claude/`; push to both neural-lace remotes.
- OUT: closing the ~25 downstream-project / 24 neural-lace stale ACTIVE plans (separate cleanup front); pruning Dispatch worktrees (separate front); any product-code change.

## Tasks
- [ ] 1. Broadcast SSH-host-alias URL parsing — add a `git@<alias>:owner/name` arm to `_origin_owner_name()` + self-test case. Verification: mechanical
- [ ] 2. Decision-context schema-path rename-sweep — make `_resolve_schema_module` / `_resolve_state_lib` / tree-state resolver / `_fallback_conv_tree_path` prefer `workstreams-ui` with `conversation-tree-ui` back-compat fallback, across all 4 decision-context-*.sh hooks; verify the gate validates a well-formed fence. Verification: mechanical
- [ ] 3. Product-acceptance over-scoping — gate should consider only plans under the session's own git root (or cwd when non-git), not glob `*/docs/plans` / `*/*/docs/plans` into sibling project checkouts; self-test for the parent-of-projects case. Verification: mechanical
- [ ] 4. Skills auto-sync — extend auto-install `SYNC_SUBDIRS` (and the extension filter) so `skills/` (`.md`) sync master-wins like `hooks`/`scripts`; self-test. Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/scripts/broadcast-active-session.sh` — Task 1 (parser arm + self-test)
- `adapters/claude-code/hooks/decision-context-gate.sh` — Task 2 (path resolvers + self-test)
- `adapters/claude-code/hooks/decision-context-pending-surfacer.sh` — Task 2 (path resolvers)
- `adapters/claude-code/hooks/decision-context-replay.sh` — Task 2 (path resolvers)
- `adapters/claude-code/hooks/decision-context-reply-emit.sh` — Task 2 (path resolvers)
- `adapters/claude-code/hooks/product-acceptance-gate.sh` — Task 3 (scope to own git root + self-test)
- `adapters/claude-code/hooks/session-start-auto-install.sh` — Task 4 (SYNC_SUBDIRS + extension filter + self-test)
- `docs/harness-architecture.md` — doc-freshness if a hook's scope description changes
- `docs/backlog.md` — mark the two HARNESS-GAP entries fixed (already present)

## In-flight scope updates
- (none yet)

## Assumptions
- Canonical `~/claude-projects/neural-lace` is the source of truth; live `~/.claude/` is synced from it (Windows copy, not symlink).
- The `workstreams-ui` rename is the intended new name; `conversation-tree-ui` references are stale and safe to demote to fallback (the schema/state modules now live under `neural-lace/workstreams-ui/state/`).
- Each gate ships a `--self-test`; extending it is the harness's native verification idiom (build-harness-infrastructure work-shape).
- Adding `skills` to SYNC_SUBDIRS is safe because canonical skills carry no legitimate machine-local drift (master-wins, per harness-maintenance.md).

## Edge Cases
- Broadcast: a multi-push `origin` returns the alias URL first; the parser must handle `git@github-pt:Owner/Repo.git` AND keep matching literal `github.com` (strict superset — existing self-test S3 must still pass).
- Decision-context: non-git cwd (parent-of-projects) → git-root resolution returns empty → must fall through to `_fallback_conv_tree_path`, which must also know `workstreams-ui`.
- Acceptance: a genuine single-repo cwd must still find its own ACTIVE plans (don't over-correct into finding none).
- Skills-sync: `.md` files (not `.sh`); the existing `grep '\.sh$'` filter must become subdir-aware so hooks/scripts stay `.sh`-only while skills match `.md`.

## Testing Strategy
- Task 1: `broadcast-active-session.sh --self-test` (add an alias-URL scenario); then live `broadcast-active-session.sh write` from neural-lace must create `harness/active-sessions/Office_PC-` on the PT remote (verify via `gh api`).
- Task 2: `decision-context-gate.sh --self-test`; then confirm a well-formed `::: decision` fence validates (no block) from within the neural-lace git root.
- Task 3: `product-acceptance-gate.sh --self-test` (add a parent-of-projects scenario).
- Task 4: `session-start-auto-install.sh --self-test` (add a skills-sync scenario).

## Walking Skeleton
Task 1 is the thinnest end-to-end slice: parser arm → self-test green → live `write` → branch appears on PT remote. It proves the whole fix→test→commit→push→sync→verify loop before the larger rename-sweep.

## Decisions Log
- 2026-06-03: Work directly on neural-lace `master` (pre-customer harness repo; git.md permits). Commit incrementally per task; push to both remotes; sync live after each. Rationale: auto-install reads `origin/master`, so master is the propagation source — fixes only help other machines (and this session, via live sync) once on master.

## Definition of Done
- [ ] All 4 tasks' self-tests pass
- [ ] Live `~/.claude/` synced byte-identical (modulo CRLF) for each changed file
- [ ] Pushed to both neural-lace remotes
- [ ] Broadcast verified writing to the PT remote
- [ ] `docs/backlog.md` HARNESS-GAP entries marked fixed
- [ ] Status flipped to COMPLETED (auto-archives)
