# Plan: Pending-Discoveries Triage 2026-06-10
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal discovery triage + small mechanism fixes; the user is the maintainer; self-tests are the acceptance artifact.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Triage all 10 `status: pending` discoveries on master in `docs/discoveries/` per
`~/.claude/rules/discovery-protocol.md` decide-and-apply: re-verify each against today's
repo, execute the reversible recommendations now (with evidence), flip statuses
(implemented / superseded / decided / pending-with-current-state-note), and surface the
genuinely irreversible decisions to Misha in the dispatching session's return.

## User-facing Outcome
The maintainer's discovery-surfacer noise drops from 10 pending master discoveries to the
ones genuinely awaiting his decision; four live mechanism defects the discoveries named
(greedy Verification parser, bug-persistence PRD blindness, git-discipline staged-set gap,
install.sh worktree hooksPath dangling) are fixed on master.

## Scope
- IN: status flips + Decision/Implementation-log updates for the 10 pending discoveries on
  master; the small reversible fixes their recommendations name (close-plan.sh parser,
  plan-reviewer.sh Check-12 collision notice + exemption-grep sweep, wire-check-gate.sh
  exemption grep, bug-persistence-gate.sh PRD durable target, risk-tiered-verification.md
  parser-contract sentence, git-discipline.md Rule 4, rules/INDEX.md row, install.sh
  stable-hooksPath resolution); one new backlog entry (HARNESS-GAP-50, session-wrap
  Signal 3).
- OUT: the 3 staged-only discoveries living in the main checkout's index (resident
  session's batch); any >30-min build (session-wrap Signal 3 rework, scope-gate
  orphan-commit redesign, dispatch-coordination build phase); the main checkout itself.

## Tasks

- [ ] 1. Triage + status-flip the 10 pending master discoveries with re-verified evidence; execute the reversible fixes (parser last-occurrence + S12 self-test, exemption-grep class sweep, Check-12 collision notice, PRD durable target + self-test, git-discipline Rule 4 + INDEX row, install.sh stable hooksPath, risk-tiered doc sentence, GAP-50 backlog entry). Verification: mechanical

## Files to Modify/Create
- `docs/plans/discoveries-triage-2026-06-10.md` — this plan
- `docs/discoveries/2026-05-11-close-plan-verification-field-parser-greedy.md` — flip implemented
- `docs/discoveries/2026-05-15-demonstration-tasks-need-real-touchpoints-not-proxy-synthesis.md` — flip implemented
- `docs/discoveries/2026-05-16-bug-persistence-gate-false-fires-on-interactive-intake-surface-turns.md` — flip implemented
- `docs/discoveries/2026-05-17-session-wrap-signal3-transitive-false-fire.md` — flip decided + GAP-50
- `docs/discoveries/2026-05-21-stash-push-single-file-leaves-unstashed-deletions-stageable.md` — flip implemented
- `docs/discoveries/2026-05-25-dispatch-coordination-debug.md` — pending + current-state note
- `docs/discoveries/2026-05-26-worktree-spawn-session-harness-friction.md` — flip implemented (item 3)
- `docs/discoveries/2026-05-27-conv-tree-checkout-divergence-and-wiring-coverage-gap.md` — flip implemented
- `docs/discoveries/2026-05-27-conv-tree-v4-design.md` — flip superseded
- `docs/discoveries/2026-06-02-conv-tree-backfill-premise-mismatch.md` — flip implemented
- `adapters/claude-code/scripts/close-plan.sh` — last-occurrence Verification parse + S12 scenario
- `adapters/claude-code/hooks/plan-reviewer.sh` — Check-12 collision notice; exemption greps last-occurrence
- `adapters/claude-code/hooks/wire-check-gate.sh` — exemption grep last-occurrence
- `adapters/claude-code/hooks/bug-persistence-gate.sh` — docs/prd.md durable target + self-test
- `adapters/claude-code/rules/risk-tiered-verification.md` — last-occurrence parser contract
- `adapters/claude-code/rules/git-discipline.md` — Rule 4 (staged-set verification)
- `adapters/claude-code/rules/INDEX.md` — git-discipline row update
- `adapters/claude-code/install.sh` — hooksPath resolves stable main checkout
- `docs/backlog.md` — HARNESS-GAP-50 entry + Last-updated bump

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The 10 pending discoveries on master are the full master-side pending set (3 more exist
  only as staged files in the main checkout and are out of scope).
- Existing self-tests for the touched hooks/scripts pass on origin/master before my edits.

## Edge Cases
- A status flip on a discovery is NOT a plan-lifecycle event (discoveries are not under
  docs/plans/), so plan-lifecycle.sh / GAP-49 worktree-index pollution does not apply to
  the discovery edits; the plan's own terminal flip is done via Bash + manual in-worktree
  git mv specifically to avoid GAP-49.
- The post-commit auto-deploy runs the worktree's install.sh; the install.sh hooksPath fix
  lands in the FIRST commit so subsequent auto-deploys never point global hooksPath at
  this ephemeral worktree.

## Acceptance Scenarios
- n/a — acceptance-exempt harness-internal work; self-tests are the acceptance artifact.

## Out-of-scope scenarios
- n/a

## Testing Strategy
- `close-plan.sh --self-test` (12 scenarios incl. new S12 inline-phrase collision) passes.
- `plan-reviewer.sh --self-test` passes unchanged.
- `wire-check-gate.sh --self-test` passes unchanged.
- `bug-persistence-gate.sh --self-test` (incl. new PRD-target scenario) passes.
- Discovery frontmatter flips verified by grep.

## Walking Skeleton
n/a — doc + small-fix sweep; the self-tests are the end-to-end slice.

## Decisions Log
(populated inline per discovery in each discovery file's Decision section)

## Evidence Log

## Definition of Done
- [ ] All tasks checked off
- [ ] Self-tests pass
- [ ] Completion report appended
