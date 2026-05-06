# Claude Code Harness — Architecture Overview
Last updated: 2026-05-04 (Discovery resolutions for sed-status-flip bypass + template-vs-live divergence + worktree-base-at-master: two new SessionStart hooks shipped — `plan-status-archival-sweep.sh` (safety-net for terminal-Status flips that bypass `plan-lifecycle.sh` because PostToolUse Edit/Write doesn't fire on Bash) and `settings-divergence-detector.sh` (surfaces hook-entry-count divergence between live `~/.claude/settings.json` and committed `settings.json.template`); `rules/orchestrator-pattern.md` extended with empirically-verified option Q (`git checkout -b worker-<id> <feature-branch>` as builder's mandatory first action inside worktree) preserving parallelism without push-before-dispatch; `.gitignore` broadened to include `.claude/state/` and `.claude/worktrees/`; HARNESS-GAP-14 logged for deferred Phase 1d-E reconciliation of the 5 pre-existing template-vs-live divergent hooks (orchestrator-driven research methodology, not user-judgment-cold). Earlier 2026-05-04 (Scope-enforcement-gate second-pass redesign per D1 deep-dive: waiver path removed entirely; replaced with 'open a new plan' as option 2 (covers hotfixes, drive-by fixes, pre-existing-untracked files); system-managed-path allowlist added for `docs/plans/archive/*` (plan-lifecycle.sh archival operations exempt). Three structural options now cover all legitimate use cases; `git commit --no-verify` remains the canonical emergency override. Earlier 2026-05-04 (Scope-enforcement-gate redesign per D1 reframe: gate now reads `## In-flight scope updates` section in plan files alongside `## Files to Modify/Create`; block-message restructured to three tiered options surfacing update-the-plan as the structurally-correct first answer rather than waiver-as-default. Plans become living artifacts; waivers become rare-and-meaningful. Earlier 2026-05-03 (Discovery Protocol — proactive capture+surface+decide-and-apply mechanism for mid-process realizations: new `~/.claude/rules/discovery-protocol.md` documenting the protocol; `bug-persistence-gate.sh` extended to accept `docs/discoveries/YYYY-MM-DD-*.md` as legitimate persistence alongside backlog/reviews; new `discovery-surfacer.sh` SessionStart hook surfaces pending discoveries; six initial-population discovery files capture this session's surfaced architectural-learnings and process-discoveries; reversible decisions auto-applied per user directive; irreversible decisions still pause-and-wait; conclusion-of-work summary lists auto-applied decisions for retrospective review. Earlier 2026-05-03 (Agent Incentive Map — proactive shift from reactive failure-correction: new `docs/agent-incentive-map.md` cataloging 17 NL agents' stated goals, latent training incentives, predicted stray-from patterns, current mitigations, residual gaps, and detection signals; `## Counter-Incentive Discipline` sections added to four highest-leverage agent prompts (task-verifier, code-reviewer, plan-phase-builder, end-user-advocate) priming each against its own training-induced bias; HARNESS-GAP-11 logged for the unaddressed reviewer-accountability one-way structural weakness. Earlier 2026-05-03: Phase 1d-C-1 of Build Doctrine + NL integration: three new first-pass C-mechanisms — `scope-enforcement-gate.sh` (PreToolUse Bash on `git commit`; blocks commits where staged files fall outside active plan's `## Files to Modify/Create` section; supports glob patterns, multiple-active-plan intersection, 1-hour-window per-plan waiver at `.claude/state/scope-waiver-<slug>-*.txt`; 8-scenario `--self-test`), `dag-review-waiver-gate.sh` (PreToolUse Task; gates first Task invocation in session for Tier 3+ active plans; requires substantive >=40-char waiver at `.claude/state/dag-approved-<slug>-*.txt`; per-session marker after first allow; 7-scenario `--self-test`), and `plan-reviewer.sh` Check 9 — quantitative-claims arithmetic check (mode-gated to `Mode: design`; detects comparative phrases and self-contradicting hedges; requires inline arithmetic per FM-013/FM-014; 4 new self-test scenarios added). Wiring lands in `settings.json.template` (2 new entries) and `vaporware-prevention.md` (3 enforcement-map rows). Earlier 2026-04-28 (Agent Teams integration per Decision 012 / `docs/decisions/012-agent-teams-integration.md` and `docs/plans/agent-teams-integration.md`: three new hooks — `teammate-spawn-validator.sh` (PreToolUse `Task|Agent`), `task-created-validator.sh` (TaskCreated event), `task-completed-evidence-gate.sh` (TaskCompleted event); team-aware extensions to `tool-call-budget.sh` (per-team counter + deferred-audit cadence + 90-call hard ceiling), `plan-edit-validator.sh` (flock concurrent-write protection), `product-acceptance-gate.sh` (multi-worktree artifact aggregation); new rule `agent-teams.md`; `automation-modes.md` extended to 5 modes; Stop chain documented at 5+ positions per HARNESS-DRIFT-03. Earlier 2026-04-26: Gen 6 adversarial-validation extensions: A2 — `pre-stop-verifier.sh` Check 5 / A2 extension verifies declared `## DoD Artifacts` against on-disk files at COMPLETED time; supports `requires_field`/`requires_value` (jq), `requires_pattern` (ERE), `requires_min_length` (bytes), and `<runId>` glob expansion; 3-fixture `--self-test` flag; plan-template introduces an optional `## DoD Artifacts` section. Earlier 2026-04-24: Gen 5 production runtime acceptance gate: new `product-acceptance-gate.sh` Stop hook (position 4 — chained AFTER pre-stop-verifier + bug-persistence + narrate-and-wait, BEFORE the Gen 6 narrative-integrity hooks at positions 5-8) blocks session end when ACTIVE plans lack PASS runtime acceptance artifacts at `.claude/state/acceptance/<slug>/*.json` with matching `plan_commit_sha`; honors `acceptance-exempt: true` + reason; per-session waiver mechanism mirrors bug-persistence pattern; 8-scenario `--self-test`. Earlier 2026-04-24: Gen 5 walking skeleton — new `end-user-advocate` agent for plan-time + runtime adversarial product observation; `pre-stop-verifier.sh` Check 0 recognizes `acceptance-exempt: true` plan-header field and emits `[acceptance-gate]` log lines. Earlier 2026-04-24: class-aware reviewer feedback — 7 adversarial-review agents emit per-gap six-field blocks with `Class:` + `Sweep query:` + `Required generalization:`; `rules/diagnosis.md` adds the "Fix the Class, Not the Instance" sub-rule consuming this contract)

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
| `plan-edit-validator.sh` | Plan checkbox flips require fresh matching evidence file AND Runtime verification entry. **(Agent Teams plan task 9, 2026-04-28)** Extended with `flock`-based concurrent-write protection: the evidence-mtime check + plan-edit allow-decision is wrapped in `flock` on `<plan>.lock` with a 30s timeout. Two parallel verifiers (e.g., team teammates each invoking `task-verifier` against the shared plan file) acquire the lock serially, eliminating the race where overlapping edits could corrupt the plan file or interleave evidence appends. PID-keyed lock-file fallback when `flock(1)` is unavailable (Windows Git Bash without msys2 flock). 4 new scenarios in `--self-test`. | Mechanical (PreToolUse) |
| `outcome-evidence-gate.sh` **(Gen 5)** | Fix tasks (matching fix/bug/broken/etc.) require before/after reproduction evidence — same runtime verification command showing FAIL pre-fix and PASS post-fix. Escape hatch for cases where automated before-state can't be captured: a "Reproduction recipe" block documenting manual repro | Mechanical (PreToolUse) |
| `systems-design-gate.sh` **(Gen 5)** | Edits to design-mode files (CI/CD workflows, migrations, vercel.json, Dockerfile, etc.) require an active plan with `Mode: design` in `docs/plans/`. Escape hatch: `Mode: design-skip` for trivial edits (version bumps, typos) with a short written justification. Forces systems-engineering thinking before implementation | Mechanical (PreToolUse) |
| `runtime-verification-executor.sh` | "Runtime verification:" lines must parse as `test`/`playwright`/`curl`/`sql`/`file` and actually execute; `test`/`playwright` entries reject files containing unannotated runtime-conditional skips (silent-skip vaporware guard, 2026-04-15) | Mechanical (Stop hook) |
| `runtime-verification-reviewer.sh` | Verification commands must correspond to modified files (curl URL, sql table, test imports). Excludes archived plans (`docs/plans/archive/**`) from modified-file analysis (2026-04-23) | Mechanical (Stop hook) |
| `plan-reviewer.sh` | Plans must have Scope, DoD, decomposed sweep tasks, Runtime verification specs, and all 7 required sections populated (Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy — Check 6b, 2026-04-22) | Mechanical (pre-commit) |
| `effort-policy-warn.sh` **(2026-04-22)** | SessionStart warning when configured effort level is below the project-level (`.claude/effort-policy.json`) or user-level (`~/.claude/local/effort-policy.json`) declared minimum. Ordering: `low < medium < high < xhigh <= max`. Non-blocking. | Mechanical (SessionStart, warn-only) |
| `tool-call-budget.sh` | Every 30 tool calls blocks until plan-evidence-reviewer is invoked. **(Agent Teams plan task 6, 2026-04-28)** Extended with team-aware mode + deferred-audit cadence: when the firing session is a member of `~/.claude/teams/<team>/config.json`, the counter is keyed by `team_name` instead of `session_id` (per-team cumulative work, not per-teammate-multiplied). At counter == 30 in agent-team mode, the hook writes a flag file at `~/.claude/state/audit-pending.<team>` and ALLOWS the call (deferred audit) — the flag is consumed by `task-completed-evidence-gate.sh` at the next TaskCompleted event. Hard ceiling at 90: a per-teammate sub-counter at `~/.claude/state/tool-call-since-task.<session_id>` blocks mid-stream when a single teammate accumulates 90+ calls without an intervening TaskCompleted (catches runaway-task drift). Solo sessions (no team) retain the 30-call mid-stream block — backward-compatible. 14-scenario `--self-test`. | Mechanical (PreToolUse) |
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
| `product-acceptance-gate.sh` **(Gen 5, 2026-04-24)** | Stop hook (position 4 — chained AFTER pre-stop-verifier + bug-persistence + narrate-and-wait). Walks every ACTIVE plan in `docs/plans/` and blocks session end unless each has either: (a) `acceptance-exempt: true` plan-header field with a substantive `acceptance-exempt-reason:` (>= 20 chars), (b) a per-session waiver at `.claude/state/acceptance-waiver-<slug>-<ts>.txt` younger than 1 hour, or (c) a runtime acceptance JSON artifact at `.claude/state/acceptance/<slug>/*.json` whose `plan_commit_sha` matches the plan file's current git SHA AND whose scenarios are all `verdict: "PASS"`. Production runtime gate for the end-user-advocate loop (Phase D of `docs/plans/end-user-advocate-acceptance-loop.md`). **(Agent Teams plan task 10, 2026-04-28)** Extended with multi-worktree artifact discovery: enumerates all worktrees of the current repo via `git worktree list --porcelain` and aggregates `.claude/state/acceptance/<plan-slug>/` artifacts found within each worktree's state dir. A scenario PASS in *any* worktree's state directory satisfies the gate, provided `plan_commit_sha` matches. Closes the Agent Teams gap where teammates write runtime PASS artifacts in their own worktree that the lead's gate would otherwise never observe. Degrades gracefully to cwd-only artifact discovery when `git worktree list` is unavailable. 10-scenario `--self-test` (8 original + 2 multi-worktree aggregation: aggregates-across-worktrees, returns-PASS-when-any-worktree-has-valid-artifact). | Mechanical (Stop hook) |
| `deferral-counter.sh` **(A5 — Gen 6, 2026-04-26)** | Stop hook (position 5; chained AFTER product-acceptance-gate, BEFORE transcript-lie-detector / imperative-evidence-linker / goal-coverage-on-stop). Reads `$TRANSCRIPT_PATH` (Claude Code's JSONL session log, which the agent cannot edit) and pattern-matches a comprehensive synonym list of deferral phrases (`deferred`, `follow-up`, `PHASE\d+-FOLLOWUP`, `for now`, `stub`, `scaffold`, `mocked`, `simulated`, `walking-skeleton`, `DO NOT run`, `out of scope for this`, `awaiting user`, `requires user`, `pending approval`, plus ~40 more). If session has matches AND the agent's last assistant message lacks `## Deferrals not executed in this session` heading with at least one bullet, blocks session end with the verbatim list in stderr — forcing the deferrals into the user-visible final message rather than buried mid-session text. The user only reliably reads end-of-effort summaries; this hook makes deferrals impossible to hide there. Origin: 2026-04-26 incident where the agent marked a plan COMPLETED while writing "deferred to user" / "PHASE6-FOLLOWUP-01" / "first run is user-driven decision" three times in PR bodies and SCRATCHPAD — none appeared in the user-facing summary. Self-tested against the live session: 92 deferral phrases matched. Escape hatch: `DEFERRAL_COUNTER_DISABLE=1` for harness-development sessions where editing the synonym list itself would self-trigger. | Mechanical (Stop hook) |
| `transcript-lie-detector.sh` **(A3 — Gen 6, 2026-04-26)** | Stop hook (position 6 — chained AFTER deferral-counter). Reads `$TRANSCRIPT_PATH` JSONL (which the agent cannot edit) and detects **self-contradiction within session**: pairs of agent text where one event class asserts completion (`Plan COMPLETED`, `Status: COMPLETED`, `all phases done`, `tests pass`, `shipped`, `verified working`, `feature is done`, `phase \d+ done`, plus ~10 more) while another event class admits deferral (`deferred to user`, `PHASE\d+-FOLLOWUP`, `A\d+-FOLLOWUP`, `first run is user-driven`, `user-driven decision`, `awaiting user`, `requires user (approval\|authorization)`, `not yet executed`, `couldn't verify`, `test failed`, `unable to verify`, `pending approval`, `did not (run\|execute)`, plus ~10 more). When both classes appear in the same session, blocks session end UNLESS the agent's last assistant message contains the heading `## Resolved contradictions in this session` with at least one bullet — forcing the contradictions to be reconciled (flip Status back to ACTIVE, surface the deferrals) or explicitly addressed in the user-visible final message. Origin: 2026-04-26 incident where the agent flipped a plan to COMPLETED while the same session's transcript contained multiple deferral-class claims; A5 catches the deferrals individually but not the contradiction with a sibling COMPLETED claim. v1 implements only the self-contradiction class; broken-promise (A3-FOLLOWUP-01) and skipped-imperative (A3-FOLLOWUP-02) are filed for v2. Self-tested via `--self-test` flag against three fixtures (self-contradiction blocks, clean allows, resolved allows) and live-validated against the originating session JSONL (caught 277 completion-class + 33 deferral-class claims; >= 33 contradiction pairs). Escape hatch: `TRANSCRIPT_LIE_DETECTOR_DISABLE=1` for harness-development sessions where editing the pattern lists self-triggers. | Mechanical (Stop hook) |
| `imperative-evidence-linker.sh` **(A7 — Gen 6, 2026-04-26)** | Stop hook (position 7 — chained AFTER transcript-lie-detector). Reads `$TRANSCRIPT_PATH` JSONL (which the agent cannot edit), extracts the user's last K substantive messages (default K=30, override `IMPERATIVE_LINKER_WINDOW`), and links each strong imperative (clauses containing `must`, `need to`, `required to`, `have to`, `please`, `go ahead and`, `make sure to`, `should`) to specific tool-call evidence in the same session. Pattern library at `adapters/claude-code/data/imperative-patterns.json` declares 12 seed patterns mapping `(verb, object_pattern)` to an `evidence` regex applied against a flat `<ToolName>:<input-summary>` ledger built from the transcript's `tool_use` events (e.g., `run` + `tests` -> `Bash:(npm test\|vitest\|jest\|playwright\|pytest\|...)`). When a triggered imperative has no matching tool-call event, it's recorded as a SKIPPED IMPERATIVE — the user explicitly asked, the agent never even tried. Blocks session end UNLESS the last assistant message contains the heading `## User-imperative coverage` with at least one bullet, forcing each gap into the user-visible final message. Closes the gap A3 left open: A3 catches the agent contradicting itself (says "done" while writing "not done"); A7 catches the agent silently skipping a user directive entirely. Self-tested via `--self-test` flag against three fixtures (run-tests-no-evidence blocks, run-tests-with-evidence allows, with-coverage-section allows) and live-validated against the originating session JSONL (caught the dispatch-prompt's "must run the tests" imperative). Escape hatch: `IMPERATIVE_LINKER_DISABLE=1` for harness-development sessions where editing the pattern library self-triggers. | Mechanical (Stop hook) |
| `vaporware-volume-gate.sh` **(A8 — Gen 6, 2026-04-26)** | PreToolUse hook on `Bash` matching `gh pr create`. Reads cumulative branch state via `git diff origin/master...HEAD --numstat` and computes (a) lines added to behavior-DESCRIBING files (`.md`, `.yml`, `.yaml`, `.json`, `.sh`, `.ts`, `.tsx`, `.js`, `.jsx`, plus paths under `docs/`, `.github/workflows/`, `scripts/`, `hooks/`) vs. (b) count of behavior-EXECUTING artifact files (`*.log`, screenshots, `*.har`, `junit*.xml`, `test-results*.json`, `*-evidence.{md,json}`, `*-trace.{json,txt}`, paths under `*/loop-history/`, `*/test-results/`, `*/logs/`, `*/screenshots/`, `*/artifacts/`, `*/coverage/`, `*/evidence/`). If describes-lines > 200 AND executes-files == 0, blocks the PR creation with a stderr message listing the offending files and the bypass instructions. Escape hatch: PR title prefix `[docs-only]` or `[no-execution]` skips the check (the prefix becomes part of the permanent PR title and is auditable). 3-fixture `--self-test` flag covering the vaporware shape, a real-feature PR with execution evidence, and the docs-only-with-prefix bypass. Origin: 2026-04-26 incident — agent shipped PR #123 with 800 lines of docs + 174 lines of CI YAML and ZERO execution evidence while the plan's own DoD said "Loop converges on master" was unchecked. The describes-vs-executes volume ratio is the canonical shape that should have caught it; this gate now does. | Mechanical (PreToolUse) |
| `task-created-validator.sh` **(Agent Teams plan task 7, 2026-04-28)** | TaskCreated event hook (new top-level event matcher in `settings.json.template`, fires per Anthropic Agent Teams `TaskCreated` events). Validates that newly-created teammate tasks have substantive subjects and reference an active plan with acceptance criteria, before allowing the task to be dispatched. Three rejection conditions: (a) `task_subject` shorter than 10 non-whitespace chars OR a generic single word (`TODO`, `fix`, `bug`, `WIP`, `TBD`, `stuff`, etc.); (b) `task_description` doesn't reference any active plan slug under `docs/plans/*.md` (top-level only) — skipped (allow) when no ACTIVE plans exist for the team-init case; (c) `task_description` doesn't reference acceptance criteria or a `Done when:` clause. Defaults to ALLOW when ambiguous: missing event input, missing `team_name` (treated as solo session, not a team task), no active plans found. Bypass paths: `TASK_CREATED_BYPASS=1` env or `bypass_validation: true` event field. Block emits structured stderr + `{"continue": false, "stopReason": "..."}` JSON on stdout. 4-scenario `--self-test` flag covering valid spawn, too-short subject, missing plan reference, generic-word subject. | Mechanical (TaskCreated event) |
| `task-completed-evidence-gate.sh` **(Agent Teams plan task 8, 2026-04-28)** | TaskCompleted event hook (new top-level event matcher). Two layered enforcement modes: (1) **Evidence enforcement** — verifies an evidence block matching `task_id` exists in either `<plan>-evidence.md` companion file or the plan's inline `## Evidence Log` section. Block if missing. Recognizes `Task ID: <id>`, `Task: <id>`, or `## Task <id>` framings (case-insensitive). (2) **Deferred-audit enforcement** — checks for `~/.claude/state/audit-pending.<team_name>` flag (set by `tool-call-budget.sh` at counter==30 in agent-team mode per plan task 6). When the flag exists, BLOCKS task completion until a fresh `plan-evidence-reviewer` review file appears at `~/.claude/state/reviews/<timestamp>.md` with `REVIEW COMPLETE` + `VERDICT: PASS` (mirrors the tool-call-budget `--ack` mechanism convention). PASS clears the flag and allows; FAIL keeps the flag and blocks. Hook does NOT directly invoke sub-agents (HARNESS-GAP — sub-agents cannot be spawned from hook scripts); instead surfaces actionable stderr instructing the user to invoke `plan-evidence-reviewer` manually. **Coordination with task 6:** also unconditionally resets the per-teammate sub-counter at `~/.claude/state/tool-call-since-task.<session_id>` on every TaskCompleted event so the per-teammate budget restarts at 0. Defaults to ALLOW when ambiguous: missing input, missing `task_id` (graceful warning), no `team_name` (solo session — skip team-aware logic), no active plans (team-init case). Bypass paths: `TASK_COMPLETED_BYPASS=1` env or `bypass_evidence_check: true` event field; bypass usage logged to `~/.claude/state/task-completed-bypass.log` for audit. 6-scenario `--self-test` flag covering reject-missing-evidence, allow-evidence-present, allow-explicit-bypass, handle-missing-task-id-gracefully, flag-set-with-PASS-clears-flag, flag-set-without-PASS-blocks. | Mechanical (TaskCompleted event) |
| `teammate-spawn-validator.sh` **(Agent Teams plan task 5, 2026-04-27)** | PreToolUse hook on `Task\|Agent` matcher. Reads `~/.claude/local/agent-teams.config.json` (the feature-flag file introduced by Task 4 of `docs/plans/agent-teams-integration.md`) and rejects unsafe teammate-spawn configurations. Three rejection conditions: (a) `enabled: false` AND tool input has `team_name` set — Agent Teams disabled, tells user how to enable; (b) `worktree_mandatory_for_write: true` AND spawn lacks `isolation: "worktree"` AND spawned `subagent_type` is not in the read-only allowlist (research, explorer, task-verifier, code reviewers, advocates, etc.) — filesystem-race risk, requires worktree isolation; (c) `force_in_process: true` AND lead session is in `--dangerously-skip-permissions` (detected via `CLAUDE_PERMISSION_MODE` env or `~/.claude/settings.json` defaultMode) — permission-bypass propagates to in-process teammates. Defaults to ALLOW when ambiguous: missing config file, missing tool_name, unrecognized fields all pass through. Origin: Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) is an experimental Anthropic feature with five known upstream bugs (#50779, #24175, #24073, #24307, #45329); enabling it without harness gates would silently degrade enforcement. 6-scenario `--self-test` flag covering non-Agent tool, missing config, each rejection condition, and the fully-specified spawn that should pass. | Mechanical (PreToolUse) |
| `goal-extraction-on-prompt.sh` + `goal-coverage-on-stop.sh` **(A1 — Gen 6, 2026-04-26)** | Two-hook pair anchoring goal extraction at the highest-signal moment in a session: the user's verbatim FIRST message. **`goal-extraction-on-prompt.sh`** is a UserPromptSubmit hook that fires on every user prompt; if `.claude/state/user-goals/<session-id>.json` already exists it exits as a no-op (this isn't the first message), otherwise it deterministically extracts imperative verbs (`test\|run\|fix\|build\|implement\|deploy\|verify\|check\|validate\|loop\|iterate\|find\|review\|ship\|merge\|continue`) at word boundaries with ~30 chars of trailing object context, computes SHA-256 of the verbatim prompt, and writes `{session_id, first_message_text_sha256, extracted_at, goals: [{verb, context, raw_clause}]}` to the goal file. **`goal-coverage-on-stop.sh`** is a Stop hook (position 8 — chained AFTER imperative-evidence-linker) that re-derives the SHA from the JSONL transcript's first user message and BLOCKS with a tamper-detected message on mismatch — the agent cannot edit the user's first message in `$TRANSCRIPT_PATH`, so any divergence proves the goal file was modified after creation. When the SHA matches, the hook walks each goal's verb-evidence regex against a flat `<ToolName>:<input-summary>` tool-call ledger built from the transcript (parallel to A7's mechanism but keyed on A1's verb list, e.g., `test` -> `Bash:(npm test\|vitest\|jest\|playwright\|...)`, `loop` -> `Bash:(test:e2e:loop\|while\|for i)`); for any unmet goal, the hook BLOCKS unless the agent's last assistant message contains `## User-goal coverage` with at least one bullet line, forcing each gap into the user-visible final message. Closes the gap left by A5/A3/A7: those read agent narrative or strong-imperative clauses; A1 anchors on the literal first-message-of-session that the agent cannot rewrite. Self-tested via `--self-test` flag against six fixtures (extraction-produces-expected-goals, second-invocation-is-noop, stop-no-evidence-blocks, stop-with-evidence-allows, stop-tampered-sha-blocks, stop-with-coverage-section-allows). Live-tested against a synthetic dispatch prompt and extracted 8 goals correctly. Escape hatch: `GOAL_EXTRACTION_DISABLE=1` for both hooks (harness-dev sessions where editing the verb list itself self-triggers). | Mechanical (UserPromptSubmit + Stop hook) |

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

### SessionStart (2 matcher entries; multiple hooks per matcher)

**Compact recovery** (matcher: `"compact"`):
- Checks SCRATCHPAD.md date against today — warns if stale or missing
- Checks `docs/backlog.md` date — warns if stale
- Checks most recent plan in `docs/plans/` — warns if active with unchecked tasks
- Instructs: read SCRATCHPAD → plan → backlog before doing anything

**Default-matcher hook chain** (matcher: `""`):
- **Account switcher** — detects the current directory against configured account `dir_triggers` in `~/.claude/local/accounts.config.json` and switches GitHub + Supabase accounts accordingly
- **Pipeline detector** — checks for `orchestrate.sh` or `evidence.md` → reports pipeline status
- **`effort-policy-warn.sh`** — warns when configured effort level is below the project-level / user-level declared minimum (non-blocking)
- **`discovery-surfacer.sh`** (2026-05-03) — scans `docs/discoveries/*.md` for files at `Status: pending` and surfaces them so pending decisions are seen before further work begins. Silent when no pending discoveries exist.
- **`plan-status-archival-sweep.sh`** (2026-05-04) — scans `docs/plans/*.md` (top-level only) for plans whose `Status:` is at a terminal value (COMPLETED / DEFERRED / ABANDONED / SUPERSEDED) and `git mv`s each (plus sibling `<slug>-evidence.md`) into `docs/plans/archive/`. Safety-net for the case where Status is flipped via Bash `sed` (which doesn't fire `plan-lifecycle.sh` PostToolUse Edit/Write events). Has `--self-test` flag exercising 5 scenarios.
- **`settings-divergence-detector.sh`** (2026-05-04) — diffs `~/.claude/settings.json` (gitignored live config) against `$HOME/claude-projects/neural-lace/adapters/claude-code/settings.json.template` (committed source-of-truth for `install.sh`). Surfaces hook-entry-count divergence per event type. Silent when both files are byte-identical or one is absent. Surfaces the worklist for HARNESS-GAP-14 (deferred reconciliation pass). Has `--self-test` flag exercising 4 scenarios.
- **`spawned-task-result-surfacer.sh`** (2026-05-05) — scans `.claude/state/spawned-task-results/*.json` for unread results (those without sibling `.json.acked`) and surfaces them as a system-reminder block listing task_id, summary, branch, commits, ended_at, file path. Mirrors `discovery-surfacer.sh` shape (silent-when-empty, exit-0-always). Skips malformed JSON files with a stderr warning. Has `--self-test` flag exercising 5 scenarios. Part of HARNESS-GAP-08 (spawn-task report-back protocol).

### PreToolUse (12 entries)

| Hook | Matcher | What it blocks / does |
|------|---------|----------------------|
| Sensitive file blocker | `Edit\|Write` | `.env`, `credentials.json`, `secrets.yaml` |
| Lock file blocker | `Edit\|Write` | `package-lock.json`, `bun.lock`, `yarn.lock`, `pnpm-lock.yaml` |
| **PRD-validity gate (Phase 1d-C-2 / C1, 2026-05-04)** | `Write` | On `Write` of a `docs/plans/<slug>.md` file: reads the plan's `prd-ref:` header field; if not the harness-dev carve-out (`n/a — harness-development`), resolves to `docs/prd.md` and verifies all 7 required sections (Problem, Scenarios, Functional, Non-functional, Success metrics, Out-of-scope, Open questions) are present with ≥ 30 non-whitespace chars each. Blocks plan creation on missing/incomplete PRD. Pass-through on non-plan-file Write calls. Wired BEFORE `plan-edit-validator.sh` so PRD-validity is checked at plan-creation time before evidence-first protocol applies. |
| **Plan-edit validator (Gen 4)** | `Edit\|Write` | Blocks casual `[ ]`→`[x]` flips on `docs/plans/*.md`. Requires fresh evidence file with matching Task ID + Runtime verification entry (evidence-first authorization). Also blocks `Status: ACTIVE`→`COMPLETED` without an evidence file. (Agent Teams plan task 9: extended with `flock` concurrent-write protection on `<plan>.lock`, 30s timeout.) |
| **Spec-freeze gate (Phase 1d-C-2 / C2, 2026-05-04)** | `Edit\|Write\|MultiEdit` | Iterates every top-level `docs/plans/*.md` with `Status: ACTIVE`; for each, parses `## Files to Modify/Create` into a path list. If the target file is declared in any active plan whose header has `frozen: false` (or missing `frozen:`), BLOCKS with a message naming the unfrozen plan(s) and the freeze-or-remove options. Self-bypasses on `docs/plans/.*\.md` paths so plans can edit themselves. Wired AFTER `plan-edit-validator.sh` (so plan-file edits flow through plan-edit-validator first) and BEFORE `tool-call-budget.sh`. Degrades gracefully on plan-parse errors. |
| **Tool-call budget (Gen 4)** | `.*` | After 30 tool calls since last `--ack`, blocks further tool calls until plan-evidence-reviewer is invoked and `tool-call-budget.sh --ack` is run. Mitigates attention decay in long sessions. (Agent Teams plan task 6: counter is per-team in agent-team mode; deferred-audit cadence sets a flag at counter==30 instead of mid-stream block; per-teammate sub-counter blocks at 90 as hard ceiling.) |
| **Teammate-spawn validator (Agent Teams plan task 5)** | `Task\|Agent` | Reads `~/.claude/local/agent-teams.config.json` and rejects: (a) `enabled: false` AND `team_name` set; (b) `worktree_mandatory_for_write: true` AND spawn lacks `isolation: "worktree"` for write-capable teammates; (c) `force_in_process: true` AND lead is in `--dangerously-skip-permissions`. Defaults to ALLOW when ambiguous. |
| Dangerous command blocker | `Bash` | `curl\|sh`, `chmod -R 777`, `mkfs.`, `dd if=` |
| Force-push / --no-verify blocker | `Bash` | `git push --force`, `--no-verify` |
| Public repo blocker | `Bash` | `gh repo create --public`, `gh repo edit --visibility public` |
| Pre-commit gate | `Bash` | On `git commit`: runs `check-harness-sync.sh` + `pre-commit-gate.sh` (TDD gate + plan-reviewer + tests + build + API audit) |
| **Findings-ledger schema gate (Phase 1d-C-3 / C9, 2026-05-04)** | `Bash` | Self-detects `git commit` (allows other Bash invocations). When the commit stages `docs/findings.md`, parses every entry and validates the locked six-field schema (ID + Severity / Scope / Source / Location / Status enum-locked, plus non-empty Description body); BLOCKs with stderr message naming the failing entry + reason on any violation. No-op when `docs/findings.md` is not staged. Wired AFTER `plan-deletion-protection.sh` and BEFORE `vaporware-volume-gate.sh` in both `settings.json.template` and `~/.claude/settings.json`. Hook script: `~/.claude/hooks/findings-ledger-schema-gate.sh` (mirror of the committed `adapters/claude-code/hooks/findings-ledger-schema-gate.sh`). |
| Account switcher | `Bash` | On `git push`: switches `gh auth` to the account matching the remote URL per `~/.claude/local/accounts.config.json` |

### PostToolUse (1 entry — Gen 4)

| Hook | Matcher | Purpose |
|------|---------|---------|
| Task-verifier reminder | `Edit\|Write` | After editing a `src/` file that matches an unchecked task in the active plan, prints a persistent stderr reminder to invoke task-verifier before continuing. Cannot block (PostToolUse is advisory). |

### TaskCreated (1 entry — Agent Teams plan task 7, 2026-04-28)

New top-level event matcher introduced by the Agent Teams integration. Fires when a teammate task is created via `TaskCreate` in `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` sessions.

| Hook | Matcher | Purpose |
|------|---------|---------|
| Task-created validator | (event) | Validates task subjects (>= 10 non-whitespace chars, not generic words like TODO/fix/WIP), requires plan reference + acceptance criteria in `task_description`. Defaults to ALLOW when ambiguous (missing event input, no `team_name`, no active plans). Bypass: `TASK_CREATED_BYPASS=1` or `bypass_validation: true` event field. |

### TaskCompleted (1 entry — Agent Teams plan task 8, 2026-04-28)

New top-level event matcher introduced by the Agent Teams integration. Fires when a teammate task is marked complete.

| Hook | Matcher | Purpose |
|------|---------|---------|
| Task-completed evidence gate | (event) | Two layered modes: (1) evidence enforcement — requires an evidence block matching `task_id` in `<plan>-evidence.md` or the plan's inline `## Evidence Log`; (2) deferred-audit enforcement — when `~/.claude/state/audit-pending.<team>` exists (set by team-aware `tool-call-budget.sh` at counter==30), blocks completion until a fresh `plan-evidence-reviewer` PASS appears at `~/.claude/state/reviews/<ts>.md`. Also resets the per-teammate sub-counter at `~/.claude/state/tool-call-since-task.<session_id>` on every TaskCompleted. Bypass: `TASK_COMPLETED_BYPASS=1` or `bypass_evidence_check: true` event field. |

### UserPromptSubmit (1 entry)
Sets terminal window title to `basename $PWD` (cosmetic).

### Notification (1 entry)
System beep (`\a`) on any notification.

### Stop (8 entries — chained in order)

The Stop chain has grown across Gen 4 / Gen 5 / Gen 6. Each hook gates session end on a different concern; if any blocks, the session cannot end until the issue is addressed (or a documented bypass is used). Order of evaluation:

1. **`pre-stop-verifier.sh`** (plan-integrity) — finds most recent ACTIVE/COMPLETED plan in `docs/plans/` (excluding `-evidence.md`); skips ABANDONED/DEFERRED. Runs Check 1 (unchecked tasks), Check 2 (checked tasks without evidence blocks), Check 3 (evidence block structural integrity), Check 4a-c (runtime-verification spec / executor / reviewer), Check 5 / A2 (DoD checklist + DoD Artifacts).
2. **`bug-persistence-gate.sh`** (user-process) — scans transcript for bug/gap trigger phrases; blocks if no persistence to `docs/backlog.md` or new `docs/reviews/`.
3. **`narrate-and-wait-gate.sh`** (user-process) — when keep-going was authorized, blocks if the final assistant message trails off with a permission-seeking phrase.
4. **`product-acceptance-gate.sh`** (Gen 5, product-outcome) — every ACTIVE non-exempt plan must have a runtime acceptance PASS artifact at `.claude/state/acceptance/<slug>/*.json` matching `plan_commit_sha`. Multi-worktree aggregation per Agent Teams plan task 10.
5. **`deferral-counter.sh`** (A5 — Gen 6) — transcript deferral surfacing; deferrals must appear in the user-visible final message.
6. **`transcript-lie-detector.sh`** (A3 — Gen 6) — completion-class + deferral-class claims in same session must be reconciled in the final message.
7. **`imperative-evidence-linker.sh`** (A7 — Gen 6) — strong user imperatives must have matching tool-call evidence or surface in the final message.
8. **`goal-coverage-on-stop.sh`** (A1 — Gen 6) — verbs from the verbatim first user message must each have matching tool-call evidence.

## Hook Scripts (`~/.claude/hooks/`)

| Script | Triggered by | Purpose |
|--------|-------------|---------|
| `pre-commit-gate.sh` | PreToolUse (on `git commit`) | Orchestrates: TDD gate (0a), plan-reviewer (0b), npm test (1), npm build (2), API audit (3) |
| `pre-commit-tdd-gate.sh` **(Gen 4)** | `pre-commit-gate.sh` step 0a | 5 layers: new-file test requirement, modified-file full-path test reference, integration-tier mock ban, trivial-assertion ban, silent-skip ban (2026-04-15) |
| `plan-reviewer.sh` **(Gen 4 + 2026-04-22; Phase 1d-E-1 narrowing 2026-05-04)** | `pre-commit-gate.sh` step 0b | Adversarial review of staged plan files: sweep decomposition (Check 1, section-aware — only flags sweep language under `## Tasks` headings), manual-verification language, missing Scope/DoD, Gen 3 anti-patterns, runtime-task test-spec coverage (Check 5, Tier A/B context-aware — runtime-keyword regex requires adjacency to database-context tokens, skipping documentation tokens like "Markdown table column"), and Check 6b — all 7 required sections must be present AND populated with non-placeholder content (Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy). Has `--self-test` flag exercising 26 scenarios. |
| `plan-edit-validator.sh` **(Gen 4; extended Agent Teams plan task 9, 2026-04-28)** | PreToolUse `Edit\|Write` | Blocks plan checkbox flips without fresh matching evidence file. Wraps the evidence-mtime check + plan-edit allow-decision in `flock` on `<plan>.lock` (30s timeout) so two parallel verifiers serialize safely; PID-keyed lock-file fallback when `flock(1)` is unavailable. |
| `plan-closure-validator.sh` **RETIRED 2026-05-05 (Tranche F audit)** | — | Hook removed. Replaced structurally by `adapters/claude-code/scripts/close-plan.sh` (Tranche E) which performs the same mechanical preconditions deterministically before flipping Status. Audit log: `.claude/state/failsafe-retirements.md`. |
| `prd-validity-gate.sh` **(Phase 1d-C-2 / C1, 2026-05-04)** | PreToolUse `Write` (on `docs/plans/<slug>.md`) | Blocks plan creation when the plan declares a `prd-ref:` resolving to a missing or incomplete `docs/prd.md` (single-PRD-per-project per Decision 015). Required PRD sections (each ≥ 30 non-whitespace chars): Problem, Scenarios, Functional, Non-functional, Success metrics, Out-of-scope, Open questions. Carve-out: `prd-ref: n/a — harness-development` (exact em-dash phrasing) bypasses entirely. Missing `prd-ref:` is ALLOWed with a WARN — plan-reviewer.sh Check 10 enforces presence. On PASS, recommends invoking the `prd-validity-reviewer` agent for substance review. Has `--self-test` flag exercising 6 scenarios (PASS-with-PRD, PASS-with-harness-dev-carveout, ALLOW-no-prd-ref-with-WARN, FAIL-prd-file-missing, FAIL-prd-section-missing, FAIL-prd-section-placeholder). |
| `spec-freeze-gate.sh` **(Phase 1d-C-2 / C2, 2026-05-04)** | PreToolUse `Edit\|Write\|MultiEdit` | Blocks edits to a file declared in any ACTIVE plan's `## Files to Modify/Create` section UNLESS that plan's header has `frozen: true`. Self-bypass for any path matching `docs/plans/*.md` (plans must edit themselves to flip frozen, append evidence, mark Status terminal, etc.). Iterates every top-level `docs/plans/*.md` (archive/ excluded), parses each `## Files to Modify/Create` (backticked paths or plain `path — desc` form), supports glob patterns + directory-prefix matches via the same engine as `scope-enforcement-gate.sh`. Multi-plan rule: ALL claiming plans must be frozen for the edit to pass; if ANY claiming plan has `frozen: false` or missing `frozen:`, the gate blocks and names the unfrozen plan(s). Degrades gracefully: any plan-parse error treats the plan as if it doesn't claim the file (so hook bugs don't lock the maintainer out of routine edits). Has `--self-test` flag exercising 6 scenarios (PASS-no-plan-claims, PASS-frozen-plan, FAIL-unfrozen-plan, PASS-multiple-plans-all-frozen, FAIL-multiple-plans-one-unfrozen, PASS-plan-file-itself). See `~/.claude/rules/spec-freeze.md` for the freeze-thaw protocol. |
| `findings-ledger-schema-gate.sh` **(Phase 1d-C-3 / C9, 2026-05-04)** | PreToolUse `Bash` (on `git commit`) | Mechanically validates every entry in `docs/findings.md` against the locked six-field schema from Decision 019: ID heading (`### <PROJECT-PREFIX>-FINDING-<NNN> — <title>`) with valid pattern + uniqueness, plus `**Severity:**` (info/warn/error/severe), `**Scope:**` (unit/spec/canon/cross-repo), `**Source:**`, `**Location:**`, `**Status:**` (open/in-progress/dispositioned-act/dispositioned-defer/dispositioned-accept/closed), and a non-empty `**Description:**` body. Enum values are case-insensitive accepted but normalized internally. No-op when `docs/findings.md` is not staged in the commit. On any failure (missing field, invalid enum, duplicate ID, orphaned field bullets) BLOCKs with stderr message naming the failing entry + reason. Has `--self-test` flag exercising 6 scenarios (PASS-valid-entry, PASS-no-findings-changes, FAIL-missing-id, FAIL-invalid-severity, FAIL-invalid-status, FAIL-duplicate-id). Template: `adapters/claude-code/templates/findings-template.md`. Rule: `adapters/claude-code/rules/findings-ledger.md`. |
| `definition-on-first-use-gate.sh` **(Phase 1d-F, 2026-05-04)** | PreToolUse `Bash` (on `git commit`) | Mechanically blocks commits that stage `*.md` files under `neural-lace/build-doctrine/` and introduce undefined acronyms. Per Decision 023: extracts uppercase 2-6 char tokens via `\b[A-Z]{2,6}\b`, filters a stopword allowlist (universally-understood tokens like `OK`, `URL`, `API`, `JSON`, `CSS`), then for each remaining acronym checks BOTH (a) the glossary at `~/claude-projects/Build Doctrine/outputs/glossary.md` (or `${REPO}/build-doctrine/outputs/glossary.md` fallback) for `**TERM**` / `## TERM` / `### TERM` / `\| TERM \|` patterns, AND (b) the same staged diff for in-context parenthetical definition `<TERM>\s*\(<2+ words>\)`. Blocks if both checks fail. Degrades gracefully when glossary is missing (warn + allow). Has `--self-test` flag exercising 7 scenarios (no-in-scope-changes, defined-in-glossary, defined-in-diff, undefined-blocked, stopwords-not-flagged, no-glossary-graceful-degrade, single-word-paren-rejected). Wiring lands in Phase 1d-F Task 3. Rule: `adapters/claude-code/rules/definition-on-first-use.md`. |
| `outcome-evidence-gate.sh` **(Gen 5)** | PreToolUse `Edit\|Write` | For fix tasks specifically: blocks checkbox flip unless evidence contains `Runtime verification (before):` + `Runtime verification (after):` with the same command (proof the fix addresses the bug). Escape hatch: `Reproduction recipe:` block for manual-repro cases. Triggered by task descriptions matching fix/bug/broken/regression/etc. Non-fix tasks pass through untouched. |
| `systems-design-gate.sh` **(Gen 5)** | PreToolUse `Edit\|Write` | Blocks edits to design-mode files (`.github/workflows/*.yml`, migrations, `vercel.json`, `Dockerfile`, deploy/migrate scripts, terraform, nginx config) unless an active plan with `Mode: design` AND `Status: ACTIVE` exists in `docs/plans/`. Escape hatch: `Mode: design-skip` plan with a written justification referencing the target file's basename. Works alongside `plan-reviewer.sh` (which enforces section presence for `Mode: design` plans) and the `systems-designer` agent (which enforces section substance). |
| `runtime-verification-executor.sh` **(Gen 4)** | `pre-stop-verifier.sh` Check 4b | Parses and executes Runtime verification entries (`test`/`playwright`/`curl`/`sql`/`file`); since 2026-04-15 also rejects cited test files that contain silent-skip patterns (`test.skip(!CRED, ...)`, `test.skipIf(...)`, etc.) unless annotated with `// harness-allow-skip:` |
| `runtime-verification-reviewer.sh` **(Gen 4)** | `pre-stop-verifier.sh` Check 4c | Correspondence check: verification commands must actually exercise modified files. Modified-file analysis excludes archived plans (`docs/plans/archive/**`) so historical-record edits don't trigger spurious correspondence demands (2026-04-23). |
| `tool-call-budget.sh` **(Gen 4; extended Agent Teams plan task 6, 2026-04-28)** | PreToolUse `.*` | Blocks after 30 tool calls without ack; `--ack` flag resets. In agent-team mode (when the firing session is a member of `~/.claude/teams/<team>/config.json`), the counter is keyed by `team_name` and at counter==30 the hook ALLOWS the call but writes a flag at `~/.claude/state/audit-pending.<team>` for `task-completed-evidence-gate.sh` to consume on the next TaskCompleted (deferred-audit cadence). Per-teammate sub-counter at `~/.claude/state/tool-call-since-task.<session_id>` blocks at 90 as a hard ceiling. Solo sessions retain the 30-call mid-stream block. |
| `post-tool-task-verifier-reminder.sh` **(Gen 4)** | PostToolUse `Edit\|Write` | Reminder to invoke task-verifier when src edit matches unchecked plan task. Uses `scripts/find-plan-file.sh` to fall back to archived plans when no active plan matches the edited file (2026-04-23). |
| `plan-lifecycle.sh` **(2026-04-23)** | PostToolUse `Edit\|Write` | Two responsibilities for files under `docs/plans/` (top-level only — not archive/): (1) on Write of a new plan file, surface a loud "uncommitted plan file" warning; (2) on any edit that transitions `Status:` from non-terminal to terminal (COMPLETED/DEFERRED/ABANDONED/SUPERSEDED), execute `git mv` to move the plan (and its `<slug>-evidence.md` companion if present) into `docs/plans/archive/`. Always advisory (PostToolUse never blocks). Has `--self-test` flag exercising 9 scenarios. |
| `pre-push-scan.sh` | Global git pre-push hook (NOT a Claude hook) | Scans push diffs for credentials. Loads 18 built-in patterns + `sensitive-patterns.local` + `business-patterns.paths` |
| `check-harness-sync.sh` | Pre-commit (via gate) | Warns if `~/.claude/` files have diverged from `neural-lace` repo |
| `pre-stop-verifier.sh` | Stop hook | Blocks session end if active plan has incomplete/unverified tasks. Check 4 calls executor + reviewer. Also surfaces a non-blocking `[uncommitted-plans-warn]` warning when `docs/plans/*.md` (top-level only — archive excluded) has uncommitted files at session end (2026-04-23). **Check 5 (M1, 2026-04-26):** when a plan declares `Status: COMPLETED`, blocks if any item under `## Definition of Done` is still `[ ]`. **Check 5 / A2 extension (2026-04-26):** when the plan ALSO declares a `## DoD Artifacts` section (optional), parses each `### bullet:` spec, locates the matching DoD checkbox, resolves the declared artifact path (supports `<runId>` glob expansion, plan-dir-relative then cwd-relative), and verifies the artifact exists with the declared `requires_field`+`requires_value` (jq lookup), `requires_pattern` (ERE regex match in file content), and/or `requires_min_length` (minimum byte size). Marking `[x]` is not sufficient when the artifact spec is declared — the artifact must exist on disk and match. No-op when `## DoD Artifacts` is absent. Has `--self-test` flag exercising 3 fixtures: completed-artifact-missing → BLOCK, completed-artifact-present → ALLOW, completed-no-artifacts-section → ALLOW. |
| `bug-persistence-gate.sh` **(extended Phase 1d-C-3, 2026-05-04)** | Stop hook | Scans transcript for bug/gap trigger phrases; blocks if no persistence happened in this session. Accepts FOUR durable-storage targets: `docs/backlog.md` (modified), `docs/reviews/YYYY-MM-DD-*.md` (added/modified), `docs/discoveries/YYYY-MM-DD-*.md` (added/modified — discovery-protocol files), and `docs/findings.md` (modified — class-aware ledger entries per Decision 019). Block-message lists all four options + the `.claude/state/bugs-attested-*.txt` escape hatch. Recent-touches branch and reflog branch both include findings.md. Has `--self-test` flag exercising 5 scenarios (PASS-with-backlog-edit, PASS-with-review-file, PASS-with-discovery-file, PASS-with-findings-entry, BLOCK-no-persistence). |
| `narrate-and-wait-gate.sh` | Stop hook | When the user has given a keep-going directive, blocks if the final assistant message trails off with a permission-seeking / wait-for-confirmation phrase. |
| `product-acceptance-gate.sh` **(Gen 5, 2026-04-24; extended Agent Teams plan task 10, 2026-04-28)** | Stop hook (position 4; chained AFTER pre-stop-verifier + bug-persistence + narrate-and-wait, BEFORE the Gen 6 narrative-integrity hooks at positions 5-8) | Blocks session end if any ACTIVE plan in `docs/plans/` lacks a PASS runtime acceptance artifact at `.claude/state/acceptance/<plan-slug>/*.json` whose `plan_commit_sha` matches the plan file's current git SHA. Recognizes `acceptance-exempt: true` plan-header field with required `acceptance-exempt-reason:` (>= 20 non-whitespace chars) — exempt plans skip the artifact check. Per-session waiver via `.claude/state/acceptance-waiver-<plan-slug>-<ts>.txt` (1-hour TTL, mirrors bug-persistence escape hatch). Production gate for the end-user-advocate loop (Phase D of `docs/plans/end-user-advocate-acceptance-loop.md`). Walking-skeleton recognition still lives in `pre-stop-verifier.sh` Check 0 (logs only, no blocking). Multi-worktree artifact discovery: enumerates all worktrees of the current repo via `git worktree list --porcelain` and aggregates artifacts found within each worktree's `.claude/state/acceptance/` — a PASS in *any* worktree satisfies the gate provided `plan_commit_sha` matches; degrades gracefully to cwd-only when `git worktree list` is unavailable. Has `--self-test` flag exercising 10 scenarios (8 original + 2 multi-worktree aggregation). |
| `teammate-spawn-validator.sh` **(Agent Teams plan task 5, 2026-04-27)** | PreToolUse `Task\|Agent` | Reads `~/.claude/local/agent-teams.config.json` and rejects unsafe teammate-spawn configurations: `enabled: false` + `team_name` set; `worktree_mandatory_for_write: true` + spawn lacks `isolation: "worktree"` for write-capable teammates; `force_in_process: true` + lead in `--dangerously-skip-permissions`. Defaults to ALLOW when ambiguous. 6-scenario `--self-test`. |
| `task-created-validator.sh` **(Agent Teams plan task 7, 2026-04-28)** | TaskCreated event | Validates teammate task subjects (>= 10 non-whitespace chars, not generic words) and `task_description` (must reference an active plan slug + acceptance criteria / `Done when:` clause). Defaults to ALLOW when ambiguous. Bypass: `TASK_CREATED_BYPASS=1` env or `bypass_validation: true` event field. 4-scenario `--self-test`. |
| `task-completed-evidence-gate.sh` **(Agent Teams plan task 8, 2026-04-28)** | TaskCompleted event | Two layered modes: evidence enforcement (requires evidence block matching `task_id` in `<plan>-evidence.md` or inline `## Evidence Log`); deferred-audit enforcement (consumes `~/.claude/state/audit-pending.<team>` flag set by team-aware `tool-call-budget.sh`, blocks until fresh `plan-evidence-reviewer` PASS at `~/.claude/state/reviews/<ts>.md`). Resets per-teammate sub-counter on every event. Bypass: `TASK_COMPLETED_BYPASS=1` env or `bypass_evidence_check: true` event field. 6-scenario `--self-test`. |
| `effort-policy-warn.sh` **(2026-04-22)** | SessionStart hook | Warns (non-blocking) when the configured effort level is below the minimum declared by a project-level `.claude/effort-policy.json` or user-level `~/.claude/local/effort-policy.json`. Ordering: `low < medium < high < xhigh <= max`. Has `--self-test` flag exercising 10 scenarios. |
| `discovery-surfacer.sh` **(2026-05-03)** | SessionStart hook | Scans `docs/discoveries/*.md` for files at `Status: pending` and surfaces them so pending decisions are seen before further work begins. Filters to YYYY-MM-DD-*.md naming convention. Silent when no pending discoveries or no `docs/discoveries/` directory. Has `--self-test` flag exercising 4 scenarios. |
| `plan-status-archival-sweep.sh` **(2026-05-04)** | SessionStart hook | Scans `docs/plans/*.md` (top-level only — not archive/) for plans whose `Status:` is at a terminal value (COMPLETED / DEFERRED / ABANDONED / SUPERSEDED) and `git mv`s each (plus sibling `<slug>-evidence.md`) into `docs/plans/archive/`. Safety-net for `plan-lifecycle.sh` when Status is flipped via Bash `sed` (which doesn't fire PostToolUse Edit/Write events). Falls back to plain `mv` for untracked files; refuses to overwrite an existing archive entry. Has `--self-test` flag exercising 5 scenarios (one asserts `git diff --cached --name-status` reports `R<num>` for tracked files to prevent silent regression of the rename-tracking path). |
| `settings-divergence-detector.sh` **(2026-05-04)** | SessionStart hook | Diffs `~/.claude/settings.json` against `$HOME/claude-projects/neural-lace/adapters/claude-code/settings.json.template`. When they differ, surfaces hook-entry-count divergence per event type (PreToolUse, PostToolUse, Stop, SessionStart, etc.) so the maintainer sees the worklist for HARNESS-GAP-14 reconciliation. Silent when files are byte-identical or either is absent. Uses jq for breakdown when available; degrades to a generic warning when not. Has `--self-test` flag exercising 4 scenarios. |
| `spawned-task-result-surfacer.sh` **(2026-05-05)** | SessionStart hook | Scans `.claude/state/spawned-task-results/*.json` for unread results (no sibling `.json.acked`) and surfaces each as a system-reminder block listing task_id, summary, branch, commits, ended_at, file path. Mirrors `discovery-surfacer.sh` shape: silent-when-empty, exit-0-always. Skips malformed JSON files with a stderr warning while still surfacing valid siblings. Uses jq when available; falls back to grep/sed parsing. Has `--self-test` flag exercising 5 scenarios (no-dir, empty-dir, all-acked, has-unread, mixed-malformed-and-valid). Part of HARNESS-GAP-08 (spawn-task report-back protocol). |
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
  → 4. product-acceptance-gate.sh (Gen 5, product-outcome)
    → Walk every ACTIVE plan in docs/plans/
    → For each: exempt? → allow. Per-session waiver? → allow.
      Otherwise: artifact at .claude/state/acceptance/<slug>/*.json
      with plan_commit_sha matching current HEAD AND all scenarios
      verdict=PASS? → allow. Otherwise → BLOCK.
  → 5. deferral-counter.sh (Gen 6 / A5 — narrative-deferral surfacing)
    → Scan transcript for deferral synonyms; if found AND last
      assistant message lacks "## Deferrals not executed in this session"
      heading with bullets → BLOCK.
  → 6. transcript-lie-detector.sh (Gen 6 / A3 — self-contradiction)
    → Scan transcript for completion-class + deferral-class phrase pairs
      in same session; if both present AND last message lacks
      "## Resolved contradictions in this session" → BLOCK.
  → 7. imperative-evidence-linker.sh (Gen 6 / A7 — strong-imperative coverage)
    → Scan last K user messages for strong imperatives (must/need to/...)
      mapping to imperative-patterns.json verbs; if any imperative lacks
      matching tool-call evidence AND last message lacks
      "## User-imperative coverage" → BLOCK.
  → 8. goal-coverage-on-stop.sh (Gen 6 / A1 — first-message goal coverage)
    → Read .claude/state/user-goals/<session-id>.json (written at first
      UserPromptSubmit by goal-extraction-on-prompt.sh).
    → Re-derive SHA-256 of first user message from $TRANSCRIPT_PATH; if
      mismatch with stored SHA → BLOCK (tamper detected).
    → Walk each extracted goal's verb-evidence regex against tool-call
      ledger; for unmet goals, BLOCK unless last assistant message
      contains "## User-goal coverage" heading with bullets.
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
| `task-verifier.md` **(extended Phase 1d-C-4 / C15, 2026-05-04)** | default | Verifies tasks are genuinely complete. **ONLY entity that can mark checkboxes in plan files.** Uses evidence-first protocol: writes evidence file with Runtime verification entries, then `plan-edit-validator.sh` authorizes the checkbox flip. Bans plain-text manual verification. **Comprehension-gate extension (Phase 1d-C-4):** when the active plan's header declares `rung: 2`, `rung: 3`, `rung: 4`, or `rung: 5`, the verifier auto-invokes `comprehension-reviewer` BEFORE flipping the checkbox; FAIL or INCOMPLETE from the comprehension-reviewer blocks the flip and surfaces the agent's class-aware feedback verbatim to the orchestrator for revision. Below R2 the auto-invocation is a no-op. | Has Edit access to plan files via evidence-first authorization |
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
| `comprehension-reviewer.md` **(Phase 1d-C-4, 2026-05-04)** | default | LLM-assisted comprehension audit of builder articulations on R2+ tasks per Decision 020. Read-only (Read/Grep/Glob/Bash for git inspection). Three-stage rubric: Stage 1 schema (four required headings — Spec meaning / Edge cases covered / Edge cases NOT covered / Assumptions); Stage 2 substance (≥ 30 non-whitespace chars per sub-section, no placeholder dodges); Stage 3 diff correspondence (each `file:line` edge-case-covered citation maps to actual diff content; no assumption is contradicted by the diff; the NOT-covered list is honest). Returns PASS / FAIL / INCOMPLETE with six-field class-aware feedback per gap. Auto-invoked by `task-verifier` at `rung: 2+` BEFORE flipping the checkbox; FAIL or INCOMPLETE blocks the flip. The task-verifier auto-invocation block lands in Phase 1d-C-4 Task 4; FM-023, the full inventory prose, and the vaporware-prevention enforcement-map row land in Task 5. |

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
| `prd-validity-reviewer.md` **(Phase 1d-C-2, 2026-05-04)** | default | Adversarial substance review of a project's `docs/prd.md` against the active plan that references it. Reviews the 7 PRD sections (problem / scenarios / functional / non-functional / success metrics / out-of-scope / open-questions) plus cross-cuts (T+30 success picture, scenario acceptance-testability, success-metric numericness, out-of-scope explicitness). Returns PASS/REFORMULATE/FAIL/INCOMPLETE with class-aware feedback per the six-field contract. Separate from `systems-designer` per Build Doctrine §9 Q6-A — PRD review is upstream of system design. Read-only: Read, Grep, Glob, Bash. Invoked manually by the planner OR via `prd-validity-gate.sh`'s recommend-invoke message after mechanical PASS. |

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
| `automation-modes.md` **(2026-04-23; extended Agent Teams plan task 13, 2026-04-28)** | Choosing where a Claude Code session runs | **Pattern-class** (self-applied). The five-mode decision tree operationalizing Decisions 011 + 012: Mode 1 (interactive local, full `~/.claude/` enforcement), Mode 2 (parallel local worktrees via Desktop "+ New session" or `isolation: "worktree"`), Mode 3 (`claude --remote` cloud sessions with project `.claude/` enforcement only), Mode 4 (`/schedule` Routines, same inheritance as Mode 3), Mode 5 (Agent Teams via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — feature-flagged, in-process default, harness gates via the new TaskCreated/TaskCompleted hooks; Decision 011 Approach A still applies — teammates inherit the same project `.claude/` as the lead). Per-mode invocation, tradeoffs, enforcement substrate, and concurrency model documented; out-of-scope modes (Dispatch, Managed Agents, DevContainers, self-hosted) explicitly listed for reach-back. Cited from top-of-CLAUDE.md "Choosing a Session Mode" section. |
| `agent-teams.md` **(Agent Teams plan task 11, 2026-04-28)** | Agent Teams integration (experimental Anthropic feature) | Hybrid (Pattern + Mechanism). Operational guide for `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Documents enable instructions (`~/.claude/local/agent-teams.config.json` + the JSON to write), the five upstream Anthropic bugs the user opts into, when to use Agent Teams vs orchestrator-pattern, the Spawn-Before-Delegate workaround, in-process vs pane-based teammate tradeoffs, and cross-references to the new hooks: `teammate-spawn-validator.sh` (PreToolUse), `task-created-validator.sh` (TaskCreated), `task-completed-evidence-gate.sh` (TaskCompleted), and the team-aware extensions to `tool-call-budget.sh`, `plan-edit-validator.sh` (flock), and `product-acceptance-gate.sh` (multi-worktree aggregation). Decision record: Decision 012 (`docs/decisions/012-agent-teams-integration.md`). |
| `acceptance-scenarios.md` **(Gen 5, 2026-04-24)** | Every plan by default; skipped via `acceptance-exempt: true` | Hybrid (Pattern + Mechanism). Documents the full plan-time → runtime → gap-analysis loop for the `end-user-advocate` agent. Plan-time: advocate authors `## Acceptance Scenarios` into the plan, flags under-specified user behaviors. Runtime: advocate executes scenarios via browser automation against the live app, writes PASS/FAIL JSON artifact to `.claude/state/acceptance/<plan-slug>/`. Stop-hook gate (walking-skeleton in `pre-stop-verifier.sh` Check 0; production lands as `product-acceptance-gate.sh` in Phase D of the parent plan) blocks session end if non-exempt ACTIVE plan lacks PASS artifact. Codifies scenarios-shared / assertions-private discipline (Goodhart prevention). Exemption mechanism: `acceptance-exempt: true` plan-header field with required `acceptance-exempt-reason:` (>= 20 chars) for harness-dev / pure-infrastructure / migration-only plans without UI surface. |
| `agent-teams.md` **(2026-04-29)** | When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` AND `~/.claude/local/agent-teams.config.json` has `enabled: true` | Hybrid (Pattern + Mechanism). Documents the Agent Teams integration: how to enable (config path + JSON + field defaults), the five upstream Anthropic bugs the user opts into (#50779, #24175, #43736, #24073, #24307) with workarounds, decision tree for Agent Teams vs orchestrator-pattern, Spawn-Before-Delegate Pattern (workaround for #24073/#24307), in-process vs pane-based teammate-mode tradeoffs (`force_in_process: true` default rejects pane-based at the spawn validator), inbox-deferral guidance (#50779 — batch coordination at TaskCreated/TaskCompleted boundaries), and the inventory of six new/extended hooks that fire in team mode (`teammate-spawn-validator.sh`, `task-created-validator.sh`, `task-completed-evidence-gate.sh`, team-aware `tool-call-budget.sh`, flock-protected `plan-edit-validator.sh`, multi-worktree-aggregating `product-acceptance-gate.sh`). Cross-references Decision 012 and the 2026-04-27 conflict analysis. |
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
| `harness-maintenance.md` | `~/.claude/**` changes | Global-first, commit to neural-lace repo, update architecture doc, no project-level copies |
| `deploy-to-production.md` **(2026-04-20)** | Any project where master merge auto-deploys to production (Vercel/similar) | Default: always merge + deploy to production after testing. Never leave work on a preview branch for manual merge. Preview is for the agent's own pre-merge validation only — the user tests in production. Pattern-class (no hook); the user's feedback memory + this rule carry it. |
| `prd-validity.md` **(Phase 1d-C-2, 2026-05-04)** | Every plan with `prd-ref:` set to a real slug (carve-out: `prd-ref: n/a — harness-development` exempts harness-internal plans) | Hybrid (Pattern + Mechanism). Documents Decision 015's PRD-validity gate (C1): single `docs/prd.md` per project, seven required sections (problem / scenarios / functional / non-functional / success metrics / out-of-scope / open-questions) each with ≥ 30 non-ws chars, harness-development carve-out via exact-string `n/a — harness-development`. The Mechanism + Pattern split: `prd-validity-gate.sh` (PreToolUse Write) checks shape; `prd-validity-reviewer` agent checks substance. Cross-references Decision 015, the agent, the hook (landing in Phase 1d-C-2 Task 3), the PRD template, and the sibling `spec-freeze.md` rule. |
| `spec-freeze.md` **(Phase 1d-C-2, 2026-05-04)** | Every ACTIVE plan with declared `## Files to Modify/Create` entries | Hybrid (Pattern + Mechanism). Documents Decision 016's spec-freeze gate (C2): `frozen: true|false` plan-header field; `frozen: false` blocks Edit/Write on declared files via `spec-freeze-gate.sh`; freeze captures the plan's commit SHA implicitly; thawing requires explicit flip with Decisions Log entry (freeze-thaw protocol); recovery from drift via `## In-flight scope updates` for light cases or freeze-thaw for heavy cases; plan files themselves exempt. Sibling to C10's commit-time `scope-enforcement-gate.sh`. Cross-references Decision 016, the hook (landing in Phase 1d-C-2 Task 4), and the sibling `prd-validity.md` rule. |
| `findings-ledger.md` **(Phase 1d-C-3, 2026-05-04)** | Every project that adopts the ledger; entries written by gates, adversarial-review agents, builders, and the orchestrator | Hybrid (Pattern + Mechanism). Documents Decision 019's findings-ledger format (C9): single `docs/findings.md` per project, six-field locked schema (id / severity / scope / source / location / status) with enum-locked values, six-state dispositioning lifecycle (open → in-progress → dispositioned-act/defer/accept → closed). The Mechanism + Pattern split: `findings-ledger-schema-gate.sh` (PreToolUse Bash on `git commit`, landing in Phase 1d-C-3 Task 3) validates schema; the rule (this doc) documents who writes entries, when, and the relationship to backlog / reviews / discoveries / failure-modes. Backstopped by the extended `bug-persistence-gate.sh` (Task 4) which accepts `docs/findings.md` as legitimate persistence. Cross-references Decision 019, the schema gate, the bug-persistence extension, and the canonical template. |
| `comprehension-gate.md` **(Phase 1d-C-4, 2026-05-04)** | Every plan with `rung: 2+`; builders write `## Comprehension Articulation` blocks inside their evidence entries | Hybrid (Pattern + Mechanism). Documents Decision 020's comprehension-gate (C15): four required articulation sub-sections (Spec meaning / Edge cases covered / Edge cases NOT covered / Assumptions) with a ≥ 30-char substance threshold per field, three-stage agent rubric (schema check → substance check → diff correspondence), rung-2 cutoff rationale. The Mechanism + Pattern split: at `rung: 2+`, `task-verifier` invokes `comprehension-reviewer` (Task 3) before flipping the checkbox; FAIL or INCOMPLETE blocks the flip. Below R2 the gate is a no-op. Cross-references Decision 020, the comprehension-template, the comprehension-reviewer agent (Task 3), the task-verifier extension (Task 4), and FM-023 (Task 5). |
| `definition-on-first-use.md` **(Phase 1d-F, 2026-05-04)** | Every commit modifying `*.md` under `neural-lace/build-doctrine/`; authors and reviewers of doctrine docs | Mechanism (hook-enforced). Documents Decision 023's definition-on-first-use semantics: acronym detection regex `\b[A-Z]{2,6}\b`, stopword allowlist for universally-understood tokens, scope-prefix `neural-lace/build-doctrine/`, "defined" semantics (glossary entry OR in-diff parenthetical with 2+ words), failure-message format. Mechanical block at commit time via `definition-on-first-use-gate.sh` when an in-scope file introduces an undefined acronym. Cross-references Decision 023, the gate, and the canonical glossary at `~/claude-projects/Build Doctrine/outputs/glossary.md`. |
| `spawn-task-report-back.md` **(HARNESS-GAP-08 Task 1, 2026-05-05)** | Orchestrator + spawned sessions using `mcp__ccd_session__spawn_task` | Hybrid (Pattern + Mechanism). Documents the convention-based callback channel for the third-party fire-and-forget MCP tool: orchestrator generates a monotonic kebab-case timestamp-prefixed task-id, embeds `Report-back: task-id=<X>` sentinel in the spawn prompt; spawned session writes JSON result file (locked schema: task_id / started_at / ended_at / branch / pr_url / exit_status / summary / commits / artifacts) to `.claude/state/spawned-task-results/<task-id>.json` before its Stop hook fires; SessionStart surfacer hook (`spawned-task-result-surfacer.sh`, landing in GAP-08 Task 2) surfaces unread results; orchestrator writes sibling `<task-id>.json.acked` marker after acting. Mirrors `discovery-surfacer.sh` shape. Includes worked example, edge-case enumeration (crashes, malformed JSON, multiple unread, duplicate task-ids, missed acks, unadopted projects), and cross-references to discovery-protocol.md and orchestrator-pattern.md. |
| `mechanical-evidence.md` **(Tranche B of architecture-simplification, 2026-05-05)** | Every plan-task verification that is `Verification: mechanical` or purely structural (file edits, hook updates, schema authoring, prompt updates, sync-to-mirror) | Hybrid (Pattern + Mechanism). Documents Build Doctrine Principle 7 ("Visibility lives in artifacts, not narration") at the harness level: a JSON Schema (`evidence.schema.json`) locks the structured evidence shape; helper script (`write-evidence.sh capture`) deterministically records mechanical-check outcomes (typecheck/lint/test/exists/schema-valid/files-in-commit/command); `plan-edit-validator.sh` recognizes both new structured artifacts (`<plan-slug>-evidence/<task-id>.evidence.json`) and legacy prose `<plan>-evidence.md` blocks. The Mechanism + Pattern split: schema + helper + hook are mechanical; the discipline of preferring mechanical evidence for structural tasks (and escalating to prose for novel work via `prose_supplement`) is Pattern. Backward compatible — existing closed plans with prose evidence remain valid. Cross-references the `task-verifier` agent extension (Tranche B Task 5) that prefers helper-script invocation over prose authorship. |
| `risk-tiered-verification.md` **(Tranche D of architecture-simplification, 2026-05-05)** | Every plan-task with an explicit `Verification: <level>` declaration; default `full` applies to unmarked tasks (backward-compatible) | Hybrid (Pattern + Mechanism). Documents Build Doctrine `04-gates.md` tier matrix at the harness level: three levels (`mechanical` / `full` / `contract`) declared inline at the end of a `## Tasks` checkbox line. The Mechanism stack: `plan-reviewer.sh` Check 12 validates the field's value at plan-edit time (rejects unknown levels with stderr explaining the legal set); `plan-edit-validator.sh` extracts the level at checkbox-flip time and routes evidence-freshness checking accordingly (mechanical/contract accept structured `.evidence.json` artifacts without runtime-verification lines; full retains existing prose-with-runtime-verification rubric); `task-verifier` Step 0 early-returns PASS for mechanical/contract, citing the structured artifact, without running typecheck/dependency-trace/runtime-replay. The Pattern: planners declare the level when authoring tasks; default-`full` preserves existing-plan semantics. Self-tested: `plan-reviewer.sh --self-test` adds 3 scenarios (vd1/vd2/vd3) covering valid mechanical, default-full, illegal level. `plan-edit-validator.sh --self-test` adds 3 scenarios (F8/F9/F10) covering structured-mechanical, structured-contract, unmarked-defaults. Cross-references Decision queued-tranche-1.5.md D.1-D.3, the `mechanical-evidence.md` rule (Tranche B), and Build Doctrine `04-gates.md`. |
| `teaching-moments.md` **(2026-05-06)** | Conversations where the user pushed back on a Claude position; capture-trigger is Claude's own judgment | Pattern (no PostMessage hook in Claude Code, so capture is judgment-based). Documents when to write a teaching-example file (substantive pushback + meaningfully better revised position + generalizable lesson + sufficient surviving context), the file format (frontmatter with date/topic/lesson/project + 5 body sections: Context / Initial / Pushback / Corrected / Lesson + optional Generalization), the discipline (high bar — 0-1 captures per session is normal, 3+ means the bar is too low), and the file location (`docs/teaching-examples/YYYY-MM-DD-<slug>.md` project-local, `~/teaching-examples/` for cross-project pool). Companion skill `teaching-moments.md` provides `capture` / `list` / `show` / `propagate` subcommands. The first captured example is `docs/teaching-examples/2026-05-06-starter-rules-vs-wait-for-pilot.md`. |

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
| `findings-template.md` **(Phase 1d-C-3, 2026-05-04)** | `findings-ledger.md` rule | Canonical shape for `docs/findings.md`. Top-of-file schema specification block (six fields with enum values + lifecycle definition + severity/scope ordering) plus three sample entries demonstrating `open` / `dispositioned-defer` / `closed` statuses. Validated at commit time by `findings-ledger-schema-gate.sh` (Phase 1d-C-3 Task 3). |
| `comprehension-template.md` **(Phase 1d-C-4 / C15, 2026-05-04)** | `comprehension-gate.md` rule + `task-verifier` evidence-block discipline | Canonical four-heading articulation block builders paste into a `## Comprehension Articulation` section inside their evidence entry on `rung: 2+` plans. The four required sub-headings: `### Spec meaning` (the builder's interpretation of what the spec asks for, in the builder's own words), `### Edge cases covered` (each with a `file:line` citation in the diff that handles it), `### Edge cases NOT covered` (each with rationale — explicit out-of-scope vs deferred vs assumed-by-caller), `### Assumptions` (every premise the diff relies on, made explicit). Substance prompts in each sub-section explain what to write so placeholder-only content cannot satisfy the schema. Validated at task-verification time by `comprehension-reviewer` agent (auto-invoked by `task-verifier` at `rung: 2+`). Cross-references Decision 020. |

## Work-Shapes (`~/.claude/work-shapes/`) — Tranche C of architecture-simplification, 2026-05-05

The engineering catalog Build Doctrine Principle 2 calls for, applied to harness-dev work. Each shape declares YAML frontmatter (`shape_id`, `category`, `required_files`, `mechanical_checks`, `worked_example`) and prose body (when-to-use, structure, common pitfalls, worked-example walk-through). The mechanical checks become the verification rubric task-verifier (or the builder in self-verification contexts) runs at evidence-block time. Library is documentation in v1; mechanical compliance enforcement at commit time deferred per Tranche C scope.

| Shape | Category | Worked example | When to use |
|---|---|---|---|
| `build-hook.md` | hook | `adapters/claude-code/hooks/harness-hygiene-scan.sh` | Creating or modifying a Claude Code hook script under `adapters/claude-code/hooks/`. Composes `write-self-test` inline. |
| `build-rule.md` | rule | `adapters/claude-code/rules/harness-hygiene.md` | Creating or modifying a doctrine file under `adapters/claude-code/rules/`. |
| `build-agent.md` | agent | `adapters/claude-code/agents/task-verifier.md` | Creating or modifying a sub-agent prompt under `adapters/claude-code/agents/`. |
| `author-ADR.md` | decision | `docs/decisions/026-harness-catches-up-to-doctrine.md` | Recording a Tier 2+ decision under `docs/decisions/NNN-<slug>.md` plus an index row in `docs/DECISIONS.md`. |
| `write-self-test.md` | test | `harness-hygiene-scan.sh --self-test` block | Adding a `--self-test` block to a bash mechanism (composes inline with `build-hook`). |
| `doc-migration.md` | migration | build-doctrine Tranche 0b migration | Moving doctrine content between locations with byte-identical or anonymization-only diff. |

The `README.md` in the same directory enumerates v1 shapes, format spec, and how-to-use. The rule documenting when to use a shape, how to add one, and the escalation path for novel work lives at `~/.claude/rules/work-shapes.md`. Cross-referenced from `~/.claude/rules/orchestrator-pattern.md` and the enforcement map in `~/.claude/rules/vaporware-prevention.md`.

## Schemas (`~/.claude/schemas/`)

JSON Schemas (draft 2020-12) lock the shape of harness-controlled artifacts. Each schema validates against the meta-schema; helper scripts and hooks cross-reference the schema by `$id`.

| Schema | Used by | Purpose |
|--------|---------|---------|
| `automation-mode.schema.json` | `automation-mode.config.json` (per-user / per-project) | Locks the two-mode automation toggle (`full-auto` vs `review-before-deploy`) plus optional `deploy_matchers` array. |
| `personal.config.schema.json`, `accounts.config.schema.json`, `projects.config.schema.json` | `~/.claude/local/*.json` per-machine config | Locks local-config shapes for personal / accounts / projects two-layer-config pattern. |
| `agent-teams.config.schema.json` | `~/.claude/local/agent-teams.config.json` | Locks the Agent Teams feature flag + tunables (`force_in_process`, `worktree_mandatory_for_write`, `per_team_budget`). Decision 012. |
| `evidence.schema.json` **(Tranche B of architecture-simplification, 2026-05-05)** | `write-evidence.sh capture`; `plan-edit-validator.sh` Path B (structured-evidence recognition); future closure-validator (Tranche E) | Locks the canonical structured evidence shape per Build Doctrine Principle 7 ("Visibility lives in artifacts, not narration"). Six required fields (`task_id`, `verdict` enum `PASS\|FAIL\|INCOMPLETE`, `commit_sha`, `files_modified`, `mechanical_checks`, `timestamp`) plus optional escalation fields (`runtime_evidence` array, `prose_supplement`, `verifier`, `plan_path`, `schema_version` defaulting to 1). The `mechanical_checks` field is a map of check-name → `{passed, detail, command, exit_code}` (or terse boolean). Self-validates against the meta-schema. Backward compatible with legacy prose `<plan>-evidence.md` blocks — both formats accepted by `plan-edit-validator.sh`. |

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
| `harness-hygiene-sanitize.sh` **(GAP-13 Task 4 / Layer 4, 2026-05-05)** | Manual sanitization workflow after `hooks/harness-hygiene-scan.sh` finds matches | Reads scanner output (canonical `<file>:<line>: <content>` format, with optional `[denylist]` / `[heuristic]` tag) from stdin or a file argument. Classifies each matched token by pattern class (cloud-bucket, OAuth client-id, project-internal-path, capitalized-cluster, customer-name, generic) and proposes a replacement (`<your-bucket>`, `<your-client-id>`, `src/<example-path>`, `<your-project>`, `<customer>`, `<redacted>`). Emits a unified diff to stdout showing proposed changes — does NOT modify files. User reviews and applies via `git apply` if accepting. `--self-test` flag exercises 5 scenarios (s1-s5) covering each replacement class plus clean input. |
| `write-evidence.sh` **(Tranche B of architecture-simplification, 2026-05-05)** | `task-verifier` agent (preferred over prose-authorship for `Verification: mechanical` and structural tasks); orchestrators capturing mechanical-check outcomes | `capture` subcommand runs `--check` specifications (typecheck, lint, test:NAME, exists:PATH, schema-valid:PATH, files-in-commit, command:CMD) and writes a JSON artifact validating against `~/.claude/schemas/evidence.schema.json` to `<plan-dir>/<plan-slug>-evidence/<task-id>.evidence.json`. Verdict logic: PASS when all checks pass; FAIL when any failed; INCOMPLETE when no checks were specified. Auto-discovers `files_modified` from `git diff-tree HEAD` (with `git ls-tree HEAD` initial-commit fallback). 9-scenario `--self-test` flag covers: capture-with-all-checks-pass, capture-with-failing-check, capture-with-no-checks-INCOMPLETE, schema-valid-check, missing-task-arg-rejects, invalid-task-id-rejects, command-check-success, command-check-failure, required-fields-all-present. |
| `close-plan.sh` **(Tranche E of architecture-simplification, 2026-05-05)** | The `/close-plan` skill (slash-command wrapper); orchestrators closing plans at end-of-build | Deterministic close-plan procedure. Subcommand `close <plan-slug> [--no-push] [--force]` performs all closure work in seconds with **zero agent dispatches**: routes each task per its declared `Verification:` level (mechanical → bash check on `<plan-slug>-evidence/<task-id>.evidence.json` with `verdict==PASS` OR commit-SHA citation in prose evidence; contract → check that `Contract:` path exists OR fall through to mechanical-style; full → existing prose `Verdict: PASS` evidence); generates the completion report from the plan's `## Files to Modify/Create` + `git log` for commits touching those files; updates SCRATCHPAD; verifies backlog reconciliation; flips `Status: ACTIVE → COMPLETED` (which triggers `plan-lifecycle.sh` archival within a Claude Code session, with idempotent fallback when run standalone); auto-pushes (per E.2). Block-by-default with `--force` audit-logged escape (per E.3 — logs to `.claude/state/close-plan-force-overrides.log`) and `--no-push` for review-locally-first. Synthetic 3-task plan closes in ~3 seconds; pre-redesign baseline was ~13 dispatches and ~65K tokens. 10-scenario `--self-test` flag covers: all-mechanical-tasks-closure, all-full-tasks-closure, mixed-tier-closure, missing-completion-report (procedure generates it), stale-SCRATCHPAD (procedure updates), unreconciled-backlog (BLOCK), --force bypass (allows + logs), mechanical-task-missing-evidence (BLOCK), contract-task-schema-fail (BLOCK), all-PASS-archives. The legacy `plan-closure-validator.sh` hook is tagged-for-retirement during Tranche F; this procedure produces evidence that satisfies its checks during the transition. |

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
| `close-plan.md` **(rewritten Tranche E of architecture-simplification, 2026-05-05)** | Thin slash-command wrapper around `adapters/claude-code/scripts/close-plan.sh close <slug>`. The script implements the deterministic close-plan procedure: routes each task per its declared `Verification:` level (mechanical/contract/full per Tranche D), generates the completion report from the plan's `## Files to Modify/Create` + `git log`, updates SCRATCHPAD, verifies backlog reconciliation, flips `Status: ACTIVE → COMPLETED` (triggering `plan-lifecycle.sh` archival), then auto-pushes (per E.2 / `feedback_full_auto_deploy.md`). Block-by-default with `--force` audit-logged escape (per E.3) and `--no-push` for review-locally-first. Closes plans in seconds with **zero agent dispatches** — pre-redesign baseline was ~13 dispatches and ~65K tokens. Self-test exercises 10 scenarios (`close-plan.sh --self-test`). The legacy `plan-closure-validator.sh` hook is tagged-for-retirement during Tranche F audit; the deterministic procedure is the replacement and produces evidence that satisfies the validator's checks during the transition. |
| `calibrate.md` **(Tranche G, 2026-05-05)** | Manual-entry calibration capture. Writes structured per-agent observations to `.claude/state/calibration/<agent-name>.md` (gitignored). Five canonical observation classes: `shortcut`, `hallucination`, `pass-by-default`, `format-drift`, `scope-drift`. Bootstraps the Knowledge Integrator role (Build Doctrine Principle 9 + Role 9) ahead of telemetry. Roll-up consumed by `/harness-review` Check 12. Discipline in `~/.claude/rules/calibration-loop.md`. |
| `teaching-moments.md` **(2026-05-06)** | Capture / browse teaching moments — interactions where the user's pushback produced a substantively better answer than Claude's first response. Subcommands: `capture` (manual capture when Claude missed one), `list` (table of all examples in current project), `show <slug>`, `propagate` (copy to `~/teaching-examples/` cross-project pool with provenance preserved). Companion to `~/.claude/rules/teaching-moments.md`. Captured examples teach developers the prompting patterns that surface Claude's confidence-without-verification failure modes. |

## Calibration Loop (Tranche G, 2026-05-05)

Manual bootstrap of the Build Doctrine Knowledge Integrator role
(`build-doctrine/doctrine/02-roles.md` Role 9) until telemetry-driven
mechanization lands (HARNESS-GAP-11, gated 2026-08). Per Decision G.1
(`docs/decisions/queued-tranche-1.5.md`), calibration entries live as
gitignored per-machine operational state at `.claude/state/calibration/<agent-name>.md`.

Three components:

- **Capture skill** (`~/.claude/skills/calibrate.md`) — `/calibrate <agent>
  <observation-class> <details>` appends a structured entry to the
  per-agent file. Five canonical observation classes (`shortcut`,
  `hallucination`, `pass-by-default`, `format-drift`, `scope-drift`);
  `new-class:<label>` prefix to propose a sixth.
- **Roll-up consumer** (`~/.claude/skills/harness-review.md` Check 12) —
  weekly audit reads all per-agent files and surfaces total entry count,
  top-3 observation classes, and most-recent entry per class. Pattern
  recognition is then human-mediated (Knowledge Integrator decides which
  patterns warrant prompt updates, work-shape extensions, or
  telemetry-deferral).
- **Discipline rule** (`~/.claude/rules/calibration-loop.md`) — when to
  invoke, what NOT to calibrate (codebase bugs go to backlog/findings,
  not calibration), and the routing logic from observation patterns to
  remediation type.

This is the harness's first reactive-to-proactive transition: every
agent-behavior failure observed during build becomes a candidate doctrine
update, not a forgotten frustration. Telemetry mechanization upgrades
the substrate but does not change the discipline.

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
