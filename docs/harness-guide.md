# Claude Code Harness Guide

> **Audience:** Developers using this harness  
> **Purpose:** Understand how the Claude Code AI harness is configured, what each file does, and how the automation works

---

## Quick Start

When you open a project in Claude Code with this harness installed:

1. **SessionStart hook** switches your GitHub and Supabase accounts based on the working directory
2. Claude Code reads `CLAUDE.md` (project-level, if any) and `~/.claude/CLAUDE.md` (global) for instructions
3. Rules in `.claude/rules/` (project) and `~/.claude/rules/` (global) activate based on what files you're editing
4. If a plan file exists in `docs/plans/`, a stop guard prevents you from ending the session with incomplete tasks

This document explains every file in the harness and why it exists.

---

## Locking down an org against accidental public repos

The harness has a hook-level defense that blocks `gh repo create --public` when the active account is flagged with `public_blocked: true` in `accounts.config.json`. That defense fires at the AI-session level — it prevents Claude Code from invoking the public-repo creation tool during a session.

**The authoritative layer is GitHub itself.** Configure the org to reject public-repo creation at the API level, so no tool (Claude Code, a script, the web UI, anything) can create a public repo under that org without an admin changing the setting first.

### Steps

1. Navigate to `https://github.com/organizations/<your-org>/settings/member_privileges`
2. Scroll to the "Repository creation" section
3. Unselect "Public" — only leave "Private" and/or "Internal" checked
4. Save

Once this is set, GitHub itself rejects public-repo creation attempts under `<your-org>` regardless of what tool makes the request. An error surfaces at the API call; there is no silent fallback to public.

### Relationship to the harness hook

The `public_blocked: true` flag in `accounts.config.json` mirrors this intent at the AI-session layer. Both should be set together for work accounts:

- **GitHub org setting** — authoritative, applies to every tool and every user under the org
- **Harness `public_blocked` flag** — AI-session defense, applies to any Claude Code session that has switched to this account

Belt-and-suspenders. The GitHub setting is the one that survives Claude Code being bypassed, misconfigured, or replaced by a different AI tool; the harness flag catches the AI session before it even attempts the call.

For personal accounts where public repos are legitimate, leave `public_blocked` unset (defaults to `false`) and leave the GitHub org setting permissive.

---

## Automation modes: full-auto vs. review-before-deploy

Claude Code can run multi-step plans in two modes, controlled by a harness config file. The mode determines whether Claude pauses for explicit approval before running deploy-class commands.

### The two modes

- **`review-before-deploy`** (default): Claude pauses before any Bash command matching a deploy-class matcher and asks for explicit approval. This is the safer default — you approve each deploy action one at a time.
- **`full-auto`**: Claude proceeds through multi-step plans without pausing on deploy-class matchers. Other safeguards — the dangerous-command blocker, the credential scanner, and the `public_blocked` account flag — still apply. Full-auto turns off the deploy-pause, not the core safety hooks.

Neither mode disables: the pre-push credential scanner, the public-repo block, the `.env`/lock-file edit block, or the `curl | sh`/`rm -rf /` block. Those are always active regardless of automation mode.

### Where the config lives

| Path | Scope | Precedence |
|------|-------|------------|
| `<project>/.claude/automation-mode.json` | Per-project override | Highest (wins if present) |
| `~/.claude/local/automation-mode.json` | User-global | Middle (used if no per-project file) |
| Hardcoded default | `review-before-deploy` | Lowest (used if neither file exists) |

Per-project beats user-global beats hardcoded default. This lets you run most projects in `full-auto` but flip a specific repo (production infra, a client project) back to `review-before-deploy` without touching the global setting.

### How to change modes

Slash commands (preferred):

- `/automation-mode full-auto` — set user-global to `full-auto`
- `/automation-mode review` — set user-global to `review-before-deploy`
- `/automation-mode status` — print the effective mode for the current session (with which layer supplied it)

Append `--project` to write to the per-project file instead of user-global:

- `/automation-mode full-auto --project` — set the current project's override to `full-auto`
- `/automation-mode review --project` — set the current project's override to `review-before-deploy`

Manual edit: open the JSON file and change the `"mode"` field. Both files share the same schema — see `adapters/claude-code/examples/automation-mode.example.json` for the reference shape.

### Default matchers

The deploy-pause fires when a Bash command matches any entry in the `deploy_matchers` array. Defaults:

- `git push`
- `gh pr merge`
- `gh repo create`
- `supabase db push`
- `vercel deploy`
- `npm publish`

Edit `deploy_matchers` in the JSON to add or remove entries per your workflow. Example additions: `terraform apply`, `kubectl apply`, `railway deploy`, `fly deploy`, a project's own deploy script path.

### First-run prompt

On a fresh install — when `~/.claude/local/automation-mode.json` does not yet exist — the SessionStart hook prints a prompt asking the user to choose:

1. `review-before-deploy` (recommended default)
2. `full-auto`

If the user answers, the chosen mode is written to `~/.claude/local/automation-mode.json`. If the user doesn't answer (session moves on without a response), the default (`review-before-deploy`) is written silently. The prompt does not repeat on subsequent sessions; the file exists and supplies the mode from then on.

To trigger the prompt again, delete `~/.claude/local/automation-mode.json` and start a new session.

### Cross-reference

- Schema: `adapters/claude-code/examples/automation-mode.example.json`
- Related safety hook docs: the "Safety Hooks" subsection under "Hooks (Automated Safety & Switching)" below

---

## File Map

### Global Files (in this repo, symlinked to `~/.claude/`)

```
~/.claude/
├── CLAUDE.md                          # Global standards (all projects)
├── settings.json                      # Permissions, hooks, plugins (per-machine, not symlinked)
├── rules/
│   ├── diagnosis.md                   # Exhaustive diagnosis protocol
│   ├── git.md                         # Commit practices
│   ├── planning.md                    # Task planning protocol
│   ├── react.md                       # React/Next.js standards
│   ├── security.md                    # Credentials, destructive ops
│   ├── testing.md                     # Test discipline, E2E, pre-commit review
│   ├── typescript.md                  # TypeScript strict mode
│   ├── ux-design.md                   # Error messages, empty states, loading
│   ├── ux-standards.md                # UI design principles, attention hierarchy
│   ├── vaporware-prevention.md        # Gen 4 stub — points at hooks that enforce anti-vaporware
│   ├── harness-maintenance.md         # Global-first rule, sync to neural-lace repo
│   └── pipeline-agents.md             # BUILDER/VERIFIER/DECOMPOSER roles for pipeline mode
├── agents/
│   ├── audience-content-reviewer.md   # Reviews user-facing text against project's target audience
│   ├── claim-reviewer.md              # Gen 4: adversarial review of product Q&A claims (self-invoked)
│   ├── code-reviewer.md               # Reviews diffs for quality
│   ├── domain-expert-tester.md        # Becomes project's target user and tests workflows
│   ├── explorer.md                    # Fast codebase exploration (uses haiku)
│   ├── harness-reviewer.md            # Adversarial review of harness rule/hook/agent changes
│   ├── plan-evidence-reviewer.md      # Independent second opinion on task evidence
│   ├── research.md                    # Read-only research agent
│   ├── security-reviewer.md           # Security-focused code review
│   ├── task-verifier.md               # ONLY agent that can check task boxes (Gen 4 evidence-first protocol)
│   ├── test-writer.md                 # Generates tests
│   ├── ux-designer.md                 # Pre-build UX review of plans for new UI surfaces
│   └── ux-end-user-tester.md          # Simulates non-technical user testing
├── skills/
│   └── verify-feature.md              # Gen 4: ripgrep-backed feature citation lookup for product Q&A
├── templates/
│   ├── plan-template.md               # Structure for plan files
│   ├── completion-report.md           # Appended to plans when done
│   └── decision-log-entry.md          # Format for mid-build decisions
├── hooks/
│   ├── pre-commit-gate.sh                      # Orchestrator: freshness gates → TDD gate → plan-reviewer → tests → build → API audit
│   ├── pre-commit-tdd-gate.sh                  # Gen 4: 4 layers (new/modified file tests, mock ban, trivial-assertion ban)
│   ├── plan-reviewer.sh                        # Gen 4: adversarial plan check (sweep, manual-verif, Scope, DoD)
│   ├── plan-edit-validator.sh                  # Gen 4: blocks casual plan checkbox flips (evidence-first authorization)
│   ├── runtime-verification-executor.sh        # Gen 4: executes "Runtime verification:" commands
│   ├── runtime-verification-reviewer.sh        # Gen 4: correspondence check (verification must match modified files)
│   ├── tool-call-budget.sh                     # Gen 4: blocks every 30 tool calls until audit acknowledged
│   ├── post-tool-task-verifier-reminder.sh     # Gen 4: reminds to invoke task-verifier on src edits
│   ├── pre-stop-verifier.sh                    # Blocks session end on incomplete/unverified plans (Check 4 calls executor + reviewer)
│   ├── check-harness-sync.sh                   # Warns if ~/.claude/ has diverged from neural-lace repo
│   ├── harness-hygiene-scan.sh                 # Scans for denylisted identity/credential patterns
│   ├── decisions-index-gate.sh                 # Rule 5: decision record ↔ DECISIONS.md atomicity
│   ├── backlog-plan-atomicity.sh               # Rule 1: plan creation absorbs backlog items
│   ├── docs-freshness-gate.sh                  # Rule 8: structural changes touch docs
│   ├── migration-claude-md-gate.sh             # Rule 3: migrations ↔ CLAUDE.md atomicity
│   ├── review-finding-fix-gate.sh              # Rule 4: review fixes update review file
│   ├── pre-push-scan.sh                        # Credential scanner (global git pre-push hook)
│   ├── sensitive-patterns.local                # Personal credential patterns (never shared)
│   └── sensitive-patterns.local.example        # Template for personal patterns
├── state/                                       # Gen 4: session state for tool-call-budget (per-session counters)
│   ├── tool-call-count.<session>
│   └── audit-ack.<session>
├── scripts/
│   ├── validate-links.ts             # Dead link validator for Next.js apps
│   └── audit-consistency.ts          # Code consistency audit (strings, colors, loading states, buttons)
├── pipeline-templates/
│   ├── orchestrate.sh                # Multi-agent pipeline orchestrator
│   ├── verify-existing-data.sh       # Database verification script
│   └── verify-ui.mjs                 # Playwright UI screenshot verification
└── docs/
    ├── harness-guide.md               # This file
    ├── harness-architecture.md        # Detailed architecture overview with diagrams
    ├── harness-strategy.md            # Vision and strategic goals
    ├── ux-guidelines.md               # UI/UX design principles
    ├── ux-checklist.md                # 22-domain UX checklist (referenced by UX agents)
    └── business-patterns-workflow.md  # Team-shared sensitive patterns setup guide
```

> **Gen 4 note (2026-04-15):** the `plan-edit-validator`, `runtime-verification-executor`, `runtime-verification-reviewer`, `plan-reviewer`, `tool-call-budget`, and `post-tool-task-verifier-reminder` hooks were added as part of the anti-vaporware enforcement redesign. Together they shift enforcement from self-applied prose rules to mechanically-executed gates: plan checkbox flips require fresh matching evidence, "Runtime verification:" entries must actually execute before session end, and the tool-call-budget forces a periodic audit during long sessions.

> **Document Freshness note (2026-04-18):** the `harness-hygiene-scan`, `decisions-index-gate`, `backlog-plan-atomicity`, `docs-freshness-gate`, `migration-claude-md-gate`, and `review-finding-fix-gate` hooks mechanically enforce the document-freshness rules: decisions land with their index entry in the same commit, new plans that claim to absorb backlog items stage `docs/backlog.md` too, structural harness changes (A/D/R) require matching doc updates, migrations and `CLAUDE.md` stay in sync, and review-finding fixes update their review file atomically. Each gate reads `git diff --cached` and blocks the commit if the invariant is violated — the gates are wired in both the repo-local `.git/hooks/pre-commit` wrapper (via `install-repo-hooks.sh`) and the Claude Code `pre-commit-gate.sh` PreToolUse hook. See `docs/best-practices.md` for the rule-by-rule rationale.

### Project-Level Files (in individual project repos)

Individual projects can extend the global config with project-specific rules:

```
<project>/
├── CLAUDE.md                          # Project-specific instructions
├── .claude/
│   ├── rules/                         # Project-specific rules (e.g., api-routes.md, database-migrations.md, ui-components.md)
│   └── pipeline-prompts/              # Project-specific decomposition prompts
├── SCRATCHPAD.md                      # (gitignored) Working memory between sessions
└── docs/
    └── plans/                         # Plan files (committed, permanent records)
```

---

## How Each File Works

### Global CLAUDE.md

**Path:** `~/.claude/CLAUDE.md`  
**What it does:** Baseline standards that apply to ALL projects

Key contents:
- Account auto-switching (GitHub + Supabase based on working directory)
- Autonomy rules (work independently, make reasonable choices, flag scope expansion)
- SCRATCHPAD.md maintenance protocol
- Code quality baseline (explicit error handling, no secrets, minimal dependencies)
- Execution patterns (parallel tool calls, read before edit, max 3 attempts before escalating)
- References detailed protocols in `~/.claude/rules/`

### Project-Level CLAUDE.md

**Path:** `<project>/CLAUDE.md`  
**When it's read:** Every session in that project  
**What it does:** Tells Claude Code how to work in this specific project

Typical contents:
- **Build commands**: project-specific commands (npm run dev, build, test, etc.)
- **Architecture overview**: how the app is structured
- **Key files**: important paths for the project
- **Conventions**: project-specific patterns (validation libraries, error tracking, etc.)
- **Framework gotchas**: version-specific or project-specific caveats

**Why it matters:** Without a project-level CLAUDE.md, Claude Code would guess the project structure from files alone, missing conventions that aren't obvious from the code.

---

### Rules (Context-Triggered Instructions)

Rules activate **only when relevant files are being edited**. They don't clutter Claude's context when you're doing something unrelated.

#### Global Rules (`~/.claude/rules/`)

| File | What It Enforces |
|------|-----------------|
| `diagnosis.md` | **Before proposing any fix:** read the full stack (frontend → API → backend → external → response), trace a concrete example end-to-end, list ALL bugs in one pass |
| `git.md` | Commit at natural milestones, `<type>: <description>` messages, never push without asking, never commit to master directly |
| `planning.md` | For work > ~15 min: create plan in `docs/plans/`, create feature branch, implement autonomously, update SCRATCHPAD. Mid-build decisions: Tier 1 (continue + log), Tier 2 (commit checkpoint + log), Tier 3 (stop + wait for approval) |
| `react.md` | Semantic HTML (`button` not `div onClick`), keyboard navigation, ARIA labels, loading/error/empty states, Server Components by default |
| `security.md` | Never commit `.env` or credentials, flag exposed secrets immediately, no destructive ops without approval, vet software installations |
| `testing.md` | Run tests before declaring done, write tests for new features, E2E after system boundary changes, **pre-commit code review mandatory**, UX validation after substantial builds |
| `typescript.md` | `strict: true`, `import type` for type-only, no `any` without justification, explicit return types on exports, no `@ts-ignore`, no `console.log` |
| `ux-design.md` | Errors suggest solutions, empty states offer first action, destructive actions need confirmation + reversibility info, loading states describe what's loading |
| `ux-standards.md` | Full UI design principles: color semantics, attention hierarchy, clickable cards, state handling, AI feature patterns. See `docs/ux-guidelines.md` for the full rationale. |

#### Project Rules (example patterns)

Individual projects can add their own rules in `.claude/rules/`. Common examples:

| File | Triggers When Editing | Typical Behavior |
|------|----------------------|------------------|
| `api-routes.md` | `src/app/api/**` or similar | Test with curl, document response shapes, verify auth middleware, confirm columns exist |
| `database-migrations.md` | `supabase/migrations/**` or similar | Check existing data before migrating, handle NOT NULL with defaults, add RLS immediately |
| `ui-components.md` | `src/components/**`, page files | Trace every prop to its data source, verify conditional rendering, confirm click handlers |

---

### Hooks (Automated Safety & Switching)

Hooks are shell scripts that run automatically at specific lifecycle points. Configured in `~/.claude/settings.json`.

#### SessionStart Hook
**When:** Every new Claude Code session  
**What it does:**
1. Detects which project you're in by checking `$PWD`
2. Switches GitHub account via `gh auth switch`
3. Logs into Supabase using a stored token (if present)
4. Checks for active pipelines or plan files

**Why:** Prevents accidentally pushing to the wrong GitHub account or running database commands against the wrong environment.

#### Pre-Commit Gate (`hooks/pre-commit-gate.sh`)
**When:** Before every `git commit`  
**What it does:**
1. `npm test` — **blocks commit if tests fail**
2. `npm run build` — **blocks commit if build fails**
3. `scripts/audit-api-consumers.sh` (if present) — **blocks if an API route changed but consumer files aren't staged**

**Why:** No broken code gets committed. Catches type errors, test regressions, and API contract breaks before they reach the repo.

#### Pre-Stop Verifier (`hooks/pre-stop-verifier.sh`)
**When:** When Claude Code session is about to end  
**What it does:**
1. Finds the most recently modified plan file in `docs/plans/`
2. If plan status is not ABANDONED/DEFERRED/COMPLETED, counts unchecked tasks (`- [ ]`)
3. For each checked task (`- [x]`), verifies a matching evidence block exists
4. Validates evidence block structural integrity
5. Checks for FAIL/INCOMPLETE verdicts
6. **Blocks session from ending** if any check fails

**Why:** Prevents both half-done work AND self-reported completion without verification. Every checked task must have an independent evidence block from the task-verifier agent.

#### Safety Hooks (inline in settings.json)
**PreToolUse hooks that block dangerous actions at the tool level:**
- Editing `.env`, `.env.local`, `.env.production`, `credentials.json`, `secrets.yaml` → **BLOCKED**
- Editing lock files (`package-lock.json`, `bun.lock`, `yarn.lock`, `pnpm-lock.yaml`) → **BLOCKED**
- Running `curl | sh`, `chmod -R 777`, `mkfs`, `dd if=` → **BLOCKED**
- Running `gh repo create --public` or `gh repo edit --visibility public` → **BLOCKED**
  (Public repos are a one-way door. Requires explicit user authorization in the current message. See `rules/security.md`.)

#### Pre-Push Scanner (git hook, not a Claude Code hook)
**When:** Every `git push` from every repo on this machine (via `git config --global core.hooksPath`)

**What it does:** Scans the diff being pushed for:
1. Built-in credential patterns (API keys, tokens, JWTs, PEM keys)
2. Sensitive filenames (`.env*`, `credentials.json`, etc.)
3. Personal patterns from `~/.claude/sensitive-patterns.local`
4. Team-shared patterns from `~/.claude/business-patterns.d/*.txt`

**How it's wired:**
- `install.sh` runs `git config --global core.hooksPath $REPO/git-hooks`
- `git-hooks/pre-push` is the dispatcher that git invokes
- Dispatcher runs `hooks/pre-push-scan.sh` (the actual scanner)
- Then runs any local `.git/hooks/pre-push.local` the repo has defined

**Why global:** No per-repo setup. A new repo cloned tomorrow is automatically protected. The scanner runs regardless of which project you're working in.

**Override:** `git push --no-verify` bypasses ALL pre-push checks.

**Full details:** See `docs/business-patterns-workflow.md` for pattern sharing across teams.

---

### Agents (Specialized Sub-Processes)

Agents are specialized Claude instances spawned for specific tasks. They run in isolation and return results.

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `code-reviewer` | Reviews git diffs for quality, type safety, security, edge cases | Before every significant commit |
| `explorer` | Fast, cheap codebase lookups using the haiku model | When you need to find something without filling the main context window |
| `research` | Read-only deep research into architecture and data flow | Understanding how systems work before making changes |
| `security-reviewer` | Security-focused review: secrets, injection, auth/authz, data exposure | Before commits touching auth, API routes, or data access |
| `test-writer` | Generates tests matching project conventions and frameworks | After writing new features or fixing bugs |
| `ux-end-user-tester` | Simulates a non-technical user navigating every page | After new features, page redesigns, or workflow changes. Reports findings as P0/P1/P2 |

The `ux-end-user-tester` is the most comprehensive — it walks through every page as if it were a non-technical office worker, checking for jargon, dead ends, broken flows, and missing context. All P0 (blocking) and P1 (confusing) findings must be fixed before shipping.

---

### Templates (Structural Patterns)

Templates provide consistent structure for planning documents:

| Template | Used For |
|----------|----------|
| `plan-template.md` | Starting a new implementation plan. Sections: Goal, Scope (IN/OUT), Tasks (checkbox list), Files to Modify, Testing Strategy, Decisions Log, Definition of Done |
| `completion-report.md` | Appended to plan files when done. Sections: Implementation Summary, Design Decisions, Known Issues, Manual Steps, Testing, Cost Estimates |
| `decision-log-entry.md` | Recording mid-build decisions. Three tiers: (1) trivially reversible → continue + log, (2) revertible but multi-file → commit checkpoint + log, (3) DB schema/auth/production → stop and wait for approval |

---

### UX Standards & Guidelines

| File | Purpose |
|------|---------|
| `rules/ux-standards.md` | Enforceable UI rules loaded when editing component/page files |
| `docs/ux-guidelines.md` | Full design principles (color semantics, attention hierarchy, component patterns, anti-patterns) |

The UX standards rule is loaded by Claude Code in real-time when you're editing UI files, giving you continuous design guidance. The guidelines doc is the full reference you can read for the rationale behind each rule.

---

### SCRATCHPAD.md (Session Memory)

**Path:** `<project>/SCRATCHPAD.md`  
**Gitignored:** Yes  
**What it does:** Working memory that persists between Claude Code sessions

Updated at: start of tasks, after completing work, when making non-obvious decisions.  
Structure: Current State, Completed Work, Key Decisions, Known Issues, Next Steps.

**Why:** After context compaction or a new session, Claude Code reads SCRATCHPAD.md first to know where things stand. Without it, every session starts from scratch.

### Plan Files (Permanent Records)

**Path:** `<project>/docs/plans/<descriptive-slug>.md`  
**Committed:** Yes — permanent part of the repo

Lifecycle:
1. Created during planning with a task checklist
2. Tasks checked off during implementation
3. Mid-build decisions logged with tier classification
4. Completion report appended at the end
5. Status set to COMPLETED (never deleted)

---

## How It All Fits Together

```
Session Start
    │
    ├── SessionStart hook: switch GitHub + Supabase accounts
    ├── Load CLAUDE.md (project + global)
    ├── Load relevant rules based on file context
    └── Read SCRATCHPAD.md for session continuity
    
During Work
    │
    ├── Rules activate/deactivate as you edit different files
    ├── Agents spawned for reviews, research, testing
    ├── Plan file tracks task progress
    └── SCRATCHPAD.md updated at milestones
    
Before Commit
    │
    ├── code-reviewer agent reviews the diff
    ├── Pre-commit gate: tests → build → API consumer audit
    └── Commit blocked if any check fails
    
Session End
    │
    ├── Stop guard checks for incomplete plan tasks
    ├── SCRATCHPAD.md updated with final state
    └── Session blocked if unchecked tasks remain in active plan
```

---

## Setting Up Your Machine

See the repo README for full setup instructions. Summary:

1. **Claude Code CLI** — install and authenticate
2. **Clone this repo** anywhere (neutral path recommended)
3. **Run `./install.sh`** — symlinks the repo into `~/.claude/`
4. **Edit `~/.claude/settings.json`** — replace the placeholders (home path, projects dir, GitHub user)
5. **GitHub CLI** (`gh`) — authenticate with your account(s)
6. **Supabase CLI** (if needed) — store tokens at `~/.supabase/tokens/<account-name>`
7. **Node.js** — required for pre-commit gate (runs `npm test` and `npm run build`)

---

## What's Gitignored

In individual project repos (not this one):

| File/Path | Why Gitignored | Shareable? |
|-----------|---------------|------------|
| `SCRATCHPAD.md` | Ephemeral session state | No — each developer has their own |
| `.claude/auth-state.json` | Stored auth tokens | **No — credentials** |
| `.claude/pipeline-prompts/` | Pipeline prompts (if project-specific) | Depends |
| `.claude/screenshot*.png` | UI verification captures | No — transient |
| `.claude/logs/` | Pipeline execution logs | No — transient |
| `.env*` | Environment variables | **No — credentials** |
| `.pipeline/evidence.md` | Per-build pipeline evidence | No — transient |

In this repo: no credentials are stored here. Per-machine config (like database project IDs, org IDs, GitHub usernames) lives in `~/.claude/settings.json` which is copied from the template and customized locally.

---

## The Pipeline Agent System

Some projects use a multi-agent pipeline for complex changes. Three roles:

| Role | Can Do | Cannot Do |
|------|--------|-----------|
| **BUILDER** | Write code, stage changes, write evidence | Commit, push, approve |
| **VERIFIER** | Review diffs, run checks, output PASS/FAIL | Modify code, commit |
| **DECOMPOSER** | Break features into atomic tasks | Write code |

The global decomposition prompt at `pipeline-prompts/decompose.txt` enforces:
- Each task changes backend OR frontend (never both unless trivial)
- Backend tasks before frontend dependencies
- Database migrations before API endpoints
- Each task has a concrete verification command
- Each task identifies impact on existing data

The pipeline is optional — useful for complex multi-file features, overkill for small fixes.

---

## Enabled Plugins

These Claude Code plugins are typically active (configured in `settings.json.template`):

| Plugin | What It Does |
|--------|-------------|
| `claude-md-management` | Helps audit and improve CLAUDE.md files |
| `claude-code-setup` | Recommends automation improvements (hooks, agents, skills) |
| `code-review` | Enhanced code review capabilities |
| `explanatory-output-style` | Provides educational insights alongside code changes |
| `frontend-design` | Production-grade frontend component generation |
| `security-guidance` | Proactive security recommendations |
