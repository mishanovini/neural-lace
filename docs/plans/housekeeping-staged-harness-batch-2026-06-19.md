# Plan: Housekeeping — commit the hygiene-clean accumulated harness-kit batch (2026-06-19)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal housekeeping commit; deliverables are hooks/rules/docs with no product user; the new hooks' --self-tests are the acceptance artifact
tier: 1
rung: 0
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
owner: orchestrator (this session)
target-completion-date: 2026-06-19

## Goal
A cross-machine sync (`check-harness-sync.sh` running `git add -A`, RWR-27) swept
a large heterogeneous set into the neural-lace index — a mix of (a) genuine
accumulated harness-kit work and (b) stale-revert regressions, machine-local
operational state, and downstream-project / coordination content. This plan
exists ONLY to give the genuine, hygiene-clean harness-kit subset a single
ACTIVE plan to satisfy `scope-enforcement-gate.sh` so it can be committed
WITHOUT `--no-verify`. The regressions, operational state, and identity-laden
content are excluded (see Decisions Log) — they are NOT committed by this plan.

## User-facing Outcome
The harness maintainer's accumulated kit improvements (a new migration-naming
gate, a plan-auto-closure hook, the consolidation-discipline and
parallel-dev-discipline rules, the RWR-27 fix to check-harness-sync, and the
supporting INDEX/architecture/.gitignore updates) are committed to the
neural-lace branch and no longer at risk of being wiped on the shared working
tree — with zero stale-revert content loss and zero identity/customer leak.

## Scope
- IN: committing the ten hygiene-clean harness-kit files listed below + this
  plan file.
- OUT: the stale-revert files restored to HEAD (backlog/failure-modes/findings/
  DECISIONS/build-doctrine-roadmap); the gitignored operational state
  (tree-state.json, walking-skeleton-*.json) + machine-local config path; the
  hygiene-flagged downstream/coordination content (handoff dump, downstream-product
  feature plans, customer-referencing discoveries/review, the machine-path .vbs) —
  surfaced to the operator for a relocation/sanitization decision, NOT committed
  here. Template-vs-live hook-wiring reconciliation (HARNESS-GAP-14) is also OUT.

## Tasks
- [ ] 1. Commit the ten hygiene-clean harness-kit files + this plan to the
  feat/plan-lifecycle-mechanical-closure branch, passing all pre-commit gates
  without `--no-verify` — Verification: mechanical

## Files to Modify/Create
- `.gitignore` — RWR-27 fix: stop sweeping conv-tree-ui operational state + machine-local config path
- `adapters/claude-code/hooks/check-harness-sync.sh` — RWR-27 root-cause fix: targeted `git add -- <synced>` replaces `git add -A`; adds a 6-scenario self-test
- `adapters/claude-code/hooks/migration-naming-gate.sh` — new PreToolUse gate: blocks bare-integer-prefixed migrations (parallel-dev Practice 7)
- `adapters/claude-code/hooks/plan-auto-closure.sh` — new PostToolUse hook implementing ADR-036-c auto-closure (see Decisions Log re: ADR status)
- `adapters/claude-code/rules/INDEX.md` — adds rows for consolidation-discipline + parallel-dev-discipline
- `adapters/claude-code/rules/consolidation-discipline.md` — new rule (Pattern): consolidate layered corrections into one canonical artifact
- `adapters/claude-code/rules/parallel-dev-discipline.md` — new rule (Hybrid): trunk-based CI/CD defaults for multi-machine work
- `docs/harness-architecture.md` — inventory row for migration-naming-gate + check-harness-sync/session-end-protocol updates
- `docs/discoveries/2026-06-17-cross-repo-orchestration-gate-misfire.md` — harness-process discovery (hygiene-clean)
- `docs/plans/exact-ask-rule-2026-06-14.md` — the exact-ask-rule plan file (rule shipped bd08119)
- `docs/plans/housekeeping-staged-harness-batch-2026-06-19.md` — this plan

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The ten files above carry no denylisted identity/org/customer/path content
  (verified: `harness-hygiene-scan.sh` flags none of them).
- The excluded files are preserved as working-tree files; the RWR-27 fix in this
  commit eliminates the auto-sweep that put them at risk, so they are not lost.
- `scope-enforcement-gate.sh` admits a staged file claimed by ANY active plan's
  `## Files to Modify/Create`; this plan claims exactly the committed set.

## Edge Cases
- `plan-auto-closure.sh` is wired in the LIVE settings.json but its ADR-036 is
  formally "Proposed/gated on Misha" — committing the script preserves the work;
  the wired-live-vs-gated discrepancy is surfaced, not silently canonicalized
  (see Decisions Log).
- `migration-naming-gate.sh` is wired live but absent from settings.json.template
  (HARNESS-GAP-14 template/live divergence) — its committed source is honest; the
  template wiring is a separate reconciliation.
- If a pre-commit gate other than scope-enforcement fires, diagnose per
  `gate-respect.md` — do not `--no-verify`.

## Acceptance Scenarios
- n/a — acceptance-exempt (harness-internal housekeeping; the new hooks'
  `--self-test` blocks are the acceptance artifact).

## Out-of-scope scenarios
- n/a — acceptance-exempt.

## Testing Strategy
- Task 1: `harness-hygiene-scan.sh` exits 0 on the committed set; the commit
  lands without `--no-verify`; `git log -1` shows the expected file set;
  `migration-naming-gate.sh --self-test` and `plan-auto-closure.sh --self-test`
  both report self-test OK.

## Walking Skeleton
n/a — housekeeping commit; no new mechanism is built by this plan.

## Decisions Log
- 2026-06-19: EXCLUDED five stale-revert files (restored to HEAD): the sync swept
  in month-old copies that deleted current content (backlog v58→v31 dropping
  WS-UI-FOLLOWUPS-01/GAP-50/51; failure-modes dropping FM-024..032; findings
  14→2; DECISIONS dropping ADR rows 030-055; build-doctrine-roadmap reverting a
  2026-05-17 fix). Tier 1 — reversible, verified via a per-file adversarial triage
  pass (8 classifiers, 0.98-0.99 confidence). Committing them would be content loss.
- 2026-06-19: EXCLUDED + gitignored the conv-tree-ui operational state
  (tree-state.json 193KB, walking-skeleton-*.json) and the machine-local
  `config/workstreams-state-path` (held an absolute `C:/Users/<user>/...` path —
  a harness-hygiene violation; machine-local config belongs in the local layer).
- 2026-06-19: EXCLUDED the stale pre-rename duplicate `conversation-tree-state.md`
  (the renamed `workstreams-state.md` is current in HEAD per ADR 045/046).
- 2026-06-19: EXCLUDED 15 hygiene-flagged files (handoff dump, 8 customer/path-
  referencing discoveries, a downstream-prod review, two downstream feature
  plans, a machine-path .vbs launcher). `harness-hygiene-scan.sh` correctly blocks
  them from the shareable kit. Disposition (sanitize-and-keep the harness-process
  learnings vs relocate the downstream content to its home repo) crosses a repo
  boundary and involves operator judgment on operator content — surfaced to the
  operator, not auto-resolved.
- 2026-06-19: `plan-auto-closure.sh` committed as accumulated work though ADR-036
  is formally "Proposed/gated on Misha" while the hook is wired LIVE. The
  wired-live-vs-gated-design discrepancy is surfaced for the operator's decision;
  this commit does NOT propagate its template wiring (no behavioral change pushed
  to other machines).

## Pre-Submission Audit
- n/a — single-task housekeeping plan (Mode: code), no class-sweep needed.

## Definition of Done
- [ ] Task 1 checked off (the commit landed without `--no-verify`)
- [ ] Excluded-file disposition surfaced to the operator
- [ ] This plan flipped to COMPLETED and archived
