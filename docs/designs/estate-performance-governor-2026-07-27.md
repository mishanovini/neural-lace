# Design — Estate Performance Governor: closed-loop 24/7 orchestration with interactive headroom

**Date:** 2026-07-27
**Status:** DRAFT — REFRAMED same day by docs/lessons/2026-07-27-outcome-blind-closure-and-estate-entropy.md:
this design is the MECHANISM for phases P0/P2 of that program, not a standalone build. Review it as a
component of that program (P0 = the minimal cap+rate+HALT subset FIRST); do not build the full
three-loop system before the registry/janitor (P1) exists. Architecture review still required pre-build.
**Golden scenario (real, this machine, today):** the 2026-07-27 13:10–14:30 freeze. 3+ concurrent
orchestrator sessions dispatched background Agent builders at an escalating rate (10-min buckets:
23 → 35 → 56 → 79 → **146**, i.e. ~1 dispatch/4s at peak; 17,790 total `bg-task-started` entries in
`signal-ledger.jsonl`). Each dispatch = a worktree + full SessionStart + console window + the Windows
process-spawn tax (~190 ms/spawn, Defender-scanned). The interactive desktop starved: System event log
went near-silent for 80 min; the Windows clock froze ~30 min and Time-Service re-synced at 14:30.
**No mechanism bounded dispatch rate or total concurrency across sessions.** The "≤5 builders" rule is
per-plan doctrine (memory-rung), unenforced across the estate.

**Operator goal:** sessions running 24/7, maximum productive throughput, while the machine stays
usable for interactive work. Observability that manages this in real time without adding meaningful
overhead; a system that keeps learning where its own bottlenecks are.

## What already exists (build on it, don't duplicate)

| Piece | State |
|---|---|
| `signal-ledger.jsonl` (flight recorder; diagnosed today's incident) | LIVE — 37k entries; writer-side only |
| P1 per-call hook-latency ledger (`hooks/lib/perf-ledger.sh`) | Built; install BLOCKED by review-before-deploy gate (missing PASS records) |
| P2 tick perf snapshot + orphan reap (`hooks/lib/perf-tick-snapshot.sh`, `health-tick.sh`) | Built; same block |
| P3 (consumer of P1 ledger) / P4 | NOT dispatched — P3 needs P1 live first |
| SessionStart single-flight + self-test-sweep gate (T2/T3) | LIVE, verified working |
| Acknowledged gap (671dd20) | P1+P2 are **writers without a consumer** |

The missing piece is not more telemetry — it is (a) an **admission controller** that consumes the
telemetry, and (b) finishing the writer→consumer loop.

## Architecture: three control loops (speed-matched to decision cost)

**Principle: deterministic mechanism in the fast loop; model intelligence only in the slow loop.**
An LLM must never sit in the dispatch path — too slow, too costly, and the incident shows the fast
loop must work even when the machine is dying.

### Loop 1 — FAST: estate dispatch governor (per-dispatch, <10 ms, deterministic)
A PreToolUse gate on Agent/Task dispatch, machine-global:
- **Concurrency semaphore:** atomic slot claim (`mkdir`-based, like `sessionstart-singleflight.sh`)
  under `~/.claude/state/governor/slots/`. Cap = min(cores − 2, operator constant, default 5) TOTAL
  concurrent builders across ALL sessions. Slot freed on task end; TTL-reaped if the owner dies.
- **Rate limiter:** token bucket in one state file — e.g. max 4 dispatches/min machine-wide, burst 6.
- **Pressure-based admission:** the gate reads the *cached* pressure snapshot (Loop 2 writes it; the
  gate never measures anything itself — one file read, ~0 ms) and applies a ladder:
  - GREEN → admit. YELLOW (CPU>75% or bash>60 or RAM<15%) → halve cap, delay non-urgent dispatch.
  - RED (CPU>90% or bash>90) → block new dispatch with teaching message; existing work continues.
  - BLACK (sustained RED >10 min) → also pause background ticks; write NEEDS-YOU alert.
- Blocked dispatch = deferred, not lost: the orchestrator retries later (natural backpressure).
- §10 evidence bar: golden scenario above; fp_expectation ≈ zero under normal load (thresholds sit
  far above healthy baseline: today's healthy baseline is ~10-20 dispatches/10 min, 40-60 bash);
  retirement = upstream Claude Code ships native cross-session concurrency budgeting.

### Loop 2 — MEDIUM: pressure snapshot tick (every 2–5 min, one process, overhead ≈ one spawn/tick)
Extends the existing `health-tick.sh`/P2 rather than a new daemon:
- Writes ONE small JSON (`~/.claude/state/governor/pressure.json`, overwritten in place): CPU load,
  free RAM, bash/claude/conhost counts, MsMpEng CPU share, dispatch-rate (tail of signal-ledger),
  ladder color. Everything else reads this file — measure once, consume everywhere.
- Runs the existing orphan reap (dead-parent/empty-cmdline bash, age>30s) — already built in P2.
- **Retry circuit breaker:** detect marker spam (today: `UNRESOLVED__*` every ~5 s for 4 min) —
  same key failing N times in M minutes → open the breaker (cool-down file), which Loop 1 honors.
  Retries without backoff are how a stuck item becomes a DoS on your own machine.
- Incident capture: on RED/BLACK transition, snapshot top processes + ledger tail to a dated file —
  today's forensics took an hour; this makes the next one a file-read.

### Loop 3 — SLOW: learning loop (daily digest + weekly evaluator; the only place a model thinks)
- Daily: a digest section (existing digest surface) summarizing yesterday: dispatch histogram, top-10
  costliest hooks (P1 ledger — this is P3, already planned), ladder-color minutes, incidents.
- Weekly: harness-evaluator consumes the same ledgers; anomalies auto-file nl-issues (existing
  triage loop). Lessons that recur become gate-threshold adjustments — reviewed, not self-modifying:
  the system *proposes* tuning; the operator or a reviewed commit applies it. A self-tuning gate with
  no review is how you get an adaptive system that adapts itself into a wall.

## Interactive headroom (the part that keeps the machine usable)
1. **Priority isolation — biggest win after Defender exclusions:** builders spawn at BelowNormal
   CPU priority (wrapper: `start /belownormal` or `Start-Process -PriorityClass BelowNormal`;
   worth testing `NL_DISPATCH_LOWPRI=1` in the dispatch path). Windows then keeps the desktop
   responsive at ANY load — today's freeze becomes "builders run slower," invisible to you.
2. **Hidden consoles:** the terminal-window storm is conhost churn; spawn builders with hidden
   windows (`-WindowStyle Hidden` / `CREATE_NO_WINDOW`) — removes desktop-heap pressure and the
   visual chaos.
3. **Utilization target ~75%, not 100%.** Queueing knee: past ~80% utilization, latency explodes
   and throughput *falls* (today: 80 min of ~zero throughput at 100%). Headroom IS throughput.
4. **Capacity budget:** reserve 2 cores + 25% RAM for interactive; the governor's caps derive from
   what remains. One constant in one config file.

## Kill switch (non-negotiable for 24/7)
`~/.claude/state/governor/HALT` — if present, Loop 1 blocks all new autonomous dispatch instantly,
everywhere. One `touch` to stop the estate; one `rm` to resume. (Precedent: `resumer-armed.txt`.)
A 24/7 autonomous system without a one-gesture stop is not safe to run 24/7.

## What the operator is NOT yet thinking about (asked directly)
1. **The metric is completed-verified work, not dispatch count.** 17,790 dispatches produced today's
   freeze; throughput of *merged, task-verified* items is the number to maximize. Loop 3 should
   report throughput (verified completions/day) next to utilization — optimizing the former is the
   actual goal; the latter is just a constraint.
2. **Cloud offload for true 24/7:** local 24/7 fights the OS, Defender, reboots, and your own
   interactive use. The harness already has cloud/scheduled modes (Decision 011) — move long
   autonomous grinds to cloud sessions; keep local for interactive + verification. The machine then
   needs headroom only for what genuinely must be local. (Cost tradeoff = operator call.)
3. **Defender exclusions are still not applied** (blocked on your admin shell, 2× recommended) —
   single biggest constant-factor CPU lever on this box (~33% at last measure).
4. **Windows tax on fan-out width:** at ~190 ms/spawn + scan, the same plan should fan out narrower
   here than on Linux. Governor caps encode this per-machine.
5. **Single-box risk:** 24/7 everything on one desktop = one power cut kills the estate. Laptop +
   cloud as spillover; the coordination substrate (git remotes, decision 064) already exists.
6. **Token/cost pool:** 24/7 dispatch also drains the invisible Model-I/O pool (rate limits, spend).
   The governor's rate limit is coincidentally also a spend limiter; Loop 3 should report both.
7. **Storage hygiene:** ledgers grow unbounded (signal-ledger 10 MB already; largest transcript
   140 MB). Loop 2 gets a rotation step (size-capped, archive-compress) or observability slowly
   becomes its own perf problem.

## Non-goals
- No new daemon/service (ticks + gates only — the existing shape).
- No LLM in the fast loop. No per-tool-call live measurement (P1 already samples cheaply).
- No silent self-modification of thresholds (proposals only, via review).

## Build order (after architecture review)
1. Unblock the in-flight P1/P2 install (write the missing PASS records honestly or fix what fails
   review) — the substrate everything else consumes.
2. Loop 1 governor MVP: semaphore + rate limit + HALT (pressure ladder can follow) — this alone
   prevents a repeat of today.
3. Loop 2 extension: pressure.json + circuit breaker + rotation.
4. Priority isolation + hidden consoles on dispatch.
5. P3/P4 + Loop 3 reporting (throughput + cost next to utilization).
6. Operator items in parallel: Defender exclusions (admin), cloud-offload decision.
