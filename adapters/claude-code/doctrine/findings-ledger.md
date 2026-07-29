# Findings Ledger — compact
> Enforcement: findings-ledger-schema-gate.sh (precommit, schema shape), bug-persistence-gate.sh (Stop, accepts as durable capture), stop-verdict-dispatcher.sh's `problems-persist` WARN check (Stop, teaches — never blocks). Full: doctrine/findings-ledger-full.md
> Applies: any class-aware observation from a gate, an adversarial-review agent, or a builder mid-task.

- Single canonical ledger per project at `docs/findings.md`. Class-aware observations — not open work (that's the backlog), not a point-in-time pass (that's `docs/reviews/`), not a decision-needing realization (that's `docs/discoveries/`).
- Six required fields per entry, schema-locked:
  1. `ID` — project-prefixed kebab identifier, unique in the file.
  2. `Severity` — `info` | `warn` | `error` | `severe`.
  3. `Scope` — `unit` | `spec` | `canon` | `cross-repo`.
  4. `Source` — which gate/agent/role surfaced it.
  5. `Location` — `file:line`, artifact path, or `n/a`.
  6. `Status` — `open` | `in-progress` | `dispositioned-act` | `dispositioned-defer` | `dispositioned-accept` | `closed`.
- Plus a substantive `Description` body.
- Lifecycle: `open` -> `in-progress` -> `dispositioned-act`/`dispositioned-defer`/`dispositioned-accept` -> `closed`. Not strictly linear — a deferred entry can return to `in-progress`.
- Write the entry as soon as the observation is recognized, not batched at session end. Every entity with epistemic authority writes: gates, review agents, the orchestrator, builders discovering sibling regressions.
- `findings-ledger-schema-gate.sh` blocks a commit that touches `docs/findings.md` if any entry is missing a field, uses an out-of-enum value, or has a duplicate ID.

## Inline ledger IDs (operator directive 2026-07-29, `SURFACED-PROBLEMS-CAN-BE-DROPPED-01`)

Filing a finding is discretionary — nothing mechanically forced it, so the ledger reflected
what a session remembered to file, not what it found. Fix, three parts (`docs/decisions/065-
problems-persist-warn-consolidation.md`):

1. **Every problem statement in operator-facing chat carries its ledger ID inline** —
   `NL-FINDING-###` (this ledger), `NL-ISSUE-###` (the `<n>` from `nl-issue.sh --list`, the
   cross-project friction ledger), or the row's own ALL-CAPS-kebab slug (e.g.
   `SURFACED-PROBLEMS-CAN-BE-DROPPED-01`). A problem statement with no ID next to it is
   itself the visible defect — the operator can see at read time that it was never filed,
   without auditing anything.
2. **Stop-time teaching check**: `stop-verdict-dispatcher.sh`'s `problems-persist` check
   (WARN-only, never blocks — see its header comment for the golden scenario / FP estimate /
   retirement condition constitution §10 requires) scans the final assistant message,
   paragraph by paragraph, for problem-shaped vocabulary (defect/bug/broken/silently/data
   loss/root cause) with no ID-shaped token in the same paragraph, and warns with an exact
   `nl-issue.sh "..."` command pre-filled.
3. **Operator-named problems auto-file themselves**: `workstreams-read.sh`'s
   `_problem_capture_on_prompt` splice (UserPromptSubmit) recognizes operator prompts naming a
   problem ("why is/why are/broken/failing/critical problem") and files a candidate row via
   `nl-issue.sh` tagged `source: operator-verbatim` — exempted from the normal 24h dedup fold
   so an operator complaint can never be silently absorbed into someone else's count bump.
