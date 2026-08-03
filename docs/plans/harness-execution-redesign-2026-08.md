# Plan: Harness Execution-Layer Redesign (2026-08)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal; the maintainer is the user — per-artifact --self-tests plus the 24h-idle-soak outcome metric (<15% CPU, all maintenance functions enabled) are the demonstration.
tier: 3
rung: 4
architecture: coding-harness
frozen: true
lifecycle-schema: v2
loe-class: harness-mechanism
owner: misha
target-completion-date: 2026-08-23
prd-ref: n/a — harness-development
ask-id: none — no linked ask
outcome-gated: true

Spec of record: `docs/designs/harness-execution-redesign-considerations-2026-08-02.md` — the
considerations brief, its round-2 Addendum, and its "Round 3 revamp (2026-08-02, operator GO)"
section. Round 3 wins on any conflict. Architecture review (verdict SOUND-WITH-AMENDMENTS; the
amendments are the binding invariants + round-2/3 directives, all adopted by this plan):
`docs/reviews/2026-08-02-harness-execution-redesign-architecture-review.md` — a derived record of
the three adversarial pre-mortems + three operator review rounds; see its Provenance section. Sibling program (consumed, never duplicated):
`docs/plans/accountable-estate-program-2026-07.md` — its T3 admission lib, T4 closers/registration,
T7 LOE calibration, and T9 outcome-gated closure + `plan-recheck-sweep.sh` are dependencies this
plan builds ON, not work this plan re-does.

## Intended Functionality

**Outcome (operator's terms):** The operator sees his desktop idle under 15 percent average CPU
across a 24-hour soak with every maintenance function enabled (recorded in the pressure snapshot),
his shell commands pay at most 0.5 s of hook latency instead of the measured 4.1 s, and any gate
that would block him tells him the exact fix command before or at the moment of the block.

**Observation:** Read the soak report in the pressure snapshot (Stage 4 writes it into this plan's
evidence file); run any shell command in a session and compare wall time against the pre-redesign
4.1 s hook tax; trip any of the five retrofitted gates and read the block message — the WHAT/WHY/
FIX/ESCAPE fields are visible in the message itself, no code-reading required.

**Deterministic pass/fail:** PASS when (a) the 24 h idle soak with all maintenance functions
enabled shows < 15% average CPU, (b) measured per-Bash hook latency is ≤ 0.5 s, (c) doctor's
gate-message lint reports 5/5 retrofitted gates emitting the four structured block-message fields,
and (d) inventory counts read: scheduled tasks ≤ 2 per machine, hooks-per-Bash ≤ 6, SessionStart
spawns ≤ 2. FAIL on any miss. Re-checked at +30 days; recurrence auto-reopens via
`plan-recheck-sweep.sh`.

**Explicitly NOT included:** builder hosting on WSL2 or anywhere new (no-WSL is final, R3.1); any
new hardware (R3.2); changes to what any rule ENFORCES (execution layer only — block semantics
unchanged); arming the orphan reaper (D2 — separate operator decision, irreversible-kill class);
any claim the kernel-pool leak is fixed (stays HYPOTHESIZED; pool is measured before/after Stage 1
as an early-warning field, refuter standing).

**Human dependencies:**
- Operator leaves the desktop idle (or overnight) for the 24 h soak window — INTENDED
- Operator may override the D3 drain watermark date (default 2026-07-27) and the D5 TTL (default
  30 min) — INTENDED (decide-and-go defaults are in force; overrides are one-line changes)

## Goal

Rebuild the harness execution layer so the machine that runs it stays usable: the maintenance
layer that measurably consumed ~90% of the desktop (17 h self-DoS, 2026-08-02) becomes a
Windows-native, portable, completion-anchored central maintenance core costing < 15% CPU at idle;
the 25-hook per-Bash chain (4.1 s measured tax) becomes 4–5 per-category stubs; and the gate
estate flips from wall to guide under the Gate Philosophy Law (structured block messages, --check
pre-flight, workaround-as-sensor, friction telemetry). Rules and block semantics are untouched —
only where and how often the execution layer does heavy work changes. The redesign is
anti-bloat by law (R3.3): every stage deletes its old counterpart, and the success metric is the
inventory counting DOWN, doctor-verified.

## User-facing Outcome

n/a — harness-internal: the operator/maintainer is the user. What the maintainer can DO after this
ships that he cannot today: run a full workday of sessions on the desktop with every maintenance
function enabled and never lose the machine to the harness (< 15% idle CPU, proven by soak);
consult any of the five retrofitted gates with `--check` BEFORE acting and get the pass/fail plus
exact fix; read one dashboard panel for cost-vs-budget, inventory counts, and per-gate friction;
and stop the entire maintenance layer with one HALT gesture instead of hand-disabling scheduled
tasks in an emergency.

## Scope

- IN: Stage 0 invariant fixes (single-flight/recursion guard in-lib, SessionStart matcher
  narrowing, schedule manifest + cadence check, hook-count budget check, HALT/drain,
  gate-friction telemetry bootstrap); Stage 0 guidance-contract retrofit of the five named
  blocking gates; Stage 1 Windows-native central maintenance (portable bash core, schtasks/launchd
  adapters, completion-anchored scheduling, TTL snapshots, doctor verdict cache, cost-budget
  dashboard panel); Stage 2 per-category tool-call stubs (4–5, never one dispatcher); Stage 3
  lost-event prevention stack + death certificates + cleanup-as-sensor; Stage 4 estate-state
  drain + outcome-gated closure (24 h soak + 30-day re-check).
- OUT: WSL2 in any load-bearing role (R3.1 — final); new hardware (R3.2); builder-fleet hosting
  moves; reaper ARMING (D2 stays with the operator; observe mode continues); rule-semantics
  changes of any kind; the accountable-estate program's own open tasks (T6 enforce-flip, T8, T10+
  — referenced, not absorbed); store consolidation (estate T10).

## Tasks

- [ ] 1. Stage 0a — Stop the bleeding: invariants in the lib, not the wiring — Verification: full — Docs impact: schedule-manifest format + HALT runbook section added to `adapters/claude-code/doctrine/harness-dev.md`; manifest.json entries for the new checks
      Build `adapters/claude-code/hooks/lib/single-flight-lib.sh` (universal single-flight +
      recursion guard, sourced unconditionally at top of heavy entry points: doctor, digest,
      coord-sync, supervisor/health ticks — invariant 4, kills the nested-chain class including
      resume storms); narrow SessionStart heavy hooks to `startup|clear` matchers in
      `adapters/claude-code/settings.json.template`; create the schedule manifest
      (`adapters/claude-code/config/schedule-manifest.json`: declared cadence + last measured
      cycle time per recurring mechanism) + doctor check cadence ≥ 2× cycle (WARN for 1 calibration
      week, then RED — invariant 2); per-Bash hook-count budget doctor check (WARN at this stage);
      HALT/drain flag honored by tick wrappers (invariant 11); bootstrap the gate-friction
      telemetry ledger (R3.5 — blocks + workaround attempts recorded from this task onward).
      **Outcome metric:** zero nested doctor chains in a 48 h window; a resume event spawns ≤ 2
      processes (measured); HALT stops the maintenance layer in one gesture (demonstrated live).
      **LOE:** 1.5–2.5 bs (reference class harness-mechanism, docs/loe/loe-calibration.md — its
      builder-session coverage is 2.1%, so the brief §6 engineering bands are used with the mined
      class cited).
      **Retires (invariant 9):** wiring-marker-only guards (`NL_SESSIONSTART_ORIGIN` as the sole
      resume defense — becomes belt, never braces) and the emergency hand-disable-5-tasks
      procedure (replaced by the supported HALT mode).
    **Prove it works:**
    1. Trigger a SessionStart resume against a session fixture; count spawned processes (≤ 2) and
       confirm no doctor invocation occurs on the resume path
    2. Start a doctor run, then invoke doctor again from within a hook context; the second
       invocation short-circuits via the lib guard with a one-line notice
    3. Set the HALT flag; confirm the next tick of each wrapped mechanism exits immediately with a
       drain log line; clear it and confirm normal resumption
    4. Corrupt the schedule manifest cadence of one entry below 2× its recorded cycle; doctor
       WARNs naming the entry
    **Wire checks:**
    - `adapters/claude-code/hooks/lib/single-flight-lib.sh` `sf_guard` → sourced at top of `adapters/claude-code/hooks/harness-doctor.sh`
    - `adapters/claude-code/config/schedule-manifest.json` → read by the new cadence check in `adapters/claude-code/hooks/harness-doctor.sh`
    - `adapters/claude-code/settings.json.template` `SessionStart` matchers → landed live by `adapters/claude-code/hooks/session-start-auto-install.sh`
    **Integration points:**
    - `adapters/claude-code/hooks/session-start-digest.sh` and `adapters/claude-code/hooks/harness-doctor.sh` both source the lib — verify with a nested-invocation fixture in each script's `--self-test`
    - merge_settings template sync (SessionStart auto-install) — matcher NARROWING is a
      modification, not an addition: verify the live `~/.claude/settings.json` actually reflects
      the narrowed matcher post-sync (the additive sync's known removal gap is Edge Case 5)

- [ ] 2. Stage 0b — Gate Philosophy Law: guidance-contract retrofit of the five blocking gates — Verification: full — Docs impact: gate-contract convention documented in `adapters/claude-code/doctrine/harness-dev.md`; the five gates' manifest entries gain contract fields
      Build `adapters/claude-code/hooks/lib/gate-contract-lib.sh`: one emitter producing the
      structured block message {WHAT fired, WHY, exact FIX command/path, sanctioned ESCAPE with
      cost} and one shared decision function that BOTH the enforce path and a new `--check`
      pre-flight mode call (guide-not-wall; drift between check and enforce is structurally
      impossible because there is one decision function). Retrofit, one gate at a time (this is
      the per-target decomposition): (a) `scope-enforcement-gate.sh` — already the gold-standard
      message, becomes the reference implementation on the lib; (b) `pre-commit-gate.sh`;
      (c) `harness-hygiene-scan.sh`; (d) `plan-edit-validator.sh` (the plan-header gate);
      (e) `concurrent-ownership-gate.sh`. Add the doctor gate-message lint (REDs a blocking gate
      whose block output lacks any of the four fields); wire workaround-as-sensor (bypass/
      workaround attempts ledgered per gate; a gate above the workaround-rate threshold is
      auto-filed via `nl-issue.sh` as a defective gate); add JIT pre-warning hints (PostToolUse
      approach-time nudges) for the two highest-friction gates per the telemetry from task 1.
      **Outcome metric:** doctor lint 5/5 gates carrying the four fields; for each gate,
      `--check` returns would-block on a violating fixture and would-pass on a clean one;
      friction metric (blocks/day × workaround-rate) renders per gate from the task-1 ledger.
      **LOE:** 1–1.5 bs (class harness-mechanism; five small same-shape retrofits on one lib).
      **Retires (invariant 9):** freeform block messages in those five gates (the lint makes
      regression impossible) and the read-the-hook-source-to-understand-the-block failure mode.
    **Prove it works:**
    1. Run each of the five gates' `--check` against a violating fixture: exit code signals
       would-block and the printed message contains WHAT/WHY/FIX/ESCAPE fields
    2. Run the same `--check` against a clean fixture: would-pass, silent or one-line OK
    3. Run doctor: the gate-message lint section reports 5/5 PASS; strip one field from a fixture
       copy of a gate and confirm the lint REDs it
    4. Attempt a sanctioned escape on one gate; confirm the workaround ledger gains a row and the
       friction metric reflects it
    **Wire checks:**
    - `adapters/claude-code/hooks/lib/gate-contract-lib.sh` `gc_block` → called by `adapters/claude-code/hooks/scope-enforcement-gate-body.sh` (sourced by `adapters/claude-code/hooks/scope-enforcement-gate.sh`, which is now a thin dispatcher — split landed in the first-half build so the common non-`commit` pass-path never parses/sources the ~2400-line body; see that task's build report)
    - `adapters/claude-code/hooks/lib/gate-contract-lib.sh` `gc_block` → called by `adapters/claude-code/hooks/concurrent-ownership-gate-body.sh` (sourced by `adapters/claude-code/hooks/concurrent-ownership-gate.sh`, same thin-dispatcher split)
    - `adapters/claude-code/hooks/lib/gate-contract-lib.sh` `gc_block` → called by `adapters/claude-code/hooks/pre-commit-gate.sh` (no split for this gate — its relevance pre-filter already lives one layer up, in the `settings.json.template` PreToolUse command that spawns it only on a detected `git commit`, so this file stays monolithic)
    - `adapters/claude-code/hooks/lib/gate-contract-lib.sh` `gc_block` → called by `adapters/claude-code/hooks/plan-edit-validator.sh` (deferred-remainder build: scoped to the file's two genuinely WARN-only checks, `check_docs_impact_warn` + `check_backlog_absorption_warn`; the file's SEPARATE checkbox-flip-authorization block mechanism, `exit 1`, ADR 059 D4 "deliberately unwaivable", is untouched — see this task's build report)
    - `adapters/claude-code/hooks/lib/gate-contract-lib.sh` `gc_escape_used` → sources + calls `adapters/claude-code/hooks/lib/workaround-sensor-lib.sh` `ws_record` (new lib, deferred-remainder build — the workaround-as-sensor mechanism itself; NOT yet called from any of the five gates' own waiver-honored call sites, which stayed off-limits for this dispatch — see In-flight scope updates)
    - gate-message lint in `adapters/claude-code/hooks/harness-doctor.sh` → scans `adapters/claude-code/hooks/pre-commit-gate.sh` (NOT YET BUILT — deferred to the remaining Task 2 scope: `harness-hygiene-scan.sh` retrofit, the doctor lint itself, workaround-as-sensor call-site wiring into the five gates' waiver-honored sites, and JIT pre-warning hints. See this task's build report for what shipped in this pass: structured fields + `--check` + relevance pre-filter on `plan-edit-validator.sh`'s WARN layer, plus the new `workaround-sensor-lib.sh` + `gc_escape_used` mechanism (self-tested, not yet call-site-wired). Structured fields + `--check` + relevance pre-filter on `scope-enforcement-gate.sh`, `pre-commit-gate.sh`, `concurrent-ownership-gate.sh` shipped in the first-half build.)
    **Integration points:**
    - `adapters/claude-code/hooks/plan-edit-validator.sh` and `adapters/claude-code/hooks/harness-hygiene-scan.sh` keep their existing exit-code contracts (pre-commit chain compatibility) — verify the repo `.git/hooks/pre-commit` chain still first-fails identically on a hygiene fixture
    - workaround ledger feeds the Stage 1 dashboard — schema agreed in this task's evidence file
      so task 3 consumes it without rework

- [ ] 3. Stage 1 — Windows-native central maintenance: portable core + platform adapters — Verification: full — Docs impact: new runbook section (install/uninstall/rollback per platform) in `adapters/claude-code/doctrine/harness-dev.md`; manifest entries for core + adapters; dashboard README note in the workstreams-ui docs
      Build `adapters/claude-code/scripts/nl-maintenance.sh` — the portable bash maintenance core
      (R3.1/R3.2): hosts the six maintenance functions (coord-sync, supervisor tick, workstreams
      heartbeat, session-resumer sweep, health tick, downstream-product health monitor) as
      internal jobs with completion-anchored scheduling (each run re-arms the next at completion —
      cadence ≥ 2× cycle by construction, overlap impossible); computes doctor/digest/pressure
      ONCE per TTL (default 30 min, D5 decide-and-go) into TTL-materialized snapshots (atomic
      tmp+rename; sessions read O(1)); doctor verdict cache with derived fingerprints computed
      from per-check declared inputs (invariant 8) + ledgered `NL_FORCE`/`--no-cache` bypasses
      (invariant 7); output-freshness health — RED on any snapshot `generated_at` > TTL or any
      breaker open > 1 h (invariant 5). Platform adapters:
      `install-maintenance-task.ps1` (schtasks, IgnoreNew) and
      `install-maintenance-task-darwin.sh` (launchd, per the `ensure-cockpit.sh` darwin
      precedent) — ONE remaining recurring OS task per machine (the deterministic watchdog/anchor
      that re-launches the core on freshness RED). Same-stage: unregister the six existing
      Windows tasks (disabled-not-deleted until the +30-day re-check) + doctor RED on
      both-substrates-alive > 14 days (invariant 9). Ship the cost-budget dashboard panel in
      workstreams-ui (R3.5): per-mechanism cost × fire-rate vs budget, the R3.3 inventory counts
      live, and the per-gate friction metric from task 2's ledger. Per-platform cost lines for
      each mechanism land in the schedule manifest (invariant 10 extended).
      **Outcome metric:** scheduled tasks 6 → 1–2 per machine on both Windows machines and the
      Mac; zero overlap events across 7 days; doctor `--quick` serves the cached verdict in
      < 2 s measured (cache hit); snapshot freshness green for 7 consecutive days; dashboard
      renders budget + inventory + friction from live data.
      **LOE:** 2.5–3.5 bs (class harness-mechanism; the hand-built completion-anchoring and two
      platform adapters price above the brief's WSL variant of this stage).
      **Retires (invariant 9):** the six per-machine scheduled tasks (become internal jobs;
      registrations disabled same-stage, deleted at +30-day pass) and hand-wired per-machine Task
      Scheduler installs (replaced by manifest + adapter).
    **Prove it works:**
    1. Install on a Windows machine via the adapter; confirm exactly one new OS task exists and
       the six legacy tasks are disabled; run 24 h; read the pressure snapshot for CPU + zero
       overlap events
    2. Kill the core mid-cycle; the watchdog relaunches it within its interval; freshness health
       shows the gap honestly (RED then GREEN), no lost snapshot writes (atomic rename)
    3. On the Mac, run the darwin adapter; confirm launchd unit registered and the same snapshot
       set is produced (BSD-userland shims covered by the core's `--self-test`)
    4. Run doctor `--quick` twice: second run < 2 s via verdict cache; touch a declared input file
       and confirm the fingerprint busts the cache; run with `NL_FORCE=1` and confirm the bypass
       ledger row
    5. Open the dashboard panel; confirm cost-vs-budget rows, inventory counts matching R3.3, and
       per-gate friction numbers
    **Wire checks:**
    - `adapters/claude-code/scripts/nl-maintenance.sh` job table → cadences declared in `adapters/claude-code/config/schedule-manifest.json`
    - `adapters/claude-code/scripts/install-maintenance-task.ps1` → registers `nl-maintenance` (schtasks); `adapters/claude-code/scripts/install-maintenance-task-darwin.sh` → registers the launchd twin
    - verdict cache read path in `adapters/claude-code/hooks/harness-doctor.sh` → snapshot files written by `adapters/claude-code/scripts/nl-maintenance.sh`
    - dashboard panel in `neural-lace/workstreams-ui/server` → reads the budget/friction snapshots emitted by `adapters/claude-code/scripts/nl-maintenance.sh`
    **Integration points:**
    - `adapters/claude-code/hooks/session-start-digest.sh` `feed_plan_recheck` and sibling feeds
      keep firing — the digest consumes snapshots instead of recomputing; verify one real
      SessionStart produces the same digest sections from cached data
    - estate janitor/brief (accountable-estate T1) remain standalone artifacts; the core invokes
      them as jobs without forking their logic — verify `estate-janitor.sh` output is unchanged
    - rollback: `Enable-ScheduledTask` on the six disabled tasks + HALT on the core — rehearsed
      once and recorded in the runbook section

- [ ] 4. Stage 2 — Thin per-category stubs on the tool-event surface (4–5, never one dispatcher) — Verification: full — Docs impact: stub-template convention + degradation-banner semantics documented in `adapters/claude-code/doctrine/harness-dev.md`; settings.json.template rewiring notes in the same commit
      Replace the per-Bash hook chain with 4–5 per-category stubs generated from shared templates
      (edge profile == template, doctor-verified — counters the re-fattening pre-mortem):
      bash-policy, file-write-policy, dispatch-admission, session-lifecycle, telemetry-emit.
      Enforcement stays distributed and fail-open per category (§4.3 — one stub's death degrades
      one category, none can block all work). SessionStart/resume path becomes one snapshot-cat
      stub (O(1), reads task-3 snapshots). Degradation banner via context injection when any
      category is running fail-open (invariant 6; storm-capable categories time-box fail-open →
      fail-closed at 24 h). Incentive-by-design (R3.4): keep Read/Grep/Glob zero-hook; extend the
      cheap path to batched commands and pre-declared scope so the right way stays the cheapest
      way. Same-commit removal of each replaced hook wiring from
      `adapters/claude-code/settings.json.template` + the live-settings reconcile (Edge Case 5) +
      exit-0 shim deletion, coordinated in a freeze window via the coordinate-estate skill.
      Observe-first: 7 days of stubs logging would-block alongside the live gates; any
      wrong-block on protected-orchestrator traffic or golden-scenario divergence → fallback =
      stubs source the existing gate scripts as in-process functions (keeps most of the spawn
      win).
      **Outcome metric:** per-Bash hook latency 4.1 s → ≤ 0.5 s measured; hooks-per-Bash 25 → ≤ 6;
      SessionStart spawns 16 → ≤ 2; block-semantics diff vs the replaced gates = zero across the
      7-day observe window.
      **LOE:** 2–3 bs (class harness-mechanism; matches the brief §6 stage-2 band).
      **Retires (invariant 9):** the 21+ per-Bash hook wirings (removed in the same commit that
      lands each stub), the exit-0 shims, and the 16-hook SessionStart chain.
    **Prove it works:**
    1. Time 20 representative shell commands pre/post: median hook tax ≤ 0.5 s post
    2. Replay the golden scenarios of the replaced gates through the stubs: identical
       block/pass decisions (the 7-day would-block diff log is the evidence)
    3. Kill one stub's category (simulate its snapshot missing): that category fails open with
       the degradation banner visible in a fresh session's context; other categories unaffected
    4. Start + resume a session: exactly the snapshot-cat stub fires (spawn count ≤ 2), digest
       content equivalent to task 3's baseline
    **Wire checks:**
    - stub sources generated from `adapters/claude-code/templates` stub template → wired in `adapters/claude-code/settings.json.template` per-category matchers
    - snapshot-cat stub wired at `SessionStart` in `adapters/claude-code/settings.json.template` → reads snapshots produced by `adapters/claude-code/scripts/nl-maintenance.sh`
    - doctor edge-profile check in `adapters/claude-code/hooks/harness-doctor.sh` → compares deployed stubs against the stub template set
    **Integration points:**
    - admission stub calls `adapters/claude-code/hooks/lib/admission-lib.sh` (estate T3 — consumed,
      not duplicated) — verify one dispatch produces exactly one admission ledger row post-cutover
    - the five task-2 gates keep firing where they live (pre-commit chain / PreToolUse) — the stub
      consolidation must not double-invoke them; verify by counting gate firings on one commit
    - live-settings reconcile: removals do NOT propagate via the additive template sync — verify
      `~/.claude/settings.json` hook count on this machine matches the template post-cutover

- [ ] 5. Stage 3 — Lost-event prevention stack + death certificates + cleanup-as-sensor — Verification: full — Docs impact: event-contract (lease/intent/bracket/seq) documented in `adapters/claude-code/doctrine/harness-dev.md`; cleanup-as-sensor law added to the janitor/reaper doc headers
      Build `adapters/claude-code/hooks/lib/event-contract-lib.sh` implementing the round-2
      prevention stack on the estate's pushed obligations: lease/ack on every pushed obligation
      (lease expiry = detected loss, self-healing within one interval); write-ahead intent (emit
      BEFORE acting so a crash mid-work leaves a visible record); open/close event brackets with
      a bracket-age invariant checked incrementally; per-emitter sequence numbers (gap detection
      at read). Death certificates: the maintenance core waits on process HANDLES of jobs it
      starts (kernel-pushed death + exit code — replaces process-table polling) and joins the
      write-ahead intent + open brackets at death into a certificate {who, what, why, exit};
      the taxonomy accumulates in a ledger and the weekly aggregation names the top killer for a
      proactive fix. Cleanup-as-sensor LAW: every cleanup action in the janitor/reaper family
      logs {what, why-it-existed, which-prevention-failed} classified by prevention_gap; a
      cleanup without a learning record is itself a defect (doctor check); cleanup volume
      trending is surfaced on the dashboard (flat-not-falling is an alarm). Reaper stays
      observe-only (D2 unarmed).
      **Outcome metric:** zero permanently-phantom obligations in a 14-day window (every
      injected lost-push fixture is detected within one lease interval); 100% of cleanup actions
      in the window carry learning records; death-certificate coverage = 100% of core-started
      jobs.
      **LOE:** 1.5–2.5 bs (class harness-mechanism; lib + two consumer retrofits + doctor
      checks).
      **Retires (invariant 9):** process-table polling for death detection in the supervised
      path (handle-wait replaces it) and silent cleanup code paths in the janitor/reaper family
      (the logging variant is the only variant left).
    **Prove it works:**
    1. Push an obligation, kill the consumer before ack: the lease expires and the loss is
       detected + re-surfaced within one interval (fixture-timed)
    2. Kill a core-started job mid-cycle: a death certificate appears with exit code, intent,
       and its open brackets; the taxonomy ledger gains the class
    3. Run a janitor cleanup against a seeded orphan: the cleanup row carries
       {what, why-it-existed, which-prevention-failed}; delete the learning fields from a
       fixture row and confirm the doctor check REDs it
    4. Write events with a gapped sequence number: the reader flags the gap at read time
    **Wire checks:**
    - `adapters/claude-code/hooks/lib/event-contract-lib.sh` `ec_lease_open` → called by `adapters/claude-code/hooks/workstreams-emit.sh` on dispatch
    - handle-wait supervision in `adapters/claude-code/scripts/nl-maintenance.sh` → death-certificate rows consumed by the dashboard in `neural-lace/workstreams-ui/server`
    - cleanup logging in `adapters/claude-code/scripts/estate-janitor.sh` → learning-record schema check in `adapters/claude-code/hooks/harness-doctor.sh`
    **Integration points:**
    - workstreams-emit's existing launch-ack/done event pair (the PROVEN lost-event class) is the
      first consumer of lease/ack — verify a builder dispatch round-trips open → close with the
      bracket invariant green
    - estate-registration-lib (estate T4) already brackets worktree open/close — the lib extends,
      never forks, that pattern; verify no double-registration on one spawn
    - Windows has no PDEATHSIG: handle-wait is the Windows adapter's mechanism, kqueue/launchd
      the Mac's — both behind one lib interface

- [ ] 6. Stage 4 — Estate-state drain + outcome-gated closure — Verification: full — Docs impact: drain record + soak report land in this plan's evidence file; backlog/alert ledger watermark note in `docs/backlog.md`
      Execute the D3 drain (watermark-ack, default watermark 2026-07-27, operator-overridable):
      bulk-ack pre-watermark alerts and nl-issues (the redesign supersedes them), triage only
      post-watermark items, dispositions for the remaining stale plans — making doctor cost
      O(small-mess) honestly rather than by cache alone. Re-measure doctor `--quick` cold
      (target < 2 s post-drain even on cache miss). Then the closure gate (invariant 12): run the
      24 h idle soak with ALL maintenance functions enabled — < 15% average CPU recorded from the
      pressure snapshot into this plan's evidence file; write the `## Closure Outcome` re-check
      (+30 days) so `plan-recheck-sweep.sh` auto-reopens on recurrence; after the +30-day pass,
      DELETE the six disabled Windows task registrations (the final invariant-9 deletion) and
      close the both-substrates doctor RED.
      **Outcome metric:** soak PASS (< 15% CPU, 24 h, all functions on); doctor `--quick` < 2 s
      on a cold cache; unacked post-watermark alerts ≤ 50 and trending down across the window;
      the re-check entry is registered and the sweep demonstrably recognizes this plan (dry-run).
      **LOE:** 1–2 bs (class harness-mechanism; mechanical drain + measurement + bookkeeping).
      **Retires (invariant 9):** the 1,193-unacked-alert / 127-untriaged-issue backlog as a
      standing fixture, and (after the +30-day pass) the disabled legacy task registrations.
    **Prove it works:**
    1. Run the drain; cite before/after counts (alerts, nl-issues, stale plans) in the evidence
       file
    2. Run doctor `--quick` with the cache deliberately busted: < 2 s
    3. Run the 24 h soak; attach the CPU series from the pressure snapshot; verdict against the
       15% threshold is mechanical
    4. Dry-run `plan-recheck-sweep.sh` against this plan's archived copy with a past re-check
       date fixture: it would reopen
    **Wire checks:**
    - drain actions ledgered via `adapters/claude-code/scripts/nl-issue.sh` triage fields → counts surfaced by `adapters/claude-code/hooks/session-start-digest.sh`
    - soak CPU series from the pressure snapshot written by `adapters/claude-code/scripts/nl-maintenance.sh` → recorded in `docs/plans/harness-execution-redesign-2026-08-evidence.md`
    - `## Closure Outcome` in this plan → parsed by `adapters/claude-code/scripts/plan-recheck-sweep.sh`
    **Integration points:**
    - close-plan.sh's `verify_closure_outcome_declared` (estate T9) enforces the populated
      Closure Outcome at close — this plan opted in via `outcome-gated: true` in its header
    - the watermark-ack must not eat post-watermark operator asks — the ask-registry SLA view
      (estate T2) is cross-checked before any bulk ack

## Files to Modify/Create

Create:
- `adapters/claude-code/hooks/lib/single-flight-lib.sh` — universal single-flight + recursion guard (task 1)
- `adapters/claude-code/hooks/lib/gate-contract-lib.sh` — structured block-message emitter + shared `--check`/enforce decision core + workaround ledger (task 2)
- `adapters/claude-code/hooks/lib/event-contract-lib.sh` — lease/ack, write-ahead intent, brackets, sequence numbers (task 5)
- `adapters/claude-code/config/schedule-manifest.json` — declared cadence + measured cycle + per-platform cost lines per recurring mechanism (tasks 1, 3)
- `adapters/claude-code/scripts/nl-maintenance.sh` — portable central maintenance core (task 3)
- `adapters/claude-code/scripts/install-maintenance-task.ps1` — Windows schtasks adapter (task 3)
- `adapters/claude-code/scripts/install-maintenance-task-darwin.sh` — launchd adapter, ensure-cockpit darwin pattern (task 3)
- per-category stub sources + shared stub template under `adapters/claude-code/hooks/` and `adapters/claude-code/templates/` — task 4 (exact names fixed by the task-4 builder from the template convention)
- `docs/plans/harness-execution-redesign-2026-08-evidence.md` — evidence blocks per task
- `adapters/claude-code/doctrine/single-flight-halt-runbook.md` — task 1's full runbook (`harness-dev.md` is builder-locked for this task; this file carries the content, see In-flight scope updates)

Modify:
- `adapters/claude-code/hooks/harness-doctor.sh` — verdict cache read path, cadence check, hook-count budget, gate-message lint, both-substrates RED, cleanup-learning-record check (tasks 1–5)
- `adapters/claude-code/hooks/session-start-digest.sh` — consume snapshots instead of recomputing (tasks 1, 3)
- `adapters/claude-code/settings.json.template` — matcher narrowing (task 1), stub rewiring + hook-wiring removals (task 4)
- `adapters/claude-code/hooks/scope-enforcement-gate.sh`, `adapters/claude-code/hooks/pre-commit-gate.sh`, `adapters/claude-code/hooks/harness-hygiene-scan.sh`, `adapters/claude-code/hooks/plan-edit-validator.sh`, `adapters/claude-code/hooks/concurrent-ownership-gate.sh` — the five guidance-contract retrofits (task 2)
- `adapters/claude-code/scripts/coord-sync.sh` — HALT/drain wiring (task 1); becomes a core job; cadence floor honored; PT1M installer path retired (task 3)
- `adapters/claude-code/scripts/supervisor-tick.sh`, `adapters/claude-code/scripts/health-tick.sh` — HALT/drain wiring (task 1; see In-flight scope updates)
- `adapters/claude-code/scripts/session-resumer.sh` — becomes a core job (task 3)
- `adapters/claude-code/scripts/estate-janitor.sh` — cleanup-as-sensor logging fields (task 5)
- `adapters/claude-code/hooks/workstreams-emit.sh` — lease/ack splice on the dispatch/stop pair (task 5)
- `adapters/claude-code/manifest.json` — entries for new mechanisms; retired entries deleted in the same commits (tasks 1–5)
- `neural-lace/workstreams-ui/server` + `neural-lace/workstreams-ui/web` — cost-budget dashboard panel (task 3), death-certificate/cleanup-trend surfaces (task 5)
- `adapters/claude-code/doctrine/harness-dev.md` — runbook + convention sections named in each task's Docs impact
- `docs/backlog.md` — drain watermark note (task 6)

## In-flight scope updates
- 2026-08-02: `docs/harness-architecture.md` — regenerated (gen-architecture-doc.sh) after the integration commit added 4 manifest entries; clears the attributable wave-f-f2-docs doctor RED the task-verifier flagged
- 2026-08-02: `docs/plans/harness-execution-redesign-2026-08-evidence.md` — the plan Closure Contract's named evidence artifact; carries Task 1's Comprehension Articulation (rung-4 requirement, Decision 020d) + orchestrator-replayed verification
- 2026-08-02: `adapters/claude-code/manifest.json` — orchestrator integration commit: the 4 entries (single-flight-recursion-guard, halt-drain-flag, schedule-manifest-cadence, budget-bash-hooks) that task 1's builder was constrained from adding (shared file, orchestrator-owned at merge)
- 2026-08-02: `adapters/claude-code/doctrine/harness-dev.md` — same integration commit: the execution-layer invariants pointer section (single-flight/HALT/schedule-manifest), also builder-locked by dispatch constraint
- 2026-08-02: `docs/handoffs/2026-08-02-stage0-pending-integration.md` — Stage-0 handoff record (live-settings reconcile procedure, per-machine rollout, verified evidence, open findings)
- 2026-08-02: `docs/designs/harness-execution-redesign-considerations-2026-08-02.md` — appended the "Round 3 revamp (2026-08-02, operator GO)" section folding the operator's binding round-3 directives into the spec of record (this session, same commit as this plan)
- 2026-08-02: `docs/plans/harness-execution-redesign-2026-08.md` — this plan file, created in the same commit
- 2026-08-02: `docs/reviews/2026-08-02-harness-execution-redesign-architecture-review.md` — derived architecture-review record (Check 17): the pre-mortems + operator rounds already performed, recorded with verdict + provenance at the gate's expected location
- 2026-08-02: `adapters/claude-code/hooks/scope-enforcement-gate-body.sh` — new file, task 2 first-half build: the retrofit's relevance-pre-filter restructuring split `scope-enforcement-gate.sh` into a thin dispatcher (still the declared Modify target) + this sourced body carrying the full mechanism, so the common non-`commit` pass-path never parses/sources it
- 2026-08-02: `adapters/claude-code/hooks/concurrent-ownership-gate-body.sh` — new file, task 2 first-half build: same thin-dispatcher split as above, off `concurrent-ownership-gate.sh`
- 2026-08-02: `docs/harness-guide.md` — structural note for the two new hooks/lib files this task added (docs-freshness-gate.sh requires one on any A/D/R hook/lib change; see the gate's own block message for the rule)
- 2026-08-02: `adapters/claude-code/doctrine/single-flight-halt-runbook.md` — task 1's full runbook (single-flight/recursion guard mechanism, belt-vs-braces rationale, HALT one-gesture command, schedule-manifest schema, the live-settings-reconcile gap); `doctrine/harness-dev.md` itself is not builder-editable per this task's dispatch constraints, so this file carries the full content with a short pointer section for the orchestrator to land in `harness-dev.md` at merge
- 2026-08-02: `adapters/claude-code/scripts/supervisor-tick.sh`, `adapters/claude-code/scripts/health-tick.sh` — task 1's HALT/drain wiring (invariant 11); named in the task's own prose ("sourced unconditionally at top of heavy entry points: doctor, digest, coord-sync, supervisor/health ticks") but omitted from this plan's `## Files to Modify/Create` table — the table is amended by this bullet rather than silently left inconsistent with the task text
- 2026-08-02: `docs/harness-guide.md` — one new subsection introducing `hooks/lib/single-flight-lib.sh` (docs-freshness-gate requires a doc note alongside any new hook-shaped file addition; `docs/harness-architecture.md` is generated-only from `manifest.json`, which this task's dispatch constraints keep builder-locked, so `harness-guide.md` is the hand-editable target)
- 2026-08-02: `adapters/claude-code/hooks/context-watermark.sh` — proven agent-misuse defect fix, single-file-scoped dispatch: the 2026-07-29 class fix's unknown-model notice replaced one wrong percentage with an "X% of A OR Y% of B" either/or, but both readings still took the familiar "N% of M" shape that overrides any caveat wrapped around it (golden case, this estate, 2026-08-02: an agent read "~211% of 200000" and ignored the parenthetical, stopping work at ~15% real usage). The unknown-model path now emits only the raw measured token count plus an explicit unknown-window statement — no percentage, no denominator, in any form; `--self-test` grew T25-T27 (31/31 passing) proving the known-model path is unchanged, the unknown-model path never contains the substring "% of", and the never-a-stop-reason clause is present on both paths. Not in this plan's `## Files to Modify/Create` table.
- 2026-08-02: `adapters/claude-code/hooks/plan-edit-validator.sh` — task 2 deferred-remainder build: retrofitted `check_docs_impact_warn` + `check_backlog_absorption_warn` (the file's two genuinely WARN-only checks) to `gate-contract-lib.sh`'s structured WHAT/WHY/FIX/ESCAPE fields, added a `--check` read-only pre-flight mode scoped to exactly those two checks (self-test F20-F24), and a cheap `docs/plans` substring relevance pre-filter ahead of the file's `jq` calls. Deliberately did NOT touch this file's separate, actually-blocking checkbox-flip-without-evidence / `Status: COMPLETED`-without-evidence mechanism (`exit 1`, manifest.json `"blocking": true`, ADR 059 D4 "deliberately unwaivable") — see this task's build report for the reasoning (the dispatch characterized this gate as "WARN-only," which is true of the two checks retrofitted but not of the file as a whole; narrowing scope to the WARN layer avoided any risk to the unwaivable, extensively self-tested authorization path).
- 2026-08-02: `adapters/claude-code/hooks/lib/workaround-sensor-lib.sh` — new file, task 2 deferred-remainder build: the operator's workaround-as-sensor law, mechanized (`ws_record`/`ws_tail`, spawn-free hot path, self-tested — 15 scenarios).
- 2026-08-02: `adapters/claude-code/hooks/lib/gate-contract-lib.sh` — small additive edit (task 2 deferred-remainder build): new `gc_escape_used <gate> <bypass_kind> <fingerprint> [detail]` function (lazily sources `workaround-sensor-lib.sh`, calls `ws_record`) + 2 new self-test scenarios. Existing `gc_mode`/`gc_block`/`gc_header`/`gc_exit_code` functions and their self-tests are untouched (verified: all three already-retrofitted gates' own self-tests — `scope-enforcement-gate.sh` 49/49, `pre-commit-gate.sh` 11/11, `concurrent-ownership-gate.sh` 21/21 — still pass unmodified against this edit). NOT done: wiring `gc_escape_used` into the five gates' own waiver-honored call sites (out of this dispatch's scope; those gate body files were off-limits).
- 2026-08-02: `docs/harness-guide.md` — two new structural-note paragraphs (docs-freshness-gate requires one alongside any new hook/lib file addition): one updates the first-half note's "not yet built" list, one introduces `hooks/lib/workaround-sensor-lib.sh` + the `gc_escape_used` wiring + the scoped `plan-edit-validator.sh` retrofit, naming what remains unbuilt (harness-hygiene-scan.sh retrofit, doctor gate-message lint, JIT pre-warning hints, call-site wiring into the five gates).

## Assumptions

- The three rounds of operator dialogue recorded in `~/.claude/state/nl-issues.jsonl`
  (2026-08-02, entries a–d) are the binding spec; the considerations brief + its Round 3 section
  is the design of record; Round 3 wins on conflict.
- D5 TTL = 30 min and D3 watermark = 2026-07-27 are decide-and-go defaults (constitution §8) with
  a trail in this plan's Decisions Log; each is a one-line override if the operator answers
  differently.
- The five legacy scheduled tasks disabled during the 2026-08-02 triage stay disabled; re-enable
  (`Enable-ScheduledTask`) is the rollback path until task 3's +30-day deletion.
- The template sync (merge_settings at SessionStart) propagates template ADDITIONS live
  automatically; REMOVALS require the manual reconcile — task 4's cutover plans for this
  explicitly (Edge Case 5), it is not assumed away.
- Measured constants from the brief remain representative on this hardware: 132–190 ms per spawn,
  4.1 s per-Bash chain, 94–119 s coord-sync cycle; task 1 re-measures before tuning targets.
- schtasks (Windows) and launchd (Mac) are available without elevation barriers for per-user
  tasks, as `ensure-cockpit.sh` and the existing installers already demonstrate.
- The accountable-estate program's shipped mechanisms (admission-lib, registration-lib,
  estate-merge, close-plan outcome gate, plan-recheck-sweep) are stable dependencies; nothing in
  this plan modifies their semantics.
- Builder-session bands are engineering estimates: the mined harness-mechanism class
  (docs/loe/loe-calibration.md) has 2.1% builder-session coverage, so the brief §6 bands are the
  prior, with the class cited for future calibration.

## Edge Cases

1. Resume storm during the stage-2 cutover window (old chain + new stub both wired): the
   both-substrates doctor RED plus a freeze-window cutover (coordinate-estate skill) bounds the
   window; the single-flight lib (task 1) already caps the blast radius before stage 2 begins.
2. Machine asleep or off at a scheduled fire: completion-anchored re-arm + StartWhenAvailable
   semantics on the anchor task; a missed fire delays, never stacks.
3. Snapshot read racing a write: atomic tmp+rename only — a reader sees the old or the new
   snapshot, never a partial one.
4. HALT set while a job is mid-flight: drain semantics — the running job finishes, nothing new
   arms, the flag state is visible in freshness health so a forgotten HALT cannot look green.
5. Live-settings drift on removals: the additive template sync lands additions but not removals
   (recorded memory), so every task-4 wiring removal includes the live reconcile step and a
   doctor edge-profile check that compares live wiring against the template.
6. `--check`/enforce divergence: structurally prevented — one shared decision function per gate
   (task 2); the golden-scenario replay in stage 2 double-checks it end-to-end.
7. Clock skew across machines: freshness TTLs are evaluated per-machine against that machine's
   own snapshots; no cross-machine wall-clock comparison is load-bearing.
8. darwin/BSD userland differences (date, stat, sed flags): the portable core's `--self-test`
   runs on both interpreters/platforms; platform-specifics live only in the adapters.
9. A wrong-strict stub blocking protected-orchestrator traffic: the 7-day observe-first diff plus
   the named fallback (stubs source gate scripts in-process) — never silent, never a storm
   readmission.
10. Bulk ack eating a live operator ask: the drain cross-checks the ask-registry SLA view before
    acking anything post-watermark; pre-watermark items are superseded by this redesign by
    definition (D3 rationale).

## Acceptance Scenarios

n/a — harness-development plan, no product user (see acceptance-exempt-reason in the header). The
per-artifact `--self-test` suites plus the Stage 4 soak metric are the runtime demonstration; each
task's "Prove it works" block is executed live and cited in the evidence file.

## Out-of-scope scenarios

None proposed-and-rejected — the deliberate exclusions (WSL2, new hardware, builder hosting,
reaper arming, rule-semantics changes) are recorded in Scope OUT and the brief's R3 section rather
than as acceptance scenarios.

## Behavioral Contracts

### Idempotency
Every maintenance job is re-runnable: snapshots are atomic tmp+rename (a re-run overwrites with
fresher truth, never corrupts); the installers converge (re-running registers/updates the single
task, never duplicates — IgnoreNew); ledger appends carry per-emitter sequence numbers so replayed
events are detectable and folds are idempotent; the drain (task 6) acks by watermark predicate, so
re-running it is a no-op.

### Performance budget
Per-Bash hook chain ≤ 0.5 s; SessionStart/resume ≤ 2 spawns; doctor `--quick` < 2 s (cache hit
after stage 1, cold after the stage-4 drain); the maintenance core's steady-state ≤ 5% CPU on the
weakest machine with < 15% total at idle (the closure soak); every recurring mechanism declares
cost × fire-rate with per-platform lines in the schedule manifest, and the doctor REDs over-budget
entries (invariant 1).

### Retry semantics
Completion-anchored: a failed job run re-arms its next run with backoff — overlap is impossible by
construction; leases that expire re-surface the obligation exactly once per interval with a
detected-loss record (no unbounded retry); the watchdog kill-and-relaunches the core only on
output-freshness RED, and each relaunch is a death-certificate row; storm-capable fail-open
categories time-box to fail-closed at 24 h rather than retrying forever.

### Failure modes
Half-death (green loop, dead jobs): countered by output-freshness health — verdicts come from
`generated_at`, never from loop liveness. Lost events: lease expiry + the anti-entropy floor
self-heal within one interval. Fail-open decay: degradation banner injected into session context
(guaranteed-read channel), never just logs. Dual-substrate drift: doctor RED on both-substrates
alive > 14 days. Cache lying while the world burns: fingerprints are DERIVED from declared inputs,
bypasses are ledgered, and a check with no declared inputs REDs (invariant 8).

## Closure Contract
- **Commands that run:** `bash adapters/claude-code/scripts/nl-maintenance.sh --self-test`;
  `bash adapters/claude-code/hooks/harness-doctor.sh --quick` (twice — cold + cached, timed);
  each retrofitted gate's `--check` against its violating + clean fixtures; the stage-2 golden-
  scenario replay; the 24 h soak measurement read from the pressure snapshot.
- **Expected outputs:** self-tests exit 0; doctor GREEN including the new lint/budget/cadence
  checks; `--check` verdicts match the enforce path on the fixtures; soak shows < 15% average
  CPU with all functions enabled; inventory counts at or under the R3.3 targets.
- **On-disk artifact location:** `docs/plans/harness-execution-redesign-2026-08-evidence.md`
  (per-task evidence blocks incl. the soak CPU series) plus the structured
  `.evidence.json` artifacts written via `write-evidence.sh capture` per task.
- **Done when:** all six tasks are task-verifier PASS AND the evidence file contains the soak
  artifact with a < 15% verdict AND `## Closure Outcome` below carries the +30-day re-check date
  — at which point close-plan.sh's outcome gate permits the Status flip.

## Testing Strategy

- Per-artifact `--self-test`, fixture-sandboxed under the `HARNESS_SELFTEST=1` conventions, on
  bash 3.2 and 5.x (the estate's two interpreter families), for: single-flight-lib,
  gate-contract-lib, event-contract-lib, nl-maintenance, both installers, each stub.
- Observe-first windows before every behavior flip: cadence/budget checks WARN one calibration
  week before RED (task 1); stubs log would-block against live gates for 7 days before cutover
  (task 4); cleanup-as-sensor logs before any doctor RED on missing learning records (task 5).
- Measured outcomes, not asserted ones: per-Bash latency timed over 20 representative commands;
  doctor timed cold and cached; the soak read from the pressure snapshot's CPU series; each
  number lands in the evidence file with its command line.
- Block-semantics equivalence: the stage-2 replay of the replaced gates' golden scenarios through
  the stubs must produce a zero-diff decision log — the brief's exit criterion for stage 2.
- The doctor is the arbiter (constitution §10): every mechanism claim this plan adds is a doctor
  check or it is not claimed; `harness-doctor.sh --quick` GREEN on both Windows machines and the
  Mac is part of every task's done-bar.

## Walking Skeleton
Task 1 is the skeleton: one lib guard sourced by the two heaviest entry points, one manifest
entry, one doctor check, and the HALT flag — the thinnest slice that exercises lib → wiring →
doctor → operator surface end-to-end on the live estate before any architecture moves. First
task: 1.

## Decisions Log
- 2026-08-02: `frozen: true` at creation — the spec was settled by three operator design rounds
  (nl-issues 2026-08-02 a–d) ending in an explicit GO; freezing at birth spares builders a
  thaw-flip round-trip. Revert = flip the field.
- 2026-08-02: D5 TTL default 30 min adopted decide-and-go (§8) — one config value to change if
  the operator answers `10m`/`event`; the bypass ledger keeps the escape hatch honest either way.
- 2026-08-02: D3 watermark default 2026-07-27 (the freeze) adopted decide-and-go for task 6 —
  overridable until the drain actually runs; the ask-registry cross-check bounds the risk.
- 2026-08-02: Reaper arming (D2) excluded from this plan — irreversible-kill class stays an
  explicit operator decision; observe mode continues meanwhile.
- 2026-08-02: The downstream-product health monitor becomes an internal job of the maintenance
  core (task 3) rather than staying a standalone task — same cadence, one fewer resident spawn
  tree; revert = re-register its task from the existing installer.

## Definition of Done
- [ ] All six tasks checked off (task-verifier is the only checkbox-flipper)
- [ ] All `--self-test` suites pass on both interpreter families and all three machines' platforms
- [ ] Evidence file complete: per-task blocks + the soak CPU series + before/after inventory counts
- [ ] SCRATCHPAD.md updated with final state
- [ ] `## Closure Outcome` populated with the real close-date +30-day re-check before Status flips

## Closure Outcome
Outcome metric: 24 h idle soak with ALL maintenance functions enabled shows < 15% average CPU
(pressure-snapshot CPU series in the evidence file); per-Bash hook latency ≤ 0.5 s measured;
inventory at targets (scheduled tasks ≤ 2/machine, hooks-per-Bash ≤ 6, SessionStart spawns ≤ 2);
doctor gate-message lint 5/5; doctor `--quick` < 2 s cold. Recurrence check: the soak re-run at
the re-check date stays under 15% — a miss auto-reopens this plan via `plan-recheck-sweep.sh`.
Re-check date: 2026-09-22 (set now as target-completion-date + 30 days; refreshed to actual
close-date + 30 days by close-plan.sh at the real close).
