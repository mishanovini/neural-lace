# Plan: Discovery Resolutions — 2026-05-04 Session

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product user. Verification is via per-hook --self-test invocations (5 + 4 scenarios PASS) plus an empirical worktree-isolation test (agentId af323f2b20494375a) that confirmed the option-Q workaround for Discovery #3.
tier: 1
rung: 0
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Goal

Resolve the three pending discoveries surfaced by `discovery-surfacer.sh` at the start of this session, using the discovery-protocol's "auto-apply if reversible" rule. Each is a real harness gap that the surfacer made visible:

1. **Bash sed-based Status flips bypass `plan-lifecycle.sh` auto-archive** — Three plans were stranded in `docs/plans/` past their COMPLETED state.
2. **Pre-existing template-vs-live `settings.json` divergence across 5 hooks** — The harness's claimed enforcement may not match its actual enforcement on this machine.
3. **Agent tool's `isolation: "worktree"` creates worktrees at master HEAD, not feature-branch HEAD** — Parallel-mode dispatch silently broken on every feature branch with commits ahead of master.

User direction (2026-05-04 chat): approve recommendations for #1 (D — document + sweep) and #3 (start with C investigation + ask about parallelism-preserving alternatives); split #2 into B-now (detector) + A-deferred (reconciliation pass deferred to Phase 1d-E with orchestrator-driven research methodology, not user-judgment-cold).

## Scope

- IN:
  - **Discovery #1 resolution:** new SessionStart hook `plan-status-archival-sweep.sh` that scans `docs/plans/*.md` for terminal-Status entries and `git mv`s them to `docs/plans/archive/` (plus sibling `<slug>-evidence.md`). 5-scenario `--self-test`. Wire into both live `~/.claude/settings.json` AND the committed template. Doc note in `rules/planning.md` (new Stage 3.5). Live-fire to archive 3 stranded plans (`document-freshness-system`, `harness-quick-wins-2026-04-22`, `public-release-hardening`).
  - **Discovery #2 partial resolution:** new SessionStart hook `settings-divergence-detector.sh` that diffs template vs live `settings.json` and surfaces hook-entry-count divergence per event type. 4-scenario `--self-test`. Wire into both files.
  - **Discovery #3 resolution:** empirical test of option Q (builder `git checkout -b worker-<id> <feature-branch>` as first action inside worktree). Update `rules/orchestrator-pattern.md` dispatch-prompt template with the mandatory step.
  - Update all three discovery files to `Status: decided`, `auto_applied: true`, with substantive Decision and Implementation log sections.
  - Add `HARNESS-GAP-14` backlog entry for the deferred Discovery #2 reconciliation pass with orchestrator-driven research methodology.
  - Update `.gitignore` to exclude `docs/plans/archive/` paths for pre-sanitization plans, broaden `.claude/state/` (was only `.claude/state/acceptance/`), and add `.claude/worktrees/`.
  - Update `docs/harness-architecture.md` SessionStart inventory to enumerate all default-matcher hooks (was claiming "2 entries" but had 5 chained) plus the new hooks in the Hook Scripts table.
- OUT:
  - **Discovery #2 reconciliation half (option A):** deferred to Phase 1d-E via HARNESS-GAP-14. Per-hook research (git blame, commit log archaeology, author-intent recovery) is genuine future work, not part of this session.
  - Phase 1d-C-4 (C15 comprehension-gate agent): explicitly the next session's work per SCRATCHPAD's hand-off note.
  - Cleanup of pre-existing untracked `adapters/claude-code/rules/url-conventions.md`: out of scope here; carried from a prior session.
  - Cleanup of two locked Agent worktrees in `.claude/worktrees/`: housekeeping clutter, not a blocker; gitignored under this plan's `.gitignore` change so they don't surface in git status.

## Tasks

- [ ] 1. Update Discovery #2 file with split-decision (B now, A deferred); add HARNESS-GAP-14 backlog entry with orchestrator-driven research methodology.
- [ ] 2. Empirically investigate Agent tool worktree primitive (option C) and test option Q (`git checkout -b worker-<id> <feature-branch>` from inside worktree).
- [ ] 3. Update `rules/orchestrator-pattern.md` dispatch-prompt template with option Q as mandatory first action for parallel-mode builders.
- [ ] 4. Implement `plan-status-archival-sweep.sh` SessionStart hook with 5-scenario `--self-test` (including assertion that `git mv` preserves rename tracking).
- [ ] 5. Implement `settings-divergence-detector.sh` SessionStart hook with 4-scenario `--self-test`.
- [ ] 6. Wire both new hooks into live `~/.claude/settings.json` AND `adapters/claude-code/settings.json.template`.
- [ ] 7. Update `rules/planning.md` Plan File Lifecycle section with new Stage 3.5 documenting the sweep + the "use Edit/Write not Bash sed" convention.
- [ ] 8. Live-fire `plan-status-archival-sweep.sh` against the 3 stranded COMPLETED plans; verify archival + `git mv` rename tracking on the tracked plan (`harness-quick-wins-2026-04-22.md`).
- [ ] 9. Mark all three discovery files as `Status: decided`, `auto_applied: true`, with substantive Decision + Implementation log sections.
- [ ] 10. Update `.gitignore` (archive paths for pre-sanitization plans, broader `.claude/state/`, `.claude/worktrees/`).
- [ ] 11. Update `docs/harness-architecture.md` SessionStart inventory + Hook Scripts table for the two new hooks (and the previously-unlisted `discovery-surfacer.sh`).

## Files to Modify/Create

- `adapters/claude-code/hooks/plan-status-archival-sweep.sh` — new SessionStart hook (Discovery #1).
- `adapters/claude-code/hooks/settings-divergence-detector.sh` — new SessionStart hook (Discovery #2 B).
- `adapters/claude-code/rules/orchestrator-pattern.md` — add option Q to parallel-mode dispatch protocol (Discovery #3).
- `adapters/claude-code/rules/planning.md` — add Stage 3.5 to Plan File Lifecycle section (Discovery #1).
- `adapters/claude-code/settings.json.template` — wire both new SessionStart hooks.
- `docs/discoveries/2026-05-04-sed-status-flip-bypasses-plan-lifecycle.md` — mark decided + auto_applied + add Decision and Implementation log.
- `docs/discoveries/2026-05-04-template-vs-live-divergence-across-other-hooks.md` — mark decided + split-decision rationale + Implementation log.
- `docs/discoveries/2026-05-04-worktree-base-points-at-master-not-branch-head.md` — mark decided + empirical Q-result + Implementation log.
- `docs/backlog.md` — add HARNESS-GAP-14 (deferred Discovery #2 reconciliation pass) with orchestrator-driven research methodology.
- `docs/harness-architecture.md` — SessionStart inventory expansion + Hook Scripts table entries for both new hooks plus `discovery-surfacer.sh`.
- `.gitignore` — extend pre-sanitization plan exclusion to archive paths; broaden `.claude/state/`; add `.claude/worktrees/`.
- `docs/plans/harness-quick-wins-2026-04-22.md` — RENAMED by live-fire of new sweep into `docs/plans/archive/harness-quick-wins-2026-04-22.md` (proper `git mv`, rename tracking preserved).

## In-flight scope updates

(no in-flight changes yet)

## Assumptions

- The discovery-protocol's "reversible → auto-apply" rule applies to all three resolutions (each can be undone by reverting one or two commits). User explicitly approved each in chat 2026-05-04.
- The Agent tool's `isolation: "worktree"` parameter has no documented base-branch override. Strong prior (the schema in the runtime system prompt only documents the flag form) but verified empirically before committing to option Q.
- `~/.claude/settings.json` is gitignored on this machine (per-machine live config) and `adapters/claude-code/settings.json.template` is the committed source-of-truth that `install.sh` materializes.
- Pre-existing template-vs-live divergence for the 5 named hooks (`outcome-evidence-gate`, `systems-design-gate`, `no-test-skip-gate`, `automation-mode-gate`, `public-repo-blocker` variants) is real and pre-dates this session — not introduced by Phase 1d-C-2 / 1d-C-3.

## Edge Cases

- **Sweep encounters a plan whose archive twin already exists** — `plan-status-archival-sweep.sh` refuses to overwrite, emits a warning, leaves the active plan in place for maintainer review. Tested in self-test scenario design.
- **Sweep encounters an untracked terminal-status plan** — Falls back to plain `mv` instead of `git mv`. Tested by self-test scenario 5 (untracked-completed).
- **Sweep encounters a tracked plan but `git mv` fails** — Falls back to plain `mv`. Self-test scenario 3 asserts `git mv` succeeds when expected (catches regressions of the original `git -C "$plans_dir/.."` bug that fell through silently).
- **Detector runs on a machine where the neural-lace template path doesn't exist** — Exits silently. Tested by scenarios 1-2 (template-missing, live-missing).
- **Detector runs without `jq` installed** — Surfaces a generic "files differ; jq unavailable" message + manual diff command. Graceful degradation built-in.
- **Worktree-Q hypothesis fails** — `git checkout -b worker-<id> <feature-branch>` errors. Empirical test 2026-05-04 confirmed it works on the live build-doctrine-integration branch (HEAD landed at 866a8d6 from worktree initially at 10adac2).
- **A plan is mid-edit when sweep fires at SessionStart** — Sweep operates on filesystem state at hook time; if Status was just flipped via Bash sed and the next session starts before any further work, the sweep archives the plan. The completion report goes to archive/ either way (whether the user finished writing it before SessionStart or appends to the archived path afterward).

## Acceptance Scenarios

n/a — `acceptance-exempt: true` (harness-development plan; no product user). Verification is via the `--self-test` flags on both new hooks.

## Out-of-scope scenarios

n/a — see acceptance-exempt rationale above.

## Testing Strategy

- **`plan-status-archival-sweep.sh --self-test`** exercises 5 scenarios: no-directory, active-stays, completed-archives (asserts `R` rename in `git diff --cached --name-status`), with-evidence (sibling pair moves), untracked-completed (plain mv fallback). All PASS.
- **`settings-divergence-detector.sh --self-test`** exercises 4 scenarios: template-missing (silent), live-missing (silent), byte-identical (silent), divergent (warning emitted naming the divergent event). All PASS.
- **Discovery #3 empirical test** dispatched a read-only Agent with `isolation: "worktree"` from the orchestrator on `build-doctrine-integration` (commit `866a8d6`, master at `10adac2`). Test confirmed: worktree rooted at `10adac2`, feature branch ref visible in `.git/refs`, `git checkout -b test-worker-q-investigation build-doctrine-integration` succeeded, post-checkout HEAD landed at `866a8d6`, plan files visible. Verdict: option Q is viable. Detailed log in discovery file's Implementation log.
- **Live-fire of new sweep** archived the 3 stranded plans (`document-freshness-system`, `harness-quick-wins-2026-04-22`, `public-release-hardening`) and their evidence siblings. Verified by `ls docs/plans/archive/` + `git status` showing `R` (rename) for the one tracked plan.
- **Live-fire of new detector** confirmed real divergence in production state: `PreToolUse: template=18, live=21`, `SessionStart: template=3, live=2`, `UserPromptSubmit: template=1, live=2`. This is the worklist HARNESS-GAP-14 will consume.

## Walking Skeleton

n/a — no novel UI or end-user surface. The two new hooks ship behind their existing `--self-test` flags.

## Decisions Log

- **Decision: Auto-apply Discovery #1 option D (document + sweep).** Tier 1 (reversible). Status: applied. Reasoning: `plan-lifecycle.sh` is a Mechanism whose post-condition (terminal-Status plans live in archive/) should hold regardless of HOW the flip happened. Documentation alone is fragile (this session itself forgot the convention). User approved 2026-05-04 chat.
- **Decision: Split Discovery #2 into B-now + A-deferred.** Tier 2 (multi-file, but hooks are reversible). Status: applied. Reasoning: detector is mechanical (~30 min); reconciliation is judgment work per hook (~2 hrs) deserving scheduled time + orchestrator-driven research. User pushed back on framing A as "user picks cold," directed orchestrator to do the per-hook git blame + commit log archaeology when 1d-E starts. HARNESS-GAP-14 captures this.
- **Decision: Auto-apply Discovery #3 option Q (builder-checkout-from-feature-branch).** Tier 1 (reversible doc edit). Status: applied. Reasoning: empirical test confirmed option Q works AND preserves parallelism. Options A/D (drop parallelism) rejected because Q works; option B (pre-flight rebase) rejected because Q is simpler; option C (file with Anthropic) unnecessary now that Q works. Reversible: one revert removes the new dispatch-prompt step.

## Pre-Submission Audit

n/a — `Mode: code` plan, single coherent piece of discovery-resolution work. No 5-sweep audit required (Pre-Submission Audit applies to `Mode: design` per `rules/design-mode-planning.md`).

## Definition of Done

- [ ] All 11 tasks checked off via task-verifier evidence.
- [ ] Both new hooks pass their `--self-test` flags (5 + 4 scenarios).
- [ ] Three stranded plans archived; `git status` clean.
- [ ] All three discovery files at `Status: decided`, `auto_applied: true`.
- [ ] HARNESS-GAP-14 committed in `docs/backlog.md`.
- [ ] `harness-architecture.md` updated for both new hooks.
- [ ] All work committed to neural-lace; multi-push covers both remotes.
