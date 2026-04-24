# Evidence Log — Failure Mode Catalog as First-Class Harness Artifact

EVIDENCE BLOCK
==============
Task ID: A.1
Task description: Create `docs/failure-modes.md` with the entry schema (ID, Symptom, Root cause, Detection, Prevention, Example) and seed 4-6 entries covering: concurrent-session plan wipe, mysterious effort-level reset on automation tasks, bug-persistence trigger firing without actual persistence, verbose plans missing required sections, and untracked plan file location ambiguity.
Verified at: 2026-04-23T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. File exists at canonical path
   Command: ls docs/failure-modes.md
   Output: docs/failure-modes.md
   Result: PASS

2. Schema documented (six fields per entry)
   Command: grep -E '^- \*\*(ID|Symptom|Root cause|Detection|Prevention|Example)\.\*\*' docs/failure-modes.md
   Output: 6 schema field bullets present in Schema section
   Result: PASS

3. Seed entry count within 4-6 target
   Command: grep -c '^## FM-' docs/failure-modes.md
   Output: 6
   Result: PASS

4. Each entry contains Root cause line
   Command: grep -c '^- \*\*Root cause\.\*\*' docs/failure-modes.md
   Output: 6
   Result: PASS (matches entry count)

5. Required failure classes seeded
   Coverage check (manual): FM-001 concurrent-session plan wipe; FM-002 mysterious effort-level reset; FM-003 bug-persistence trigger fired without persistence; FM-004 verbose plan with placeholder-only required sections; FM-005 untracked plan file location ambiguity; FM-006 self-reported task completion without evidence (bonus class — included because it is the dominant historical failure class and grounds the Detection field for several other entries).
   Result: PASS

6. Sanitization check
   Grep: codenames, real product names, absolute paths with usernames, real incident dates
   Output: none found — entries use generic terms ("a workflow", "an automation task", "a plan with 41 tasks")
   Result: PASS

Runtime verification: file docs/failure-modes.md::^## FM-001 — Concurrent-session plan wipe$
Runtime verification: file docs/failure-modes.md::^- \*\*Root cause\.\*\*

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.8
Task description: Update `~/.claude/docs/harness-architecture.md` to add a row for `docs/failure-modes.md` in the relevant inventory table, then mirror to the repo.
Verified at: 2026-04-24T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. Catalog row added in Patterns table
   Verification: harness-architecture.md Patterns table now has a second row "docs/failure-modes.md (2026-04-24)" with What it documents + Enforcement status columns
   Result: PASS

2. Last-updated header bumped to today
   Command: head -2 ~/.claude/docs/harness-architecture.md
   Output: "Last updated: 2026-04-24 (failure mode catalog as first-class harness artifact...)"
   Result: PASS

3. References to all five wiring sites included in the description
   Verification: catalog row mentions diagnosis.md, harness-lesson.md, why-slipped.md, claim-reviewer.md, task-verifier.md
   Result: PASS

4. Mirror to repo
   Command: cp ~/.claude/docs/harness-architecture.md docs/harness-architecture.md && diff -q
   Output: ARCH DOC IN SYNC
   Result: PASS

Runtime verification: file ~/.claude/docs/harness-architecture.md::docs/failure-modes.md
Runtime verification: file ~/claude-projects/neural-lace/docs/harness-architecture.md::docs/failure-modes.md

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.7
Task description: Mirror every modified file from `~/.claude/` into `~/claude-projects/neural-lace/adapters/claude-code/` and run the diff check from `harness-maintenance.md` to confirm zero drift.
Verified at: 2026-04-24T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. All five files modified in this plan are mirrored to repo
   Command: cp ~/.claude/{rules/diagnosis.md,skills/harness-lesson.md,skills/why-slipped.md,agents/claim-reviewer.md,agents/task-verifier.md} → adapters/claude-code/<same-paths>
   Output: copies completed without error
   Result: PASS

2. Per-file diff check for plan-modified files
   Command: diff -q ~/.claude/<file> adapters/claude-code/<file> for each of 5 modified files
   Output: all 5 IN SYNC (rules/diagnosis.md, skills/harness-lesson.md, skills/why-slipped.md, agents/claim-reviewer.md, agents/task-verifier.md)
   Result: PASS

3. Full diff loop (per harness-maintenance.md)
   Command: full diff loop across agents/rules/docs/hooks/templates/skills
   Output: 25 DIFFERS + 4 MISSING reported — all are pre-existing drift unrelated to this plan; the 5 plan-modified files are all in sync. Pre-existing drift was logged to docs/backlog.md as a P2 follow-up so the discovery is not lost.
   Result: PASS for plan scope; pre-existing drift is OUT OF SCOPE per the plan's Scope clause and is now tracked.

Runtime verification: file ~/claude-projects/neural-lace/adapters/claude-code/rules/diagnosis.md::docs/failure-modes.md
Runtime verification: file ~/claude-projects/neural-lace/adapters/claude-code/skills/harness-lesson.md::Step 0. Check the failure mode catalog FIRST
Runtime verification: file ~/claude-projects/neural-lace/adapters/claude-code/skills/why-slipped.md::Step 0. Check the failure mode catalog FIRST
Runtime verification: file ~/claude-projects/neural-lace/adapters/claude-code/agents/claim-reviewer.md::Consult the failure mode catalog
Runtime verification: file ~/claude-projects/neural-lace/adapters/claude-code/agents/task-verifier.md::Step 2.5: Cross-check against the failure mode catalog

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.6
Task description: Update `~/.claude/agents/task-verifier.md` to consult the catalog for known-bad patterns (e.g., self-reported completion without evidence) during verification.
Verified at: 2026-04-24T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. Step 2.5 inserted between Step 2 (git history) and Step 3 (task-type-specific checks)
   Verification: task-verifier.md now contains "### Step 2.5: Cross-check against the failure mode catalog" heading between "### Step 2: Inspect the git history" and "### Step 3: Run task-type-specific checks"
   Result: PASS

2. References docs/failure-modes.md by exact path
   Command: grep -c 'docs/failure-modes.md' ~/.claude/agents/task-verifier.md
   Output: 1+
   Result: PASS

3. Names specific catalog entries relevant to known-bad patterns (FM-006 self-report, FM-004 placeholder sections, FM-001 uncommitted plan)
   Verification: Step 2.5 body contains "FM-006", "FM-004", and "FM-001" explicitly tied to phenotype matches
   Result: PASS

4. FAIL behavior on catalog match without satisfied Prevention
   Verification: Step 2.5 instructs: "FAIL with a citation: `Catalog match: FM-NNN; Prevention requires X; evidence does not show X`"
   Result: PASS

Runtime verification: file ~/.claude/agents/task-verifier.md::docs/failure-modes.md
Runtime verification: file ~/.claude/agents/task-verifier.md::Step 2.5: Cross-check against the failure mode catalog

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.5
Task description: Update `~/.claude/agents/claim-reviewer.md` to consult the catalog when evaluating claims that match known symptoms.
Verified at: 2026-04-24T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. Catalog consult step inserted in Verification process
   Verification: claim-reviewer.md Verification process now contains a numbered "Consult the failure mode catalog" step (step 3), and subsequent steps are renumbered 4-7 accordingly
   Result: PASS

2. References docs/failure-modes.md by exact path
   Command: grep -c 'docs/failure-modes.md' ~/.claude/agents/claim-reviewer.md
   Output: 1+
   Result: PASS

3. Catalog consult step specifies the FAIL behavior for unmatched claims
   Verification: paragraph contains "FAIL such drafts and require a rewrite that cites the catalog entry's Prevention field"
   Result: PASS

Runtime verification: file ~/.claude/agents/claim-reviewer.md::docs/failure-modes.md
Runtime verification: file ~/.claude/agents/claim-reviewer.md::Consult the failure mode catalog

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.4
Task description: Update `~/.claude/skills/why-slipped.md` with the same check-catalog-first guidance so diagnosis starts from the known-failure corpus.
Verified at: 2026-04-24T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. Step 0 added before Step 1 in Procedure section
   Verification: why-slipped.md now contains "### Step 0. Check the failure mode catalog FIRST" immediately after "Execute these steps in order. Do NOT skip steps" and before "### Step 1. Identify the specific failure"
   Result: PASS

2. Step 0 references docs/failure-modes.md
   Command: grep -c 'docs/failure-modes.md' ~/.claude/skills/why-slipped.md
   Output: 2+ (Step 0 + Step 4 catalog-update note)
   Result: PASS

3. Step 4 instructs adding catalog edit alongside the mechanism
   Verification: why-slipped.md Step 4 contains "ALSO list `docs/failure-modes.md` as a required edit"
   Result: PASS

Runtime verification: file ~/.claude/skills/why-slipped.md::docs/failure-modes.md
Runtime verification: file ~/.claude/skills/why-slipped.md::Step 0. Check the failure mode catalog FIRST

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.3
Task description: Update `~/.claude/skills/harness-lesson.md` to instruct the skill to consult the catalog first and extend an existing entry rather than duplicate a pattern.
Verified at: 2026-04-24T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. Step 0 added before Step 1 in Procedure section
   Verification: harness-lesson.md now contains "### Step 0. Check the failure mode catalog FIRST" immediately after "## Procedure" and before "### Step 1. Restate the failure precisely"
   Result: PASS

2. Step 0 references docs/failure-modes.md by exact path
   Command: grep -c 'docs/failure-modes.md' ~/.claude/skills/harness-lesson.md
   Output: 2+ (Step 0 + Companion-work)
   Result: PASS

3. Step 0 includes both extend (yes) and append (no) decision branches
   Verification: paragraph contains "If yes: the correct output is to EXTEND" and "If no: proceed to Step 1"
   Result: PASS

4. Companion-work section now lists catalog update as a required companion change
   Verification: harness-lesson.md Companion-work bullets now include "A new or extended entry in `docs/failure-modes.md`"
   Result: PASS

Runtime verification: file ~/.claude/skills/harness-lesson.md::docs/failure-modes.md
Runtime verification: file ~/.claude/skills/harness-lesson.md::Step 0. Check the failure mode catalog FIRST

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.2
Task description: Update `~/.claude/rules/diagnosis.md` to add a directive after the "Encode the Fix" section: when a root cause is identified, add it to `docs/failure-modes.md` or explicitly justify why it is not a new class.
Verified at: 2026-04-24T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. New paragraph references the catalog
   Command: grep -c 'docs/failure-modes.md' ~/.claude/rules/diagnosis.md
   Output: 1+
   Result: PASS

2. Paragraph placed inside "After Every Failure: Encode the Fix" section, after the Generalize-at-encoding-time paragraph
   Verification: read diagnosis.md and confirm the catalog directive immediately follows the "Generalize at encoding time" paragraph and precedes the "When the User Corrects You" heading.
   Result: PASS

3. Directive includes (a) extend OR (b) append decision and (c) justify-if-not-new requirement
   Verification: paragraph contains "extend an existing entry", "append a new", and "briefly justify the decision in the diagnosis notes — do not skip the catalog step silently"
   Result: PASS

Runtime verification: file ~/.claude/rules/diagnosis.md::docs/failure-modes.md
Runtime verification: file ~/.claude/rules/diagnosis.md::Update the failure mode catalog

Verdict: PASS
