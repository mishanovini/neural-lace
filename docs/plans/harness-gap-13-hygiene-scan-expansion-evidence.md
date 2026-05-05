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
