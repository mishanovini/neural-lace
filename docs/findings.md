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
