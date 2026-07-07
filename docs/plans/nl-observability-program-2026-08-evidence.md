# Evidence Log — NL Observability Program — derived-truth cockpit + six-questions estate visibility

## Task O.5 — Push (ntfy.sh) — terminal disposition: DESCOPED by operator

EVIDENCE BLOCK
==============
Task ID: O.5
Task description: Push (ntfy.sh): exactly three rules — NEEDS-YOU created, session stalled/throttled >N min, doctor RED; registration + drill — Model: sonnet. TERMINAL DISPOSITION: descoped by operator 2026-07-07; original Done-when (phone drill) superseded, not satisfiable by directive.
Verified at: 2026-07-07T09:15:00Z
Verifier: task-verifier agent

Oracle: specified — the operator's explicit descope directive 2026-07-07 ("no interest in ntfy... don't need observability from my phone"); the verification bar for a user-descoped task is the completeness and mechanical truth of the terminal-disposition record, not the superseded Done-when.

Comprehension-gate: not applicable (rung: 1)

Checks run:
1. Plan O.5 block carries the DESCOPED disposition naming directive + date
   Command: git show c767ddd -- docs/plans/nl-observability-program-2026-08.md
   Output: +9 lines: 'DESCOPED by operator 2026-07-07 ("no interest in ntfy... don't need observability from my phone" ...) ... task closes as descoped-by-operator' — landed on master via PR #89 squash c767dddda41053b304e13c92ef00852eb7d58761 (origin/master). Same block applied verbatim to the main-checkout working copy in this verification (local master at d141119 is behind origin; ff blocked by another session's uncommitted docs/backlog.md — identical-content lines merge clean at next pull).
   Result: PASS
2. Build evidence real: origin branch + SHA
   Command: git ls-remote origin refs/heads/build/wave-o-o5
   Output: d8741b0b2c3bafa26feeb93bce5b75ef7908fc1e refs/heads/build/wave-o-o5 (tip commit: "build(wave-o-o5): ntfy.sh push — send/scan verbs + guarded needs-you call")
   Result: PASS
3. Self-test covers topic-absent no-op and unknown-class rejection — EXECUTED, not just read
   Command: git show d8741b0:adapters/claude-code/scripts/ntfy-push.sh > "$SCRATCH/ntfy-push.sh" && bash "$SCRATCH/ntfy-push.sh" --self-test
   Output: RESULT: 18 passed, 0 failed (exit 0). T1/T1b: topic-absent send exits 0, no network attempt recorded (mocked curl recorder log empty); T2/T2b: unknown --class rejected exit 1, no network attempt; T6: unknown class rejected even with topic present; T13/T13b: topic-absent scan does not burn pending item ids. Matches the disposition's "18/18 incl. the negative" claim exactly. NOTE: first replay showed 17/18 — T12 (flagless self-reinvocation via $_NTFY_SELF_DIR/ntfy-push.sh) failed exit 127 because the verifier extracted the file under a non-canonical name; re-extraction as ntfy-push.sh → 18/18. Replay artifact, not a script defect. Script path on the branch is adapters/claude-code/scripts/ntfy-push.sh (repo-canonical), not scripts/ntfy-push.sh as the invocation claimed — noted, not verdict-affecting.
   Result: PASS
4. Dormancy mechanically true on this machine
   Command: ls -la "$HOME/.claude/local/ntfy-topic"
   Output: No such file or directory (exit 2). Additionally: script absent from origin/master tree (git ls-tree origin/master adapters/claude-code/scripts/ntfy-push.sh → empty) and absent from installed ~/.claude/scripts/ — the push surface cannot fire at all; by the self-tested topic-absent contract it would be a silent no-op even if installed.
   Result: PASS
5. specs-o §O.5 DESCOPED banner on master
   Command: git show c767ddd -- docs/plans/nl-observability-program-2026-08-specs-o.md
   Output: +5 lines under '## §O.5 Push (ntfy.sh) — exactly three rules': '> **DESCOPED by operator 2026-07-07** ... spec text below retained for the record.' — on origin/master via c767ddd; local checkout receives it at next pull.
   Result: PASS

Runtime verification: file docs/plans/nl-observability-program-2026-08.md::DESCOPED by operator 2026-07-07
Runtime verification: test adapters/claude-code/scripts/ntfy-push.sh@d8741b0::--self-test (18/18 PASS; replay: git show d8741b0:adapters/claude-code/scripts/ntfy-push.sh > /tmp/ntfy-push.sh && bash /tmp/ntfy-push.sh --self-test)

DEPENDENCY TRACE (descope record chain)
================
Step 1: Operator directive 2026-07-07 — no phone observability
  ↓ Recorded at: plan O.5 DESCOPED block (c767ddd, PR #89) + specs-o §O.5 banner
Step 2: Built artifact disposed dormant-by-design
  ↓ Verified at: build/wave-o-o5 @ d8741b0, adapters/claude-code/scripts/ntfy-push.sh --self-test 18/18 (T1/T1b topic-absent no-op; T2/T2b+T6 unknown-class negative)
Step 3: Dormancy precondition on this machine
  ↓ Verified at: ~/.claude/local/ntfy-topic ENOENT; script not on master, not installed
Step 4: Consumer-map law 2 disposition
  ↓ Recorded at: plan DESCOPED block — push:* consumers removed at batch-2 integration; three classes keep digest/cockpit/cli consumers

Git evidence:
  origin/master: c767dddda41053b304e13c92ef00852eb7d58761 "ops(wave-o): O.5 operator descope ..." (#89, 2026-07-06 21:57 -0700) — plan +9, specs-o +5
  build branch: refs/heads/build/wave-o-o5 @ d8741b0b2c3bafa26feeb93bce5b75ef7908fc1e

Verdict: PASS
Confidence: 9
Reason: PROVEN: closure basis is descoped-by-operator, not built-to-Done-when. The terminal-disposition record is complete (directive quoted + dated in plan and specs on master via c767ddd), and every mechanical claim in it was independently replayed: branch SHA matches ls-remote; the cited 18/18 self-test was re-executed from the exact ref and passed 18/18 including both negatives; the dormancy precondition (~/.claude/local/ntfy-topic absent) holds on this machine. Original Done-when (phone drill) is superseded by the same directive and does not gate closure.
