# Harness Review: execution-redesign Stage 0a / 0b / Stage 1 (post-merge adversarial pass)

**Reviewed commits (all on master, merged WITHOUT the required harness-reviewer pass — this review is the missing gate, run after the fact):**
`e9c5bc0f` (Stage 0a: single-flight-lib + HALT + schedule-manifest + budget checks) ·
`ce7cca52` + `46826022` (Stage 0b: gate-contract-lib + five-gate retrofit) ·
`0110fdae` (plan-edit-validator WARN layer + workaround-sensor-lib) ·
`ed32a7b4` (context-watermark raw-fact fix) ·
`e5432f3c` (Stage 1: nl-maintenance core + adapters + doctor verdict cache + dashboard pane)

**Governing context read:** `docs/plans/harness-execution-redesign-2026-08.md` ·
`docs/designs/harness-execution-redesign-considerations-2026-08-02.md` (12 invariants + R3.1–R3.6) ·
`docs/plans/harness-execution-redesign-2026-08-evidence.md` ·
`adapters/claude-code/doctrine/single-flight-halt-runbook.md` ·
`docs/handoffs/2026-08-02-stage1-pending-integration.md` ·
last 12 entries of `~/.claude/state/nl-issues.jsonl` (binding operator directives 2026-08-02a–e).

**Reviewed at:** 2026-08-03

---

## Verdict: REFORMULATE

Per-stage sub-verdicts:

- **Stage 0a (e9c5bc0f)** — CONDITIONAL-PASS. The lib, HALT, matcher narrowing, and both WARN
  checks are real, wired, self-tested Mechanisms that fire today on real violations. Conditions:
  fix the doctor-skip exit-0 ambiguity (F2/F8), the 120s-TTL-vs-9m-cycle guard gap (F3), and
  mechanize the two WARN checks' flip/retirement conditions (F7).
- **Stage 0b (ce7cca52 / 46826022 / 0110fdae)** — CONDITIONAL-PASS. The highest-quality work in
  the batch: additive retrofits, block semantics provably unchanged (baseline-identical
  self-tests), `--check` sharing the enforce decision site, NL-FINDING-016 trap preserved.
  Condition: resolve the friction-ledger writer/consumer mismatch (F6) BEFORE the in-flight
  call-site wiring lands.
- **`ed32a7b4` context-watermark** — PASS. Golden case named, negative self-test assertions
  (output must NOT contain "% of"), raw-fact-only output. The exemplar the other artifacts
  should be held to.
- **Stage 1 (e5432f3c)** — REJECT AS SHIPPED for the activation path. Two Critical defects
  (F1 daemon accumulation, F2 cache-corruption composition) live in exactly the code the
  operator is about to activate. **Do NOT run `install-maintenance-task.ps1` for real on any
  machine until F1 and F2 are fixed.** The only reason the top line is REFORMULATE and not a
  revert demand is that the live installer has not been executed (evidence file, Known gap #4),
  so the Critical paths are dormant on every machine today.

---

## Independent classification (Step 1 — before reading any self-labels)

| Artifact | Independent class | Basis (content, not label) | Agreement |
|---|---|---|---|
| `hooks/lib/single-flight-lib.sh` + 5 unconditional wirings | Mechanism | fires unconditionally, skips real work, manifest entry `single-flight-recursion-guard`, 25/25 self-test | AGREE |
| HALT/drain flag + runbook | Mechanism (flag) + Pattern (runbook) | flag mechanically drains all wired ticks (demonstrated live per evidence); runbook documents | AGREE |
| `config/schedule-manifest.json` + `check_schedule_manifest_cadence` | Mechanism (WARN-mode) | doctor check fires today on the real coord-sync 60s/110s violation | AGREE |
| `check_budget_bash_hooks` | Mechanism (WARN-mode) | fires today, 25-vs-6, live + template | AGREE |
| `lib/gate-contract-lib.sh` + retrofits (scope-enforcement / pre-commit / concurrent-ownership / harness-hygiene / backlog-plan-atomicity) | Mechanism | called from the real block sites (`gc_block` at scope-enforcement-gate-body.sh:2337, pre-commit-gate.sh:65, concurrent-ownership-gate-body.sh:389); per-gate self-tests assert the fields | AGREE |
| `plan-edit-validator.sh` WARN-layer retrofit | Hybrid | WARN layer advisory by design; the untouched checkbox-flip block stays Mechanism | AGREE — scope-narrowing reasoning honest and correct |
| `lib/workaround-sensor-lib.sh` + `gc_escape_used` | Mechanism SHIPPED UNWIRED | zero call sites in any gate (verified by grep; both files say so explicitly) | AGREE — not theater, because no doc claims it fires. See F6. |
| `context-watermark.sh` unknown-window path | Mechanism | hook behavior + T25–T27 negative assertions | AGREE |
| `scripts/nl-maintenance.sh` + 2 installers + verdict cache + `check_maintenance_both_substrates_alive` + dashboard pane | Mechanism | scheduler + cache + doctor check + HTTP pane, all self-tested | AGREE on class; REJECT on two behaviors (F1, F2) |

No under- or over-claiming found: every artifact that claims enforcement actually fires (or, for
the workaround sensor, explicitly says it does not yet). The constitution-§10 theater class is
NOT present in the shipped copy — with one boundary case: Stage 1's mechanisms are live on
master without their `manifest.json` entries (F9), a claimed-vs-actual inventory gap even though
no prose overclaims.

---

## Evidence trail (commands run; everything marked PROVEN below cites this)

- `git show --stat` on all six commits; full read of `single-flight-lib.sh` (391 ln),
  `gate-contract-lib.sh` (160 ln), `nl-maintenance.sh` (834 ln), `install-maintenance-task.ps1`
  (253 ln), `schedule-manifest.json`, the plan, the considerations brief, the evidence file, the
  runbook; targeted reads of `harness-doctor.sh` (lines 186–333, 2290–2500, 3900–3903,
  7040–7110, 7340–7491), `session-start-digest.sh` (490–564, 2435–2465),
  `scope-enforcement-gate.sh` (full), `scope-enforcement-gate-body.sh` (2300–2380),
  `pre-commit-gate.sh` (25–104), `coord-sync.sh` (145–175).
- `grep SF_DISABLE` across `adapters/claude-code` (found the two amended self-tests + the
  nl-maintenance self-test exports incl. S11's daemon run under SF_DISABLE=1).
- grep `gc_block|GATE:ESCAPE|gc_escape_used` across hooks (confirmed real call sites; confirmed
  ZERO `gc_escape_used` call sites outside the lib self-test).
- `jq` over `settings.json.template` (confirmed doctor+digest now under `startup|clear` only).
- grep over `manifest.json` (Stage-0 entries present: `single-flight-recursion-guard`,
  `halt-drain-flag`, `schedule-manifest-cadence`, `budget-bash-hooks`; Stage-1 entries ABSENT).
- `tail -12 ~/.claude/state/nl-issues.jsonl` (operator directives incl. 2026-08-02e
  push-not-pull compliance-failure class — checked the new dashboard pane against it: the pane
  reads a snapshot FILE per request, no subprocess poll; compliant).
- Wiring check of the three new doctor checks into `run_quick_checks` (lines 3900–3903).

---

## Remedy-chain / composition analysis (ADR 059 D5, extended to guard-skip paths)

The five gate retrofits are message-additive with baseline-identical self-tests, so their remedy
chains are unchanged from their previously-reviewed state (scope-gate's In-flight-scope-update
remedy retains the NL-FINDING-019 exemption; pre-commit-gate retains the NL-FINDING-016
compound-command EXIT trap — verified at `pre-commit-gate.sh:35–52`). The NEW composition
defects are in the guard/cache layer:

| Prescribed remedy / skip path | Tool call it implies | Other mechanism that also fires | Deadlock / corruption? |
|---|---|---|---|
| cadence WARN's fix: "move it to completion-anchored scheduling (Stage 1)" | adopt `managed_by: nl-maintenance` | `check_schedule_manifest_cadence` has NO `managed_by` filter (harness-doctor.sh:2342–2364) | **Remedy does not clear the WARN** — coord-sync will warn forever even after its prescribed fix is implemented (F7) |
| `sf_guard` skip in doctor → `exit 0`, no verdict line (harness-doctor.sh:7364–7366) | any caller consuming doctor output | `refresh_doctor_cache` (session-start-digest.sh:528–535) greps for `GREEN\|FAILED`, finds nothing, writes `verdict unavailable (exit 0)` OVER the fingerprinted cache entry | **YES — cache corruption** (F2) |
| doctor cache HIT (echo cached verdict, exit) | `refresh_doctor_cache` subprocess call | digest re-stamps the cached verdict with `ts=now` and NO fingerprint | **Staleness laundering + fast-path destruction** (F2) |
| watchdog remedy for stale heartbeat: relaunch `--daemon` (nl-maintenance.sh:575–580) | nohup new daemon; old daemon NOT killed | `sf_guard` recursion guard wedges every daemon after its first tick (F1 trace) | **YES — unbounded process accumulation** (F1) |
| HALT one-gesture (runbook:69) | write `~/.claude/state/single-flight/HALT` | `sf_guard` in doctor drains → `harness-doctor.sh --quick` exits 0 with no verdict during the emergency | **Arbiter unavailable exactly when diagnosing the emergency** (F8) |

---

## Answers to the seven weighted questions

**Q1 (classification / theater):** table above. No §10 theater in the shipped copy. The nearest
misses are F9 (Stage-1 mechanisms on master with no manifest entries — the enforcement
inventory doesn't know about the arbiter's own cache) and F4 (invariant-9's inverse: the doctor
REDs both-substrates-alive but nothing detects ZERO substrates alive — the machine's actual
state today).

**Q2 (WARN-only checks, trust erosion):** WARN-first was the right call — the evidence file's
own reasoning ("shipping it RED would have made the doctor permanently red and trained everyone
to ignore it") is sound and matches the observe-first testing strategy. The defect is that BOTH
flip conditions exist only as prose: "WARN for 1 calibration week, then RED" has no recorded
week-start and no mechanism that flips it; the budget check's flip is "Stage 2" with no marker.
Constitution §1: no mechanism = say there is no mechanism; §10 demands a retirement condition
per gate. A WARN that fires on 100% of runs on 100% of machines for an unbounded period is
wallpaper — the exact "mandatory writes, voluntary reads" channel the brief indicts (1,193
unacked alerts). Additionally the cadence WARN's own prescribed remedy does not clear it (F7).

**Q3 (verdict cache, the highest-risk item):** the concern is confirmed. The fingerprint
(`_doctor_compute_fingerprint`, harness-doctor.sh:296–321) covers exactly: live `settings.json`
mtime, template mtime, `manifest.json` mtime, `schedule-manifest.json` mtime, repo HEAD. Changes
that do NOT invalidate the cache and therefore serve a stale-but-plausible verdict for up to 30
min: **(a) any hand-edit or drift in the live `~/.claude/hooks/*.sh` mirror** — the
claimed-vs-actual drift surface that is the doctor's core reason to exist; **(b) any uncommitted
working-tree edit to repo files beyond the two config files** (HEAD unchanged — including
`harness-doctor.sh` itself); (c) local settings overlays if any check reads them. State-drift
waiting out the TTL is the operator-sanctioned D5 trade. But D5's stated contract —
"config/wiring changes bust the cache immediately via derived fingerprints" — is only true for
4 files; the code honestly says "first-approximation," the D5 decision text does not (F5).
Worse than the blind spots is the two-writer composition on the same cache file (F2): the
digest's refresher can overwrite the fingerprinted entry with a fingerprint-less,
freshly-timestamped copy of a stale verdict (staleness laundering — a wrong GREEN outliving the
TTL), or — when the doctor's sf_guard skips — with the literal string
`verdict unavailable (exit 0)`.

**Q4 (SF_DISABLE=1 self-test amendments):** legitimate, and unusually well done — the behavior
change is declared in the runbook ("A real, deliberate behavior change",
single-flight-halt-runbook.md:53–62), both amended scenarios carry comments naming exactly what
they now isolate, and the NEW contract got dedicated scenarios (doctor 9b/9c, digest S22). Not a
masked regression **in those two files**. Two residues: the scenario names
(`9-ssf-explicit-invocation-never-suppressed`, digest S20c's label) now assert a property that
is false at system level — true only of the old mechanism in isolation (F10); and the SAME
SF_DISABLE=1 pattern in `nl-maintenance.sh`'s S11 daemon scenario DOES mask a real Critical
regression (F1) — the daemon self-test never exercises the guard the daemon actually runs under.

**Q5 (retire-before-extend):** the retirement half is real: 5 legacy tasks Disabled (confirmed
against live Task Scheduler in the evidence file), rollback documented and implemented
(`-Rollback`), the +30-day deletion owned by plan Task 6, and
`check_maintenance_both_substrates_alive` REDs the stall-at-stage-2 trap. What is NOT tracked
by any mechanism is the **install** half: the replacement task was never registered, health-tick
(the hourly doctor-cache refresher) is among the disabled, and no doctor check fires on "zero
maintenance substrates alive" — the both-substrates check returns silently when the activation
marker is absent (harness-doctor.sh:2462–2465). The estate is currently running with NO
recurring maintenance and only a soft digest "STALE cache" line as the signal. Retirement:
real. Replacement activation: deferred-and-FORGETTABLE (F4).

**Q6 (§10 evidence bar per new gate/check):**
- `single-flight-recursion-guard`: golden scenario YES (the 2026-08-02 resume storm, replayed as
  doctor 9b/9c + live nested-invocation demo); FP rate PARTIALLY modeled (the 120s-TTL
  over-reclaim under long runs — F3 — is an unmodeled wrong-ALLOW; explicit-rerun suppression is
  an accepted, documented FP class); retirement condition: none stated (defensible — it is the
  invariant, not a calibration gate).
- `schedule-manifest-cadence`: golden YES (live coord-sync C2); FP modeled (null-measured
  skipped) but one PROVEN future FP found (managed_by=nl-maintenance entries, F7);
  retirement/flip condition PROSE ONLY — **fails the §10 bar until mechanized**.
- `budget-bash-hooks`: golden YES (live 25-count); FP low (JSON parse, two-source); flip
  condition PROSE ONLY ("Stage 2") — **fails the §10 bar until mechanized**.
- `check_maintenance_both_substrates_alive`: golden named (platform pre-mortem stall trap); FP
  low (tolerate-absent early returns); retirement YES (+30-day deletion closes it); but NO
  dedicated self-test scenario (evidence Known gap #2) and its inverse (zero substrates) is
  unchecked (F4).
- doctor verdict cache: golden YES (C3, measured 9m12s→1.557s); bypass ledgered (invariant 7);
  fingerprint honesty gap vs D5 (F5); no retirement condition needed (it IS the D5 contract).
- gate retrofits: not new gates — no new evidence bar owed; block semantics unchanged, proven by
  baseline-identical suites.

**Q7 (sensor lib with zero call sites):** shipping the lib ahead of call sites is acceptable
staging — self-tested, its no-call-sites state loudly documented in three places, a named
builder wiring it now. What converts it from staged rollout into writer-without-consumer is F6:
the consumer that already shipped (`nl-maintenance.sh` dashboard) reads a DIFFERENT file with a
DIFFERENT schema than the writer writes. If the in-flight wiring lands against `ws_record`
as-is, the friction pane stays empty forever and no test catches it (the pane's self-test uses
its own fixture ledger). The plan's Task-2 integration point — "schema agreed in this task's
evidence file so task 3 consumes it without rework" — was not executed. Fix the schema/path
agreement BEFORE the call-site builder finishes.

---

## Findings (class-aware, sorted Critical → Major → Minor)

```
- Line(s): adapters/claude-code/scripts/nl-maintenance.sh:488-528 (run_daemon/run_tick), 537-581 (run_watchdog); adapters/claude-code/hooks/lib/single-flight-lib.sh:219-253 (recursion guard, no release API); adapters/claude-code/scripts/install-maintenance-task.ps1:57,190-206 (watchdog every 300s)
  Severity: Critical  [F1]
  Confidence: PROVEN (code trace: pass 1 of run_daemon's loop exports _SF_ACTIVE_nl_maintenance_tick=1 inside the daemon process; every subsequent run_tick in the SAME process hits the recursion branch at single-flight-lib.sh:221-225 and skips — the lib has no sf_release and nothing unsets the var; a skipped tick writes NO heartbeat, since the heartbeat is only written inside _nm_tick_body, so the heartbeat permanently stales at ~300s; run_watchdog relaunches a NEW daemon WITHOUT killing the old one — daemon.pid is written but never read, no kill anywhere; schtasks fires --watchdog every 300s)
  Defect: The daemon ticks exactly ONCE per process lifetime, then wedges on its own recursion guard; the watchdog then spawns a new daemon roughly every stale-heartbeat interval while old daemons loop sleep-20 forever — unbounded accumulation of resident bash processes, each paying a sleep-spawn every 20s on the platform where spawns cost 132-190ms. This re-creates the 2026-08-02 self-DoS class inside its own fix. The self-test never sees it because S11 runs --daemon under SF_DISABLE=1 (nl-maintenance.sh:790-791), and the header claim "writing a heartbeat file every pass" (lines 40-44) is false on skipped passes.
  Class: run-to-exit guard reused inside a long-lived loop (guard semantics assume process exit clears state)
  Sweep query: rg -ln "sf_guard" adapters/claude-code   # then per caller, ask: is the call site inside a loop or a function invoked repeatedly in one process? (today: only nl-maintenance.sh run_tick-from-run_daemon)
  Required fix: BEFORE any live install: (a) have run_daemon clear the tick recursion var + release/refresh the lock each pass (add sf_release to the lib), or drop --daemon entirely and let the OS task run --tick directly (IgnoreNew + completion-anchored last_completed marks already give the overlap guarantees); (b) make run_watchdog kill the pid in daemon.pid before relaunching; (c) re-run S11 WITHOUT SF_DISABLE and assert two-or-more real ticks occurred.
  Required generalization: single-flight-lib.sh header must state the run-to-exit assumption and offer sf_release; every future sf_guard call site inside a resident loop is a defect the lib docs name.
```

```
- Line(s): adapters/claude-code/hooks/harness-doctor.sh:7363-7367 (sf_guard skip -> exit 0, before any verdict); adapters/claude-code/hooks/session-start-digest.sh:521-538 (refresh_doctor_cache: greps GREEN/FAILED, writes ts+verdict_line+exit_code with NO fingerprint/ts_epoch, ts=now); harness-doctor.sh:7411-7431 (reader trusts fingerprinted entries only)
  Severity: Critical  [F2]
  Confidence: PROVEN (code trace of both writers + the reader; trigger requires only refresh_doctor_cache running within 120s of any other doctor --quick, or within the 30-min TTL of a fingerprinted entry — both routine once the health-tick / doctor-verdict-refresh jobs activate)
  Defect: Two writers with incompatible schemas share one cache file, composing three failure modes on the harness arbiter of truth: (1) doctor sf-skip yields no verdict line, so the digest refresher OVERWRITES a valid fingerprinted entry with verdict_line="[doctor] verdict unavailable (exit 0)", exit_code 0 — served to every SessionStart digest; (2) on a cache HIT, the refresher re-stamps the CACHED verdict with ts=now, laundering its age past feed_doctor staleness checks and extending a wrong-GREEN window beyond the TTL; (3) every digest-side write strips the fingerprint, silently destroying the measured sub-2s fast path until the next direct recompute.
  Class: multi-writer shared cache without a schema contract + skip-exit-code indistinguishable from success
  Sweep query: rg -n "doctor-cache.json|DOCTOR_CACHE_PATH" adapters/claude-code   # every writer/reader of the shared cache; verify each writes/validates the same field set
  Required fix: (a) on sf_guard skip, doctor should serve the existing cached verdict (honest + fast) or exit a DISTINCT code with a machine-parseable skip line — never a bare exit 0; (b) refresh_doctor_cache must either write the full fingerprinted schema or refuse to overwrite when it captured no verdict line; (c) the refresher (whose whole job is a real recompute) should invoke doctor with DOCTOR_VERDICT_CACHE_DISABLE=1 and SF_DISABLE=1.
  Required generalization: any cache with more than one writer gets a written schema contract and a self-test that runs BOTH writers against one file; sweep other shared-state files with plural writers (workstreams state, coord snapshots).
```

```
- Line(s): adapters/claude-code/hooks/harness-doctor.sh:7364 (sf_guard "doctor-quick" 120); adapters/claude-code/hooks/lib/single-flight-lib.sh:183-192 (_sf_is_stale: age >= ttl -> reclaim, no pid-liveness check); docs/plans/harness-execution-redesign-2026-08-evidence.md:186-196 (cold run = 9m12s measured)
  Severity: Major  [F3]
  Confidence: PROVEN (the lib reclaims a lock whose owner stamp is older than 120s; the doctor's own measured cold cycle is 552s; therefore from t+120s of any cold run, every concurrent invocation reclaims the lock and runs concurrently)
  Defect: The single-flight TTL (120s) is ~4.6x SHORTER than the guarded work's measured cycle (9m12s cold), so the guard lapses mid-run — concurrent doctors are again possible exactly when the estate is degraded and runs are longest. This is the brief's own C2 pathology (cadence < cycle) reproduced inside the mechanism built to kill it; the near-simultaneous resume-storm golden case IS caught, but a storm spread over more than 2 minutes is not.
  Class: guard TTL not sized to the guarded work's measured cycle (invariant 2, applied to locks)
  Sweep query: rg -n "sf_guard .* [0-9]+|ss_singleflight .* [0-9]+" adapters/claude-code   # compare each TTL against that entry point's measured worst-case runtime
  Required fix: raise doctor-quick TTL to at least 2x measured cold cycle (e.g. 1200s), or better: have _sf_is_stale check owner-pid liveness (kill -0) before reclaiming, falling back to TTL only when the pid is gone.
  Required generalization: every sf_guard TTL must be justified against a measured cycle time in a comment — the schedule-manifest discipline applied to the lib's own locks.
```

```
- Line(s): adapters/claude-code/hooks/harness-doctor.sh:2457-2500 (check_maintenance_both_substrates_alive: silent return when activation marker absent); docs/plans/harness-execution-redesign-2026-08-evidence.md Known gap #4 (installer never run live) + lines 169-176 (all 5 legacy tasks Disabled)
  Severity: Major  [F4]
  Confidence: PROVEN (current machine state: 5 legacy tasks Disabled since Stage 0, NL-Maintenance never registered, health-tick — the hourly doctor-cache refresher — among the disabled; the only substrate-state doctor check exits silently in precisely this configuration)
  Defect: Invariant 9's check covers "both substrates alive" but not its inverse — ZERO substrates alive, which is the estate's actual state today: no coord-sync, no supervisor-tick, no heartbeat sweep, no session-resumer, no hourly doctor-cache refresh, indefinitely, with the doctor GREEN-capable throughout. The retirement half of retire-before-extend is mechanized; ACTIVATION of the replacement is tracked by nothing but a handoff file and an unchecked plan task.
  Class: migration invariant checked in one direction only (both-alive RED, none-alive silent)
  Sweep query: rg -n "activation-marker|both_substrates" adapters/claude-code
  Required fix: add a doctor WARN (RED after N days) when schedule-manifest declares managed_by=nl-maintenance mechanisms, all legacy_task_name tasks are Disabled, AND no fresh nl-maintenance heartbeat/activation marker exists; separately surface "register NL-Maintenance" as an explicit operator action item (blocked today on F1/F2).
  Required generalization: every disable-then-replace migration ships BOTH direction checks (both-alive AND none-alive) in the same commit that disables the old substrate.
```

```
- Line(s): adapters/claude-code/hooks/harness-doctor.sh:296-321 (_doctor_compute_fingerprint: 4 file mtimes + repo HEAD); docs/designs/harness-execution-redesign-considerations-2026-08-02.md:193 (D5: "config/wiring changes bust the cache immediately")
  Severity: Major  [F5]
  Confidence: PROVEN for the coverage gap (the fingerprint input list is literal in the code); HYPOTHESIZED for operator impact (refuted if the operator reads the code comment rather than the D5 contract)
  Defect: The fingerprint does not cover the live hooks mirror (~/.claude/hooks/*.sh — the doctor's primary claimed-vs-actual drift surface) nor uncommitted working-tree edits to repo files beyond the two config files, so exactly the "wiring changes" D5 promises will "bust the cache immediately" instead serve a stale verdict for up to 30 min. The code self-describes as first-approximation; the operator-facing D5 contract does not carry that caveat.
  Class: cache-freshness contract stated broader than the fingerprint's actual input coverage
  Sweep query: rg -n "fingerprint|declared.inputs|invariant 8" adapters/claude-code docs/designs
  Required fix: add a cheap live-hooks-dir freshness input (newest-mtime scan of ~/.claude/hooks — pennies vs a 9-minute recompute) and a working-tree-dirty bit (git diff --quiet rc) to the fingerprint; amend the D5 text (or the plan Behavioral Contracts) to state the covered input classes explicitly.
  Required generalization: invariant 8's own rule — a check with no declared inputs REDs — must eventually apply to the fingerprint itself; keep the per-check declared-inputs follow-up on the plan, not just in a comment.
```

```
- Line(s): adapters/claude-code/hooks/lib/workaround-sensor-lib.sh:150 (writes ~/.claude/state/workaround-sensor.jsonl, schema bypass_kind/command_fingerprint); adapters/claude-code/scripts/nl-maintenance.sh:392-403 (reads ~/.claude/state/gate-friction/ledger.jsonl, schema event block/workaround); adapters/claude-code/hooks/lib/single-flight-lib.sh:162-166 (skip telemetry goes to a THIRD ledger, signal-ledger)
  Severity: Major  [F6]
  Confidence: PROVEN (three literal paths/schemas in the three files; zero call sites of gc_escape_used outside its self-test, verified by grep)
  Defect: The gate-friction telemetry pipeline shipped as a writer and a consumer that point past each other: when the in-flight builder wires gc_escape_used into the five gates, rows land in workaround-sensor.jsonl while the dashboard pane reads gate-friction/ledger.jsonl forever-empty — and nothing writes the "block" events the friction metric (blocks/day x workaround-rate) needs at all. The plan's own integration point ("schema agreed ... so task 3 consumes it without rework") was skipped; both builds documented the gap honestly but nobody owns the join.
  Class: writer/consumer pair shipped in parallel without executing the declared schema-agreement step
  Sweep query: rg -n "workaround-sensor.jsonl|gate-friction/ledger.jsonl|NL_MAINT_FRICTION_LEDGER" adapters/claude-code neural-lace/workstreams-ui
  Required fix: BEFORE the call-site wiring lands: pick one file+schema (simplest: point the NL_MAINT_FRICTION_LEDGER default at workaround-sensor.jsonl and map bypass_kind rows to "workaround" in the pane jq; add the block-event writer decision to Task 2 remaining scope), and add one end-to-end test: gc_escape_used -> dashboard row.
  Required generalization: an integration point named in a plan task is a wire check, not prose — task-verifier should refuse the producing AND consuming tasks until a shared fixture round-trips.
```

```
- Line(s): adapters/claude-code/hooks/harness-doctor.sh:2370 (cadence WARN text), 2317 ("WARN for 1 calibration week, then RED -- the RED flip is explicitly a LATER task"), 2440 (budget WARN, "Stage 2 ... is the actual fix"); adapters/claude-code/config/schedule-manifest.json:5 ("mode":"warn")
  Severity: Major  [F7]
  Confidence: PROVEN for the missing mechanism (no date/marker/task encodes either flip; the budget WARN fires twice per run — live + template — on every machine today); HYPOTHESIZED for the erosion rate (refuted if the operator demonstrably keeps reading doctor WARNs after a month of both lines on every run)
  Defect: Both new WARN checks promise a future behavior flip ("1 calibration week, then RED"; "Stage 2 is the actual fix") with no mechanism that triggers it — constitution paragraph-1's exact prohibited shape — and paragraph-10's per-gate retirement condition is unmet for both. A WARN firing on 100% of runs indefinitely is the proven ignored-channel class. Bonus PROVEN false positive: the cadence WARN's own prescribed remedy ("move it to completion-anchored scheduling") does not clear the WARN, because the check never reads managed_by (harness-doctor.sh:2342-2364) — post-Stage-1 coord-sync would warn forever with its remedy already implemented.
  Class: observe-first gate without a mechanized flip/retirement condition
  Sweep query: rg -n "WARN-only|calibration week|not yet RED|WARN at this stage" adapters/claude-code/hooks
  Required fix: put the flip in data the checks read: cadence_check gains warn_since/red_after dates in schedule-manifest.json (doctor flips on date); cadence check skips (or annotates as satisfied-by-construction) managed_by=nl-maintenance entries once the activation marker exists; the budget check WARN names its flip condition and the manifest records it.
  Required generalization: every observe-first check ships its flip condition as machine-readable data in the same commit — "WARN now, RED later" without a stored date is the same class paragraph-10 bans for enforcement claims.
```

```
- Line(s): adapters/claude-code/hooks/harness-doctor.sh:7363-7366 (skip -> exit 0); adapters/claude-code/hooks/lib/single-flight-lib.sh:211-217 (HALT checked first); adapters/claude-code/doctrine/single-flight-halt-runbook.md:80-82 ("doctor ... get the same check for free")
  Severity: Major  [F8]
  Confidence: PROVEN (exit 0 on both skip reasons precedes any verdict output; CLAUDE.md designates doctor GREEN as the truth report and its exit code as the contract)
  Defect: Both the single-flight skip and the HALT drain make the arbiter exit 0 with no verdict — indistinguishable from GREEN to every exit-code consumer — and during a HALT (an emergency, exactly when the operator diagnoses) the diagnostic tool is silently unavailable. F2 is the first proven consumer casualty; any future scripted "doctor --quick && proceed" is the next.
  Class: skip/drain exit code aliased to the success code on a truth-reporting tool
  Sweep query: rg -n "harness-doctor.sh --quick" adapters/claude-code neural-lace   # every exit-code consumer of the arbiter
  Required fix: on sf-skip, serve the cached verdict when one exists (honest AND fast — the cache makes the skip largely redundant); otherwise exit a distinct documented code (e.g. 3) with a parseable "[doctor] SKIPPED (reason)" line; consider exempting explicit diagnostic invocations from HALT (HALT's charter is the maintenance layer, not diagnosis).
  Required generalization: any guard-skip path in a script whose exit code carries meaning must emit a distinguishable code/line — audit the other four sf_guard entry points' callers.
```

```
- Line(s): adapters/claude-code/manifest.json (Stage-1 entries absent — verified by grep: no nl-maintenance/verdict-cache/both-substrates ids); docs/handoffs/2026-08-02-stage1-pending-integration.md (carries the six entries as prose)
  Severity: Major  [F9]
  Confidence: PROVEN (grep over manifest.json; commit e5432f3c's own message defers the deltas)
  Defect: Stage-1 mechanisms (including the verdict cache on the arbiter itself) are merged to master — the durability boundary session-start-auto-install syncs live to every machine — while the enforcement inventory (manifest.json, "verified by harness-doctor.sh") has no entries for them. Between merge and the orchestrator integration commit, claimed-vs-actual is structurally out of sync; the only tracking is a handoff file plus an unchecked plan task.
  Class: builder-locked shared-file deferral leaving master in an inventory gap
  Sweep query: rg -n "pending-integration|orchestrator applies|builder-locked" docs/handoffs docs/plans
  Required fix: land the Stage-1 manifest.json + harness-dev.md integration commit immediately (fully drafted in the handoff); until then the doctor cannot verify what master already ships.
  Required generalization: when dispatch constraints defer shared-file deltas, the integration commit lands in the SAME merge train as the code commit — a handoff file is a record, not a mechanism.
```

```
- Line(s): adapters/claude-code/hooks/harness-doctor.sh:7069 (scenario name "9-ssf-explicit-invocation-never-suppressed"); adapters/claude-code/hooks/session-start-digest.sh:2443-2464 (S20c label)
  Severity: Minor  [F10]
  Confidence: PROVEN (read both scenarios; the named property is now false at system level — sf_guard deliberately suppresses explicit reruns — and true only of ss_singleflight in isolation under SF_DISABLE=1)
  Defect: The amended scenarios' names still assert "explicit invocation never suppressed," which a future reader can cite as a system guarantee that no longer holds.
  Class: test name asserting a retired system-level contract after scope-narrowing
  Sweep query: rg -n "never-suppressed|never_suppressed" adapters/claude-code/hooks
  Required fix: rename to ...-never-suppressed-BY-SSF (and the S20c label likewise) so the narrowed scope is in the name, not only the comment.
  Required generalization: when a test is scope-narrowed to an old mechanism's isolated contract, rename it in the same edit that adds the isolation flag.
```

```
- Line(s): adapters/claude-code/scripts/nl-maintenance.sh:493 (sf_guard under scoped SF_STATE_DIR), 562 (watchdog same), 465 (tick body checks HALT at the DEFAULT path); adapters/claude-code/doctrine/single-flight-halt-runbook.md:69 (one-gesture writes the default path)
  Severity: Minor  [F11]
  Confidence: PROVEN (three literal paths; behavior survives today only because _nm_tick_body's unscoped check runs after the scoped guard)
  Defect: The HALT flag is machine-global by definition, but sf_guard consults it at whatever SF_STATE_DIR the call site scoped — the nl-maintenance tick/watchdog guards check a private path where the operator's one-gesture HALT never lands; drain works only via the tick body's second, unscoped check.
  Class: global kill-switch resolved through a scopable state-dir override
  Sweep query: rg -n "SF_STATE_DIR=" adapters/claude-code
  Required fix: split the paths in the lib — locks under SF_STATE_DIR, HALT always at one canonical location (an SF_HALT_DIR defaulting to ~/.claude/state/single-flight) regardless of lock scoping; self-tests override SF_HALT_DIR explicitly.
  Required generalization: emergency-stop flags get exactly one canonical location; never co-locate them with per-caller-scopable state.
```

```
- Line(s): docs/plans/harness-execution-redesign-2026-08.md:568 (inventory target "scheduled tasks <= 2/machine"); adapters/claude-code/config/schedule-manifest.json (downstream monitor stays standalone; NL-LimitResume untouched by design)
  Severity: Minor  [F12]
  Confidence: PROVEN for the arithmetic (NL-Maintenance + downstream-product-health-monitor + NL-LimitResume = 3 enabled recurring tasks post-activation); HYPOTHESIZED that the closure gate would miscount (refuted if Stage 4 counts all three honestly)
  Defect: The "6 -> 1" headline undercounts the machine's post-migration recurring-task census: the honest number is 3 (one consolidation anchor + two deliberate exclusions), above the plan's own <= 2 target.
  Class: inventory metric scoped to the consolidated subset rather than the machine census
  Sweep query: rg -n "scheduled tasks|target_max" docs/plans/harness-execution-redesign-2026-08.md adapters/claude-code/config/schedule-manifest.json
  Required fix: amend the target to name the exclusions, or fold NL-LimitResume/downstream-monitor accounting into the dashboard legacy_scheduled_tasks pane so the Stage 4 count is the census, not the subset.
  Required generalization: R3.3 inventory counts are measured over the machine, not over the set the plan chose to consolidate.
```

---

## What is genuinely good (so the fixes do not regress it)

- The five-gate retrofit discipline: one emitter, baseline-identical self-tests, `--check`
  sharing the enforce decision site, NL-FINDING-016 trap kept, NL-FINDING-019 remedy kept,
  measured early-exit wins (0.551s to 0.176s). The scope-gate thin dispatcher documents its one
  accepted residual (obfuscated `commit`) instead of hiding it.
- `context-watermark.sh` (ed32a7b4) is the model constitution-§10 fix: golden case, root
  principle, negative self-test assertion, no new surface.
- Honesty hygiene throughout: the evidence file names what was NOT proven (resume spawn count,
  live installs, fingerprint approximation, friction schema not agreed); the plan-edit-validator
  builder narrowed scope rather than touch an unwaivable path; the 9m12s cold-doctor number was
  reported as an adverse open finding rather than buried.
- The WARN-first posture itself (both new checks) is correctly argued; only the flip mechanism
  is missing.

## Summary for the author

The Stage-0 invariant work and the gate retrofits are substantively sound and can stand with the
named conditions. The batch's two Criticals live in Stage 1's not-yet-activated path and MUST be
fixed before `install-maintenance-task.ps1` is run on any machine: (F1) the daemon wedges on its
own recursion guard after one tick and the watchdog then accumulates resident daemons without
bound — the self-DoS class reborn, masked by an SF_DISABLE=1 self-test; (F2) the doctor's
skip-exit-0 plus the digest's schema-less cache writes corrupt and stale-launder the verdict
cache on the arbiter of truth. The single most important structural lesson across the batch:
the guards were sized and tested against the incident's snapshot (near-simultaneous storm, fast
checks) rather than against the degraded regime the brief itself says maintenance runs hottest
in (120s TTL vs 9m cycle; WARN checks with no flip; zero-substrate interim with no alarm).
Fix F1/F2/F6 before the in-flight builders land their halves; mechanize the F7 flips; then
Stage 1 can be activated and this review's conditions closed.

---

# Fix status (maintained per review-finding-fix-gate; plan: docs/plans/gated-pipeline-master-2026-08.md)

| Finding | Status |
|---|---|
| F1 (Critical, daemon wedge) | **FIXED** @ 6f5d1b22 (merged dc9f2299); re-reviewed PASS in docs/reviews/2026-08-03-gated-pipeline-t3-t4-implementation-review.md |
| F2 (Critical, cache corruption) | **FIXED** @ d46beee5 (merged ec349c3f), single-writer form; re-reviewed PASS (same record) |
| F3 (TTL vs cycle) | OPEN — gated-pipeline T7 (in flight) |
| F4 (zero-substrate silent) | **FIXED** @ 422257c2 (inverse check, dates-in-data; live-probed firing) |
| F5 (fingerprint coverage) | **FIXED** @ d46beee5 (live-hooks mtime + unstaged-dirty bit; staged-edit residual named in the implementation review) |
| F6 (friction writer/consumer) | **FIXED** @ be5e4273 (T5; one file+schema, end-to-end proven) |
| F7 (prose-only WARN flips) | OPEN — gated-pipeline T7 |
| F8 (skip exit-0 aliased) | **FIXED** @ d46beee5 for the sf_guard doctor-quick site (serves-cache-or-exit-3); two non-sf_guard bare-exit-0 paths remain as a filed follow-up (accepted scoping per the implementation review note 3) |
| F9 (Stage-1 manifest entries absent) | **FIXED** @ c3dae56c (review-chain/dispatch-chain entries) + 422257c2 (nl-maintenance-core, doctor-verdict-cache, maintenance-both-substrates-alive) |
| F10 (test-name rename) | OPEN — gated-pipeline T7 (7d) |
| F11 (HALT canonical path) | OPEN — gated-pipeline T7 (7c) |
| F12 (census undercount) | OPEN — gated-pipeline T22 (counting method specified) |

(Predecessor plan archived 2026-08-03 under docs/plans/archive/ — the F1-F12 fix-status above is the authoritative disposition; carry-forwards registered in docs/backlog.md.)
