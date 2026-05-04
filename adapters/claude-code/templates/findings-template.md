# Findings ledger

<!--
This is the canonical findings-ledger template for projects using the
Neural Lace harness. The findings ledger is the single source-of-truth
for class-aware observations made by gates, adversarial-review agents,
and builders during the work — separate from the backlog (open work),
the reviews directory (review-pass output), and the discoveries
directory (mid-process learnings).

ONE findings file per project. Path: docs/findings.md (repo-relative).
All entries — across every gate, every agent, every severity, every
scope — live in this one file.

The findings-ledger schema gate (`findings-ledger-schema-gate.sh`)
validates each entry at commit time:

  Six required fields per entry, with locked enum values:
    1. id        — project-prefixed kebab-case identifier (unique)
    2. severity  — info | warn | error | severe
    3. scope     — unit | spec | canon | cross-repo
    4. source    — which gate / agent / role surfaced the entry
    5. location  — file:line, artifact path, or `n/a`
    6. status    — open | in-progress | dispositioned-act |
                   dispositioned-defer | dispositioned-accept | closed

Out-of-range enum values FAIL the gate. Missing fields FAIL the gate.
Duplicate IDs FAIL the gate. The block-message names the failing
field.

Format per entry: a `###`-level heading carrying the ID and a short
title, followed by a bulleted list of the six fields plus a
`Description` body. Sample entries below illustrate the shape.

For substantive review of entry content (is it well-stated, is the
disposition appropriate), the existing class-aware-feedback contract
from the seven adversarial-review agents covers the substance review
path. The schema gate only validates shape.

The ledger is append-mostly: new entries are added at the bottom (or
under a topical sub-section); existing entries have their `Status:`
field updated as the disposition progresses. Closed entries are
typically left in place as the audit trail; long ledgers may be
periodically migrated to `docs/findings-archive/<year>.md`.
-->

## Schema specification

| Field | Required | Type | Valid values |
|---|---|---|---|
| `ID` | Yes | string | Project-prefixed kebab-case identifier (e.g., `NL-FINDING-001`). Unique within `docs/findings.md`. |
| `Severity` | Yes | enum | `info`, `warn`, `error`, `severe` |
| `Scope` | Yes | enum | `unit`, `spec`, `canon`, `cross-repo` |
| `Source` | Yes | string | Names which gate / agent / role surfaced the entry (e.g., `harness-reviewer`, `prd-validity-reviewer`, `orchestrator`). |
| `Location` | Yes | string | `file:line` reference, artifact path, or `n/a` if process-shaped rather than artifact-shaped. |
| `Status` | Yes | enum | `open`, `in-progress`, `dispositioned-act`, `dispositioned-defer`, `dispositioned-accept`, `closed` |

The `Description` field is required body content (not a metadata field). It explains the observation in enough detail that a future-session reader can understand it without re-deriving the context.

### Lifecycle (status enum)

- **`open`** — recorded but no action taken. Default initial status.
- **`in-progress`** — work is actively underway to resolve.
- **`dispositioned-act`** — the team has decided to act (a fix is planned or in flight).
- **`dispositioned-defer`** — intentionally deferred; "we know about it, we chose not to act now."
- **`dispositioned-accept`** — acceptable behavior; closes without a fix.
- **`closed`** — fully resolved. For an `act`-class entry, fix has shipped and verification passed.

Transitions are not strictly linear. A `dispositioned-defer` entry may flip to `in-progress` when a future session picks it up, then to `closed`. The schema gate validates the field is in the enum; transition order is Pattern-level discipline.

### Severity enum (severity-ordered)

`info` < `warn` < `error` < `severe`. Use `info` for observations that document but don't demand action; `warn` for observations that should be addressed but are not breaking; `error` for observations that block correctness or completeness; `severe` for observations that imply data loss, security exposure, or systemic failure.

### Scope enum (breadth-ordered)

`unit` (one file or hook) < `spec` (one plan or PRD) < `canon` (rule, doctrine, or decision-record-level) < `cross-repo` (touches more than one repo or downstream consumer). Use the broadest applicable scope.

## Sample entries

The entries below illustrate the canonical shape. Real ledger entries replace these.

### SAMPLE-001 — example entry showing the canonical 6-field shape

- **Severity:** warn
- **Scope:** unit
- **Source:** harness-reviewer
- **Location:** adapters/claude-code/hooks/example-gate.sh:42
- **Status:** open
- **Description:** When `example-gate.sh` encounters a path containing whitespace, the regex match silently fails because the path-comparison loop uses unquoted `$IFS`. Add a quoting test scenario to `--self-test`. Workaround: avoid paths with whitespace until the fix lands.

### SAMPLE-002 — example entry showing dispositioned-defer

- **Severity:** info
- **Scope:** spec
- **Source:** prd-validity-reviewer
- **Location:** docs/prd.md
- **Status:** dispositioned-defer
- **Description:** PRD's Open Questions section currently lists 7 items; agent observed that 2 of them have been resolved in subsequent decision records but not pruned from the PRD. Disposition: defer cleanup until next PRD revision pass — the staleness is documentation drift, not an active misclassification, and patching item-by-item is less effective than a holistic re-author when the next major feature lands.

### SAMPLE-003 — example entry showing closed status

- **Severity:** error
- **Scope:** unit
- **Source:** code-reviewer
- **Location:** adapters/claude-code/hooks/sample-hook.sh:101-115
- **Status:** closed
- **Description:** Hook had a race condition between two parallel verifier invocations editing the same plan file. Fixed by wrapping the edit in `flock` on the plan-file lock. Closed when verification confirmed parallel verifier runs no longer interleave.
