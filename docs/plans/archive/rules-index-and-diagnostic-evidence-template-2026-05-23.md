# Plan: docs/rules-index + diagnostic-evidence PR-template extension
Status: COMPLETED
<!-- Closed 2026-06-04 by stale-ACTIVE-plan cleanup. Verified on master HEAD: rules/INDEX.md, evals/golden/rules-index-coverage.sh, "## Primary evidence" section in PULL_REQUEST_TEMPLATE.md, validate_evidence in validate-pr-template.sh (+ self-test cases). Both adjacent gaps shipped. Dispatch never ran task-verifier. -->
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 0
architecture: pattern
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal documentation + validator extension; no user-observable runtime — the verification artifact is the validator's `--self-test` (now 22 cases including 7 new evidence-section cases) plus the new `evals/golden/rules-index-coverage.sh` test exercising the INDEX↔directory sync.
Backlog items absorbed: none

## Goal

The expert review of 2026-05-23 surfaced two adjacent gaps:

1. **The rules system is sprawling and has no canonical entry point.** 45 rule
   files live under `adapters/claude-code/rules/`, each well-written
   individually, but discoverability across the set requires reading every
   file. Future maintainers need a one-page navigation aid.

2. **The diagnostic loop relies entirely on self-application.** The
   FM-001 case study (8+ days of misdiagnosis built on inferential evidence
   that never pulled runtime logs) is the canonical example of what happens
   when class-fix / sweep / refactor PRs ship without showing primary
   evidence. The harness has rules for the discipline (`diagnosis.md`
   DIAGNOSTIC-FIRST PROTOCOL + `claims.md` HYPOTHESIS-VS-PROOF LABELING),
   but no mechanical gate forces a sweep PR to demonstrate the evidence it
   was built on.

This plan ships both — a one-line-per-rule INDEX with CI enforcement that no
new rule lands without a row, AND a Primary-evidence PR-template section with
validator enforcement that requires it for any PR whose title contains `fix:`,
`sweep`, `class-sweep`, or `refactor`.

## User-facing Outcome

1. A future maintainer or reviewer can read `adapters/claude-code/rules/INDEX.md`
   and in under a minute know what rules exist, what type of enforcement each
   provides (Mechanism / Pattern / Hybrid / Convention), and when each fires.
2. A PR with `fix:` / `sweep:` / `class-sweep` / `refactor` in its title is
   mechanically blocked at PR-template-check time unless either the four-
   sub-section Primary-evidence block is filled OR an `[evidence-exempt:
   <reason ≥ 20 chars>]` opt-out marker is present.
3. A new rule file landing without an INDEX entry fails CI via
   `evals/golden/rules-index-coverage.sh`.

## Scope

- IN:
  - `adapters/claude-code/rules/INDEX.md` (new) — one-row-per-rule navigation table.
  - `evals/golden/rules-index-coverage.sh` (new) — CI check enforcing INDEX↔directory sync.
  - `.github/PULL_REQUEST_TEMPLATE.md` — adds a "## Primary evidence" section.
  - `.github/scripts/validate-pr-template.sh` — extends `validate_pr_body` with
    `validate_evidence`; adds 7 new self-test cases (16-22); total 22 cases.
  - `.github/workflows/pr-template-check.yml` — passes `PR_TITLE` env to the validator.
  - `docs/plans/rules-index-and-diagnostic-evidence-template-2026-05-23.md` — this plan.
- OUT: changes to existing rule files' content (the INDEX is a navigation aid,
  not a refactor); changes to other workflows like `server-side-enforcement.yml`
  (those run their own copy of the validator and inherit the extension
  automatically); branch-protection wiring (manual repo-admin action).

## Tasks

- [ ] 1. Land INDEX + coverage check + template + validator extension + plan, open draft PR — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/rules/INDEX.md` — new file. Table of 45 rules with
  filename, title, type (Mechanism/Pattern/Hybrid/Convention), trigger (one
  short sentence), and last-updated date.
- `evals/golden/rules-index-coverage.sh` — new golden test. Verifies every
  `*.md` under `adapters/claude-code/rules/` (except `INDEX.md` itself) has
  a backtick-quoted row in `INDEX.md`, and every backtick-quoted filename in
  the INDEX's table rows points at an existing file. Scopes the grep to
  table rows (lines starting with `|` `\``) to avoid false positives from
  cross-reference links in prose.
- `.github/PULL_REQUEST_TEMPLATE.md` — adds the "## Primary evidence (required
  for any sweep / class-fix / refactor PR)" section between the mechanism
  question and the testing-performed section. Four sub-sections (runtime/log
  evidence, what evidence showed, hypothesis tested, refutation criteria) +
  opt-out marker spec.
- `.github/scripts/validate-pr-template.sh` — extends the validator with:
  - New constants block for evidence-section heading + 4 sub-headings + 40-char
    sub-section threshold + 20-char opt-out threshold + title-trigger regex.
  - New failure-message types: `evidence_section_missing`,
    `evidence_subsection_missing`, `evidence_exempt_too_short`.
  - New functions: `pr_title_requires_evidence`, `detect_evidence_exemption`,
    `extract_evidence_section`, `validate_evidence_subsections`, `validate_evidence`.
  - `validate_pr_body` signature extended with optional 2nd arg (PR title) or
    PR_TITLE env. Backward compatible — without a title, the evidence check is
    skipped and the validator behaves exactly as before.
  - Self-test extended from 15 to 22 cases (7 new cases cover all evidence
    paths: skip-on-non-fix-title, fail-on-missing-section, pass-with-opt-out,
    fail-on-thin-opt-out, pass-with-substantive-evidence, fail-on-thin-sub-section,
    PR_TITLE-via-env).
- `.github/workflows/pr-template-check.yml` — passes `PR_TITLE` env var to the
  validator so the evidence-section check fires on title-triggered PRs.
- `docs/plans/rules-index-and-diagnostic-evidence-template-2026-05-23.md` — this plan file.

## Assumptions

- The 45 rules in `adapters/claude-code/rules/` are stable enough that a
  one-line-per-rule INDEX captures useful information without becoming stale
  every commit. Last-updated dates are pulled via `git log -1` and are
  point-in-time at INDEX authorship; they will drift but the trigger field is
  the load-bearing one.
- The 4-sub-section evidence-block shape is the minimum bar that catches the
  FM-001 failure mode. The FM-001 case study showed the agent could spend
  8 days building a fix without ever pulling runtime logs — requiring an
  explicit "what runtime/log evidence" field forces the diagnostic-first
  protocol to be visible in every sweep PR.
- The opt-out marker `[evidence-exempt: <reason>]` mirrors the
  `[docs-only]` / `[no-execution]` escape hatches that already exist in
  `vaporware-volume-gate.sh`. Authors who genuinely have a typo-only or
  rename-only PR can opt out with one line; the audit trail is preserved.
- The 20-char and 40-char thresholds mirror existing harness conventions:
  - 20 for substantive justification (mirror `acceptance-exempt-reason`,
    Stop-hook waivers).
  - 40 for sub-section content (mirror the (c) rationale threshold).

## Edge Cases

- **A `feat:` PR that incidentally fixes a recurring class.** The title-trigger
  regex matches only `fix:`/`sweep`/`class-sweep`/`refactor` — a `feat:` PR
  that includes a class fix as a side effect won't fire the gate. This is
  intentional: the evidence section's purpose is to catch PRs that CLAIM to
  fix a class. A feat PR can still include the evidence section voluntarily.
- **A PR whose title contains `prefix:` inside an unrelated token** (e.g.,
  `feat: implement json-schema:foo-bar`). The title-trigger regex uses word-
  boundary-ish anchors (`(^|[^a-z])(fix:|sweep|class-sweep|refactor)([^a-z]|$)`)
  to avoid this false positive.
- **A PR with both the strict-form and prose-form evidence-exempt markers.**
  The validator finds the first matching marker and uses its reason chars.
  If both are present and the first is too short but the second is
  substantive, the PR fails. Authors should write one marker, not two.
- **A rule file whose basename contains characters outside `[a-z0-9-]`.**
  The coverage check's regex would not pick it up. Current rules all use
  kebab-case ASCII; if a rule with underscores or non-ASCII chars lands, the
  regex needs widening.
- **A new rule file whose `# ` title differs from the INDEX's title cell.**
  The coverage check verifies presence-by-filename only, not title parity.
  This is intentional — the maintainer is responsible for keeping titles
  synced, and a broken title is a P3 cleanup, not a CI-blocker.

## Testing Strategy

- Local: `bash evals/golden/rules-index-coverage.sh` (currently PASS — 45
  rules indexed). `bash .github/scripts/validate-pr-template.sh --self-test`
  (currently PASS — 22 cases, including 7 new evidence-section cases).
- CI: the new coverage check runs as part of the existing `evals.yml`
  workflow (added in Task 1). The extended validator runs as part of the
  existing `pr-template-check.yml` workflow. Opening this draft PR is itself
  the test — the validator now scrutinizes its own PR body.

## In-flight scope updates

(none yet)

## Decisions Log

### Decision: backward-compatible validator signature
- **Tier:** 1
- **Status:** proceeded
- **Chosen:** `validate_pr_body <body> [pr_title]` with optional 2nd arg or
  PR_TITLE env var. Without a title, the evidence check skips and the
  validator behaves exactly as before.
- **Alternatives:** require the PR title as a mandatory 2nd arg; this would
  break any existing caller that does not pass title.
- **Reasoning:** the local pre-push hook at `git-hooks/pre-push-pr-template.sh`
  invokes the validator without a title (it operates on a local PR-body file
  before any push). Forcing it to compute a title would add complexity for a
  niche case; the env-var fallback is the simplest way to keep both paths
  working.
- **Checkpoint:** n/a (single commit)
- **To reverse:** revert the function signature; the new self-test cases stay
  green because the title is still optional.

### Decision: opt-out marker `[evidence-exempt: ...]` vs no opt-out
- **Tier:** 1
- **Status:** proceeded
- **Chosen:** opt-out with ≥ 20-char substantive reason. Pattern mirrors
  `[docs-only]` / `[no-execution]` markers in `vaporware-volume-gate.sh`.
- **Alternatives:** no opt-out (every fix:/sweep PR must fill the section).
- **Reasoning:** docs-typo and prose-only fix PRs use `fix:` in their title
  per convention. Without an opt-out, the rule becomes friction theater on
  those PRs. The 20-char threshold mirrors `acceptance-exempt-reason` and
  Stop-hook waivers — short enough to be cheap to write, long enough to
  preserve audit-trail signal.
- **Checkpoint:** n/a (single commit)
- **To reverse:** delete the `detect_evidence_exemption` path; PRs with
  legitimate exemptions would need to either remove the `fix:` prefix or
  fill the section with placeholder data (worse outcome).

## Definition of Done

- [ ] INDEX lands at `adapters/claude-code/rules/INDEX.md` with rows for all
      45 rule files.
- [ ] `evals/golden/rules-index-coverage.sh` lands and exits 0.
- [ ] PR template gets the new Primary-evidence section.
- [ ] Validator extended to 22 self-test cases, all PASS locally.
- [ ] `pr-template-check.yml` passes `PR_TITLE` env to the validator.
- [ ] Draft PR open against master, NOT merged.
- [ ] The PR body itself uses the new Primary-evidence section to demonstrate
      the format (meta-evidence: this PR is a refactor/fix-class PR by
      title, so it must pass its own gate).
