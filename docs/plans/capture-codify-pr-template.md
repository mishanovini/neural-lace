# Plan: Capture-Codify PR Template — Structural Enforcement of Failure-to-Mechanism Cycle
Status: ACTIVE
Execution Mode: orchestrator
Mode: design
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
- [ ] `systems-designer` PASS verdict on this plan (required before implementation per design-mode protocol)

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)

**Within 30 days of rollout to neural-lace, every fix-PR merged to master has a non-empty, non-placeholder mechanism field. Within 90 days, the failure-mode catalog (`docs/failure-modes.md`) has grown by at least 5 entries derived from real PR mechanism analyses.** Measurable via `gh pr list --state merged --limit 50 --search "merged:>2026-04-23"` then sampling the body text for the mechanism section. Failure mode for the outcome: PRs accumulate filled-but-trivial mechanism answers ("N/A" rotation), producing the appearance of compliance without the substance. Mitigated by the ~40-character substantive-rationale floor (Task 2's CI check).

Secondary outcome: the time from "I just fixed a bug" to "the harness has a mechanism that would catch it next time" drops from days/weeks (current — depends on retrospective discipline) to same-PR (the mechanism analysis happens in the PR body before merge). The capture-codify cycle becomes structurally synchronous with fix shipping rather than asynchronously deferred.

### 2. End-to-end trace with a concrete example

Consider a future fix-PR: "Fix: pre-commit-tdd-gate.sh allowed a 12-line file with a single trivial-assertion test."

- **T=0**: Developer (or autonomous Claude session) opens PR #N against neural-lace master. PR body is auto-populated from `.github/PULL_REQUEST_TEMPLATE.md` with sections: Summary, What changed and why, **What mechanism would have caught this?** (with three answer-form options), Testing performed.
- **T=1**: Developer fills the mechanism section with answer form (a): "Existing catalog entry FM-007 (trivial-assertion bypass). The current Layer 4 check counts assertion-with-string-literal patterns, but missed `expect(true).toBe(true)` because it counted the literal `true` as a property access, not an assertion. Tightened the regex to also detect bare-identifier assertions."
- **T=2**: PR is opened. GitHub Actions workflow `pr-template-check.yml` triggers on `opened` event. Workflow checks out repo, reads `${{ github.event.pull_request.body }}`, locates the mechanism section heading via regex, extracts the content, validates: (a) section present (yes), (b) placeholder text absent (yes — no `<mechanism answer — replace this bracketed text>` pattern), (c) if "no mechanism" option, then ≥40 chars rationale (n/a — option (a) selected). All pass. Workflow exits 0; check shows green.
- **T=3**: Developer pushes a fixup commit, edits PR body to clarify wording. Workflow re-fires on `synchronize` + `edited` events. Re-validates. Still passes.
- **T=4**: PR merges to master via `gh pr merge --squash`. The merge commit message includes the PR body's mechanism analysis text by default (squash convention). Future grep for "FM-007" finds both the catalog entry AND this commit, providing traceability.

**Divergent trace — empty mechanism section.** At T=1, developer forgets to fill it in. At T=2, workflow runs, finds the placeholder text `<mechanism answer — replace this bracketed text>` still present. Workflow exits 1 with stderr: "PR body is missing the 'What mechanism would have caught this?' section content. Edit the PR description and try again." Check shows red. Branch protection rule (if configured) blocks merge until the check passes.

**Divergent trace — fork PR from external contributor.** Workflow runs on `pull_request` event, which fires for fork PRs too. GitHub Actions handles fork PRs with a restricted permissions model — `GITHUB_TOKEN` for fork PRs has read-only repo access, which is sufficient to read the PR body. No special handling needed.

### 3. Interface contracts between components

| Producer | Consumer | Contract |
|---|---|---|
| `.github/PULL_REQUEST_TEMPLATE.md` | GitHub PR creation flow | UTF-8 Markdown, valid frontmatter optional. GitHub auto-populates the PR body with this template's content on PR open. Sections must be Markdown headings (`##`) so the workflow's regex can locate them by text match. Placeholder text must be obviously-not-real (e.g., bracketed lowercase prose) so the workflow can detect un-filled state. |
| `.github/workflows/pr-template-check.yml` | GitHub Actions runner | Standard YAML workflow. Triggered on `pull_request` event types `[opened, edited, synchronize, reopened]`. Reads `${{ github.event.pull_request.body }}`. Exits 0 (pass) or non-zero (fail). Failure surfaces as a red check on the PR. Timeout: 60s (should run in <5s — just regex matching). |
| `adapters/claude-code/git-hooks/pre-push-pr-template.sh` | Local git pre-push hook | Bash script. Reads either `.pr-description.md` (if present) or the latest commit message body. Same validation logic as the workflow. Exits 0 to allow push, non-zero to block with stderr message. Idempotent: rerun-able with no side effects. |
| Validation logic | PR body content | Inputs: PR body string (≤ 65536 chars, GitHub limit). Outputs: pass/fail verdict + diagnostic message. Detects: (a) section heading present, (b) placeholder text absent, (c) if "no mechanism — accepted residual risk" answer form selected, ≥40 chars after the colon. |
| Workflow | Branch protection rule | Workflow's check name is `pr-template-check`. Branch protection rule (if configured) requires this check to pass before merge. Configuration is per-repo and out-of-scope for this plan; documented in rule update for opt-in. |
| `rules/planning.md` (updated) | Future plan authors | Adds "Capture-codify at PR time" section explaining the convention, the three answer forms, and the rationale. Discoverable via the rule file index in `CLAUDE.md`. |

### 4. Environment & execution context

**GitHub Actions workflow runs on:** Ubuntu-latest runner. Pre-installed: standard CI tools (bash, jq, git, curl, grep). `${{ github.event.pull_request.body }}` is provided in the trigger context; no API call needed. `GITHUB_TOKEN` is auto-provisioned with default permissions (`pull-requests: read` is sufficient for this workflow). VM destroyed at job end; no persistent state needed.

**Local pre-push hook runs on:** developer's local machine (varied OS — macOS, Linux, Windows-with-Git-Bash). Working directory is the repo root. Has access to `git log -1 --format=%B` for the latest commit message and `cat .pr-description.md` for an alternative description-source convention. Bash 3+ assumed. No network access needed.

**Persistence:** None. All inputs are read-on-demand; no caching.

**Cross-environment behavior:** workflow result is the source of truth (CI is canonical). Local hook is a pre-push convenience to catch mistakes before they reach CI; it can be skipped (`git push --no-verify`) for legitimate WIP pushes — branch protection still gates merge.

### 5. Authentication & authorization map

- **GitHub Actions workflow → GitHub API**: uses `GITHUB_TOKEN` (auto-provisioned, scoped to repo, read-only by default). Permissions needed: `pull-requests: read` (for body text — included in event context anyway), `checks: write` (to set the check status). Both are default for `pull_request` workflows.
- **Local pre-push hook → file system**: reads `.pr-description.md` and runs `git log` against local repo. No external auth.
- **Branch protection rule → workflow check**: managed by GitHub repo admin; out-of-scope for this plan but documented for opt-in.

No new tokens or secrets introduced. Rate limit is GitHub Actions' standard 2000 requests/hour per repo (way over what this workflow consumes). No rate-limit concerns.

### 6. Observability plan (built before the feature)

**Per-PR signals:**
- Workflow check status visible on the PR page (green/red).
- Workflow log accessible via `gh pr checks <PR>` or the GitHub UI.
- On failure, workflow stderr names the specific deficiency (missing section / placeholder present / insufficient rationale).
- Local hook stderr explains the same on push attempt.

**Cross-PR aggregation (for outcome measurement):**
- `gh pr list --state merged --limit 50 --json body,number` returns recent merged PRs with body text.
- A simple grep against this output measures the % of PRs with a non-empty mechanism section.
- Catalog growth measured by `git log --oneline docs/failure-modes.md | wc -l` over time.

**Observability gaps (acknowledged):**
- No automatic tracking of "this PR cited FM-NNN, did the cited entry actually exist?" — reviewer responsibility for now.
- No tracking of "answer form (a) vs (b) vs (c) distribution" — could be added later via a script over PR bodies.

### 7. Failure-mode analysis per step

| Step | Failure mode | Observable symptom | Recovery / retry | Escalation |
|---|---|---|---|---|
| PR template autopopulation | GitHub doesn't autopopulate body (rare; happens if user uses an API client that bypasses templates) | PR body is whatever the user wrote, no template structure | Workflow detects missing section heading, fails with clear message | User edits PR body to include the template structure |
| Workflow trigger | Workflow doesn't run (GitHub outage, malformed YAML) | No check appears on the PR | Re-trigger via a dummy commit; check GitHub status page | If chronic, surface as a known issue in the runbook |
| Workflow regex | Regex falsely matches placeholder pattern in valid content (e.g., user writes `<mechanism answer goes here>` literally as part of explanation) | False fail | Edit the PR body to phrase differently | Tighten regex if pattern recurs |
| Workflow regex | Regex misses an actual placeholder (variant phrasing) | False pass | Reviewer catches in code review | Add the missed pattern to the regex; ship a hook update |
| Workflow rationale check | "No mechanism" answer with 39-char rationale (just under threshold) | Workflow fails with "rationale too short" | User extends to ≥40 chars | Threshold tuning if false-positive rate is high |
| Workflow exit code | Workflow exits 0 despite failure (bug in workflow logic) | Bad PR slips through | Catch via post-merge audit; fix workflow | Self-test with known-bad inputs |
| Local hook | Hook doesn't fire (not installed, opt-out) | Bad push reaches origin | CI check still catches at PR open | Local hook is a convenience; CI is canonical |
| Local hook | Hook false-positive blocks legitimate push (e.g., WIP commit) | Push rejected | User uses `--no-verify` for WIP pushes | Document the WIP-skip pattern; consider auto-skip for `wip-` branches |
| Branch protection rule | Not configured on the repo | Bad PRs can merge despite check failing | Reviewer must enforce manually | Document in setup instructions; recommend repo admins enable |
| External contributor PR | Workflow has reduced permissions on fork PRs | May not be able to write checks back | Verify GitHub Actions defaults — body-read is sufficient; check writes work for forks too in standard config | Document any limitations |
| Sweep PR with multiple fixes | Single mechanism field can't cover 5 unrelated fixes coherently | User writes a multi-bullet list | Workflow accepts (≥40 chars total) | Document multi-bullet pattern in the template |
| Emergency hotfix | Mechanism analysis is genuinely n/a (rollback) | User selects "no mechanism — accepted residual risk" + writes "Rollback; mechanism analysis lives on the rolled-back PR" | PASS (>40 chars) | Normal flow |
| Workflow YAML breaks on update | Plan #3 update breaks the workflow | Workflow check shows error, not pass/fail | Revert the update; fix; redeploy | Test workflow changes in a draft PR first |
| Placeholder text drift | Future template revision changes placeholder text without updating regex | Workflow's placeholder-detect stops working | False-pass on un-filled PRs | Self-test catches this; require updating both files atomically |

### 8. Idempotency & restart semantics

- **Workflow re-run on edited PR** is fully idempotent. Re-fires on `edited` event, re-validates current body, sets check status. No state from prior runs is consulted.
- **Manual re-run via `gh workflow run`** also idempotent — same input (PR body), same verdict.
- **Local hook re-run** is read-only on file system; no side effects. Run-many-times-safely.
- **Workflow partial completion** (runner crash mid-execution) — GitHub auto-retries failed jobs once; if both fail, check shows error (yellow) and merge is blocked pending resolution.
- **Hook installation** (rollout script) is idempotent — installing twice has no effect; uninstalling and reinstalling matches install-once.

There's no "intermediate state" to recover from because the workflow is stateless — the only outputs are the check status and stderr message, both of which are tied to the workflow run instance, not persistent state.

### 9. Load / capacity model

- **Workflow runs per day**: bounded by PR open/edit/synchronize event count. neural-lace currently sees ~5-10 PRs per active day; workflow runs ~3-5x per PR (open + ~2-4 edits/syncs). Total: ~25-50 workflow runs per day at current pace. Negligible against GitHub Actions' free-tier 2000 minutes/month.
- **Per-run resource cost**: <30s wall-clock; <5s of CPU; trivial network. Each run consumes ~0.05% of monthly Actions budget.
- **Bottleneck**: none. GitHub Actions' job concurrency (20 simultaneous on free tier) is way over what this workflow needs.
- **Local hook overhead**: <100ms per push. Imperceptible to user.
- **Saturation behavior**: not applicable — load is far below any limit.

### 10. Decision records & runbook

**Decisions requiring records in `docs/decisions/NNN-*.md`:**

1. **Single `What mechanism would have caught this?` field vs. structured answer form selector.** Chose: a single Markdown section with three explicit answer-form sub-headings (existing catalog entry / new entry proposed / accepted residual risk). Alternatives: (a) GitHub Issue Forms for structured input — rejected because Issue Forms only work for issues, not PR bodies; (b) HTML comment instructions only — rejected because the workflow needs to detect placeholder vs. filled state, which requires distinct text patterns. Tradeoff: requires writers to choose an answer form, which is a slight cognitive cost; offsets are clearer auditing and easier regex-matching.

2. **~40-character rationale threshold for "no mechanism" option.** Chose 40. Alternatives: 80 (more substance required), 20 (lower bar). Rejected 80 because legitimate one-sentence rationales can be tight ("This is a copy-paste typo; no mechanism catches single-char prose typos without false positives" is 89 chars but a tighter one might be 50). Rejected 20 because "N/A — see prior PR" is 18 chars and gameable. 40 is the floor that rejects 1-3 word brush-offs while accepting genuine one-sentence rationales. Tunable.

3. **CI workflow + local hook (both layers) vs CI only.** Chose both. Alternative: CI only — rejected because the local hook saves a CI roundtrip when the omission is caught locally. Local-only would miss cases where the developer pushes from an environment without the hook installed. Both layers cost little and catch overlapping windows.

4. **Per-repo opt-in for the local hook vs. global install.** Chose per-repo. Alternative: global install (every repo on the developer's machine gets the hook). Rejected because not every harness-equipped repo uses GitHub PRs; a global hook would fire on pushes to any repo and be wrong for many. Per-repo opt-in (rollout script copies the hook into the repo's `.git/hooks/`) is the minimum correct default.

5. **Failure-modes file as a stub created by this plan vs. requiring the catalog plan first.** Chose: this plan creates a one-paragraph stub at `docs/failure-modes.md` that forward-links to the catalog plan. The PR template references the catalog (`FM-NNN` IDs); without at least a stub, the references are dangling. Real catalog content is plan #2's scope. Stub is a 5-minute task that unblocks the PR template's references regardless of plan #2 sequencing. (Note: in the reorganization sequence, plan #2 ships before this plan, so the stub may be no-op by the time plan #3 builds — that's fine, the stub is overwriteable.)

**Runbook entries:**

- **Symptom**: my PR check is failing on `pr-template-check`. **Diagnostic**: read the failure message (visible on PR check status). It will name the specific deficiency: missing section, placeholder still present, or insufficient rationale. **Fix**: edit PR body to address. Workflow re-fires on `edited` event automatically.

- **Symptom**: workflow's check shows "error" (yellow) not pass/fail. **Diagnostic**: open the workflow run via `gh pr checks <PR> --json link` and read the log. Common causes: GitHub Actions outage, YAML syntax error from a recent workflow edit. **Fix**: if outage, wait + retry; if YAML, revert and fix in a separate PR.

- **Symptom**: I genuinely cannot fill the mechanism field (e.g., the PR is auto-generated by a tool with no body customization). **Diagnostic**: edit the PR body manually after creation. **Fix**: the workflow re-fires on `edited` events, so post-creation edits work.

- **Symptom**: local hook is blocking my WIP push. **Diagnostic**: confirm the hook is installed (`ls .git/hooks/pre-push`) and that the branch isn't a recognized WIP pattern. **Fix**: either name the branch with a `wip-` prefix (auto-skip) OR push with `--no-verify` (the CI check will still gate merge).

- **Symptom**: I want to opt out of the local hook for a specific repo. **Diagnostic**: check `.git/hooks/pre-push` for the installed script. **Fix**: delete or rename `.git/hooks/pre-push`; the CI check is canonical and continues to gate merges.

- **Symptom**: a PR was merged with a low-quality mechanism answer (gibberish that passed the threshold). **Diagnostic**: review the merged PR's body. **Fix**: the threshold caught the bypass-by-omission case but not bypass-by-gibberish. Acknowledged residual risk in original plan; mitigation is reviewer vigilance + the harness-reviewer agent flagging suspicious patterns over time.
