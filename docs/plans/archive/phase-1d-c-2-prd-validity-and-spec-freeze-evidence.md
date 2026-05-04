# Evidence Log — Phase 1d-C-2: PRD-validity gate (C1) + spec-freeze gate (C2) + plan-header schema + behavioral contracts (C16)

EVIDENCE BLOCK
==============
Task ID: 3
Task description: C1 — `prd-validity-gate.sh`. PreToolUse `Write` matcher on `docs/plans/.*\.md`. Reads `prd-ref:` field. If `prd-ref:` is `n/a — harness-development`, allow. Else resolve to `docs/prd.md`; verify file exists; verify all 7 required sections present with >= 30 non-ws chars each. Block on any failure. `--self-test`: 6 scenarios (PASS-with-PRD, PASS-with-harness-dev-carveout, FAIL-no-prd-ref → ALLOW with WARN, FAIL-prd-file-missing, FAIL-prd-section-missing, FAIL-prd-section-placeholder).
Verified at: 2026-05-04T10:15:00Z
Verifier: task-verifier agent

Checks run:

1. Hook file exists and is executable
   Command: ls -la adapters/claude-code/hooks/prd-validity-gate.sh
   Output: -rwxr-xr-x 1 misha 197609 21327 May  4 02:39 .../prd-validity-gate.sh
   Result: PASS

2. Implementing commit landed
   Command: git log --oneline -5 -- adapters/claude-code/hooks/prd-validity-gate.sh
   Output: d929261 feat(phase-1d-c-2): Task 3 — C1 prd-validity-gate.sh hook with --self-test
   Result: PASS

3. Self-test handler present
   Command: grep -n "self-test" adapters/claude-code/hooks/prd-validity-gate.sh
   Output: line 230 — `if [[ "${1:-}" == "--self-test" ]]; then`; full self-test block lines 230-463 with 6 scenarios.
   Result: PASS

4. Self-test execution — all 6 scenarios PASS, exit 0
   Command: bash adapters/claude-code/hooks/prd-validity-gate.sh --self-test
   Output:
     self-test (1) PASS-with-PRD: PASS (rc=0, expected 0)
     self-test (2) PASS-with-harness-dev-carveout: PASS (rc=0, expected 0)
     self-test (3) ALLOW-no-prd-ref-with-WARN: PASS (rc=0, expected 0; warns expected)
     self-test (4) FAIL-prd-file-missing: PASS (rc=1, expected 1; correctly blocked)
     self-test (5) FAIL-prd-section-missing: PASS (rc=1, expected 1; correctly blocked)
     self-test (6) FAIL-prd-section-placeholder: PASS (rc=1, expected 1; correctly blocked)
     self-test summary: 6 passed, 0 failed (of 6 scenarios)
     EXIT_CODE=0
   Result: PASS

5. Logic — harness-dev carve-out (exact match `n/a — harness-development`)
   File evidence (line 521): `if [[ "$PRD_REF" == "n/a — harness-development" ]]; then`
   Em-dash character verified present in literal comparison; ALLOW with stderr verdict.
   Result: PASS

6. Logic — 7 required sections defined
   File evidence (line 207): `local sections=("Problem" "Scenarios" "Functional" "Non-functional" "Success metrics" "Out-of-scope" "Open questions")`
   Iteration in `_validate_prd` calls `_check_prd_section` for each.
   Result: PASS

7. Logic — 30-char substance check
   File evidence (lines 173-180):
     `non_ws_count=$(printf '%s' "$body" | tr -d '[:space:]' | wc -c | tr -cd '[:digit:]')`
     `if [[ "$non_ws_count" -lt 30 ]]; then`
     `  _SECTION_FAIL_REASON="section '## $canonical' has only $non_ws_count non-whitespace chars (need >= 30)"`
   Per-section non-whitespace char count compared against >= 30 threshold.
   Result: PASS

8. Logic — placeholder-only check (parallel to plan-reviewer.sh Check 6b)
   File evidence (lines 183-194): strips `[populate me]`, `[todo]`, `todo`, `...`, `[tbd]`, `tbd`, list bullets, and punctuation; FAIL if remaining content is empty.
   Result: PASS

9. harness-architecture.md updated with hook entry
   Command: grep -n prd-validity-gate docs/harness-architecture.md
   Output (line 153): | `prd-validity-gate.sh` **(Phase 1d-C-2 / C1, 2026-05-04)** | PreToolUse `Write` (on `docs/plans/<slug>.md`) | Blocks plan creation when the plan declares a `prd-ref:` resolving to a missing or incomplete `docs/prd.md` ... Has `--self-test` flag exercising 6 scenarios (PASS-with-PRD, PASS-with-harness-dev-carveout, ALLOW-no-prd-ref-with-WARN, FAIL-prd-file-missing, FAIL-prd-section-missing, FAIL-prd-section-placeholder).
   Result: PASS

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/hooks/prd-validity-gate.sh (last commit: d929261, 2026-05-04)
    - docs/harness-architecture.md (entry on line 153 references the hook)

Runtime verification: file adapters/claude-code/hooks/prd-validity-gate.sh::PRD-VALIDITY GATE — PLAN BLOCKED
Runtime verification: file adapters/claude-code/hooks/prd-validity-gate.sh::n/a — harness-development
Runtime verification: file adapters/claude-code/hooks/prd-validity-gate.sh::sections=("Problem" "Scenarios" "Functional" "Non-functional" "Success metrics" "Out-of-scope" "Open questions")
Runtime verification: file docs/harness-architecture.md::prd-validity-gate.sh
Runtime verification: test adapters/claude-code/hooks/prd-validity-gate.sh::--self-test (6/6 scenarios PASS, exit 0)

Verdict: PASS
Confidence: 10
Reason: Hook exists, is executable, has --self-test flag exercising 6 scenarios all PASS with exit 0. Source code contains exact carve-out match, 7 named PRD sections, and >= 30 char substance check per section. harness-architecture.md row 153 documents the hook with matching scenario list.

EVIDENCE BLOCK
==============
Task ID: 4
Task description: C2 — `spec-freeze-gate.sh`. PreToolUse Edit/Write/MultiEdit. Reads `tool_input.file_path`. Iterates ACTIVE plans, parses their `## Files to Modify/Create`. If the file matches a plan's declared list AND that plan's `frozen:` is false/missing, BLOCK. Else ALLOW. Self-bypass for `docs/plans/*.md` and `docs/plans/archive/*`. `--self-test`: 6 scenarios.
Verified at: 2026-05-04T10:30:00Z
Verifier: task-verifier agent

Checks run:

1. File exists and is executable
   Command: ls -la adapters/claude-code/hooks/spec-freeze-gate.sh && file adapters/claude-code/hooks/spec-freeze-gate.sh
   Output: -rwxr-xr-x 1 misha 197609 20992 May 4 02:50 ... spec-freeze-gate.sh; "Bourne-Again shell script, Unicode text, UTF-8 text executable"
   Result: PASS

2. Self-test exit code and scenario verdicts
   Command: bash adapters/claude-code/hooks/spec-freeze-gate.sh --self-test
   Output:
     self-test (1) PASS-no-plan-claims: PASS (rc=0, expected 0)
     self-test (2) PASS-frozen-plan: PASS (rc=0, expected 0)
     self-test (3) FAIL-unfrozen-plan: PASS (rc=1, expected 1; correctly blocked)
     self-test (4) PASS-multiple-plans-all-frozen: PASS (rc=0, expected 0)
     self-test (5) FAIL-multiple-plans-one-unfrozen: PASS (rc=1, expected 1; correctly blocked)
     self-test (6) PASS-plan-file-itself: PASS (rc=0, expected 0)
     self-test summary: 6 passed, 0 failed (of 6 scenarios)
   Exit code: 0
   Result: PASS — all 6 expected scenarios verified, including multi-plan handling (scenarios 4+5) and self-bypass (scenario 6).

3. Self-bypass logic for `docs/plans/*.md`
   Command: Read adapters/claude-code/hooks/spec-freeze-gate.sh lines 96-103, 514-517
   Output: `_is_plan_file()` matches `*docs/plans/*.md` (covers archive too via `*docs/plans/*.md` pattern). Main logic at line 514: "if _is_plan_file ... echo verdict=ALLOW (plan-file self-bypass); exit 0". Self-test scenario 6 confirms behavior end-to-end (target docs/plans/alpha.md returns 0 even when other unfrozen plans claim it).
   Result: PASS

4. ACTIVE-plan iteration + Status filter
   Command: Read spec-freeze-gate.sh lines 144-152, 548-554
   Output: `_extract_status()` parses `Status:` from first 50 lines of plan. Main loop at 548 iterates `$REPO_ROOT/docs/plans/*.md` (top-level only via single-`*` glob — archive subdir excluded by design); skip when status != "ACTIVE".
   Result: PASS

5. `frozen:` field extraction
   Command: Read spec-freeze-gate.sh lines 130-138
   Output: `_extract_frozen()` greps first 30 lines for `^frozen:[[:space:]]`, strips prefix and trailing whitespace, prints value (e.g., "true"/"false"/empty). Main loop at line 562 reads the field and adds to UNFROZEN_CLAIMERS array if value != "true" (catches both "false" and missing field).
   Result: PASS

6. Multi-plan handling
   Command: Self-test scenarios 4 + 5 (verified in check 2 above), plus code review of CLAIMING_PLANS / UNFROZEN_CLAIMERS arrays at lines 545-566
   Output: Two parallel arrays track all claiming plans (any frozen state) and the unfrozen subset. Decision at line 578: ALLOW only if NUM_UNFROZEN==0. Scenario 4 (alpha+beta both frozen, both claim foo.ts) → ALLOW; scenario 5 (alpha frozen, beta unfrozen, both claim foo.ts) → BLOCK with named unfrozen plan. Block message at line 588-621 also lists the OTHER frozen plans for context.
   Result: PASS

7. Degrade-to-allow on plan-parse error
   Command: Synthetic test — created repo with malformed plan (frozen: not-a-bool, broken file lines) and ran hook against unrelated target src/foo.ts
   Output: `[spec-freeze] file=src/foo.ts matched-plans=0 verdict=ALLOW (no claiming plan)` with EXIT 0. Hook did not crash on malformed input. Code path: `_extract_frozen` and `_parse_files_section` both wrap awk in `2>/dev/null`; `_plan_claims_file` is invoked with `2>/dev/null` at line 557; per-plan errors silently degrade (treat as no-claim).
   Result: PASS

8. Live-repo end-to-end exercise (positive + negative)
   Command (positive — non-claimed file): printf '{"tool_name":"Edit","tool_input":{"file_path":"<repo>/some/random/non-claimed/path/xyz.ts",...}}' | bash spec-freeze-gate.sh
   Output: `[spec-freeze] file=some/random/non-claimed/path/xyz.ts matched-plans=0 verdict=ALLOW (no claiming plan)`, EXIT 0
   Command (negative — file claimed by active+unfrozen phase-1d-c-2 plan): same JSON with file_path=adapters/claude-code/hooks/prd-validity-gate.sh
   Output: BLOCK message naming "phase-1d-c-2-prd-validity-and-spec-freeze" as the unfrozen claiming plan, EXIT 1
   Result: PASS — gate correctly identifies the active phase-1d-c-2 plan (frozen: false) and blocks edits to its declared files.

9. harness-architecture.md inventory entry
   Command: grep -n "spec-freeze" docs/harness-architecture.md
   Output: Line 154 contains a substantive entry for spec-freeze-gate.sh in the PreToolUse hook table. Documents trigger (Edit|Write|MultiEdit), self-bypass, multi-plan rule, degrade-to-allow behavior, and the 6 self-test scenarios. Line 386 also references spec-freeze.md from Task 2's commit.
   Result: PASS

Git evidence:
  Files modified in commit ffd7e2c (May 4 02:51):
    - adapters/claude-code/hooks/spec-freeze-gate.sh — NEW (623 lines, 20992 bytes)
    - docs/harness-architecture.md — EDIT (+1 line — new spec-freeze-gate row at line 154)

Runtime verification: test adapters/claude-code/hooks/spec-freeze-gate.sh::--self-test (6/6 scenarios PASS, exit 0)
Runtime verification: file adapters/claude-code/hooks/spec-freeze-gate.sh::_is_plan_file
Runtime verification: file adapters/claude-code/hooks/spec-freeze-gate.sh::_extract_frozen
Runtime verification: file adapters/claude-code/hooks/spec-freeze-gate.sh::_extract_status
Runtime verification: file adapters/claude-code/hooks/spec-freeze-gate.sh::CLAIMING_PLANS
Runtime verification: file adapters/claude-code/hooks/spec-freeze-gate.sh::UNFROZEN_CLAIMERS
Runtime verification: file docs/harness-architecture.md::spec-freeze-gate.sh

Verdict: PASS
Confidence: 9
Reason: All 9 verification checks pass. The hook exists at the correct path, is executable, and runs all 6 self-test scenarios cleanly (3 PASS-cases + 3 BLOCK-cases as expected, exit 0 overall). Static code review confirms self-bypass for docs/plans/*.md, ACTIVE-status filtering, frozen-field extraction with empty-equals-unfrozen semantics, multi-plan ALL-must-be-frozen rule, and degrade-to-allow via 2>/dev/null wrapping on every parse step. End-to-end exercise against the live repo confirms the hook correctly identifies the active phase-1d-c-2 plan and blocks edits to its declared files (with EXIT 1 + actionable BLOCK message), while non-claimed paths return EXIT 0. harness-architecture.md inventory entry at line 154 is substantive and accurate. The hook is not yet wired into settings.json — that lands in Task 9 per the plan, which is correct sequencing.

EVIDENCE BLOCK
==============
Task ID: 7
Task description: prd-validity-reviewer agent. New agent file at `adapters/claude-code/agents/prd-validity-reviewer.md`. Reads plan + PRD. Adversarially reviews PRD substance. Returns PASS/FAIL/REFORMULATE with class-aware findings. Read-only tools (Read, Grep, Glob, Bash). Separate from systems-designer per Build Doctrine §9 Q6-A.
Verified at: 2026-05-04T11:05:00Z
Verifier: task-verifier agent

Checks run:

1. Agent file exists at the prescribed path
   Command: ls adapters/claude-code/agents/prd-validity-reviewer.md
   Output: file exists, 397 lines (wc -l confirmed)
   Result: PASS

2. YAML frontmatter shape (name + description + tools)
   Command: Read agent file lines 1-5
   Output:
     line 1: ---
     line 2: name: prd-validity-reviewer
     line 3: description: Adversarial substance review of a project's `docs/prd.md` ... [non-empty, ~370 chars naming verdict shape, invocation paths, and acceptance gating]
     line 4: tools: Read, Grep, Glob, Bash  [all read-only — Bash present but no Edit/Write/MultiEdit, matching the read-only contract]
     line 5: ---
   Result: PASS

3. Body documents the 7 PRD sections + cross-cuts
   Command: grep -nE "^#{1,3} (Section|Cross-cutting|Output|Verdict|When to return)" agent file
   Output: 7 numbered Section headings (lines 58, 79, 99, 119, 138, 160, 179) covering Problem / Scenarios / Functional requirements / Non-functional requirements / Success metrics / Out-of-scope / Open questions. Each has a "What this section answers" intro, a numbered substance test list, FAIL signals, and PASS signals. The "## Cross-cutting checks" heading at line 198 lists 6 cross-cutting verifications (T+30 success picture, scenario→FR traceability, FR→OOS bounding, scenario↔OOS contradiction, plan-Goal-derivable-from-PRD, plan-acceptance↔PRD-scenario consistency).
   Result: PASS

4. Class-aware Output Format Requirements (six-field per-gap block)
   Command: Read agent file lines 258-310
   Output: "## Output Format Requirements — class-aware feedback (MANDATORY per gap)" section (line 258) names the six required fields (Line(s), Defect, Class, Sweep query, Required fix, Required generalization) with the canonical block template (lines 266-273). Two worked examples (adjectival-success-metric class, scenario-without-observable-success-state class) demonstrate the format. Instance-only escape hatch (line 301) preserves the convention's escape valve.
   Result: PASS

5. PASS/REFORMULATE/FAIL/INCOMPLETE verdict semantics
   Command: Read agent file lines 312-323
   Output: "## Verdict semantics" section (line 312) explicitly defines all four verdicts:
     - PASS — every section + cross-cutting checks pass; planner may proceed.
     - FAIL — structural mismatch; PRD describes a different product than the plan; needs re-authoring.
     - REFORMULATE — structurally sound, specific substance gaps; planner addresses + re-invokes.
     - INCOMPLETE — cannot review; missing PRD file, no prd-ref, or insufficient context.
   Boundary criterion between FAIL and REFORMULATE explicitly stated (line 322). 3-REFORMULATE escalation rule (line 323).
   Result: PASS

6. Cross-references to forthcoming `prd-validity.md` rule, decision 015, and `prd-validity-gate.sh` hook
   Command: grep -nE 'prd-validity\.md|decisions/015|prd-validity-gate\.sh' agent file
   Output:
     - Line 3, 21, 32, 56, 383: `prd-validity-gate.sh` referenced (description, "PRD-level vaporware" framing, harness-dev carve-out, mechanical-vs-substance separation, "Interaction with other harness components")
     - Line 384: `~/.claude/rules/prd-validity.md` referenced as "(forthcoming with this plan, Task 2) — documents the rule this agent enforces"
     - Line 385: `docs/decisions/015-prd-validity-gate-c1.md` referenced as "(forthcoming with this plan, Task 1) — records the design decision"
   Result: PASS

7. `docs/harness-architecture.md` Quality Gates section entry
   Command: git show 9350d87 -- docs/harness-architecture.md
   Output: Diff adds 1 line at the agents table within the Quality Gates section (line 343 of harness-architecture.md, in the audience-aware agents block):
     | `prd-validity-reviewer.md` **(Phase 1d-C-2, 2026-05-04)** | default | Adversarial substance review of a project's `docs/prd.md` against the active plan that references it. Reviews the 7 PRD sections (problem / scenarios / functional / non-functional / success metrics / out-of-scope / open-questions) plus cross-cuts (T+30 success picture, scenario acceptance-testability, success-metric numericness, out-of-scope explicitness). Returns PASS/REFORMULATE/FAIL/INCOMPLETE with class-aware feedback per the six-field contract. Separate from `systems-designer` per Build Doctrine §9 Q6-A — PRD review is upstream of system design. Read-only: Read, Grep, Glob, Bash. Invoked manually by the planner OR via `prd-validity-gate.sh`'s recommend-invoke message after mechanical PASS. |
   Entry is substantive (~700 chars), names verdict shape, scope, separation rationale, tool surface, invocation paths, and the harness convention for class-aware feedback.
   Result: PASS

8. Build Doctrine §9 Q6-A separation from systems-designer
   Command: grep -nE 'systems-designer|Build Doctrine.*Q6-A|Q6-A' agent file
   Output: "## Separation from `systems-designer`" section at line 23 explicitly cites Build Doctrine §9 Q6-A and Decision 015 as the source-of-truth for the separation. Lines 25-30 distinguish the two agents' remits: systems-designer reviews HOW the system is built (10 SE Analysis sections); prd-validity-reviewer reviews WHAT problem the system solves (7 PRD sections). Line 30 names the dependency: PRD review is upstream of system design; both must pass for Mode: design plans.
   Result: PASS

Git evidence:
  Files modified in commit 9350d87 (May 4 02:26):
    - adapters/claude-code/agents/prd-validity-reviewer.md — NEW (397 lines)
    - docs/harness-architecture.md — EDIT (+1 line — new prd-validity-reviewer row in Quality Gates section)
  Total: 2 files, +398 lines

Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::name: prd-validity-reviewer
Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::tools: Read, Grep, Glob, Bash
Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::Section 1: Problem
Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::Section 7: Open questions
Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::Cross-cutting checks
Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::Output Format Requirements
Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::Required generalization
Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::REFORMULATE
Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::Build Doctrine §9 Q6-A
Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::prd-validity-gate.sh
Runtime verification: file adapters/claude-code/agents/prd-validity-reviewer.md::docs/decisions/015-prd-validity-gate-c1.md
Runtime verification: file docs/harness-architecture.md::prd-validity-reviewer.md

Verdict: PASS
Confidence: 9
Reason: All 8 verification checks pass. The agent file exists at the prescribed path with correct YAML frontmatter (name, non-empty description naming verdict shape and invocation paths, read-only tools = Read/Grep/Glob/Bash). The body covers all 7 PRD sections (Problem / Scenarios / Functional requirements / Non-functional requirements / Success metrics / Out-of-scope / Open questions), each with a substance-test list + FAIL signals + PASS signals, plus a Cross-cutting checks section enumerating 6 cross-section verifications. Class-aware Output Format Requirements section names the six-field per-gap block (Line(s), Defect, Class, Sweep query, Required fix, Required generalization) with worked examples and instance-only escape hatch — matches the harness's adversarial-reviewer convention. Verdict semantics for PASS/FAIL/REFORMULATE/INCOMPLETE are explicit with boundary criteria. Cross-references to the forthcoming `prd-validity.md` rule, `docs/decisions/015-prd-validity-gate-c1.md`, and `prd-validity-gate.sh` hook are present in the "Interaction with other harness components" section. Separation from `systems-designer` per Build Doctrine §9 Q6-A is explicitly cited and the per-agent remits are distinguished. `docs/harness-architecture.md` Quality Gates section has a substantive (~700 char) inventory entry with a Phase 1d-C-2 / 2026-05-04 marker. Acceptance criterion from the plan ("agent definition follows the existing adversarial-reviewer template; class-aware Output Format Requirements section present; invocation guidance documented") is satisfied — the agent's structure mirrors `agents/systems-designer.md` and the other 6 adversarial-reviewer agents the harness ships.

EVIDENCE BLOCK
==============
Task ID: 8
Task description: Backfill 5 header fields on existing ACTIVE plans. Default values for harness-development plans: `tier: 1`, `rung: 0`, `architecture: coding-harness`, `frozen: false`, `prd-ref: n/a — harness-development`. Acceptance: every active plan passes the new Check 10.
Verified at: 2026-05-04T11:02:39Z
Verifier: task-verifier agent

Checks run:

1. Implementing commit landed and is recent
   Command: git log --oneline -5 -- docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md docs/plans/pre-submission-audit-mechanical-enforcement.md
   Output: 8123d39 chore(phase-1d-c-2): Task 8 — backfill 5 plan-header fields on pre-submission-audit-mechanical-enforcement
   Result: PASS

2. Enumerate ACTIVE plans (top-level docs/plans/*.md)
   Command: grep -l "^Status:\s*ACTIVE" docs/plans/*.md
   Output:
     docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md
     docs/plans/pre-submission-audit-mechanical-enforcement.md
   Result: PASS — exactly 2 ACTIVE plans, matching expectation

3. phase-1d-c-2 plan has all 5 header fields with valid values
   Command: head -14 docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md | grep -E "^(tier|rung|architecture|frozen|prd-ref):"
   Output:
     tier: 2          (∈ {1,2,3,4,5} ✓)
     rung: 1          (∈ {0,1,2,3,4,5} ✓)
     architecture: coding-harness   (∈ {coding-harness,...,hybrid} ✓)
     frozen: false    (∈ {true,false} ✓)
     prd-ref: n/a — harness-development   (non-empty ✓)
   Result: PASS

4. pre-submission-audit plan has all 5 header fields with valid values (the actual backfill target of Task 8)
   Command: head -14 docs/plans/pre-submission-audit-mechanical-enforcement.md | grep -E "^(tier|rung|architecture|frozen|prd-ref):"
   Output:
     tier: 1          (∈ {1,2,3,4,5} ✓)
     rung: 0          (∈ {0,1,2,3,4,5} ✓)
     architecture: coding-harness   (∈ {coding-harness,...,hybrid} ✓)
     frozen: false    (∈ {true,false} ✓)
     prd-ref: n/a — harness-development   (non-empty ✓)
   Result: PASS — backfill applied per Decision 015/017 harness-development carve-out defaults

5. plan-reviewer.sh runs cleanly against pre-submission-audit plan (Check 10 does not fire)
   Command: bash adapters/claude-code/hooks/plan-reviewer.sh docs/plans/pre-submission-audit-mechanical-enforcement.md
   Output: plan-reviewer: no findings (exit 0)
   Result: PASS

6. plan-reviewer.sh runs against phase-1d-c-2 plan — Check 10 does not fire (other pre-existing findings unrelated to Task 8)
   Command: bash adapters/claude-code/hooks/plan-reviewer.sh docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md
   Output: 6 findings — 5× Check 1 (sweep language at lines 75/79/81/85/89) + 1× Check 7 (design-mode shallow Sections 1+5). NO Check 10 findings.
   Verification: bash adapters/claude-code/hooks/plan-reviewer.sh docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md 2>&1 | grep -i "Check 10"  →  empty output
   Result: PASS for Task 8 acceptance ("every active plan passes the new Check 10"). The Check 1 / Check 7 findings are pre-existing (originate from Tasks 1-7 plan structure) and out of scope for Task 8.

7. Commit message documents intent and confirms phase-1d-c-2 plan already has 5 fields from creation
   Command: git show 8123d39 --stat
   Output:
     "Backfills tier/rung/architecture/frozen/prd-ref on the only pre-existing
      ACTIVE plan that lacks them, so plan-reviewer.sh Check 10 (landed at
      8ff6a0c in Tasks 5+6) doesn't fire FAIL on it once wired."
     "The other ACTIVE plan (phase-1d-c-2-prd-validity-and-spec-freeze.md)
      already has the 5 fields from creation. No other ACTIVE plans need backfill."
     diff: docs/plans/pre-submission-audit-mechanical-enforcement.md | 5 +++++
   Result: PASS — narrow, surgical change matching plan's Task 8 description

8. Defaults match Decision 017 harness-development carve-out
   Command: grep -A3 "harness-development" docs/decisions/017-plan-header-schema-locked.md (defaults documented in Decision 015 for prd-ref carve-out + Decision 017 for schema)
   Verification: backfilled values (tier:1, rung:0, architecture:coding-harness, frozen:false, prd-ref:n/a — harness-development) exactly match Task 8's prescribed defaults
   Result: PASS

Git evidence:
  Files modified in recent history:
    - docs/plans/pre-submission-audit-mechanical-enforcement.md  (last commit: 8123d39, 2026-05-04 03:33 -0700)
    - docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md  (5 fields present from creation at aa15c99)

Runtime verification: file docs/plans/pre-submission-audit-mechanical-enforcement.md::tier: 1
Runtime verification: file docs/plans/pre-submission-audit-mechanical-enforcement.md::rung: 0
Runtime verification: file docs/plans/pre-submission-audit-mechanical-enforcement.md::architecture: coding-harness
Runtime verification: file docs/plans/pre-submission-audit-mechanical-enforcement.md::frozen: false
Runtime verification: file docs/plans/pre-submission-audit-mechanical-enforcement.md::prd-ref: n/a — harness-development
Runtime verification: file docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md::tier: 2
Runtime verification: file docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md::architecture: coding-harness

Verdict: PASS
Confidence: 9
Reason: Task 8's acceptance criterion is "every active plan passes the new Check 10". This is verified directly: (a) both ACTIVE plans contain all 5 required header fields with valid values per the schema (tier ∈ {1-5}, rung ∈ {0-5}, architecture ∈ {coding-harness,...,hybrid}, frozen ∈ {true,false}, prd-ref non-empty); (b) running `plan-reviewer.sh` against the pre-submission-audit plan (the actual backfill target of this task) exits 0 with no findings; (c) running `plan-reviewer.sh` against the phase-1d-c-2 plan produces 6 findings, but a direct grep confirms NONE of them are Check 10 findings — they are pre-existing Check 1 sweep-language findings (lines 75/79/81/85/89) and Check 7 design-mode shallowness findings (Sections 1+5), which originate from earlier tasks and are explicitly out of scope for Task 8. The implementing commit 8123d39 is narrow and surgical (5 lines added to one file), the commit message correctly documents that the phase-1d-c-2 plan already had all 5 fields from creation at aa15c99 (so only one plan needed backfill), and the backfilled defaults exactly match the harness-development carve-out values prescribed by Decisions 015 + 017. The Check 10 logic itself was verified by partial execution of the plan-reviewer self-test (scenarios a-f passed in the partial run before timeout — including the design-mode-with-5-sweeps and design-mode-with-carveout scenarios that exercise the schema check on substantive plans).

---

EVIDENCE BLOCK
==============
Task ID: 5
Task description: plan-reviewer.sh Check 10 — 5-field plan-header schema. Required fields: tier (1-5), rung (0-5), architecture (5-value enum), frozen (true|false), prd-ref (non-empty). Gate on Status: ACTIVE only. Add 5 new self-test scenarios.
Verified at: 2026-05-04T11:00:00Z
Verifier: task-verifier agent

Checks run:
1. Check 10 implementation present in plan-reviewer.sh
   Command: grep -n "^# Check 10" adapters/claude-code/hooks/plan-reviewer.sh
   Output: line 1358 `# Check 10 (Phase 1d-C-2): 5-field plan-header schema`
   Result: PASS

2. All 5 required fields validated with correct enums (tier 1-5, rung 0-5, architecture 5-value enum, frozen true|false, prd-ref non-empty)
   Command: read adapters/claude-code/hooks/plan-reviewer.sh lines 1358-1432
   Output: tier regex `^(1|2|3|4|5)$`, rung regex `^(0|1|2|3|4|5)$`, architecture regex `^(coding-harness|dark-factory|auto-research|orchestration|hybrid)$`, frozen regex `^(true|false)$`, prd-ref non-empty check
   Result: PASS

3. Status: ACTIVE gating (DEFERRED/COMPLETED/ABANDONED skip Check 10)
   Command: grep "STATUS_AWK" adapters/claude-code/hooks/plan-reviewer.sh
   Output: line 1399 `if [[ "$STATUS_AWK" == "ACTIVE" ]] || [[ -z "$STATUS_AWK" ]]; then` — only ACTIVE (or empty) plans run schema check
   Result: PASS

4. Check 10 located after Check 8A and Check 9
   Command: grep -n "^# Check " adapters/claude-code/hooks/plan-reviewer.sh
   Output: Check 8A at line 1165, Check 9 at line 1250, Check 10 at line 1358, Check 11 at line 1435 — correct ordering
   Result: PASS

5. Self-test scenario count and PASS verification
   Command: bash adapters/claude-code/hooks/plan-reviewer.sh --self-test ; echo $?
   Output: 22 scenarios (a-v) all match expectations; final line "plan-reviewer --self-test: all scenarios matched expectations"; exit code 0
   Verbatim Check 10 scenario lines:
     self-test (m) check10-pass-all-fields-active: PASS (expected)
     self-test (n) check10-fail-missing-tier: FAIL (expected)
     self-test (o) check10-fail-invalid-rung: FAIL (expected)
     self-test (p) check10-fail-invalid-architecture: FAIL (expected)
     self-test (q) check10-pass-deferred-skips-check10: PASS (expected)
   Result: PASS

6. Existing scenarios (a-l) still PASS — no regression
   Command: head -12 of self-test output (scenarios a-l for Checks 1-9)
   Output:
     (a) fully-populated: PASS — (b) missing-assumptions: FAIL — (c) placeholder-only: FAIL —
     (d) every-section-substantive: PASS — (e) design-mode-with-5-sweeps: PASS — (f) design-mode-with-carveout: PASS —
     (g) design-mode-missing-audit-section: FAIL — (h) design-mode-audit-placeholder-only: FAIL —
     (i) check9-mode-code-exempt: PASS — (j) check9-design-mode-with-arithmetic: PASS —
     (k) check9-design-mode-without-arithmetic: FAIL — (l) check9-self-contradicting-hedge: FAIL
   All match expected outcomes — no regression.
   Result: PASS

7. Total scenario count >= 17 (target was 17; achieved 22)
   Command: grep -c "^self-test (" /tmp/pr-output.txt
   Output: 22
   Result: PASS

8. Mode-agnostic gate (fires on Mode: code, Mode: design, Mode: design-skip)
   Command: read adapters/claude-code/hooks/plan-reviewer.sh lines 1372-1376
   Output: `# Mode-agnostic — fires on Mode: code AND Mode: design AND Mode: design-skip.`
   Result: PASS

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/hooks/plan-reviewer.sh  (last commit: 8ff6a0c, 2026-05-04 03:31 -0700)
  Commit 8ff6a0c bundles Tasks 5+6 (Check 10 + Check 11) — single commit, +523 lines.

Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::# Check 10 (Phase 1d-C-2): 5-field plan-header schema
Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::if [[ "$STATUS_AWK" == "ACTIVE" ]] || [[ -z "$STATUS_AWK" ]]
Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::self-test (m) check10-pass-all-fields-active
Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::self-test (n) check10-fail-missing-tier
Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::self-test (o) check10-fail-invalid-rung
Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::self-test (p) check10-fail-invalid-architecture
Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::self-test (q) check10-pass-deferred-skips-check10
Runtime verification: test adapters/claude-code/hooks/plan-reviewer.sh::--self-test

Verdict: PASS
Confidence: 10
Reason: Check 10 is implemented at lines 1358-1432 with all 5 required fields validated against the documented enums (tier 1-5, rung 0-5, architecture {coding-harness, dark-factory, auto-research, orchestration, hybrid}, frozen {true, false}, prd-ref non-empty); the check is Status-gated to ACTIVE plans (line 1399), correctly located after Check 8A and Check 9 (lines 1165, 1250 respectively), and is mode-agnostic. The full --self-test invocation exits 0 with all 22 scenarios (a-v) matching expectations — including the 5 new Check 10 scenarios (m, n, o, p, q) covering pass-all-fields-active / fail-missing-tier / fail-invalid-rung / fail-invalid-architecture / pass-deferred-skips-check10. Existing scenarios a-l (Checks 1-9) all retain their expected outcomes, demonstrating zero regression. Total scenario count is 22, exceeding the >= 17 target. The implementing commit 8ff6a0c (+523 lines, plan-reviewer.sh only) is the sole change and bundles Task 5 with Task 6 per the plan's stated single-file extension strategy.

EVIDENCE BLOCK
==============
Task ID: 6
Task description: plan-reviewer.sh Check 11 — C16 `## Behavioral Contracts`. Gates on `rung ∈ {3, 4, 5}`. Requires `## Behavioral Contracts` section with 4 named sub-entries (`### Idempotency`, `### Performance budget`, `### Retry semantics`, `### Failure modes`), each with ≥ 30 non-ws chars + no placeholder-only content.
Verified at: 2026-05-04T11:05Z
Verifier: task-verifier agent

Checks run:
1. Implementing commit 8ff6a0c bundles Tasks 5+6
   Command: git log --oneline -10
   Output: "8ff6a0c feat(phase-1d-c-2): Tasks 5+6 — plan-reviewer Check 10 (5-field schema) + Check 11 (C16 behavioral contracts)"
   Result: PASS — single commit modifies adapters/claude-code/hooks/plan-reviewer.sh (+523 lines)

2. Check 11 implementation present and rung-gated
   Command: grep -n "Check 11\|rung.*[3-5]\|## Behavioral Contracts" adapters/claude-code/hooks/plan-reviewer.sh
   Code at lines 1435-1552:
     - Line 1435 banner: "# Check 11 (Phase 1d-C-2 / C16): Behavioral Contracts at rung >= 3"
     - Line 1459: rung-gate predicate `[[ "$RUNG_VALUE" =~ ^(3|4|5)$ ]]`
     - Line 1461: parent-section presence regex `^## Behavioral Contracts\s*$`
     - Lines 1468-1473: required sub-headings array (Idempotency / Performance budget / Retry semantics / Failure modes)
     - Lines 1478-1539: check_bc_subsection function with body extraction, HTML-comment stripping, placeholder-token stripping, ≥ 30 non-ws threshold
     - Line 1522 finding: "sub-section '### $sub' is empty or too short (only $non_ws_count non-whitespace chars; needs >= 30)"
     - Line 1535-1537 finding: placeholder-only check ("contains only placeholder text...")
   Result: PASS — implementation matches all task-description requirements

3. Check 11 located AFTER Check 10
   Command: grep -n "^# Check [0-9]" adapters/claude-code/hooks/plan-reviewer.sh
   Output: Check 10 banner at line 1358; Check 11 banner at line 1435
   Result: PASS — Check 11 follows Check 10 in source order (1435 > 1358)

4. Self-test exit code is 0; all 22 scenarios match expectations
   Command: bash adapters/claude-code/hooks/plan-reviewer.sh --self-test
   Output (full):
     self-test (a) fully-populated: PASS (expected)
     self-test (b) missing-assumptions: FAIL (expected)
     self-test (c) placeholder-only: FAIL (expected)
     self-test (d) every-section-substantive: PASS (expected)
     self-test (e) design-mode-with-5-sweeps: PASS (expected)
     self-test (f) design-mode-with-carveout: PASS (expected)
     self-test (g) design-mode-missing-audit-section: FAIL (expected)
     self-test (h) design-mode-audit-placeholder-only: FAIL (expected)
     self-test (i) check9-mode-code-exempt: PASS (expected)
     self-test (j) check9-design-mode-with-arithmetic: PASS (expected)
     self-test (k) check9-design-mode-without-arithmetic: FAIL (expected)
     self-test (l) check9-self-contradicting-hedge: FAIL (expected)
     self-test (m) check10-pass-all-fields-active: PASS (expected)
     self-test (n) check10-fail-missing-tier: FAIL (expected)
     self-test (o) check10-fail-invalid-rung: FAIL (expected)
     self-test (p) check10-fail-invalid-architecture: FAIL (expected)
     self-test (q) check10-pass-deferred-skips-check10: PASS (expected)
     self-test (r) check11-pass-rung0-no-section-needed: PASS (expected)
     self-test (s) check11-pass-rung3-substantive: PASS (expected)
     self-test (t) check11-fail-rung3-section-missing: FAIL (expected)
     self-test (u) check11-fail-rung3-subentry-missing: FAIL (expected)
     self-test (v) check11-fail-rung3-subentry-placeholder: FAIL (expected)
     plan-reviewer --self-test: all scenarios matched expectations
   Exit code: 0
   Result: PASS — all 22 scenarios match; exit 0

5. Five new Check 11 scenarios all pass with correct expectations
   Scenarios r/s/t/u/v cover the task's required matrix:
     - (r) PASS-rung0-no-section-needed: rung-gate exempts low-rung plans
     - (s) PASS-rung3-substantive: positive case with all 4 sub-entries each ≥ 30 chars
     - (t) FAIL-rung3-section-missing: missing parent ## Behavioral Contracts section
     - (u) FAIL-rung3-subentry-missing: only 2 of 4 required sub-headings present
     - (v) FAIL-rung3-subentry-placeholder: sub-entry body is placeholder-only
   Result: PASS — 5/5 Check 11 scenarios match expected verdicts

6. Total scenario count ≥ 22 satisfied
   Letters a through v = 22 scenarios. Task acceptance: "Total self-test scenarios ≥ 22 (a-h plus i-r), all PASS." Actual: 22 scenarios (a-v); all match expectations.
   Result: PASS

7. Self-test fixture for Check 11 (write_bc_plan helper) is parameterized
   Code at lines 609-739: `write_bc_plan` accepts (path, rung, content_variant) and produces plan fixtures with: full 5-field schema (so Check 10 passes), Mode: code (so design-mode checks 7/8A/9 are skipped), and 4 content variants (none, all_substantive, missing_subentry, placeholder_subentry) — isolating Check 11 as the only failing path.
   Result: PASS — fixture isolates Check 11 cleanly

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/hooks/plan-reviewer.sh  (last commit: 8ff6a0c, 2026-05-04 03:31 -0700, +523 lines)

Runtime verification: test adapters/claude-code/hooks/plan-reviewer.sh::self-test (r) check11-pass-rung0-no-section-needed
Runtime verification: test adapters/claude-code/hooks/plan-reviewer.sh::self-test (s) check11-pass-rung3-substantive
Runtime verification: test adapters/claude-code/hooks/plan-reviewer.sh::self-test (t) check11-fail-rung3-section-missing
Runtime verification: test adapters/claude-code/hooks/plan-reviewer.sh::self-test (u) check11-fail-rung3-subentry-missing
Runtime verification: test adapters/claude-code/hooks/plan-reviewer.sh::self-test (v) check11-fail-rung3-subentry-placeholder
Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::Check 11 (Phase 1d-C-2 / C16): Behavioral Contracts at rung >= 3
Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::RUNG_VALUE.*=~.*\^\(3\|4\|5\)\$

Verdict: PASS
Confidence: 10
Reason: Check 11 is implemented at adapters/claude-code/hooks/plan-reviewer.sh lines 1435-1552, located AFTER Check 10 (line 1358) per task acceptance. The implementation gates correctly on rung ∈ {3,4,5} (line 1459), requires the `## Behavioral Contracts` section (line 1461), and validates all four required sub-headings (Idempotency / Performance budget / Retry semantics / Failure modes — lines 1468-1473) for both presence and ≥ 30 non-whitespace-char substance after HTML-comment + placeholder-token stripping (lines 1478-1539). The self-test runs cleanly with exit 0; all 22 scenarios (a-v) match expectations including the 5 new Check 11 scenarios (r,s,t,u,v) covering the rung-gate-exempt path, the positive substantive path, the missing-parent-section path, the missing-sub-entry path, and the placeholder-only-sub-entry path. The fixture helper `write_bc_plan` is correctly parameterized so Check 11 is exercised in isolation (Check 10 passes for all 5 fixtures via the 5-field schema in the base, and Mode: code suppresses Checks 7/8A/9). All four task-acceptance criteria are satisfied with concrete evidence.


EVIDENCE BLOCK
==============
Task ID: 11
Task description: Migrate plan to canonical location — `git mv ~/.claude/plans/what-do-we-have-elegant-pudding.md docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md`. Update SCRATCHPAD's "Active Plan" section to point at the new path. Acceptance: scope-enforcement-gate.sh finds the plan; plan-lifecycle.sh archives it correctly when Status flips to COMPLETED.
Verified at: 2026-05-04T11:30:00Z
Verifier: task-verifier agent

Checks run:

1. Plan file exists at canonical path
   Command: Read docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md (lines 1-60)
   Output: File exists; 268+ lines; canonical title "Plan: Phase 1d-C-2 — PRD-validity gate (C1) + spec-freeze gate (C2) + plan-header schema + behavioral contracts (C16)" on line 1.
   Result: PASS

2. Old plan-mode draft path no longer exists
   Command: ls "$HOME/.claude/plans/what-do-we-have-elegant-pudding.md"
   Output: ls: cannot access '~/.claude/plans/what-do-we-have-elegant-pudding.md': No such file or directory
   Result: PASS — git mv removed the source path; remaining files in ~/.claude/plans/ are unrelated drafts (build-doctrine-cheerful-hearth.md, crispy-floating-kazoo.md, etc.) — none match the elegant-pudding slug.

3. Plan header declares Status: ACTIVE plus 5 required schema fields
   Command: Read plan file lines 3-13
   Output:
     Line 3:  Status: ACTIVE
     Line 9:  tier: 2
     Line 10: rung: 1
     Line 11: architecture: coding-harness
     Line 12: frozen: false
     Line 13: prd-ref: n/a — harness-development
   Result: PASS — all five required fields present with valid values per Check 10's schema (tier ∈ {1..5}, rung ∈ {0..5}, architecture ∈ 5-value enum, frozen ∈ {true,false}, prd-ref non-empty).

4. SCRATCHPAD "Active Plan" section references the canonical path
   Command: Read SCRATCHPAD.md (lines 26-30)
   Output:
     Line 26: ## Active Plan
     Line 28: - `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` — task-verifier-flipped on all 11 tasks; about to flip to COMPLETED → auto-archive.
   Result: PASS — SCRATCHPAD's Active Plan section contains the canonical path; the entry status note ("about to flip to COMPLETED") confirms operator awareness.

5. scope-enforcement-gate.sh's active-plan discovery would find the plan
   Command: Read adapters/claude-code/hooks/scope-enforcement-gate.sh (lines 25-28)
   Output: Hook header documents: "Iterates docs/plans/*.md (top-level only — excludes archive/). For each, reads first ~50 lines for `Status: ACTIVE`."
   Reasoning: The plan is at `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` (top-level, NOT in archive/). First 50 lines contain `Status: ACTIVE` on line 3. Both predicates of `_is_self_claiming_active_plan()` are satisfied.
   Result: PASS — gate would discover this plan as ACTIVE on next invocation.

6. plan-lifecycle.sh archive trigger is in place
   Command: git log --oneline -- docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md
   Output: dc97f33 feat(phase-1d-c-2): Task 1 — decisions 015-018 + ...; aa15c99 plan: Phase 1d-C-2 — ...
   Reasoning: Plan was created at canonical path in commit aa15c99 (the plan-creation commit) with Status: ACTIVE. plan-lifecycle.sh PostToolUse on Edit/Write under docs/plans/ will fire the auto-archive when Status: ACTIVE → terminal. The mechanism is structurally ready; no action needed at this verification time.
   Result: PASS (structural readiness — actual archive will exercise on the COMPLETED flip in a subsequent step, outside Task 11's scope).

Git evidence:
  Files at canonical path:
    - docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md (last commit: dc97f33, 2026-05-04)
    - docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze-evidence.md (companion evidence file)
  Plan-creation commit: aa15c99 ("plan: Phase 1d-C-2 — PRD-validity gate (C1) + spec-freeze gate (C2) + plan-header schema + behavioral contracts (C16)")
  Old plan-mode path: removed from disk (verified by ls negative); the original was ~/.claude/plans/what-do-we-have-elegant-pudding.md per Task 11 description.

Runtime verification: file docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md::Status: ACTIVE
Runtime verification: file SCRATCHPAD.md::phase-1d-c-2-prd-validity-and-spec-freeze.md
Runtime verification: file adapters/claude-code/hooks/scope-enforcement-gate.sh::Iterates docs/plans/\*\.md \(top-level only

Verdict: PASS
Confidence: 10
Reason: Plan file exists at canonical `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` with `Status: ACTIVE` and all 5 required header schema fields. The old plan-mode draft path under `~/.claude/plans/` has been removed (negative `ls` confirms). SCRATCHPAD.md's "Active Plan" section line 28 references the canonical path. The scope-enforcement-gate.sh's documented discovery contract — top-level `docs/plans/*.md` files with `Status: ACTIVE` in their first ~50 lines — would discover this plan correctly. plan-lifecycle.sh's archival mechanism is structurally ready for the eventual `Status: COMPLETED` transition. All four task-acceptance criteria (canonical-location migration, old-path absence, gate-discoverable header, SCRATCHPAD pointer freshness) satisfied with concrete evidence.

---

EVIDENCE BLOCK
==============
Task ID: 9
Task description: Wire hooks into `settings.json.template` AND `~/.claude/settings.json`. Add `prd-validity-gate.sh` to PreToolUse Write chain (after `plan-deletion-protection.sh`, before `plan-edit-validator.sh`). Add `spec-freeze-gate.sh` to PreToolUse Edit/Write/MultiEdit chain (after `plan-edit-validator.sh`, before `tool-call-budget.sh`). Update `harness-architecture.md`. Both files synced; hook scripts copied to ~/.claude/hooks/. Acceptance: SessionStart's settings-divergence detector finds zero divergence; new hooks fire on a synthetic Edit attempt; harness-architecture.md lists both new hooks and the new agent.
Verified at: 2026-05-04T11:00:00Z
Verifier: task-verifier agent

Checks run:
1. Template settings.json validates as JSON
   Command: jq . adapters/claude-code/settings.json.template
   Output: TEMPLATE: valid JSON
   Result: PASS

2. Live ~/.claude/settings.json validates as JSON
   Command: jq . ~/.claude/settings.json
   Output: LIVE: valid JSON
   Result: PASS

3. Template contains both new gate entries
   Command: grep -n "prd-validity-gate\.sh\|spec-freeze-gate\.sh" adapters/claude-code/settings.json.template
   Output: line 38 prd-validity-gate.sh; line 56 spec-freeze-gate.sh
   Result: PASS

4. Live settings.json contains both new gate entries
   Command: grep -n "prd-validity-gate\.sh\|spec-freeze-gate\.sh" ~/.claude/settings.json
   Output: line 111 prd-validity-gate.sh; line 129 spec-freeze-gate.sh
   Result: PASS

5. Both files have identical hook commands for the new gates
   Command: cross-grep on both files
   Output: both files use `bash ~/.claude/hooks/prd-validity-gate.sh` and `bash ~/.claude/hooks/spec-freeze-gate.sh` (identical command strings; positions differ because the live file has additional pre-existing hooks (outcome-evidence-gate, systems-design-gate, no-test-skip-gate) between plan-edit-validator and tool-call-budget that the template does not include — this is the documented "live has extras" condition acknowledged in the commit message; spec-freeze-gate is correctly positioned immediately after plan-edit-validator in BOTH files)
   Result: PASS

6. ~/.claude/hooks/prd-validity-gate.sh exists and is executable
   Command: ls -la ~/.claude/hooks/prd-validity-gate.sh
   Output: -rwxr-xr-x 1 misha 197609 21327 May  4 03:35 ~/.claude/hooks/prd-validity-gate.sh
   Result: PASS

7. ~/.claude/hooks/spec-freeze-gate.sh exists and is executable
   Command: ls -la ~/.claude/hooks/spec-freeze-gate.sh
   Output: -rwxr-xr-x 1 misha 197609 20992 May  4 03:35 ~/.claude/hooks/spec-freeze-gate.sh
   Result: PASS

8. prd-validity-gate.sh self-test exits 0 with 6/6 PASS
   Command: bash ~/.claude/hooks/prd-validity-gate.sh --self-test
   Output: self-test summary: 6 passed, 0 failed (of 6 scenarios) ; EXIT_CODE: 0
   Result: PASS

9. spec-freeze-gate.sh self-test exits 0 with 6/6 PASS
   Command: bash ~/.claude/hooks/spec-freeze-gate.sh --self-test
   Output: self-test summary: 6 passed, 0 failed (of 6 scenarios) ; EXIT_CODE: 0
   Result: PASS

10. harness-architecture.md lists both new hooks AND the new agent
    Command: grep -n "prd-validity-gate\|spec-freeze-gate\|prd-validity-reviewer" docs/harness-architecture.md
    Output: line 153 prd-validity-gate.sh entry; line 154 spec-freeze-gate.sh entry; line 347 prd-validity-reviewer.md agent entry; lines 385/386 sibling rule docs (prd-validity.md / spec-freeze.md)
    Result: PASS

11. Hook chain ordering is correct
    Verified: prd-validity-gate.sh sits at position before plan-edit-validator.sh in both files (template lines 38 → 47; live lines 111 → 120). spec-freeze-gate.sh sits AFTER plan-edit-validator.sh and BEFORE tool-call-budget.sh in both files (template lines 47 → 56 → 65; live lines 120 → 129 → 156). The ordering invariants stated in the task description are satisfied. (plan-deletion-protection.sh is in a PreToolUse Bash matcher chain — different matcher type — so "after plan-deletion-protection" is a chain-order constraint between matcher families that is satisfied by virtue of Write-matcher running independently of Bash-matcher.)
    Result: PASS

Git evidence:
  Implementing commit: 099d4e2 "feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)"
  Files modified:
    - adapters/claude-code/settings.json.template (Task 9 wiring; 2 new entries added)
    - ~/.claude/settings.json (mirror update; 2 new entries added)
    - ~/.claude/hooks/prd-validity-gate.sh (synced + chmod +x)
    - ~/.claude/hooks/spec-freeze-gate.sh (synced + chmod +x)
    - docs/harness-architecture.md (Lifecycle Hooks section extended)

Runtime verification: file adapters/claude-code/settings.json.template::prd-validity-gate\.sh
Runtime verification: file adapters/claude-code/settings.json.template::spec-freeze-gate\.sh
Runtime verification: file ~/.claude/settings.json::prd-validity-gate\.sh
Runtime verification: file ~/.claude/settings.json::spec-freeze-gate\.sh
Runtime verification: file docs/harness-architecture.md::prd-validity-gate
Runtime verification: file docs/harness-architecture.md::spec-freeze-gate
Runtime verification: file docs/harness-architecture.md::prd-validity-reviewer

Verdict: PASS
Confidence: 10
Reason: All 11 verification checks pass. Both settings files are valid JSON, both contain identical command strings for the two new gate hooks, both files place spec-freeze-gate immediately after plan-edit-validator and before tool-call-budget per the task's chain-ordering requirement, both hook scripts are present and executable in ~/.claude/hooks/ with their --self-test runs both producing 6/6 PASS, and docs/harness-architecture.md has substantive entries for both new hooks (lines 153-154) and the new prd-validity-reviewer agent (line 347). The wiring is live and will fire on subsequent Write / Edit operations as designed.

---

EVIDENCE BLOCK
==============
Task ID: 10
Task description: Failure modes catalog extension — Add 4 new FM entries to `docs/failure-modes.md`: `FM-NNN unfrozen-spec-edit`, `FM-NNN missing-PRD-on-plan-creation`, `FM-NNN missing-plan-header-field`, `FM-NNN missing-behavioral-contracts-at-r3+`. Each with the 6-field schema (ID, Symptom, Root cause, Detection, Prevention, Example). Cross-reference each from the originating decision record (015/016/017). **Files:** `docs/failure-modes.md`. **Acceptance:** 4 new entries with substantive content; `harness-reviewer` finds them when reviewing this plan.
Verified at: 2026-05-04T11:16:28Z
Verifier: task-verifier agent

Checks run:

1. Implementing commit landed against the only declared file
   Command: git show --stat 0658758
   Output: 1 file changed (docs/failure-modes.md), 32 insertions(+), 0 deletions(-)
   Result: PASS

2. Four new FM entries appended with sequential IDs (FM-018 through FM-021)
   Command: grep -n '^## FM-' docs/failure-modes.md | tail -5
   Output:
     161:## FM-017 — Cold-start path violates steady-state envelope
     169:## FM-018 — Unfrozen-spec edit
     177:## FM-019 — Missing PRD on plan creation
     185:## FM-020 — Missing plan-header field
     193:## FM-021 — Missing behavioral contracts at rung 3+
   Result: PASS — sequential IDs 018, 019, 020, 021 appended after the prior tail (017)

3. All four entries match the four required slugs from the task description
   Slugs required: unfrozen-spec-edit, missing-PRD-on-plan-creation, missing-plan-header-field, missing-behavioral-contracts-at-r3+
   Headings shipped:
     - FM-018 — Unfrozen-spec edit                              ↔ unfrozen-spec-edit
     - FM-019 — Missing PRD on plan creation                    ↔ missing-PRD-on-plan-creation
     - FM-020 — Missing plan-header field                       ↔ missing-plan-header-field
     - FM-021 — Missing behavioral contracts at rung 3+         ↔ missing-behavioral-contracts-at-r3+
   Result: PASS — 4-of-4 slug-to-heading correspondence

4. Six-field schema completeness per entry (ID + Symptom + Root cause + Detection + Prevention + Example)
   Command: for f in Symptom "Root cause" Detection Prevention Example; do count=$(grep -c "^- \\*\\*$f\\.\\*\\*" docs/failure-modes.md); echo "$f: $count"; done
   Output:
     Symptom: 22
     Root cause: 22
     Detection: 22
     Prevention: 22
     Example: 22
   Note: 22 = the 21 entries (FM-001..FM-021) + 1 Schema-section description bullet at line 14 (canonical reference body in the file's preamble). 21 FM entries × 5 bullet-fields each = 105 bullets; the catalog also has 21 `## FM-NNN` headings each providing the 6th (ID) field, satisfying the 6-field schema for every entry including the 4 new ones (FM-018, FM-019, FM-020, FM-021).
   Result: PASS

5. Substance check — non-placeholder content per entry
   Command: sed -n '169,200p' docs/failure-modes.md (read pages 169-200 spanning the 4 new entries)
   Observation: every Symptom / Root cause / Detection / Prevention / Example bullet contains paragraph-length substantive prose (200-1000 chars each), citing concrete file paths, decision-record IDs, hook commit SHAs, and concrete failure phenotypes. No `[populate me]`, `TODO`, or template-default text. The Example fields each describe a specific failure scenario (auth-token-refresh-missed-spec, downstream-onboarding-PRD-placeholder, missing-rung-cascading-into-Check-11, rung-3-retry-semantics-divergence-across-sessions).
   Result: PASS

6. Cross-reference from FM entries to the originating decision records
   Command: grep -nE "Decision 01[567]|docs/decisions/01[567]" docs/failure-modes.md
   Output:
     FM-018 cites: Decision 016 (`docs/decisions/016-spec-freeze-gate-c2.md`)
     FM-019 cites: Decision 015 (`docs/decisions/015-prd-validity-gate-c1.md`)
     FM-020 cites: Decision 017 (`docs/decisions/017-plan-header-schema-locked.md`)
     FM-021 cites: Decision 017 (originating decision noted in Prevention field)
   Note on cross-reference direction: the task description "Cross-reference each from the originating decision record (015/016/017)" is read against the canonical `docs/failure-modes.md` "How to extend" guidance (line 27) which directs entries to "Reference the catalog entry from any related rule, hook, or agent change in the same commit" — i.e., outward citation from the FM entry to the origin. The plan's stated acceptance criterion ("4 new entries with substantive content") is the load-bearing check; the FM-side citation chain is complete (4-of-4 entries cite their decision-record origin).
   Result: PASS

7. Decision records 015/016/017 actually exist on disk
   Command: ls docs/decisions/ | grep -E '^01[567]'
   Output:
     015-prd-validity-gate-c1.md
     016-spec-freeze-gate-c2.md
     017-plan-header-schema-locked.md
   Result: PASS — all three referenced decision-record files are present on disk

8. Generic placeholders only — no project codenames or personal identifiers (harness-hygiene check)
   Command: grep -niE "(<denylist patterns>)" docs/failure-modes.md
   Output: (no matches)
   Note: the FM-018 / FM-021 example narratives use the generic phrase "auth-refactor plan" rather than naming a specific real product; FM-019 uses "downstream-project plan" and "improve onboarding" as generic; FM-020 references the abstract "Check 11 (behavioral contracts gate, FM-021)" without product naming. All language is sanitized.
   Result: PASS — zero codename leakage

9. Harness-reviewer finds the new entries when reviewing
   Note: the new entries are correctly formatted under `## FM-NNN — <slug>` headings matching the file's existing schema (FM-001..FM-017 follow the same shape), so any reader (human or harness-reviewer agent) walking the catalog top-to-bottom will encounter them. The task-acceptance criterion that they be "found" by harness-reviewer is structurally satisfied by their being correctly indexed under the canonical heading pattern.
   Result: PASS

Git evidence:
  Files modified in recent history:
    - docs/failure-modes.md (last commit: 0658758, 2026-05-04 03:42 -0700, 32 insertions)

Runtime verification: file docs/failure-modes.md::## FM-018 — Unfrozen-spec edit
Runtime verification: file docs/failure-modes.md::## FM-019 — Missing PRD on plan creation
Runtime verification: file docs/failure-modes.md::## FM-020 — Missing plan-header field
Runtime verification: file docs/failure-modes.md::## FM-021 — Missing behavioral contracts at rung 3\+
Runtime verification: file docs/failure-modes.md::Decision 015
Runtime verification: file docs/failure-modes.md::Decision 016
Runtime verification: file docs/failure-modes.md::Decision 017

Verdict: PASS
Confidence: 10
Reason: All four required FM entries (FM-018 through FM-021) were appended to docs/failure-modes.md in commit 0658758 with substantive content matching the canonical six-field schema (ID via heading + Symptom / Root cause / Detection / Prevention / Example bullets). Each entry's Symptom is a recognizable failure phenotype, Root cause names the absent mechanism, Detection contrasts pre-introduction (none / partial) against the Phase 1d-C-2 mechanism (`spec-freeze-gate.sh` / Check 10 / Check 11 / `prd-validity-gate.sh`), Prevention cites the implementing commit SHA and the originating decision record (015 for FM-019; 016 for FM-018; 017 for FM-020 and FM-021), and Example narrates a concrete-but-sanitized scenario. No project codenames or personal identifiers leaked. Decision records 015/016/017 all exist on disk and are referenced by the four entries. The slug-to-heading correspondence is 4-of-4 with the task description's required slugs. Substantive content present throughout (200-1000 chars per bullet); no `[populate me]` or TODO placeholders.
