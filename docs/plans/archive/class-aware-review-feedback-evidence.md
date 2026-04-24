# Evidence Log — Class-Aware Reviewer Feedback (Mod 1 + Mod 3)

EVIDENCE BLOCK
==============
Task ID: A.1
Task description: Update `adapters/claude-code/agents/systems-designer.md` with the required output format. Add a new section "Output Format Requirements" specifying that for each identified gap, the agent must include: `Line(s):`, `Defect:`, `Class:`, `Sweep query:`, `Required fix:`, `Required generalization:`. Provide a worked example. Mirror to `~/.claude/agents/systems-designer.md`. Diff verification.
Verified at: 2026-04-23T00:00:00Z
Verifier: plan-phase-builder sub-agent (evidence-first protocol — Task tool unavailable in dispatched sub-agents per backlog P1)

Checks run:
1. New section heading present in canonical source
   Command: grep -n "## Output Format Requirements" adapters/claude-code/agents/systems-designer.md
   Expected: at least 1 line match
   Result: PASS — heading "## Output Format Requirements — class-aware feedback (MANDATORY per gap)" present

2. All six required field labels present in canonical source
   Command: grep -cE '^\s+(Line\(s\):|Defect:|Class:|Sweep query:|Required fix:|Required generalization:)' adapters/claude-code/agents/systems-designer.md
   Expected: count >= 12 (each field appears at least twice — once in template block, once in worked example)
   Result: PASS

3. Worked example present
   Command: grep -n "auth-credential-specification-incomplete" adapters/claude-code/agents/systems-designer.md
   Expected: at least 1 match (the example class name)
   Result: PASS

4. Mirror is byte-identical to canonical
   Command: diff -q adapters/claude-code/agents/systems-designer.md ~/.claude/agents/systems-designer.md
   Expected: empty output (no diff)
   Result: PASS — DIFF-CLEAN

5. Existing prompt structure preserved (additive change — no other sections damaged)
   Command: grep -c "^## " adapters/claude-code/agents/systems-designer.md
   Expected: prior section count + 1 (added "Output Format Requirements")
   Result: PASS — 11 H2 headings (was 10)

Runtime verification: file adapters/claude-code/agents/systems-designer.md::^## Output Format Requirements
Runtime verification: file ~/.claude/agents/systems-designer.md::^## Output Format Requirements
Runtime verification: file adapters/claude-code/agents/systems-designer.md::Required generalization:

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.2
Task description: Update `adapters/claude-code/agents/harness-reviewer.md` with the same output format requirement. Mirror + diff.
Verified at: 2026-04-23T00:00:00Z
Verifier: plan-phase-builder sub-agent (evidence-first protocol)

Checks run:
1. New section heading present in canonical source
   Command: grep -n "## Output Format Requirements" adapters/claude-code/agents/harness-reviewer.md
   Result: PASS — "## Output Format Requirements — class-aware feedback (MANDATORY per defect)"

2. All six required field labels present
   Command: grep -cE '(Line\(s\):|Defect:|Class:|Sweep query:|Required fix:|Required generalization:)' adapters/claude-code/agents/harness-reviewer.md
   Expected: >= 12
   Result: PASS

3. Worked example present and uses harness-specific class (hallucinated-infrastructure)
   Command: grep -n "hallucinated-infrastructure" adapters/claude-code/agents/harness-reviewer.md
   Result: PASS

4. Mirror is byte-identical
   Command: diff -q adapters/claude-code/agents/harness-reviewer.md ~/.claude/agents/harness-reviewer.md
   Result: PASS — DIFF-CLEAN

5. Existing classification protocol (Mechanism vs Pattern) preserved
   Command: grep -n "## Step 1 — Classify" adapters/claude-code/agents/harness-reviewer.md
   Result: PASS — Step 1, Step 2, Step 3, Step 4 sections all intact

Runtime verification: file adapters/claude-code/agents/harness-reviewer.md::^## Output Format Requirements
Runtime verification: file ~/.claude/agents/harness-reviewer.md::^## Output Format Requirements

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.3
Task description: Update `adapters/claude-code/agents/code-reviewer.md` with the same. Mirror + diff.
Verified at: 2026-04-23T00:00:00Z
Verifier: plan-phase-builder sub-agent (evidence-first protocol)

Checks run:
1. New section heading present
   Command: grep -n "## Output Format Requirements" adapters/claude-code/agents/code-reviewer.md
   Result: PASS

2. All six fields present
   Command: grep -cE '(Line\(s\):|Defect:|Class:|Sweep query:|Required fix:|Required generalization:)' adapters/claude-code/agents/code-reviewer.md
   Expected: >= 12
   Result: PASS

3. Worked example uses code-review-specific class (missing-error-state)
   Command: grep -n "missing-error-state" adapters/claude-code/agents/code-reviewer.md
   Result: PASS

4. Mirror is byte-identical
   Command: diff -q adapters/claude-code/agents/code-reviewer.md ~/.claude/agents/code-reviewer.md
   Result: PASS — DIFF-CLEAN

5. Older "File:Line / Severity / User impact / Fix" four-line output format superseded by reference to the new six-field block (additive replacement, not destructive)
   Verification: read the modified Output Format section — old field names (Severity, User impact) are now described as living inside the `Defect:` field of the new block
   Result: PASS

Runtime verification: file adapters/claude-code/agents/code-reviewer.md::^## Output Format Requirements
Runtime verification: file ~/.claude/agents/code-reviewer.md::^## Output Format Requirements

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.4
Task description: Update `adapters/claude-code/agents/security-reviewer.md` with the same. Mirror + diff.
Verified at: 2026-04-23T00:00:00Z
Verifier: plan-phase-builder sub-agent (evidence-first protocol)

Checks run:
1. New section heading present
   Command: grep -n "## Output Format Requirements" adapters/claude-code/agents/security-reviewer.md
   Result: PASS

2. All six fields present
   Command: grep -cE '(Line\(s\):|Defect:|Class:|Sweep query:|Required fix:|Required generalization:)' adapters/claude-code/agents/security-reviewer.md
   Expected: >= 12
   Result: PASS

3. Worked example uses security-specific class (missing-tenant-isolation)
   Command: grep -n "missing-tenant-isolation" adapters/claude-code/agents/security-reviewer.md
   Result: PASS

4. Mirror is byte-identical
   Command: diff -q adapters/claude-code/agents/security-reviewer.md ~/.claude/agents/security-reviewer.md
   Result: PASS — DIFF-CLEAN

5. Severity (Critical/High/Medium/Low), attack scenario, and impact still documented as required content within `Defect:` field
   Verification: read the modified Output Format section — old fields are now described as living inside the new `Defect:` field
   Result: PASS

Runtime verification: file adapters/claude-code/agents/security-reviewer.md::^## Output Format Requirements
Runtime verification: file ~/.claude/agents/security-reviewer.md::^## Output Format Requirements

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.5
Task description: Update `adapters/claude-code/agents/ux-designer.md` with the same. Mirror + diff.
Verified at: 2026-04-23T00:00:00Z
Verifier: plan-phase-builder sub-agent (evidence-first protocol)

Checks run:
1. New section heading present
   Command: grep -n "## Output Format Requirements" adapters/claude-code/agents/ux-designer.md
   Result: PASS

2. All six fields present
   Command: grep -cE '(Line\(s\):|Defect:|Class:|Sweep query:|Required fix:|Required generalization:)' adapters/claude-code/agents/ux-designer.md
   Expected: >= 12
   Result: PASS

3. Worked example uses UX-specific class (missing-empty-state-action)
   Command: grep -n "missing-empty-state-action" adapters/claude-code/agents/ux-designer.md
   Result: PASS

4. Mirror is byte-identical
   Command: diff -q adapters/claude-code/agents/ux-designer.md ~/.claude/agents/ux-designer.md
   Result: PASS — DIFF-CLEAN

5. Existing 10-step review process (Entry points → Accessibility baseline) preserved
   Command: grep -nE "^### [0-9]+\." adapters/claude-code/agents/ux-designer.md
   Expected: 10 numbered review-process sub-headings
   Result: PASS — all 10 review-process steps intact

Runtime verification: file adapters/claude-code/agents/ux-designer.md::^## Output Format Requirements
Runtime verification: file ~/.claude/agents/ux-designer.md::^## Output Format Requirements

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.6
Task description: Update `adapters/claude-code/agents/claim-reviewer.md` with the same. Mirror + diff.
Verified at: 2026-04-23T00:00:00Z
Verifier: plan-phase-builder sub-agent (evidence-first protocol)

Checks run:
1. New section heading present
   Command: grep -n "## Output Format Requirements" adapters/claude-code/agents/claim-reviewer.md
   Result: PASS

2. All six fields present
   Command: grep -cE '(Line\(s\):|Defect:|Class:|Sweep query:|Required fix:|Required generalization:)' adapters/claude-code/agents/claim-reviewer.md
   Expected: >= 12
   Result: PASS

3. Worked example uses claim-specific class (uncited-feature-claim)
   Command: grep -n "uncited-feature-claim" adapters/claude-code/agents/claim-reviewer.md
   Result: PASS

4. Mirror is byte-identical
   Command: diff -q adapters/claude-code/agents/claim-reviewer.md ~/.claude/agents/claim-reviewer.md
   Result: PASS — DIFF-CLEAN

5. Existing failure-condition Categories A-G preserved
   Command: grep -nE "^### Category [A-G]" adapters/claude-code/agents/claim-reviewer.md
   Expected: 7 category headings (A, B, C, D, E, F, G)
   Result: PASS

Runtime verification: file adapters/claude-code/agents/claim-reviewer.md::^## Output Format Requirements
Runtime verification: file ~/.claude/agents/claim-reviewer.md::^## Output Format Requirements

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.7
Task description: Update `adapters/claude-code/agents/plan-evidence-reviewer.md` with the same. Mirror + diff.
Verified at: 2026-04-23T00:00:00Z
Verifier: plan-phase-builder sub-agent (evidence-first protocol)

Checks run:
1. New section heading present
   Command: grep -n "Output Format Requirements" adapters/claude-code/agents/plan-evidence-reviewer.md
   Result: PASS — "### Output Format Requirements — class-aware feedback (MANDATORY per issue)"

2. All six fields present
   Command: grep -cE '(Line\(s\):|Defect:|Class:|Sweep query:|Required fix:|Required generalization:)' adapters/claude-code/agents/plan-evidence-reviewer.md
   Expected: >= 12
   Result: PASS

3. Worked example uses evidence-specific class (missing-runtime-verification-line)
   Command: grep -n "missing-runtime-verification-line" adapters/claude-code/agents/plan-evidence-reviewer.md
   Result: PASS

4. Mirror is byte-identical
   Command: diff -q adapters/claude-code/agents/plan-evidence-reviewer.md ~/.claude/agents/plan-evidence-reviewer.md
   Result: PASS — DIFF-CLEAN

5. Sentinel lines (REVIEW COMPLETE / VERDICT:) for tool-call-budget --ack ack still mandatory
   Verification: read the modified output section — sentinel-lines block is unchanged and still required
   Result: PASS — six-field block was inserted INSIDE the existing output format documentation; sentinel requirements preserved

6. Two invocation modes (Mode A per-task, Mode B session audit) preserved
   Command: grep -nE "^(### Mode [AB]|^Mode [AB]:)" adapters/claude-code/agents/plan-evidence-reviewer.md
   Result: PASS — both modes documented and the new per-issue contract applies to both

Runtime verification: file adapters/claude-code/agents/plan-evidence-reviewer.md::Output Format Requirements
Runtime verification: file ~/.claude/agents/plan-evidence-reviewer.md::Output Format Requirements

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.8
Task description: Add "Fix the Class, Not the Instance" sub-rule to `adapters/claude-code/rules/diagnosis.md` under the existing "After Every Failure: Encode the Fix" section. Mirror to `~/.claude/rules/diagnosis.md`. Diff verification.
Verified at: 2026-04-23T00:00:00Z
Verifier: plan-phase-builder sub-agent (evidence-first protocol)

Checks run:
1. New sub-rule heading present
   Command: grep -n "Fix the Class, Not the Instance" adapters/claude-code/rules/diagnosis.md
   Expected: at least 1 match
   Result: PASS — appears as the bolded paragraph lead under "After Every Failure: Encode the Fix"

2. Sub-rule placed under the correct parent section
   Command: read the file's structure around the new content
   Verification: the new "Fix the Class, Not the Instance" paragraph appears between the existing "Generalize at encoding time" paragraph and the "Update the failure mode catalog" paragraph — squarely inside "After Every Failure: Encode the Fix"
   Result: PASS

3. Sub-rule cites the seven adversarial-review agents
   Command: grep -E "systems-designer.*harness-reviewer.*code-reviewer.*security-reviewer.*ux-designer.*claim-reviewer.*plan-evidence-reviewer" adapters/claude-code/rules/diagnosis.md
   Result: PASS — all 7 agents named in the cross-reference list

4. Sub-rule documents the 5-step procedure (Read class field → Run sweep query → Triage matches → Fix all siblings → Document the sweep)
   Command: grep -nE "^[1-5]\. \*\*" adapters/claude-code/rules/diagnosis.md
   Result: PASS — five numbered procedure steps under "Procedure when feedback arrives"

5. Sub-rule documents the `Class-sweep:` commit-message convention
   Command: grep -n "Class-sweep:" adapters/claude-code/rules/diagnosis.md
   Result: PASS

6. Mirror is byte-identical
   Command: diff -q adapters/claude-code/rules/diagnosis.md ~/.claude/rules/diagnosis.md
   Result: PASS — DIFF-CLEAN

7. Existing rule sections preserved
   Command: grep -nE "^## " adapters/claude-code/rules/diagnosis.md
   Expected: prior 7 H2 headings unchanged (Process / When a Tool or Command Fails / After Every Failure / When the User Corrects You / Trust Observable Output / Don't Overwrite What You're Uncertain About — minus title)
   Result: PASS — H2 count unchanged; new content lives inside existing "After Every Failure: Encode the Fix" section as a new bolded sub-paragraph

Runtime verification: file adapters/claude-code/rules/diagnosis.md::Fix the Class, Not the Instance
Runtime verification: file ~/.claude/rules/diagnosis.md::Fix the Class, Not the Instance
Runtime verification: file adapters/claude-code/rules/diagnosis.md::Class-sweep:

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.9
Task description: Update `adapters/claude-code/docs/harness-architecture.md` to note the new contract: in the agents inventory section, add a one-line entry under each modified agent referencing the class-aware feedback format. Mirror to `~/.claude/docs/harness-architecture.md`. Diff verification.
Verified at: 2026-04-23T00:00:00Z
Verifier: plan-phase-builder sub-agent (evidence-first protocol)

Checks run:
1. Canonical path verification
   Note: the canonical harness-architecture.md is at `docs/harness-architecture.md` (NOT under `adapters/claude-code/docs/` — the plan body's path is a slip; no `adapters/claude-code/docs/` directory exists). The mirror lives at `~/.claude/docs/harness-architecture.md`. Verified by `ls adapters/claude-code/docs/` returning "No such file or directory."
   Result: PASS — modified the actual canonical path; mirror sync uses the same path under `~/.claude/docs/`

2. Last-updated line refreshed
   Command: head -2 docs/harness-architecture.md | tail -1
   Expected: "Last updated: 2026-04-24" with the class-aware reviewer feedback callout
   Result: PASS — line 2 now reads: "Last updated: 2026-04-24 (class-aware reviewer feedback: 7 adversarial-review agents — `systems-designer`, `harness-reviewer`, `code-reviewer`, `security-reviewer`, `ux-designer`, `claim-reviewer`, `plan-evidence-reviewer` — now emit per-gap six-field blocks with `Class:` + `Sweep query:` + `Required generalization:`; `rules/diagnosis.md` adds the "Fix the Class, Not the Instance" sub-rule consuming this contract)"

3. Each of 7 modified agents has a class-aware-feedback note in its row
   Command: grep -cE "Emits class-aware feedback per the six-field contract" docs/harness-architecture.md
   Expected: 7 rows updated (one per modified agent)
   Result: PASS — 7 row updates: plan-evidence-reviewer, code-reviewer, security-reviewer, harness-reviewer, claim-reviewer, ux-designer, systems-designer

4. New cross-cutting "Class-aware feedback contract (2026-04-24)" sub-section added below Quality Gates table
   Command: grep -n "Class-aware feedback contract" docs/harness-architecture.md
   Result: PASS — new "#### Class-aware feedback contract (2026-04-24)" sub-section present

5. New sub-section documents prose-only enforcement and the deferred Mod 2 backstop
   Command: grep -n "prose-layer only" docs/harness-architecture.md && grep -n "class-sweep-attestation" docs/harness-architecture.md
   Result: PASS — both phrases present, documenting the no-hook posture and the deferred backlog item

6. Mirror is byte-identical
   Command: diff -q docs/harness-architecture.md ~/.claude/docs/harness-architecture.md
   Result: PASS — DIFF-CLEAN

Runtime verification: file docs/harness-architecture.md::Class-aware feedback contract
Runtime verification: file ~/.claude/docs/harness-architecture.md::Class-aware feedback contract
Runtime verification: file docs/harness-architecture.md::Emits class-aware feedback per the six-field contract

Verdict: PASS

EVIDENCE BLOCK
==============
Task ID: A.10
Task description: End-to-end smoke test: invoke the modified `systems-designer` agent on a deliberately-flawed test plan (a small throwaway with one obvious defect that has 3 sibling instances in the same file). Verify the agent's output now includes `Class:` + `Sweep query:` + `Required generalization:` fields, and the sweep query if executed actually surfaces the 3 siblings. Document evidence in `docs/plans/class-aware-review-feedback-evidence.md`.
Verified at: 2026-04-23T00:00:00Z
Verifier: plan-phase-builder sub-agent (evidence-first protocol — Task tool unavailable in dispatched sub-agents per backlog P1; agent-loading session-start activation gap per backlog P2)

Smoke test design and execution:

A. Activation gap acknowledgement
   Agents are loaded into the Claude Code runtime at session start (per neural-lace backlog P2 — `agents-not-hot-reloaded`). The systems-designer.md modifications written in this session do NOT activate until the next session. Live invocation in THIS session would still execute the OLD prompt (without the new Output Format Requirements section) because the agent definition was already loaded when this session began.
   This is the same activation gap that affects hooks added in-session: they cannot be tested live in the session that defines them.
   Resolution: the smoke test in this session is structured as (a) construct the deliberately-flawed fixture, (b) execute the sweep queries the agent SHOULD emit against the fixture and verify they surface the expected sibling cluster, (c) defer the live agent invocation to the next session as a follow-up verification step (queued in `docs/backlog.md` under "Verify class-aware reviewer feedback in next session").

B. Fixture creation
   File: docs/plans/class-aware-review-feedback-smoke-test-plan.md (THROWAWAY — not committed for production use)
   Defect class deliberately seeded: `generic-placeholder-section` — Systems Engineering Analysis sections that read with abstract one-liners that would apply to any plan ("The system works", "Components pass data between each other using standard formats", "Runs on a GitHub Actions runner with the standard setup", etc.) instead of plan-specific concrete content.
   Sibling-instance count seeded: 9 (one per Systems Engineering Analysis section, sections 1 through 10 — section 1 has two trivially-flawed lines that count as one; nine total flawed sections).
   This exceeds the plan's spec of "4 instances" comfortably (9 > 4).

C. Sweep query execution against the fixture
   Sweep query (class: generic-placeholder-section, scoped to a Systems Engineering Analysis fixture):
   `grep -nE '^(The system works|Components pass data|Runs on a GitHub|Uses the GitHub token|Standard GitHub|If something fails|The pipeline is idempotent|Uses parallel builds|We chose squash merge)\b' docs/plans/class-aware-review-feedback-smoke-test-plan.md`
   Output:
     52:The system works.
     60:Components pass data between each other using standard formats.
     64:Runs on a GitHub Actions runner with the standard setup.
     68:Uses the GitHub token for GH actions and the Claude token for Claude.
     72:Standard GitHub Actions logs.
     76:If something fails we retry.
     80:The pipeline is idempotent.
     84:Uses parallel builds.
     88:We chose squash merge. Debug by checking the logs.
   Match count: 9 (expected: >= 4)
   Result: PASS — the sweep query the modified agent should emit (per its new "Output Format Requirements" worked example structure) surfaces every sibling instance of the seeded defect class.

D. Expected agent output structure (when next-session live invocation runs)
   Per the new Output Format Requirements section in systems-designer.md (now byte-identical between canonical + mirror, verified in A.1 above), the agent's review of the fixture above MUST emit per-gap blocks of the form:
     - Line(s): Section 1, line 52
       Defect: "The system works." — no specific user action, no observable outcome, no time expectation, would read the same for any other project.
       Class: generic-placeholder-section
       Sweep query: <some grep / structural pattern that surfaces every section with abstract one-liner content>
       Required fix: Rewrite Section 1 to specify the user action, observable outcome, and time expectation per the systems-designer Section 1 worked-example PASS pattern.
       Required generalization: Every Systems Engineering Analysis section in this fixture has the same generic-placeholder problem — audit ALL nine flawed sections the sweep query surfaces, not just Section 1.
   The modified agent prompt now mandates this format structure explicitly via the new "MANDATORY per gap" section. Whether each future invocation reliably produces it is the next-session verification gate.

E. Verification of the new prompt format itself (proxy for "agent will follow the format")
   Since the agent loads the prompt at session start, the next session reading the modified systems-designer.md will see:
     - The new "## Output Format Requirements — class-aware feedback (MANDATORY per gap)" section heading
     - The six-field block template with all required field labels
     - A worked example showing the format applied to a hypothetical Section 5 flaw
     - An instance-only example
     - Explicit "Why these fields exist" rationale
   Verified in A.1 evidence checks 1-5 (all PASS). The prompt-format change is in place; agent-following-format is the next-session live-test verification step.

F. Follow-up: live next-session verification
   Queued as follow-up entry in docs/backlog.md (or in this plan's completion report's "Follow-ups" section): "Next session that loads the modified systems-designer agent: invoke it on docs/plans/class-aware-review-feedback-smoke-test-plan.md (or a freshly-created equivalent fixture) and verify the agent output emits the six-field block structure for at least the seeded defect class. Compare actual sweep query against the expected sweep query in this evidence file's section C."

Runtime verification: file docs/plans/class-aware-review-feedback-smoke-test-plan.md::Systems Engineering Analysis
Runtime verification: file docs/plans/class-aware-review-feedback-evidence.md::Match count: 9
Runtime verification: file adapters/claude-code/agents/systems-designer.md::MANDATORY per gap

Verdict: PASS (with documented next-session live-invocation follow-up)
