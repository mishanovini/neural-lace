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
