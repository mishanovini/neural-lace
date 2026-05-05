# Comprehension Articulation

<!--
This is the canonical comprehension-articulation template for builders
working on R2+ tasks under the Neural Lace harness. The comprehension-
gate (C15, per Build Doctrine §6) fires when a plan's `rung:` field is
2 or higher; below R2 the gate is a no-op and this template does not
apply.

The articulation block lives INSIDE the task's evidence block, not in
the plan file proper. Specifically: under `## Evidence Log` in the
plan file, the entry corresponding to the task being verified, append
a `## Comprehension Articulation` sub-section just below the existing
evidence content for that task. task-verifier reads this sub-section
and (at R2+) invokes `comprehension-reviewer` against it before
flipping the task's checkbox.

The schema is locked by Decision 020 (`docs/decisions/020-comprehension-gate-semantics.md`):

  Four required sub-sections, in this order:
    1. Spec meaning              — what the spec asks for, in your words
    2. Edge cases covered        — which edge cases the diff handles, with file:line citations
    3. Edge cases NOT covered    — honest list of gaps; if zero, justify
    4. Assumptions               — premises the diff relies on

  Substance threshold: each sub-section must contain >= 30 non-whitespace
  characters of substantive content. Below the threshold FAILS the gate.

  Verdict propagation: comprehension-reviewer FAIL or INCOMPLETE blocks
  task-verifier's checkbox flip; PASS allows verification to proceed.

The agent rubric (per the comprehension-reviewer agent file) layers
diff-correspondence on top of the substance threshold: each claimed
edge-case-covered must have corresponding diff content. Generic
articulations that clear the threshold but could apply to any task
fail diff-correspondence.

The example below illustrates the canonical shape for a synthetic R2
task that hypothetically modified two backend service files
(`src/services/notifier.ts` and `src/services/notifier-queue.ts`) to
add per-org rate-limiting to outbound notifications. Real evidence
blocks replace this example.
-->

## Comprehension Articulation (sample — replace with task-specific content)

### Spec meaning

The spec asks me to add per-org outbound-notification rate-limiting that caps each org at 100 notifications per rolling 60-second window. Limit is enforced server-side at the notifier level, before the queue handoff, so an org that exceeds the cap gets back a structured rejection (not a silent drop).

### Edge cases covered

- New org with zero history: first notification accepted; the rate-limiter initializes the org's window lazily on first call (`src/services/notifier.ts:84-91`).
- Notifications exactly at the cap: the 100th notification within the window is accepted; the 101st is rejected (`src/services/notifier.ts:112`, comparison is `>= 100` not `> 100`).
- Window rollover: notifications outside the rolling 60s window are pruned before the cap-check (`src/services/notifier.ts:97-103`).

### Edge cases NOT covered

- Cross-process rate-limiter state. The current implementation holds the per-org window in a single-process in-memory map; horizontally-scaled notifier processes will each enforce the cap independently. This is acceptable for the current single-instance deployment but breaks under future horizontal scale. Flagged for follow-up; not in scope per the plan's `## Scope` OUT clause.
- Burst-vs-sustained distinction. The cap is a flat 100/60s, not a token-bucket — the spec did not ask for burst smoothing.

### Assumptions

- Caller provides a non-null `org_id`; the rate-limiter does not validate this and would key on the literal string `"null"` if passed. Upstream auth middleware guarantees non-null per the existing `requireAuthUser(orgId)` contract.
- Wall-clock time is monotonically increasing. Standard assumption for the deployment environment; rate-limiter would mis-prune on clock skew but the deployment is single-tenant cloud with NTP-synced clocks.
- The rejection structure (`{error: "rate_limit_exceeded", retry_after_seconds: <n>}`) is what the existing API surface returns for rate-limit-class errors elsewhere in the codebase (verified at `src/services/api-rate-limiter.ts:42`).
