<!-- scaffold-created: 2026-07-13T02:32:19Z by start-plan.sh slug=doctrine-compact-bytecap-fix-2026-07 -->
# Plan: Doctrine Compact Bytecap Fix 2026-07
Status: ACTIVE
Execution Mode: direct
<!-- direct: 3 tightly-coupled mechanical doc-trim tasks, sub-15-min, one session.
     Orchestrator dispatch would add context+latency for zero benefit — the value of
     the orchestrator pattern (keeping main context lean over a long multi-phase build)
     does not apply to a deterministic doc trim. Template sanctions `direct` for
     quick fixes. -->
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development doc change; the user is the maintainer. The deliverable is the golden test (rules-index-coverage.sh) and harness-doctor byte-cap check passing — no product user surface.
tier: 1
rung: 0
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: Misha
target-completion-date: 2026-07-12
prd-ref: n/a — harness-development
ask-id: none — no linked ask

## Goal

Master is RED on the neural-lace upstream mirror: the golden test
`evals/golden/rules-index-coverage.sh` (invariant 4, the C.4 compact-form 3000-byte
hard cap) fails because two doctrine compacts exceed it —
`adapters/claude-code/doctrine/orchestrator-pattern.md` (3451 bytes) and
`adapters/claude-code/doctrine/git.md` (3653 bytes). Both are byte-identical on
origin/master, so this blocks the "Golden behavioral tests" CI check on **every** PR
to master (surfaced while landing PR #100). This plan brings both compacts to
≤ 3000 bytes using the harness's prescribed pattern — trim the compact to its
load-bearing rules + a `Full:` pointer, and relocate the overflow *detail* to the
paired `<name>-full.md` companion — so no doctrine content is lost, only relocated.

## User-facing Outcome

n/a — harness-internal: the user is the maintainer. The deliverable outcome is that
`bash evals/golden/rules-index-coverage.sh` exits 0 and the `harness-doctor.sh`
compact-byte-cap check is green, unblocking the Golden behavioral tests CI check on
every PR to master. No product-user surface changes.

## Scope
- IN: `adapters/claude-code/doctrine/git.md` — trim to ≤ 3000 bytes, keep every
  load-bearing rule, condense two verbose passages (deploy-preflight, plan-rooted
  trailer) to a rule + pointer.
- IN: `adapters/claude-code/doctrine/git-full.md` — receive the two passages'
  full detail as new sections (they are NOT currently present in `-full`, so they
  must be added there before the compact is trimmed, or content is lost).
- IN: `adapters/claude-code/doctrine/orchestrator-pattern.md` — trim to ≤ 3000
  bytes by condensing two passages (shared-checkout git-state disciplines, proactive
  audit loop) whose full detail ALREADY lives in `orchestrator-pattern-full.md`.
- OUT: `orchestrator-pattern-full.md` — no edit needed; it already carries the
  detail (verified: lines 109/111/113 shared-checkout, line 290+ audit patterns).
- OUT: any change to the substance of the rules, the INDEX rows (both compacts
  already have rows — invariant 3 passes), or any other doctrine compact.
- OUT: PR #100 / vaporware-config-controls itself (its own compacts are already
  within cap at 2401/2998 bytes).

## Tasks

- [ ] 1. Add two new sections to `adapters/claude-code/doctrine/git-full.md` carrying
  the full detail currently only in the compact: (a) "Deploy preflight — mandatory
  before production deploy" (the `deploy-preflight.sh` invocation, its FAIL-CLOSED
  conditions, and the 2026-06-18 incident) and (b) "Plan-rooted work — the `plan:`
  attribution trailer" (the trailer mechanism, the merge-emission auditor, the
  diff-touches fallback). — Verification: mechanical — Docs impact: extends
  git-full.md with two sections; no README/runbook delta (doctrine-internal).

- [ ] 2. Trim `adapters/claude-code/doctrine/git.md` to ≤ 3000 bytes: condense the
  deploy-preflight and plan-rooted-trailer bullets to a load-bearing rule + `Full:`
  pointer (detail now in git-full.md per Task 1), keeping the NEVER-force-push,
  no-`--no-verify`, post-merge-sync, staged-set-verify, stop-hook-waiver,
  branch-hygiene, PR-merge, deploy-default, customer-tier, and wrong-account rules
  intact. — Verification: mechanical — Docs impact: none — doctrine compact trim,
  detail relocated to companion in Task 1.

- [ ] 3. Trim `adapters/claude-code/doctrine/orchestrator-pattern.md` to ≤ 3000
  bytes: condense the shared-checkout git-state-disciplines bullet and the
  proactive-audit-loop bullet to their load-bearing gist + the existing `-full`
  pointer (detail already present in orchestrator-pattern-full.md), keeping the
  dispatch, parallel-worktree, build-parallel-verify-sequentially, builder-claim,
  BLOCKED/FAIL, and closed-plan-deliverable rules intact. — Verification: mechanical
  — Docs impact: none — doctrine compact trim, detail already in companion.

## Files to Modify/Create
- `adapters/claude-code/doctrine/git-full.md` — MODIFY: append two sections
  (deploy-preflight, plan-rooted trailer) so the detail trimmed from the compact is
  preserved in the companion.
- `adapters/claude-code/doctrine/git.md` — MODIFY: trim from 3653 → ≤ 3000 bytes.
- `adapters/claude-code/doctrine/orchestrator-pattern.md` — MODIFY: trim from 3451
  → ≤ 3000 bytes.

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The golden test's byte cap is a strict `> 3000` fail (verified in the script:
  `if [[ "$byte_count" -gt 3000 ]]`), so ≤ 3000 passes; I target ≤ ~2950 for margin.
- `git-full.md` and `orchestrator-pattern-full.md` are exempt from the cap
  (`*-full.md` skipped in the test loop) — growing them is safe.
- No other session is editing these three doctrine files concurrently (the active
  broadcast shows worktrees on unrelated branches; these compacts are byte-identical
  on origin/master, i.e. untouched).
- `harness-doctor.sh` has an equivalent compact-byte-cap check; passing the golden
  test implies the doctor's check on these files is also green.

## Edge Cases
- Trimming must not drop a load-bearing SAFETY rule (NEVER force-push, no
  `--no-verify`, deploy-preflight-mandatory). Handled: each rule stays in the compact
  as an imperative; only the *incident narration / mechanism detail* moves to `-full`.
- Content-loss risk: the two git.md passages are NOT in git-full.md today (verified
  by grep — 0 hits for preflight/trailer). Handled by Task 1 adding them to `-full`
  BEFORE Task 2 removes them from the compact.
- Multibyte characters (em-dashes `—`, `≤`) count as >1 byte under `wc -c`. Handled:
  the pass/fail check is by actual `wc -c` byte count, which I re-measure after each
  edit, not by character count.
- INDEX row requirement: both compacts already have INDEX rows (invariant 3 passes);
  trimming body prose does not touch the `[doctrine/x.md](x.md)` link, so no INDEX
  regeneration is needed.

## Acceptance Scenarios
n/a — acceptance-exempt: true (harness-dev plan, no product user; see
acceptance-exempt-reason in header).

## Out-of-scope scenarios
None — all relevant verification is mechanical (golden test + doctor), captured in the
Closure Contract.

## Closure Contract
- **Commands that run:**
  - `bash evals/golden/rules-index-coverage.sh`
  - `wc -c adapters/claude-code/doctrine/git.md adapters/claude-code/doctrine/orchestrator-pattern.md`
  - `bash adapters/claude-code/scripts/harness-doctor.sh --quick` (compact-byte-cap check)
- **Expected outputs:** golden test prints `PASS:` and exits 0; both compacts report
  ≤ 3000 bytes; doctor's byte-cap check is not among the red checks.
- **On-disk artifact location:** the per-task evidence set at
  `docs/plans/doctrine-compact-bytecap-fix-2026-07-evidence/<task-id>.evidence.json`
  (acceptance-exempt harness plan → self-test/mechanical evidence is the closure target).
- **Done when:** all 3 tasks are task-verifier PASS AND
  `bash evals/golden/rules-index-coverage.sh` exits 0 with both compacts ≤ 3000 bytes.

## Testing Strategy
- Task 1: `grep` git-full.md for the two new section headers + their key tokens
  (`deploy-preflight.sh`, `2026-06-18`, `plan:` trailer, `merge-emission`), confirming
  the detail is present; confirm git-full.md is still a valid `-full` (exempt from cap).
- Task 2: `wc -c adapters/claude-code/doctrine/git.md` ≤ 3000; `grep` confirms the
  load-bearing rules (NEVER force-push, no `--no-verify`, deploy-preflight mandatory,
  post-merge sync) remain; the `Full:` pointer line is present.
- Task 3: `wc -c adapters/claude-code/doctrine/orchestrator-pattern.md` ≤ 3000; `grep`
  confirms the dispatch/parallel/verify-sequentially/builder-claim/BLOCKED rules and
  the `Full:` pointer remain.
- Whole plan: `bash evals/golden/rules-index-coverage.sh` exits 0; `harness-reviewer`
  reviews the doctrine change before landing; open a PR to the upstream neural-lace
  mirror (base master) via the dual-push origin remote.

## Walking Skeleton: n/a — pure doctrine-doc trim; no end-to-end runtime slice exists.

## Decisions Log
- 2026-07-12: Execution Mode `direct` (not orchestrator) — 3 mechanical doc-trim
  tasks in one file-family, sub-15-min; orchestrator dispatch adds context+latency for
  zero benefit. Reversible (flip header) — decide-and-go per constitution §8.
- 2026-07-12: For git.md, ADD the deploy-preflight + plan-trailer detail to
  git-full.md rather than delete it — grep confirmed those passages are absent from
  git-full.md, so deleting from the compact without adding to `-full` would lose
  doctrine. For orchestrator-pattern.md, the detail already exists in `-full`, so
  those passages are condensed in place with no `-full` edit.

## Definition of Done
- [ ] All tasks checked off
- [ ] All tests pass (golden test exits 0; both compacts ≤ 3000 bytes)
- [ ] harness-reviewer PASS on the doctrine change
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file
