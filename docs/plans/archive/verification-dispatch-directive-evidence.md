# Evidence Log — Verification dispatch is standard process (harness governance)

## Task V1 — CLAUDE.md <=4-line Pattern-class pointer bullet

EVIDENCE BLOCK
==============
Task ID: V1
Task description: Replace the 11-line always-loaded directive in CLAUDE.md with a <=4-line pointer bullet (Pattern-class verbs, no "does NOT apply / is overridden" mechanism claim). Verification: mechanical (line count; claude-md-hygiene-gate.sh check 2c no longer classifies it as extractable rule-body).
Verified at: 2026-07-29T22:54:19Z
Verifier: task-verifier agent (reconciliation pass; work landed 2026-07-28 in 84f5a3c)

Oracle: specified — the plan's V1 text (line-count cap + hygiene-gate 2c non-classification), exercised mechanically against the REAL file content and the REAL 84f5a3c diff.

Comprehension-gate: skipped — rung field missing (plan header has no `rung:`; treated as rung 0)
Operator invariants: none registered (exit 3)

Checks run:
1. Bullet exists and is exactly 4 lines
   Command: grep -n "Verification dispatch is standard process" adapters/claude-code/CLAUDE.md; awk '/Verification dispatch is standard process/,/^$/' ... | grep -c .
   Output: line 27 start; 4 non-empty lines (27-30)
   Result: PASS (<=4-line cap met)
2. No mechanism claim in the bullet or anywhere in CLAUDE.md
   Command: grep -n "does NOT apply\|overridden" adapters/claude-code/CLAUDE.md
   Output: no hits ("Agent tool" appears only inside the new bullet as the thing NOT to cite)
   Result: PASS
3. Shipped diff is the 4-line bullet only
   Command: git show 84f5a3c -- adapters/claude-code/CLAUDE.md
   Output: +4 lines, no deletions. NOTE (honest finding): the "11-line directive" being replaced was a REFORMULATE'd draft never committed — git log -S 'does NOT apply' -- adapters/claude-code/CLAUDE.md returns zero commits. The verifiable Done state (a <=4-line Pattern-class pointer, no mechanism claim) holds.
   Result: PASS
4. Hygiene-gate check 2c does not classify the bullet as rule-body
   Command: sourced detect_hygiene_violations() from claude-md-hygiene-gate.sh; ran against REAL current CLAUDE.md content + REAL added lines from `git show 84f5a3c` (SIZE_THRESHOLD=120)
   Output: FIND_SIZE=0 FIND_RULE_BODY=0 FIND_DUPLICATION=0; FINDINGS empty. (2c fires only on >5-line added runs; the run is 4 lines, and the direct replay confirms 0.)
   Result: PASS
5. Gate self-test
   Command: bash adapters/claude-code/hooks/claude-md-hygiene-gate.sh --self-test
   Output: 7 passed, 0 failed
   Result: PASS

Runtime verification: file adapters/claude-code/CLAUDE.md::Verification dispatch is standard process, not a user request
Runtime verification: test adapters/claude-code/hooks/claude-md-hygiene-gate.sh::--self-test
Runtime verification: test adapters/claude-code/hooks/claude-md-hygiene-gate.sh::detect_hygiene_violations(real CLAUDE.md + 84f5a3c added lines) -> FIND_RULE_BODY=0

Git evidence:
  adapters/claude-code/CLAUDE.md — modified in 84f5a3c (2026-07-28 20:33:17 -0700), ancestor of origin/master (tip 9708ced)

Verdict: PASS
Confidence: 9
Reason: PROVEN: the 4-line bullet exists at CLAUDE.md:27-30 with no mechanism claim, and detect_hygiene_violations replayed against the real content + real 84f5a3c diff returned FIND_RULE_BODY=0 (self-test 7/7 confirms the detector itself works).

## Task V2 — doctrine/verification-dispatch.md created and JIT-injecting

EVIDENCE BLOCK
==============
Task ID: V2
Task description: Create doctrine/verification-dispatch.md carrying the body: the rule, the trigger table, an explicit NOT-triggers exemption set, model-routing guidance (pass an explicit `model`; retry on opus on a spend-limit error), the say-so-explicitly clause, and the GOLDEN CASE. Verification: full (JIT injection observed firing).
Verified at: 2026-07-29T22:54:19Z
Verifier: task-verifier agent (reconciliation pass; work landed 2026-07-28 in 84f5a3c)

Oracle: specified — the plan's six required content elements, plus the plan's Testing-Strategy functional oracle: JIT injection of this file observed firing on a hooks/ edit. Injection re-executed live (sandboxed) by this verifier, not taken from the builder's claim.

Comprehension-gate: skipped — rung field missing (plan header has no `rung:`; treated as rung 0)
Operator invariants: none registered (exit 3)

Checks run:
1. File exists with all six required elements (adapters/claude-code/doctrine/verification-dispatch.md, 41 lines)
   - the rule: line 8 ("**The rule.** Dispatching a verifier or reviewer is standard process...")
   - trigger table: lines 14-20 (4-row markdown table: harness-reviewer / task-verifier / plan panel / functionality-verifier)
   - NOT-triggers exemption set: lines 22-24 (doc typos, no-artifact turns, observe-only no-ops, operator opt-out)
   - model-routing: lines 26-29 ("Pass an explicit `model` on every verifier dispatch, and on a spend-limit or availability error, retry once on `opus`")
   - say-so-explicitly clause: lines 31-33
   - GOLDEN CASE: lines 35-41 (f6562b2, T3 admission lib)
   Result: PASS
2. JIT injection observed firing (live sandboxed probe, executed by this verifier)
   Command: printf '{"session_id":"verify-after-x2","tool_name":"Edit","tool_input":{"file_path":"<worktree>/adapters/claude-code/hooks/doctrine-jit.sh"}}' | HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR=<sandbox> DOCTRINE_JIT_MANIFEST=<worktree>/adapters/claude-code/manifest.json DOCTRINE_JIT_DOCTRINE_DIR=<worktree>/adapters/claude-code/doctrine bash adapters/claude-code/hooks/doctrine-jit.sh   (repeated; one entry injects per call)
   Output: call 3 emitted hookSpecificOutput.additionalContext = "[doctrine-jit] verification-dispatch — injected once for this session (trigger: adapters/claude-code/)" followed by the V2 file's own content — injected end-to-end through the real hook + real manifest.
   Result: PASS
3. Hook self-test
   Command: bash adapters/claude-code/hooks/doctrine-jit.sh --self-test
   Output: 11 passed, 0 failed
   Result: PASS

Runtime verification: file adapters/claude-code/doctrine/verification-dispatch.md::GOLDEN CASE
Runtime verification: test adapters/claude-code/hooks/doctrine-jit.sh::--self-test
Runtime verification: test adapters/claude-code/hooks/doctrine-jit.sh::live-probe(Edit of hooks/ file, real manifest) -> injects verification-dispatch compact
Runtime verification: functionality-verifier V2::SKIP (rationale: harness-internal surface — maintainer-as-user exercise executed directly by this verifier via the sandboxed live JIT probe + 11/11 self-test; Task tool unavailable in this verification context)

DEPENDENCY TRACE
================
Step 1: maintainer edits a file under adapters/claude-code/ (Edit tool)
  v Verified at: probe payload tool_name=Edit, file_path=.../hooks/doctrine-jit.sh
Step 2: PostToolUse doctrine-jit.sh matches manifest.json entries[94].jit_triggers.paths ("adapters/claude-code/")
  v Verified at: injected header names trigger "adapters/claude-code/"
Step 3: doctrine compact delivered as additionalContext to the session
  v Verified at: probe call 3 stdout carries the file's content ("# Verification dispatch — compact")

Git evidence:
  adapters/claude-code/doctrine/verification-dispatch.md — created in 84f5a3c (2026-07-28 20:33:17 -0700), ancestor of origin/master

Verdict: PASS
Confidence: 9
Reason: PROVEN: all six required content elements present at the cited lines, and the injection path was re-executed live by this verifier — the real hook, reading the real manifest, injected this exact file on a simulated hooks/ Edit (probe call 3 output).

## Task V3 — entries[93] review-before-deploy JIT routing fixed to the governed surfaces

EVIDENCE BLOCK
==============
Task ID: V3
Task description: Fix manifest.json entries[93] (review-before-deploy) jit_triggers.paths to route to the surfaces the gate GOVERNS (hooks/, scripts/, agents/, rules/, manifest.json), not only the two files that implement its carriers. Verification: full (edit a hooks/ file, observe the doctrine inject).
Verified at: 2026-07-29T22:54:19Z
Verifier: task-verifier agent (reconciliation pass; work landed 2026-07-28 in fe78ed3)

Oracle: derived-preexisting — differential against the pre-fix manifest (git show fe78ed3~1:adapters/claude-code/manifest.json): the SAME probe command must NOT inject before the fix and MUST inject after. This is a fix task; before/after reproduction executed by this verifier.

Comprehension-gate: skipped — rung field missing (plan header has no `rung:`; treated as rung 0)
Operator invariants: none registered (exit 3)

Checks run:
1. entries[93] path list — originals preserved + governed surfaces added
   Command: jq '.entries[93].jit_triggers.paths' adapters/claude-code/manifest.json
   Output: 8 paths — the original 3 (install.sh, hooks/session-start-auto-install.sh, docs/design-notes/review-record-primitive.md) PLUS adapters/claude-code/hooks/, scripts/, agents/, rules/, manifest.json. Edge case "existing three paths must be preserved, not replaced" (plan line 79-80): satisfied.
   Result: PASS
2. fe78ed3 diff shows exactly the 5 added paths
   Command: git show fe78ed3 -- adapters/claude-code/manifest.json
   Output: +hooks/ +scripts/ +agents/ +rules/ +manifest.json appended after the preserved review-record-primitive.md line
   Result: PASS

Runtime verification (before): sandboxed JIT probe — printf '{"session_id":"verify-before-x2","tool_name":"Edit","tool_input":{"file_path":"<worktree>/adapters/claude-code/hooks/doctrine-jit.sh"}}' | HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR=<sandbox> DOCTRINE_JIT_MANIFEST=<manifest at fe78ed3~1> bash adapters/claude-code/hooks/doctrine-jit.sh (repeated to exhaustion)
  Commit: fe78ed3~1 (manifest extracted via git show fe78ed3~1:adapters/claude-code/manifest.json)
  Expected: FAIL — review-before-deploy must NOT inject on a hooks/ edit (old 3-path list has no hooks/ prefix)
  Observed: call 1 injected only harness-hygiene-scan; calls 2-3 emitted NOTHING. review-before-deploy never fired; verification-dispatch entry count in that manifest = 0.

Runtime verification (after): the SAME probe command with DOCTRINE_JIT_MANIFEST=<current worktree manifest>, fresh session id
  Commit: fe78ed3 (current worktree state, ancestor of origin/master)
  Expected: PASS — review-before-deploy injects on the hooks/ edit
  Observed: call 2 emitted "[doctrine-jit] review-before-deploy — injected once for this session (trigger: adapters/claude-code/hooks/)" — the trigger string IS one of the 5 paths V3 added.

Runtime verification: test adapters/claude-code/hooks/doctrine-jit.sh::--self-test
Runtime verification: functionality-verifier V3::SKIP (rationale: harness-internal surface — maintainer-as-user exercise executed directly by this verifier via the before/after sandboxed probe; Task tool unavailable in this verification context)

DEPENDENCY TRACE
================
Step 1: maintainer edits a file under adapters/claude-code/hooks/
  v Verified at: probe payload tool_name=Edit, file_path=.../hooks/doctrine-jit.sh
Step 2: doctrine-jit.sh matches entries[93].jit_triggers.paths "adapters/claude-code/hooks/" (added by fe78ed3; absent at fe78ed3~1)
  v Verified at: injected header names that exact trigger; before-run with fe78ed3~1 manifest produced no fire
Step 3: review-before-deploy compact delivered as additionalContext
  v Verified at: probe output "# Review-before-deploy — compact ... install.sh hard-blocks an uncovered change"

Git evidence:
  adapters/claude-code/manifest.json — modified in fe78ed3 (2026-07-28 20:32:55 -0700), ancestor of origin/master

Verdict: PASS
Confidence: 9
Reason: PROVEN: same-command differential — with the fe78ed3~1 manifest the hooks/-edit probe never injects review-before-deploy; with the current manifest it injects on trigger "adapters/claude-code/hooks/". The fix is distinguishable from a no-op and the original 3 paths are preserved.

## Task V4 — verification-dispatch manifest entry, honestly labelled PATTERN

EVIDENCE BLOCK
==============
Task ID: V4
Task description: Add the verification-dispatch manifest entry, honestly labelled PATTERN with the missing commit-time mechanism named. Verification: mechanical (manifest-check.sh).
Verified at: 2026-07-29T22:54:19Z
Verifier: task-verifier agent (reconciliation pass; work landed 2026-07-28 in fe78ed3)

Oracle: mechanical — manifest-check.sh, scoped per the plan's Testing Strategy ("manifest-check.sh green for the NEW AND AMENDED entries"), plus the plan's honesty requirements checked against the entry's literal fields.

Comprehension-gate: skipped — rung field missing (plan header has no `rung:`; treated as rung 0)
Operator invariants: none registered (exit 3)

Checks run:
1. Entry exists and is honestly labelled
   Command: jq '.entries[94]' adapters/claude-code/manifest.json
   Output: id "verification-dispatch", kind "pattern", blocking false, doctrine_file "doctrine/verification-dispatch.md". honest_status opens "PATTERN, memory-rung, NOT A MECHANISM" and names the missing commit-time carrier (PreToolUse gate sourcing rrg_in_surface/rrg_is_covered, write-review-record.sh unwired). retirement_condition names the same carrier gate as the retirement trigger. golden_scenario carries f6562b2.
   Result: PASS
2. manifest-check.sh — green for the new and amended entries
   Command: bash adapters/claude-code/scripts/manifest-check.sh
   Output: "FAILED — 2 red, 0 warn (136 entries)". Both REDs are estate-janitor / estate-brief (hook path shape '../scripts/*.sh'), NEITHER concerns entries[93] review-before-deploy nor entries[94] verification-dispatch.
   Result: PASS (scoped per plan Testing Strategy) — see check 3 for why the 2 REDs do not belong to this plan.
3. Differential: the 2 REDs pre-date this plan's commits
   Command: MANIFEST_CHECK_MANIFEST=<manifest at fe78ed3~1> bash adapters/claude-code/scripts/manifest-check.sh
   Output: identical 2 REDs (estate-janitor, estate-brief) at 135 entries. The RED-causing hook paths were introduced by db1449c (accountable-estate T1), an ancestor of fe78ed3~1. This plan's +1 entry and amended entries[93] introduced ZERO new red/warn.
   Result: PASS
4. DISCREPANCY NOTE (caller expected 3 pre-existing REDs incl. harness-claim-lint): not reproduced. Both the fe78ed3~1 manifest and the current manifest show exactly 2 REDs; no harness-claim-lint entry or file exists in this tree. Observed evidence stands at 2 pre-existing REDs.

Runtime verification: test adapters/claude-code/scripts/manifest-check.sh::check (2 red, both pre-existing estate-* entries; zero findings on entries 93/94; differential vs fe78ed3~1 manifest identical)
Runtime verification: file adapters/claude-code/manifest.json::"id": "verification-dispatch"

Git evidence:
  adapters/claude-code/manifest.json — entries[94] added in fe78ed3 (2026-07-28 20:32:55 -0700), ancestor of origin/master

Verdict: PASS
Confidence: 8
Reason: PROVEN: the entry exists with kind:pattern/blocking:false and the missing commit-time mechanism named in honest_status AND retirement_condition; manifest-check replayed on both the pre-fix and current manifests shows the identical 2 pre-existing estate-* REDs and zero findings attributable to this plan's new/amended entries — the plan's stated bar ("green for the new and amended entries") is met. Caveat honestly recorded: the overall run is FAILED on pre-existing debt owned by the accountable-estate plan (db1449c).

## Task V5 — two review-surface-gap nl-issues filed

EVIDENCE BLOCK
==============
Task ID: V5
Task description: File the two review-surface gaps harness-reviewer surfaced as nl-issues: rrg_in_surface returns OUT for CLAUDE.md and doctrine/*.md (the highest-leverage behavior files are outside the review surface), and the Fable-exhaustion event. Verification: mechanical (rows in the ledger).
Verified at: 2026-07-29T22:54:19Z
Verifier: task-verifier agent (reconciliation pass)

Oracle: mechanical — rows exist in the machine-wide ledger ~/.claude/state/nl-issues.jsonl (the plan's stated bar). The ledger is not in git; row content and timestamps are the evidence.

Comprehension-gate: skipped — rung field missing (plan header has no `rung:`; treated as rung 0)
Operator invariants: none registered (exit 3)

Checks run:
1. Both rows exist and carry the required substance
   Command: grep -in "rrg_in_surface\|fable" ~/.claude/state/nl-issues.jsonl
   Output: line 7 — ts 2026-07-29T03:32:30Z, "rrg_in_surface returns OUT for adapters/claude-code/CLAUDE.md and doctrine/*.md, so the always-loaded operating text and every doctrine compact can be edited and deployed with ZERO review record"; line 8 — same ts, "BOTH task-verifier and harness-reviewer dispatches died instantly on 'You have hit your monthly spend limit ... Fable 5' until manually overridden to opus ... silently converts every verification into a skipped verification". Both project=neural-lace, count=1, untriaged.
   Result: PASS
2. Timestamp plausibility
   Output: 2026-07-29T03:32:30Z = 2026-07-28 20:32:30 PT — inside the same minute as fe78ed3 (20:32:55 PT), consistent with the rows being filed during the landing session.
   Result: PASS

Runtime verification: file ~/.claude/state/nl-issues.jsonl::rrg_in_surface returns OUT for adapters/claude-code/CLAUDE.md
Runtime verification: file ~/.claude/state/nl-issues.jsonl::monthly spend limit

Git evidence:
  Not applicable — ~/.claude/state/nl-issues.jsonl is a machine-wide ledger outside version control (plan's Verification line explicitly scopes the bar to "rows in the ledger").

Verdict: PASS
Confidence: 8
Reason: PROVEN: both required rows exist in the ledger with the exact substance the task names (grep output lines 7-8), timestamped inside the landing-commit minute. Confidence capped at 8 because ledger rows are not git-attested; the plan's own mechanical bar (rows exist) is fully met.
