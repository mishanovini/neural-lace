# Global Claude Code Standards

> **For the catalog of best practices this harness encodes** (decision records, anti-vaporware, orchestrator pattern, two-layer config, and 20+ more with rationale for each), see [`docs/best-practices.md`](../../docs/best-practices.md). The sections below are the operational rules — the best-practices doc is the narrative guide that explains *why* each rule exists.

## Accounts & Auto-Switching
- Work account for business repos, personal account for personal repos
- Directory-based: `~/claude-projects/<org>/` determines which GitHub + Supabase account is active
- SessionStart hook auto-switches `gh auth` and Supabase based on working directory
- Supabase tokens stored under `~/.supabase/tokens/<account-name>`
- Project IDs and org IDs are configured in per-machine settings, not committed here

## Naming & Identity
- NEVER name projects/products without consulting the user first
- Use placeholder names until the user provides a name

## Autonomy
- Work autonomously with minimal interruptions
- Ambiguous minor details: make a reasonable choice, state the assumption
- Multiple valid approaches: pick simplest, note alternatives briefly
- Bugs outside current task: flag but don't fix unless trivial (< 5 min)
- Task grows beyond scope: check in before continuing
- Builds/tests fail: investigate and fix (up to 3 attempts) before escalating
- Business logic/user intent unclear: ask — don't guess on user-facing behavior
- Pre-authorized actions: file creation, folder creation, cd, ls, mkdir

## Context Persistence (SCRATCHPAD.md)
Maintain `SCRATCHPAD.md` in project root as working memory (add to .gitignore). On session start: read SCRATCHPAD.md FIRST.

**Format (hard cap: 30 lines):**
```
# SCRATCHPAD — [Project Name]
## Current State (YYYY-MM-DD)
Branch: X | Deployed: Y | Migrations: through NNN

## Latest Milestone
[2-3 lines — what just shipped or was verified]

## Active Plan
[Path to plan file, or "None". Status: ACTIVE/COMPLETED/etc.]

## Backlog Pointer
[Path to backlog file, or key priorities if no backlog file exists]

## What's Next
[3-5 lines — immediate priorities for the next session]

## Blocking / Known Issues
[2-3 lines, or "None"]
```

**When to rewrite (not append):**
- After completing a milestone or plan task
- Before `/compact` or `/clear` — the compact SessionStart hook will remind you
- When the date in "Current State" is older than today
- When "What's Next" no longer reflects reality

**Key principle:** SCRATCHPAD is a pointer, not a log. Details live in plan files (`docs/plans/`), backlog (`docs/backlog.md`), and session summaries (`docs/sessions/`). SCRATCHPAD just tells a fresh session where to look and what's urgent.

## Keeping Plans and Backlogs Current

The compact SessionStart hook checks SCRATCHPAD, backlog, and plan freshness — but hooks only catch staleness, they don't prevent it. These are the mandatory update triggers:

**Backlog (`docs/backlog.md`):**
- Must have `Last updated: YYYY-MM-DD` on line 2
- Update when: completing a backlog item (move to Completed), discovering a new issue during testing or development, after any UX/testing agent run that produces findings
- Never leave completed items in the active sections — move them immediately
- **Identifying a gap = writing a backlog entry, in the same response.** When you say or think "we should also build X", "this is missing", "we don't have Y yet", "ideally we'd add Z", "as a future enhancement", or "I'll add this later" — that IS the moment to add it to the backlog, not later. Phrases like "later" and "ideally" are signals that you're about to forget. Stop, write the backlog entry with the date, then continue with the current work. The bar: if a future Claude session needs to know about this, it goes in the backlog NOW.

**Plan files (`docs/plans/`):**
- Covered by `planning.md` rules + task-verifier mandate
- Additional: if work is happening WITHOUT a plan (ad-hoc fixes, user requests), either create a plan or capture the work in the backlog. Undocumented work is lost work.
- When a plan is finished, set Status: COMPLETED in the plan file

**Testing results (`docs/reviews/`):**
- UX agent findings, testing runs, and audit results MUST be persisted to `docs/reviews/YYYY-MM-DD-<slug>.md` immediately when results arrive — before analysis, before fixes, before anything else
- Rationale: if the session crashes after agents complete but before results are saved, all findings are lost. Persist first, analyze second.
- After fixing findings, update the review file with fix status (don't delete findings — mark them as fixed with the commit SHA)

## Code Quality
- Handle errors explicitly — never swallow silently
- No hardcoded secrets in source files
- Keep dependencies minimal
- Read existing code before modifying
- Prefer minimal, focused changes — don't refactor beyond the task
- No new files unless necessary — edit existing files when possible

## Execution
- Default to parallel tool calls for independent operations
- Always read a file before editing — never edit from stale context
- Break complex edits into small, targeted replacements
- Add timeouts to commands expected to run > 10 seconds
- Every task needs an explicit exit condition — define 'done' first
- After 3 failed attempts at the same step, stop and report
- **Update status documents when work completes, not later.** When a task, feature, or milestone finishes, immediately update SCRATCHPAD.md, backlog, and plan status before moving to the next task. "I'll update docs later" means "docs will be stale."

## Context Hygiene
- Use `/clear` between unrelated tasks
- Scope investigations with subagents to avoid filling main context
- Prefer explorer agent for quick lookups
- **For multi-task plans: use the orchestrator pattern.** The main session dispatches build work to `plan-phase-builder` sub-agents (preferring parallel dispatch when tasks are independent) and stays lean as an orchestrator. The main session does NOT do the build work itself. See `~/.claude/rules/orchestrator-pattern.md`. This is the load-bearing defense against context degradation across long plans — every Edit/Write/Bash the main session does directly is context it will carry for the rest of the session.

## Memory Discipline
- CLAUDE.md = index (short pointers)
- SCRATCHPAD.md = ephemeral state
- Do not store facts derivable from the codebase
- Memory is a hint, not truth — verify from source before using

## Harness Source of Truth
The harness config lives in `~/claude-projects/neural-lace` (git repo, dual remotes: personal + PT org). On Windows, `install.sh` copies files to `~/.claude/` (no symlinks). Changes to `~/.claude/` must be synced back to the repo — see `rules/harness-maintenance.md`. A SessionStart hook warns when files in `~/.claude/` don't exist in the repo.

## Generation 4 Enforcement (2026-04-15)
Anti-vaporware enforcement is hook-executed, not prose-enforced. Key mechanisms: `pre-commit-tdd-gate.sh` (4 layers), `plan-edit-validator.sh` (evidence-first checkbox auth), `runtime-verification-executor.sh` + `runtime-verification-reviewer.sh` (pre-stop Check 4b/4c), `plan-reviewer.sh`, `tool-call-budget.sh` (blocks every 30 calls), `claim-reviewer` agent (self-invoked residual gap), `verify-feature` skill. See `docs/harness-architecture.md` for the full inventory and `~/.claude/rules/vaporware-prevention.md` for the enforcement map.

## Detailed Protocols (in ~/.claude/rules/)
- `planning.md` — task planning, mid-build decisions, completion reports, decision records, session history
- `testing.md` — test discipline, E2E, pre-commit review, UX validation, deployment validation, purpose validation
- `vaporware-prevention.md` — Gen 4 enforcement map (hook-backed anti-vaporware)
- `diagnosis.md` — exhaustive diagnosis before fixing, full-chain tracing
- `security.md` — credentials, destructive ops, software installation safety
- `git.md` — commit practices, branch strategy
- `harness-hygiene.md` — no sensitive data / personal identifiers in harness code; two-layer config; instances never ship in harness repos
- `harness-maintenance.md` — global-first rule changes, commit to neural-lace, update architecture doc
- `ux-design.md` — error messages, empty states, loading states, destructive actions
- `react.md` — React/Next.js standards
- `typescript.md` — TypeScript strict mode, no any, import type
