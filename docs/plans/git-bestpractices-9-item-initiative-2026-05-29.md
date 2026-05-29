# Plan: Git Best-Practices 9-Item Coordinated Harness Initiative

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: harness-extension
frozen: false
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanisms (scripts, hooks, rules, install-time config); verification is per-artifact `--self-test` PASS + tree-equivalence between PT and personal masters at each merge — no user-facing runtime to advocate for.
Backlog items absorbed: none

## Goal

Ship 7 standard git-best-practice mechanisms (items 1, 2, 3, 6, 7, 8, 9 — items 4 and 5 already in place) as a coordinated initiative. Each item ships as its own PR to PT master, then cherry-picks onto personal master via the new sync script (item 6). The deliverables strengthen the going-forward sync posture (PT canonical, personal mirrored via cherry-pick + non-force direct push) by automating freshness checks, divergence detection, sync mechanics, branch hygiene, and cross-computer coordination.

## Scope

- IN:
  - Item 3 — install.sh sets global `pull.rebase=true` + `rebase.autoStash=true`; documented in CLAUDE.md.
  - Item 6 — `adapters/claude-code/scripts/sync-pt-to-personal.sh` (cherry-pick PT-master commit onto personal, non-force push, tree-equivalence verification).
  - Item 1 — `adapters/claude-code/hooks/session-start-git-freshness.sh` SessionStart hook (fetch + behind-warning).
  - Item 9 — Working-tree-clean check bundled into item 1's hook.
  - Item 2 — Pre-push divergence-detection git hook (refuses push when remote master advanced since last fetch).
  - Item 8 — `adapters/claude-code/rules/branch-hygiene.md` + extension of stale-active-plan-surfacer to surface stale local branches.
  - Item 7 — `adapters/claude-code/scripts/broadcast-active-session.sh` + SessionStart/SessionEnd integration writing/clearing a reserved `harness/active-sessions/<hostname>` branch on PT.

- OUT:
  - Items 4 + 5 (branch protection + linear history) — already in place per Misha's directive.
  - Resolving the existing 12-PT-only / 7-personal-only commit-SHA divergence (pre-existing; trees already equivalent at `89dfd1e4...`; orthogonal to this initiative).
  - The pending fork-sync discovery's Q1-Q6 (Misha tonight's directive effectively resolves Q1 + Q5; remaining questions out of scope here).

## Tasks

- [ ] 1. Item 3 — pull.rebase + rebase.autoStash global defaults (install.sh + CLAUDE.md). — Verification: mechanical
- [ ] 2. Item 6 — sync-pt-to-personal.sh cross-fork sync script (cherry-pick + tree-verify + non-force push). — Verification: mechanical
- [ ] 3. Item 1 — session-start-git-freshness.sh (fetch + behind-warning). — Verification: mechanical
- [ ] 4. Item 9 — bundle: working-tree-clean check into the session-start-git-freshness hook. — Verification: mechanical
- [ ] 5. Item 2 — pre-push divergence-detection git hook. — Verification: mechanical
- [ ] 6. Item 8 — branch-hygiene rule + stale-branch surfacer. — Verification: mechanical
- [ ] 7. Item 7 — active-session broadcast (reserved-branch coordination). — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/install.sh` — item 3: + `set_global_git_default()` helper + invocations; dry-run Phase 4b.
- `adapters/claude-code/CLAUDE.md` — item 3: + "Global git defaults (set by install.sh)" section.
- `adapters/claude-code/scripts/sync-pt-to-personal.sh` — item 6: NEW; cherry-pick PT-master commit onto personal master with `--self-test`.
- `adapters/claude-code/hooks/session-start-git-freshness.sh` — items 1 + 9: NEW; SessionStart hook running fetch + behind-warning + clean-tree check.
- `adapters/claude-code/settings.json.template` — items 1, 7: wire session-start-git-freshness + active-session broadcast hooks.
- `adapters/claude-code/git-hooks/pre-push` (or new dispatch entry) — item 2: pre-push divergence-detection.
- `adapters/claude-code/hooks/pre-push-divergence-check.sh` — item 2: NEW; called by the global pre-push dispatcher.
- `adapters/claude-code/rules/branch-hygiene.md` — item 8: NEW rule.
- `adapters/claude-code/hooks/stale-active-plan-surfacer.sh` — item 8: extend to also surface stale local branches.
- `adapters/claude-code/scripts/broadcast-active-session.sh` — item 7: NEW; writes/clears `harness/active-sessions/<hostname>` reserved branch.
- `docs/harness-architecture.md` — index updates for new hooks/rules/scripts.

## In-flight scope updates

- 2026-05-29: `adapters/claude-code/rules/INDEX.md` — item 8 adds a new rule (`branch-hygiene.md`); the INDEX coverage golden test requires every rule have an INDEX row. Edit is mechanical (one row insertion).

## Assumptions

- PT remains the canonical remote (`origin` in standardized clones).
- Personal remote URL contains the mirror account's owner segment.
- `gh` is authenticated to BOTH accounts (PT account + personal account) on every machine running the harness.
- Cherry-pick + non-force push is durable: each item's PT-master merge cherry-picks cleanly because no concurrent work touches the same files (item-per-PR atomicity).
- Reserved-branch mechanism for item 7 (`harness/active-sessions/*`) does not collide with any existing branch naming convention.

## Edge Cases

- Cherry-pick conflict during sync — script aborts cleanly, reports the conflicting file, exits non-zero (the operator resolves manually).
- Mirror push fails because mirror master advanced since fetch — script reports the non-FF condition (no force-push); operator re-fetches + re-runs.
- gh auth not switched to mirror account — script attempts the push, reports the 403, and recommends `gh auth switch -u <mirror-owner>`.
- Sessions on multiple computers concurrently editing master — item 7's broadcast mechanism surfaces this at SessionStart; item 2's pre-push divergence check catches the actual collision moment.
- Stale broadcast branches (computer crashed without clearing) — operator-driven cleanup is acceptable for v1; automated TTL could land later.

## Testing Strategy

- **Per-item self-test.** Every script and hook ships with a `--self-test` block exercising at least the success path, an error path, and at least one edge-case scenario. Tests run on every PR via the existing "Bash hooks --self-test" + "Standalone test scripts" CI checks.
- **Tree-equivalence verification at sync.** After each PR merges, item 6's script (or the manual procedure pre-item-6) verifies `git rev-parse origin/master^{tree} == git rev-parse personal/master^{tree}` post-sync. Per-item PR report cites the tree hash.
- **Initiative-level eat-own-cooking.** Once item 6 ships, every subsequent PR uses it to sync to personal — this exercises item 6 in production on items 1, 2, 7, 8, 9.

## Walking Skeleton

The skeleton is the per-item ship-and-sync cycle, validated end-to-end on item 3 before item 6 ships:

1. Branch off `origin/master`.
2. Implement + self-test.
3. Push, gh pr create, wait for CI green.
4. Squash-merge to PT master; capture merge SHA.
5. Cherry-pick onto a temp branch from personal/master.
6. Verify tree-equivalence with PT master.
7. Push to personal master (non-force, FF-only).
8. Verify post-push tree-equivalence.

Item 3 walked this skeleton manually (no item 6 script yet); item 6 codifies the cycle as a script; items 1, 2, 7, 8, 9 use the script.

## Decisions Log

### Decision: Build-harness-infrastructure work-shape; no PRD; acceptance-exempt
- **Tier:** 1 (low-blast, harness-internal, reversible)
- **Status:** proceeded with recommendation
- **Chosen:** Plan declares `acceptance-exempt: true` with substantive reason, `prd-ref: n/a — harness-development`, `Mode: code`. No systems-designer review (per work-shape carve-out). Per-task `Verification: mechanical` with self-test artifacts as evidence.
- **Alternatives:** (a) full Mode: design treatment — rejected, no user-observable runtime to design for; (b) per-item separate plans — rejected, the 9-item initiative is one coherent piece of work with shared scope.
- **Reasoning:** Build-doctrine `build-harness-infrastructure` work-shape (`adapters/claude-code/work-shapes/build-harness-infrastructure.md`) explicitly covers this case — every file the plan touches is under `adapters/claude-code/`; "user" is a hook firing at an event boundary; self-tests are the native verification idiom.
- **To reverse:** Set `Status: ABANDONED` on this plan; revert any landed item commits via standard `git revert`.

## Definition of Done

- [ ] All 7 items shipped: PR# + merge SHA on PT + cherry-pick SHA on personal recorded per item.
- [ ] All items' self-tests pass on every PR.
- [ ] Final tree-equivalence check: the two `gh api repos/<canonical-owner>/<repo>/branches/master --jq '.commit.commit.tree.sha'` calls (one per remote URL from `git remote -v`) return identical hashes.
- [ ] `Status: COMPLETED` set + plan auto-archived.
- [ ] SCRATCHPAD.md updated to reflect closed state.
