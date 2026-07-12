# Plan: Flat-skills → directory-form migration

Status: ACTIVE
Date: 2026-07-12
Owner: builder session (worktree wf_490488a8, branch feat/plan-lifecycle-mechanical-closure)
Discovery: docs/discoveries/2026-06-02-flat-md-skills-not-skill-tool-invocable.md

## Problem

Flat `adapters/claude-code/skills/<name>.md` files do not register as
Skill-tool-invocable; only the directory form `<name>/SKILL.md` does. All 12
in-repo flat skills (plus their live mirrors) are silently non-invocable —
including orchestrator-prime, whose keepalive cold-start depends on the Skill
route. Additionally, `session-start-auto-install.sh` used a NON-recursive
`git ls-tree`, so directory-form skills (e.g. the existing `nl-issue/`
template) were never synced to live `~/.claude/skills/` at all.

## Refutation check (ran first — premise CONFIRMED)

- Live `~/.claude/skills/` dir-form entries (`<product>-doc-reviewer/`,
  `<product>-docs-designer/`, new-project-setup/, find-skills→dir symlink) ALL
  appear in a fresh session's available-skills list.
- All live flat `<name>.md` entries are ABSENT from that list. The one
  apparent exception (grant-local-edit) registers from `~/.claude/commands/
  grant-local-edit.md`, not from skills/ — commands register regardless.
- `nl-issue/SKILL.md` exists in-repo with valid frontmatter but is absent
  from live — proving the auto-installer's non-recursive sync gap.

## Tasks

- [x] 1. Refutation check (above). Verification: mechanical.
- [x] 2. `git mv` all 12 flat skills to `<name>/SKILL.md`, byte-for-byte.
- [x] 3. Fix `session-start-auto-install.sh` skill sync: recursive ls-tree
  with relative paths, nested-path targets/backups, prune stale live flat
  `skills/<name>.md` only when canonical twin is `<name>/SKILL.md` (backup
  first). Extend self-test 13 → 15 scenarios. Verification: `--self-test`.
- [x] 4. `install.sh`: verified NO change needed — `sync_directory()` copies
  recursively and mirrors exactly (rm -rf + recopy), pruning stale flat
  files on full install. Comment-only touch (path reference).
- [x] 5. Update flat-path references in current-state docs/doctrine/agents/
  manifest. Archives, discoveries, decisions, and history files left
  untouched as records.
- [ ] 6. Registration confirmation in a fresh scheduled-context session
  (post-merge; cannot be demonstrated from this worktree — live sync only
  happens after master merge). Discovery stays `status: pending` with a
  note until then.

## Files to Modify/Create

- adapters/claude-code/skills/calibrate.md → adapters/claude-code/skills/calibrate/SKILL.md
- adapters/claude-code/skills/close-plan.md → adapters/claude-code/skills/close-plan/SKILL.md
- adapters/claude-code/skills/coordinate-estate.md → adapters/claude-code/skills/coordinate-estate/SKILL.md
- adapters/claude-code/skills/find-bugs.md → adapters/claude-code/skills/find-bugs/SKILL.md
- adapters/claude-code/skills/grant-local-edit.md → adapters/claude-code/skills/grant-local-edit/SKILL.md
- adapters/claude-code/skills/harness-lesson.md → adapters/claude-code/skills/harness-lesson/SKILL.md
- adapters/claude-code/skills/harness-review.md → adapters/claude-code/skills/harness-review/SKILL.md
- adapters/claude-code/skills/orchestrator-prime.md → adapters/claude-code/skills/orchestrator-prime/SKILL.md
- adapters/claude-code/skills/teaching-moments.md → adapters/claude-code/skills/teaching-moments/SKILL.md
- adapters/claude-code/skills/verbose-plan.md → adapters/claude-code/skills/verbose-plan/SKILL.md
- adapters/claude-code/skills/verify-feature.md → adapters/claude-code/skills/verify-feature/SKILL.md
- adapters/claude-code/skills/why-slipped.md → adapters/claude-code/skills/why-slipped/SKILL.md
- adapters/claude-code/hooks/session-start-auto-install.sh — MODIFY (recursive sync + prune + self-test)
- adapters/claude-code/install.sh — MODIFY (comment-only path reference)
- adapters/claude-code/manifest.json — MODIFY (path reference)
- adapters/claude-code/doctrine/INDEX.md — MODIFY (path reference)
- adapters/claude-code/doctrine/estate-coordination.md — MODIFY (path reference)
- adapters/claude-code/doctrine/estate-coordination-full.md — MODIFY (path reference)
- adapters/claude-code/doctrine/harness-hygiene-full.md — MODIFY (path reference)
- adapters/claude-code/agents/claim-reviewer.md — MODIFY (path reference)
- adapters/claude-code/agents/functionality-verifier.md — MODIFY (path reference)
- adapters/claude-code/hooks/local-edit-gate.sh — MODIFY (comment path reference)
- docs/harness-architecture.md — MODIFY (path reference; matches manifest source)
- docs/best-practices.md — MODIFY (path reference)
- docs/backlog.md — MODIFY (path reference)
- docs/conventions/failure-mode-catalogs.md — MODIFY (path reference)
- docs/guides/existing-project-gap-audit-runbook.md — MODIFY (path reference)
- docs/harness-strategy.md — MODIFY (path reference)
- build-doctrine/doctrine/06-propagation.md — MODIFY (path reference)
- build-doctrine/doctrine/07-knowledge-integration.md — MODIFY (path reference)
- build-doctrine/propagation/README.md — MODIFY (path reference)
- docs/discoveries/2026-06-02-flat-md-skills-not-skill-tool-invocable.md — MODIFY (implementation-log note; status stays pending)
- docs/plans/flat-skills-directory-form-migration.md — CREATE (this plan)

## Assumptions

- Skill-tool name for a directory-form skill defaults to the directory name
  when frontmatter `name:` is absent (relevant to teaching-moments, whose
  frontmatter carries only `description:`; content preserved byte-for-byte
  per dispatch instructions — flagged for follow-up if registration fails).
- Live flat skills `pt-implement.md` / `pt-test.md` exist ONLY live (no repo
  twin) — the prune step never touches them (drift-preserved).

## Edge cases

- Auto-installer prune only fires when BOTH the live flat file and the
  canonical dir-form twin exist; operator-local flat skills are preserved.
- Nested backup paths (`.backup-auto-install-*/skills/<name>/SKILL.md`)
  created via `mkdir -p $(dirname)`.

## Testing strategy

- `session-start-auto-install.sh --self-test`: 15/15 PASS (sandboxed temp
  fixture; scenarios 14 dir-form-skill-installs, 15
  stale-flat-skill-pruned-with-backup are new).
- End-to-end Skill-tool registration in a fresh session is NOT demonstrable
  pre-merge (live sync reads origin/master) — Task 6 tracks it honestly.
