# Plan: Harness deploy-verification audit + improvement proposal
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: read-only investigation + documentation; no user-facing artifact, no running app, no acceptance scenarios to verify
tier: 1
rung: 0
architecture: doc-only
frozen: true

## Goal

Misha asked, in a Dispatch turn 2026-05-21:

> the harness is supposed to ensure that deploys actually succeed. can you
> validate that there's actually functionality in the harness for this? how do
> you think we can improve this?

Investigate the harness's current deploy-verification machinery (hooks, rules,
scripts, workflows), catalogue the conversation's observed deploy-verification
failures, propose concrete improvements with implementation sketches +
ranking, and recommend a priority set. Produce two cross-referenced docs
(read-only investigation; no implementation in this session).

## Scope

- IN:
  - Read-only inventory of `adapters/claude-code/hooks/`, `adapters/claude-code/rules/`, `adapters/claude-code/scripts/`, `.github/workflows/`, and supporting docs.
  - Cross-check the inventory against the conversation's observed failure pattern.
  - Author `docs/reviews/2026-05-21-harness-deploy-verification-audit.md` — what exists, what doesn't, why it matters.
  - Author `docs/proposals/harness-reliability-improvements-2026-05-21.md` — six proposed mechanisms (A-F), implementation sketches, effort estimates, unilateral-buildability flags, ranking matrix, recommended priority set (A+B+C).
  - This plan file itself (`docs/plans/harness-deploy-verification-investigation-2026-05-21.md`).
- OUT:
  - Implementation of any proposed mechanism (separate work; gated on Misha's decisions per the proposal §7 asks).
  - Modifications to existing hooks / rules / scripts.
  - Per-project `deploy-config.json` authoring (covered in proposal §7 ask 5).
  - Cross-repo investigation (this session investigated neural-lace only — the audit explicitly notes that limitation).

## Tasks

- [x] 1. Inventory the harness's current deploy-verification machinery. Verification: mechanical
  **Prove it works:** the audit doc's §1 lists every relevant hook, rule, script, and workflow with file paths + behavior + enforcement class.
  **Wire checks:** n/a — read-only investigation, no code wiring.
  **Integration points:** the audit doc is the durable record; cross-referenced from the proposal.

- [x] 2. Catalogue conversation-observed deploy-verification failures. Verification: mechanical
  **Prove it works:** the audit doc's §2 lists 6 failure instances (PR #19, PR #304 Sentry, PR #298 RBAC, Conv Tree 26/27/28, rate-limit silent death, PR-sitting-with-red-CI) each with a "what would have caught it" pointer to a proposal mechanism.
  **Wire checks:** n/a.
  **Integration points:** audit §2 ↔ proposal §2 (mechanism by mechanism).

- [x] 3. Propose 6 concrete improvements with implementation sketches + ranking. Verification: mechanical
  **Prove it works:** proposal doc lists mechanisms A through F, each with trigger, behavior, implementation sketch, estimated effort, unilateral-buildability flag, what it catches, limitations. Section 3 is the ranking matrix; §4 recommends A+B+C as the priority set with justification.
  **Wire checks:** n/a.
  **Integration points:** §7 lists 6 Misha-decision items including the synchronous-block-vs-background-subprocess choice for A and B.

- [x] 4. Write both docs with cross-references. Verification: mechanical
  **Prove it works:** `docs/reviews/2026-05-21-harness-deploy-verification-audit.md` exists and cross-references the proposal; `docs/proposals/harness-reliability-improvements-2026-05-21.md` exists and cross-references the audit. Naming: audit uses `YYYY-MM-DD-*` prefix per `docs/.gitignore` review-file allowlist (per `harness-hygiene.md`); proposal has no naming restriction.
  **Wire checks:** n/a.
  **Integration points:** docs/reviews/ ↔ docs/proposals/ ↔ this plan.

## Files to Modify/Create

- `docs/reviews/2026-05-21-harness-deploy-verification-audit.md` — audit doc (NEW).
- `docs/proposals/harness-reliability-improvements-2026-05-21.md` — proposal doc (NEW).
- `docs/plans/harness-deploy-verification-investigation-2026-05-21.md` — this plan (NEW, self-claiming).

## In-flight scope updates

(none)

## Assumptions

- Read-only investigation in a single Dispatch turn is sufficient — no follow-up sessions needed for the audit + proposal phase.
- Misha will review the proposal §7 asks before any A/B/C implementation begins.
- The external-monitor pattern shipped 2026-05-21 (PR #19) is the right shape to extend; the proposal builds on it rather than introducing a new pattern.

## Edge Cases

- The harness has zero active mechanism for post-push / post-merge verification — the audit names this honestly rather than fabricating coverage.
- Existing rules (`deploy-to-production.md`, `testing.md` Deployment Validation, `git-discipline.md` Rule 2) are Pattern-only — the audit cross-references them but does not claim they enforce anything.
- Some failures (Conv Tree 26/27/28, rate-limit death) are orthogonal to deploy verification — the audit notes which mechanisms are out of scope for this proposal and which would belong in a separate proposal.

## Testing Strategy

- Verification is mechanical: both docs exist at the named paths, cross-reference each other, and contain the named sections (§1-§5 in audit; §1-§8 in proposal).
- No runtime verification — these are doc artifacts, not code.
- Acceptance-exempt with substantive reason: read-only investigation + docs, no user-facing artifact.

## Walking Skeleton

(n/a — this is a single-session investigation, not a multi-phase build)

## Decisions Log

### Decision: Use `--no-verify` to bypass scope-enforcement-gate OR create a self-claiming plan
- **Tier:** 1
- **Status:** chose self-claiming plan
- **Chosen:** Author this plan file alongside the two doc commits. The gate explicitly supports "newly-staged plan file with `Status: ACTIVE` is self-claiming" (scope-enforcement-gate.sh lines ~770-780). The plan flips to `Status: COMPLETED` in the same authorship since the work is finished.
- **Alternatives:**
  - `git commit --no-verify` — doesn't actually bypass the PreToolUse Bash hook (the gate fires before git runs). Rejected: doesn't work.
  - Add the two doc paths to an existing ACTIVE plan's `## In-flight scope updates` — both ACTIVE plans (conv-tree-ui-v1.1.2-polish, misha-decision-batch-handoff-2026-05-20) are unrelated. Rejected: misclassifies the work under the wrong plan.
  - Defer the doc commits entirely — work is finished; deferring loses it. Rejected.
- **Reasoning:** The self-claiming plan path is exactly what the gate's design supports for this case. It gives the work a tracked home + audit trail without bureaucratic ceremony.
- **Checkpoint:** This commit.
- **To reverse:** delete the plan file + revert the docs (single revert).

## Definition of Done

- [x] All tasks checked off (via this self-claiming plan's authorship)
- [x] Both docs cross-reference each other
- [x] This plan file describes the investigation completely
- [x] No tests / linting needed (doc-only work)
- [x] SCRATCHPAD update not required (single-turn investigation; the plan IS the durable record)
- [x] Status flipped to COMPLETED so `plan-lifecycle.sh` archives the plan in the same edit cycle

## Completion Report

### 1. Implementation Summary

Two docs shipped:
- `docs/reviews/2026-05-21-harness-deploy-verification-audit.md` — read-only inventory + failure catalogue + structural pattern analysis.
- `docs/proposals/harness-reliability-improvements-2026-05-21.md` — six proposed mechanisms (A-F) with implementation sketches, effort estimates, unilateral-buildability flags, ranking matrix, recommended A+B+C priority set, and 6 Misha-decision asks before implementation begins.

Backlog items absorbed: none.

### 2. Design Decisions & Plan Deviations

One decision logged: use self-claiming plan rather than `--no-verify` (which would not have worked) or adding to an unrelated ACTIVE plan (which would have misclassified the work).

### 3. Known Issues & Gotchas

- The audit/proposal are read-only investigation — no code or hooks were changed. Implementation of any A-F mechanism is gated on Misha's decisions per the proposal §7 asks.
- Cross-machine state aspects are NOT covered (Misha works on multiple machines; the external-monitor pattern is per-machine). Filed as a deferral in proposal §6.
- Two orthogonal failure modes (Conv Tree 26/27/28 — DONE on un-re-merged branch; rate-limit silent death) are noted in proposal §6 as candidates for separate proposals; this one is scoped to deploy verification specifically.

### 4. Manual Steps Required

None for this investigation. Implementation of A/B/C (the recommended priority set) requires:
- Misha approves the A+B+C ranking (proposal §7 ask 1).
- Misha decides synchronous-block vs background-subprocess for A and B v1 (proposal §7 ask 2).
- Misha confirms alert-directory + schema conventions (proposal §7 ask 3-4).
- Per-project `deploy-config.json` for B (proposal §7 ask 5).

### 5. Testing Performed & Recommended

Performed: file-existence verification (both docs exist; both cross-reference correctly; cross-reference paths corrected after audit doc was renamed for `docs/.gitignore` compliance). No runtime testing needed for doc artifacts.

Recommended: when A/B/C are built, each needs a separate plan with proper `Verification: full` tasks + `--self-test` blocks per harness convention.

### 6. Cost Estimates

Doc work: $0 ongoing. Investigation cost was the Dispatch turn that produced it.

Future A/B/C implementation costs are sketched in the proposal:
- A: 4-6h harness work
- B: 6-8h harness work + ~30min per downstream project for `deploy-config.json`
- C: 4-5h harness work + a multi-repo allowlist file

D/E/F have higher costs (proposal §3 ranking matrix).
