# Lesson — Why the harness keeps "succeeding" while the operator keeps experiencing failure

**Date:** 2026-07-27
**Trigger:** Operator, after the dispatch-storm freeze, on learning orchestrators were running they
didn't know about: "I've tried repeatedly to update Neural Lace to manage the Workstreams properly
and close things out… and you have consistently failed. What have we been missing? Why do you keep
failing?" This is the correct question and it deserves a structural answer, not another gate.

## The four root causes (each PROVEN from this estate's own history)

### 1. "Done" is measured at the component, not the outcome
The 07-13 fork-storm session closed with a lesson doc and no code — operator saw transient relief,
then recurrence. Decision 064 (mirror divergence) shipped its gate but its PRIMARY mechanism
(server-side branch protection) was operator-only and never enabled — divergence recurred a 3rd
time. `agent-efficiency-fixes-2026-07` closed 07-24 with T2/T3 genuinely shipped — and the machine
froze 07-27 anyway, from an adjacent vector (dispatch runaway) that "closure" never measured.
Pattern: closures are TRUE about artifacts and FALSE about the operator's experienced problem.
Constitution §4 (functionality over components) is applied to product work but not to harness work,
where "self-test passes + doctor green" substitutes for "the symptom stopped recurring."

### 2. Accountability is session-scoped; the problem is estate-scoped
Every mechanism fires inside one session's lifecycle and requires that session's cooperation.
The mess is machine-wide and regenerates BETWEEN sessions: 9+ worktrees, 13 stashes, 40+ untriaged
nl-issues with daily auto-escalations, orphaned bash chains, sessions running that the operator
doesn't know exist (the session-resumer auto-revives dead sessions; scheduled ticks keep dispatching;
long-lived orchestrators outlive the operator's memory of starting them). **Creating autonomous work
is frictionless; closing it is voluntary.** Entropy wins by default. No single authority owns the
estate's inventory or its garbage collection.

### 3. The additive reflex — every failure adds mechanism, and harness weight is now itself a cause
105 hooks, 2.9 MB of bash, ~10 hooks per tool call, measured 190 ms/spawn Windows tax. Today's
freeze was AMPLIFIED by harness weight: each runaway dispatch paid a full SessionStart. Failures
produce new gates faster than old ones are retired (exit-0 shims still firing weeks after being
flagged). A control system that grows monotonically eventually causes the failures it exists to
prevent. Nobody subtracts.

### 4. Operator-surface overload — the human side of the loop is saturated by design
The system emits more decisions/NEEDS-YOU/nl-issues than one person can absorb (40 untriaged,
oldest 15d, escalation rows auto-filed daily). Critical human-only steps therefore silently don't
happen — branch protection (064), Defender exclusions (asked 3×), pausing runaway orchestrators —
and the resulting recurrence reads as "Claude failed again." Not operator blame: a system that
generates asks faster than they can be processed has designed its own open loop. Asks must be few,
batched, prioritized, and re-surfaced until closed — not scattered across ledgers.

## Why "it'll be different this time" is credible AT ALL (the existence proof)
T2/T3 (single-flight + self-test-sweep gate) shipped, held, and verifiably fired this very session
("another SessionStart-origin session ran the digest within ~2 min — skipping"). When a fix targets
the measured outcome and the outcome is re-checked, the loop DOES close. The failure is not ability;
it is the definition of done and the missing estate authority.

## The program (SMALL first; each phase closes on an OUTCOME metric, not an artifact)

- **P0 — Brake + kill switch (days):** machine-global builder-concurrency cap + dispatch rate limit +
  `HALT` file honored by all dispatch paths. Outcome metric: zero >90-bash events for 14 days.
- **P1 — Estate registry + janitor (the "I didn't know it was running" fix):** every autonomous
  session/builder/tick MUST register (what, why, authorized-by, heartbeat) in ONE ledger; ONE
  scheduled janitor tick enforces — unregistered work flagged then stopped, merged worktrees pruned,
  stale stashes surfaced, ledgers rotated. Outcome: operator can answer "what is Claude doing right
  now and who asked for it" from one surface in <30 s; worktree/stash counts trend down.
- **P2 — Outcome-gated closure:** harness plans declare a symptom metric + re-check window at close;
  recurrence within the window auto-reopens (doctor checks outcomes, not just wiring). Outcome: no
  recurrence-of-closed-class incidents in 30 days — measured, not asserted.
- **P3 — Subtraction audit:** using the P1 perf ledger, every hook justifies its per-call cost or is
  retired/merged; target: halve PreToolUse spawns per Bash call. Outcome: measured hook latency and
  hook count down, doctor green.
- **P4 — One operator surface:** converge the parallel status/dashboard efforts into a single view
  (running / queued / closed-yesterday / needs-you ≤5 items, re-surfaced until acted on).
  The estate-performance-governor design (2026-07-27) slots in as P0/P2's mechanism, not as its own
  parallel program.

## Standing rule change (binding on future harness sessions, this file is the record)
1. No harness fix may claim DONE without naming its outcome metric and re-check date in the closure.
2. No new blocking hook without naming which existing hook it replaces or why subtraction fails (§10
   already caps always-loaded prose; extend the spirit to hook COUNT).
3. Operator asks: batched, ≤5 open at a time, each with a one-line "what happens if you don't."
