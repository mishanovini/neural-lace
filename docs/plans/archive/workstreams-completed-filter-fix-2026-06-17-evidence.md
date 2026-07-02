# Evidence Log — Workstreams UI "show completed" filter + ACTIVE-plan-badged-shipped fix

Plan: docs/plans/workstreams-completed-filter-fix-2026-06-17.md
Work shipped via PR #62, commit d4ce1f3903d18c89a29138daaad47a4deab3021f
("fix(workstreams): [ACTIVE] plan status wins over stale shipped; show-completed hides done"),
merged 2026-06-17; contained in master and claude/modest-satoshi-150d97 (verified via
`git branch --contains d4ce1f3`). Boxes were never flipped at merge time; verified
retroactively against CURRENT code at HEAD 3eb010f per operator approval DEC-2026-07-02-002.

## Task 1 — itemState() status-precedence override

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Add a status-precedence override to itemState() in web/app.js: when an item's text carries a plan-status marker that means "still open" ([ACTIVE]), do not return shipped even if it.state==='shipped'/it.checked. Derive the truthful open state instead (in-flight, or blocked if contested). Verification: mechanical
Verified at: 2026-07-02T21:06:44Z
Verifier: task-verifier agent

Oracle: specified — the plan's task Done-when (guard exists; [ACTIVE] never derives shipped; blocked preserved) exercised against the REAL app.js functions via extraction-based selftest; derived — pre-fix commit d4ce1f3~1 as the RED reference.
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Guard exists in current code
   Command: grep -n "planStatusSaysOpen" neural-lace/workstreams-ui/web/app.js
   Output: definition at app.js:292-294 (regex /\[ACTIVE\]/i on item text); called as first clause of itemState() at app.js:302-306 — returns 'blocked' if contested, 'committed' if deferred/backlogged, else 'in-flight'; never 'shipped' (the it.state / it.checked branches at 307-308 are unreachable when the marker is present).
   Result: PASS
2. Behavioral proof via extraction-based selftest (REAL functions lifted verbatim from app.js — E1-E4 prove extraction, no replica)
   Command: node neural-lace/workstreams-ui/state/filter-status.selftest.js
   Output: A1 [ACTIVE]+state=shipped derives non-complete PASS; A2 derives in-flight PASS; A3 NOT isComplete PASS; A4 [ACTIVE]+contested derives blocked PASS; A5 [ACTIVE]+deferred derives committed PASS. Suite: 17 passed, 0 failed, exit 0.
   Result: PASS

Runtime verification (before): git show d4ce1f3~1:neural-lace/workstreams-ui/web/app.js | grep -c "planStatusSaysOpen"
  Commit: d4ce1f3~1 (pre-fix)
  Expected: FAIL — this command demonstrates the bug (guard absent)
  Observed: 0 occurrences; itemState() had no precedence clause (the bug: [ACTIVE] items derived 'shipped')
Runtime verification (after): grep -c "planStatusSaysOpen" neural-lace/workstreams-ui/web/app.js
  Commit: HEAD 3eb010f (contains d4ce1f3)
  Expected: PASS — guard present
  Observed: 2 occurrences (definition + itemState call); selftest A1-A5 green against extracted live source
Runtime verification: file neural-lace/workstreams-ui/web/app.js::planStatusSaysOpen
Runtime verification: test neural-lace/workstreams-ui/state/filter-status.selftest.js::A1

Git evidence:
  Commit: d4ce1f3903d18c89a29138daaad47a4deab3021f (2026-06-17, PR #62) — touched exactly the plan's 3 declared files (app.js +38/-1, filter-status.selftest.js +166, plan +168); contained in master + current branch.

Verdict: PASS
Confidence: 9
Reason: PROVEN: guard read at app.js:292-312; selftest extracting the real functions passed A1-A5 (17/17 suite, exit 0); before/after differential shows 0 guard occurrences at d4ce1f3~1 vs 2 at HEAD — the same check fails pre-fix and passes post-fix.

## Task 2 — branchGroup allDone short-circuit no longer bypasses the filter

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Fix branchGroup so the allDone short-circuit does not bypass the show-completed filter: items still obey visibleInTree; an all-complete branch shows the "N done hidden — use show done" affordance when show-completed is off; explicit-expand-reveals-done preserved only when show-completed/archived is on. Verification: mechanical
Verified at: 2026-07-02T21:06:44Z
Verifier: task-verifier agent

Oracle: specified — the plan's task Done-when exercised against current branchGroup code + the extraction-based selftest D1/C1-C4 checks; derived — pre-fix d4ce1f3~1 line 1685 as the RED reference.
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Bypass removed from code
   Command: grep -n "allDone || visibleInTree" neural-lace/workstreams-ui/web/app.js
   Output: sole match at line 1727 — inside the explanatory COMMENT describing the prior bug. The render path at app.js:1733 is unconditional: refs.filter(visibleInTree); empty-visible case at 1735-1738 renders the 'N done hidden — use "show done"' affordance. visibleInTree (app.js:1746-1750) = showArchived.checked || showCompleted.checked || !isComplete(r.item), so expanding a done branch with show-done ON still reveals items (intent preserved).
   Result: PASS
2. Behavioral proof via selftest
   Command: node neural-lace/workstreams-ui/state/filter-status.selftest.js
   Output: D1 "branchGroup visible-set filters by visibleInTree (allDone bypass removed)" PASS; C1 [ACTIVE]-fixed item INCLUDED at show-completed=false PASS; C2 genuinely-shipped EXCLUDED at show-completed=false PASS; C3 INCLUDED at show-completed=true PASS; C4 INCLUDED at show-archived=true PASS. Suite 17/17, exit 0.
   Result: PASS

Runtime verification (before): git show d4ce1f3~1:neural-lace/workstreams-ui/web/app.js | grep -n "allDone || visibleInTree"
  Commit: d4ce1f3~1 (pre-fix)
  Expected: FAIL — this command demonstrates the bug (leaky bypass present as CODE)
  Observed: line 1685: var visible = refs.filter(function (r) { return allDone || visibleInTree(r); }); — exactly the line the plan's Goal cited
Runtime verification (after): grep -n "allDone || visibleInTree" neural-lace/workstreams-ui/web/app.js
  Commit: HEAD 3eb010f (contains d4ce1f3)
  Expected: PASS — bypass survives only in the comment; filter unconditional
  Observed: only line 1727 (comment); code path 1733 filters unconditionally via visibleInTree; selftest D1 green
Runtime verification: file neural-lace/workstreams-ui/web/app.js::visibleInTree
Runtime verification: test neural-lace/workstreams-ui/state/filter-status.selftest.js::D1

Git evidence:
  Commit: d4ce1f3903d18c89a29138daaad47a4deab3021f — same commit as Task 1 (app.js hunk covers branchGroup 1723-1740).

Verdict: PASS
Confidence: 9
Reason: PROVEN: code read at app.js:1700-1750 shows unconditional visibleInTree filtering + the hidden-count affordance; selftest D1/C1-C4 green against extracted live source; before/after differential shows the bypass as live code at d4ce1f3~1:1685 vs comment-only at HEAD.

## Task 3 — state/filter-status.selftest.js proves precedence + filter behavior

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Add state/filter-status.selftest.js proving (a) an [ACTIVE]-text item with state:'shipped' derives non-complete and is INCLUDED when show-completed=false; (b) a genuinely-shipped item is EXCLUDED when show-completed=false and INCLUDED when true. Run existing state/selftest.js + state/reducer.selftest.js + the new test; all pass. Verification: mechanical
Verified at: 2026-07-02T21:06:44Z
Verifier: task-verifier agent

Oracle: specified — the task's (a)/(b) assertions executed directly; the test extracts the REAL app.js functions (its file header states "no replica"; E1-E4 assert extraction succeeded).
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Checks run:
1. File exists and is the d4ce1f3 artifact
   Command: ls -la neural-lace/workstreams-ui/state/filter-status.selftest.js; git log --oneline -- neural-lace/workstreams-ui/state/filter-status.selftest.js
   Output: 7880 bytes; sole history commit is d4ce1f3 (PR #62).
   Result: PASS
2. New test runs green — covers (a) via A1/A3/C1 and (b) via B1/B2/C2/C3
   Command: node neural-lace/workstreams-ui/state/filter-status.selftest.js
   Output: 17 passed, 0 failed, exit 0. One SKIP: check E (live /api/state cross-check) — "no canonical state path configured" in this worktree; test self-declares it best-effort/skippable.
   Result: PASS
3. Existing suite state/selftest.js
   Command: node neural-lace/workstreams-ui/state/selftest.js
   Output: Run 1: 22 passed / 1 failed — P22 "stale-temp cleanup ... sweptAtZero=false". Run 2: 23 passed, 0 failed (P22 PASS). P22 is a timing-sensitive Windows-mtime sub-check introduced by LATER commit 89479e5 (d4ce1f3 is its ancestor; 89479e5 touched store.js + selftest.js only — files this plan's diff never touched). Flake is unattributable to this plan's work.
   Result: PASS (green on re-run; flake provenance outside plan scope, PROVEN via git show --stat 89479e5 + d4ce1f3)
4. Existing suite state/reducer.selftest.js — DOES NOT EXIST and NEVER EXISTED
   Command: node neural-lace/workstreams-ui/state/reducer.selftest.js; git log --follow --diff-filter=ADR -- neural-lace/workstreams-ui/state/reducer.selftest.js; git ls-tree d4ce1f3 --name-only neural-lace/workstreams-ui/state/
   Output: MODULE_NOT_FOUND (file absent at HEAD); git history has zero add/delete/rename events for the path; the d4ce1f3 tree contains only filter-status.selftest.js, reconciler.selftest.js, selftest.js. The plan's Testing Strategy named a file that never existed at merge time — a plan-authoring inaccuracy, not a regression.
   Result: SKIPPED (file never existed; substantive intent "existing state suites stay green" satisfied by checks 3 + 5)
5. Existing suite state/reconciler.selftest.js (the actual sibling suite)
   Command: node neural-lace/workstreams-ui/state/reconciler.selftest.js
   Output: 33 passed, 0 failed.
   Result: PASS

Runtime verification: test neural-lace/workstreams-ui/state/filter-status.selftest.js::A1
Runtime verification: test neural-lace/workstreams-ui/state/filter-status.selftest.js::C2
Runtime verification: test neural-lace/workstreams-ui/state/selftest.js::P22
Runtime verification: test neural-lace/workstreams-ui/state/reconciler.selftest.js::S7
Runtime verification: file neural-lace/workstreams-ui/state/filter-status.selftest.js::extractFn

Git evidence:
  Commit: d4ce1f3903d18c89a29138daaad47a4deab3021f — added filter-status.selftest.js (+166 lines).

Verdict: PASS
Confidence: 8
Reason: PROVEN: the new test exists (sole-commit d4ce1f3), executed 17/17 green this session covering the task's (a) and (b) assertions against the real extracted app.js functions; existing suites green (selftest.js 23/23 on re-run — single P22 timing flake PROVEN to originate in later commit 89479e5 outside this plan's diff; reconciler.selftest.js 33/33). Caveat honestly noted: reducer.selftest.js named in the Done-when never existed in git history — unsatisfiable-as-written, treated as plan-authoring inaccuracy.

## DoD line — "state self-tests + new filter test pass"

EVIDENCE BLOCK
==============
Task ID: DoD-selftests
Task description: DoD checkbox "state self-tests + new filter test pass"
Verified at: 2026-07-02T21:06:44Z
Verifier: task-verifier agent
Oracle: specified — the named suites executed this session.
Comprehension-gate: not applicable (rung < 2)
Runtime verification: test neural-lace/workstreams-ui/state/filter-status.selftest.js::A1
Runtime verification: test neural-lace/workstreams-ui/state/selftest.js::P20
Runtime verification: test neural-lace/workstreams-ui/state/reconciler.selftest.js::S7
Commit: d4ce1f3903d18c89a29138daaad47a4deab3021f
Verdict: PASS
Confidence: 8
Reason: PROVEN: filter-status 17/17, selftest.js 23/23 (run 2; P22 flake provenance = commit 89479e5, outside plan scope), reconciler.selftest.js 33/33 — all executed 2026-07-02T21:0xZ this session. reducer.selftest.js never existed (see Task 3 check 4).

## DoD line — "All tasks checked off"

EVIDENCE BLOCK
==============
Task ID: DoD-all-tasks
Task description: DoD checkbox "All tasks checked off"
Verified at: 2026-07-02T21:06:44Z
Verifier: task-verifier agent
Oracle: mechanical — grep of the plan's ## Tasks section after Tasks 1-3 flips land this session.
Comprehension-gate: not applicable (rung < 2)
Runtime verification: file docs/plans/workstreams-completed-filter-fix-2026-06-17.md::- [x] 1.
Commit: d4ce1f3903d18c89a29138daaad47a4deab3021f
Verdict: PASS
Confidence: 9
Reason: PROVEN: Tasks 1, 2, 3 each verified PASS above and flipped by this verifier in the same session; the ## Tasks section contains no remaining unchecked task lines after the flips.

## NOT flipped (left for the orchestrator / closure)

- "SCRATCHPAD updated (n/a — builder worktree, no SCRATCHPAD per convention)" — the n/a rationale references the build-time builder worktree, which cannot be reconstructed; the CURRENT worktree does contain a SCRATCHPAD.md, so the n/a claim is not mechanically verifiable now. HYPOTHESIZED the n/a held at build time (would be REFUTED by evidence of a SCRATCHPAD in the PR-#62 builder worktree, which no longer exists to check). Left unflipped.
- "Completion report appended" — condition is FALSE: no completion report exists in the plan file. Appending it is closure work (close-plan.sh generates it); the orchestrator owns Status + closure per DEC-2026-07-02-002. Left unflipped.
