# Evidence Log — Phase 1d-F Definition-on-first-use enforcement

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Decision 023 + rule documentation. Land Decision 023 (acronym regex; stopword allowlist; scope-prefix; failure message format). Create adapters/claude-code/rules/definition-on-first-use.md documenting when the gate fires and how authors should respond. Update docs/DECISIONS.md. Single commit.
Verified at: 2026-05-05T02:05:43Z
Verifier: task-verifier agent

Checks run:
1. Decision 023 file exists with required sections
   Command: ls -la docs/decisions/023-definition-on-first-use-enforcement.md && grep -E '^## (Context|Decision|Alternatives considered|Consequences|Cross-references)' docs/decisions/023-definition-on-first-use-enforcement.md
   Output: file exists (9058 bytes); 5 required sections found (Context line 9; Decision line 19; Alternatives considered line 88; Consequences line 98; Cross-references line 122). Five sub-decisions 023a-023e present (lines 23, 27, 43, 47, 61).
   Result: PASS

2. Rule file exists with substance
   Command: ls -la adapters/claude-code/rules/definition-on-first-use.md (9694 bytes), wc -l (~150+ lines)
   Output: file exists with classification block, "Why this rule exists", "When the gate fires", "What authors should do" sections.
   Result: PASS

3. DECISIONS.md row 023 added
   Command: grep -n "023" docs/DECISIONS.md
   Output: line 33 — "| 023 | [Definition-on-first-use enforcement: ...](decisions/023-definition-on-first-use-enforcement.md) | 2026-05-04 | Active |"
   Result: PASS

4. Rule synced to ~/.claude/rules/
   Command: diff -q adapters/claude-code/rules/definition-on-first-use.md ~/.claude/rules/definition-on-first-use.md
   Output: files are identical
   Result: PASS

Git evidence:
  Files modified in commit 7f24907 (2026-05-04 18:59:18 -0700):
    - adapters/claude-code/rules/definition-on-first-use.md (NEW, 161 lines)
    - docs/DECISIONS.md (1 row added)
    - docs/decisions/023-definition-on-first-use-enforcement.md (NEW, 129 lines)

Runtime verification: file <repo>/docs/decisions/023-definition-on-first-use-enforcement.md::^## Decision$
Runtime verification: file <repo>/adapters/claude-code/rules/definition-on-first-use.md::^# Definition-on-first-use
Runtime verification: file <repo>/docs/DECISIONS.md::023-definition-on-first-use-enforcement.md

Verdict: PASS
Confidence: 10
Reason: Decision 023 file exists with all required sections and five sub-decisions; rule file exists with substantive content; DECISIONS.md updated with row 023; rule synced to live ~/.claude/rules/.


EVIDENCE BLOCK
==============
Task ID: 2
Task description: Hook implementation definition-on-first-use-gate.sh. NEW pre-commit hook (PreToolUse Bash on git commit). On commit modifying *.md files in scope, parse the staged diff via git diff --cached, extract new acronyms, look up each in glossary.md OR confirm defined in the same diff. Block if any new acronym is undefined. --self-test with 5+ scenarios.
Verified at: 2026-05-05T02:05:43Z
Verifier: task-verifier agent

Checks run:
1. Hook file exists at adapters location, executable
   Command: ls -la adapters/claude-code/hooks/definition-on-first-use-gate.sh
   Output: -rwxr-xr-x 1 misha 197609 17533 May 4 18:55 (executable, 520 lines)
   Result: PASS

2. Hook synced to ~/.claude/hooks/, executable
   Command: ls -la ~/.claude/hooks/definition-on-first-use-gate.sh && diff -q
   Output: -rwxr-xr-x 1 misha 197609 17533 May 4 18:56 (executable). Files are byte-identical.
   Result: PASS

3. --self-test mode runs and PASSes 5+ scenarios
   Command: bash adapters/claude-code/hooks/definition-on-first-use-gate.sh --self-test
   Output:
     self-test (1) PASS-no-in-scope-changes: PASS (rc=0, expected 0)
     self-test (2) PASS-defined-in-glossary: PASS (rc=0, expected 0)
     self-test (3) PASS-defined-in-diff: PASS (rc=0, expected 0)
     self-test (4) FAIL-undefined-acronym: PASS (rc=1, expected 1; correctly blocked)
     self-test (5) PASS-stopwords-not-flagged: PASS (rc=0, expected 0)
     self-test (6) PASS-no-glossary-graceful-degrade: PASS (rc=0, expected 0)
     self-test (7) FAIL-single-word-paren-not-definition: PASS (rc=1, expected 1; correctly blocked)
     self-test summary: 7 passed, 0 failed (of 7 scenarios)
   Result: PASS — 7 scenarios all pass (exceeds the required 5+)

Git evidence:
  Files modified in commit 7f24907 (2026-05-04 18:59:18 -0700):
    - adapters/claude-code/hooks/definition-on-first-use-gate.sh (NEW, 520 lines)

Runtime verification: file <repo>/adapters/claude-code/hooks/definition-on-first-use-gate.sh::^#!/.*bash
Runtime verification: file <repo>/adapters/claude-code/hooks/definition-on-first-use-gate.sh::--self-test

Verdict: PASS
Confidence: 10
Reason: Hook exists, is executable, byte-identical with live mirror, and --self-test passes all 7 scenarios (exceeds 5+ requirement). The four mandatory scenario types from the plan (no-md-changes, defined-in-glossary, defined-in-diff, undefined-blocked, stopword-not-flagged) are all present and passing.


EVIDENCE BLOCK
==============
Task ID: 3
Task description: Wire hook + glossary path resolution. EDIT adapters/claude-code/settings.json.template to add the hook to PreToolUse Bash chain, position after harness-hygiene-scan.sh. The hook reads glossary path from a configured location. Mirror to live. Single commit.
Verified at: 2026-05-05T02:05:43Z
Verifier: task-verifier agent

Checks run:
1. Hook wired into adapters/claude-code/settings.json.template
   Command: grep -n "definition-on-first-use" adapters/claude-code/settings.json.template
   Output: line 167 — "command": "bash ~/.claude/hooks/definition-on-first-use-gate.sh"
   Result: PASS

2. Hook wired into live ~/.claude/settings.json
   Command: grep -n "definition-on-first-use" ~/.claude/settings.json
   Output: line 276 — "command": "bash ~/.claude/hooks/definition-on-first-use-gate.sh"
   Result: PASS

3. Both settings.json files are valid JSON
   Command: jq -e . on each file
   Output: "OK template valid JSON" + "OK live valid JSON"
   Result: PASS

Git evidence:
  Files modified in commit e4fcbc2 (2026-05-04 19:03:08 -0700):
    - adapters/claude-code/settings.json.template (+9 lines, hook block added)
  Live ~/.claude/settings.json is gitignored (not in commit), separately verified to contain matching block.

Runtime verification: file <repo>/adapters/claude-code/settings.json.template::definition-on-first-use-gate.sh
Runtime verification: file ~/.claude/settings.json::definition-on-first-use-gate.sh

Verdict: PASS
Confidence: 10
Reason: Hook is wired into both the committed settings.json.template (line 167) AND the live gitignored ~/.claude/settings.json (line 276). Both files are valid JSON. Hook command line "bash ~/.claude/hooks/definition-on-first-use-gate.sh" matches the wiring requirement.


EVIDENCE BLOCK
==============
Task ID: 4
Task description: Inventory + enforcement-map + backlog cleanup. Add inventory row to docs/harness-architecture.md for the new hook + new rule. Add row to vaporware-prevention.md enforcement map. Mark sub-gap G as IMPLEMENTED in docs/backlog.md "Recently implemented" section with commit SHA. Single commit.
Verified at: 2026-05-05T02:05:43Z
Verifier: task-verifier agent

Checks run:
1. harness-architecture.md inventory has row for new hook
   Command: grep -n "definition-on-first-use" docs/harness-architecture.md
   Output: line 161 — hook row "definition-on-first-use-gate.sh (Phase 1d-F, 2026-05-04) | PreToolUse Bash (on git commit) | ..." with full description of acronym extraction, stopword allowlist, glossary lookup, in-diff parenthetical detection, --self-test 7 scenarios.
   Result: PASS

2. harness-architecture.md inventory has row for new rule
   Command: same grep — line 399
   Output: line 399 — rule row "definition-on-first-use.md (Phase 1d-F, 2026-05-04) | Every commit modifying *.md under neural-lace/build-doctrine/ | Mechanism (hook-enforced). Documents Decision 023's definition-on-first-use semantics..."
   Result: PASS

3. vaporware-prevention.md enforcement-map row added
   Command: grep -n "definition-on-first-use" adapters/claude-code/rules/vaporware-prevention.md
   Output: line 41 — "| Definition-on-first-use enforcement at neural-lace/build-doctrine/ | definition-on-first-use-gate.sh PreToolUse Bash on git commit (Phase 1d-F / sub-gap G) | ~/.claude/hooks/definition-on-first-use-gate.sh |"
   Result: PASS

4. backlog.md "Recently implemented" includes Phase 1d-F section crediting sub-gap G IMPLEMENTED
   Command: grep -n "sub-gap G\|Phase 1d-F\|1d-F" docs/backlog.md
   Output:
     line 3 — header "v15: HARNESS-GAP-10 sub-gap G IMPLEMENTED via Phase 1d-F (...); definition-on-first-use enforcement live via new pre-commit hook + Decision 023 + new rule."
     line 25 — "These items shipped in Phase 1d-F (docs/plans/archive/phase-1d-f-definition-on-first-use.md):"
     line 27 — "**HARNESS-GAP-10 sub-gap G** — Definition-on-first-use enforcement shipped (commits 7f24907 + this commit). Pre-commit hook scans *.md under build-doctrine/ for first-use acronyms; blocks if undefined in glossary or in-context. See Decision 023."
   Result: PASS

Git evidence:
  Files modified in commit e4fcbc2 (2026-05-04 19:03:08 -0700):
    - adapters/claude-code/rules/vaporware-prevention.md (+1 line, enforcement-map row)
    - docs/backlog.md (+5/-1 lines, v15 header + Phase 1d-F "Recently implemented" sub-section)
  harness-architecture.md inventory rows landed earlier in commit 7f24907 (Tasks 1+2) per builder note; verified in place at lines 161 + 399.

Runtime verification: file <repo>/docs/harness-architecture.md::definition-on-first-use-gate.sh
Runtime verification: file <repo>/docs/harness-architecture.md::definition-on-first-use.md
Runtime verification: file <repo>/adapters/claude-code/rules/vaporware-prevention.md::Definition-on-first-use enforcement
Runtime verification: file <repo>/docs/backlog.md::HARNESS-GAP-10 sub-gap G

Verdict: PASS
Confidence: 10
Reason: All four documentation surfaces updated. harness-architecture.md has both hook row (line 161) and rule row (line 399). vaporware-prevention.md has the enforcement-map row (line 41). backlog.md has v15 header bump + Phase 1d-F "Recently implemented" sub-section crediting commit 7f24907. Note: forward-pointing reference to docs/plans/archive/ in backlog line 25 is anticipatory of pending COMPLETED status flip, accurate as future state.

