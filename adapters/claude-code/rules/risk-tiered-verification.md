# Risk-Tiered Verification — Verify Proportionate to Risk

**Classification:** Hybrid. The `Verification: <level>` declaration on a task line is Pattern (the planner self-applies when authoring tasks). The mechanical routing — `plan-reviewer.sh` validates the field at plan-creation time, `plan-edit-validator.sh` routes per-task evidence checks at checkbox-flip time, `task-verifier` skips the agent dispatch when level is not `full` — is Mechanism.

**Ships with:** `docs/decisions/queued-tranche-1.5.md` D.1-D.3 (three tiers, default `full`, inline declaration), Tranche D of `docs/plans/architecture-simplification.md`. Cross-reference: Build Doctrine `04-gates.md` tier matrix.

## Why this rule exists

`task-verifier`'s mandate is the harness's most expensive verification operation. It launches a fresh agent dispatch (~30-60s wall time, real LLM tokens), reads the plan, runs typecheck, replays runtime-verification commands, cross-checks against the failure-mode catalog, and emits a structured evidence block. That cost is **proportionate** for novel runtime work — UI pages where the user can observe a broken feature, API routes where a wrong response shape reaches a real client, migrations whose effects are irreversible.

It is **disproportionate** for the bulk of harness-development work. A task that says "add a new hook file under `adapters/claude-code/hooks/foo.sh` and wire it in `settings.json.template`" has a deterministic correctness check: does the file exist with the expected content, does the wiring match the expected JSON. The agent dispatch is theater for these tasks — it generates prose evidence around outcomes that grep already confirmed. The cost is wasted; worse, the friction trains builders to skip verification entirely on small tasks because "it's obvious."

Risk-tiered verification rebalances cost to risk: mechanical work gets a deterministic bash check (cheap, fast, verifiable by re-execution), contract work gets a schema/golden-file match (medium-cheap, anchored to a reference truth), and the full agent dispatch is reserved for genuinely-novel or runtime-bearing work. The harness pays full cost only where full cost is warranted.

## The three levels

### `Verification: mechanical`

**When to use.** The task's correctness can be attested by deterministic bash checks. The work is structural: file edits, hook updates, prompt updates, schema authoring, doc-only changes, sync-to-mirror operations, configuration wiring. The "did this happen?" question reduces to "does this file exist with this content?" or "does this command exit 0?".

**What the validator checks.** `plan-edit-validator.sh` accepts EITHER:
- A structured `.evidence.json` artifact under `<plan-dir>/<plan-slug>-evidence/<task-id>.evidence.json` validating against `~/.claude/schemas/evidence.schema.json` (Tranche B substrate). The file must be mtime-fresh (< 120s) and its `task_id` field must match.
- A one-line evidence-block citing a commit SHA for the work, in the legacy `<plan>-evidence.md` file. The block must contain `Task ID: <id>` and at least one cited `Commit:` SHA on its own line, mtime-fresh < 120s.

**Authoring guidance.** Prefer `write-evidence.sh capture` (the Tranche B helper) over hand-writing prose. The helper deterministically captures `--check exists:<file>`, `--check files-in-commit`, `--check command:<cmd>`, `--check schema-valid:<path>`, `--check typecheck`, `--check lint`, `--check test:<name>` outcomes and writes the structured artifact. Your role is invocation + outcome interpretation, not narrative composition.

**No agent dispatch.** `task-verifier` reads the plan task line, sees `Verification: mechanical`, and returns PASS immediately citing the structured artifact (or the one-line evidence). The verifier's correctness work was already done by the helper script.

### `Verification: contract`

**When to use.** The task ships an artifact whose correctness is a match against a locked shape: a JSON Schema, a golden fixture, a reference output. Examples: extending `evidence.schema.json` (the artifact must validate against the meta-schema), adding a finding entry (the schema-gate validates against `findings-template.md`'s six-field structure), updating the plan template (the resulting fixture must round-trip through `plan-reviewer.sh --self-test` without findings).

**What the validator checks.** `plan-edit-validator.sh` accepts a referenced golden-file or schema match. The evidence must cite either:
- A schema-validation invocation (e.g., `jq -e --arg id "$task_id" '.task_id == $id' <artifact>`) that exits 0, OR
- A golden-file diff that produces zero output (e.g., `diff <new-output> <expected-fixture>`).

The check-script exit code is the authority. Fresh structured `.evidence.json` artifacts from `write-evidence.sh capture --check schema-valid:<path>` satisfy the same check.

**No agent dispatch.** Same as mechanical — `task-verifier` returns PASS citing the contract match.

### `Verification: full`

**When to use.** The default. Use for: UI pages, API routes, webhooks, migrations, scheduled jobs, state-machine transitions, anything user-facing. Use also for: tasks with novel judgment (e.g., "design the new mechanism's failure-mode taxonomy"), tasks whose acceptance criterion is a runtime user-observable outcome that no single bash check can attest.

**What the validator checks.** Existing behavior, unchanged. `plan-edit-validator.sh` requires:
- Companion `<plan>-evidence.md` file modified within last 120s
- Evidence block with matching `Task ID: <id>`
- At least one `Runtime verification: <replayable-command>` line in the same block
- The runtime-verification command corresponds to the feature (cross-checked by `runtime-verification-reviewer.sh`)

**Agent dispatch fires.** `task-verifier` runs its full rubric: re-read plan, walk dependency trace, run task-type-specific checks, replay runtime-verification commands, emit structured evidence block with PASS/FAIL/INCOMPLETE verdict.

## Default behavior — backward compatibility

**Tasks without an explicit `Verification:` field default to `full`.** This is by design (Decision queued-tranche-1.5.md D.2): every existing plan in `docs/plans/` and `docs/plans/archive/` was authored before this rule existed. Treating their tasks as `full` preserves their semantics — the verifier mandate remains, evidence requirements are unchanged, the harness's anti-vaporware story stays intact for legacy plans.

Migration of existing plans to use the new field is **not required** and is **not in scope** for Tranche D. Plan authors writing new tasks SHOULD declare the verification level inline; the default carries the rest.

## Inline declaration format

The `Verification:` field appears at the END of a task description, on the same line as the checkbox. Examples:

```
- [ ] 1. Author the new hook file at hooks/foo.sh and wire it in settings.json.template — Verification: mechanical
- [ ] 2. Add the new evidence schema field to evidence.schema.json — Verification: contract
- [ ] 3. Implement the new dashboard widget end-to-end with Playwright coverage — Verification: full
- [ ] 4. Legacy task with no declaration   (defaults to full)
```

Field rules:
- Token name is exactly `Verification:` (case-sensitive, single colon, no surrounding bold).
- Legal levels are exactly `mechanical`, `full`, `contract` (case-sensitive, lowercase).
- The field MUST appear on the same line as the checkbox; multi-line task descriptions place the field on the first line.
- A task line MAY use any separator before `Verification:` (`—`, `--`, `;`, `|`); the parser scans the line for the literal `Verification:` token and reads the next word.
- Unknown levels (`Verification: contract-strict`, `Verification: minimal`, etc.) are rejected by `plan-reviewer.sh` with a clear stderr message naming the legal levels.

## Escalation patterns

**Misclassified at plan-time, caught at build-time.** A task author marks a task `Verification: mechanical` but during execution discovers the work is novel (a missed runtime surface, an unexpected user-facing outcome). The correct response is an in-flight scope update (`## In-flight scope updates` section in the plan, per `scope-enforcement-gate.sh`) noting the level escalation, plus a Decisions Log entry explaining the reclassification. The new level applies; the verifier dispatches accordingly.

**Mechanical level used for a structurally trivial task that nonetheless carries hidden risk.** Example: editing `settings.json.template` to wire a new hook. Mechanically the change is one JSON edit; semantically it changes when a hook fires. The author SHOULD include a runtime-verification entry even at mechanical level — the structured `.evidence.json` artifact's `runtime_evidence` array exists exactly for this case. Mechanical doesn't mean "skip verification"; it means "verification is mechanical."

**Contract used for a task lacking a clear truth-target.** If the task has no schema, no golden fixture, and no reference output, `contract` is the wrong level — use `full` instead. The contract level requires an explicit truth-target the validator can match against.

## How `plan-reviewer.sh` validates the field

At plan-creation/edit time, `plan-reviewer.sh` scans every line under `## Tasks` matching the checkbox shape `^- \[[ xX]\]`. For each line:

1. If the line contains `Verification:` followed by a token, the token MUST be one of `mechanical`, `full`, `contract`. Any other token (including typos like `mechanicall` or capitalized `Mechanical`) FAILS the check.
2. If the line does not contain `Verification:`, the task implicitly defaults to `full` (no finding emitted — backward-compatible).

The check is mode-agnostic and rung-agnostic. Every plan with a `## Tasks` section is subject to it; tasks already-checked (`- [x]`) are scanned identically (so retroactive reclassification stays type-safe).

## How `plan-edit-validator.sh` routes per-task evidence

When a checkbox flip is attempted (Edit tool: `- [ ]` → `- [x]`), the validator extracts the task ID and the line content, then:

1. Parses `Verification: <level>` from the task line in the plan file. Default: `full`.
2. Branches on level:
   - `mechanical`: check for fresh structured `.evidence.json` (per Tranche B) OR fresh one-line evidence block citing commit SHA. PASS if either present.
   - `contract`: check for referenced golden-file or schema-match assertion. PASS if check-script exit 0 OR fresh structured `.evidence.json` with a `schema-valid:` mechanical_check.
   - `full`: existing behavior — fresh prose evidence with matching Task ID + Runtime verification line.
3. Authorizes the edit if the level's check passes; blocks otherwise with a stderr message explaining what the level requires.

The lock-protected concurrency layer (flock + 120s mtime window) applies identically across all three levels.

## How `task-verifier` honors the level

When invoked on a task whose plan line declares `Verification: mechanical` or `Verification: contract`, `task-verifier` returns PASS immediately, citing:
- The level declared
- The structured `.evidence.json` artifact path (or the legacy one-line evidence block) that satisfies the level

The agent does NOT run typecheck, dependency-trace, runtime-replay, or comprehension-gate. The mechanical or contract check is the verification; the agent's existence in the chain would just re-narrate what bash already confirmed.

When the task declares `Verification: full` (or omits the field, defaulting to full), `task-verifier` runs its full rubric unchanged.

## Cross-references

- Build Doctrine `04-gates.md` tier matrix — risk-tiered gates as the underlying principle.
- `~/.claude/templates/plan-template.md` — comment block introducing the field with examples.
- `~/.claude/hooks/plan-reviewer.sh` — validates the field at plan-edit time.
- `~/.claude/hooks/plan-edit-validator.sh` — routes per-task evidence at checkbox-flip time.
- `~/.claude/agents/task-verifier.md` — skips agent dispatch when level is not `full`.
- `~/.claude/rules/mechanical-evidence.md` — the structured-evidence substrate Tranche B shipped; this rule consumes it for `Verification: mechanical`.
- `~/.claude/schemas/evidence.schema.json` — JSON Schema for `.evidence.json` artifacts.
- `~/.claude/scripts/write-evidence.sh` — helper script for capturing mechanical-check outcomes.
- `~/.claude/rules/vaporware-prevention.md` — enforcement-map row pointing at this rule.
- `docs/plans/architecture-simplification.md` Task 4 — parent plan reference.
- `docs/plans/architecture-simplification-tranche-d-risk-tiered-verification.md` — child plan that introduced this rule.
- `docs/decisions/queued-tranche-1.5.md` D.1-D.3 — pre-emptive decisions backing the three-tier shape, default-full backward compat, and inline-declaration form.

## Enforcement summary

| Layer | What it enforces | File |
|---|---|---|
| Template | Shape of `Verification:` declaration with examples and level guidance | `adapters/claude-code/templates/plan-template.md` |
| Rule (this doc) | When to use each level; routing logic per level; default-`full` semantics | `adapters/claude-code/rules/risk-tiered-verification.md` |
| plan-reviewer.sh | Field-value validity (legal levels: mechanical, full, contract); rejects unknown levels | `adapters/claude-code/hooks/plan-reviewer.sh` |
| plan-edit-validator.sh | Per-task routing of evidence-freshness check at checkbox-flip time | `adapters/claude-code/hooks/plan-edit-validator.sh` |
| task-verifier agent | Skip-when-non-full early-return; full rubric unchanged for `full` and unmarked | `adapters/claude-code/agents/task-verifier.md` |
| Vaporware prevention enforcement map | One row pointing at this rule + the four enforcement files above | `adapters/claude-code/rules/vaporware-prevention.md` |

The first two are documentation (Pattern-level). The middle three are mechanism layers — field validation at plan creation, routing at checkbox flip, and conditional agent dispatch at verification time. Together they make the cost of verification proportionate to the risk of the work.

## Scope

This rule applies in any project whose Claude Code installation has the extended `plan-reviewer.sh`, `plan-edit-validator.sh`, and `task-verifier.md` artifacts. Projects without the extensions see the field as documentation — `task-verifier` runs its full rubric on every task regardless of declaration, which is the pre-Tranche-D behavior. Adoption is implicit on harness install/sync.

Existing plans are unaffected: their tasks default to `full`, preserving the existing verifier mandate. New plans MAY declare per-task levels to reduce verification overhead on mechanical and contract work.
