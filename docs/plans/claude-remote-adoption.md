# Plan: Adopt `claude --remote` + Harness Portability to Cloud Sessions
Status: ACTIVE
Execution Mode: orchestrator
Backlog items absorbed: Adopt claude --remote + dotfiles sync as official background-work pattern, Harness portability to claude --remote cloud sessions

## Goal

Establish an official decision tree for when to use interactive local Claude Code vs git-worktree parallel sessions vs `claude --remote` cloud sessions vs `/schedule` recurring jobs — and solve harness portability to cloud sessions so the same enforcement rules apply regardless of where a session runs.

The triggering pain: running multiple Claude Code sessions concurrently on one local filesystem has caused recurring data loss, because sibling sessions issue `git stash -u` and `git clean -fd` against the shared working tree and wipe uncommitted files authored by other sessions. Anthropic's documented answers are (a) `claude --remote` for autonomous cloud sessions with per-invocation isolated sandboxes, and (b) git worktrees for parallel local sessions (the Desktop app's "+ New session" button handles this automatically). Neither is adopted as a harness standard yet, and neither has a documented harness-portability story.

This plan investigates the current mechanics, picks a cloud-portability approach based on evidence from that investigation, writes the decision tree into a new rule file, updates `CLAUDE.md` to point at it, and implements the chosen approach.

## Scope

- IN:
  - Empirical testing of `claude --remote` mechanics (clone behavior, `/tasks` monitoring surface, config inheritance)
  - Empirical testing of Desktop app "+ New session" worktree behavior
  - Inventory of which harness components (hooks, rules, agents, skills) a cloud session would be missing by default
  - Writing `rules/automation-modes.md` — the decision tree covering interactive local / parallel local / cloud remote / scheduled recurring
  - Updating the top-level `CLAUDE.md` to reference `automation-modes.md` in a new "Choosing a Session Mode" section
  - Updating `docs/claude-code-quality-strategy.md` with the final cloud-sync answer based on Phase A findings
  - Implementing one of three harness-portability approaches (A = commit critical harness into project `.claude/`; B = cloud-session startup script that clones neural-lace and runs `install.sh`; C = scoped harness-less cloud sessions for a restricted task class)
  - Mirroring the final state into `adapters/claude-code/` so the harness repo ships the new rule and any supporting assets
- OUT:
  - Building the synthetic-session harness test runner (separate P0 backlog item — `harness-tests-itself`)
  - Solving verbal-vaporware post-message verification (separate residual gap)
  - Making `~/.claude/` itself a git repo or changing how the local install pipeline works — this plan takes the existing install mechanism as given
  - Per-project overrides or audience-specific cloud-session behavior — the rule is harness-global
  - Replacing any existing enforcement hook; this plan extends coverage to cloud sessions, it does not weaken local enforcement

## Tasks

- [ ] 1. **Test `claude --remote` in isolation.** Launch a cloud session against a trivial test repo. Record: how the repo is cloned (git URL + branch? upload? archive?), whether the sandbox sees `.claude/` from the repo root, what `/tasks` monitoring surface looks like, what happens when the session finishes (commits pushed back? PR opened? artifacts returned?). Save evidence to `docs/plans/claude-remote-adoption-evidence.md`. Parallelizable with Task 2.
- [ ] 2. **Test Desktop app "+ New session" behavior.** Create two concurrent sessions on a local project. Observe whether the second session creates a git worktree, what the worktree path is, how commits from the worktree land on the main branch, and whether the two sessions see each other's uncommitted state. Document findings in the same evidence file. Parallelizable with Task 1.
- [ ] 3. **Verify config inheritance for cloud sessions.** With the test cloud session from Task 1, confirm (a) whether a repo-level `.claude/` directory is read and its hooks executed, (b) whether `~/.claude/` contents travel with the session or are absent, (c) what `settings.json` the cloud session uses, and (d) whether any environment-based config (e.g. `CLAUDE_CONFIG_DIR`) is honored. Depends on Task 1.
- [ ] 4. **Identify missing-in-cloud harness components.** From Task 3 findings, produce a list of every hook, rule, agent, skill, and template currently in `~/.claude/` that a cloud session would NOT have by default. Cross-reference against `~/.claude/docs/harness-architecture.md`. Depends on Task 3.
- [ ] 5. **Pick the harness-in-cloud approach (A vs B vs C).** Candidates: **A** — commit critical harness config into the project's own `.claude/` directory so cloud sessions inherit it automatically via the repo clone; **B** — script harness sync via a postCreateCommand (devcontainer-style) or equivalent startup hook that clones `neural-lace` and runs `install.sh` inside the cloud sandbox at session start; **C** — accept harness-less cloud sessions for a restricted task class (e.g. only well-scoped mechanical work that doesn't need plan-edit-validator or the TDD gate) and gate cloud-session usage on task shape. The choice is explicitly deferred until after Phase A completes — record the picked option plus rejection reasons for the other two as a Tier 2 decision record at `docs/decisions/NNN-claude-remote-harness-approach.md`. Depends on Tasks 1-4.
- [ ] 6. **Write `~/.claude/rules/automation-modes.md`.** The decision tree: interactive work → local Claude Code with IDE; parallel local autonomous work → git worktrees via Desktop "+ New session"; unattended autonomous background work → `claude --remote`; recurring work → `/schedule`. Each branch has: when to use, concrete examples, how to invoke, tradeoffs, and what harness enforcement is available in that mode (based on Task 5's decision). Depends on Task 5.
- [ ] 7. **Update `CLAUDE.md` with "Choosing a Session Mode" section.** Insert a new short section near the top of `~/.claude/CLAUDE.md` that points at `rules/automation-modes.md` and summarizes the four-mode decision in three lines. Depends on Task 6.
- [ ] 8. **Update `docs/claude-code-quality-strategy.md` with the final cloud-sync answer.** The strategy doc currently calls out cloud-session harness-portability as an open caveat. Replace the caveat with a paragraph pointing at the picked approach and linking to the decision record from Task 5. Depends on Task 5.
- [ ] 9. **Implement the chosen approach from Task 5.** For A: identify which harness files get project-level copies, document how they stay in sync with `~/.claude/` (manual sync? install-time copy? a new hook that warns on drift?), and set it up on one reference project. For B: write the cloud-session startup script (location, invocation, idempotency, failure behavior if `neural-lace` can't be cloned) and document how to enable it. For C: write the explicit restricted-task-class definition, the gating check (how the user or dispatcher knows a task qualifies), and what happens if a cloud session attempts unsupported work. Depends on Task 5.
- [ ] 10. **Mirror all changes to `adapters/claude-code/`.** Copy `CLAUDE.md`, `rules/automation-modes.md`, the new decision record, any new scripts from Task 9, and the updated strategy doc into `~/claude-projects/neural-lace/adapters/claude-code/` per `rules/harness-maintenance.md`. Run the diff-verification loop from that rule file to confirm nothing was missed. Depends on Tasks 6-9.

## Files to Modify/Create

- `~/.claude/rules/automation-modes.md` — new rule file: the four-mode decision tree (interactive / parallel local / cloud remote / scheduled)
- `~/.claude/CLAUDE.md` — new "Choosing a Session Mode" section pointing at `automation-modes.md`
- `~/claude-projects/neural-lace/docs/claude-code-quality-strategy.md` — replace the cloud-caveat paragraph with the picked approach
- `~/claude-projects/neural-lace/docs/decisions/NNN-claude-remote-harness-approach.md` — Tier 2 decision record documenting the A-vs-B-vs-C choice and the rejected alternatives
- `~/claude-projects/neural-lace/docs/plans/claude-remote-adoption-evidence.md` — evidence notes from Phase A investigation (raw observations, command outputs, screenshots if needed)
- `~/claude-projects/neural-lace/adapters/claude-code/rules/automation-modes.md` — mirror of the new rule
- `~/claude-projects/neural-lace/adapters/claude-code/CLAUDE.md` — mirror of the updated top-level CLAUDE.md (if it ships one)
- Additional files depend on which of A/B/C wins — Task 9 may add: project `.claude/` templates (A), a `scripts/cloud-session-startup.sh` or equivalent plus `install.sh` changes (B), or a `rules/cloud-session-scope.md` restricted-task definition (C)
- `~/claude-projects/neural-lace/docs/backlog.md` — the two absorbed backlog items are removed from the open sections in the same commit that creates this plan file (per `rules/planning.md` backlog absorption protocol)

## Assumptions

1. `claude --remote` is generally available on the user's account and supports the documented `/tasks` monitoring surface — if not, Phase A will surface the gap and Task 5 will pick approach C (accept the limitation) while the plan records the blocker.
2. The Desktop app's "+ New session" button does in fact create git worktrees under the hood — if it instead shares the working tree, Task 2 will document the contradiction and the "parallel local autonomous" branch of the decision tree will shift from worktrees to "don't run parallel locally at all".
3. The harness repo `neural-lace` is network-reachable from a cloud Claude session — this matters for approach B. If cloud sessions have restricted outbound network access, B is ruled out regardless of investigation.
4. The user's local `~/.claude/` can legitimately be treated as "not portable" — i.e. we are solving for how cloud sessions get harness-equivalent enforcement, not for how cloud sessions literally mount the user's home directory.
5. The restricted task class in approach C, if picked, is narrow enough to be useful — if the only cloud-safe work is "things that need no enforcement", approach C collapses into "don't use cloud sessions" and the investigation should fall back to A or B.
6. Implementation (Task 9) fits inside a single follow-up phase — if the chosen approach turns out to need its own multi-week build (e.g. approach B requires a full devcontainer toolchain), Task 9 becomes a stub that opens a new plan rather than attempting the full build here.

## Edge Cases

- **Cloud session's `.claude/` cannot find `$HOME/.claude/local/`.** The harness reads personal config from `~/.claude/local/` at runtime. A cloud sandbox has no such directory. Every hook must handle missing-local-layer gracefully (it already does per `harness-hygiene.md` two-layer architecture, but this plan verifies).
- **Two concurrent cloud sessions on the same repo.** Each is sandboxed and gets its own clone, so the local-session collision problem doesn't reappear. But if both push to the same branch, git-level conflicts still happen. The decision tree must note this.
- **A worktree-based local session deletes its worktree while still running.** Undefined behavior; the plan documents this as "don't" rather than attempting to handle it.
- **The user runs `claude --remote` from a working tree that has uncommitted local changes.** If the remote session clones from origin/master, those local changes don't travel. Could be surprising. The rule must note: commit before dispatching, or use `/schedule` against a pushed branch.
- **Cloud session fails mid-run and leaves a PR or branch in an unclear state.** The `/tasks` monitoring surface should show this, but the rule must tell the user where to look.
- **Approach A ships harness copies that go stale vs `~/.claude/`.** If Task 9 picks A, the sync story must address drift — either a pre-commit hook in each project that warns, or a scheduled sync, or explicit "you MUST re-copy after harness updates" documentation.
- **Approach B's startup script fails because `neural-lace` is private.** The sandbox needs a credential. Task 9 must address auth — a PAT in a secret, a public mirror, or deploy-key setup.
- **Approach C's gating check gets bypassed.** If the rule says "only mechanical work in cloud sessions" but there's no mechanical enforcement, users will cloud-dispatch things that need the TDD gate and ship vaporware. Task 9 must propose a gating mechanism or honestly document that C is pattern-only.

## Testing Strategy

- **Task 1 + 2 + 3:** empirical — the evidence file is the test artifact. A task-verifier run should confirm the evidence file exists, contains concrete observations (commands run + outputs captured, not just prose), and covers all the questions listed in each task's description.
- **Task 4:** cross-reference check — task-verifier greps `~/.claude/docs/harness-architecture.md` and confirms every listed component is classified in the missing-in-cloud list as either "present by default" or "missing + matters" or "missing + doesn't matter".
- **Task 5:** decision record audit — task-verifier confirms the decision record exists at the expected path, lists all three alternatives with reject reasons, and references the Phase A evidence file. Tier 2 decision, so the record is mandatory per `rules/planning.md`.
- **Task 6:** rule file structure — task-verifier confirms `rules/automation-modes.md` has sections for each of the four modes, each with invocation example + tradeoffs, and that `harness-architecture.md` is updated to list the new file.
- **Task 7:** grep-based — `~/.claude/CLAUDE.md` must contain a `Choosing a Session Mode` section referencing `rules/automation-modes.md`.
- **Task 8:** grep-based — the strategy doc's open-caveat paragraph is replaced, not merely appended-to, and the replacement text references the decision record from Task 5.
- **Task 9:** varies by approach. A: confirm project-level `.claude/` templates exist and an example project has been set up end-to-end. B: confirm the startup script exists, is idempotent, and the install.sh integration point is documented; run it once against a test cloud session and verify harness hooks fire. C: confirm the restricted-task-class rule exists, has concrete examples of in-scope vs out-of-scope work, and documents the gating mechanism honestly (enforcement-backed or pattern-only).
- **Task 10:** the diff-verification loop from `rules/harness-maintenance.md`. If it outputs any line, Task 10 fails.
- **No runtime spec required for this plan** because it is primarily a documentation + decision plan — the runtime component of Task 9 (for approach B specifically) has its own verification spec defined within that task. The `plan-reviewer.sh` check should accept this since the plan's main output is rules, docs, and a decision record, not a runtime feature.

## Decisions Log

_(populated during implementation — see Mid-Build Decision Protocol in `rules/planning.md`)_

## Definition of Done

- [ ] All 10 tasks checked off (by task-verifier, not self-reported)
- [ ] Phase A evidence file exists with concrete observations for Tasks 1-4
- [ ] Decision record `docs/decisions/NNN-claude-remote-harness-approach.md` committed alongside the Task 5 commit
- [ ] `rules/automation-modes.md` exists in both `~/.claude/rules/` and `adapters/claude-code/rules/` and the two copies are byte-identical per the maintenance-rule diff loop
- [ ] `~/.claude/CLAUDE.md` has the "Choosing a Session Mode" section
- [ ] `docs/claude-code-quality-strategy.md` no longer calls cloud-session portability an open caveat — it points at the picked approach
- [ ] `docs/harness-architecture.md` lists `rules/automation-modes.md`
- [ ] The two absorbed backlog items are removed from `docs/backlog.md` open sections as of the plan's creation commit
- [ ] SCRATCHPAD.md updated with plan completion state
- [ ] Completion report appended to this plan file per `templates/completion-report.md`, including the "Backlog items shipped" subsection listing both absorbed entries with their final status (built with commit SHA, or deferred/abandoned with reason + backlog-return marker)
