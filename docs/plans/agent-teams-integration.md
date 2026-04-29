# Plan: Agent Teams Integration

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Tier: 2
Backlog items absorbed: HARNESS-DRIFT-03, HARNESS-DRIFT-04
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan integrating an experimental Anthropic feature (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS); no product-user surface to verify at runtime. Per-task runtime verification specs substitute. The integration is exercised by the maintainer enabling the env flag in a subsequent session.

## Why Tier 2 (not Tier 3)

Per `principles/permission-model.md` reversibility / blast-radius / sensitivity dimensions: every change in this plan is to harness-layer files (rules, hooks, plan templates, settings.json) — fully reversible by `git revert`. Blast radius is bounded to Claude Code session behavior; no production database, no third-party API, no data migration. Sensitivity is medium (changes how the harness gates work) but not high (no credential handling, no shared infra). The closest Tier-3 trigger is "Authority Escalation" — but the new hooks REDUCE authority by adding gates, not relax them. Tier 2 with mandatory plan review + decision record + post-task verification is the right tier.

## Goal

Make the Neural Lace Claude Code harness compatible with Anthropic's experimental Agent Teams feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, requires Claude Code v2.1.32+) such that enabling the env flag does not silently degrade enforcement. Specifically: when a lead session spawns teammates via `TaskCreate`, every hook-enforced quality gate that protects the user's plan, code, and credentials continues to fire correctly across all teammate sessions, without per-team-multiplied false negatives, races on shared state, or platform-dependent silent drops.

Enabling Agent Teams without this work would silently degrade the harness in five concrete ways (named hard blockers in `docs/reviews/2026-04-27-agent-teams-conflict-analysis.md`). After this plan ships, the harness gates work the same in single-session and team contexts, with a feature flag for safe rollout.

This plan does NOT enable Agent Teams. It makes enabling Agent Teams safe. The user enables the flag in `settings.json` after this plan completes.

## Scope

**IN:**
- New hook: `teammate-spawn-validator.sh` — PreToolUse on `Agent` (formerly `Task`) tool; rejects unsafe spawn configurations
- New hook: `task-created-validator.sh` — TaskCreated event handler; enforces plan-reference + acceptance-criteria
- New hook: `task-completed-evidence-gate.sh` — TaskCompleted event handler; enforces evidence-block existence
- Extend `tool-call-budget.sh` with team-aware mode (counter keyed by `team_name` resolved from `session_id`)
- Extend `plan-edit-validator.sh` with parallel-write protection (flock on `<plan>.lock`)
- Extend `product-acceptance-gate.sh` with multi-worktree artifact discovery
- New rule: `rules/agent-teams.md` documenting the integration
- Plan template: new value `Execution Mode: agent-team` with section in `rules/planning.md` + `rules/orchestrator-pattern.md` documenting tradeoffs
- Feature flag config: `~/.claude/local/agent-teams.config.example.json` + schema; honored by spawn validator
- Templates parity: copy `decision-log-entry.md` and `completion-report.md` from `~/.claude/templates/` to `adapters/claude-code/templates/` (HARNESS-DRIFT-04)
- Stop chain doc update: `rules/acceptance-scenarios.md` 4→5 positions (HARNESS-DRIFT-03)
- Decision record: `docs/decisions/012-agent-teams-integration.md`
- Documentation updates: `docs/harness-architecture.md`, `README.md`, `rules/automation-modes.md`
- Self-tests for every new hook (`--self-test` flag with 5+ scenarios)

**OUT:**
- Wiring the 6 unwired Gen-6 hooks (HARNESS-DRIFT-01) — separate plan, broader fix
- Replacing the hardcoded account-switching hook with config-driven (HARNESS-DRIFT-02) — separate plan, broader fix
- Trust-ledger implementation — pre-existing aspirational design, separate plan
- Anthropic-side bug fixes (#50779, #24175, #24073, #24307, #45329) — workarounds documented; cannot resolve harness-side
- Actually enabling `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — explicit user action after plan completes
- Per-teammate-frontmatter enforcement (since `hooks:` empirically NOT propagated to teammates per #45329) — different mechanism class
- Wiring TaskCreated / TaskCompleted into existing acceptance / orchestrator flows beyond what's in scope here — phase 2 work after the new hooks prove out
- Promoting Agent Teams to a 5th value of `Execution Mode` if user pushback on `agent-team` value

## Tasks

- [x] 1. **Setup + decision record.** Create `docs/decisions/012-agent-teams-integration.md` recording the 6 design decisions (see Decisions Log). Stage this with the plan-creation commit per decisions-index-gate atomicity rule.

- [x] 2. **Templates parity (HARNESS-DRIFT-04).** Copy `~/.claude/templates/decision-log-entry.md` and `~/.claude/templates/completion-report.md` into `adapters/claude-code/templates/`. Verify identical content (`diff -q`). Update `rules/harness-maintenance.md` if needed to reflect templates as adapter-tracked.

- [x] 3. **Stop chain doc update (HARNESS-DRIFT-03).** Edit `rules/acceptance-scenarios.md:49-55` to reflect 5-position Stop chain (add `deferral-counter.sh`). Audit `docs/harness-architecture.md` for the same staleness; fix if found.

- [x] 4. **Feature flag config.** Create `adapters/claude-code/examples/agent-teams.config.example.json` + `schemas/agent-teams.config.schema.json`. Schema fields: `enabled` (bool, default false), `force_in_process` (bool, default true), `worktree_mandatory_for_write` (bool, default true), `per_team_budget` (bool, default true). Document in `docs/harness-guide.md`.

- [x] 5. **`teammate-spawn-validator.sh` — new PreToolUse hook on Agent tool.** Reads `~/.claude/local/agent-teams.config.json` (if exists) + `~/.claude/teams/<team>/config.json` for current team state. Rejects spawn when:
   - (a) `enabled: false` AND target tool is `Agent` with `team_name` parameter set
   - (b) `worktree_mandatory_for_write: true` AND spawn lacks `isolation: "worktree"` AND spawned agent has write-capable tools (Edit/Write/MultiEdit/Bash)
   - (c) lead is in `--dangerously-skip-permissions` mode AND `force_in_process: true`
   - Includes `--self-test` with 6 scenarios. Wires into `settings.json` PreToolUse `Task|Agent` matcher.

- [x] 6. **`tool-call-budget.sh` team-aware extension with deferred-audit cadence.** Add team-awareness AND deferred-audit behavior:
   - **Counter scope:** at hook fire, derive `effective_session_id`: if `~/.claude/teams/<team>/config.json` lists current `CLAUDE_SESSION_ID` as a member, use `team_name`; else fallback to `CLAUDE_SESSION_ID`. Counter file at `~/.claude/state/tool-call-count.<effective_session_id>` with flock(1)-based read-modify-write protection (PID-keyed fallback if flock unavailable).
   - **Audit cadence — agent-team mode (counter keyed by team):** at counter == 30, instead of blocking, write a flag file at `~/.claude/state/audit-pending.<team>` with the current task_id and a timestamp. Allow the tool call. The flag is consumed by the new TaskCompleted hook (Task 8) which runs `plan-evidence-reviewer` and clears the flag (or blocks completion on FAIL).
   - **Hard ceiling — agent-team mode:** if a single teammate accumulates 90+ tool calls without an intervening TaskCompleted clearing the flag, fall back to mid-stream block. Counter is per-team but the per-teammate accumulation is tracked via a sub-counter at `~/.claude/state/tool-call-since-task.<session_id>`.
   - **Audit cadence — solo mode (counter keyed by session):** unchanged — block at 30, require ack.
   - **Self-test extended:** existing 8 scenarios pass + 6 new scenarios = 14/14:
     - Solo session falls back to session-id and 30-call mid-stream block (regression test)
     - Team member at counter 25 passes through with no flag
     - Team member at counter 30 sets flag, allows tool call (no block)
     - Team member at counter 31 with flag set: still passes through (audit not yet run)
     - Team member at counter 89 (single teammate sub-counter) passes through
     - Team member at counter 90 (single teammate sub-counter) blocks mid-stream as hard ceiling
   - Backward-compatible: solo sessions (no team) get the existing per-session block-at-30 behavior.

- [x] 7. **`task-created-validator.sh` — new TaskCreated event hook.** Reads `task_subject` and `task_description` from event input. Rejects (exit 2 + JSON `{"continue": false, "stopReason": "..."}`) when:
   - (a) `task_description` doesn't reference an active plan file path (regex `docs/plans/[a-z0-9-]+\.md`)
   - (b) `task_description` doesn't reference acceptance criteria or a `Done when:` clause
   - Self-test with 4 scenarios. Wires into `settings.json` TaskCreated matcher (new event type, requires settings.json schema check).

- [x] 8. **`task-completed-evidence-gate.sh` — new TaskCompleted event hook.** Reads `task_id` and `team_name`. Two enforcement modes layered:
   - **Evidence enforcement:** verifies an evidence block exists at `<plan>-evidence.md` referencing the same task ID (via `task_id`-to-plan-task-ID convention to be established in this hook). Blocks completion if missing.
   - **Deferred-audit enforcement:** checks for `~/.claude/state/audit-pending.<team_name>` flag. If present, invokes `plan-evidence-reviewer` for the team's active plan. PASS verdict → clears flag, counter reset, TaskCompleted allowed. FAIL verdict → flag stays set, TaskCompleted blocked, error message points at audit findings. Coordinates with Task 6's flag-setting behavior.
   - **Self-test with 6 scenarios:** rejects-missing-evidence, allows-evidence-present, allows-explicit-bypass, handles-missing-task-id-gracefully, runs-audit-when-flag-set-and-PASS-clears-flag, runs-audit-when-flag-set-and-FAIL-blocks-completion.

- [x] 9. **`plan-edit-validator.sh` flock extension.** Wrap the validator's evidence-mtime check + plan-edit allow-decision in `flock` on `<plan>.lock`. Two parallel verifiers each acquire the lock serially. Add a 30s lock timeout to prevent indefinite hang if a previous verifier crashed. Self-test with 4 scenarios (single-writer baseline, two-writer serialization, lock-timeout, lock-cleanup).

- [x] 10. **`product-acceptance-gate.sh` multi-worktree artifact discovery.** Extend the gate to enumerate the current repo's worktrees (via `git worktree list`) and aggregate `.claude/state/acceptance/` artifacts found within them. A scenario PASS in any worktree's state dir satisfies the gate, provided `plan_commit_sha` matches. Documents the new behavior in `rules/acceptance-scenarios.md` and the gate's header comment.

- [x] 11. **New rule: `rules/agent-teams.md`.** Documents:
   - **First sub-section: "How to enable Agent Teams"** — exact config file path (`~/.claude/local/agent-teams.config.json`), the JSON to write (`{"enabled": true}`), the field defaults, and a clear-eyed list of the five upstream bugs the user is opting into ([#50779](https://github.com/anthropics/claude-code/issues/50779), [#24175](https://github.com/anthropics/claude-code/issues/24175), [#43736](https://github.com/anthropics/claude-code/issues/43736), [#24073](https://github.com/anthropics/claude-code/issues/24073), [#24307](https://github.com/anthropics/claude-code/issues/24307)). Visible at the top so a user landing on this rule sees the enable instructions immediately.
   - When to use Agent Teams vs orchestrator-pattern (decision tree)
   - Spawn-Before-Delegate pattern (workaround for #24073/#24307)
   - In-process vs pane-based teammate mode tradeoffs
   - Inbox-deferral bug (#50779) behavioral guidance
   - The 4 unfixed Anthropic upstream issues with workarounds
   - Cross-references to all hooks and config files in this plan

- [x] 12. **Plan template `Execution Mode: agent-team`.** Add the new value to `templates/plan-template.md` line 3 alternatives. Add a section to `rules/planning.md` documenting when `agent-team` vs `orchestrator` is appropriate. Add a section to `rules/orchestrator-pattern.md` named "Agent Teams pairing" describing how the two execution modes coexist.

- [x] 13. **Documentation updates.**
   - `docs/harness-architecture.md`: add new hooks to the inventory table; describe new event matchers (TaskCreated, TaskCompleted); reference Decision 012; reflect Stop chain corrections from Task 3.
   - `README.md`: add a row to the status table — `**Agent Teams:** feature-flagged (experimental). To enable: see [`adapters/claude-code/rules/agent-teams.md`](adapters/claude-code/rules/agent-teams.md).` Position the row prominently so it's visible from the repo's first scroll. The user must be able to find the enable instructions without searching.
   - `rules/automation-modes.md`: add Agent Teams as Mode 5 (or sub-mode) with the harness-portability story (Decision 011 Approach A still applies; teammates inherit project `.claude/`).

- [x] 14. **Integration self-test: `tests/agent-teams-self-test.sh`.** Synthetic scenario runner that exercises each new hook with mocked event input. Validates spawn-validator scenarios, budget team-counter, task-created/completed gates, plan-edit-validator flock behavior, acceptance-gate worktree aggregation. Pass-fail report. Wired into `/harness-review` Check 11 (next available slot after acceptance-loop-self-test).

## Files to Modify/Create

**Create:**
- `docs/decisions/012-agent-teams-integration.md` — decision record
- `adapters/claude-code/hooks/teammate-spawn-validator.sh` — Task 5
- `adapters/claude-code/hooks/task-created-validator.sh` — Task 7
- `adapters/claude-code/hooks/task-completed-evidence-gate.sh` — Task 8
- `adapters/claude-code/rules/agent-teams.md` — Task 11
- `adapters/claude-code/examples/agent-teams.config.example.json` — Task 4
- `adapters/claude-code/schemas/agent-teams.config.schema.json` — Task 4
- `adapters/claude-code/templates/decision-log-entry.md` — Task 2 (copy)
- `adapters/claude-code/templates/completion-report.md` — Task 2 (copy)
- `adapters/claude-code/tests/agent-teams-self-test.sh` — Task 14

**Modify:**
- `adapters/claude-code/hooks/tool-call-budget.sh` — Task 6
- `adapters/claude-code/hooks/plan-edit-validator.sh` — Task 9
- `adapters/claude-code/hooks/product-acceptance-gate.sh` — Task 10
- `adapters/claude-code/settings.json` — Task 5, 7, 8 (wire new hooks)
- `adapters/claude-code/rules/acceptance-scenarios.md` — Task 3, 10
- `adapters/claude-code/rules/planning.md` — Task 12
- `adapters/claude-code/rules/orchestrator-pattern.md` — Task 12
- `adapters/claude-code/rules/automation-modes.md` — Task 13
- `adapters/claude-code/templates/plan-template.md` — Task 12
- `adapters/claude-code/skills/harness-review.md` — Task 14 (add Check 11)
- `docs/harness-architecture.md` — Task 13
- `README.md` — Task 13
- `docs/harness-guide.md` — Task 4
- `docs/DECISIONS.md` — Task 1 (add row pointing at 012)
- `docs/backlog.md` — Task 1 (mark HARNESS-DRIFT-03 + 04 as absorbed)

## Assumptions

- **Anthropic's TaskCreated and TaskCompleted hook events DO fire as documented.** The Anthropic docs claim these events fire reliably. Empirical confirmation deferred to Task 14 self-test (with mocked input). If runtime testing reveals the events don't fire, Tasks 7 and 8 are blocked and the plan moves to DEFERRED until Anthropic ships the fix.

- **`session_id` in `~/.claude/teams/<team>/config.json` is queryable.** The team config is supposed to include a `members` array with each teammate's session_id. Anthropic's docs are silent on the exact schema. If the schema doesn't expose session_ids, Task 6 (team-aware budget) needs an alternative attribution mechanism — possibly via TaskCreated event capture instead.

- **`flock(1)` is available in the bash environment** on all supported platforms (Linux, macOS, Windows Git Bash). On Windows Git Bash, `flock` is provided by msys2; verify before Task 9. If flock unavailable, fallback to a PID-keyed lock file with mtime-based timeout (less robust but compatible).

- **`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag honors the same precedence as other settings.json values** (project overrides user, user overrides default). The agent-teams docs don't explicitly say. If the flag has different precedence, the feature-flag mechanism in Task 4 needs adjustment.

- **The `Agent` tool's `team_name` parameter is observable in the tool call's input JSON** at PreToolUse time. If it's not (the parameter is internal), Task 5 needs an alternative discrimination — possibly inferring from the spawned agent's `subagent_type` value or by listing teammates via `~/.claude/teams/`.

- **Pane-based teammate sessions DO load the project's `~/.claude/settings.json` independently.** Per #24175 source-level analysis, this is the case. If they don't, hooks declared in user settings won't fire for pane-based teammates and the integration's safety guarantees are weaker on macOS+tmux.

- **`docs/plans/<slug>-evidence.md` companion files persist across worktrees in a way that the lead can read.** This requires either (a) evidence files committed to the branch (current default) or (b) a known shared location. Task 8 assumes (a). If teammates write evidence in their own worktree and don't push, the evidence is invisible to lead-side gates until the worktree is merged.

## Edge Cases

- **Solo session (no team)** — every new hook must fall back to existing single-session behavior. Confirmed by self-test scenario in each hook.

- **Lead crashes mid-session, teammates orphaned** — orphaned teammates may continue spawning Edit/Write hooks against their own state directories. Their plan-edit-validator races become moot since the lead's plan is no longer being verified. Cleanup is per teammate-self-cleanup; flock timeouts mean stale locks self-clear after 30s.

- **Two teams running concurrently on the same machine for different projects** — each team has its own `~/.claude/teams/<team-A>/` and `<team-B>/`. Counter scope is per-team_name; the `effective_session_id` derivation in Task 6 returns the correct team for the firing session. No cross-contamination expected.

- **Two teams running concurrently on the same project** — flock-on-`<plan>.lock` covers concurrent verification. Two team leads could still race on creating new plans; this is out of scope and falls back to existing single-session behavior.

- **Teammate spawns same `Agent` tool with `subagent_type` of a write-capable agent (e.g., `task-verifier`)** — task-verifier is a sub-sub-agent; per Anthropic docs, "no nested teams" so this scenario fails at Anthropic's layer. Task 5 doesn't need to gate it, but the validator's self-test should confirm Anthropic's rejection is visible to the user.

- **Pre-existing tool-call counters from before the team-aware migration** — `~/.claude/state/tool-call-count.*` files older than 24h are auto-cleaned by `tool-call-budget.sh` (existing behavior). New keys (team_name strings) coexist with old session_id strings; no migration needed.

- **`team_name` containing special characters** — keys go directly into a filename. Validator/normalizer at Task 6 strips non-alphanumeric characters and applies a length cap of 64 chars. Reject team names with disallowed characters at TaskCreated time (Task 7).

- **Decision 011 Approach A teammate inherits project `.claude/` only — does it see the new hooks?** Yes if the project `.claude/` is populated from the adapter (per Decision 011's solo-dev symlink path or team-shared committed-copy path). The integration plan's hooks land in `adapters/claude-code/hooks/` and propagate via existing sync flow.

## Acceptance Scenarios

This plan is `acceptance-exempt: true` per the header. Per-task runtime verification specs (in Testing Strategy) substitute for `## Acceptance Scenarios` runtime PASS artifacts.

## Out-of-scope scenarios

This plan is `acceptance-exempt: true`.

## Testing Strategy

Per task, runtime-verifiable specifications:

**Task 1 (decision record):** verify `docs/decisions/012-agent-teams-integration.md` exists with required schema fields, `docs/DECISIONS.md` row added, decisions-index-gate passes pre-commit (`git commit` succeeds without exit 2 from gate).

**Task 2 (templates parity):**
- `diff -q ~/.claude/templates/decision-log-entry.md adapters/claude-code/templates/decision-log-entry.md` returns 0
- Same for completion-report.md
- `harness-hygiene-scan.sh --full-tree` passes (templates contain no personal identifiers)

**Task 3 (Stop chain doc):** `grep -c '^[0-9]\.' rules/acceptance-scenarios.md | grep '5'` (the chain list now numbers 5 positions). Manually compare against `settings.json:235-260` to confirm match.

**Task 4 (feature flag config):** schema validates against the example file using `ajv` (or jq schema validator if ajv unavailable). Documented field defaults match what hooks expect.

**Task 5 (teammate-spawn-validator):**
```bash
adapters/claude-code/hooks/teammate-spawn-validator.sh --self-test
# Expected: 6/6 PASS, exit 0
```
6 scenarios: enabled-flag-respected, worktree-mandatory-blocks-without-isolation, dangerously-skip-blocks-when-force-in-process, allows-read-only-spawn, allows-when-config-missing, allows-when-not-team-context.

**Task 6 (tool-call-budget team-aware):**
```bash
adapters/claude-code/hooks/tool-call-budget.sh --self-test
# Expected: existing 8 scenarios pass + 4 new scenarios pass = 12/12
```
4 new scenarios: solo-session-falls-back-to-session-id, team-member-uses-team-name, non-member-uses-session-id, flock-serializes-concurrent-increments.

**Task 7 (task-created-validator):**
```bash
adapters/claude-code/hooks/task-created-validator.sh --self-test
# Expected: 4/4 PASS
```
4 scenarios: rejects-no-plan-reference, rejects-no-acceptance-criteria, allows-fully-specified, allows-with-bypass-flag.

**Task 8 (task-completed-evidence-gate):**
```bash
adapters/claude-code/hooks/task-completed-evidence-gate.sh --self-test
# Expected: 4/4 PASS
```
4 scenarios: rejects-missing-evidence, allows-evidence-present, allows-explicit-bypass, handles-missing-task-id-gracefully.

**Task 9 (plan-edit-validator flock):**
```bash
adapters/claude-code/hooks/plan-edit-validator.sh --self-test
# Expected: existing scenarios + 4 new = total scenarios pass
```
4 new scenarios: single-writer-baseline, two-writer-serialization, lock-timeout-after-30s, lock-cleanup-after-process-exit.

**Task 10 (acceptance-gate worktree aggregation):**
```bash
adapters/claude-code/hooks/product-acceptance-gate.sh --self-test
# Expected: existing 8 scenarios + 2 new = 10/10
```
2 new scenarios: aggregates-across-worktrees, returns-PASS-when-any-worktree-has-valid-artifact.

**Task 11 (rules/agent-teams.md):** content review against `docs/reviews/2026-04-27-agent-teams-conflict-analysis.md` — verifies all 6 design decisions are documented + 5 hard blocker workarounds + 4 upstream-issue workarounds.

**Task 12 (plan template):** `plan-reviewer.sh --self-test` continues to pass (the new value `agent-team` is recognized; old value `orchestrator` still works).

**Task 13 (documentation):**
- `grep -l 'Agent Teams' docs/harness-architecture.md` returns the file
- `grep -l 'Agent Teams' README.md` returns the file
- `grep -l 'Agent Teams' rules/automation-modes.md` returns the file

**Task 14 (integration self-test):**
```bash
adapters/claude-code/tests/agent-teams-self-test.sh
# Expected: all sub-suites green, exit 0
```

## Walking Skeleton

Day 1: Tasks 1, 2, 3, 4 (decision record, templates, doc fix, config schema). Lands as one PR — pure documentation + structural setup, no behavior change. Confirms the team-shared filesystem state is correct for the rest of the plan.

Day 2: Task 5 (spawn validator) + Task 6 (budget team-awareness). Two new mechanisms with clear self-tests. Land separately if independent.

Day 3: Tasks 7-10 (TaskCreated/Completed gates + plan-edit flock + acceptance-gate worktree aggregation). The four hardest tasks; each has a substantial self-test. Land in one PR if cohesive, separate if not.

Day 4: Tasks 11-14 (new rule, plan template + rule edits, documentation, integration self-test). Land as one PR.

Each day's PR is independently revertible. The walking skeleton goal: at end of Day 1, harness drift fixed and config schema in place; at end of Day 2, basic guardrails in place; at end of Day 3, all hard blockers resolved; at end of Day 4, integration documented and tested. Enable Agent Teams flag in a Day 5 follow-up session.

## Decisions Log

### Decision: Tool-call budget scope + audit cadence (revised 2026-04-27)
- **Tier:** 2
- **Status:** APPROVED by user 2026-04-27 (initial per-team scope confirmed; refined to deferred-audit-on-TaskCompleted with hard ceiling)
- **Chosen:**
  - **Scope:** per-team (counter keyed by `team_name` resolved from `session_id` membership in `~/.claude/teams/<team>/config.json`); falls back to per-session for solo sessions
  - **Audit cadence in agent-team mode:** at call 30, set a flag at `~/.claude/state/audit-pending.<team>` instead of blocking. TaskCompleted hook reads the flag and runs `plan-evidence-reviewer` before allowing the task to complete. PASS → flag cleared, counter reset. FAIL → TaskCompleted blocked, findings must be addressed.
  - **Hard ceiling at call 90:** if a single teammate accumulates 90+ calls without an intervening TaskCompleted, fall back to mid-stream block. Catches runaway-task drift while leaving normal-length tasks uninterrupted.
  - **Audit cadence in solo mode:** unchanged — 30-call mid-stream block as today. The original single-builder calibration stays intact.
- **Alternatives:**
  - Per-session (status quo extended): per-teammate-multiplied; 5 teammates × 30 = 150 calls before audit, six times the calibrated cadence
  - Per-team with mid-stream block at 30: maps to original gate intent but disrupts team coordination
  - Per-team with deferred audit only (no hard ceiling): elegant but lets drift compound across long tasks
  - Per-machine / per-user: cross-pollination across unrelated work; predictability erodes
- **Reasoning:** team is the natural unit of cumulative work. Mid-stream blocking in a team disrupts coordination across teammates. Deferring to TaskCompleted matches the natural task-completion checkpoint while giving audits more context. The hard ceiling at 90 preserves the original "drift detection" property for tasks that grow long.
- **To reverse:** rewrite Task 6 to use mid-stream blocking at 30 (the original simpler behavior). All other changes contained within Task 6.

### Decision: teammateMode default
- **Tier:** 2
- **Status:** APPROVED by user 2026-04-27 (user requested recommendation; recommendation accepted)
- **Chosen:** force `teammateMode: in-process` via feature flag default until #24175 is fixed upstream
- **Alternatives:**
  - Default `auto`: silently drops `SubagentStart`/`Stop`/`TeammateIdle`/`TaskCompleted` at parent on macOS+tmux
  - Always pane-based: never in-process; loses lead-process visibility into teammates entirely
- **Reasoning:** in-process gives reliable hook firing at the cost of caps on parallelism. Reliability is the load-bearing property of a harness. For Windows users, no practical impact (pane-based requires tmux/iTerm2 which Windows Git Bash lacks; auto already chooses in-process). Safety belt for future macOS / cloud-Linux scenarios.
- **To reverse:** flip `force_in_process: false` in `~/.claude/local/agent-teams.config.json`. User-controllable per machine. Teammate hooks still fire from teammate's own settings, only parent-visibility events drop.

### Decision: Worktree-mandatory for write-capable teammates
- **Tier:** 2
- **Status:** APPROVED by user 2026-04-27 ("Yeah, I think that's a good idea")
- **Chosen:** yes, enforced via Task 5 spawn validator
- **Alternatives:**
  - Optional (warning only): teammates without worktrees race on filesystem
  - Worktree always (read-only too): unnecessary complexity for read-only spawns
- **Reasoning:** write-capable teammates without worktrees produce filesystem races at non-negligible rates per orchestrator-pattern history. Read-only teammates don't need worktrees.
- **To reverse:** flip `worktree_mandatory_for_write: false` in config.

### Decision: TaskCreated/TaskCompleted hooks as new enforcement surface
- **Tier:** 2
- **Status:** APPROVED by user 2026-04-27 ("Sure, that sounds like a good idea")
- **Chosen:** yes, add Tasks 7 and 8 as new mechanisms
- **Alternatives:**
  - Per-Edit gating only (status quo extended): less granular, can't enforce team-aggregate concerns
  - Defer to Phase 2: ships agent-teams without team-task-aware enforcement
- **Reasoning:** TaskCreated/Completed provide team-attributable enforcement (`teammate_name`/`team_name` ARE in event input per #39101 resolved). Per-Edit hooks lack this attribution per #45329.
- **To reverse:** disable both hooks in settings.json. Plan integrity falls back to per-Edit.

### Decision: Acceptance loop in team mode — lead-aggregate
- **Tier:** 2
- **Status:** APPROVED by user 2026-04-27 ("team-level outcome (recommended)")
- **Chosen:** lead's runtime end-user-advocate covers team-level outcome; per-teammate work is validated by lead-invoked task-verifier
- **Alternatives:**
  - Per-teammate scenarios: each teammate runs its own advocate against its own scenario subset
  - Lead AND per-teammate: maximum coverage, multiplied infrastructure
- **Reasoning:** scenarios are per-plan, plans are per-team in agent-team mode. The advocate's adversarial-observation discipline is unchanged. Per-teammate scenarios introduce coordination overhead that doesn't add detection power for team-level outcomes.
- **To reverse:** add a `per-teammate-scenarios: true` field to the plan template; advocate iterates per teammate. Implementation in a future plan.

### Decision: Feature flag for safe rollout
- **Tier:** 2
- **Status:** APPROVED by user 2026-04-27 (user requested explanation; explanation accepted, recommendation locked)
- **Chosen:** yes — `~/.claude/local/agent-teams.config.json` with `enabled: false` default
- **Alternatives:**
  - Always enabled: high upstream-bug density (#50779, #24175, #24073, #24307, #45329) makes silent breakage likely
  - Always disabled: integration provides no value
- **Reasoning:** safe-by-default with explicit opt-in. Same pattern as the existing public-repo block, force-push block, and `--no-verify` block: dangerous-by-default behaviors that are fine if the user knows what they're doing. Re-evaluate the default once Anthropic resolves #50779 and #24175.
- **To reverse:** flip `enabled` field. Reversible per session.

## Definition of Done

- [ ] All 14 tasks checked off (by task-verifier — not self-reported)
- [ ] All hook self-tests passing (each hook's `--self-test` returns 0 on its full scenario count)
- [ ] `tests/agent-teams-self-test.sh` returns 0
- [ ] Harness-hygiene scan passes on the full tree (`harness-hygiene-scan.sh --full-tree` returns 0)
- [ ] Plan-reviewer passes on this plan file (`plan-reviewer.sh` exit 0)
- [ ] Decision 012 record exists at `docs/decisions/012-agent-teams-integration.md` and `docs/DECISIONS.md` references it
- [ ] `docs/harness-architecture.md`, `README.md`, `rules/automation-modes.md` reference Agent Teams support
- [ ] SCRATCHPAD.md updated to reflect plan completion
- [ ] Backlog items HARNESS-DRIFT-03 and HARNESS-DRIFT-04 moved from open list to Completed (with commit SHAs)
- [ ] Completion report appended per `templates/completion-report.md`

## Decisions Log
[Populated above — six decisions resolved with recommended defaults; user can override any in plan review]
