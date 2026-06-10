# Plan: Pending-Discoveries Triage 2026-06-10
Status: COMPLETED
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

- [x] 1. Triage + status-flip the 10 pending master discoveries with re-verified evidence; execute the reversible fixes (parser last-occurrence + S12 self-test, exemption-grep class sweep, Check-12 collision notice, PRD durable target + self-test, git-discipline Rule 4 + INDEX row, install.sh stable hooksPath, risk-tiered doc sentence, GAP-50 backlog entry). Verification: mechanical

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
- 2026-06-10: `docs/plans/discoveries-triage-2026-06-10-evidence.md` — closure evidence file (mechanical-level one-line evidence block).
- 2026-06-10: `docs/plans/discoveries-triage-2026-06-10-evidence/1.evidence.json` — structured mechanical-evidence artifact for close-plan.sh's mechanical route (closure routed through the canonical procedure after the scope gate correctly rejected a hand-rolled archive commit from a no-longer-ACTIVE plan).

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
- [x] All tasks checked off
- [x] Self-tests pass
- [x] Completion report appended

## Completion Report

_Generated by close-plan.sh on 2026-06-10T14:57:04Z._

### 1. Implementation Summary

Plan: `docs/plans/discoveries-triage-2026-06-10.md` (slug: `discoveries-triage-2026-06-10`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/bug-persistence-gate.sh`
- `adapters/claude-code/hooks/plan-reviewer.sh`
- `adapters/claude-code/hooks/wire-check-gate.sh`
- `adapters/claude-code/install.sh`
- `adapters/claude-code/rules/INDEX.md`
- `adapters/claude-code/rules/git-discipline.md`
- `adapters/claude-code/rules/risk-tiered-verification.md`
- `adapters/claude-code/scripts/close-plan.sh`
- `docs/backlog.md`
- `docs/discoveries/2026-05-11-close-plan-verification-field-parser-greedy.md`
- `docs/discoveries/2026-05-15-demonstration-tasks-need-real-touchpoints-not-proxy-synthesis.md`
- `docs/discoveries/2026-05-16-bug-persistence-gate-false-fires-on-interactive-intake-surface-turns.md`
- `docs/discoveries/2026-05-17-session-wrap-signal3-transitive-false-fire.md`
- `docs/discoveries/2026-05-21-stash-push-single-file-leaves-unstashed-deletions-stageable.md`
- `docs/discoveries/2026-05-25-dispatch-coordination-debug.md`
- `docs/discoveries/2026-05-26-worktree-spawn-session-harness-friction.md`
- `docs/discoveries/2026-05-27-conv-tree-checkout-divergence-and-wiring-coverage-gap.md`
- `docs/discoveries/2026-05-27-conv-tree-v4-design.md`
- `docs/discoveries/2026-06-02-conv-tree-backfill-premise-mismatch.md`
- `docs/plans/discoveries-triage-2026-06-10.md`

Commits referencing these files:

```
00293c4 docs(discoveries): triage remaining pending — 4 status flips + 1 current-state note + HARNESS-GAP-50
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
01bc9ba feat(rules): pre-existing-oracle paragraph in FUNCTIONALITY-OVER-COMPONENTS (#37)
01d3867 docs: recover unique-to-this-machine audit + conv-tree-v4 design discovery (#42)
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
07b5097 feat(item10): credentials-reference presence check in install.sh + CLAUDE.md strengthening (#53)
0b14705 fix(scope-gate): Windows drive-letter git-dir recognized as absolute (+ HARNESS-GAP-27 docs superseded) (#27)
0b56c31 docs(strategy): capture Claude Code quality strategy + backlog gaps
10adac2 feat(plan-reviewer): land Check 8A — Pre-Submission Audit gate on Mode: design plans
11c9d13 docs(backlog): correct decision-context finding — bug #3 (Windows node-path) REFUTED; gate core verified working post path-fix + zod (P1->P2)
15496c3 feat(rules+hook): branch-hygiene + stale-local-branch surfacer (#49)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1900089 feat(harness): static-trace.sh — auto-detect chain tracer for modified files
19af838 plan(amend): capture-codify — pass-5 generalization sweep + harness-improvement backlog
1a67d05 docs(handoff): SCRATCHPAD + roadmap + backlog + discovery state for next-session pickup
1d485de plan(1d-F): definition-on-first-use enforcement (sub-gap G absorbed)
2068db5 docs(backlog): file harness gap 23 — gate reads stale commit message file
243c675 backlog: P1 — harness-work plans have no tracked home (2026-04-22)
25ed7f5 docs(handoff): refresh backlog + roadmap to reflect closed Tranche 1.5 + add HARNESS-GAP-19
2987804 docs(backlog): mark bug-persistence-gate as delivered (shipped 0090d4b)
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
2c272c6 backlog: HARNESS-GAP-27 — scope-enforcement-gate merge-aware
2cbf9fe docs(discoveries): session-wrap Signal 3 transitive false-fire (pending)
2f3be21 feat(harness): D1+D4+D5 follow-through — plan template, multi-push impl, hygiene-scan expansion gap
30fc0c7 plan: claude-remote adoption + harness portability to cloud sessions
31067e7 docs(accounting): GAP-20 + GAP-21 backlog + honest force-usage accounting (committed in docs/reviews/)
3402cd6 feat(hooks): land customer-facing-review gate from 2026-06-02 salvage (ADR 053, renumbered from 046)
38a6ea9 feat(rules): information-architecture rule — canonical content router (#51)
3a2babc reconverge: land personal fork onto PT master (decision-context + pr-health + F7 + principles)
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
