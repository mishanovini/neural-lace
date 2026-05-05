---
title: Harness needs proactive incentive-design layer alongside reactive correction
date: 2026-05-03
type: architectural-learning
status: decided
auto_applied: true
originating_context: user prompt 2026-05-03 invoking Munger's incentive frame
predicted_downstream:
  - agent prompt design conventions across all NL agents
  - /harness-review weekly audit
  - enforcement-gap-analyzer reasoning
  - Phase 1d-G calibration-mimicry plan
decision_needed: n/a — auto-applied
---

# Harness needs proactive incentive-design layer alongside reactive correction

## What was discovered

The harness has been entirely reactive in its self-improvement. `diagnosis.md`'s "After Every Failure: Encode the Fix" loop closes gaps as they appear: a failure occurs, the root cause is identified, a mechanism is added to prevent recurrence, the catalog is updated. Every Gen 4 / Gen 5 mechanism (`pre-commit-tdd-gate`, `runtime-verification-executor`, `plan-edit-validator`, `pre-stop-verifier`, `product-acceptance-gate`) was added in response to a specific observed failure.

The user surfaced (via Munger's frame): "Show me the incentive and I'll show you the outcome" applied to AI agents. Each agent has training-induced incentives (please the user, appear competent, finish quickly) plus prompt-induced incentives (the specific framing of its role in the prompt) that produce predictable strays. The reactive loop catches strays one at a time, after they cost the user a failure. A proactive layer — explicitly modeling each agent's incentive landscape and writing counter-incentive prompt sections — would pre-empt many strays before they ship.

## Why it matters

Every reactive cycle costs the user a failure: a vaporware shipment, a missed cross-doc inconsistency, a bug that should have been caught at planning time. The reactive loop's per-cycle cost is bounded, but its accumulated cost compounds across the harness's lifetime. A proactive layer cuts the cycle count materially by addressing the systemic root (the agent's incentive landscape) rather than each surface symptom in isolation.

## Options considered

- **(a) Reject — there's not enough incentive on agents to be truthful about their own incentives; the proactive layer becomes self-justifying theater.** Real concern, but the reactive loop has the same risk: every "lesson learned" entry is itself an incentive-shaped artifact. Rejection here is rejection of all introspection, not just the proactive layer.
- **(b) Build calibration-mimicry only.** Heavy mechanism that requires telemetry from a findings ledger (Phase 1d-C-3) and prompt-injection infrastructure. Doesn't ship today.
- **(c) Build incentive-map document + Counter-Incentive Discipline sections in agent prompts.** Lighter. Ships now. Captures the explicit model of incentives + counter-prompts as a maintained artifact.

## Recommendation

Option (c) for first pass; option (b) deferred to Phase 1d-G with user-confirmed design constraints.

## Decision

Option (c). Build the proactive layer alongside reactive failure-correction. Calibration-mimicry deferred to Phase 1d-G pending its dependencies.

## Implementation log

- `docs/agent-incentive-map.md` created mapping each agent's training + prompt incentives and likely strays (commit 18d3911).
- Counter-Incentive Discipline sections added to 4 agent prompts (task-verifier, harness-reviewer, end-user-advocate, claim-reviewer).
- HARNESS-GAP-11 captured for follow-up; Phase 1d-G plan to be drafted in T7 with calibration-mimicry decisions G-1 through G-4.
