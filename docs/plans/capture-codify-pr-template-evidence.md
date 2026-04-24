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
