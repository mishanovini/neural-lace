# Plan: THE GATED PIPELINE — master build (Phase A criticals + Phase B pipeline + Phase C debts)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal plan — the user is the maintainer; self-tests plus the REQ-B8 three-variant blocked-dispatch demonstration are the deliverable outcome (constitution §4 harness clause).
tier: 4
rung: 5
architecture: hybrid
<!-- hybrid: coding-harness (gates, libs, agents, templates) + orchestration (dispatch-time gating, dispatch ledger, orchestrator-pattern doctrine step). -->
frozen: true
lifecycle-schema: v2
loe-class: harness-mechanism
owner: misha
target-completion-date: 2026-08-10
prd-ref: n/a — harness-development
ask-id: none — no linked ask

design-ref: docs/designs/gated-pipeline-master-2026-08-03.md@53fd8f27bbc3fc83c19f0c1aa8021779ce0d7391
<!-- The design-ref: header field is introduced BY this plan (REQ-B5); carried here from birth,
     voluntarily, so the plan itself exercises the shape it builds. The anchor is the design r3
     BLOB sha (git hash-object), per the r3 chain format. -->

## Review Chain
<!-- Introduced by REQ-B5/B6; carried from birth. Validity semantics per design §4 (three rules)
     once Task 1's parser exists; all records below predate the dispatch ledger and are covered by
     rule 3's pre-ledger exemption (rules 1-2 apply in full). -->
authored-by: Fable main session 4a470c8c (design-author agent does not exist yet — created by Task 12; this plan's authoring provenance is the session itself, named honestly)
design-ref: docs/designs/gated-pipeline-master-2026-08-03.md@53fd8f27bbc3fc83c19f0c1aa8021779ce0d7391
design-reviews:
  - reviewer: harness-reviewer       verdict: PASS   record: docs/reviews/2026-08-03-gated-pipeline-design-harness-review.md  (r1 REFORMULATE → r2 delta REFORMULATE → r3 scoped confirmation PASS)
  - reviewer: architecture-reviewer  verdict: SOUND  record: docs/reviews/2026-08-03-gated-pipeline-design-architecture-review.md  (r1 SOUND-WITH-AMENDMENTS → r2 delta SOUND-WITH-AMENDMENTS → r3 scoped confirmation SOUND)
plan-reviews:
  - reviewer: harness-reviewer (role: plan-fidelity, bootstrap per design §8.1)  verdict: PASS  record: docs/reviews/2026-08-03-gated-pipeline-plan-fidelity-review.md  (REFORMULATE → F-1..F-5 fixed in a4176686 → amendment confirmation PASS)
  <!-- replaced by plan-fidelity-reviewer for all future plans once Task 13 lands; T16 re-reviews
       THIS plan with the real agent and re-anchors. -->

## Intended Functionality

**Outcome (operator's terms):** The operator no longer has to catch skipped reviews after the
fact: when any session tries to send builders at a plan whose reviews have not actually run, the
dispatch is refused on the spot with an instruction naming the exact missing review, and the
operator can switch the maintenance layer on without the machine re-entering the process-storm
state, because the three defects sitting in its activation path are fixed and independently
re-verified.

**Observation:** The operator (or anyone) runs the attempted-skip demo and watches the dispatch
get blocked; runs `nl-maintenance --tick` repeatedly and sees fresh heartbeats each pass with a
flat process count; opens the dashboard and sees the friction pane populated with real rows.

**Deterministic pass/fail:** (1) All three REQ-B8 demo variants produce a block or parse-failure,
captured as transcripts in the evidence file — zero variants pass through. (2) A 3-iteration
daemon run under the real single-flight guard writes ≥3 distinct heartbeat timestamps (was: 1).
(3) `bash adapters/claude-code/hooks/session-start-digest.sh` leaves `doctor-cache.json`
byte-identical except through the doctor's own writer (two-writer test asserts it). (4)
`gc_escape_used` test row appears in the dashboard's friction pane JSON. (5) Doctor quick-run
reports ≤9 REDs after Task 8. Any of the five failing = the plan is not done.

**Explicitly NOT included:** Stage-2 hook-stub consolidation (admission-triggered next cycle via
REQ-C6); WSL anything; new hardware; server-side branch protection (operator-only, S-34);
Workflow-internal spawn gating (documented residual); transcript-anchored review proof.

**Human dependencies:**
- Operator ratifies (or rejects) the resident-daemon shape before `NL-Maintenance` registration executes (DEC-4; prepared ask, non-blocking for every other task) — INTENDED
- Operator may override DEC-1 (two new agents), which decided open questions Q-01/Q-08 — INTENDED
- Server-side branch protection remains an operator-only step, tracked as a register entry — INTENDED

## Goal

Implement `docs/designs/gated-pipeline-master-2026-08-03.md` (r3 — reviewed to harness-reviewer
PASS + architecture-reviewer SOUND through three Fable-tier rounds):
fix the four open findings blocking maintenance activation (HR-F1 daemon wedge, HR-F2 cache
corruption, HR-F6 friction-ledger mismatch, HR-F9 manifest gap) plus the mechanized-flip debt
(HR-F3/F7/F10/F11), then build the gated pipeline — review-chain artifacts with hook-observed
trust roots, gates G1/G2/G3, the operator-directives register with three carriage channels, the
`design-author` and `plan-fidelity-reviewer` agents — then pay the sequencing debts (doctor
triage, estate drain, honest scorecard, Stage-2 admission trigger). Every task maps 1:1 onto the
design's REQ table; the design is the fidelity contract this plan is reviewed against.

## User-facing Outcome

n/a — harness-internal: the user is the maintainer. The maintainer-observable outcomes are the
five deterministic pass/fail items above, chief among them: an attempted review-skip is BLOCKED
live (D-15's acceptance bar), and maintenance activation no longer risks the storm class.

## Scope

- IN: every file listed in `## Files to Modify/Create`; the REQ-A/B/C tables of the design r2 in
  full; the predecessor plan's honest closure (REQ-A6); the estate reconcile (REQ-A0).
- OUT: everything in the design's NON-GOALS list (Stage-2 stubs, WSL, hardware, S-23 cut
  mechanisms, invariant-8 full machinery, JIT pre-warnings, S-24/25/26/27/28, Workflow-internal
  gating, transcript-anchored proof); product-repo changes of any kind; arming the orphan reaper
  before activation + ratification (DEC-9).

## Tasks

<!-- Dispatch batching: [parallel] tasks are file-disjoint per the Files map; everything else
     serial in task-ID order. Builders are forbidden from manifest.json and doctrine INDEX
     regeneration — the orchestrator integrates those serially at merge (established precedent).
     NAMED DEVIATION from the design's "manifest entry same-commit" letter (fidelity F-2): under
     the builder-locked model, each mechanism's manifest delta lands in the SAME MERGE TRAIN as
     its mechanism — integrated by the orchestrator before any push containing that mechanism,
     verified by manifest-check before push. Never deferred past the push boundary (the HR-F9
     class lives exactly there). -->

- [x] 1. Walking skeleton: `hooks/lib/review-chain-lib.sh` v1 — the three validity rules per
  design r3 §4 (record parse incl. the record's own `**Reviewed:** <path> @ <blob>` attestation;
  THREE-WAY anchor match chain==record-attested==HEAD, plan-blob canonicalization +
  `inflight-blob:` WARN hash; dispatch-ledger cross-check with artifact-ref match + pre-ledger
  exemption keyed on the ledger-landing date in the lib config) + the full r3 fixture set
  (honest-derived record FAILS; never-dispatched reviewer FAILS rule 3; author-re-anchored chain
  without fresh record FAILS rule 2; wrong-artifact-ref row FAILS rule 3; pre-ledger-dated record
  PASSES rules 1-2 exempt from 3; stale anchor FAILS-post-calibration; inflight change = ledgered
  WARN, passes; valid chain PASSES) + a `--check`-only skeleton of the G2 gate
  (`hooks/dispatch-chain-gate.sh --check <fixture-plan>`) proving lib→gate end-to-end. TWO
  BINDING implementation constraints (arch r3 confirmation): (i) a plan record's attested blob is
  the CANONICALIZED plan blob (file minus chain + In-flight sections) — the lib computes both
  comparison sides identically; (ii) the pre-ledger exemption keys on the record file's
  first-commit time (`git log --follow --format=%ct | tail -1`), never a self-declared header
  date — Verification: full — Implements: REQ-B6 (core), REQ-B8 (skeleton) — Docs impact: lib
  header contract + manifest entry (orchestrator-integrated)
    **Prove it works:**
    1. Run `bash adapters/claude-code/hooks/lib/review-chain-lib.sh --self-test` → all fixture verdicts as specified (derived FAILS, ghost-reviewer FAILS, stale-anchor FAILS, valid PASSES)
    2. Run `bash adapters/claude-code/hooks/dispatch-chain-gate.sh --check tests/fixtures/chainless-plan.md` → exit nonzero with a {WHAT/WHY/FIX/ESCAPE} block naming the missing review
    3. Run the same `--check` against the valid-chain fixture → exit 0
    **Wire checks:**
    - `adapters/claude-code/hooks/dispatch-chain-gate.sh` sources `adapters/claude-code/hooks/lib/review-chain-lib.sh` → `rc_validate_chain`
    - `adapters/claude-code/hooks/lib/review-chain-lib.sh` `rc_validate_chain` → reads `## Review Chain` + `## Verdict:` + `Reviewer:` tokens from record fixtures
    - `adapters/claude-code/hooks/dispatch-chain-gate.sh` block path → `gc_block` from `adapters/claude-code/hooks/lib/gate-contract-lib.sh`
    **Integration points:**
    - `gate-contract-lib.sh` (exists, Stage 0b) — message emission; verify via the --check output containing the four contract fields
    - dispatch-ledger fixture format must match what Task 15 writes — the fixture schema line is quoted in both files (shared fixture round-trip)
- [x] 2. [parallel] Estate reconcile: stash `docs/backlog.md` churn; merge `origin/master` (the two
  duplicate-content review commits) into local master via merge commit; push both mirrors; verify
  `git rev-list --left-right --count` = 0/0 against both — Verification: mechanical — Implements:
  REQ-A0 — Docs impact: none — git-state operation, no doc surface
- [x] 3. [parallel] HR-F1 fix: `sf_release` API in `single-flight-lib.sh` (+ header run-to-exit
  statement); `run_daemon` releases per pass; `run_watchdog` reads `daemon.pid`, verifies the
  target cmdline contains `nl-maintenance` + `--daemon` (identity mismatch ⇒ log-and-skip, never
  kill), kills verified-stale daemon before relaunch; S11 mask (`SF_DISABLE=1` at
  `nl-maintenance.sh:790-791`) DELETED; S11 asserts ≥2 real ticks under the real guard —
  Verification: full — Implements: REQ-A1 — Docs impact: single-flight-halt-runbook.md gains the
  sf_release contract + daemon-lifecycle paragraph
    **Prove it works:**
    1. Run `bash adapters/claude-code/scripts/nl-maintenance.sh --self-test` → S11 passes WITHOUT SF_DISABLE, asserting ≥2 heartbeat writes across 3 iterations
    2. Start a daemon (`--daemon --interval 0 --max-iterations 3` in a scoped state dir), confirm 3 heartbeat timestamps, confirm exactly one daemon process at any point
    3. Write a bogus `daemon.pid` naming this shell's PID; run `--watchdog`; confirm log-and-skip (this shell survives) and a new daemon launched
    **Wire checks:**
    - `adapters/claude-code/scripts/nl-maintenance.sh` `run_daemon` → `sf_release` in `adapters/claude-code/hooks/lib/single-flight-lib.sh`
    - `adapters/claude-code/scripts/nl-maintenance.sh` `run_watchdog` → reads `daemon.pid` via `_nm_pid_path`
    - `adapters/claude-code/scripts/nl-maintenance.sh` watchdog kill path → `/proc/` cmdline identity check before `kill`
    **Integration points:**
    - `install-maintenance-task.ps1` watchdog cadence (300s) unchanged — verify installer self-test still passes
    - Task 7 touches `single-flight-lib.sh` too (`_sf_is_stale` pid-liveness) — serialized after this task
- [x] 4. [parallel] HR-F2+F5+F8 fix, single-writer form: doctor sf-skip serves cached verdict when
  present else exits code 3 with `[doctor] SKIPPED (<reason>)`; `refresh_doctor_cache` becomes
  invoke-and-read-only (runs `--quick` with `SF_DISABLE=1 DOCTOR_VERDICT_CACHE_DISABLE=1` — the
  proactive-recompute semantics, per the harness delta; NEVER writes the cache file);
  fingerprint gains live-hooks newest-mtime + `git diff --quiet` dirty bit; new self-test scenario
  runs digest-then-doctor against one cache file asserting the single-writer property —
  Verification: full — Implements: REQ-A2 — Docs impact: none — behavior change is inside the two
  scripts' own header contracts, updated in place
    **Prove it works:**
    1. Prime the cache via `harness-doctor.sh --quick`; run it again within the sf TTL → cached verdict served, exit matches cached exit, cache file byte-identical
    2. Corrupt the guard state to force an sf-skip with an EMPTY cache → exit 3 + parseable SKIPPED line, cache file untouched
    3. Run the digest's `refresh_doctor_cache` → cache file's only mutation is the doctor's own 5-field record (fingerprint present, ts_epoch numeric)
    **Wire checks:**
    - `adapters/claude-code/hooks/harness-doctor.sh` sf-skip path → serves `_doctor_verdict_cache_path` content or `exit 3`
    - `adapters/claude-code/hooks/session-start-digest.sh` `refresh_doctor_cache` → invokes `harness-doctor.sh` `--quick`; contains NO `>` write to `doctor-cache.json`
    - `adapters/claude-code/hooks/harness-doctor.sh` `_doctor_compute_fingerprint` → includes `hooks` dir newest-mtime + `git diff --quiet` bit
    **Integration points:**
    - Every exit-code consumer of `--quick` (grep sweep in task) tolerates exit 3 as SKIPPED-not-GREEN — sweep + fix consumers in the same commit
    - Task 7's cadence-flip data lives in `schedule-manifest.json` — no file overlap, but the doctor check text changes land there; serialized after
- [x] 5. HR-F6 fix (after Task 3 — same file): `NL_MAINT_FRICTION_LEDGER` default →
  `~/.claude/state/workaround-sensor.jsonl`; pane jq maps `bypass_kind` rows → `workarounds`;
  block-event decision recorded in the task evidence (gc_block counter rows or explicit metric
  rename); end-to-end test `gc_escape_used` → pane row — Verification: full — Implements: REQ-A3
  — Docs impact: none — pane help text updated in place
    **Prove it works:**
    1. Fire `gc_escape_used testgate test-bypass` via a scoped-ledger test invocation
    2. Render the dashboard friction pane → the row appears with gate=testgate under `workarounds`
    3. Empty-ledger case → pane renders zero-counts, not an error
    **Wire checks:**
    - `adapters/claude-code/scripts/nl-maintenance.sh` `friction_path` default → `workaround-sensor.jsonl`
    - `adapters/claude-code/scripts/nl-maintenance.sh` pane jq → keys off `bypass_kind` from `adapters/claude-code/hooks/lib/workaround-sensor-lib.sh` `ws_record`
    **Integration points:**
    - The 4 live `gc_escape_used` call sites (concurrent-ownership-gate-body.sh:467,482,977; scope-enforcement-gate-body.sh:1901) — no change needed there; verify one fires into the pane end-to-end
- [ ] 6. HR-F9+F4 fix (orchestrator-integrated; after Tasks 3-5): manifest.json entries for
  nl-maintenance, doctor-verdict-cache, both-substrates-alive; zero-substrate WARN (RED after 14
  days, dates in `schedule-manifest.json` data); `manifest-check.sh --gen-index` regenerated —
  Verification: contract — Implements: REQ-A4 — Docs impact: doctrine/INDEX.md regenerated (generator)
- [ ] 7. Mechanized flips + targeted fixes (after Tasks 3,4,6 — shared files), decomposed per
  target — Verification: full — Implements: REQ-A5 — Docs impact:
  single-flight-halt-runbook.md HALT-path note; CPU methodology note in the perf research doc
  - 7a. `adapters/claude-code/config/schedule-manifest.json`: HR-F7 flip dates (`warn_since`/`red_after`) per WARN entry + budget-check flip date
  - 7b. `adapters/claude-code/hooks/harness-doctor.sh`: cadence check reads the dates; managed_by entries satisfied-by-construction post-activation
  - 7c. `adapters/claude-code/hooks/lib/single-flight-lib.sh`: HR-F3 `_sf_is_stale` owner-pid liveness (kill -0, TTL fallback); HR-F11 `SF_HALT_DIR` canonical split
  - 7d. `adapters/claude-code/hooks/harness-doctor.sh` + `adapters/claude-code/hooks/session-start-digest.sh`: doctor-quick TTL → 1200s + measured-cycle justification comment on EVERY sf_guard TTL call site; HR-F10 scenario labels → `…-never-suppressed-BY-SSF`
  - 7e. `docs/reviews/2026-07-31-wsl2-windows-performance-research.md`: INV-F10 CPU counter side-by-side validation vs Task Manager, documented
    **Prove it works:**
    1. Doctor + lib self-tests pass with renamed scenarios and pid-liveness branch covered (live-owner lock NOT reclaimed at TTL; dead-owner lock reclaimed)
    2. Set `red_after` to yesterday in a fixture manifest → cadence check REDs; to tomorrow → WARNs
    3. Write HALT to the canonical dir with a scoped `SF_STATE_DIR` lock elsewhere → tick drains
    **Wire checks:**
    - `adapters/claude-code/hooks/lib/single-flight-lib.sh` `_sf_is_stale` → `kill -0` liveness before TTL reclaim
    - `adapters/claude-code/hooks/harness-doctor.sh` cadence check → reads `warn_since`/`red_after` from `adapters/claude-code/config/schedule-manifest.json`
    - `adapters/claude-code/hooks/lib/single-flight-lib.sh` HALT check → `SF_HALT_DIR` canonical default
    **Integration points:**
    - Tasks 3/4 land first (same files); this task rebases on their result
    - The budget-bash-hooks WARN flip condition also gains a data date (same manifest edit)
- [ ] 8. [parallel] REQ-A8 doctor triage (A-parallel; independent of Tasks 3-7), decomposed per
  disposition stage — Verification: full — Implements: REQ-A8 — Docs impact: triage record
  appended to the entropy-triage review doc
  - 8a. Inventory: one full doctor run captured; a classification table (one row per RED check id → fix / retire / waiver) written to the triage record, seeded from `docs/reviews/2026-08-02-estate-entropy-triage.md` dispositions where they exist
  - 8b. Execute the fix class (each fix is one row's named remedy; committed per-file)
  - 8c. Retire class: each retired check removed with a retire-rationale row (never silently deleted)
  - 8d. Waiver class: waivers-with-reasons landed where the gate genuinely does not apply
  - 8e. Re-measure: full doctor run ≤9 REDs, each survivor named with its open disposition
    **Prove it works:**
    1. `harness-doctor.sh` full run before (71 red baseline recorded) and after → ≤9 REDs, each survivor named with its open disposition
    2. No check DELETED without a retire-rationale line in the triage record
    **Wire checks:**
    - n/a — this task's product is doctor-state + a triage record, not a new code chain (justification ≥30 chars: the work is classification and disposition of existing checks, no new wiring is created)
    **Integration points:**
    - Done-bar rule (design REQ-A8): until this lands, Tasks 1-7 use targeted self-tests as done-bars, never global doctor state
- [ ] 9. REQ-A6 predecessor closure (after Task 8): task-verifier on
  `harness-execution-redesign-2026-08.md` T1/T2/T3 evidence; flip checkboxes where PASS; flip plan
  → `Status: SUPERSEDED` with pointer to this plan; verify plan-lifecycle archives it —
  Verification: mechanical — Implements: REQ-A6 — Docs impact: SCRATCHPAD pointer line
- [ ] 10. REQ-A7 registration prep: installer + `-Rollback` self-tested end-to-end on this machine
  (register→verify→rollback→verify-gone, under a test task name); DEC-4 ratification ask surfaced
  via `needs-you.sh` with the §3 compact block — PRECONDITION (fidelity F-3, hard-stop letter):
  the ask is surfaced only after the T3 and T4 review-record SHAs exist and are cited inside the
  ask block (the "fixed AND re-reviewed" bar); registration itself executes ONLY on operator YES
  — Verification: contract — Implements: REQ-A7 — Docs impact: NEEDS-YOU.md entry (via generator)
- [ ] 11. REQ-B1+B4 register: `config/operator-directives.json` (canonical) + generator for
  `docs/operator-directives.md` view + `hooks/lib/directives-register-lib.sh` (ONE parser,
  round-trip fixture test) + seeding (nl-issues 153/154/158 + curated D-01…D-23, each intake entry
  `register_ref`'d) + ADR forward-guard WARN lint + same-commit `derive-cache.js:7-11` supersession
  sweep — Verification: full — Implements: REQ-B1, REQ-B4 — Docs impact: the generated register
  view IS the doc; nl-issue triage notes
    **Prove it works:**
    1. `directives-register-lib.sh --self-test` → round-trip fixture passes; glob surface-match returns the tagged entries for a fixture file list
    2. Generator produces the md view; re-running is idempotent (byte-identical)
    3. `derive-cache.js` header names OD-push-materialize as superseding the timer-refresh reading, same commit
    **Wire checks:**
    - `adapters/claude-code/hooks/lib/directives-register-lib.sh` → reads `adapters/claude-code/config/operator-directives.json`
    - `neural-lace/workstreams-ui/server/derive-cache.js` header → cites `OD-` id from the register
    - ADR lint → greps `docs/decisions/` for standing-rule language lacking `register_ref`
    **Integration points:**
    - Task 20 (dispatch-directives + JIT walk) consumes this lib — schema agreed HERE via the shared fixture (the HR-F6 lesson, executed)
- [ ] 12. [parallel] REQ-B2 `design-author` agent + `templates/design-template.md` (rationale-per-
  decision, non-goals, supersedes, machine-parsable REQ table, Directives-honored, Review Chain
  stub with authored-by; frontmatter `model: fable`) — Verification: contract — Implements: REQ-B2
  — Docs impact: model-policy.json agents block gains the entry (category design)
- [ ] 13. [parallel] REQ-B3 `plan-fidelity-reviewer` agent (frontmatter `model: fable`, category
  review; protocol per design §5; anti-rubber-stamp step; GOLDEN CASE fixture = the P-32
  push-directive drop replayed as a design+plan pair in the agent's eval block) — Verification:
  contract — Implements: REQ-B3 — Docs impact: model-policy.json entry (category review)
- [ ] 14. REQ-B5+B7 template + checks: plan-template gains `design-ref:` header + per-task
  `Implements:`/`Directives:` + Review Chain section; plan-reviewer Checks 20-22 (20: design-ref
  required-when-triggered + design-reviews valid incl. anchor-at-HEAD comparison; 21: every design
  MUST-REQ claimed by ≥1 task + Directives fields present; 22: chain records name
  agent+verdict+ledger-row) with G1 surface-trigger fire-rate measured over the plan corpus and
  recorded before any flip — Verification: full — Implements: REQ-B5, REQ-B7 — Docs impact:
  planning doctrine compact + full gain the fields
    **Prove it works:**
    1. `plan-reviewer.sh --self-test` → new scenarios: chain-less triggering plan FAILS 20; plan missing a MUST-REQ claim FAILS 21; derived-style record FAILS 22; this plan's own file PASSES all three
    2. Corpus measurement: surface-trigger fire-rate over docs/plans/ recorded in the evidence file with the number
    **Wire checks:**
    - `adapters/claude-code/hooks/plan-reviewer.sh` Check 20 → `rc_validate_chain` in `adapters/claude-code/hooks/lib/review-chain-lib.sh`
    - `adapters/claude-code/hooks/plan-reviewer.sh` Check 21 → parses `## Requirements` REQ table from the file named by `design-ref:`
    - `~/.claude/templates/plan-template.md` ← synced from `adapters/claude-code/templates/plan-template.md` (install path)
    **Integration points:**
    - Check 17 comment marked superseded (kept for keyword-triggering only) — same commit
    - Task 1's lib is the parser — no second implementation (M-3 rule)
- [ ] 15. REQ-B14 dispatch ledger (delta-D2 form): `workstreams-emit.sh` **`--on-builder-complete`
  PostToolUse path** appends `{subagent_type, model, ts, session_id, artifact_ref}` to
  `~/.claude/state/dispatch-ledger.jsonl` — completion-side so blocked/failed dispatches mint no
  row; `artifact_ref` from the existing prompt parse; ledger-landing date recorded in the lib
  config (the rule-3 pre-ledger exemption boundary); always-exit-0 preserved; quoted-header parse
  quirk fixed in the shared parse — Verification: full — Implements: REQ-B14 — Docs impact:
  orchestrator-pattern doctrine notes the ledger
    **Prove it works:**
    1. Self-test fixture completion event (subagent_type + prompt carrying a docs/ path) → exactly one well-formed JSONL row with artifact_ref populated
    2. Malformed event → no row, exit 0 (writer contract); a PreToolUse dispatch event → no row (completion-side only)
    3. `review-chain-lib.sh` rule-3 fixture validates against a row this writer produced (shared fixture round-trip), and REJECTS a row whose artifact_ref names a different file
    **Wire checks:**
    - `adapters/claude-code/hooks/workstreams-emit.sh` `--on-builder-complete` → appends to `dispatch-ledger.jsonl`
    - `adapters/claude-code/hooks/lib/review-chain-lib.sh` rule 3 → reads `dispatch-ledger.jsonl` rows by `subagent_type` + `artifact_ref` + `ts`
    **Integration points:**
    - Fixture schema is the SAME file Task 1 quoted — round-trip test binds them
    - Lands BEFORE Task 16 (bootstrap order per design r3) so the self-review is itself ledgered
- [ ] 16. REQ-B13 bootstrap self-review (after Tasks 13,14,15): dispatch `plan-fidelity-reviewer`
  on THIS plan against design r3; commit its record; append the plan-reviews chain entry with
  CANONICALIZED plan-blob anchor (re-anchoring the bootstrap record); only then is Task 17
  dispatchable — Verification: mechanical — Implements: REQ-B13 — Docs impact: the review record
  itself
- [ ] 17. REQ-B8 G2 gate live (after Task 16): `dispatch-chain-gate.sh` wired PreToolUse
  Task|Agent (subagent_type-keyed per design §4; grandfather list generated at install from extant
  plan slugs; gate-contract messages; `--check`; escape ledgered) + THE THREE-VARIANT DEMO with
  transcripts in the evidence file: (i) plan-phase-builder vs chain-less NEW fixture plan →
  BLOCKED; (ii) same with NO attribution line → BLOCKED; (iii) chain entry naming never-dispatched
  reviewer → fails validity. Gate ordering rule (fidelity F-4): the gate validates the CHAIN
  FIRST and applies the grandfather path only when no chain parses — a plan with an earned valid
  chain (this one, post-T16) never rides the WARN path — Verification: full — Implements: REQ-B8
  — Docs impact: manifest entry + orchestrator-pattern doctrine gains the gate step;
  settings.json.template wiring
    **Prove it works:**
    1. The three demo variants, live, transcripts captured (this IS the D-15 acceptance bar)
    2. A grandfathered legacy plan slug → ledgered WARN naming the retrofit path, dispatch proceeds
    3. A non-build subagent_type (research) → passes untouched
    **Wire checks:**
    - `adapters/claude-code/settings.json.template` PreToolUse Task|Agent → `dispatch-chain-gate.sh`
    - `adapters/claude-code/hooks/dispatch-chain-gate.sh` → `model-policy.json` build-category types
    - `adapters/claude-code/hooks/dispatch-chain-gate.sh` grandfather list → `config/` install-generated slug file
    **Integration points:**
    - model-pin-gate rides the same matcher — ordering verified non-conflicting (both read-only on tool_input)
    - Live settings reconcile on THIS machine after template lands (additive sync limitation known)
- [ ] 18. REQ-B9 G3 extension: `review-record-push-gate.sh` consumes the DEC-5 class-table config
  (harness class → BLOCK by config date; provenance-docs EXEMPT; product/other → WARN with
  per-class baselines measured from the calibration week's real push history); same-push
  record-honoring stated + tested — Verification: full — Implements: REQ-B9 — Docs impact:
  manifest entry updated; gate header contract
    **Prove it works:**
    1. Gate self-test: harness-class fixture push lacking a required review → refused (WARN text during calibration window per config date)
    2. Provenance-docs-only fixture push → exempt, passes silently
    3. Record committed in the same push as the gated commit → honored (same-push read)
    **Wire checks:**
    - `adapters/claude-code/hooks/review-record-push-gate.sh` → reads `adapters/claude-code/config/review-class-table.json`
    - `adapters/claude-code/hooks/review-record-push-gate.sh` class computation → pushed paths via the pre-push ref args
    **Integration points:**
    - `git-hooks/pre-push` stage 4 dispatcher unchanged (extension is inside the gate script)
- [ ] 19. REQ-B10 no-addendum lint (in hygiene-scan; narrowed pattern per M-9 + harness delta:
  Addendum/Update: in designs+plans with `docs/plans/archive/**` EXCLUDED from scope entirely;
  `Round [0-9]` in `docs/designs/**` ONLY; case-insensitive; fresh-waiver escape, ledgered; the 5
  measured legitimate hits as verbatim negative fixtures) + the considerations brief's addenda
  integrated into its body (golden case executed) — Verification: full — Implements: REQ-B10 —
  Docs impact: brief body integration IS the doc change
    **Prove it works:**
    1. Hygiene-scan self-test: fixture design with `## Addendum` → blocked with escape named; `## Round 3 — harness-reviewer REJECT` inside a PLAN → passes (negative fixture verbatim)
    2. The brief (`harness-execution-redesign-considerations-2026-08-02.md`) carries no Addendum/Round headings; a changelog line records the integration
    **Wire checks:**
    - `adapters/claude-code/hooks/harness-hygiene-scan-body.sh` (or its body split) → the narrowed regex + `docs/designs` scoping
    - `docs/designs/harness-execution-redesign-considerations-2026-08-02.md` → zero `^#+ .*Addendum` matches post-integration
    **Integration points:**
    - Pre-commit chain ordering unchanged; the lint rides the existing hygiene-scan invocation
- [ ] 20. REQ-B11+B12 carriage channels 2+3 (after Task 11): `scripts/dispatch-directives.sh`
  (tag-matched entries for a task's Files-to-Modify, printed for prompt inlining) +
  orchestrator-pattern doctrine step + doctrine-jit merged single-emission register walk (C-1
  form: both walks compute, ONE `hookSpecificOutput` JSON object emitted containing both bodies;
  per-walk markers; always-exit-0; both-match-same-event self-test scenario) + G1/G2 carriage
  WARNs (tagged-surface plan/dispatch lacking matched OD citations) — Verification: full —
  Implements: REQ-B11, REQ-B12 — Docs impact: orchestrator-pattern + doctrine-jit header contracts
    **Prove it works:**
    1. `dispatch-directives.sh <this-plan> 20` → prints the OD entries whose globs match this task's files
    2. doctrine-jit self-test: an Edit matching BOTH a doctrine trigger AND a register glob → ONE valid JSON object on stdout containing both bodies; jq parses it
    3. Second identical Edit in the same session → no re-injection (markers)
    4. TIMING (fidelity F-5): the register walk's added latency measured 10-run average and recorded in the evidence file; must be < 50 ms — which forbids any per-event jq/subprocess in the walk (pure-bash parse or a pre-parsed cache file; jq alone costs ~174 ms on this platform)
    **Wire checks:**
    - `adapters/claude-code/scripts/dispatch-directives.sh` → `directives-register-lib.sh` glob matcher
    - `adapters/claude-code/hooks/doctrine-jit.sh` register walk → same lib; single `jq -n` emission site
    **Integration points:**
    - C-1's both-match scenario is the load-bearing test — asserted on raw stdout being ONE parseable JSON object
- [ ] 21. REQ-C2 estate drain (after Task 17, so legacy-plan dispositions retire G2's grandfather
  population): 10 verified-safe worktrees pruned; 135 nl-issues triaged via the mechanized
  supersession sweep + dispositions; 23 stale ACTIVE plans dispositioned (close/SUPERSEDE/DEFER,
  one line each); the 1,254 alerts: execute the 36%-clearing route fix or explicitly re-own it,
  disposition the remainder — Verification: full — Implements: REQ-C2 — Docs impact: drain record
  in docs/reviews/
    **Prove it works:**
    1. `git worktree list` count drops by 10 with zero unmerged-content loss (pre-verified safe list)
    2. nl-issues untriaged count 135 → <20, each closure naming supersession evidence or a disposition
    3. ACTIVE plan census 23 → ≤5 honest ACTIVEs (this plan + verified-live work)
    **Wire checks:**
    - n/a — drain task: the products are dispositions and removals verified by the counts above, not a new code chain (justification ≥30 chars)
    **Integration points:**
    - Concurrent-ownership gate will challenge Status flips on session-owned plans — follow its guidance per flip; never bypass
- [ ] 22. REQ-C3+C4: honest scorecard in the existing dashboard snapshot (net-artifact delta,
  hooks-per-Bash, SessionStart spawns, machine-census scheduled tasks) + DEC-6 invariant-8
  amendment and DEC-7 cold-target re-scope recorded in the brief's body. Counting method (fidelity
  weakest-mapping fix): net-artifact delta = `git diff --stat` file census between the program's
  start tag (predecessor plan's first commit) and HEAD restricted to `adapters/claude-code/**`,
  cross-checked against the design §7 ledger rows; hooks-per-Bash and SessionStart spawns counted
  from the live settings.json the same way budget-bash-hooks counts them; the evidence file
  asserts ONE recomputable number per metric with its exact command — Verification: contract —
  Implements: REQ-C3, REQ-C4 — Docs impact: brief body edits ARE the doc change
- [ ] 23. REQ-C5 minimal Stage-3 subset: death-certificate fields on nl-maintenance's existing
  handle-wait + cleanup-as-sensor fields on the existing janitor log, each naming its consumer at
  birth in the field comment — Verification: contract — Implements: REQ-C5 — Docs impact: none —
  fields documented at their write sites
- [ ] 24. REQ-C6 Stage-2 admission trigger: doctor WARN "stage-2 admission open since <date>"
  (data-file date written by Task 8's completion) persisting until a Stage-2 plan goes ACTIVE —
  Verification: contract — Implements: REQ-C6 — Docs impact: manifest entry
</br>

## Files to Modify/Create

Create:
- `adapters/claude-code/hooks/lib/review-chain-lib.sh` — the ONE chain parser (T1)
- `adapters/claude-code/hooks/dispatch-chain-gate.sh` — G2 (T1 skeleton, T17 live)
- `adapters/claude-code/config/operator-directives.json` + `adapters/claude-code/scripts/gen-directives-view.sh` — register + generator (T11)
- `adapters/claude-code/hooks/lib/directives-register-lib.sh` — register parser (T11)
- `adapters/claude-code/agents/design-author.md`, `adapters/claude-code/templates/design-template.md` (T12)
- `adapters/claude-code/agents/plan-fidelity-reviewer.md` (T13)
- `adapters/claude-code/scripts/dispatch-directives.sh` (T20)
- `adapters/claude-code/config/review-class-table.json` (T18); G2 grandfather slug file under `adapters/claude-code/config/` (T17)
- test fixtures under `adapters/claude-code/tests/fixtures/` for chain/ledger/plan shapes (T1/T15/T17)

Modify:
- `adapters/claude-code/hooks/lib/single-flight-lib.sh` — sf_release, pid-liveness, HALT dir (T3, T7)
- `adapters/claude-code/scripts/nl-maintenance.sh` — daemon/watchdog fixes, friction path, death-cert fields (T3, T5, T23)
- `adapters/claude-code/scripts/install-maintenance-task.ps1` — only if watchdog contract changes require (T3)
- `adapters/claude-code/hooks/harness-doctor.sh` — skip-exit contract, fingerprint, cadence data-flip reads, stage-2 admission WARN, triage waivers (T4, T7, T8, T24)
- `adapters/claude-code/hooks/session-start-digest.sh` — refresh becomes invoke-and-read-only; label renames (T4, T7)
- `adapters/claude-code/config/schedule-manifest.json` — flip dates, zero-substrate data (T6, T7)
- `adapters/claude-code/manifest.json` + `adapters/claude-code/doctrine/INDEX.md` — orchestrator-integrated entries (T6 + each new mechanism)
- `adapters/claude-code/hooks/plan-reviewer.sh` — Checks 20-22 (T14)
- `adapters/claude-code/templates/plan-template.md` (+ live sync) — new fields (T14)
- `adapters/claude-code/hooks/workstreams-emit.sh` — dispatch ledger + shared parse fix (T15)
- `adapters/claude-code/settings.json.template` — G2 wiring (T17)
- `adapters/claude-code/hooks/review-record-push-gate.sh` — class-table consumption (T18)
- `adapters/claude-code/hooks/harness-hygiene-scan-body.sh` (exact filename per repo) — no-addendum lint (T19)
- `adapters/claude-code/hooks/doctrine-jit.sh` — merged single-emission register walk (T20)
- `adapters/claude-code/doctrine/orchestrator-pattern.md` (live+repo per install flow), `single-flight-halt-runbook.md`, `planning.md` compact — doctrine deltas (T3, T15, T17, T20)
- `neural-lace/workstreams-ui/server/derive-cache.js` — Law-1 header supersession sweep (T11)
- `adapters/claude-code/config/model-policy.json` — two agent entries (T12, T13)
- `docs/designs/harness-execution-redesign-considerations-2026-08-02.md` — addenda integrated (T19)
- `docs/plans/harness-execution-redesign-2026-08.md` — closure flips + SUPERSEDED (T9)
- `~/.claude/state` ledgers/markers as specified (runtime state, not committed)

## In-flight scope updates
- 2026-08-03: `neural-lace/workstreams-ui/web/app.js` + `neural-lace/workstreams-ui/web/index.html`
  — T5's schema change (dropping the never-populated `blocks` key) would have broken the pane's
  live consumer ("undefined blocks" per gate row); the T5 builder fixed the consumer in the same
  commit, disclosed it, and verified via node --check + maintenance-pane.selftest.js (9/9). A fix
  to a break one's own edit causes, not scope creep.

## Assumptions

- The design is FINAL at r3 (blob `53fd8f27…`, harness PASS + architecture SOUND, all delta
  findings discharged); any post-r3 design change re-opens the chain (rule 2) and obliges
  re-review BEFORE affected tasks dispatch (frozen flips back to false, Decisions Log entry).
- `subagent_type` is present and inspectable in PreToolUse tool_input for Task|Agent (proven by
  model-pin-gate's live behavior at `model-pin-gate.sh:166-167`).
- The grounding sweep's line numbers remain valid at dispatch time for Tasks 3-5 (HEAD moves only
  via this plan's own commits until they land; builders re-verify before editing).
- `workstreams-emit.sh`'s existing event parse can be extended without changing its exit-0
  contract (its header states writer semantics).
- The estate's other machines pick up template changes via session-start-auto-install; live
  settings reconcile beyond additive sync is per-machine manual (known limitation, tracked).
- Windows `/proc/<pid>/cmdline` is readable under MSYS2 bash for the identity check (fallback
  `ps -p` exists if not).

## Edge Cases

- **Sf-skip with cold empty cache** (T4): exit 3 + SKIPPED line, never fabricate a verdict.
- **PID reuse at watchdog kill time** (T3): identity mismatch ⇒ log-and-skip; two live daemons
  briefly coexisting is bounded by sf_release semantics.
- **Both-match JIT event** (T20): one JSON object, both bodies — the C-1 scenario.
- **Chain-block edits self-invalidating anchors** (T1): canonicalization excludes the chain
  section and In-flight updates — appending an entry never breaks the anchor.
- **Grandfathered plan dispatched on another machine before its retrofit** (T17): ledgered WARN,
  never block — the population retires via T21.
- **A record and its gated commit in the same push** (T18): same-push honoring reads records as of
  the pushed SHA.
- **plan-phase-builder dispatch with no derivable plan slug** (T17): BLOCK (that agent exists only
  for plan work); `test-writer` without a slug: WARN + ledger row.
- **Dirty worktree at fingerprint time** (T4): dirty bit changes the fingerprint → cache miss →
  honest recompute (correct, slightly slower — never stale-serve).

## Acceptance Scenarios

n/a — harness-dev plan, no product user; see acceptance-exempt-reason in the header. The
REQ-B8 three-variant demo transcripts are this plan's acceptance artifact.

## Out-of-scope scenarios

None — all scenarios live in the design's NON-GOALS list, restated in Scope OUT above.

## Behavioral Contracts

### Idempotency
Review-chain validation is read-only and repeatable (same inputs → same verdict); dispatch-ledger
appends are at-least-once with rows keyed by ts+session (duplicate rows are harmless to rule 3);
register generation is idempotent (byte-identical re-runs, T11 proof); sf_release is idempotent
(releasing a released lock is a no-op).

### Performance budget
G2 adds work ONLY on Task|Agent events (zero per-Bash cost); its check is file-reads + one git
hash-object (< 300 ms budget, measured in T17 evidence); the JIT register walk adds < 50 ms to an
existing hook (no new spawns); G3 adds one config read + record greps at push time (< 1 s).
Nothing in this plan adds a per-Bash hook (the 25-count does not grow — verified in T22's
scorecard).

### Retry semantics
Gates are stateless deciders — a blocked call is retried by fixing the input and re-invoking (the
{FIX} field names the exact step); no gate holds locks; the daemon watchdog relaunch is
single-flighted with identity-verified kill.

### Failure modes
Lib unreadable/parse error in any gate ⇒ fail-open with a WARN line naming the degradation (never
silent, never fail-closed on an internal error — the model-pin-gate precedent); ledger unwritable
⇒ exit 0 (writer contract) + degradation line; register JSON invalid ⇒ all three consumers
surface the same parse error from the shared lib.

## Closure Contract

- **Commands that run:** `review-chain-lib.sh --self-test` · `dispatch-chain-gate.sh --self-test`
  (includes the three demo variants) · `nl-maintenance.sh --self-test` (S11 unmasked) ·
  `harness-doctor.sh --self-test` + a full quick run · `plan-reviewer.sh --self-test` (new
  scenarios) · `directives-register-lib.sh --self-test` · doctrine-jit both-match scenario ·
  hygiene-scan lint scenarios · `manifest-check.sh` · the T21 count checks.
- **Expected outputs:** all self-tests PASS; the three demo-variant transcripts show BLOCK /
  BLOCK / parse-FAIL; doctor ≤9 REDs; friction pane row present; daemon 3-tick heartbeat proof.
- **On-disk artifact location:** `docs/plans/gated-pipeline-master-2026-08-evidence.md` +
  structured `.evidence.json` per mechanical/contract task + demo transcripts under
  `docs/plans/gated-pipeline-master-2026-08-evidence/` .
- **Done when:** every task is task-verifier PASS, the evidence file carries the three demo
  transcripts with BLOCK verdicts, and the five Intended-Functionality pass/fail items all hold.

## Testing Strategy

Every harness artifact ships/extends a `--self-test` (the estate convention); task-level proof is
the self-test PLUS the task's Prove-it-works runtime steps. The load-bearing novel tests: the
chain fixture quartet (T1), the single-writer cache assertion (T4), the ≥2-real-ticks daemon
assertion under the real guard (T3), the both-match single-emission JIT scenario (T20), the
three-variant blocked-dispatch demo (T17), the negative lint fixtures taken verbatim from the
live corpus (T19), and the register round-trip fixture shared by T11/T20. No AI-output features
in this plan (gates are deterministic), so no live-model evidence is required. Orchestrator
re-runs every builder's self-test independently before merge (never trusts builder claims).

## Walking Skeleton

The thinnest end-to-end slice of the pipeline is: a Review Chain block in a fixture plan →
parsed by `review-chain-lib.sh` (all three validity rules, fixture ledger) → consumed by
`dispatch-chain-gate.sh --check` → a correct BLOCK with a complete instruction. That slice
exercises every architectural layer the plan adds (artifact contract → parser lib → gate →
gate-contract message) before any of the surrounding machinery exists. First task: 1.

## Decisions Log

- 2026-08-03 (plan-time): all DEC-1…DEC-10 decisions live in the design r2 §3 with rationale +
  reversal costs; DEC-1 is flagged for operator §8 review (it decides open questions Q-01/Q-08).
  This log gains only NEW mid-build decisions.

## Definition of Done

- [ ] All 24 tasks checked off (task-verifier is the only checkbox-flipper)
- [ ] All self-tests in the Closure Contract pass, re-run by the orchestrator
- [ ] The three-variant demo transcripts captured in the evidence directory
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file, including every decide-and-go decision
