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
| Total manifest entries | 100 |
| Unique hook scripts | 101 |
| Blocking gates (`blocking: true`) | 32 |

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
| PostToolUse | workstreams-emitters | writer | no | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-extract-pending.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh |
| PreCompact | pre-compact-continuity | writer | no | pre-compact-continuity.sh |
| PreToolUse | agent-teams | gate | yes | task-completed-evidence-gate.sh, task-created-validator.sh, teammate-spawn-validator.sh |
| PreToolUse | claude-md-hygiene | gate | yes | claude-md-hygiene-gate.sh |
| PreToolUse | cross-repo-nl-touch-warn | surfacer | no | cross-repo-nl-touch-warn.sh |
| PreToolUse | definition-on-first-use | gate | no | definition-on-first-use-gate.sh |
| PreToolUse | deploy-automation-mode | gate | yes | automation-mode-gate.sh |
| PreToolUse | design-mode-planning | gate | no | systems-design-gate.sh |
| PreToolUse | doc-gate | gate | no | doc-gate.sh |
| PreToolUse | env-local-protection | gate | yes | env-local-protection.sh |
| PreToolUse | findings-ledger | gate | yes | findings-ledger-schema-gate.sh |
| PreToolUse | local-edit-authorization | gate | yes | local-edit-gate.sh |
| PreToolUse | no-test-skip | gate | yes | no-test-skip-gate.sh |
| PreToolUse | observed-errors-first | gate | no | observed-errors-gate.sh |
| PreToolUse | outcome-evidence | gate | no | outcome-evidence-gate.sh |
| PreToolUse | parallel-dev-migration-naming | gate | yes | migration-naming-gate.sh |
| PreToolUse | plan-deletion-protection | gate | yes | plan-deletion-protection.sh |
| PreToolUse | plan-edit-validator | gate | yes | plan-edit-validator.sh |
| PreToolUse | pr-template-inline | gate | no | pr-template-inline-gate.sh |
| PreToolUse | prd-validity | gate | no | prd-validity-gate.sh |
| PreToolUse | pre-commit-chain | gate | yes | pre-commit-gate.sh |
| PreToolUse | spec-freeze | gate | yes | scope-enforcement-gate.sh, spec-freeze-gate.sh |
| PreToolUse | vaporware-volume | gate | yes | vaporware-volume-gate.sh |
| PreToolUse | wire-check | gate | yes | wire-check-gate.sh |
| PreToolUse | workstreams-emitters | writer | no | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-extract-pending.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh |
| PreToolUse | workstreams-spawn-gate | gate | yes | workstreams-state-gate.sh |
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
| SessionStart | session-start-auto-install | writer | no | session-start-auto-install.sh |
| SessionStart | session-start-digest | surfacer | no | session-start-digest.sh |
| SessionStart | session-start-surfacer-pack | surfacer | no | session-start-surfacer-pack.sh |
| SessionStart | spawn-task-report-back | surfacer | no | spawned-task-result-surfacer.sh |
| SessionStart | stale-plan-surfacer | surfacer | no | stale-active-plan-surfacer.sh |
| SessionStart | workstreams-emitters | writer | no | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-extract-pending.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh |
| SessionStart | workstreams-task-binding | gate | no | workstreams-task-binding.sh |
| SessionStart | worktree-advisor | surfacer | no | session-start-worktree-advisor.sh |
| Stop | bug-persistence | gate | yes | bug-persistence-gate.sh |
| Stop | runtime-verification | gate | yes | runtime-verification-executor.sh, runtime-verification-reviewer.sh |
| Stop | session-honesty | gate | yes | session-honesty-gate.sh |
| Stop | signal-ledger-flush | writer | no | signal-ledger-flush.sh |
| Stop | stop-verdict-dispatcher | gate | yes | stop-verdict-dispatcher.sh |
| Stop | work-integrity | gate | yes | work-integrity-gate.sh |
| Stop | workstreams-emitters | writer | no | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-extract-pending.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh |
| Stop | workstreams-stop-gate | gate | no | workstreams-stop-gate.sh |
| Stop | workstreams-stop-writer | writer | no | workstreams-stop-writer.sh |
| Stop | workstreams-task-binding | gate | no | workstreams-task-binding.sh |
| TaskCompleted | agent-teams | gate | yes | task-completed-evidence-gate.sh, task-created-validator.sh, teammate-spawn-validator.sh |
| TaskCreated | agent-teams | gate | yes | task-completed-evidence-gate.sh, task-created-validator.sh, teammate-spawn-validator.sh |
| UserPromptSubmit | decision-context-emitters | writer | no | decision-context-pending-surfacer.sh, decision-context-reply-emit.sh |
| UserPromptSubmit | workstreams-emitters | writer | no | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-extract-pending.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh |
| manual | harness-doctor | surfacer | no | harness-doctor.sh |
| manual | harness-hygiene-scan | gate | yes | harness-hygiene-scan.sh |
| manual | plan-reviewer | gate | yes | plan-reviewer.sh |
| manual | propagation-engine | writer | no | propagation-trigger-router.sh |
| manual | synthetic-runner-ci | gate | yes | — |
| manual | wave-d-retired-shims | writer | no | check-harness-sync.sh, completion-criteria-gate.sh, continuation-enforcer.sh, cross-repo-drift-warn.sh, customer-facing-review-gate.sh, dag-review-waiver-gate.sh, decision-context-gate.sh, decision-context-replay.sh, deferral-counter.sh, goal-coverage-on-stop.sh, goal-extraction-on-prompt.sh, imperative-evidence-linker.sh, narrate-and-wait-gate.sh, pr-health-snapshot-gate.sh, pre-stop-verifier.sh, principles-compliance-gate.sh, product-acceptance-gate.sh, register-progress-gate.sh, settings-divergence-detector.sh, tool-call-budget.sh, transcript-lie-detector.sh, worktree-teardown-gate.sh |
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
| gate | 32 | 10 |
| writer | 0 | 18 |
| surfacer | 0 | 16 |
| pattern | 0 | 22 |
| convention | 0 | 2 |

## Budgets

Per §F.1 (`blocking-budget-check.js`): blocking gates ≤ 12 (counted structurally
here as manifest `blocking:true` entries — the F.1 budget check counts the same
field against the SAME-EVENT-CHAIN definition; see that check's own doc for the
distinction between total blocking:true entries and blocking CHAIN POSITIONS).

| budget_class | entries |
|---|---|
| stop | 8 |
| session-start | 15 |
| pretool | 23 |
| posttool | 6 |
| none | 48 |

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
| doctrine/automation-modes.md | 1 (automation-modes) |
| doctrine/background-work-tracking.md | 1 (background-work-tracking) |
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
| doctrine/findings-ledger.md | 1 (findings-ledger) |
| doctrine/friction-reflexion.md | 1 (friction-reflexion) |
| doctrine/frontend-conventions.md | 1 (frontend-conventions) |
| doctrine/gate-respect.md | 1 (gate-respect) |
| doctrine/git.md | 5 (cross-repo-drift-gate, deploy-automation-mode, gh-account-hint, git-freshness, pre-push-divergence) |
| doctrine/harness-dev.md | 9 (claude-md-hygiene, discovery-cheatsheet, docs-freshness, harness-doctor, harness-hygiene-scan, session-start-auto-install, session-start-surfacer-pack, signal-ledger-flush, wave-d-retired-shims) |
| doctrine/interactive-process-fidelity.md | 1 (interactive-process-fidelity) |
| doctrine/local-edit-authorization.md | 1 (local-edit-authorization) |
| doctrine/mechanical-evidence.md | 1 (mechanical-evidence) |
| doctrine/observed-errors-first.md | 1 (observed-errors-first) |
| doctrine/orchestrator-pattern.md | 1 (orchestrator-pattern) |
| doctrine/parallel-dev-discipline.md | 1 (parallel-dev-migration-naming) |
| doctrine/planning.md | 11 (backlog-plan-atomicity, decisions-index, plan-deletion-protection, plan-edit-validator, plan-lifecycle, plan-reviewer, pr-template-inline, stale-plan-surfacer, task-verifier-reminder, wire-check, work-integrity) |
| doctrine/pr-health-snapshot.md | 1 (pr-health-snapshot) |
| doctrine/prd-validity.md | 1 (prd-validity) |
| doctrine/risk-tiered-verification.md | 1 (risk-tiered-verification) |
| doctrine/security.md | 2 (env-local-protection, secret-hygiene-prepush) |
| doctrine/session-end-protocol.md | 2 (register-surfacer, session-honesty) |
| doctrine/spawn-task-report-back.md | 1 (spawn-task-report-back) |
| doctrine/spec-freeze.md | 1 (spec-freeze) |
| doctrine/teaching-moments.md | 1 (teaching-moments) |
| doctrine/testing.md | 6 (bug-persistence, no-test-skip, outcome-evidence, pre-push-test, review-finding-fix, tdd-gate) |
| doctrine/vaporware-prevention.md | 2 (runtime-verification, vaporware-volume) |
| doctrine/work-shapes.md | 1 (work-shapes) |
| doctrine/workstream-memory-ecology.md | 1 (workstream-memory-ecology) |
| doctrine/workstreams-state.md | 6 (workstreams-emitters, workstreams-spawn-gate, workstreams-stop-gate, workstreams-stop-writer, workstreams-task-binding, workstreams-turn-emit) |
| doctrine/worktree-isolation.md | 1 (worktree-advisor) |
| rules/constitution.md | 1 (constitution) |

Entries with no doctrine_file (`-`): 20.

## Full entry listing

| id | kind | events | blocking | budget_class | honest_status |
|---|---|---|---|---|---|
| acceptance-scenarios | pattern | — | no | none | — |
| agent-teams | gate | PreToolUse, TaskCompleted, TaskCreated | yes | pretool | — |
| automation-modes | pattern | — | no | none | — |
| background-work-tracking | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| backlog-plan-atomicity | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| bug-persistence | gate | Stop | yes | stop | Invoked by stop-verdict-dispatcher.sh in --report mode (E.11, §E.W); no longer a direct Stop-chain entry. --self-test + blocking logic intact. |
| claims | pattern | — | no | none | — |
| claude-md-hygiene | gate | PreToolUse | yes | pretool | — |
| code-conventions | convention | — | no | none | — |
| completion-criteria | pattern | — | no | none | — |
| comprehension-gate | pattern | — | no | none | — |
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
| doc-gate | gate | PreToolUse | no | pretool | — |
| docs-freshness | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| doctrine-jit | writer | PostToolUse | no | posttool | — |
| effort-policy-warn | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| end-manifest | writer | — | no | none | scripts/end-manifest.sh (E.12) — session end-manifest writer+validator; invoked by the dispatcher when a manifest is present, not event-wired. |
| env-local-protection | gate | PreToolUse | yes | pretool | — |
| external-monitor-alerts | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| findings-ledger | gate | PreToolUse | yes | pretool | — |
| friction-reflexion | pattern | — | no | none | — |
| frontend-conventions | convention | — | no | none | — |
| gate-demotion | pattern | — | no | none | — |
| gate-respect | pattern | — | no | none | — |
| gen-architecture-doc | writer | — | no | none | scripts/gen-architecture-doc.sh (F.2) -- regenerates docs/harness-architecture.md from manifest.json; --check is the doctor drift predicate (tests/fixtures/wave-f/F.2/doctor-predicate.md); not event-wired (manual + doctor-invoked). |
| gh-account-hint | surfacer | PostToolUse, SessionStart | no | posttool | — |
| git-freshness | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| harness-changelog | writer | — | no | none | scripts/harness-changelog.sh (F.2b) -- machine-wide 'what's new' ledger + --digest-line consumed by session-start-digest.sh's feed 15; not event-wired. |
| harness-doctor | surfacer | SessionStart, manual | no | session-start | diagnostic tool — invoked on demand (harness-doctor.sh --quick); chain wiring is a post-Wave-D decision |
| harness-hygiene-scan | gate | manual, precommit | yes | none | invoked via pre-commit-gate.sh chain and manual --full-tree runs; not directly wired in settings.json.template |
| harness-kpis | writer | — | no | none | scripts/harness-kpis.sh — weekly KPI report from the signal ledger (E.5); scheduled-task registration documented, not a hook. |
| interactive-process-fidelity | pattern | — | no | none | — |
| local-edit-authorization | gate | PreToolUse | yes | pretool | — |
| mechanical-evidence | pattern | — | no | none | — |
| migration-claude-md | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| needs-you-ledger | writer | — | no | none | scripts/needs-you.sh — maintains NEEDS-YOU.md (E.6); called by decision-log flow + digest, not event-wired. |
| nl-issue-capture-loop | pattern | — | no | none | scripts/nl-issue.sh + skill (E.8) — cross-project capture; not event-wired. |
| no-test-skip | gate | PreToolUse | yes | pretool | — |
| observed-errors-first | gate | PreToolUse | no | pretool | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| orchestrator-pattern | pattern | — | no | none | — |
| outcome-evidence | gate | PreToolUse | no | pretool | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| parallel-dev-migration-naming | gate | PreToolUse | yes | pretool | — |
| plan-deletion-protection | gate | PreToolUse | yes | pretool | — |
| plan-edit-validator | gate | PreToolUse | yes | pretool | — |
| plan-lifecycle | writer | PostToolUse, SessionStart | no | posttool | plan-status-archival-sweep.sh dispatched via session-start-surfacer-pack.sh since D.5; plan-auto-closure.sh/plan-lifecycle.sh fire on PostToolUse as before. |
| plan-reviewer | gate | manual, precommit | yes | none | invoked via pre-commit-gate.sh chain and plan-edit flows; not directly wired in settings.json.template |
| pr-health-snapshot | pattern | — | no | none | — |
| pr-template-inline | gate | PreToolUse | no | pretool | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| prd-validity | gate | PreToolUse | no | pretool | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| pre-commit-chain | gate | PreToolUse | yes | pretool | — |
| pre-compact-continuity | writer | PreCompact | no | none | E.9b PreCompact backstop; wired (auto+manual) at §E.W. PreCompact additionalContext channel HYPOTHESIZED on this CC version; snapshot-file + SessionStart compact-echo is the PROVEN fallback (constitution §1). |
| pre-push-divergence | gate | prepush | yes | none | wired via git-hooks/pre-push dispatcher (core.hooksPath), not settings.json.template |
| pre-push-test | gate | prepush | yes | none | wired via git-hooks/pre-push dispatcher (core.hooksPath) with per-repo opt-in marker; not settings.json.template |
| propagation-engine | writer | manual | no | none | invoked manually or by future PostToolUse wiring (Tranche 6a); not wired in settings.json.template |
| register-surfacer | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| review-finding-fix | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| risk-tiered-verification | pattern | — | no | none | — |
| runtime-verification | gate | Stop | yes | none | invoked via pre-stop-verifier.sh (Stop chain); not directly wired in settings.json.template |
| secret-hygiene-prepush | gate | prepush | yes | none | wired via git-hooks/pre-push dispatcher (core.hooksPath), not settings.json.template |
| session-honesty | gate | Stop | yes | stop | Invoked by stop-verdict-dispatcher.sh in --report mode (E.11, §E.W); no longer a direct Stop-chain entry. --self-test + blocking logic intact. |
| session-resumer | writer | — | no | none | scripts/session-resumer.sh — OS-scheduled watchdog (E.7); schtasks registration is a §E.W.6 step, not a settings.json hook. |
| session-start-auto-install | writer | SessionStart | no | session-start | — |
| session-start-digest | surfacer | SessionStart | no | session-start | ONE SessionStart digest replacing the transitional surfacer-pack (E.1); wired at §E.W. |
| session-start-surfacer-pack | surfacer | SessionStart | no | session-start | Replaced by session-start-digest.sh at §E.W (E.1); retained on disk, attic at F-wave. |
| signal-ledger-flush | writer | Stop | no | stop | — |
| spawn-task-report-back | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| spec-freeze | gate | PreToolUse | yes | pretool | — |
| stale-plan-surfacer | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| stop-verdict-dispatcher | gate | Stop | yes | stop | E.11 batched Stop verdict; invokes work-integrity/session-honesty/bug-persistence in --report mode, aggregates one verdict; replaces their 3 blocking Stop entries at §E.W (Stop 6->4). pin-f: delegates to the gates that validate purpose clauses. |
| synthetic-runner-ci | gate | manual | yes | none | GitHub Actions workflow (.github/workflows/synthetic-runner.yml), not a Claude Code hook; events:["manual"] is a schema-gap stand-in for CI cron+PR triggers. |
| task-verifier-reminder | surfacer | PostToolUse | no | posttool | — |
| tdd-gate | gate | precommit | yes | none | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| teaching-moments | pattern | — | no | none | — |
| vaporware-volume | gate | PreToolUse | yes | pretool | Member of the commit-boundary blocking unit (specs-d §D.0.4 as amended at D.5); CI relocation follows in E.4 companion. |
| waiver-density-alarm | pattern | — | no | none | scripts/waiver-density.sh — invoked by the digest (--digest-line) + E.5 KPI (--report); not an event-wired hook. |
| wave-d-retired-shims | writer | manual | no | none | Exit-0 shims at retired live paths for one release (live-session safety, ADR 058 D5 pin c); originals in attic/. Hard-delete next release. |
| wire-check | gate | PreToolUse | yes | pretool | — |
| work-integrity | gate | Stop | yes | stop | Invoked by stop-verdict-dispatcher.sh in --report mode (E.11, §E.W); no longer a direct Stop-chain entry. --self-test + blocking logic intact. |
| work-shapes | pattern | — | no | none | — |
| workstream-memory-ecology | pattern | — | no | none | — |
| workstreams-emitters | writer | PostToolUse, PreToolUse, SessionStart, Stop, UserPromptSubmit | no | none | workstreams-emit.sh wired directly (SessionStart + spawn PreToolUse); Stop-side members dispatched via workstreams-stop-writer.sh since D.5. |
| workstreams-spawn-gate | gate | PreToolUse | yes | pretool | — |
| workstreams-stop-gate | gate | Stop | no | stop | retired at D.5 cutover (attic + exit-0 shim); consolidated into the single workstreams Stop writer per ADR 058 D5 / specs-d |
| workstreams-stop-writer | writer | Stop | no | stop | — |
| workstreams-task-binding | gate | SessionStart, Stop | no | stop | retired at D.5 cutover (attic + exit-0 shim); consolidated into the single workstreams Stop writer (D.0 collision resolution) per ADR 058 D5 / specs-d |
| workstreams-turn-emit | writer | manual | no | none | pending wiring — deterministic every-turn writer exists with green self-tests but is not wired in settings.json.template (doctor claim-honesty item) |
| worktree-advisor | surfacer | SessionStart | no | session-start | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
