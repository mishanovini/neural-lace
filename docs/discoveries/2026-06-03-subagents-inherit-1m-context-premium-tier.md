---
title: 1M-context sub-agent dispatch fails under bursty load — intermittent throttling, not a billing wall
date: 2026-06-03
type: failure-mode
status: pending
auto_applied: false
originating_context: orchestrator-prime evening session — intermittent "Usage credits required for 1M context" / "temporarily unavailable" failures on sub-agent dispatch; Misha challenged the billing framing and was right
decision_needed: Should the orchestrator pace heavy 1M-context sub-agent dispatch (1-2 at a time + retry) as standing policy, and/or default builder/reviewer agents to standard context to reduce 1M-tier pressure?
predicted_downstream:
  - adapters/claude-code/rules/orchestrator-pattern.md (pacing policy)
  - adapters/claude-code/agents/*.md (optional model: standard-context default)
---

## What was discovered (corrected 2026-06-03 after live probe)

Earlier framing (credit-exhaustion / "enable usage billing") was WRONG — refuted by a live probe.

PROVEN:
- 3 heavy sub-agent dispatches failed at dispatch (0 tokens, ~360ms) with "Usage credits
  required for 1M context"; one Bash classifier call failed with "claude-opus-4-8[1m]
  temporarily unavailable" and recovered seconds later; earlier "Server is temporarily
  limiting requests" errors also cleared on retry.
- A trivial read-only sub-agent (Explore) then succeeded immediately with no intervention.
- A HEAVY builder sub-agent (387k tokens, 118 tool calls, ~24 min) then succeeded fully
  when dispatched as a SINGLE agent.

Conclusion (evidence-based): the failures are INTERMITTENT THROTTLING / capacity limits on
the heavy 1M-context model under BURSTY parallel load (the 6-agent bursts tripped it), NOT a
hard billing/credit wall and NOT an account out of money. Inconsistent error wording
("usage credits required" vs "temporarily unavailable" vs "temporarily limiting requests")
is the fingerprint of transient throttling. The `model: sonnet` override did not bypass it
(1M is a session-level mode), which is a separate true fact.

## Why it matters

The orchestrator burst 5-7 heavy sub-agents at once and tripped the throttle, then mislabeled
it as a billing wall and (wrongly) advised enabling paid usage billing. The real mitigation is
free: PACE dispatch (1-2 heavy agents at a time, retry transient errors).

## Recommendation

Standing pacing policy in orchestrator-pattern.md: dispatch heavy (1M-context) sub-agents
1-2 at a time, retry on transient throttle, don't burst. Optionally default reviewer/builder
agents to standard context to lower 1M-tier pressure. Billing change is NOT required.

## Decision

Pending Misha. Billing recommendation WITHDRAWN.

## Implementation log

(empty — pending decision)
