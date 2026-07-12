---
title: Orchestrator was REACTIVE — fixed only operator-pointed bugs, never self-drove the audit→fix→re-audit loop it promised
date: 2026-06-18
type: process
status: implemented
auto_applied: false
resolution: 2026-07-12 — 'Proactive audit loop' encoded as a standing obligation in doctrine/orchestrator-pattern.md (compact bullet) + doctrine/orchestrator-pattern-full.md (full section) — 6-pattern static hunt + runtime exercise of every claimed flow + fix→re-audit to a clean pass; bar = surface problems the operator did NOT point at.
originating_context: Multi-hour <product>-fix session. The operator (Misha) observed that EVERY failed-functionality the orchestrator "found" was one Misha had explicitly pointed it at — the orchestrator surfaced nothing independently, despite earlier saying it would "run the audit itself, find the bugs, fix the bugs, and run the audit again." That loop never happened.
decision_needed: Should the orchestrator pattern encode a MANDATORY proactive failed-functionality sweep (static + runtime functional exercise) + a fix→re-audit loop as a standing step, so "find what the operator did NOT point at" is structural rather than discretionary?
predicted_downstream:
  - rules/orchestrator-pattern.md (a proactive-audit-loop obligation)
  - rules/verification-pipeline.md (a comprehensive functional-exercise sweep, not just per-task)
  - rules/diagnosis.md "After Every Failure: Encode the Fix" (extend to proactive discovery, not just reactive)
---

## What was discovered

Across a long <product> session the orchestrator fixed ~9 real bugs and ran three audits — but every
failed-functionality it reported (cost-page fabrications, Alert-404, Response-Rate-off-dead-field,
duration-never-metered, recordUsage-never-called, engagement-dormant) was either pointed at directly by the
operator OR fell out of the cost audit the operator explicitly requested. **The orchestrator surfaced ZERO
problems independently.** Worse: it had told the operator earlier in the session that it would run the audit
itself, find the bugs, fix them, and re-run the audit — and that self-driven loop never executed. The audits
that did run were SCOPED and REACTIVE (a functional audit; a route/metric audit added only AFTER the operator
found bugs it missed; the operator-requested cost audit). The operator's bugs were "not particularly difficult
to find" by clicking the live app — so a code-reading-only, operator-prompted posture is strictly weaker than
the operator's own manual testing.

## Why it matters

This is the FUNCTIONALITY-OVER-COMPONENTS principle failing at the ORCHESTRATOR layer. The whole anti-vaporware
stack exists to catch "shipped a component, not working functionality" — but if the orchestrator only ever
verifies what it's pointed at, the class it's meant to catch survives everywhere it wasn't pointed. Reactive
bug-fixing is not the same as proactively guaranteeing the app does what it claims. The operator should not be
the primary discovery mechanism for whether functionality actually works.

## Remediation (in progress this session)

1. A codebase-wide static failed-functionality hunt (6 patterns: computed-then-discarded, never-invoked,
   placeholder-as-real, UI-reads-dead-field, endpoint-noop, dead-flag-path) — running.
2. A runtime functional exercise — systematically USE every page/feature/flow against the demo org and verify
   the outcome matches the claim (matching how the operator found bugs, but exhaustive) — next.
3. The loop the orchestrator owes: fix every confirmed problem → re-run both audits → repeat to a clean pass.
4. The bar: surface problems the operator did NOT point at, or the audit has failed.

## The generalizable lesson

The orchestrator pattern needs a STANDING proactive-audit obligation, not a discretionary one — "before
declaring a product area done, independently exercise it end-to-end and hunt the failed-functionality class,
and run the fix→re-audit loop to convergence." Encode it so a future session cannot substitute operator-pointed
fixes for a self-driven audit. Surfaced to the operator; not auto-applied (it changes the orchestrator pattern).
