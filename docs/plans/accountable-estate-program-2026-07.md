# Plan — Accountable Estate Program (build plan, cross-machine)

Status: ACTIVE
Mode: code
Execution Mode: orchestrator
Backlog items absorbed: none
acceptance-exempt: yes (harness-internal; each slice demonstrates via its own outcome metric + --self-test)
Build machine: the operator's OTHER computer (this repo pulled fresh); the desktop stays on downstream-product work.

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

- Standing split (2026-07-29): OTHER machine → T4 then T5 (closer family / merge-lock surfaces),
  plus the T7 full mine (one command, heavy fork load — the faster machine; see backlog
  ESTATE-T7-LOE-BACKFILL-FULL-MINE-PENDING-01). DESKTOP → T6 prerequisites as file-disjoint
  micro-slices (occupancy TTL cache in admission-lib; env-bypass closure; Loop-2 pressure tick),
  then T9 after T4 lands (T9 builds on T4's generalized closers). T8 waits on telemetry accrual.
- CLEARED 2026-07-29: T7 remainder — full 163-plan mine completed on the DESKTOP post-purge
  (the purge collapsed the fork tax that killed it 3x); docs/loe/loe-calibration.json/.md
  committed. T7 awaits task-verifier only.
- CLEARED 2026-07-29: T6 prerequisites (a)(b)(d) — landed on desktop master as 5ee67c2 (TTL
  cache) + 1cdef7f (bypass closure, decision 065) + 4fdfc83 (Loop-2 pressure tick); suites
  55/55 + 26/26 re-run by the orchestrator post-cherry-pick. T6 flip still gated on the 7-day
  clock + operator thresholds + criterion (c) darwin janitor schedule (darwin-machine work).

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
- [ ] T4 — Deterministic closers: generalize close-plan.sh pattern per work-item type + the
      closure-gates-new-work WIP rule in the admission lib + no-orphan registration at
      spawn-worktree. ALSO OWNS (T7 verifier residual #1, 2026-07-29): the LOE
      actuals-append-at-close seam — T7's outcome-metric clause 2 ("actuals append at close")
      has a documented-but-unbuilt splice (loe-backfill.sh header lines ~96–114 names the exact
      site: close-plan.sh cmd_close, before emit_plan_completed_progress_log_event ~:1293);
      wire it here so every closure appends the plan's actuals and docs/loe/ stays fresh —
      without this the calibration table silently goes stale until a manual re-mine.
      Outcome metric: zero unattributable worktrees/branches older than 48 h.
      LOE: MEDIUM, 2–3 bs, medium-high variance (lifecycle semantics). Verification: full.
- [ ] T5 — Estate merge lock + single deterministic merge script (coord-sync single-writer idiom);
      closers call it; nothing else merges. Outcome metric: zero master divergence events while
      active (re-check 14 d). LOE: SMALL-MEDIUM, 1–2 bs, medium variance (git edge cases).
      Verification: full.
- [ ] T6 — Enforce flip for admission (pressure-ladder thresholds from T3's calibration data).
      GATED: requires ≥7 calendar days of T3 observe data + operator sign-off on thresholds.
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
- [ ] T9 — Outcome-gated closure semantics for harness plans (metric + re-check + auto-reopen),
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
- 2026-07-28: adapters/claude-code/scripts/loe-backfill.sh (NEW) + adapters/claude-code/hooks/plan-reviewer.sh
  (Check 18, WARN-only) + adapters/claude-code/manifest.json (loe-backfill entry) — T7 mining +
  reviewer-surfacing halves; close-side actuals-append shipped as a documented seam in
  loe-backfill.sh's own header (exact close-plan.sh function + call site named), not built, per
  the operator's WIP-1 directive keeping this slice out of admission/dispatch/closer files while
  the other machine owns T3.
- 2026-07-29: `docs/decisions/065-admission-lib-env-bypass-closure.md` (NEW) — T6-PREREQUISITES (b)
  written acceptance for the one of four T6-named env bypasses (NL_PROTECTED_ORCHESTRATOR) that
  stays open by design; the other three (ADM_ABSURD_SESSION_CAP, ADM_ESTATE_SNAPSHOT,
  ADM_STATE_DIR) are closed mechanically in admission-lib.sh itself (already in scope, T3/T4/T6 row
  above). Desktop machine, per the CLAIM line in Machine claims above.
- 2026-07-29: `adapters/claude-code/hooks/lib/perf-tick-snapshot.sh` — T6-PREREQUISITES (d) Loop-2
  pressure tick (pts_write_pressure_tick, wired into pts_run_tick, therefore into health-tick.sh's
  existing hourly cadence — no new scheduled task; NL-estate-janitor is not installed on this
  machine per Get-ScheduledTask, so health-tick's already-active cadence is the honest carrier).
  Desktop machine, per the CLAIM line in Machine claims above.
