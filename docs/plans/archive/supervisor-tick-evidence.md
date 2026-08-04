# Evidence Log — Supervisor tick — the operators never-stall mechanism

## Task 1 — Build supervisor-tick.sh, extend install-coord-sync-task.ps1, add the manifest entry

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Build supervisor-tick.sh, extend install-coord-sync-task.ps1, and add the manifest entry -- Verification: full -- Docs impact: none -- the script own header doc is the runbook; no separate README/runbook file exists for scheduled-tick scripts in this codebase (health-tick.sh / coord-sync.sh set the precedent of header-doc-as-runbook).
Verified at: 2026-07-21T03:46:22Z
Verifier: task-verifier agent (second invocation -- comprehension-gate precondition re-check + fresh re-verification)

Oracle: specified (this plan own User-facing Outcome + Closure Contract) combined with implicit/pseudo (self-test exercising the real, unmodified worktree-hygiene-sweep.sh detector against real fixture worktrees) -- per constitution paragraph 4 harness-internal carve-out (for harness work the maintainer is the user: the self-test passing and the doctor staying green IS the demonstration), corroborated by this plan own acceptance-exempt-reason.

Comprehension-gate: PASS (confidence 9) -- comprehension-reviewer second pass (following commit 2651f59 citation fixes) returned verdict PASS with all stages (1, 2, 3a-3e) PASS and all 13 file:line citations independently re-derived and confirmed grounded. task-verifier independently spot-checked all 13 citations against the on-disk files in this session and confirms every one resolves exactly as claimed:
  - supervisor-tick.sh:380-389 (realert-window gate) -- CONFIRMED verbatim
  - supervisor-tick.sh:385-386 (now_epoch minus last_alerted_epoch >= realert_after -> should_alert=1) -- CONFIRMED verbatim
  - supervisor-tick.sh:361 (tag == ORPHANED-HOLDS-CONTENT filter, else continue) -- CONFIRMED verbatim
  - supervisor-tick.sh:313-319 (detector-missing graceful WARN) -- CONFIRMED verbatim
  - supervisor-tick.sh:228-236 (_st_run timeout-wrap) -- CONFIRMED verbatim
  - supervisor-tick.sh:325,345,409 (remaining = budget minus SECONDS occurrences) -- CONFIRMED, exact line numbers match
  - supervisor-tick.sh:330-334 (SWEEP_TIMEOUT alert on rc=124) -- CONFIRMED verbatim
  - supervisor-tick.sh:243-262 (_st_resolve_repos, line-by-line array read) -- CONFIRMED verbatim
  - supervisor-tick.sh:327 (ST_REPOS array expansion in the sweep invocation) -- CONFIRMED verbatim
  - supervisor-tick.sh:421-429 (ledger reconcile/prune loop) -- CONFIRMED verbatim
  - install-coord-sync-task.ps1:212-222 (Write-Warning + continue for missing per-task script) -- CONFIRMED verbatim
  Also confirmed: commit a44a6c6 added the four required Comprehension Articulation sub-sections (Spec meaning / Edge cases covered / Edge cases NOT covered / Assumptions), each substantive (well over the 30 non-ws-char floor); commit 2651f59 is docs-only (docs/plans/supervisor-tick.md, 22 lines changed) and fixed exactly the two mis-citations the reviewer first pass flagged, per its own commit message. Neither docs commit touched supervisor-tick.sh, install-coord-sync-task.ps1, or manifest.json (confirmed via git log --oneline for each file: all three show only cebc26f).

Checks run:
1. Git history confirms code files unchanged since first task-verifier pass
   Command: git log --oneline -- adapters/claude-code/scripts/supervisor-tick.sh adapters/claude-code/scripts/install-coord-sync-task.ps1 adapters/claude-code/manifest.json
   Output: cebc26f (only) for all three files
   Result: PASS

2. Self-test -- 4 fixture-driven scenarios / 16 assertions against the real, unmodified worktree-hygiene-sweep.sh
   Command: bash adapters/claude-code/scripts/supervisor-tick.sh --self-test
   Output: self-test summary: 16 passed, 0 failed (Scenario 1 alert-fires, Scenario 1b idempotent-refire, Scenario 2 live-owned-silent, Scenario 3 detector-missing-graceful, Scenario 4 TTL-realert)
   Result: PASS

3. Manifest validity + schema conformance
   Command: jq empty adapters/claude-code/manifest.json ; bash adapters/claude-code/scripts/manifest-check.sh
   Output: valid JSON; manifest-check GREEN -- 130 entries, 110 hooks covered, 0 warn
   Result: PASS

4. Manifest entry for supervisor-tick actually present (not just aggregate GREEN)
   Command: grep -n supervisor-tick adapters/claude-code/manifest.json
   Output: line 2206 id: supervisor-tick, with golden_scenario and fp_expectation fields populated
   Result: PASS

5. PowerShell AST parse validity
   Command: powershell AST Parser.ParseFile against install-coord-sync-task.ps1
   Output: PARSE_OK: 0 errors
   Result: PASS

6. -WhatIf dry run registers both scheduled tasks, touches neither disk nor Task Scheduler
   Command: powershell -File install-coord-sync-task.ps1 -RepoPath <this worktree> -WhatIf
   Output: both NL-CoordSync and NL-SupervisorTick sections printed with What if: Performing the operation ... Register scheduled task for each; Both tasks registered from ONE run; no real Task Scheduler mutation (all lines prefixed What if / -WhatIf)
   Result: PASS

7. Comprehension Articulation citation spot-check (13 citations)
   Command: sed -n against each cited line range in supervisor-tick.sh and install-coord-sync-task.ps1
   Output: all 13 citations resolve to the exact code described (see Comprehension-gate section above)
   Result: PASS

Runtime verification: file adapters/claude-code/scripts/supervisor-tick.sh::--self-test (bash adapters/claude-code/scripts/supervisor-tick.sh --self-test -> self-test summary: 16 passed, 0 failed)
Runtime verification: file adapters/claude-code/manifest.json::id-supervisor-tick (jq empty adapters/claude-code/manifest.json ; bash adapters/claude-code/scripts/manifest-check.sh -> manifest-check GREEN -- 130 entries, 110 hooks covered, 0 warn)
Runtime verification: file adapters/claude-code/scripts/install-coord-sync-task.ps1::Write-Warning (powershell AST ParseFile -> PARSE_OK: 0 errors; -WhatIf -RepoPath <worktree> -> both NL-CoordSync and NL-SupervisorTick registered, Task Scheduler untouched)
Runtime verification: functionality-verifier supervisor-tick-task1::SKIP (rationale: no Task-tool/sub-agent access available in this task-verifier invocation; the plan own specified oracle for this harness-internal, acceptance-exempt mechanism is --self-test per constitution paragraph 4 harness carve-out, and that self-test was independently re-executed live in this session against the real unmodified detector with the documented 16/16 outcome)

DEPENDENCY TRACE
================
Step 1: Scheduled OS task (NL-SupervisorTick, registered by install-coord-sync-task.ps1) fires supervisor-tick.sh on a timer with no session open
  Verified at: install-coord-sync-task.ps1 -WhatIf output, the NL-SupervisorTick block registering the scheduled task with RepetitionInterval 300 seconds, Action pointing at supervisor-tick.sh
Step 2: supervisor-tick.sh run_tick invokes worktree-hygiene-sweep.sh --stranded --porcelain (the pre-existing, already-deployed orphan detector) and classifies rows, filtering to ORPHANED-HOLDS-CONTENT only
  Verified at: supervisor-tick.sh:327 (sweep invocation), supervisor-tick.sh:361 (tag filter) -- both exercised live by --self-test Scenario 1 (orphan detected) and Scenario 2 (live-owned worktree correctly excluded)
Step 3: A detected orphan writes a NEEDS-YOU.md entry (via needs-you.sh add --section question) AND an external-monitor-alerts JSON file, gated idempotent by a per-orphan ledger keyed on cksum(path,branch)
  Verified at: supervisor-tick.sh needs-you.sh invocation near line 345-350, supervisor-tick.sh:380-389 (realert-window ledger gate) -- exercised live by --self-test Scenario 1 (first fire: NEEDS-YOU.md entry + 1 alert file + 1 ledger record) and Scenario 1b (immediate refire: zero duplicates)
Step 4: Operator observes the NEEDS-YOU.md entry without having to open a session or run harness-doctor.sh by hand
  Verified at: this is the plan own specified User-facing Outcome; the self-test Scenario 1 assertion (NEEDS-YOU.md carries an entry naming the orphaned worktree) is the mechanical proxy for this step per the plan own acceptance-exempt-reason (self-test IS the demonstration for this harness-internal mechanism)

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/scripts/supervisor-tick.sh           (last commit: cebc26f, 2026-07-20)
    - adapters/claude-code/scripts/install-coord-sync-task.ps1  (last commit: cebc26f, 2026-07-20)
    - adapters/claude-code/manifest.json                        (last commit: cebc26f, 2026-07-20)
    - docs/plans/supervisor-tick.md                             (last commits: 2651f59, a44a6c6 -- docs-only, Comprehension Articulation)

Verdict: PASS
Confidence: 9
Reason: PROVEN: all four Closure Contract commands were independently re-executed live in this session (self-test 16/16; jq+manifest-check GREEN 130 entries/110 hooks/0 warn; PowerShell AST parse 0 errors; -WhatIf registers both NL-CoordSync and NL-SupervisorTick with zero disk/Task-Scheduler mutation) and match the documented expected outputs exactly. The manifest supervisor-tick entry was independently confirmed present (not inferred from aggregate GREEN alone). The rung:4 comprehension-gate precondition is now satisfied: the required four-sub-section Comprehension Articulation block exists (added a44a6c6, corrected 2651f59) and all 13 of its file:line citations were independently re-derived by task-verifier against the on-disk files in this session and found to resolve exactly as claimed -- not merely accepted on the builder or reviewer say-so. Git history confirms the three code files (supervisor-tick.sh, install-coord-sync-task.ps1, manifest.json) are unchanged since cebc26f, the same commit verified PASS on the first task-verifier pass, so the prior substantive functionality verification remains valid. The one gap (functionality-verifier sub-agent invocation) is a tool-availability constraint of this invocation, not a skipped check; it is bridged by direct, fresh, live re-execution of the plan own specified oracle (--self-test against the real unmodified detector) rather than a delegated re-statement of it.
