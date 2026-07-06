# Plan: NL-FINDING-030 — rerun-safe CI body fetch (fix 2 of 2) (design-skip)
Status: ACTIVE
Execution Mode: direct
Mode: design-skip
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-dev CI/validator change with no product user; the deliverable is the validator --self-test (23/23) plus harness-reviewer PASS, not a user-facing surface.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Why design-skip

The two `.github/workflows/*.yml` edits — `pr-template-check.yml` and
`server-side-enforcement.yml` — trip the systems-design-gate, but the change is
trivial and localized: each swaps the SOURCE of the PR body/title from the frozen
`github.event.pull_request.*` webhook payload to a run-time `gh pr view --json
body,title` fetch. No new job, no new external dependency (`gh` + `jq` are
pre-installed on `ubuntu-latest`), no new infrastructure, no change to the validator's
pass/fail contract. It reverts in one commit. This is exactly the "CI-config change
with no systems-design surface" case the design-skip hatch exists for.

## Change

- `.github/workflows/pr-template-check.yml` and `.github/workflows/server-side-enforcement.yml`
  (job `pr-template-redundancy`): fetch body/title via `gh pr view "$PR_NUMBER" --json
  body,title` at run time instead of the creation-time event payload, so job reruns
  validate the CURRENT body. Adds a job-scoped `pull-requests: read` to the redundancy
  job (the primary check job already grants it).
- `.github/scripts/validate-pr-template.sh`: defense-in-depth `title="${title//$'\r'/}"`
  strip (the body CR-strip already landed on master via #84 — see Collision note).

## Collision note (NL-FINDING-013 class)

NL-FINDING-030 has TWO class fixes. Fix (1) — the CR-strip + self-test Case 23 — landed
INDEPENDENTLY on master via **#84 / d412e1c** while this session was in flight (Session
B/Fable hit the identical CRLF false-fail on PR #84's own body and fixed it inline).
This session's byte-identical fix (1) was therefore DROPPED on re-base onto master
(verified `od` byte-proof + self-test 23/23 against #84's version). This change lands
ONLY fix (2) — the rerun-safe run-time fetch — plus the title-strip defense-in-depth and
the finding closure. Net effect: both class fixes reach master.

## Goal

Complete NL-FINDING-030 by making failed CI reruns meaningful — read the live PR
body/title instead of the frozen webhook snapshot — now that #84 has landed the
CR-tolerance half. Closes NL-FINDING-030.

## Scope
- IN: the workflow run-time fetch in both PR-template jobs, the validator title-strip,
  closing NL-FINDING-030 in `docs/findings.md`, and this skip-plan record.
- OUT: re-landing the CR-strip / Case 23 (already on master via #84); any change to the
  validator's pass/fail rubric; the other CR-intolerant `grep -Fxq` sites in the estate
  (NL-FINDING-030 sweep query, not fixed here); and adding an `edited` trigger to
  `server-side-enforcement.yml` (see Decisions Log DEC-1).

## Tasks

All tasks complete — shipped on branch `claude/dazzling-hawking-2da281` (harness-reviewer
PASS). Direct-execution design-skip audit note; the items below are a descriptive
done-record, not task-verifier-gated checkboxes.

- 1. Fetch body/title at run time in both PR-template CI jobs + job-scoped `pull-requests: read` — DONE.
- 2. Defense-in-depth title `\r`-strip in `validate_pr_body` — DONE (self-test 23/23).
- 3. Close NL-FINDING-030 with the collision-aware note — DONE (Status: closed).

## Files to Modify/Create
- `.github/workflows/pr-template-check.yml` — run-time `gh pr view` fetch of body/title.
- `.github/workflows/server-side-enforcement.yml` — same fetch in `pr-template-redundancy`; adds `pull-requests: read`.
- `.github/scripts/validate-pr-template.sh` — title `\r`-strip (body strip already on master via #84).
- `docs/findings.md` — NL-FINDING-030 Status → closed with the collision + resolving-commit note.
- `docs/plans/nl-finding-030-crlf-validator-skip.md` — this design-skip record.

## In-flight scope updates
- 2026-07-05: `.gitattributes` — repo-wide eol=lf pin: the whole-file escalation of this plan's CRLF class (NL-FINDING-038, Wave-F F.1 incident); operator-directed remediation shipped alongside the doctor `line-endings` check (adapters/claude-code/hooks/harness-doctor.sh, already in the overhaul plans' scope).

## Assumptions
- `ubuntu-latest` runners ship `gh` and `jq` (both pre-installed by GitHub).
- `gh pr view --json body,title` requires `pull-requests: read`; the primary check job
  already grants it, the redundancy job gets a job-scoped grant added here.
- Master already carries #84's `body="${body//$'\r'/}"` + Case 23, so re-landing them
  would only create duplicate lines — deliberately omitted.

## Edge Cases
- Empty PR body: `jq -r '.body // ""'` yields an empty string; the validator already
  handles empty body → `section_missing` FAIL (unchanged behavior).
- `gh` auth/rate-limit failure: `set -eo pipefail` aborts the step at the assignment —
  the check goes RED, never a false PASS (fail-closed; reviewer-verified).

## Testing Strategy
- `bash .github/scripts/validate-pr-template.sh --self-test` → expect "Self-test passed
  (23 cases)" (master's Case 23 + this title-strip; the strip does not add a case).
- harness-reviewer agent on the full diff (enforcement-surface change, constitution §10)
  — returned PASS.

## Walking Skeleton
Walking Skeleton: n/a — harness-internal CI/validator change with no UI→API→DB layers; the validator `--self-test` (23 cases) is the end-to-end proof.

## Decisions Log

**DEC-1 (reversible — decide-and-go): do NOT add the `edited` trigger to
`server-side-enforcement.yml`.** harness-reviewer flagged (Major, PROVEN) that
`pr-template-check.yml` fires on `[opened, edited, synchronize, reopened]` while
`server-side-enforcement.yml` fires on `[opened, synchronize, reopened]` — so a
body-only *edit* re-validates on the primary check but not the redundancy job. Options:
(a) add `edited`; (b) document the deliberate divergence. **Chose (b).** The primary
`pr-template-check.yml` is the authoritative gate and DOES fire on `edited`; the
`server-side-enforcement.yml` job is a branch-protection atomicity backstop that
re-validates on code-state changes (push/synchronize), and its new run-time fetch means
any such run — or a manual rerun — validates the CURRENT body. Adding `edited` would
re-run the whole server-side workflow on every body/title edit — wasteful blast radius
for no correctness gain, outside NL-FINDING-030's prescribed scope. Revert is a one-line
trigger add. Reviewer accepted "document why" as a valid resolution.

**DEC-2 (reversible — decide-and-go): also CR-strip the title.** Reviewer noted (Minor)
the title is not CR-normalized. It is currently only consumed by a substring regex
(`grep -iqE`), which tolerates a trailing `\r`, so this is defense-in-depth, not a
correctness fix. Revert is deleting one line.

## Definition of Done

All met (shipped on branch `claude/dazzling-hawking-2da281`):
- Validator self-test green at 23 cases — MET.
- harness-reviewer returns PASS — MET (1 Major documented in DEC-1, 2 Minor addressed).
- NL-FINDING-030 Status flipped to closed with the resolving note — MET.
- Both CI jobs fetch body/title at run time; redundancy job carries `pull-requests: read` — MET.

## Completion

Resolved 2026-07-04. Fix (1) [CR-strip + Case 23] already on master via #84/d412e1c
(parallel collision — dropped this session's duplicate on re-base). Fix (2) [rerun-safe
fetch] + the title-strip + finding closure land via this branch; harness-reviewer PASS.
Reaches master via PR under the Session-A estate-coordination order (dazzling-hawking /
030-validator satellite). Status stays ACTIVE until merge; archive on merge.
