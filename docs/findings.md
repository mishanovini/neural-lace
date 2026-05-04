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
