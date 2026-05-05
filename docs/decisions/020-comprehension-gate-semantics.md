# Decision 020 — Comprehension-gate semantics (C15): rung-2 cutoff, four required articulation fields, FAIL/INCOMPLETE blocks task-verifier

**Date:** 2026-05-04
**Status:** Active
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/phase-1d-c-4-comprehension-gate.md` (Status: ACTIVE)
**Related Build Doctrine source:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 C15

## Context

Build Doctrine §6 C15 specifies a comprehension-gate agent: an adversarial peer to `task-verifier` whose job is to verify that the **builder understood what was supposed to be written**, not just that what was written is syntactically correct. The motivation: every existing adversarial reviewer (`code-reviewer`, `task-verifier`, `plan-evidence-reviewer`) verifies what was written — none verifies the builder's mental model. A builder can produce a syntactically-correct diff that passes typecheck and even matches a section of the spec while having silently misunderstood an edge case, an assumption, or the spec's intent. The diff is correct; the builder's mental model isn't. This shows up in practice as edge-cases-not-handled, assumptions-implicit-not-stated, and side-effects-overlooked.

The comprehension gate makes the builder articulate their model before commit; the agent verifies the articulation matches the diff. C15 is the last first-pass mechanism in Build Doctrine §6 (1d-C-1 shipped C10/C22/C7-DAG, 1d-C-2 shipped C1/C2/Check 10/Check 11/C16, 1d-C-3 shipped C9), and depends on the rung field landing in 1d-C-2 (Check 10 enforces 5-field plan-header schema including `rung: 0-5`). With the rung infrastructure live, C15 can ship.

Five implementation details require explicit decisions before C15 can be built:

1. **Rung cutoff.** Build Doctrine §6 marks C15's reliability tier as "High at R2+" but does not mechanically lock the cutoff. Choose where the gate fires before the agent + task-verifier extension is wired.
2. **Articulation field set.** Build Doctrine §6 lists four sub-sections (Spec meaning, Edge cases covered, Edge cases NOT covered, Assumptions); lock the set before authoring the template.
3. **Substance threshold per field.** Articulations must clear a substance bar to count, not just be non-empty. Pick the threshold before authoring the agent rubric.
4. **Verdict propagation semantics.** Build Doctrine §6 specifies the gate is "enforced by `task-verifier` invoking it" but does not lock what task-verifier does on FAIL/INCOMPLETE. Pick the semantics before extending task-verifier.
5. **Articulation block location.** The articulation could live in the plan file (alongside tasks) or in the Evidence Log (alongside the task's evidence block). Pick the location before authoring the template + the rule.

Without (1) through (5), the agent cannot be authored against a stable contract.

## Decision

### Decision 020a — Rung-2 cutoff

The comprehension-gate fires at `rung: 2` and above only. R0/R1 plans skip the gate; `task-verifier` proceeds with its existing logic without invoking `comprehension-reviewer`.

Rationale: at R0/R1 (single-file diffs, no behavioral contracts required), the diff is small enough that misunderstanding shows up directly in code-review — the gate would be overhead without commensurate reliability gain. At R2+ (multi-file or behavioral-contract scopes), the diff is large enough that misunderstanding can hide; the gate becomes load-bearing. The rung-2 cutoff matches Build Doctrine §6's "High reliability at R2+" classification and aligns with Check 11's behavioral-contracts cutoff (also R2+) so a single rung threshold gates both substance bars.

### Decision 020b — Four required articulation fields, locked

Every articulation block declares exactly these four sub-sections, in this order:

1. **Spec meaning** — what the spec asks for, in the builder's words.
2. **Edge cases covered** — which edge cases the diff handles, with file:line citations.
3. **Edge cases NOT covered** — honest list of gaps the diff does not address; if zero, the builder justifies why none exist.
4. **Assumptions** — premises the diff relies on (about callers, environment, data shape, future maintainers).

The four are locked. Expanding the schema (e.g., adding a "threat model" sub-section for security-shaped tasks) requires a new ADR. Build Doctrine §6 lists exactly these four; we honor that lock without inflation.

### Decision 020c — ≥ 30-character substance threshold per field

Each of the four sub-sections must contain at least 30 non-whitespace characters of substantive content to count as populated. Below the threshold returns FAIL with the specific sub-section named.

Rationale: this mirrors the same threshold used in Phase 1d-C-2's behavioral-contracts validator (Check 11 sub-entries) — keeping a consistent substance bar across mechanisms means builders don't have to learn a different threshold per gate. Stricter than "non-empty" (which lets vacuous one-liners through); lighter than full-paragraph review (which would block legitimate-but-concise articulations).

### Decision 020d — FAIL/INCOMPLETE blocks the checkbox flip

`task-verifier` propagates the comprehension-reviewer verdict:

- `comprehension-reviewer` returns **PASS** → `task-verifier` proceeds with its existing verification logic (typecheck, evidence-block format, runtime-verification correspondence).
- `comprehension-reviewer` returns **FAIL** → `task-verifier` returns FAIL. Do not flip the checkbox. Surface the reviewer's specific feedback (which sub-section failed, the reason) to the builder so the builder can revise the articulation or the diff.
- `comprehension-reviewer` returns **INCOMPLETE** (typically: missing articulation block; missing one or more sub-sections; format error preventing parse) → `task-verifier` returns FAIL with the reviewer's specific message. Builder must add the missing content and re-invoke task-verifier.

Rationale: a comprehension gap is a correctness gap. If the gate flags FAIL, the diff is shipping with a model mismatch the builder hasn't reconciled — that is exactly the class of vaporware C15 exists to prevent. Allowing PASS-by-default-on-reviewer-error would defeat the gate.

### Decision 020e — Articulation block lives in Evidence Log, not the plan file

Builders write the articulation as a `## Comprehension Articulation` sub-section inside their evidence block — that is, inside the task's entry under `## Evidence Log` in the plan file (the section task-verifier already writes evidence into). The articulation is part of the evidence audit trail, not part of the plan's task list or scope sections.

Rationale: keeps the audit trail co-located with evidence; avoids cluttering plan files with builder-specific content (the Tasks and Files-to-Modify sections stay focused on what the planner specified). Also: the articulation is per-task, not per-plan — multiple tasks on the same plan each get their own articulation, naturally housed under their own evidence block. Putting them in the plan body would force builders to invent a per-task naming convention; nesting under the existing per-task evidence block is structurally clean.

## Alternatives considered

- **Rung-3 cutoff.** Rejected. Defers the gate to where it is least valuable: R3+ already get behavioral-contracts review per Check 11, and R2 is where bare diff review starts becoming insufficient. Skipping R2 leaves the most common multi-file plans without comprehension coverage.
- **Rung-1 cutoff.** Rejected. Overhead exceeds reliability gain at R1. Single-file diffs do not hide misunderstandings the way multi-file diffs do; running the gate on every R1 task adds ~30s of wall time per task without surfacing meaningful gaps in practice.
- **Builder articulates in the plan file directly (e.g., a `## Comprehension Articulations` section).** Rejected. Would clutter plan files with per-task builder content; conflicts with frozen-spec discipline (Decision 016) which keeps the plan file's spec sections stable post-freeze. Per-task articulations belong with per-task evidence.
- **Free-form articulation (no required field set).** Rejected. Without required fields, vague "I understood it" content passes; the agent has no rubric for surfacing gaps. The four required fields force the builder to explicitly name what they understood, what edge cases they handled, what they did not handle, and what they assumed — exactly the dimensions where comprehension fails.
- **Third-party agent (separate from task-verifier) invokes comprehension-reviewer.** Rejected. Would split the audit trail: task-verifier owns the checkbox flip, but comprehension-reviewer would be invoked elsewhere. Keeping the chain builder → task-verifier → comprehension-reviewer means the comprehension verdict propagates through the existing single-invocation gate; no parallel enforcement path to maintain.
- **Six-field schema (add "side effects" + "rollback plan").** Rejected. Build Doctrine §6 lists four; the extra two overlap with existing sections (Failure-mode analysis covers rollback; the Files-to-Modify section names side-effected files). Holding the line at four matches the doctrine and avoids inflation.
- **Substance threshold by character count alone, no diff-correspondence check.** Rejected. The 30-char threshold is necessary but not sufficient — generic articulations that clear the threshold but could apply to any task would still pass. The agent rubric in Task 3 of the parent plan layers diff-correspondence on top of the threshold (each claimed edge-case-covered must have corresponding diff content; generic content fails).

## Consequences

**Enables:**
- R2+ tasks now have a comprehension audit point. Misunderstandings that previously slipped past code-review surface as articulation-vs-diff mismatches the agent flags.
- The chain builder → task-verifier → comprehension-reviewer is the single invocation path; no parallel enforcement to maintain.
- The articulation block becomes durable evidence: future-session readers see what the builder thought they were building, not just what they shipped.

**Costs:**
- One extra agent invocation per R2+ task (~30s of wall time per task; reviewer invocations do not count against tool-call-budget per Decision-021-equivalent precedent for plan-evidence-reviewer audits).
- Builders at R2+ must write four sub-sections of substantive content per task. The 30-char threshold keeps the floor low; thoughtful builders will write more than 30 chars per field anyway.
- Templates and rules must teach the four-field schema; harness-architecture inventory and vaporware-prevention enforcement-map both grow by one row.

**Depends on:**
- The `rung:` field in plan headers landed in 1d-C-2 via Check 10. Without it, the cutoff cannot fire mechanically.
- task-verifier is the single invocation point for checkbox flips. The existing verifier mandate (only task-verifier flips checkboxes) is preserved; the gate adds a precondition, not a parallel path.

**Propagates downstream:**
- `vaporware-prevention.md` enforcement map grows by one row pointing at `comprehension-reviewer.md` + the task-verifier extension.
- `harness-architecture.md` inventory grows by one new agent + one new rule + one new template + one modified agent.
- `docs/failure-modes.md` grows by FM-023 `vaporware-spec-misunderstood-by-builder` — the failure class C15 prevents.

**Blocks:**
- R2+ task-verifier runs whose evidence block lacks a `## Comprehension Articulation` section, or whose articulation has a sub-section below the substance threshold, or whose articulation claims edge-case coverage the diff does not provide. Recovery: builder revises the articulation or the diff; re-invokes task-verifier.

## Implementation status

Active — to be implemented across Tasks 1-5 of the parent plan. Task 1 (this commit) lands the decision record + the template + the DECISIONS.md row. Task 2 lands the rule (`comprehension-gate.md`). Task 3 lands the agent (`comprehension-reviewer.md`). Task 4 extends `task-verifier.md` with the gate-invocation block. Task 5 lands FM-023, harness-architecture inventory updates, and the vaporware-prevention enforcement-map row.

## Failure modes catalogued

- `FM-023 vaporware-spec-misunderstood-by-builder` — to be added to `docs/failure-modes.md` in Task 5 of the parent plan. Symptom: a builder ships a syntactically-correct diff that passes typecheck and matches the spec on its face, while having silently misunderstood an edge case, an assumption, or the spec's intent. The diff is correct; the mental model is not. Detection: comprehension-reviewer's articulation-vs-diff cross-check at R2+. Prevention: the comprehension-gate forces the builder to articulate the four required dimensions before commit; the agent fails the verdict when the articulation does not correspond to the diff. Example: a builder modifies an auth helper to handle a new role, articulates "Edge cases covered: empty role string returns 401" but the diff returns 403 for empty role — articulation-vs-diff mismatch, FAIL.

## Cross-references

- `docs/plans/phase-1d-c-4-comprehension-gate.md` — the implementing plan
- `adapters/claude-code/templates/comprehension-template.md` — canonical template (Task 1, this commit)
- `adapters/claude-code/agents/comprehension-reviewer.md` — the reviewer agent (Task 3)
- `adapters/claude-code/agents/task-verifier.md` — extended in Task 4 to invoke the gate at R2+
- `adapters/claude-code/rules/comprehension-gate.md` — the rule documenting when and how (Task 2)
- `adapters/claude-code/rules/vaporware-prevention.md` — extended in Task 5 with one new enforcement-map row
- `docs/harness-architecture.md` — extended in Task 5 with the new inventory entries
- `docs/failure-modes.md` — extended in Task 5 with FM-023
- Decision 017 — 5-field plan-header schema; ships the `rung:` field this gate depends on
- Decision 019 — findings-ledger format; the precedent for shipping a Build Doctrine §6 first-pass mechanism via decision + template + rule + agent + inventory updates
- Build Doctrine §6 C15 — the original specification for the comprehension-gate agent
