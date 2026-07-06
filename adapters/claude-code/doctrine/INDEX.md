# Doctrine INDEX — generated from manifest.json by manifest-check.sh --gen-index

Do not hand-edit: regenerate with `bash adapters/claude-code/scripts/manifest-check.sh --gen-index`.

| id | kind | doctrine | hooks | blocking | honest_status |
|---|---|---|---|---|---|
| agent-teams | gate | [doctrine/agent-teams.md](agent-teams.md) | task-completed-evidence-gate.sh, task-created-validator.sh, teammate-spawn-validator.sh | yes | — |
| automation-modes | pattern | [doctrine/automation-modes.md](automation-modes.md) | — | no | — |
| background-work-tracking | surfacer | [doctrine/background-work-tracking.md](background-work-tracking.md) | stalled-work-surfacer.sh | no | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| backlog-plan-atomicity | gate | [doctrine/planning.md](planning.md) | backlog-plan-atomicity.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| bug-persistence | gate | [doctrine/testing.md](testing.md) | bug-persistence-gate.sh | yes | Invoked by stop-verdict-dispatcher.sh in --report mode (E.11, §E.W); no longer a direct Stop-chain entry. --self-test + blocking logic intact. |
| claude-md-hygiene | gate | [doctrine/harness-dev.md](harness-dev.md) | claude-md-hygiene-gate.sh | yes | — |
| code-conventions | convention | [doctrine/code-conventions.md](code-conventions.md) | — | no | — |
| comprehension-gate | pattern | [doctrine/comprehension-gate.md](comprehension-gate.md) | — | no | — |
| consolidation-discipline | pattern | [doctrine/consolidation-discipline.md](consolidation-discipline.md) | — | no | — |
| constitution | pattern | [rules/constitution.md](../rules/constitution.md) | — | no | — |
| context-watermark | writer | — | context-watermark.sh | no | E.9a early-warning context watermark; wired PostToolUse at §E.W. |
| cross-repo-drift-gate | gate | [doctrine/git.md](git.md) | cross-repo-drift-postpush-gate.sh | no | — |
| decision-context-emitters | writer | [doctrine/decision-context.md](decision-context.md) | decision-context-pending-surfacer.sh, decision-context-reply-emit.sh | no | replay retired to attic (fence retirement, D.4/D.5); pending-surfacer dispatched via surfacer-pack; reply-emit wired at UserPromptSubmit. |
| decisions-index | gate | [doctrine/planning.md](planning.md) | decisions-index-gate.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| definition-on-first-use | gate | [doctrine/definition-on-first-use.md](definition-on-first-use.md) | definition-on-first-use-gate.sh | no | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| deploy-automation-mode | gate | [doctrine/git.md](git.md) | automation-mode-gate.sh | yes | — |
| design-mode-planning | gate | [doctrine/design-mode-planning.md](design-mode-planning.md) | systems-design-gate.sh | no | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| diagnosis | pattern | [doctrine/diagnosis.md](diagnosis.md) | — | no | — |
| discovery-cheatsheet | surfacer | [doctrine/harness-dev.md](harness-dev.md) | session-start-discovery-cheatsheet.sh | no | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| discovery-protocol | surfacer | [doctrine/discovery-protocol.md](discovery-protocol.md) | discovery-surfacer.sh | no | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| doc-gate | gate | [doctrine/code-conventions.md](code-conventions.md) | doc-gate.sh | no | — |
| docs-freshness | gate | [doctrine/harness-dev.md](harness-dev.md) | docs-freshness-gate.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| doctrine-jit | writer | — | doctrine-jit.sh | no | — |
| effort-policy-warn | surfacer | — | effort-policy-warn.sh | no | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| end-manifest | writer | — | — | no | scripts/end-manifest.sh (E.12) — session end-manifest writer+validator; invoked by the dispatcher when a manifest is present, not event-wired. |
| env-local-protection | gate | [doctrine/security.md](security.md) | env-local-protection.sh | yes | — |
| external-monitor-alerts | surfacer | — | external-monitor-alert-surfacer.sh | no | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| findings-ledger | gate | [doctrine/findings-ledger.md](findings-ledger.md) | findings-ledger-schema-gate.sh | yes | — |
| friction-reflexion | pattern | [doctrine/friction-reflexion.md](friction-reflexion.md) | — | no | — |
| frontend-conventions | convention | [doctrine/frontend-conventions.md](frontend-conventions.md) | — | no | — |
| gate-respect | pattern | [doctrine/gate-respect.md](gate-respect.md) | — | no | — |
| gh-account-hint | surfacer | [doctrine/git.md](git.md) | gh-account-blindness-hint.sh | no | — |
| git-freshness | surfacer | [doctrine/git.md](git.md) | session-start-git-freshness.sh | no | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| harness-doctor | surfacer | [doctrine/harness-dev.md](harness-dev.md) | harness-doctor.sh | no | diagnostic tool — invoked on demand (harness-doctor.sh --quick); chain wiring is a post-Wave-D decision |
| harness-hygiene-scan | gate | [doctrine/harness-dev.md](harness-dev.md) | harness-hygiene-scan.sh | yes | invoked via pre-commit-gate.sh chain and manual --full-tree runs; not directly wired in settings.json.template |
| harness-kpis | writer | — | — | no | scripts/harness-kpis.sh — weekly KPI report from the signal ledger (E.5); scheduled-task registration documented, not a hook. |
| interactive-process-fidelity | pattern | [doctrine/interactive-process-fidelity.md](interactive-process-fidelity.md) | — | no | — |
| local-edit-authorization | gate | [doctrine/local-edit-authorization.md](local-edit-authorization.md) | local-edit-gate.sh | yes | — |
| mechanical-evidence | pattern | [doctrine/mechanical-evidence.md](mechanical-evidence.md) | — | no | — |
| migration-claude-md | gate | [doctrine/code-conventions.md](code-conventions.md) | migration-claude-md-gate.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| needs-you-ledger | writer | — | — | no | scripts/needs-you.sh — maintains NEEDS-YOU.md (E.6); called by decision-log flow + digest, not event-wired. |
| nl-issue-capture-loop | pattern | — | — | no | scripts/nl-issue.sh + skill (E.8) — cross-project capture; not event-wired. |
| no-test-skip | gate | [doctrine/testing.md](testing.md) | no-test-skip-gate.sh | yes | — |
| observed-errors-first | gate | [doctrine/observed-errors-first.md](observed-errors-first.md) | observed-errors-gate.sh | no | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| outcome-evidence | gate | [doctrine/testing.md](testing.md) | outcome-evidence-gate.sh | no | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| parallel-dev-migration-naming | gate | [doctrine/parallel-dev-discipline.md](parallel-dev-discipline.md) | migration-naming-gate.sh | yes | — |
| plan-deletion-protection | gate | [doctrine/planning.md](planning.md) | plan-deletion-protection.sh | yes | — |
| plan-edit-validator | gate | [doctrine/planning.md](planning.md) | plan-edit-validator.sh | yes | — |
| plan-lifecycle | writer | [doctrine/planning.md](planning.md) | plan-auto-closure.sh, plan-lifecycle.sh, plan-status-archival-sweep.sh | no | plan-status-archival-sweep.sh dispatched via session-start-surfacer-pack.sh since D.5; plan-auto-closure.sh/plan-lifecycle.sh fire on PostToolUse as before. |
| plan-reviewer | gate | [doctrine/planning.md](planning.md) | plan-reviewer.sh | yes | invoked via pre-commit-gate.sh chain and plan-edit flows; not directly wired in settings.json.template |
| pr-template-inline | gate | [doctrine/planning.md](planning.md) | pr-template-inline-gate.sh | no | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| prd-validity | gate | [doctrine/prd-validity.md](prd-validity.md) | prd-validity-gate.sh | no | Demoted to warn (exit 0 + additionalContext + ledger event) at Wave D.6 per specs-d §D.0.4. |
| pre-commit-chain | gate | — | pre-commit-gate.sh | yes | — |
| pre-compact-continuity | writer | — | pre-compact-continuity.sh | no | E.9b PreCompact backstop; wired (auto+manual) at §E.W. PreCompact additionalContext channel HYPOTHESIZED on this CC version; snapshot-file + SessionStart compact-echo is the PROVEN fallback (constitution §1). |
| pre-push-divergence | gate | [doctrine/git.md](git.md) | pre-push-divergence-check.sh | yes | wired via git-hooks/pre-push dispatcher (core.hooksPath), not settings.json.template |
| pre-push-test | gate | [doctrine/testing.md](testing.md) | pre-push-test-gate.sh | yes | wired via git-hooks/pre-push dispatcher (core.hooksPath) with per-repo opt-in marker; not settings.json.template |
| propagation-engine | writer | — | propagation-trigger-router.sh | no | invoked manually or by future PostToolUse wiring (Tranche 6a); not wired in settings.json.template |
| register-surfacer | surfacer | [doctrine/session-end-protocol.md](session-end-protocol.md) | register-surfacer.sh | no | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| review-finding-fix | gate | [doctrine/testing.md](testing.md) | review-finding-fix-gate.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| risk-tiered-verification | pattern | [doctrine/risk-tiered-verification.md](risk-tiered-verification.md) | — | no | — |
| runtime-verification | gate | [doctrine/vaporware-prevention.md](vaporware-prevention.md) | runtime-verification-executor.sh, runtime-verification-reviewer.sh | yes | invoked via pre-stop-verifier.sh (Stop chain); not directly wired in settings.json.template |
| secret-hygiene-prepush | gate | [doctrine/security.md](security.md) | pre-push-scan.sh | yes | wired via git-hooks/pre-push dispatcher (core.hooksPath), not settings.json.template |
| session-honesty | gate | [doctrine/session-end-protocol.md](session-end-protocol.md) | session-honesty-gate.sh | yes | Invoked by stop-verdict-dispatcher.sh in --report mode (E.11, §E.W); no longer a direct Stop-chain entry. --self-test + blocking logic intact. |
| session-resumer | writer | — | — | no | scripts/session-resumer.sh — OS-scheduled watchdog (E.7); schtasks registration is a §E.W.6 step, not a settings.json hook. |
| session-start-auto-install | writer | [doctrine/harness-dev.md](harness-dev.md) | session-start-auto-install.sh | no | — |
| session-start-digest | surfacer | — | session-start-digest.sh | no | ONE SessionStart digest replacing the transitional surfacer-pack (E.1); wired at §E.W. |
| session-start-surfacer-pack | surfacer | [doctrine/harness-dev.md](harness-dev.md) | session-start-surfacer-pack.sh | no | Replaced by session-start-digest.sh at §E.W (E.1); retained on disk, attic at F-wave. |
| signal-ledger-flush | writer | [doctrine/harness-dev.md](harness-dev.md) | signal-ledger-flush.sh | no | — |
| spawn-task-report-back | surfacer | [doctrine/spawn-task-report-back.md](spawn-task-report-back.md) | spawned-task-result-surfacer.sh | no | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| spec-freeze | gate | [doctrine/spec-freeze.md](spec-freeze.md) | scope-enforcement-gate.sh, spec-freeze-gate.sh | yes | — |
| stale-plan-surfacer | surfacer | [doctrine/planning.md](planning.md) | stale-active-plan-surfacer.sh | no | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
| stop-verdict-dispatcher | gate | — | stop-verdict-dispatcher.sh | yes | E.11 batched Stop verdict; invokes work-integrity/session-honesty/bug-persistence in --report mode, aggregates one verdict; replaces their 3 blocking Stop entries at §E.W (Stop 6->4). pin-f: delegates to the gates that validate purpose clauses. |
| synthetic-runner-ci | gate | — | — | yes | GitHub Actions workflow (.github/workflows/synthetic-runner.yml), not a Claude Code hook; events:["manual"] is a schema-gap stand-in for CI cron+PR triggers. |
| task-verifier-reminder | surfacer | [doctrine/planning.md](planning.md) | post-tool-task-verifier-reminder.sh | no | — |
| tdd-gate | gate | [doctrine/testing.md](testing.md) | pre-commit-tdd-gate.sh | yes | invoked via pre-commit-gate.sh chain; not directly wired in settings.json.template |
| teaching-moments | pattern | [doctrine/teaching-moments.md](teaching-moments.md) | — | no | — |
| vaporware-volume | gate | [doctrine/vaporware-prevention.md](vaporware-prevention.md) | vaporware-volume-gate.sh | yes | Member of the commit-boundary blocking unit (specs-d §D.0.4 as amended at D.5); CI relocation follows in E.4 companion. |
| waiver-density-alarm | pattern | — | — | no | scripts/waiver-density.sh — invoked by the digest (--digest-line) + E.5 KPI (--report); not an event-wired hook. |
| wave-d-retired-shims | writer | [doctrine/harness-dev.md](harness-dev.md) | check-harness-sync.sh, completion-criteria-gate.sh, continuation-enforcer.sh, cross-repo-drift-warn.sh, customer-facing-review-gate.sh, dag-review-waiver-gate.sh, decision-context-gate.sh, decision-context-replay.sh, deferral-counter.sh, goal-coverage-on-stop.sh, goal-extraction-on-prompt.sh, imperative-evidence-linker.sh, narrate-and-wait-gate.sh, pr-health-snapshot-gate.sh, pre-stop-verifier.sh, principles-compliance-gate.sh, product-acceptance-gate.sh, register-progress-gate.sh, settings-divergence-detector.sh, tool-call-budget.sh, transcript-lie-detector.sh, worktree-teardown-gate.sh | no | Exit-0 shims at retired live paths for one release (live-session safety, ADR 058 D5 pin c); originals in attic/. Hard-delete next release. |
| wire-check | gate | [doctrine/planning.md](planning.md) | wire-check-gate.sh | yes | — |
| work-integrity | gate | [doctrine/planning.md](planning.md) | work-integrity-gate.sh | yes | Invoked by stop-verdict-dispatcher.sh in --report mode (E.11, §E.W); no longer a direct Stop-chain entry. --self-test + blocking logic intact. |
| work-shapes | pattern | [doctrine/work-shapes.md](work-shapes.md) | — | no | — |
| workstream-memory-ecology | pattern | [doctrine/workstream-memory-ecology.md](workstream-memory-ecology.md) | — | no | — |
| workstreams-emitters | writer | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-emit-reconciler.sh, workstreams-emit.sh, workstreams-extract-pending.sh, workstreams-orchestrator-queue.sh, workstreams-read.sh | no | workstreams-emit.sh wired directly (SessionStart + spawn PreToolUse); Stop-side members dispatched via workstreams-stop-writer.sh since D.5. |
| workstreams-spawn-gate | gate | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-state-gate.sh | yes | — |
| workstreams-stop-gate | gate | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-stop-gate.sh | no | retired at D.5 cutover (attic + exit-0 shim); consolidated into the single workstreams Stop writer per ADR 058 D5 / specs-d |
| workstreams-stop-writer | writer | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-stop-writer.sh | no | — |
| workstreams-task-binding | gate | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-task-binding.sh | no | retired at D.5 cutover (attic + exit-0 shim); consolidated into the single workstreams Stop writer (D.0 collision resolution) per ADR 058 D5 / specs-d |
| workstreams-turn-emit | writer | [doctrine/workstreams-state.md](workstreams-state.md) | workstreams-turn-emit.sh | no | pending wiring — deterministic every-turn writer exists with green self-tests but is not wired in settings.json.template (doctor claim-honesty item) |
| worktree-advisor | surfacer | [doctrine/worktree-isolation.md](worktree-isolation.md) | session-start-worktree-advisor.sh | no | Dispatched via session-start-surfacer-pack.sh since D.5 (one SessionStart entry); E.1 digest replaces the pack. |
