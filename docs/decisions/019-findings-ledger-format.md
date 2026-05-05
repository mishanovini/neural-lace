# Decision 019 — Findings-ledger format (C9): 6-field schema, single `docs/findings.md` per project, dispositioning lifecycle

**Date:** 2026-05-04
**Status:** Active
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/phase-1d-c-3-findings-ledger.md` (Status: ACTIVE)
**Related Build Doctrine source:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 C9 + §9 Q5-A

## Context

Build Doctrine §6 C9 specifies a findings-ledger gate: a durable, structured surface where every gate, every adversarial-review agent, and every builder records class-aware observations as the work progresses. The motivation: today's harness has multiple substrates for capturing observed gaps — `docs/backlog.md` (open work), `docs/reviews/YYYY-MM-DD-*.md` (review-pass outputs), `docs/discoveries/YYYY-MM-DD-*.md` (mid-process learnings), and project-internal commit messages — but no single surface where a future-session reader can scan "what has the harness observed about itself, with what severity, in what scope, in what status." C13 (promotion/demotion gate) and Phase 1d-G (calibration-mimicry) both READ this ledger as their substrate; without C9, neither can land.

Two implementation details require explicit decisions before C9 can be built:

1. **Schema shape.** Build Doctrine §6 C9 mentions a "suggested action" field as a possible 7th column, but §9 Q5-A's Recommended option (which is what the user locked in earlier) is 6 fields, not 7. The two specifications disagree; choose one before authoring the gate.
2. **File-layout convention.** Discoveries use one file per discovery (`docs/discoveries/YYYY-MM-DD-<slug>.md`); reviews use one file per review (`docs/reviews/YYYY-MM-DD-<slug>.md`); backlog uses a single file (`docs/backlog.md`). Findings could go either way; pick the convention before the gate's diff-validator is wired.

Without (1), the gate cannot validate against an enum-locked schema. Without (2), tooling (C13, calibration-mimicry, future automated dispositioners) cannot agree on where to read findings from.

## Decision

### Decision 019a — Six-field schema, locked

Every entry in `docs/findings.md` declares exactly six fields. The §6 mention of "suggested action" as a 7th field is treated as imprecise prose; the §9 Q5-A Recommended option is the authoritative lock.

| Field | Required | Type | Valid values |
|---|---|---|---|
| `id` | Yes | string | Project-prefixed kebab-case identifier (e.g., `NL-FINDING-001`). Unique within `docs/findings.md`. |
| `severity` | Yes | enum | `info`, `warn`, `error`, `severe` |
| `scope` | Yes | enum | `unit`, `spec`, `canon`, `cross-repo` |
| `source` | Yes | string | Names which gate / agent / role surfaced the finding (e.g., `harness-reviewer`, `prd-validity-reviewer`, `orchestrator`). |
| `location` | Yes | string | `file:line` reference, an artifact path, or `n/a` if the finding is process-shaped rather than artifact-shaped. |
| `status` | Yes | enum | `open`, `in-progress`, `dispositioned-act`, `dispositioned-defer`, `dispositioned-accept`, `closed` |

The `severity` enum is severity-ordered: `info < warn < error < severe`. The `scope` enum is breadth-ordered: `unit` (one file or hook) < `spec` (one plan or PRD) < `canon` (rule, doctrine, decision-record-level) < `cross-repo` (touches more than one repo or downstream consumer).

The `status` enum encodes the dispositioning lifecycle (Decision 019c). Out-of-range values FAIL `findings-ledger-schema-gate.sh` Check 0 with a message naming the offending field, the offending value, and the valid set.

### Decision 019b — Single `docs/findings.md` per project (NOT per-finding files)

Every project covered by C9 maintains exactly **one** findings file at `docs/findings.md` (repo-relative). All findings — across every gate, every agent, every severity, every scope — live in this one file. Sub-categorization within the file (sections per source / severity / status) is allowed but not required.

Rationale: findings are typically 5-30 lines each, reference each other frequently (a `dispositioned-defer` may link to a future `act`-class sibling), and benefit from a single readable surface. One file matches the precedent set by Decision 015 (single PRD per project) and contrasts with the discovery-protocol convention (many files per directory) which suits longer, decision-shaped artifacts. Findings are observations; observations should be cheap to scan.

### Decision 019c — Dispositioning lifecycle: open → in-progress → dispositioned-* → closed

A finding moves through these states:

- **`open`** — the finding has been recorded but no action has been taken. The default initial status when an agent or gate writes the finding.
- **`in-progress`** — work is actively underway to resolve the finding. The author of the work flips the status to indicate they have picked it up.
- **`dispositioned-act`** — the team has decided to act on the finding (a fix is planned or in flight). Captures the decision; the actual fix may land in this commit, the next, or a subsequent plan.
- **`dispositioned-defer`** — the team has decided not to act now (intentionally deferred). The finding remains in the ledger as the audit trail; "we know about it, we chose not to act."
- **`dispositioned-accept`** — the team has decided the finding describes acceptable behavior. Closes the finding without a fix; the audit trail records why the team accepts the trade-off.
- **`closed`** — the finding is fully resolved. For an `act`-class finding, this is reached when the fix has shipped and verification passed. For a `defer`-class finding, this is reached when a future session decides to act and the action lands. For an `accept`-class finding, this is reached when the acceptance has been captured in the audit trail.

Transitions are not strictly linear: a `dispositioned-defer` finding may flip to `in-progress` when a future session picks it up, then to `closed` when the fix lands. The schema gate validates the field is in the enum; it does NOT enforce transition order. Order is Pattern-level discipline.

Substantive lifecycle examples live in the rule (`adapters/claude-code/rules/findings-ledger.md`).

## Alternatives considered

- **Seven-field schema with a "suggested action" column (Build Doctrine §6 prose).** Rejected per Decision 019a. Two reasons: (a) §9 Q5-A's Recommended option is six fields, presented as the user's locked choice; the §9 lock wins when sources disagree. (b) "Suggested action" as a structured field forces every finding to propose a remedy at write time, which is premature for findings whose right disposition is "we don't know yet — observe more first." A free-form remedy lives in the `description` body, where it can be added or refined without schema friction. Reversal cost is small if the user later wants the field — extending the gate to a 7-column schema is straightforward.
- **Per-finding files at `docs/findings/<id>.md`.** Rejected per Decision 019b. Findings are typically too short to justify their own file; the directory churn of one file per finding (and the discoverability cost of needing to grep through dozens of files) outweighs the per-file benefit. Single-file format mirrors the PRD convention (Decision 015a) and is easier to scan with tooling (`grep -A 3 "Status: open" docs/findings.md`).
- **Per-source files at `docs/findings/<source>.md`.** Rejected. Cross-source findings (one finding observed by both `harness-reviewer` and `code-reviewer`) would have to be duplicated or split, complicating the dedup story. Single-file format keeps every finding in one place regardless of who surfaced it.
- **Strict transition order in the gate (block `closed` if previous state wasn't `dispositioned-*`).** Rejected. The strict order is the common case but not universal — a finding may be observed and immediately resolved in the same commit (legitimate `open` → `closed` jump). Locking the gate against legitimate jumps creates friction without preventing real failures. Pattern-level discipline catches out-of-order transitions in routine harness-reviewer audits.
- **Status as an open enum (allow custom statuses with a `dispositioned-*` prefix).** Rejected. Open enums make tooling harder (C13 needs an exact list to compute promotion/demotion eligibility). The six-status closed enum covers every observed lifecycle in practice; if a project needs a seventh status, that's a schema amendment.

## Consequences

**Enables:**
- C13 (promotion/demotion gate) and Phase 1d-G (calibration-mimicry) both unblock — they now have a stable, schema-validated substrate to read from.
- Adversarial-review agents (the seven that emit class-aware feedback) can write structured findings into a single durable surface; future readers see the cumulative observation history.
- Audit queries are mechanical: `grep -c "Status: open" docs/findings.md` shows open-finding count; `grep -B 1 "Status: dispositioned-defer" docs/findings.md | grep "ID:"` lists every deferred finding.

**Costs:**
- One additional file in every adopting project's `docs/`. The maintenance cost is small (append-only writes, occasional status updates); the discoverability benefit is durable.
- The 6-field schema means agents that observe a finding must populate every field at write time. For findings where one field (typically `location`) is genuinely unknown, the convention is `n/a` — the gate accepts that value.

**Blocks:**
- Any commit that adds a malformed entry to `docs/findings.md` (missing field, invalid enum value, duplicate ID) is blocked by `findings-ledger-schema-gate.sh`. Recovery: fix the entry's syntax. The block-message names the failing field.

## Implementation status

Active — to be enforced by `adapters/claude-code/hooks/findings-ledger-schema-gate.sh` (Task 3 of the parent plan). The findings template at `adapters/claude-code/templates/findings-template.md` ships in Task 1 alongside this decision. The bootstrap `docs/findings.md` (with one example entry NL-FINDING-001) lands in Task 6.

## Failure modes catalogued

- `FM-022 unpersisted-finding-discovered-mid-session` — to be added to `docs/failure-modes.md` in Task 7 of the parent plan. Symptom: an agent or gate identifies a finding mid-session but the finding is not persisted to `docs/findings.md` before session end. Detection: `bug-persistence-gate.sh` extension (Task 4) accepts `docs/findings.md` modifications as legitimate persistence; without the persistence, the gate continues to BLOCK session end on trigger-phrase matches. Prevention: the pattern is the same as `docs/discoveries/` — when the agent surfaces a finding, write it to the ledger immediately rather than narrating it in chat.

## Cross-references

- `docs/plans/phase-1d-c-3-findings-ledger.md` — the implementing plan
- `adapters/claude-code/templates/findings-template.md` — canonical template (Task 1)
- `adapters/claude-code/hooks/findings-ledger-schema-gate.sh` — the schema-gate hook (Task 3)
- `adapters/claude-code/rules/findings-ledger.md` — the rule documenting when findings are required and how the lifecycle works (Task 2)
- `adapters/claude-code/hooks/bug-persistence-gate.sh` — extended in Task 4 to accept `docs/findings.md` as legitimate persistence
- `docs/findings.md` — the ledger itself (bootstrapped in Task 6)
- Decision 015 — PRD-validity gate; the precedent for single-file-per-project conventions
- Decision 016 — spec-freeze gate; the precedent for plan-header-field-driven gates
- Decision 017 — 5-field plan-header schema; the precedent for locked-enum schemas
- Build Doctrine §6 C9 + §9 Q5-A — the original specification for C9 and the field-count lock
