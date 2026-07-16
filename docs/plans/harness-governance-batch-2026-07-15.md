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

## In-flight scope updates

- 2026-07-15 (R3): `docs/decisions/064-never-diverge-single-canonical-master.md` — the R3
  design decision record (decide-and-go per §8).
- 2026-07-15 (R1/R3/batch, executing session): `adapters/claude-code/manifest.json`,
  `adapters/claude-code/config/model-policy.json`, `adapters/claude-code/agents/architecture-reviewer.md`,
  `docs/harness-architecture.md` — R1 merge-invariant surface (union + pins + regenerated doc).
- 2026-07-16 (R1 merge-fix, reviewer-REJECT remediation): the 11 pt-side files dropped from
  `937e8cb` by the stash/index corruption — `adapters/claude-code/doctrine/INDEX.md`,
  `adapters/claude-code/hooks/lib/merge-scan-lib.sh`, `adapters/claude-code/hooks/lib/progress-log-lib.sh`,
  `adapters/claude-code/hooks/plan-lifecycle.sh`, `adapters/claude-code/hooks/workstreams-emit.sh`,
  `adapters/claude-code/schemas/progress-log-event.schema.json`, `adapters/claude-code/scripts/dispatch-provenance.sh`,
  `docs/plans/ask-rooted-workstreams-p1-evidence.md`, `docs/plans/ask-rooted-workstreams-p1.md`,
  `docs/runbooks/ask-workstreams.md`, `neural-lace/workstreams-ui/server/auditor.js` — plus the
  manifest 123-union, the model-policy entry, and the runbook verification hardening.
- 2026-07-15 (residue capture, task 6): `docs/handoffs/2026-07-14-model-enforcement-and-rootcause-gate-checkpoint.md`,
  `docs/lessons/2026-07-14-credentials-are-available-inject-dont-surrender.md`,
  `docs/plans/model-enforcement-2026-07-14-evidence/` — prior-session on-disk artifacts needing a home.

## Evidence Log

### R1 (2026-07-15, orchestrating session)
- pt reachable on the work gh account (active at session start); `git fetch pt master` OK. Divergence pre-merge: `14 10` (pt-only / local-only).
- Conflict surface pre-verified via merge-base `974aa22` + `comm -12`: exactly `adapters/claude-code/manifest.json` + `docs/backlog.md` (as runbook predicted).
- Merge commit **`937e8cb`** (parents `0085781` local + `6db4c3e` pt). Unions: manifest kept BOTH new entries (model-pin + artifact-evidence-bar), JSON validated; backlog kept HEAD's GUARD-REFORMULATE-01 superset + WS-UI row, dropped pt's older duplicate.
- Invariant fixes in the merge commit: `agents/architecture-reviewer.md` pinned `model: fable`; `config/model-policy.json` + architecture-reviewer (design, [fable,opus]); `docs/harness-architecture.md` regenerated (gen --check GREEN).
- Verify: model-pin-gate self-test 13/13; harness-doctor self-test 105/105. doctor --quick REDs triaged: all pre-existing on BOTH parents (manifest-check path-join bug on sessionstart-singleflight — **nl-issue filed**), or clear-on-install (manifest-freshness), or R2 scope (worktree budget), or environmental (cockpit port / ask-capture / needs-you headers / live Stop-chain budget).
- Incident (self-caused, resolved): a baseline `git stash` snapshot destroyed MERGE_HEAD mid-merge; restored via `git rev-parse pt/master > .git/MERGE_HEAD` before committing, so `937e8cb` has correct dual parents. Gates behaved correctly throughout (scope gate's merge full-skip resumed once MERGE_HEAD was restored; docs-freshness correctly demanded the regenerated architecture doc).
- harness-reviewer (FRESH dispatch, model: opus — Fable spend-capped) dispatched on `937e8cb` BEFORE push, per runbook step 7. Verdict: (pending)
- PUSH: (pending review PASS)

### R2 (inventory so far)
- 7 worktrees; broadcast marks 5 signals live-owned (main, nl-ux-wt, agent-aeed9a16, agent-afdcb723, workstreams-ui-server) + sleepy-albattani claim. Non-owned candidates: `beautiful-mcnulty-e8bc42` worktree (clean, detached @6149a45, PR #100 MERGED on pt 2026-07-13) and branches `claude/beautiful-mcnulty-e8bc42` (ahead-of-origin by 1 doc commit) + `close-100` (12 commits, unpushed, content landed via PR 100→pt→master — verified: archived plan + FM-038 + vaporware doctrine present in master). Neither branch is ancestry-merged nor stale >7d → runbook says KEEP; revisit via estate coordination (are the broadcast signals themselves stale?).
