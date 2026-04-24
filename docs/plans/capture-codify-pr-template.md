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

- [x] A.1 Create `.github/PULL_REQUEST_TEMPLATE.md` in the neural-lace repo with the required sections (Summary, What changed and why, **What mechanism would have caught this?** with three explicit answer forms, Testing performed). Placeholder text must be obviously-not-real so the CI scanner can detect un-filled submissions.
- [x] A.2 Write the GitHub Actions workflow at `.github/workflows/pr-template-check.yml` that parses the PR body, locates the mechanism section, and fails the check if: (a) the section is missing, (b) the placeholder text is still present, (c) the "no mechanism — accepted residual risk" option is selected without at least ~40 characters of rationale after the colon. The workflow runs on `pull_request` events with types `opened, edited, synchronize, reopened`.
- [x] A.3 Write a local git hook at `adapters/claude-code/git-hooks/pre-push-pr-template.sh` that performs an equivalent check against the latest commit message body OR an adjacent `.pr-description.md` file, so Claude-assisted work catches the omission before push. The hook must be opt-in per-repo (copied by a rollout script) rather than globally installed, because not all harness-using repos use GitHub PRs.
- [x] A.4 Update `adapters/claude-code/rules/planning.md` with a new section "Capture-codify at PR time" that describes the convention, cites the template, and documents the three allowed answer forms. Mirror the change to `~/.claude/rules/planning.md` per the harness-maintenance rule.
- [x] A.5 Update `adapters/claude-code/docs/harness-architecture.md` (the architecture doc) to record all four new artifacts in the relevant tables: (a) the PR template, (b) the workflow, (c) the local pre-push git hook, (d) the shared validator library at `.github/scripts/validate-pr-template.sh` (with a one-line cross-reference per Decision 7).
- [x] A.6 Add a one-paragraph stub at `docs/failure-modes.md` declaring the file's purpose and linking forward to the companion `failure-mode-catalog` plan. Rationale: the PR template references the catalog (`catalog entry FM-NNN`), so the catalog file must at minimum exist as a stub so the reference doesn't 404 when reviewers click it. Full catalog content is the companion plan's scope.
- [ ] A.7 Smoke-test the workflow end-to-end by opening throwaway PRs with (a) an empty mechanism section (expect fail), (b) a filled section citing a catalog entry (expect pass), (c) a "residual risk" answer with only "N/A" (expect fail), (d) a "residual risk" answer with substantive rationale (expect pass), AND **(e) a fork-PR scenario** verifying that the auto-emitted check appears for fork-originated PRs without `checks: write` permission. Record the five GitHub Actions run URLs as evidence. The fork-PR scenario is required because Section 5's resolution depends on it; if the auto-check doesn't appear, fall back to documenting the fork-PR limitation honestly in the rule update (Task 4).
- [x] A.8 Commit the plan file itself in its own commit immediately after creation (satisfies the "commit the plan file immediately" requirement in the dispatch prompt). Subsequent implementation commits reference this plan by path.
- [ ] A.9 **Configure branch protection on neural-lace** to require the `PR Template Check / validate` check. Use `gh api repos/<owner>/neural-lace/branches/master/protection -X PUT --input -` with the following JSON body:
  ```json
  {
    "required_status_checks": {
      "strict": true,
      "contexts": ["PR Template Check / validate"]
    },
    "enforce_admins": false,
    "required_pull_request_reviews": null,
    "restrictions": null
  }
  ```
  Verify by attempting a merge on a failing PR — should be blocked. Without this task, Section 1's outcome ("every fix-PR merged to master has a non-empty mechanism field") is not enforceable; the check would be advisory only.
- [ ] A.10 **Create decision records** as standalone files in `docs/decisions/NNN-*.md` for each Tier 2+ decision listed in Section 10 — seven decisions total: (1) single-field-vs-structured, (2) 40-char threshold, (3) CI+local both layers, (4) per-repo opt-in for hook, (5) failure-modes stub creation, (6) squash-merge body inclusion, (7) validator library location at `.github/scripts/`. Each record uses the format from `~/.claude/templates/decision-log-entry.md` (Title, Date, Status, Stakeholders, Context, Decision, Alternatives Considered with reject reasons, Consequences). Add one row per record to `docs/DECISIONS.md`. Atomicity gate (`decisions-index-gate.sh`) enforces records ↔ index consistency at commit time.
- [ ] A.11 **Write rollout helper script** `adapters/claude-code/scripts/install-pr-template.sh <target-repo-path>` that copies (a) the PR template `.github/PULL_REQUEST_TEMPLATE.md`, (b) the workflow `.github/workflows/pr-template-check.yml`, (c) the validator library `.github/scripts/validate-pr-template.sh`, and (d) the local pre-push hook into a target downstream repo. Idempotent (re-runnable). Documented in the rule update (Task 4). Per Decision 7, the validator library lives at `.github/scripts/` in neural-lace itself — no path rewriting needed during rollout.
- [ ] A.12 **Write retroactive-audit script** `adapters/claude-code/scripts/audit-merged-prs.sh --limit N` that iterates `gh pr list --state merged` and runs the validator library against each PR body, reporting per-PR PASS/FAIL with the count of pre-rollout PRs that would have failed. Used in the runbook entry for retroactive audit.
- [ ] A.13 **File observability backlog entries** in `docs/backlog.md` for the gaps acknowledged in Section 6: (a) "P2 — automatic detection of FM-NNN-cited-but-doesn't-exist in `docs/failure-modes.md`"; (b) "P2 — answer-form (a/b/c) distribution tracking for capture-codify telemetry"; (c) "P2 — pre-commit atomicity gate: PR template edits must atomically update the validator regex" (per Section 7's accidental-template-edit failure mode). Each entry brief but actionable.
- [ ] A.14 **Update Testing Strategy section** of this plan to remove the `act` reference (Section 4 documents `act` as optional; Testing Strategy should not depend on it). Sole verification path is Task 7's real GitHub Actions runs.
- [ ] A.15 **Update the `/harness-review` skill body** at `adapters/claude-code/skills/harness-review.md` (canonical source) to add the operational-measurement queries from Section 6 (compliance % via `gh pr list --state merged ...`; catalog growth via `git log docs/failure-modes.md`). Then sync to `~/.claude/skills/harness-review.md` per `harness-maintenance.md`. **Note on install state:** the `~/.claude/skills/harness-review.md` file may not currently exist on a given machine (Windows installs are independent copies; the file ships only when `install.sh` runs after the canonical source exists). If absent, Task 15 includes the initial `cp` as part of the mirror operation. Verify both files identical via diff after the sync.

## Files to Modify/Create

### Tasks 1-8 (original plan)
- `docs/plans/capture-codify-pr-template.md` — this plan file (created in task 8's commit).
- `.github/PULL_REQUEST_TEMPLATE.md` — new file, required PR template with the mechanism field. (Task 1)
- `.github/workflows/pr-template-check.yml` — new workflow, validates the mechanism field on PR events. (Task 2)
- `adapters/claude-code/git-hooks/pre-push-pr-template.sh` — new local hook, equivalent check before push. (Task 3)
- `.github/scripts/validate-pr-template.sh` — NEW shared validator library sourced by both the workflow and the local hook. Per Decision 7, lives at `.github/scripts/` (not under `adapters/claude-code/`) so the rollout script can copy `.github/` to downstream repos with no path rewriting. (Tasks 2 + 3)
- `adapters/claude-code/rules/planning.md` — add "Capture-codify at PR time" section. Mirror to `~/.claude/rules/planning.md`. (Task 4)
- `~/.claude/rules/planning.md` — mirror the rule change per harness-maintenance rule. (Task 4)
- `adapters/claude-code/docs/harness-architecture.md` — record the four new artifacts in the architecture tables. (Task 5)
- `docs/failure-modes.md` — stub file, links forward to the companion catalog plan. (Task 6)

### Tasks 9-13 (cross-cutting fixes added during plan revision)
- Branch protection configuration on `repos/<owner>/neural-lace/branches/master/protection` — applied via `gh api ... -X PUT --input <protection-config.json>`. Not a file in the repo but a GitHub API state change. (Task 9)
- `docs/decisions/NNN-capture-codify-mechanism-field-shape.md` — Decision 1 record. (Task 10)
- `docs/decisions/NNN-capture-codify-rationale-threshold.md` — Decision 2 record. (Task 10)
- `docs/decisions/NNN-capture-codify-ci-and-local-hook.md` — Decision 3 record. (Task 10)
- `docs/decisions/NNN-capture-codify-per-repo-hook-optin.md` — Decision 4 record. (Task 10)
- `docs/decisions/NNN-capture-codify-failure-modes-stub.md` — Decision 5 record. (Task 10)
- `docs/decisions/NNN-capture-codify-squash-merge-body.md` — Decision 6 record. (Task 10)
- `docs/decisions/NNN-capture-codify-validator-library-location.md` — Decision 7 record. (Task 10)
- `docs/DECISIONS.md` — add 7 new rows pointing at the records above. Atomicity gate (`decisions-index-gate.sh`) enforces records ↔ index in same commit. (Task 10)
- `adapters/claude-code/scripts/install-pr-template.sh` — NEW rollout helper. (Task 11)
- `adapters/claude-code/scripts/audit-merged-prs.sh` — NEW retroactive-audit script. (Task 12)
- `docs/backlog.md` — append 3 new entries (catalog-cited-but-doesnt-exist gap, answer-form distribution telemetry, template-edit atomicity gate). (Task 13)
- `adapters/claude-code/skills/harness-review.md` — add operational-measurement queries section (compliance %, catalog growth). (Task 15)
- `~/.claude/skills/harness-review.md` — mirror of skill body update. (Task 15)

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

- **Task 1 (template):** verify the file exists at the correct path, contains all four required `##` sections (Summary, What changed and why, What mechanism would have caught this?, Testing performed), the three `### a/b/c)` answer-form sub-headings under the mechanism section, and the obviously-not-real placeholder text. Grep: `grep -c '^## ' .github/PULL_REQUEST_TEMPLATE.md` returns 4; `grep -c '^### ' .github/PULL_REQUEST_TEMPLATE.md` returns 3; `grep -c 'mechanism answer — replace this bracketed text' .github/PULL_REQUEST_TEMPLATE.md` returns 1.
- **Task 2 (workflow):** trigger the workflow via a throwaway PR (see task 7). Capture the full GitHub Actions run log showing fail-on-empty and pass-on-filled. Evidence must include the run URL and exit code. Workflow YAML must include `actions/checkout@v4` as the first job step (verified via `grep checkout@v4 .github/workflows/pr-template-check.yml`). (Optional pre-task fast-feedback: `act` per Section 4, but the canonical verification is the real GitHub Actions run.)
- **Task 3 (local hook):** run the hook manually against a staged commit with (a) empty mechanism field (expect exit 1), (b) filled field (expect exit 0). Capture both stderr outputs and verify they match the canonical messages from Section 6.
- **Task 4 (rule update):** grep `~/.claude/rules/planning.md` and `adapters/claude-code/rules/planning.md` for the new section heading "Capture-codify at PR time" after the edit. Diff the two files to confirm they match (per harness-maintenance's mirror-verify loop).
- **Task 5 (architecture doc):** grep the architecture doc for ALL FOUR new artifact names: `.github/PULL_REQUEST_TEMPLATE.md`, `.github/workflows/pr-template-check.yml`, `adapters/claude-code/git-hooks/pre-push-pr-template.sh`, `.github/scripts/validate-pr-template.sh`. All four must be present with one-line descriptions.
- **Task 6 (failure-modes stub):** verify the file exists at `docs/failure-modes.md` and contains a forward-link to the companion `failure-mode-catalog` plan (grep for `failure-mode-catalog`).
- **Task 7 (smoke test):** five throwaway PRs with explicit pass/fail expectations (per Task 7's a/b/c/d/e enumeration, including the fork-PR scenario); each PR's check-run URL recorded as evidence. The throwaway PRs are closed without merging after verification. Fork-PR test confirms the auto-emitted check name on the PR matches `PR Template Check / validate`.
- **Task 8 (commit discipline):** verify via `git log` that the plan file's creation commit is distinct from any implementation commit, and that implementation commits reference the plan path in their message.
- **Task 9 (branch protection):** verify via `gh api repos/<owner>/neural-lace/branches/master/protection --jq '.required_status_checks.contexts'` that the array includes `PR Template Check / validate`. Additionally, attempt a merge on a deliberately-failing throwaway PR; verify the merge is blocked.
- **Task 10 (decision records):** verify all 7 records exist with `ls docs/decisions/*-capture-codify-*.md | wc -l` returning 7. Verify `docs/DECISIONS.md` has 7 new rows by `grep -c 'capture-codify-' docs/DECISIONS.md`. Verify each record has the required fields (Title, Date, Status, Stakeholders, Context, Decision, Alternatives Considered, Consequences) via `for f in docs/decisions/*-capture-codify-*.md; do grep -c '^## ' "$f"; done` showing each ≥ 4.
- **Task 11 (rollout script):** run the script against a throwaway test directory: `mkdir -p /tmp/rollout-test && cd /tmp/rollout-test && git init && bash <neural-lace>/adapters/claude-code/scripts/install-pr-template.sh .`. Verify the four artifacts (template, workflow, validator library, local hook) exist in the test directory. Re-run the script (idempotency check) — second run must not error.
- **Task 12 (audit script):** run `bash adapters/claude-code/scripts/audit-merged-prs.sh --limit 5` and verify it produces per-PR PASS/FAIL output for the last 5 merged PRs. Test against a known-failing PR body and confirm FAIL is reported.
- **Task 13 (backlog entries):** verify `docs/backlog.md` contains the 3 new entries via `grep -c 'capture-codify' docs/backlog.md` returning ≥ 3, and each entry has a P0/P1/P2 prefix.
- **Task 14 (Testing Strategy cleanup):** verify the `act` reference no longer appears in the Task 2 Testing Strategy bullet via `grep -A1 '\*\*Task 2 ' docs/plans/capture-codify-pr-template.md | grep -c 'act'` returning 0. (Section 4's optional-tooling mention of `act` is unaffected and remains.)
- **Task 15 (skill body update):** verify both `adapters/claude-code/skills/harness-review.md` and `~/.claude/skills/harness-review.md` contain the new compliance-measurement queries via `grep -c 'gh pr list --state merged' adapters/claude-code/skills/harness-review.md` returning ≥ 1; same for the `~/.claude/` path. Diff the two files and confirm zero differences.

Each task's evidence block will be written by `task-verifier` after the builder runs the relevant verification command; the builder does NOT write evidence directly.

## Decisions Log

[Populated during implementation — see Mid-Build Decision Protocol]

## Definition of Done

- [ ] All tasks 1-15 checked off by `task-verifier`
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

**Real example:** retroactively applying the template to neural-lace commit `9d21965` ("fix(hook): bug-persistence-gate now checks --all branches + reflog (6h window)") — a real fix to an existing hook, identified during dogfooding.

- **T=0**: Maintainer opens PR (hypothetical PR-N for commit `9d21965`) against `<owner>/neural-lace` master. PR body is auto-populated from `.github/PULL_REQUEST_TEMPLATE.md` with the four sections: `## Summary`, `## What changed and why`, `## What mechanism would have caught this?` (with three answer-form sub-headings — see Section 3 for exact text), `## Testing performed`.
- **T=1**: Maintainer fills the mechanism section with answer form (a): "Existing catalog entry FM-NNN (bug-persistence trigger fires without actual persistence) — to be added to docs/failure-modes.md by failure-mode-catalog plan. The hook scanned the current branch's recent commits but missed bugs that had been persisted to a different branch's backlog within the same session. Mitigation: scan `--all` branches + reflog within a 6h window."
- **T=2**: PR opened. GitHub Actions workflow file `.github/workflows/pr-template-check.yml` triggers on `pull_request` event of types `[opened, edited, synchronize, reopened]`. The workflow defines a single job with ID `validate` (no explicit `name:` field, so the job's display name is `validate`). The check name auto-emitted by GitHub Actions is `PR Template Check / validate` (workflow-name / job-id). First step is `actions/checkout@v4` to make the validator library available at `$GITHUB_WORKSPACE/<library-path>`. Second step reads `${{ github.event.pull_request.body }}` from the trigger context (no API call required) and runs Bash logic:
  - Locate section heading via case-sensitive regex: `^## What mechanism would have caught this\?$` (anchored, `\?` escaped). If not matched → exit 1, stderr: `[pr-template] FAIL: required section heading "## What mechanism would have caught this?" not found in PR body`.
  - Extract content from after the heading to the next `^## ` heading or EOF.
  - Detect placeholder via regex: `<mechanism answer — replace this bracketed text>` (literal substring match for the angle-bracketed instruction text). If present → exit 1, stderr: `[pr-template] FAIL: placeholder text still present; section was not filled in`.
  - Detect answer-form selection by Markdown sub-heading: `^### (a\) Existing catalog entry|b\) New catalog entry proposed|c\) No mechanism — accepted residual risk)`. If `c)` selected, count chars of content after the sub-heading; if < 40 → exit 1, stderr: `[pr-template] FAIL: "no mechanism" option requires ≥40 chars of substantive rationale (got N chars)`.
  - All checks pass → exit 0; job concludes success → GitHub Actions auto-creates a check named `PR Template Check / validate` (job + step naming) with status `success`.
- **T=3**: Maintainer pushes a fixup commit, edits PR body to clarify wording. Workflow re-fires on `edited` and `synchronize` events. Re-validates. Still passes.
- **T=4**: PR merges to master via `gh pr merge --squash`. **Squash-merge body behavior on neural-lace specifically:** repo was created 2026-04-19 with no custom squash-merge commit-message setting (`squash_merge_commit_message: null` per `gh api repos/<owner>/neural-lace`). GitHub's default for unset `squash_merge_commit_message` uses `COMMIT_MESSAGES` (concatenated commit messages of the squashed commits), NOT the PR body. **Therefore the mechanism analysis from the PR body does NOT automatically land in the master commit log.** Traceability must come from grepping the PRs (`gh pr list --search FM-NNN`), not from the merge commit. This is a real consequence: future archaeology requires PR-search, not git-log-search. Acknowledged limitation; addressed by Decision 6 below (whether to change repo squash setting to include PR body) and Section 6 (observability via PR-list aggregation).

**Divergent trace — empty mechanism section.** At T=1, maintainer forgets to fill it in. At T=2, workflow runs, the regex for section heading matches (heading is in the template), but the placeholder regex matches the still-present `<mechanism answer — replace this bracketed text>`. Workflow exits 1 with stderr message named above. Job conclusion is `failure` → GitHub auto-creates check with status `failure`. Branch protection rule (if configured per Task 9 below) blocks merge until the check passes.

**Divergent trace — fork PR from external contributor.** Workflow runs on `pull_request` event, which fires for fork PRs too. The fork PR's workflow runs with a **read-only** `GITHUB_TOKEN` and **no access to repo secrets** (standard GitHub Actions behavior for `pull_request` from forks; well-documented). Reading `${{ github.event.pull_request.body }}` works because it's an event-context value, not an API call. The check is auto-created from the workflow conclusion (`success` or `failure`) — this auto-creation does NOT require `checks: write` permission and works for fork PRs. **The plan therefore does NOT require `checks: write` and does NOT require `pull_request_target` (which would be a security risk for an untrusted-code workflow).** Section 5 documents the resolved permissions. Verification at Task 7 smoke test must include a fork-PR scenario.

### 3. Interface contracts between components

**Identifier conventions used throughout this plan:**
- Workflow file: `.github/workflows/pr-template-check.yml`
- Workflow `name:` field (top of YAML): `PR Template Check`
- Job ID inside workflow: `validate`
- Job `name:` field: OMITTED (so GitHub uses the job ID `validate` as the job's display name)
- GitHub-emitted check name (what branch protection requires): `PR Template Check / validate` (workflow-name / job-name format per GitHub Actions convention; verify in Task 7 smoke test)
- PR template path: `.github/PULL_REQUEST_TEMPLATE.md`

**Exact section heading text the template uses (case-sensitive, regex-anchored):**
- `## Summary`
- `## What changed and why`
- `## What mechanism would have caught this?` ← the load-bearing one
  - `### a) Existing catalog entry`
  - `### b) New catalog entry proposed`
  - `### c) No mechanism — accepted residual risk`
- `## Testing performed`

**Exact placeholder text the template uses** (multi-line block under each section, lowercase bracketed instruction):
- After mechanism heading: `<mechanism answer — replace this bracketed text>`
- After other sections: `<replace this bracketed text with content>`

| Producer | Consumer | Contract |
|---|---|---|
| `.github/PULL_REQUEST_TEMPLATE.md` | GitHub PR creation flow | UTF-8 Markdown, no frontmatter (GitHub PR templates ignore YAML frontmatter; rendered as-is). GitHub auto-populates the PR body with this template's content on PR open via the `pull_request_body` value in the new-PR API. Sections are Markdown `##` headings as enumerated above. Placeholder text is the angle-bracketed strings as enumerated above; the regex's literal-substring detection requires byte-for-byte match. |
| `.github/workflows/pr-template-check.yml` | GitHub Actions runner | Standard YAML workflow, `name: PR Template Check`. Triggered on `pull_request` event types `[opened, edited, synchronize, reopened]`. Defines a single job with ID `validate` (no `name:` field, so the ID is the display name). Job runs on `ubuntu-latest`. **First step is `actions/checkout@v4`** (required so the next step can `source` the validator library — see below). Reads `${{ github.event.pull_request.body }}` from the trigger context. Exits 0 (pass) or non-zero (fail). Auto-emitted check name on the PR is `PR Template Check / validate`. Timeout: 60s (workflow-level). |
| `adapters/claude-code/git-hooks/pre-push-pr-template.sh` | Local git pre-push hook | Bash script. Reads `.pr-description.md` from repo root if present, otherwise reads `git log -1 --format=%B` for the latest commit message body. Same validation logic as the workflow (identical regex patterns; shared via a sourced `validate-pr-template.sh` library file to avoid drift). Exits 0 to allow push, non-zero to block with stderr message naming the same failure category as the workflow. Idempotent. **Note on `.pr-description.md` flow:** this is a local-only file; it is NOT auto-uploaded to the PR body. The convention is: developer writes `.pr-description.md` locally, runs the hook to validate, then on `gh pr create` passes `--body-file .pr-description.md` to upload. Documented in Task 4's rule update. |
| Shared `.github/scripts/validate-pr-template.sh` (NEW — added during implementation; lives at `.github/scripts/` rather than `adapters/claude-code/git-hooks/` to be portable across rollout — see Decision 7) | Workflow + local hook | Bash function library sourced by both the workflow's `run:` step (after `actions/checkout@v4`) and the local pre-push hook. Defines: `find_section_heading()`, `extract_section_content()`, `detect_placeholder()`, `detect_answer_form()`, `validate_rationale_length()`, `emit_failure_message()`. Functions return 0/non-zero; messages go to stderr in the same format from both call sites. Eliminates regex drift between CI and local. Local pre-push hook sources from the same path; the rollout script (Task 11) trivially copies the `.github/` directory to downstream repos with no path rewriting needed. |
| Validation logic | PR body content | Inputs: PR body string (whatever GitHub provides in the event context — the validator does not assume a specific size limit; runs over the body as-is). Outputs: exit code (0/1) + stderr diagnostic. Detects in order: (a) `^## What mechanism would have caught this\?$` heading present, (b) `<mechanism answer — replace this bracketed text>` placeholder absent in extracted content, (c) one of `^### (a|b|c)\)` answer-form sub-headings selected and present, (d) if `c)` selected, ≥40 chars of non-whitespace content after that sub-heading. |
| Workflow → GitHub auto-check | Branch protection rule | The check name `PR Template Check / validate` is what branch protection rules opt-in for required-status-check enforcement. Branch protection configuration is per-repo and is added by Task 9 (newly added — see Cross-cutting fix). |
| `rules/planning.md` (updated) | Future plan authors | Adds "Capture-codify at PR time" section explaining the convention, the three answer forms, and the `.pr-description.md` local-flow convention. Discoverable via the rule file index in `CLAUDE.md`. |

### 4. Environment & execution context

**GitHub Actions workflow runs on:** `ubuntu-latest` runner. Pre-installed: standard CI tools (bash, jq, git, curl, grep). `${{ github.event.pull_request.body }}` is provided in the trigger context; no API call needed for body retrieval. `GITHUB_TOKEN` is auto-provisioned but with **restrictive defaults** because neural-lace was created 2026-04-19 (after the 2023-02-02 GitHub default-permissions change). The workflow MUST declare an explicit `permissions:` block (see Section 5). VM destroyed at job end; no persistent state needed.

**Local pre-push hook runs on:** developer's local machine (varied OS — macOS, Linux, Windows-with-Git-Bash). Working directory is the repo root. Has access to `git log -1 --format=%B` for the latest commit message and `cat .pr-description.md` for an alternative description-source convention. **Bash 3.2+ assumed** (macOS default). The hook script must avoid Bash-4-only features: associative arrays (`declare -A`), `mapfile`, `${var,,}` lowercase parameter expansion, `&>>` append-redirect — these will silently fail or error on macOS. No network access needed.

**Workspace state:** `actions/checkout@v4` checks the repo out at `$GITHUB_WORKSPACE` (default `/home/runner/work/<repo>/<repo>`). The validator library is sourced from this checkout; the workflow has read access to all repo files. No write-back to the repo (no commits from the workflow).

**Persistence:** None. All inputs are read-on-demand; no caching.

**Cross-environment behavior:** workflow result is the source of truth (CI is canonical). Local hook is a pre-push convenience to catch mistakes before they reach CI; it can be skipped (`git push --no-verify`) for legitimate WIP pushes — branch protection still gates merge.

**Optional local-only tooling:** `act` (https://github.com/nektos/act) can run GitHub Actions workflows locally for testing without opening a real PR. Mentioned in the Testing Strategy as an OPTIONAL pre-Task-7 fast-feedback loop. NOT a hard dependency; the plan ships and tests against real GitHub Actions runs (Task 7) regardless.

### 5. Authentication & authorization map

- **GitHub Actions workflow → GitHub API (same-repo PR):** uses `GITHUB_TOKEN`. neural-lace is post-2023-02-02 so default permissions are restrictive (`contents: read` only). The workflow YAML must declare an explicit `permissions:` block. **Required permissions:** `pull-requests: read` is technically not even needed because `${{ github.event.pull_request.body }}` is read from the event context (no API call). The workflow can declare `permissions: read-all` or even `permissions: {}` — neither requires elevation. **Decision: declare `permissions: {}` (no elevated permissions)** to minimize attack surface, since the workflow only reads event-context data and emits exit codes.
- **GitHub Actions workflow → check status:** the check is auto-emitted by GitHub Actions from the job conclusion (success/failure/cancelled). This auto-emission does NOT require `checks: write`. The workflow does NOT use `actions/github-script` or `gh api` to manually create custom check runs — auto-emission is sufficient. **This means Section 7's "External contributor PR" failure-mode row is RESOLVED: auto-emitted checks work for fork PRs too, with no permissions difference.**
- **Fork PR auth (resolved):** workflow runs with read-only `GITHUB_TOKEN`, no secrets access. Reading the event context still works. Auto-emitted check still works. No special handling needed; no `pull_request_target` required (which would be a security risk because it would run untrusted code with elevated permissions).
- **Local pre-push hook → file system:** reads `.pr-description.md` and runs `git log` against local repo. No external auth.
- **Branch protection rule → workflow check:** managed by GitHub repo admin. **Configuration is now IN scope** (added as Task 9 — see Cross-cutting fix below); the outcome in Section 1 only holds if branch protection enforces the check.
- **Token rotation:** `GITHUB_TOKEN` is auto-managed per workflow run (ephemeral); no manual rotation needed.

No new tokens or secrets introduced. Rate limit is GitHub Actions' standard 1000 requests/hour per repo for `GITHUB_TOKEN`-authenticated requests (way over what this workflow consumes — it makes zero API calls). No rate-limit concerns.

### 6. Observability plan (built before the feature)

**Canonical workflow stderr messages** (one per failure mode; consistent format `[pr-template] FAIL: <reason>`):

| Failure | Canonical stderr message |
|---|---|
| Section heading missing | `[pr-template] FAIL: required section heading "## What mechanism would have caught this?" not found in PR body` |
| Placeholder still present | `[pr-template] FAIL: placeholder text "<mechanism answer — replace this bracketed text>" still present; section was not filled in` |
| No answer-form sub-heading | `[pr-template] FAIL: no answer form selected; expected one of "### a) Existing catalog entry", "### b) New catalog entry proposed", or "### c) No mechanism — accepted residual risk"` |
| Insufficient rationale on (c) | `[pr-template] FAIL: "no mechanism" option requires ≥40 chars of substantive rationale (got N chars)` |

The local hook uses identical messages (sourced from the shared library — Section 3) so users see the same message in both contexts.

**Intra-workflow logging** (stdout, for forensic reconstruction from the workflow log):

```
[pr-template] checking PR #N body (M chars)
[pr-template] section heading found at offset O
[pr-template] extracted N chars of mechanism content
[pr-template] placeholder detection: <PRESENT|ABSENT>
[pr-template] answer form: <a|b|c|NONE>
[pr-template] (if c) rationale length: N chars (threshold: 40)
[pr-template] verdict: PASS|FAIL
```

These lines appear in every workflow run and let an operator reconstruct exactly what the validator saw.

**Per-PR signals:**
- Workflow check status visible on the PR page (green/red), check name `PR Template Check / validate`.
- Workflow log accessible via `gh pr checks <PR>` (look at the `link` field of the JSON output) or the GitHub UI.
- Failure stderr message names the specific deficiency (one of the four canonical messages above).
- Local hook stderr uses the same messages on push attempt.

**Operational outcome measurement** (how Section 1's 30-day / 90-day metrics are produced):

Add to weekly `/harness-review` skill: a step that runs the following commands and records results in the dated review document at `docs/reviews/YYYY-MM-DD-harness-review.md`:

```bash
# Measure mechanism-field compliance over the last 30 days
gh pr list --state merged --limit 200 --search "merged:>$(date -d '30 days ago' +%Y-%m-%d)" \
  --json number,body \
  | jq -r '.[] | select(.body | contains("## What mechanism would have caught this?")) | .number' \
  | wc -l
# Compare against total PR count for percentage

# Measure catalog growth
git log --oneline --since='30 days ago' docs/failure-modes.md | wc -l
```

The existing `/harness-review` skill (shipped 2026-04-18 per SCRATCHPAD's milestone log) already has a weekly cadence; adding these queries to its run is the operational implementation of the metric. Skill body updated by Task 15.

**Observability gaps (filed to backlog as P2 entries via Task 13 below):**
- No automatic detection of "this PR cited FM-NNN, did the cited entry actually exist in `docs/failure-modes.md` at PR open time?" — reviewer responsibility for now. **Backlog entry filed in Task 13.**
- No tracking of "answer form (a) vs (b) vs (c) distribution" — could be added later via a script over PR bodies. **Backlog entry filed in Task 13.**

### 7. Failure-mode analysis per step

| Step | Failure mode | Observable symptom | Recovery / retry | Escalation |
|---|---|---|---|---|
| PR template autopopulation | GitHub doesn't autopopulate body (rare; happens if user uses an API client that bypasses templates) | PR body is whatever the user wrote, no template structure | Workflow detects missing section heading, fails with clear message | User edits PR body to include the template structure |
| Workflow trigger | Workflow doesn't run (GitHub outage, malformed YAML) | No check appears on the PR | Re-trigger via a dummy commit; check GitHub status page | If chronic, surface as a known issue in the runbook |
| Workflow regex (false positive) | Regex falsely matches placeholder pattern in valid content (e.g., user writes the literal placeholder text inside a fenced code block to document the template itself) | False fail on a meta-PR | Edit the PR body to use a different code-block fence pattern OR document the template-edit exemption | Add code-fence-aware extraction to the validator if pattern recurs |
| Workflow regex (false negative) | Regex misses an actual placeholder (variant phrasing) | False pass | Reviewer catches in code review | Add the missed pattern to the regex; ship a validator update |
| Workflow regex (code-block placeholder) | A PR that's documenting the PR template itself includes the literal placeholder string in a fenced code block; validator counts it as un-filled | False fail | Validator should extract content excluding fenced-code blocks before placeholder check; if not implemented, user adjusts wording | Implement code-fence-aware extraction in shared validator library |
| Workflow rationale check | "No mechanism" answer with 39-char rationale (just under threshold) | Workflow fails with "rationale too short" | User extends to ≥40 chars | Threshold tuning if false-positive rate is high |
| Workflow exit code | Workflow exits 0 despite failure (bug in workflow logic) | Bad PR slips through | Catch via post-merge audit; fix workflow | Self-test with known-bad inputs |
| Empty PR body entirely | PR opened with empty body (developer skipped the template entirely, e.g., used `gh pr create --title X` without `--body`) | Workflow runs, finds NO section headings (not even mis-filled) | Workflow fails with section-missing message, points user at the template path | Same as above — workflow message names the template file |
| Accidental template-file edit | A builder modifies `.github/PULL_REQUEST_TEMPLATE.md` for an unrelated reason (e.g., changes wording while editing nearby files), breaking the regex contract for all future PRs | First PR after the change fails CI unexpectedly; nothing wrong with the PR itself | Revert the template change; investigate why it was edited | Add a `pre-commit` check that warns if `.github/PULL_REQUEST_TEMPLATE.md` is staged and `.github/workflows/pr-template-check.yml` is NOT staged in the same commit (atomicity rule similar to existing `decisions-index-gate.sh`). **Filed as backlog entry in Task 13.** |
| Local hook | Hook doesn't fire (not installed, opt-out) | Bad push reaches origin | CI check still catches at PR open | Local hook is a convenience; CI is canonical |
| Local hook | Hook false-positive blocks legitimate push (e.g., WIP commit) | Push rejected | User uses `--no-verify` for WIP pushes | Document the WIP-skip pattern; consider auto-skip for `wip-` branches |
| Branch protection rule | Not configured on the repo | Bad PRs can merge despite check failing | **Now in scope: Task 9 configures branch protection for neural-lace.** For downstream rollout, document in setup instructions. | If repo admins disable branch protection later, the check becomes advisory; surfaced by `/harness-review` audit |
| External contributor PR | Fork-PR auth nuances | Workflow runs but fails to set check status | **RESOLVED in Section 5: auto-emitted check from job conclusion works for fork PRs without `checks: write`. Verified by Task 7 smoke test which now MUST include a fork-PR scenario.** | If smoke test reveals the auto-check doesn't appear, fall back to documenting fork-PR limitation honestly |
| Sweep PR with multiple fixes | Single mechanism field can't cover 5 unrelated fixes coherently | User writes a multi-bullet list | Workflow accepts (≥40 chars total) | Document multi-bullet pattern in the template |
| Emergency hotfix | Mechanism analysis is genuinely n/a (rollback) | User selects "no mechanism — accepted residual risk" + writes "Rollback; mechanism analysis lives on the rolled-back PR" | PASS (>40 chars) | Normal flow |
| Workflow YAML breaks on update | Plan #3 update breaks the workflow | Workflow check shows error, not pass/fail | Revert the update; fix; redeploy | Test workflow changes in a draft PR first |
| Placeholder text drift | Future template revision changes placeholder text without updating regex | Workflow's placeholder-detect stops working | False-pass on un-filled PRs | Self-test catches this; require updating both files atomically (see "accidental template-file edit" row above for the proposed enforcement) |

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

2. **~40-character rationale threshold for "no mechanism" option.** Chose 40. Alternatives: 80, 20. **Rejected 80** because tighter legitimate one-sentence rationales fall in the 40-70 range (e.g., a tight 50-char justification like "Single-char prose typo; no rule catches that cheaply." is meaningful but would fail an 80-char gate, producing false rejections of substantive answers). **Rejected 20** because terse brush-offs ("N/A — see prior PR" is 18 chars; "Rollback only" is 13 chars) would slip through. 40 sits at the inflection point where most genuine one-sentence rationales succeed and most cop-outs fail. Threshold is tunable later via a single constant in the shared validator library; if FP rate is high after rollout, raise to 50.

3. **CI workflow + local hook (both layers) vs CI only.** Chose both. Alternative: CI only — rejected because the local hook saves a CI roundtrip when the omission is caught locally. Local-only would miss cases where the developer pushes from an environment without the hook installed. Both layers cost little and catch overlapping windows.

4. **Per-repo opt-in for the local hook vs. global install.** Chose per-repo. Alternative: global install (every repo on the developer's machine gets the hook). Rejected because not every harness-equipped repo uses GitHub PRs; a global hook would fire on pushes to any repo and be wrong for many. Per-repo opt-in (rollout script copies the hook into the repo's `.git/hooks/`) is the minimum correct default.

5. **Failure-modes file as a stub created by this plan vs. requiring the catalog plan first.** Chose: this plan creates a one-paragraph stub at `docs/failure-modes.md` that forward-links to the catalog plan. The PR template references the catalog (`FM-NNN` IDs); without at least a stub, the references are dangling. Real catalog content is plan #2's scope. Stub is a 5-minute task that unblocks the PR template's references regardless of plan #2 sequencing. (Note: in the reorganization sequence, plan #2 ships before this plan, so the stub may be no-op by the time plan #3 builds — that's fine, the stub is overwriteable.)

6. **Squash-merge body inclusion (whether to change repo setting).** Chose: do NOT change the repo's `squash_merge_commit_message` setting. Alternative: change to `PR_BODY` so the mechanism analysis lands in the master commit log automatically. Rejected because (a) it would change ALL squash-merge bodies repo-wide, not just the mechanism section — affects unrelated work; (b) PR-list aggregation (Section 6) provides equivalent traceability without the side effect; (c) the change is reversible later if the absence proves painful.

7. **Validator library location: `.github/scripts/` vs `adapters/claude-code/git-hooks/`.** Chose `.github/scripts/validate-pr-template.sh`. Alternative: `adapters/claude-code/git-hooks/validate-pr-template.sh` (proper harness location). Rejected because the workflow sources the library and downstream repos receiving the rollout don't have an `adapters/claude-code/` tree — path-rewriting at rollout-time is brittle. `.github/scripts/` is a path that exists naturally in any repo using GitHub Actions, makes the rollout script trivially `cp -r .github/ <target>/`, and keeps a single source of truth. Tradeoff: the validator library is technically a harness asset but lives outside the `adapters/claude-code/` tree. Mitigated by adding a one-line note in `adapters/claude-code/docs/harness-architecture.md` (Task 5) pointing at the `.github/scripts/` location.

**Runbook entries:**

- **Symptom**: my PR check is failing on `PR Template Check / validate`. **Diagnostic**: open the workflow run via `gh pr checks <PR-number>` (look at the `link` JSON field) and read the canonical stderr message naming the specific deficiency (one of the four messages enumerated in Section 6). **Fix**: edit PR body to address. Workflow re-fires on `edited` event automatically.

- **Symptom**: workflow's check shows "error" (yellow) not pass/fail. **Diagnostic**: open the workflow run via `gh pr checks <PR>` and read the log. Common causes: GitHub Actions outage, YAML syntax error from a recent workflow edit. **Fix**: if outage, wait + retry; if YAML, revert and fix in a separate PR.

- **Symptom**: I genuinely cannot fill the mechanism field (e.g., the PR is auto-generated by a tool with no body customization). **Diagnostic**: edit the PR body manually after creation. **Fix**: the workflow re-fires on `edited` events, so post-creation edits work.

- **Symptom**: local hook is blocking my WIP push. **Diagnostic**: confirm the hook is installed (`ls .git/hooks/pre-push`) and that the branch isn't a recognized WIP pattern. **Fix**: either name the branch with a `wip-` prefix (auto-skip) OR push with `--no-verify` (the CI check will still gate merge).

- **Symptom**: I want to opt out of the local hook for a specific repo. **Diagnostic**: check `.git/hooks/pre-push` for the installed script. **Fix**: delete or rename `.git/hooks/pre-push`; the CI check is canonical and continues to gate merges.

- **Symptom**: a PR was merged with a low-quality mechanism answer (gibberish that passed the threshold). **Diagnostic**: review the merged PR's body. **Fix**: the threshold caught the bypass-by-omission case but not bypass-by-gibberish. Acknowledged residual risk; mitigation is reviewer vigilance + the harness-reviewer agent flagging suspicious patterns over time.

- **Symptom**: I changed `.github/PULL_REQUEST_TEMPLATE.md` and now all open PRs are failing CI. **Diagnostic**: the regex in the validator expects specific section headings and placeholder text (per Section 3's "exact text" tables). If the template wording changed, the validator's expectations diverged. **Fix**: either revert the template change OR update the shared validator library `validate-pr-template.sh` (and re-test via self-test) in the same commit. The "atomicity" gate proposed in Section 7 is the future enforcement.

- **Symptom**: I want to roll out the workflow to a downstream repo. **Diagnostic**: the rollout script (Task 11) handles this. **Fix**: run `bash adapters/claude-code/scripts/install-pr-template.sh <target-repo-path>`. Verify by opening a draft PR in the target repo and confirming the check appears.

- **Symptom**: I want to retroactively check whether the past N merged PRs would have passed the new check. **Diagnostic**: the validator library is sourceable as a script. **Fix**: run `bash adapters/claude-code/scripts/audit-merged-prs.sh --limit N` (Task 12) which iterates `gh pr list --state merged` and reports per-PR PASS/FAIL.
