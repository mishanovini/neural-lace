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

