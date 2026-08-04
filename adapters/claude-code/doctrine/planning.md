# Planning — compact
> Enforcement: plan-reviewer.sh, plan-edit-validator.sh, plan-lifecycle.sh, stop-verdict-dispatcher.sh, scope-enforcement-gate.sh. Full: doctrine/planning-full.md
> Applies: any task with architectural decisions, multi-file interactions, or >~15 min of work — plan first, then build.

- FUNCTIONALITY OVER COMPONENTS (constitution §4): done = a user can do the thing, not code compiles. Prefer a pre-existing oracle (suite, contract, golden output). A control is done only when flipping it provably changes behavior — unwired/shadow-mode = vaporware (detail: -full.md).
- Write plans to `docs/plans/<slug>.md` with all seven required sections populated (Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy); no placeholders; commit immediately.
- Declare `Mode: code` (default) or `Mode: design` (infra/migrations — doctrine/design-mode-planning.md). Multi-task plans declare `Execution Mode: orchestrator` (doctrine/orchestrator-pattern.md).
- Plan headers record `ask-id:`; `start-plan.sh --ask-id <id>` back-links the registry via `ask-registry.sh link-plan` (`plan-reviewer.sh` WARNs when an ACTIVE v2 plan lacks it).
- Design-projected plans carry `design-ref: <path>@<blob>` + `## Review Chain`; per-task `Implements:`/`Directives:` when design-ref is real (Checks 20-22; detail -full.md).
- Scope is mechanical: the plan's task list. Never drop, defer, or narrow a task to finish faster; legitimate deferral = dependency-blocked, user-deferred this session, or never in the plan.
- Decompose sweep tasks ("fix X across all forms") before starting: grep the codebase, write one sub-task per file, verify each individually.
- Only task-verifier flips checkboxes (`- [ ]` → `- [x]`). Never self-flip; never write your own evidence blocks.
- Mid-build decisions: two-tier by reversibility (constitution §8) — reversible → decide-and-go (log, proceed, batch-present); hard-to-reverse → pause with options+rec.
- Verify obligations (OD-022): open ledger row blocks builder @3+; Stop refuses unnamed DONE. -full.md.
- Every substantive decision (new schema, cross-file pattern, alternatives chosen, scope shape) gets a `docs/decisions/NNN-slug.md` record + index row, same commit.
- Plan-time either/or choices with interface impact: surface options, tradeoffs, and a recommendation before recording.
- A plan that absorbs backlog items declares `Backlog items absorbed:` in its header and deletes those items from the backlog in the same commit.
- The Status field is the LAST edit: write the completion report first, then flip `Status: COMPLETED` (or DEFERRED/ABANDONED) via the Edit tool — the flip auto-archives.
- `Status:` = 8-value enum (`schemas/plan-status.schema.json`); `Status-note:` = optional prose, never parsed for state.
- New UI surfaces need ux-designer review at plan time; every plan gets end-user-advocate review unless acceptance-exempt (doctrine/acceptance-scenarios.md).
