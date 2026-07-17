# Evidence Log — Cockpit v2 — cross-machine plan store (push-projected, staleness-detecting)

## Task 1 — The ONE parser + the ONE resolver (shared module)

EVIDENCE BLOCK
==============
Task ID: 1
Task description: [serial] **The ONE parser + the ONE resolver (shared module).** Build one parser + one resolver, used by every consumer. Handles: numeric AND lettered ids, continuation lines, the [serial] prefix, the Verification suffix, correct JSON escaping; --self-test incl. malformed plan -> damaged, never a silent zero. — Verification: mechanical
Verified at: 2026-07-17T11:49:18Z
Verifier: task-verifier agent (Verification: mechanical — full re-derivation; no prior evidence artifact existed)
Commit: fbb58a7dfe1dd0ad0fdee326dd4f5dece4b7a0db

Oracle: derived (pre-existing) — plan-lifecycle.sh's extract_all_task_line_ids grammar (the pre-existing lettered-id oracle) + the pre-existing server/auditor/cockpit self-test suites (139+18+84 tests green before this change) + the real docs/plans/** corpus.
Verification level: mechanical
Comprehension-gate: not applicable (Verification: mechanical — Step 0 routing exempts mechanical tasks from the R2+ comprehension-gate)

Checks run:
1. Self-test: shared module
   Command: node neural-lace/workstreams-ui/server/plan-parse.js --self-test
   Output: "plan-parse self-test summary: 14 passed, 0 failed" (incl. "loadPlanFile reports damaged (present but unreadable)" — the malformed-plan->damaged case, exercised via a directory at a .md path)
   Result: PASS
2. Self-test: auditor (spawn-heavy, real git/bash CLIs)
   Command: node neural-lace/workstreams-ui/server/auditor.js --self-test
   Output: "self-test summary: 18 passed, 0 failed" (exit 0) — full parity, no regression from the repoint
   Result: PASS
3. Self-test: server suite incl. new S60-S63
   Command: node neural-lace/workstreams-ui/server/server.selftest.js
   Output: "self-test summary: 148 passed, 0 failed" — S60 numeric regression, S60b lettered ids, S60c quote/newline JSON round-trip, S61b archive resolution, S61c honest null, S62/S62b live GET /api/ask/<id> counts lettered tasks, S63 live GET resolves archive-only plan
   Result: PASS
4. Self-test: cockpit web regression (untouched surface)
   Command: node neural-lace/workstreams-ui/web/cockpit.selftest.js
   Output: "self-test summary: 84 passed, 0 failed"
   Result: PASS
5. Grammar port fidelity (verbatim)
   Command: sed -n '335,360p' adapters/claude-code/hooks/plan-lifecycle.sh vs plan-parse.js:103
   Output: awk grammar ^([A-Za-z]+\.)?[0-9]+[A-Za-z]?(\.[0-9]+[A-Za-z]?)* is character-identical to TASK_ID_TOKEN_RE; line anchor ^- \[[ xX]\][ \t]+ identical to TASK_LINE_START_RE (plan-parse.js:95)
   Result: PASS
6. Resolver checks archive/
   Output: plan-parse.js:215-218 — candidates are docs/plans/<slug>.md THEN docs/plans/archive/<slug>.md; honest null at :224
   Result: PASS
7. absent vs damaged distinction
   Output: plan-parse.js:242-246 — ENOENT -> {reason:'absent', error:null}; ANY other read failure -> {reason:'damaged', error:<message>}; never a silent zero
   Result: PASS
8. Old private implementations GONE (deleted, not shadowed)
   Output: git show fbb58a7 shows deleted TASK_LINE_RE = /^- \[([ xX])\][ \t]*([0-9]+(?:\.[0-9]+)?)\./ + STATUS_LINE_RE from BOTH server.js and auditor.js; grep confirms remaining checkbox regexes in both files are unrelated surfaces (OPERATOR_TODO_ITEM_RE server.js:271, AUTO_POINTER_RE server.js:280, POINTER_RE auditor.js:294, self-test assertions). Call-sites now route through require('./plan-parse.js'): server.js:38,779,792,795; auditor.js:122,233,244,247
   Result: PASS
9. plan-lifecycle.sh untouched (explicitly forbidden by the task)
   Output: git show --stat fbb58a7 lists exactly 5 files, plan-lifecycle.sh absent; git status --porcelain for the file is clean; last commit touching it is 9fe4aba (pre-existing)
   Result: PASS
10. Numeric-fact re-derivation: "176 lettered-id task lines"
   Command: grep -rEh "^- \[[ xX]\][ \t]+[A-Za-z]+\.[0-9]" docs/plans --include="*.md" | wc -l
   Output: 176 (exactly the plan's cited number; +2 trailing-letter 20R-style lines)
   Result: PASS
11. Adversarial probe against the real corpus
   Command: node -e "require('./plan-parse.js').loadPlanFile(...)" on the live plan + a real archived lettered plan
   Output: cockpit plan -> ok=true, status=ACTIVE, 7 tasks, ids 1..7, task 1 done=false; capture-codify-pr-template.md (archive-only) -> resolved via archive/, 15 lettered tasks (sample id A.1). Falsification attempt on suffix-stripping FAILED correctly: task 1's mid-description QUOTED mention of the Verification suffix is preserved while its real trailing "— Verification: mechanical" suffix is stripped (description tail = "never a silent zero")
   Result: PASS

Runtime verification: test neural-lace/workstreams-ui/server/plan-parse.js::--self-test
Runtime verification: test neural-lace/workstreams-ui/server/auditor.js::--self-test
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::S60-S63
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::regression
Runtime verification: file neural-lace/workstreams-ui/server/plan-parse.js::TASK_ID_TOKEN_RE
Runtime verification: file adapters/claude-code/hooks/plan-lifecycle.sh::extract_all_task_line_ids

DEPENDENCY TRACE
================
Step 1: GET /api/ask/<id> (or auditor cycle) needs a plan's tasks/status
  v Verified at: server.js:855 (countPlanTasks call-site), auditor.js:676-677
Step 2: slug -> absolute path via the ONE resolver (docs/plans/ then archive/)
  v Verified at: server.js:792,795 + auditor.js:244,247 -> planParse.resolvePlanAbsPath (plan-parse.js:213-225); S61b/S63 green
Step 3: path -> honest read (ok | absent | damaged) via the ONE loader
  v Verified at: plan-parse.js:237-254; self-test cases absent/damaged/ok all green
Step 4: markdown -> tasks via the ONE grammar (numeric + lettered + prefix/suffix/continuations)
  v Verified at: plan-parse.js:95-190; S60/S60b/S60c green
Step 5: user-observable outcome — the API now counts ALL tasks incl. lettered ids and archive-only plans
  v Verified at: server.selftest.js S62 ("counts ALL THREE tasks (2 lettered + 1 numeric)") and S63 (archive-only plan resolves) — both green in the 148/148 run

Git evidence:
  Files modified in commit fbb58a7 (2026-07-17):
    - neural-lace/workstreams-ui/server/plan-parse.js (NEW, 411 lines)
    - neural-lace/workstreams-ui/server/server.js
    - neural-lace/workstreams-ui/server/auditor.js
    - neural-lace/workstreams-ui/server/server.selftest.js
    - docs/plans/cockpit-v2-push-materialized-store.md (Status DRAFT->ACTIVE + Files-to-Modify section + Decisions Log entry, documented inline)

Verdict: PASS
Confidence: 9
Reason: PROVEN: all four suites re-executed by the verifier (14/14, 18/18, 148/148, 84/84 — outputs observed, not trusted); grammar is a character-identical port of the pre-existing plan-lifecycle.sh oracle; the "176 lettered lines" numeric claim independently re-derived at exactly 176; old private grammars shown DELETED in the diff with call-sites re-routed through plan-parse.js; plan-lifecycle.sh untouched; an adversarial suffix-stripping falsification attempt failed correctly.
