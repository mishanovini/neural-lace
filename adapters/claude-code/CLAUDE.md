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

## Choosing a Session Mode
Every Claude Code session runs in one of FIVE modes — each with a different enforcement substrate and isolation story. Pick the mode whose enforcement matches the task before starting work:
- **Interactive local** (default) — full `~/.claude/` harness, single session per working tree. Best for tight-loop work, UX decisions, planning.
- **Parallel local (worktrees)** — full harness, git-tree isolation, but `~/.claude/` state is shared. Best for 2-5 concurrent short builds via Desktop "+ New session" or `isolation: "worktree"`.
- **Cloud remote (`claude --remote`)** — fully isolated VM per session, but only project `.claude/` enforcement (NOT `~/.claude/`). Requires Decision 011 Approach A (project `.claude/` populated). Best for multi-hour autonomous builds.
- **Scheduled (`/schedule` Routines)** — same as cloud remote, on a cron or event trigger. Best for nightly verification, CI auto-fix, recurring jobs.
- **Agent Teams** *(experimental, feature-flagged)* — lead session spawns peer teammates that message each other directly via `TaskCreated` / `TaskCompleted` events. Disabled by default per Decision 012. Enable only when continuous teammate-to-teammate coordination is the load-bearing requirement (vs. orchestrator's lead-dispatch model).

Full decision tree, per-mode invocation, tradeoffs, and pairing rules in `~/.claude/rules/automation-modes.md`. Decision records: `docs/decisions/011-claude-remote-harness-approach.md` (cloud-remote inheritance), `docs/decisions/012-agent-teams-integration.md` (Agent Teams).

## Autonomy
- Work autonomously with minimal interruptions
- Ambiguous minor details: make a reasonable choice, state the assumption
- Multiple valid approaches: pick simplest, note alternatives briefly
- Bugs outside current task: flag but don't fix unless trivial (< 5 min)
- Task grows beyond scope: check in before continuing
- Builds/tests fail: investigate and fix (up to 3 attempts) before escalating
- Business logic/user intent unclear: ask — don't guess on user-facing behavior
- Pre-authorized actions: file creation, folder creation, cd, ls, mkdir
- **Drive to completion. Do not end the turn between sub-tasks if there is more work to do.** A code session ends its turn only when (a) all assigned work is complete and pushed, (b) you hit a genuine blocker requiring user input (Tier 3 per `planning.md` — irreversible op, ambiguous product decision, missing credentials), or (c) the user has explicitly said "stop" / "pause" / "that's enough" in their most-recent message. Stopping for any other reason — "natural breakpoint," "good place to check in," "ready for the next phase" — is narrate-and-wait behavior and is prohibited when autonomous execution was authorized. If you must stop, tag the final response with `WHY I STOPPED:` plus a concrete reason so the orchestrator (or the next session) can diagnose. Cross-reference: `~/.claude/rules/testing.md` "Keep Going When Keep-Going Is Authorized" + `narrate-and-wait-gate.sh` Stop hook.
- **No `AskUserQuestion` / multiple-choice tool when running under a remote-Dispatch client.** The MC widget does not relay answers back through the Dispatch UI; questions asked via that tool block the session with no path forward. All clarifying questions and multi-option surfacing MUST be plain text in a normal response. The user reads and replies in their next message. This applies to ALL clarifying-question flows including the plan-time decision-surfacing protocol (`~/.claude/rules/planning.md` "Plan-Time Decisions With Interface Impact"): surface the choice + options + tradeoffs + recommendation as plain prose, NOT via `AskUserQuestion`. When in doubt about client type, assume remote-Dispatch.

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
- **When a plan is created** — add an entry to the "Active Plan" section pointing at the new plan file with its status
- **When a plan's status transitions** (ACTIVE → COMPLETED / DEFERRED / ABANDONED) — rewrite so "Active Plan" reflects the new state; move completed work out of "What's Next"
- **When a feature branch merges to master** — rewrite "Latest Milestone" to reflect the merged work, and clear items in "What's Next" that the merge completed

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

## What "Done" Means for the Orchestrator (Incentive Redesign — 2026-05-05)

**A plan is not "shipped" until it is `Status: COMPLETED` and archived. Code on master without a closed plan is incomplete work. The orchestrator's deliverable is the closed plan, not the code.**

This reframing is load-bearing across every other agent's behavior. The natural completion signal for an LLM orchestrator is "the last builder returned DONE and the commits landed on master." That signal is wrong. The orchestrator's work is not done until:

1. The final task-verifier verdict has flipped the last checkbox (or, under the lightweight-evidence pattern, the parent plan's task is marked complete by the orchestrator's own closure procedure).
2. The completion report has been appended.
3. `Status:` has been flipped to `COMPLETED` and the plan has auto-archived to `docs/plans/archive/`.
4. SCRATCHPAD has been rewritten so the next session sees the closed state.

Until those four are true, the plan is in flight — and the orchestrator's reward signal is plan closure, not dispatch completion. "Bookkeeping is later" is a deferral pattern; closure IS the work, not a follow-up to the work. See `~/.claude/rules/orchestrator-pattern.md` and `~/.claude/rules/planning.md` for the per-role consequences.

## Memory Discipline
- CLAUDE.md = index (short pointers)
- SCRATCHPAD.md = ephemeral state
- Do not store facts derivable from the codebase
- Memory is a hint, not truth — verify from source before using

**Memory freshness (`last_verified`):**
- Memory files SHOULD include an optional `last_verified: YYYY-MM-DD` field in their frontmatter, placed below the existing `name`, `description`, `type` fields.
- When you read a memory and confirm it's still accurate for today's code, update `last_verified: YYYY-MM-DD` to today in the same session.
- When you read a memory and find it wrong or outdated, either correct the body and update `last_verified`, or delete the memory entirely. Do not leave stale content behind.
- The SessionStart compact-recovery hook will flag memories whose `last_verified` is older than 7 days for attention. This is a reminder, not a block — the session still starts normally.

## Harness Source of Truth
The harness config lives in `~/claude-projects/neural-lace` (git repo, dual remotes: personal + PT org). On Windows, `install.sh` copies files to `~/.claude/` (no symlinks). Changes to `~/.claude/` must be synced back to the repo — see `rules/harness-maintenance.md`. A SessionStart hook warns when files in `~/.claude/` don't exist in the repo.

## Generation 5 Enforcement (2026-04-24)
Generation 5 builds on the Gen 4 hook-executed anti-vaporware foundation by adding adversarial observation of the running product, plan-lifecycle integrity, and a self-improvement meta-loop. Key Gen 5 mechanisms: `plan-lifecycle.sh` (PostToolUse — uncommitted-plan warning + auto-archive on terminal status), `plan-deletion-protection.sh` (PreToolUse — blocks unauthorised plan deletes), `docs/failure-modes.md` (project-level catalog of failure CLASSES with six-field schema), class-aware reviewer feedback (7 adversarial-review agents emit per-gap blocks with `Class:` + `Sweep query:` + `Required generalization:`), the capture-codify PR template + branch-protection guardrails, and the end-user-advocate acceptance loop: `agents/end-user-advocate.md` (plan-time + runtime modes), `hooks/product-acceptance-gate.sh` (Stop hook position 4 — blocks session end without PASS artifact whose `plan_commit_sha` matches), `agents/enforcement-gap-analyzer.md` (drafts harness-improvement proposals on every runtime FAIL), and `tests/acceptance-loop-self-test.sh` (six-stage structural check wired into weekly `/harness-review` Check 10).

## Generation 6 Enforcement — Narrative Integrity (2026-04-26)
Gen 6 closes the gap between what the agent CLAIMS in user-facing messages and what its OWN transcript reveals about deferred / contradicted / skipped work. Six new Stop hooks (positions 5-8 plus PreToolUse A8) read `$TRANSCRIPT_PATH` JSONL — which the agent cannot edit — and force gaps into the user-visible final message:

- **A1 (`goal-extraction-on-prompt.sh` + `goal-coverage-on-stop.sh`)** — extracts imperative verbs from the user's verbatim FIRST message at UserPromptSubmit time, SHA-checksums the prompt, and at Stop time blocks if any extracted goal lacks matching tool-call evidence. Tamper-detected: agent cannot edit the user's first message.
- **A3 (`transcript-lie-detector.sh`)** — pairs completion-class claims (`Status: COMPLETED`, `tests pass`, `shipped`) with deferral-class claims (`PHASE\d+-FOLLOWUP`, `awaiting user`, `did not execute`) within the same session; blocks unless reconciled.
- **A5 (`deferral-counter.sh`)** — pattern-matches a comprehensive synonym list of deferral phrases against the JSONL transcript; blocks unless the user-visible final message has `## Deferrals not executed in this session` with at least one bullet.
- **A7 (`imperative-evidence-linker.sh`)** — links each strong imperative in the user's last K substantive messages (`must`, `need to`, `please`) to specific tool-call evidence; blocks if any imperative was silently skipped.
- **A8 (`vaporware-volume-gate.sh`)** — PreToolUse on `gh pr create`; blocks PRs with > 200 lines of describing files (docs, YAML, source) AND ZERO behavior-executing artifact files (logs, screenshots, test results, evidence files). Escape hatch: PR title prefix `[docs-only]` or `[no-execution]`.

## Build Doctrine Integration (May 2026)
Phase 1d of the Build Doctrine arc shipped seven mechanisms to address gaps in the Gen 4-6 substrate:

- **Discovery Protocol** (`rules/discovery-protocol.md` + `hooks/discovery-surfacer.sh` SessionStart + `bug-persistence-gate.sh` extension) — proactive capture-and-decide for mid-process learnings; pending discoveries surface at session start with educational option/recommendation summaries; reversible decisions auto-apply, irreversible decisions pause-and-wait.
- **Comprehension Gate** (`rules/comprehension-gate.md` + `agents/comprehension-reviewer.md` + `task-verifier` extension) — at plan rung >= 2, builders articulate Spec meaning / Edge cases covered / Edge cases NOT covered / Assumptions in their evidence entry; the agent applies a three-stage rubric (schema / substance / diff correspondence); FAIL or INCOMPLETE blocks the checkbox flip.
- **Scope-Enforcement Gate redesign** (`hooks/scope-enforcement-gate.sh`) — blocks builder commits that touch files outside the active plan's `## Files to Modify/Create` OR `## In-flight scope updates` sections. Three structural options (update plan / open new plan / defer to backlog) replace the old waiver model. The plan template ships an `## In-flight scope updates` section by default.
- **PRD Validity + Spec Freeze** (`rules/prd-validity.md` + `rules/spec-freeze.md` + `hooks/prd-validity-gate.sh` + `hooks/spec-freeze-gate.sh` + `agents/prd-validity-reviewer.md`) — plan creation requires a valid `prd-ref:` in the header; edits to declared files are blocked unless the plan declares `frozen: true`; 5-field plan-header schema (`tier`, `rung`, `architecture`, `frozen`, `prd-ref`) on `Status: ACTIVE` plans.
- **Findings Ledger** (`rules/findings-ledger.md` + `hooks/findings-ledger-schema-gate.sh` + `bug-persistence-gate.sh` extension) — `docs/findings.md` carries six-field entries (ID, Severity, Scope, Source, Location, Status); accepted as the fourth durable-storage target alongside backlog / reviews / discoveries.
- **Definition-on-First-Use** (`rules/definition-on-first-use.md` + `hooks/definition-on-first-use-gate.sh`) — uppercase 2-6-char acronyms in doctrine docs must be defined either in the glossary or via an in-diff parenthetical; pre-commit gate blocks otherwise.
- **DAG Review Waiver Gate** (`hooks/dag-review-waiver-gate.sh`) — Tier 3+ active plans require a substantive (>= 40 chars) waiver at `.claude/state/dag-approved-<slug>-*.txt` before the first Task invocation in a session.
- **Knowledge Integration Ritual** (`build-doctrine/doctrine/07-knowledge-integration.md` + `~/.claude/skills/harness-review.md` Check 13 + `~/.claude/scripts/analyze-propagation-audit-log.sh` + `~/.claude/templates/pilot-friction.md`) — operationalizes Build Doctrine Principle 9 + Role 9 (Knowledge Integrator). 7 KIT triggers (KIT-1 calibration / KIT-2 findings / KIT-3 discoveries / KIT-4 ADR-staleness / KIT-5 `/harness-review` cadence / KIT-6 propagation-engine audit log / KIT-7 drift). Check 13 sweeps each KIT against the existing capture substrate. Cadence + thresholds tagged `(hypothesis, pending pilot evidence)` per AP16. Pre-pilot infrastructure shipped 2026-05-06.
- **Propagation Engine** (`hooks/propagation-trigger-router.sh` + `build-doctrine/propagation/propagation-rules.json` + `build-doctrine/telemetry/propagation.jsonl`) — config-driven engine evaluating 8 starter rules (4 proven + 3 conjectural + 1 docs-coupling) against per-event input; writes JSONL audit log (the measurement substrate KIT-6 consumes). Real-time hook wiring deferred to post-pilot evidence.

Gen 4 mechanisms still apply unchanged: `pre-commit-tdd-gate.sh` (4 layers), `plan-edit-validator.sh` (evidence-first checkbox auth), `runtime-verification-executor.sh` + `runtime-verification-reviewer.sh` (pre-stop Check 4b/4c), `plan-reviewer.sh` (now extended with Check 9 quantitative-arithmetic, Check 10 5-field schema, Check 11 behavioral contracts), `tool-call-budget.sh` (blocks every 30 calls; team-aware mode for Agent Teams), `claim-reviewer` agent (self-invoked residual gap), `verify-feature` skill. See `docs/harness-architecture.md` for the full inventory and `~/.claude/rules/vaporware-prevention.md` for the enforcement map.

## Counter-Incentive Discipline (2026-05-03)
Four highest-leverage agent prompts (`task-verifier`, `code-reviewer`, `plan-phase-builder`, `end-user-advocate`) carry `## Counter-Incentive Discipline` sections priming each agent against its own training-induced bias toward call-it-done shortcuts. Builder agents are primed against finding-workarounds-to-mark-complete; reviewers are primed against trust-the-builder-by-default. Reviewer-accountability tracker (HARNESS-GAP-11) is the structural follow-up gated on telemetry.

## Detailed Protocols (in ~/.claude/rules/)
- `planning.md` — task planning, mid-build decisions, completion reports, decision records, session history
- `testing.md` — test discipline, E2E, pre-commit review, UX validation, deployment validation, purpose validation
- `vaporware-prevention.md` — Gen 4-6 enforcement map (hook-backed anti-vaporware) + Build Doctrine extensions
- `diagnosis.md` — exhaustive diagnosis before fixing, full-chain tracing, "Fix the Class, Not the Instance" sub-rule
- `discovery-protocol.md` — proactive capture-and-decide for mid-process learnings (Build Doctrine)
- `comprehension-gate.md` — articulate-before-checkbox-flip at plan rung >= 2 (Build Doctrine)
- `prd-validity.md` + `spec-freeze.md` — plan-PRD link requirement + frozen-spec-before-edit gate (Build Doctrine)
- `findings-ledger.md` — six-field finding entries in `docs/findings.md` (Build Doctrine)
- `definition-on-first-use.md` — acronym-must-be-defined gate for doctrine docs (Build Doctrine)
- `acceptance-scenarios.md` — plan-time + runtime end-user-advocate loop (Gen 5)
- `agent-teams.md` — five-mode framework, feature flag, Spawn-Before-Delegate workaround, upstream-bug list
- `automation-modes.md` — five session modes and the decision tree for choosing one
- `orchestrator-pattern.md` — multi-task plan dispatch + parallel builders in worktrees
- `security.md` — credentials, destructive ops, software installation safety
- `git.md` — commit practices, branch strategy, customer-tier branching
- `git-discipline.md` — force-push prohibition (absolute, no exceptions), post-merge sync of user's main checkout, Stop-hook waivers-before-retry-guard
- `gate-respect.md` — diagnose-before-bypass when any gate blocks; read stderr first, apply the gate's named remediation, bypass only with explicit current-chat user authorization
- `harness-hygiene.md` — no sensitive data / personal identifiers in harness code; two-layer config; instances never ship in harness repos
- `harness-maintenance.md` — global-first rule changes, commit to neural-lace, update architecture doc
- `ux-design.md` — error messages, empty states, loading states, destructive actions
- `react.md` — React/Next.js standards
- `typescript.md` — TypeScript strict mode, no any, import type
