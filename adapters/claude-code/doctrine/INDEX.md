# Doctrine INDEX — generated from manifest.json by manifest-check.sh --gen-index

Do not hand-edit: regenerate with `bash adapters/claude-code/scripts/manifest-check.sh --gen-index`.

| id | kind | doctrine | hooks | blocking | honest_status |
|---|---|---|---|---|---|
| acceptance-scenarios | gate | [doctrine/acceptance-scenarios.md](acceptance-scenarios.md) | product-acceptance-gate.sh | yes | — |
| agent-teams | gate | [doctrine/agent-teams.md](agent-teams.md) | task-completed-evidence-gate.sh, task-created-validator.sh, teammate-spawn-validator.sh | yes | — |
| automation-modes | pattern | [doctrine/automation-modes.md](automation-modes.md) | — | no | — |
| background-work-tracking | surfacer | [doctrine/background-work-tracking.md](background-work-tracking.md) | stalled-work-surfacer.sh | no | — |
| backlog-plan-atomicity | gate | [doctrine/planning.md](planning.md) | backlog-plan-atomicity.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| bug-persistence | gate | [doctrine/testing.md](testing.md) | bug-persistence-gate.sh | yes | — |
| claude-md-hygiene | gate | [doctrine/harness-dev.md](harness-dev.md) | claude-md-hygiene-gate.sh | yes | — |
| code-conventions | convention | [doctrine/code-conventions.md](code-conventions.md) | — | no | — |
| completion-criteria | gate | [doctrine/completion-criteria.md](completion-criteria.md) | completion-criteria-gate.sh | yes | — |
| comprehension-gate | pattern | [doctrine/comprehension-gate.md](comprehension-gate.md) | — | no | — |
| consolidation-discipline | pattern | [doctrine/consolidation-discipline.md](consolidation-discipline.md) | — | no | — |
| constitution | pattern | [rules/constitution.md](../rules/constitution.md) | — | no | — |
| cross-repo-drift-gate | gate | [doctrine/git.md](git.md) | cross-repo-drift-postpush-gate.sh | no | — |
| cross-repo-drift-warn | surfacer | [doctrine/git.md](git.md) | cross-repo-drift-warn.sh | no | — |
| customer-facing-review | gate | [doctrine/customer-facing-review.md](customer-facing-review.md) | customer-facing-review-gate.sh | yes | — |
| dag-review-waiver | gate | [doctrine/orchestrator-pattern.md](orchestrator-pattern.md) | dag-review-waiver-gate.sh | yes | — |
| decision-context-emitters | writer | [doctrine/decision-context.md](decision-context.md) | decision-context-pending-surfacer.sh, decision-context-replay.sh, decision-context-reply-emit.sh | no | — |
| decision-context-gate | gate | [doctrine/decision-context.md](decision-context.md) | decision-context-gate.sh | yes | — |
| decisions-index | gate | [doctrine/planning.md](planning.md) | decisions-index-gate.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| definition-on-first-use | gate | [doctrine/definition-on-first-use.md](definition-on-first-use.md) | definition-on-first-use-gate.sh | yes | — |
| deploy-automation-mode | gate | [doctrine/git.md](git.md) | automation-mode-gate.sh | yes | — |
| design-mode-planning | gate | [doctrine/design-mode-planning.md](design-mode-planning.md) | systems-design-gate.sh | yes | — |
| diagnosis | pattern | [doctrine/diagnosis.md](diagnosis.md) | — | no | — |
| discovery-cheatsheet | surfacer | [doctrine/harness-dev.md](harness-dev.md) | session-start-discovery-cheatsheet.sh | no | — |
| discovery-protocol | surfacer | [doctrine/discovery-protocol.md](discovery-protocol.md) | discovery-surfacer.sh | no | — |
| doc-gate | gate | [doctrine/code-conventions.md](code-conventions.md) | doc-gate.sh | no | — |
| docs-freshness | gate | [doctrine/harness-dev.md](harness-dev.md) | docs-freshness-gate.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| effort-policy-warn | surfacer | — | effort-policy-warn.sh | no | — |
| env-local-protection | gate | [doctrine/security.md](security.md) | env-local-protection.sh | yes | — |
| external-monitor-alerts | surfacer | — | external-monitor-alert-surfacer.sh | no | — |
| findings-ledger | gate | [doctrine/findings-ledger.md](findings-ledger.md) | findings-ledger-schema-gate.sh | yes | — |
| friction-reflexion | pattern | [doctrine/friction-reflexion.md](friction-reflexion.md) | — | no | — |
| frontend-conventions | convention | [doctrine/frontend-conventions.md](frontend-conventions.md) | — | no | — |
| gate-respect | pattern | [doctrine/gate-respect.md](gate-respect.md) | — | no | — |
| gh-account-hint | surfacer | [doctrine/git.md](git.md) | gh-account-blindness-hint.sh | no | — |
| git-freshness | surfacer | [doctrine/git.md](git.md) | session-start-git-freshness.sh | no | — |
| harness-doctor | surfacer | [doctrine/harness-dev.md](harness-dev.md) | harness-doctor.sh | no | diagnostic tool — invoked on demand (harness-doctor.sh --quick); chain wiring is a post-Wave-D decision |
| harness-hygiene-scan | gate | [doctrine/harness-dev.md](harness-dev.md) | harness-hygiene-scan.sh | yes | invoked via pre-commit-gate.sh chain and manual --full-tree runs; not directly wired in settings.json.template |
| harness-sync-check | gate | [doctrine/harness-dev.md](harness-dev.md) | check-harness-sync.sh | yes | — |
| interactive-process-fidelity | pattern | [doctrine/interactive-process-fidelity.md](interactive-process-fidelity.md) | — | no | — |
| local-edit-authorization | gate | [doctrine/local-edit-authorization.md](local-edit-authorization.md) | local-edit-gate.sh | yes | — |
| mechanical-evidence | pattern | [doctrine/mechanical-evidence.md](mechanical-evidence.md) | — | no | — |
| migration-claude-md | gate | [doctrine/code-conventions.md](code-conventions.md) | migration-claude-md-gate.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| narrate-and-wait | gate | [doctrine/session-end-protocol.md](session-end-protocol.md) | narrate-and-wait-gate.sh | yes | — |
| narrative-integrity | gate | [doctrine/claims.md](claims.md) | deferral-counter.sh, goal-coverage-on-stop.sh, goal-extraction-on-prompt.sh, imperative-evidence-linker.sh, transcript-lie-detector.sh | yes | — |
| no-test-skip | gate | [doctrine/testing.md](testing.md) | no-test-skip-gate.sh | yes | — |
| observed-errors-first | gate | [doctrine/observed-errors-first.md](observed-errors-first.md) | observed-errors-gate.sh | yes | — |
| outcome-evidence | gate | [doctrine/testing.md](testing.md) | outcome-evidence-gate.sh | yes | — |
| parallel-dev-migration-naming | gate | [doctrine/parallel-dev-discipline.md](parallel-dev-discipline.md) | migration-naming-gate.sh | yes | — |
| plan-deletion-protection | gate | [doctrine/planning.md](planning.md) | plan-deletion-protection.sh | yes | — |
| plan-edit-validator | gate | [doctrine/planning.md](planning.md) | plan-edit-validator.sh | yes | — |
| plan-lifecycle | writer | [doctrine/planning.md](planning.md) | plan-auto-closure.sh, plan-lifecycle.sh, plan-status-archival-sweep.sh | no | — |
| plan-reviewer | gate | [doctrine/planning.md](planning.md) | plan-reviewer.sh | yes | invoked via pre-commit-gate.sh chain and plan-edit flows; not directly wired in settings.json.template |
| pr-health-snapshot | gate | [doctrine/pr-health-snapshot.md](pr-health-snapshot.md) | pr-health-snapshot-gate.sh | yes | — |
| pr-template-inline | gate | [doctrine/planning.md](planning.md) | pr-template-inline-gate.sh | yes | — |
| prd-validity | gate | [doctrine/prd-validity.md](prd-validity.md) | prd-validity-gate.sh | yes | — |
| pre-commit-chain | gate | — | pre-commit-gate.sh | yes | — |
| pre-push-divergence | gate | [doctrine/git.md](git.md) | pre-push-divergence-check.sh | yes | wired via git-hooks/pre-push dispatcher (core.hooksPath), not settings.json.template |
| pre-push-test | gate | [doctrine/testing.md](testing.md) | pre-push-test-gate.sh | yes | wired via git-hooks/pre-push dispatcher (core.hooksPath) with per-repo opt-in marker; not settings.json.template |
| pre-stop-verifier | gate | [doctrine/planning.md](planning.md) | pre-stop-verifier.sh | yes | — |
| principles-compliance | gate | [doctrine/principles-full.md](principles-full.md) | principles-compliance-gate.sh | no | — |
| propagation-engine | writer | — | propagation-trigger-router.sh | no | invoked manually or by future PostToolUse wiring (Tranche 6a); not wired in settings.json.template |
| register-progress | gate | [doctrine/session-end-protocol.md](session-end-protocol.md) | register-progress-gate.sh | yes | — |
| register-surfacer | surfacer | [doctrine/session-end-protocol.md](session-end-protocol.md) | register-surfacer.sh | no | — |
| review-finding-fix | gate | [doctrine/testing.md](testing.md) | review-finding-fix-gate.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| risk-tiered-verification | pattern | [doctrine/risk-tiered-verification.md](risk-tiered-verification.md) | — | no | — |
| runtime-verification | gate | [doctrine/vaporware-prevention.md](vaporware-prevention.md) | runtime-verification-executor.sh, runtime-verification-reviewer.sh | yes | invoked via pre-stop-verifier.sh (Stop chain); not directly wired in settings.json.template |
| secret-hygiene-prepush | gate | [doctrine/security.md](security.md) | pre-push-scan.sh | yes | wired via git-hooks/pre-push dispatcher (core.hooksPath), not settings.json.template |
| session-end-marker | gate | [doctrine/session-end-protocol.md](session-end-protocol.md) | continuation-enforcer.sh | yes | pending Wave D (D.3 session-honesty-gate) — hook exists with green self-tests but is not wired into the live Stop chain |
| session-start-auto-install | writer | [doctrine/harness-dev.md](harness-dev.md) | session-start-auto-install.sh | no | — |
| settings-divergence | surfacer | [doctrine/harness-dev.md](harness-dev.md) | settings-divergence-detector.sh | no | — |
| spawn-task-report-back | surfacer | [doctrine/spawn-task-report-back.md](spawn-task-report-back.md) | spawned-task-result-surfacer.sh | no | — |
| spec-freeze | gate | [doctrine/spec-freeze.md](spec-freeze.md) | scope-enforcement-gate.sh, spec-freeze-gate.sh | yes | — |
| stale-plan-surfacer | surfacer | [doctrine/planning.md](planning.md) | stale-active-plan-surfacer.sh | no | — |
| task-verifier-reminder | surfacer | [doctrine/planning.md](planning.md) | post-tool-task-verifier-reminder.sh | no | — |
| tdd-gate | gate | [doctrine/testing.md](testing.md) | pre-commit-tdd-gate.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| teaching-moments | pattern | [doctrine/teaching-moments.md](teaching-moments.md) | — | no | — |
| tool-call-budget | gate | [doctrine/orchestrator-pattern.md](orchestrator-pattern.md) | tool-call-budget.sh | yes | — |
| vaporware-volume | gate | [doctrine/vaporware-prevention.md](vaporware-prevention.md) | vaporware-volume-gate.sh | yes | — |
| wire-check | gate | [doctrine/planning.md](planning.md) | wire-check-gate.sh | yes | — |
| work-shapes | pattern | [doctrine/work-shapes.md](work-shapes.md) | — | no | — |
| workstream-memory-ecology | pattern | [doctrine/workstream-memory-ecology.md](workstream-memory-ecology.md) | — | no | — |
| workstreams-emitters | writer | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-extract-pending.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh | no | — |
| workstreams-spawn-gate | gate | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-state-gate.sh | yes | — |
| workstreams-stop-gate | gate | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-stop-gate.sh | yes | — |
| workstreams-task-binding | gate | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-task-binding.sh | yes | — |
| workstreams-turn-emit | writer | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-turn-emit.sh | no | pending wiring — deterministic every-turn writer exists with green self-tests but is not wired in settings.json.template (doctor claim-honesty item) |
| worktree-advisor | surfacer | [doctrine/worktree-isolation.md](worktree-isolation.md) | session-start-worktree-advisor.sh | no | — |
| worktree-teardown | gate | [doctrine/worktree-isolation.md](worktree-isolation.md) | worktree-teardown-gate.sh | yes | — |
