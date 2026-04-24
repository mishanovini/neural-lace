# Claude Code Harness — Architecture Overview
Last updated: 2026-04-22 (quick-win automation: effort policy, verbose plans, meta-skills)

## Strategy & Evolution

See `docs/harness-strategy.md` for:
- Vision and strategic goals (self-evaluation, tech agnosticism, distribution)
- The 4-layer architecture model (Principles → Patterns → Adapters → Project-specific)
- Security maturity model and targets
- Component lifecycle policy (agents, rules, hooks, templates)
- Version milestones toward distribution-readiness

## Generation 4 Enforcement (2026-04-15) — Mechanisms and Patterns

The harness has two classes of improvement: **Mechanisms** (hook-enforced, mechanically block the failure mode) and **Patterns** (documented conventions the builder self-applies, valuable even without a hook). Gen 4 established a stronger mechanism layer by moving enforcement from self-applied prose rules to mechanically-executed hooks. Patterns complement mechanisms by documenting workflows that would be over-engineered to mechanize.

Both are reviewed by the `harness-reviewer` agent, which classifies changes first and applies class-appropriate criteria (see `~/.claude/agents/harness-reviewer.md`).

### Mechanisms (hook-enforced, mechanical gates)

| Mechanism | What it enforces | Type |
|---|---|---|
| `pre-commit-tdd-gate.sh` | New + modified runtime files must have tests; integration tiers cannot mock; trivial assertions alone are rejected; silent-skip tests blocked (Layer 5) | Mechanical (pre-commit) |
| `plan-edit-validator.sh` | Plan checkbox flips require fresh matching evidence file AND Runtime verification entry | Mechanical (PreToolUse) |
| `outcome-evidence-gate.sh` **(Gen 5)** | Fix tasks (matching fix/bug/broken/etc.) require before/after reproduction evidence — same runtime verification command showing FAIL pre-fix and PASS post-fix. Escape hatch for cases where automated before-state can't be captured: a "Reproduction recipe" block documenting manual repro | Mechanical (PreToolUse) |
| `systems-design-gate.sh` **(Gen 5)** | Edits to design-mode files (CI/CD workflows, migrations, vercel.json, Dockerfile, etc.) require an active plan with `Mode: design` in `docs/plans/`. Escape hatch: `Mode: design-skip` for trivial edits (version bumps, typos) with a short written justification. Forces systems-engineering thinking before implementation | Mechanical (PreToolUse) |
| `runtime-verification-executor.sh` | "Runtime verification:" lines must parse as `test`/`playwright`/`curl`/`sql`/`file` and actually execute; `test`/`playwright` entries reject files containing unannotated runtime-conditional skips (silent-skip vaporware guard, 2026-04-15) | Mechanical (Stop hook) |
| `runtime-verification-reviewer.sh` | Verification commands must correspond to modified files (curl URL, sql table, test imports) | Mechanical (Stop hook) |
| `plan-reviewer.sh` | Plans must have Scope, DoD, decomposed sweep tasks, Runtime verification specs, and all 7 required sections populated (Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy — Check 6b, 2026-04-22) | Mechanical (pre-commit) |
| `effort-policy-warn.sh` **(2026-04-22)** | SessionStart warning when configured effort level is below the project-level (`.claude/effort-policy.json`) or user-level (`~/.claude/local/effort-policy.json`) declared minimum. Ordering: `low < medium < high < xhigh <= max`. Non-blocking. | Mechanical (SessionStart, warn-only) |
| `tool-call-budget.sh` | Every 30 tool calls blocks until plan-evidence-reviewer is invoked | Mechanical (PreToolUse) |
| `post-tool-task-verifier-reminder.sh` | Reminds to invoke task-verifier when editing src files matching unchecked plan tasks | Soft (PostToolUse) |
| `claim-reviewer.md` (agent) | Product Q&A claims must cite file:line | Self-invoked (residual gap) |
| `verify-feature` skill | Ripgrep-backed citation lookup before making feature claims | Self-invoked |
| `backlog-plan-atomicity.sh` | New plan with non-empty `Backlog items absorbed:` requires `docs/backlog.md` also staged | Mechanical (pre-commit) |
| `decisions-index-gate.sh` | Decision record (`docs/decisions/NNN-*.md`) and `docs/DECISIONS.md` index must be staged together | Mechanical (pre-commit) |
| `docs-freshness-gate.sh` | Structural harness changes (A/D/R) require docs staged | Mechanical (pre-commit) |
| `migration-claude-md-gate.sh` | New `supabase/migrations/*.sql` requires `CLAUDE.md "Migrations: through N"` line update | Mechanical (pre-commit, opt-in) |
| `review-finding-fix-gate.sh` | Commit message references review finding ID → review file must also be staged | Mechanical (pre-commit) |
| `no-test-skip-gate.sh` **(2026-04-20)** | Staged `*.spec.ts` / `*.test.ts` diffs are scanned for new `test.skip(`, `it.skip(`, `.skip(` on describe blocks, and `xtest(` / `xdescribe(`. Blocked unless the skip line references an issue number (`#NNN` or `github.com/.*/issues/NNN`). Prevents vaporware testing where data-unavailability was dodged by skipping instead of seeding. | Mechanical (pre-commit) |
| `bug-persistence-gate.sh` **(2026-04-20)** | Stop hook. Scans session transcript for trigger phrases indicating a bug was identified ("we should also", "for next session", "turns out X doesn't work", "as a follow-up", "known issue", etc.). If matches exist AND no change to `docs/backlog.md` or new `docs/reviews/YYYY-MM-DD-*.md` file exists in working tree / recent commits, blocks session end. Escape hatch: `.claude/state/bugs-attested-YYYY-MM-DD-HHMM.txt` with per-match justification (false positives). Mechanical enforcement of the bug-persistence rule in `testing.md`. | Mechanical (Stop hook) |

The residual gap (verbal vaporware) is bounded by Claude Code's lack of a PostMessage hook and is mitigated via the `verify-feature` skill + memory priming + user interrupt authority.

### Patterns (documented conventions, self-applied)

| Pattern | What it documents | Enforcement status |
|---|---|---|
| `orchestrator-pattern.md` **(2026-04-16)** | Multi-task plans: main session dispatches build work to `plan-phase-builder` sub-agents instead of building directly, preferring parallel dispatch in isolated git worktrees when tasks are independent. Build-in-parallel, verify-sequentially. | Self-applied; `task-verifier` + `tool-call-budget.sh` + `plan-edit-validator.sh` catch correctness regressions indirectly; no mechanism detects direct-build discipline violations. Documented gaps and future-hook candidates listed in the rule. |

Patterns are NOT weaker than Mechanisms — they solve different problems. Mechanisms block specific failure modes at the moment of temptation; Patterns document workflows that improve quality across time but aren't about blocking a single identifiable failure. Turning every Pattern into a Mechanism would create friction disproportionate to the benefit; leaving every Mechanism as a Pattern reintroduces the self-enforcement failure modes Gen 4 was built to address. Both classes coexist.

## Core Configuration

| File | Purpose |
|------|---------|
| `~/.claude/settings.json` | Central config: permissions, 13 hooks across 6 lifecycle events, 6 plugins, effort level |
| `~/.claude/settings.json.template` | Template shipped via neural-lace install.sh. Declares `effortLevel: "max"` as the default for fresh installs (2026-04-22). User-edited `settings.json` is preserved on re-install via `.example` suffix convention. |
| `~/.claude/local/effort-policy.json.example` **(2026-04-22)** | User-level effort policy template. User copies to `effort-policy.json` to declare a per-account minimum effort level that `effort-policy-warn.sh` checks on each SessionStart. Schema: `{"minimum_effort_level": "<low\|medium\|high\|xhigh\|max>"}`. |
| `~/.claude/CLAUDE.md` | Global behavioral instructions: autonomy, SCRATCHPAD protocol, code quality, context hygiene, memory discipline. References all rule files. |

## Lifecycle Hooks (settings.json)

### SessionStart (2 entries)

**Compact recovery** (matcher: `"compact"`):
- Checks SCRATCHPAD.md date against today — warns if stale or missing
- Checks `docs/backlog.md` date — warns if stale
- Checks most recent plan in `docs/plans/` — warns if active with unchecked tasks
- Instructs: read SCRATCHPAD → plan → backlog before doing anything

**Account switcher + pipeline detector** (matcher: `""`):
- Detects the current directory against configured account `dir_triggers` in `~/.claude/local/accounts.config.json` and switches GitHub + Supabase accounts accordingly
- Checks for `orchestrate.sh` or `evidence.md` → reports pipeline status

### PreToolUse (8 entries)

| Hook | Matcher | What it blocks / does |
|------|---------|----------------------|
| Sensitive file blocker | `Edit\|Write` | `.env`, `credentials.json`, `secrets.yaml` |
| Lock file blocker | `Edit\|Write` | `package-lock.json`, `bun.lock`, `yarn.lock`, `pnpm-lock.yaml` |
| **Plan-edit validator (Gen 4)** | `Edit\|Write` | Blocks casual `[ ]`→`[x]` flips on `docs/plans/*.md`. Requires fresh evidence file with matching Task ID + Runtime verification entry (evidence-first authorization). Also blocks `Status: ACTIVE`→`COMPLETED` without an evidence file. |
| **Tool-call budget (Gen 4)** | `.*` | After 30 tool calls since last `--ack`, blocks further tool calls until plan-evidence-reviewer is invoked and `tool-call-budget.sh --ack` is run. Mitigates attention decay in long sessions. |
| Dangerous command blocker | `Bash` | `curl\|sh`, `chmod -R 777`, `mkfs.`, `dd if=` |
| Force-push / --no-verify blocker | `Bash` | `git push --force`, `--no-verify` |
| Public repo blocker | `Bash` | `gh repo create --public`, `gh repo edit --visibility public` |
| Pre-commit gate | `Bash` | On `git commit`: runs `check-harness-sync.sh` + `pre-commit-gate.sh` (TDD gate + plan-reviewer + tests + build + API audit) |
| Account switcher | `Bash` | On `git push`: switches `gh auth` to the account matching the remote URL per `~/.claude/local/accounts.config.json` |

### PostToolUse (1 entry — Gen 4)

| Hook | Matcher | Purpose |
|------|---------|---------|
| Task-verifier reminder | `Edit\|Write` | After editing a `src/` file that matches an unchecked task in the active plan, prints a persistent stderr reminder to invoke task-verifier before continuing. Cannot block (PostToolUse is advisory). |

### UserPromptSubmit (1 entry)
Sets terminal window title to `basename $PWD` (cosmetic).

### Notification (1 entry)
System beep (`\a`) on any notification.

### Stop (1 entry)
Runs `pre-stop-verifier.sh`:
1. Finds most recent plan in `docs/plans/` (excluding `-evidence.md`)
2. Skips if ABANDONED/DEFERRED (COMPLETED is the STRICTEST state)
3. Check 1: Unchecked tasks → BLOCK (stricter for COMPLETED plans)
4. Check 2: Checked tasks without evidence blocks → BLOCK
5. Check 3: Evidence block structural integrity → BLOCK
6. **Check 4a (Gen 4):** plans with runtime-feature tasks must have ≥1 `Runtime verification:` entry
7. **Check 4b (Gen 4):** calls `runtime-verification-executor.sh` — every entry must parse and execute successfully
8. **Check 4c (Gen 4):** calls `runtime-verification-reviewer.sh` — commands must correspond to modified files (curl URL, sql table, test imports)

## Hook Scripts (`~/.claude/hooks/`)

| Script | Triggered by | Purpose |
|--------|-------------|---------|
| `pre-commit-gate.sh` | PreToolUse (on `git commit`) | Orchestrates: TDD gate (0a), plan-reviewer (0b), npm test (1), npm build (2), API audit (3) |
| `pre-commit-tdd-gate.sh` **(Gen 4)** | `pre-commit-gate.sh` step 0a | 5 layers: new-file test requirement, modified-file full-path test reference, integration-tier mock ban, trivial-assertion ban, silent-skip ban (2026-04-15) |
| `plan-reviewer.sh` **(Gen 4 + 2026-04-22)** | `pre-commit-gate.sh` step 0b | Adversarial review of staged plan files: sweep decomposition, manual-verification language, missing Scope/DoD, Gen 3 anti-patterns, and Check 6b — all 7 required sections must be present AND populated with non-placeholder content (Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy). Has `--self-test` flag exercising 4 scenarios. |
| `plan-edit-validator.sh` **(Gen 4)** | PreToolUse `Edit\|Write` | Blocks plan checkbox flips without fresh matching evidence file |
| `outcome-evidence-gate.sh` **(Gen 5)** | PreToolUse `Edit\|Write` | For fix tasks specifically: blocks checkbox flip unless evidence contains `Runtime verification (before):` + `Runtime verification (after):` with the same command (proof the fix addresses the bug). Escape hatch: `Reproduction recipe:` block for manual-repro cases. Triggered by task descriptions matching fix/bug/broken/regression/etc. Non-fix tasks pass through untouched. |
| `systems-design-gate.sh` **(Gen 5)** | PreToolUse `Edit\|Write` | Blocks edits to design-mode files (`.github/workflows/*.yml`, migrations, `vercel.json`, `Dockerfile`, deploy/migrate scripts, terraform, nginx config) unless an active plan with `Mode: design` AND `Status: ACTIVE` exists in `docs/plans/`. Escape hatch: `Mode: design-skip` plan with a written justification referencing the target file's basename. Works alongside `plan-reviewer.sh` (which enforces section presence for `Mode: design` plans) and the `systems-designer` agent (which enforces section substance). |
| `runtime-verification-executor.sh` **(Gen 4)** | `pre-stop-verifier.sh` Check 4b | Parses and executes Runtime verification entries (`test`/`playwright`/`curl`/`sql`/`file`); since 2026-04-15 also rejects cited test files that contain silent-skip patterns (`test.skip(!CRED, ...)`, `test.skipIf(...)`, etc.) unless annotated with `// harness-allow-skip:` |
| `runtime-verification-reviewer.sh` **(Gen 4)** | `pre-stop-verifier.sh` Check 4c | Correspondence check: verification commands must actually exercise modified files |
| `tool-call-budget.sh` **(Gen 4)** | PreToolUse `.*` | Blocks after 30 tool calls without ack; `--ack` flag resets |
| `post-tool-task-verifier-reminder.sh` **(Gen 4)** | PostToolUse `Edit\|Write` | Reminder to invoke task-verifier when src edit matches unchecked plan task |
| `plan-lifecycle.sh` **(2026-04-23)** | PostToolUse `Edit\|Write` | Two responsibilities for files under `docs/plans/` (top-level only — not archive/): (1) on Write of a new plan file, surface a loud "uncommitted plan file" warning; (2) on any edit that transitions `Status:` from non-terminal to terminal (COMPLETED/DEFERRED/ABANDONED/SUPERSEDED), execute `git mv` to move the plan (and its `<slug>-evidence.md` companion if present) into `docs/plans/archive/`. Always advisory (PostToolUse never blocks). Has `--self-test` flag exercising 9 scenarios. |
| `pre-push-scan.sh` | Global git pre-push hook (NOT a Claude hook) | Scans push diffs for credentials. Loads 18 built-in patterns + `sensitive-patterns.local` + `business-patterns.paths` |
| `check-harness-sync.sh` | Pre-commit (via gate) | Warns if `~/.claude/` files have diverged from `neural-lace` repo |
| `pre-stop-verifier.sh` | Stop hook | Blocks session end if active plan has incomplete/unverified tasks. Check 4 calls executor + reviewer. |
| `bug-persistence-gate.sh` | Stop hook | Scans transcript for bug/gap trigger phrases; blocks if no persistence (backlog or review file) happened in this session. |
| `narrate-and-wait-gate.sh` | Stop hook | When the user has given a keep-going directive, blocks if the final assistant message trails off with a permission-seeking / wait-for-confirmation phrase. |
| `effort-policy-warn.sh` **(2026-04-22)** | SessionStart hook | Warns (non-blocking) when the configured effort level is below the minimum declared by a project-level `.claude/effort-policy.json` or user-level `~/.claude/local/effort-policy.json`. Ordering: `low < medium < high < xhigh <= max`. Has `--self-test` flag exercising 10 scenarios. |
| `sensitive-patterns.local` | Loaded by `pre-push-scan.sh` | Personal credential patterns (never shared) |
| `sensitive-patterns.local.example` | Documentation | Template showing the format for personal patterns |

### Full Hook Chain Traces

**git commit (Gen 4):**
```
Claude calls Bash("git commit ...")
  → PreToolUse → pre-commit-gate.sh
    → Step 0a: pre-commit-tdd-gate.sh
      Layer 1: new runtime files must have matching test files
      Layer 2: modified runtime files must have a test importing them (full-path)
      Layer 3: integration-tier tests cannot contain vi.mock/jest.mock/etc.
      Layer 4: test files cannot consist only of trivial assertions
      Layer 5: staged test code cannot introduce silent-skip patterns (2026-04-15)
      Any layer fires → BLOCK
    → Step 0b: plan-reviewer.sh (if staged docs/plans/*.md)
      6 checks: sweep decomposition, manual-verif, Scope, DoD, runtime specs, Gen 3 patterns
      Any finding → BLOCK
    → Step 1: npm test        (fail → BLOCK)
    → Step 2: npm run build   (fail → BLOCK)
    → Step 3: API audit       (fail → BLOCK)
    → All pass → commit executes
```

**Edit on a plan file (Gen 4):**
```
Claude calls Edit(docs/plans/foo.md, "- [ ]", "- [x]")
  → PreToolUse → plan-edit-validator.sh
    → Read CLAUDE_TOOL_INPUT or stdin (both supported)
    → Detect file_path matches docs/plans/*.md
    → Detect old_string has "- [ ]" and new_string has "- [x]"
    → Extract task ID (e.g., A.1)
    → check_evidence_first(plan, task_id):
        - Evidence file must exist at <plan>-evidence.md
        - Evidence file mtime must be <120 seconds old
        - Must contain "Task ID: A.1" line
        - Must contain ≥1 "Runtime verification:" line
        - All conditions → ALLOW
        - Any condition → BLOCK
```

**Tool call mid-session (Gen 4):**
```
Claude calls any tool (30th call since last ack)
  → PreToolUse → tool-call-budget.sh
    → Read counter from ~/.claude/state/tool-call-count.<session>
    → Increment counter
    → Compare counter - last_ack >= 30
    → BLOCK with "invoke plan-evidence-reviewer, then --ack"
    → Builder invokes plan-evidence-reviewer via Task tool
    → Builder runs: bash ~/.claude/hooks/tool-call-budget.sh --ack
    → ack file updated → unblocked
```

**Session ending (Gen 4):**
```
Session terminating
  → Stop hook → pre-stop-verifier.sh
    → Find most recent plan in docs/plans/ (excl -evidence)
    → Skip if ABANDONED/DEFERRED
    → Check 1: unchecked tasks on ACTIVE/COMPLETED → BLOCK
    → Check 2: checked tasks without evidence blocks → BLOCK
    → Check 3: evidence block structural integrity → BLOCK
    → Check 4a: runtime tasks require ≥1 "Runtime verification:" entry
    → Check 4b: runtime-verification-executor.sh runs every entry
                (test/playwright/curl/sql/file) — any failure → BLOCK
    → Check 4c: runtime-verification-reviewer.sh correspondence check
                (curl URL matches modified route, sql queries modified table,
                 test imports modified source) — any mismatch → BLOCK
```

**git push (any terminal):**
```
git push
  → global pre-push hook → pre-push-scan.sh
    → Load patterns: built-in + personal + team
    → Scan filenames (.env, .pem, id_rsa, etc.)
    → Scan content (API keys, tokens, JWTs, etc.)
    → Match → BLOCK with report
```

**Context compaction:**
```
/compact runs
  → SessionStart "compact" hook fires
    → Check SCRATCHPAD.md date → WARN if stale
    → Check docs/backlog.md date → WARN if stale
    → Check active plan → WARN if unchecked tasks
    → Print instructions: read SCRATCHPAD → plan → backlog
```

## Agents (`~/.claude/agents/`)

### Planning System
| Agent | Model | Purpose | Key constraint |
|-------|-------|---------|----------------|
| `task-verifier.md` | default | Verifies tasks are genuinely complete. **ONLY entity that can mark checkboxes in plan files.** Uses evidence-first protocol: writes evidence file with Runtime verification entries, then `plan-edit-validator.sh` authorizes the checkbox flip. Bans plain-text manual verification. | Has Edit access to plan files via evidence-first authorization |
| `plan-evidence-reviewer.md` | default | Independent second opinion on evidence blocks. Verdicts: CONSISTENT/INCONSISTENT/INSUFFICIENT/STALE. Invoked by the builder after every 30-call tool-call-budget block. | Read-only |
| `plan-phase-builder.md` **(2026-04-15)** | default | Builds a specific task or tightly-coupled cluster of tasks from an active plan end-to-end. Invoked by the orchestrator (main session) via the Task tool. Supports SERIAL and PARALLEL dispatch modes — PARALLEL builders run in isolated git worktrees to avoid commit races. The main session dispatches build work here instead of doing it directly, keeping the main context lean as an orchestrator. See `~/.claude/rules/orchestrator-pattern.md`. | Full `*` tool access; returns concise verdict under 500 tokens |

### Quality Gates
| Agent | Model | Purpose |
|-------|-------|---------|
| `code-reviewer.md` | default | Reviews diffs for quality, correctness, user impact, conventions |
| `security-reviewer.md` | default | Security-focused review: secrets, injection, auth, multi-tenant, rate limiting |
| `test-writer.md` | default | Generates tests for failure modes, not coverage numbers |
| `harness-reviewer.md` | default | Adversarial review of harness rule/hook/agent changes. Default verdict is REJECT. Used before landing any `~/.claude/` modification. |
| `claim-reviewer.md` **(Gen 4)** | default | Adversarial review of draft responses to product Q&A questions. Extracts feature claims and cross-checks against the codebase via `verify-feature` skill. **Self-invoked — residual gap** (Claude Code lacks a PostMessage hook). |

### UX Testing (3 mandatory after substantial UI builds)
All three are **audience-aware** — they read the target user from `.claude/audience.md` in the project root, or from the project's `CLAUDE.md`, or infer it from the code.

| Agent | Model | Purpose |
|-------|-------|---------|
| `ux-end-user-tester.md` | Sonnet | Generic non-technical user walkthrough (any project) |
| `domain-expert-tester.md` | Sonnet | Becomes the project's target persona as declared in `.claude/audience.md` and tests workflows from their perspective |
| `audience-content-reviewer.md` | Sonnet | Reviews all user-facing text against the project's target audience for wrong-audience language, jargon, empty/placeholder content, and vendor names |
| `ux-designer.md` | default | Pre-build UX review of plans for new UI surfaces |
| `systems-designer.md` **(Gen 5)** | default | Pre-build systems-engineering review for plans with `Mode: design`. Reviews the 10-section Systems Engineering Analysis (outcome, trace, contracts, environment, auth, observability, FMEA, idempotency, capacity, runbook) for substance. Returns PASS/FAIL with specific gaps. MUST pass before implementation on design-mode plans |

**To define your project's audience:** create `.claude/audience.md` with a description of the persona, their vocabulary, what they care about, and what confuses them.

### Exploration
| Agent | Model | Purpose |
|-------|-------|---------|
| `explorer.md` | Haiku | Fast, cheap codebase lookups (avoids filling main context) |
| `research.md` | default | Deep architecture analysis with structured output |

## Rules (`~/.claude/rules/`)

Rules are loaded contextually when Claude detects relevant files being edited.

| Rule | Scope | Key enforcement |
|------|-------|-----------------|
| `planning.md` | Task planning | Strategy-first for substantial features, UX during design, plan files in `docs/plans/`, task-verifier mandate, reusable component rule, session retrospectives, decision tiers. References `orchestrator-pattern.md` for multi-task plan execution. Distinguishes `Mode: code` vs `Mode: design` and points at `design-mode-planning.md` for systems work. Contains "Verbose Plans Are Mandatory" section (2026-04-22) — all plans must enumerate Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy regardless of size; enforced by `plan-reviewer.sh` Check 6b. |
| `design-mode-planning.md` **(Gen 5)** | System design tasks | The 10-section Systems Engineering Analysis protocol for design-mode plans. When to use design-mode (CI/CD, migrations, infra, multi-service integrations). What each of the 10 sections requires with PASS/FAIL examples. Documents the enforcement chain (template → plan-reviewer → systems-designer agent → systems-design-gate). Escape hatch: `Mode: design-skip` for trivial edits. |
| `orchestrator-pattern.md` **(2026-04-16)** | Multi-task plans | **Pattern-class** (self-applied, not hook-enforced). Main session dispatches build work to `plan-phase-builder` sub-agents instead of building directly. Parallel dispatch is the preferred mode when tasks touch disjoint files — up to 5 concurrent builders in isolated git worktrees via `isolation: "worktree"`. Build-in-parallel, verify-sequentially. See also Patterns section of this doc. |
| `testing.md` | All testing | 6-layer tests, pre-commit code review, 3 UX agents mandatory, link validation, deployment validation |
| `vaporware-prevention.md` **(Gen 4 stub)** | UI/API/webhook/cron/migration edits | 46-line pointer at Gen 4 hooks; enforcement map; pattern recognition; residual gap disclosure |
| `diagnosis.md` | Bug investigation + failure response | Full-chain tracing, retry before giving up, encode fixes into rules proactively, trust observable output, user corrections → rule proposals |
| `api-routes.md` | `src/app/api/**` | Test with curl, document response shape, verify auth/RLS/columns |
| `database-migrations.md` | `supabase/**` | Check existing data, handle NOT NULL, add RLS immediately, verify schema |
| `ui-components.md` | `src/components/**` | Trace every prop, verify conditionals, confirm click handlers, check dynamic styles |
| `ux-standards.md` | `src/components/**` | Color rules, visual contrast mandates, state handling, AI features, accessibility |
| `ux-design.md` | UI work | Error messages suggest solutions, empty states explain + offer action, destructive confirmations |
| `react.md` | `*.tsx` | Semantic HTML, ARIA, async states, Server Components default |
| `typescript.md` | `*.ts` | strict:true, import type, no any, explicit returns, no console.log |
| `git.md` | Git operations | Natural milestones, `<type>: <desc>`, never push without asking, never commit to main |
| `security.md` | All | Never commit .env, never create public repos, pre-push scanner |
| `pipeline-agents.md` | Pipeline mode | BUILDER/VERIFIER/DECOMPOSER roles with strict boundaries |
| `harness-maintenance.md` | `~/.claude/**` changes | Global-first, commit to neural-lace repo, update architecture doc, no project-level copies |
| `deploy-to-production.md` **(2026-04-20)** | Any project where master merge auto-deploys to production (Vercel/similar) | Default: always merge + deploy to production after testing. Never leave work on a preview branch for manual merge. Preview is for the agent's own pre-merge validation only — the user tests in production. Pattern-class (no hook); the user's feedback memory + this rule carry it. |

## Templates (`~/.claude/templates/`)

| Template | Used by | Purpose |
|----------|---------|---------|
| `plan-template.md` | `planning.md` | Structure for new plan files. Contains 7 required sections (2026-04-22): Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy — each with placeholder prompts. Validated by `plan-reviewer.sh` Check 6b. |
| `completion-report.md` | `planning.md` | Appended to plan files when all tasks complete |
| `decision-log-entry.md` | `planning.md` | Mid-build decision records |

## Scripts (`~/.claude/scripts/`)

Copy-in testing utilities that projects install into their own `tests/` or `scripts/` directory. These are framework-agnostic and configurable.

| Script | Purpose | Install |
|--------|---------|---------|
| `validate-links.ts` | Dead link validator for Next.js/Remix apps. Walks `href` values in source files and verifies routes exist. | `cp ~/.claude/scripts/validate-links.ts tests/` then add `"test:links": "npx tsx tests/validate-links.ts"` to package.json |
| `audit-consistency.ts` | Code-consistency audit. Flags raw string formatting, unapproved colors, HTML entity arrows, h1 in pages, outline-only buttons, missing loading.tsx, inline fallback chains. Configurable via `.audit-consistency.json`. | `cp ~/.claude/scripts/audit-consistency.ts scripts/` then add `"audit:consistency": "npx tsx scripts/audit-consistency.ts"` to package.json |

Both scripts exit non-zero on failure and print a structured report. They can be wired into CI or git hooks.

## Skills (`~/.claude/skills/`)

| Skill | Purpose |
|-------|---------|
| `verify-feature.md` **(Gen 4)** | Ripgrep-backed citation lookup. Invoke BEFORE answering any "does X work?" / "is Y wired up?" / "how does Z handle W?" question to ground the answer with file:line citations. |
| `find-skills` | Discovery helper for finding which skill matches a task |
| `new-project-setup` | Scaffolds a new project with Claude Code configuration |
| `why-slipped.md` | Post-mortem analyzer. After a bug, identifies what hook/rule/agent should have caught it and proposes a specific harness fix. |
| `find-bugs.md` | Adversarial self-audit. Invoke after significant changes to enumerate likely failure modes and run verification commands before the user finds issues. |
| `verbose-plan.md` | Plan expander. Fills gaps in thin plan files (Assumptions, Edge Cases, Testing Strategy) so they meet the mandatory verbose-plan standard. |
| `harness-lesson.md` | Failure-to-mechanism encoder. Takes a recent failure and proposes a concrete harness change (full file path + actual content) to prevent the class. |

## Docs (`~/.claude/docs/`)

| Doc | Referenced by | Purpose |
|-----|--------------|---------|
| `ux-checklist.md` | UX agents, `ux-standards.md` | 22-domain UX design checklist |
| `ux-guidelines.md` | `ux-standards.md` | Full design principles, component patterns, anti-patterns |
| `harness-guide.md` | — | Developer documentation for the harness |
| `harness-strategy.md` | — | Evolution strategy and vision |
| `business-patterns-workflow.md` | `pre-push-scan.sh` | Team-shared sensitive patterns setup guide |
| `harness-architecture.md` | — | This file |

## Persistence Layers

```
EPHEMERAL (dies with session)     DURABLE (survives /clear and /compact)
┌────────────────────────┐        ┌──────────────────────────────────┐
│ Conversation context   │        │ SCRATCHPAD.md (30-line pointer)  │
│ Todo list              │        │ docs/plans/*.md (detailed tasks) │
│ In-flight tool state   │        │ docs/backlog.md (feature queue)  │
└────────────────────────┘        │ docs/sessions/*.md (history)     │
                                  │ docs/decisions/*.md (records)    │
CROSS-CONVERSATION                │ Git history                      │
┌────────────────────────┐        └──────────────────────────────────┘
│ Auto-memory (MEMORY.md)│
│  user / feedback /     │
│  project / reference   │
└────────────────────────┘

GEN 4 SESSION STATE
┌──────────────────────────────────┐
│ ~/.claude/state/                 │
│   tool-call-count.<session>      │
│   audit-ack.<session>            │
└──────────────────────────────────┘
```

**Freshness enforcement:**
- SCRATCHPAD.md — compact hook checks date, warns if stale
- Plan files — pre-stop hook checks task completion + evidence + runtime verification execution
- Backlog — compact hook checks date, warns if stale
- Session summaries — no enforcement (write-once records)
- Decisions — no enforcement (write-once records)
- Tool-call state — per-session, reset on session start, explicitly ack'd via `tool-call-budget.sh --ack`

## Project-Level Overrides

Projects can have their own `.claude/` directory with:
- `rules/` — project-specific rules (loaded alongside global rules)
- `skills/` — project-specific MCP skills
- `pipeline-prompts/` — project-specific decomposition prompts
- `auth-state.json` — Playwright auth tokens

## Pipeline System (`~/.claude/pipeline-templates/`)

Optional multi-agent autonomous pipeline for complex features:

| File | Purpose |
|------|---------|
| `orchestrate.sh` | Coordinates BUILDER and VERIFIER agents. Builder stages + writes evidence, verifier checks, orchestrator commits. |
| `verify-existing-data.sh` | Database verification: check-nulls, check-fk, check-enum, run-query |
| `verify-ui.mjs` | Playwright-based UI screenshot verification |

Activated per-project by copying templates into the project directory. SessionStart hook detects active pipelines.

## Credential Protection (3 layers)

1. **PreToolUse hooks** — block Edit/Write on `.env`, credentials, secrets
2. **Pre-commit gate** — runs tests + build before every commit (catches runtime credential usage)
3. **Pre-push scan** — pattern-matches push diffs against 18+ credential regexes + personal + team patterns. Last-line defense.

Pattern sources merged at push time:
- Built-in: 18 generic patterns (GitHub tokens, Anthropic/OpenAI keys, Stripe, AWS, Google, Twilio, SendGrid, Mailgun, JWTs, PEM blocks, Supabase service role)
- `~/.claude/sensitive-patterns.local` — personal patterns
- `~/.claude/business-patterns.paths` → resolves to team `security-docs/business-patterns.txt`

## Plugin System

6 plugins enabled in settings.json:
- `claude-md-management` — manages CLAUDE.md files
- `claude-code-setup` — initial setup assistance
- `code-review` — code review integration
- `explanatory-output-style` — educational insights with ★ markers
- `frontend-design` — frontend design assistance
- `security-guidance` — security best practices
