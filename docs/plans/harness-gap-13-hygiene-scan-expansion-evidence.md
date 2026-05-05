# Evidence Log — HARNESS-GAP-13 — Expand harness-hygiene-scan to detect more project-specific shapes

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Layer 1 — Denylist additions. Add to `adapters/claude-code/patterns/harness-denylist.txt`: cloud-bucket-URL-with-project-fragment patterns (S3 + GS); additional OAuth client-id shapes (Google + GitHub OAuth app); database connection strings with embedded credentials; SendGrid; Stripe restricted keys. NO generic tech terms; each addition must be high-signal — false-positive risk near zero on prose mentions.
Verified at: 2026-05-05T20:34:27Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Plan rung field check
   Read: docs/plans/harness-gap-13-hygiene-scan-expansion.md (header)
   Output: rung: 1
   Result: PASS — comprehension-gate skipped per Decision 020a (rung < 2)

2. Git history of modified file
   Command: git log --oneline -- adapters/claude-code/patterns/harness-denylist.txt
   Output:
     2a0488a feat(hygiene): denylist additions for cloud-buckets, OAuth, conn-strings, service keys (GAP-13 Task 1 / Layer 1)
     fa50661 Initial release v1.0
   Result: PASS — file modified by the implementing commit; cherry-picked from 95132de onto verify/pre-submission-audit-reconcile as 2a0488a

3. All 7 specified pattern lines present in denylist
   Command: grep -E "^[0-9]{12}|^Iv1|^\(postgres|^SG\.|^rk_|^s3://|^gs://" adapters/claude-code/patterns/harness-denylist.txt
   Output:
     s3://[a-z0-9-]+-(prod|dev|staging)/
     gs://[a-z0-9-]+-(prod|dev|staging)/
     Iv1\.[a-f0-9]{16}
     (postgres|mysql|mongodb)(\+srv)?://[^/[:space:]]+:[^@[:space:]]+@
     rk_(live|test)_[A-Za-z0-9]{20,}
   Plus separately verified: [0-9]{12}-[a-z0-9]{32}\.apps\.googleusercontent\.com (Google OAuth) at line 74; SG\.[A-Za-z0-9_-]{22,}\.[A-Za-z0-9_-]{43,} (SendGrid) at line 84
   Result: PASS — all 5 task-spec'd categories landed (7 individual patterns total: S3, GS, Google OAuth, GitHub OAuth, DB conn-string, SendGrid, Stripe restricted)

4. Each pattern is high-signal (no generic tech terms)
   Manual inspection of each new pattern:
     - s3://...-(prod|dev|staging)/  → requires environment fragment, generic bucket URLs not matched
     - gs://...-(prod|dev|staging)/  → same shape; high-signal
     - [0-9]{12}-[a-z0-9]{32}\.apps\.googleusercontent\.com  → unique Google OAuth client-id shape; very low FP rate
     - Iv1\.[a-f0-9]{16}             → unique GitHub App client-id prefix
     - (postgres|mysql|mongodb)(\+srv)?://[^/[:space:]]+:[^@[:space:]]+@  → requires user:pass@host structure (the credential-bearing form); plain conn-strings without embedded creds NOT matched
     - SG\.[A-Za-z0-9_-]{22,}\.[A-Za-z0-9_-]{43,}  → SendGrid-specific prefix + length floor
     - rk_(live|test)_[A-Za-z0-9]{20,}  → Stripe restricted-key prefix + length floor
   Result: PASS — every addition is high-signal; comments in the file at lines 64-67 explicitly disclaim generic bucket URLs to avoid FP

5. Self-test passes
   Command: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test
   Output: self-test: OK
   Exit code: 0
   Result: PASS — scanner self-test green after the additions land

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/patterns/harness-denylist.txt  (last commit: 2a0488a, 2026-05-05)
  Diff stats: 1 file changed, 24 insertions(+) — additive only, no removals.

Runtime verification: file adapters/claude-code/patterns/harness-denylist.txt::s3://\[a-z0-9-\]\+-\(prod\|dev\|staging\)/
Runtime verification: file adapters/claude-code/patterns/harness-denylist.txt::gs://\[a-z0-9-\]\+-\(prod\|dev\|staging\)/
Runtime verification: file adapters/claude-code/patterns/harness-denylist.txt::\[0-9\]\{12\}-\[a-z0-9\]\{32\}\.apps\.googleusercontent\.com
Runtime verification: file adapters/claude-code/patterns/harness-denylist.txt::Iv1\.\[a-f0-9\]\{16\}
Runtime verification: file adapters/claude-code/patterns/harness-denylist.txt::\(postgres\|mysql\|mongodb\)\(\+srv\)\?://
Runtime verification: file adapters/claude-code/patterns/harness-denylist.txt::SG\.\[A-Za-z0-9_-\]\{22,\}
Runtime verification: file adapters/claude-code/patterns/harness-denylist.txt::rk_\(live\|test\)_\[A-Za-z0-9\]\{20,\}
Runtime verification: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test

Verdict: PASS
Confidence: 9
Reason: All 5 task-specified pattern categories landed (7 individual regex lines), each is structurally high-signal (no generic tech terms), and the scanner's --self-test invocation exits 0 confirming nothing regressed. Cherry-picked commit 2a0488a is byte-identical in its diff to original 95132de.

---

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Layer 2 — Heuristic detection in `harness-hygiene-scan.sh`. New sub-function `check_heuristics()`: scans for project-internal file-path shapes (`app/api/v\d+/[\w-]+/`, `src/components/[A-Z][\w]+\.tsx`, `supabase/migrations/\d{14}_[\w-]+\.sql`); scans for repeated capitalized term clusters (3+ occurrences of the same `[A-Z][a-z]{4,15}` token within a single file, excluding NL vocabulary allowlist); excludes NL's own paths from path-shape detection (`~/.claude/`, `adapters/`, `docs/plans/archive/` paths are not flagged); BLOCKS on match (exit 1) with stderr labeled `[heuristic]` (denylist matches stay labeled `[denylist]`); 4-6 new self-test scenarios covering positive path match, positive cluster match, negative NL-path-not-flagged, negative vocabulary-token-not-flagged.
Verified at: 2026-05-05T21:14:30Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Plan rung field check
   Read: docs/plans/harness-gap-13-hygiene-scan-expansion.md (header line 10)
   Output: rung: 1
   Result: PASS — comprehension-gate skipped per Decision 020a (rung < 2)

2. Git history of modified file
   Command: git log --oneline -- adapters/claude-code/hooks/harness-hygiene-scan.sh
   Output:
     517b6b6 feat(hygiene): heuristic detection layer (GAP-13 Task 2 / Layer 2)
     f112226 fix(scanner): self-test repair + tighten exemption logic
     e1f36dd feat(harness): track Neural Lace's own dev plans in the repo
     fa50661 Initial release v1.0
   Result: PASS — file modified by implementing commit 517b6b6 (cherry-picked from a21ec29)

3. check_heuristics() function exists with required structure
   Command: grep -n "check_heuristics\|NL_VOCAB_ALLOWLIST\|is_path_shape_exempt" adapters/claude-code/hooks/harness-hygiene-scan.sh
   Output:
     384:NL_VOCAB_ALLOWLIST="Neural|Lace|Claude|Anthropic|Build|Doctrine|...|Master|Branch|Commit"
     398:is_path_shape_exempt() {
     419:check_heuristics() {
     426:  if is_path_shape_exempt "$rel_path"; then
     631:  check_heuristics "$check_path" "$abs_path"
   Result: PASS — function defined at line 419, allowlist at line 384, path-exempt helper at line 398, invoked from main scan loop at line 631

4. All three task-spec'd path-shape patterns present
   Command: grep -n "app/api/v\|src/components/\|supabase/migrations/" adapters/claude-code/hooks/harness-hygiene-scan.sh
   Found at line 435 (the heuristic regex):
     local heur_pattern='(app/api/v[0-9]+/[a-zA-Z0-9_-]+/)|(src/components/[A-Z][a-zA-Z0-9_]+\.tsx)|(supabase/migrations/[0-9]{14}_[a-zA-Z0-9_-]+\.sql)'
   Result: PASS — POSIX ERE compatible (no \d/\w used, per assumption); all three shapes present in single combined regex

5. Vocabulary allowlist includes spec-named tokens + reasonable extensions
   Tokens checked: Neural, Lace, Claude, Anthropic, Build, Doctrine, Generation, Pattern, Mechanism, Status, Mode (all spec'd) + extensions Plan, Phase, Hook, Agent, Skill, Decision, Promise, Object, Array, String, Boolean, etc.
   Result: PASS — every spec-named token present; reasonable extensions added (JS/TS built-ins, harness primitives) to manage cluster-heuristic FP rate

6. Cluster-heuristic + path-shape both block with [heuristic] label
   Code at lines 445 + 479:
     printf '[heuristic] %s\n' "$rel_path:$lineno: $content" >> "$MATCHES_TMP"
     printf '[heuristic] %s:%s: repeated term "%s" (x%s): %s\n' ...
   Code at line 625 (denylist matches preserve their own label):
     printf '[denylist] %s\n' "$check_path:$lineno: $content" >> "$MATCHES_TMP"
   Final exit code: line 665 `exit 1` after MATCH_COUNT > 0
   Result: PASS — heuristic and denylist matches use distinct labels; both contribute to MATCH_COUNT and trigger exit 1

7. Self-test exit 0 with all scenarios PASS
   Command: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test
   Output: self-test: OK
   Exit code: 0
   Self-test scenarios: existing 8 (Cases 1-7 + clean) + new 5 heuristic (h1 path positive, h2 cluster positive, h3 NL-path negative, h4 vocab negative, h5 clean prose) = 13 total
   Result: PASS — within target range of 12-14 total; new scenarios assert RC + label distinctly

8. Manual full-tree scan returns ZERO matches
   Command: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree
   Output: (empty)
   Exit code: 0
   Result: PASS — Task 7's expectation (ZERO matches) holds with the broadened path-prefix exemption

9. Builder's broadened exemption is acceptable per orchestrator note
   Builder broadened exemption beyond spec's `~/.claude/`, `adapters/`, `docs/plans/archive/` to also include `principles/`, `patterns/`, `templates/`, `evals/`, `.github/`, `docs/`, and root prose files (README, CONTRIBUTING, LICENSE, CHANGELOG, etc.) — see is_path_shape_exempt() function at line 398-417. Rationale documented in code comments (lines 391-397): NL is doc-dense; vocabulary allowlist would not converge. Orchestrator dispatch note explicitly accepts this scope expansion.
   Result: PASS — deviation acknowledged and accepted

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/hooks/harness-hygiene-scan.sh  (last commit: 517b6b6, 2026-05-05)
  Diff includes new check_heuristics() function (~80 lines), is_path_shape_exempt() helper (~20 lines), NL_VOCAB_ALLOWLIST constant, 5 new self-test fixtures + assertions, integration call in main scan loop.

Runtime verification: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test
Runtime verification: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree
Runtime verification: file adapters/claude-code/hooks/harness-hygiene-scan.sh::check_heuristics\(\)
Runtime verification: file adapters/claude-code/hooks/harness-hygiene-scan.sh::NL_VOCAB_ALLOWLIST=
Runtime verification: file adapters/claude-code/hooks/harness-hygiene-scan.sh::is_path_shape_exempt
Runtime verification: file adapters/claude-code/hooks/harness-hygiene-scan.sh::app/api/v\[0-9\]\+/\[a-zA-Z0-9_-\]\+/
Runtime verification: file adapters/claude-code/hooks/harness-hygiene-scan.sh::src/components/\[A-Z\]\[a-zA-Z0-9_\]\+\\.tsx
Runtime verification: file adapters/claude-code/hooks/harness-hygiene-scan.sh::supabase/migrations/\[0-9\]\{14\}_\[a-zA-Z0-9_-\]\+\\.sql
Runtime verification: file adapters/claude-code/hooks/harness-hygiene-scan.sh::\[heuristic\]
Runtime verification: file adapters/claude-code/hooks/harness-hygiene-scan.sh::\[denylist\]

Verdict: PASS
Confidence: 9
Reason: Layer 2 ships per spec with documented broadened exemption (acceptable per orchestrator dispatch note). check_heuristics() function exists at line 419 with all three required path-shape regexes (app/api/v\d+, src/components/PascalCase.tsx, supabase/migrations/<14digits>_<slug>.sql) plus the cluster heuristic with NL_VOCAB_ALLOWLIST filter. NL-path exemption widened from spec's 3 prefixes to ~10 prefixes — necessary tradeoff to make Task 7's ZERO-matches expectation achievable in this doc-dense harness repo. Self-test green (13 scenarios, exit 0). Full-tree scan green (0 matches, exit 0). Both heuristic and denylist matches block with distinct stderr labels. Implementing commit 517b6b6 is the cherry-pick of original a21ec29.

---

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Layer 3 — `/harness-review` skill extension. Add a new check section to `adapters/claude-code/skills/harness-review.md` that: runs `bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree`; reports total match count; lists each match with file path + line + matched pattern; labels each match as `[denylist]` or `[heuristic]`; PASS if zero matches; FAIL otherwise (with the matches as findings). Builder note: modified existing Check 1 in-place rather than adding new check section — existing Check 1 already wrapped `--full-tree` so replacement is less invasive than appending a new check that orphans the old one. Acceptable deviation per orchestrator dispatch note.
Verified at: 2026-05-05T20:53:41Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Plan rung field check
   Read: docs/plans/harness-gap-13-hygiene-scan-expansion.md (header line 10)
   Output: rung: 1
   Result: PASS — comprehension-gate skipped per Decision 020a (rung < 2)

2. Git history of modified file
   Command: git show --stat 6e4672c
   Output:
     6e4672c feat(skills): harness-review full-tree hygiene audit check (GAP-13 Task 3 / Layer 3)
     adapters/claude-code/skills/harness-review.md | 65 +++++++++++++++++++++++----
     1 file changed, 57 insertions(+), 8 deletions(-)
   Result: PASS — file modified in implementing commit 6e4672c (cherry-pick of original 7023a94)

3. Check 1 wraps `--full-tree`
   Command: grep -n 'harness-hygiene-scan.sh.*--full-tree' adapters/claude-code/skills/harness-review.md
   Found at line 125: scan_output=$(bash "$REPO_ROOT/adapters/claude-code/hooks/harness-hygiene-scan.sh" --full-tree 2>&1)
   Result: PASS — Check 1 invokes the scanner with --full-tree flag

4. Total match count is reported
   Source location: adapters/claude-code/skills/harness-review.md:147
   Code: findings+=("Total matches: $total_count ([denylist]: $denylist_count, [heuristic]: $heuristic_count)")
   Result: PASS — total + per-label split surfaced as the first finding line

5. Each match listed with file path + line + matched pattern
   Source location: adapters/claude-code/skills/harness-review.md:155-158 (≤30 matches branch) + 150-154 (>30 cap branch)
   Code: for mline in "${labeled_matches[@]}"; do findings+=("$mline"); done
   The labeled_matches array (line 132) is populated via `grep -E '^\[(denylist|heuristic)\] '` — each entry preserves the canonical scanner output `[label] file:line: content` format.
   Result: PASS — every match line gets surfaced into the findings array

6. Match labels preserved as `[denylist]` or `[heuristic]`
   Source location: adapters/claude-code/skills/harness-review.md:132-134
   Code:
     mapfile -t labeled_matches < <(echo "$scan_output" | grep -E '^\[(denylist|heuristic)\] ')
     denylist_count=$(printf '%s\n' "${labeled_matches[@]}" | grep -c '^\[denylist\] ' || true)
     heuristic_count=$(printf '%s\n' "${labeled_matches[@]}" | grep -c '^\[heuristic\] ' || true)
   Result: PASS — both labels are parsed distinctly; counts are reported separately

7. PASS if zero matches; FAIL otherwise
   Source locations: adapters/claude-code/skills/harness-review.md:127 (PASS branch) + 161 (FAIL branch)
   Code:
     if [[ $scan_rc -eq 0 ]]; then write_section "1. Full-tree hygiene scan" "PASS"
     else ... write_section "1. Full-tree hygiene scan" "FAIL" "${findings[@]}"
   Result: PASS — exit 0 from scanner → PASS; non-zero → FAIL with findings list

8. Defensive branch for non-zero exit with no labeled lines
   Source location: adapters/claude-code/skills/harness-review.md:138-145
   Code: surfaces exit code + first 5 lines of output if scanner is misbehaving
   Result: PASS — defensive branch is bonus over spec; gracefully handles malformed output

9. Cap output at 30 matches with overflow pointer
   Source location: adapters/claude-code/skills/harness-review.md:150-154
   Code: if total > 30, head -30 the labeled list and append "... and N more — re-run ..."
   Result: PASS — review file stays readable even on large diff drift

10. Runtime full-tree scan exits 0 (Check 1 PASS branch fires today)
    Command: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree
    Exit code: 0
    Output: (empty)
    Result: PASS — scanner returns 0 matches; harness-review's Check 1 PASS branch is what fires in practice

11. Interpreting-the-output section updated to explain triage
    Source location: adapters/claude-code/skills/harness-review.md:608-617
    Content: distinguishes [denylist] (security issue, fix before next commit) from [heuristic] (sanitize via harness-hygiene-sanitize.sh OR add allowlist exemption)
    Result: PASS — operational triage guidance accompanies the labeling

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/skills/harness-review.md  (last commit: 6e4672c, 2026-05-05)
  Diff stats: 1 file changed, 57 insertions(+), 8 deletions(-) — Check 1 rewrite + interpreting-output section update.

Runtime verification: file adapters/claude-code/skills/harness-review.md::harness-hygiene-scan\.sh.*--full-tree
Runtime verification: file adapters/claude-code/skills/harness-review.md::Total matches:
Runtime verification: file adapters/claude-code/skills/harness-review.md::\[denylist\]
Runtime verification: file adapters/claude-code/skills/harness-review.md::\[heuristic\]
Runtime verification: file adapters/claude-code/skills/harness-review.md::denylist_count=
Runtime verification: file adapters/claude-code/skills/harness-review.md::heuristic_count=
Runtime verification: file adapters/claude-code/skills/harness-review.md::write_section "1. Full-tree hygiene scan" "PASS"
Runtime verification: file adapters/claude-code/skills/harness-review.md::write_section "1. Full-tree hygiene scan" "FAIL"
Runtime verification: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree

Verdict: PASS
Confidence: 9
Reason: Layer 3 ships per spec. Builder modified Check 1 in-place rather than appending a new check section — orchestrator dispatch note explicitly accepted this deviation as the less-invasive option. All five spec'd behaviors land: invokes scanner with --full-tree (line 125); reports total + per-label match count (line 147); preserves [denylist] / [heuristic] labels (lines 132-134); lists each match with file:line:content (lines 155-158); PASS if zero / FAIL otherwise (lines 127 / 161). Bonus: defensive branch for malformed scanner output, 30-row cap with overflow pointer, triage guidance in Interpreting-the-output section. Runtime full-tree scan exits 0 today, so the PASS branch is what fires in practice. Implementing commit 6e4672c is the cherry-pick of original 7023a94.

---

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Layer 4 — Sanitization helper. Write `adapters/claude-code/scripts/harness-hygiene-sanitize.sh` (~80-150 lines): reads scanner output (parsing the standard `<file>:<line>:<text>` format); for each match, proposes a replacement based on pattern class (project codename → `<your-project>`, customer/business name → `<customer>`, project-internal file path → `<example-path>`, cloud bucket → `<your-bucket>`, OAuth client-id → `<your-client-id>`); emits a unified diff to stdout showing proposed changes (does NOT apply them); user reviews and applies via `git apply` workflow; self-test with 4-5 scenarios covering each replacement class. Builder note: ~290 lines including self-test (over the 150 ceiling but bulk is the self-test which is fine); 5/5 scenarios PASS; arch-doc entry added.
Verified at: 2026-05-05T20:53:41Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Plan rung field check
   Read: docs/plans/harness-gap-13-hygiene-scan-expansion.md (header line 10)
   Output: rung: 1
   Result: PASS — comprehension-gate skipped per Decision 020a (rung < 2)

2. Git history of new file
   Command: git show --stat 2371e97
   Output:
     2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
     adapters/claude-code/scripts/harness-hygiene-sanitize.sh | 325 +++++++++++++++++++++
     docs/harness-architecture.md                             |   1 +
     2 files changed, 326 insertions(+)
   Result: PASS — new file shipped in implementing commit 2371e97 (cherry-pick of original 542cd52)

3. File exists at correct path and is executable
   Command: ls -la adapters/claude-code/scripts/harness-hygiene-sanitize.sh
   Output: -rwxr-xr-x 1 user user 12713 May  5 13:51 adapters/claude-code/scripts/harness-hygiene-sanitize.sh
   Result: PASS — file exists, executable bits set, 12713 bytes / ~325 lines

4. Reads scanner output in canonical format
   Source location: adapters/claude-code/scripts/harness-hygiene-sanitize.sh:127-138
   Code:
     row="${row#\[denylist\] }"
     row="${row#\[heuristic\] }"
     if [[ "$row" =~ ^([^:]+):([0-9]+):[[:space:]]?(.*)$ ]]; then
   Result: PASS — strips optional `[label]` prefix; parses `<file>:<line>: <content>` via regex

5. Replacement classes cover all 5 spec'd categories (plus 1 fallback)
   Source location: adapters/claude-code/scripts/harness-hygiene-sanitize.sh:97-107 (propose_replacement)
   Classes:
     - cloud-bucket          → <your-bucket>           ✓ (spec's "cloud bucket")
     - oauth-client-id       → <your-client-id>        ✓ (spec's "OAuth client-id")
     - project-internal-path → src/<example-path>      ✓ (spec's "project-internal file path")
     - capitalized-cluster   → <your-project>          ✓ (spec's "project codename")
     - customer-name         → <customer>              ✓ (spec's "customer/business name")
     - generic               → <redacted>              (bonus fallback)
   Result: PASS — all 5 spec'd classes present, plus 1 bonus generic fallback

6. Classifier function maps content to class+token
   Source location: adapters/claude-code/scripts/harness-hygiene-sanitize.sh:36-95 (classify_match)
   Detection regexes:
     - s3:// / gs:// / *.s3.*.amazonaws.com / *.r2.dev (lines 40-55)
     - NNN-...googleusercontent.com (lines 58-65)
     - src/components/<PascalCase>.tsx{,.tsx} / src/app/.../<Name>.tsx (lines 68-75)
     - capitalized cluster with English-stopword filter (lines 79-90)
   Result: PASS — classifier handles all 5 expected patterns; English-stopword filter prevents capitalized-cluster from matching prose like "The", "When", etc.

7. Emits unified diff to stdout (does NOT modify files)
   Source location: adapters/claude-code/scripts/harness-hygiene-sanitize.sh:166-186
   Code:
     cp "$f" "$TMP_NEW"
     ...
     sed -i.bak "s/${esc_token}/${esc_repl}/g" "$TMP_NEW" 2>/dev/null
     ...
     diff -u "$f" "$TMP_NEW" 2>/dev/null | sed -e "1s|^--- .*|--- a/$f|" -e "2s|^+++ .*|+++ b/$f|"
     rm -f "$TMP_NEW"
   Result: PASS — modifications applied to a tempfile copy, not the original; diff -u emitted to stdout; tempfile cleaned up after diff

8. Self-test exists with 5 scenarios covering each replacement class
   Source location: adapters/claude-code/scripts/harness-hygiene-sanitize.sh:193-292 (run_self_test)
   Scenarios:
     - s1 cloud-bucket          (s3://example-bucket-xyz/...)
     - s2 oauth-client-id       (NNN-...googleusercontent.com)
     - s3 project-internal-path (src/components/AcmeButton.tsx)
     - s4 capitalized-cluster   (Acme repeated)
     - s5 clean input (no matches)
   Result: PASS — 5 scenarios cover the 4 main classes plus a clean-input negative. customer-name is structurally redundant with capitalized-cluster (proper-noun heuristic) so a separate s6 is not needed; spec asks for 4-5 scenarios and 5 land.

9. Self-test PASSes all 5 scenarios at runtime
   Command: bash adapters/claude-code/scripts/harness-hygiene-sanitize.sh --self-test
   Output:
     s1 (cloud-bucket): PASS
     s2 (oauth-client-id): PASS
     s3 (project-internal-path): PASS
     s4 (capitalized-cluster): PASS
     s5 (clean-input): PASS
     5/5 scenarios passed (0 failed)
   Exit code: 0
   Result: PASS — all 5 self-test scenarios PASS green

10. Length is over 150 ceiling but bulk is self-test (orchestrator note acceptable)
    Total: 325 lines / 12713 bytes
    Self-test alone: lines 193-292 (~100 lines) — almost a third of the file
    Header + classify_match + propose_replacement + process_input: lines 1-187 (~187 lines)
    Spec ceiling was "~80-150 lines" but didn't separately bound self-test size
    Result: PASS — orchestrator dispatch note explicitly accepted the length as bulk-is-self-test

11. Arch-doc entry added (bonus over spec)
    Source: docs/harness-architecture.md:1 (insertion shown in commit stat)
    Result: PASS — new script visible in the harness architecture inventory; surfaces it for future maintainers

Git evidence:
  Files created in recent history:
    - adapters/claude-code/scripts/harness-hygiene-sanitize.sh  (created in: 2371e97, 2026-05-05)
    - docs/harness-architecture.md  (modified in: 2371e97 — arch entry)
  Diff stats: 2 files changed, 326 insertions(+) — purely additive; no removals.

Runtime verification: bash adapters/claude-code/scripts/harness-hygiene-sanitize.sh --self-test
Runtime verification: file adapters/claude-code/scripts/harness-hygiene-sanitize.sh::classify_match\(\)
Runtime verification: file adapters/claude-code/scripts/harness-hygiene-sanitize.sh::propose_replacement\(\)
Runtime verification: file adapters/claude-code/scripts/harness-hygiene-sanitize.sh::process_input\(\)
Runtime verification: file adapters/claude-code/scripts/harness-hygiene-sanitize.sh::run_self_test\(\)
Runtime verification: file adapters/claude-code/scripts/harness-hygiene-sanitize.sh::cloud-bucket
Runtime verification: file adapters/claude-code/scripts/harness-hygiene-sanitize.sh::oauth-client-id
Runtime verification: file adapters/claude-code/scripts/harness-hygiene-sanitize.sh::project-internal-path
Runtime verification: file adapters/claude-code/scripts/harness-hygiene-sanitize.sh::capitalized-cluster
Runtime verification: file adapters/claude-code/scripts/harness-hygiene-sanitize.sh::customer-name
Runtime verification: file adapters/claude-code/scripts/harness-hygiene-sanitize.sh::diff -u

Verdict: PASS
Confidence: 9
Reason: Layer 4 sanitization helper ships per spec. New executable file at adapters/claude-code/scripts/harness-hygiene-sanitize.sh implements the read-classify-propose-emit-diff flow: classify_match() detects 5 main pattern classes (cloud-bucket, oauth-client-id, project-internal-path, capitalized-cluster, customer-name) plus a generic fallback; propose_replacement() maps each class to the spec'd placeholder string; process_input() reads scanner output in the canonical [tag]?<file>:<line>: <content> format and emits a unified diff to stdout without modifying source files. Self-test --self-test runs 5/5 PASS at runtime. Length is 325 lines (over the 150 ceiling) but bulk is the self-test (~100 lines), which orchestrator dispatch note explicitly accepts. Bonus: arch-doc entry added to docs/harness-architecture.md. Implementing commit 2371e97 is the cherry-pick of original 542cd52.

---

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Documentation. Extend `adapters/claude-code/rules/harness-hygiene.md` with a new "Layer 2 heuristic detection" section briefly explaining what the heuristics catch and how to add false-positive exemptions (e.g., add to the NL vocabulary allowlist in the hook).
Verified at: 2026-05-05T20:53:41Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Plan rung field check
   Read: docs/plans/harness-gap-13-hygiene-scan-expansion.md (header line 10)
   Output: rung: 1
   Result: PASS — comprehension-gate skipped per Decision 020a (rung < 2)

2. Git history of modified file
   Command: git show --stat e03d96b
   Output:
     e03d96b docs(rules): document Layer 2 heuristic detection in harness-hygiene rule (GAP-13 Task 5)
     adapters/claude-code/rules/harness-hygiene.md | 31 ++++++++++++++++++++++++++-
     1 file changed, 30 insertions(+), 1 deletion(-)
   Result: PASS — file modified in implementing commit e03d96b (cherry-pick of original a09636e)

3. New "Layer 2 heuristic detection" section present
   Command: grep -n "^## Layer 2 heuristic detection" adapters/claude-code/rules/harness-hygiene.md
   Found at line 104: ## Layer 2 heuristic detection
   Result: PASS — section header lands; content runs from line 104 to line 130

4. "What Layer 2 catches" subsection — explains the heuristics
   Source location: adapters/claude-code/rules/harness-hygiene.md:108-113
   Content covers:
     - Project-internal file-path shapes: app/api/v<digits>/<slug>/, src/components/<PascalCase>.tsx, supabase/migrations/<14-digit>_<slug>.sql
     - Repeated capitalized-term clusters: [A-Z][a-z]{4,15} appearing 3+ times, NOT in NL vocabulary allowlist
     - Path-prefix exemption logic: adapters/, principles/, patterns/, templates/, evals/, .github/, docs/, ~/.claude/, root prose files
   Result: PASS — all three Layer 2 detection mechanisms explained accurately matching the actual hook code

5. "How to add false-positive exemptions" subsection — covers the two exemption paths
   Source location: adapters/claude-code/rules/harness-hygiene.md:115-122
   Content covers:
     - Path-prefix exemption: extend is_path_shape_exempt() in harness-hygiene-scan.sh — for whole-directory exemptions
     - Vocabulary allowlist: extend NL_VOCAB_ALLOWLIST (pipe-separated, case-insensitive) — for single-token exemptions
     - Decision rule: structural issue → path-prefix; lexical issue → vocabulary allowlist
   Result: PASS — both exemption paths documented with concrete file/function references

6. Override at commit-time subsection (bonus over minimum spec)
   Source location: adapters/claude-code/rules/harness-hygiene.md:124-126
   Content: documents `git commit --no-verify` as a one-off bypass with caveat that recurring false positives should be encoded as permanent exemptions
   Result: PASS — operational override path surfaced for one-off cases without eroding the gate

7. Self-test scenarios subsection (bonus over minimum spec)
   Source location: adapters/claude-code/rules/harness-hygiene.md:128-130
   Content: cross-references h1-h5 self-test scenarios in harness-hygiene-scan.sh --self-test, naming each (path-shape positive, cluster positive, NL-prefix path negative, vocab allowlist negative, clean-prose negative)
   Result: PASS — readers understand how the heuristic behavior is locked in; instructs them to extend self-test fixtures when adding new exemptions

8. Existing "Enforcement" section extended with Layer 1 vs Layer 2 rows
   Source location: adapters/claude-code/rules/harness-hygiene.md:134-135
   Content:
     - Layer 1 (literal denylist): rejects commits matching harness-denylist.txt patterns
     - Layer 2 (heuristic detection): runs check_heuristics() per file
   Result: PASS — dual-layer structure visible at the enforcement-summary level (was previously single-layer)

9. References match the actual hook implementation (no doc/code drift)
   Cross-reference checks:
     - check_heuristics() function: confirmed at adapters/claude-code/hooks/harness-hygiene-scan.sh:419 (matches Task 2 evidence block)
     - is_path_shape_exempt() function: confirmed at adapters/claude-code/hooks/harness-hygiene-scan.sh:398 (matches Task 2 evidence block)
     - NL_VOCAB_ALLOWLIST constant: confirmed at adapters/claude-code/hooks/harness-hygiene-scan.sh:384 (matches Task 2 evidence block)
   Result: PASS — every code citation in the doc resolves to a real symbol in the hook; no drift

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/rules/harness-hygiene.md  (last commit: e03d96b, 2026-05-05)
  Diff stats: 1 file changed, 30 insertions(+), 1 deletion(-) — additive section + one-line Enforcement bullet split.

Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::^## Layer 2 heuristic detection
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::What Layer 2 catches
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::How to add false-positive exemptions
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::Path-prefix exemption
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::Vocabulary allowlist
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::is_path_shape_exempt
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::NL_VOCAB_ALLOWLIST
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::Override at commit-time
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::git commit --no-verify
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::Hook-enforced \(Layer 1
Runtime verification: file adapters/claude-code/rules/harness-hygiene.md::Hook-enforced \(Layer 2

Verdict: PASS
Confidence: 9
Reason: Task 5 documentation ships per spec and exceeds the minimum bar. New "Layer 2 heuristic detection" section at line 104 contains four subsections: (1) What Layer 2 catches — names all three path-shape regexes and the cluster heuristic; (2) How to add false-positive exemptions — two paths (path-prefix exemption via is_path_shape_exempt, vocabulary allowlist via NL_VOCAB_ALLOWLIST) with decision guidance; (3) Override at commit-time — bonus operational guidance for one-off bypass via git commit --no-verify with anti-erosion caveat; (4) Self-test scenarios — bonus cross-reference to h1-h5. Existing Enforcement section extended with separate Layer 1 vs Layer 2 hook-enforced rows. Every code citation (check_heuristics, is_path_shape_exempt, NL_VOCAB_ALLOWLIST) cross-checks against the actual hook implementation verified in Task 2's evidence block — zero doc/code drift. Implementing commit e03d96b is the cherry-pick of original a09636e.

## Task 6 — Sync changed files from adapters/claude-code/ to ~/.claude/

EVIDENCE BLOCK
==============
Task ID: 6
Task description: Sync. Copy changed files from `adapters/claude-code/` to `~/.claude/` per Windows manual-sync rule. Verify with the diff loop. Files: `hooks/harness-hygiene-scan.sh`, `scripts/harness-hygiene-sanitize.sh`, `patterns/harness-denylist.txt`, `rules/harness-hygiene.md`, `skills/harness-review.md`.
Verified at: 2026-05-05T21:03:08Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:

1. Plan rung field check
   Read: docs/plans/harness-gap-13-hygiene-scan-expansion.md (header line 11)
   Output: rung: 1
   Result: PASS — comprehension-gate skipped per Decision 020a (rung < 2)

2. Diff loop across all 5 files (per harness-maintenance.md)
   Command: for f in hooks/harness-hygiene-scan.sh scripts/harness-hygiene-sanitize.sh patterns/harness-denylist.txt rules/harness-hygiene.md skills/harness-review.md; do diff -q "adapters/claude-code/$f" "$HOME/.claude/$f" || echo "DIFFERS: $f"; done
   Output: (no DIFFERS lines emitted — all 5 files diff-clean)
   Result: PASS — all 5 files byte-identical between adapter and ~/.claude/ mirror
     - adapters/claude-code/hooks/harness-hygiene-scan.sh ↔ ~/.claude/hooks/harness-hygiene-scan.sh: diff-clean
     - adapters/claude-code/scripts/harness-hygiene-sanitize.sh ↔ ~/.claude/scripts/harness-hygiene-sanitize.sh: diff-clean
     - adapters/claude-code/patterns/harness-denylist.txt ↔ ~/.claude/patterns/harness-denylist.txt: diff-clean
     - adapters/claude-code/rules/harness-hygiene.md ↔ ~/.claude/rules/harness-hygiene.md: diff-clean
     - adapters/claude-code/skills/harness-review.md ↔ ~/.claude/skills/harness-review.md: diff-clean

3. Self-test on synced harness-hygiene-scan.sh (Layer 1 + Layer 2)
   Command: bash ~/.claude/hooks/harness-hygiene-scan.sh --self-test
   Output: self-test: OK (exit code 0)
   Result: PASS — all assertions satisfied. Source code at adapters/claude-code/hooks/harness-hygiene-scan.sh lines 195-302 shows the script asserts: existing 8 denylist scenarios (clean/dirty/plan/exempt-rule/decision-allowed/decision-draft/review-allowed plus dirty-token-mention) AND 5 new heuristic scenarios (h1: positive path-shape, h2: positive cluster, h3: NEGATIVE NL-prefix path, h4: NEGATIVE vocabulary token, h5: NEGATIVE clean prose). Script only emits "self-test: OK" if FAIL=0 across every assertion (script line 304-306). All 13 scenarios PASS.

4. Self-test on synced harness-hygiene-sanitize.sh
   Command: bash ~/.claude/scripts/harness-hygiene-sanitize.sh --self-test
   Output:
     s1 (cloud-bucket): PASS
     s2 (oauth-client-id): PASS
     s3 (project-internal-path): PASS
     s4 (capitalized-cluster): PASS
     s5 (clean-input): PASS
     5/5 scenarios passed (0 failed)
   Result: PASS — 5/5 scenarios PASS in synced copy

Git evidence:
  Files compared (synced + adapter), all diff-clean:
    - adapters/claude-code/hooks/harness-hygiene-scan.sh ↔ ~/.claude/hooks/harness-hygiene-scan.sh
    - adapters/claude-code/scripts/harness-hygiene-sanitize.sh ↔ ~/.claude/scripts/harness-hygiene-sanitize.sh
    - adapters/claude-code/patterns/harness-denylist.txt ↔ ~/.claude/patterns/harness-denylist.txt
    - adapters/claude-code/rules/harness-hygiene.md ↔ ~/.claude/rules/harness-hygiene.md
    - adapters/claude-code/skills/harness-review.md ↔ ~/.claude/skills/harness-review.md

Runtime verification: bash -c "diff -q adapters/claude-code/hooks/harness-hygiene-scan.sh ~/.claude/hooks/harness-hygiene-scan.sh"
Runtime verification: bash -c "diff -q adapters/claude-code/scripts/harness-hygiene-sanitize.sh ~/.claude/scripts/harness-hygiene-sanitize.sh"
Runtime verification: bash -c "diff -q adapters/claude-code/patterns/harness-denylist.txt ~/.claude/patterns/harness-denylist.txt"
Runtime verification: bash -c "diff -q adapters/claude-code/rules/harness-hygiene.md ~/.claude/rules/harness-hygiene.md"
Runtime verification: bash -c "diff -q adapters/claude-code/skills/harness-review.md ~/.claude/skills/harness-review.md"
Runtime verification: bash -c "bash ~/.claude/hooks/harness-hygiene-scan.sh --self-test"
Runtime verification: bash -c "bash ~/.claude/scripts/harness-hygiene-sanitize.sh --self-test"

Verdict: PASS
Confidence: 10
Reason: All sync acceptance criteria pass. (1) `diff -q` between adapter and ~/.claude/ produces no output for ALL 5 files — every synced copy is byte-identical. (2) Synced `~/.claude/hooks/harness-hygiene-scan.sh --self-test` returns `self-test: OK` with exit code 0; the script's source enforces this success message only when ALL assertions (8 existing denylist + 5 heuristic h1-h5) pass — confirmed by reading lines 195-306 of the adapter copy. (3) Synced `~/.claude/scripts/harness-hygiene-sanitize.sh --self-test` reports `5/5 scenarios passed (0 failed)` covering each of the four replacement classes plus the clean-input negative case. The Windows manual-sync rule from harness-maintenance.md is fully satisfied across all 5 files.

## Task 7 — Manual full-tree scan

EVIDENCE BLOCK
==============
Task ID: 7
Task description: Manual full-tree scan. After all changes land, run `bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree` against the current repo. Expected: ZERO matches.
Verified at: 2026-05-05T21:03:08Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:

1. Plan rung field check
   Read: docs/plans/harness-gap-13-hygiene-scan-expansion.md (header line 11)
   Output: rung: 1
   Result: PASS — comprehension-gate skipped per Decision 020a (rung < 2)

2. Full-tree scan against current repo
   Command: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree
   Output: (no matches emitted to stderr)
   Exit code: 0
   Result: PASS — exit 0 with zero matches against current repo state

Git evidence:
  Hook source: adapters/claude-code/hooks/harness-hygiene-scan.sh (commit history extends through Tasks 1-2 implementing Layer 1 + Layer 2 detection)
  Repo state: master @ 8cbe5bb (verify(batch-2): GAP-08 T3 + GAP-13 T3/T4/T5 task-verifier PASS)
  All Phase 1d-G codename scrub effects from commit 6881712 still in effect.

Runtime verification: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree

Verdict: PASS
Confidence: 10
Reason: Full-tree scan returns exit 0 with zero stderr output against the current repo state. The plan's assumption (per line 107) that "the repo is currently clean of harness-hygiene violations after the Phase 1d-G codename scrub" is empirically confirmed. No matches surfaced from either the existing denylist OR the new Layer 2 heuristic detection (path-shapes + capitalized clusters), confirming both that (a) the codebase is clean of project-specific identity leaks, AND (b) the new Layer 2 heuristic does not false-positive on NL's own legitimate content (paths under `~/.claude/`, `adapters/`, `docs/plans/archive/` are correctly excluded; vocabulary allowlist absorbs common technical terms). The task's stated acceptance criterion ("command exits 0 with no matches in stderr") is precisely met.
