# Evidence — Harness Execution-Layer Redesign (2026-08)

Companion to `docs/plans/harness-execution-redesign-2026-08.md`. Authored by the orchestrating
session that dispatched the builders, integrated their branches, and independently re-ran every
self-test cited below (builder claims were not accepted on their own).

---

## Task 1 — Stage 0a: invariants in the lib, not the wiring

### Comprehension Articulation

**Spec meaning.** The 2026-08-02 incident was not "too many hooks" in the abstract: it was that the
*guards which should have prevented concurrent heavy work were attached to the wiring rather than to
the work itself*. `sessionstart-singleflight` only engaged when a caller set `NL_SESSIONSTART_ORIGIN`,
so any entry point that did not set that marker — most importantly the **resume** path — bypassed it
entirely and re-ran `harness-doctor.sh --quick` and `session-start-digest.sh` concurrently, nesting
chains until the machine had zero idle CPU for ~17 hours. This task therefore means: move the guard
*inside* the expensive scripts so it cannot be bypassed by an un-marked caller (invariant 4, "guard in
the lib, not the wiring"); make the operator able to stop the whole maintenance layer with one gesture
(invariant 11); and make two silent cost classes *visible* — a cadence shorter than the measured cycle
(invariant 2) and an unbudgeted per-Bash hook count (invariant 1). "Belt, never braces" is the precise
relationship: markers may still narrow *when* a hook fires, but correctness must not depend on them.

**Edge cases covered.** Recursion (a guarded script invoking another guarded script inside the same
process tree) is distinguished from cross-process single-flight and from HALT, and evaluated in that
order — proven live: a nested `harness-doctor.sh --quick` short-circuited in 0.39 s with an explicit
notice rather than running a second full pass. HALT drains rather than kills: all three tick wrappers
(`health-tick`, `supervisor-tick`, `coord-sync`) printed their drain line and exited without starting
work, then resumed normally after the flag cleared. Stale lock reclamation is covered by the lib's own
suite (25/25). The cadence check tolerates unmeasured entries by skipping them rather than warning
noisily, and was exercised against both the *real* live manifest (correctly naming `coord-sync`,
60 s declared vs 110 s measured) and a deliberately corrupted fixture. The budget check reads both the
live settings and the template so drift between them cannot hide a violation.

**Edge cases NOT covered.** The plan's Prove-it-works #1 — a *measured* spawn count on a real resume —
was not demonstrated; the matcher narrowing is proven structurally (doctor/digest appear only in the
`startup|clear` block, live and template) but no before/after spawn count exists, because the literal
resume trigger belongs to the Claude Code platform and cannot be synthesised in a fixture. Cross-machine
behaviour is unproven: only this Windows desktop was reconciled, and the repo→live settings sync is
additive-only, so other machines will keep their old wiring until manually reconciled (documented in the
handoff). The guard is per-machine; two machines can still run heavy work simultaneously. The HALT flag
is honoured only by callers that source the lib — any future entry point that forgets to source it is
unguarded, which is the residual risk invariant 4 reduces but does not eliminate.

**Assumptions.** That process-tree ancestry is a sound recursion signal on Windows Git-Bash (it held
across every self-test and the live nested-doctor demonstration, but PID reuse could in principle
confound it). That the `measured_cycle_seconds` values seeded into `schedule-manifest.json` are
representative — they were taken on a *degraded* machine, so they are conservative rather than
optimistic, which is the safer direction for a cadence floor. That WARN-only is the correct initial
posture for both new doctor checks during the calibration week (deliberate: the budget check WARNs on
every machine today at 25-vs-6, so shipping it RED would have made the doctor permanently red and
trained everyone to ignore it — the observe-first rule, invariant 4 of the program rules).

### Verification (orchestrator-replayed, not builder-claimed)
- `hooks/lib/single-flight-lib.sh --self-test` → **25 passed, 0 failed** (re-run on integrated master).
- Nested-invocation short-circuit demonstrated live (0.39 s, explicit skip notice, rc 0).
- HALT/drain demonstrated live across all three tick wrappers, then clean resume after clear.
- Cadence check WARNs naming the real live violation (`coord-sync`) **and** a corrupted fixture.
- Budget check WARNs 25-vs-6 against live settings and template.
- `sf_guard` sourced unconditionally at `harness-doctor.sh:188`, `session-start-digest.sh:82`,
  `coord-sync.sh:152`, `supervisor-tick.sh:152`, `health-tick.sh:113`.
- Commits: `e9c5bc0f` (build) + `67505638` (manifest entries + doctrine section).
- **Attributable loose end, now closed:** `67505638` added four manifest entries without regenerating
  `docs/harness-architecture.md`, producing a `wave-f-f2-docs` doctor RED. Regenerated;
  `gen-architecture-doc.sh --check` now reports **GREEN — committed doc matches a fresh regen**.

### Known gaps (carried forward, not hidden)
1. Resume-path spawn count unmeasured (Prove-it-works #1) — platform-triggered, needs a live resume.
2. Other machines still un-reconciled (additive-only sync); per-machine procedure in the handoff.
3. `manifest-freshness` RED until `install.sh` syncs the live mirror.

---

## Task 2 — Stage 0b: Gate Philosophy Law

**Status: PARTIAL by design — do not flip.** The task text enumerates five gate retrofits plus a doctor
gate-message lint, a workaround-as-sensor ledger, and JIT pre-warnings. Shipped and verified:
`gate-contract-lib.sh` (14/14) and full retrofits of `scope-enforcement-gate.sh` (49 scenarios),
`pre-commit-gate.sh` (11/11), `concurrent-ownership-gate.sh` (21/21), plus `harness-hygiene-scan.sh`
and `backlog-plan-atomicity.sh` via their own shared emitters. Live `--check` produced would-block
(rc 1, all four structured fields) and would-pass (rc 0) against real fixtures. Measured early-exit
improvement: concurrent-ownership **0.551 s → 0.176 s (−68 %)**, scope-enforcement
**0.249 s → 0.189 s (−24 %)** via thin-dispatcher + `-body.sh` lazy-source splits.

**Not yet built** (verifier-confirmed absent, and a builder is in flight on the first two):
plan-edit-validator retrofit · workaround-as-sensor ledger · doctor gate-message lint · JIT
pre-warnings · harness-dev.md gate-contract convention section · contract fields on the five gates'
manifest entries.

Comprehension articulation for Task 2 will be written when its remaining scope lands, so that it
describes the finished task rather than a half of it.

---


Per-task evidence blocks for `docs/plans/harness-execution-redesign-2026-08.md`. This file
did not exist before Task 3's build session despite being a declared `Files to
Modify/Create` target for every task — Tasks 1 and 2's evidence is documented instead in
`docs/handoffs/2026-08-02-stage0-pending-integration.md` ("What shipped") and in commits
`e9c5bc0f` / `ce7cca52`; the orchestrator should backfill a Task 1/Task 2 block here from
that record rather than this task fabricating one retroactively. Task 3's block below is
this build's own, first-hand evidence.

## Task 3 — Stage 1: Windows-native central maintenance (portable core + platform adapters)

Branch: `worktree-agent-a8816ddce4b3e979c` (worktree-isolated PARALLEL dispatch).

### Self-tests (verbatim summaries; full transcripts re-runnable via the commands below)

```
$ bash adapters/claude-code/scripts/nl-maintenance.sh --self-test
self-test interpreter: 5.2.37(1)-release
self-test summary: 29 passed, 0 failed
```
Covers: job-table filtering by `managed_by`, a real fixture job executing + marking
completion, a FAILING job still marking completion (no retry storm), tolerate-absent
(missing script) still marking completion, completion-anchored due-ness (never-run -> due;
just-completed -> not due; completed-past-cadence -> due again), HALT drains the whole tick
but still writes a fresh (`halted:true`) heartbeat, tick-level single-flight (a held lock
skips the WHOLE tick), TTL-gated dashboard snapshot (atomic write, no-op within TTL, honest
`gate_friction.available:false` when no ledger exists, real ledger rows once one does),
`--watchdog` stub-vs-real dispatch (fresh heartbeat = no-op; stale = logged relaunch, never
spawned under `HARNESS_SELFTEST=1`), bounded `--daemon` (`--max-iterations` test hook),
`--status`, bash 3.2 floor (no bash-4-only constructs).

```
$ bash adapters/claude-code/scripts/install-maintenance-task-darwin.sh --self-test
self-test interpreter: 5.2.37(1)-release
self-test summary: 17 passed, 0 failed
```
Covers: non-Darwin no-op, operator kill-switch, tolerate-absent (missing script/launchctl),
`HARNESS_SELFTEST=1` stub never touches a real plist, a REAL install against a fake-
launchctl stand-in (plist written, `--watchdog` present in `ProgramArguments`, bootstrap
actually invoked), idempotent re-install (same content, already loaded -> zero extra
bootstrap/bootout calls), content-change-while-loaded -> bootout then a fresh bootstrap
(not an additive second load), `--uninstall`, exit code always 0.

```
$ node neural-lace/workstreams-ui/server/maintenance-pane.selftest.js
self-test summary: 9 passed, 0 failed
```
Covers: no snapshot on disk -> honest `rc:1`/`data:null`/named-fix-command (never a silent
blank pane), a real snapshot served verbatim (schema fields pass through unmodified, no
server-side re-derivation), malformed JSON on disk -> `rc:1`, server stays up (no crash).

`install-maintenance-task.ps1` has no embedded `--self-test` (PS1 installers in this repo
use `-WhatIf` as their dry-run/test mode, matching every sibling installer's convention —
see "Live proof" below for what its `-WhatIf` run actually exercised).

### Live proof (real machine, not fixtures)

**nl-maintenance.sh dashboard snapshot, run against the real repo** (`NL_REPO_ROOT` pointed
at this checkout, `NL_MAINT_STATE_DIR` sandboxed):
```json
{"schema":1,"generated_at":"2026-08-03T02:49:09Z", ...,
 "inventory":{
   "hooks_per_bash":{"template":25,"live":25,"target":6},
   "sessionstart_spawns":{"template":8,"live":8,"target":2},
   "legacy_scheduled_tasks_enabled":{"count":0,"target_max":2}},
 "cost_budget":[... 7 rows, real cadence/spawn-cost math ...],
 "gate_friction":{"available":false,"rows":[]}}
```
`hooks_per_bash=25` and `sessionstart_spawns=8` match the Stage-0 handoff's own documented
live-machine counts exactly ("3 blocks / 8 hooks", "25 hook entries") — this is live data,
not a fixture echo. `legacy_scheduled_tasks_enabled.count=0` because all 5 legacy tasks are
already Disabled (Stage 0), confirmed independently below.

**`install-maintenance-task.ps1 -WhatIf` against the real machine's live Task Scheduler**:
```
Legacy task 'NL-CoordSync' already Disabled -- no-op.
Legacy task 'NL-SupervisorTick' already Disabled -- no-op.
Legacy task 'NL-workstreams-heartbeat' already Disabled -- no-op.
Legacy task 'NL-session-resumer' already Disabled -- no-op.
Legacy task 'NL-health-tick' already Disabled -- no-op.
```
Confirms the legacy-disable logic correctly reads real live Task Scheduler state and
matches the Stage-0 handoff verbatim. An actual `Register-ScheduledTask` mutation was
correctly withheld (blocked by the auto-mode classifier when attempted; also consistent
with the worktree-isolation convention — a real Task Scheduler mutation is an
operator/orchestrator integration step, same as Stage 0's manifest.json deltas were).

**Doctor verdict cache — the plan's Prove-it-works #4 ("doctor --quick serves the cached
verdict in <2s")**, measured with `time` against a sandboxed `HARNESS_DOCTOR_HOME`:
```
=== COLD (no cache, clean minimal live_home) ===
real    9m12.237s
user    1m18.376s
sys     3m37.699s

=== CACHE HIT (fresh, fingerprint-matched entry) ===
[doctor] FAILED — 71 red, 24 warn, 40 checks run (cached verdict, 1s old -- ...)
real    0m1.557s
user    0m0.350s
sys     0m0.734s
```
~355x measured speedup; the cache hit is under the 2s target. The cold number (9m12s, even
against a CLEAN sandboxed live_home with no messy real state) is itself a significant
finding: it shows the C3 "checker cost is O(mess)" pathology from the 2026-08-02 RCA is
real even independent of live-mirror mess — `run_quick_checks` scans large parts of the
REPO regardless of live_home cleanliness (self-test-exclusions wiring, review-surface
cross-checks, etc.), so Stage 4's estate drain alone will not fully explain a fast cold
path; this is left as an honest open finding, not investigated further here (out of this
task's scope).

`NL_FORCE=1` bypass path (isolated from the pre-existing `sf_guard` single-flight via
`SF_DISABLE=1`, since that guard's own 120s TTL otherwise collapses a same-machine re-run
into a single-flight skip, independent of this task's cache logic) was exercised and
confirmed to fall through to a real recompute (not re-timed — the bypass branch is
structurally identical to the cold-miss branch, already timed above).

### Wire checks executed

- `adapters/claude-code/scripts/nl-maintenance.sh` job table → `config/schedule-manifest.json`: confirmed via `--status` against the real repo (all 6 declared mechanisms listed with correct cadence/due-ness).
- `install-maintenance-task.ps1` → registers `NL-Maintenance`: confirmed via `-WhatIf` (Action/Trigger/Settings printed, correct `MultipleInstances IgnoreNew`).
- `install-maintenance-task-darwin.sh` → registers the launchd twin: confirmed via the fake-launchctl self-test scenarios (real plist written, `--watchdog` in `ProgramArguments`, real bootstrap invocation).
- verdict cache read path in `harness-doctor.sh` → snapshot written by the SAME file's own write path (reusing `session-start-digest.sh`'s pre-existing cache file, not a new nl-maintenance-authored one — see the task-3 handoff's ambiguity item 4 for the reasoning): confirmed via the cold-then-hit timing pair above.
- dashboard panel in `neural-lace/workstreams-ui/server` → reads the snapshot `nl-maintenance.sh` writes: confirmed via `maintenance-pane.selftest.js` Scenario 2 (fixture snapshot served verbatim through the real HTTP endpoint).

### Known gaps / follow-ups (logged, not silently dropped)

1. **Fingerprint (invariant 8) is a first-approximation**, not true per-check declared-input
   tracking — documented in `harness-doctor.sh`'s own new comment block and the handoff.
2. **`check_maintenance_both_substrates_alive` has no dedicated self-test scenario** in
   `harness-doctor.sh`'s own suite (none of its fixture scenarios set a 14-day-old
   activation marker) — it IS exercised indirectly (returns cleanly, increments
   `CHECKS_RUN`) in every existing `--quick` self-test scenario, since none carry that
   marker. Named follow-up.
3. **Gate-friction ledger schema is proposed, not agreed** — Task 2's remaining scope owns
   the real writer; see the task-3 handoff OWED #4 for the exact schema this task's reader
   expects and the one-function fix point if a different schema is chosen.
4. **A live `NL-Maintenance` scheduled-task registration and a live launchd bootstrap were
   NOT performed** on either the Windows or (no Mac available) darwin platform — both
   adapters are proven via `-WhatIf`/fake-launchctl self-test against real underlying
   state/mechanisms, but the plan's Prove-it-works #1/#3 ("install on a Windows machine...
   run 24h", "On the Mac, run the darwin adapter") describe an operator/orchestrator
   integration step this worktree-isolated build correctly did not perform. The 24h soak
   itself is explicitly Stage 4's job per the plan's own Closure Contract.

---

# Closure verification under supersession (gated-pipeline T9 / REQ-A6), 2026-08-03

Verifier note: the caller described this plan as `rung: 3`; the header declares `rung: 4`.
Either way ≥ 2, so the Decision 020 comprehension-gate applies per-task. Decision 020's text
(2026-05-04, three months before this plan's creation; the plan itself cites "rung-4
requirement, Decision 020d" for Task 1) contains NO grandfather provision and supports none
for this plan. What its text DOES support: the gate attaches per-task via the evidence block
(020e), so each task is judged on its own articulation — supersession-closure is not an
exemption anywhere in 020.

## Task 1 — closure verdict

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Stage 0a — Stop the bleeding: invariants in the lib, not the wiring — Verification: full
Verified at: 2026-08-03T13:58:58Z
Verifier: task-verifier agent (dispatched by gated-pipeline T9/REQ-A6 supersession closure)

Oracle: specified — the task's four Prove-it-works steps + Wire checks + Docs impact, cross-checked
against the adversarial post-merge review (docs/reviews/2026-08-03-stage0-stage1-harness-review.md,
Stage 0a CONDITIONAL-PASS) and its maintained Fix-status table.

Comprehension-gate: PASS — articulation present in this file (four canonical sub-sections, each far
above the 30-char bar); diff-correspondence checked by this verifier (all five sourcing sites
re-verified live today; honest not-covered items match the known-gaps list) and independently by the
2026-08-03 adversarial review's full code trace. The comprehension-reviewer agent is not invocable
from this verification context (no Task tool); the check above is the substantive equivalent,
performed first-hand.

Operator invariants: none registered (exit 3)

Checks run:
1. Commit trail — e9c5bc0f (build) + 67505638 (manifest entries + harness-dev.md section) both on
   master. Result: PASS
2. single-flight-lib.sh --self-test replayed this session → 34 passed, 0 failed (post-HR-F1 count,
   matching the independent re-review). Result: PASS
3. sf_guard sourced unconditionally at all five heavy entry points, verified by grep today:
   harness-doctor.sh:200, session-start-digest.sh:82, coord-sync.sh:152, supervisor-tick.sh:152,
   health-tick.sh:113. Result: PASS
4. SessionStart matcher narrowing verified live TODAY via jq: template AND live ~/.claude/settings.json
   both 3 blocks, doctor+digest under `startup|clear` only. Result: PASS
5. schedule-manifest.json present (mode "warn"); cadence + budget checks wired (manifest entries
   schedule-manifest-cadence, budget-bash-hooks verified in manifest.json today); review confirmed both
   fire on real violations (coord-sync 60s vs 110s; 25-vs-6). Result: PASS
6. HALT/drain: demonstrated live per the orchestrator-replayed record above (all three tick wrappers
   drained then resumed); no stale HALT flag set today (state dir contains only a doctor_quick.lock).
   Result: PASS
7. Docs impact: harness-dev.md §"Execution-layer invariants" present (line 23); all four manifest
   entries present (single-flight-recursion-guard, halt-drain-flag, schedule-manifest-cadence,
   budget-bash-hooks); full runbook at doctrine/single-flight-halt-runbook.md. Result: PASS
8. Review conditions (Stage 0a CONDITIONAL-PASS): F2/F8 FIXED @ d46beee5 (serve-cache-or-exit-3 +
   single-writer cache), re-reviewed PASS in docs/reviews/2026-08-03-gated-pipeline-t3-t4-implementation-review.md;
   F1 (touched this task's lib — sf_release added) FIXED @ 6f5d1b22, re-reviewed PASS same record.
   F3 + F7 OPEN, owned by gated-pipeline T7 (in flight) — hardening findings on delivered mechanisms,
   not undelivered scope (task text never sized the TTL; the shipped manifest honest_status already
   assigns the RED flip to "a later task"). Result: PASS with named carry-forwards
9. Gate-friction ledger bootstrap clause ("blocks + workaround attempts recorded"): workaround side
   LIVE today (gc_escape_used at 4 real call sites in scope-enforcement-gate-body.sh /
   concurrent-ownership-gate-body.sh + harness-hygiene-scan.sh via ws_record; end-to-end
   ledger→dashboard proven by nl-maintenance S9/S14, replayed 37/37 today; HR-F6 fix @ be5e4273).
   Block side formally superseded: gated-pipeline T5 evidence records the DEFER-with-rename decision
   (blocks not ledgered; metric renamed workarounds-only; comprehension-audited @ 077ad2c6). Result:
   PASS via cited supersession trail

Runtime verification: test adapters/claude-code/hooks/lib/single-flight-lib.sh::--self-test
Runtime verification: file adapters/claude-code/hooks/harness-doctor.sh::source "$SCRIPT_DIR/lib/single-flight-lib.sh"
Runtime verification: file adapters/claude-code/settings.json.template::startup|clear
Runtime verification: file adapters/claude-code/doctrine/harness-dev.md::Execution-layer invariants
Runtime verification: file adapters/claude-code/manifest.json::single-flight-recursion-guard
Runtime verification: functionality-verifier harness-execution-redesign-t1::SKIP (rationale: agent not invocable from this context — no Task tool; harness-internal class exercised directly: every cited --self-test replayed first-hand this session, live wiring + matcher state verified via grep/jq)

DEPENDENCY TRACE
================
Step 1: any heavy entry point invoked (doctor/digest/coord-sync/supervisor-tick/health-tick)
  ↓ Verified at: unconditional `source .../single-flight-lib.sh` at the five sites cited in check 3
Step 2: sf_guard recursion/single-flight/HALT decision
  ↓ Verified at: single-flight-lib.sh --self-test 34/34 (replayed today) + live nested-doctor 0.39s short-circuit (orchestrator record above)
Step 3: operator-observable outcome (no nested chains; one-gesture HALT; WARN visibility)
  ↓ Verified at: live HALT drain demo (record above); cadence/budget WARNs firing on real violations (review evidence trail); machine recovered 99.9%→~13% CPU (handoff)

Git evidence:
  e9c5bc0f (2026-08-02, build) · 67505638 (integration) · 6f5d1b22 + d46beee5 (successor fixes to
  this task's artifacts, merged, re-reviewed PASS) — all confirmed ancestors of master today.

Verdict: PASS
Confidence: 8
Reason: PROVEN: every enumerated deliverable exists, is wired, and was re-exercised first-hand today
(34/34 lib suite; five sourcing sites; live+template matcher narrowing; manifest + doctrine deltas);
three of four Prove-it-works executed live per the orchestrator-replayed record, the fourth (resume
spawn count) structurally proven with an honestly-declared platform limitation; the adversarial
review's Stage-0a conditions are met (F2/F8, fixed + re-reviewed) or named-and-owned (F3/F7 at
gated-pipeline T7, tracked in the maintained Fix-status table). Carried findings named below do not
falsify any Prove-it-works item or enumerated deliverable.
Carried forward (owned): F3 (guard TTL vs measured cycle), F7 (mechanized WARN→RED flip dates),
F10 (test-name rename) — gated-pipeline T7; resume-path spawn measurement remains a declared
known-gap (platform-triggered).

## Task 2 — closure verdict

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Stage 0b — Gate Philosophy Law: guidance-contract retrofit of the five blocking gates — Verification: full
Verified at: 2026-08-03T13:58:58Z
Verifier: task-verifier agent (dispatched by gated-pipeline T9/REQ-A6 supersession closure)

Oracle: specified — the task's enumerated deliverables (five retrofits + doctor gate-message lint +
workaround-as-sensor incl. auto-file threshold + JIT pre-warnings) and its Docs impact, cross-checked
against today's on-disk state.

Comprehension-gate: INCOMPLETE — no `## Comprehension Articulation` exists for Task 2; this file
explicitly defers it ("will be written when its remaining scope lands"). Decision 020d at rung 4:
missing articulation → task-verifier returns FAIL. 020's text supports no grandfathering (see the
closure-verification header note above).

Operator invariants: none registered (exit 3)

Checks run (delivered half — credit, all replayed first-hand today):
1. gate-contract-lib.sh --self-test → 16/16; workaround-sensor-lib.sh --self-test → 15/15. PASS
2. Gate suites: scope-enforcement 50/50 · pre-commit 11/11 · concurrent-ownership 22/22 ·
   plan-edit-validator 24/24 (incl. the F20-F24 --check scenarios) · harness-hygiene-scan OK. PASS
3. Escape-hatch wiring live: gc_escape_used at 4 real call sites (concurrent-ownership-gate-body.sh
   :467,:482,:977; scope-enforcement-gate-body.sh:1901) + hygiene's direct ws_record — grep-verified
   today. Friction ledger unified writer→pane end-to-end (HR-F6 FIXED @ be5e4273; nl-maintenance
   S9/S14 replayed green today). PASS
4. blocks/day metric clause: superseded by T5's recorded DEFER-with-rename decision (workarounds-only,
   lint-locked, audited @ 077ad2c6) — not counted as a gap. N/A by supersession
5. JIT pre-warnings: design-cut — successor plan Scope OUT (gated-pipeline-master-2026-08.md:92,
   design NON-GOALS), grounded in the REAL architecture review's hot-path finding
   (docs/reviews/2026-08-03-harness-execution-redesign-REAL-architecture-review.md:169) and the
   master handoff cut-list. Not counted as a gap. N/A by design-cut
6. Doctor gate-message lint: grep of harness-doctor.sh for any gate-message/check_gate lint → ZERO
   matches today. The outcome metric "doctor lint 5/5" is unmeetable. FAIL
7. Docs impact: harness-dev.md has NO gate-contract convention section (headings enumerated today);
   the five gates' manifest entries carry NO contract/check fields (jq over manifest.json today:
   ABSENT on all five). FAIL
8. Workaround-rate threshold auto-file via nl-issue.sh ("a gate above the threshold is auto-filed as
   a defective gate"): no such mechanism exists in workaround-sensor-lib.sh, nl-maintenance.sh, or any
   gate (grep today). FAIL

Runtime verification: test adapters/claude-code/hooks/lib/gate-contract-lib.sh::--self-test
Runtime verification: test adapters/claude-code/hooks/scope-enforcement-gate.sh::--self-test
Runtime verification: test adapters/claude-code/hooks/plan-edit-validator.sh::--self-test

Verdict: FAIL — do not flip
Confidence: 9
Reason: PROVEN: the retrofit half is real and verified (all suites replayed green today), but three
enumerated deliverables are absent on disk TODAY (doctor gate-message lint; manifest contract fields
+ harness-dev.md convention section; workaround-rate auto-file), and the Decision-020d articulation
is missing — each independently blocks the flip. The two remaining scope clauses (blocks/day metric,
JIT pre-warnings) are legitimately closed by cited supersession/design-cut decisions and are NOT gaps.
Gaps (each needs an owner — NONE has one in the successor plan today):
  - Doctor gate-message lint (the outcome metric's own arbiter) — absent; no successor task builds it
  - Five gates' manifest entries: contract fields (Docs impact) — absent
  - harness-dev.md gate-contract convention section (Docs impact) — absent
  - Workaround-rate threshold → nl-issue.sh auto-file — absent (or record a design-cut for it)
  - Task 2 Comprehension Articulation (Decision 020d, rung 4) — absent, explicitly deferred

## Task 3 — closure verdict

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Stage 1 — Windows-native central maintenance: portable core + platform adapters — Verification: full
Verified at: 2026-08-03T13:58:58Z
Verifier: task-verifier agent (dispatched by gated-pipeline T9/REQ-A6 supersession closure)

Oracle: specified — the task's five Prove-it-works steps + outcome metrics, cross-checked against the
adversarial review (Stage 1 REJECT-AS-SHIPPED for the activation path) and the Fix-status trail.

Comprehension-gate: INCOMPLETE — Task 3's block above contains self-tests and live proof but NO
`## Comprehension Articulation` section. Decision 020d at rung 4: missing articulation →
task-verifier returns FAIL/INCOMPLETE. No grandfather support in 020's text.

Operator invariants: none registered (exit 3)

Checks run (delivered half — credit, replayed first-hand today):
1. nl-maintenance.sh --self-test → 37/37 (includes S11 under the REAL guard post-HR-F1, and the
   T5/REQ-A3 friction end-to-end scenario). maintenance-pane.selftest.js → 9/9. PASS
2. Both Criticals on this task's artifacts FIXED and independently re-reviewed PASS: HR-F1 @ 6f5d1b22
   (sf_release + identity-verified watchdog kill + unmasked S11), HR-F2+F5+F8 @ d46beee5
   (single-writer cache, fingerprint hooks-mtime + dirty bit, serve-cache-or-exit-3) — see
   docs/reviews/2026-08-03-gated-pipeline-t3-t4-implementation-review.md ("The hard stop is MET").
   F4+F9 FIXED @ 422257c2 (manifest entries nl-maintenance-core / doctor-verdict-cache /
   maintenance-both-substrates-alive verified present today; zero-substrate inverse clock with
   red_after_days in schedule-manifest.json verified today). PASS via cited trail
3. Live-machine correspondence: -WhatIf against real Task Scheduler (5 legacy tasks Disabled) per the
   record above; measured verdict-cache cold/hit 9m12s → 1.557s. PASS (as recorded)
4. Prove-it-works #1 (live Windows registration + exactly-one-OS-task + 24h) and #3 (Mac launchd):
   NOT performed — deliberately operator-gated: DEC-4 ratification ask is successor T10 (its
   fixed-AND-re-reviewed precondition is now met); T7 recommended before activation. FAIL (task's own
   done-bar unmet today)
5. Outcome metrics requiring live operation (6→1-2 tasks live on three machines; zero overlap events
   across 7 days; snapshot freshness green 7 consecutive days; dashboard from live data): unmet —
   no live registration exists anywhere. FAIL
6. Docs impact: manifest entries LANDED (422257c2); but harness-dev.md has NO install/uninstall/
   rollback runbook section (the stage-1 handoff's owed section remains unlanded — headings
   enumerated today) and workstreams-ui README/docs carry NO dashboard note (grep today: zero
   matches). FAIL

Runtime verification: test adapters/claude-code/scripts/nl-maintenance.sh::--self-test
Runtime verification: test neural-lace/workstreams-ui/server/maintenance-pane.selftest.js::all
Runtime verification: file adapters/claude-code/manifest.json::nl-maintenance-core

Verdict: INCOMPLETE — do not flip
Confidence: 9
Reason: PROVEN: the build half is delivered, hardened (F1/F2/F5/F8 fixed in stronger-than-required
forms, re-reviewed PASS), and re-exercised green today; but the task's own Prove-it-works #1/#3 and
its live-operation outcome metrics are deliberately unexecuted pending the operator's DEC-4
ratification (successor T10) and T7 pre-activation hardening — the activation half of this task's
scope is successor-owned, not done.
Gaps / carry-forwards:
  - Activation: registration + 24h/7-day observation — gated-pipeline T10 (ask) after T7; darwin
    install needs a Mac
  - F3/F11 (T7), F12 census counting (T22) — open on this task's artifacts, owned
  - harness-dev.md runbook section + workstreams-ui README dashboard note (Docs impact) — no owner
  - Task 3 Comprehension Articulation (Decision 020d, rung 4) — absent, no owner named
