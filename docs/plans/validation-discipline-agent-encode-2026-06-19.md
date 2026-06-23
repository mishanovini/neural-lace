# Plan: Encode the validation-discipline lesson into the verifier/builder agents (2026-06-19)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal agent-prompt edits; deliverables are three agent definition files with no product user; frontmatter/section-contract checks + the consuming hooks' parse-stability are the acceptance artifact
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
owner: orchestrator (this session)
target-completion-date: 2026-06-19

## Goal
A proven failure this week: agents validated "the value reaches a function" or
"a test passes" without validating the USER-FACING RENDERED OUTPUT. A cost test
was green while the pricing tab stayed broken (#589); config cards stayed inert
for the highest-traffic states because the setting was wired but never changed
the output (#592). Encode the corrective into the three agents that write and
gate tests — `functionality-verifier`, `plan-phase-builder`, `task-verifier` —
as ADDITIVE, contract-preserving sharpenings of their existing functionality-
over-components discipline. Three principles:
1. Tests drive the REAL component and assert the rendered output the user sees —
   never an intermediate data shape (a computed value, props, store state, or an
   API field before it is rendered).
2. RED-GREEN: the test must be shown to FAIL against the broken/old/absent
   behavior before it is accepted; a green-only test with no demonstrated RED may
   be asserting an intermediate the bug never touched.
3. "wired != reached != behaving": for a setting/flag/config, prove the OUTPUT
   changes across the setting's values, for the states that actually exercise it
   (especially the highest-traffic ones) — not merely that the setting is read.

## User-facing Outcome
The harness maintainer's verifier and builder agents reject the green-but-broken
class: a builder will not return DONE on a test asserting an intermediate shape,
and `task-verifier` / `functionality-verifier` will not PASS one — they require an
assertion against the rendered output, a demonstrated RED, and (for settings) an
output-change proof. The #589/#592 failure class cannot pass the verification
pipeline silently.

## Scope
- IN: additive edits to the three agent files; this plan; the live-mirror sync of
  the three files to `~/.claude/agents/`; revisiting the agent-upgrades-batch2
  plan (disposition note).
- OUT: the full 2026-06-05 batch2 rewrites of these agents (a separate, larger
  effort); any other agent; any hook/rule/template change; the A/B staging
  program (never materialized on this branch — see Decisions Log).

## Tasks
- [ ] 1. Add the rendered-output + RED-GREEN + wired-reached-behaving sharpenings
  to `functionality-verifier.md`, `plan-phase-builder.md`, `task-verifier.md` —
  additive, contract-preserving (no hook-parsed string touched); sync the live
  mirror; pass `harness-reviewer` adversarial review — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/agents/functionality-verifier.md` — add wired≠reached≠behaving setting/flag probe + rendered-output reinforcement
- `adapters/claude-code/agents/plan-phase-builder.md` — sharpen Phase 2 RED (assert rendered output; RED against the real bug) + add the #589/#592 failure shapes + setting→output-change test
- `adapters/claude-code/agents/task-verifier.md` — add the rendered-output rule, the generalized RED-GREEN requirement, and the wired≠reached≠behaving setting check to the FUNCTIONALITY-OVER-COMPONENTS axis
- `docs/plans/validation-discipline-agent-encode-2026-06-19.md` — this plan

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The edits are purely additive; no existing hook-parsed contract string
  (evidence-block format, `Runtime verification:` line formats, verdict tokens,
  required section headings) is altered — verified by the consuming hooks'
  self-tests still passing post-edit.
- The lesson is PROVEN (observed failures #589/#592), not speculative, so it is
  direct-applied rather than routed through the batch2 A/B program (which never
  materialized on this branch — `agents-staged/` is absent).
- `harness-reviewer` is the independent adversarial gate before commit.

## Edge Cases
- task-verifier touches a hook-parsed evidence-block contract; the edit adds a
  new rubric sub-section and does NOT modify the `Runtime verification:` formats
  or the evidence-block schema → consuming-hook parse stability preserved.
- The three NEEDS-MISHA/WATCH classifications from batch2 are superseded for THIS
  specific proven lesson by the operator's explicit direction (the session
  instruction) — documented in the Decisions Log.

## Acceptance Scenarios
- n/a — acceptance-exempt (harness-internal agent edits; the consuming hooks'
  self-tests + frontmatter/section-contract checks are the acceptance artifact).

## Out-of-scope scenarios
- n/a — acceptance-exempt.

## Testing Strategy
- Task 1: `harness-reviewer` PASS on the three diffs (contract-preservation +
  class-vs-instance + false-positive modeling of any verdict-affecting language);
  frontmatter intact + all pre-existing required section headings present in each
  file; the consuming hooks that parse these agents' outputs
  (`runtime-verification-executor.sh`, `plan-edit-validator.sh`) still
  `--self-test` green; live mirror byte-identical to canonical (`diff -q`).

## Walking Skeleton
n/a — additive doctrine edits; no new mechanism is built.

## Decisions Log
- 2026-06-19: DIRECT-APPLY (not A/B). The batch2 A/B program
  (`agent-upgrades-batch2-ab-staging.md`) staged 16 agent upgrades for per-agent
  A/B before apply, with task-verifier/plan-phase-builder flagged NEEDS-MISHA.
  That program's `agents-staged/` + fixtures NEVER materialized on this branch
  (absent in working tree and HEAD). This lesson is PROVEN (observed #589/#592),
  narrow, and operator-directed (the session instruction explicitly names the
  three agents + "ship to master") — so it is direct-applied as a focused
  additive edit, NOT the full 2026-06-05 rewrites batch2 contemplated (those
  remain a separate effort). This is the "revisit batch2" deliverable. Tier 1 —
  reversible (additive text); harness-reviewer gates it.

## Pre-Submission Audit
- n/a — single-task additive-edit plan (Mode: code), no class-sweep needed.

## Definition of Done
- [ ] Task 1 checked off (three agents edited, mirror synced, harness-reviewer PASS)
- [ ] batch2 plan revisited (disposition note added)
- [ ] Committed to the branch; shipped to master
- [ ] This plan flipped to COMPLETED and archived
