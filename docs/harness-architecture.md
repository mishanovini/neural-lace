# Claude Code Harness — Architecture Inventory

<!-- GENERATED FILE — do not hand-edit. Regenerate with:
       bash adapters/claude-code/scripts/gen-architecture-doc.sh
     Source of truth: adapters/claude-code/manifest.json.
     Doctor predicate (drift = RED): tests/fixtures/wave-f/F.2/doctor-predicate.md -->

For the pre-generation narrative history (mechanism-by-mechanism changelog
back to Gen 4, preserved verbatim), see [`harness-architecture-history.md`](harness-architecture-history.md).
For the Tier-3 unified narrative (team-role analogy + layer cross-walk), see
[`architecture-overview.md`](architecture-overview.md). This file is the
Tier-4 exhaustive machine-derived inventory.

## Summary

| Metric | Count |
|---|---|
| Total manifest entries | 138 |
| Unique hook scripts | 116 |
| Blocking gates (`blocking: true`) | 38 |

## Hooks by event

One row per (entry, event) pair — an entry wired to N events appears N times, once per event, so this table doubles as the per-event hook count.

| event | id | kind | blocking | hooks |
|---|---|---|---|---|
| PostToolUse | context-watermark | writer | no | context-watermark.sh |
| PostToolUse | cross-repo-drift-gate | gate | no | cross-repo-drift-postpush-gate.sh |
| PostToolUse | doctrine-jit | writer | no | doctrine-jit.sh |
| PostToolUse | gh-account-hint | surfacer | no | gh-account-blindness-hint.sh |
| PostToolUse | plan-lifecycle | writer | no | plan-auto-closure.sh, plan-lifecycle.sh, plan-status-archival-sweep.sh |
| PostToolUse | task-verifier-reminder | surfacer | no | post-tool-task-verifier-reminder.sh |
| PostToolUse | workstreams-emitters | writer | no | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh |
| PreCompact | pre-compact-continuity | writer | no | pre-compact-continuity.sh |
| PreToolUse | agent-design-gate | gate | no | agent-design-gate.sh |
| PreToolUse | agent-teams | gate | yes | task-completed-evidence-gate.sh, task-created-validator.sh, teammate-spawn-validator.sh |
| PreToolUse | claude-md-hygiene | gate | yes | claude-md-hygiene-gate.sh |
| PreToolUse | concurrent-ownership-gate | gate | yes | concurrent-ownership-gate.sh |
| PreToolUse | cross-repo-nl-touch-warn | surfacer | no | cross-repo-nl-touch-warn.sh |
| PreToolUse | definition-on-first-use | gate | no | definition-on-first-use-gate.sh |
| PreToolUse | deploy-automation-mode | gate | yes | automation-mode-gate.sh |
| PreToolUse | design-mode-planning | gate | no | systems-design-gate.sh |
| PreToolUse | doc-gate | gate | no | doc-gate.sh |
| PreToolUse | env-local-protection | gate | yes | env-local-protection.sh |
| PreToolUse | evidence-before-fix | gate | no | evidence-before-fix-gate.sh |
| PreToolUse | find-disk-scan-gate | gate | yes | find-disk-scan-gate.sh |
| PreToolUse | find-scan-warn | surfacer | no | find-scan-warn.sh |
| PreToolUse | findings-ledger | gate | yes | findings-ledger-schema-gate.sh |
| PreToolUse | gh-account-autoswitch | surfacer | no | gh-account-autoswitch.sh |
| PreToolUse | gh-merge-canonical | gate | yes | gh-merge-canonical-gate.sh |
| PreToolUse | local-edit-authorization | gate | yes | local-edit-gate.sh |
| PreToolUse | model-availability | gate | yes | model-pin-gate.sh |
| PreToolUse | model-pin | gate | yes | model-pin-gate.sh |
| PreToolUse | no-test-skip | gate | yes | no-test-skip-gate.sh |
| PreToolUse | observed-errors-first | gate | no | observed-errors-gate.sh |
| PreToolUse | outcome-evidence | gate | no | outcome-evidence-gate.sh |
| PreToolUse | parallel-dev-migration-naming | gate | yes | migration-naming-gate.sh |
| PreToolUse | perf-ledger | writer | no | lib/perf-ledger.sh |
| PreToolUse | plan-deletion-protection | gate | yes | plan-deletion-protection.sh |
| PreToolUse | plan-edit-validator | gate | yes | plan-edit-validator.sh |
| PreToolUse | pr-template-inline | gate | no | pr-template-inline-gate.sh |
| PreToolUse | prd-validity | gate | no | prd-validity-gate.sh |
| PreToolUse | pre-commit-chain | gate | yes | pre-commit-gate.sh |
| PreToolUse | review-record-commit-gate | gate | yes | review-record-commit-gate.sh |
| PreToolUse | spec-freeze | gate | yes | scope-enforcement-gate.sh, spec-freeze-gate.sh |
| PreToolUse | vaporware-volume | gate | no | vaporware-volume-gate.sh |
| PreToolUse | wire-check | gate | yes | wire-check-gate.sh |
| PreToolUse | workstreams-emitters | writer | no | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh |
| SessionStart | background-work-tracking | surfacer | no | stalled-work-surfacer.sh |
| SessionStart | decision-context-emitters | writer | no | decision-context-pending-surfacer.sh, decision-context-reply-emit.sh |
| SessionStart | discovery-cheatsheet | surfacer | no | session-start-discovery-cheatsheet.sh |
| SessionStart | discovery-protocol | surfacer | no | discovery-surfacer.sh |
| SessionStart | effort-policy-warn | surfacer | no | effort-policy-warn.sh |
| SessionStart | external-monitor-alerts | surfacer | no | external-monitor-alert-surfacer.sh |
| SessionStart | gh-account-hint | surfacer | no | gh-account-blindness-hint.sh |
| SessionStart | git-freshness | surfacer | no | session-start-git-freshness.sh |
| SessionStart | harness-doctor | surfacer | no | harness-doctor.sh |
| SessionStart | plan-lifecycle | writer | no | plan-auto-closure.sh, plan-lifecycle.sh, plan-status-archival-sweep.sh |
| SessionStart | register-surfacer | surfacer | no | register-surfacer.sh |
| SessionStart | review-before-deploy | gate | yes | — |
| SessionStart | session-start-auto-install | writer | no | lib/sessionstart-singleflight.sh, session-start-auto-install.sh |
| SessionStart | session-start-digest | surfacer | no | session-start-digest.sh |
| SessionStart | session-start-surfacer-pack | surfacer | no | session-start-surfacer-pack.sh |
| SessionStart | spawn-task-report-back | surfacer | no | spawned-task-result-surfacer.sh |
| SessionStart | stale-plan-surfacer | surfacer | no | stale-active-plan-surfacer.sh |
| SessionStart | workstreams-emitters | writer | no | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh |
| SessionStart | workstreams-task-binding | gate | no | workstreams-task-binding.sh |
| SessionStart | worktree-advisor | surfacer | no | session-start-worktree-advisor.sh |
| Stop | bug-persistence | gate | yes | bug-persistence-gate.sh |
| Stop | runtime-verification | gate | yes | runtime-verification-executor.sh, runtime-verification-reviewer.sh |
| Stop | session-honesty | gate | yes | session-honesty-gate.sh |
| Stop | signal-ledger-flush | writer | no | signal-ledger-flush.sh |
| Stop | stop-verdict-dispatcher | gate | yes | stop-verdict-dispatcher.sh |
| Stop | work-integrity | gate | yes | work-integrity-gate.sh |
| Stop | workstreams-emitters | writer | no | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh |
| Stop | workstreams-stop-gate | gate | no | workstreams-stop-gate.sh |
| Stop | workstreams-stop-writer | writer | no | workstreams-stop-writer.sh |
| Stop | workstreams-task-binding | gate | no | workstreams-task-binding.sh |
| SubagentStop | agent-commit-gate | gate | no | agent-commit-gate.sh |
| TaskCompleted | agent-teams | gate | yes | task-completed-evidence-gate.sh, task-created-validator.sh, teammate-spawn-validator.sh |
| TaskCreated | agent-teams | gate | yes | task-completed-evidence-gate.sh, task-created-validator.sh, teammate-spawn-validator.sh |
| UserPromptSubmit | decision-context-emitters | writer | no | decision-context-pending-surfacer.sh, decision-context-reply-emit.sh |
| UserPromptSubmit | workstreams-emitters | writer | no | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh |
| manual | admission-lib | writer | no | lib/admission-lib.sh |
| manual | estate-brief | writer | no | ../scripts/estate-brief.sh |
| manual | estate-janitor | writer | no | ../scripts/estate-janitor.sh |
| manual | harness-doctor | surfacer | no | harness-doctor.sh |
| manual | harness-hygiene-scan | gate | yes | harness-hygiene-scan.sh |
| manual | ntfy-push | surfacer | no | — |
| manual | perf-tick-snapshot | writer | no | lib/perf-tick-snapshot.sh |
| manual | plan-reviewer | gate | yes | plan-reviewer.sh |
| manual | propagation-engine | writer | no | propagation-trigger-router.sh |
| manual | review-before-deploy | gate | yes | — |
| manual | secret-scan-ci-backstop | gate | yes | — |
| manual | synthetic-runner-ci | gate | yes | — |
| manual | verification-dispatch | pattern | no | — |
| manual | wave-d-retired-shims | writer | no | check-harness-sync.sh, completion-criteria-gate.sh, continuation-enforcer.sh, cross-repo-drift-warn.sh, customer-facing-review-gate.sh, dag-review-waiver-gate.sh, decision-context-gate.sh, decision-context-replay.sh, deferral-counter.sh, goal-coverage-on-stop.sh, goal-extraction-on-prompt.sh, imperative-evidence-linker.sh, narrate-and-wait-gate.sh, pr-health-snapshot-gate.sh, pre-stop-verifier.sh, principles-compliance-gate.sh, product-acceptance-gate.sh, register-progress-gate.sh, settings-divergence-detector.sh, tool-call-budget.sh, transcript-lie-detector.sh, worktree-teardown-gate.sh |
| manual | workstreams-extract-pending | writer | no | workstreams-extract-pending.sh |
| manual | workstreams-turn-emit | writer | no | workstreams-turn-emit.sh |
| precommit | backlog-plan-atomicity | gate | yes | backlog-plan-atomicity.sh |
| precommit | decisions-index | gate | yes | decisions-index-gate.sh |
| precommit | docs-freshness | gate | yes | docs-freshness-gate.sh |
| precommit | harness-hygiene-scan | gate | yes | harness-hygiene-scan.sh |
| precommit | migration-claude-md | gate | yes | migration-claude-md-gate.sh |
| precommit | plan-reviewer | gate | yes | plan-reviewer.sh |
| precommit | review-finding-fix | gate | yes | review-finding-fix-gate.sh |
| precommit | tdd-gate | gate | yes | pre-commit-tdd-gate.sh |
| prepush | pre-push-divergence | gate | yes | pre-push-divergence-check.sh |
| prepush | pre-push-test | gate | yes | pre-push-test-gate.sh |
| prepush | secret-hygiene-prepush | gate | yes | pre-push-scan.sh |

## Blocking vs warn, by kind

| kind | blocking | warn/non-blocking |
|---|---|---|
| gate | 38 | 14 |
| writer | 0 | 33 |
| surfacer | 0 | 22 |
| pattern | 0 | 28 |
| convention | 0 | 3 |

## Budgets

Per §F.1 (`blocking-budget-check.js`): blocking gates ≤ 12 (counted structurally
here as manifest `blocking:true` entries — the F.1 budget check counts the same
field against the SAME-EVENT-CHAIN definition; see that check's own doc for the
distinction between total blocking:true entries and blocking CHAIN POSITIONS).

| budget_class | entries |
|---|---|
| stop | 8 |
| session-start | 15 |
| pretool | 33 |
| posttool | 6 |
| none | 76 |

## Doctrine index

Generated inventory of every entry's `doctrine_file` target. The canonical
per-doctrine-file table (id/kind/hooks/blocking/honest_status, one row per
entry) lives at [`doctrine/INDEX.md`](../adapters/claude-code/doctrine/INDEX.md)
(generated by `manifest-check.sh --gen-index` — this section cross-references
it rather than duplicating it, so the two generators cannot disagree).

| doctrine_file | entries pointing to it |
|---|---|
| doctrine/acceptance-scenarios.md | 1 (acceptance-scenarios) |
| doctrine/agent-teams.md | 1 (agent-teams) |
| doctrine/artifact-evidence-bar.md | 2 (agent-design-gate, artifact-evidence-bar) |
| doctrine/automation-modes.md | 1 (automation-modes) |
| doctrine/background-work-tracking.md | 2 (agent-heartbeat, background-work-tracking) |
| doctrine/claims.md | 1 (claims) |
| doctrine/code-conventions.md | 3 (code-conventions, doc-gate, migration-claude-md) |
| doctrine/completion-criteria.md | 1 (completion-criteria) |
| doctrine/comprehension-gate.md | 1 (comprehension-gate) |
| doctrine/consolidation-discipline.md | 1 (consolidation-discipline) |
| doctrine/customer-facing-review.md | 1 (customer-facing-review) |
| doctrine/decision-context.md | 1 (decision-context-emitters) |
| doctrine/definition-on-first-use.md | 1 (definition-on-first-use) |
| doctrine/design-mode-planning.md | 1 (design-mode-planning) |
| doctrine/diagnosis.md | 1 (diagnosis) |
| doctrine/discovery-protocol.md | 1 (discovery-protocol) |
| doctrine/estate-coordination.md | 1 (estate-coordination) |
| doctrine/evidence-before-fix.md | 1 (evidence-before-fix) |
| doctrine/findings-ledger.md | 1 (findings-ledger) |
| doctrine/friction-reflexion.md | 1 (friction-reflexion) |
| doctrine/frontend-conventions.md | 1 (frontend-conventions) |
| doctrine/gate-respect.md | 1 (gate-respect) |
| doctrine/gh-merge-canonical.md | 1 (gh-merge-canonical) |
| doctrine/git.md | 6 (cross-repo-drift-gate, deploy-automation-mode, gh-account-autoswitch, gh-account-hint, git-freshness, pre-push-divergence) |
| doctrine/harness-dev.md | 9 (claude-md-hygiene, discovery-cheatsheet, docs-freshness, harness-doctor, harness-hygiene-scan, session-start-auto-install, session-start-surfacer-pack, signal-ledger-flush, wave-d-retired-shims) |
| doctrine/interactive-process-fidelity.md | 1 (interactive-process-fidelity) |
| doctrine/local-edit-authorization.md | 1 (local-edit-authorization) |
| doctrine/mechanical-evidence.md | 1 (mechanical-evidence) |
| doctrine/model-selection.md | 2 (model-availability, model-pin) |
| doctrine/observability.md | 3 (nl-cli, observability, observability-consumer-map) |
| doctrine/observed-errors-first.md | 1 (observed-errors-first) |
| doctrine/orchestrator-pattern.md | 1 (orchestrator-pattern) |
| doctrine/parallel-dev-discipline.md | 2 (concurrent-ownership-gate, parallel-dev-migration-naming) |
| doctrine/planning.md | 11 (backlog-plan-atomicity, decisions-index, plan-deletion-protection, plan-edit-validator, plan-lifecycle, plan-reviewer, pr-template-inline, stale-plan-surfacer, task-verifier-reminder, wire-check, work-integrity) |
| doctrine/pr-health-snapshot.md | 1 (pr-health-snapshot) |
| doctrine/prd-validity.md | 1 (prd-validity) |
| doctrine/reap-what-you-spawn.md | 2 (agent-commit-gate, reap-what-you-spawn) |
| doctrine/review-before-deploy.md | 2 (review-before-deploy, review-record-commit-gate) |
| doctrine/risk-tiered-verification.md | 1 (risk-tiered-verification) |
| doctrine/security.md | 3 (env-local-protection, secret-hygiene-prepush, secret-scan-ci-backstop) |
| doctrine/session-end-protocol.md | 2 (register-surfacer, session-honesty) |
| doctrine/spawn-task-report-back.md | 1 (spawn-task-report-back) |
| doctrine/spec-freeze.md | 1 (spec-freeze) |
| doctrine/teaching-moments.md | 1 (teaching-moments) |
| doctrine/testing.md | 6 (bug-persistence, no-test-skip, outcome-evidence, pre-push-test, review-finding-fix, tdd-gate) |
| doctrine/vaporware-prevention.md | 3 (runtime-verification, vaporware-config-control, vaporware-volume) |
| doctrine/verification-dispatch.md | 1 (verification-dispatch) |
| doctrine/work-shapes.md | 1 (work-shapes) |
| doctrine/workstream-memory-ecology.md | 1 (workstream-memory-ecology) |
| doctrine/workstreams-state.md | 6 (workstreams-emitters, workstreams-extract-pending, workstreams-stop-gate, workstreams-stop-writer, workstreams-task-binding, workstreams-turn-emit) |
| doctrine/worktree-isolation.md | 1 (worktree-advisor) |
| rules/constitution.md | 1 (constitution) |

Entries with no doctrine_file (`-`): 38.

## Full entry listing

| id | kind | events | blocking | budget_class | honest_status |
|---|---|---|---|---|---|
| acceptance-scenarios | pattern | — | no | none | — |
| admission-lib | writer | manual | no | none | OBSERVE MODE ONLY -- NOT an enforcement mechanism. blocking:false is literal: adm_admit's final statement is an unconditional return 0 and Scenario 15 fails the suite if any input combination produces non-zero. The flip is T6, gated on >=7 days of ledger plus operator sign-off. STATE OF THE DELIVERABLE AFTER THE 2026-07-28 REVIEW ROUND (harness-reviewer REJECT-amend-forward + task-verifier FAIL, both on commit f6562b2; amended in the follow-up commit): the ledger as originally shipped was NOT recording what this entry claimed. Two Critical parser defects -- adm_live_sessions read a live_sessions key estate-janitor.sh NEVER writes, and both extractors stripped to end-of-line against a producer that emits the whole snapshot as ONE line (a true 3 parsed as 3379, which at T6 would have blocked every dispatch) -- plus an uninterpretable kind:"0" label on the highest-volume source. All 14 pre-fix production lines were archived to state/governor/discarded/ and the >=7-day clock restarted from the fixed build. RETIRED CLAIMS (this slice's program-rule-3 retirement -- rule 3 permits retiring a hook, store, OR CLAIM, and task-verifier correctly noted the claim column was the one available): (a) the 'spawn-free hot path / forks at most ONCE / ~0 ms' claim, refuted by two independent measurements (19.3 ms and 20.1 ms per dispatch, ~45 forks, 2 execs) and replaced with the measured numbers plus a <5 ms T6 budget; (b) the absolute 'nothing here trusts a caller-supplied claim' claim, refuted because the lib is SOURCED into the dispatcher's shell -- ADM_ABSURD_SESSION_CAP, ADM_ESTATE_SNAPSHOT and especially ADM_STATE_DIR (which hides the HALT kill switch entirely) are environment bypasses, now PINNED by Scenario 10b so T6 cannot flip enforcement believing they are closed. The accurate claim is 'no caller ARGUMENT decides'. COVERAGE: Task/Agent/Workflow dispatch; session-resumer resume, fresh-spawn AND storm-cap-queued deferrals (that early return previously emitted nothing -- silence exactly during the storms this slice exists to characterize); spawn-worktree creates. NOT COVERED: Decision-011 cloud/scheduled sessions, a human running claude directly, MCP-side agent spawns -- unmeasured load when reading calibration. Not event-wired in settings.json.template -- a sourced lib with four one-line splices inside already-wired scripts; manifest-check's disk scan only walks top-level hooks/*.sh, never hooks/lib/, so this entry is inventory-for-honesty, not enforcement. |
| agent-commit-gate | gate | SubagentStop | no | none | — |
| agent-design-gate | gate | PreToolUse | no | pretool | — |
| agent-heartbeat | writer | — | no | none | scripts/agent-heartbeat.sh (emit/conclude/watch/reap) — per-AGENT liveness heartbeat in the heartbeats/agents/ namespace (2026-07-14 lesson: background agents need a push heartbeat + watchdog, not orchestrator output-polling). watch AND reap are spliced into hooks/stalled-work-surfacer.sh run() (watch surfaces stalled agents at SessionStart alongside stalled Workflow runs; reap bounds the namespace — the session-heartbeat reaper's 2026-07-09 dead-reaper defect, avoided here by wiring reap in the same commit). conclude is the terminal beat: an agent self-removes on clean completion so a COMPLETED agent is never surfaced as stalled (mirrors the workflow half's started==result suppression; without it every finished agent false-fires — the cry-wolf that REFORMULATE'd orphaned-worktree-guard, fixed here per harness-review CONDITIONAL-PASS 2026-07-14). INTERIM PATTERN: relies on the dispatched agent calling emit/conclude (dispatch-prompt convention in doctrine/background-work-tracking.md); the true runtime auto-heartbeat is not in-repo. Detection covers agents that emitted then stopped (the worked-then-wedged class). Not event-wired as its own settings.json entry — a splice inside the already-wired stalled-work-surfacer.sh; inventory-only per the manifest-check disk-coverage note (scripts/ is not disk-scanned). |
| agent-teams | gate | PreToolUse, TaskCompleted, TaskCreated | yes | pretool | — |
| artifact-evidence-bar | pattern | — | no | none | PATTERN, backed by two real MECHANISMS as of 2026-07-14 (this is the doctrine entry; the two gates are their own manifest entries with their own golden_scenario/fp_expectation/retirement_condition). (1) GATE 1 = plan-reviewer.sh Check 17 (see the 'plan-reviewer' entry): blocking, fires on Status: ACTIVE (or unset) plans whose text matches a tight architecture-keyword set (source of truth / read-write path / staleness / materialize / derived store / cache-invalidation / sync engine-job / projection / reconcile loop — calibrated against this repo's own 237-plan corpus to 27.0% hit rate after a bare-stem draft measured 50.6%), requiring a linked docs/reviews/*-architecture-review.md whose verdict is SOUND or SOUND-WITH-AMENDMENTS (NEEDS-RESHAPING does not satisfy it); 7/7 self-test scenarios including the real cockpit-v2-push-materialized-store.md/2026-07-14-cockpit-v2-architecture-review.md NEEDS-RESHAPING golden case. (2) GATE 2 = the 'agent-design-gate' entry (adapters/claude-code/hooks/agent-design-gate.sh): PreToolUse on Edit|Write|MultiEdit, blocks a brand-new adapters/claude-code/agents/*.md Write lacking a '## GOLDEN CASE' section + evidence of the seven properties; grandfathers all pre-bar agents by on-disk-existence check; 7/7 self-test scenarios. Operator directive 2026-07-14. |
| ask-registry | writer | — | no | none | scripts/ask-registry.sh — the ask-registry CLI (register/attach-session/link-plan/set-status/merge/override-project, plus the cockpit-roadmap-redesign Task 2 work-item-layer verbs: set-title/capture-candidate/classify-candidate/detach-candidate/amend, PLUS the accountable-estate-program-2026-07 Task 2 ask-SLA verbs: set-deadline/clear-deadline/set-default-action/sla) writing ~/.claude/state/ask-registry.jsonl plus a best-effort in-repo mirror at docs/asks/ask-registry.jsonl (path resolved via nl_main_checkout_root, never a worktree) and a heuristic-first summarizer (ASK_SUMMARIZER=haiku upgrade, async, best-effort; the SAME gated async lane classifies amendment candidates amendment/noise — best-effort, candidates stay honestly pending on any failure). Round-6-gap-5 follow-on fix (cockpit-roadmap-redesign): the flag was proven dormant in production (grep found zero exporters anywhere) — hooks/workstreams-read.sh's ASK-CAPTURE SPLICE now defaults it to "haiku" mechanically for every real (non-HARNESS_SELFTEST) register/capture-candidate call, so the lane runs without anyone remembering to export it; an operator can still override to any other value ahead of a session. Title records carry title_source auto|operator; readers MUST fold operator-beats-auto regardless of timestamp (the A3 precedence contract in the script header). Deadline records carry a matching carve-out (DEADLINE FOLD, script header SCHEMA section): a reader folds ONLY deadline_set/deadline_cleared records by ts and takes the latest, since plain last-non-empty-wins can never represent an explicit clear; default_action has no such carve-out (plain last-non-empty-wins). set-deadline validates + normalizes to canonical %Y-%m-%dT%H:%M:%SZ before storing (rejects unparseable input, no-op); set-default-action stores a disposition AS DATA ONLY this slice (no automatic enforcement reads it yet, per the program's observe-first rule); sla is a read-only TSV read-out (overdue|due-soon|ok|no-deadline, sorted soonest-first) consumed manually and by estate-janitor.sh's ask-fold (which folds the same deadline/default_action fields into snapshot.json for estate-brief.sh's SLA panel — see the estate-janitor/estate-brief manifest entries). Called by hooks/workstreams-read.sh's capture splices (register on the first operator prompt; capture-candidate on every later prompt of an ask-attached session — both guarded by hooks/lib/progress-log-lib.sh's pl_classify_session against spawned/builder sessions) and by hooks/session-start-digest.sh's session-attach splice (attach-session, beside the existing heartbeat splice); set-status/merge are also called by the workstreams-ui server's POST /api/ask/<id>/lifecycle endpoint (operator override) and by the background auditor (mechanical completion). Not event-wired as its own settings.json entry — a one-line splice call-site inside already-wired hooks, mirroring the session-heartbeat/ensure-cockpit convention. Inventory-only per the filed nl-issue note that manifest-check's disk-coverage check (b) only disk-scans hooks/*.sh top-level, never scripts/ — this entry exists for honesty, not enforcement. |
| automation-modes | pattern | — | no | none | — |
| background-work-tracking | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| backlog-plan-atomicity | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| bug-persistence | gate | Stop | yes | stop | Invoked by stop-verdict-dispatcher.sh in --report mode (E.11, §E.W); no longer a direct Stop-chain entry. --self-test + blocking logic intact. |
| claims | pattern | — | no | none | — |
| claude-md-hygiene | gate | PreToolUse | yes | pretool | — |
| code-conventions | convention | — | no | none | — |
| completion-criteria | pattern | — | no | none | — |
| comprehension-gate | pattern | — | no | none | — |
| concurrent-ownership-gate | gate | PreToolUse | yes | pretool | — |
| consolidation-discipline | pattern | — | no | none | — |
| constitution | pattern | — | no | none | — |
| context-watermark | writer | PostToolUse | no | posttool | E.9a early-warning context watermark; wired PostToolUse at §E.W. |
| cross-repo-drift-gate | gate | PostToolUse | no | posttool | — |
| cross-repo-nl-touch-warn | surfacer | PreToolUse | no | pretool | — |
| customer-facing-review | pattern | — | no | none | — |
| decision-context-emitters | writer | SessionStart, UserPromptSubmit | no | session-start | replay retired to attic (fence retirement, D.4/D.5); pending-surfacer dispatched via surfacer-pack; reply-emit wired at UserPromptSubmit. |
| decisions-index | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| definition-on-first-use | gate | PreToolUse | no | pretool | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| deploy-automation-mode | gate | PreToolUse | yes | pretool | — |
| design-mode-planning | gate | PreToolUse | no | pretool | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| diagnosis | pattern | — | no | none | — |
| discovery-cheatsheet | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| discovery-protocol | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| dispatch-provenance | writer | — | no | none | scripts/dispatch-provenance.sh — writes a per-dispatch provenance marker (cmd_write) recording which worktree/session a builder dispatch spawned into, read back by hooks/lib/progress-log-lib.sh's pl_classify_session (the Task 9 spawned-session guard) to distinguish a dispatched child session from a genuine new operator ask. Called by hooks/workstreams-emit.sh's task_started splice (the same --on-builder-dispatch call path that emits the task_started progress-log event, so the marker and the event share provenance for one dispatch). Not event-wired as its own settings.json entry — a one-line splice call-site inside an already-wired hook, mirroring the session-heartbeat convention. Inventory-only per the filed nl-issue note that manifest-check's disk-coverage check (b) only disk-scans hooks/*.sh top-level, never scripts/ — this entry exists for honesty, not enforcement. |
| doc-gate | gate | PreToolUse | no | pretool | — |
| docs-freshness | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| doctrine-jit | writer | PostToolUse | no | posttool | — |
| effort-policy-warn | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| end-manifest | writer | — | no | none | scripts/end-manifest.sh (E.12) — session end-manifest writer+validator; invoked by the dispatcher when a manifest is present, not event-wired. |
| ensure-cockpit | writer | — | no | none | scripts/ensure-cockpit.sh — best-effort SessionStart ensure for the observability cockpit (workstreams-ui node server, port 7733); called by a one-line splice in session-start-digest.sh run_digest() (mirrors the session-heartbeat splice convention), not event-wired as its own settings.json entry. Guards: operator kill-switch (~/.claude/local/cockpit-disabled or ENSURE_COCKPIT_DISABLE=1), Windows-only, HARNESS_SELFTEST stub, machine-wide nl_repo_root resolution normalized to the MAIN checkout (never a worktree) with session-cwd fallback, nohup+disown non-blocking dispatch, tolerate-absent (always exit 0). Replaces the ConversationTreeUI-AutoStart logon scheduled task (retired at integration 2026-07-09). |
| env-local-protection | gate | PreToolUse | yes | pretool | — |
| estate-brief | writer | manual | no | none | — |
| estate-coordination | pattern | — | no | none | docs+skill unit only (skills/coordinate-estate/SKILL.md + doctrine/estate-coordination.md); no hook, no wiring; jit_triggers fire doctrine-jit.sh's paths-match on any edit whose file_path contains SCRATCHPAD.md (keywords reserved for v2 per schema, not yet matched). |
| estate-janitor | writer | manual | no | none | — |
| evidence-before-fix | gate | PreToolUse | no | pretool | WARN-MODE-PENDING-CALIBRATION (harness-review REJECT remediation, 2026-07-16): evidence-before-fix-gate.sh ALWAYS exits 0 -- it never blocks a commit. On a triggering fix(/fix: commit lacking evidence it prints the full teaching banner (stderr + hookSpecificOutput.additionalContext) but the commit proceeds regardless. blocking:false reflects ACTUAL current behavior, not a designed end-state kept hidden behind a default -- unlike claude-md-hygiene's entry (blocking:true with a warn-mode default via env var), this entry is honest about the runtime being warn-only right now. PROMOTION CONDITION (tracked docs/backlog.md EVIDENCE-BEFORE-FIX-PROMOTION-01): promote to blocking:true only after a measured calibration period (method: the reviewer's own sweep, `git log -N --format=%s` bucketed into {incident-shaped, review/audit-remediation, refactor/typo, other}) shows the over-fire class (non-incident maintenance/review-remediation fixes, measured ~13-15% of this repo's fix(/fix: commits at the 2026-07-16 baseline) is EITHER separable by a trigger refinement OR acceptably rare once the parser-reach fixes below are reflected in a fresh measurement. |
| external-monitor-alerts | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| find-disk-scan-gate | gate | PreToolUse | yes | pretool | Residuals (documented, not caught): a scan hidden one level down inside a nested quoted string handed to another interpreter (`bash -c "find / ..."`, `ssh host 'find / ...'`, `docker exec ... find /`) is not unwrapped — only the outer command string's own segments are parsed. Exotic quoting/escaping (a root built at runtime via command substitution or variable expansion, base64-encoded commands, `$'...'` ANSI-C quoting) is not evaluated. The quote-aware segment splitter (added 2026-07-23 batch review) tracks single-/double-quote state char-by-char but not parenthesis depth or backslash-escaped quotes: an unquoted subshell containing a top-level-looking separator (`echo $(echo a && echo b)`) could still split at the wrong point, and a backslash-escaped quote inside a double-quoted span (`"foo\"bar"`) ends quote-tracking early. PowerShell aliases for Get-ChildItem (`gci`, `ls`, `dir`) are not recognized, only the literal cmdlet name. `find`'s pre-path global options are handled for the common set (-H/-L/-P/-O0..3/-D) — an unrecognized one placed before the root could shift the parse. |
| find-scan-warn | surfacer | PreToolUse | no | pretool | — |
| findings-ledger | gate | PreToolUse | yes | pretool | — |
| friction-reflexion | pattern | — | no | none | — |
| frontend-conventions | convention | — | no | none | — |
| gate-demotion | pattern | — | no | none | — |
| gate-respect | pattern | — | no | none | — |
| gen-architecture-doc | writer | — | no | none | scripts/gen-architecture-doc.sh (F.2) -- regenerates docs/harness-architecture.md from manifest.json; --check is the doctor drift predicate (tests/fixtures/wave-f/F.2/doctor-predicate.md); not event-wired (manual + doctor-invoked). |
| gh-account-autoswitch | surfacer | PreToolUse | no | pretool | — |
| gh-account-hint | surfacer | PostToolUse, SessionStart | no | posttool | — |
| gh-merge-canonical | gate | PreToolUse | yes | pretool | gh-merge-canonical-gate.sh (PreToolUse Bash) BLOCKS `gh pr merge` / `gh api .../pulls/N/merge` when the RESOLVED target repo equals the `pt` remote's repo (read from `git remote get-url pt` at runtime, never hardcoded). DEFENSE-IN-DEPTH ONLY (decision 064 amendments A1/A2) — the PRIMARY structural mechanism is server-side branch protection on pt/master (operator-only, not agent-executable, surfaced as a standing NEEDS-YOU item until enabled). Scopes itself by the remote NAME `pt` (a neural-lace-specific convention); on any other repo across the estate that names its mirror remote something else, this gate is a silent no-op for that repo. Target resolution (post 2026-07-16 harness-review fixup) reads `.tool_input.command` with a `.command` flat-shape fallback, tolerates irregular whitespace in `gh pr merge`, and parses positional PR-URL / `OWNER/REPO#N` targets ahead of default-repo resolution; a gh-api `{owner}/{repo}` template placeholder is treated as not-explicit (falls through) rather than as a literal never-matching owner/repo. HONEST RESIDUAL — invocation shapes still uncovered by the parser (fall through to default-repo resolution or the loud ambiguous-block, never misread as a false ALLOW/BLOCK): a runtime-interpolated value (`gh pr merge $N --repo "$REPO_VAR"` — invisible to a static-string check); a bundled short flag with no space (`-Rowner/repo`); a `gh pr merge` invoked via a shell alias/function whose name doesn't literally contain adjacent `gh`/`pr`/`merge` tokens. Also not covered by this gate at all (A1): GitHub web-UI merges, a machine that hasn't yet synced this hook (deploy-lag window), un-harnessed/external machines, CI/GitHub Actions, scheduled/cloud agents (Decision 011 — no PreToolUse), direct `git push pt master`. |
| git-freshness | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| harness-changelog | writer | — | no | none | scripts/harness-changelog.sh (F.2b) -- machine-wide 'what's new' ledger + --digest-line consumed by session-start-digest.sh's feed 15; not event-wired. |
| harness-doctor | surfacer | SessionStart, manual | no | session-start | diagnostic tool — invoked on demand (harness-doctor.sh --quick); chain wiring is a post-Wave-D decision |
| harness-hygiene-scan | gate | manual, precommit | yes | none | invoked via pre-commit-gate.sh chain and manual --full-tree runs; not directly wired in settings.json.template |
| harness-kpis | writer | — | no | none | scripts/harness-kpis.sh — weekly KPI report from the signal ledger (E.5); scheduled-task registration documented, not a hook. |
| interactive-process-fidelity | pattern | — | no | none | — |
| local-edit-authorization | gate | PreToolUse | yes | pretool | — |
| master-drift-autocorrect | writer | — | no | none | scripts/master-drift-autocorrect.sh — FF-only remote-master drift corrector (docs/plans/master-drift-autocorrection-2026-07.md). Not event-wired itself: dispatched BACKGROUNDED by hooks/session-start-git-freshness.sh (the git-freshness entry's hook) on remote-vs-remote master SHA inequality or a non-quiet ~/.claude/state/master-drift/<repo>.status, and directly invocable by hand. All mutating git ops run in the F.6 dedicated sync clone (~/.claude/sync-clone/<repo>); true divergence is surfaced (one digest line), never auto-merged; kill switch MASTER_DRIFT_AUTOCORRECT=0. Doctor predicate: check_master_drift_autocorrect (quick: script + --self-test entrypoint + hook wiring; --full additionally runs the script's --self-test). Runbook: docs/runbooks/master-drift-autocorrect.md. |
| mechanical-evidence | pattern | — | no | none | — |
| merge-scan | writer | — | no | none | hooks/lib/merge-scan-lib.sh — ms_emit_merged_for_commit (per-commit `merged` progress-log event, natural-keyed on commit SHA) + ms_scan_repo_for_merges (git-log backfill lane reconciling any missed `merged` events, Task 5b/12). Called by adapters/claude-code/git-hooks/post-commit's post-commit hook body (local-only, best-effort, never blocks the commit) and by the workstreams-ui background auditor's git-log comparison pass. Lives under hooks/lib/ — a subdirectory manifest-check's disk-coverage check (b) never scans (only top-level hooks/*.sh is scanned), so it carries no hooks[] entry of its own; this entry is inventory-only, included for honesty per the filed nl-issue note on manifest-check's disk-scope. |
| migration-claude-md | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| model-availability | gate | PreToolUse | yes | pretool | HONEST SCOPE -- this is a REROUTE, not an automatic fallback, and must not be described as one. A PreToolUse hook cannot rewrite tool input and cannot catch an API error raised after the call is admitted, so no harness-side code can transparently retry a dead Fable dispatch on Opus. What this does is convert a SILENT 100%-reproducible death into a LOUD block naming the override, which is the strongest rung actually available. The tier's unavailability must still be OBSERVED and marked by whoever sees the spend-limit error (`model-availability.sh mark-exhausted fable --reason ...`); there is no API to query budget, so this is not self-detecting. That is a real residual, stated rather than hidden. NOT COVERED, same as model-pin-gate's pre-existing residual: Workflow-inline agent() model:, spawn_task, and cron/remote dispatch surfaces a PreToolUse hook never sees. |
| model-pin | gate | PreToolUse | yes | pretool | model-pin-gate.sh (PreToolUse Task|Agent) BLOCKS a subagent spawn with no explicit model whose agent type is unpinned/unknown — forcing explicit model selection so a spawn never SILENTLY INHERITS the main-loop model (operator directive 2026-07-14; silent Fable inheritance drained ~1.7M tokens). Source of truth config/model-policy.json; all 24 agents/*.md pinned. HONEST RESIDUAL (NOT gate-able, doctrine/model-selection.md): Workflow-inline agent(), spawn_task, cron/remote expose no model field a PreToolUse hook can inspect — convention + review only. A harness-doctor check (model-pins) enforces that every agents/*.md stays pinned. |
| needs-you-ledger | writer | — | no | none | scripts/needs-you.sh — maintains NEEDS-YOU.md (E.6); called by decision-log flow + digest, not event-wired. Cold-reader lint (constitution §3 amendment 53d3bee, operator directive 2026-07-07): `add --section decision` scores every new entry's --text against three zero-session-context checks (background/context, a concrete artifact anchor, per-option outcome text — see _ny_lint_decision_text) and stores the result as a `lint_warnings` array on the item. TWO-PATH contract (T4/A1 cold-reader block-promotion, cockpit-roadmap-redesign 2026-07-20): an INTERACTIVE `add --section decision` whose --text fails the lint BLOCKS (exit 1, nothing written, teaching message printed) so the session retries with context; a `--mechanical` caller (stop-verdict-dispatcher, session-resumer, session-honesty-gate PAUSING) STORES-AND-QUARANTINES instead (exit 0, `lint_warnings` stamped, NEVER rejected — the ledger-never-rejects contract is preserved so a waiting item never lands nowhere). Golden scenario: the 2026-07-18 bare-token sign-off incident; retirement: demote to warn if weekly triage shows FP blocks exceeding true catches. Self-tested (T22-T25 + interactive-block + mechanical-quarantine). |
| nl-cli | surfacer | — | no | none | scripts/nl.sh (C5 dispatcher) + hooks/lib/observability-derive.sh (C4 pure-read derivation lib: od_sessions/od_needs_me/od_shipped_since/od_harness_health/od_costs/od_backlog_health/od_why) — the six-question observability CLI (specs-o §O.3). Read-only, zero state writes; not event-wired (invoked on demand by the operator or by the future §O.4 cockpit server shelling out to `nl <sub> --json`). |
| nl-issue-capture-loop | pattern | — | no | none | scripts/nl-issue.sh + skill (E.8) — cross-project capture; not event-wired. |
| no-test-skip | gate | PreToolUse | yes | pretool | — |
| ntfy-push | surfacer | manual | no | none | — |
| observability | pattern | — | no | none | CANONICAL-COUNTERS-01 rule + the six operator questions + nl usage (specs-o §O.3 deliverable 1). doctrine/observability.md (compact) + doctrine/observability-full.md (detail, per the estate-coordination.md compact/full split precedent). No hook; the rule is self-applied discipline (per Pattern kind), same class as `estate-coordination`. ORCHESTRATOR RECONCILIATION (batch 2): O.3's fragment proposed the same jit_triggers.paths (scripts/nl.sh, hooks/lib/observability-derive.sh) as the sibling `nl-cli` entry above; doctrine-jit.sh's _compute_injection returns on the FIRST array-order match (see hooks/doctrine-jit.sh ~line 283), so with identical paths on both entries `nl-cli` (earlier in array order) would always win and this entry's own trigger would never fire — a dead, shadowed config. Resolved toward path-disjoint triggers: `nl-cli` (the mechanism entry) keeps the paths; this entry (the doctrine entry, same doctrine_file) keeps only its keywords, which the schema documents as reserved/not yet mechanically matched in v1 but preserved as documentation-of-intent. |
| observability-consumer-map | convention | — | no | none | Data contract (specs-o §O.0.3 contract C3): every signal-ledger event type observed in the ledger or emitted anywhere in the repo MUST have >=1 named entry here (law 2). Seeded by O.1 (batch 1) with all 18 known types (8 pre-existing + 10 Wave-O new); enforced by O.6's check_obs_consumer_map doctor predicate. doctrine_file backfilled to "doctrine/observability.md" at orchestrator integration (batch 2) per O.3's report-back — that file now exists. |
| observed-errors-first | gate | PreToolUse | no | pretool | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| orchestrator-pattern | pattern | — | no | none | — |
| outcome-evidence | gate | PreToolUse | no | pretool | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| parallel-dev-migration-naming | gate | PreToolUse | yes | pretool | — |
| perf-ledger | writer | PreToolUse | no | pretool | — |
| perf-tick-snapshot | writer | manual | no | none | — |
| plan-deletion-protection | gate | PreToolUse | yes | pretool | — |
| plan-edit-validator | gate | PreToolUse | yes | pretool | — |
| plan-lifecycle | writer | PostToolUse, SessionStart | no | posttool | plan-status-archival-sweep.sh dispatched via session-start-surfacer-pack.sh since D.5; plan-auto-closure.sh/plan-lifecycle.sh fire on PostToolUse as before. |
| plan-reviewer | gate | manual, precommit | yes | none | invoked via pre-commit-gate.sh chain and plan-edit flows; not directly wired in settings.json.template. Includes Check 17 (2026-07-14, GATE 1 of artifact-evidence-bar): blocks Status: ACTIVE plans matching an architecture-keyword set that don't link a SOUND/SOUND-WITH-AMENDMENTS architecture-review artifact — see the 'artifact-evidence-bar' entry for golden_scenario/fp_expectation/retirement_condition. |
| pr-health-snapshot | pattern | — | no | none | — |
| pr-template-inline | gate | PreToolUse | no | pretool | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| prd-validity | gate | PreToolUse | no | pretool | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| pre-commit-chain | gate | PreToolUse | yes | pretool | — |
| pre-compact-continuity | writer | PreCompact | no | none | E.9b PreCompact backstop; wired (auto+manual) at §E.W. PreCompact additionalContext channel HYPOTHESIZED on this CC version; snapshot-file + SessionStart compact-echo is the PROVEN fallback (constitution §1). |
| pre-push-divergence | gate | prepush | yes | none | wired via git-hooks/pre-push dispatcher (core.hooksPath), not settings.json.template |
| pre-push-test | gate | prepush | yes | none | wired via git-hooks/pre-push dispatcher (core.hooksPath) with per-repo opt-in marker; not settings.json.template |
| progress-log | writer | — | no | none | hooks/lib/progress-log-lib.sh (pl_emit/pl_path_for/pl_classify_session — the shared writer lib: natural-key dedup, sandbox-only-writes, per-ask JSONL under ~/.claude/state/progress-logs) + scripts/progress-log.sh (the stable `emit` CLI wrapper every splice below shells out to; no splice sources the lib directly) — the ask-rooted-workstreams-p1 progress-log writer family (Tasks 1-6, 9). Every emission site is a one-line splice inside an ALREADY-wired hook or script, never its own settings.json entry, mirroring the session-heartbeat convention. Emitting splices, named verbatim: (1) hooks/plan-lifecycle.sh's emit_task_done_progress_log_events (task_done, on task-verifier checkbox flip) and emit_plan_amended_progress_log_events (plan_amended, on newly-introduced task lines / scope-section edits); (2) hooks/workstreams-emit.sh's task_started splice (best-effort on --on-builder-dispatch) firing alongside scripts/dispatch-provenance.sh's marker write (cmd_write) for the same dispatch; (3) scripts/needs-you.sh's Task-4 splice: waiting_on_operator emission plus a docs/operator-todo.md auto-pointer append, each independently best-effort-wrapped; (4) hooks/lib/merge-scan-lib.sh's ms_emit_merged_for_commit (merged event) called from adapters/claude-code/git-hooks/post-commit's post-commit hook body, backfilled by the auditor's ms_scan_repo_for_merges git-log scan (Task 5b/12); (5) scripts/close-plan.sh's emit_plan_completed_progress_log_event (plan_completed, the sixth/exit lane), reached via both the wired plan-auto-closure.sh PostToolUse hook and manual `close-plan.sh close` runs; (6) hooks/workstreams-read.sh's first-prompt ask_registered capture splice (calls scripts/ask-registry.sh register, guarded against spawned/builder/sub-agent sessions via pl_classify_session) and hooks/session-start-digest.sh's session_attached splice beside the existing heartbeat splice (calls scripts/ask-registry.sh attach-session on resume/spawn). See the sibling `ask-registry`, `dispatch-provenance`, and `merge-scan` manifest entries for those three scripts' own honest_status detail. |
| propagation-engine | writer | manual | no | none | invoked manually or by future PostToolUse wiring (Tranche 6a); not wired in settings.json.template |
| reap-what-you-spawn | pattern | — | no | none | PATTERN — self-applied. The law (reap what you initiate, on every exit path) is doctrine, NOT yet a Mechanism: the code-reviewer/architecture-reviewer lens that would flag timeout-without-kill and spawn-without-tree-kill is proposed in the -full companion but not wired. Golden case: auditor.js runCli timeout-without-kill leaked 781 bash.exe / 3 reboots (fixed 2026-07-14). |
| register-surfacer | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| review-before-deploy | gate | SessionStart, manual | yes | none | Not represented in hooks[] (the schema restricts hooks[] to bare *.sh basenames directly under adapters/claude-code/hooks/, which excludes both scripts/ and hooks/lib/). The actual mechanism: scripts/write-review-record.sh (writer, self-test) + hooks/lib/review-record-gate-lib.sh (shared surface/coverage lib, self-test), consumed by a hard-block splice in adapters/claude-code/install.sh (manual, operator-present) and a fail-open skip+warn splice in adapters/claude-code/hooks/session-start-auto-install.sh (SessionStart -- already separately cataloged under the session-start-auto-install entry, whose own hooks[] is unaffected by this addition). |
| review-finding-fix | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| review-record-commit-gate | gate | PreToolUse | yes | pretool | BLOCKING (exit 2) from day one, at the operator's explicit direction 2026-07-29: 'Why are you suggesting warn mode? If it's valuable, then build and deploy it.' harness-reviewer had recommended warn-mode first; the retroactive measurement supplies the section 10 evidence instead, with its population stated (see fp_expectation). Self-test 25/25 on BOTH bash 5.3 and bash 3.2, including a scenario per live false-positive class. REVIEW HISTORY, recorded because the defects were severe: harness-reviewer returned REJECT on the first version with two Criticals. (1) The gate hashed the WORKING TREE while git commits the INDEX -- the reviewer staged unreviewed content, restored the worktree to a covered blob, and the commit sailed through rc=0. The gate was attesting to bytes it never read. Fixed to read the index; scenario 11 is the regression. (2) The fp_expectation was arithmetically vacuous, as described above. Seven Majors were also fixed: substring-as-intent command matching, unscoped repo identity, `ledger_emit` guarded on a symbol the hook never sourced (so no block was ever recorded), the missing NL-FINDING-016 whole-command-discarded banner, an unvalidated one-character waiver reason, and a --self-test flag on the measurement script that did not exist. SCOPE, honestly: this gate matches `git commit` ONLY. `git push` was deliberately removed -- the push arm checked the INDEX, which is the wrong subject: it blocked pushes over unrelated staged work while giving zero protection against pushing already-committed unreviewed changes, which is literally the golden case's final step. A correct push arm must diff @{u}..HEAD against the records; until that is built, matching push would be pure cost. That is an OPEN GAP, not a closed one. ESCAPE HATCH: REVIEW_RECORD_GATE_OVERRIDE='<reason>' requires a substantive reason (>=20 chars, placeholders rejected) and appends to ~/.claude/state/review-record-gate-overrides.log. HONEST RESIDUAL: nothing yet READS that log -- a self-waiver is recorded but not surfaced to the operator in-session. Also uncovered: commits made outside a harnessed session (another machine, CI, a Decision-011 cloud session with no hooks) and merges from the GitHub web UI. Those remain the deploy-time carriers' job. |
| risk-tiered-verification | pattern | — | no | none | — |
| runtime-verification | gate | Stop | yes | none | invoked via pre-stop-verifier.sh (Stop chain); not directly wired in settings.json.template |
| scheduled-task-health | writer | — | no | none | scripts/scheduled-task-health.sh — one-line-per-task Last-Result report for every NL-owned (NL-*) Windows scheduled task (O.6); called by harness-doctor.sh's check_obs_scheduled_tasks predicate, not event-wired as its own settings.json entry. Reports raw values only; makes no pass/fail judgment itself. |
| secret-hygiene-prepush | gate | prepush | yes | none | wired via git-hooks/pre-push dispatcher (core.hooksPath), not settings.json.template |
| secret-scan-ci-backstop | gate | manual | yes | none | GitHub Actions workflow (.github/workflows/secret-backstop.yml), not a Claude Code hook; events:["manual"] is a schema-gap stand-in for CI push+PR triggers (same convention as the synthetic-runner-ci entry). Re-invokes the EXISTING pre-push-scan.sh + harness-hygiene-scan.sh scripts against the diff range server-side — the compensating control the F.3 disposition on secret-hygiene-prepush's --no-verify bypass required. Deliberately overlaps server-side-enforcement.yml's credential-scan/harness-hygiene jobs (defense-in-depth, documented in the workflow file's header) rather than being the sole CI coverage. |
| session-heartbeat | writer | — | no | none | scripts/session-heartbeat.sh (touch/sweep/reap) + hooks/lib/session-heartbeat-lib.sh (hb_path_for/hb_write/hb_is_stale/hb_classify, the shared C1 read-side implementation) — per-session liveness file (O.2); touch called by one-line splices in session-start-digest.sh / workstreams-stop-writer.sh / pre-compact-continuity.sh / session-resumer.sh, reap called by a best-effort splice in session-start-digest.sh run_digest() (review fix 2026-07-09: reaper previously had no production call-site; bounds the heartbeat set by removing definitively-dead entries), not event-wired as its own settings.json entry. |
| session-honesty | gate | Stop | yes | stop | Invoked by stop-verdict-dispatcher.sh in --report mode (E.11, §E.W); no longer a direct Stop-chain entry. --self-test + blocking logic intact. |
| session-resumer | writer | — | no | none | scripts/session-resumer.sh — OS-scheduled watchdog (E.7); schtasks registration is a §E.W.6 step, not a settings.json hook. |
| session-start-auto-install | writer | SessionStart | no | session-start | — |
| session-start-digest | surfacer | SessionStart | no | session-start | ONE SessionStart digest replacing the transitional surfacer-pack (E.1); wired at §E.W. |
| session-start-surfacer-pack | surfacer | SessionStart | no | session-start | Replaced by session-start-digest.sh at §E.W (E.1); retained on disk, attic at F-wave. |
| signal-ledger-flush | writer | Stop | no | stop | — |
| spawn-task-report-back | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| spec-freeze | gate | PreToolUse | yes | pretool | — |
| stale-plan-surfacer | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| stop-verdict-dispatcher | gate | Stop | yes | stop | E.11 batched Stop verdict; invokes work-integrity/session-honesty/bug-persistence in --report mode, aggregates one verdict; replaces their 3 blocking Stop entries at §E.W (Stop 6->4). pin-f: delegates to the gates that validate purpose clauses. Cold-reader-lint WARN (constitution §3 amendment 53d3bee, operator directive 2026-07-07), following FUNCTIONAL-LINK's own precedent immediately above it in this same file: scans the final assistant message for a §3-format "Decision needed" block and, if it is missing an artifact anchor or per-option outcome text, emits ONE ledger_emit warn + a stderr notice. WARN-only — never contributes to the block/gap verdict above, never participates in cycle-counting/DONE-refusal, never touches stdout. Self-tested (scenarios renumbered 20-23 at batch-integration to avoid colliding with the FIX-2a/FIX-2b automation-ceiling scenarios 18-19 already on master; 3 of 4 pass). KNOWN BUG (found during batch integration, confirmed pre-existing on the source branch in isolation, not introduced by the merge): `_svd_message_has_decision_block`'s heuristic does a naive case-insensitive substring match for `decision needed`, so prose that negates it (e.g. "no decision needed here") still matches and false-positive-warns as a decision block missing an anchor — 1 self-test scenario (ordinary-prose-not-scanned) fails on this. Low severity (WARN-only, never blocks) but real; follow-up filed to require the heuristic to exclude a preceding negation token. |
| stranded-worktree-work | surfacer | — | no | none | — |
| supervisor-tick | surfacer | — | no | none | — |
| synthetic-runner-ci | gate | manual | yes | none | GitHub Actions workflow (.github/workflows/synthetic-runner.yml), not a Claude Code hook; events:["manual"] is a schema-gap stand-in for CI cron+PR triggers. |
| task-verifier-reminder | surfacer | PostToolUse | no | posttool | — |
| tdd-gate | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| teaching-moments | pattern | — | no | none | — |
| vaporware-config-control | pattern | — | no | none | pattern — checked via functionality-verifier's config-control protocol, dispatched by task-verifier (the sole checkbox-flipper) before flipping any Verification: full user-observable task; the flip is mechanically backstopped by plan-edit-validator.sh (blocking PreToolUse — evidence block with a Runtime verification: line required) and work-integrity-gate via stop-verdict-dispatcher.sh (blocking Stop — checked tasks require evidence blocks); standing surfaces via functionality-auditor's registry-vs-callsite sweep; no dedicated hook by design (plan vaporware-config-controls D-2) |
| vaporware-volume | gate | PreToolUse | no | pretool | RETIRED from live PreToolUse 2026-07-06 per synth-ci plan task 2 — coverage relocated to .github/workflows/synthetic-runner.yml (first scheduled live run GREEN: actions/runs/28785582207). Hook file retained for the CI path. |
| verification-dispatch | pattern | manual | no | none | PATTERN, memory-rung, NOT A MECHANISM — stated plainly because constitution s10 calls undelivered enforcement THEATER. This file documents that verifier/reviewer dispatch is standard process and overrides an app-level 'do not call the Agent tool unless the user requested it' default that ships in some Claude Code builds. Nothing enforces it: no hook blocks a commit that skipped verification. The mechanical half that WOULD enforce it is review-before-deploy, whose only carriers are install.sh (hard-block) and session-start-auto-install.sh (fail-open warn) — both at DEPLOY time, never at commit. harness-reviewer's 2026-07-28 REFORMULATE named the commit-time carrier as the single most important fix and noted the enforcement API (rrg_in_surface / rrg_is_covered in hooks/lib/review-record-gate-lib.sh) plus scripts/write-review-record.sh already exist unwired. Tracked as a named gap, not claimed as a control. KNOWN RESIDUAL (same review): rrg_in_surface returns OUT for CLAUDE.md and doctrine/*.md, so the always-loaded operating text and every doctrine compact can be changed with zero review record — the highest-leverage behavior files are outside the review surface. |
| waiver-density-alarm | pattern | — | no | none | scripts/waiver-density.sh — invoked by the digest (--digest-line) + E.5 KPI (--report); not an event-wired hook. |
| wave-d-retired-shims | writer | manual | no | none | Exit-0 shims at retired live paths for one release (live-session safety, ADR 058 D5 pin c); originals in attic/. Hard-delete next release. |
| wire-check | gate | PreToolUse | yes | pretool | — |
| work-integrity | gate | Stop | yes | stop | Invoked by stop-verdict-dispatcher.sh in --report mode (E.11, §E.W); no longer a direct Stop-chain entry. --self-test + blocking logic intact. |
| work-shapes | pattern | — | no | none | — |
| workstream-memory-ecology | pattern | — | no | none | — |
| workstreams-emitters | writer | PostToolUse, PreToolUse, SessionStart, Stop, UserPromptSubmit | no | none | workstreams-emit.sh wired directly (SessionStart + spawn PreToolUse); Stop-side members dispatched via workstreams-stop-writer.sh since D.5. workstreams-extract-pending.sh split out to its own entry (id: workstreams-extract-pending) and retired at O.4 cutover; removed from workstreams-stop-writer.sh's MEMBERS array in the same commit. |
| workstreams-extract-pending | writer | manual | no | none | retired to attic at O.4 cutover (attic + exit-0 shim, per manifest-amendments.md fragment adapters/claude-code/tests/fixtures/wave-o/O.4/manifest-amendments.md Entry 2) — superseded by needs-you.sh per that file's own header; item-extraction from Stop-time transcript scanning is no longer the mechanism. Removed from workstreams-stop-writer.sh's MEMBERS array in the same integration commit. |
| workstreams-stop-gate | gate | Stop | no | stop | retired at D.5 cutover (attic + exit-0 shim); consolidated into the single workstreams Stop writer per ADR 058 D5 / specs-d |
| workstreams-stop-writer | writer | Stop | no | stop | — |
| workstreams-task-binding | gate | SessionStart, Stop | no | stop | retired at D.5 cutover (attic + exit-0 shim); consolidated into the single workstreams Stop writer (D.0 collision resolution) per ADR 058 D5 / specs-d |
| workstreams-turn-emit | writer | manual | no | none | retired to attic at O.4 cutover, unwired — item-extraction is superseded by needs-you.sh; this deterministic every-turn writer was built but never connected to settings.json.template and is no longer needed now that tree-state.json is not the cockpit's truth source. |
| worktree-advisor | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
