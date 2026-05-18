# Findings ledger

This file records class-aware observations made by gates, adversarial-review agents, and builders during work on Neural Lace itself. Per Decision 019 (`docs/decisions/019-findings-ledger-format.md`), every entry follows the six-field schema. The schema gate (`adapters/claude-code/hooks/findings-ledger-schema-gate.sh`) validates each entry on commit; the rule documenting when and how to write entries is `adapters/claude-code/rules/findings-ledger.md`; the canonical template is `adapters/claude-code/templates/findings-template.md`.

## Schema specification

| Field | Required | Type | Valid values |
|---|---|---|---|
| `ID` | Yes | string | Project-prefixed kebab-case identifier (e.g., `NL-FINDING-001`). Unique within `docs/findings.md`. |
| `Severity` | Yes | enum | `info`, `warn`, `error`, `severe` |
| `Scope` | Yes | enum | `unit`, `spec`, `canon`, `cross-repo` |
| `Source` | Yes | string | Names which gate / agent / role surfaced the entry. |
| `Location` | Yes | string | `file:line` reference, artifact path, or `n/a` if process-shaped. |
| `Status` | Yes | enum | `open`, `in-progress`, `dispositioned-act`, `dispositioned-defer`, `dispositioned-accept`, `closed` |

The `Description` body field is required substantive content explaining the observation in enough detail that a future-session reader can understand it without re-deriving the context.

## Entries

### NL-FINDING-001 — plan-reviewer.sh Check 1 + Check 7 false-positives on meta-plans

- **Severity:** warn
- **Scope:** unit
- **Source:** orchestrator (manual observation during Phase 1d-C-2 plan-review pass; corroborated by Phase 1d-C-2 plan-builder return)
- **Location:** adapters/claude-code/hooks/plan-reviewer.sh — Check 1 (undecomposed sweep regex on Definition of Done plural language) and Check 7 (design-mode shallowness regex on legitimate concise sections)
- **Status:** dispositioned-defer
- **Description:** When plan-reviewer.sh runs against meta-plans (plans about the harness itself, not project features), Check 1 trips on plural language in `## Definition of Done` ("all scenarios", "every task") and Check 7 trips on the word `table` in design-mode sections referring to Markdown tables rather than database tables. Workaround: rephrase plan content to avoid the regex hits. Mitigation deferred per HARNESS-GAP-09 (P3 — workaround is trivial; not blocking). To act: tighten the Check 1 regex to NOT fire on lines under `## Definition of Done`, and Check 5 regex to be context-aware (database-context vs documentation-context). Estimated effort: ~30 minutes.

### NL-FINDING-002 — Sub-agent background tasks and polling loops leak past sub-agent completion

- **Severity:** warn
- **Scope:** unit
- **Source:** orchestrator (observed 2026-05-04 in this session arc; user surfaced via UI screenshot of ~21 "Running" tasks; OS-level confirmation via `ps -ef`)
- **Location:** Pattern, not a single file. Affects any sub-agent that uses Bash `run_in_background: true` or Monitor. Cleanup gap is in Claude Code's task-state machine, not in user code.
- **Status:** open
- **Description:** During this session arc, sub-agents (plan-phase-builders + task-verifiers + audit agents) spawned background bash tasks for self-tests, polling loops (`until ...; do sleep 5; done`), and CI-watch invocations. After each sub-agent returned, two distinct leak patterns observed: (1) **OS-level zombies** — at least one `until` polling loop on `gh pr checks 3` was found alive 15 hours past its parent sub-agent's completion (PID 475, killed manually). (2) **Task-tracker zombies** — the Claude Code task panel showed ~21 "Running" entries while OS-level `ps` showed only 1 actual process. Most "Running" entries had no corresponding OS process; their tracking metadata was stale, not their underlying work. Practical effects: (a) genuinely-stuck `until` loops poll forever (one cycle per 5 seconds is ~17K cycles in 24 hours; cumulatively wastes CPU + API quota for `gh` calls), (b) the task panel becomes unreadable as zombie entries accumulate session-arc-over-session-arc, and (c) future sub-agents and the `bug-persistence-gate.sh` may misinterpret zombie task records as in-flight work. Mitigation candidates: (i) sub-agents should explicitly `TaskStop` any background tasks they spawn before returning (rule + builder-prompt update), (ii) Claude Code's task tracker should auto-transition tasks whose owning sub-agent has terminated (upstream change), (iii) periodic OS-level sweep of zombie polling loops as a SessionStart housekeeping hook (mechanism). Cross-reference: `~/.claude/rules/orchestrator-pattern.md` (parallel-builder protocol — does not currently document the cleanup obligation).

### NL-FINDING-003 — automation-mode-gate.sh resolves project config only from $PWD/.claude, blinding worktrees branched before the config commit (HARNESS-GAP-37)

- **Severity:** warn
- **Scope:** unit
- **Source:** orchestrator (operator-directed harness-friction triage, 2026-05-17 — GAP-2)
- **Location:** adapters/claude-code/hooks/automation-mode-gate.sh (config resolution in `_run_gate`, formerly only `$PWD/.claude/automation-mode.json`)
- **Status:** closed
- **Description:** `automation-mode-gate.sh` resolved the per-project automation mode solely from `$PWD/.claude/automation-mode.json`. A git worktree whose branch was created from a master that PREDATES the project's `full-auto` config commit has no such file in its own working tree, so the probe missed and the gate silently fell back to the user-global `review-before-deploy` default — then correctly-but-confusingly BLOCKED deploy-class Bash commands (`git push`, `gh pr merge`, `vercel deploy`) in a project that IS configured `full-auto`. Every Dispatch worktree of a `full-auto` project that branched before the config landed paid this friction. Fix: when the `$PWD/.claude/` probe misses AND the cwd is a git worktree (`git --git-dir` ≠ `--git-common-dir`), resolve the parent checkout via `dirname(git-common-dir)` and read its committed-and-checked-out `.claude/automation-mode.json` — the same parent-resolution ADR 028 applied to `session-wrap.sh`'s SCRATCHPAD lookup. The parent checkout is the canonical project root and carries the config regardless of how old the worktree branch is. Verified by a new self-test Scenario 5 (positive: PASS from a worktree branched pre-config because the parent's full-auto is resolved; negative control: BLOCK once the parent config is removed, proving the PASS came from the fallback). 5/5 self-test scenarios PASS; mirror synced byte-identical.

### NL-FINDING-004 — session-wrap.sh tracked-file freshness signals read the parent checkout, structurally unclearable from a worktree (HARNESS-GAP-38)

- **Severity:** warn
- **Scope:** unit
- **Source:** orchestrator (operator-directed harness-friction triage, 2026-05-17 — GAP-3)
- **Location:** adapters/claude-code/scripts/session-wrap.sh (`cmd_verify` Signals 3/4/5 + `plans_touched_this_session`, formerly all keyed to `find_repo_root` = parent)
- **Status:** closed
- **Description:** `session-wrap.sh`'s `find_repo_root()` resolves to the PARENT repo when run from a worktree (ADR 028 — correct for SCRATCHPAD, which is gitignored ephemeral state, one per repo). But Signals 3 (roadmap), 4 (discoveries) and 5 (backlog) read TRACKED, version-controlled files that a worktree session legitimately edits in its OWN worktree and ships via PR; the parent checkout's copy is correctly untouched until that PR merges. Reading the parent's copy made the agent's correct action (edit the worktree copy, open a PR) structurally unable to clear the freshness signal — the check reads the other checkout. Fix: added `find_worktree_root()` (returns `git rev-parse --show-toplevel` = the worktree's own toplevel, or the repo root when not a worktree); `cmd_verify`/`cmd_refresh` now take an optional second `wt_repo` arg (defaults to `repo` so direct callers and non-worktree sessions are byte-for-byte unchanged); the tracked-file signals + `plans_touched_this_session` read `wt_repo`, SCRATCHPAD signals keep reading the parent. New self-test S9a (worktree's fresh backlog → PASS, proving the fix) + S9b (genuinely stale worktree backlog → STALE, proving the fix does NOT mask real staleness — it just reads the right copy). S1–S8 unchanged (no regression); 10/10 PASS; mirror synced. **Boundary:** this is orthogonal to and does NOT resolve the still-pending discovery `2026-05-17-session-wrap-signal3-transitive-false-fire.md` — that is a separate root cause (the global 4h `--since` window mis-attributes WHICH COMMITS count) awaiting Misha's decision; this finding fixes WHICH CHECKOUT's copy is read. The two compose cleanly.

### NL-FINDING-005 — chronic per-session acceptance waivers on a stale unstarted ACTIVE plan (downstream-project instance) (HARNESS-GAP-36)

- **Severity:** warn
- **Scope:** cross-repo
- **Source:** orchestrator (operator-directed harness-friction triage, 2026-05-17 — GAP-1)
- **Location:** a downstream pre-customer project — `docs/plans/prd-v1.1-and-audit-resolution.md` (Status: ACTIVE, 0/7 tasks); ~5 acceptance waivers on 2026-05-17
- **Status:** dispositioned-act
- **Description:** Diagnosis (per the operator's GAP-1 ask: incomplete vs complete-but-not-flipped vs gate-over-firing): **genuinely incomplete**. The plan was filed 2026-05-14 ("file PRD-v1.1 resolution plan") but never started — all 7 task checkboxes `- [ ]`, Evidence Log empty, no completion report, every Definition-of-Done item unchecked, and Task 5's partial-UNIQUE-index migration is absent from the project's migrations dir. `product-acceptance-gate.sh` is therefore firing CORRECTLY (a real, unstarted, non-exempt `Status: ACTIVE` plan with no PASS artifact); the per-session waivers are the CORRECT behavior for unrelated sessions. The defect is not the gate — it is that real product work sat unstarted for 3 days while every session in that project paid the waiver tax (its SCRATCHPAD itself notes "11 stale Status: ACTIVE plans force per-session acceptance waivers"). Resolution (operator pre-authorized "if incomplete: spawn the dedicated session"): a dedicated downstream build session was spawned via `mcp__ccd_session__spawn_task` to drive all 7 tasks to task-verifier PASS + flip `Status: COMPLETED` (which stops the waiver tax at its root). **This is a downstream-project instance of the harness-wide plan-staleness class already tracked by HARNESS-GAP-29/30/31** (DoD-saturation surfacer, all-checked-but-ACTIVE detector, waiver-density alarm). The broader observation (≥11 stale ACTIVE plans in that project) is the GAP-29/30/31 aggregation gap manifesting concretely, not a new class — recorded here as the trigger instance; the systemic fix remains GAP-29/30/31.
