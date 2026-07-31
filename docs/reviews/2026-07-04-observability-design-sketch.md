# NL observability — design sketch (operator request 2026-07-04; Fable-authored)

Status: DESIGN SKETCH for the post-overhaul successor effort. Absorbs/redirects
WORKSTREAMS-UI-PURPOSE-AUDIT-01 (backlog P1). Not in nl-overhaul scope; sequenced
after F.4 retro. Evidence base: audit RC4 (0%-signal-consumption), Workstreams UI
purpose failure (operator verdict), 2026-07-03 lived forensics (NL-FINDING-024 took
~40 min of log archaeology; multi-session coordination via hand-edited SCRATCHPAD).

## Two design laws (from the failure evidence)

1. DERIVE, DON'T MAINTAIN. Status is recomputed on read from ground truth that
   cannot lie: transcripts, git, filesystem, signal ledger. The Workstreams tree
   failed because it was MAINTAINED state fed by cooperative self-reporting hooks —
   every silent writer failure (022 unwired heartbeat, dead extract-pending, 024
   race) made it drift, and a sometimes-wrong status surface loses operator trust
   permanently. Event-sourced views are acceptable only with a ground-truth
   reconciler that flags divergence.
2. EVERY SIGNAL HAS A NAMED CONSUMER OR IT DOESN'T SHIP. Consumer = automated
   action, the E.1 digest, ONE operator cockpit, or a push rule. Ledger event types
   without a mapped consumer are a doctor RED (anti-RC4 invariant).

## The six operator questions (the product spec — each answerable <10s)

1. WHAT'S RUNNING: live sessions across machines — repo/branch/worktree, current
   activity (last ledger events), state: working | blocked | WAITING-ON-ME |
   throttled | stalled.
2. WHAT NEEDS ME: NEEDS-YOU ledger (E.6) with §3-format inline context.
3. WHAT HAPPENED: diff-since-last-look — shipped SHAs, plans closed, decide-and-go
   decisions, failures.
4. IS THE HARNESS WORKING: doctor status; per-gate block/waiver/downgrade rates
   (waiver-dominant gate = broken gate, E.3); synthetic-runner score trend.
5. WHAT'S IT COSTING: tokens/spend per session+wave; throttle events + time lost.
6. WHY DID X HAPPEN (forensics, on demand): `nl why <session> [--last-block]`
   reconstructs the causal chain (hooks fired → state read → verdict → session's
   response) from ledger + transcript. Target: the 024-class diagnosis in ~2 min.

## Architecture (layered; Wave E already builds much of the bottom)

- EMIT (extend, mostly exists): D6 signal ledger is the spine; extend the shared
  lib beyond gate events to: session lifecycle (start/stop/compact/THROTTLE/resume
  — E.7 taps), spawn/dispatch, background-task lifecycle, and TURN-TRACES (per turn:
  hooks fired, order, duration-ms, verdict, reason — the tracing pillar; would have
  made the 024 race a one-query diagnosis).
- HEARTBEAT (new, small): per-session liveness file {pid, cwd, branch, last-activity
  ts, marker-state, model}; staleness IS the crash signal (derived, not claimed).
- DERIVATION LIB (new, the core): one module computing Q1–Q5 from ground truth.
  CLI FIRST: `nl status`, `nl needs-me`, `nl why`, `nl costs` — testable,
  doctor-checkable, zero UI debt. Cross-machine: per-machine ledgers, cockpit reads
  both (simplest viable; revisit sync later).
- SURFACES (exactly three): (a) in-session digest (E.1, live) for agents;
  (b) ONE operator cockpit = Workstreams UI REBUILT as a thin view over the
  derivation lib (this is the WORKSTREAMS-UI-PURPOSE-AUDIT-01 disposition:
  keep the GUI shell, replace its event-sourced truth with derived truth);
  (c) push (ntfy.sh backlog item) for ONLY: NEEDS-YOU created, session
  stalled/throttled >N min, doctor RED.
- FORENSICS: `nl why` as above; reads ledger + transcript, no new state.
- OBSERVABILITY OF THE OBSERVABILITY (§10): doctor verifies the pipeline live —
  writers firing, ledger growing, heartbeats fresh, cockpit regenerated recently,
  every event type consumer-mapped. No theater.

## Non-goals

Real-time streaming; per-gate custom surfacers (just retired 12 of them); any
mechanism requiring cooperative session discipline where a mechanical tap exists;
dashboards beyond the one cockpit.

## Pre-registered success metrics

Median time-to-answer for Q1–Q6 (measure by drill); zero ledger event types
without a mapped consumer (doctor-audited); operator trusts the cockpit enough to
stop asking sessions for status (the Workstreams failure inverted).

## Sequencing

Wave E lands: ledger, digest, KPIs, NEEDS-YOU, resumer/throttle detection,
pre-compaction snapshots. Post-F successor wave builds: turn-traces + heartbeat
(emit), derivation lib + CLI, cockpit rebuild on derived truth, push rules,
`nl why`. Recommend running it as its own short program with the same D9 pattern
(strong-model specs, lesser-model builders) after the F.4 retro verdict.
