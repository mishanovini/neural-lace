# Evidence Log — Concurrent-Ownership Gate — promote Practice 8 from Pattern to Mechanism

## Task 1 — Author adapters/claude-code/hooks/concurrent-ownership-gate.sh
EVIDENCE BLOCK
==============
Task ID: 1
Task description: Author adapters/claude-code/hooks/concurrent-ownership-gate.sh — PreToolUse gate with command-segment parsing, Edit/Write payload handling, ownership check, block message naming owning worktree + branch + coordination path, structured waiver, and a sandboxed --self-test
Verified at: 2026-07-12T22:27:53Z
Verifier: task-verifier agent (Verification: mechanical — oracle re-run on landed master tree)

Oracle: mechanical — deterministic --self-test of the gate (12+ scenarios incl. the lesson's golden bulk-defer block), re-executed by the verifier against master HEAD, not builder-claimed output
Verification level: mechanical
Comprehension-gate: not applicable (Verification: mechanical — Step 0 early-return path; articulation not required)

Checks run:
1. Gate self-test re-run on landed tree
   Command: bash adapters/claude-code/hooks/concurrent-ownership-gate.sh --self-test
   Output: self-test summary: 19 passed, 0 failed (of 19 scenarios) — incl. (1) golden-bulk-defer-blocks-naming-worktree, (2) unowned-single-flip-allowed, (3) waiver-honored-and-ledger-logged, (4) stale-waiver-rejected, (5) clause-less-waiver-rejected, (6) edit-payload-owned-status-flip-blocked, (7) own-plan-edit-from-owning-worktree-allowed, (16) powershell-tool-parsed, (18) foreign-repo-claim-does-not-block
   Result: PASS
2. Structural spot-check: waiver + ledger libs sourced; self-test sandboxed
   Output: lines 118-121 source lib/waiver-purpose-clause.sh and lib/signal-ledger.sh; lines 124-128 route COG_CLAIMS_DIR to tempdir under HARNESS_SELFTEST=1; header carries the §10 evidence fields (golden_scenario / fp_expectation / retirement_condition) as the doc
   Result: PASS

Runtime verification: test adapters/claude-code/hooks/concurrent-ownership-gate.sh::--self-test
Runtime verification: file adapters/claude-code/hooks/concurrent-ownership-gate.sh::source "$_COG_SELF_DIR/lib/waiver-purpose-clause.sh"

Git evidence:
  Commit: 7e6b5c4 (feat(hooks): concurrent-ownership gate — 929 lines NEW)
  Commit: 1505d27 (fix(gate): repo-scope ownership claims + reviewer minors — +121 lines)
  Both ancestors of master HEAD (verified via git merge-base --is-ancestor).
Docs impact: none — verified substantive (gate header comment IS the doc; §10 fields live in manifest entry, confirmed present)

Verdict: PASS
Confidence: 9
Reason: PROVEN: verifier re-ran the gate's sandboxed --self-test on the landed master tree — 19/19 scenarios PASS including the golden bulk-defer block naming the owning worktree, waiver honored/stale/clause-less paths, and Edit-payload blocking; libs and sandboxing confirmed at file:line.

## Task 2 — Extend adapters/claude-code/scripts/broadcast-active-session.sh
EVIDENCE BLOCK
==============
Task ID: 2
Task description: Extend broadcast-active-session.sh with same-machine worktree visibility (worktrees array in state JSON, additive) and local per-branch claims (claim / unclaim subcommands + claims surfaced by check), keeping existing state.json consumers compatible
Verified at: 2026-07-12T22:30:31Z
Verifier: task-verifier agent (Verification: mechanical — oracle re-run on landed master tree)

Oracle: mechanical — deterministic --self-test of the broadcast script (S1-S6 pre-existing oracle preserved + S7-S10 new scenarios), re-executed by the verifier against master HEAD
Verification level: mechanical
Comprehension-gate: not applicable (Verification: mechanical — Step 0 early-return path)

Checks run:
1. Broadcast self-test re-run on landed tree
   Command: bash adapters/claude-code/scripts/broadcast-active-session.sh --self-test
   Output: [self-test] 10 passed, 0 failed — S1-S6 pre-existing scenarios stay green (backward compat), S7 claim file schema, S8 worktrees array in state.json, S9 unclaim removes claim, S10 check_local repo-scoping
   Result: PASS
2. Structural spot-check: subcommands + usage text
   Output: claim)/unclaim)/check) dispatch at lines 706-708; worktrees array injected into state JSON at line 227 (_worktrees_json, line 170); usage text updated (lines 716-717, 735 name the new subcommands + worktrees consumption)
   Result: PASS

Runtime verification: test adapters/claude-code/scripts/broadcast-active-session.sh::--self-test
Runtime verification: file adapters/claude-code/scripts/broadcast-active-session.sh::"worktrees": $worktrees

Git evidence:
  Commit: 7e6b5c4 (broadcast-active-session.sh +253 lines)
  Commit: 1505d27 (+82 lines, repo-scoped claims)
Docs impact: none — verified substantive (usage text inside the script updated in the same change, confirmed at lines 716-735)

Verdict: PASS
Confidence: 9
Reason: PROVEN: pre-existing oracle S1-S6 stays green AND new scenarios S7-S10 pass on the landed tree (10/10, exit 0); claim/unclaim/check dispatch and additive worktrees array confirmed at file:line.

## Task 3 — Register in manifest.json + wire in settings.json.template
EVIDENCE BLOCK
==============
Task ID: 3
Task description: Register the gate in adapters/claude-code/manifest.json (kind: gate, blocking: true, golden_scenario / fp_expectation / retirement_condition from the lesson) and wire it in adapters/claude-code/settings.json.template under PreToolUse for both Bash|PowerShell and Edit|Write|MultiEdit matchers
Verified at: 2026-07-12T22:33:04Z
Verifier: task-verifier agent (Verification: mechanical — oracle re-run on landed master tree)

Oracle: mechanical — jq validity + jq/python extraction of the manifest entry and template matcher groups on master HEAD
Verification level: mechanical
Comprehension-gate: not applicable (Verification: mechanical — Step 0 early-return path)

Checks run:
1. JSON validity
   Command: jq -e '.' adapters/claude-code/manifest.json && jq -e '.' adapters/claude-code/settings.json.template
   Output: both valid JSON
   Result: PASS
2. Manifest entry fields (constitution §10)
   Output: id=concurrent-ownership-gate, kind=gate, blocking=true, events=[PreToolUse], wired_template=true, selftest=true; golden_scenario cites the 2026-07-11 lesson + nl-issue [35]; fp_expectation is substantive (terminal-state token requirement, repo-scoped claims, known fail-open miss classes, claim-lifecycle caveat); retirement_condition names the upstream launcher-lock condition + ADR 059 D7 waiver-density demotion
   Result: PASS
3. Template wiring — both matcher groups under PreToolUse
   Command: python extraction of hooks.PreToolUse groups containing concurrent-ownership-gate
   Output: PreToolUse matchers "Bash|PowerShell" AND "Edit|Write|MultiEdit" both invoke bash ~/.claude/hooks/concurrent-ownership-gate.sh
   Result: PASS

Runtime verification: file adapters/claude-code/manifest.json::"id": "concurrent-ownership-gate"
Runtime verification: file adapters/claude-code/settings.json.template::concurrent-ownership-gate.sh

Git evidence:
  Commit: 7e6b5c4 (manifest.json +24, settings.json.template +18)
  Commit: 1505d27 (manifest fp_expectation update, template +4)
Docs impact: none — verified substantive (manifest IS the enforcement inventory doc; additionally gen-architecture-doc.sh --check re-run GREEN — committed docs/harness-architecture.md matches a fresh regen, covering the in-flight scope update)

Verdict: PASS
Confidence: 9
Reason: PROVEN: both JSON files parse; the manifest entry carries all three §10 evidence fields with lesson-grounded content; the template wires the gate under PreToolUse in exactly the two required matcher groups — all extracted mechanically from master HEAD.

## Task 4 — Run both self-tests; both must exit 0 with all scenarios PASS
EVIDENCE BLOCK
==============
Task ID: 4
Task description: Run bash adapters/claude-code/hooks/concurrent-ownership-gate.sh --self-test and bash adapters/claude-code/scripts/broadcast-active-session.sh --self-test; both must exit 0 with all scenarios PASS
Verified at: 2026-07-12T22:35:31Z
Verifier: task-verifier agent (Verification: mechanical — oracles re-executed by the verifier, not accepted from builder claims)

Oracle: mechanical — the two --self-test suites themselves; the Closure Contract names them as the acceptance surface (acceptance-exempt harness plan, constitution §4: self-test passing IS the demonstration)
Verification level: mechanical
Comprehension-gate: not applicable (Verification: mechanical — Step 0 early-return path)

Checks run:
1. Gate self-test
   Command: bash adapters/claude-code/hooks/concurrent-ownership-gate.sh --self-test
   Output: self-test summary: 19 passed, 0 failed (of 19 scenarios); exit 0
   Result: PASS
2. Broadcast self-test
   Command: bash adapters/claude-code/scripts/broadcast-active-session.sh --self-test
   Output: [self-test] 10 passed, 0 failed; exit 0
   Result: PASS
3. Closure Contract cross-check
   Output: golden-bulk-block (scenario 1), clean-pass (scenario 2), waiver-honored (scenario 3) all present and PASS — matches the plan's Expected outputs exactly
   Result: PASS

Runtime verification: test adapters/claude-code/hooks/concurrent-ownership-gate.sh::--self-test
Runtime verification: test adapters/claude-code/scripts/broadcast-active-session.sh::--self-test

Git evidence:
  Commit: 1505d27 (final landed state both suites ran against; ancestor of master HEAD)
Docs impact: none — verified substantive (evidence is these summary lines, now durably captured in this evidence log rather than only the builder report)

Verdict: PASS
Confidence: 9
Reason: PROVEN: verifier re-executed both suites on the landed master tree in this session — 19/19 and 10/10, both exit 0, matching the Closure Contract's expected outputs including golden-bulk-block, clean-pass, and waiver-honored.

