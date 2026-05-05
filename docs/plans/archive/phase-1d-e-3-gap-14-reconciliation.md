# Plan: Phase 1d-E-3 — GAP-14 template-vs-live reconciliation

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-GAP-14
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product-user surface to verify at runtime. Verification is per-hook proposal substance + post-reconciliation settings-divergence-detector clean output.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Context

HARNESS-GAP-14 (added 2026-05-04) tracks the template-vs-live `settings.json` reconciliation deferred from the discovery `2026-05-04-template-vs-live-divergence-across-other-hooks`. The detector half (B) shipped; this plan is the reconciliation half (A).

Per backlog: per-hook orchestrator-driven research methodology. The user reviews proposals; the orchestrator does NOT pick canonical side cold.

Hooks to reconcile (after 1d-E-1 resolved automation-mode-gate):
1. `outcome-evidence-gate.sh` — in live, not in template
2. `systems-design-gate.sh` — in live, not in template
3. `no-test-skip-gate.sh` — in live, not in template
4. `check-harness-sync.sh` — in live, not in template

Plus public-repo-blocker variants (per backlog) — investigate.

## Goal

For each divergent hook, produce a per-hook proposal citing evidence (commit SHA, plan file, decision record, doc reference). Auto-apply REVERSIBLE proposals (per discovery protocol). Surface IRREVERSIBLE choices to user. Final state: settings-divergence-detector reports zero divergence (or only intentional, documented divergence).

## Scope

**IN:**
- `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md` — NEW (per-hook research output with proposals)
- `adapters/claude-code/settings.json.template` — EDIT (add hooks where decision is "template canonical = live")
- `~/.claude/settings.json` — EDIT (remove hooks where decision is "template canonical, live drifted") [unlikely; mostly add to template]
- `docs/decisions/024-*.md` — NEW (gap-14 reconciliation decision)
- `docs/DECISIONS.md` — EDIT
- `docs/backlog.md` — EDIT (mark GAP-14 IMPLEMENTED)
- `docs/harness-architecture.md` — EDIT (inventory updates if any hook gets newly-documented)

**OUT:**
- Re-design of any hook itself (only wiring decisions).
- Adding new hooks not in either layer.

## Tasks

- [ ] **1. Per-hook research + proposals.** Author audit doc at `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md`. For each of the 4 divergent hooks (plus public-repo-blocker variants if relevant): run `git log --all --follow adapters/claude-code/hooks/<hook>.sh`, find originating commit + plan + decision; check `git blame adapters/claude-code/settings.json.template` for relevant lines; cross-reference `docs/harness-architecture.md`; produce per-hook proposal with `template canonical / live canonical / intentional divergence` verdict + evidence. Single commit.

- [ ] **2. Reconcile hooks per proposals.** For each proposal verdict, apply the reconciliation: most likely "live → template" (add the hook to template + sync). EDIT settings.json.template + sync to live. Verify JSON validity. Run settings-divergence-detector after — confirm zero (or only intentional) divergence. Single commit.

- [ ] **3. Decision 024 + cleanup.** Land Decision 024 (per-hook reconciliation outcomes; cite each verdict). Update DECISIONS.md. Mark HARNESS-GAP-14 IMPLEMENTED in backlog "Recently implemented" with commit SHAs. Single commit.

## Files to Modify/Create

- `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md` — NEW.
- `adapters/claude-code/settings.json.template` — EDIT.
- `~/.claude/settings.json` — EDIT (gitignored mirror).
- `docs/decisions/024-gap-14-reconciliation.md` — NEW.
- `docs/DECISIONS.md` — EDIT.
- `docs/backlog.md` — EDIT.
- `docs/harness-architecture.md` — EDIT if needed.

## In-flight scope updates

(none yet)

## Assumptions

- The 4 hooks in question all have legitimate intent (they were authored deliberately, just got mis-wired to one layer).
- Most divergences resolve as "live canonical → add to template" (the hook is genuinely needed; just the template wasn't updated).
- The settings-divergence-detector hook shipped earlier produces a clean output once the 4 hooks are aligned.
- The public-repo-blocker variants reference may be stale (the public-repo blocker pattern is multiple inline-Bash hooks; investigation will reveal if there's actual divergence).

## Edge Cases

- **A hook in live has no clear originating commit / plan.** Default to "live canonical" with an explanatory note in the proposal.
- **A hook is in live with a different matcher pattern than template would naturally have.** Document the matcher difference; pick the more permissive side.
- **JSON edit causes parse failure.** Catch via `jq -e .`; revert and re-edit.
- **Reconciliation surfaces a new hook design issue (e.g., the hook is buggy).** Out of scope for this plan; surface as a new backlog entry.

## Acceptance Scenarios

(none — `acceptance-exempt: true`. Verification is per-task task-verifier PASS + post-reconciliation settings-divergence-detector clean output.)

## Out-of-scope scenarios

- Hook re-design.
- New hook authoring.

## Testing Strategy

Each task task-verified.

1. Task 1: audit doc has per-hook proposals with evidence citations.
2. Task 2: settings-divergence-detector returns clean output (or only intentional, documented divergence).
3. Task 3: Decision 024 lands; backlog reflects GAP-14 IMPLEMENTED.

## Walking Skeleton

Task 1's audit doc is the smallest unit and the most independent — proposals can be reviewed even if Task 2 is deferred. Start there.

## Decisions Log

(populated during implementation)

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept, 0 stranded.
- S2 (Existing-Code-Claim Verification): swept, 4 claims (4 hooks identified by name; settings-divergence-detector exists; harness-architecture.md inventory format; gitignore for live settings) — verified.
- S3 (Cross-Section Consistency): swept.
- S4 (Numeric-Parameter Sweep): swept for [4 hooks divergent] — consistent.
- S5 (Scope-vs-Analysis Check): swept.

## Definition of Done

- [ ] All 3 tasks task-verified PASS.
- [ ] Per-hook proposals authored with evidence.
- [ ] settings-divergence-detector reports clean (or documented divergence).
- [ ] Decision 024 landed.
- [ ] Backlog reflects GAP-14 IMPLEMENTED.
- [ ] Plan archived.
