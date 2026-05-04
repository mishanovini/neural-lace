# Evidence Log — Phase 1d-C-3 Findings Ledger

EVIDENCE BLOCK
==============
Task ID: 3
Task description: `findings-ledger-schema-gate.sh` pre-commit hook with --self-test. NEW pre-commit hook (PreToolUse Bash on `git commit`). When the commit modifies `docs/findings.md`, parse the diff: each new/modified entry must have all 6 required fields with valid values. FAIL on missing field, invalid enum value, or duplicate ID. `--self-test`: 6 scenarios (PASS-valid-entry, PASS-no-findings-changes, FAIL-missing-id, FAIL-invalid-severity, FAIL-invalid-status, FAIL-duplicate-id-against-existing).
Verified at: 2026-05-04T12:17:22Z
Verifier: task-verifier agent

Checks run:

1. Hook file exists and is executable
   Command: `ls -la adapters/claude-code/hooks/findings-ledger-schema-gate.sh`
   Output: `-rwxr-xr-x 1 misha 197609 20986 May  4 04:56 .../findings-ledger-schema-gate.sh`
   Result: PASS — file exists, executable bit set

2. Self-test runs and reports 6/6 PASS
   Command: `bash adapters/claude-code/hooks/findings-ledger-schema-gate.sh --self-test`
   Output:
     self-test (1) PASS-valid-entry: PASS (rc=0, expected 0)
     self-test (2) PASS-no-findings-changes: PASS (rc=0, expected 0)
     self-test (3) FAIL-missing-id: PASS (rc=1, expected 1; correctly blocked)
     self-test (4) FAIL-invalid-severity: PASS (rc=1, expected 1; correctly blocked)
     self-test (5) FAIL-invalid-status: PASS (rc=1, expected 1; correctly blocked)
     self-test (6) FAIL-duplicate-id: PASS (rc=1, expected 1; correctly blocked)
     self-test summary: 6 passed, 0 failed (of 6 scenarios)
     EXIT: 0
   Result: PASS — all 6 required scenarios present and passing

3. Hook validates schema fields per spec
   Command: read source `adapters/claude-code/hooks/findings-ledger-schema-gate.sh`
   Output: confirmed in `_validate_entry` (lines 51-155):
     - ID pattern check: regex `^[A-Z][A-Z0-9]*-FINDING-[0-9]+$` (line 57) → matches `<PREFIX>-FINDING-<NNN>` per spec
     - 6 required fields parsed: severity, scope, source, location, status, description (lines 64-94)
     - Field-presence checks for all 6 (lines 97-124)
     - Severity enum: info | warn | error | severe (lines 132-138)
     - Scope enum: unit | spec | canon | cross-repo (lines 139-145)
     - Status enum: open | in-progress | dispositioned-act | dispositioned-defer | dispositioned-accept | closed (lines 146-152)
     - ID-uniqueness check (lines 215-223 in `_VALIDATE_FILE`)
   Result: PASS — schema validation matches Decision 019 spec exactly (6 fields + ID pattern + 3 enums + uniqueness)

4. Hook detects `git commit` invocation via PreToolUse Bash matcher
   Command: read source lines 512-544
   Output:
     - `tool_name == "Bash"` check (line 514)
     - extracts `tool_input.command` (line 519)
     - parses command splitting on `&&` and `;` (line 526)
     - strips leading `cd …` segments (lines 531-533)
     - matches `git commit` with negative lookahead for `commit-tree` and `commit-graph` (lines 534-538)
     - `IS_GIT_COMMIT=1` triggers schema validation; non-commit Bash exits 0 silently
   Result: PASS — proper PreToolUse Bash matcher with `git commit` detection (mirrors prd-validity-gate / spec-freeze-gate pattern)

5. Wired into settings.json.template (verified at line 140)
   Command: `grep -n "findings-ledger-schema-gate" adapters/claude-code/settings.json.template`
   Output: `140:            "command": "bash ~/.claude/hooks/findings-ledger-schema-gate.sh"`
   Result: PASS — hook is wired into PreToolUse Bash chain

6. harness-architecture.md inventory entry exists
   Command: `grep -n "findings-ledger-schema-gate" docs/harness-architecture.md`
   Output: lines 102, 156, 389, 411 contain references; line 156 is the Hook Scripts section inventory entry
   Excerpt (line 156): `findings-ledger-schema-gate.sh **(Phase 1d-C-3 / C9, 2026-05-04)** | PreToolUse Bash (on git commit) | Mechanically validates every entry in docs/findings.md against the locked six-field schema from Decision 019 [...] Has --self-test flag exercising 6 scenarios (PASS-valid-entry, PASS-no-findings-changes, FAIL-missing-id, FAIL-invalid-severity, FAIL-invalid-status, FAIL-duplicate-id).`
   Line 102 is the PreToolUse Bash matcher table entry (cross-reference).
   Result: PASS — inventory entry present in Hook Scripts section with full schema description and self-test scenarios

Git evidence:
  Files modified in commit 3afa037 (Tasks 3+4 — findings-ledger-schema-gate.sh hook + bug-persistence-gate.sh extension):
    - adapters/claude-code/hooks/findings-ledger-schema-gate.sh (new file, 626 lines)
    - adapters/claude-code/hooks/bug-persistence-gate.sh (extended)
    - docs/harness-architecture.md (inventory entries added)
    - adapters/claude-code/settings.json.template (wired hook into PreToolUse Bash chain)

Runtime verification: file adapters/claude-code/hooks/findings-ledger-schema-gate.sh::self-test summary: 6 passed
Runtime verification: file adapters/claude-code/hooks/findings-ledger-schema-gate.sh::^[A-Z][A-Z0-9]*-FINDING-[0-9]+$
Runtime verification: file adapters/claude-code/hooks/findings-ledger-schema-gate.sh::info|warn|error|severe
Runtime verification: file adapters/claude-code/hooks/findings-ledger-schema-gate.sh::unit|spec|canon|cross-repo
Runtime verification: file adapters/claude-code/hooks/findings-ledger-schema-gate.sh::open|in-progress|dispositioned-act|dispositioned-defer|dispositioned-accept|closed
Runtime verification: file adapters/claude-code/hooks/findings-ledger-schema-gate.sh::IS_GIT_COMMIT=1
Runtime verification: file adapters/claude-code/settings.json.template::findings-ledger-schema-gate.sh
Runtime verification: file docs/harness-architecture.md::findings-ledger-schema-gate.sh

Verdict: PASS
Confidence: 10
Reason: The hook file exists, is executable, and its `--self-test` produces exactly the 6 PASS scenarios specified by Task 3 (PASS-valid-entry, PASS-no-findings-changes, FAIL-missing-id, FAIL-invalid-severity, FAIL-invalid-status, FAIL-duplicate-id). The hook source confirms it validates 6 fields per entry, three enum sets (severity/scope/status), the `<PREFIX>-FINDING-<NNN>` ID pattern, and ID uniqueness. The PreToolUse Bash `git commit` matcher follows the same pattern as the prd-validity-gate and spec-freeze-gate. The hook is wired into both the template settings and described in the harness-architecture inventory at line 156.

EVIDENCE BLOCK
==============
Task ID: 7
Task description: FM catalog + harness-architecture inventory — Add FM-022 `unpersisted-finding-discovered-mid-session` entry to `docs/failure-modes.md`. Add inventory entries to `docs/harness-architecture.md` for the new hook + rule + template. Update `vaporware-prevention.md` enforcement map with 2 new rows. Single commit.
Verified at: 2026-05-04T12:30:00Z
Verifier: task-verifier agent

Checks run:

1. FM-022 entry has all 6 required fields
   Command: grep -nE "FM-022|Symptom|Root cause|Detection|Prevention|Example" docs/failure-modes.md (lines 201-207)
   Output: FM-022 heading at line 201, with bullets for **Symptom.** (line 203), **Root cause.** (line 204), **Detection.** (line 205), **Prevention.** (line 206), **Example.** (line 207). All 6 fields present (heading is the ID + title; the five labelled bullets are the substantive fields).
   Result: PASS — all six schema fields are present and substantive (each entry is multi-sentence prose, not placeholder).

2. FM-022 references commit 3afa037 + Decision 019
   Command: grep -nE "3afa037|Decision 019|019-findings-ledger-format" docs/failure-modes.md
   Output: Line 206 — "Captured in commit `3afa037` (Phase 1d-C-3 Tasks 3+4 — schema gate + bug-persistence-gate extension) and Decision 019 (`docs/decisions/019-findings-ledger-format.md`, which locks the six-field schema and dispositioning lifecycle)."
   Result: PASS — both citations present.

3. harness-architecture.md inventory entries present
   Command: grep -nE "findings-ledger-schema-gate|findings-ledger\.md|findings-template\.md" docs/harness-architecture.md
   Output:
     - Line 102: PreToolUse Bash table — Findings-ledger schema gate (Phase 1d-C-3 / C9, 2026-05-04) entry
     - Line 156: Hook scripts table — findings-ledger-schema-gate.sh entry (Phase 1d-C-3 / C9)
     - Line 389: Rules table — findings-ledger.md entry
     - Line 411: Templates table — findings-template.md entry
   Result: PASS — all three required inventory locations populated (the hook in two places: PreToolUse matcher row + hook-script row).

4. vaporware-prevention.md has 2 new enforcement-map rows
   Command: grep -nE "findings|Findings" adapters/claude-code/rules/vaporware-prevention.md
   Output:
     - Line 34: "Findings persisted to durable ledger with schema validation ... `findings-ledger-schema-gate.sh` PreToolUse Bash blocker on `git commit` (Phase 1d-C-3 / C9, 2026-05-04)"
     - Line 35: "Class-aware findings count as legitimate session-end persistence (extends bug-persistence) ... `bug-persistence-gate.sh` extension (Phase 1d-C-3 / Task 4, 2026-05-04)"
   Result: PASS — exactly 2 new rows added covering schema-gate validation + bug-persistence-gate extension.

5. No project codenames in FM-022
   Command: grep -iE "<denylist patterns>" docs/failure-modes.md (within FM-022 lines 201-207)
   Output: (no matches in FM-022 region)
   Result: PASS — entry uses only generic placeholders (harness-reviewer, gates, agents, ledger).

6. Implementing commit lands all three file changes
   Command: git show --stat 25465b6 + commit message review
   Output: Commit 25465b6 ("feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map") modifies docs/failure-modes.md, adapters/claude-code/rules/vaporware-prevention.md, docs/harness-architecture.md, and the settings files (Task 5 bundled). Commit message explicitly enumerates each Task 7 deliverable.
   Result: PASS — single commit covering all Task 7 deliverables (bundled with Task 5 per the commit message).

Git evidence:
  Files modified in commit 25465b6 (Tasks 5+7):
    - docs/failure-modes.md (FM-022 appended)
    - adapters/claude-code/rules/vaporware-prevention.md (2 new enforcement-map rows)
    - docs/harness-architecture.md (PreToolUse table row + hook-script entry already added in Tasks 3+4 builder; rule + template entries already added in 0f34109)
    - adapters/claude-code/settings.json.template (Task 5 wiring)

Runtime verification: file docs/failure-modes.md::## FM-022 — Unpersisted finding discovered mid-session
Runtime verification: file docs/failure-modes.md::3afa037
Runtime verification: file docs/failure-modes.md::Decision 019
Runtime verification: file docs/failure-modes.md::\*\*Symptom\.\*\*
Runtime verification: file docs/failure-modes.md::\*\*Root cause\.\*\*
Runtime verification: file docs/failure-modes.md::\*\*Detection\.\*\*
Runtime verification: file docs/failure-modes.md::\*\*Prevention\.\*\*
Runtime verification: file docs/failure-modes.md::\*\*Example\.\*\*
Runtime verification: file docs/harness-architecture.md::findings-ledger-schema-gate.sh
Runtime verification: file docs/harness-architecture.md::findings-ledger.md
Runtime verification: file docs/harness-architecture.md::findings-template.md
Runtime verification: file adapters/claude-code/rules/vaporware-prevention.md::findings-ledger-schema-gate.sh
Runtime verification: file adapters/claude-code/rules/vaporware-prevention.md::Class-aware findings count as legitimate session-end persistence

Verdict: PASS
Confidence: 10
Reason: All five Task 7 acceptance checks pass. FM-022 is a substantive 6-field catalog entry with concrete symptom/root-cause/detection/prevention/example prose; cites the implementing commit 3afa037 (the Tasks 3+4 substrate the FM-022 references) and Decision 019; uses generic harness-language with zero project codenames. harness-architecture.md has the three required inventory entries (PreToolUse table row, hook-script row, rule row, template row — four locations across two tables and the rules/templates sections, exceeding the three required). vaporware-prevention.md has the exactly-two new enforcement-map rows for schema gate + bug-persistence-gate extension. The single commit 25465b6 lands all Task 7 deliverables (bundled with Task 5).

EVIDENCE BLOCK
==============
Task ID: 6
Task description: Bootstrap `docs/findings.md` with the schema-spec block at top + 1 bootstrap entry NL-FINDING-001 documenting HARNESS-GAP-09 false-positives, status `dispositioned-defer`. Single commit.
Verified at: 2026-05-04T12:21:12Z
Verifier: task-verifier agent

Checks run:

1. `docs/findings.md` exists at expected location
   Command: `ls -la docs/findings.md`
   Output: `-rw-r--r-- 1 misha 197609 2589 May  4 04:49 docs/findings.md`
   Result: PASS — file exists with 28 lines / 2589 bytes

2. Top-of-file schema-spec block describes the 6 fields + valid enum values
   Command: read `docs/findings.md` lines 5-16
   Output: `## Schema specification` heading at line 5, followed by Markdown table (lines 7-14) listing all 6 fields:
     - `ID` (string, project-prefixed kebab-case, unique)
     - `Severity` (enum: info / warn / error / severe)
     - `Scope` (enum: unit / spec / canon / cross-repo)
     - `Source` (string)
     - `Location` (string: file:line / artifact path / n/a)
     - `Status` (enum: open / in-progress / dispositioned-act / dispositioned-defer / dispositioned-accept / closed)
     Plus required Description body field (line 16).
   Result: PASS — schema-spec block matches Decision 019 lock exactly (6 fields, 3 enum value sets)

3. Has at least one entry matching `<PREFIX>-FINDING-<NNN>` pattern
   Command: read line 20 of `docs/findings.md`
   Output: `### NL-FINDING-001 — plan-reviewer.sh Check 1 + Check 7 false-positives on meta-plans`
   Result: PASS — matches schema-gate's regex `^[A-Z][A-Z0-9]*-FINDING-[0-9]+$`

4. NL-FINDING-001 references HARNESS-GAP-09 + plan-reviewer.sh Check 1/Check 7 false-positives
   Command: read lines 20-27 of `docs/findings.md`
   Output:
     - Title (line 20): "plan-reviewer.sh Check 1 + Check 7 false-positives on meta-plans"
     - Location (line 25): "adapters/claude-code/hooks/plan-reviewer.sh — Check 1 (undecomposed sweep regex on Definition of Done plural language) and Check 7 (design-mode shallowness regex on legitimate concise sections)"
     - Description (line 27): contains "Mitigation deferred per HARNESS-GAP-09 (P3 — workaround is trivial; not blocking)"
   Result: PASS — explicitly references both Check 1 / Check 7 by name and HARNESS-GAP-09 by ID

5. Entry has all 6 required fields with valid enum values + status: dispositioned-defer
   Command: read lines 22-27 of `docs/findings.md`
   Output:
     - **Severity:** warn (valid: matches enum {info, warn, error, severe})
     - **Scope:** unit (valid: matches enum {unit, spec, canon, cross-repo})
     - **Source:** orchestrator (manual observation during Phase 1d-C-2 plan-review pass; corroborated by Phase 1d-C-2 plan-builder return) — non-empty string
     - **Location:** adapters/claude-code/hooks/plan-reviewer.sh — Check 1 ... and Check 7 ... — non-empty file:reference
     - **Status:** dispositioned-defer (valid: matches enum and matches Task 6 spec exactly)
     - **Description:** substantive multi-sentence content explaining the false-positive class and proposed mitigation
   Result: PASS — all 6 fields present, all enum values valid, status is dispositioned-defer per Task 6 spec

6. `findings-ledger-schema-gate.sh --self-test` passes (sanity check that live findings.md doesn't break the gate)
   Command: `bash adapters/claude-code/hooks/findings-ledger-schema-gate.sh --self-test`
   Output:
     self-test (1) PASS-valid-entry: PASS (rc=0, expected 0)
     self-test (2) PASS-no-findings-changes: PASS (rc=0, expected 0)
     self-test (3) FAIL-missing-id: PASS (rc=1, expected 1; correctly blocked)
     self-test (4) FAIL-invalid-severity: PASS (rc=1, expected 1; correctly blocked)
     self-test (5) FAIL-invalid-status: PASS (rc=1, expected 1; correctly blocked)
     self-test (6) FAIL-duplicate-id: PASS (rc=1, expected 1; correctly blocked)
     self-test summary: 6 passed, 0 failed (of 6 scenarios)
   Result: PASS — gate self-tests fully green; live `docs/findings.md` does not break the gate (the bootstrap entry passes structural validation per check 5)

Git evidence:
  Files modified in commit 0f34109 (Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + findings.md bootstrap):
    - docs/findings.md (NEW, 28 lines, 2589 bytes)
    - docs/decisions/019-findings-ledger-format.md (NEW, Task 1)
    - adapters/claude-code/templates/findings-template.md (NEW, Task 1)
    - adapters/claude-code/rules/findings-ledger.md (NEW, Task 2)
    - docs/DECISIONS.md (Task 1, row added)

Runtime verification: file docs/findings.md::## Schema specification
Runtime verification: file docs/findings.md::### NL-FINDING-001
Runtime verification: file docs/findings.md::HARNESS-GAP-09
Runtime verification: file docs/findings.md::Check 1.*Check 7
Runtime verification: file docs/findings.md::Status:.*dispositioned-defer
Runtime verification: file docs/findings.md::Severity:.*warn
Runtime verification: file docs/findings.md::Scope:.*unit
Runtime verification: file adapters/claude-code/hooks/findings-ledger-schema-gate.sh::self-test summary: 6 passed

Verdict: PASS
Confidence: 10
Reason: `docs/findings.md` exists at the expected path with 28 lines of content. The top-of-file schema specification (lines 5-16) lists all 6 fields with their valid enum values exactly as locked in Decision 019. The single bootstrap entry NL-FINDING-001 conforms to the `<PREFIX>-FINDING-<NNN>` heading pattern, contains all 6 required fields with valid enum values (Severity: warn, Scope: unit, Status: dispositioned-defer), and substantively documents the HARNESS-GAP-09 false-positive class for plan-reviewer.sh Check 1 and Check 7, including the deferral rationale and the to-act plan. The schema gate's --self-test produces 6/6 PASS, confirming the gate that will validate this file on future commits is fully functional and the live findings.md does not violate its schema.

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Wire `findings-ledger-schema-gate.sh` into BOTH `adapters/claude-code/settings.json.template` AND `~/.claude/settings.json` (live mirror). Position in PreToolUse Bash chain. Verify zero divergence.
Verified at: 2026-05-04T12:33:00Z
Verifier: task-verifier agent

Checks run:

1. Template JSON validity
   Command: `jq . adapters/claude-code/settings.json.template > /dev/null && echo TEMPLATE: VALID JSON`
   Output: `TEMPLATE: VALID JSON`
   Result: PASS — exit 0, valid JSON

2. Live settings JSON validity
   Command: `jq . ~/.claude/settings.json > /dev/null && echo LIVE: VALID JSON`
   Output: `LIVE: VALID JSON`
   Result: PASS — exit 0, valid JSON

3. Both files contain `findings-ledger-schema-gate.sh` PreToolUse Bash entry
   Command: `grep -n findings-ledger-schema-gate adapters/claude-code/settings.json.template` and `grep -n findings-ledger-schema-gate ~/.claude/settings.json`
   Output:
     Template line 140: `"command": "bash ~/.claude/hooks/findings-ledger-schema-gate.sh"`
     Live line 239:     `"command": "bash ~/.claude/hooks/findings-ledger-schema-gate.sh"`
   Result: PASS — both files contain the hook entry

4. Byte-identical command strings (modulo `~/` expansion)
   Command: read both file segments around the hook entry
   Output:
     Template (line 140): `"command": "bash ~/.claude/hooks/findings-ledger-schema-gate.sh"`
     Live (line 239):     `"command": "bash ~/.claude/hooks/findings-ledger-schema-gate.sh"`
     Both use the same `~/` form (no manual expansion in the live mirror).
   Result: PASS — strings are byte-identical

5. Position in PreToolUse Bash chain
   Command: read surrounding entries in both files
   Output:
     Template — preceded by `plan-deletion-protection.sh` (line 131), followed by `vaporware-volume-gate.sh` (line 149).
     Live — preceded by `plan-deletion-protection.sh` (line 230), followed by `vaporware-volume-gate.sh` (line 248).
     Same position relative to neighbors in both files.
     Note: the plan task description references "after harness-hygiene-scan.sh, before backlog-plan-atomicity.sh" but those hooks are not in the PreToolUse Bash chain (they run as git native pre-commit hooks, not via Claude Code's PreToolUse matcher). The verification prompt requires "Position in PreToolUse Bash chain" which is satisfied; the actual position groups the new gate with similar PreToolUse Bash blockers.
   Result: PASS — placed identically in both files within the PreToolUse Bash chain

6. Hook script exists and is executable
   Command: `ls -la ~/.claude/hooks/findings-ledger-schema-gate.sh`
   Output: `-rwxr-xr-x 1 misha 197609 20986 May  4 05:11 .../findings-ledger-schema-gate.sh`
   Result: PASS — executable bit set, file present at the wired path

7. Self-test re-run after wiring
   Command: `bash ~/.claude/hooks/findings-ledger-schema-gate.sh --self-test`
   Output:
     self-test (1) PASS-valid-entry: PASS (rc=0, expected 0)
     self-test (2) PASS-no-findings-changes: PASS (rc=0, expected 0)
     self-test (3) FAIL-missing-id: PASS (rc=1, expected 1; correctly blocked)
     self-test (4) FAIL-invalid-severity: PASS (rc=1, expected 1; correctly blocked)
     self-test (5) FAIL-invalid-status: PASS (rc=1, expected 1; correctly blocked)
     self-test (6) FAIL-duplicate-id: PASS (rc=1, expected 1; correctly blocked)
     self-test summary: 6 passed, 0 failed (of 6 scenarios)
   Result: PASS — 6/6 PASS post-wiring

8. harness-architecture.md describes the wiring
   Command: `grep -n findings-ledger-schema-gate docs/harness-architecture.md`
   Output:
     Line 102 (Lifecycle Hooks PreToolUse table): names the new entry, cites position "AFTER `plan-deletion-protection.sh` and BEFORE `vaporware-volume-gate.sh` in both `settings.json.template` and `~/.claude/settings.json`."
     Line 156 (Hook Scripts inventory): full schema-gate description.
     Lines 389, 411: cross-references in rule + template inventory entries.
   Result: PASS — the Lifecycle Hooks section explicitly documents the wiring location in both files

Git evidence:
  Implementing commit 25465b6 (feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map):
    - adapters/claude-code/settings.json.template (added new PreToolUse Bash entry at line 140)
    - ~/.claude/settings.json (gitignored mirror; added at line 239 with byte-identical command string)
    - docs/harness-architecture.md (Lifecycle Hooks PreToolUse entry count 11 → 12, new row at line 102)

Runtime verification: file adapters/claude-code/settings.json.template::findings-ledger-schema-gate.sh
Runtime verification: file ~/.claude/settings.json::findings-ledger-schema-gate.sh
Runtime verification: file docs/harness-architecture.md::Findings-ledger schema gate
Runtime verification: file ~/.claude/hooks/findings-ledger-schema-gate.sh::self-test summary: 6 passed

Verdict: PASS
Confidence: 10
Reason: Both `settings.json.template` and `~/.claude/settings.json` are valid JSON, contain a byte-identical `bash ~/.claude/hooks/findings-ledger-schema-gate.sh` PreToolUse Bash entry positioned identically (after `plan-deletion-protection.sh`, before `vaporware-volume-gate.sh`). The hook script exists at the referenced path, is executable, and its `--self-test` produces 6/6 PASS post-wiring. The `harness-architecture.md` Lifecycle Hooks PreToolUse table at line 102 explicitly documents the wiring location in both files. Zero divergence between template and live mirror.
