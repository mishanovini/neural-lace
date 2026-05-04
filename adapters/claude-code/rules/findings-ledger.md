# Findings Ledger — Class-Aware Observations Land in `docs/findings.md`

**Classification:** Hybrid. The discipline of writing class-aware entries when a gate fires, an agent surfaces a defect, or a builder discovers a sibling regression is a Pattern self-applied by every observing agent. The schema validation (six fields, locked enum values, unique IDs) is a Mechanism enforced by `findings-ledger-schema-gate.sh` (PreToolUse Bash on `git commit`). The durable-capture requirement (sessions cannot end with trigger-phrase observations un-persisted) is also Mechanism-enforced by the extended `bug-persistence-gate.sh` (Stop hook), which accepts modifications to `docs/findings.md` as legitimate persistence alongside the existing `docs/backlog.md`, `docs/reviews/`, and `docs/discoveries/` targets.

**Ships with:** Decision 019 (`docs/decisions/019-findings-ledger-format.md`) — read it first for the three sub-decisions (six-field schema locked at Build Doctrine §9 Q5-A; single `docs/findings.md` per project; dispositioning lifecycle).

## Why this rule exists

The harness has multiple substrates for capturing observed gaps:

- `docs/backlog.md` — open work the team intends to do.
- `docs/reviews/YYYY-MM-DD-<slug>.md` — reviewer-pass output (UX-test agent runs, audit results, code-review batches).
- `docs/discoveries/YYYY-MM-DD-<slug>.md` — mid-process learnings (architectural realizations, scope expansions, dependency surprises).

What was missing: a single durable surface where every gate, every adversarial-review agent, and every builder can record class-aware observations in a structured, schema-validated format. The backlog tracks open work but not the audit trail of "we observed X and dispositioned it as accept." The reviews directory captures reviewer output but is one-file-per-pass and does not aggregate across passes. Discoveries capture learnings but are decision-shaped rather than observation-shaped.

The ledger closes that gap. It is the canonical surface for observations:

- **Schema-validated.** Every entry has six required fields with locked enum values; downstream tooling (C13 promotion/demotion gate, Phase 1d-G calibration-mimicry, future automated dispositioners) can read the ledger reliably without re-deriving the schema.
- **Durable.** The `bug-persistence-gate.sh` extension treats `docs/findings.md` as a legitimate persistence target; trigger-phrase observations that fire during a session cannot escape persistence by being narrated in chat instead.
- **Single surface.** One file per project at `docs/findings.md`. All severities, all scopes, all sources combined. Greppable in one pass.

The ledger is upstream of two future capabilities the harness is building toward: C13 (the promotion/demotion gate that decides when a Pattern matures into a Mechanism) reads the ledger to compute "sustained-green" eligibility; Phase 1d-G (calibration-mimicry, the agent that learns from the ledger observation history) reads it as its training substrate. Landing the ledger now unblocks both.

## What a finding is

A finding is **a class-aware observation made by an entity with epistemic authority during the work**. Concretely:

- A gate fires and surfaces a class-aware feedback block (severity, scope, suggested generalization). The gate (or the agent that invoked it) writes the entry.
- An adversarial-review agent (one of the seven that emit class-aware feedback per the six-field contract: `systems-designer`, `harness-reviewer`, `code-reviewer`, `security-reviewer`, `ux-designer`, `claim-reviewer`, `plan-evidence-reviewer`) returns a finding. The orchestrator or builder writes the entry capturing the agent observation.
- A builder discovers a sibling regression mid-task that the plan did not anticipate. The builder writes the entry (typically `dispositioned-defer` if the regression is out of scope for the current commit; `open` if in scope and being addressed).
- A reviewer reading a plan or commit notices a structural pattern that does not fit any existing rule. The reviewer writes the entry (usually `info` severity, `canon` scope) so the pattern enters the audit trail.

A finding is NOT:

- An open work item the team has not yet committed to addressing (that is a backlog entry).
- A point-in-time review pass (that is a reviews directory document).
- A mid-process realization that requires a decision (that is a discovery).
- An observation captured only in chat or a commit message body (those evaporate; observations must reach the ledger to count).

When in doubt: if the observation has a class (a phenotype that could recur) and is worth a future-session reader knowing about, it goes in the ledger. Backlog and ledger may overlap when the observation is also tracked work; the ledger is the audit trail, the backlog is the work queue.

## File location

One file per project at `docs/findings.md` (repo-relative). All entries — across every gate, every agent, every severity, every scope — live in this one file. Sub-categorization within the file (sections per source / severity / status) is allowed but not required.

The single-file convention mirrors Decision 015 (single PRD per project) and contrasts with the discovery-protocol convention (one file per discovery). Findings are typically 5-30 lines each, reference each other frequently, and benefit from a single readable surface; the per-file overhead of the discoveries pattern is not justified.

## The six-field schema

Per Decision 019a, every entry declares exactly six fields. The schema is locked.

| Field | Required | Type | Valid values |
|---|---|---|---|
| `ID` | Yes | string | Project-prefixed kebab-case identifier (e.g., `NL-FINDING-001`). Unique within `docs/findings.md`. |
| `Severity` | Yes | enum | `info`, `warn`, `error`, `severe` |
| `Scope` | Yes | enum | `unit`, `spec`, `canon`, `cross-repo` |
| `Source` | Yes | string | Names which gate / agent / role surfaced the entry. |
| `Location` | Yes | string | `file:line` reference, artifact path, or `n/a` if process-shaped. |
| `Status` | Yes | enum | `open`, `in-progress`, `dispositioned-act`, `dispositioned-defer`, `dispositioned-accept`, `closed` |

A `Description` body field follows the metadata block — not part of the schema enum check, but required as substantive content.

### Severity enum (severity-ordered)

`info` < `warn` < `error` < `severe`.

- `info` — observations that document but do not demand action ("the PRD has 7 open questions; some are stale").
- `warn` — observations that should be addressed but are not breaking ("a hook regex false-positives on plural language under `## Definition of Done`").
- `error` — observations that block correctness or completeness ("the deduplication key is wrong; loses 1 in 30 records").
- `severe` — observations that imply data loss, security exposure, or systemic failure ("the gate that should block force-push is silently disabled").

### Scope enum (breadth-ordered)

`unit` < `spec` < `canon` < `cross-repo`.

- `unit` — one file, one hook, one function. Blast radius is local.
- `spec` — one plan or PRD. Affects the work-product of one document.
- `canon` — a rule, a doctrine, a decision record. Affects how the harness behaves system-wide.
- `cross-repo` — touches more than one repo, or a downstream consumer of the harness.

Use the broadest applicable scope. A finding about a regex in one hook is `unit`; a finding about a discipline that should be encoded in a rule is `canon`.

## The dispositioning lifecycle

Per Decision 019c, the status enum encodes a six-state lifecycle.

```
open --> in-progress --> dispositioned-act --> closed
   \                  \--> dispositioned-defer (may later return to in-progress)
    \                  \--> dispositioned-accept --> closed
     \--> closed (when fix lands in same commit as observation)
```

### Concrete examples per transition

**`open` to `in-progress`.** A reviewer wrote `NL-FINDING-007` (status `open`) noting a hook regex false-positives on a specific input. A future session picks it up, edits the hook, and flips the entry to `in-progress` to indicate work is underway.

**`open` to `dispositioned-act`.** A reviewer wrote `NL-FINDING-012` noting a gap in the plan-template guidance. The orchestrator decides to act, schedules the fix in the next plan, and flips the status to `dispositioned-act`. The fix may land later; the disposition captures the decision.

**`open` to `dispositioned-defer`.** A reviewer wrote `NL-FINDING-018` noting an existing rule wording is ambiguous in a corner case. The orchestrator decides the corner case is rare and the workaround is trivial; flips to `dispositioned-defer` with a description naming the workaround. The entry stays in the ledger as the audit trail.

**`open` to `dispositioned-accept`.** A reviewer wrote `NL-FINDING-022` noting a hook is silent when no input matches. The orchestrator confirms the silence is intentional (the hook job is to validate, not to narrate); flips to `dispositioned-accept`. The entry remains for future readers who might rediscover the observation.

**`in-progress` to `closed`.** The work to resolve `NL-FINDING-007` lands in a commit. The author flips the status to `closed`, optionally amending the description with the resolving commit SHA.

**`dispositioned-defer` to `in-progress`.** A future session decides the deferred entry should be acted on. The author flips the status back to `in-progress` and proceeds with the fix.

**`dispositioned-act` to `closed`.** The scheduled fix lands; status flips to `closed`.

**`open` to `closed` (same commit).** A reviewer observes a defect AND fixes it in the same commit. The entry is recorded with `Status: closed` directly, capturing the audit trail without an intermediate `in-progress` state.

### Transitions are not strictly linear

The schema gate validates the status field is in the enum; it does NOT enforce transition order. A finding may flip from `dispositioned-defer` back to `open` if the team decides the deferral was wrong. A `dispositioned-accept` may later be re-opened if the acceptance turns out to have been premature. Order is Pattern-level discipline; the gate enforces shape only.

## Who writes findings

Every entity with epistemic authority during the work writes findings. Concretely:

- **Gates** that emit class-aware feedback (the seven adversarial-review agents per their Output Format Requirements). When a gate fires and the observation is class-aware (has a phenotype, a sweep query, a required generalization), the invoker writes the entry to the ledger.
- **Agents** during dispatched task execution (`plan-phase-builder`, `task-verifier`, `plan-evidence-reviewer`, etc.). When an agent observes a sibling regression or a structural pattern outside its narrow task scope, the agent writes the entry.
- **The orchestrator** during plan dispatch and review-pass aggregation. When the orchestrator notices a pattern across multiple builder returns, the orchestrator writes the entry.
- **Builders** during build work. When a builder discovers a sibling regression mid-task, the builder writes the entry (usually `dispositioned-defer` if the sibling is out of scope; `open` if in scope and being addressed).

The convention: write the entry as soon as the observation is recognized. The cost of writing an entry is small (5-30 lines); the cost of forgetting an observation is large (it evaporates with the session).

## Relationship to other substrates

- **Backlog (`docs/backlog.md`).** The backlog is the queue of open work the team has committed to. The ledger is the audit trail of class-aware observations. Overlap is fine and expected: a finding marked `dispositioned-act` may also have a corresponding backlog entry tracking the work. The two substrates serve different consumers — the backlog answers "what are we doing next?"; the ledger answers "what have we observed?"
- **Reviews (`docs/reviews/`).** A reviews document captures one review pass at one point in time. A finding may originate in a reviews document and then be promoted to the ledger as a class-aware entry. The ledger is the persistent audit trail; the reviews document is the per-pass snapshot.
- **Discoveries (`docs/discoveries/`).** A discovery is a mid-process realization that requires a decision. A finding is an observation that may or may not require a decision. Discoveries propagate to ADRs, plan-file edits, or backlog HARNESS-GAP entries; findings stay in the ledger and progress through the dispositioning lifecycle. If a finding requires a decision, the decision is captured separately (Decisions Log entry, ADR) and the finding status flips to reflect the decided disposition.
- **Failure modes (`docs/failure-modes.md`).** A `FM-NNN` entry is the catalog of named failure classes. A finding may reference a `FM-NNN` ID in its description if it is a known instance of a catalogued class. Findings whose root cause is a NEW class trigger both a ledger entry AND a `FM-NNN` catalog update (per the diagnosis rule "After Every Failure: Encode the Fix" loop).

## The Mechanism + Pattern split

C9 is intentionally split into two enforcement layers:

- **Mechanism (`findings-ledger-schema-gate.sh` PreToolUse Bash on `git commit`).** Runs on every commit that modifies `docs/findings.md`. Reads the diff, parses each new or modified entry, validates: (a) all six required fields present, (b) `severity` / `scope` / `status` values within their enums, (c) `id` field unique within the file. Out-of-range or missing values FAIL with a message naming the offending entry and field. Fast (<500ms typical) and runs on every commit.

- **Pattern (this rule).** Self-applied discipline. Agents and builders who observe a class-aware entry write it to the ledger as soon as recognized; the bug-persistence-gate trigger-phrase check at session end backstops forgetfulness, but the discipline is to capture eagerly.

Both layers must operate together. The gate catches malformed entries at commit time; the rule (and the supporting bug-persistence-gate extension) backstops sessions where observations were narrated in chat instead of recorded.

## Cross-references

- **Decision record:** `docs/decisions/019-findings-ledger-format.md` — the three sub-decisions (six-field schema; single-file per project; lifecycle).
- **Hook (schema gate):** `adapters/claude-code/hooks/findings-ledger-schema-gate.sh` — the PreToolUse Bash mechanism (lands in Phase 1d-C-3 Task 3).
- **Hook (durable capture):** `adapters/claude-code/hooks/bug-persistence-gate.sh` — extended in Phase 1d-C-3 Task 4 to accept `docs/findings.md` as legitimate persistence.
- **Template:** `adapters/claude-code/templates/findings-template.md` — the canonical shape with the six-field schema spec and sample entries.
- **Sibling rule (reactive):** `~/.claude/rules/diagnosis.md` — the "After Every Failure: Encode the Fix" loop. Findings of severity `error` or `severe` typically trigger the diagnosis loop; the ledger is the durable record of the observation.
- **Sibling rule (proactive learnings):** `~/.claude/rules/discovery-protocol.md` — captures decision-shaped mid-process realizations. Discoveries propagate; findings progress through dispositions.
- **Sibling rule (durable capture):** `~/.claude/rules/testing.md` "Bug Persistence" section — defines the trigger-phrase contract that the extended `bug-persistence-gate.sh` enforces.
- **Build Doctrine source:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 C9 + §9 Q5-A — the original specification for the gate and the field-count lock.

## Enforcement

| Layer | What it enforces | File | Status |
|---|---|---|---|
| Rule (this doc) | When findings are required, the six-field schema, the dispositioning lifecycle, the relationship to backlog and reviews | `adapters/claude-code/rules/findings-ledger.md` | landing in Phase 1d-C-3 Task 2 |
| Template | Shape of a correct findings ledger with schema spec and sample entries | `adapters/claude-code/templates/findings-template.md` | landing in Phase 1d-C-3 Task 1 |
| Hook (`findings-ledger-schema-gate.sh`) | Schema validation on every commit modifying `docs/findings.md` | `adapters/claude-code/hooks/findings-ledger-schema-gate.sh` | landing in Phase 1d-C-3 Task 3 |
| Hook (`bug-persistence-gate.sh` extended) | Sessions cannot end with trigger-phrase observations un-persisted; `docs/findings.md` is a legitimate persistence target | `adapters/claude-code/hooks/bug-persistence-gate.sh` | landing in Phase 1d-C-3 Task 4 |
| Decision record | The three sub-decisions backing this rule | `docs/decisions/019-findings-ledger-format.md` | landing in Phase 1d-C-3 Task 1 |

The rule is documentation (Pattern-level). The mechanism stack (schema gate + bug-persistence extension) is hook-enforced. Together they close the loop: cannot commit a malformed entry (gate); cannot end a session with un-persisted trigger-phrase observations (extended Stop hook); the discipline of class-aware writing is the agent self-applying.

## Scope

This rule applies in any project whose Claude Code installation has the `findings-ledger-schema-gate.sh` hook wired in `settings.json` AND has chosen to adopt the ledger. Adoption is per-project: a project opts in by creating `docs/findings.md` (typically with a single bootstrap entry to start) and authoring entries as observations arise. A project that has not adopted the ledger sees the gate exit silently (no findings.md changes in the diff means nothing to validate); the bug-persistence-gate extension also degrades gracefully (existing accepted-targets remain accepted).

Neural Lace itself adopts the ledger first; downstream projects opt in via separate per-project plans (per the rollout sequence — NL adopts the substrate first; downstream projects follow).