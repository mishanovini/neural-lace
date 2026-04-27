# Claude Code Harness — Architecture Overview
Last updated: 2026-04-24 (Gen 5 production runtime acceptance gate: new `product-acceptance-gate.sh` Stop hook (position 4 — last in chain) blocks session end when ACTIVE plans lack PASS runtime acceptance artifacts at `.claude/state/acceptance/<slug>/*.json` with matching `plan_commit_sha`; honors `acceptance-exempt: true` + reason; per-session waiver mechanism mirrors bug-persistence pattern; 8-scenario `--self-test`. Earlier 2026-04-24: Gen 5 walking skeleton — new `end-user-advocate` agent for plan-time + runtime adversarial product observation; `pre-stop-verifier.sh` Check 0 recognizes `acceptance-exempt: true` plan-header field and emits `[acceptance-gate]` log lines. Earlier 2026-04-24: class-aware reviewer feedback — 7 adversarial-review agents emit per-gap six-field blocks with `Class:` + `Sweep query:` + `Required generalization:`; `rules/diagnosis.md` adds the "Fix the Class, Not the Instance" sub-rule consuming this contract)

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
| `runtime-verification-reviewer.sh` | Verification commands must correspond to modified files (curl URL, sql table, test imports). Excludes archived plans (`docs/plans/archive/**`) from modified-file analysis (2026-04-23) | Mechanical (Stop hook) |
| `plan-reviewer.sh` | Plans must have Scope, DoD, decomposed sweep tasks, Runtime verification specs, and all 7 required sections populated (Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy — Check 6b, 2026-04-22) | Mechanical (pre-commit) |
| `effort-policy-warn.sh` **(2026-04-22)** | SessionStart warning when configured effort level is below the project-level (`.claude/effort-policy.json`) or user-level (`~/.claude/local/effort-policy.json`) declared minimum. Ordering: `low < medium < high < xhigh <= max`. Non-blocking. | Mechanical (SessionStart, warn-only) |
| `tool-call-budget.sh` | Every 30 tool calls blocks until plan-evidence-reviewer is invoked | Mechanical (PreToolUse) |
| `post-tool-task-verifier-reminder.sh` | Reminds to invoke task-verifier when editing src files matching unchecked plan tasks. Uses `scripts/find-plan-file.sh` to fall back to archived plans when no active plan correlates with the edited file (2026-04-23) | Soft (PostToolUse) |
| `claim-reviewer.md` (agent) | Product Q&A claims must cite file:line | Self-invoked (residual gap) |
| `verify-feature` skill | Ripgrep-backed citation lookup before making feature claims | Self-invoked |
| `backlog-plan-atomicity.sh` | New plan with non-empty `Backlog items absorbed:` requires `docs/backlog.md` also staged | Mechanical (pre-commit) |
| `decisions-index-gate.sh` | Decision record (`docs/decisions/NNN-*.md`) and `docs/DECISIONS.md` index must be staged together | Mechanical (pre-commit) |
| `docs-freshness-gate.sh` | Structural harness changes (A/D/R) require docs staged | Mechanical (pre-commit) |
| `migration-claude-md-gate.sh` | New `supabase/migrations/*.sql` requires `CLAUDE.md "Migrations: through N"` line update | Mechanical (pre-commit, opt-in) |
| `review-finding-fix-gate.sh` | Commit message references review finding ID → review file must also be staged | Mechanical (pre-commit) |
| `no-test-skip-gate.sh` **(2026-04-20)** | Staged `*.spec.ts` / `*.test.ts` diffs are scanned for new `test.skip(`, `it.skip(`, `.skip(` on describe blocks, and `xtest(` / `xdescribe(`. Blocked unless the skip line references an issue number (`#NNN` or `github.com/.*/issues/NNN`). Prevents vaporware testing where data-unavailability was dodged by skipping instead of seeding. | Mechanical (pre-commit) |
| `observed-errors-gate.sh` **(2026-04-25)** | PreToolUse hook on `git commit`. When commit message contains a fix-class keyword (`fix\|fixed\|fixes\|bug\|broken\|regression\|repair\|resolve\|hotfix`) AND the commit modifies non-doc-only files, requires `.claude/state/observed-errors.md` to (a) exist, (b) have mtime within last 60 minutes, (c) contain at least one recognizable error pattern (HTTP 4xx/5xx, exception keyword, stack frame, test failure diff, or console error). Forces the verbatim-error-capture step before fixes ship. Override via `OBSERVED_ERRORS_OVERRIDE=<reason>` env var; overrides logged to `.claude/state/observed-errors-overrides.log` for periodic chronic-use review. Origin: incident where the agent saw HTTP 500 returned five times before reading the response body — body would have given the root cause instantly. Audit lenses applied: triggers on observable commit shape (not self-classification), narrow remedy, low cheap-evasion paths. Rule: `rules/observed-errors-first.md`. | Mechanical (PreToolUse) |
| `bug-persistence-gate.sh` **(2026-04-20)** | Stop hook. Scans session transcript for trigger phrases indicating a bug was identified ("we should also", "for next session", "turns out X doesn't work", "as a follow-up", "known issue", etc.). If matches exist AND no change to `docs/backlog.md` or new `docs/reviews/YYYY-MM-DD-*.md` file exists in working tree / recent commits, blocks session end. Escape hatch: `.claude/state/bugs-attested-YYYY-MM-DD-HHMM.txt` with per-match justification (false positives). Mechanical enforcement of the bug-persistence rule in `testing.md`. | Mechanical (Stop hook) |
| `product-acceptance-gate.sh` **(Gen 5, 2026-04-24)** | Stop hook (position 4 — chained AFTER pre-stop-verifier + bug-persistence + narrate-and-wait). Walks every ACTIVE plan in `docs/plans/` and blocks session end unless each has either: (a) `acceptance-exempt: true` plan-header field with a substantive `acceptance-exempt-reason:` (>= 20 chars), (b) a per-session waiver at `.claude/state/acceptance-waiver-<slug>-<ts>.txt` younger than 1 hour, or (c) a runtime acceptance JSON artifact at `.claude/state/acceptance/<slug>/*.json` whose `plan_commit_sha` matches the plan file's current git SHA AND whose scenarios are all `verdict: "PASS"`. Production runtime gate for the end-user-advocate loop (Phase D of `docs/plans/end-user-advocate-acceptance-loop.md`). 8-scenario `--self-test` flag. | Mechanical (Stop hook) |
| `deferral-counter.sh` **(A5 — Gen 6, 2026-04-26)** | Stop hook (position 5 — last in chain). Reads `$TRANSCRIPT_PATH` (Claude Code's JSONL session log, which the agent cannot edit) and pattern-matches a comprehensive synonym list of deferral phrases (`deferred`, `follow-up`, `PHASE\d+-FOLLOWUP`, `for now`, `stub`, `scaffold`, `mocked`, `simulated`, `walking-skeleton`, `DO NOT run`, `out of scope for this`, `awaiting user`, `requires user`, `pending approval`, plus ~40 more). If session has matches AND the agent's last assistant message lacks `## Deferrals not executed in this session` heading with at least one bullet, blocks session end with the verbatim list in stderr — forcing the deferrals into the user-visible final message rather than buried mid-session text. The user only reliably reads end-of-effort summaries; this hook makes deferrals impossible to hide there. Origin: 2026-04-26 incident where the agent marked a plan COMPLETED while writing "deferred to user" / "PHASE6-FOLLOWUP-01" / "first run is user-driven decision" three times in PR bodies and SCRATCHPAD — none appeared in the user-facing summary. Self-tested against the live session: 92 deferral phrases matched. Escape hatch: `DEFERRAL_COUNTER_DISABLE=1` for harness-development sessions where editing the synonym list itself would self-trigger. | Mechanical (Stop hook) |
| `transcript-lie-detector.sh` **(A3 — Gen 6, 2026-04-26)** | Stop hook (position 6 — chained AFTER deferral-counter). Reads `$TRANSCRIPT_PATH` JSONL (which the agent cannot edit) and detects **self-contradiction within session**: pairs of agent text where one event class asserts completion (`Plan COMPLETED`, `Status: COMPLETED`, `all phases done`, `tests pass`, `shipped`, `verified working`, `feature is done`, `phase \d+ done`, plus ~10 more) while another event class admits deferral (`deferred to user`, `PHASE\d+-FOLLOWUP`, `A\d+-FOLLOWUP`, `first run is user-driven`, `user-driven decision`, `awaiting user`, `requires user (approval\|authorization)`, `not yet executed`, `couldn't verify`, `test failed`, `unable to verify`, `pending approval`, `did not (run\|execute)`, plus ~10 more). When both classes appear in the same session, blocks session end UNLESS the agent's last assistant message contains the heading `## Resolved contradictions in this session` with at least one bullet — forcing the contradictions to be reconciled (flip Status back to ACTIVE, surface the deferrals) or explicitly addressed in the user-visible final message. Origin: 2026-04-26 incident where the agent flipped a plan to COMPLETED while the same session's transcript contained multiple deferral-class claims; A5 catches the deferrals individually but not the contradiction with a sibling COMPLETED claim. v1 implements only the self-contradiction class; broken-promise (A3-FOLLOWUP-01) and skipped-imperative (A3-FOLLOWUP-02) are filed for v2. Self-tested via `--self-test` flag against three fixtures (self-contradiction blocks, clean allows, resolved allows) and live-validated against the originating session JSONL (caught 277 completion-class + 33 deferral-class claims; >= 33 contradiction pairs). Escape hatch: `TRANSCRIPT_LIE_DETECTOR_DISABLE=1` for harness-development sessions where editing the pattern lists self-triggers. | Mechanical (Stop hook) |
| `imperative-evidence-linker.sh` **(A7 — Gen 6, 2026-04-26)** | Stop hook (position 7 — chained AFTER transcript-lie-detector). Reads `$TRANSCRIPT_PATH` JSONL (which the agent cannot edit), extracts the user's last K substantive messages (default K=30, override `IMPERATIVE_LINKER_WINDOW`), and links each strong imperative (clauses containing `must`, `need to`, `required to`, `have to`, `please`, `go ahead and`, `make sure to`, `should`) to specific tool-call evidence in the same session. Pattern library at `adapters/claude-code/data/imperative-patterns.json` declares 12 seed patterns mapping `(verb, object_pattern)` to an `evidence` regex applied against a flat `<ToolName>:<input-summary>` ledger built from the transcript's `tool_use` events (e.g., `run` + `tests` -> `Bash:(npm test\|vitest\|jest\|playwright\|pytest\|...)`). When a triggered imperative has no matching tool-call event, it's recorded as a SKIPPED IMPERATIVE — the user explicitly asked, the agent never even tried. Blocks session end UNLESS the last assistant message contains the heading `## User-imperative coverage` with at least one bullet, forcing each gap into the user-visible final message. Closes the gap A3 left open: A3 catches the agent contradicting itself (says "done" while writing "not done"); A7 catches the agent silently skipping a user directive entirely. Self-tested via `--self-test` flag against three fixtures (run-tests-no-evidence blocks, run-tests-with-evidence allows, with-coverage-section allows) and live-validated against the originating session JSONL (caught the dispatch-prompt's "must run the tests" imperative). Escape hatch: `IMPERATIVE_LINKER_DISABLE=1` for harness-development sessions where editing the pattern library self-triggers. | Mechanical (Stop hook) |
| `vaporware-volume-gate.sh` **(A8 — Gen 6, 2026-04-26)** | PreToolUse hook on `Bash` matching `gh pr create`. Reads cumulative branch state via `git diff origin/master...HEAD --numstat` and computes (a) lines added to behavior-DESCRIBING files (`.md`, `.yml`, `.yaml`, `.json`, `.sh`, `.ts`, `.tsx`, `.js`, `.jsx`, plus paths under `docs/`, `.github/workflows/`, `scripts/`, `hooks/`) vs. (b) count of behavior-EXECUTING artifact files (`*.log`, screenshots, `*.har`, `junit*.xml`, `test-results*.json`, `*-evidence.{md,json}`, `*-trace.{json,txt}`, paths under `*/loop-history/`, `*/test-results/`, `*/logs/`, `*/screenshots/`, `*/artifacts/`, `*/coverage/`, `*/evidence/`). If describes-lines > 200 AND executes-files == 0, blocks the PR creation with a stderr message listing the offending files and the bypass instructions. Escape hatch: PR title prefix `[docs-only]` or `[no-execution]` skips the check (the prefix becomes part of the permanent PR title and is auditable). 3-fixture `--self-test` flag covering the vaporware shape, a real-feature PR with execution evidence, and the docs-only-with-prefix bypass. Origin: 2026-04-26 incident — agent shipped PR #123 with 800 lines of docs + 174 lines of CI YAML and ZERO execution evidence while the plan's own DoD said "Loop converges on master" was unchecked. The describes-vs-executes volume ratio is the canonical shape that should have caught it; this gate now does. | Mechanical (PreToolUse) |

The residual gap (verbal vaporware) is bounded by Claude Code's lack of a PostMessage hook and is mitigated via the `verify-feature` skill + memory priming + user interrupt authority.

### Patterns (documented conventions, self-applied)

| Pattern | What it documents | Enforcement status |
|---|---|---|
| `orchestrator-pattern.md` **(2026-04-16)** | Multi-task plans: main session dispatches build work to `plan-phase-builder` sub-agents instead of building directly, preferring parallel dispatch in isolated git worktrees when tasks are independent. Build-in-parallel, verify-sequentially. | Self-applied; `task-verifier` + `tool-call-budget.sh` + `plan-edit-validator.sh` catch correctness regressions indirectly; no mechanism detects direct-build discipline violations. Documented gaps and future-hook candidates listed in the rule. |
| `docs/failure-modes.md` **(2026-04-24)** | Project-level catalog of known harness failure CLASSES (not individual incidents). Each entry has six fields: ID (`FM-NNN`), Symptom, Root cause, Detection, Prevention, Example. Lives in the downstream project repo. Consulted by `rules/diagnosis.md` ("After Every Failure: Encode the Fix" — update the catalog or justify why not), `skills/harness-lesson.md` + `skills/why-slipped.md` (Step 0 — check catalog first to avoid duplicate mechanisms), `agents/claim-reviewer.md` (consult catalog when claims match known symptoms), `agents/task-verifier.md` (Step 2.5 — cross-check known-bad patterns like FM-006 self-report, FM-004 placeholder sections, FM-001 uncommitted plan). | Self-applied; behavioral enforcement only. No hook detects "session diagnosed a root cause without updating the catalog." Future hook candidate: a Stop-hook scan for diagnosis-language transcript signals AND no `docs/failure-modes.md` edit, blocking session end (parallel design to `bug-persistence-gate.sh`). |

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
| `runtime-verification-reviewer.sh` **(Gen 4)** | `pre-stop-verifier.sh` Check 4c | Correspondence check: verification commands must actually exercise modified files. Modified-file analysis excludes archived plans (`docs/plans/archive/**`) so historical-record edits don't trigger spurious correspondence demands (2026-04-23). |
| `tool-call-budget.sh` **(Gen 4)** | PreToolUse `.*` | Blocks after 30 tool calls without ack; `--ack` flag resets |
| `post-tool-task-verifier-reminder.sh` **(Gen 4)** | PostToolUse `Edit\|Write` | Reminder to invoke task-verifier when src edit matches unchecked plan task. Uses `scripts/find-plan-file.sh` to fall back to archived plans when no active plan matches the edited file (2026-04-23). |
| `plan-lifecycle.sh` **(2026-04-23)** | PostToolUse `Edit\|Write` | Two responsibilities for files under `docs/plans/` (top-level only — not archive/): (1) on Write of a new plan file, surface a loud "uncommitted plan file" warning; (2) on any edit that transitions `Status:` from non-terminal to terminal (COMPLETED/DEFERRED/ABANDONED/SUPERSEDED), execute `git mv` to move the plan (and its `<slug>-evidence.md` companion if present) into `docs/plans/archive/`. Always advisory (PostToolUse never blocks). Has `--self-test` flag exercising 9 scenarios. |
| `pre-push-scan.sh` | Global git pre-push hook (NOT a Claude hook) | Scans push diffs for credentials. Loads 18 built-in patterns + `sensitive-patterns.local` + `business-patterns.paths` |
| `check-harness-sync.sh` | Pre-commit (via gate) | Warns if `~/.claude/` files have diverged from `neural-lace` repo |
| `pre-stop-verifier.sh` | Stop hook | Blocks session end if active plan has incomplete/unverified tasks. Check 4 calls executor + reviewer. Also surfaces a non-blocking `[uncommitted-plans-warn]` warning when `docs/plans/*.md` (top-level only — archive excluded) has uncommitted files at session end (2026-04-23). |
| `bug-persistence-gate.sh` | Stop hook | Scans transcript for bug/gap trigger phrases; blocks if no persistence (backlog or review file) happened in this session. |
| `narrate-and-wait-gate.sh` | Stop hook | When the user has given a keep-going directive, blocks if the final assistant message trails off with a permission-seeking / wait-for-confirmation phrase. |
| `product-acceptance-gate.sh` **(Gen 5, 2026-04-24)** | Stop hook (position 4 — last in chain after pre-stop-verifier, bug-persistence, narrate-and-wait) | Blocks session end if any ACTIVE plan in `docs/plans/` lacks a PASS runtime acceptance artifact at `.claude/state/acceptance/<plan-slug>/*.json` whose `plan_commit_sha` matches the plan file's current git SHA. Recognizes `acceptance-exempt: true` plan-header field with required `acceptance-exempt-reason:` (>= 20 non-whitespace chars) — exempt plans skip the artifact check. Per-session waiver via `.claude/state/acceptance-waiver-<plan-slug>-<ts>.txt` (1-hour TTL, mirrors bug-persistence escape hatch). Production gate for the end-user-advocate loop (Phase D of `docs/plans/end-user-advocate-acceptance-loop.md`). Walking-skeleton recognition still lives in `pre-stop-verifier.sh` Check 0 (logs only, no blocking). Has `--self-test` flag exercising 8 scenarios: no-active-plan, valid-PASS, FAIL-artifact, no-artifact, stale-sha, valid-waiver, exempt-with-reason, exempt-without-reason. |
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

**Session ending (Gen 4 + Gen 5):**
```
Session terminating
  → Stop hook chain (in order):
  → 1. pre-stop-verifier.sh (plan-integrity)
    → Find most recent plan in docs/plans/ (excl -evidence)
    → Skip if ABANDONED/DEFERRED
    → Check 0: acceptance-loop awareness (logs only — Phase A walking skeleton)
    → Check 1: unchecked tasks on ACTIVE/COMPLETED → BLOCK
    → Check 2: checked tasks without evidence blocks → BLOCK
    → Check 3: evidence block structural integrity → BLOCK
    → Check 4a: runtime tasks require ≥1 "Runtime verification:" entry
    → Check 4b: runtime-verification-executor.sh runs every entry
                (test/playwright/curl/sql/file) — any failure → BLOCK
    → Check 4c: runtime-verification-reviewer.sh correspondence check
                (curl URL matches modified route, sql queries modified table,
                 test imports modified source) — any mismatch → BLOCK
  → 2. bug-persistence-gate.sh (user-process)
    → Scan transcript for trigger phrases; if matches found AND nothing
      persisted to docs/backlog.md or docs/reviews/ → BLOCK
  → 3. narrate-and-wait-gate.sh (user-process)
    → If keep-going directive given AND final assistant message trails
      off with permission-seeking phrase → BLOCK
  → 4. product-acceptance-gate.sh (Gen 5, product-outcome — last in chain)
    → Walk every ACTIVE plan in docs/plans/
    → For each: exempt? → allow. Per-session waiver? → allow.
      Otherwise: artifact at .claude/state/acceptance/<slug>/*.json
      with plan_commit_sha matching current HEAD AND all scenarios
      verdict=PASS? → allow. Otherwise → BLOCK.
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
| `plan-evidence-reviewer.md` | default | Independent second opinion on evidence blocks. Verdicts: CONSISTENT/INCONSISTENT/INSUFFICIENT/STALE. Invoked by the builder after every 30-call tool-call-budget block. Emits class-aware feedback per the six-field contract (`Line(s):` / `Defect:` / `Class:` / `Sweep query:` / `Required fix:` / `Required generalization:`) for every issue surfaced. | Read-only |
| `plan-phase-builder.md` **(2026-04-15)** | default | Builds a specific task or tightly-coupled cluster of tasks from an active plan end-to-end. Invoked by the orchestrator (main session) via the Task tool. Supports SERIAL and PARALLEL dispatch modes — PARALLEL builders run in isolated git worktrees to avoid commit races. The main session dispatches build work here instead of doing it directly, keeping the main context lean as an orchestrator. See `~/.claude/rules/orchestrator-pattern.md`. | Full `*` tool access; returns concise verdict under 500 tokens |

### Quality Gates
| Agent | Model | Purpose |
|-------|-------|---------|
| `code-reviewer.md` | default | Reviews diffs for quality, correctness, user impact, conventions. Emits class-aware feedback per the six-field contract (`Line(s):` / `Defect:` / `Class:` / `Sweep query:` / `Required fix:` / `Required generalization:`) per finding. |
| `security-reviewer.md` | default | Security-focused review: secrets, injection, auth, multi-tenant, rate limiting. Emits class-aware feedback per the six-field contract per finding. |
| `test-writer.md` | default | Generates tests for failure modes, not coverage numbers |
| `harness-reviewer.md` | default | Adversarial review of harness rule/hook/agent changes. Default verdict is REJECT. Used before landing any `~/.claude/` modification. Emits class-aware feedback per the six-field contract per defect. |
| `claim-reviewer.md` **(Gen 4)** | default | Adversarial review of draft responses to product Q&A questions. Extracts feature claims and cross-checks against the codebase via `verify-feature` skill. **Self-invoked — residual gap** (Claude Code lacks a PostMessage hook). Emits class-aware feedback per the six-field contract per FAIL reason. |
| `end-user-advocate.md` **(Gen 5, walking-skeleton 2026-04-24)** | default | Adversarial observer of the running product from the end user's perspective. Two modes: plan-time (paper review — reads plan, authors `## Acceptance Scenarios` into the plan file, flags under-specified user behaviors) and runtime (browser automation via `mcp__Claude_in_Chrome__*` with Playwright MCP fallback — executes scenarios against the live app, writes JSON PASS/FAIL artifact under `.claude/state/acceptance/<plan-slug>/` with screenshot + network + console log siblings). Phase A skeleton supports one scenario type ("navigate URL, observe literal text"); production protocol lands in Phase C of `docs/plans/end-user-advocate-acceptance-loop.md`. |

#### Class-aware feedback contract (2026-04-24)

All seven adversarial-review agents (`systems-designer`, `harness-reviewer`, `code-reviewer`, `security-reviewer`, `ux-designer`, `claim-reviewer`, `plan-evidence-reviewer`) share a common per-gap output contract. Every gap, defect, finding, or FAIL reason MUST be reported as a six-field block:

```
- Line(s): <location>
  Defect: <what's wrong here>
  Class: <one-phrase name for the defect class, or "instance-only">
  Sweep query: <grep / structural search to find every sibling instance>
  Required fix: <what to change AT this location>
  Required generalization: <class-level discipline to apply across siblings>
```

The `Class:`, `Sweep query:`, and `Required generalization:` fields are the load-bearing additions. They name the defect *class* — not just the named instance — and give the consuming builder the sweep query upfront so the class is fixed in one pass instead of iterating 5+ times to surface siblings. The escape hatch `Class: instance-only` is allowed when the defect is genuinely unique, but defaults expect a class.

`rules/diagnosis.md` consumes this contract via the "Fix the Class, Not the Instance" sub-rule (under "After Every Failure: Encode the Fix") which instructs the builder to read the `Class:` field, run the `Sweep query:`, fix every sibling in the same commit, and document the sweep with `Class-sweep: <pattern> — N matches, M fixed` in the commit message.

This pattern is **prose-layer only** — it is not hook-enforced. A mechanical backstop (`class-sweep-attestation.sh` pre-commit hook that requires a `Class-sweep:` trailer when commits cite reviewer-finding IDs) is held in the backlog as a P1 reserved for the case where prose alone proves insufficient. Rationale: "prose as guidance, hooks as physics" — start with prose, add hook only if pattern persists.

### UX Testing (3 mandatory after substantial UI builds)
All three are **audience-aware** — they read the target user from `.claude/audience.md` in the project root, or from the project's `CLAUDE.md`, or infer it from the code.

| Agent | Model | Purpose |
|-------|-------|---------|
| `ux-end-user-tester.md` | Sonnet | Generic non-technical user walkthrough (any project) |
| `domain-expert-tester.md` | Sonnet | Becomes the project's target persona as declared in `.claude/audience.md` and tests workflows from their perspective |
| `audience-content-reviewer.md` | Sonnet | Reviews all user-facing text against the project's target audience for wrong-audience language, jargon, empty/placeholder content, and vendor names |
| `ux-designer.md` | default | Pre-build UX review of plans for new UI surfaces. Emits class-aware feedback per the six-field contract per gap. |
| `systems-designer.md` **(Gen 5)** | default | Pre-build systems-engineering review for plans with `Mode: design`. Reviews the 10-section Systems Engineering Analysis (outcome, trace, contracts, environment, auth, observability, FMEA, idempotency, capacity, runbook) for substance. Returns PASS/FAIL with specific gaps. MUST pass before implementation on design-mode plans. Emits class-aware feedback per the six-field contract per gap. |

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
| `planning.md` | Task planning | Strategy-first for substantial features, UX during design, plan files in `docs/plans/`, task-verifier mandate, reusable component rule, session retrospectives, decision tiers. References `orchestrator-pattern.md` for multi-task plan execution. Distinguishes `Mode: code` vs `Mode: design` and points at `design-mode-planning.md` for systems work. Contains "Verbose Plans Are Mandatory" section (2026-04-22) — all plans must enumerate Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy regardless of size; enforced by `plan-reviewer.sh` Check 6b. Contains "Plan File Lifecycle" section (2026-04-23) documenting the four stages (creation → in-progress → archival → lookup) and the "Status is the last edit" convention; enforced by `plan-lifecycle.sh` and supported by `scripts/find-plan-file.sh`. **(Gen 5, 2026-04-24)** contains "Mandatory: end-user-advocate review for every plan (skip via `acceptance-exempt: true`)" sub-section pointing at `acceptance-scenarios.md` for the full plan-time → runtime → gap-analysis loop. |
| `design-mode-planning.md` **(Gen 5)** | System design tasks | The 10-section Systems Engineering Analysis protocol for design-mode plans. When to use design-mode (CI/CD, migrations, infra, multi-service integrations). What each of the 10 sections requires with PASS/FAIL examples. Documents the enforcement chain (template → plan-reviewer → systems-designer agent → systems-design-gate). Escape hatch: `Mode: design-skip` for trivial edits. |
| `orchestrator-pattern.md` **(2026-04-16)** | Multi-task plans | **Pattern-class** (self-applied, not hook-enforced). Main session dispatches build work to `plan-phase-builder` sub-agents instead of building directly. Parallel dispatch is the preferred mode when tasks touch disjoint files — up to 5 concurrent builders in isolated git worktrees via `isolation: "worktree"`. Build-in-parallel, verify-sequentially. See also Patterns section of this doc. |
| `automation-modes.md` **(2026-04-23)** | Choosing where a Claude Code session runs | **Pattern-class** (self-applied). The four-mode decision tree operationalizing Decision 011: Mode 1 (interactive local, full `~/.claude/` enforcement), Mode 2 (parallel local worktrees via Desktop "+ New session" or `isolation: "worktree"`), Mode 3 (`claude --remote` cloud sessions with project `.claude/` enforcement only), Mode 4 (`/schedule` Routines, same inheritance as Mode 3). Per-mode invocation, tradeoffs, enforcement substrate, and concurrency model documented; out-of-scope modes (Dispatch, Managed Agents, DevContainers, self-hosted) explicitly listed for reach-back. Cited from top-of-CLAUDE.md "Choosing a Session Mode" section. |
| `acceptance-scenarios.md` **(Gen 5, 2026-04-24)** | Every plan by default; skipped via `acceptance-exempt: true` | Hybrid (Pattern + Mechanism). Documents the full plan-time → runtime → gap-analysis loop for the `end-user-advocate` agent. Plan-time: advocate authors `## Acceptance Scenarios` into the plan, flags under-specified user behaviors. Runtime: advocate executes scenarios via browser automation against the live app, writes PASS/FAIL JSON artifact to `.claude/state/acceptance/<plan-slug>/`. Stop-hook gate (walking-skeleton in `pre-stop-verifier.sh` Check 0; production lands as `product-acceptance-gate.sh` in Phase D of the parent plan) blocks session end if non-exempt ACTIVE plan lacks PASS artifact. Codifies scenarios-shared / assertions-private discipline (Goodhart prevention). Exemption mechanism: `acceptance-exempt: true` plan-header field with required `acceptance-exempt-reason:` (>= 20 chars) for harness-dev / pure-infrastructure / migration-only plans without UI surface. |
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

### Plan File Lifecycle (2026-04-23)

`planning.md` and the `plan-lifecycle.sh` hook together implement a four-stage lifecycle for every plan file in `docs/plans/`. The mechanisms close gaps that have repeatedly bitten in practice (a downstream-project plan was wiped by a concurrent session before commit; 13 terminal-status plans accumulated in active directory because no mechanism moved them on completion).

1. **Creation.** When a new plan file is written, `plan-lifecycle.sh` (PostToolUse on `Write`) detects the new file and surfaces a loud `[plan-uncommitted-warn]` warning instructing the session to commit immediately. Uncommitted plans are vulnerable to concurrent-session wipeout. The pre-stop-verifier reinforces this with a final session-end warning if the plan is still uncommitted.
2. **In-progress.** Standard mechanics apply: `task-verifier` agent flips checkboxes via the evidence-first protocol enforced by `plan-edit-validator.sh`. No lifecycle-specific hook activity at this stage.
3. **Status transition (atomic archival).** When a plan's `Status:` field transitions from non-terminal to terminal (`COMPLETED`, `DEFERRED`, `ABANDONED`, `SUPERSEDED`), `plan-lifecycle.sh` immediately stages `git mv docs/plans/<slug>.md docs/plans/archive/<slug>.md` (and the `<slug>-evidence.md` companion if present). The status change and file rename land in the same commit. **Status is the last edit:** completion reports, final decisions log entries, and closing notes must be written BEFORE flipping `Status:` because the file moves in the same edit cycle.
4. **Post-archival lookup.** `scripts/find-plan-file.sh` resolves a slug transparently across active and archive directories (active preferred, archive as fallback with stderr provenance note). Hooks (`post-tool-task-verifier-reminder.sh`) and agent prompts (`task-verifier`, `plan-evidence-reviewer`, `ux-designer`) use the helper for archive-aware path resolution.

Recovery from accidental terminal-status writes: `git mv docs/plans/archive/<slug>.md docs/plans/<slug>.md` to restore, then edit `Status:` back. The hook does NOT fire on archive→active transitions (only terminal→archive). The cost of the rare mistake is one `git mv`; the benefit of automatic archival in the common case is eliminating an entire class of "forgot to archive" failures.

Hooks intentionally NOT made archive-aware: `pre-commit-gate.sh`, `backlog-plan-atomicity.sh`, `harness-hygiene-scan.sh`, `plan-edit-validator.sh` — these are scoped to active-work enforcement; archived plans are terminal historical records and archive-aware behavior would break their semantics.

## Templates (`~/.claude/templates/`)

| Template | Used by | Purpose |
|----------|---------|---------|
| `plan-template.md` | `planning.md` | Structure for new plan files. Contains 7 required sections (2026-04-22): Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy — each with placeholder prompts. Validated by `plan-reviewer.sh` Check 6b. **(Gen 5, 2026-04-24)** also includes `## Acceptance Scenarios` and `## Out-of-scope scenarios` between Edge Cases and Testing Strategy (authored by `end-user-advocate` in plan-time mode), and the `acceptance-exempt: true` / `acceptance-exempt-reason:` header fields for plans without product users. |
| `completion-report.md` | `planning.md` | Appended to plan files when all tasks complete |
| `decision-log-entry.md` | `planning.md` | Mid-build decision records |

## Scripts (`~/.claude/scripts/`)

Two classes of scripts live in `~/.claude/scripts/`:

1. **Harness-internal helpers** — invoked by hooks, agents, and Claude sessions. Not copied into projects. They expect to run from a project repo's root directory and operate on its `docs/`, `src/`, etc.
2. **Copy-in testing utilities** — projects install them into their own `tests/` or `scripts/` directory. Framework-agnostic and configurable.

### Harness-internal helpers

| Script | Used by | Purpose |
|--------|---------|---------|
| `find-plan-file.sh` **(2026-04-23)** | `hooks/post-tool-task-verifier-reminder.sh`, agent prompts (`task-verifier`, `plan-evidence-reviewer`, `ux-designer`), Claude sessions doing plan lookup | Archive-aware plan resolver. Given a plan slug (with or without `.md`), resolves in order `docs/plans/<slug>.md` → `docs/plans/archive/<slug>.md` and prints the relative path. Supports glob patterns. Emits a stderr `resolved from archive: <path>` note when the match comes from the archive subdirectory. Exit 0 on match, 1 on no match, 2 on usage error. Has `--self-test` flag exercising resolution-order, glob, and not-found scenarios. |
| `read-local-config.sh` | SessionStart hooks | Safely reads keys from `~/.claude/local/*.json` files with default fallback when the local file is absent. |
| `install-repo-hooks.sh` | One-shot install step | Wires git hooks (e.g., `pre-push-scan.sh`) into the user's global git hook directory. |

### Copy-in testing utilities

| Script | Purpose | Install |
|--------|---------|---------|
| `validate-links.ts` | Dead link validator for Next.js/Remix apps. Walks `href` values in source files and verifies routes exist. | `cp ~/.claude/scripts/validate-links.ts tests/` then add `"test:links": "npx tsx tests/validate-links.ts"` to package.json |
| `audit-consistency.ts` | Code-consistency audit. Flags raw string formatting, unapproved colors, HTML entity arrows, h1 in pages, outline-only buttons, missing loading.tsx, inline fallback chains. Configurable via `.audit-consistency.json`. | `cp ~/.claude/scripts/audit-consistency.ts scripts/` then add `"audit:consistency": "npx tsx scripts/audit-consistency.ts"` to package.json |

Both copy-in scripts exit non-zero on failure and print a structured report. They can be wired into CI or git hooks.

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

## Capture-Codify PR Template (2026-04-23)

Structural enforcement of the capture-codify cycle (every failure is a harness opportunity — encode the prevention) at PR-merge time. Every PR must answer "what mechanism would have caught this?" via one of three answer forms (existing catalog entry, new entry proposed, accepted residual risk with rationale). CI blocks the PR if the field is missing or trivially filled. Implements the discipline previously documented only in `rules/diagnosis.md` "After Every Failure: Encode the Fix."

| Artifact | Path | Purpose |
|----------|------|---------|
| PR template | `.github/PULL_REQUEST_TEMPLATE.md` | Auto-populates the PR body on `gh pr create` / GitHub UI with four required sections (Summary, What changed and why, **What mechanism would have caught this?**, Testing performed). The mechanism section has three answer-form sub-headings (`### a) Existing catalog entry`, `### b) New catalog entry proposed`, `### c) No mechanism — accepted residual risk`). Bracketed placeholder text uses `<mechanism answer — replace this bracketed text>` so the validator can detect un-filled submissions. |
| CI workflow | `.github/workflows/pr-template-check.yml` | Workflow `name: PR Template Check`, single job ID `validate`. Triggers on `pull_request` events `[opened, edited, synchronize, reopened]`. Declares `permissions: {}` (reads `${{ github.event.pull_request.body }}` from event context, no API calls). Sources the validator library and emits the auto-check `PR Template Check / validate`. Required by branch protection on master so the field cannot be skipped. |
| Local pre-push hook | `adapters/claude-code/git-hooks/pre-push-pr-template.sh` | Opt-in per-repo hook (installed by the rollout script, not globally). Reads `.pr-description.md` if present (preferred — write PR body locally, then `gh pr create --body-file .pr-description.md`), otherwise `git log -1 --format=%B`. Auto-skips WIP branches (`wip-*`, `*scratch*`). Same canonical stderr messages as CI (sourced from the shared validator library). |
| Validator library | `.github/scripts/validate-pr-template.sh` | Bash 3.2+ shared library defining `find_section_heading()`, `extract_section_content()`, `detect_placeholder()`, `detect_answer_form()`, `validate_rationale_length()`, `emit_failure_message()`. Sourced by both the workflow's `run:` step (after `actions/checkout@v4`) and the local pre-push hook. Single source of truth for regex patterns + canonical messages — eliminates CI/local drift. Has `--self-test` flag exercising 6 cases. Lives at `.github/scripts/` (not under `adapters/claude-code/`) per Decision 7 of the capture-codify-pr-template plan, so the rollout script trivially copies `.github/` to downstream repos with no path rewriting. |

The convention is documented in `rules/planning.md` "Capture-codify at PR time" section. The companion `docs/failure-modes.md` catalog (FM-NNN entries) is referenced by answer form (a). See plan `docs/plans/archive/capture-codify-pr-template.md` (or active path during build) for the full systems-engineering analysis.

## Plugin System

6 plugins enabled in settings.json:
- `claude-md-management` — manages CLAUDE.md files
- `claude-code-setup` — initial setup assistance
- `code-review` — code review integration
- `explanatory-output-style` — educational insights with ★ markers
- `frontend-design` — frontend design assistance
- `security-guidance` — security best practices
