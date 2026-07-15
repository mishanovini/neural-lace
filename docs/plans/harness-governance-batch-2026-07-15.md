# Plan: harness-governance batch — review-before-deploy + evidence-before-fix + artifact-evidence-bar

Status: ACTIVE
Mode: design
acceptance-exempt: true (harness-internal; the maintainer is the user, self-tests are the demonstration)
Created: 2026-07-15
Owner: handed off — a fresh session executes this (see docs/handoffs/2026-07-15-followup-batch-handoff.md)

## Problem

The originating session (model-enforcement, archived) surfaced that **§10 "harness-review before
a change lands" is a Pattern, not a Mechanism** — nothing deterministically requires a harness
change to be reviewed before it is committed, merged, or deployed. This failed twice in that one
workstream: a prior session live-synced a buggy gate with zero review, and the session itself
deployed a fix (`install.sh`) before its re-review returned. Three follow-ups share ONE root
primitive — **a review/evidence record keyed to a change that gates the next step** — so they are
batched here to design that primitive once. This plan is the tracked home; the portable,
copy-into-a-fresh-session brief with full context is
`docs/handoffs/2026-07-15-followup-batch-handoff.md`.

## Decisions already made (do NOT re-litigate)

- **Decision 063:** `model-pin-gate` BLOCKS rather than auto-assigns a model, because Claude Code
  excludes Task/Agent spawns from PreToolUse `updatedInput` (verified vs official docs). Recorded in
  `docs/decisions/063-model-pin-gate-blocks-not-injects.md`.
- **Batch, not standalone** (operator, 2026-07-15): the three Mechanisms share one review-record
  substrate; design it once.

## Tasks

- [ ] 1. **Design the review-record primitive** — a structured record (à la close-plan's
  `.evidence.json`) keyed to a change/commit, carrying a `harness-reviewer` PASS verdict. Decide the
  identity key and the trigger surface (all `adapters/claude-code/**`, or only gate/hook/rule files).
  MUST go through `architecture-reviewer` (design SHAPE review) before any build — high blast radius.
  Verification: design
- [ ] 2. **Review-before-deploy gate** — a gate on the DEPLOY step (`install.sh` +
  `session-start-auto-install.sh`) that blocks harness changes lacking a PASS review record. Own
  golden scenario, fp_expectation, retirement condition (§10). Verification: full (self-test + a live
  deploy-blocked demonstration).
- [ ] 3. **Directive 1 — evidence-before-fix commit gate** — require an evidenced
  `## Root cause (evidenced)` block (PROVEN/INFERRED-tagged) before a `fix(...)` commit; reject an
  inferred-not-observed cause. Broaden `diagnosis.md` beyond prod-crashes to data/behavior bugs.
  Lesson: `docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md`. Verification: full.
- [ ] 4. **Integrate pt/master `artifact-evidence-bar`** — fold pt's §10-generalization (evidence for
  gates/AGENTS/DESIGNS/reviews) into the primitive; land during the pt reconcile. Verification: contract.
- [ ] 5. **Evidence-bar evasion-by-omission** — backfill `added_after` on the 31 legacy `blocking:true`
  manifest entries, THEN assert its presence on every `blocking:true` entry in `check_new_gate_evidence_bar`.
  Verification: full (doctor self-test RED-then-GREEN).
- [ ] 6. **Commit-capture (this session's residue)** — commit the on-disk `docs/decisions/063*` +
  `doctrine/model-selection.md` note + this plan + the handoff + the ws-UI design-note + backlog row.
  Verification: mechanical (files in commit).

## Out of scope / separate tracks

- pt/master reconcile mechanics (14 commits, pin `architecture-reviewer` design→fable) — estate hygiene,
  its own session; blocker: `github-pt` SSH access. See the handoff §7.
- Built-in-strictness operator decision (live default STRICT) — handoff §6.
- Status-page → Workstreams-UI adoption — `docs/design-notes/status-page-for-ws-ui-adoption.md`,
  backlog `WS-UI-STATUS-PAGE-ADOPTION-01`. Unrelated track.

## Files to Modify/Create

- `docs/plans/harness-governance-batch-2026-07-15.md` — this plan.
- `docs/handoffs/2026-07-15-followup-batch-handoff.md` — the portable brief.
- `docs/design-notes/status-page-for-ws-ui-adoption.md` — ws-UI reference (separate track).
- `docs/decisions/063-model-pin-gate-blocks-not-injects.md` — the block-not-inject decision.
- `adapters/claude-code/doctrine/model-selection.md` — the "why block not inject" note.
- `docs/backlog.md` — the ws-UI adoption row.
- (build tasks 1–5 create their own files in the executing session.)

## Evidence Log
- (filled by the executing session)
