# Plan: Capture-Codify PR Template — Structural Enforcement of Failure-to-Mechanism Cycle
Status: ACTIVE
Execution Mode: orchestrator
Backlog items absorbed: Capture-codify cycle at PR level

## Goal
Close the single biggest behavioral gap in the harness: the "every failure is a harness opportunity — encode the prevention" discipline is currently verbal, which means it is forgotten under time pressure, skipped on small bug-fix PRs, and invisible to reviewers. Replace the verbal discipline with a structural requirement: every PR must answer the question **"what mechanism would have caught this?"** in its description, and CI blocks the PR if the field is missing or trivially filled. This forces the capture-codify cycle to happen at the moment of fix, not "when I remember to come back to it later."

## Scope

**IN:**
- A `.github/PULL_REQUEST_TEMPLATE.md` in the neural-lace repo with the required "What mechanism would have caught this?" section and three allowed answer forms (existing catalog entry, new entry proposed, accepted residual risk with rationale).
- A GitHub Actions workflow that parses PR descriptions, validates the required field, and fails the check if the field is empty, unfilled-placeholder, or if the "no mechanism" option lacks substantive rationale.
- A local git hook (pre-push or commit-msg) that performs the same validation for PR-targeted branches, so the loop is caught before the push instead of only in CI.
- A rule documentation update in `rules/planning.md` (and mirrored to `~/.claude/rules/planning.md`) describing the convention and linking to the template.
- Rollout to the neural-lace repo as primary target. One downstream project repo as secondary target (user will designate at rollout time — left as a deferred step until designation).

**OUT:**
- Building the failure-mode catalog itself (`docs/failure-modes.md`) — that is the companion plan `failure-mode-catalog` and is a separate scope. This plan references it but does not create it.
- Migrating existing open PRs to conform to the new template.
- Retroactively annotating historical PRs with mechanism analyses.
- Rolling out to all downstream projects at once — one secondary target is enough to prove the pattern; broader rollout is a backlog item after this plan ships.
- Automating catalog entry creation from the PR field (future enhancement; out of scope).

## Tasks

- [ ] 1. Create `.github/PULL_REQUEST_TEMPLATE.md` in the neural-lace repo with the required sections (Summary, What changed and why, **What mechanism would have caught this?** with three explicit answer forms, Testing performed). Placeholder text must be obviously-not-real so the CI scanner can detect un-filled submissions.
- [ ] 2. Write the GitHub Actions workflow at `.github/workflows/pr-template-check.yml` that parses the PR body, locates the mechanism section, and fails the check if: (a) the section is missing, (b) the placeholder text is still present, (c) the "no mechanism — accepted residual risk" option is selected without at least ~40 characters of rationale after the colon. The workflow runs on `pull_request` events with types `opened, edited, synchronize, reopened`.
- [ ] 3. Write a local git hook at `adapters/claude-code/git-hooks/pre-push-pr-template.sh` that performs an equivalent check against the latest commit message body OR an adjacent `.pr-description.md` file, so Claude-assisted work catches the omission before push. The hook must be opt-in per-repo (copied by a rollout script) rather than globally installed, because not all harness-using repos use GitHub PRs.
- [ ] 4. Update `adapters/claude-code/rules/planning.md` with a new section "Capture-codify at PR time" that describes the convention, cites the template, and documents the three allowed answer forms. Mirror the change to `~/.claude/rules/planning.md` per the harness-maintenance rule.
- [ ] 5. Update `adapters/claude-code/docs/harness-architecture.md` (the architecture doc) to record the new template file, the new workflow, and the new git hook in the relevant tables.
- [ ] 6. Add a one-paragraph stub at `docs/failure-modes.md` declaring the file's purpose and linking forward to the companion `failure-mode-catalog` plan. Rationale: the PR template references the catalog (`catalog entry FM-NNN`), so the catalog file must at minimum exist as a stub so the reference doesn't 404 when reviewers click it. Full catalog content is the companion plan's scope.
- [ ] 7. Smoke-test the workflow end-to-end by opening a throwaway PR with (a) an empty mechanism section (expect fail), (b) a filled section citing a catalog entry (expect pass), (c) a "residual risk" answer with only "N/A" (expect fail), (d) a "residual risk" answer with substantive rationale (expect pass). Record the four GitHub Actions run URLs as evidence.
- [ ] 8. Commit the plan file itself in its own commit immediately after creation (satisfies the "commit the plan file immediately" requirement in the dispatch prompt). Subsequent implementation commits reference this plan by path.

## Files to Modify/Create
- `docs/plans/capture-codify-pr-template.md` — this plan file (created in task 8's commit).
- `.github/PULL_REQUEST_TEMPLATE.md` — new file, required PR template with the mechanism field.
- `.github/workflows/pr-template-check.yml` — new workflow, validates the mechanism field on PR events.
- `adapters/claude-code/git-hooks/pre-push-pr-template.sh` — new local hook, equivalent check before push.
- `adapters/claude-code/rules/planning.md` — add "Capture-codify at PR time" section. Mirror to `~/.claude/rules/planning.md`.
- `~/.claude/rules/planning.md` — mirror the rule change per harness-maintenance rule.
- `adapters/claude-code/docs/harness-architecture.md` — record the new artifacts in the architecture tables.
- `docs/failure-modes.md` — stub file, links forward to the companion catalog plan.

## Assumptions

1. **GitHub PRs are the primary delivery surface.** Neural-lace itself uses GitHub PRs as the canonical review gate. Projects using other forges (GitLab, Gitea, bare git) are out of scope for the CI half — the local git hook is their fallback.
2. **The failure-mode catalog plan is a separate, imminent-or-parallel effort.** This plan references `docs/failure-modes.md` and `FM-NNN` IDs as if they exist or will exist. If the catalog plan is deferred indefinitely, the stub file created in task 6 is sufficient to unblock this plan's references.
3. **A PR description is the right level for the enforcement.** Commit messages are too granular (one PR may have 5 commits; repeating the mechanism analysis 5x is noise). The PR description is one per logical unit of change, which matches the granularity of "one fix → one mechanism analysis."
4. **Placeholder-text detection is sufficient to catch the "I forgot to fill it in" failure mode.** A determined actor can paste gibberish to bypass the check; the enforcement assumes good faith and targets forgetful-honest failures, not adversarial bypass.
5. **~40-character rationale threshold is a reasonable floor.** Chosen because "N/A", "none", "skip", and "TBD" are all well under 40 chars, while a genuine one-sentence rationale ("This is a copy-paste typo in a doc file; no mechanism would catch single-char typos in prose without false positives") comfortably clears it. The exact threshold is tunable.
6. **The local git hook is opt-in per-repo.** Claude-assisted work often happens across repos with varying conventions; a globally-installed hook would fire on every push everywhere, which is wrong. Opt-in per-repo via a rollout script is the minimum correct default.

## Edge Cases

- **PR created from a fork by an external contributor.** The workflow still runs on the PR event and can validate the description. No permissions issue because reading the PR body does not require write access.
- **PR description edited after initial creation.** The workflow triggers on `edited` events, so a PR opened empty and filled later still gets validated. The check will flip from fail to pass once the field is populated.
- **Emergency hotfix where the mechanism question is genuinely irrelevant** (e.g., rolling back a bad deploy). The "accepted residual risk" answer form covers this — the rationale field becomes "This is a rollback; the original mechanism analysis belongs on the PR being rolled back, not this one."
- **Sweep PRs that address many small unrelated fixes.** The mechanism analysis may list multiple entries. The template should explicitly allow a bullet list of catalog references, not force a single answer. Validated by the ~40-char threshold applying to the whole section, not per-bullet.
- **PRs that add new features (not fixes).** The mechanism question reframes as "what mechanism would have caught this if it had shipped broken?" — still applicable. The template's section heading should cover both framings.
- **CI flakes / GitHub Actions outage.** If the workflow cannot run, GitHub will not mark the check as failed — it will show as pending. Branch protection rules (if configured) will prevent merge on pending. Acceptable — no silent bypass.
- **Placeholder text evolution.** If the template is updated later (e.g., adding a new answer form), the workflow's placeholder-detection regex must be updated in the same commit. Documented in task 2's acceptance criteria.
- **Local hook false positives on WIP pushes.** A developer pushing a feature branch that is not yet PR-ready should not be blocked. The hook should skip the check when the push target is not a PR-targeted branch pattern (configurable; default: skip for branches ending in `-wip` or containing `scratch`).

## Testing Strategy

- **Task 1 (template):** verify the file exists at the correct path, contains all four required sections, and the placeholder text is obviously-not-real (e.g., `<mechanism answer — replace this bracketed text>`). Grep for `<mechanism` to confirm.
- **Task 2 (workflow):** run the workflow locally via `act` if available, OR trigger it via a throwaway PR (see task 7). Capture the full GitHub Actions run log showing fail-on-empty and pass-on-filled. Evidence must include the run URL and exit code.
- **Task 3 (local hook):** run the hook manually against a staged commit with (a) empty mechanism field (expect exit 1), (b) filled field (expect exit 0). Capture both outputs.
- **Task 4 (rule update):** grep `~/.claude/rules/planning.md` and `adapters/claude-code/rules/planning.md` for the new section heading after the edit. Diff the two files to confirm they match (per harness-maintenance's mirror-verify loop).
- **Task 5 (architecture doc):** grep the architecture doc for the three new file names; all three must be present with one-line descriptions.
- **Task 6 (failure-modes stub):** verify the file exists and contains a forward-link to the companion plan.
- **Task 7 (smoke test):** four throwaway PRs with explicit pass/fail expectations; each PR's check-run URL recorded as evidence. The throwaway PRs are closed without merging after verification.
- **Task 8 (commit discipline):** verify via `git log` that the plan file's creation commit is distinct from any implementation commit, and that implementation commits reference the plan path in their message.

Each task's evidence block will be written by `task-verifier` after the builder runs the relevant verification command; the builder does NOT write evidence directly.

## Decisions Log

[Populated during implementation — see Mid-Build Decision Protocol]

## Definition of Done

- [ ] All tasks 1-8 checked off by `task-verifier`
- [ ] Plan file committed to neural-lace `master` branch
- [ ] PR template file live at `.github/PULL_REQUEST_TEMPLATE.md` in the neural-lace repo root
- [ ] GitHub Actions workflow runs and produces the expected pass/fail verdicts in the smoke test (task 7 evidence attached)
- [ ] Local git hook runs and produces the expected pass/fail verdicts (task 3 evidence attached)
- [ ] `rules/planning.md` updated in both locations (repo + `~/.claude/`) and verified identical
- [ ] Architecture doc updated to list the new artifacts
- [ ] `docs/failure-modes.md` stub exists and forward-links to the catalog plan
- [ ] SCRATCHPAD.md updated with final state and plan status flipped to COMPLETED
- [ ] Completion report appended to this plan file per `templates/completion-report.md`
- [ ] Decision records created for any Tier 2+ decisions surfaced during implementation
- [ ] Rollout to one designated downstream project repo is either completed OR explicitly deferred with a `(deferred from capture-codify-pr-template.md)` backlog entry
