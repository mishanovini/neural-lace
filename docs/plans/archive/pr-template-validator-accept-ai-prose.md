# Plan: PR Template Validator — Accept AI-Natural Prose Answer Form
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: harness-internal
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal validator change; self-tests are the acceptance artifact (15-case --self-test extended from 9, plus 3 reconstructed-failing-PR-body replays)
Backlog items absorbed: none

## Goal

13 of the last 17 `PR Template Check / validate` CI runs failed with
`answer form: NONE`. The validator required the strict
`### a) / ### b) / ### c)` heading scaffold, but AI-spawned PRs naturally
write the answer as a prose paragraph (`**(b) New catalog entry proposed.**
…content…`). The failures keep recurring because the validator's contract
and AI's natural PR-writing form are misaligned.

Add a graceful fallback in `validate-pr-template.sh`: when the strict
heading form is not detected, look for the AI-prose form. Either form
must back the selection with ≥30 chars of substantive non-placeholder
content; the (c)-rationale ≥40-char rule still applies in the prose
path. Strict form remains primary detector. Document both accepted
writing styles in the PR template and the capture-codify rule.

## Scope

- IN:
  - `.github/scripts/validate-pr-template.sh` — add `detect_ai_prose_form`
    + `validate_rationale_length_prose` + form_source-aware branch in
    `validate_pr_body` + 6 new self-test cases (10-15).
  - `.github/PULL_REQUEST_TEMPLATE.md` — brief note that two writing
    styles are accepted.
  - `adapters/claude-code/rules/planning.md` — Capture-codify section
    documents both accepted forms.
  - Live mirror sync: `~/.claude/rules/planning.md`.

- OUT:
  - Retroactive editing of already-merged PR bodies (the failing checks
    didn't block merge; they were noise).
  - Changes to other validators or hooks beyond what's strictly needed
    for the form-fallback fix.
  - Changes to AI-session PR-creation prompts (the validator's
    graceful fallback eliminates the need).

## Tasks

- [x] 1. Add prose-form detector + form_source branching + 6 new self-test cases. Verification: mechanical
- [x] 2. Update PR template with both-forms-accepted note. Verification: mechanical
- [x] 3. Update planning.md capture-codify section documenting both forms; sync to live mirror byte-identical. Verification: mechanical
- [x] 4. Replay 3 reconstructed failing PR bodies through patched validator (PR #20, v1.1.1-polish, Dispatch-reader); all PASS via prose path. Verification: mechanical

## Files to Modify/Create

- `.github/scripts/validate-pr-template.sh` — prose-form detector + branched validator + extended self-test
- `.github/PULL_REQUEST_TEMPLATE.md` — document both writing styles
- `adapters/claude-code/rules/planning.md` — capture-codify rule update
- `docs/plans/pr-template-validator-accept-ai-prose.md` — this plan file

## Assumptions

- The dominant 13/17 failure pattern is AI-prose-form; verified by sampling 11
  failing runs from the past 4 days.
- Loosening the validator to accept prose form does not erode the capture-codify
  discipline — the substance check (≥30 chars non-placeholder, plus
  ≥40-char (c) rationale) is preserved.
- The validator's library at `.github/scripts/` is the single source consumed
  by both CI (`pr-template-check.yml`) and the local pre-push hook; one fix
  propagates to both.

## Edge Cases

- Body containing BOTH `### b)` heading AND `(b)` prose line → heading wins
  (covered by self-test case 14).
- Prose form with just `(b)` and no substantive content → still FAIL
  (case 13; substance threshold).
- Prose form (c) with too-short rationale → still FAIL (case 12).
- Prose author who pasted placeholder text into prose → FAIL via
  whole-section placeholder check (case 15).

## Testing Strategy

- `bash .github/scripts/validate-pr-template.sh --self-test` → 15/15 PASS
  (9 original + 6 new).
- Replay 3 reconstructed failing PR bodies via `validate_pr_body` → all PASS
  via `source: prose` path.
- Live mirror byte-identical via `diff -q
  adapters/claude-code/rules/planning.md ~/.claude/rules/planning.md`.

## Walking Skeleton

The thinnest end-to-end slice is: a single PR body with `(b) ...content...`
prose runs through `validate_pr_body` and exits PASS. That slice is
implemented by `detect_ai_prose_form` + the `form_source=prose` branch in
`validate_pr_body`. Everything else (substance threshold, placeholder check
for prose form, rationale-length check for prose-form (c)) elaborates the
same slice with edge-case coverage.

## In-flight scope updates

(none)

## Decisions Log

### Decision: prose-form is fallback, not replacement
- **Tier:** 1 (reversible)
- **Status:** proceeded with recommendation
- **Chosen:** heading form remains primary detector; prose form is fallback when heading returns NONE
- **Alternatives:** (a) replace heading detector entirely with prose; (b) accept both equivalently with explicit preference setting
- **Reasoning:** preserves original capture-codify contract (humans filling the template scaffold get exact same behavior as before); the prose path only activates when the strict path would have FAILED with `answer form: NONE`. Zero risk of regressing the existing 4 PRs that already PASS heading-form.
- **Checkpoint:** N/A (single commit)
- **To reverse:** revert this commit; validator returns to strict-heading-only

### Decision: prose-form placeholder check scopes to whole section
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** when form_source=prose, placeholder check scopes to whole section minus any unselected `###` sub-heading content
- **Alternatives:** (a) skip placeholder check entirely for prose form; (b) require prose authors to delete all sub-heading scaffolds
- **Reasoning:** prose form has no sub-section boundaries; the strict-form's per-sub-section scoping doesn't apply. Excluding text inside unselected `###` sub-headings prevents double-penalty for prose authors who left the scaffold partially in place. In practice prose-form PRs omit the scaffold entirely so the distinction rarely matters.
- **To reverse:** simplify placeholder check to whole-section-no-exclusion; semantics differ only for the rare hybrid PR

## Definition of Done

- [x] All tasks checked off
- [x] All self-tests pass (15/15)
- [x] Three reconstructed failing PR bodies PASS via patched validator
- [x] Live mirror sync verified byte-identical
- [x] SCRATCHPAD.md not applicable (harness-internal narrow fix)
- [x] Completion report appended below

## Completion Report

### 1. Implementation Summary

Shipped in commit `e1f471e` (validator + rule + template + plan) + merge
`3e3098c` (master into branch). Merged to master via `gh pr merge --merge` at
commit `f70e1e6` on 2026-05-22T01:48:44Z (PR #21).

Backlog items absorbed: none (header declared `none`).

### 2. Design Decisions & Plan Deviations

Two decisions in the Decisions Log above:

1. prose-form is fallback, not replacement (heading detector remains primary)
2. prose-form placeholder check scopes to whole section minus unselected `###`
   sub-headings

No deviations from the original plan; tasks executed in declared order.

### 3. Known Issues & Gotchas

- AI-prose form detector is permissive on the label-phrase after `(x)`. It only
  requires the leading `(a)`, `(b)`, or `(c)` marker; the rest of the line
  could in principle be arbitrary prose. The substantive-content threshold
  (≥30 chars non-placeholder in section) and the (c)-rationale threshold
  (≥40 chars) are the substance guardrails. In practice AI sessions write a
  recognizable label phrase after `(x)` anyway.
- The fix accepts both forms uniformly across all PRs. Future PRs (human or AI)
  may use either form; both pass the validator.

### 4. Manual Steps Required

None. The fix took effect the moment PR #21 merged. The next PR opened against
neural-lace will use the patched validator.

### 5. Testing Performed & Recommended

Performed:

- `bash .github/scripts/validate-pr-template.sh --self-test` → 15/15 PASS
- Replay of 3 reconstructed failing PR bodies → all PASS via `source: prose`
- Live mirror sync via `diff -q ... ... && echo MIRRORED OK`
- **End-to-end integration test**: PR #21's own body used AI-prose form; CI run
  `26263692560` returned `[pr-template] answer form: b (source: prose)` →
  `verdict: PASS`

Recommended (not blocking):

- Periodic review of `gh run list --status failure --workflow "PR Template Check"`
  to confirm the failure rate has dropped. If a new failure pattern emerges,
  the diagnosis-rule's "After Every Failure: Encode the Fix" loop applies.

### 6. Cost Estimates

Zero recurring cost. The fix is a bash regex addition in a validator script
that runs on every PR. CI minute usage is unchanged.
