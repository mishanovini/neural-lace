# Plan: Phase 1d-C-4 — Comprehension-gate agent (C15)

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product-user surface to verify at runtime. Verification is per-agent test invocation against synthetic articulations + per-task task-verifier PASS + plan-reviewer self-test PASS for the rung-aware extension.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Context

Phase 1d-C-4 is the fourth and final batch of the Build Doctrine §6 first-pass mechanisms (1d-C-1 shipped C10/C22/C7-DAG; 1d-C-2 shipped C1/C2/Check 10/Check 11/C16; 1d-C-3 shipped C9). C15 is the last first-pass mechanism. Per §6:

> **C15 — Comprehension-gate agent (`comprehension-reviewer.md`).** Trigger: self-invoked by builder before commit (mandatory at R2+); enforced by `task-verifier` invoking it. Enforcement target: builder articulates spec meaning + edge cases covered + edge cases NOT covered + assumptions; agent verifies articulation matches diff. Operationalizes: Phase 1b N-G-1. Classification: Hybrid (agent invocation = Mechanism; substance review = LLM-assisted). Reliability: **High** at R2+. Cost: Medium. Dependencies: rung field in plan header.

The dependency on rung field landed in 1d-C-2 (Check 10 enforces 5-field plan-header schema including `rung: 0-5`). With the rung infrastructure live, C15 can ship.

**Why C15 matters.** Adversarial reviewers (`code-reviewer`, `task-verifier`, `plan-evidence-reviewer`) verify **what was written**. None verifies that the **builder understood what was supposed to be written**. A builder can produce a syntactically-correct diff that passes typecheck and even matches a section of the spec — while having silently misunderstood an edge case, an assumption, or the spec's intent. The diff is correct; the builder's mental model isn't. This is the comprehension gap, and it shows up in practice as edge-cases-not-handled, assumptions-implicit-not-stated, and side-effects-overlooked. The comprehension gate makes the builder articulate their model before commit; the agent verifies the articulation matches the diff.

**Reliability tier.** R2+ (rung 2 and above). At R0/R1 (single-file diffs, no behavioral contracts required), a comprehension gate is overhead without commensurate reliability gain — the diff is small enough that misunderstanding shows up directly in code-review. At R2+ (multi-file or behavioral-contract scopes), the diff is large enough that misunderstanding can hide; the gate becomes load-bearing.

Source-of-truth: `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 C15.

## Goal

Three artifacts ship in one coherent unit:

1. **`comprehension-reviewer.md` agent (NEW).** Adversarial peer to `task-verifier`. Invoked at R2+ before checkbox flip. Reads the builder's comprehension articulation (a specific markdown block: spec-meaning + edge-cases-covered + edge-cases-NOT-covered + assumptions) AND the staged diff. Returns PASS / FAIL / INCOMPLETE with class-aware feedback per the seven adversarial-review agent standard.
2. **`task-verifier` extension.** When verifying a task on a plan with `rung >= 2`, task-verifier MUST invoke `comprehension-reviewer` BEFORE flipping the checkbox. comprehension-reviewer FAIL/INCOMPLETE blocks the flip; PASS allows verification to proceed normally.
3. **`comprehension-gate.md` rule.** Documents when the gate fires, what the builder must articulate, the articulation format, the agent's verification rubric, the rung-2 cutoff rationale, and the failure-mode catalog entry.

Plus enabling work:
- Decision 020 (comprehension-gate semantics — locks the rung-2 cutoff, the four required articulation fields, the agent invocation point in task-verifier, the FAIL/INCOMPLETE blocking semantics).
- New template `comprehension-template.md` showing the markdown shape of a builder articulation.
- New failure-mode entry FM-023 `vaporware-spec-misunderstood-by-builder`.
- Extension of `vaporware-prevention.md` enforcement map: 1 new row (comprehension-gate).
- Extension of `harness-architecture.md` inventory: 1 new agent + 1 new rule + 1 new template + 1 modified agent.

## Scope

**IN:**
- `adapters/claude-code/agents/comprehension-reviewer.md` — NEW agent file with full Output Format Requirements, class-aware feedback contract, rubric for the four articulation fields.
- `adapters/claude-code/agents/task-verifier.md` — EDIT to add the comprehension-gate invocation block at rung >= 2, before checkbox flip.
- `adapters/claude-code/templates/comprehension-template.md` — NEW template showing the markdown shape: a `## Comprehension Articulation` block with four required sub-sections (Spec meaning, Edge cases covered, Edge cases NOT covered, Assumptions), each ≥ 30 non-whitespace characters of substance.
- `adapters/claude-code/rules/comprehension-gate.md` — NEW rule documenting the gate, the rung-2 cutoff, the articulation format, the agent rubric, examples of PASS / FAIL / INCOMPLETE, and the failure-mode entry.
- `adapters/claude-code/rules/vaporware-prevention.md` — EDIT to add 1 new enforcement-map row (Comprehension articulation required at R2+ → comprehension-reviewer agent + task-verifier extension).
- `docs/decisions/020-comprehension-gate-semantics.md` — NEW decision record.
- `docs/DECISIONS.md` — EDIT to add row for 020.
- `docs/failure-modes.md` — EXTEND with FM-023 `vaporware-spec-misunderstood-by-builder`.
- `docs/harness-architecture.md` — EDIT inventory tables for the new + modified files.

**OUT:**
- C13 promotion/demotion gate — separate plan; depends on C9 (shipped) + C14 (second-pass) + C15 (this plan).
- C14 holdout-scenarios gate — second-pass; depends on rung field (which is live) but blocked on C13 sequencing.
- Builder-side automation that auto-generates the articulation block — Build Doctrine §6 leaves the articulation as the builder's deliberate work; we keep that discipline.
- LLM-assisted automated rubric tightening from accumulated PASS/FAIL data — second-pass; depends on findings ledger (C9, shipped) plus telemetry (HARNESS-GAP-10 sub-gap D, 2026-08).
- Per-project comprehension-gate adoption (downstream projects opt in via separate plans).
- Backporting comprehension-gate retroactively to already-built plans at R2+.

## Tasks

- [x] **1. Decision 020 + comprehension-template.md.** Land Decision 020 (comprehension-gate semantics: rung-2 cutoff, four required articulation fields, ≥ 30-char substance threshold per field, FAIL/INCOMPLETE blocks task-verifier's checkbox flip, agent invokes via Task tool). Create `comprehension-template.md` showing the markdown shape: top-of-file schema-spec block + a sample articulation with each of the four sub-sections populated for a synthetic R2 task. Update `docs/DECISIONS.md` with the row. Single commit.

- [x] **2. Rule docs — comprehension-gate.md.** NEW rule documenting: when the gate fires (R2+ tasks; task-verifier auto-invokes), what the builder must articulate (the four sub-sections per Decision 020), the articulation format (template at `comprehension-template.md`), the agent rubric (each sub-section graded for substance + diff-correspondence; PASS requires the four sub-sections valid; FAIL on any vacuous; INCOMPLETE on missing sub-section), examples of each verdict, and the rung-2 cutoff rationale. Cross-references to Decision 020, the agent, the failure-mode entry, the enforcement-map row. Single commit.

- [ ] **3. Agent — comprehension-reviewer.md.** NEW agent file. Front-matter declaring tools (Read, Grep, Glob — no write tools). Output Format Requirements section per the class-aware feedback contract (Class:, Sweep query:, Required generalization: where applicable). Three-stage rubric: (a) parse the builder's articulation block; (b) verify each sub-section meets the ≥ 30-char substance threshold + non-placeholder content; (c) cross-check articulation against staged diff (read changed files; verify each claimed edge-case-covered actually has corresponding diff content; verify edge-cases-NOT-covered is honest about gaps). Returns PASS / FAIL / INCOMPLETE. Single commit.

- [ ] **4. task-verifier extension.** EDIT `task-verifier.md` to add the comprehension-gate invocation block: when the plan's `rung:` field is ≥ 2, task-verifier MUST invoke `comprehension-reviewer` via Task tool with the plan path, task ID, and the builder's articulation block. comprehension-reviewer FAIL or INCOMPLETE → task-verifier returns FAIL (do not flip checkbox); comprehension-reviewer PASS → task-verifier proceeds with its existing verification logic. The articulation block is expected at the bottom of the task's Evidence Log entry per the template. Single commit.

- [ ] **5. FM catalog + harness-architecture inventory + vaporware-prevention enforcement map.** Add FM-023 `vaporware-spec-misunderstood-by-builder` to `docs/failure-modes.md` with the six-field schema (ID, Symptom, Root cause, Detection, Prevention, Example). Add inventory entries to `docs/harness-architecture.md` for the new agent + new rule + new template + modified task-verifier. Update `vaporware-prevention.md` enforcement map with 1 new row pointing at `comprehension-reviewer.md` + task-verifier extension. Single commit.

## Files to Modify/Create

- `adapters/claude-code/agents/comprehension-reviewer.md` — NEW.
- `adapters/claude-code/agents/task-verifier.md` — EDIT.
- `adapters/claude-code/templates/comprehension-template.md` — NEW.
- `adapters/claude-code/rules/comprehension-gate.md` — NEW.
- `adapters/claude-code/rules/vaporware-prevention.md` — EDIT.
- `docs/decisions/020-comprehension-gate-semantics.md` — NEW.
- `docs/DECISIONS.md` — EDIT.
- `docs/failure-modes.md` — EXTEND.
- `docs/harness-architecture.md` — EDIT.

## In-flight scope updates

- `docs/plans/phase-1d-c-4-comprehension-gate-evidence.md` — added 2026-05-04 by orchestrator. The evidence file is the standard task-verifier companion and is created automatically on the first task verification. Adding here to satisfy scope-enforcement-gate without spec-thaw.

## Assumptions

- The `rung:` field in plan headers is canonical and reliable. It landed in 1d-C-2 via Check 10 and is enforced on `Status: ACTIVE` plans.
- The four articulation fields (Spec meaning, Edge cases covered, Edge cases NOT covered, Assumptions) are sufficient to surface comprehension gaps. Build Doctrine §6 lists exactly these four; we honor that lock.
- The ≥ 30-char substance threshold mirrors the same threshold from Phase 1d-C-2's behavioral-contracts validator (Check 11 sub-entries) — keeping a consistent substance bar across mechanisms.
- task-verifier is the single invocation point. Builder agents (`plan-phase-builder` and the bare main session) MUST invoke task-verifier per the existing verifier mandate; task-verifier invokes comprehension-reviewer at R2+. There is no separate "builder must invoke comprehension-reviewer" step; the chain is builder → task-verifier → comprehension-reviewer.
- comprehension-reviewer is read-only (no Edit/Write tools). Its job is judgment, not file mutation. The verdict propagates to task-verifier which decides whether to flip the checkbox.
- The articulation block lives in the Evidence Log, not in the plan file proper. This avoids cluttering the plan with builder-specific content and keeps the audit trail with the evidence.
- Failed comprehension-gate runs do NOT count against tool-call-budget (they are reviewer invocations, not builder work). This matches the existing behavior for plan-evidence-reviewer audits.

## Edge Cases

- **Plan with no `rung:` field.** Per Check 10 (1d-C-2), `Status: ACTIVE` plans MUST declare rung. If somehow a plan lacks the field, task-verifier treats it as `rung: 0` and the comprehension gate does not fire. Plan-reviewer catches the missing field at edit time before this can happen.
- **Plan with `rung: 0` or `rung: 1`.** Comprehension-gate is a no-op. task-verifier proceeds with its existing logic.
- **Plan with `rung: 2` (or higher) but builder's evidence block has no `## Comprehension Articulation` section.** comprehension-reviewer returns INCOMPLETE with a specific message naming the missing section. task-verifier returns FAIL. Builder must add the articulation and re-invoke task-verifier.
- **Articulation block with one or more sub-sections under the substance threshold.** comprehension-reviewer returns FAIL with the specific sub-section(s) named.
- **Articulation block claims edge-case-covered that the diff doesn't actually cover.** comprehension-reviewer returns FAIL with the specific claim and the diff gap.
- **Articulation block honestly claims an edge case is NOT covered.** PASS — honesty about gaps is exactly what we want. The downstream consequence (whether to defer the gap to a follow-up task or expand scope) is the planner's call, not the comprehension-gate's call.
- **Builder articulates four sub-sections but their content is generic (could apply to any task).** comprehension-reviewer's diff-correspondence check catches this — generic content doesn't cite specific files / lines / decisions, so the diff-correspondence check fails. FAIL.
- **Multiple parallel builders, each with their own articulation.** task-verifier runs sequentially per the orchestrator pattern's "build-in-parallel, verify-sequentially" rule. comprehension-reviewer runs once per task, not once per parallel build.
- **Plan transitions from `rung: 1` to `rung: 2` mid-build (rung-revision via in-flight scope updates).** Per the freeze-thaw protocol, this is a rare deliberate amendment. Tasks already verified at the prior rung do not retroactively need a comprehension-gate run; new tasks fired after the rung increase do.

## Acceptance Scenarios

(none — `acceptance-exempt: true`. Verification is via per-agent test invocation against synthetic articulations + per-task task-verifier PASS + plan-reviewer self-test PASS for the rung-aware extension.)

## Out-of-scope scenarios

- Per-builder customization of articulation field set (e.g., a security-builder needing a fifth "threat model" sub-section). If this need surfaces, expand the schema in a follow-up plan.
- Comprehension-gate for plan-time reviewers (do they comprehend the spec they're reviewing?). The gate is about builder-side comprehension; reviewer-side comprehension is HARNESS-GAP-11's reviewer-accountability concern.
- Cross-plan comprehension carry-over (does the builder of plan B understand what plan A's builder shipped?). Out of scope; if needed, surfaces as a separate harness gap.

## Testing Strategy

Each task is verified by `task-verifier` per the harness's verifier mandate. The new agent is tested via:

1. **Synthetic-articulation tests** (Task 3 + Task 5): exercise comprehension-reviewer with three synthetic articulations — one PASS-shaped (all four fields substantive + diff-correspondent), one FAIL-shaped (one field below threshold), one INCOMPLETE-shaped (missing one sub-section). Confirm the verdict in each case.
2. **task-verifier extension test** (Task 4): exercise task-verifier against a synthetic R2 plan with a synthetic articulation; confirm task-verifier invokes comprehension-reviewer and propagates the verdict.
3. **plan-reviewer compatibility check** (Task 5): confirm Check 10 + Check 11 still pass on a plan declaring `rung: 2` plus the existing behavioral-contracts section.
4. **vaporware-prevention enforcement map sanity check** (Task 5): the new row's File column resolves to an artifact on disk.
5. **harness-architecture inventory cross-check** (Task 5): every modified file's inventory entry resolves to its actual file.

No `--self-test` invocations apply (this is an agent + rule, not a hook). The agent's rubric IS its self-test, exercised through Task 3 + Task 5 verification.

## Walking Skeleton

The minimum viable shape: comprehension-reviewer.md agent file + task-verifier extension + a single template entry that exercises the gate against a synthetic R2 articulation. Once that round-trip works (builder writes articulation → task-verifier invokes comprehension-reviewer → verdict propagates), the rest is documentation (rule, decision record, FM entry, inventory updates).

## Decisions Log

(populated during implementation per Mid-Build Decision Protocol; Decision 020 is landed by Task 1 as a Tier 2 ADR)

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept, 0 matches — single agent + 1 task-verifier extension; no behavior changes are stranded in analysis sections (the `## Goal` enumerates them and each maps to a Task).
- S2 (Existing-Code-Claim Verification): swept, 4 claims (`task-verifier.md` exists at the cited path; rung field landed in 1d-C-2 Check 10; behavioral-contracts threshold mirrors Check 11; class-aware feedback contract is the seven-agent standard) — all 4 verified against the actual files at audit time.
- S3 (Cross-Section Consistency): swept, 0 contradictions — the rung-2 cutoff, the four articulation fields, and the FAIL/INCOMPLETE blocking semantics are stated identically in Goal, Tasks, Edge Cases, and Decisions Log carry-forward.
- S4 (Numeric-Parameter Sweep): swept for params [rung-2 cutoff = 2, substance threshold = 30 chars] — both values appear consistently throughout. No drift.
- S5 (Scope-vs-Analysis Check): swept, 0 contradictions — every `Add` / `Modify` / `New` verb in the analysis sections targets a file in `## Files to Modify/Create`. Scope OUT items (C13, C14, downstream-project adoption) are not contradicted by any prescription in the analysis.

## Definition of Done

- [ ] All 5 tasks checked off (each via task-verifier, with comprehension-gate firing on this plan as a self-test of itself once Task 4 lands — meta-validation).
- [ ] Decision 020 landed and indexed.
- [ ] FM-023 added to failure-modes catalog.
- [ ] vaporware-prevention enforcement map row added; File field resolves to comprehension-reviewer.md.
- [ ] harness-architecture.md inventory updated.
- [ ] Plan-reviewer self-test still passes (no regression on Check 10 / Check 11).
- [ ] SCRATCHPAD updated with phase outcome.
- [ ] Plan archived (Status: COMPLETED → auto-archive via plan-lifecycle.sh, OR manual archive via `git mv` if Status flip happens via Bash).
