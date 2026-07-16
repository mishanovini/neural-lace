# Evidence Log — harness-governance batch (task-verifier companion)

Independent re-derivation by the task-verifier agent (session 29f2930a), 2026-07-15.
Plan is acceptance-exempt (harness-internal; self-tests + live-deploy parity are the demonstration).

## Task R1
EVIDENCE BLOCK
==============
Task ID: R1
Verified at: 2026-07-15
Verifier: task-verifier agent
Oracle: derived-preexisting -- git rev-list convergence + live doctor R1 checks.
Runtime verification: test git rev-list --left-right --count pt/master...master => 0 0 (origin + pt/origin also 0 0)
Runtime verification: test model-pin-gate.sh::--self-test => 13/13 PASS
Runtime verification: test manifest-check.sh => GREEN 126 entries 0 warn
Runtime verification: file ~/.claude/manifest.json::sha256==repo (manifest-freshness GREEN)
Commit: 937e8cb + 9fe4aba (dual-parent merge + reviewer-REJECT remediation)
Verdict: PASS

## Task R2
EVIDENCE BLOCK
==============
Task ID: R2
Verified at: 2026-07-15
Verifier: task-verifier agent
Oracle: specified -- removed-vs-kept report + git worktree/branch state.
Runtime verification: test git worktree list => NO agent-afdcb7239ab5755d9 (removed)
Runtime verification: test git branch -a => NO worktree-agent-afdcb7239ab5755d9 (deleted)
Commit: R2 executed 2026-07-16 (report in plan Evidence Log)
Verdict: PASS

## Task R3
EVIDENCE BLOCK
==============
Task ID: R3
Verified at: 2026-07-15
Verifier: task-verifier agent
Oracle: specified -- decision 064 + gh-merge gate self-test + live deploy.
Runtime verification: test gh-merge-canonical-gate.sh::--self-test => 23/23 PASS
Runtime verification: file ~/.claude/hooks/gh-merge-canonical-gate.sh (live, byte-identical)
Runtime verification: file docs/decisions/064-never-diverge-single-canonical-master.md::SOUND-WITH-AMENDMENTS A1-A6
Commit: e2cf8b8 (decision 064 amendments folded)
Verdict: PASS

## Task 1
EVIDENCE BLOCK
==============
Task ID: 1
Verified at: 2026-07-15
Verifier: task-verifier agent
Oracle: specified -- design doc with architecture-review amendments folded.
Runtime verification: file docs/design-notes/review-record-primitive.md::SOUND-WITH-AMENDMENTS [amended A-F]
Commit: 55120cb (task 1 finalize, fold A-F)
Verdict: PASS

## Task 2
EVIDENCE BLOCK
==============
Task ID: 2
Verified at: 2026-07-15
Verifier: task-verifier agent
Oracle: specified -- deploy-gate self-tests exercising uncovered-blob block + real PASS record.
Runtime verification: test review-record-gate-lib.sh::--self-test => 25/25 PASS
Runtime verification: test write-review-record.sh::--self-test => 16/16 PASS
Runtime verification: test session-start-auto-install.sh::--self-test => 18/18 PASS
Runtime verification: file docs/reviews/records/2026-07-16-harness-change-review-30d61135.json::verdict PASS
Commit: 07c9f8e (real PASS record supersedes placeholder)
Verdict: PASS

## Task 3
EVIDENCE BLOCK
==============
Task ID: 3
Verified at: 2026-07-15
Verifier: task-verifier agent
Oracle: specified -- gate self-test + honest warn-mode manifest + backlog promotion row.
Runtime verification: test evidence-before-fix-gate.sh::--self-test => 18/18 PASS
Runtime verification: file adapters/claude-code/manifest.json::evidence-before-fix blocking:false WARN-MODE-PENDING-CALIBRATION
Runtime verification: file docs/backlog.md::EVIDENCE-BEFORE-FIX-PROMOTION-01
Commit: f597cb6 (warn-mode conversion) + fce4f48 (decision log)
Verdict: PASS (warn-mode, promotion tracked)

## Task 4
EVIDENCE BLOCK
==============
Task ID: 4
Verified at: 2026-07-15
Verifier: task-verifier agent
Oracle: derived-preexisting (contract) -- artifact-evidence-bar manifest + doctrine landed via R1, consumed by design.
Runtime verification: file adapters/claude-code/manifest.json::artifact-evidence-bar entry present
Runtime verification: file adapters/claude-code/doctrine/artifact-evidence-bar.md + -full.md present
Runtime verification: file docs/design-notes/review-record-primitive.md::cites artifact-evidence-bar (6x)
Commit: 937e8cb (R1 pt merge brought artifact-evidence-bar)
Verdict: PASS

## Task 5
EVIDENCE BLOCK
==============
Task ID: 5
Verified at: 2026-07-15
Verifier: task-verifier agent
Oracle: derived-metamorphic -- every blocking:true manifest entry MUST carry added_after.
Runtime verification: test node sweep => 35 blocking:true entries, 0 without added_after (GREEN)
Runtime verification: file adapters/claude-code/hooks/harness-doctor.sh::check_new_gate_evidence_bar missing-added_after assertion (node+jq) + PRE_BAR_GRANDFATHERED
Commit: 40f7034 (true landing months + closed grandfather exempt-list)
Verdict: PASS

## Task 6
EVIDENCE BLOCK
==============
Task ID: 6
Verified at: 2026-07-15
Verifier: task-verifier agent
Oracle: implicit/mechanical -- residue files in commit e2cf8b8 (ancestor of HEAD), tracked, clean tree.
Runtime verification: test git show --stat e2cf8b8 => checkpoint handoff + credentials lesson + 5 evidence.json + decision 064
Runtime verification: test git merge-base --is-ancestor e2cf8b8 HEAD => YES (07c9f8e); git status --porcelain => clean
Commit: e2cf8b8 (batch-6 residue capture)
Verdict: PASS
