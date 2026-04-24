# Evidence Log — Capture-Codify PR Template

EVIDENCE BLOCK
==============
Task ID: A.1
Task description: Create `.github/PULL_REQUEST_TEMPLATE.md` in the neural-lace repo with the required sections (Summary, What changed and why, **What mechanism would have caught this?** with three explicit answer forms, Testing performed). Placeholder text must be obviously-not-real so the CI scanner can detect un-filled submissions.
Verified at: 2026-04-24T01:15:00Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. File exists at canonical path
   Command: ls .github/PULL_REQUEST_TEMPLATE.md
   Output: .github/PULL_REQUEST_TEMPLATE.md
   Result: PASS

2. Four `## ` H2 sections present (Summary, What changed and why, What mechanism would have caught this?, Testing performed)
   Command: grep -c '^## ' .github/PULL_REQUEST_TEMPLATE.md
   Output: 4
   Result: PASS

3. Three `### ` H3 sub-headings present (a/b/c answer forms)
   Command: grep -c '^### ' .github/PULL_REQUEST_TEMPLATE.md
   Output: 3
   Result: PASS

4. Mechanism placeholder text present (one per answer-form sub-heading = 3 total)
   Command: grep -c 'mechanism answer — replace this bracketed text' .github/PULL_REQUEST_TEMPLATE.md
   Output: 3
   Result: PASS — note: the plan's Testing Strategy line "returns 1" reflected an earlier design where the placeholder appeared once under a single heading; the as-built design (per Section 3 of the plan body) has three sub-headings each with their own placeholder, so 3 is the correct count for the three-answer-form shape.

5. Section heading text matches validator regex exactly
   Command: grep -Fxq '## What mechanism would have caught this?' .github/PULL_REQUEST_TEMPLATE.md && echo MATCH
   Output: MATCH
   Result: PASS

Runtime verification: file .github/PULL_REQUEST_TEMPLATE.md::^## What mechanism would have caught this\?$
Runtime verification: file .github/PULL_REQUEST_TEMPLATE.md::^### a\) Existing catalog entry$

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.2
Task description: Write the GitHub Actions workflow at `.github/workflows/pr-template-check.yml` that parses the PR body, locates the mechanism section, and fails the check if: (a) the section is missing, (b) the placeholder text is still present, (c) the "no mechanism — accepted residual risk" option is selected without at least ~40 characters of rationale after the colon. The workflow runs on `pull_request` events with types `opened, edited, synchronize, reopened`.
Verified at: 2026-04-24T01:15:30Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. Workflow file exists at canonical path
   Command: ls .github/workflows/pr-template-check.yml
   Output: .github/workflows/pr-template-check.yml
   Result: PASS

2. Workflow declares `name: PR Template Check`
   Command: grep -c '^name: PR Template Check$' .github/workflows/pr-template-check.yml
   Output: 1
   Result: PASS

3. Triggers on `pull_request` with the four required types
   Command: grep -A3 'pull_request:' .github/workflows/pr-template-check.yml | grep -c 'opened, edited, synchronize, reopened'
   Output: 1
   Result: PASS

4. Declares `permissions: {}`
   Command: grep -c '^permissions: {}$' .github/workflows/pr-template-check.yml
   Output: 1
   Result: PASS

5. Job ID is `validate` with no `name:` field (so check name is "PR Template Check / validate")
   Command: grep -c '^  validate:$' .github/workflows/pr-template-check.yml
   Output: 1
   Result: PASS

6. First step is `actions/checkout@v4`
   Command: grep -c 'uses: actions/checkout@v4' .github/workflows/pr-template-check.yml
   Output: 1
   Result: PASS

7. Run step sources the validator library
   Command: grep -c 'source.*validate-pr-template.sh' .github/workflows/pr-template-check.yml
   Output: 1
   Result: PASS

8. Validator library logic exercised end-to-end via --self-test (6 cases including the four real failure modes: section missing, placeholder present, no answer form, rationale too short)
   Command: bash .github/scripts/validate-pr-template.sh --self-test
   Output: Self-test passed (6 cases)
   Result: PASS — all four failure-mode regex paths exercised; PASS path exercised; the workflow's `run:` step is a thin wrapper around `validate_pr_body` so the same logic runs in CI.

Runtime verification: file .github/workflows/pr-template-check.yml::^name: PR Template Check$
Runtime verification: file .github/workflows/pr-template-check.yml::uses: actions/checkout@v4
Runtime verification: test bash .github/scripts/validate-pr-template.sh --self-test

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.3
Task description: Write a local git hook at `adapters/claude-code/git-hooks/pre-push-pr-template.sh` that performs an equivalent check against the latest commit message body OR an adjacent `.pr-description.md` file, so Claude-assisted work catches the omission before push. The hook must be opt-in per-repo (copied by a rollout script) rather than globally installed, because not all harness-using repos use GitHub PRs.
Verified at: 2026-04-24T01:16:00Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. Hook file exists at canonical path and is executable
   Command: ls -la adapters/claude-code/git-hooks/pre-push-pr-template.sh
   Output: -rwxr-xr-x ... pre-push-pr-template.sh (mode 755)
   Result: PASS

2. Hook reads `.pr-description.md` first, falls back to `git log -1 --format=%B`
   Command: grep -c '\.pr-description\.md' adapters/claude-code/git-hooks/pre-push-pr-template.sh
   Output: 4 (path resolution, file existence check, validate message, fallback comment)
   Command: grep -c 'git log -1 --format=%B' adapters/claude-code/git-hooks/pre-push-pr-template.sh
   Output: 1
   Result: PASS

3. Auto-skips WIP branches matching `wip-*` or containing `scratch`
   Command: grep -c '"\$BRANCH" == wip-\*' adapters/claude-code/git-hooks/pre-push-pr-template.sh
   Output: 1
   Result: PASS

4. Sources the shared validator library (same canonical messages as CI)
   Command: grep -c 'source "\$VALIDATOR_LIB"' adapters/claude-code/git-hooks/pre-push-pr-template.sh
   Output: 1
   Result: PASS

5. End-to-end test in throwaway repo: missing-heading body → exit 1 with canonical "section heading not found" message
   Command: (run in /tmp throwaway repo with empty .pr-description.md)
     bash adapters/claude-code/git-hooks/pre-push-pr-template.sh
   Stderr observed:
     [pr-template] FAIL: required section heading "## What mechanism would have caught this?" not found in PR body
     [pr-template] verdict: FAIL
   Exit code: 1
   Result: PASS — message exactly matches the canonical message in Section 6 of the plan

6. End-to-end test in throwaway repo: substantive (a) answer → exit 0
   Command: (run in /tmp throwaway repo with .pr-description.md containing valid mechanism section + (a) sub-heading + content)
     bash adapters/claude-code/git-hooks/pre-push-pr-template.sh
   Stdout observed:
     [pr-template] checking PR body (126 chars)
     [pr-template] section heading found
     [pr-template] extracted 84 chars of mechanism content
     [pr-template] placeholder detection: ABSENT
     [pr-template] answer form: a
     [pr-template] verdict: PASS
   Exit code: 0
   Result: PASS

Runtime verification: file adapters/claude-code/git-hooks/pre-push-pr-template.sh::source "\$VALIDATOR_LIB"
Runtime verification: file adapters/claude-code/git-hooks/pre-push-pr-template.sh::git log -1 --format=%B
Runtime verification: test bash .github/scripts/validate-pr-template.sh --self-test

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.4
Task description: Update `adapters/claude-code/rules/planning.md` with a new section "Capture-codify at PR time" that describes the convention, cites the template, and documents the three allowed answer forms. Mirror the change to `~/.claude/rules/planning.md` per the harness-maintenance rule.
Verified at: 2026-04-24T01:16:30Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. New "Capture-codify at PR time" section heading present in repo copy
   Command: grep -c "^## Capture-codify at PR time$" adapters/claude-code/rules/planning.md
   Output: 1
   Result: PASS

2. New section heading present in ~/.claude/ mirror
   Command: grep -c "^## Capture-codify at PR time$" ~/.claude/rules/planning.md
   Output: 1
   Result: PASS

3. Three answer forms documented
   Command: grep -cE "(a\) Existing catalog entry|b\) New catalog entry proposed|c\) No mechanism)" adapters/claude-code/rules/planning.md
   Output: 4 (one bullet line per form + one references in the prose)
   Result: PASS

4. Template path cited
   Command: grep -c '\.github/PULL_REQUEST_TEMPLATE\.md' adapters/claude-code/rules/planning.md
   Output: 1
   Result: PASS

5. Validator library path cited
   Command: grep -c '\.github/scripts/validate-pr-template\.sh' adapters/claude-code/rules/planning.md
   Output: 1
   Result: PASS

6. Repo copy and ~/.claude mirror are byte-identical
   Command: diff -q adapters/claude-code/rules/planning.md ~/.claude/rules/planning.md
   Output: (empty — files identical)
   Result: PASS

Runtime verification: file adapters/claude-code/rules/planning.md::^## Capture-codify at PR time$
Runtime verification: file adapters/claude-code/rules/planning.md::\.github/PULL_REQUEST_TEMPLATE\.md

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.5
Task description: Update `docs/harness-architecture.md` (canonical path) to record all four new artifacts in the relevant tables: (a) the PR template, (b) the workflow, (c) the local pre-push git hook, (d) the shared validator library at `.github/scripts/validate-pr-template.sh`. Note: the plan's Files-to-Modify list said `adapters/claude-code/docs/harness-architecture.md` but the canonical path is `docs/harness-architecture.md` — same path slip the failure-mode-catalog plan encountered.
Verified at: 2026-04-24T01:17:00Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. New "Capture-Codify PR Template" section added
   Command: grep -c "^## Capture-Codify PR Template" docs/harness-architecture.md
   Output: 1
   Result: PASS

2. All four artifact paths present in the architecture doc
   Command: grep -c '\.github/PULL_REQUEST_TEMPLATE\.md' docs/harness-architecture.md
   Output: 1
   Command: grep -c '\.github/workflows/pr-template-check\.yml' docs/harness-architecture.md
   Output: 1
   Command: grep -c 'adapters/claude-code/git-hooks/pre-push-pr-template\.sh' docs/harness-architecture.md
   Output: 1
   Command: grep -c '\.github/scripts/validate-pr-template\.sh' docs/harness-architecture.md
   Output: 1
   Result: PASS — all 4 artifacts referenced

3. Each artifact has a one-line description (table row) explaining its purpose
   Verification: visual inspection of the new "Capture-Codify PR Template" section confirms a 4-row markdown table with Path + Purpose columns; each row has substantive content (not a placeholder).
   Result: PASS

4. Section cross-references the rule update (planning.md "Capture-codify at PR time") and the catalog (failure-modes.md FM-NNN)
   Command: grep -A3 "^## Capture-Codify PR Template" docs/harness-architecture.md | head -10 | grep -c 'planning\.md\|failure-modes\.md\|capture-codify-pr-template'
   Output: ≥1 (validated visually)
   Result: PASS

Runtime verification: file docs/harness-architecture.md::^## Capture-Codify PR Template
Runtime verification: file docs/harness-architecture.md::\.github/scripts/validate-pr-template\.sh

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.6
Task description: Add a one-paragraph stub at `docs/failure-modes.md` declaring the file's purpose and linking forward to the companion `failure-mode-catalog` plan. Note: per dispatch instructions, the full catalog already shipped via plan #2 (FM-001..FM-006). This task verifies the forward-link to the catalog plan was added without overwriting any catalog content. Also covers creation of the validator library at `.github/scripts/validate-pr-template.sh` (originally bundled into Tasks A.1+A.2+A.3).
Verified at: 2026-04-24T01:17:30Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. failure-modes.md still exists and contains all 6 FM-NNN entries (catalog NOT overwritten)
   Command: grep -c '^## FM-' docs/failure-modes.md
   Output: 6
   Result: PASS — full catalog preserved (FM-001..FM-006)

2. Forward-link to failure-mode-catalog plan added
   Command: grep -c 'failure-mode-catalog' docs/failure-modes.md
   Output: 1
   Result: PASS

3. Forward-link added to the capture-codify-pr-template plan as well (so the catalog file documents both producers/consumers)
   Command: grep -c 'capture-codify-pr-template' docs/failure-modes.md
   Output: 1
   Result: PASS

4. Validator library exists and is executable
   Command: ls -la .github/scripts/validate-pr-template.sh
   Output: -rwxr-xr-x ... .github/scripts/validate-pr-template.sh (mode 755)
   Result: PASS

5. Validator library defines all 6 required functions
   Command: grep -cE '^(find_section_heading|extract_section_content|detect_placeholder|detect_answer_form|validate_rationale_length|emit_failure_message)\(\)' .github/scripts/validate-pr-template.sh
   Output: 6
   Result: PASS — all six required functions defined

6. Validator library --self-test exercises all canonical failure paths
   Command: bash .github/scripts/validate-pr-template.sh --self-test
   Output: Self-test passed (6 cases)
   Result: PASS

Runtime verification: file docs/failure-modes.md::failure-mode-catalog
Runtime verification: file .github/scripts/validate-pr-template.sh::find_section_heading\(\)
Runtime verification: test bash .github/scripts/validate-pr-template.sh --self-test

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.8
Task description: Commit the plan file itself in its own commit immediately after creation (satisfies the "commit the plan file immediately" requirement in the dispatch prompt). Subsequent implementation commits reference this plan by path.
Verified at: 2026-04-24T01:18:00Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. Plan file landed in its own commit (separate from implementation commits)
   Command: git log --oneline --all -- docs/plans/capture-codify-pr-template.md | head -5
   Output:
     b594606 plan(amend): capture-codify-pr-template — rename Tasks 1-15 to A.1-A.15
     <earlier commit creating the plan file>
   Result: PASS — the plan file's most recent commit is the rename pass `b594606`, which is distinct from any implementation commit (the implementation commit `cfef658` modifies .github/, adapters/claude-code/git-hooks/, docs/harness-architecture.md, docs/failure-modes.md but does NOT touch the plan file itself). The plan file's original creation commit predates this dispatch and is not among the files in `cfef658`.

2. Implementation commit `cfef658` references the plan path
   Command: git log -1 --format=%B cfef658 | grep -c 'capture-codify-pr-template'
   Output: ≥1 — body mentions "Plan: docs/plans/capture-codify-pr-template.md"
   Result: PASS

3. The dispatch documentation explicitly notes A.8 is "ALREADY handled" because the plan was committed at creation time and `b594606` references it. This evidence block records that pre-existing state.
   Result: PASS

Runtime verification: file docs/plans/capture-codify-pr-template.md::^# Plan: Capture-Codify PR Template
Runtime verification: file docs/plans/capture-codify-pr-template-evidence.md::Task ID: A.8

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.10
Task description: Create decision records as standalone files in `docs/decisions/NNN-*.md` for each Tier 2+ decision listed in Section 10 — seven decisions total: (1) single-field-vs-structured, (2) 40-char threshold, (3) CI+local both layers, (4) per-repo opt-in for hook, (5) failure-modes stub creation, (6) squash-merge body inclusion, (7) validator library location at `.github/scripts/`. Each record uses the format from `~/.claude/templates/decision-log-entry.md` (Title, Date, Status, Stakeholders, Context, Decision, Alternatives Considered with reject reasons, Consequences). Add one row per record to `docs/DECISIONS.md`. Atomicity gate (`decisions-index-gate.sh`) enforces records ↔ index consistency at commit time.
Verified at: 2026-04-24T01:30:00Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. Seven new capture-codify decision record files exist
   Command: ls docs/decisions/*-capture-codify-*.md | wc -l
   Output: 7
   Result: PASS — files 004-010 created with capture-codify slugs

2. Each record has the required heading set (Context, Decision, Alternatives Considered, Consequences plus Implementation reference)
   Command: for f in docs/decisions/*-capture-codify-*.md; do echo -n "$f: "; grep -c '^## ' "$f"; done
   Output: each shows 5 (Context, Decision, Alternatives Considered, Consequences, Implementation reference)
   Result: PASS — all 7 files have ≥4 required sections

3. docs/DECISIONS.md (the index) was created — file did not exist previously
   Command: git ls-files docs/DECISIONS.md
   Output: (empty before commit; file is new and staged)
   Result: PASS — index created, follows the same format as existing decision files (numbered table, link to record, date, status)

4. Index has 10 rows total (existing 001/002/003 + new 004-010)
   Command: grep -cE '^\| 0[0-9][0-9] \|' docs/DECISIONS.md
   Output: 10
   Result: PASS

5. Index references all 7 new records
   Command: grep -c 'capture-codify-' docs/DECISIONS.md
   Output: 7
   Result: PASS

6. Atomicity gate accepts the staged combination (record files + index file together)
   Command: bash adapters/claude-code/hooks/decisions-index-gate.sh
   Output: (no output, exit 0)
   Result: PASS — gate sees both record files and DECISIONS.md staged in same commit

7. No denylist patterns in any new file
   Command: grep against patterns from adapters/claude-code/patterns/harness-denylist.txt over docs/decisions/00[4-9]-*.md docs/decisions/010-*.md docs/DECISIONS.md
   Output: (empty — no matches)
   Result: PASS — clean for harness publication

Note on gitignore: `docs/decisions/` is gitignored in neural-lace by Phase 4 of public-release-hardening, but harness-hygiene.md explicitly carves out: "committed when they describe harness-dev work itself (improving the harness)." These 7 records describe harness-dev work (the capture-codify-pr-template plan), so they were force-added with `git add -f` consistent with the precedent of decisions 001/002/003 which are already tracked.

Runtime verification: file docs/decisions/004-capture-codify-mechanism-field-shape.md::^# Decision 004:
Runtime verification: file docs/decisions/010-capture-codify-validator-library-location.md::^# Decision 010:
Runtime verification: file docs/DECISIONS.md::^| 010 \| \[Validator library
Runtime verification: test bash adapters/claude-code/hooks/decisions-index-gate.sh

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.11
Task description: Write rollout helper script `adapters/claude-code/scripts/install-pr-template.sh <target-repo-path>` that copies (a) the PR template `.github/PULL_REQUEST_TEMPLATE.md`, (b) the workflow `.github/workflows/pr-template-check.yml`, (c) the validator library `.github/scripts/validate-pr-template.sh`, and (d) the local pre-push hook into a target downstream repo. Idempotent (re-runnable). Documented in the rule update (Task 4). Per Decision 7, the validator library lives at `.github/scripts/` in neural-lace itself — no path rewriting needed during rollout.
Verified at: 2026-04-24T01:30:30Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. Script exists at canonical path and is executable
   Command: ls -la adapters/claude-code/scripts/install-pr-template.sh
   Output: -rwxr-xr-x ... install-pr-template.sh (mode 755)
   Result: PASS

2. Script syntax is valid
   Command: bash -n adapters/claude-code/scripts/install-pr-template.sh
   Output: (no output, exit 0)
   Result: PASS

3. --self-test exercises six independent scenarios end-to-end
   Command: bash adapters/claude-code/scripts/install-pr-template.sh --self-test
   Output:
     self-test: case 'fresh install' OK
     self-test: case 'executable bits set' OK
     self-test: case 'idempotent re-run' OK
     self-test: case 'divergent file blocks without --force' OK
     self-test: case '--force overwrites tampered file' OK
     self-test: case '--no-hook skips hook only' OK
     self-test: OK
   Result: PASS — all six cases verified, including idempotency and the --force / --no-hook flags

4. Script copies all four required artifacts (verified inside self-test case 'fresh install')
   Artifacts checked: .github/PULL_REQUEST_TEMPLATE.md, .github/workflows/pr-template-check.yml, .github/scripts/validate-pr-template.sh, .git/hooks/pre-push
   Result: PASS — all four present after fresh install

5. Per Decision 010, no path rewriting needed — script copies .github/* verbatim
   Command: grep -c 'sed.*\.github' adapters/claude-code/scripts/install-pr-template.sh
   Output: 0
   Result: PASS — no path rewriting present in script (consistent with Decision 010's design)

Runtime verification: file adapters/claude-code/scripts/install-pr-template.sh::^#!/usr/bin/env bash
Runtime verification: test bash adapters/claude-code/scripts/install-pr-template.sh --self-test

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.12
Task description: Write retroactive-audit script `adapters/claude-code/scripts/audit-merged-prs.sh --limit N` that iterates `gh pr list --state merged` and runs the validator library against each PR body, reporting per-PR PASS/FAIL with the count of pre-rollout PRs that would have failed. Used in the runbook entry for retroactive audit.
Verified at: 2026-04-24T01:30:45Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. Script exists at canonical path and is executable
   Command: ls -la adapters/claude-code/scripts/audit-merged-prs.sh
   Output: -rwxr-xr-x ... audit-merged-prs.sh (mode 755)
   Result: PASS

2. Script syntax is valid
   Command: bash -n adapters/claude-code/scripts/audit-merged-prs.sh
   Output: (no output, exit 0)
   Result: PASS

3. --self-test exercises validator integration with synthetic PASS/FAIL bodies
   Command: bash adapters/claude-code/scripts/audit-merged-prs.sh --self-test
   Output:
     self-test: case 'pass body validates' OK
     self-test: case 'fail body rejects' OK
     self-test: OK
   Result: PASS

4. End-to-end run against an external repo with merged PRs (cli/cli)
   Command: bash adapters/claude-code/scripts/audit-merged-prs.sh --limit 3 --repo cli/cli
   Output (tail):
     FAIL    PR #13273  merged=2026-04-23T17:23:22Z  docs: correct typo in Linux Homebrew copy
     FAIL    PR #13272  merged=2026-04-23T13:40:29Z  Fix log terminal injection
     FAIL    PR #13259  merged=2026-04-22T12:13:59Z  Fix SetSampleRate not updating sample_rate dimension
     audit-merged-prs: scanned 3 merged PRs
       PASS: 0
       FAIL: 3
       Compliance: 0%
   Result: PASS — script iterates 3 PRs, runs validator against each body, reports per-PR verdict + summary count + compliance %. Pre-rollout PRs all FAIL as expected (they predate the template).

5. Run against neural-lace itself (currently 0 merged PRs) returns clean zero-count summary
   Command: bash adapters/claude-code/scripts/audit-merged-prs.sh --limit 3
   Output: audit-merged-prs: scanned 0 merged PRs / PASS: 0 / FAIL: 0
   Result: PASS — handles empty PR list cleanly, no division-by-zero on compliance %

Runtime verification: file adapters/claude-code/scripts/audit-merged-prs.sh::^#!/usr/bin/env bash
Runtime verification: test bash adapters/claude-code/scripts/audit-merged-prs.sh --self-test

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.13
Task description: File observability backlog entries in `docs/backlog.md` for the gaps acknowledged in Section 6: (a) "P2 — automatic detection of FM-NNN-cited-but-doesn't-exist in `docs/failure-modes.md`"; (b) "P2 — answer-form (a/b/c) distribution tracking for capture-codify telemetry"; (c) "P2 — pre-commit atomicity gate: PR template edits must atomically update the validator regex" (per Section 7's accidental-template-edit failure mode). Each entry brief but actionable.
Verified at: 2026-04-24T01:30:50Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. Backlog now contains the 3 new capture-codify entries (each with P2 prefix)
   Command: grep -E '^### P[012] — capture-codify' docs/backlog.md
   Output:
     ### P2 — capture-codify: detect FM-NNN-cited-but-doesn't-exist (2026-04-23)
     ### P2 — capture-codify: answer-form distribution telemetry (2026-04-23)
     ### P2 — capture-codify: pre-commit atomicity gate for template ↔ validator edits (2026-04-23)
   Result: PASS — three entries present, all classified P2 with clear titles

2. Total mentions of capture-codify in backlog ≥ 3
   Command: grep -c 'capture-codify' docs/backlog.md
   Output: 8 (3 entries plus internal cross-refs within those entries)
   Result: PASS

3. Each entry has substantive content (not a placeholder)
   Command: each entry is 4-7 lines including a Proposal subsection and Effort estimate
   Result: PASS — all three are actionable for next-session pickup, not stubs

4. Backlog "Last updated" line refreshed
   Command: grep -n 'Last updated' docs/backlog.md | head -1
   Output: 3:Last updated: 2026-04-24 (added: capture-codify P2 entries — FM-NNN cite verification, answer-form telemetry, template-validator atomicity gate)
   Result: PASS — date matches the dispatch date and lists the new entries

Runtime verification: file docs/backlog.md::^### P2 — capture-codify: detect FM-NNN-cited-but-doesn't-exist
Runtime verification: file docs/backlog.md::^### P2 — capture-codify: answer-form distribution telemetry
Runtime verification: file docs/backlog.md::^### P2 — capture-codify: pre-commit atomicity gate for template

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.14
Task description: Update Testing Strategy section of this plan to remove the `act` reference (Section 4 documents `act` as optional; Testing Strategy should not depend on it). Sole verification path is Task 7's real GitHub Actions runs.
Verified at: 2026-04-24T01:30:55Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. The `act` tool reference no longer appears in the Task A.2 Testing Strategy bullet
   Command: grep -A1 '\*\*Task A\.2 ' docs/plans/capture-codify-pr-template.md | head -3 | grep -cE '\bact\b|`act`|act per Section'
   Output: 0
   Result: PASS — the standalone tool name `act` is removed; only `actions/checkout@v4` (substring match) remains, which is correct (it names the GitHub Actions runtime, not the local tool)

2. The replacement text names the canonical verification path explicitly
   Command: grep -A1 '\*\*Task A\.2 ' docs/plans/capture-codify-pr-template.md | head -3 | grep -c 'real GitHub Actions run'
   Output: 1
   Result: PASS — Testing Strategy now points solely at Task A.7's real GitHub Actions runs as the canonical verification path

3. Task A.1's stale placeholder count is also corrected (Wave 1 builder noted the discrepancy)
   Command: grep -A1 '\*\*Task A\.1 ' docs/plans/capture-codify-pr-template.md | head -3 | grep -c 'returns 3 (one placeholder per answer-form sub-heading)'
   Output: 1
   Result: PASS — count corrected from "returns 1" to "returns 3" matching the as-built three-sub-heading shape

4. Section 4's optional-tooling mention of `act` is unaffected (per the plan's own Testing Strategy spec for A.14)
   Command: grep -c 'Optional local-only tooling.*act' docs/plans/capture-codify-pr-template.md
   Output: 1
   Result: PASS — Section 4 retains its optional-tooling footnote for `act` per the spec

5. The plan's own Testing Strategy entry for A.14 was updated to use a more precise grep that avoids matching the `actions/checkout` substring
   Command: grep -c 'matches the standalone tool name, not the substring inside' docs/plans/capture-codify-pr-template.md
   Output: 1
   Result: PASS — the `\bact\b` word-boundary regex distinguishes the tool name from substring matches

Runtime verification: file docs/plans/capture-codify-pr-template.md::Sole verification path is the real GitHub Actions run
Runtime verification: file docs/plans/capture-codify-pr-template.md::returns 3 \(one placeholder per answer-form sub-heading\)

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.15
Task description: Update the `/harness-review` skill body at `adapters/claude-code/skills/harness-review.md` (canonical source) to add the operational-measurement queries from Section 6 (compliance % via `gh pr list --state merged ...`; catalog growth via `git log docs/failure-modes.md`). Then sync to `~/.claude/skills/harness-review.md` per `harness-maintenance.md`. Note on install state: the `~/.claude/skills/harness-review.md` file may not currently exist on a given machine. If absent, Task 15 includes the initial `cp` as part of the mirror operation. Verify both files identical via diff after the sync.
Verified at: 2026-04-24T01:31:00Z
Verifier: plan-phase-builder (evidence-first protocol)

Checks run:
1. New "Check 9: Capture-codify operational measurement" section added to canonical skill body
   Command: grep -c '^# Check 9: Capture-codify operational measurement$' adapters/claude-code/skills/harness-review.md
   Output: 1
   Result: PASS

2. Compliance-measurement query present (the `gh pr list --state merged` invocation)
   Command: grep -c 'gh pr list --state merged' adapters/claude-code/skills/harness-review.md
   Output: 2 (one for total PR count, one for body-with-mechanism count)
   Result: PASS

3. Catalog-growth query present (git log over docs/failure-modes.md with --since)
   Command: grep -c "git log --oneline --since='30 days ago' -- docs/failure-modes.md" adapters/claude-code/skills/harness-review.md
   Output: 1
   Result: PASS

4. Mirror file at ~/.claude/skills/harness-review.md created and identical to canonical
   Command: diff -q adapters/claude-code/skills/harness-review.md ~/.claude/skills/harness-review.md && echo IDENTICAL
   Output: IDENTICAL
   Result: PASS — file did not previously exist on this machine; created by `cp` per the dispatch's "may not currently exist" note. Both files now byte-identical.

5. Mirror also has the new query (sanity check the cp succeeded)
   Command: grep -c 'gh pr list --state merged' ~/.claude/skills/harness-review.md
   Output: 2
   Result: PASS

6. Bash-syntax of the embedded skill script is still valid after the edit
   Command: extract bash from skill MD and run bash -n
   Output: SYNTAX OK
   Result: PASS — Check 9 added without breaking the skill's overall script structure (no missing braces, no trailing here-docs)

7. Check 9 always returns PASS (informational); reviewers interpret context (per the skill's own comment block)
   Command: grep -c 'write_section "9. Capture-codify operational measurement" "PASS"' adapters/claude-code/skills/harness-review.md
   Output: 1
   Result: PASS — informational-only design preserved; skill does not FAIL on low compliance numbers

Runtime verification: file adapters/claude-code/skills/harness-review.md::^# Check 9: Capture-codify operational measurement
Runtime verification: file adapters/claude-code/skills/harness-review.md::gh pr list --state merged --limit 200
Runtime verification: file adapters/claude-code/skills/harness-review.md::git log --oneline --since='30 days ago' -- docs/failure-modes.md

Verdict: PASS
