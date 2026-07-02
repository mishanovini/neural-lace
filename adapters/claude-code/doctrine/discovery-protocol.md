# Discovery Protocol — compact
> Enforcement: discovery-surfacer.sh (SessionStart, surfaces pending discoveries), bug-persistence-gate.sh (Stop, accepts discovery files as durable capture). Full: doctrine/discovery-protocol-full.md
> Applies: proactive mid-process learnings — not bug-shaped, not yet a decision.

- Files at `docs/discoveries/YYYY-MM-DD-<slug>.md`. Seven types: `architectural-learning`, `scope-expansion`, `dependency-surprise`, `performance`, `failure-mode`, `process`, `user-experience`.
- Frontmatter: `title`, `date`, `type`, `status` (`pending` | `decided` | `implemented` | `rejected` | `superseded`), `auto_applied`, `originating_context`, `decision_needed`, `predicted_downstream`.
- Body: What was discovered / Why it matters / Options / Recommendation / Decision / Implementation log.
- Decide-and-apply discipline: lay out options + recommendation + reasoning; if the decision is **reversible** (single revert undoes it), auto-apply and mark `status: decided, auto_applied: true`; if **irreversible** (force-push, master push, schema/prod-data change, new recurring cost, cross-project propagation), pause and surface options+recommendation to the user, wait for explicit call.
- `docs/discoveries/` with `status: pending` surfaces at every SessionStart via `discovery-surfacer.sh`; silent when nothing pending or the directory doesn't exist.
- Propagation per type: architectural-learning/performance -> new ADR; scope-expansion/dependency-surprise -> plan edit; failure-mode -> `docs/failure-modes.md` entry; process -> `docs/backlog.md` HARNESS-GAP; user-experience -> plan's `## Acceptance Scenarios`.
- Educational surfacing format for substantive decisions: what happened, options with cost/benefit, your recommendation + the principle behind it, tradeoff acknowledgment, what changes on redirect.
