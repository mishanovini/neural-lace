# Neural Lace — Harness Backlog

**Last updated:** 2026-05-15 v35 — Filed HARNESS-GAP-32 (close-plan.sh retroactive friction on legacy plans). Surfaced in the same session that filed GAP-29/30/31: when closing two ACTIVE-but-100%-done plans authored 2026-05-12 (after Tranche B's structured-evidence substrate but using the legacy prose-evidence convention), `close-plan.sh` BLOCKED both with "missing structured `.evidence.json` per task." The work was unambiguously shipped (PRs #179, #180 merged to master with full completion reports appended); the evidence-of-completion lives in prose + git history, not in `<plan-slug>-evidence/<task-id>.evidence.json` artifacts. Manual `Status:` Edit (triggering `plan-lifecycle.sh` PostToolUse auto-archive) was the workable path — the same "manual git ops, visible, several steps, appropriately rare" path the script's own header names. Filed as a sibling concern to GAP-29/30 since the gate's retroactive friction is itself contributing to staleness — it's why the two plans sat ACTIVE long enough to bleed ~20 waivers/day each. v34 — Filed three HARNESS-GAP entries (GAP-29, GAP-30, GAP-31) addressing plan-staleness as a class. Surfaced from a downstream-project audit: 14 ACTIVE plans with 1369 acceptance-waivers across 38 worktrees (200 alone on the project's largest in-flight plan, 96 on a since-closed support-agent plan, 69 on a stalled CI-coverage plan). Three distinct staleness archetypes identified: (A) work-shipped-Status-not-flipped — two plans (`capacity-preset-ui-polish`, `team-rollout-documentation-package`) have 100% of tasks AND DoD items checked but Status is still ACTIVE; (B) plan-filed-no-work — a CI-coverage plan 8 days old, 0 commits, 18 unchecked tasks; (C) silent-waiver-accumulation — operators write per-session waivers when an unrelated ACTIVE plan blocks Stop, but no mechanism reads aggregate waiver counts to surface "this plan got 60+ waivers; close-or-justify." GAP-29 proposes a SessionStart `plan-staleness-surfacer.sh` that reads the three signals (DoD-saturation, days-since-last-commit, cross-worktree waiver count) and emits actionable suggestions. GAP-30 extends `pre-stop-verifier.sh` with an "all-checked-but-ACTIVE" detector that surfaces `/close-plan <slug>` at session end with leverage to act. GAP-31 adds a `waiver-density-alarm.sh` that converts the silent waiver accumulator into a forcing function when any plan crosses a threshold. Companion to GAP-22 (escape-hatch sweep) but complementary — waivers themselves are legitimate; the gap is the missing aggregation. v33 — Reshape: the no-AskUserQuestion rule is now Dispatch-conditional, not blanket. MC widget OK on standalone Claude Code clients (Desktop / IDE / terminal); plain text only under remote-Dispatch clients (where the widget doesn't relay). Detection priority documented (env var `CLAUDE_CODE_DISPATCH=1` target convention, `~/.claude/local/dispatch-mode.json` interim fallback, explicit user signal, default standalone). Touched: CLAUDE.md Autonomy, planning.md "Plan-Time Decisions", discovery-protocol.md "Irreversible-decision PAUSE", new example template at `examples/dispatch-mode.example.json`. Filed HARNESS-GAP-28 for the Dispatch spawner to adopt the env var convention. v32 — Shipped HARNESS-GAP-27 option (a) lightweight migration-allowlist for `scope-enforcement-gate.sh`. When `$GIT_DIR/MERGE_HEAD` exists (merge resolution), `supabase/migrations/*.sql`, `prisma/migrations/**`, and `db/migrations/**` are exempt as system-managed. 4 self-test scenarios added (s13-s16); 16/16 PASS. Option (b) union-of-plans deferred per ADR 030 (trigger criteria documented). Also shipped new doctrine rule `gate-respect.md` (diagnose-before-bypass when any gate blocks; codifies the PR #197 lesson — root-cause diagnosis is the first move, applying the gate's named remediation is the second, bypass-with-explicit-user-authorization is the last). v31 — Filed three HARNESS-GAP entries transferred from a downstream-project findings ledger (FINDING-036/037/038, all P2): GAP-24 (wire propagation engine into PostToolUse to surface real-time events; companion to GAP-19), GAP-25 (profile + optimize slow `git log`-based propagation rules — both exceed 1s wall time, blocks promotion to blocking action), GAP-26 (build ADR cross-reference staleness analyzer for KIT-4 — 45 ADRs × 5 canon artifacts makes manual sweep impractical). All three properly belong in the harness, not in any project-level findings ledger; transfer pattern follows the precedent that harness-shaped issues surfaced in downstream-project work get filed here. v30 — Continued autonomous Build Doctrine push: shipped Tranche 6a (propagation engine framework + 8 starter rules + JSONL audit log at `build-doctrine/telemetry/propagation.jsonl`; 14/14 self-test PASS; 10/10 plan tasks PASS) and **Tranche 5a-integration** (audit-log analyzer at `analyze-propagation-audit-log.sh` with `summary`/`cadence`/`unmatched`/`slow` subcommands — 7/7 self-test PASS; `/harness-review` skill Check 13 KIT-1..KIT-7 sweep; pilot-friction template at `templates/pilot-friction.md`; enforcement-map row + harness-architecture section + 5 narrative-doc citations; 8/8 plan tasks PASS). All closures via `close-plan.sh` with zero `--force`. Build Doctrine roadmap headline status v6 — 7 of 8 tranches DONE. **Pre-pilot infrastructure now complete** — Tranche 4 (canonical pilot) is the only structural wall remaining; pilot consumes a fully-wired substrate (doctrine + templates + propagation engine + audit log + ritual + sweep + analyzer + friction template). 5b/6b/7 gate on pilot evidence; 5c/6c/HARNESS-GAP-11 gate on 2026-08 telemetry. v29 — Autonomous Build Doctrine continuation push: shipped Tranches 2 (template schemas — 7 schemas + 7 examples + README, 10/10 PASS), 3 (template content — 22 universal-floor templates × 2 depths + 4 language naming + branching/commits + API-style architectural default + README, 15/15 PASS), and 6-scaffolding (Python orchestrator package — DAG state machine + state types + Dispatcher protocol + ~32 pytest tests + validation-gap README, 9/9 PASS). All closures via `close-plan.sh` with zero `--force`. Tranche 4 (canonical pilot) is the wall — needs user-side decisions: pilot project identity, readiness assessment, cross-repo access, Python-equipped environment for Tranche 6 scaffolding validation. Handoff doc at `docs/plans/tranche-4-canonical-pilot-handoff.md`. Tranches 5, 7, and Tranche 6 propagation engine all gate on Tranche 4 empirical signal per doctrine. Build Doctrine roadmap headline status v3 — 7 of 8 tranches DONE. v28 — REOPENED 4 plans (Tranche E, parent of Tranche 1.5, Tranche F, HARNESS-GAP-17) per user 2026-05-06: original 2026-05-05 closures used close-plan.sh --force bypassing per-task verification on every task; not actually completed. Status flipped COMPLETED → ACTIVE; plans moved back from `docs/plans/archive/` to `docs/plans/`. Re-closure must be genuine (close-plan.sh's --force flag has since been removed). v27 — Path A in flight: state-summary.sh hybrid shipped (4/4 self-tests PASS, demarcated DERIVED + LLM-SYNTHESIS regions); env-var "override" removed from close-plan.sh entirely (was theater for an LLM agent — "loud is not rare" per user 2026-05-06; 13/13 self-tests PASS); session-wrap.sh wired into Stop chain in prior session. Pending Path A item: start-plan.sh for task-start automation. Added HARNESS-GAP-22 — sweep harness for other --force / --no-verify / OVERRIDE-style escape hatches; remove or convert to friction-the-agent-cannot-satisfy. v26 — Tied off the previous session's loose ends in this brief follow-up session: committed `session-wrap.sh` + ADR 027 v2 (Layer 5: handoff-freshness-as-precondition); flipped 2 stale 2026-05-05 discoveries (codenames → implemented; multi-active-stranding → superseded by Tranche E); archived expired `architecture-simplification-gate-relaxation` policy. Master is now CLEAN (zero ACTIVE plans). Added HARNESS-GAP-19 — wire `session-wrap.sh` into Stop chain (script is built and self-tests 5/5 PASS, just not auto-invoked yet). Earlier v25 — **Tranche 1.5 (architecture simplification) substantively complete** in the prior session. 6 of 7 sub-tranches shipped: A (incentive redesign), B (mechanical evidence substrate), C (work-shape library), D (risk-tiered verification), E (deterministic close-plan procedure — **2.8 sec closure benchmark** vs 65K-token baseline), G (calibration loop bootstrap). Tranche F (failsafe audit) deferred to next session — depends on A-E being battle-tested first. ADR 026 (harness catches up to doctrine) + ADR 027 (autonomous decision-making process) + queued-tranche-1.5.md (14 pre-emptive decisions for async user review) + doctrine extensions N1/N2/N3 (now Anti-Principle 16, Principle 17, Principle 18 in `01-principles.md`) all shipped. Hard freeze on new failsafes in effect. Live acceptance test for close-plan.sh deferred to next session — closing the architecture-simplification plans themselves via the new procedure. Closure-validator (today's GAP-16 ship) tagged-for-retirement; Tranche F's first retirement target. 8 plans currently ACTIVE on master (parent + 6 sub-tranches + HARNESS-GAP-17), all substantively done, all closing via close-plan.sh in next session. v24 — HARNESS-GAP-08 (spawn_task report-back) + HARNESS-GAP-13 (hygiene-scan 4-layer expansion) BOTH IMPLEMENTED + auto-archived this session per Option B. 14 task-verifier PASS commits on `verify/pre-submission-audit-reconcile`. Also reconciled stranded pre-submission-audit-mechanical-enforcement plan; HARNESS-GAP-16 added as next-after pickup (closure-validation gate). v23 — HARNESS-GAP-17 Part A IMPLEMENTED in this session: all 5 user-facing narrative docs (README, harness-strategy, best-practices, quality-strategy, CLAUDE.md) updated to reflect Gen 5/6 + Build Doctrine integration arc; live `~/.claude/CLAUDE.md` synced. Part B (docs-freshness-gate narrative-doc extension) remains deferred per original P2 estimate. Earlier v22 — duplicate-numbering conflict resolved: narrative-docs-stale entry (originally tagged GAP-16 in v21) renumbered to **HARNESS-GAP-17**. GAP-16 is the closure-validation gate per the "Open work" pickup list. Both entries were added 2026-05-05 within 40 minutes; the v21 header tagged the docs-stale one GAP-16 first, then the closure-validation entry duplicated the number 40 min later — closure-validation kept as GAP-16 since the "Open work" section treats it as such. v21 — HARNESS-GAP-16 added — user-facing narrative docs (README, harness-strategy, best-practices, quality-strategy, CLAUDE.md) stale post-integration; docs-freshness-gate has narrative-doc blind spot. Earlier 2026-05-05 v20 — HARNESS-GAP-08 absorbed into `docs/plans/harness-gap-08-spawn-task-report-back.md` (per backlog-plan-atomicity rule). pre-submission-audit-mechanical-enforcement plan reconciled and auto-archived this session (was stranded ACTIVE since 2026-05-03 with all 5 tasks shipped but bookkeeping never run; see commits `588b6db` + `4e8f658` on `verify/pre-submission-audit-reconcile` branch). Earlier 2026-05-05 v19 — backlog header restructured for legibility; full version log moved to bottom of file. Phase 1d-G shipped 2026-05-04 (codename scrub + GAP-14-followups + observed-errors-first stub conversion all IMPLEMENTED). Two stale plans archived: `adversarial-validation-mechanisms.md` SUPERSEDED (mechanisms shipped piecemeal), `acceptance-loop-smoke-test-evidence.md` moved to archive (orphan evidence file).

Outstanding improvements to the Claude Code harness (rules, agents, hooks, skills). Project-level backlogs live in individual project repos; this file tracks harness-level work.

## Next pickup (recommended)

**HARNESS-GAP-13 — harness-hygiene-scan expansion** is the next-cleanest pickup once GAP-08 ships. Full original scope per user 2026-05-05: ~9-10 hr; layers 1-4 (denylist additions + heuristic detection + periodic full-tree audit + sanitization helper).

In flight this session: GAP-08 (`docs/plans/harness-gap-08-spawn-task-report-back.md`) + reconciliation of stranded pre-submission-audit plan.

## Open work — substantive deferrals

- **HARNESS-GAP-32 — `close-plan.sh` retroactive friction on legacy plans whose evidence-of-completion lives in prose + git history, not structured `.evidence.json` artifacts** (added 2026-05-15). Surfaced when closing two ACTIVE-but-100%-done plans on a downstream project (`capacity-preset-ui-polish` and `team-rollout-documentation-package`), both authored 2026-05-12 — calendar-after Tranche B's structured-evidence substrate (shipped 2026-05-05) but using the legacy prose-evidence-block convention that pre-dated it. Both plans had: every `^- \[x\]` task checkbox flipped, every `## Definition of Done` checkbox flipped, completion reports appended to the plan body, and the work merged to master via PRs (#179, #180). `close-plan.sh close <slug>` BLOCKED both with `"missing structured .evidence.json per task"` because the substrate's `<plan-slug>-evidence/<task-id>.evidence.json` files were never authored — the prose evidence in the plan body was the substrate when the planner wrote it. The fallback path the gate's own header names ("Genuine emergencies use manual git ops (visible, several steps)") — direct `Status:` Edit triggering `plan-lifecycle.sh` PostToolUse auto-archive — worked cleanly but treats every legacy-plan closure as an "emergency," which it isn't. The retroactive friction is itself contributing to staleness: it's why these two plans sat ACTIVE long enough to bleed ~20 waivers/day each into unrelated sessions (see GAP-29/30/31). **Three remediation options (any one would close the gap; not exclusive):** (a) **Grandfather by authoring date.** Detect the plan file's git-creation date; if before Tranche B's substrate-availability cutoff (2026-05-05 or configurable per-project), fall back to checking the legacy prose-evidence path (`docs/plans/<slug>-evidence.md` OR inline prose-evidence blocks in the plan body) instead of structured artifacts. Self-test: legacy plan with prose evidence PASSES; new plan without structured evidence FAILS. (b) **Add `close-plan.sh --legacy` flag** that explicitly opts into the prose-evidence path with audit-logged justification at `.claude/state/close-plan-legacy-overrides.log` (one entry per use, naming plan + reason ≥ 30 chars). Friction-but-not-blocking; visible in audit. (c) **Document the manual-close path as the recognized escape for legacy plans** in `~/.claude/rules/planning.md` "Plan File Lifecycle" section — currently the path lives only in close-plan.sh's header comment, so operators must read script source to discover it. **Recommendation:** (a) is the cleanest because it's automatic and doesn't introduce an escape hatch the agent could reflexively reach for (per the "loud is not rare" principle that killed the `--force` flag). (b) is workable but adds an audit-logged escape hatch. (c) is the cheapest — documentation only. Could ship (a) + (c) together. **Effort estimate:** (a) ~2-3 hours including the date-detection + per-task prose-evidence parsing + 4-5 self-test scenarios; (b) ~1 hour; (c) ~30 min. **Priority:** P2 — friction not data-loss; the workaround (manual Edit) takes 30 seconds. **Composes with:** GAP-29/30 (which surface the plans needing closure; GAP-32 ensures the closure path is friction-proportionate). **Companion-inverse to:** the `--force` flag removal 2026-05-06 (which intentionally raised friction to prevent reflexive bypass). GAP-32 lowers friction for a legitimately-different case (legacy plans), not for vaporware closures.

- **HARNESS-GAP-29 — `plan-staleness-surfacer.sh` SessionStart hook surfacing the three plan-staleness archetypes with concrete next-actions** (added 2026-05-14). Surfaced from a downstream-project audit (2026-05-14): the project has 14 ACTIVE plans, four of which fit recognizable staleness archetypes that no existing hook surfaces. **Archetype A — work-shipped-but-Status-not-flipped:** two plans (`capacity-preset-ui-polish` and `team-rollout-documentation-package`) have 100% of `^- \[x\]` task checkboxes flipped AND 100% of `## Definition of Done` checkboxes flipped, but `Status:` is still `ACTIVE`. Each has accumulated ~20 cross-worktree waivers in 2 days because the gate fires at session-end of every unrelated session. **Archetype B — plan-filed-but-no-work:** a CI-coverage plan is 8 days old, has 18 unchecked tasks and 0 checked, and has zero commits referencing the plan slug or its `## Files to Modify/Create` paths since the plan-creation commit. 69 cross-worktree waivers accumulated. **Archetype C — chronic high-waiver:** the project's largest in-flight plan has accumulated 200 cross-worktree waivers; another long-running ACTIVE plan, 69. The waiver volume itself is a signal nobody reads. **Archetype D — DRAFT plans never advancing:** a 24-day-stale voice-integration DRAFT plan, plus a 23-day-stale consent-intake DRAFT blocked on a parent that may itself be done. **Proposed mechanism:** new SessionStart hook that iterates every plan in `docs/plans/*.md` (top-level only), computes for each: `task_completion_pct = checked / (checked + unchecked)`, `dod_completion_pct` (same for `## Definition of Done`), `days_since_last_commit_touching_plan` (via `git log -1 --format=%ct` on the plan file), `waiver_count` (cross-worktree count of `acceptance-waiver-<slug>-*.txt` matching this plan's slug across `git worktree list` outputs). Emit a system-reminder block listing plans matching any of: (A) `task_completion_pct == 100 AND dod_completion_pct == 100 AND status == ACTIVE` → "READY TO CLOSE: run `/close-plan <slug>`"; (B) `days_since_last_commit > 7 AND task_completion_pct == 0` → "STALLED: 0 work in 7+ days; abandon, defer, or restart"; (C) `waiver_count > 30 AND status == ACTIVE` → "HIGH WAIVER COUNT (N waivers); close, defer, or split"; (D) `status == DRAFT AND days_since_last_commit > 14` → "DRAFT 14+ days untouched; advance to ACTIVE or archive as SUPERSEDED". **Effort estimate:** ~3 hours including 6+ self-test scenarios (one per archetype + clean-no-stale-plans + multi-archetype-same-plan + zero-plans-edge-case). **Priority:** P1 — this addresses the highest-frequency operator-friction pattern Misha called out 2026-05-14 ("why are so many tasks going stale?"). **Risk:** low (SessionStart hooks are advisory; the surfacer cannot break sessions, only inform). **Composes with:** GAP-30 (close-eligibility detector at Stop) and GAP-31 (waiver-density alarm) — the three together close the staleness loop end-to-end. **Reverse-companion to:** the existing `plan-status-archival-sweep.sh` (which catches `Status: terminal` plans whose archive didn't fire) — this is the inverse: catches `Status: ACTIVE` plans whose close didn't fire.

- **HARNESS-GAP-30 — Extend `pre-stop-verifier.sh` with "ready-to-close" detector (Status: ACTIVE + all task boxes + all DoD boxes checked)** (added 2026-05-14). Companion to GAP-29. The existing `pre-stop-verifier.sh` (Stop hook position 1) catches the inverse problem mechanically: `Status: COMPLETED` with unchecked tasks (line 340), `Status: COMPLETED` with unchecked DoD bullets (line 650), `Status: COMPLETED` with failing DoD-artifact verification (line 831). The symmetric problem — `Status: ACTIVE` with EVERYTHING checked — is invisible. The downstream-project audit found 2 of 14 ACTIVE plans (`capacity-preset-ui-polish`, `team-rollout-documentation-package`) where every checkbox under `## Tasks` AND every checkbox under `## Definition of Done` is filled in, but Status was never flipped. Both plans now bleed waivers into every other session. **Proposed mechanism:** add a new check (e.g., Check 4d) that reads each ACTIVE plan in the working directory's `docs/plans/`, parses the task list and DoD section, and when `unchecked_tasks == 0 AND unchecked_dod == 0 AND status == ACTIVE`, emits a non-blocking system message: "Plan `<slug>` is ready to close (all tasks + all DoD items checked, Status: ACTIVE). Run `/close-plan <slug>` before session end to flip Status and trigger auto-archival." Non-blocking because: (a) sometimes the operator legitimately wants to keep ACTIVE for a final-review pass; (b) blocking would defeat the leverage moment — operator is at Stop with 30s of attention left. **Effort estimate:** ~1 hour including 3 self-test scenarios (ready-to-close-firing, ACTIVE-with-some-unchecked-not-firing, COMPLETED-with-everything-checked-not-firing). **Priority:** P1 — same root cause as GAP-29 but at a different lifecycle position (Stop vs SessionStart). **Risk:** very low (advisory only; uses existing `pre-stop-verifier.sh` plumbing). **Why both this AND GAP-29:** GAP-29 surfaces at session START so the operator picks up the cleanup at the top of their attention budget; GAP-30 surfaces at session END when the same session may have just finished work that completed the plan, with leverage to close in the same session. Together they double-tap the same condition at the two highest-leverage moments.

- **HARNESS-GAP-31 — `waiver-density-alarm.sh` SessionStart hook converting silent acceptance-waiver accumulation into a forcing function** (added 2026-05-14). Surfaced from the downstream-project audit: cumulative 1369 `acceptance-waiver-*.txt` files exist across all 38 active worktrees on this single project. Top offenders (all anonymized; see audit notes for slugs): the project's largest in-flight plan 200 waivers, a since-closed support-agent plan 96 waivers (the 96 accumulated BEFORE someone finally flipped Status), a comprehensive-rebuild plan 69 waivers, a stalled CI-coverage plan 69 waivers, three since-closed plans at 60 waivers each (a scheduling default-fix, a journey-test-harness plan, an early-2026 roadmap plan). **The pattern is reproducible:** plans that should be closed accumulate 60-200 waivers before anyone notices. Each waiver represents a session that hit `product-acceptance-gate.sh` (Stop hook position 4), decided the blocking plan was unrelated to the current session's scope, wrote a one-line justification to a `.claude/state/acceptance-waiver-<slug>-<ts>.txt`, and exited. The waiver mechanism itself is legitimate (per `~/.claude/rules/acceptance-scenarios.md` and `git-discipline.md` Rule 3 — "write waivers, don't loop"). The gap: no mechanism reads the AGGREGATE waiver count per plan and surfaces it. **Proposed mechanism:** new SessionStart hook that runs `git worktree list --porcelain`, iterates each worktree's `.claude/state/acceptance-waiver-*.txt`, deduplicates by plan-slug (the slug is between `acceptance-waiver-` and the trailing timestamp), counts per slug, and emits: when any ACTIVE plan crosses a configurable threshold (suggested default: **30 waivers, ~10/day for 3 days**), surface "Plan `<slug>` has accumulated N waivers across worktrees (W7 distribution: …, oldest waiver: …). The waivers indicate every other session sees this plan as orthogonal to their scope. Three structural options: (a) close (work shipped — run `/close-plan <slug>`); (b) defer (work blocked — flip `Status: DEFERRED`); (c) split (scope too broad — decompose into smaller plans the gate can recognize as in-scope per-session)." **Effort estimate:** ~2-3 hours including the cross-worktree aggregation logic, threshold-tuning self-tests (4-5 scenarios: under-threshold-silent, at-threshold-warn, over-threshold-loud, multi-plan-multi-threshold, no-waivers-silent), and a flag to gate on `Status: ACTIVE` only (don't alarm on already-closed plans whose old waivers persist on disk). **Priority:** P1 — addresses the highest-volume signal Misha called out and is the most-load-bearing of the three GAPs because it surfaces structural problems (scope-too-broad plans) the other two GAPs cannot see. **Risk:** low (advisory only; threshold is configurable). **Composes with:** GAP-29 (which uses the same waiver-count signal as one of its four archetypes — but GAP-29 surfaces it as one of many, GAP-31 surfaces it loudly when it crosses threshold). **Companion to GAP-22** (escape-hatch sweep): GAP-22 asks whether escape hatches should exist at all; GAP-31 accepts they exist and surfaces aggregate usage as the alarm. Both can ship; they don't conflict. **Threshold rationale:** a project with 4-5 ACTIVE plans for ~5 days, each session triggering the gate on the 4 unrelated ACTIVE plans → ~20 waivers per plan per week is normal noise. 30+ in less time signals "this plan is irrelevant to the current work portfolio and should be closed or split." Tunable via `~/.claude/local/waiver-density-config.json` if needed.

- **HARNESS-GAP-28 — Dispatch spawner should set `CLAUDE_CODE_DISPATCH=1` env var so sessions can detect remote-Dispatch client mode** (added 2026-05-14). The `AskUserQuestion` / multiple-choice tool renders fine on standalone Claude Code clients (Desktop / IDE / terminal) but does NOT relay through remote-Dispatch clients (sessions spawned via `mcp__ccd_session_mgmt__start_code_task` where the user is on a phone, web UI, or another device). Under Dispatch, MC widget invocations block the session with no path forward. The rule (per `~/.claude/CLAUDE.md` Autonomy section, 2026-05-14 reshape) is now Dispatch-conditional: detect client mode, use plain text under Dispatch, MC widget OK standalone. **Current detection signal:** none reliable — investigation 2026-05-14 confirmed `CLAUDE_CODE_ENABLE_ASK_USER_QUESTION_TOOL=true` and `CLAUDE_CODE_ENTRYPOINT=claude-desktop` are BOTH set during confirmed Dispatch sessions, so neither distinguishes. **Proposed target convention:** the Dispatch spawner (start_code_task implementation in `mcp__ccd_session_mgmt` or wherever the orchestrator session-init lives) should inject `CLAUDE_CODE_DISPATCH=1` into the spawned session's environment. Interim fallback: users may set `~/.claude/local/dispatch-mode.json` (example at `adapters/claude-code/examples/dispatch-mode.example.json`) or signal in-conversation; agents default to standalone (MC widget OK) when no positive signal exists. **Effort estimate:** ~30 min (one-line env-injection edit in the spawner + a quick verification by spawning a Dispatch session and confirming `echo $CLAUDE_CODE_DISPATCH` returns `1`). **Priority:** P2 — operational papercut today; without it, the default-to-standalone fallback occasionally produces MC-widget invocations under Dispatch that block sessions. **Risk:** low (additive env injection, no existing behavior changes). **Related:** documented in CLAUDE.md Autonomy section under "Detection priority"; `dispatch-mode.json.example` template ships in `adapters/claude-code/examples/`.

- **HARNESS-GAP-27 — `scope-enforcement-gate.sh` blind to merge-commit semantics; option (a) lightweight migration-allowlist SHIPPED 2026-05-14; option (b) union-of-plans deferred per ADR 030** (added 2026-05-14, updated 2026-05-14). Surfaced during a downstream-project PR-merge session (UX-audit follow-up work). The gate iterates ACTIVE plans currently visible in `docs/plans/*.md` and rejects any staged file not claimed by an active plan's `## Files to Modify/Create` section. When a feature branch merges master back in, master's concurrent commits pull in files from plans that were ACTIVE on master but are now archived (their parent plans got `Status: COMPLETED` and auto-archived to `docs/plans/archive/`). The gate doesn't see archived plans, so master's pulled-in files appear unclaimed, blocking the merge commit. **Today's workaround for non-migration files:** author a session-scope "merge-resolution plan" that wildcard-claims everything master might have touched (`docs/**`, `src/**`, project-specific subtrees, etc.). Fragile but workable. **Status of fix candidates:** (a) **Lightweight (SHIPPED 2026-05-14):** `_is_system_managed_path()` now honors a merge-context allowlist when `$(git rev-parse --git-dir)/MERGE_HEAD` exists. Currently allows `supabase/migrations/*.sql`, `prisma/migrations/**`, `db/migrations/**` — the commit-numbered migration paths master generates procedurally. 4 self-test scenarios added (s13-s16). Validates the highest-frequency failure case (PR #197). (b) **More general (DEFERRED, see ADR 030):** when MERGE_HEAD exists, check staged files against the UNION of all plans active on EITHER branch since the divergence point. Trigger to un-defer: 3+ distinct file classes beyond migrations require allowlist entries within a 30-day window, OR a merge-resolution-plan workaround takes >10 min for a single merge, OR a pilot project requests it as a structural blocker. (c) **Smallest (NOT YET shipped):** stderr documents the merge-resolution-plan pattern for non-migration cases. Could complement option (a) — captured here as a follow-up sub-task if recurrence justifies it. Priority: P3 now that option (a) is shipped (handles PR #197's specific failure shape).


- **HARNESS-GAP-19** — Wire `session-wrap.sh` into the Stop hook chain. The script is built (`adapters/claude-code/scripts/session-wrap.sh`, 321 lines), self-tests 5/5 PASS, and ADR 027 v2 Layer 5 specifies it as the handoff-freshness mechanism — but it's currently callable by hand only, not auto-invoked at session end. Wiring it into the Stop chain (likely position 9, after the existing 8 narrative-integrity hooks) would make Layer 5 mechanical rather than discipline-only. Estimated effort: ~30 min (one settings.json.template edit + one live `~/.claude/settings.json` edit + a quick verification cycle). Recommended next-up after the Tranche 1.5 ship since the risk is small (script is idempotent + soft warnings) but the benefit is real (the orchestrator that wrote the rule was the same orchestrator that violated it). Added 2026-05-05.

- **HARNESS-GAP-23 — `review-finding-fix-gate.sh` reads stale `.git/COMMIT_EDITMSG` on `git commit -m` invocations** (added 2026-05-06). Surfaced during Tranche 5a authoring: the gate reads `.git/COMMIT_EDITMSG` to extract finding-ID tokens from the commit message, but on `git commit -m "..."` invocations git does NOT update `COMMIT_EDITMSG` until later in the commit cycle. Result: the gate matches against the PREVIOUS commit's message, producing false-positive blocks when the previous message contained tokens that match `<TAG>-NNN` and appeared in any review file. Reproduced 3 times in the 5a session: previous commit had token-shaped strings in its body (Tranche 6 decomposition), the next 3 commit attempts (with completely different messages, including an explicit `-F` invocation) were all blocked because the gate kept reading the stale prior message. Workaround used: write desired message to `.git/COMMIT_EDITMSG` first, then `git commit -F .git/COMMIT_EDITMSG`. Fix candidates: (a) gate sources message from `git log --format=%B HEAD@{1}` style introspection rather than the file; (b) gate explicitly handles the `-m` case by reading from environment vars git exposes during commit; (c) gate documents the workaround as a known limitation. Effort estimate: ~1-2 hours including self-test scenario for `-m`-after-tokenful-prior-commit. Priority: P2 (false positives are friction, not data loss). Risk: low (correctness-only fix). Companion to GAP-19 / GAP-22 family of "agent friction must be present-moment, not stale-state-from-prior-actions" patterns.

- **HARNESS-GAP-20 — Retrofit existing rules + agents from discipline form to mechanism form** (deferred 2026-05-06). Surfaced during the architecture-simplification arc when user asked "what else do we need to consider?" The pattern: many existing harness rules say "the LLM should do X at time Y." Convert those to: "a hook fires at time Y and does X mechanically." Examples of candidates:
  - `~/.claude/rules/orchestrator-pattern.md` "When to use orchestrator mode" — currently LLM-judges; could be a heuristic in a UserPromptSubmit hook that suggests dispatch when prompt resembles multi-task work.
  - `~/.claude/rules/planning.md` "Update SCRATCHPAD when plan status transitions" — currently LLM-discipline; converted to derived `state-summary.sh` per Path A this session, but the *rule itself* still says LLM should update SCRATCHPAD.
  - `~/.claude/rules/diagnosis.md` "After Every Failure: Encode the Fix" — discipline; could be a Stop hook that scans the session transcript for diagnosed-but-unencoded failures and surfaces them.
  - `~/.claude/rules/testing.md` various "must invoke X" disciplines — many candidates for auto-invocation hooks.
  - The 4 rules-vs-hooks splits already identified (acceptance-scenarios.md, agent-teams.md, design-mode-planning.md, testing.md) — partially captured separately.
  - Generally: every place a rule's body says "the agent must remember to..." is a candidate for mechanism conversion.
  Effort estimate: substantial (~5-10 hours of careful audit work plus per-conversion implementation; depending on how aggressively retrofitting, could be 20+ hours total). Priority: P2 — important but not blocking. Risk: low (retrofitting discipline → mechanism is structurally additive; original rules remain as documentation). Per ADR 026 ("harness catches up to doctrine") this is the long-tail of the catch-up; the architecture-simplification arc shipped the highest-leverage pieces, retrofit handles the residual. **Substantial context note:** the originating user observation 2026-05-06 was that even after Tranche 1.5 + Layer 5 + Signal 6, the orchestrator continues to make LLM-discipline-shaped fixes when blocked — every time a new failure mode surfaces, the agent's instinct is "add a rule the LLM follows" rather than "add a hook that fires automatically." The retrofit IS the systematic conversion of past LLM-discipline rules to current-best-practice mechanism form. Should NOT be conflated with new-rule-creation; the principle is "if the rule already exists, see if it can become a hook."

- **HARNESS-GAP-22 — Sweep harness for other escape-hatch flags / env-vars; remove or convert to non-LLM-satisfiable friction** (added 2026-05-06). Originated when user caught the `CLOSE_PLAN_EMERGENCY_OVERRIDE` env var I had added 2026-05-06 as a "removal of --force": *"I don't see how an env variable is any more friction to an agent than a --force flag... Just because it's loud doesn't make it rare."* Correct. Audit-logged escape hatches with rationale-length checks are not meaningfully more friction than `--force` for an LLM. Sweep candidates (non-exhaustive, per session memory): inline PreToolUse Bash blockers in `~/.claude/settings.json` already block git push --force, --no-verify, --no-gpg-sign — these are good (rejected outright, not gated). But various tooling commands the agent invokes through Bash may have --force flags that are NOT yet blocked: `git worktree remove --force`, `npm install --force`, `pip --force-reinstall`, `docker rm -f`, `git checkout --` (force-overwrite working tree), `git clean -fd`, `git reset --hard`. Each needs case-by-case judgment (worktree --force is legitimately needed when a builder crashed mid-state; npm --force is a code smell but sometimes warranted). Output: a documented inventory + rules for each. Effort estimate: ~3-5 hours of audit + per-flag judgment + selective hook additions. Priority: P2 once the immediate close-plan fix proves out. Risk: low (reversal trivial). Companion to GAP-20 (retrofit existing rules) and GAP-21 (deeper architectural review). Per the saved feedback memory `feedback_loud_is_not_rare.md`, the principle is: agent friction must be present-moment, not consequence-deferred; "loud and audit-logged" are not friction.

- **HARNESS-GAP-21 — Deeper architectural review of the harness from automation-first lens** (deferred 2026-05-06). Surfaced when user asked "what else do we need to consider to resolve this once and for all?" The architecture-simplification arc (Tranche 1.5) addressed verification overhead by building deterministic procedures; the user's observation is that even with those procedures, the orchestrator continues to exhibit LLM-discipline-shaped failures (composing summaries while artifacts are stale, using `--force` escapes, building scripts that require manual invocation). The pattern suggests a deeper architectural review is warranted — not "fix this one gap" but "what does the cleanest-possible automation-first harness design look like, and how does the current harness compare?" Possible scope: (a) end-to-end audit of every harness component against the question "does this require LLM discipline or is it mechanical?", (b) systematic redesign of any LLM-authored artifact that the next session reads (every such artifact is at risk; the deeper redesign would replace each with a derived view + clearly-bounded LLM synthesis section), (c) re-examination of the rule + agent + hook inventory through the lens "what's the minimum LLM dependence we can have here?", (d) a refreshed roadmap that sequences the harness's own ongoing development under the automation-first principle, (e) examination of cases where Claude Code's hook event surface limits what's achievable (e.g., no PostMessage hook for verbal vaporware) and what workarounds exist. Effort estimate: substantial (~20-40 hours of focused review work + drafting + deep diff against current state). Priority: P1 once Path A from this session lands (HARNESS-GAP-19 + state-summary.sh + start-plan.sh + close-plan.sh `--force` removal). Risk: low; output is paper review + roadmap, not implementation. **Substantial context note:** this is the work the architecture-simplification arc was supposed to be, but Tranche 1.5 was scoped narrowly to the verification-overhead problem because that's what was acutely painful at the time. The user's repeated observation that the orchestrator keeps making LLM-discipline-shaped fixes suggests the principle was incompletely applied — a focused review would surface the long-tail systematically rather than discovering it gap-by-gap as failures occur. Run AFTER Path A's mechanisms have shipped + been operationally validated for at least one work cycle so the review has empirical evidence to reference, not just the existing inventory.

- **HARNESS-GAP-24 — Wire propagation engine into PostToolUse to surface real-time events** (added 2026-05-09, transferred from a downstream-project findings ledger as FINDING-036). Tranche 6a shipped the propagation engine (`propagation-trigger-router.sh` + `propagation-rules.json` + JSONL audit log at `build-doctrine/telemetry/propagation.jsonl`) but NOT the PostToolUse hook that would route real-time events to the engine. Consequence observed in a downstream project's Phase B work: dozens of qualifying events (plan-status flips, decisions-index edits, finding insertions, etc.) generated zero audit-log entries during the actual work because the engine fired only when invoked explicitly. The engine therefore cannot become a measurement substrate for KIT-6 until it's wired to fire on every relevant event. Fix candidates: (a) add a single PostToolUse hook entry in `settings.json.template` matching `Edit|Write|Bash` that pipes the event JSON to `propagation-trigger-router.sh`; (b) more selective per-tool matchers that route only events the engine's rule conditions can act on; (c) defer until Tranche 6b decision settles routing semantics. Per the originating finding: "Recommendation: defer to neural-lace Tranche 6b decision." Effort estimate: ~2-4 hours including self-test scenario for "PostToolUse fires → router invoked → audit-log entry written" + verification that no propagation rule has side effects beyond log-only in v1. Priority: P2 (gates KIT-6 mechanical firing; pre-pilot infrastructure complete except this). Risk: low (rules are log-only in v1; no behavioral change beyond audit-log volume). Companion to HARNESS-GAP-19 (session-wrap.sh wiring) — both are "scripts built but not auto-invoked."

- **HARNESS-GAP-25 — Profile + optimize slow propagation rules (`pt-proven-decisions-index-update`, `pt-proven-narrative-doc-staleness`)** (added 2026-05-09, transferred from a downstream-project findings ledger as FINDING-037). Both rules exceed 1s wall time per evaluation (flagged by `analyze-propagation-audit-log.sh slow`). With 16 events tolerable; at 1000 events/day = 30 min wall time per day spent in these two rules alone. Block on promotion: do NOT advance either rule from `log-only` to any blocking action until profiled. Both rules invoke `git log` style introspection; likely fixable by (a) caching the most-recent commit's metadata across rule invocations within a single router run, (b) replacing `git log` with cheaper `git rev-parse HEAD` + `git show --stat HEAD` calls where applicable, (c) lazy evaluation guarded behind cheaper preconditions, (d) parallel rule evaluation if profiling shows the bottleneck is sequential dispatch rather than per-rule cost. Effort estimate: ~3-5 hours including profiling instrumentation + rewrite + benchmark + self-test scenario asserting wall time under 200ms per rule. Priority: P2 (gates HARNESS-GAP-24's wiring — slow rules + per-event firing = 30min/day before optimization). Risk: low (rule semantics unchanged; correctness-only rewrite). Companion to HARNESS-GAP-24 (PostToolUse wiring); resolve in tandem.

- **HARNESS-GAP-26 — Build ADR cross-reference staleness analyzer for KIT-4** (added 2026-05-09, transferred from a downstream-project findings ledger as FINDING-038). KIT-4 (ADR cross-reference staleness) is one of the seven Knowledge-Integration Triggers in `build-doctrine/doctrine/07-knowledge-integration.md`; the `/harness-review` skill Check 13 sweeps each KIT trigger but KIT-4's analyzer is a stub. With 45 ADRs in `docs/decisions/` and 5 canon artifacts that should cross-reference them (architecture-overview, harness-architecture, doctrine principles/roles/gates, etc.), manual review is impractical. Fix: build `adapters/claude-code/scripts/analyze-adr-cross-references.sh` with subcommands matching the propagation-audit-log analyzer's pattern: `summary` (count of ADRs by referenced/unreferenced status), `stale` (ADRs whose last cross-ref edit predates their `Status:` change by N days), `orphans` (ADRs with zero cross-refs in canon docs). Output feeds `/harness-review` Check 13 KIT-4 row mechanically rather than as a "(pending analyzer)" stub. Effort estimate: ~4-6 hours including script + self-test scenarios + Check 13 wiring. Priority: P2 (Check 13 already exists with the row stubbed; building this graduates one of the seven KITs from manual-only to mechanical). Risk: low (read-only script, additive). Companion to Tranche 5a-integration's analyzer pattern (same shape as `analyze-propagation-audit-log.sh`).

- **HARNESS-GAP-08** — IMPLEMENTED 2026-05-05 via `docs/plans/archive/harness-gap-08-spawn-task-report-back.md`. spawn_task report-back convention shipped: rule, surfacer hook, settings wiring, vaporware-prevention map row, sync to ~/.claude/, multi-push to both remotes. 6/6 tasks PASS, 5/5 self-test scenarios PASS. Commits: `440a2d9`, `a7002e7`, `4627e01`, `343d5c6`, `606c70e`.
- **HARNESS-GAP-13** — IMPLEMENTED 2026-05-05 via `docs/plans/archive/harness-gap-13-hygiene-scan-expansion.md`. Full original 4-layer scope: denylist additions (Layer 1), heuristic detection (Layer 2 BLOCK), `/harness-review` skill extension (Layer 3), sanitization helper (Layer 4). 8/8 tasks PASS, 13/13 hygiene-scan self-test PASS, 5/5 sanitize self-test PASS, full-tree scan ZERO matches. Commits: `2a0488a`, `517b6b6`, `6e4672c`, `2371e97`, `e03d96b`, `606c70e`.
- **HARNESS-GAP-16** — ABSORBED 2026-05-05 into `docs/plans/harness-gap-16-closure-validation.md`. Building this session in parallel with Build Doctrine Tranche 0b per user directive 2026-05-05.
- **HARNESS-GAP-17 Part A** — User-facing narrative docs stale post-Build-Doctrine-integration (~3-5 hr doc sweep). **IMPLEMENTED 2026-05-05 (this session)** — see HARNESS-GAP-17 entry below for the per-doc summary. Part B (gate extension preventing recurrence, ~6-10 hr) remains DEFERRED per original P2 estimate.
- **HARNESS-GAP-14-followups** — IMPLEMENTED 2026-05-04 via Phase 1d-G (entry below preserved as the audit trail).
- **Rules-vs-hooks 4 remaining splits** (per Phase 1d-E-2 audit) — acceptance-scenarios.md, agent-teams.md, design-mode-planning.md, testing.md. Each is substantial restructuring per rule. Per Option B 2026-05-05, now eligible to dispatch via `spawn_task` with the new GAP-08 report-back convention.
- **Doctrine-migration codename discipline** — Surfaced 2026-05-05 during Tranche 0b parallel build; see `docs/discoveries/2026-05-05-doctrine-content-codenames-vs-hygiene-scanner.md`. Future doctrine migrations from `~/claude-projects/Build Doctrine/outputs/` (private repo, real codenames) into `build-doctrine/` (NL repo, harness-hygiene rules apply) must anonymize codenames to generic placeholders before commit. Heuristic-cluster check resolved via `is_path_shape_exempt()` extension (commit `b5cdccb`); denylist scan still applies and is correct. May not need a dedicated mechanism — the discovery file + this rule callout in harness-hygiene.md may be sufficient. Reassess if a future migration produces friction; otherwise treat as resolved-by-discipline.

## Open work — telemetry-gated (don't pick up yet)

- **HARNESS-GAP-11** — reviewer-accountability tracker. Gated on telemetry (2026-08 target).
- **Phase 1d-G calibration-mimicry** — same telemetry gate.



Strategy context and reasoning for many entries below lives in [`docs/claude-code-quality-strategy.md`](./claude-code-quality-strategy.md).

## Recently implemented (2026-05-04)

These items shipped in Phase 1d-E-1 (`docs/plans/phase-1d-e-1-p1-drift-fixes.md`):

- **HARNESS-GAP-09** — `plan-reviewer.sh` Check 1 + Check 5 false-positives narrowed via section-awareness (Check 1 only flags sweep language under `## Tasks` headings) + Tier A/B context-awareness (Check 5 runtime-keyword regex requires adjacency to database-context tokens). 4 new self-test scenarios added (commit b3951ba); 26-scenario self-test suite PASS.
- **HARNESS-DRIFT-01** — Six Gen-6 hooks confirmed wired in both template and live. `automation-mode-gate.sh` was the residual missing wiring; added to live (commit b973cf5). Other settings template-vs-live divergence remains in HARNESS-GAP-14's scope.
- **HARNESS-DRIFT-02** — SessionStart + push-time account-switching hooks replaced with config-driven `read-local-config.sh match-dir` calls (commits f2d812a template + 430365c evidence + live mirror). Decision 021 records the rationale: literal-substring approach rejected per its brittleness (identity leakage, single-org assumption, code-edit-to-add-account, false-positive fall-through).

These items shipped in Phase 1d-E-2 (`docs/plans/archive/phase-1d-e-2-audit-cleanup.md`):

- **Sub-gap A of the Build Doctrine integration audit batch** — Stop-hook orthogonality audit shipped (commit fd9f663). All 5 hooks (narrate-and-wait-gate, transcript-lie-detector, goal-coverage-on-stop, imperative-evidence-linker, deferral-counter) confirmed orthogonal; 2 pairs flagged CLARIFY BOUNDARY for documentation follow-up. Audit lives at `docs/reviews/2026-05-04-stop-hook-orthogonality.md`.
- **Sub-gap B of the audit batch** — `pipeline-agents.md` deleted from global rules (commit d8b30f3). Wholly project-specific; orchestrator pattern superseded the role framing. See Decision 022 for the alternatives considered and the rationale for deletion vs. relocation/generalization.
- **Sub-gap C of the audit batch** — `claim-reviewer` post-Gen6 reassessment shipped (commit d8b30f3). Verdict: KEEP as-is. Gen 6 hooks don't fully supersede; `claim-reviewer` remains the residual mitigation for verbal vaporware until Anthropic ships a PostMessage hook event. Reassess if/when that arrives. Audit lives at `docs/reviews/2026-05-04-claim-reviewer-reassessment.md`.
- **Sub-gap F of the audit batch** — Rules-vs-hooks audit shipped (commit d8b30f3). 24 rules audited; recommendations: 1 convert-to-stub, 4 split-into-stub-plus-extension, 19 keep verbose. Restructuring is OUT-OF-SCOPE for this plan; tracked via the audit document. Audit lives at `docs/reviews/2026-05-04-rules-vs-hooks-audit.md`.
- **Sub-gap H of the audit batch** — `docs/reviews/` gitignore convention documented (commit 7abe23e). Existing `.gitignore` was already correctly designed via date-prefix allowlist (`2026-*` → tracked). Documented the convention in `harness-hygiene.md` and added a sentinel comment in `.gitignore` itself.

These items shipped in Phase 1d-F (`docs/plans/archive/phase-1d-f-definition-on-first-use.md`):

- **HARNESS-GAP-10 sub-gap G** — Definition-on-first-use enforcement shipped (commits 7f24907 + this commit). Pre-commit hook scans *.md under build-doctrine/ for first-use acronyms; blocks if undefined in glossary or in-context. See Decision 023.

These items shipped in Phase 1d-E-4 (`docs/plans/archive/phase-1d-e-4-gap-15-cleanup.md`):

- **Audit gap sub-item A — scanner self-test repair.** `harness-hygiene-scan.sh --self-test` previously asserted an exemption for `docs/plans/foo.md` that had been deliberately removed. Self-test updated to assert the opposite (exit 1 on plan files); two new assertions added for the allow-list behavior. Commit f112226.
- **Audit gap sub-item B — scanner exemption logic tightened.** Directory-level exemption for `docs/decisions/`, `docs/reviews/`, `docs/sessions/` now applies ONLY to non-allow-listed paths within those directories. Allow-listed files (`NNN-*.md`, `YYYY-MM-DD-*.md`) ARE scanned. Full-tree scan after the fix surfaces 15 codename hits in committed decision/review files — these are the pre-existing leakage tracked separately as audit gap sub-item C. Commit f112226.
- **Audit gap sub-item D — automation-mode JSON schema authored.** `adapters/claude-code/schemas/automation-mode.schema.json` was claimed in `public-release-hardening.md` Task 6.1 but never authored at v1.0 publication. Schema now live with `{version, mode, deploy_matchers}`, version: 1 sentinel matching the existing four schemas. Commit 22c0e65.
- **Audit gap sub-item E — `public-release-hardening.md` properly closed.** Plan flipped to COMPLETED with honest annotations on the four previously-unchecked tasks: Task 1.2 scoped down per Option A; Task 4.2 shipped via HARNESS-DRIFT-02; Task 5.3 deferred with rationale; Task 6.1 shipped in commit 22c0e65. Auto-archived. Plan file is gitignored (would leak codenames if committed).
- **Audit gap sub-item F — `harness-quick-wins-2026-04-22.md` properly closed.** Plan flipped to COMPLETED. Phase A Task 1 (set `effortLevel: "xhigh"` in live `~/.claude/settings.json`) deferred with rationale: per-project `effort-policy-warn.sh` covers most of the value; global default flip is a personal-cost change best done interactively. 17 of 18 tasks remain shipped. Auto-archived. Commit ff5717d.

**Audit gap sub-item C — codename scrub before next master merge.** Still deferred per the right-sized P3 remediation plan. The scanner now reports the leakage (15 hits across 5 decision/review files), so the cleanup work has a verifier when it lands.

These items shipped in Phase 1d-E-3 (`docs/plans/archive/phase-1d-e-3-gap-14-reconciliation.md`):

- **HARNESS-GAP-14** — Template-vs-live `settings.json` reconciliation shipped (commits 84a0c61 audit + 9d3c2f0 reconciliation + this commit). Six per-hook proposals authored with originating-commit + plan + architecture-doc citations; all REVERSIBLE; auto-applied per discovery-protocol decide-and-apply. Five hooks added to template (`outcome-evidence-gate`, `systems-design-gate`, `no-test-skip-gate`, force-push/`--no-verify` blocker, `check-harness-sync` composition into pre-commit-gate); one hook upgraded in live (`public-repo` blocker to elaborate `read-local-config.sh public-blocked` form). Tool-call-budget matcher tightened to `Edit|Write|Bash` to match documented form. Post-reconciliation: `settings-divergence-detector.sh` PreToolUse counts equal between template and live (template=23, live=23). Out-of-scope SessionStart + UserPromptSubmit divergences (4-6 items) flagged in audit doc as follow-up; new backlog item to track. See Decision 024. Audit lives at `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md`.

These items shipped in Phase 1d-G (`docs/plans/phase-1d-g-final-cleanup.md`):

- **HARNESS-GAP-14 sub-item C — codename scrub before next master merge.** 15 hits across 5 committed decision/review files sanitized to generic placeholders (e.g., `<personal-account>`, `<work-org-codename>`, `<product-codename-X>`). Audit-trail readability preserved; substantive content unchanged. Full-tree scanner reports zero matches after scrub. DECISIONS.md gained a footnote acknowledging the in-place scrub of records 001, 002, 013 (no status or substance changes). Commit 6881712.
- **HARNESS-GAP-14-followups** — Four out-of-scope SessionStart/UserPromptSubmit divergences reconciled. Template was canonical for all four; live `~/.claude/settings.json` was updated to match: (1) compact-recovery hook stripped of hardcoded per-project subdirectory paths, (2) automation-mode initializer SessionStart block added, (3) legacy `claude-config` harness-sync hook removed (referenced pre-rename path), (4) UserPromptSubmit title-bar upgraded from basename-only to automation-mode-aware form. Verification: `jq -S '.hooks'` of live and template byte-identical; remaining file-level divergence is confined to the per-machine `permissions` array (intentional). Commit b27ab7e.
- **Rules-vs-hooks restructuring (observed-errors-first.md convert)** — Per Phase 1d-E-2 audit's recommendation, `observed-errors-first.md` was ~80% hook-enforced; converted to stub mirroring `vaporware-prevention.md`'s pattern (short opening + classification + enforcement-map table + cross-references). 25 lines (was 74). Synced to `~/.claude/rules/` (gitignored mirror). Commit ffff6e6.

Older closed items live in plan completion reports under `docs/plans/archive/`.

## HARNESS-GAP-08 — ABSORBED 2026-05-05 into `docs/plans/harness-gap-08-spawn-task-report-back.md`

Per backlog-plan-atomicity rule, the full entry is removed from open sections at the same commit as plan creation. Audit trail of the original entry preserved in git history at the commit prior to plan creation.

---

## HARNESS-GAP-10 — Seven gaps surfaced during Build Doctrine integration analysis (added 2026-05-03)

**Source.** Build Doctrine + Neural Lace deep comparative review (plan `~/.claude/plans/build-doctrine-cheerful-hearth.md`, completed 2026-05-03). Full evidence in `docs/reviews/2026-05-03-build-doctrine-integration-gaps.md` (gitignored — content is local-only; this entry is the public pointer). Seven sub-gaps named below; each is a candidate for Phase 1d-E (harness cleanup) per the unified methodology recommendation at `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md`.

**Sub-gap A — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (Stop-hook overlap analysis).

**Sub-gap B — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (`pipeline-agents.md` relocation/restructure).

**Sub-gap C — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (`claim-reviewer` post-Gen6 reassessment).

**Sub-gap D — PARTIALLY ABSORBED 2026-05-04 into `docs/plans/phase-1d-c-3-findings-ledger.md`.** C9 ships the findings-ledger substrate (`docs/findings.md` + schema gate + bug-persistence extension) that telemetry will eventually populate. The MANUAL-WRITE path is operational starting Phase 1d-C-3 — agents/gates write findings explicitly. The AUTOMATED-EXTRACTION path (LLM-assisted finding extraction from session transcripts) remains gated on telemetry's 2026-08 target. C13 (promotion/demotion) and Phase 1d-G (calibration-mimicry, deferred) can both proceed against the manual ledger; if telemetry slips, only the automation slips.

**Sub-gap E — ABSORBED 2026-05-04 into `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md`.** C16 behavioral-contracts validator implementation includes the concrete-invariants requirement (idempotency / performance budget / retry semantics / failure modes each ≥ 30 non-ws chars + no placeholder-only content). Vacuous-filler rejection is partial in 1d-C-2 (mechanical substance check); deeper semantic validation (e.g., "idempotency must reference a specific input→output mapping") deferred to a future plan if substance check proves insufficient.

**Sub-gap F — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (Rules-superseded-by-hooks audit).

**Sub-gap G — ABSORBED 2026-05-04 into `docs/plans/phase-1d-f-definition-on-first-use.md`** (Definition-on-first-use enforcement).

**Sub-gap H — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (`docs/reviews/` gitignore refinement).

**Cross-references.**
- Full review (gitignored, local-only): `docs/reviews/2026-05-03-build-doctrine-integration-gaps.md`
- Originating analysis: `~/claude-projects/Build Doctrine/outputs/analysis/03-comparative-analysis.md`
- Methodology recommendation: `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md`
- Recovery point for the integration: tag `pre-build-doctrine-integration` at NL master HEAD, branch `build-doctrine-integration` for Phase 1d work.

---

## HARNESS-GAP-11 — Reviewer accountability is one-way (added 2026-05-03)

**Source.** Surfaced during agent-incentive-map work (`docs/agent-incentive-map.md`, plan `docs/plans/agent-incentive-map.md`). Identified as a structural weakness in NL's adversarial-pairing architecture: when a reviewer agent (code-reviewer, task-verifier, end-user-advocate, harness-reviewer, systems-designer, ux-designer, claim-reviewer, plan-evidence-reviewer) PASSes work that subsequently fails at runtime acceptance OR fails in the next session OR fails in production, no signal flows back to the agent (or to a meta-tracker) for calibration.

**Why this is a gap.** Each reviewer's incentive to be careful is purely intrinsic — there is no consequence to PASSing too easily. Over time this creates calibration drift: reviewers pass borderline work because no penalty arrives when borderline work later fails. The user observed this pattern explicitly: "I don't trust the builder agents because they seem the most willing to find workarounds in order to call their work done." The same dynamic applies to reviewers — they have a structural incentive to take builders at their word because doing so is faster and friction-free.

This is the reviewer-side analogue of the documented `claim-reviewer` self-invocation gap in `~/.claude/rules/vaporware-prevention.md` ("the single unclosed gap from Generation 4"). Both are unaccountability gaps; both reduce the harness's actual quality below its nominal quality.

**Proposed mechanism.** Reviewer-calibration tracker — a new mechanism that:

1. Records every reviewer PASS verdict to `.claude/state/reviewer-passes/<reviewer-name>-<task-id>-<timestamp>.json` with: reviewer agent name, task ID, plan path, verdict, claimed-substance summary, file:line citations made.
2. When `enforcement-gap-analyzer` fires on a runtime acceptance FAIL OR `bug-persistence-gate` fires on a session-end with bug observations OR a future production-failure signal lands, it cross-references the reviewer-passes log to identify which reviewer last said PASS on the now-failed work. Surfaces the (reviewer, failed-work) pair to a per-reviewer calibration log at `.claude/state/reviewer-calibration-<reviewer-name>.md`.
3. Periodic audit: `/harness-review` weekly self-audit (a new check) reads each reviewer's calibration log and surfaces patterns: which reviewer's PASS verdicts most often precede later failures? That reviewer's prompt or rubric needs sharpening.

**Why this is a meaty mechanism (not first-pass).** Three implementation gates:

1. The mechanism depends on `enforcement-gap-analyzer` being able to attribute the failure to specific prior reviewer verdicts. That attribution requires Phase 1d-D telemetry (see HARNESS-GAP-10 sub-gap D — telemetry not yet shipped, blocks dependent mechanisms).
2. The mechanism depends on `findings-ledger schema` (C9) shipping so that "later failure" has a structured comparable form to the PASS verdict.
3. The mechanism's value compounds with TIME — a single PASS-then-FAIL pair is noise; a pattern of N PASS-then-FAIL pairs is signal. So the mechanism needs to ship and run for weeks before the audit produces actionable findings.

**Effort estimate.** L (~12-20 hours). One JSON-write helper for reviewer-pass logging, extension to `enforcement-gap-analyzer` for cross-reference, calibration-log format design, `/harness-review` audit extension, self-test scenarios.

**Why P2 (not P1).** Calibration drift is a slow-moving structural risk; it doesn't cause individual session failures. The first-pass C-mechanisms (C10 scope-enforcement, C22 quantitative-claims, C7-DAG-waiver — already shipped) catch immediate failure modes. C1/C2/C9/C15/C16 catch upstream failure modes. The reviewer-calibration mechanism catches drift across many sessions, which only matters once the harness is running stably enough to accumulate the pattern data. Sequence after Phase 1d-C-4 (C15 ships).

**Originating context.** The user posed (2026-05-03): "Show me the incentive and I'll show you the outcome — applied to AI agents." The agent-incentive-map document catalogued each agent's stray-from patterns; this gap is the most consequential unaddressed weakness across the catalogue.

---

## HARNESS-GAP-13 — ABSORBED 2026-05-05 into `docs/plans/harness-gap-13-hygiene-scan-expansion.md`

Per backlog-plan-atomicity rule, the full entry is removed from open sections at the same commit as plan creation. Audit trail of the original entry preserved in git history at the commit prior to plan creation.

---

## HARNESS-GAP-16 — ABSORBED 2026-05-05 into `docs/plans/harness-gap-16-closure-validation.md`

Per backlog-plan-atomicity rule, the full entry is removed from open sections at the same commit as plan creation. Audit trail of the original entry preserved in git history at the commit prior to plan creation (`e9985be`).

## HARNESS-GAP-16 — Plan-closure validation gate + `/close-plan` skill (historical entry — added 2026-05-05, absorbed into plan same day)

**Source.** Surfaced 2026-05-05 from the pre-submission-audit-mechanical-enforcement plan stranding incident. The plan was Status: ACTIVE since 2026-05-03 with all 5 task checkboxes empty despite all 5 tasks' code work being shipped on master. Recovery took ~2 hours of task-verifier dispatches + commit + closure. Root cause per user: bookkeeping discipline was not followed at session end; existing pre-stop-verifier did not catch it.

**Why this is a gap.** The harness has multiple Pattern-level rules requiring closure bookkeeping (verifier mandate, "update status documents when work completes", planning.md's plan-completion checklist) but no Mechanism that REFUSES the irreversible Status: COMPLETED transition until closure is mechanically complete. Sessions can flip Status without checking all bases, and once flipped + auto-archived, the audit trail is in a final state regardless of whether bookkeeping was done.

**Proposed mechanism — two layers:**

1. **Layer 1 (~2 hr): Extend `plan-lifecycle.sh` with closure-validation gate.** When an Edit changes Status from ACTIVE to COMPLETED, run mechanical checks BEFORE the auto-archive runs:
   - All task checkboxes are `[x]` in `## Tasks`
   - For each task ID, an evidence block exists in `## Evidence Log` with `Verdict: PASS`
   - `## Completion Report` section is present with non-empty Implementation Summary, Design Decisions, Known Issues sub-sections
   - For each `Backlog items absorbed:` entry in plan header, the backlog has been reconciled (item not in open sections)
   - SCRATCHPAD.md mtime within last hour AND mentions plan slug
   
   If any check fails, refuse the Status flip with specific error listing unmet items. Pre-flight gate, not backstop — refuses forward progress until closure work is real.

2. **Layer 2 (~1.5 hr): `/close-plan <slug>` skill.** Walks the orchestrator through closure mechanically:
   - Validates which Layer 1 checks currently pass; surfaces gaps with specific actions ("invoke task-verifier on Task 3", "update SCRATCHPAD")
   - Writes the completion report from `~/.claude/templates/completion-report.md`
   - Updates SCRATCHPAD + backlog
   - Flips Status (which triggers Layer 1 + auto-archive)
   - Commits + offers to push
   
   Makes the right path easier than the wrong path.

3. **Layer 3 (already landed 2026-05-05):** `feedback_complete_plan_bookkeeping_in_session.md` memory in `~/.claude/projects/.../memory/`. Behavioral reinforcement only.

**Why pre-flight gate (Layer 1) is different from a backstop.** This isn't a mechanism catching mistakes after the fact — it's a deterministic pre-condition gate. It runs BEFORE the irreversible action (Status flip + auto-archive). It refuses forward progress until closure work is satisfied. Compare: `pre-commit-tdd-gate.sh` is a pre-flight gate (refuses bad commits), not a backstop. Same shape.

**What it doesn't catch.** Terminal-killed sessions where Stop hook never fires. For those, `plan-status-archival-sweep.sh` already catches terminal-status plans at next session start. Could also extend that sweep to flag "ACTIVE plans whose tasks are all `[x]` but Status hasn't flipped" — half-closed plans visible at next session start (~30 min add).

**Effort estimate.** ~4-5 hr for Layers 1+2. Optional half-closed-detection extension ~30 min.

**Why scheduled next-after GAP-13** (per user 2026-05-05 sequencing decision): GAP-08 + GAP-13 ship user-facing improvements (orchestrator coordination + scanner expansion). GAP-16 is structural protection against the failure mode that just consumed effort to recover. Per user: "continue with GAP-08 + GAP-13 as planned per Option B, schedule this as next-after."

**Originating context.** Stranded plan recovery 2026-05-05 (commits `588b6db` + `4e8f658` on `verify/pre-submission-audit-reconcile` branch). User's framing: "the root cause of the problem is that you're not doing your due diligence and properly updating all the documentation when you complete a plan. That's what needs to be fixed." Discipline + memory landed (Layer 3); deterministic mechanism (Layers 1+2) deferred to this entry.

**Class.** `plan-closure-not-mechanically-gated` — irreversible terminal-status transition allowed without verified closure work.

---

## HARNESS-GAP-12 — Neural-lace dual-remote sync requires manual gh-auth dance (added 2026-05-03; STATUS: IMPLEMENTED 2026-05-04)

**Resolution.** Closed 2026-05-04 via SSH multi-push configuration on origin remote. See `docs/discoveries/2026-05-04-multi-push-ssh-config-implemented.md` for the full implementation log. `git push origin <branch>` now pushes to BOTH GitHub accounts atomically via per-Host SSH keys; auth-switch hook is irrelevant for neural-lace pushes.



**Source.** Surfaced 2026-05-03 during autonomous-delivery work. The harness's `git push` PreToolUse hook in `settings.json.template` calls `read-local-config.sh match-dir "$PWD"` and switches the active gh account based on directory pattern matching. For neural-lace specifically (dual-hosted: `origin = <personal-account>/neural-lace`, `pt = <work-org>/neural-lace`), the pattern matching switches to the wrong account on push, producing 403 errors. This recurred 2+ times in the same session.

**Why this is a gap.** Neural Lace is dual-hosted by design — pushes should reach BOTH GitHub accounts so the harness stays in sync across personal and work-org. The current setup has TWO distinct problems:

1. **Auth-switch fires wrong for neural-lace.** The local config's directory→account mapping doesn't have a tiebreaker for the dual-hosted case; the matcher picks one account, but if the push targets the other account's URL, it 403s.
2. **No automated dual-sync.** Even when one push succeeds, the OTHER remote isn't updated. The maintainer must remember to manually push to both, or accept that one remote drifts.

User stated requirement (2026-05-03): "Neural Lace needs to always be kept up to date in both GH accounts. They need to stay in sync. What's the best solution that automates this and keeps us from continuing to run into this issue?"

**Proposed mechanism.** Multi-push remote configuration plus per-host credential differentiation:

1. Configure `origin` as a multi-push remote: `git remote set-url --add --push origin <pt-url>` so a single `git push origin` sends to BOTH URLs.
2. Use SSH for one URL (typically the work-org), HTTPS for the other. SSH key auth bypasses the gh-active-account dependency entirely; HTTPS auth uses gh credentials for whichever active account.
3. The auth-switch hook becomes irrelevant for neural-lace pushes (both URLs auth independently).

Alternative simpler approach: explicit `neural-lace/` → `<personal-account>` mapping in `~/.claude/local/accounts.config.json` to fix the auth-switch. Doesn't solve dual-sync; manual `git push <work-org-remote>` still needed.

**Why this matters now.** Three commits this session hit the auth-switch failure, requiring manual `gh auth switch --user <personal-account>` + retry. This is recurring friction that should be fixed structurally rather than worked around.

**Effort estimate.** S (~30-60 minutes for multi-push + SSH config). Or XS (~5 minutes) for the local-config-only patch.

**Why P2.** Friction is meaningful but not a correctness threat — pushes still happen, just with extra steps. Schedule for Phase 1d-E (harness cleanup) alongside HARNESS-GAP-10 sub-gaps.

**Originating context.** Recurred during D4-discussion of the D1-D5 educational re-do (2026-05-03). The user pushed back on the recurrence: "I thought we set things up so that you're always aware of which account to use for each repo." The setup was correct for single-hosted projects; neural-lace's dual-hosting wasn't accounted for.

---

## HARNESS-GAP-14 — IMPLEMENTED 2026-05-04 via Phase 1d-E-3 (`docs/plans/archive/phase-1d-e-3-gap-14-reconciliation.md`)

See "Recently implemented" section above for commit SHAs + Decision 024. Follow-up entry below covers out-of-scope SessionStart / UserPromptSubmit divergences.

## HARNESS-GAP-14-followups — IMPLEMENTED 2026-05-04 via Phase 1d-G (`docs/plans/phase-1d-g-final-cleanup.md`)

See "Recently implemented" section above for commit SHA (b27ab7e). All four out-of-scope SessionStart/UserPromptSubmit divergences reconciled. Audit doc updated with the Phase 1d-G addendum at `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md`.

(Historical entry preserved below.)

## HARNESS-GAP-14-followups — Out-of-scope settings divergences from GAP-14 audit (added 2026-05-04)

**Source.** Audit `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md` "Out-of-scope divergences" section. Phase 1d-E-3 reconciled the named PreToolUse hooks; the divergence-detector still surfaces remaining items in SessionStart and UserPromptSubmit hook chains.

**The remaining divergences:**
1. SessionStart compact-recovery hook — live has hardcoded per-project subdirectory paths in its backlog/plan-glob lists; template canonical (per-project paths shouldn't live in the global hook).
2. SessionStart automation-mode initializer — present in template, NOT in live; template canonical (live missed update when automation-mode shipped).
3. SessionStart legacy `claude-config` harness-sync warn hook — present in template referencing `~/claude-projects/claude-config` (predates rename to `neural-lace`). Live correctly omits; template needs path correction or removal.
4. UserPromptSubmit title-bar hook — template version reads `automation-mode` from local config and includes it in the title; live is older form (just basename). Template canonical.

**Effort estimate.** S (~30-60 min when taken up). Apply the verdicts; verify divergence-detector reports clean output.

**Why P3.** Real divergence but the in-scope reconciliation closed the higher-impact PreToolUse drift. Each remaining item is a single-line fix with an obvious canonical side.

**Originating context.** Surfaced during Phase 1d-E-3 audit as out-of-scope drift not covered by the plan's named four hooks.

---

## HARNESS-GAP-17 — User-facing narrative docs stale; docs-freshness-gate has narrative-doc blind spot (added 2026-05-05; renumbered from GAP-16 to GAP-17 on 2026-05-05 — duplicate-numbering conflict with closure-validation entry above)

**Status (2026-05-05):** Part A IMPLEMENTED in this session. All 5 narrative docs updated to reflect Gen 5/6 + Build Doctrine integration arc — README.md (Gen 5/6 + Build Doctrine highlights, Status table extended), `adapters/claude-code/CLAUDE.md` (5-mode framework + Gen 5/6 sections + Build Doctrine integration block + Counter-Incentive Discipline + Detailed Protocols expanded; live mirror synced), `docs/harness-strategy.md` (milestones for Gen 5/6 + Build Doctrine arc, security maturity table extended with anti-vaporware / narrative-integrity / spec-discipline / hygiene rows), `docs/best-practices.md` (six new pattern entries: Discovery Protocol, comprehension gate, plans as living artifacts, PRD validity + spec freeze, findings ledger, definition-on-first-use; References section expanded with all new rules + decision records), `docs/claude-code-quality-strategy.md` (Build Doctrine arc framing, generation arc up to Gen 6, mechanism stack tables extended for "Adversarial separation" / "Determinism via mechanism" with Gen 5/6 + Build Doctrine entries, Known Gaps section updated to reflect Gen 6 partial closure of verbal-vaporware gap and explicit GAP-16 plan-closure-discipline gap, References section lists decision records 011-024). Part B (gate extension) remains deferred per the original P2 estimate. Originating commit on this branch.

**Source.** Surfaced 2026-05-05 when user asked "Have we updated the documentation to reflect these updates?" Investigation revealed substantial drift between mechanism-tracking layer (current via docs-freshness-gate enforcement) and narrative/orientation layer (stale, no enforcement).

**Why this is a gap (two-part).**

**Part A — content drift.** After ~11 phases of Build Doctrine + NL integration work shipping new mechanisms (scope-gate redesign, discovery protocol, comprehension-gate, definition-on-first-use, multi-push, push-policy change, plus 12 new decision records 013-024), the user-facing narrative docs are stale by 1-2+ weeks:

- `README.md` (last touched 2026-04-29) — pre-dates entire integration arc
- `docs/harness-strategy.md` (last touched 2026-04-18) — pre-dates Build Doctrine entirely
- `docs/best-practices.md` (last touched 2026-04-27) — missing all new patterns (educational decision format, in-flight scope updates, no-waiver gate model, calibration mimicry framing, discovery protocol)
- `docs/claude-code-quality-strategy.md` (2026-04-24) — pre-Build Doctrine
- `adapters/claude-code/CLAUDE.md` (2026-04-24) — missing Counter-Incentive Discipline patterns, discovery protocol, educational-format requirement

**Part B — structural blind spot.** `docs-freshness-gate.sh` only fires on Add/Delete/Rename of hooks/rules/agents/skills. It catches structural surface-area changes but doesn't require updates to narrative docs that should propagate from those changes. The harness gained 11 mechanisms; the gate dutifully required `harness-architecture.md` preface annotations for each but didn't require the same propagation to `README.md` or `best-practices.md` because those aren't in its detection set. This is the documentation analogue of FM-023 (vaporware-spec-misunderstood-by-builder) — gates that look right on the surface but miss a class of drift.

**Proposed action — two parts.**

1. **Documentation sweep** (~3-5 hours, dedicated plan). Update the 5 stale narrative docs to reflect current mechanism state. README.md gets the highest priority since it's the public-facing first-impression artifact. Best-practices.md needs the most additions (new patterns and rationales). Strategy.md and quality-strategy.md need milestone updates. CLAUDE.md needs the Counter-Incentive Discipline + educational-format additions.

2. **Extend `docs-freshness-gate.sh` to require narrative-doc updates** when N or more hooks/rules/agents/skills change in a defined window OR when major decision records (Tier 2+) land. Mechanism: a periodic full-tree audit (could compose with `/harness-review` weekly skill) that diffs the harness-architecture.md preface chain against the README's claimed-features section and surfaces stale narrative.

**Effort estimate.**
- Part 1 (sweep): M (~3-5 hours). Pure docs work, no mechanism changes, low risk.
- Part 2 (gate extension): M-L (~6-10 hours). Heuristic detection design + integration with /harness-review.

**Why P1 for Part 1, P2 for Part 2.** Part 1 is content drift that affects every fresh user/session's first orientation; high reach, fixable with focused effort. Part 2 prevents recurrence but is structural mechanism work that should land after the initial sweep produces empirical data on what kinds of changes the gate should detect.

**Originating context.** User asked 2026-05-05: "These updates to NL are substantial. Have we updated the documentation to reflect these updates?" Quick verification confirmed the gap.

---

## Pre-existing harness drift surfaced 2026-04-27 (during agent-teams conflict analysis)

Items found while doing the Phase 1 ground-truth inventory for Agent Teams integration. Two items (P2-class) were absorbed into `docs/plans/agent-teams-integration.md` on plan creation; HARNESS-DRIFT-01 and HARNESS-DRIFT-02 were absorbed into `docs/plans/phase-1d-e-1-p1-drift-fixes.md` on 2026-05-04.

## Known gaps in current enforcement (from strategy doc, 2026-04-22)

These are residual risks in the Gen 4+ harness. Each is documented honestly rather than left hidden.

### P1 — Verbal vaporware in conversation is not mechanically blocked

Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped. When the agent makes a feature claim in conversation without citing file:line, no mechanism catches it. Current mitigation: user reflex to ask for citations. Closing requires either a PostMessage hook in Claude Code itself or an adversarial post-response review agent that fires on every Nth response.

### P1 — Tool-call-budget `--ack` attestation is bypassable

The `tool-call-budget.sh` hook looks for sentinel lines in `~/.claude/state/reviews/`. A builder agent could Write that file directly without actually invoking `plan-evidence-reviewer`. Friction is raised but not cryptographically closed. Closing requires either per-session HMAC signing or architectural support for observing Task tool invocations.

### P1 — Concurrent-session state collisions (plan-wipe incidents)

Multiple Claude Code sessions on the same machine share `~/.claude/` state and the git working tree. Uncommitted plan files have been lost to concurrent-session `git stash`/`clean` operations on multiple documented occasions (2026-04-19, 2026-04-20). A project-level plan addressing commit-on-creation is in flight, but cross-session state coordination (shared `~/.claude/` directory) is still unresolved.

### P2 — `plan-lifecycle.sh` archival staging misses content change

Surfaced 2026-04-23 (during plan #5's own self-archival, commit 93ef15d). When the Status field is edited, the hook stages a `git mv` to archive but does NOT stage the actual Status text change. Resulting commit captures the rename only; the content change sits unstaged in the working tree at the new path, requiring a manual follow-up `git add <new-path> && git commit`.

**Fix candidates:**
- (a) Hook also runs `git add <new-path>` after the `git mv` so the content change is staged together with the rename. Risk: if the new path doesn't exist yet (race condition with the rename being staged but not committed), `git add` may fail.
- (b) Hook emits a clear warning message reminding the user to `git add <new-path>` before committing. Pattern enforcement, not mechanism.
- (c) Hook moves the file via `mv` (filesystem rename) BEFORE the Edit tool's content change reaches disk, then user does `git add -A` which captures both as a single staged change. Requires hook re-architecture.

Workaround pattern (used 2026-04-23): commit twice — first commit captures the rename (zero-content change), second commit captures the Status text update. See plan #5's archival commits 93ef15d + 6f4c057.

### P1 — Concurrent ACTIVE plans need acceptance-exempt declaration before next session-end (2026-04-24)

After Phase D of `docs/plans/end-user-advocate-acceptance-loop.md` registered `product-acceptance-gate.sh` as Stop-hook position 4, two concurrent ACTIVE plans will block session end on the next session unless reconciled:

- `docs/plans/claude-remote-adoption.md`
- `docs/plans/class-aware-review-feedback-smoke-test-plan.md`

Both are harness-dev plans without a product-user surface. Per `rules/acceptance-scenarios.md`'s exemption guidance, each should declare `acceptance-exempt: true` with a substantive `acceptance-exempt-reason:` (>= 20 chars). The third concurrent plan, `end-user-advocate-acceptance-loop.md` itself, has already been declared exempt in Phase D (bootstrap meta-plan rationale).

**Fix path:** in the next session, edit each plan file's header to add the two fields. Example for `claude-remote-adoption.md`:
```
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan (Claude Code remote-mode adoption); no product-user surface to verify at runtime — the maintainer exercises the harness in subsequent sessions.
```

Until done, sessions ending while these plans are ACTIVE will hit a BLOCK with a clear remediation message from `product-acceptance-gate.sh`. Per-session waiver is also available as a fallback (`echo "..." > .claude/state/acceptance-waiver-<slug>-$(date +%s).txt`).

### P1 — `plan-phase-builder` sub-agent dispatched without Task tool — cannot invoke `task-verifier` (2026-04-23)

**Flagged for harness-reviewer 2026-04-27:** the agent-teams integration session re-encountered this gap (commits f993a83, ed42e8b, ff28441, 6cca4b8 — Phase 5 Tasks 1-4 of `docs/plans/agent-teams-integration.md`). The evidence-first fallback worked end-to-end across four builders, providing additional empirical confirmation that path (b) below is viable. Next `/harness-review` skill run should evaluate which fix to commit to.

When the orchestrator dispatches a `plan-phase-builder` sub-agent (the dispatch type used while building Phase A of `docs/plans/archive/robust-plan-file-lifecycle.md`), the sub-agent's tool surface does NOT include the Task tool — it is not in the top-level tool list and is also not surfaced via ToolSearch (`select:Task` returns no results). Consequence: the sub-agent cannot invoke `task-verifier` as instructed by both the orchestrator-pattern rule and the dispatch prompt. The builder must fall back to writing evidence blocks directly under the evidence-first protocol enforced by `plan-edit-validator.sh` + `runtime-verification-executor.sh` — which works (the harness was specifically designed to allow this path), but it conflicts with the rule's "only `task-verifier` flips checkboxes" framing. Two possible fixes: (a) ensure dispatched `plan-phase-builder` sub-agents inherit the Task tool so they can invoke `task-verifier`; (b) update `~/.claude/rules/orchestrator-pattern.md` and the dispatch-prompt boilerplate to explicitly authorize the evidence-first fallback when Task is unavailable, with a written rationale. Either way, the current mismatch between the rule and the runtime tool surface should be reconciled. Reference instances: original Phase A build (commits d2d1494 + 4cc9c2a on `feat/robust-plan-file-lifecycle`); agent-teams integration Phase 5 Tasks 1-4 (commits f993a83, ed42e8b, ff28441, 6cca4b8 on master, 2026-04-27).

## Improvements surfaced by a downstream plan-staleness sweep (2026-04-24)

Seven structural gaps that allowed ~22 ACTIVE plans to accumulate across two sibling project repos without any enforcement firing. Each entry is named HARNESS-GAP-NN for cross-reference. Surfaced during a Q&A session that hit the `product-acceptance-gate.sh` Stop hook in storm — the gate fired, the user asked "why are so many plans considered done without everything checked off?", and these are the answers.

### HARNESS-GAP-01 — `pre-stop-verifier.sh` doesn't block terminal-Status flips with unverified tasks

`pre-stop-verifier.sh` blocks "checked tasks without evidence blocks" AND "unchecked tasks AND `Status: ACTIVE`." It does NOT block "terminal Status (`COMPLETED` / `DEFERRED` / `ABANDONED` / `SUPERSEDED`) AND unchecked tasks AND no evidence block names them shipped." Consequence: the cleanup move (flip Status to clear the gate) silently legitimizes whatever checkbox state is in the file — the precise pattern that produced a downstream plan-staleness sweep. Proposed fix: add Check 4d to `pre-stop-verifier.sh` that requires every unchecked task in a terminal-Status plan to either (a) have an evidence block claiming it shipped, or (b) appear in an explicit "Tasks deferred to Phase 2 / out of scope" section in the closing note.

### HARNESS-GAP-02 — No git-log → plan-checkbox correlation

A commit that touches files in a task's `Files to Modify/Create` list could plausibly satisfy that task, but no hook reads the diff, finds the matching task, and surfaces "this commit may satisfy Task X.Y in plan Z — invoke task-verifier?" Sync is one-way: builder must remember. If the builder errors, exits, or work goes through any non-orchestrator path (manual fix, hotfix, kanban-engine direct commit), the link is never formed. Proposed fix: PostToolUse hook on Git commits that scans the commit's diff against `docs/plans/*.md` ACTIVE plans' file lists and emits a non-blocking surface message naming the candidate tasks. User or next session can act on it.

### HARNESS-GAP-03 — Auto-generated kanban plans bypass task-checkbox enforcement

Plans created by `kanban-engine.yml` from GitHub Issues have task lists that read "(The build agent will investigate, diagnose, and implement autonomously.)" — i.e., 0 checkboxes by design. The verification model assumes plans have task lists. Kanban plans don't, so `pre-stop-verifier`'s "unchecked tasks" check is vacuously satisfied — but there's also no positive signal that the work shipped. The kanban plan can sit at `Status: ACTIVE` indefinitely while the underlying GitHub Issue is closed. Proposed fix (two parts): (a) `Status: ISSUE-TRACKED` sentinel that exempts kanban plans from task-checkbox enforcement and treats issue-close as the verification, (b) periodic Routine that scans kanban plans whose source issue is CLOSED and auto-flips Status: COMPLETED.

### HARNESS-GAP-04 — Reactive audit, not preventive

a downstream plan-staleness sweep exists in the backlog because the `product-acceptance-gate.sh` Stop hook started failing loudly enough that someone noticed 22 stale plans. There's no scheduled "weekly plan-audit" Routine that surfaces stale plans before they accumulate. By the time you see drift, you have 22 plans to triage, the sweep takes hours instead of minutes, and the user's confidence in the gate erodes. Proposed fix: weekly `/schedule` Routine that lists every plan with `Status: ACTIVE` for >14 days where the most recent commit touching `docs/plans/<slug>` is >7 days old. Output goes to `docs/reviews/YYYY-MM-DD-plan-staleness-audit.md` so it's actionable at human scale.

### HARNESS-GAP-05 — Status-audit sub-agents conflate "code shipped" with "feature works"

When a research / status-audit sub-agent reports on a plan (e.g., "the roadmap is functionally complete"), the agent typically correlates checkbox state with git log — both static signals. It does NOT exercise the feature at runtime. The `end-user-advocate` exists for runtime verification but is not invoked by status-audit agents by default. Result: a plan can be reported "done" based on artifacts that exist on disk, without anyone ever confirming a real user can use the feature. Proposed fix: either (a) extend `task-verifier`'s verdict shape to distinguish `evidence: artifact-only` from `evidence: runtime-PASS` and require runtime evidence for any task whose `Done when:` criterion involves user-observable behavior, OR (b) add a rule that any agent reporting "this plan is done" must call out which checks were performed and which were skipped, in a structured `## Verification Coverage` block.

### HARNESS-GAP-06 — No first-class `Status: PENDING-REVIEW` for "code shipped, human QA pending"

The current terminal Status taxonomy (`COMPLETED`, `DEFERRED`, `ABANDONED`, `SUPERSEDED`) lacks an honest label for the very common state "the engineering work shipped but the user hasn't yet exercised it to confirm the build matches their expectation." Sessions are forced to choose: leave Status: ACTIVE (gates fire forever) or flip COMPLETED (loses the "I haven't actually tried this yet" signal). Workaround in the surfacing project: pair `Status: COMPLETED` with `MANUAL-QA-<plan-slug>` backlog items.

Proposed fix: real `Status: PENDING-REVIEW` sentinel honored by the harness — plan auto-archives like other terminal statuses, but session-end gate emits a non-blocking reminder listing pending-review plans the user should triage. The sub-status `PENDING-REVIEW` ages out into `COMPLETED` after explicit user sign-off (or `DEFERRED` if QA found regressions).

**User-supplied requirements (refined 2026-04-24):**

1. **MUST NOT block continued progress.** A plan in `PENDING-REVIEW` does NOT trigger acceptance gates, does NOT gate session end, does NOT gate dispatch of new builders, does NOT block other plans from being created or worked. The only signal is informational. Specifically: `product-acceptance-gate.sh` must treat `PENDING-REVIEW` as equivalent to `acceptance-exempt` for blocking purposes; `pre-stop-verifier.sh` must treat `PENDING-REVIEW` as a terminal status for completion-check purposes.

2. **Persistent roadmap-level + plan-level overview.** A dashboard (or session-start surface) that shows what's pending review at both levels:
   - **Plan level:** within a plan file, individual tasks could carry per-task review state (`- [x] Task 1 (PENDING-REVIEW)` vs `- [x] Task 1 (REVIEWED 2026-04-25 by user)`). Lets the user know which specific tasks within a plan they've actually verified.
   - **Roadmap level:** a Routine or skill that scans all plans (active + archived) and produces a dashboard at `docs/reviews/<date>-pending-review-dashboard.md` (or surfaces in SCRATCHPAD on session start). Lists every plan currently in `PENDING-REVIEW` with a one-line summary of what's awaiting verification and how long it's been waiting. Roadmap docs (like `an active project roadmap doc`) should be able to query this state inline.

3. **Sign-off discipline.** The transition `PENDING-REVIEW` → `COMPLETED` requires an explicit user-attributed reviewed-by/reviewed-on annotation in the plan or a companion review file. Prevents the agent from silently flipping it on the user's behalf.

4. **Roadmap-aware archival.** Plans that are owned by an active roadmap (e.g., `an active project roadmap doc`) should not auto-archive on `PENDING-REVIEW` — they stay reachable from the roadmap until the user signs them off and the roadmap itself updates the link. Otherwise the user loses the "where are we on the roadmap" overview that the roadmap doc is supposed to provide.

These requirements push HARNESS-GAP-06 from a small Status sentinel to a small subsystem (status semantics + dashboard generator + review annotations + roadmap-awareness). Scope it as a multi-phase plan when picking up. P1.

### HARNESS-GAP-07 — `plan-lifecycle.sh` doesn't recognize YAML frontmatter Status

Surfaced 2026-04-24 during a downstream plan-staleness sweep Phase 1 closures. The hook's awk pattern `/^Status:[[:space:]]*[A-Za-z][A-Za-z0-9_-]*/` matches only the standard `Status: ACTIVE` line at the top of a plan. It does NOT match YAML frontmatter format where the field is `status: ACTIVE` (lowercase) inside a `---` block. Reference instance: a kanban-engine-generated plan in a downstream project had to be manually `git mv`'d to archive because flipping its YAML frontmatter `status:` to `COMPLETED` did not trigger the hook. Two fix options: (a) extend the hook's awk pattern to also recognize YAML frontmatter `status:` lines (case-insensitive), OR (b) add a pre-commit hook (`plan-format-normalizer.sh`) that detects YAML frontmatter plans and either rewrites them to standard format or refuses the commit with a message pointing at the standard. Option (a) is non-invasive but legitimizes two formats; option (b) forces consistency. Light P2 — rare format outside the kanban-engine pipeline, but the inconsistency surprises operators when archives don't auto-fire.

### HARNESS-GAP-08 — No `Status: REFERENCE` for index/roadmap docs in `docs/plans/`

Surfaced 2026-04-24, recurring 2026-05-06. The Status taxonomy (`ACTIVE` / `COMPLETED` / `DEFERRED` / `ABANDONED` / `SUPERSEDED`) has no honest label for docs that live in `docs/plans/` but are NOT units of work — they're indexes, roadmaps, or reference material that point AT the actual plans. Reference instance: a downstream project has a roadmap doc at `docs/plans/<roadmap-name>.md` (0/0 task list) that tracks 6 workstream plans. With `Status: ACTIVE` it triggers `product-acceptance-gate.sh` (no PASS artifact ever exists) and pollutes the active-plan view at session start. With `Status: COMPLETED` it auto-archives away from active reach. The user explicitly wants such docs accessible AS reference, not closed. Three fix options: (a) `Status: REFERENCE` sentinel that exempts from acceptance gate + plan-staleness sweeps + auto-archival, while keeping the file at top-level `docs/plans/`; (b) introduce a `docs/roadmaps/` directory that's not gated; (c) accept the inconsistency and document as Pattern that operators avoid putting reference docs in `docs/plans/`. Option (a) is most expressive — orthogonal status field for "is this a unit of work?" — but adds complexity. Option (b) is cleaner architecturally; requires migrating existing roadmap docs. Light P2; mostly affects operators with concentrated multi-plan campaigns (audit campaigns, large refactors). The 14-plan PLAN-SWEEP-01 Phase 2 on a downstream project (2026-05-06) had to skip 1 ACTIVE plan that was a roadmap doc, surfacing the gap a second time.

## Improvements surfaced by 2026-04-22 strategy review

Prioritized order of leverage. Full reasoning in `docs/claude-code-quality-strategy.md` section "Additional Suggestions for Improvement."

### P0 — Harness-tests-itself: synthetic session runner

Build a tool that runs synthetic Claude Code sessions against known-bad scenarios and measures whether hooks catch them (unauthorized checkbox flip, mocked integration test, uncited feature claim, budget exhaustion without audit). Runs on demand or weekly via `/schedule`. Produces a report showing which enforcement mechanisms have regressed. This catches silent enforcement regressions — currently invisible.

### P2 — Claude Code doesn't dynamically load new agents OR hooks added mid-session

Surfaced 2026-04-23. Two confirmed instances of the same root cause:

- **Agents:** the `plan-phase-builder` agent file exists at both `~/.claude/agents/plan-phase-builder.md` and `adapters/claude-code/agents/plan-phase-builder.md`, but a session that started before the file was added returns "Agent type 'plan-phase-builder' not found" when invoked via the Task tool. Workaround: use `general-purpose` agent with orchestrator-pattern discipline inlined in the prompt.
- **Hooks:** the `plan-deletion-protection.sh` hook was registered via `jq` into `~/.claude/settings.json`'s PreToolUse Bash matcher mid-session. A subsequent `rm docs/plans/dpc-test.md` (which the hook should BLOCK per its self-test scenario 1) was NOT blocked — the file was deleted with exit code 0. The hook's `--self-test` passes 14/14 in a fresh subprocess invocation, proving the hook logic is correct. The session simply isn't aware of the new hook registration. Workaround: end and re-start the session (or rely on next-session activation, which is acceptable for non-urgent enforcement additions).

Mitigation candidates:
- (a) Document the limitation in `harness-maintenance.md` so future Claude sessions know to restart after adding new agents.
- (b) SessionStart hook that re-scans `~/.claude/agents/` and writes a "missing agents" warning if any expected agent isn't loaded — surface staleness without forcing a restart.
- (c) Investigate whether Claude Code has an agent-reload command; if so, document it.

Low priority because the workaround (general-purpose dispatch with inlined discipline) is functional and the issue resolves on next session start.

### P1 — Class-aware reviewer feedback Mod 2: pre-commit class-sweep attestation hook

Deferred from the original bundled "Class-aware reviewer feedback (narrow-fix bias mitigation)" entry on 2026-04-23. Mods 1 + 3 of that entry are absorbed by the `class-aware-review-feedback` plan. Mod 2 stays in the backlog pending evidence that Mods 1+3 alone don't fully close the narrow-fix-bias pattern.

**Pattern this would address:** adversarial reviewers identify named instances; LLM builders fix the named instances; sibling instances of the same defect class slip; next pass surfaces a sibling; loop. Surfaced across 5 `systems-designer` iterations on the `capture-codify-pr-template` plan (2026-04-23). Affects every adversarial-review loop in the harness.

**Proposal:** New PreToolUse hook `class-sweep-attestation.sh` (matching `git commit`) that detects fix-commits — message contains "amend" / "fix" / "address review" AND a prior reviewer FAIL exists in `~/.claude/state/reviews/`. Requires the commit message to include a `Class-sweep: <pattern> — N matches, M fixed` line. Blocks commit otherwise. Estimated effort: ~6 hrs (with self-test); existing `bug-persistence-gate.sh` is a good template.

**Trigger to revive:** if after `class-aware-review-feedback` ships, an adversarial-review loop still produces 3+ rounds of FAIL where each round surfaces a sibling instance of a defect class the prior round was supposed to address, that's the signal to ship Mod 2. Until then, the prose-layer interventions (Mod 1 + Mod 3) are believed sufficient.

### P1 — Verify class-aware reviewer feedback in next session (live agent invocation) (2026-04-23)

The `class-aware-review-feedback` plan completed Task A.10 with the smoke-test fixture at `docs/plans/class-aware-review-feedback-smoke-test-plan.md` and a sweep-query verification (9 matches against the seeded class), but could NOT live-invoke the modified `systems-designer` agent because (a) sub-agents dispatched as `plan-phase-builder` lack the Task tool (P1 above), and (b) agent definitions are loaded at session start, so in-session prompt edits don't activate until the next session (P2 below). Next-session work: invoke the modified `systems-designer` agent on the smoke-test fixture (or a fresh equivalent) and verify the agent output contains the six-field block structure (`Line(s):`, `Defect:`, `Class:`, `Sweep query:`, `Required fix:`, `Required generalization:`) for at least the seeded `generic-placeholder-section` defect class. Compare the agent's emitted sweep query against the expected sweep query in the evidence file's section C. If the agent does NOT reliably emit the six-field structure, that's the signal to either tighten the prompt language or escalate to Mod 2 (the pre-commit `class-sweep-attestation.sh` hook above). After verification, the throwaway smoke-test fixture file can be deleted.

### P1 — Prompt template library for meta-questions

Codify canonical meta-questions as slash commands or skills: `/why-did-this-bug-slip`, `/find-my-bugs`, `/make-this-plan-verbose`, `/harness-this-lesson`. Currently these patterns live in individual memory; codifying makes them reusable and consistent.

### P1 — Delegability classification on plan tasks

Every plan task declares: fully-delegable / review-at-phase / interactive. Shapes dispatch automatically — fully-delegable auto-dispatches to background sessions, review-at-phase produces PRs at phase boundaries, interactive stays in foreground. Replaces per-task manual routing decisions.

### P1 — Explicit interactive vs autonomous session mode

Session-start directive declaring interactive (human watching; more permissive) or autonomous (human not watching; stricter gates, auto-commit plans, harder enforcement). Same cadence shouldn't apply to both modes.

### P2 — Effort-level enforcement at project level

`.claude/minimum-effort.json` in project root declares minimum effort level. SessionStart hook warns if effort is below project minimum. Eliminates "forgot to set max" errors on quality-critical projects.

### P2 — Multi-model routing strategy

Codify model assignment per task type: Opus for planning/adversarial review/judgment; Sonnet for implementation; Haiku for mechanical operations. Partially done via individual agent frontmatter; could be more systematic via a central routing config.

### P2 — Scheduled retrospectives via `/schedule`

Weekly scheduled agent that reads the week's completed plans, decisions, and failure-mode entries; proposes harness improvements based on patterns; drafts `docs/retrospectives/YYYY-WW.md`. Turns ad-hoc "half my time on the harness" into systematic weekly attention.

### P2 — Session observability dashboard

Lightweight `claude-status` command aggregating active sessions (local + `--remote`), active plans, tool-call budget consumption, recent hook firings, uncommitted work at risk of wipe. Aggregates existing state files — no new infrastructure needed.

### P2 — Harness version contracts

Each project declares `harness-version: >=N` in its CLAUDE.md. Breaking harness changes bump the version. SessionStart warns if project version predates current harness. Prevents silent regressions as harness evolves beyond what older projects expected.

### P2 — Validate Decision 011 Approach A end-to-end via real `claude --remote` session (2026-04-23)

Plan #4 (`docs/plans/claude-remote-adoption.md`) Phase B set up Approach A on a reference downstream project (a small work-account demo repo on GitHub) — `.claude/` directory exists in that project's working tree with the harness committed-copy form per Decision 011, but the `git commit` and `git push` were deferred because the reference repo had no configured user identity and the builder did not have authority to set it.

Required user action:
1. From the reference project's directory: confirm the appropriate git identity is set (one-time per-machine), then `git add .claude/ && git commit -m "chore: adopt Neural Lace harness via project .claude/ (Decision 011 Approach A)" && git push`.
2. Launch `claude --remote "list every rule loaded for this session and confirm any one hook fires"` against the reference project's pushed branch.
3. Confirm: (a) cloud session enumerates the rules in `.claude/rules/` matching the local set, (b) at least one hook from `.claude/settings.json` fires during the session, (c) `task-verifier` agent is dispatchable from the cloud session.
4. If any of (a)/(b)/(c) fails, file the failure mode against Decision 011 — Approach A may need refinement (e.g., symlink fallback, settings.json adjustments for cloud).

This is the integration test referenced in Decision 011's Test Plan section, and the empirical validation deferred from Phase A.



### P1 — Mysterious `effortLevel` wipe during session (2026-04-22/23)

Observed: `~/.claude/settings.json` started the session with `effortLevel: "max"`. Partway through, a subsequent `jq -r '.effortLevel'` returned `null` (key removed or value nulled). No task in the executing plan intentionally touched this field. Neither the main session nor any dispatched builder agent reported editing it.

Plausible causes:
- A PreToolUse or PostToolUse hook silently normalizing settings.json (e.g., a JSON rewriter that drops unknown keys)
- A concurrent session on the same machine overwriting settings.json with an older version (the concurrent-session state collision pattern we already have logged)
- An `install.sh` re-run during the session restoring from a template that had the key but was processed incorrectly
- A tool call with a full-file Write to settings.json that didn't preserve the effortLevel field

Remediation needed:
- Audit every hook that reads/writes `~/.claude/settings.json` for normalization that could drop top-level keys
- Consider adding a SessionStart hook that snapshots `settings.json` to `~/.claude/state/settings-snapshot.json` and, on next SessionStart, diffs against the current file to surface silent mutations
- Document the root cause once identified, then add a test/guard

Until fixed: users should periodically check `jq -r '.effortLevel' ~/.claude/settings.json` is not `null`. The existing `effort-policy-warn.sh` hook catches this indirectly (will warn if env var is unset and settings is missing the key AND policy requires non-low).

### P1 — Harness-work plans have no tracked home

Per `harness-hygiene.md`, the harness repo adds `docs/plans/` to `.gitignore` (harness repos don't ship instance artifacts). But harness-dev work DOES produce plan files, and those plans have no naturally-tracked home:

- `neural-lace/docs/plans/` — gitignored; plans there survive locally but aren't protected from `git clean`
- `~/.claude/plans/` — outside any git repo; plans there survive git operations anywhere but aren't version-controlled or shareable

Encountered 2026-04-22: wrote `harness-quick-wins-2026-04-22.md` to `neural-lace/docs/plans/`, hit the `.gitignore` at commit time, moved to `~/.claude/plans/` which is outside any repo.

Options to resolve:
- **Separate harness-dev repo:** e.g., `neural-lace-dev` or similar, tracking only the working plans/decisions/sessions for harness evolution. Isolates instance artifacts from shareable harness code.
- **Carve-out within neural-lace:** a `docs/internal-plans/` (not gitignored) specifically for harness-dev plans. Weakens the hygiene guarantee (contributors may leak identifiers), requires reviewer vigilance.
- **Accept `~/.claude/plans/`:** formalize this as THE location for harness-dev plans. Add a README there explaining the convention. Plans are local-only by design; cross-machine collaboration requires explicit git init + separate repo setup by the contributor.

Recommendation pending: option 3 (accept local-only) is cheapest and matches actual practice. Options 1-2 are correct for a growing contributor base.

### P2 — Bug-persistence gate should recognize cross-repo persistence

The `bug-persistence-gate.sh` hook scopes its check to the current project's `docs/backlog.md` or `docs/reviews/`. When trigger phrases reference harness-level concerns and persistence legitimately happens in the neural-lace repo, the hook still fires against the project cwd.

Two possible fixes:
- **Harness-aware scoping:** check both the current project's `docs/` AND `~/claude-projects/neural-lace/docs/backlog.md` when trigger phrases reference harness concerns (would require classifying trigger phrases as project-level vs harness-level)
- **Cross-repo persistence attestation:** explicit sentinel file (e.g., `.claude/state/persisted-elsewhere-<hash>.txt`) carrying the commit SHA of the cross-repo persistence; similar to the existing `--ack` pattern

Workaround pattern (used 2026-04-22): write a dated review file in the current project's `docs/reviews/` that points at the authoritative persistence location. Works but requires the agent to remember to do it.

### P2 — Pre-existing harness-mirror drift between `~/.claude/` and `adapters/claude-code/` (surfaced 2026-04-24)

While building the failure-mode catalog plan (`docs/plans/failure-mode-catalog.md`), the harness-maintenance diff loop surfaced 25 pre-existing files that DIFFER between `~/.claude/` and `adapters/claude-code/`, plus 4 files MISSING from the repo. The drift is unrelated to the catalog plan and was already present at branch base. Affected categories: 7 agents, 11 rules, 7 hooks/skills/templates. Until reconciled, the harness-maintenance diff loop produces a noisy baseline that masks new drift.

**Fix:** dedicated reconciliation pass — for each DIFFERS file, decide which side is canonical (the live `~/.claude/` typically reflects the most recent thinking) and re-mirror. For the 4 MISSING files (`templates/completion-report.md`, `templates/decision-log-entry.md`, `skills/pt-implement.md`, `skills/pt-test.md`), copy to the repo. Then the diff loop returns clean and any future drift is immediately visible.

### P2 — capture-codify: detect FM-NNN-cited-but-doesn't-exist (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 6 ("Observability gaps"). Currently when a PR's mechanism field selects answer form (a) "Existing catalog entry" and cites `FM-NNN`, neither the CI workflow nor the local pre-push hook checks whether `FM-NNN` actually exists in `docs/failure-modes.md` at PR open time. A typo (`FM-001` vs `FM-100`) or a stale citation slips through silently — the PR passes the validator but the cite is dangling.

**Proposal:** extend the validator library (`.github/scripts/validate-pr-template.sh`) to optionally cross-reference any `FM-\d+` substring in the (a) section against `docs/failure-modes.md` headings (`^## FM-\d+`). On miss, emit a soft warning (`[pr-template] WARN: cited FM-NNN not found in catalog`) without failing the check — reviewer responsibility for now, but the warning makes the gap visible. Hard-fail later if false-positive rate is low.

**Effort:** ~1 hour (single regex addition, self-test cases for hit/miss/no-cite). Existing validator structure makes this trivial.

### P2 — capture-codify: answer-form distribution telemetry (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 6. The mechanism field has three answer forms (a / b / c). Tracking the distribution over time would surface meaningful patterns: a sudden spike in (c) "no mechanism" answers signals discipline drift; a steady stream of (b) "new entry proposed" with no follow-up catalog growth signals a broken capture-codify cycle.

**Proposal:** extend `adapters/claude-code/scripts/audit-merged-prs.sh` to count (a/b/c) selections per PR and emit a distribution summary alongside the per-PR PASS/FAIL output. Optionally feed the counts into the weekly `/harness-review` skill's compliance section.

**Effort:** ~2 hours. The validator library already detects answer-form selection in `detect_answer_form()`; surfacing it from the audit script is a single counter loop.

### P2 — capture-codify: pre-commit atomicity gate for template ↔ validator edits (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 7 (failure-mode row "Accidental template-file edit"). The validator library expects specific section headings and placeholder text in `.github/PULL_REQUEST_TEMPLATE.md`. If a maintainer edits the template (e.g., changes wording while editing nearby files) without updating the validator's regex constants, the validator silently breaks — the next PR after the edit fails CI unexpectedly with a confusing message.

**Proposal:** new pre-commit hook `template-validator-atomicity-gate.sh` that detects when `.github/PULL_REQUEST_TEMPLATE.md` is staged AND `.github/scripts/validate-pr-template.sh` is NOT staged in the same commit; blocks with a stderr message naming the rule. Mirror of the existing `decisions-index-gate.sh` atomicity pattern.

**Effort:** ~3 hours. Existing atomicity gate (`decisions-index-gate.sh`) is a direct template; copy + adapt regex + write self-test.

## Existing entries

## ✅ DELIVERED 2026-04-20 — Mechanical enforcement of bug-persistence rule

Shipped in commit `0090d4b`: `hooks/bug-persistence-gate.sh` Stop hook wired into `settings.json.template`. Scans session transcript for trigger phrases, checks `docs/backlog.md` + `docs/reviews/` for persistence, blocks session end if bugs mentioned without being recorded. Attestation escape hatch via `.claude/state/bugs-attested-*.txt`. Documented in `docs/harness-architecture.md`.

## P1 — Consolidated findings rollup on session end

Related to the bug-persistence hook: a skill or helper that, at session end, reads all `docs/reviews/YYYY-MM-DD-*.md` files + recent git log for `docs/backlog.md` changes, and produces a single `docs/sessions/YYYY-MM-DD-session-summary.md` cataloging every finding + its disposition (fixed in commit X / deferred to backlog entry Y / invalid).

## P1 — Hardening of existing self-applied rules

Several rules in `~/.claude/rules/` are Pattern-level (no hook enforcement) and depend on agent discipline. Audit them for which ones are violated most often in practice, and propose Mechanism-level enforcement (hook / schema / assertion) for the top offenders. Candidates from observation:

- `planning.md`'s "Identifying a gap = writing a backlog entry, in the same response" — violated on 2026-04-20
- `orchestrator-pattern.md`'s "Main session dispatches, doesn't build directly" — violated when main session is tempted by small edits
- `testing.md`'s "E2E testing after system-boundary commit" — often skipped when under time pressure

## P0 — Stop hook for "narrate-and-wait" pattern (new 2026-04-21)

Counterpart to bug-persistence-gate: catch the pattern where the agent
completes a unit of work, narrates a summary, and implicitly stops
waiting for user confirmation. Specifically blocks session termination
when the last N assistant turns contain trigger phrases like "next up
is", "ready to continue", "want me to proceed", "after merge", "then
I'll" — indicating the agent has queued up work it could be doing now
but is pausing to announce.

Scope ~3 hrs: Stop hook script, transcript regex, allowlist for genuine
end-of-session summaries (e.g., "done for tonight", explicit /clear
requests, explicit "stop" from user).

This was added after the maintainer repeatedly observed the agent
stopping mid-execution on 2026-04-21 and asking rhetorical "are you
still working?" questions.

---

## HARNESS-GAP-15 — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-4-gap-15-cleanup.md` (sub-items A/B/D/E/F; sub-item C deferred to next master merge)

(Historical entry preserved below for context.)

## HARNESS-GAP-15 — Phase 1d-E public-release-hardening + harness-quick-wins audit-cleanup (added 2026-05-04)

**Source.** 2026-05-04 stale-plan audit. Three plans were marked COMPLETED but two had falsely-complete state (the third — `document-freshness-system.md` — verified ACTUALLY COMPLETE and stays archived). The two that were prematurely marked are now flipped back to ACTIVE; this gap aggregates their resolution paths with related Phase 1d-E hygiene work into a single rollup so they ship as one focused phase.

**Sub-items (P2 unless noted):**

**A — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit f112226). Scanner self-test repaired; assertion flipped to exit 1 on `docs/plans/foo.md`; two new assertions added for the allow-list behavior. Self-test PASS today.

**B — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit f112226). Scanner exemption tightened: directory-level exemption applies ONLY to non-allow-listed paths within `docs/decisions/`, `docs/reviews/`, `docs/sessions/`. Committed allow-listed files (`NNN-*.md`, `YYYY-MM-DD-*.md`) ARE scanned. Full-tree scan after the fix correctly reports 15 codename hits in committed decision/review files — these are the pre-existing leakage tracked in sub-item C below.

**C — Codename scrub from feature-branch commits before next master merge (P2, deferred).** Public feature branches currently contain identifying codenames + the maintainers GitHub usernames in tracked decision/review files. Specific identifiers redacted from this entry per the hygiene-scan denylist; see the 2026-05-04 audit conversation transcript for the actual strings. **Right-sized severity: P3 distribution-readiness/hygiene concern, NOT a security incident** — no credentials/tokens/secrets in the leak; identity-correlation already trivially derivable from public commit author fields. Cleanup approach: at next master-merge time, scrub the merging diff of identifiers OR rebase the merging branch through orphan-commit (Phase 8 pattern). Force-pushing the public feature branch is rejected per the right-sized threat model — unnecessary urgency. Effort: ~1 hr per merge; integrates with normal merge workflow.

**D — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit 22c0e65). Schema authored at `adapters/claude-code/schemas/automation-mode.schema.json` per the original Task 6.1 spec — `{version, mode, deploy_matchers}` with version: 1 sentinel matching the existing four schemas. Validates against the example.json that already shipped.

**E — IMPLEMENTED 2026-05-04 via Phase 1d-E-4.** `public-release-hardening.md` flipped to COMPLETED; auto-archived. Honest annotations on the four previously-unchecked tasks: 1.2 scoped down per Option A; 4.2 shipped via HARNESS-DRIFT-02; 5.3 deferred with rationale; 6.1 shipped in commit 22c0e65. Plan file is gitignored, but the audit closure section is preserved in working tree.

**F — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit ff5717d). `harness-quick-wins-2026-04-22.md` flipped to COMPLETED; auto-archived. Phase A Task 1 deferred with rationale: per-project `effort-policy-warn.sh` covers most of the value; global default flip is a personal-cost change that should happen interactively. 17 of 18 tasks remain shipped.

**G — Phase 1d-E rollup (HARNESS-GAP-14 + HARNESS-GAP-15 + HARNESS-GAP-10 sub-gaps A/B/C/F/G/H + HARNESS-GAP-13).** When Phase 1d-E is planned, bundle these into a single coherent plan so the audit-cleanup work ships as one phase with one shared verification pass.

**Effort estimate.** S-M for A/D/F individually; M for B (depends on what new findings the tightened scanner surfaces); incremental cost for C (zero now, ~1 hr at next merge); A+B+D+E+F together: ~4-6 hr of focused work. G is the planning step, ~30 min.

**Class.** `falsely-marked-complete-plan` (sub-class of `stale-state-claim`). The 2026-05-04 audit caught the pattern; the resolution path here closes the specific instances + restores the post-conditions the plans claimed.

**Cross-references.**
- Audit findings: this session's transcript (2026-05-04 conversation about stale plans)
- The two un-archived plans: `docs/plans/harness-quick-wins-2026-04-22.md`, `docs/plans/public-release-hardening.md`
- The third plan (verified complete, stays archived): `docs/plans/archive/document-freshness-system.md`
- Companion gaps: HARNESS-GAP-14, HARNESS-GAP-13, HARNESS-GAP-10 sub-gaps A/B/C/F/G/H
