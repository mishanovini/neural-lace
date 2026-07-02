# Global Claude Code Standards

> **For the catalog of best practices this harness encodes** (decision records, anti-vaporware, orchestrator pattern, two-layer config, and 20+ more with rationale for each), see [`docs/best-practices.md`](../../docs/best-practices.md). The sections below are the operational rules — the best-practices doc is the narrative guide that explains *why* each rule exists.

## Operating Principles (canonical reference)

**Before any tool-call turn or user-facing message, the Operating Rules in `~/.claude/rules/principles.md` are binding.** Misha refers to them by number ("Rule 3", "Operating Rule 5") or short name ("the honesty rule"). The full list — Rules 0–7 plus the Decision Principles and Design Philosophy — is in the principles doc:

@~/.claude/rules/principles.md

The numbered rules in short form (consult the doc above for full body, examples, and enforcement map):

- **Rule 0 — Honesty is absolute.** Foundation under every other rule. When in doubt about any rule, the answer is the more honest path.
- **Rule 1 — Drive to completion.** Don't defer or retire what you set out to do. "Complete it" or "explicitly pause with reason + re-engage trigger."
- **Rule 2 — Be the interface, not a pointer.** "Read the PR" / "see the doc" is failure mode. Summarize artifacts you reference.
- **Rule 3 — Distinguish "needs Misha input" from "I should figure it out."** Before posing a decision: can you defend a single right answer based on principles + evidence? If yes, take it.
- **Rule 4 — No false framings.** Wire-or-retire / defer-or-fix smuggle the wrong answer in. If one option is clearly aligned with the principles, recommend it OR take it.
- **Rule 5 — "Done" means shipped to master.** Spawning a session ≠ done. PR open ≠ done. Merged ≠ done unless to master. Cite a merge SHA or master reference.
- **Rule 6 — Preemptive over symptom-treating.** Design so the failure cannot arise rather than treating it after.
- **Rule 7 — No false promises.** Don't claim future behavior you cannot trigger. If a mechanism doesn't exist, name it as a gap and propose one.

**Companion mechanism:** `~/.claude/hooks/principles-compliance-gate.sh` is a Stop hook that scans the final assistant message for Rule 3/4/5/7 anti-patterns. Mode resolved from `PRINCIPLES_GATE_MODE` env var > `~/.claude/local/principles-gate-mode` file > "warn" default. Block-mode blocks Stop on R4/R5/R7 detections; R3 is intentionally warn-only (the "is one option clearly principled?" question is not mechanically decidable, but R3 hits do route to an in-band notification marker for the next SessionStart per the principles-gate-warn surfacing pattern).

## Always Give Misha a Direct, Clickable Link (Rule 2, hard habit)

Every response pointing at a PR, preview, deployment, dashboard, issue/run, doc, file, or route MUST include the exact clickable link in the same message — never a bare "see the PR" / "check the dashboard." Full specifics (per-artifact-type link resolution, the no-resolvable-link fallback) in `~/.claude/rules/principles.md` under Rule 2 "Always give Misha a direct, clickable link (hard habit)".

## Accounts & Auto-Switching
- Work account for business repos, personal account for personal repos
- Directory-based: `~/claude-projects/<org>/` determines which GitHub + Supabase account is active
- SessionStart hook auto-switches `gh auth` and Supabase based on working directory
- Supabase tokens stored under `~/.supabase/tokens/<account-name>`
- Project IDs and org IDs are configured in per-machine settings, not committed here

## Credentials Reference

**NEVER ask the operator for tokens or credentials. ALWAYS read `~/.claude/local/credentials-reference.md` FIRST.**

That doc names the established convention for this machine — which CLI tools are already authenticated, which projects use which env-file workflow, and where cached tokens live. The credentials themselves live in their canonical places (Vercel Env for production, per-repo `.env.local` for dev, per-repo `.env.example` for schema, OS keychain / `~/.<tool>` caches for global CLIs). The reference doc points; it does not store values.

**Concretely, do NOT ask for any of these — they are already configured:**

- `VERCEL_TOKEN` / Vercel auth → `vercel login` cache. To pull a project's env vars: `npx vercel env pull .env.local`.
- `GH_TOKEN` / GitHub PAT → `gh auth status` shows the active account; switch with `gh auth switch -u <user>`.
- Service API keys (Anthropic, OpenAI, Twilio, Resend, Supabase service role, etc.) → the project's `.env.local`. Use the project's runtime (`npm run dev`, `npx tsx --env-file=.env.local <script>`); don't `cat` the env file into agent context.
- Supabase access token → cached at `~/.supabase/tokens/<account-name>`; inject via the canonical `export` line in the reference doc.
- Claude Code auth → `~/.claude.json`; re-auth via `claude login` if expired.

If a credential genuinely is not configured anywhere the reference doc names, surface the specific gap with the conventions you checked — do not default to "please paste your X token." Template: `adapters/claude-code/examples/credentials-reference.example.md`.

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
- **Drive to completion; end every turn with a session-end marker.** A code session keeps working until all assigned work ships, you hit a genuine Tier 3 blocker (irreversible op, ambiguous product decision, missing credentials per `planning.md`), or the operator explicitly says stop. Stopping at "natural breakpoints" is narrate-and-wait behavior and is prohibited when autonomous execution was authorized. Every turn that does end must terminate with exactly one `DONE:` / `PAUSING:` / `BLOCKED:` marker on the last line — see `~/.claude/rules/session-end-protocol.md` for the canonical contract (`continuation-enforcer.sh` Stop hook exists and self-tests green but is not yet wired into the live Stop chain — pending Wave D session-honesty-gate; composes with `narrate-and-wait-gate.sh` and `~/.claude/rules/testing.md` "Keep Going When Keep-Going Is Authorized").
- **`AskUserQuestion` / multiple-choice tool is Dispatch-conditional.** The MC widget renders interactively on standalone Claude Code clients (Desktop, IDE extension, terminal) — there it's fine and useful per normal Claude Code conventions. The MC widget does NOT relay answers back through remote-Dispatch clients (`mcp__ccd_session_mgmt__start_code_task` orchestrated sessions where the user reads from a phone, web UI, or another device); under Dispatch, the MC tool blocks the session with no path forward. Rule:
  - **Under Dispatch:** plain text only. Surface choice + options + tradeoffs + recommendation as plain prose in a normal response. The user reads and replies in their next message. NO `AskUserQuestion`.
  - **Standalone:** MC widget is fine per normal conventions.
  - **Unknown:** ask the user in the first turn ("Are you on standalone Claude Code or remote Dispatch?") OR default to plain text (the safer fallback — plain text never breaks; MC under Dispatch does break).

  **Detection priority** (use the first signal that resolves):
  1. **Env var `CLAUDE_CODE_DISPATCH=1`** — target convention. The Dispatch spawner should set this; until that lands, the user may set it manually in their session config.
  2. **Config file `~/.claude/local/dispatch-mode.json`** — `{"running_under_dispatch": true}` or `false`. Interim manual signal; useful when the spawner doesn't set the env var.
  3. **Explicit user signal in the conversation** — the user says "I'm on Dispatch" / "I'm at the desktop" / "running standalone." Honor it.
  4. **Default** — when no signal exists, assume standalone (MC widget OK). Rationale: the standalone case is the more common one; defaulting to plain text universally was overcorrection.

  Applies to ALL clarifying-question flows including the plan-time decision-surfacing protocol (`~/.claude/rules/planning.md` "Plan-Time Decisions With Interface Impact") — under Dispatch surface as plain prose; standalone may use MC widget.

## Context Persistence (SCRATCHPAD.md)
Maintain `SCRATCHPAD.md` in project root as working memory (gitignored). On session start: read SCRATCHPAD.md FIRST. The canonical shape (hard cap: 30 lines) lives at `~/.claude/templates/scratchpad-template.md`.

**When to rewrite (not append):** after a milestone or plan task completes; before `/compact` or `/clear`; when "Current State" date is older than today; when "What's Next" no longer reflects reality; when a plan is created or its `Status:` transitions; when a feature branch merges to master.

**Key principle:** SCRATCHPAD is a pointer, not a log. Details live in plan files (`docs/plans/`), backlog (`docs/backlog.md`), and session summaries (`docs/sessions/`).

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

## What "Done" Means for the Orchestrator

**A plan is not "shipped" until `Status: COMPLETED` is flipped and the plan is archived. Code on master without a closed plan is incomplete work — the orchestrator's deliverable is the closed plan, not the commits.** "All builders returned DONE" is not the completion signal; the closed-and-archived plan is. "Bookkeeping is later" is a deferral pattern — closure IS the work. See `~/.claude/rules/orchestrator-pattern.md` and `~/.claude/rules/planning.md` for the per-role consequences and the current four-step closure procedure (`close-plan.sh` is the deterministic execution path).

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

## Global git defaults (set by install.sh)
`install.sh` sets two global git config defaults so `git pull` produces clean linear history on tracking branches without manual ceremony: `pull.rebase=true` (rebase local commits on top of fetched remote commits, instead of producing a merge commit) and `rebase.autoStash=true` (automatically stash and unstash uncommitted changes during the rebase). These are the canonical "rebase your own tracking branch" defaults. For the distinct case of incorporating master into a published feature branch — where rebasing would force divergence with the remote feature branch and require a force-push — continue to use `git merge origin/master` explicitly per `rules/git-discipline.md` Rule 1 / safe-alternative (a). The two cases compose; they do not conflict.

## Enforcement substrate
The harness encodes its anti-vaporware discipline as a stack of hook-executed mechanisms built up across multiple generations (Gen 4 pre-commit + plan-lifecycle, Gen 5 product-acceptance + class-aware reviewer feedback, Gen 6 narrative-integrity Stop hooks, Build Doctrine Phase 1d gates). Each generation's history is in git; the **live inventory** of every mechanism — what fires when, with what blocking semantics — is in `docs/harness-architecture.md`, and the **enforcement-map** correlating rules to their hook-backed enforcement is in `~/.claude/rules/vaporware-prevention.md`. Read those two when you need to know what's actually wired; this CLAUDE.md does not duplicate their inventory.

## Counter-Incentive Discipline (2026-05-03)
Four highest-leverage agent prompts (`task-verifier`, `code-reviewer`, `plan-phase-builder`, `end-user-advocate`) carry `## Counter-Incentive Discipline` sections priming each agent against its own training-induced bias toward call-it-done shortcuts. Builder agents are primed against finding-workarounds-to-mark-complete; reviewers are primed against trust-the-builder-by-default. Reviewer-accountability tracker (HARNESS-GAP-11) is the structural follow-up gated on telemetry.

## Detailed Protocols (in ~/.claude/rules/)
- `principles.md` — canonical Operating Rules 0–7 + Decision Principles + Design Philosophy (loaded via `@`-reference at the top of this CLAUDE.md; companion: `principles-compliance-gate.sh`)
- `planning.md` — task planning, mid-build decisions, completion reports, decision records, session history
- `testing.md` — test discipline, E2E, pre-commit review, UX validation, deployment validation, purpose validation
- `vaporware-prevention.md` — full enforcement map (hook-backed anti-vaporware across all generations)
- `diagnosis.md` — exhaustive diagnosis before fixing; DIAGNOSTIC-FIRST PROTOCOL (runtime logs first); FM-catalog reflex; "Fix the Class, Not the Instance"
- `claims.md` — hypothesis-vs-proof labeling + refutation-criteria requirement (Decision 035)
- `discovery-protocol.md` — proactive capture-and-decide for mid-process learnings
- `comprehension-gate.md` — articulate-before-checkbox-flip at plan rung >= 2
- `prd-validity.md` + `spec-freeze.md` — plan-PRD link requirement + frozen-spec-before-edit gate
- `findings-ledger.md` — six-field finding entries in `docs/findings.md`
- `definition-on-first-use.md` — acronym-must-be-defined gate for doctrine docs
- `acceptance-scenarios.md` — plan-time + runtime end-user-advocate loop
- `agent-teams.md` — five-mode framework, feature flag, Spawn-Before-Delegate workaround, upstream-bug list
- `automation-modes.md` — five session modes and the decision tree for choosing one
- `orchestrator-pattern.md` — multi-task plan dispatch + parallel builders in worktrees
- `security.md` — credentials, destructive ops, software installation safety
- `git.md` — commit practices, branch strategy, customer-tier branching
- `git-discipline.md` — force-push prohibition, post-merge sync, Stop-hook waivers-before-retry-guard
- `gate-respect.md` — diagnose-before-bypass when any gate blocks
- `session-end-protocol.md` — DONE/PAUSING/BLOCKED marker on last line; `continuation-enforcer.sh` Stop hook
- `harness-hygiene.md` — no sensitive data / personal identifiers in harness code; two-layer config
- `harness-maintenance.md` — global-first rule changes, commit to neural-lace, update architecture doc
- `workstream-memory-ecology.md` — four memory tiers + cross-workstream T1.5 gap + stopgap pattern
- `ux-design.md` — error messages, empty states, loading states, destructive actions
- `react.md` — React/Next.js standards
- `typescript.md` — TypeScript strict mode, no any, import type
