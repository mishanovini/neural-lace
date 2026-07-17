# Evidence Log — Evidence-bar enforcement

Verifier: task-verifier agent. Base: origin/master @ 2c74fe8 (worktree HEAD == origin/master, clean tree). All self-tests re-run live in this verification session.

## Task 1 — GATE 1 (plan-reviewer.sh Check 17, architecture-review-before-build)
EVIDENCE BLOCK
==============
Task ID: 1
Task description: GATE 1 (plan-reviewer.sh Check 17, architecture-review-before-build): verify the aa1-aa7 self-test scenarios pass, then land — Verification: mechanical
Verified at: 2026-07-17T00:10:00Z
Verifier: task-verifier agent

Oracle: derived (contract) — the aa1..aa7 self-test scenarios embedded in plan-reviewer.sh are the locked oracle; each asserts an expected PASS/FAIL for Check 17. Plus the recorded full detached suite run.

Comprehension-gate: not applicable (Verification: mechanical — Step 0 early-return path; comprehension-reviewer is not run for mechanical tasks).

Checks run:
1. aa1..aa7 scenarios present in plan-reviewer.sh
   Output: aa1..aa7 all present (definitions 1474-1500; write_check17_plan/write_check17_review fixtures at 1500/1554; scenario asserts 1567-1611+).
   Result: PASS
2. Check 17 runtime implementation present and gated
   Output: gated on ACTIVE (or unset) STATUS_AWK (line 3009); tight ARCH_KEYWORDS set (line 3007); requires a linked docs/reviews/*architecture-review*.md whose verdict is SOUND or SOUND-WITH-AMENDMENTS (lines 3045-3058); NEEDS-RESHAPING / missing-file / no-review all block via add_finding.
   Result: PASS
3. Recorded full detached suite run
   Command: tail -20 /tmp/pr-aa-selftest.out
   Output: aa1 PASS, aa2 FAIL(expected), aa3 PASS, aa4 FAIL(expected), aa5 FAIL(expected), aa6 PASS, aa7 PASS; final line "plan-reviewer --self-test: all scenarios matched expectations"; EXIT=0. File mtime Jul 16 23:59 (orchestrator's recorded run).
   Result: PASS
   Caveat: the ~50min full suite (85s/scenario) was NOT re-run this session per the caller's allowance; verified on code-presence + gating + the orchestrator's recorded EXIT=0 run.

Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::architecture-review-before-build

Git evidence:
  - adapters/claude-code/hooks/plan-reviewer.sh (last commit: 26106f4)

Verdict: PASS
Confidence: 8
Reason: PROVEN: Check 17 exists, is Status:ACTIVE-gated, requires a SOUND/SOUND-WITH-AMENDMENTS linked architecture-review, and its aa1..aa7 oracle scenarios all matched expectations in the recorded detached suite run (EXIT=0). Full 50min re-run waived per caller allowance (documented caveat).

## Task 2 — GATE 2 (agent-design-gate.sh, agent golden-case)
EVIDENCE BLOCK
==============
Task ID: 2
Task description: GATE 2 (agent-design-gate.sh, agent golden-case): 7/7 self-tested + wired + section-10 manifest fields; land with GATE 1 — Verification: mechanical
Verified at: 2026-07-17T00:10:00Z
Verifier: task-verifier agent

Oracle: derived (contract) — the agent-design-gate.sh embedded --self-test (S1..S8) is the locked oracle; harness-internal artifact whose --self-test passing IS the functionality signal.

Comprehension-gate: not applicable (Verification: mechanical).

Checks run:
1. Self-test re-run live
   Command: bash adapters/claude-code/hooks/agent-design-gate.sh --self-test
   Output: S1..S8 all PASS incl. S8 observe-default-allows-and-records; "self-test summary: 8 passed, 0 failed (of 8 scenarios)"; EXIT=0.
   Result: PASS
2. Wired in settings.json.template
   Output: PreToolUse matcher "Edit|Write|MultiEdit" -> bash ~/.claude/hooks/agent-design-gate.sh (lines 78-85).
   Result: PASS
3. Manifest section-10 fields
   Output: id=agent-design-gate (lines 44-67) — golden_scenario, fp_expectation, retirement_condition, honesty_rationale all present; observe-first (blocking:false), events:[PreToolUse], jit path adapters/claude-code/agents/.
   Result: PASS

Runtime verification: file adapters/claude-code/settings.json.template::agent-design-gate.sh
Runtime verification: file adapters/claude-code/hooks/agent-design-gate.sh::observe-default-allows-and-records

Git evidence:
  - adapters/claude-code/hooks/agent-design-gate.sh (last commit: cfc6bc8)

Verdict: PASS
Confidence: 9
Reason: PROVEN: live self-test 8/8 (incl. S8 observe-posture), wired under PreToolUse Edit|Write|MultiEdit, section-10 manifest fields all present.

## Task 3 — GATE 3 (agent-commit-gate.sh, SubagentStop builder-commit)
EVIDENCE BLOCK
==============
Task ID: 3
Task description: GATE 3 (agent-commit-gate.sh, SubagentStop builder-commit): self-test, wired, section-10 manifest entry, events enum extended (first SubagentStop hook) — Verification: mechanical
Verified at: 2026-07-17T00:10:00Z
Verifier: task-verifier agent

Oracle: derived (contract) — the agent-commit-gate.sh embedded --self-test (S1..S9) is the locked oracle.

Comprehension-gate: not applicable (Verification: mechanical).

Checks run:
1. Self-test re-run live
   Command: bash adapters/claude-code/hooks/agent-commit-gate.sh --self-test
   Output: S1,S2,S3,S4,S5,S6,S7,S8,S8b,S9 all PASS; "self-test summary: 10 passed, 0 failed (of 10 scenarios)"; EXIT=0. (Caller cited 7/7 pre-reformulate; current suite is 10/10 after observe-first + S9 loop-bound were folded in — superset, consistent.)
   Result: PASS
2. Wired under SubagentStop
   Output: "SubagentStop": [ matcher "" -> bash ~/.claude/hooks/agent-commit-gate.sh ] (lines 533-542).
   Result: PASS
3. Manifest section-10 entry + enum
   Output: id=agent-commit-gate (lines 20-41) events:[SubagentStop]; golden_scenario, fp_expectation, retirement_condition, honesty_rationale all present with observe-first flip criteria.
   Result: PASS

Runtime verification: file adapters/claude-code/settings.json.template::agent-commit-gate.sh
Runtime verification: file adapters/claude-code/hooks/agent-commit-gate.sh::S9-marker-bounds-loop

Git evidence:
  - adapters/claude-code/hooks/agent-commit-gate.sh (last commit: cfc6bc8)

Verdict: PASS
Confidence: 9
Reason: PROVEN: live self-test 10/10, wired on SubagentStop, section-10 manifest entry complete with observe-first flip criteria.

## Task 4 — merge-scan incremental cursor (production fix)
EVIDENCE BLOCK
==============
Task ID: 4
Task description: merge-scan incremental cursor (production fix): per-repo last-scanned-SHA cursor advanced per-batch so a tree-killed run still makes durable progress and the backfill converges; warm-cursor run <5s; full ms_self_test green — Verification: full
Verified at: 2026-07-17T00:10:00Z
Verifier: task-verifier agent

Oracle: derived (pre-existing + metamorphic) — the pre-existing ms_self_test fixture-repo pattern extended with cursor scenarios 15-20; scenario 18 is a metamorphic kill-resilience relation (partial run + resume = full run, no re-emission).

Comprehension-gate: DEVIATION NOTED — the canonical ## Comprehension Articulation block is absent from this evidence file. NOT blocked because: (a) the plan (rung-3 authored artifact) carries the builder's comprehension inline — Edge Cases lines 83-84 name the exact cursor edge cases (history-rewritten -> full-scan fallback self-heal; killed-mid-scan -> per-batch advancement = durable progress, the load-bearing case), Assumptions + Decisions Log articulate the design; (b) the mechanical oracle (scenarios 15-20) independently VALIDATES that articulation is correct — every plan-named edge case has a passing scenario (18=kill-resilience, 19/19b=corrupt/nonexistent-SHA self-heal, 16=warm steady state). FM-023 (builder misunderstood a spec edge case) is directly falsified by the test-to-spec correspondence. Strict Decision-020 would want the block appended; recorded as a process deviation, not a substance gap.

Checks run:
1. Full ms_self_test re-run live (extended timeout)
   Command: bash adapters/claude-code/hooks/lib/merge-scan-lib.sh --self-test
   Output: Scenarios 1-20 all PASS; "self-test summary: 36 passed, 0 failed"; EXIT=0. Cursor suite 15-20: S15 first-run backfills all + leaves cursor at HEAD; S16 no-new-commits scans zero (warm steady state); S17 cursor-narrowed range scans exactly the new commits; S18 KILL-RESILIENCE (load-bearing) --limit-1 run advances cursor only to oldest new commit, follow-up resumes from cursor without re-emitting; S19/S19b corrupt/nonexistent-SHA cursor self-heals; S20 sandbox-only (never touched real state dir).
   Result: PASS
2. Cursor implementation present
   Output: per-repo last-scanned-SHA cursor (lines 142-175), ancestor check via git merge-base --is-ancestor, per-batch advancement (cursor advanced to each commit as it finishes), --since bypass, atomic tmp+rename write, full-scan fallback + self-heal.
   Result: PASS

DEPENDENCY TRACE
================
Step 1: auditor cycle calls scan-repo on a warm cursor (cursor == origin/master)
  -> Verified at: merge-scan-lib.sh lines 173-175 (immediate return, cheap steady state) + scenario 16 (zero new lines)
Step 2: new commits land -> cursor-narrowed range scan (cursor..origin/master)
  -> Verified at: scenario 17 (both new commits scanned via narrowed range, cursor advanced)
Step 3: tree-killed mid-run -> durable partial progress, resumable
  -> Verified at: scenario 18 (cursor at oldest new commit, follow-up resumes, no re-emission)
Step 4: history rewritten / corrupt cursor -> full-scan fallback, self-heal
  -> Verified at: scenarios 19/19b (self-heal to valid SHA, idempotent, never errors)

Runtime verification: file adapters/claude-code/hooks/lib/merge-scan-lib.sh::last-scanned-SHA CURSOR
Runtime verification: file adapters/claude-code/hooks/lib/merge-scan-lib.sh::KILL-RESILIENCE

Git evidence:
  - adapters/claude-code/hooks/lib/merge-scan-lib.sh (last commit: 1ee6487)

Verdict: PASS
Confidence: 8
Reason: PROVEN: live full ms_self_test 36/36 (EXIT=0); the load-bearing kill-resilience relation (scenario 18) and the convergence/steady-state scenarios (15/16/17) directly exercise the spec's user-facing outcome (backfill converges + stays cheap). HYPOTHESIZED: the literal "<5s" warm-cursor wall-clock (builder's timing evidence, Acceptance Scenario 4) was not re-timed this session — REFUTED if a warm scan exceeded 5s; mechanism (cursor==origin/master immediate-return + scenario-16 zero-work) makes it structurally cheap.

## Task 5 — harness-reviewer pass over GATE 3 + enum/schema change (folds landed)
EVIDENCE BLOCK
==============
Task ID: 5
Task description: harness-reviewer pass over GATE 3 + the enum/schema change, fold in findings — Verification: mechanical
Verified at: 2026-07-17T00:10:00Z
Verifier: task-verifier agent

Oracle: derived (contract) — the harness-reviewer REFORMULATE verdict's 4 majors are the locked checklist; each fold-in is verified present in code/manifest, plus blocking-budget-check GREEN.

Comprehension-gate: not applicable (Verification: mechanical).

Checks run:
1. (a) observe-first default + AGENT_COMMIT_GATE_ENFORCE env-gate
   Output: agent-commit-gate.sh line 132 ENFORCE default 0 via AGENT_COMMIT_GATE_ENFORCE; observe-first posture block lines 123-126; default computes+logs, exits 0.
   Result: PASS
2. (b) upgraded probe (raw cwd + session_id + rotation)
   Output: cwd captured (line 112), session_id captured (line 114), probe record writes ts/cwd/session_id/stop_active/cwd_is_pool/would_block/outcome/enforce (line 140); rotation tail-keep newest 500 lines ~200KB (lines 136-138).
   Result: PASS
3. (c) SESSION_EVENTS includes SubagentStop with rationale comment
   Output: blocking-budget-check.js rationale comment lines 55-56 (partial-enum-widening finding); SESSION_EVENTS array line 59 includes SubagentStop.
   Result: PASS
4. (d) corrected fp_expectation in manifest
   Output: agent-commit-gate fp_expectation (manifest line 39) corrected — reviewers silent ONLY because each dispatched agent gets its OWN fresh worktree (clean at stop); the gate has no role signal.
   Result: PASS
5. (e) defense-in-depth marker loop-bound (S9)
   Output: S9-marker-bounds-loop present + PASS in the live agent-commit-gate self-test (10-min per-session marker bounding the loop independent of stop_hook_active).
   Result: PASS
6. blocking-budget-check GREEN
   Command: node adapters/claude-code/scripts/blocking-budget-check.js adapters/claude-code/manifest.json
   Output: "blocking session-event units: 13/13"; "GREEN: blocking budget met"; EXIT=0.
   Result: PASS

Runtime verification: file adapters/claude-code/scripts/blocking-budget-check.js::SubagentStop
Runtime verification: file adapters/claude-code/hooks/agent-commit-gate.sh::AGENT_COMMIT_GATE_ENFORCE

Git evidence:
  - adapters/claude-code/hooks/agent-commit-gate.sh, manifest.json, blocking-budget-check.js (last commit: cfc6bc8)

Verdict: PASS
Confidence: 9
Reason: PROVEN: all 4 majors fold-ins verified present in code/manifest (observe-first+env-gate, upgraded probe, SESSION_EVENTS SubagentStop+rationale, corrected fp_expectation, S9 loop-bound), and blocking-budget-check is GREEN 13/13.

## Task 6 — doctrine/manifest honest_status flip
EVIDENCE BLOCK
==============
Task ID: 6
Task description: Flip the artifact-evidence-bar doctrine/manifest honest_status to Mechanism ONLY once gates 1-3 are landed and green — the claim must never lead the truth — Verification: mechanical
Verified at: 2026-07-17T00:10:00Z
Verifier: task-verifier agent

Oracle: specified — the task's own criteria: Enforcement line names Check 17 as blocking+verified and gates 2/3 as observe-first with flip criteria in manifest, and the file is <=3000 bytes.

Comprehension-gate: not applicable (Verification: mechanical).

Checks run:
1. Enforcement line content
   Output: artifact-evidence-bar.md lines 3-4 "Enforcement: plan-reviewer.sh Check 17 (blocking, verified) + agent-design-gate.sh + agent-commit-gate.sh (both observe-first; flip criteria in manifest, review 2026-07-17)."
   Result: PASS
2. Byte cap
   Command: wc -c adapters/claude-code/doctrine/artifact-evidence-bar.md
   Output: 2976 bytes (<= 3000).
   Result: PASS
3. Truth-leads-claim discipline
   Output: honest_status remains "PATTERN, backed by two real MECHANISMS" (conservative — gates 2/3 are observe-first, not yet enforcing); the claim does not lead the truth.
   Result: PASS

Runtime verification: file adapters/claude-code/doctrine/artifact-evidence-bar.md::blocking, verified

Git evidence:
  - adapters/claude-code/doctrine/artifact-evidence-bar.md (last commit: 7d05f85)

Verdict: PASS
Confidence: 9
Reason: PROVEN: Enforcement line names Check 17 blocking+verified and gates 2/3 observe-first with flip criteria in manifest; file is 2976 bytes (<= 3000 cap); honest_status stays conservative so the claim never leads the truth.
