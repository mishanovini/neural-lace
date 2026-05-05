# Plan: Phase 1d-E-2 — Audit + cleanup batch (GAP-10 sub-gaps A/B/C/F/H)

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-GAP-10 sub-gap A, HARNESS-GAP-10 sub-gap B, HARNESS-GAP-10 sub-gap C, HARNESS-GAP-10 sub-gap F, HARNESS-GAP-10 sub-gap H
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product-user surface to verify at runtime. Each sub-gap produces an audit document or a small structural change; verification is per-task review of the audit output + filesystem change.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Context

Phase 1d-E-2 is the audit + cleanup follow-up in the Phase 1d-E series (1d-E-1 shipped P1 drift fixes). This batch addresses five HARNESS-GAP-10 sub-gaps that surfaced during Build Doctrine integration analysis. Each sub-gap is a small audit or structural cleanup; together they sharpen the harness's documentation-vs-mechanism boundary.

**Sub-gap A — Stop-hook overlap analysis.** Five Stop hooks (`narrate-and-wait-gate`, `transcript-lie-detector`, `goal-coverage-on-stop`, `imperative-evidence-linker`, `deferral-counter`) all detect narrative-integrity failures with adjacent classes. Need a written orthogonality matrix.

**Sub-gap B — `pipeline-agents.md` project-specific in global rules.** The rule references roles and failure patterns specific to one downstream project. Relocate or restructure.

**Sub-gap C — `claim-reviewer` post-Gen6 reassessment.** `claim-reviewer` was the residual mitigation for verbal vaporware. Gen 6 narrative-integrity hooks may have superseded most of it. Audit each class it was meant to catch.

**Sub-gap F — Rules possibly superseded by hooks need audit.** Multiple rule files may have mechanism content that's now hook-enforced; their prose remains as-if-authoritative. Candidates: `testing.md` (TDD enforced by `pre-commit-tdd-gate.sh`), portions of `diagnosis.md`, portions of `git.md`.

**Sub-gap H — `docs/reviews/` gitignore overly broad.** `docs/reviews/` is gitignored to prevent downstream-project reviews leaking into NL, but the gitignore also makes legitimate NL-self-reviews invisible to `bug-persistence-gate.sh`.

## Goal

Five small audits / cleanups ship in one coherent unit, each with a deliverable artifact:

1. **Sub-gap A — Stop-hook orthogonality matrix.** A markdown table at `docs/reviews/2026-05-04-stop-hook-orthogonality.md` (or a project-architecture sub-document) listing the five Stop hooks pairwise; for each pair, one example the first catches that the second misses. Recommendation per pair: keep separate / consolidate / clarify boundary.

2. **Sub-gap B — `pipeline-agents.md` relocation.** Move project-specific content out of `~/.claude/rules/pipeline-agents.md`. Either (a) relocate to a project's `.claude/rules/`, OR (b) generalize the rule to be tool-agnostic, OR (c) delete and rely on per-project CLAUDE.md.

3. **Sub-gap C — `claim-reviewer` reassessment.** A per-class table mapping each behavior `claim-reviewer` was meant to catch to whether a Gen 6 hook now catches it. Recommendation: deprecate / keep / mechanize.

4. **Sub-gap F — Rules-superseded-by-hooks audit.** A per-rule audit at `docs/reviews/2026-05-04-rules-vs-hooks-audit.md`. For each `~/.claude/rules/*.md` file, identify which sections are operationalized by hooks. Rules where >70% of content is hook-enforced get a stub-style restructuring recommendation (mirror `vaporware-prevention.md`'s pattern).

5. **Sub-gap H — `docs/reviews/` gitignore refinement.** Refine `.gitignore` to exclude downstream-project reviews specifically (by naming convention) while allowing NL-self-reviews. Document the convention so future reviewers know which directory to use.

## Scope

**IN:**
- `docs/reviews/2026-05-04-stop-hook-orthogonality.md` — NEW (audit output for Sub-gap A)
- `adapters/claude-code/rules/pipeline-agents.md` — EDIT or DELETE (Sub-gap B)
- `~/.claude/rules/pipeline-agents.md` — EDIT or DELETE (mirror)
- `docs/reviews/2026-05-04-claim-reviewer-reassessment.md` — NEW (audit output for Sub-gap C)
- `docs/reviews/2026-05-04-rules-vs-hooks-audit.md` — NEW (audit output for Sub-gap F)
- `.gitignore` — EDIT (Sub-gap H)
- `docs/backlog.md` — EDIT (mark sub-gaps closed in "Recently implemented" section)
- `docs/harness-architecture.md` — EDIT if any rule reorganization triggers inventory updates

**OUT:**
- HARNESS-GAP-14 template-vs-live reconciliation — Phase 1d-E-3 (its own focused plan with the documented orchestrator-research methodology).
- HARNESS-GAP-15 codename scrub + un-archived plans — Phase 1d-E-4.
- HARNESS-GAP-10 sub-gap G definition-on-first-use — Phase 1d-F.
- HARNESS-GAP-10 sub-gap D telemetry — gated on 2026-08; deferred.
- HARNESS-GAP-10 sub-gap E concrete-invariants — already absorbed into 1d-C-2.
- HARNESS-GAP-08 spawn_task report-back — substantive new mechanism; deferred to a focused plan.
- HARNESS-GAP-13 hygiene-scan expansion — substantive new mechanism; deferred.

## Tasks

- [x] **1. Sub-gap A — Stop-hook orthogonality matrix.** Author the audit document. Read each of the five Stop hooks; write a 5x5 orthogonality matrix where each cell `(row=A, col=B)` names ONE specific example A catches but B does NOT. Recommendation per pair. If any pair has no clear separation, list as "candidate for consolidation". Single commit.

- [x] **2. Sub-gap B — `pipeline-agents.md` relocation/restructure.** Read the rule. Identify project-specific content vs general-purpose content. Take the action that fits the analysis: relocate project-specific content (back-stop: delete the file when its content is wholly project-specific). Update any references. Sync to live. Single commit.

- [x] **3. Sub-gap C — `claim-reviewer` reassessment.** Author audit document at `docs/reviews/2026-05-04-claim-reviewer-reassessment.md`. Read `~/.claude/agents/claim-reviewer.md` to enumerate claim classes; for each, identify whether a Gen 6 hook now catches it (`transcript-lie-detector`, `goal-coverage-on-stop`, `imperative-evidence-linker`, `deferral-counter`, `vaporware-volume-gate`). Recommendation per class: deprecate / keep / mechanize. Single commit.

- [x] **4. Sub-gap F — Rules-superseded-by-hooks audit.** Author audit document at `docs/reviews/2026-05-04-rules-vs-hooks-audit.md`. For each rule file in `~/.claude/rules/` (skip already-stub `vaporware-prevention.md`), produce: rule name, % content hook-enforced, recommendation (keep verbose / convert to stub / split into stub + extension). Single commit.

- [x] **5. Sub-gap H — `docs/reviews/` gitignore refinement.** Edit `.gitignore` to exclude downstream-project reviews specifically (by codename naming convention) while allowing NL-self-reviews (e.g., `docs/reviews/2026-*-stop-hook-*.md`, `docs/reviews/2026-*-rules-vs-hooks-*.md`). Document the naming convention in a brief comment in `.gitignore` AND in `harness-hygiene.md`. Test: `git status` after running — confirm the audit docs from Tasks 1, 3, 4 ARE tracked (visible to git) under the refined gitignore. Single commit.

- [x] **6. Decision + DECISIONS index + backlog cleanup.** Land Decision 022 if any structural decision was made (likely from Sub-gap B's relocation choice or Sub-gap H's gitignore refinement). Update `docs/DECISIONS.md`. Update `docs/backlog.md` "Recently implemented" section with the 5 sub-gap closures. Single commit.

## Files to Modify/Create

- `docs/reviews/2026-05-04-stop-hook-orthogonality.md` — NEW.
- `docs/reviews/2026-05-04-claim-reviewer-reassessment.md` — NEW.
- `docs/reviews/2026-05-04-rules-vs-hooks-audit.md` — NEW.
- `adapters/claude-code/rules/pipeline-agents.md` — EDIT or DELETE.
- `~/.claude/rules/pipeline-agents.md` — EDIT or DELETE (gitignored mirror).
- `.gitignore` — EDIT.
- `adapters/claude-code/rules/harness-hygiene.md` — EDIT (document naming convention if Sub-gap H applies).
- `docs/decisions/022-*.md` — NEW (if applicable from Sub-gap B or H decision).
- `docs/DECISIONS.md` — EDIT.
- `docs/backlog.md` — EDIT.
- `docs/harness-architecture.md` — EDIT if rule reorganization warrants.

## In-flight scope updates

- `docs/plans/phase-1d-e-2-audit-cleanup-evidence.md` — added 2026-05-04 by orchestrator. Standard task-verifier companion.

## Assumptions

- The five Stop hooks listed in Sub-gap A all currently exist in `~/.claude/hooks/` and have header-comments explaining their purpose. Audit reads from those headers + the hook bodies.
- `pipeline-agents.md` exists in both `adapters/claude-code/rules/` (committed) and `~/.claude/rules/` (live). Cleanup applies to both layers.
- The `docs/reviews/` directory exists; it's already gitignored. The audit documents from Tasks 1/3/4 will be the test cases for Sub-gap H's refinement (they should be VISIBLE to git after the gitignore change).
- Each audit task's output is a markdown document of ~100-200 lines. Substance > brevity.
- `claim-reviewer.md` agent file contains an enumeration of claim classes it's meant to catch; these are the classes Sub-gap C will map.
- Rule files in `~/.claude/rules/` are independent; restructuring one doesn't affect the others. Audit can proceed file-by-file without cross-coordination.

## Edge Cases

- **Sub-gap A finds no overlap to consolidate.** Record "all five hooks are sufficiently orthogonal" with citing examples; no action item flows downstream. The audit document still ships.
- **Sub-gap B finds `pipeline-agents.md` is fully project-specific.** Recommendation: delete from global, optionally archive in a project-specific location. The deletion itself is the action.
- **Sub-gap C finds `claim-reviewer` is fully superseded by Gen 6 hooks.** Recommendation: deprecate the agent (mark its frontmatter; document the deprecation in the agent file's body). Don't delete — kept for historical reference.
- **Sub-gap F finds a rule is 100% hook-enforced.** Recommendation: convert to stub. The stub conversion may be a significant edit; defer the conversion itself to a follow-up plan if scope balloons.
- **Sub-gap H gitignore refinement breaks `git ls-files --exclude-standard`.** Test the refined gitignore against `bug-persistence-gate.sh`'s glob to confirm legitimate NL-self-reviews are visible to git but downstream-project reviews remain ignored. If both can't be satisfied with a single gitignore pattern, fall back to relocating NL-self-reviews to a sub-directory.

## Acceptance Scenarios

(none — `acceptance-exempt: true`. Verification per task: audit document substance check + filesystem state check.)

## Out-of-scope scenarios

- Implementing the recommendations from the audits. Each audit document declares what should change; the actual implementation (e.g., converting a rule to a stub) is a follow-up plan if the recommendation is non-trivial.

## Testing Strategy

Each task task-verified against:
1. The deliverable artifact (audit document or filesystem change) exists at the declared path.
2. Substance check: audit documents have substance per the task description (orthogonality matrix populated; per-rule analysis per Sub-gap F; per-class mapping per Sub-gap C).
3. For Sub-gap H: verify `git status` shows the audit documents as tracked-or-trackable after the gitignore edit.
4. For Sub-gap B: verify the rule is removed from the relocation source AND added to the relocation target (if applicable), or deleted cleanly.

## Walking Skeleton

Sub-gap A's audit document is the smallest unit and the most independent — it ships value alone (the orthogonality matrix is useful even if Sub-gaps B/C/F/H are deferred). Start there.

## Decisions Log

(populated during implementation)

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept, 0 matches stranded; tasks cite each artifact and its target file path.
- S2 (Existing-Code-Claim Verification): swept, 6 claims (claim-reviewer.md exists; pipeline-agents.md exists in both layers; .gitignore current state; vaporware-prevention.md is a stub; bug-persistence-gate uses `git ls-files --exclude-standard`; the five Stop hooks exist) — all 6 verified.
- S3 (Cross-Section Consistency): swept, 0 contradictions.
- S4 (Numeric-Parameter Sweep): swept for [5 sub-gaps absorbed, 5 stop hooks listed in Sub-gap A] — values consistent.
- S5 (Scope-vs-Analysis Check): swept, 0 contradictions; Scope OUT items are not contradicted by any prescription.

## Definition of Done

- [x] All 6 tasks task-verified PASS (commits fd9f663, d8b30f3, 7abe23e, 6d30d7b).
- [x] Three audit documents shipped under `docs/reviews/`.
- [x] `pipeline-agents.md` deleted per Sub-gap B's analysis (Decision 022).
- [x] `.gitignore` already correctly designed via date-prefix allowlist; convention now documented in harness-hygiene.md.
- [x] Backlog "Recently implemented" updated with the 5 sub-gap closures.
- [x] Plan archived (this Status flip triggers auto-archive).

## Completion Report

All 6 tasks shipped. Decision 022 (pipeline-agents.md deletion) landed. Three audit docs in `docs/reviews/`. Single coherent batch closing 5 sub-gaps from the Build Doctrine integration analysis.
