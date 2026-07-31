---
title: orchestrator-prime never built the single-deploy-point / no-account-repo-flip-flop mechanism; red-master time-bomb regressed
date: 2026-06-17
type: process
status: decided
resolution: P0 self-refuted in-doc (master green); deploy-serialization mechanism deferred with the orchestrator-prime cluster per DEC-2026-07-02-002 (d6e3990), re-engage post-F.4. Marked 2026-07-12 per state audit.
auto_applied: false
originating_context: Misha asked what happened to the "single agent that manages all deployments — no flip-flopping between accounts/repos, no stepping on toes." This session demonstrated all three failures the mechanism was meant to prevent.
decision_needed: Greenlight building the deploy-serialization + per-context-account/repo mechanism (as orchestrator-prime Task or a new focused plan), and fix the red-master time-bomb (P0, blocks all <product> deploys).
predicted_downstream:
  - docs/plans/orchestrator-prime.md (add a deploy-serialization + single-account-context task) OR a new plan
  - <product>: extend the #554 pin-clock helper to the 6 still-unpinned scheduling tests
---

## What was discovered

**1. The "single deployment point" Misha is asking about was never actually built.**
`docs/plans/orchestrator-prime.md` (ACTIVE, Mode:design, ADR 050) built the always-on
ORCHESTRATION LOOP — SKILL/brain, inbox/outbox scaffold, harness-awareness, conv-tree
emission, keepalive task (Tasks 1,2,8,9,10 done). But it has NO deploy-serialization queue
and NO per-context account/repo scoping. Task 5 (smoke-test the inbox/outbox seam) and Task 6
(systems-designer PASS) are NOT done — the seam is UNVERIFIED. So the specific thing Misha
described — one point through which all deploys flow, no account/repo flip-flop, no stepping
on toes — does not exist as a built mechanism.

**2. This session demonstrated all three failures it was meant to prevent:**
- **Account flip-flop:** the orchestrator + multiple concurrent background builders all ran
  `gh auth switch -u work-account` against the GLOBAL gh account → the active account flipped under
  the orchestrator mid-query → intermittent 404s on `work-org/*`.
- **Repo flip-flop:** the orchestrator queried `work-account/<product>` (a stale, divergent, WRONG
  repo) instead of `work-org/<product>` — produced a false "0 open PRs / can't find
  #551" before correction.
- **Stepping on toes at the deploy gate:** master CI is intermittently RED again (6 clock-
  dependent tests: `scheduling/business-hours-times`, `agent-tools/booking-flow`,
  `agent-tools/find-available-slots`) → breaks the Vercel build → blocks ALL <product> PR
  previews + prod deploys, intermittently, depending on wall-clock time when the build runs.

**3. NO-TRUST miss: the deploy freeze was only PARTIALLY fixed.** I earlier reported #552/#554
(pin-clock helper) "closed the time-bomb class." The simulator PR (#558) preview just FAILED
on those exact 6 tests — so #554 did NOT cover them. Master is a time-bomb again. I should
have verified master CI was green before claiming the freeze resolved.

## Why it matters

Misha is right: without a single deploy point + per-context account/repo scoping, concurrent
agents collide exactly as they did today. And a time-bomb red master means a "verified,
merged" PR can silently fail to deploy — the 8-hour-freeze class, recurring.

## Proposed mechanism (the real single-deploy-point)

A. **Deploy-serialization lock** — one durable per-repo lock; only one merge+deploy proceeds
   at a time; all deploys flow through one orchestrator-owned step.
B. **CI-green precondition** — that step refuses to merge/deploy unless master CI is green
   (kills the "merged but deploy fails on red master" class).
C. **Per-context account/repo resolution** — NEVER `gh auth switch` the global account from
   concurrent agents; resolve account+repo PER operation from the checkout's `git remote`
   (kills the account/repo flip-flop race). Builders use the repo their worktree's origin
   points at; the orchestrator reads active-repos.txt / git remote, never a remembered slug.
D. Land as an orchestrator-prime task (or a focused plan) WITH the systems-designer PASS that
   Task 6 never got.

## P0 (separate, urgent)

Extend the #554 pin-clock helper to the 6 still-unpinned scheduling tests so master CI stops
time-bombing red and unblocks the deploy pipeline. This gates the deploy of every verified
<product> PR (#557, #558, #551, #556, analytics).

## Options / Decision

Surfaced to Misha for a build greenlight (the mechanism is a meaty harness build; the P0
time-bomb fix is mine to dispatch immediately). Awaiting his call on scope/priority.

## Adjacent-work progress (NOT this decision's implementation — the single-deploy-point mechanism below remains PENDING Misha's greenlight)
- 2026-06-17: PR #560 (analytics + Alert-404) landed all 4 metric/route fixes; the Alert-404
  was a 2-bad-column SELECT (`resolved_by`→`resolved_by_user_id`, `trigger_message_id`
  hallucinated). Completed=0 confirmed an ADOPTION gap (visit-completion flow unused), not a
  code bug — flagged for separate triage, no flow fabricated.
- 2026-06-17 (CORRECTED — my prior "red master" claim was WRONG): master HEAD `2636f33e` is
  GREEN (28/28 scheduling tests pass; #554 ALREADY pinned all 3 files). The red preview was PR
  #558's STALE branch (5 commits behind, missing #554's pin); #560 (current) is green. NO
  master fix was needed — the dispatched time-bomb-fix builder correctly REFUTED the premise
  and created no PR (avoided vaporware). NO-TRUST lesson: I claimed "red master blocks all
  deploys" from a single preview failure WITHOUT verifying master itself; the failure was
  branch staleness, not master. Fix for #558: merge master in. Residual (separate follow-up):
  3 non-unit test files (tests/api, tests/integration) lack the pin but don't run in
  vercel-build, so they can't block prod deploy. ∴ deploy pipeline is UNBLOCKED.
- Single-deploy-point mechanism: NOT yet built — awaiting Misha's greenlight.
