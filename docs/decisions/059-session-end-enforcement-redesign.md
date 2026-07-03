# ADR 059 — Session-end enforcement redesign: batched verdicts, block-once-then-ledger, session-scoped invariants

Date: 2026-07-03
Status: Accepted (operator approved 2026-07-03: "I think this is a great approach. Let's incorporate it into what we're building.")
Stakeholders: Misha (operator), all sessions (every session ends through this surface)
Amends: ADR 058 D5 (gate consolidation — this ADR governs the *semantics* of the surviving Stop chain, not its census)
Companion plan: `docs/plans/nl-overhaul-program-2026-07.md` (tasks E.8, E.9, F.5; immediate increment via NL-FINDING-019 patch)
Evidence base: live four-cycle Stop trap on 2026-07-03 (the session that shipped PR #74 / master a9c1c69), NL-FINDING-016 (compound-command gate trap), NL-FINDING-019 (check (a) × in-flight-scope-update two-gate trap), discovery 2026-06-17 (cross-repo gate misfire → waiver/attestation anti-pattern), audit 2026-07-01 (107 retry-guard downgrades; ride-through economics)

## Context

Wave D consolidated the Stop chain 22→6, but the *semantics* of session-end
enforcement are unchanged: independent gates each block serially, each
re-derives "what this session did" from its own transcript heuristics, some
blocks have no legitimate exit, and each retry replays the full conversation
at the session's most expensive moment. On 2026-07-03 a session that had
merged its deliverable cleanly needed FOUR Stop cycles to end: check (c)
caught a real gap (one cycle, fixed), but its remedy required a plan
scope-line edit that triggered check (a)'s plan-ownership block, which has no
waiver valve, and the session ended only via the retry-guard's emergency
downgrade. Each gate was locally sensible; the composition was a trap. The
gates' actual intent — no lost work, no lies, nothing silently dropped, clean
handoff — requires detection, a durable record, ONE remediation opportunity,
and escalation. It does not require loops.

## Decisions

### D1 — Batched Stop verdict
The Stop chain presents ONE combined verdict: all checks run, all gaps are
reported in a single block message. Serial whack-a-mole (fix gap 1, re-stop,
discover gap 2) is a design defect. The ≤6-unit census from ADR 058 D5 is
unchanged; what changes is that a blocking Stop aggregates every unit's
findings before the agent sees any of them.
*Alternatives rejected:* keep serial blocks and tune ordering (the composition
problem is unowned either way).

### D2 — Block-once-then-ledger
First blocking Stop: the full gap list, one remediation opportunity. If the
next Stop still has unresolved gaps, they are written to the unresolved-gaps
ledger + `NEEDS-YOU.md` + the next-session digest, and the session ENDS. This
is the intent preserved — nothing silently dropped; recorded and re-surfaced
with fresh context — without the loop. The retry-guard's downgrade valve
(currently threshold 3, framed as failure) becomes the designed protocol at
threshold 1–2. The DONE-refusal is retained verbatim: a verification-class
block is never downgraded under a `DONE:` claim (that rule is load-bearing
honesty enforcement and is explicitly NOT relaxed by this ADR).
*Refutation criterion:* if unresolved-ledger entries accumulate unconsumed
(the 0/32-alerts class), D2 has failed and needs consumption enforcement at
SessionStart — not restored blocking.

### D3 — Session-scoped invariants only at Stop
Stop gates assert what THIS SESSION did: work preserved, claims honest,
surfaced items recorded. They never assert world-state ("this plan is
finished") — world-state checks belong to the digest, the doctor, and CI.
Golden counterexample: work-integrity check (a) demanding 20 Wave-E/F tasks
from a session whose only plan edit was the scope-line append the
scope-enforcement gate itself mandates (NL-FINDING-019). Gate on the
session's diff shape, not on what remains in the world.

### D4 — Waiver parity as a hard design rule
Every blocking check MUST ship a structured waiver path — same shape
everywhere: fresh (<1h), substantive reason, ledger-logged, auditable. A
block with no legitimate exit is a deadlock by construction, and deadlocks
train the waiver-abuse/attestation anti-pattern the operator caught on
2026-06-17. Added to F.1's new-gate evidence bar (golden scenario + FP
expectation + retirement condition + **waiver path**).
Scoping rule: a waiver clears world-state assertions (e.g., unchecked tasks);
it never clears session-honesty assertions (e.g., a checked box with no
evidence) — those are resolvable by the session that created them, so no
valve is needed or offered.

### D5 — Remedy-chain analysis at gate review
harness-reviewer's checklist gains a mandatory question: *for each remedy
this gate's block message prescribes, which OTHER gates does executing that
remedy trigger?* A one-table analysis would have caught both NL-FINDING-016
(fix+commit compound → commit-gate re-block) and NL-FINDING-019 (scope-line
append → plan-ownership block) before they shipped. Nobody previously owned
gate composition; this makes the reviewer own it at the cheapest moment.

### D6 — Session end-manifest: validate claims, don't parse transcripts
The session ends by writing one small structured end-manifest (shipped: SHAs;
unresolved: list + where each is durably recorded; needs-operator: list; the
§6 marker as its last line). Stop gates VALIDATE the manifest's claims with
cheap mechanical checks (SHA exists on master? named finding present in the
ledger? worktree clean?) instead of each gate forensically re-deriving
session history from transcript heuristics — which is where the misfires
breed. The constitution §6 marker contract is unchanged; the manifest is its
machine-checkable expansion.
*Alternatives rejected:* better transcript heuristics per gate (N
re-implementations of the same fragile parse).

### D7 — Metric-driven auto-demotion
E.3 (waiver-density alarm) and E.5 (KPI rollup) currently *report*. This ADR
gives the numbers teeth: a gate whose false-fire/waiver/downgrade rate
crosses the E.3 threshold is AUTO-DEMOTED to WARN (manifest.json
`blocking: false` + honest_status note) pending harness-reviewer re-review.
Wave D.6 demoted two gates ad-hoc (observed-errors, pr-template-inline);
this makes demotion a telemetry-driven lifecycle instead of an operator
intervention.

## Immediate increment (shipped with this ADR)

NL-FINDING-019's minimal fix — waiver parity for work-integrity check (a),
scoped per D4 (waiver clears the unchecked-tasks world-state block; never the
checked-box-without-evidence honesty block) + the block message gains the
honest-hatch text per the E.10 block-message contract. Self-test scenarios
added; harness-reviewer review required before commit. The fuller D1/D2/D6
mechanics land via plan tasks E.8/E.9; D4/D5/D7 governance via F.5; exact
mechanical specs via E.0's specs-e refinement.

## Program-level refutation criteria

- Mean Stop cycles per session-end (ledger-measurable) must fall to ≤2. If
  it doesn't, D1/D2 are mis-implemented or mis-designed — pause and re-review.
- If any gate's waiver rate RISES after waiver parity lands, that gate's
  detection is wrong (people waive what they can't comply with) — it goes to
  re-review, not to a higher threshold.

## Consequences

- Sessions stop burning full-context replays on unresolvable blocks; the
  next session (or the operator, via NEEDS-YOU) inherits a recorded gap
  instead of a loop inheriting nothing.
- Gate authors owe a waiver path and a remedy-chain analysis up front —
  slightly more design cost per gate, paid once, at review time.
- The unresolved-gaps ledger becomes a first-class consumed channel; its
  non-consumption is itself a monitored failure mode (D2 refutation).
