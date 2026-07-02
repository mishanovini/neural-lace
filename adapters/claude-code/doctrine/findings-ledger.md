# Findings Ledger — compact
> Enforcement: findings-ledger-schema-gate.sh (precommit, schema shape), bug-persistence-gate.sh (Stop, accepts as durable capture). Full: doctrine/findings-ledger-full.md
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
