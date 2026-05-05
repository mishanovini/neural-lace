---
title: Multi-active-plan stranding bypasses pre-stop-verifier
date: 2026-05-05
type: process
status: pending
auto_applied: false
originating_context: GAP-08+13 dispatch session — discovered pre-submission-audit-mechanical-enforcement.md stranded ACTIVE despite all 5 tasks being shipped in code
decision_needed: Should we add a SessionStart hook that surfaces ALL Status:ACTIVE plans (not just the most-recently-edited), with a warning when count > 1?
predicted_downstream:
  - adapters/claude-code/hooks/active-plans-surfacer.sh (NEW — proposed)
  - adapters/claude-code/settings.json.template (SessionStart wiring)
  - docs/backlog.md (new HARNESS-GAP-N entry tracking the mechanism)
---

## What was discovered

`docs/plans/pre-submission-audit-mechanical-enforcement.md` was Status: ACTIVE
with 5 unchecked tasks at session start (2026-05-05), but ALL 5 tasks had
shipped in code on master:

- Task 1 (Check 8A in plan-reviewer.sh): commit `10adac2` (May 3) — 16 source
  references confirm
- Task 2 (self-test scenarios): same commit
- Task 3 (FM-007 update): present in `docs/failure-modes.md`
- Task 4 (design-mode-planning.md Enforcement summary): present, table row
  reads "**landed** — gates S1 mechanically"
- Task 5 (sync to `~/.claude/`): `diff -q adapters/claude-code/hooks/plan-reviewer.sh
  ~/.claude/hooks/plan-reviewer.sh` returns no output

The plan was effectively complete; only the bookkeeping (task-verifier
checkbox flips, evidence blocks, Status: COMPLETED) was stranded.

The session that built `10adac2` ended without finishing the bookkeeping.
Subsequent sessions (May 4 — Phase 1d-C-2, 1d-E-1, 1d-E-2, 1d-F, 1d-E-3,
1d-E-4, 1d-G — and the May 5 cleanup commit `99e1e12`) all worked on OTHER
plans and never reconciled this one. The cleanup session at `99e1e12`
specifically archived two stale plans but missed this one.

The user's SCRATCHPAD said "ACTIVE in another session" — false memory,
likely propagated forward across sessions without verification.

## Why it matters

The harness was designed in `~/.claude/rules/planning.md` to prevent exactly
this:

> **Do NOT start a new plan with the previous one still ACTIVE.** The
> pre-stop hook will block session termination, and worse, the unbuilt tasks
> from the previous plan will be invisible to future sessions because the
> new plan becomes the source of truth in SCRATCHPAD.

But the rule is Pattern-only (planner-self-applied), not Mechanism. The
existing pre-stop-verifier check has a structural blind spot when multiple
plans are simultaneously ACTIVE: it focuses on the most-recently-edited
active plan and lets older ones slip past. SCRATCHPAD's manual-update model
amplifies the gap — once the orchestrator's mental model is on Plan B, Plan A
disappears from view.

This is FM-shape: `multi-active-plan-blind-spot` — the mechanisms know about
"the active plan" but not "all active plans," and the gap is how stranded
plans accumulate silently.

## Options

A. **SessionStart hook `active-plans-surfacer.sh`.** Mirrors
   `discovery-surfacer.sh`. Scans `docs/plans/*.md` (top-level only, not
   archive) for `Status: ACTIVE` files. Surfaces ALL of them with title,
   unchecked-count, and last-edit date. If count > 1, emits an explicit
   warning citing the multi-active failure mode and the
   `planning.md` rule. Cheap: ~80 lines, mirrors an existing pattern,
   self-test extends from discovery-surfacer template.

B. **Extend pre-stop-verifier to iterate over ALL active plans.** Block
   session end if ANY active plan has unchecked tasks without terminal
   status. More invasive (changes existing hook), but closer to the existing
   protection model. Risk: false-positives where a session legitimately
   leaves multiple plans ACTIVE because they're worked across sessions.

C. **Both A and B.** Surfacer at session start (visibility), pre-stop
   iteration (block-at-end). Most thorough.

D. **No mechanism — pure documentation.** Update the `planning.md` rule with
   a stronger warning. Lowest cost, but Pattern-only fixes for failures
   already shown to bypass Patterns is harness theatre.

## Recommendation

Option C (A + B). Option A alone gets visibility (a future session sees
"there are 2 ACTIVE plans" at start) but doesn't block stranding. Option B
alone closes the back-end but leaves the front-end blind. Together they
match the existing layered defenses (pre-commit-tdd-gate has 4 layers;
runtime-verification has executor + reviewer; etc.).

Estimated effort: ~3-4 hours. A is ~80 lines + self-test (~1.5 hr); B is
extending an existing hook function (~1.5 hr); wiring + sync + commit is
~30 min.

This proposal is NOT auto-applied because it's a substantive new mechanism
design touching pre-stop-verifier (load-bearing harness component) and
adding a new SessionStart hook. User decision needed.

## Decision

(To be populated by user when surfaced at next session start, or now if
addressed inline.)

## Implementation log

(empty — pending decision)
