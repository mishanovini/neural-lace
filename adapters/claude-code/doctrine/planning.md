# Planning — compact
> Enforcement: plan-reviewer.sh, plan-edit-validator.sh, plan-lifecycle.sh, stop-verdict-dispatcher.sh, scope-enforcement-gate.sh. Full: doctrine/planning-full.md
> Applies: any task with architectural decisions, multi-file interactions, or >~15 min of work — plan first, then build.

- FUNCTIONALITY OVER COMPONENTS (constitution §4): a task is done when a user can do the thing, not when code compiles. When a pre-existing oracle exists (original test suite, consumer contract, golden outputs), it IS the done criterion. A configurable control (permission toggle, feature flag, setting, dropdown) is done only when changing it provably changes observable behavior — wired to nothing or never-flipped shadow-mode = vaporware.
- Write plans to `docs/plans/<slug>.md` with all seven required sections populated (Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy). No placeholders. Commit the plan immediately.
- Declare `Mode: code` (default) or `Mode: design` (infra/workflows/migrations — doctrine/design-mode-planning.md). Multi-task plans declare `Execution Mode: orchestrator` (doctrine/orchestrator-pattern.md).
- Plan headers record `ask-id:`; `start-plan.sh --ask-id <id>` back-links the registry via `ask-registry.sh link-plan` (`plan-reviewer.sh` WARNs when an ACTIVE v2 plan lacks it).
- Scope is mechanical: whatever is in the plan's task list. Never drop, defer, or narrow a planned task to finish faster. Legitimate deferral = dependency-blocked, user-deferred this session, or never in the plan.
- Decompose sweep tasks ("fix X across all forms") before starting: grep the codebase, write one sub-task per file, verify each individually.
- Only task-verifier flips checkboxes (`- [ ]` → `- [x]`). Never self-flip; never write your own evidence blocks.
- Mid-build decisions are two-tier by reversibility (constitution §8): reversible (one revert/flip) → decide-and-go — log in the Decisions Log, proceed, batch-present in completion report; hard-to-reverse (backups, schema/prod-data surgery, third parties, unrecoverable spend, unretractable exposure) → pause with options + recommendation prepared.
- Every substantive decision (new schema, cross-file pattern, chosen-between-alternatives, scope shape) gets a `docs/decisions/NNN-slug.md` record in the same commit, plus an index row.
- Plan-time either/or choices with interface impact: surface with options, tradeoffs, and a recommendation before recording — don't pick alone.
- A plan that absorbs backlog items declares `Backlog items absorbed:` in its header and deletes those items from the backlog in the same commit.
- The Status field is the LAST edit: write the completion report first, then flip `Status: COMPLETED` (or DEFERRED/ABANDONED) via the Edit tool — the flip auto-archives.
- New UI surfaces need ux-designer review at plan time; every plan gets end-user-advocate review unless acceptance-exempt (doctrine/acceptance-scenarios.md).
