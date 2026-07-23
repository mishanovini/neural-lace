# Plan — Performance telemetry: passive metering, biting budgets, loop-liveness

Status: ACTIVE
Mode: code
Owner: session 29f2930a (orchestrator) — opened 2026-07-23 on the operator's directive:
"keep tabs on performance without dragging it down; continuously improve; ACTUALLY DO IT,
don't let ideas sit in a document."
Backlog items absorbed: PERF-ESTATE-PROGRAM-01 (P1, operator-requested 2026-07-23 in session
d3059d78 — "monitor performance, document what slows things down, manage/remediate autonomously";
its live evidence and lever list are folded into this plan's tasks and Notes).
acceptance-exempt: yes (harness-internal; self-tests + live before/after measurements are the demonstration)

## Why (root cause this plan closes)

The E.1 fork-storm (agent-efficiency-fixes plan, Evidence Log) shipped and ran for weeks with zero
mechanical signal — discovered only when the operator's machine became unresponsive. The 2026-07-18
deep audit's headline: "detects well, consumes poorly — 5/10 self-improvement loops DEAD; doctor
blind to loop-liveness." Root cause of the class: NO passive performance telemetry, NO budgets on
the per-call hook chain (audit: "23 per-Bash hooks unbudgeted"), and NO liveness check on the loops
that were supposed to notice. This plan builds the feedback loop, not another report.

## Design constraints (operator directive)
- Measurement must be PASSIVE (piggyback existing choke points: the hook chain, the hourly
  health-tick) — never new polling processes; zero added process spawns on the hot path
  ($EPOCHREALTIME, builtin appends only).
- Every measurement must be CONSUMED by a mechanism (doctor RED with named offender), never
  land in a file nobody reads. A metric without a budget is a report; a budget without a RED
  is a wish.

## Tasks
- [ ] P1 — Per-call chain latency ledger: wrap the PreToolUse chain execution with $EPOCHREALTIME
      stamps; append ONE JSONL line per tool call (total ms, 3 slowest hooks, hook count) to a
      daily-rotated file under ~/.claude/state/perf/. Hot-path cost budget: <5ms, zero forks
      (asserted in self-test). Verification: full (self-test + a live capture line quoted).
- [ ] P2 — Tick perf snapshot + orphan reap: one line per tick — bash.exe count, claude/Defender
      CPU, worktree count — on the EXISTING supervisor-tick.sh (landed f22b55d; PERF-ESTATE-
      PROGRAM-01's named home) with health-tick as fallback if supervisor-tick's cadence is
      unsuitable; same tick reaps parent-dead orphan bash/claude processes (log each reap).
      No new scheduler. Verification: full.
- [ ] P3 — Doctor budget check `perf-budgets`: REDs when (a) chain p95 over trailing 24h exceeds
      budget, or (b) bash-count high-water exceeds budget — RED names the top offender hook and
      cites the ledger lines. Budgets start at measured-baseline + headroom, recorded with named
      rationale (blocking-budget precedent); they RATCHET DOWN only (tighten on sustained
      improvement, never silently loosen). Verification: full (RED/GREEN fixtures).
- [ ] P4 — Doctor loop-liveness check: every recurring loop declared in the manifest (weekly
      evaluator, nl-issue triage cadence, health-tick itself, perf review) REDs when its
      last-run marker exceeds its declared period. Kills the dead-loop class structurally
      (deep-audit P0 predicate). Verification: full (RED/GREEN fixtures).
- [ ] P5 — Weekly consumption: extend the EXISTING weekly harness-evaluator remit with a perf
      section — reads the week's ledger, proposes ONE ratchet or ONE offender fix, files it as
      a backlog row with evidence. Consumption is verified by P4 (evaluator is itself
      liveness-checked). Verification: contract.
- [ ] P7 — Mechanical concurrency ceiling (PERF-ESTATE-PROGRAM-01 lever f): ≤2 heavy agents
      (builders/reviewers) concurrently per machine, enforced at spawn time (PreToolUse Task/Agent
      check against live claim/heartbeat counts — extend an existing spawn gate, no new hook if
      avoidable), not left to session discipline. The 2026-07-23 storm had 3 builders + main
      session; pacing by memory failed. Structured-waiver hatch for operator-authorized bursts.
      Verification: full (RED/GREEN self-test).
- [ ] P6 — PRETOOLUSE-DISPATCHER-01 design doc + architecture review (build in a FOLLOW-ON plan):
      one dispatcher process runs hook checks in-process, eliminating the 20-hook × 2-3-process
      fork tax per Bash call. P1's ledger is the before/after oracle. Verification: design
      (architecture-reviewer verdict recorded; build explicitly out of this plan's scope).

## Files to Modify/Create
- docs/plans/perf-telemetry-2026-07.md — this plan.
- adapters/claude-code/hooks/lib/perf-ledger.sh — P1 lib (new).
- adapters/claude-code/settings.json.template — P1 chain wrapper wiring.
- adapters/claude-code/scripts/health-tick.sh — P2 snapshot line.
- adapters/claude-code/hooks/harness-doctor.sh — P3 + P4 checks.
- adapters/claude-code/manifest.json — entries for P1-P4 (evidence bar each) + loop-period
  declarations for P4.
- adapters/claude-code/agents/harness-evaluator.md — P5 remit extension.
- docs/design-notes/pretooluse-dispatcher.md — P6 design (new).
- docs/harness-architecture.md — regen.
- docs/backlog.md — absorbed-row deletion + follow-on rows.

## Assumptions
- $EPOCHREALTIME is available (bash ≥5 ships with current Git for Windows — verify in P1
  self-test; fallback: skip metering, never fork for a timestamp).
- The hook chain has a single wrappable execution point in settings.json.template; if hooks are
  invoked individually by the platform (no wrapper), P1 falls back to per-hook self-metering in
  the highest-cost hooks only (top 5 by the 07-13 profile) — declared honestly in the manifest.
- Health-tick stays hourly; no new schedulers.

## Edge Cases
- Ledger file contention across concurrent sessions → O_APPEND single-line writes (atomic under
  ~4KB); daily rotation caps size; P3 tolerates missing/short ledgers (young machine = SKIP not RED).
- Clock skew / suspended laptops → p95 over trailing window, not absolute gaps; liveness periods
  get 25% grace.
- A RED perf budget during a legitimately heavy batch (like this week's) → the check reads a
  structured waiver (house pattern) naming the batch and expiry; never silently raised budgets.
- Defender CPU read may need elevation → P2 degrades to bash-count-only, notes the degradation.

## Testing Strategy
- Each artifact: --self-test with RED/GREEN fixtures (P1: fork-count assertion via process
  accounting in the test; P3/P4: fixture ledgers/markers both sides of budget).
- Live demonstration per Verification: full task: quoted ledger lines from THIS machine, a real
  perf-budget evaluation against the current baseline, and P4 catching one of the audit's
  known-dead loops as its golden scenario (RED on first run = proof it bites).
- Golden scenario for the whole plan: the E.1 class — replay the 07-23 storm shape against P3's
  budget → RED naming harness-doctor as offender (fixture from the captured evidence).

## Dispatch sequencing (deliberate pacing — itself a perf lesson)
Builders dispatch ONE AT A TIME, and only after the agent-efficiency-fixes batch fully deploys
(its T2/T3 fixes must be live first so this plan's baseline measurements reflect the fixed
system, and so builder self-test load doesn't re-storm the machine). Order: P1+P2 (one builder),
then P3+P4 (one builder, consumes P1's real ledger), then P5 (remit edit + review), P6 design in
parallel with P5 (doc-only). Each: build → verify → harness-review → deploy per house discipline.

## Notes
The operator's bar for this plan: no idea may terminate in a document. P4 is the enforcement of
that bar applied to this plan itself — if the weekly perf loop stops running, the doctor goes RED.

Carried from PERF-ESTATE-PROGRAM-01 (absorbed row, 2026-07-23):
- Its live evidence baseline: 67 bash + 16 claude processes; workstreams-read self-test ~40 min
  under load; nl-issue one-line append >2 min; git commits ~15s via global hooksPath; ~85
  worktrees with broadcast scans.
- Levers NOT built here, kept visible: NL-FINDING-029 hooksPath fixture-tax sweep (own backlog
  row survives); the operator PURGE decision NY-1784489893-c961 (43 worktrees + 82
  verified-on-master branches — awaiting-operator, NOT agent-actionable); Defender exclusions
  re-audit (CLOSED 2026-07-23 — operator applied + verified, see agent-efficiency plan T6).
- The monitoring-agent ask lands as P5 (evaluator perf remit) + P3/P4 REDs rather than a new
  standing agent process — a new always-on agent would itself be load; mechanisms that bite at
  existing choke points honor the ask without the drag. If the operator wants the dedicated
  agent anyway after seeing P1-P5 run, that's the follow-on conversation.
