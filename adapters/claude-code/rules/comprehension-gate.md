# Comprehension Gate — Builders Articulate Their Mental Model Before Commit at R2+

**Classification:** Hybrid. The gate's invocation point (task-verifier reads `rung:` at >= 2 → invokes comprehension-reviewer agent → propagates verdict) is a Mechanism. The substance review of the four articulation fields is LLM-assisted (Pattern + agent judgment). The schema spec (four required sub-sections, ≥ 30-char threshold per field) is mechanically checked by the agent during invocation.

**Ships with:** Decision 020 (`docs/decisions/020-comprehension-gate-semantics.md`) — read it first for the five locked sub-decisions (rung-2 cutoff; four required fields; 30-char threshold; FAIL/INCOMPLETE blocks the checkbox flip; articulation lives in the Evidence Log).

## Why this rule exists

Every adversarial reviewer the harness ships verifies what was *written*. `code-reviewer` reads the diff. `task-verifier` reads the diff plus the evidence block plus the runtime-verification commands. `plan-evidence-reviewer` reads the evidence log and cross-checks against the plan. None of these verify that the **builder understood what was supposed to be written**.

A builder can produce a syntactically-correct diff that passes typecheck and even matches the spec on its face — while having silently misunderstood an edge case, an assumption, or the spec's intent. The diff is correct; the builder's mental model isn't. This shows up in practice as:

- **Edge-case-not-handled-because-builder-thought-it-was-out-of-scope.** The spec named an edge case in passing; the builder read it as "interesting but not required" and the diff does not handle it. Code review finds nothing wrong with the lines that exist; the missing lines are invisible.
- **Assumption-implicit-not-stated-then-violated-by-caller.** The builder relied on a property the spec did not promise (e.g., "callers always pass a non-null `org_id`"). The assumption holds today; a future caller violates it; the bug is silent until it surfaces in production.
- **Side-effect-overlooked.** The builder wired a new code path through an existing function whose side effects (logging, metrics emission, downstream cache invalidation) the builder did not consider. The diff compiles; the side effect either fires when it should not, or fails to fire when it should.

These three failure shapes share one root cause: the builder shipped a model mismatch the audit chain could not surface. The comprehension gate makes the builder articulate their model in writing before commit; the agent verifies the articulation matches the diff. Mental-model verification becomes part of the audit trail, not just code-correctness verification.

## When the gate fires

The gate fires at plans declaring `rung: 2` or higher in the header (per Decision 020a). Specifically:

1. Builder finishes a task and invokes `task-verifier` per the existing verifier mandate (see `~/.claude/rules/planning.md` Verifier Mandate).
2. task-verifier reads the plan's `rung:` field. If `rung: 0` or `rung: 1`, task-verifier proceeds with its existing logic without invoking comprehension-reviewer (the gate is a no-op below R2).
3. If `rung: 2` or higher, task-verifier invokes `comprehension-reviewer` BEFORE flipping the task's checkbox, passing the plan path, the task ID, and the builder's articulation block.
4. comprehension-reviewer returns PASS / FAIL / INCOMPLETE with structured feedback.
5. Verdict propagates per Decision 020d: PASS allows task-verifier to proceed with normal verification (typecheck, evidence-block format, runtime-verification correspondence); FAIL or INCOMPLETE causes task-verifier to return FAIL without flipping the checkbox.

The chain is single-invocation: builder → task-verifier → comprehension-reviewer → task-verifier verdict. There is no parallel enforcement path; the audit trail stays co-located with task-verifier's existing evidence-block writes.

## What the builder must articulate

The builder writes a `## Comprehension Articulation` sub-section inside the task's entry under `## Evidence Log` in the plan file (per Decision 020e — articulation lives in the Evidence Log, not in plan-body sections). Four required sub-sections, in this order, locked by Decision 020b:

1. **`### Spec meaning`** — what the spec asks for, in the builder's own words. Not a copy-paste of the plan's Goal section; a paraphrase that demonstrates the builder's understanding.
2. **`### Edge cases covered`** — which edge cases the diff handles, with `file:line` citations pointing at the specific code that handles each named case.
3. **`### Edge cases NOT covered`** — honest list of gaps the diff does not address. If the builder believes zero gaps exist, the builder explicitly justifies why none apply (e.g., "the spec scopes the change to a single-tenant deployment; multi-tenant edge cases are out-of-scope per `## Scope` OUT").
4. **`### Assumptions`** — premises the diff relies on, about callers, environment, data shape, future maintainers, or anything else not guaranteed by the spec but on which the diff's correctness depends.

Each sub-section must contain at least 30 non-whitespace characters of substantive content (per Decision 020c). Below the threshold returns FAIL with the specific sub-section named.

The template at `adapters/claude-code/templates/comprehension-template.md` shows a worked example for a synthetic R2 task; real articulations replace the template's sample content with task-specific content.

## The agent's rubric

`comprehension-reviewer` runs a three-stage review (full agent rubric in `adapters/claude-code/agents/comprehension-reviewer.md` — lands in Task 3):

### Stage 1 — Schema check

Parse the articulation block from the named task's evidence entry. Confirm all four required sub-sections are present with their canonical headings (`### Spec meaning`, `### Edge cases covered`, `### Edge cases NOT covered`, `### Assumptions`). Headings must match exactly; case-insensitive match on the sub-section name is allowed but the leading `### ` and the trailing label must be present.

Verdict at this stage:
- All four headings present → proceed to Stage 2.
- One or more headings missing → return INCOMPLETE with the names of the missing sub-sections.
- Block missing entirely (no `## Comprehension Articulation` in the task's evidence entry) → return INCOMPLETE with `articulation block missing`.

### Stage 2 — Substance check

For each of the four sub-sections, count non-whitespace characters in the body. Reject content that consists entirely of placeholder text — specifically, content matching common placeholders (`TODO`, `n/a`, `none`, `see code`, `see diff`, `same as above`) without surrounding substantive content also fails.

Verdict at this stage:
- All four sub-sections meet the ≥ 30-char threshold AND none consist solely of placeholder text → proceed to Stage 3.
- One or more sub-sections fall below the threshold or are vacuous → return FAIL with the specific sub-section(s) named and the reason (`below threshold` or `vacuous content`).

### Stage 3 — Diff correspondence

Read the staged diff (the commit named in the evidence block, or the working-tree diff if the evidence block precedes the commit). Cross-check the articulation against the diff:

- Every claim under `### Edge cases covered` that cites `file:line` must map to actual diff content. If the builder claims "handles concurrent writes via mutex at `src/db/writer.ts:45`" and `src/db/writer.ts:45` in the diff has no mutex, the claim is unsupported — FAIL.
- Every premise under `### Assumptions` must be plausible against the diff's actual behavior. If the builder claims "assumes caller passes non-null `org_id`" but the diff explicitly handles `null` (e.g., a `??` fallback or a null-check that returns), the assumption is contradicted — FAIL.
- Generic articulations that clear the substance threshold but could apply to any task ("handles edge cases gracefully", "assumes the existing API contract") fail diff-correspondence: there is no specific diff content the claim maps to.

Verdict at this stage:
- All claimed edge-cases-covered map to diff content AND no assumption is actively contradicted by the diff → return PASS.
- One or more claims unsupported or contradicted → return FAIL with the specific claim and the diff location that contradicts it.

The three stages are sequential: a schema failure short-circuits substance and correspondence checks; a substance failure short-circuits the correspondence check.

## Worked PASS example

For a synthetic R2 task that adds per-org outbound rate-limiting to a notifier service (see the template for the full block), the articulation might read:

```
### Spec meaning
The spec asks me to add per-org outbound-notification rate-limiting that caps each
org at 100 notifications per rolling 60-second window. Enforced at notifier level
before queue handoff so excess returns a structured rejection (not silent drop).

### Edge cases covered
- New org with zero history: first notification accepted; rate-limiter initializes
  the org's window lazily on first call (`src/services/notifier.ts:84-91`).
- 100th notification accepted, 101st rejected (`src/services/notifier.ts:112`,
  comparison is `>= 100` not `> 100`).
- Window rollover: notifications outside the rolling 60s window pruned before
  the cap-check (`src/services/notifier.ts:97-103`).

### Edge cases NOT covered
- Cross-process rate-limiter state. Current implementation holds per-org window
  in single-process in-memory map; horizontally-scaled notifier processes would
  each enforce independently. Acceptable for current single-instance deployment;
  out-of-scope per plan's `## Scope` OUT clause.

### Assumptions
- Caller provides non-null `org_id`; upstream auth middleware guarantees this per
  the existing `requireAuthUser(orgId)` contract.
- Wall-clock time monotonically increasing; rate-limiter would mis-prune on clock
  skew but deployment is single-tenant with NTP-synced clocks.
```

PASS reasoning: Stage 1 (all four headings present) → Stage 2 (each sub-section well above 30 chars, no placeholder text) → Stage 3 (each `file:line` citation maps to actual diff content; assumptions are not contradicted by the diff).

## Worked FAIL examples

### Example A — Vacuous sub-section

```
### Edge cases NOT covered
None.
```

FAIL at Stage 2 with `### Edge cases NOT covered` named. The content is below the 30-char threshold AND is a placeholder (`None.` without justification). The builder must either (a) name actual gaps the diff does not address, or (b) explicitly justify why zero gaps apply (e.g., "the spec's `## Scope` OUT clause excludes the multi-tenant case which would otherwise apply; no other gaps exist because the cap-check is the only behavioral surface added").

### Example B — Diff-correspondence failure

```
### Edge cases covered
- Handles concurrent writes via mutex at `src/db/writer.ts:45`.
- Validates input length before persisting (`src/api/routes/items.ts:120`).
```

FAIL at Stage 3 with the first claim flagged. Inspecting `src/db/writer.ts:45` in the diff reveals no mutex — the line is part of an unrelated function. The builder either fabricated the citation, copy-pasted from a different task's articulation, or confused mutex-based vs. lock-free strategies in their model. The agent surfaces the specific mismatch: "claim cites `src/db/writer.ts:45` but the diff at that location contains no mutex; closest mutex usage is at `src/db/writer.ts:78` and operates on a different code path."

## Worked INCOMPLETE example

```
### Spec meaning
[populated]

### Edge cases covered
[populated]

### Edge cases NOT covered
[populated]
```

INCOMPLETE at Stage 1. The articulation has only three sub-sections — the `### Assumptions` heading is missing entirely. The builder must add the missing sub-section with substantive content and re-invoke task-verifier. INCOMPLETE differs from FAIL in that the gate cannot fully evaluate the articulation; the builder is being told "we cannot grade this until the missing piece arrives" rather than "we graded this and it failed."

## Rung-2 cutoff rationale

The gate fires at R2 and above only (per Decision 020a). At R0 and R1, the diff is small enough — single-file, no behavioral contract required — that misunderstanding shows up directly in code-review. Running the gate on every R0/R1 task would add ~30s of wall time per task without surfacing meaningful gaps in practice; the overhead exceeds the reliability gain.

At R2 and above, the diff is multi-file or the task's behavioral-contract scope is wide enough that misunderstanding can hide. A multi-file diff has many surfaces where a builder's model can drift from the spec without any single line of code looking wrong; behavioral contracts (R2+ already gets Check 11 sub-entry review per Phase 1d-C-2) introduce semantic surfaces where edge cases and assumptions matter more than syntax. The gate becomes load-bearing exactly where bare diff-review starts becoming insufficient.

The R2 cutoff also aligns with the existing R2+ infrastructure: Check 11 (behavioral contracts) gates the same rung threshold; Check 10 (5-field plan-header schema) ships the `rung:` field both gates read. A single rung threshold gates both substance bars without requiring builders to track multiple cutoffs.

## Cross-references

- **Decision record:** `docs/decisions/020-comprehension-gate-semantics.md` — the five locked sub-decisions (rung cutoff, field set, threshold, verdict propagation, articulation location).
- **Agent:** `adapters/claude-code/agents/comprehension-reviewer.md` — lands in Task 3 of the parent plan; codifies the three-stage rubric and emits structured PASS/FAIL/INCOMPLETE verdicts.
- **Template:** `adapters/claude-code/templates/comprehension-template.md` — canonical articulation shape with a worked example. Replace the sample content with task-specific content per task.
- **Failure-mode entry:** `FM-023 vaporware-spec-misunderstood-by-builder` in `docs/failure-modes.md` — lands in Task 5 of the parent plan; catalogs the failure class C15 prevents.
- **Enforcement-map row:** `adapters/claude-code/rules/vaporware-prevention.md` — extended in Task 5 of the parent plan with a row pointing at the comprehension-reviewer agent and the task-verifier extension.
- **task-verifier extension:** `adapters/claude-code/agents/task-verifier.md` — extended in Task 4 of the parent plan with the gate-invocation block at R2+.
- **Sibling rule (substance bar):** `adapters/claude-code/rules/spec-freeze.md` — Check 11 uses the same 30-char threshold for behavioral-contract sub-entries; consistent substance bar across mechanisms.
- **Sibling rule (verifier mandate):** `~/.claude/rules/planning.md` Verifier Mandate — task-verifier remains the only entity that flips checkboxes; the comprehension gate adds a precondition, not a parallel path.
- **Build Doctrine source:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 C15 — the original specification for the comprehension-gate agent.

## Enforcement summary

| Layer | What it enforces | File |
|---|---|---|
| Template | Articulation block shape (four required sub-sections in order) with a worked example | `adapters/claude-code/templates/comprehension-template.md` |
| Rule (this doc) | When the gate fires (R2+); the four required articulation fields; the three-stage rubric | `adapters/claude-code/rules/comprehension-gate.md` |
| Agent | Three-stage substance + diff-correspondence review; structured PASS/FAIL/INCOMPLETE verdict | `adapters/claude-code/agents/comprehension-reviewer.md` |
| task-verifier extension | Auto-invokes the agent at `rung: 2+`; propagates FAIL/INCOMPLETE as task-verifier FAIL (no checkbox flip) | `adapters/claude-code/agents/task-verifier.md` |
| Decision record | Locks the five semantic decisions (rung cutoff, four fields, 30-char threshold, verdict propagation, evidence-log location) | `docs/decisions/020-comprehension-gate-semantics.md` |
| Failure-mode entry | `FM-023 vaporware-spec-misunderstood-by-builder` — the failure class the gate prevents | `docs/failure-modes.md` |
| Enforcement-map row | Inventory of which mechanism enforces what; pointer to the comprehension gate | `adapters/claude-code/rules/vaporware-prevention.md` |

The first two layers are documentation (Pattern-level + invocation contract). The agent + task-verifier extension is the Mechanism stack: at R2+, comprehension-reviewer is auto-invoked by task-verifier, and FAIL or INCOMPLETE blocks the checkbox flip without a parallel enforcement path. The decision record locks the semantics so future revisions require an ADR; the failure-mode entry catalogs the class the gate exists to prevent.

## Scope

This rule applies in any project whose Claude Code installation has the `comprehension-reviewer` agent file and the task-verifier rung >= 2 invocation block. Neural Lace adopts the gate first; downstream projects opt in by their plan files declaring `rung: 2` or higher and the harness propagating the agent + task-verifier extension into the project's `.claude/` directory (per the standard rollout pattern). A project whose plans never declare `rung: 2+` sees the gate as a no-op — task-verifier reads the rung field and skips the comprehension-reviewer invocation entirely.
