# NL Observability Program — derived-truth cockpit + six-questions estate visibility

Status: DRAFT
frozen: true
Mode: design
Execution Mode: orchestrator
rung: 1
Owner: operator (greenlit as a build commitment 2026-07-04: "Let's please make sure
this gets into an actual build"); START TRIGGER: nl-overhaul F.4 retro complete —
the F.4 completion report MUST carry this program's activation proposal (wired into
specs-f §F.4-PROTOCOL). Flip Status: ACTIVE only then (ACTIVE ≤3 budget applies).
Design: docs/reviews/2026-07-04-observability-design-sketch.md (normative — the two
laws, the six operator questions, surfaces, non-goals, success metrics).
Backlog items absorbed: WORKSTREAMS-UI-PURPOSE-AUDIT-01 (P1 — dispositioned by the
sketch: rebuild cockpit as a thin view over derived truth); ntfy.sh phone-notification
item (absorb at activation; mark both in backlog in the activation commit).

## Goal

The operator answers the six questions (sketch §"six operator questions") in <10s
each without opening a session, from one cockpit, with push for the three
interrupt-worthy classes — all computed from ground truth (transcripts, git,
filesystem, signal ledger), never from cooperative self-reporting.

## Scope

IN: signal-ledger event-coverage extension (session lifecycle, spawn/dispatch,
background tasks, turn-traces); session heartbeat files; derivation library +
`nl status|needs-me|why|costs` CLI; cockpit rebuild (Workstreams UI shell over the
derivation lib); ntfy.sh push rules (3 classes); doctor pipeline-health checks +
consumer-map invariant. OUT (sketch non-goals): real-time streaming, per-gate
surfacers, additional dashboards, cross-machine ledger sync beyond read-both.

## Waves (D9 pattern: strong-model wave-spec first, then ≤5 sonnet builders)

- [ ] O.0 Wave-spec refinement: `*-specs-o.md` from the sketch + Wave-E as-built
  (ledger schema, digest, NEEDS-YOU, resumer) — Model: strongest available —
  Parallelizable: no — Verification: mechanical
  - Done-when: specs-o exists with per-task exact specs, dispatch map, serialization
    rules (orchestrator-only: settings template, manifest, doctor, install).
- [ ] O.1 Emit extension: lifecycle/spawn/task events + turn-trace spans via the D6
  shared lib; every new event type registered in a consumer-map file — Model: sonnet
  - Done-when: self-test proves each event class lands; consumer-map covers 100% of
    event types (doctor predicate fragment).
- [ ] O.2 Session heartbeat: liveness file per session (pid, cwd, branch,
  last-activity, marker-state, model); staleness = crash signal — Model: sonnet
  - Done-when: kill-drill — killed session's heartbeat goes stale and `nl status`
    reports stalled within one refresh.
- [ ] O.3 Derivation lib + CLI (`nl status|needs-me|why|costs`): computes Q1–Q5 from
  ground truth only; `nl why` replays ledger+transcript for a session's last block —
  Model: sonnet (lib) + strongest-available review of `nl why` output quality
  - Done-when: drill — each of Q1–Q5 answered <10s on live estate; `nl why`
    reconstructs a seeded gate-block chain end-to-end (024-class fixture).
- [ ] O.4 Cockpit rebuild: Workstreams UI reads the derivation lib (delete/retire
  its event-sourced truth path per the sketch disposition); divergence-reconciler
  flags derived-vs-displayed drift — Model: sonnet — needs ux acceptance run
  - Done-when: operator exercises the six questions in the GUI; acceptance scenario
    recorded (constitution §4 — demonstrated, not shipped-as-components).
- [ ] O.5 Push (ntfy.sh): exactly three rules — NEEDS-YOU created, session
  stalled/throttled >N min, doctor RED; registration + drill — Model: sonnet
  - Done-when: drill fires all three to the operator's phone; no other event class
    can reach push (test the negative).
- [ ] O.6 Pipeline health in doctor: writers firing, ledger growing, heartbeats
  fresh, cockpit regenerated recently, consumer-map 100% — Model: sonnet
  - Done-when: red-fixtures per check; live green.
- [ ] O.7 Retro vs pre-registered metrics (sketch §success-metrics): time-to-answer
  drill Q1–Q6, zero unmapped event types, operator-trust check — Model: strongest
  available — Done-when: completion review doc with measured numbers.

- [ ] O.9 Backlog accountability loop (operator directive 2026-07-06 — "I do not look at the backlog and I forget about it; Claude manages it"): (1) digest feed — age-tiered surfacing (high>7d, medium>30d, low>90d) with one-word disposition proposals (SCHEDULE/FOLD-INTO-<plan>/DEMOTE/WONTFIX), idempotent per item-week, F.1-staleness-proposal pattern; (2) plan-time absorption matching — plan-edit validation greps backlog rows naming the plan-touched surfaces; header must absorb or explicitly defer each match; (3) KPI backlog-health section (adds vs closes, aging histogram) + periodic terminal-state batch proposal (F.3 one-word format); every row ends done/absorbed/wontfix-with-reason. Immediate increment (digest feed + validator warn + KPI section) ships pre-activation as BACKLOG-LOOP-01 — this task hardens + derives it from ground truth in the O.3 lib — Model: sonnet
  - Done-when: seeded aged-fixture rows surface exactly once per tier with correct proposals; a fixture plan touching a backlog-named surface without absorbing warns; KPI fixture renders the health section; drill — operator answers one digest proposal word and the row reaches terminal state.
- [ ] O.8 Estate-coordination protocol (from NL-FINDING-031 + the 2026-07-04 manual run):
  `/coordinate-estate` skill + doctrine compact encoding what the origin session did by
  hand — inventory sessions (list_sessions), classify (active / stalled>2h / wedged-
  undeliverable / superseded), re-home orphans via nl-issue, stand-down superseded
  satellites, freeze-window protocol (declare in main-checkout SCRATCHPAD coordination
  section; satellites land-or-hold; cutover owner proceeds on ACTIVE flag), spawn-time
  supersession check (grep master+branches for existing fix before building) — file-based
  channels ONLY (send_message requires per-message operator confirmation by design; it is
  a nudge, not an orchestration primitive) — Model: sonnet
  - Done-when: skill file exists + doctrine compact with JIT trigger; drill — a seeded
    stale-session fixture is classified and its task re-homed to the nl-issue ledger;
    coordination-section format documented in the doctrine.

## Files to Modify/Create

`adapters/claude-code/hooks/lib/signal-ledger.sh` (extend), new
`adapters/claude-code/scripts/nl-status.sh` + `nl-why.sh` (or one `nl` dispatcher),
new `adapters/claude-code/scripts/session-heartbeat.sh`, `workstreams-ui/`
(derivation-backed refactor), `adapters/claude-code/manifest.json` +
`settings.json.template` + doctor (orchestrator-only at integration),
`observability-consumer-map.json` (new, doctor-read).

## Assumptions

Wave E's ledger/digest/NEEDS-YOU/resumer are live and stable (they are the
foundation); F.4 retro did not refute the program hypothesis (if it did, this
program's design gets re-reviewed with it); two-machine estate (read-both, no sync).

## Edge Cases

Crashed sessions (heartbeat staleness IS the signal); worktree sessions (heartbeat
records worktree root + main checkout); cloud sessions with no local hooks (Layer-D
class — cockpit marks them "unobserved: cloud" honestly rather than guessing);
transcript rotation/compaction mid-derivation (derivation tolerates partial reads,
labels stale sections); ledger growth (rotation policy + `nl` reads tail-first).

## Testing Strategy

Per-task self-tests (sandboxed, RETRY_GUARD_STATE_DIR + HARNESS_SELFTEST — findings
028/025 discipline); drills as Done-whens (kill-drill, push-drill, time-to-answer
drill); doctor red-fixtures; UX acceptance run on the cockpit (§4).
