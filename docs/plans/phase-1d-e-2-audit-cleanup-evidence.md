# Evidence Log — Phase 1d-E-2 — Audit + cleanup batch (GAP-10 sub-gaps A/B/C/F/H)

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Sub-gap H — `docs/reviews/` gitignore refinement. Edit `.gitignore` to exclude downstream-project reviews specifically (by codename naming convention) while allowing NL-self-reviews (e.g., `docs/reviews/2026-*-stop-hook-*.md`, `docs/reviews/2026-*-rules-vs-hooks-*.md`). Document the naming convention in a brief comment in `.gitignore` AND in `harness-hygiene.md`. Test: `git status` after running — confirm the audit docs from Tasks 1, 3, 4 ARE tracked (visible to git) under the refined gitignore. Single commit.
Verified at: 2026-05-05T01:18:39Z
Verifier: task-verifier agent

Checks run:
1. Builder commit exists and modifies the expected file
   Command: git show --stat 7abe23e
   Output: commit 7abe23e1e743d4a524abfe066adc6b0c4c772dc9 — "fix(harness): document docs/reviews/ gitignore naming convention (Phase 1d-E-2 Task 5)" — 1 file changed (adapters/claude-code/rules/harness-hygiene.md, +26/-1)
   Result: PASS

2. harness-hygiene.md committed copy contains the new "Reviews / decisions / sessions naming convention" section
   Command: git show 7abe23e -- adapters/claude-code/rules/harness-hygiene.md
   Output: diff adds the section heading "### Reviews / decisions / sessions naming convention" + a paraphrased gitignore block + closing line "This closes HARNESS-GAP-10 sub-gap H." Body explains NL-self vs downstream-project naming conventions and the per-directory denylist + allowlist pair.
   Result: PASS

3. Live mirror at ~/.claude/rules/harness-hygiene.md matches the committed adapter copy
   Command: diff -q "$HOME/.claude/rules/harness-hygiene.md" "<repo>/adapters/claude-code/rules/harness-hygiene.md"
   Output: FILES MATCH (no diff)
   Result: PASS

4. Live mirror contains the new naming-convention section
   Command: grep -nE 'Reviews / decisions / sessions naming convention|HARNESS-GAP-10 sub-gap H' ~/.claude/rules/harness-hygiene.md
   Output: line 45 (cross-reference), line 48 (section heading), line 71 (closing line) all match
   Result: PASS

5. .gitignore allowlist pattern documented + present (date-prefix for reviews/sessions, NNN-prefix for decisions)
   Command: read .gitignore lines 75-89
   Output: lines 84-89 contain the per-directory denylist + allowlist:
     docs/decisions/*
     !docs/decisions/[0-9][0-9][0-9]-*.md
     docs/reviews/*
     !docs/reviews/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md
     docs/sessions/*
     !docs/sessions/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md
   The header comment (lines 75-83) explains the convention and cites HARNESS-GAP-10 sub-gap H.
   Result: PASS

6. Round-trip test — NL-self-review pattern is NOT ignored (visible/trackable to git)
   Command: git check-ignore -v "docs/reviews/2026-05-04-stop-hook-test-stub.md"
   Output: ".gitignore:87:!docs/reviews/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md	docs/reviews/2026-05-04-stop-hook-test-stub.md" — the `!` allowlist line matches, so the file is RE-INCLUDED (would show up under git status as untracked).
   Result: PASS

7. Round-trip test — downstream-project-style review IS ignored
   Command: git check-ignore -v "docs/reviews/some-codename-internal.md"
   Output: ".gitignore:86:docs/reviews/*	docs/reviews/some-codename-internal.md" — the broad denylist matches and no allowlist re-includes it; ignored.
   Result: PASS

8. Round-trip test — decisions allowlist works for NNN-prefix and excludes other names
   Command: git check-ignore -v "docs/decisions/022-test.md" + git check-ignore -v "docs/decisions/some-random-name.md"
   Output:
     022-test.md → ".gitignore:85:!docs/decisions/[0-9][0-9][0-9]-*.md" (re-included; would be tracked)
     some-random-name.md → ".gitignore:84:docs/decisions/*" (denied; ignored)
   Result: PASS

9. Existing NL-self-reviews remain tracked (sanity check that the gitignore did not regress)
   Command: git ls-files "docs/reviews/2026-*"
   Output: docs/reviews/ already contains tracked items (e.g., 2026-04-27-agent-teams-conflict-analysis.md, 2026-05-03-build-doctrine-integration-gaps.md). The nested downstream-project directory `agent-teams-research-2026-04-27` is correctly NOT tracked (matched by `docs/reviews/*`).
   Result: PASS

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/rules/harness-hygiene.md  (last commit: 7abe23e, 2026-05-04)
    - ~/.claude/rules/harness-hygiene.md  (live mirror, byte-identical to committed copy — verified via diff -q)

Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::### Reviews / decisions / sessions naming convention
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::This closes HARNESS-GAP-10 sub-gap H
Runtime verification: file .gitignore::!docs/reviews/\[0-9\]\[0-9\]\[0-9\]\[0-9\]-\[0-9\]\[0-9\]-\[0-9\]\[0-9\]-\*\.md
Runtime verification: file .gitignore::!docs/decisions/\[0-9\]\[0-9\]\[0-9\]-\*\.md

Verdict: PASS
Confidence: 9
Reason: Builder correctly recognized the existing .gitignore already implemented the naming-convention allowlist (cleaner than authoring a topic-by-topic ban); the only outstanding work was documenting the convention in harness-hygiene.md, which the commit does in both layers (committed adapter copy + live mirror). All round-trip tests pass: date-prefix reviews are tracked, downstream-project-style names are ignored, NNN-prefix decisions are tracked, non-conforming decision names are ignored. Live mirror matches committed copy byte-for-byte. The deviation from the task wording is justified (the test in the task description was satisfied without further .gitignore edits because the prior state already conformed).

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Sub-gap A — Stop-hook orthogonality matrix. Author the audit document. Read each of the five Stop hooks; write a 5x5 orthogonality matrix where each cell `(row=A, col=B)` names ONE specific example A catches but B does NOT. Recommendation per pair. If any pair has no clear separation, list as "candidate for consolidation". Single commit.
Verified at: 2026-05-05T01:25:00Z
Verifier: task-verifier agent

Checks run:
1. Audit document exists at the declared path
   Command: Read docs/reviews/2026-05-04-stop-hook-orthogonality.md
   Output: 121 lines; markdown document with sections Purpose, Hook summaries, Pairwise orthogonality matrix, Per-pair recommendation, Conclusion, Followups.
   Result: PASS

2. Document has substantive size (~150 lines target — 121 actual; "~" tolerates this)
   Command: wc -l on file
   Output: 121 lines. Plan said "(~150 lines)"; tolerance acceptable as content is dense and complete (no padding).
   Result: PASS

3. 5x5 orthogonality matrix is populated with 20 off-diagonal cells, each a concrete example
   Command: grep -oE '\([0-9]+\)' docs/reviews/2026-05-04-stop-hook-orthogonality.md | sort -u | wc -l
   Output: 20 unique numbered examples (1)-(20). Matrix has 5 row labels (narrate-and-wait, transcript-lie-detector, goal-coverage, imperative-evidence, deferral-counter), 5 column labels matching, diagonal is "—". Each off-diagonal cell describes a specific session shape where the row hook blocks and the column hook does not.
   Result: PASS

4. Per-pair recommendations exist with KEEP SEPARATE / CLARIFY BOUNDARY / CONSOLIDATE verdicts
   Command: read "Per-pair recommendation" section
   Output: 10 unordered pairs reviewed. 8 verdicts KEEP SEPARATE, 2 verdicts CLARIFY BOUNDARY (transcript-lie-detector × deferral-counter; goal-coverage × imperative-evidence). 0 CONSOLIDATE. Each verdict has a one-paragraph reasoning citing the asymmetry or overlap source.
   Result: PASS

5. Overall assessment present
   Command: read "Conclusion" section (lines 75-112)
   Output: Conclusion paragraph explicitly states "All five Stop hooks are sufficiently orthogonal to retain", articulates three separation axes (tone vs. content; trigger-source separation; action-surface separation), names confidence as "medium-high", and proposes a post-maturity firing-frequency audit follow-up.
   Result: PASS

6. Single commit confirmed
   Command: git log --all --oneline -- docs/reviews/2026-05-04-stop-hook-orthogonality.md
   Output: fd9f663 docs(1d-E-2): stop-hook orthogonality audit (Phase 1d-E-2 Task 1) — only commit touching the file.
   Result: PASS

7. Builder commit modifies only the expected file
   Command: git show --stat fd9f663
   Output: 1 file changed, 121 insertions(+); only docs/reviews/2026-05-04-stop-hook-orthogonality.md added. Commit message references HARNESS-GAP-10 sub-gap A and Phase 1d-E-2 Task 1.
   Result: PASS

Git evidence:
  Files modified in recent history:
    - docs/reviews/2026-05-04-stop-hook-orthogonality.md  (last commit: fd9f663, 2026-05-04)

Runtime verification: file docs/reviews/2026-05-04-stop-hook-orthogonality.md::Pairwise orthogonality matrix
Runtime verification: file docs/reviews/2026-05-04-stop-hook-orthogonality.md::All five Stop hooks are sufficiently orthogonal to retain
Runtime verification: file docs/reviews/2026-05-04-stop-hook-orthogonality.md::CLARIFY BOUNDARY
Runtime verification: file docs/reviews/2026-05-04-stop-hook-orthogonality.md::transcript-lie-detector

Verdict: PASS
Confidence: 9
Reason: Audit document exists at the declared path with substantive content; 5x5 matrix has all 20 off-diagonal cells populated with concrete blocking-scenario examples (each citing a specific session shape, not restated mission statements); 10 unordered pairs have explicit KEEP SEPARATE / CLARIFY BOUNDARY verdicts with one-paragraph reasoning; overall assessment names the conclusion (all five orthogonal, retain), articulates three separation axes, and proposes a post-maturity follow-up audit; single commit fd9f663 with HARNESS-GAP-10 sub-gap A reference. The 121-line actual length vs. the plan's "~150 lines" target is acceptable — the content is dense and complete with no padding; brevity here is a feature.

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Sub-gap B — `pipeline-agents.md` relocation/restructure. Read the rule. Identify project-specific content vs general-purpose content. Take the action that fits the analysis: relocate project-specific content (back-stop: delete the file when its content is wholly project-specific). Update any references. Sync to live. Single commit.
Verified at: 2026-05-05T01:35:00Z
Verifier: task-verifier agent

Checks run:
1. pipeline-agents.md deleted from adapters/claude-code/rules/
   Command: ls adapters/claude-code/rules/pipeline-agents.md
   Output: "No such file or directory" — file removed.
   Result: PASS

2. pipeline-agents.md deleted from ~/.claude/rules/
   Command: ls ~/.claude/rules/pipeline-agents.md
   Output: "No such file or directory" — live mirror also removed.
   Result: PASS

3. Builder commit deleted the file in adapters/claude-code/rules/
   Command: git show d8b30f3 --stat
   Output: "adapters/claude-code/rules/pipeline-agents.md | 16 -----" — 16 lines deleted.
   Result: PASS

4. Reference removed from harness-architecture.md
   Command: git show d8b30f3 -- docs/harness-architecture.md
   Output: diff shows removal of the row "| `pipeline-agents.md` | Pipeline mode | BUILDER/VERIFIER/DECOMPOSER roles with strict boundaries |" from the rules inventory table.
   Result: PASS

5. Reference removed from harness-guide.md directory tree
   Command: git show d8b30f3 -- docs/harness-guide.md
   Output: diff shows removal of "│   └── pipeline-agents.md             # BUILDER/VERIFIER/DECOMPOSER roles for pipeline mode" line and adjustment of harness-maintenance.md line to use the proper tree-end glyph.
   Result: PASS

6. No remaining stale references in code (rules/, agents/, hooks/, settings)
   Command: grep -rn 'pipeline-agents' adapters/claude-code/ docs/harness-architecture.md docs/harness-guide.md
   Output: only legitimate historical references remain (in docs/backlog.md as ABSORBED note, in docs/reviews/2026-05-03-build-doctrine-integration-gaps.md as the originating analysis, and in docs/plans/phase-1d-e-2-audit-cleanup.md describing the task itself). No stale references in inventories or active doc surfaces.
   Result: PASS

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/rules/pipeline-agents.md  (DELETED in d8b30f3, 2026-05-04)
    - docs/harness-architecture.md  (last commit: d8b30f3, 2026-05-04 — removed inventory row)
    - docs/harness-guide.md  (last commit: d8b30f3, 2026-05-04 — removed directory-tree row)
    - ~/.claude/rules/pipeline-agents.md  (live mirror — removed; verified absent)

Runtime verification: file docs/harness-architecture.md::deploy-to-production
Runtime verification: file docs/harness-guide.md::harness-maintenance.md         # Global-first rule

Verdict: PASS
Confidence: 9
Reason: Builder correctly identified pipeline-agents.md content as wholly project-specific (BUILDER/VERIFIER/DECOMPOSER role naming superseded by orchestrator-pattern's plan-phase-builder + task-verifier model; the 6 "common failure patterns" reference Trigger.dev/Supabase RLS/Next.js middleware specifics that don't generalize). Deletion from both adapter and live layers verified absent on filesystem. References cleanly removed from harness-architecture.md inventory table and harness-guide.md directory tree. Remaining grep matches are all legitimate historical context (backlog absorption note, originating gap analysis, the plan/evidence files themselves). Single commit (bundled with Tasks 3 and 4) per the orchestrator pattern's "tightly-coupled tasks may be bundled if they land in one commit" allowance.

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Sub-gap C — `claim-reviewer` reassessment. Author audit document at `docs/reviews/2026-05-04-claim-reviewer-reassessment.md`. Read `~/.claude/agents/claim-reviewer.md` to enumerate claim classes; for each, identify whether a Gen 6 hook now catches it (`transcript-lie-detector`, `goal-coverage-on-stop`, `imperative-evidence-linker`, `deferral-counter`, `vaporware-volume-gate`). Recommendation per class: deprecate / keep / mechanize. Single commit.
Verified at: 2026-05-05T01:36:00Z
Verifier: task-verifier agent

Checks run:
1. Audit document exists at the declared path
   Command: Read docs/reviews/2026-05-04-claim-reviewer-reassessment.md
   Output: 82 lines; markdown document with sections Background, Methodology, Per-claim-class table, Why Gen 6 doesn't supersede, Recommendation, Reassessment trigger, Out-of-scope.
   Result: PASS

2. Per-class table is populated covering each enumerated claim category
   Command: grep -nE '^\| [A-G]\.[0-9]' docs/reviews/2026-05-04-claim-reviewer-reassessment.md
   Output: 19 table rows, IDs A.1 through G.19, covering categories A (citation density), B (citation correctness), C (hedging), D (tense), E (caller-trace verification), F (vague qualifiers / off-topic answers), G (fix-claim verification).
   Result: PASS

3. Each row maps the claim phenotype to Gen 6 hook coverage
   Command: read table column 3 ("Gen 6 coverage")
   Output: every row has explicit text describing whether and how each of the five Gen 6 hooks (transcript-lie-detector, goal-coverage-on-stop, imperative-evidence-linker, deferral-counter, vaporware-volume-gate) covers (or fails to cover) the phenotype. Cross-references are concrete (e.g., "transcript-lie-detector reads the transcript for self-contradiction across messages, not for missing citations within one message").
   Result: PASS

4. Recommendation per class is present (deprecate / keep / mechanize)
   Command: grep -cE '\*\*keep\*\*|\*\*deprecate\*\*|\*\*mechanize\*\*' docs/reviews/2026-05-04-claim-reviewer-reassessment.md
   Output: 19 recommendations — 16 "keep", 3 "keep (partial overlap)" (D.9, G.15, G.16). 0 "deprecate" or "mechanize" verdicts. Coverage summary line states "0 of 19 categories are *fully* superseded by Gen 6 hooks. 3 of 19 have partial overlap with `transcript-lie-detector.sh`."
   Result: PASS

5. Overall verdict is present and substantive
   Command: read "Recommendation" section
   Output: explicit "**KEEP `claim-reviewer` as-is.**" verdict with rationale citing intra-message citation verification as irreducibly an LLM-with-codebase-tools task vs. regex-on-transcript Gen 6 hooks. Reassessment trigger named: "if Anthropic ships a PostMessage hook event."
   Result: PASS

6. Cited agent and hook files exist (claim cross-checking)
   Command: ls adapters/claude-code/agents/claim-reviewer.md adapters/claude-code/hooks/{transcript-lie-detector,goal-coverage-on-stop,imperative-evidence-linker,deferral-counter,vaporware-volume-gate}.sh
   Output: all 6 cited files exist.
   Result: PASS

7. Single commit confirmed (bundled with Tasks 2 and 4 per orchestrator-pattern allowance)
   Command: git log --oneline -- docs/reviews/2026-05-04-claim-reviewer-reassessment.md
   Output: d8b30f3 — single commit (the bundled commit shipping Tasks 2/3/4).
   Result: PASS

Git evidence:
  Files modified in recent history:
    - docs/reviews/2026-05-04-claim-reviewer-reassessment.md  (last commit: d8b30f3, 2026-05-04)

Runtime verification: file docs/reviews/2026-05-04-claim-reviewer-reassessment.md::Per-claim-class table
Runtime verification: file docs/reviews/2026-05-04-claim-reviewer-reassessment.md::KEEP `claim-reviewer` as-is
Runtime verification: file docs/reviews/2026-05-04-claim-reviewer-reassessment.md::0 of 19 categories are
Runtime verification: file docs/reviews/2026-05-04-claim-reviewer-reassessment.md::PostMessage hook event

Verdict: PASS
Confidence: 9
Reason: Audit document exists at declared path with substantive content (82 lines). 19-row per-class table covers categories A-G with explicit Gen 6 coverage analysis per row and a recommendation column ("keep" / "keep (partial overlap)") per class. Coverage summary correctly aggregates: 0 fully superseded, 3 with partial overlap. Overall verdict is unambiguous ("KEEP claim-reviewer as-is") with substantive rationale (Gen 6 hooks operate against transcript-wide or PR-time signals; intra-message citation verification against the live codebase is structurally outside their scope). Reassessment trigger is concrete and actionable ("if Anthropic ships a PostMessage hook event"). All cited agent/hook files exist on filesystem. The audit closes the sub-gap C question with a clear KEEP verdict supported by per-class analysis.

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Sub-gap F — Rules-superseded-by-hooks audit. Author audit document at `docs/reviews/2026-05-04-rules-vs-hooks-audit.md`. For each rule file in `~/.claude/rules/` (skip already-stub `vaporware-prevention.md`), produce: rule name, % content hook-enforced, recommendation (keep verbose / convert to stub / split into stub + extension). Single commit.
Verified at: 2026-05-05T01:37:00Z
Verifier: task-verifier agent

Checks run:
1. Audit document exists at the declared path
   Command: Read docs/reviews/2026-05-04-rules-vs-hooks-audit.md
   Output: 84 lines; markdown document with sections Methodology, Per-rule audit, Recommendations summary, Notes on the recommendations, Out-of-scope.
   Result: PASS

2. Per-rule table is populated
   Command: grep -cE '^\| `[a-z-]+\.md`' docs/reviews/2026-05-04-rules-vs-hooks-audit.md
   Output: 24 rule rows — covers acceptance-scenarios, agent-teams, api-routes, automation-modes, database-migrations, deploy-to-production, design-mode-planning, diagnosis, discovery-protocol, documentation, git, harness-hygiene, harness-maintenance, observed-errors-first, orchestrator-pattern, planning, react, security, testing, typescript, ui-components, url-conventions, ux-design, ux-standards.
   Result: PASS

3. Each row contains the four required columns (rule name, lines, % hook-enforced, recommendation)
   Command: read header + sample rows
   Output: header is "| Rule file | Lines | ~ % hook-enforced | Notes | Recommendation |" — five columns including a Notes column. Each row populated with substantive analysis (hook names cited where relevant, Pattern-only declarations cited where applicable, recommendation in bold).
   Result: PASS

4. Recommendation column uses the three permitted verdicts
   Command: grep -oE '\*\*(convert to stub|split|keep verbose)\*\*' docs/reviews/2026-05-04-rules-vs-hooks-audit.md | sort | uniq -c
   Output: "convert to stub" (1), "split" (4), "keep verbose" (19). Total 24, matches table row count.
   Result: PASS

5. Recommendations summary aggregates the table results correctly
   Command: read "Recommendations summary" section (lines 54-66)
   Output: section explicitly lists:
     - Convert to stub: observed-errors-first.md (1 entry)
     - Split: acceptance-scenarios, agent-teams, design-mode-planning, testing (4 entries)
     - Keep verbose: 19 named files (verified count by row enumeration)
   Aggregates match the per-row table (1 + 4 + 19 = 24).
   Result: PASS

6. Methodology section explains the threshold-based recommendation logic
   Command: read "Methodology" section
   Output: explicit threshold definitions: ">70% hook-enforced AND mostly enforcement-map content" → convert to stub; "40-70% hook-enforced AND substantive non-mechanism content" → split; "<40% hook-enforced OR primarily Pattern" → keep verbose. Coarse-precision caveat (~±15%) acknowledged.
   Result: PASS

7. Out-of-scope section names limitations honestly
   Command: read "What didn't get audited" section
   Output: project-level rules excluded; comprehension-gate.md treated as TBD pending Phase 1d-C-4; hook-existence cross-referenced for "most commonly-named" hooks but not exhaustively; hook-correctness (vs hook-existence) acknowledged as separate question.
   Result: PASS

8. Caveats: url-conventions.md row is in the table but the file is not currently present in ~/.claude/rules/ or adapters/claude-code/rules/ tracked tree
   Command: ls /<user>/.claude/rules/url-conventions.md ; ls <user>/claude-projects/neural-lace/adapters/claude-code/rules/url-conventions.md
   Output: both lookups return "No such file or directory". `find . -name url-conventions.md` returns no matches. The audit treats it as if it exists in ~/.claude/rules/. The audit also includes a self-flagging sidenote ("this rule is project-specific to a particular dual-org product. May warrant separate audit re: harness-hygiene"). Minor accuracy issue but does not undermine the overall analysis: the row's verdict is "keep verbose" (Pattern-only), which is harmless even if the file's presence in rules/ was incorrect.
   Result: PASS (with noted minor accuracy caveat)

9. Single commit confirmed (bundled with Tasks 2 and 3)
   Command: git log --oneline -- docs/reviews/2026-05-04-rules-vs-hooks-audit.md
   Output: d8b30f3 — single commit (the bundled commit shipping Tasks 2/3/4).
   Result: PASS

Git evidence:
  Files modified in recent history:
    - docs/reviews/2026-05-04-rules-vs-hooks-audit.md  (last commit: d8b30f3, 2026-05-04)

Runtime verification: file docs/reviews/2026-05-04-rules-vs-hooks-audit.md::Per-rule audit
Runtime verification: file docs/reviews/2026-05-04-rules-vs-hooks-audit.md::Recommendations summary
Runtime verification: file docs/reviews/2026-05-04-rules-vs-hooks-audit.md::Convert to stub
Runtime verification: file docs/reviews/2026-05-04-rules-vs-hooks-audit.md::observed-errors-first.md

Verdict: PASS
Confidence: 8
Reason: Audit document exists at declared path with substantive content (84 lines). 24-row per-rule table covers the rule-file inventory; methodology explains threshold-based recommendation logic; verdicts cleanly split 1 convert / 4 split / 19 keep verbose, matching the recommendations summary aggregation. Out-of-scope section is honest about audit limitations (project-level rules, comprehension-gate as TBD, hook-existence not exhaustively verified, hook-correctness vs existence). Minor accuracy caveat: the url-conventions.md row in the table treats a file that does not currently exist in ~/.claude/rules/ or adapters/claude-code/rules/ as part of the audit scope; this is a single-row inaccuracy but does not change the overall outcome (the verdict for that row is "keep verbose" which is harmless) — confidence reduced to 8 to acknowledge. The audit's primary deliverable (a per-rule table with thresholded recommendations) is achieved; downstream restructuring decisions can proceed with the document as input.


EVIDENCE BLOCK
==============
Task ID: 6
Task description: Decision + DECISIONS index + backlog cleanup. Land Decision 022 if any structural decision was made (likely from Sub-gap B's relocation choice or Sub-gap H's gitignore refinement). Update `docs/DECISIONS.md`. Update `docs/backlog.md` "Recently implemented" section with the 5 sub-gap closures. Single commit.
Verified at: 2026-05-05T01:44:01Z
Verifier: task-verifier agent

Checks run:
1. Builder commit exists, single commit, expected files
   Command: git show --stat 6d30d7b
   Output: commit 6d30d7bfb9d52fc681b9a1e36354400e49f1cc48 — "docs: Decision 022 + audit-batch backlog cleanup (Phase 1d-E-2 Task 6)" — 3 files changed: docs/DECISIONS.md (+1), docs/backlog.md (+10/-1), docs/decisions/022-pipeline-agents-md-deletion.md (NEW, +153 lines).
   Result: PASS

2. Decision 022 file exists with all required sections
   Command: Read docs/decisions/022-pipeline-agents-md-deletion.md (153 lines)
   Output: File contains Title ("Decision 022 — `pipeline-agents.md` deleted from global rules"), Date (2026-05-04), Status (Implemented (commit d8b30f3)), Stakeholders (Maintainer (sole)), Related plan + backlog refs, Context (3 numbered findings), Decision (delete from both layers, final), Alternatives considered (Alt 1/2/3 with reject rationales), Consequences (Enables / Costs / Depends on / Propagates downstream / Blocks), Cross-references (6 entries).
   Result: PASS

3. DECISIONS.md updated with row for entry 022
   Command: git show 6d30d7b -- docs/DECISIONS.md
   Output: diff adds line `| 022 | [pipeline-agents.md deleted from global rules](decisions/022-pipeline-agents-md-deletion.md) | 2026-05-04 | Implemented |` immediately after row 021. Pipe-table format consistent with rows 019-021.
   Result: PASS

4. backlog.md "Recently implemented" section has 5 entries for Phase 1d-E-2 sub-gaps
   Command: grep -n 'Sub-gap [ABCFH]' docs/backlog.md
   Output:
     Line 19: Sub-gap A of the Build Doctrine integration audit batch — Stop-hook orthogonality audit shipped (commit fd9f663)
     Line 20: Sub-gap B of the audit batch — pipeline-agents.md deleted from global rules (commit d8b30f3)
     Line 21: Sub-gap C of the audit batch — claim-reviewer post-Gen6 reassessment shipped (commit d8b30f3)
     Line 22: Sub-gap F of the audit batch — Rules-vs-hooks audit shipped (commit d8b30f3)
     Line 23: Sub-gap H of the audit batch — docs/reviews/ gitignore convention documented (commit 7abe23e)
   All 5 entries present (A, B, C, F, H), each with a commit SHA citation.
   Result: PASS

5. backlog.md "Last updated" header refreshed to v14
   Command: head -3 docs/backlog.md
   Output: line 3 begins "Last updated: 2026-05-04 v14: HARNESS-GAP-10 sub-gaps A, B, C, F, H IMPLEMENTED via Phase 1d-E-2 (`docs/plans/phase-1d-e-2-audit-cleanup.md`); see "Recently implemented" section below for commit SHAs and audit document paths. Decision 022 records the structural choice (pipeline-agents.md deleted from global rules)."
   Bumped from v13 → v14; new entry chains the prior version notes.
   Result: PASS

6. Single commit (no batched siblings)
   Command: git log --oneline 6d30d7b^..6d30d7b
   Output: only 6d30d7b in the range; no follow-up amendment commits before HEAD touch the same files.
   Result: PASS

Git evidence:
  Files modified in commit 6d30d7b:
    - docs/decisions/022-pipeline-agents-md-deletion.md (NEW, 153 lines)
    - docs/DECISIONS.md (1 line added — index row for 022)
    - docs/backlog.md (10 added / 1 removed — "Last updated" v13→v14 + 5 sub-gap closure entries appended to "Recently implemented in Phase 1d-E series" section)

Runtime verification: file <repo>/claude-projects/neural-lace/docs/decisions/022-pipeline-agents-md-deletion.md::pipeline-agents.md deleted from global rules
Runtime verification: file <repo>/claude-projects/neural-lace/docs/DECISIONS.md::022-pipeline-agents-md-deletion.md
Runtime verification: file <repo>/claude-projects/neural-lace/docs/backlog.md::Sub-gap A of the Build Doctrine integration audit batch
Runtime verification: file <repo>/claude-projects/neural-lace/docs/backlog.md::Sub-gap H of the audit batch

Verdict: PASS
Confidence: 9
Reason: All four acceptance criteria met. Decision 022 file is substantive (153 lines) with every required ADR section populated (Title, Date 2026-05-04, Status Implemented, Stakeholders, Context, Decision, Alternatives, Consequences, Cross-references). DECISIONS.md row 022 lands correctly in the index table. backlog.md "Recently implemented" section gains all 5 sub-gap entries (A/B/C/F/H), each with a commit SHA and audit document path where applicable. Single commit 6d30d7b contains exactly the expected file set. Last-updated header bumped v13 → v14 with consistent chained-history format. No defects observed; this is the closing-out task of Phase 1d-E-2 and it lands cleanly.
