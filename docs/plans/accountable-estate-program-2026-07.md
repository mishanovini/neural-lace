# Plan — Accountable Estate Program (build plan, cross-machine)

Status: ACTIVE
Mode: code
Execution Mode: orchestrator
Backlog items absorbed: none
acceptance-exempt: yes (harness-internal; each slice demonstrates via its own outcome metric + --self-test)
Build machine: the operator's OTHER computer (this repo pulled fresh); the desktop stays on downstream-product work.
outcome-gated: true (T9, 2026-07-30 — "applied to THIS program first" per the T9 task's own words:
this program opts into the outcome-gate close-plan.sh now enforces (`verify_closure_outcome_declared`).
Harmless today (this plan has many open tasks and will not close soon), but when it eventually DOES
close, close-plan.sh will require the `## Closure Outcome` section below to be genuinely populated
(non-placeholder metric + re-check date) before flipping Status — the program's own program-rule-2
requirement, now mechanically enforced on itself rather than aspirational prose.)

## Goal
Ship the reviewed Accountable Estate program — estate observability, deterministic closure,
admission control, and the self-learning loop — in thin outcome-gated slices, per:
- Failure analysis: docs/lessons/2026-07-27-outcome-blind-closure-and-estate-entropy.md
- Spine design (+operator directives §6b/§6c): docs/designs/accountable-estate-2026-07-27.md
- Mechanism design: docs/designs/estate-performance-governor-2026-07-27.md
- Architecture review (SOUND-WITH-AMENDMENTS, binding): docs/reviews/2026-07-27-accountable-estate-architecture-review.md

## Program rules (from the review's pre-mortem prevention — binding)
1. WIP limit: ONE slice in flight at a time. 2. Every slice closes with a demonstrated outcome
metric + re-check date; recurrence auto-reopens. 3. Every slice RETIRES something (a hook, store,
or claim) as part of its Definition of Done. 4. Observe-first before every enforcement flip.
5. Enforcement lives in libs called by every dispatcher (incl. session-resumer), never gates alone.

## Machine claims (cross-machine WIP coordination — added 2026-07-29, operator throughput directive)

Rule 1's honest restatement: never two slices in the SAME FILES at once — file-disjoint slices
MAY run in parallel across machines (T3∥T7 proved this safe). To prevent overlap without waiting:
before dispatching a builder for any slice, PULL master, add a claim line here, and push it (or
include it in the dispatch-adjacent commit); clear the line in the landing commit. A stale claim
(>24h, no matching worktree commits) may be taken over after a pull confirms no landed work.
Format: `CLAIM: <task> — <machine> — <UTC date> — <surface files>`

- Standing split (2026-07-29): OTHER machine → T4 then T5 — **CLEARED 2026-07-30: both landed + verified conf 9 (T4 336162c, T5 8be2e3d)** (closer family / merge-lock surfaces),
  plus the T7 full mine (one command, heavy fork load — the faster machine; see backlog
  ESTATE-T7-LOE-BACKFILL-FULL-MINE-PENDING-01). DESKTOP → T6 prerequisites as file-disjoint
  micro-slices (occupancy TTL cache in admission-lib; env-bypass closure; Loop-2 pressure tick),
  then T9 after T4 lands (T9 builds on T4's generalized closers). T8 waits on telemetry accrual.
- T9 NOTE (2026-07-30, T7 flip): the append-at-close seam is T9's to build — splice spec in loe-backfill.sh's header; ESTATE-T7-LOE-BACKFILL-FULL-MINE-PENDING-01 closed against 6ffe534.
- CLEARED 2026-07-29: T7 remainder — full 163-plan mine completed on the DESKTOP post-purge
  (the purge collapsed the fork tax that killed it 3x); docs/loe/loe-calibration.json/.md
  committed. T7 awaits task-verifier only.
- CLAIM: T6 prerequisites (a) occupancy TTL cache + (b) env-bypass closure/acceptance —
  desktop — 2026-07-29 — adapters/claude-code/hooks/lib/admission-lib.sh (NOTE for the other
  machine: T4's closure-gates-new-work splice also touches this file — pull and rebase small;
  the TTL cache is confined to the occupancy read path) + (d) Loop-2 pressure tick —
  surface per docs/designs/estate-performance-governor-2026-07-27.md (tick writer + pressure_src)

## Scope / Tasks (LOE: plan-level reference classes per review F11; 1 bs = one builder-session ≈ 80–150k tokens; bands are P50–P90 priors, calibrated as T7 lands)

- [x] T1 — Read-only estate inventory + daily brief. New janitor scheduled task (deterministic bash)
      reducing existing truth (heartbeats, process table, `git worktree list`, signal-ledger tail,
      ask-registry) → `snapshot.json` + rendered brief, incl. orphaned-worktree/branch found-list.
      Outcome metric: "what is running and who asked" answerable from one surface in <30 s.
      LOE: SMALL, 1–2 bs (class: reducer+renderer; comparable: digest sections, coord-sync).
      Verification: full.
- [x] T2 — Ask SLAs: deadline/default-action/SLA verbs on ask-registry + the brief's ≤5-asks panel.
      Outcome metric: zero operator-asks silently older than their deadline in a 14-day window.
      LOE: SMALL, 1 bs (class: lib-extension+view). Verification: full.
- [x] T3 — Admission lib (slots + rate + HALT + drain flag), OBSERVE MODE ONLY, called from the
      dispatch gate AND session-resumer AND emit-feed registration (derived lineage per review F2/F4).
      Outcome metric: 7 days of would-block ledger separating storm vs legitimate load.
      LOE: SMALL-MEDIUM, 2 bs, medium variance (multi-callsite wiring). Verification: full.
- [x] T4 — Deterministic closers: generalize close-plan.sh pattern per work-item type + the
      closure-gates-new-work WIP rule in the admission lib + no-orphan registration at
      spawn-worktree. Outcome metric: zero unattributable worktrees/branches older than 48 h.
      LOE: MEDIUM, 2–3 bs, medium-high variance (lifecycle semantics). Verification: full.
- [x] T5 — Estate merge lock + single deterministic merge script (coord-sync single-writer idiom);
      closers call it; nothing else merges. Outcome metric: zero master divergence events while
      active (re-check 14 d). LOE: SMALL-MEDIUM, 1–2 bs, medium variance (git edge cases).
      Verification: full.
      Clock start (this worktree, 2026-07-30T05:56:59Z — the first real, non-fixture
      `estate-merge.sh --check --into master` run against this machine's actual checkout, which
      wrote the tracking-since marker and PROVED the live detection: `master` was BEHIND
      `origin/master` by 6 commits at that moment): the 14-day re-check window opens
      2026-08-13T05:56Z. Re-check command (safe, read-only, no fixtures):
      `bash adapters/claude-code/scripts/estate-merge.sh --check --into master --repo <main-checkout>`
      — exit 0 + no "RED: merge commit ... bypassed the estate-merge lock" line across the window
      is the metric; a WARN-only "BEHIND" finding is expected/healthy staleness, not a divergence
      event. Today's real integration target is wip/harness-hardening-2026-07-29 (master cannot
      take merges — see this plan's LIVE CONTEXT note in T5's own build session), so until that
      clears the operationally-relevant re-check is
      `--into wip/harness-hardening-2026-07-29` (that branch has no configured upstream today, so
      its own freshness axis reads INFO/no-upstream — only the lock-bypass axis applies there).
- [ ] T6 — Enforce flip for admission (pressure-ladder thresholds from T3's calibration data).
      GATED: requires ≥7 calendar days of T3 observe data + operator sign-off on thresholds.
      Clock start (task-verifier pass 4 D-5): the ledger's first row is 2026-07-29T03:33:44Z,
      so the ≥7-day gate opens 2026-08-05T03:33Z — that date IS the T6 re-check trigger.
      ADDITIONAL ACCEPTANCE CRITERIA (from T3's review round, 2026-07-28 — the flip MUST NOT
      happen until all four hold): (a) admission hot path under 5 ms/dispatch — measured
      70.8 ms with a real janitor snapshot present, 19.0 ms without, so a TTL cache on
      occupancy is required work here; (b) the four environment bypasses named in
      admission-lib.sh's header (ADM_ABSURD_SESSION_CAP, ADM_ESTATE_SNAPSHOT, ADM_STATE_DIR
      which hides HALT, and the caller-declared NL_PROTECTED_ORCHESTRATOR tag) closed or
      accepted in writing; (c) occupancy real on the collecting machine (needs a darwin
      janitor schedule — the installer is Windows-only today); (d) the Loop-2 pressure tick
      emitting, so pressure_src stops reading 'absent' on every line.
      LOE: TRIVIAL, 0.5 bs. Verification: full.
- [x] T7 — LOE v1: per-PLAN actuals mining (archived plans + evidence + git history), 3–5 plan
      classes, P50/P90 bands + concentration flag surfaced by plan-reviewer. Outcome metric: every
      new plan carries class+band annotations; actuals append at close.
      LOE: MEDIUM, 2 bs. Verification: full.
- [ ] T8 — Self-learning wiring: anomaly rules over telemetry → auto-filed incident item with
      forensic snapshot → RCA dispatch as queued work → proposal draft + ledger ask (approve/deny
      with default-action) → outcome-track. Outcome metric: next incident's forensics cost ≈ one
      file-read; ≥1 proposal round-trips the full loop. LOE: MEDIUM, 2–3 bs, medium variance
      (anomaly thresholds need T1/T3 data). Verification: full.
- [x] T9 — Outcome-gated closure semantics for harness plans (metric + re-check + auto-reopen),
      applied to THIS program first. LOE: MEDIUM, 2 bs. Verification: full.
- [ ] T10 — Store consolidation tail (8 → ≤3, one store at a time, views-first sequencing per
      review F6; signal-ledger stays a dumb flight recorder per F5). DEFERRED until T1–T9 prove
      out. LOE: LARGE, 5–10 bs, HIGH variance — the program's flagged risky bet; operator
      re-authorizes before start. Verification: full, per store.

**Program totals (T1–T9): ~13–17 builder-sessions ≈ 1.5–2.5M tokens; wall-clock ≈ 1–2 weeks of
part-time autonomous work with review gates. T10 adds 5–10 bs and is separately authorized.**

## Additions 2026-07-28 (operator directives — design §3b.1–3b.3; append-only to avoid collision with in-flight builders)
- [ ] T11 — Keep-moving watchdog + completion-refill contract (design §3b.1 rules 1–4): janitor
      rule (idle orchestrator ∧ non-empty frontier ∧ no live children ≥N min → resumer-channel
      nudge) + orchestrator-pattern doctrine edits (background-first dispatch; watchers are
      Monitors/ticks, never builder sessions) + **child-completion notifications carry the refill
      prompt** (frontier count + free slots injected with the wake event) obliging a FULL frontier
      re-dispatch — never one-for-one replacement; unexplained non-dispatch with ready work +
      headroom = the watchdog's idle anomaly. Outcome metrics: zero "idle orchestrator + ready
      work >30 min" events in a 7-day window AND median completion→next-dispatch latency <2 min.
      LOE: SMALL-MED, 1.5–2.5 bs (depends-on: T1, T3). Verification: full.
- [ ] T12 — Presence-aware headroom: last-input idle capture in janitor → presence.json; admission
      lib widens/narrows ladder. Outcome metric: idle-hours dispatch width ≥2× active-hours width
      with zero interactive-use complaints. LOE: SMALL, 0.5–1 bs (depends-on: T3). Verification: full.
- [ ] T13 — Model-routing enforcement: class→model config table; queue item carries the routing
      key; dispatch path applies it mechanically; effort-policy-warn flags mismatches
      (observe-first); brief reports compliance %. Outcome metric: ≥80% of mechanical-class
      dispatches on the designated tier within 14 days of enforce. LOE: SMALL-MED, 1–2 bs (coarse
      classes pre-T7, full post-T7). Verification: full.
- [ ] T14 — Cloud offload path: queue items flagged cloud-ok; dispatcher opens cloud/scheduled
      sessions for them; results land via git; closers register completion. Outcome metric: ≥1
      slice built end-to-end in cloud with local verify+merge. LOE: MED, 2–3 bs (depends-on: T1,
      T4). Verification: full.

## Files to Modify/Create
- adapters/claude-code/scripts/estate-janitor.sh — T1 (deterministic bash, plus installer task); T2
  extended the ask-fold to carry deadline/default_action (brief-only wiring gap the table didn't
  originally name — estate-brief.sh renders ONLY snapshot.json, never raw ask-registry.jsonl, so the
  SLA panel had no source without this)
- adapters/claude-code/scripts/install-estate-janitor-task.ps1 — T1 installer, ship-only per task scope
- adapters/claude-code/scripts/estate-brief.sh — T1/T2
- adapters/claude-code/scripts/ask-registry.sh (extend: deadline/SLA/default-action verbs) — T2
- adapters/claude-code/hooks/lib/admission-lib.sh — T3/T4/T6
- adapters/claude-code/scripts/session-resumer.sh (call admission lib) — T3
- adapters/claude-code/hooks/workstreams-emit.sh (call admission lib at
  `--on-builder-dispatch`) — T3. NOT in the original table, but named by T3's own
  task text ("called from the dispatch gate AND session-resumer AND emit-feed
  registration"): this hook IS the emit-feed registration point and sits on the
  PreToolUse `Task|Agent|Workflow` matcher, so it is also the dispatch-gate
  surface. Same class of table-vs-task-text gap T2 recorded for estate-brief.sh.
- adapters/claude-code/scripts/spawn-worktree.sh (call admission lib after a
  successful worktree create) — T3 for the OBSERVE call; T4 still owns the
  no-orphan ledger REGISTRATION at this same site (design §6c). Listed here
  because a worktree create is a real dispatch and would otherwise be a
  substantial dispatch path emitting nothing into the ledger — the review's
  named NEEDS-RESHAPING condition.
- adapters/claude-code/scripts/close-*.sh closer family + spawn-worktree registration — T4
- adapters/claude-code/scripts/merge-serialized.sh + lock — T5
- adapters/claude-code/hooks/plan-reviewer.sh (LOE surfacing) — T7
- adapters/claude-code/scripts/loe-backfill.sh (NEW) — T7 mining half: per-PLAN
  actuals miner (docs/plans/archive/*.md + companion evidence + git history),
  5-class deterministic classifier, emits docs/plans/loe-calibration.json (the
  committed calibration artifact) + docs/plans/loe-calibration.md (rendered
  summary). Close-side "actuals append" is a documented seam (this file's own
  header comment names the exact close-plan.sh call site) — not built here,
  per the WIP-1 directive keeping T7 out of closer/admission/dispatch files.
- docs/plans/loe-calibration.json + docs/plans/loe-calibration.md (NEW,
  committed artifacts) — T7 calibration table output
- anomaly rules + incident capture in janitor — T8
- manifest.json + settings.json.template wiring throughout; docs/designs + this plan as specs
- `adapters/claude-code/scripts/close-plan.sh` — T9: outcome-gate (verify_closure_outcome_declared
  and write_closure_outcome_section), the T7 append-at-close splice, the Task-ID/PASS-conf parser
  fixes, the Scope-slash-Tasks heading-variant fix, and the multi-line-field extraction fix
  (already covered by the T4 close-star-dot-sh glob above, named explicitly here for T9's own record)
- `adapters/claude-code/scripts/plan-recheck-sweep.sh` — NEW, T9 AUTO-REOPEN sweep
- `adapters/claude-code/hooks/session-start-digest.sh` — T9 chokepoint wiring, new feed_plan_recheck
- `adapters/claude-code/hooks/lib/progress-log-lib.sh` — T9: plan_outcome_recorded and
  plan_reopened case arms, plus the plan-recheck-sweep known-emitter entry
- `docs/plans/context-watermark-opus5-window.md` — T9 acceptance demonstration, real plan closure
- `docs/plans/context-watermark-opus5-window-evidence.md` — moved to archive by the same closure
- `docs/loe/loe-calibration.json` — T7 splice side effect of the T9 demonstration closure above
- `docs/loe/loe-calibration.md` — T7 splice side effect of the T9 demonstration closure above

## Assumptions
- The architecture review's amendments are binding (lib-not-gate, observe-first, views-first, ≤3
  stores, per-PLAN LOE v1); deviation requires re-review.
- Builder-session token range (80–150k) from this repo's measured subagent runs; recalibrated by T7.
- The other computer has run docs/runbooks/windows-machine-perf-setup.md before heavy building.

## Edge Cases
The design's §6b register (janitor-vs-resumer drain flag, session identity across resume,
calibration pollution labeling, hygiene scrub-at-write, clock skew, spawn-free ledger access, LOE
model/mode skew) — each slice's builder must consult §6b and address the entries touching its files.

## Testing Strategy
Each artifact ships --self-test (fixture-sandboxed, HARNESS_SELFTEST=1 conventions); slices verify
via task-verifier + their declared outcome metric demonstrated live (constitution §4); enforcement
flips (T6) additionally require the calibration data attached to the evidence file.

## Closure Outcome
(T9, 2026-07-30 — this program applying its own outcome-gated-closure mechanism to itself, per the
task's own words "applied to THIS program first." This section is LIVE prose, not yet the final
close-time record — close-plan.sh's write_closure_outcome_section preserves whatever is here
verbatim at the real close, so a future session should refine this metric as T6/T8/T10-14 land, the
same way the Decisions Log / In-flight scope updates sections already accrete prose across the
program's life. Right now it states the program's honest current-best success condition.)

Outcome metric: every task T1-T9 has a task-verifier PASS + a live-demonstrated outcome metric
(constitution §4); T6's enforce-vs-defer decision is made and recorded with reasoning (not silently
skipped); T10's go/no-go re-authorization decision is made explicitly by the operator (not
defaulted); zero of the shipped mechanisms (admission-lib, estate-registration-lib, estate-merge,
loe-backfill, close-plan's outcome-gate, plan-recheck-sweep) have been silently disabled or bypassed
during the observation window.
Re-check date: 2026-08-13T05:56:00Z (aligned to T5's own already-declared 14-day re-check window —
the program's nearest existing calibration horizon; a program-wide re-check sooner than the pieces
it depends on finishing their own observation windows would fire before there is anything new to
observe).

## In-flight scope updates
- 2026-07-27: docs/designs/accountable-estate-2026-07-27.md — program spec (this plan's design)
- 2026-07-27: docs/designs/estate-performance-governor-2026-07-27.md — P0 mechanism spec
- 2026-07-27: docs/lessons/2026-07-27-outcome-blind-closure-and-estate-entropy.md — failure analysis grounding the program
- 2026-07-27: docs/reviews/2026-07-27-accountable-estate-architecture-review.md — binding review verdict
- 2026-07-27: docs/runbooks/windows-machine-perf-setup.md — other-machine setup prerequisite
- 2026-07-27: docs/plans/accountable-estate-program-2026-07.md — this plan
- 2026-07-28: adapters/claude-code/manifest.json — T1 entries (estate-janitor, estate-brief)
- 2026-07-28: docs/backlog.md — T1 perf finding (ESTATE-T1-HB-CLASSIFY-PERF-01)
- 2026-07-29: adapters/claude-code/hooks/lib/admission-lib.sh — T3 admission lib (observe mode)
- 2026-07-29: adapters/claude-code/manifest.json — T3 entry (admission-lib)
- 2026-07-29: adapters/claude-code/tests/fixtures/admission-lib/janitor-snapshot.golden.json — T3 golden fixture PRODUCED BY estate-janitor.sh (harness-reviewer C2: the author-written fixture masked two Critical parser defects)
- 2026-07-29: adapters/claude-code/hooks/workstreams-emit.sh — T3 admission splice at the emit-feed registration point (PreToolUse Task|Agent|Workflow)
- 2026-07-29: adapters/claude-code/scripts/session-resumer.sh — T3 admission splice at the storm-cap commit point (the hookless dispatcher, review F2)
- 2026-07-29: adapters/claude-code/scripts/spawn-worktree.sh — T3 admission splice after a successful worktree create; otherwise this dispatch path emits nothing into the ledger, the review's named NEEDS-RESHAPING condition
- 2026-07-29: docs/plans/accountable-estate-program-2026-07-evidence.md — T3 builder-claim evidence block (task-verifier has NOT run; checkbox left unchecked for the desktop machine)
- 2026-07-29: `adapters/claude-code/hooks/lib/estate-registration-lib.sh` — NEW, T4 no-orphan registration store (reg_register/reg_close/reg_is_open/reg_open_count/reg_has_any_record), same HARNESS_SELFTEST sandboxing convention as admission-lib.sh
- 2026-07-29: `adapters/claude-code/scripts/spawn-worktree.sh` — T4 additions on top of the T3 admission splice: `--plan`/`--task`/`--who` attribution flags, a no-orphan REGISTRATION splice on `--apply` create, `--disposition` on `--remove`, and a DE-REGISTRATION splice in `remove_worktree()`
- 2026-07-29: `adapters/claude-code/hooks/lib/admission-lib.sh` — T4 addition on top of T3: a fifth ladder rung, `would-block:wip-exceeded` (design §6c "closure gates new work"), scoped to `source=worktree` only, reading `estate-registration-lib.sh`'s open-registration count; still OBSERVE ONLY
- 2026-07-29: `adapters/claude-code/scripts/close-worktree.sh` — NEW, T4's generalized closer for the "worktree/builder" work-item type (close-plan.sh's pattern generalized to a second type): verify → integration-check (merge, or explicit `--keep-branch --reason`) → remove → de-registration
- 2026-07-29: `adapters/claude-code/scripts/estate-attribution-check.sh` — NEW, T4's outcome-metric tool: derives "zero unattributable worktrees/branches older than 48h" from the registration store + `git worktree list`
- 2026-07-29: `adapters/claude-code/manifest.json` — T4 entry (estate-registration-lib) + T4 additions to the existing admission-lib entry (golden_scenario, jit_triggers.paths)
- 2026-07-29: `docs/conventions/worktree-per-session.md` — T4 retirement (program rule 3): the bare "run `spawn-worktree.sh --remove <slug>` at session end" instruction is superseded by `close-worktree.sh` as the recommended per-session closer; Cross-references updated
- 2026-07-29: `docs/backlog.md` — T4 finding (ESTATE-T4-PRE-EXISTING-UNREGISTERED-WORKTREES-01: 25-27 real worktrees predate the mechanism, named as expected pre-existing debt with a re-check date, not silently pruned or hidden); also fixed two stray unresolved merge-conflict markers left by this session's own earlier reconciliation of this worktree's branch against `wip/harness-hardening-2026-07-29`
- 2026-07-29: `docs/plans/accountable-estate-program-2026-07-evidence.md` — T4 builder-claim evidence block (task-verifier has NOT run; checkbox left unchecked)

- 2026-07-29: `adapters/claude-code/schemas/manifest.schema.json` — hooks[] accepts scripts/<name>.sh, the form T1 needed and could not express
- 2026-07-29: `adapters/claude-code/scripts/manifest-check.sh` — scripts/ resolver, rejection scenarios, three jq-fallback defect fixes
- 2026-07-29: `adapters/claude-code/manifest.json` — estate-janitor and estate-brief moved off the inexpressible ../scripts/ form
- 2026-07-29: `adapters/claude-code/doctrine/INDEX.md` — regenerated; it carried the now-schema-invalid path string
- 2026-07-28: adapters/claude-code/scripts/loe-backfill.sh (NEW) + adapters/claude-code/hooks/plan-reviewer.sh
  (Check 18, WARN-only) + adapters/claude-code/manifest.json (loe-backfill entry) — T7 mining +
  reviewer-surfacing halves; close-side actuals-append shipped as a documented seam in
  loe-backfill.sh's own header (exact close-plan.sh function + call site named), not built, per
  the operator's WIP-1 directive keeping this slice out of admission/dispatch/closer files while
  the other machine owns T3.
- 2026-07-29: `adapters/claude-code/hooks/workstreams-emit.sh` — attribution-pipeline task (operator directive: "how do we ensure we don't keep running into this same damn issue of you reporting something that's complete false"): NL-ATTRIBUTION header convention + `_extract_nl_attribution`/`_stop_extract_nl_attribution` parsers, wired into `--on-builder-dispatch` (START, threaded into the existing T3 admission-lib splice's ledger row + `_emit_dispatch_provenance`) and `--on-stop` (END, `spawn-concluded` detail enrichment) — this is the natural next increment on T3's emit-feed registration point, closing the "attribution" half T3/T4 left as governor-only
- 2026-07-29: `adapters/claude-code/hooks/lib/admission-lib.sh` — `_adm_key_allowed` extended with `role`/`attributed` labels for the attribution-pipeline task, alongside T3/T4's existing `plan`/`task` keys
- 2026-07-29: `adapters/claude-code/scripts/dispatch-provenance.sh` — attribution-pipeline task: additive `--role` field on the dispatch-provenance marker (backward compatible)
- 2026-07-29: `adapters/claude-code/doctrine/orchestrator-pattern.md` — attribution-pipeline task: NL-ATTRIBUTION header made MANDATORY in dispatch prompts, WARN-only enforcement rung named per constitution §10
- 2026-07-29: `adapters/claude-code/doctrine/orchestrator-pattern-full.md` — attribution-pipeline task: full NL-ATTRIBUTION section (format, wiring, honest gap, enforcement rung, retirement condition)
- 2026-07-29: `docs/plans/fragments/attribution-server-fragment.md` — NEW, attribution-pipeline task: consumer contract for the workstreams-ui builder (different file owner) — how `deriveLiveAgentLeaves` should join the new START/END attribution rows to a `<plan>/<task>` id

- 2026-07-30: `adapters/claude-code/scripts/manifest-check.sh` — synced from
  wip/harness-hardening-2026-07-29@a41b0e1 (post-merge repair commit 51ef97a: apostrophe bug in
  the embedded Node program fixed, `scripts/<name>.sh` AND legacy `../scripts/<name>.sh` both
  accepted at the schema rung via a shared `_hook_disk_path` resolver, harness-claim-lint
  registered). This worktree's prior copy predated that fix and RED-failed on the
  `scripts/estate-janitor.sh` / `scripts/estate-brief.sh` / `scripts/loe-backfill.sh` form its own
  T1/T7 siblings already use — not a T5 defect, but T5's own new `estate-merge` entry needed a
  working validator to check itself against, so this dependency is synced rather than worked
  around. Manifest-check now shows 4 pre-existing REDs unrelated to T5 (harness-claim-lint.sh,
  review-record-commit-gate.sh, operator-requirement-ledger.md doctrine file — all referenced by
  manifest entries this worktree inherited from the a41b0e1 sync but whose actual hook files were
  never pulled into this worktree, since they belong to other, unrelated slices) — named here as
  pre-existing debt out of T5's scope, not silently hidden; T5's own `estate-merge` entry causes
  zero new REDs.
- 2026-07-29: `adapters/claude-code/scripts/estate-merge.sh` — NEW, T5's single deterministic merge
  path: estate-wide mkdir-atomic lock (coord-sync.sh single-writer idiom) → preflight (target
  branch exists + is checked out clean in `--repo`'s main checkout + freshness/divergence vs its
  configured upstream, when one exists) → merge (ff-only preferred; else an explicit `--no-ff`
  merge commit whose message records the rationale — never a rebase, never a force, never history
  rewrite) → best-effort dual-remote push per Decision-064 when `--into` resolves to a canonical
  branch and a second mirror remote is discovered → one log line per invocation
  (`state/estate-merge/merges.log`, coord-sync `cycles.log` idiom). `--check` is the standalone
  divergence detector (deliverable 3): REDs on target-vs-upstream true divergence, WARNs on
  target-strictly-behind-upstream (the live class proven against this machine's real `master`
  vs `origin/master`, 6 commits behind at the moment this ran for real), and REDs on any merge
  commit in the target's recent history whose SHA is absent from merges.log (a merge that
  bypassed the lock) — bounded by a PER-TARGET tracking-since marker
  (`tracking-since-sha.<target>`) so pre-existing history is never false-flagged. That per-target
  scoping is itself a bug this session found by running `--check` for real against BOTH `master`
  AND `wip/harness-hardening-2026-07-29` from the same STATE_DIR: the marker was originally one
  file per STATE_DIR, so checking `master` first left its marker in place and the
  wip/harness-hardening check reused it as a baseline, false-flagging that branch's own genuinely
  pre-existing merge commit (`9037ed3`) as a lock bypass. Fixed same-session; Scenario 19 pins the
  isolation; re-ran clean against both real branches after the fix.
- 2026-07-29: `adapters/claude-code/scripts/close-worktree.sh` — T5 graduation: the previously-hard
  BLOCKED path for an unintegrated branch now calls `estate-merge.sh merge <branch> --into <base>`
  before falling back to the ancestor check; a successful merge sets disposition=merged exactly
  like the already-integrated path. The `--keep-branch --reason` escape valve and the no-plan/task
  verification gate are unchanged. Doc comment updated to drop the "T5 not yet built" honest-gap
  note (T5 is this commit).
- 2026-07-29: `adapters/claude-code/manifest.json` — estate-merge entry (writer, OBSERVE-adjacent:
  the lock is real but nothing enforces "closers must call this" yet — see estate-merge.sh's own
  honest_status)
- 2026-07-30: `docs/runbooks/master-reconcile-and-estate-cleanup.md` — T5 retirement (program rule
  3, partial — not a deletion, an honest scope narrowing): step 6's manual post-merge VERIFY
  checklist exists to catch a MANUAL conflict-resolution mistake (a human/agent UNION-resolving a
  conflict and silently dropping one side's real change). estate-merge.sh never does manual
  conflict resolution — it fast-forwards (lossless) or lets git's own automatic merge succeed
  cleanly, and ABORTS ENTIRELY on any conflict (proven: `--self-test` Scenario 4) — so the
  dropped-side failure mode step 6 defends against cannot occur for anything merged through it.
  Step 6 is retired AS A REQUIRED STEP only for that class of merge; it remains fully required for
  this runbook's own Part A (the origin/pt two-master reconcile), which still does manual UNION
  resolution and is NOT what estate-merge.sh replaces. The runbook's opening + step 6 are both
  edited to state this scope explicitly, so a future reader does not wrongly assume the whole
  runbook — or the full step-6 checklist (manifest id-set union, generated-doc check, doctor
  self-test greens) — is now automated; only the dropped-side-sweep's FAILURE MODE is retired for
  the estate-merge.sh class, not the checklist's other checks, which estate-merge.sh does not run.
- 2026-07-29: this worktree's copy of this plan file was rebuilt from
  `wip/harness-hardening-2026-07-29@db280f2` (this worktree's own branch predates T3/T4 and lacked
  their files entirely — close-worktree.sh, estate-registration-lib.sh, spawn-worktree.sh's
  registration splices — so they were synced in as a prerequisite, non-T5 commit before this
  session's own T5 commits; see that commit's message for the full file list) with this worktree's
  own T7-only additions (the Machine-claims section, the richer T7 Files-to-Modify entry, and the
  2026-07-28 T7 in-flight-scope line above) re-applied on top so neither side's honest record is lost.
- 2026-07-30: `adapters/claude-code/scripts/close-plan.sh` — T9: (a) fixed the KNOWN-BUG fragile
  parser (verify_task_full's block-boundary regex matched any "Task <word>" prose line, orphaning
  real verdicts — new Scenario S22 regression-tests it against this repo's OWN real evidence-block
  shape, reproduced+confirmed BEFORE the fix via a standalone awk repro); also broadened PASS
  detection to accept the task-verifier agent's own "PASS conf N" convention alongside the literal
  "Verdict: PASS" form (both real, already-verified plans this task's acceptance demonstration
  closes use the terser form); (b) added the opt-in `outcome-gated: true` closure gate
  (verify_closure_outcome_declared) requiring a non-placeholder `## Closure Outcome` section
  (Outcome metric + Re-check date) before a plan can close — opt-in, never retroactive, per program
  rule 4 (observe-first before every enforcement flip: this gate must not surprise-block the ~163
  other archived plans or any other in-flight plan across the estate); (c) added the UNCONDITIONAL,
  observe-only write half (write_closure_outcome_section/generate_closure_outcome_section) — every
  plan this script closes, opted in or not, gets a `## Closure Outcome` section written into its
  archived copy (author-declared metric/re-check preserved verbatim if present; an honest default
  otherwise), with derived Evidence pointers (same git-log traversal generate_completion_report
  already used — one implementation, not two); (d) the T7 append-at-close splice, exactly per
  loe-backfill.sh's own documented seam (`bash .../loe-backfill.sh >/dev/null 2>&1 || true`,
  `|| true`-guarded per the T3 admission-lib splice convention); (e) two new progress-log event
  types, `plan_outcome_recorded` and `plan_reopened` (added to progress-log-lib.sh's
  `_pl_natural_key` + `_PL_KNOWN_EMITTERS`), emitted from the SAME successful-close call site as the
  pre-existing `plan_completed`. Self-test grew from 21 to 25 scenarios (28 assertions incl. S7's
  4 sub-parts), 28/0 on BOTH `/bin/bash` 3.2.57 and Homebrew bash 5.3.15. UPDATED 2026-07-30
  (harness-reviewer REFORMULATE remediation on close-plan.sh + plan-recheck-sweep.sh — this stale
  "25 scenarios 28/0" record was itself a finding): the C1 default-date storm fix (Re-check dates
  now marked `(default)` and refreshed at re-close), the M1 found_pass verdict-anchor fix, and
  their regression scenarios (S28, S29) grew the suite to 29 scenarios / 32 assertions, 32/0 on
  BOTH interpreters as of that remediation.
- 2026-07-30: `adapters/claude-code/scripts/plan-recheck-sweep.sh` — NEW, T9's AUTO-REOPEN half.
  Sweeps `docs/plans/archive/*.md` for Status: COMPLETED plans carrying a `## Closure Outcome`
  section whose Re-check date has passed, or whose optional author-declared Recurrence check
  command now exits nonzero (bounded via `portable-timeout.sh`'s `nl_run_bounded`, 10s) — reopens
  them: `git mv` back to `docs/plans/`, Status flip to ACTIVE, a Reopen Log entry, a
  `docs/backlog.md` row, a `needs-you.sh --mechanical` cockpit-visible entry, a `plan_reopened`
  event, one pathspec-limited commit. Never silent, never destructive (only appends + one field
  flip), idempotent by construction (a reopened plan is no longer in `archive/`, so it is never
  found twice — no separate tracking file to drift). DETERMINISTIC TRIGGER decision (SE design law:
  chokepoint, not memory): wired as a new `feed_plan_recheck` in `session-start-digest.sh`, NOT
  `supervisor-tick.sh`/`health-tick.sh` — `launchctl list` on this machine PROVED neither is
  actually registered here (both ship Windows-Task-Scheduler installers only, the same honest gap
  T1's `estate-janitor.sh` already disclosed), so the digest is the one chokepoint proven to fire on
  every real session today; the `--quick` entry point is fully decoupled from its caller so a future
  janitor/supervisor registration can invoke it with zero changes to this file. 8/8 self-test
  scenarios, both interpreters green. UPDATED 2026-07-30 (harness-reviewer REFORMULATE
  remediation): the C1 default-date-skip fix and the M3 untrusted-repo trust gate (Recurrence
  check commands now only auto-execute in the harness repo or an explicitly-trusted repo via a
  `.claude/trust-recurrence-exec` marker) added 2 regression scenarios (S9, S10) — 10/10 self-test
  scenarios, both interpreters green as of that remediation.
- 2026-07-30: `adapters/claude-code/hooks/session-start-digest.sh` — T9: `feed_plan_recheck` (new
  feed, delegates to `plan-recheck-sweep.sh --quick` exactly like `feed_nl_issues` delegates to
  `nl-issue.sh --digest-feed`) + its call site alongside `feed_stale_plans`; 2 new self-test
  scenarios (S21a/b: silent-when-clean, one-line-when-a-plan-reopens). 91/91 on Homebrew bash;
  88/91 on `/bin/bash` 3.2.57 — the 3 failures (S1 monitor-alerts, S4 auto-ack) are PRE-EXISTING on
  bash 3.2 (confirmed via `git stash` — present before this task's changes, unrelated to T9; out of
  this task's scope, not silently hidden).
- 2026-07-30: `adapters/claude-code/hooks/lib/progress-log-lib.sh` — T9: `plan_outcome_recorded` +
  `plan_reopened` case arms in `_pl_natural_key` (dedup keys mirror `plan_completed`'s own
  convention exactly) + `plan-recheck-sweep` added to `_PL_KNOWN_EMITTERS`.
- 2026-07-30: `adapters/claude-code/manifest.json` — plan-recheck-sweep entry (writer,
  SessionStart-triggered via the digest feed, golden_scenario/fp_expectation/retirement_condition/
  honesty_rationale all named honestly, incl. the SessionStart-only-not-periodic gap).
  `manifest-check.sh` GREEN (148 entries, 0 new REDs) after the addition.
- 2026-07-30: `docs/plans/accountable-estate-program-2026-07.md` (this file) — T9 "applied to THIS
  program first": added `outcome-gated: true` (opt-in, harmless today — no other open task is
  affected — but binding when this plan eventually closes) + a `## Closure Outcome` section with a
  real, honest current-best program-level metric and a re-check date aligned to T5's own already-
  declared 2026-08-13T05:56Z window (the program's nearest existing calibration horizon).
- 2026-07-30: `docs/plans/context-watermark-opus5-window.md` + its evidence file — T9 acceptance
  demonstration (real closure, not a fixture): see this plan's own Decisions/commit log for the
  close-plan.sh invocation and outcome. `docs/plans/macos-portability-2026-07.md` was NOT closed —
  its M6 task is still `[ ]` unchecked at this session's landing time (verified via
  `git log --oneline -- docs/plans/macos-portability-2026-07.md`: the latest commit, `00d592d`, is
  a FIX, not a task-verifier FLIP) — per the task's own explicit instruction ("if M6 is still open
  at your landing time, close only the watermark plan and say so").
