# Evidence Log — Conv Tree Dispatch-Reader Hook

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Build conversation-tree-read.sh (reader hook + >=15-scenario --self-test) — Verification: mechanical
Verified at: 2026-05-18T16:57:32Z
Verifier: task-verifier agent (Verification: mechanical)

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Reader self-test
   Command: bash adapters/claude-code/hooks/conversation-tree-read.sh --self-test
   Output: self-test: 37 passed, 0 failed / self-test: OK / EXIT=0
   Result: PASS (>=15 scenarios required; 37 observed)
2. Hook structure inspection
   Output: UserPromptSubmit reader; frozen A2 readState facade; actor==gui filter; RESPONSE_TYPES allowlist; emits hookSpecificOutput/UserPromptSubmit/additionalContext JSON; all runtime paths exit 0
   Result: PASS
3. Git evidence: adapters/claude-code/hooks/conversation-tree-read.sh 588 lines committed in HEAD e383a2e — PASS

Runtime verification: test adapters/claude-code/hooks/conversation-tree-read.sh::--self-test (37 passed, 0 failed, self-test: OK, exit 0)
Runtime verification: file adapters/claude-code/hooks/conversation-tree-read.sh::hookEventName.*UserPromptSubmit

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/hooks/conversation-tree-read.sh  (last commit: e383a2e, 2026-05-18)

Verdict: PASS
Confidence: 9
Reason: reader hook exists, committed in HEAD, self-test passes 37/37 (>=15 required), structure matches UserPromptSubmit-reader / A2-facade / actor-gui-filter / exit-0 contract.

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Scripted end-to-end via self-test R16/R17/R18 — Verification: mechanical
Verified at: 2026-05-18T16:57:32Z
Verifier: task-verifier agent (Verification: mechanical)

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. End-to-end self-test scenarios R16/R17/R18
   Command: bash adapters/claude-code/hooks/conversation-tree-read.sh --self-test | grep -E R16 R17 R18
   Output:
     PASS: R16 e2e stdout is valid JSON, hookEventName==UserPromptSubmit
     PASS: R16 e2e additionalContext carries the operator response
     PASS: R17 stdout is exactly one valid JSON object
     PASS: R18 e2e re-fire is idempotent no-op
   Result: PASS

Runtime verification: test adapters/claude-code/hooks/conversation-tree-read.sh::R16-R17-R18 (facade appends GUI answered+response, hook fires with synthetic UserPromptSubmit stdin, valid JSON, hookEventName==UserPromptSubmit, additionalContext carries response, idempotent re-fire empty)

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/hooks/conversation-tree-read.sh  (last commit: e383a2e, 2026-05-18)

Verdict: PASS
Confidence: 9
Reason: the walking-skeleton end-to-end slice is self-test scenarios R16/R17/R18; all three PASS — valid JSON output, hookEventName==UserPromptSubmit, additionalContext contains the operator response, idempotent re-fire.

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Register the hook in live settings.json UserPromptSubmit chain + mirror into settings.json.template — Verification: mechanical
Verified at: 2026-05-18T16:57:32Z
Verifier: task-verifier agent (Verification: mechanical)

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Template registration + JSON validity
   Output: TEMPLATE valid JSON; last UserPromptSubmit hook = bash ~/.claude/hooks/conversation-tree-read.sh — PASS
2. Live settings registration + JSON validity
   Output: LIVE valid JSON; last UserPromptSubmit hook = bash ~/.claude/hooks/conversation-tree-read.sh — PASS

Runtime verification: file adapters/claude-code/settings.json.template::conversation-tree-read.sh
Runtime verification: file ~/.claude/settings.json::conversation-tree-read.sh

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/settings.json.template  (last commit: e383a2e, 2026-05-18; +4 lines)

Verdict: PASS
Confidence: 9
Reason: reader is the LAST hook in the UserPromptSubmit chain in BOTH the committed template and the live settings; both files are valid JSON.

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Dual-mirror sync: live conversation-tree-read.sh byte-identical to canonical — Verification: mechanical
Verified at: 2026-05-18T16:57:32Z
Verifier: task-verifier agent (Verification: mechanical)

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Byte-identical mirror
   Command: diff -q adapters/claude-code/hooks/conversation-tree-read.sh ~/.claude/hooks/conversation-tree-read.sh
   Output: no output, exit 0 — byte-identical
   Result: PASS
2. Live mirror self-test: bash ~/.claude/hooks/conversation-tree-read.sh --self-test | tail -1 -> self-test: OK — PASS

Runtime verification: command diff -q adapters/claude-code/hooks/conversation-tree-read.sh ~/.claude/hooks/conversation-tree-read.sh
Runtime verification: test ~/.claude/hooks/conversation-tree-read.sh::--self-test (self-test: OK)

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/hooks/conversation-tree-read.sh  (last commit: e383a2e, 2026-05-18)

Verdict: PASS
Confidence: 9
Reason: canonical and live-mirror copies are byte-identical (diff -q exit 0); the live mirror self-test passes.

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Architecture doc conv-tree-dispatch-reader.md + one-line row in harness-architecture.md — Verification: mechanical
Verified at: 2026-05-18T16:57:32Z
Verifier: task-verifier agent (Verification: mechanical)

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Architecture doc exists + substantive
   Output: docs/conv-tree-dispatch-reader.md 179 lines; headings What this closes / Mechanism / Output contract / What gets surfaced / Per-session cursor / Read path / mtime fast-path / Performance / Verification / Out of scope / Cross-references
   Result: PASS (substantive — full reader architecture)
2. Harness-architecture inventory row
   Output: line 700 Claude-side reader row referencing adapters/claude-code/hooks/conversation-tree-read.sh (full inventory row)
   Result: PASS

Note: live mirror ~/.claude/docs/harness-architecture.md is pre-existingly stale (HARNESS-GAP-14 settings-divergence drift, missing ALL conv-tree content from master) — explicitly out of scope per the plan In-flight scope updates (2026-05-18 entry). The canonical repo doc docs/harness-architecture.md is the source of truth and is updated. Not a Task 5 failure.

Runtime verification: file docs/conv-tree-dispatch-reader.md::Mechanism
Runtime verification: file docs/harness-architecture.md::conversation-tree-read.sh

Git evidence:
  Files modified in recent history:
    - docs/conv-tree-dispatch-reader.md  (last commit: e383a2e, 2026-05-18; +179 lines, NEW)
    - docs/harness-architecture.md  (last commit: e383a2e, 2026-05-18; +1 line)

Verdict: PASS
Confidence: 9
Reason: architecture doc exists with substantive 179-line reader architecture; canonical harness-architecture.md has the Claude-side-reader inventory row; the stale live mirror is documented as out-of-scope drift in the plan in-flight scope updates, not a defect of this task.

EVIDENCE BLOCK
==============
Task ID: 6
Task description: Regression: emit hook 17/17; state-gate + stop-gate self-tests still green — Verification: mechanical
Verified at: 2026-05-18T16:57:32Z
Verifier: task-verifier agent (Verification: mechanical)

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Emit hook regression: bash adapters/claude-code/hooks/conversation-tree-emit.sh --self-test | tail -2 -> self-test: 17 passed, 0 failed / self-test: OK — PASS
2. State-gate regression: bash adapters/claude-code/hooks/conversation-tree-state-gate.sh --self-test | tail -1 -> 18 passed, 0 failed — PASS
3. Stop-gate regression: bash adapters/claude-code/hooks/conversation-tree-stop-gate.sh --self-test | tail -1 -> 8 passed, 0 failed — PASS

Runtime verification: test adapters/claude-code/hooks/conversation-tree-emit.sh::--self-test (17 passed, 0 failed, self-test: OK)
Runtime verification: test adapters/claude-code/hooks/conversation-tree-state-gate.sh::--self-test (18 passed, 0 failed)
Runtime verification: test adapters/claude-code/hooks/conversation-tree-stop-gate.sh::--self-test (8 passed, 0 failed)

Git evidence:
  No regressions: sibling hooks unchanged by e383a2e; all self-tests green post-change.

Verdict: PASS
Confidence: 9
Reason: the new reader hook introduced zero regressions — emit hook 17/17, state-gate 18/18, stop-gate 8/8 all green.


---

EVIDENCE BLOCK
==============
Task ID: 7
Task description: One PR to neural-lace master, drive to merge, sync the ~/claude-projects/neural-lace main checkout — Verification: mechanical
Verified at: 2026-05-18T17:30:00Z
Verifier: task-verifier agent (Verification: mechanical)

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. PR #6 merge state
   Command: gh pr view 6 --json state,mergedAt -q '{s:.state,m:.mergedAt}'
   Output: {"m":"2026-05-18T17:11:19Z","s":"MERGED"}
   Result: PASS — state == MERGED, mergedAt non-null

2. Merged artifacts present on origin/master
   Command: cd ~/claude-projects/neural-lace && git fetch origin master -q && git show origin/master:adapters/claude-code/hooks/conversation-tree-read.sh | head -1; git show origin/master:docs/conv-tree-dispatch-reader.md | head -1; git log origin/master --oneline -1
   Output: read.sh first line = "#!/bin/bash"; doc H1 = "# Conversation-Tree Dispatch Reader — Closing the GUI Loop"; origin/master HEAD line included "Merge pull request #6 from <owner>/claude/agitated-thompson-84c93e" (481de18, in history)
   Result: PASS — hook + doc shipped to master; PR #6 merge commit 481de18 confirmed in origin/master history

3. Reader hook registered in settings template on master
   Command: cd ~/claude-projects/neural-lace && git show origin/master:adapters/claude-code/settings.json.template | jq -e '.hooks.UserPromptSubmit[0].hooks[-1].command'
   Output: "bash ~/.claude/hooks/conversation-tree-read.sh"
   Result: PASS — reader is the last UserPromptSubmit hook in the merged template

4. Main checkout synced to current origin/master, PR #6 deliverable present
   Command: cd ~/claude-projects/neural-lace && git rev-parse --abbrev-ref HEAD; git log --oneline -1; git rev-list --left-right --count HEAD...origin/master; git merge-base --is-ancestor 481de18 HEAD
   Output: branch=fix/conv-tree-launcher-node-resolution (tip byte-identical to master — `git rev-list --left-right --count HEAD...origin/master` == "0 0"); HEAD=12cddc2 (PR #7 merge, unrelated v1.1 launcher work); 481de18 (PR #6) IS an ancestor of local HEAD; local HEAD == origin/master EXACTLY (0 ahead, 0 behind)
   Result: PASS — main checkout fully synced to current origin/master (0/0 divergence); PR #6's merge commit is present in the synced tree. Branch-name = fix/conv-tree-launcher-node-resolution and HEAD = PR #7 merge are the DOCUMENTED out-of-scope condition (v1.1 GUI/launcher session's independent work advanced master past PR #6); the substantive Task-7 requirement "PR merged + main checkout on synced master" is satisfied. stash@{0} "On master: auto-pre-pull-20260518T171142Z" confirms the git-discipline.md Rule 2 post-merge sync ran and preserved the operator's pre-existing launch-gui.ps1 edits (surfaced, not auto-resolved — explicitly out of scope per caller note).

Git evidence:
  - PR #6 merged 2026-05-18T17:11:19Z; merge commit 481de18 ("Merge pull request #6 from <owner>/claude/agitated-thompson-84c93e")
  - origin/master HEAD = 12cddc2 (PR #7, unrelated); 481de18 is an ancestor (git merge-base --is-ancestor 481de18 HEAD == true)
  - Main checkout ~/claude-projects/neural-lace synced: HEAD == origin/master, divergence 0/0
  - Post-merge sync evidenced by stash@{0}: On master: auto-pre-pull-20260518T171142Z (operator's launch-gui.ps1 edits preserved)

Verdict: PASS
Confidence: 9
Reason: PR #6 MERGED with non-null mergedAt; reader hook + architecture doc + settings-template registration all present on origin/master; main checkout fully synced to current origin/master (0/0 divergence) with PR #6's merge commit as an ancestor; the branch-name detail and PR #7 advance are the caller-documented out-of-scope v1.1 condition, not a Task-7 failure.
