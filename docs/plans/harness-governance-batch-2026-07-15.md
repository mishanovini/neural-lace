# Plan: harness-governance batch — review-before-deploy + evidence-before-fix + artifact-evidence-bar

Status: ACTIVE
Mode: design
acceptance-exempt: true (harness-internal; the maintainer is the user, self-tests are the demonstration)
Created: 2026-07-15
Owner: handed off — a fresh session ORCHESTRATES this end-to-end (see docs/handoffs/2026-07-15-followup-batch-handoff.md)

**Execution contract (non-negotiable — constitution §8 + orchestrator pattern):** the executing
session is the ORCHESTRATOR. It dispatches worktree-isolated builder/reviewer subagents, integrates
their commits, verifies on-disk evidence (never trusts a builder's claim), and does NOT do the
build work itself. It runs until EVERY task is completed, reviewed, AND deployed (merged to BOTH
masters + live-synced + verified live) — it never pauses to ask whether to continue; continuing to
full completion is the only acceptable end state. The sole exception is a genuinely irreversible
operator-only action, which it surfaces while continuing all parallel work.

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

FOUNDATION — do FIRST; the batch builds on a unified, clean master. Full procedure:
`docs/runbooks/master-reconcile-and-estate-cleanup.md`.

- [ ] R1. **Reconcile the two masters to convergence (0/0).** Runbook Part A: fetch pt on the work
  account, merge (only manifest.json + backlog.md conflict — resolve by UNION), pin the
  architecture-reviewer that arrives from pt (`model: fable` + add to config/model-policy.json),
  verify (self-tests + doctor), harness-review BEFORE push, push BOTH remotes. Verification: full —
  `git rev-list --left-right --count pt/master...master` == `0 0` AND doctor green live.
- [ ] R2. **Clean the branch/worktree estate.** Runbook Part B: remove only merged/stale UNOWNED
  worktrees + branches; respect the ownership broadcast + concurrent-ownership gate (never force).
  Verification: full — a report of what was removed vs kept, with the reason for each keep.
- [ ] R3. **Never-diverge design fix.** Diagnose why the masters diverged and why the fork-sync
  isn't running (PT-FORK-SYNC-NOT-RUNNING-01); DECIDE the design that makes recurrence structurally
  impossible (decision-log entry, decide-and-go per §8); architecture-review it; build + review +
  deploy. Verification: full.

BATCH — after the foundation lands (unified master):

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

- Built-in-strictness operator decision (live default STRICT) — handoff §6. (Now folded into the
  execution contract: the orchestrating session surfaces it but does not block; default stays STRICT.)
- Status-page → Workstreams-UI adoption — `docs/design-notes/status-page-for-ws-ui-adoption.md`,
  backlog `WS-UI-STATUS-PAGE-ADOPTION-01`. Unrelated track.

## Files to Modify/Create

- `docs/plans/harness-governance-batch-2026-07-15.md` — this plan.
- `docs/handoffs/2026-07-15-followup-batch-handoff.md` — the portable brief.
- `docs/design-notes/status-page-for-ws-ui-adoption.md` — ws-UI reference (separate track).
- `docs/decisions/063-model-pin-gate-blocks-not-injects.md` — the block-not-inject decision.
- `adapters/claude-code/doctrine/model-selection.md` — the "why block not inject" note.
- `docs/backlog.md` — the ws-UI adoption row.
- `docs/runbooks/master-reconcile-and-estate-cleanup.md` — the reusable reconcile+cleanup procedure (tasks R1–R2).
- (build tasks R3 + 1–5 create their own files in the executing session.)

## Evidence Log
- (filled by the executing session)
