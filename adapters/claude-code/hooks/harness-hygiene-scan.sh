#!/bin/bash
# harness-hygiene-scan.sh
#
# Classification: Mechanism (hook-enforced pre-commit blocker)
#
# Scans staged git changes (or specified files, or the full tree) against the
# harness denylist at `adapters/claude-code/patterns/harness-denylist.txt`.
# Blocks a commit if any non-exempt file contains content that matches any
# denylist pattern.
#
# Purpose: harness repos (this one) must not ship personal, business, or
# identity-bearing strings. This hook is the last-line mechanical enforcement
# for the harness-hygiene principle. Override with `git commit --no-verify`
# only if you are CERTAIN the match is a legitimate false positive AND you
# have added an explicit exemption (or fixed the content).
#
# INVOCATION MODES
#   1. Pre-commit hook:  harness-hygiene-scan.sh
#                        (no args — reads `git diff --cached --name-only -z`)
#   2. Full-tree scan:   harness-hygiene-scan.sh --full-tree
#                        (scans all tracked files via `git ls-files -z`)
#   3. Specific files:   harness-hygiene-scan.sh path/to/a path/to/b
#                        (scans the listed paths directly)
#   4. Self-test:        harness-hygiene-scan.sh --self-test
#                        (runs internal assertions, prints OK/FAIL, exits)
#
# EXEMPT PATHS (never scanned)
#   - The denylist file itself (would match infinitely)
#   - SCRATCHPAD.md (gitignored working memory)
#   - Any file matching *.example, *.example.json, *.example.sh
#     (placeholders are supposed to look placeholder-ish)
#   - docs/decisions/, docs/reviews/, docs/sessions/ ONLY for non-allow-listed
#     paths within those directories. Committed (allow-listed) files
#     (e.g., `docs/decisions/NNN-*.md`, `docs/reviews/YYYY-MM-DD-*.md`,
#     `docs/sessions/YYYY-MM-DD-*.md`) ARE scanned because they ship in the
#     harness repo and must follow the same hygiene rules. Other paths under
#     those directories are gitignored instance artifacts and are exempt.
#   - docs/plans/ is NOT exempt — Neural Lace now commits its own
#     development plans (subject to hygiene like any other committed file).
#
# WAIVER (F.5 waiver-parity audit row 12 / ADR 059 D4 fix): the exemption
# list above is a PLAN-TIME allowlist (known-legitimate files/paths, edited
# out-of-band). It does not help a session that hits a genuine NOVEL
# false-positive at commit time (a denylisted string appearing legitimately
# in, e.g., a test fixture never seen before). For that case, a fresh (<1h)
# structured waiver at .claude/state/harness-hygiene-waiver-*.txt, naming
# BOTH purpose clauses (lib/waiver-purpose-clause.sh) AND the specific
# file(s) it covers, suppresses ONLY the matches on those named files for
# this run (never a blanket suppression of the whole scan). See
# `_hhs_waived_files` below.
#
# EXIT CODES
#   0 — no matches (or denylist missing / not in a git repo — silent no-op)
#   1 — one or more matches detected (denylist or heuristic)
#
# DETECTION LAYERS
#   Layer 1 (denylist) — literal/regex patterns from harness-denylist.txt.
#                         Matches are labeled `[denylist]` in stderr output.
#   Layer 2 (heuristic) — project-specific shape detection inside
#                         `check_heuristics()`. Catches patterns the literal
#                         denylist cannot (project-internal file paths,
#                         repeated capitalized term clusters outside NL
#                         vocabulary). Matches are labeled `[heuristic]`.
#                         Files in NL-prefix paths (`adapters/`, `docs/`,
#                         the synced `~/.claude/` mirror) are exempt from
#                         path-shape detection because plans, decisions,
#                         and rules legitimately cite paths in prose.
#                         Plan files under `docs/plans/*.md` are exempt
#                         from path-shape detection for the same reason.

set -u

# ---------- structured waiver (F.5 waiver-parity audit row 12 / ADR 059 D4)
# ----------------------------------------------------------------------------
# Fresh (<1h) .claude/state/harness-hygiene-waiver-*.txt files, each naming
# BOTH purpose clauses (lib/waiver-purpose-clause.sh) AND a "Files:" line
# listing the repo-relative path(s) the waiver covers (space or newline
# separated). Matches on a listed file are suppressed for this run only —
# this is per-file and per-run, distinct from the plan-time exempt-list
# (is_exempt below), which is a durable, out-of-band, known-legitimate list.
_HHS_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/waiver-purpose-clause.sh
source "$_HHS_SELF_DIR/lib/waiver-purpose-clause.sh" 2>/dev/null || true
# shellcheck source=lib/signal-ledger.sh
source "$_HHS_SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true

# _hhs_waived_files <state-dir>
# Prints, one per line, every repo-relative file path named in a fresh
# (<1h), purpose-clause-valid waiver's "Files:" line(s). Empty output if no
# valid fresh waiver exists (fails closed — same posture as every other
# structured waiver in the harness).
_hhs_waived_files() {
  local state_dir="$1"
  [ -d "$state_dir" ] || return 0
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if declare -F waiver_has_purpose_clauses >/dev/null 2>&1; then
      waiver_has_purpose_clauses "$f" || continue
    fi
    # "Files:" line(s), case-insensitive label, space/comma-separated paths.
    grep -iE '^[[:space:]]*files[[:space:]]*:' "$f" 2>/dev/null \
      | sed -E 's/^[[:space:]]*[Ff][Ii][Ll][Ee][Ss][[:space:]]*:[[:space:]]*//' \
      | tr ', ' '\n\n'
  done < <(find "$state_dir" -maxdepth 1 -type f -name 'harness-hygiene-waiver-*.txt' -newermt '1 hour ago' 2>/dev/null)
}

# ---------- self-test ----------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  # Build a minimal denylist
  mkdir -p "$TMPDIR_ST/adapters/claude-code/patterns"
  printf '%s\n' '# test denylist' 'FORBIDDEN_TOKEN' > "$TMPDIR_ST/adapters/claude-code/patterns/harness-denylist.txt"

  # Initialize a temp repo so the script's git rev-parse works
  (
    cd "$TMPDIR_ST" || exit 1
    git init -q . >/dev/null 2>&1
    git config user.email "selftest@example.com"
    git config user.name "selftest"
  )

  # Case 1: dirty file with the forbidden token
  DIRTY="$TMPDIR_ST/dirty.txt"
  printf '%s\n' 'line one' 'this line contains FORBIDDEN_TOKEN which should match' 'line three' > "$DIRTY"

  # Case 2: clean file
  CLEAN="$TMPDIR_ST/clean.txt"
  printf '%s\n' 'nothing bad here' 'just words' > "$CLEAN"

  # Case 3: dirty content in docs/plans/ SHOULD match (no longer exempt — NL
  # commits its own plans now, so they're subject to hygiene like any other
  # committed file).
  mkdir -p "$TMPDIR_ST/docs/plans"
  PLAN_FILE="$TMPDIR_ST/docs/plans/foo.md"
  printf '%s\n' 'this plan mentions FORBIDDEN_TOKEN as part of documenting it' > "$PLAN_FILE"

  # Case 4: dirty content in an exempt rule file should NOT match.
  mkdir -p "$TMPDIR_ST/adapters/claude-code/rules"
  EXEMPT_RULE="$TMPDIR_ST/adapters/claude-code/rules/harness-hygiene.md"
  printf '%s\n' 'harness-hygiene rule documents FORBIDDEN_TOKEN as a denylist example' > "$EXEMPT_RULE"

  # Case 5: allow-listed decision file (NNN-*.md) SHOULD be scanned (not exempt).
  mkdir -p "$TMPDIR_ST/docs/decisions"
  DECISION_ALLOWED="$TMPDIR_ST/docs/decisions/001-foo.md"
  printf '%s\n' 'decision NNN-* with FORBIDDEN_TOKEN must be caught' > "$DECISION_ALLOWED"

  # Case 6: non-allow-listed decision file (e.g., draft.md) is gitignored
  # instance artifact — still exempt to support drafts that never ship.
  DECISION_DRAFT="$TMPDIR_ST/docs/decisions/draft.md"
  printf '%s\n' 'draft mentions FORBIDDEN_TOKEN; gitignored, never ships' > "$DECISION_DRAFT"

  # Case 7: allow-listed review file (YYYY-MM-DD-*.md) SHOULD be scanned.
  mkdir -p "$TMPDIR_ST/docs/reviews"
  REVIEW_ALLOWED="$TMPDIR_ST/docs/reviews/2026-05-04-foo.md"
  printf '%s\n' 'review with FORBIDDEN_TOKEN must be caught' > "$REVIEW_ALLOWED"

  # ---- Layer 2 heuristic test fixtures ----

  # Case h1: positive path-shape match. File outside any NL-prefix path
  # mentions a project-internal API path. Should BLOCK with [heuristic] label.
  HEUR_PATH_DIRTY="$TMPDIR_ST/some-doc.md"
  printf '%s\n' 'See the route at app/api/v1/users/ for details.' > "$HEUR_PATH_DIRTY"

  # Case h2: positive cluster match. File mentions a fake project name 5x,
  # not in the NL vocabulary allowlist. Should BLOCK with [heuristic] label.
  HEUR_CLUSTER_DIRTY="$TMPDIR_ST/cluster-doc.md"
  printf '%s\n' \
    'Examplecorp ships a thing.' \
    'Examplecorp also ships another thing.' \
    'Why Examplecorp does this is unclear.' \
    'The Examplecorp engineering team made it work.' \
    'Examplecorp customers are happy.' \
    > "$HEUR_CLUSTER_DIRTY"

  # Case h3: NEGATIVE — NL-prefix path containing a project-internal-looking
  # path-shape should NOT trigger the heuristic (path-shape detection is
  # SKIPPED inside NL-prefix paths because they legitimately cite paths).
  mkdir -p "$TMPDIR_ST/adapters/claude-code/hooks"
  HEUR_NL_PATH="$TMPDIR_ST/adapters/claude-code/hooks/foo.sh"
  printf '%s\n' '# This hook references app/api/v1/users/ as an example.' > "$HEUR_NL_PATH"

  # Case h4: NEGATIVE — vocabulary allowlist token (Promise) appearing 5x
  # should NOT trigger cluster heuristic. Note: this file ALSO must not
  # match the path-shape heuristic, so we keep it path-free.
  HEUR_VOCAB="$TMPDIR_ST/vocab-doc.md"
  printf '%s\n' \
    'Promise me one thing.' \
    'A Promise is a contract.' \
    'Promise resolution is deterministic.' \
    'When a Promise rejects we handle the error.' \
    'Promise.all is the classic combinator.' \
    > "$HEUR_VOCAB"

  # Case h5: NEGATIVE — a clean file with no project-internal shapes and
  # no repeated non-allowlisted clusters should pass cleanly.
  HEUR_CLEAN="$TMPDIR_ST/clean-prose.md"
  printf '%s\n' \
    'This is just some prose.' \
    'Nothing dramatic happens.' \
    'Words appear and then leave.' \
    > "$HEUR_CLEAN"

  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  # Invoke from the tmp repo so REPO_ROOT resolves to $TMPDIR_ST.
  # Pass relative paths so the exemption logic sees the repo-relative path,
  # matching how staged paths appear in pre-commit mode.
  set +e
  ST_DIRTY_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_DIRTY_RC=$?
  ST_CLEAN_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "clean.txt" 2>&1)
  ST_CLEAN_RC=$?
  ST_PLAN_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/plans/foo.md" 2>&1)
  ST_PLAN_RC=$?
  ST_EXEMPT_RULE_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "adapters/claude-code/rules/harness-hygiene.md" 2>&1)
  ST_EXEMPT_RULE_RC=$?
  ST_DECISION_ALLOWED_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/decisions/001-foo.md" 2>&1)
  ST_DECISION_ALLOWED_RC=$?
  ST_DECISION_DRAFT_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/decisions/draft.md" 2>&1)
  ST_DECISION_DRAFT_RC=$?
  ST_REVIEW_ALLOWED_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/reviews/2026-05-04-foo.md" 2>&1)
  ST_REVIEW_ALLOWED_RC=$?

  # ---- Layer 2 heuristic invocations ----
  ST_HEUR_PATH_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "some-doc.md" 2>&1)
  ST_HEUR_PATH_RC=$?
  ST_HEUR_CLUSTER_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "cluster-doc.md" 2>&1)
  ST_HEUR_CLUSTER_RC=$?
  ST_HEUR_NL_PATH_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "adapters/claude-code/hooks/foo.sh" 2>&1)
  ST_HEUR_NL_PATH_RC=$?
  ST_HEUR_VOCAB_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "vocab-doc.md" 2>&1)
  ST_HEUR_VOCAB_RC=$?
  ST_HEUR_CLEAN_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "clean-prose.md" 2>&1)
  ST_HEUR_CLEAN_RC=$?

  # ---- Structured-waiver scenarios (F.5 audit row 12 / ADR 059 D4) ----
  # Reuses dirty.txt (the FORBIDDEN_TOKEN fixture) as the "novel false
  # positive" file the waiver covers.
  ST_WAIVER_STATE="$TMPDIR_ST/.claude/state"
  mkdir -p "$ST_WAIVER_STATE"

  # W1 — waiver-absent-blocks: no waiver file → same as plain dirty (exit 1)
  ST_W1_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_W1_RC=$?

  # W2 — waiver-honored: fresh waiver naming both clauses + Files: dirty.txt
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: dirty.txt is a self-test fixture, not a real leak"
    echo "Files: dirty.txt"
  } > "$ST_WAIVER_STATE/harness-hygiene-waiver-selftest.txt"
  ST_W2_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_W2_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-waiver-selftest.txt"

  # W3 — waiver-stale-rejected: same valid waiver but backdated >1h → BLOCK
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: dirty.txt is a self-test fixture, not a real leak"
    echo "Files: dirty.txt"
  } > "$ST_WAIVER_STATE/harness-hygiene-waiver-stale.txt"
  touch -d '2 hours ago' "$ST_WAIVER_STATE/harness-hygiene-waiver-stale.txt" 2>/dev/null \
    || touch -t "$(date -d '2 hours ago' +%Y%m%d%H%M.%S 2>/dev/null)" "$ST_WAIVER_STATE/harness-hygiene-waiver-stale.txt" 2>/dev/null \
    || true
  ST_W3_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_W3_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-waiver-stale.txt"

  # W4 — regression: waiver naming clauses but a DIFFERENT file → dirty.txt
  # still BLOCKS (per-file scoping actually scopes, not a blanket valve)
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: some other file is a self-test fixture, not a real leak"
    echo "Files: some-other-file.txt"
  } > "$ST_WAIVER_STATE/harness-hygiene-waiver-otherfile.txt"
  ST_W4_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_W4_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-waiver-otherfile.txt"

  # W5 — regression (pin f): non-empty waiver WITHOUT purpose-clause pair,
  # even with a matching Files: line, does NOT open the valve → BLOCK
  echo "Files: dirty.txt" > "$ST_WAIVER_STATE/harness-hygiene-waiver-weak.txt"
  ST_W5_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_W5_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-waiver-weak.txt"

  # ---- Codename-pattern scenarios (nl-issue [47]) ----
  # These run against the REAL shipped denylist (copied verbatim into a
  # second temp repo) so they exercise the actual pattern that ships —
  # including that the whole patterns file still compiles under
  # `grep -iE -f` (one invalid ERE makes grep exit 2, which the scanner
  # reads as "no match": ALL of Layer 1 would silently no-op).
  # One product codename is also a generic electrical-engineering noun; the
  # shipped pattern must catch it standalone (prose either case, file paths,
  # identifiers, end-of-line) but must NOT catch the generic two-word idiom
  # "<word> breaker" / "<word>-breaker", which false-blocked PR #91.
  # Loud SKIP when the real denylist is not reachable (e.g. the script runs
  # from a live ~/.claude copy outside the repo checkout).
  ST_C_SKIP=1
  REAL_ROOT=$(git -C "$(dirname "$SCRIPT_PATH")" rev-parse --show-toplevel 2>/dev/null || true)
  REAL_DENYLIST="$REAL_ROOT/adapters/claude-code/patterns/harness-denylist.txt"
  if [ -n "$REAL_ROOT" ] && [ -f "$REAL_DENYLIST" ]; then
    ST_C_SKIP=0
    TMPDIR_C="$TMPDIR_ST/codename-repo"
    mkdir -p "$TMPDIR_C/adapters/claude-code/patterns"
    cp "$REAL_DENYLIST" "$TMPDIR_C/adapters/claude-code/patterns/harness-denylist.txt"
    (
      cd "$TMPDIR_C" || exit 1
      git init -q . >/dev/null 2>&1
      git config user.email "selftest@example.com"
      git config user.name "selftest"
    )
    # Positives — the codename must still trip in every real leak context:
    printf '%s\n' 'the circuit rollout is delayed'                  > "$TMPDIR_C/c1-prose-lower.md"
    printf '%s\n' 'The Circuit rollout starts tomorrow.'            > "$TMPDIR_C/c2-prose-upper.md"
    printf '%s\n' 'stored under repos/circuit/config.yaml today'    > "$TMPDIR_C/c3-filepath.md"
    printf '%s\n' 'export circuit_env=prod for the test run'        > "$TMPDIR_C/c4-identifier.md"
    printf '%s\n' 'first enable circuit'                            > "$TMPDIR_C/c5-eol.md"
    # Negatives — the generic idiom must NOT trip (nl-issue [47] / PR #91):
    printf '%s\n' 'a circuit breaker guards the spawn path'         > "$TMPDIR_C/c6-idiom-space.md"
    printf '%s\n' 'add a circuit-breaker to the retry loop'         > "$TMPDIR_C/c7-idiom-hyphen.md"
    printf '%s\n' 'The Circuit Breaker pattern is well documented.' > "$TMPDIR_C/c8-idiom-caps.md"
    printf '%s\n' 'plain control prose with nothing special'        > "$TMPDIR_C/c9-clean.md"

    ST_C1_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c1-prose-lower.md" 2>&1); ST_C1_RC=$?
    ST_C2_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c2-prose-upper.md" 2>&1); ST_C2_RC=$?
    ST_C3_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c3-filepath.md" 2>&1); ST_C3_RC=$?
    ST_C4_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c4-identifier.md" 2>&1); ST_C4_RC=$?
    ST_C5_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c5-eol.md" 2>&1); ST_C5_RC=$?
    ST_C6_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c6-idiom-space.md" 2>&1); ST_C6_RC=$?
    ST_C7_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c7-idiom-hyphen.md" 2>&1); ST_C7_RC=$?
    ST_C8_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c8-idiom-caps.md" 2>&1); ST_C8_RC=$?
    ST_C9_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c9-clean.md" 2>&1); ST_C9_RC=$?
  fi

  # ---- Machine-local secret-layer scenario (nl-issue [25] / GAP-56) ----
  # The literal credential VALUE relocated out of the shipped denylist must
  # never re-enter this repo's tracked tree. When the machine-local layer
  # (~/.claude/business-patterns.d/*.txt) exists, grep every tracked file of
  # the REAL repo for each of its patterns — zero matches required. Loud
  # SKIP where the layer or the repo checkout is absent (e.g. CI runners).
  ST_D_SKIP=1
  ST_D_OUT=""
  ST_D_RC=1
  BPD_DIR="$HOME/.claude/business-patterns.d"
  if [ -n "$REAL_ROOT" ] && [ -d "$BPD_DIR" ]; then
    BPD_PATS="$TMPDIR_ST/bpd-patterns.txt"
    cat "$BPD_DIR"/*.txt 2>/dev/null | awk '
      { gsub(/\r$/, "") }
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*#/ { next }
      { print }
    ' > "$BPD_PATS"
    if [ -s "$BPD_PATS" ]; then
      ST_D_SKIP=0
      ST_D_OUT=$(git -C "$REAL_ROOT" grep -I -i -l -E -f "$BPD_PATS" 2>&1)
      ST_D_RC=$?
    fi
  fi

  set -e

  FAIL=0
  if [ "$ST_DIRTY_RC" -ne 1 ]; then
    echo "self-test: FAIL — expected exit 1 on dirty file, got $ST_DIRTY_RC" >&2
    echo "output was:" >&2
    echo "$ST_DIRTY_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_DIRTY_OUT" | grep -q 'FORBIDDEN_TOKEN'; then
    echo "self-test: FAIL — dirty output did not mention the matched token" >&2
    echo "output was:" >&2
    echo "$ST_DIRTY_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_CLEAN_RC" -ne 0 ]; then
    echo "self-test: FAIL — expected exit 0 on clean file, got $ST_CLEAN_RC" >&2
    echo "output was:" >&2
    echo "$ST_CLEAN_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_PLAN_RC" -ne 1 ]; then
    echo "self-test: FAIL — expected exit 1 on docs/plans/foo.md (no longer exempt), got $ST_PLAN_RC" >&2
    echo "(NL commits its own plans now; docs/plans/ is subject to hygiene)" >&2
    echo "output was:" >&2
    echo "$ST_PLAN_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_EXEMPT_RULE_RC" -ne 0 ]; then
    echo "self-test: FAIL — expected exit 0 on exempt rules/harness-hygiene.md, got $ST_EXEMPT_RULE_RC" >&2
    echo "(exemption logic did not trigger; scanner would have blocked a harness-hygiene rule file)" >&2
    echo "output was:" >&2
    echo "$ST_EXEMPT_RULE_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_DECISION_ALLOWED_RC" -ne 1 ]; then
    echo "self-test: FAIL — expected exit 1 on allow-listed docs/decisions/001-foo.md, got $ST_DECISION_ALLOWED_RC" >&2
    echo "(committed decision files MUST be scanned; only gitignored drafts are exempt)" >&2
    echo "output was:" >&2
    echo "$ST_DECISION_ALLOWED_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_DECISION_DRAFT_RC" -ne 0 ]; then
    echo "self-test: FAIL — expected exit 0 on non-allow-listed docs/decisions/draft.md (gitignored), got $ST_DECISION_DRAFT_RC" >&2
    echo "(non-NNN-prefixed files in docs/decisions/ are instance artifacts, still exempt)" >&2
    echo "output was:" >&2
    echo "$ST_DECISION_DRAFT_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_REVIEW_ALLOWED_RC" -ne 1 ]; then
    echo "self-test: FAIL — expected exit 1 on allow-listed docs/reviews/2026-05-04-foo.md, got $ST_REVIEW_ALLOWED_RC" >&2
    echo "(committed review files MUST be scanned)" >&2
    echo "output was:" >&2
    echo "$ST_REVIEW_ALLOWED_OUT" >&2
    FAIL=1
  fi

  # ---- Layer 2 heuristic assertions ----
  # h1: positive path-shape match outside NL-prefix paths must BLOCK with [heuristic] label
  if [ "$ST_HEUR_PATH_RC" -ne 1 ]; then
    echo "self-test: FAIL (h1) — expected exit 1 on path-shape match in some-doc.md, got $ST_HEUR_PATH_RC" >&2
    echo "(file mentions app/api/v1/users/ outside NL-prefix paths and should be blocked)" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_PATH_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_HEUR_PATH_OUT" | grep -q '\[heuristic\]'; then
    echo "self-test: FAIL (h1) — path-shape match output did not carry [heuristic] label" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_PATH_OUT" >&2
    FAIL=1
  fi
  # h2: positive cluster match (Examplecorp x5) must BLOCK with [heuristic] label
  if [ "$ST_HEUR_CLUSTER_RC" -ne 1 ]; then
    echo "self-test: FAIL (h2) — expected exit 1 on cluster match in cluster-doc.md, got $ST_HEUR_CLUSTER_RC" >&2
    echo "(file mentions 'Examplecorp' 5+ times, not in NL vocabulary allowlist)" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_CLUSTER_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_HEUR_CLUSTER_OUT" | grep -q 'Examplecorp'; then
    echo "self-test: FAIL (h2) — cluster output did not mention the matched token Examplecorp" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_CLUSTER_OUT" >&2
    FAIL=1
  fi
  # h3: NEGATIVE — NL-prefix path with project-internal-looking path-shape must NOT fire path-shape heuristic
  if [ "$ST_HEUR_NL_PATH_RC" -ne 0 ]; then
    echo "self-test: FAIL (h3) — expected exit 0 on NL-prefix file mentioning a path, got $ST_HEUR_NL_PATH_RC" >&2
    echo "(adapters/claude-code/hooks/foo.sh is NL-prefix exempt for path-shape detection)" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_NL_PATH_OUT" >&2
    FAIL=1
  fi
  # h4: NEGATIVE — vocabulary token Promise x5 must NOT fire cluster heuristic
  if [ "$ST_HEUR_VOCAB_RC" -ne 0 ]; then
    echo "self-test: FAIL (h4) — expected exit 0 on vocab-doc.md (Promise in allowlist), got $ST_HEUR_VOCAB_RC" >&2
    echo "(Promise appears 5x but is in NL_VOCAB_ALLOWLIST — should not fire)" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_VOCAB_OUT" >&2
    FAIL=1
  fi
  # h5: NEGATIVE — clean prose must produce no heuristic matches
  if [ "$ST_HEUR_CLEAN_RC" -ne 0 ]; then
    echo "self-test: FAIL (h5) — expected exit 0 on clean-prose.md, got $ST_HEUR_CLEAN_RC" >&2
    echo "(no project-internal shapes and no repeated non-allowlist clusters)" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_CLEAN_OUT" >&2
    FAIL=1
  fi

  # ---- Structured-waiver assertions (F.5 audit row 12 / ADR 059 D4) ----
  # W1: waiver-absent-blocks
  if [ "$ST_W1_RC" -ne 1 ]; then
    echo "self-test: FAIL (w1) — waiver-absent expected exit 1, got $ST_W1_RC" >&2
    echo "$ST_W1_OUT" >&2
    FAIL=1
  fi
  # W2: waiver-honored (fresh, both clauses, Files: matches) → ALLOW
  if [ "$ST_W2_RC" -ne 0 ]; then
    echo "self-test: FAIL (w2) — waiver-honored expected exit 0, got $ST_W2_RC" >&2
    echo "$ST_W2_OUT" >&2
    FAIL=1
  fi
  # W3: waiver-stale-rejected (>1h old) → BLOCK
  if [ "$ST_W3_RC" -ne 1 ]; then
    echo "self-test: FAIL (w3) — waiver-stale expected exit 1, got $ST_W3_RC" >&2
    echo "$ST_W3_OUT" >&2
    FAIL=1
  fi
  # W4: waiver names a DIFFERENT file → dirty.txt still BLOCKS (scoping works)
  if [ "$ST_W4_RC" -ne 1 ]; then
    echo "self-test: FAIL (w4) — waiver for a different file must not cover dirty.txt, expected exit 1, got $ST_W4_RC" >&2
    echo "$ST_W4_OUT" >&2
    FAIL=1
  fi
  # W5: non-empty waiver without purpose-clause pair (pin f) → BLOCK
  if [ "$ST_W5_RC" -ne 1 ]; then
    echo "self-test: FAIL (w5) — weak waiver (no purpose-clauses) expected exit 1, got $ST_W5_RC" >&2
    echo "$ST_W5_OUT" >&2
    FAIL=1
  fi

  # ---- Codename-pattern assertions (nl-issue [47]) ----
  if [ "$ST_C_SKIP" -eq 1 ]; then
    echo "self-test: SKIP (c1-c9) — real shipped denylist not reachable from this script location; run from the repo checkout to exercise the codename-pattern scenarios" >&2
  else
    # c1-c5: the codename must trip, and via Layer 1 ([denylist] label) —
    # a heuristic-caused block would be a false pass for the pattern.
    if [ "$ST_C1_RC" -ne 1 ] || ! printf '%s' "$ST_C1_OUT" | grep -q '\[denylist\]'; then
      echo "self-test: FAIL (c1) — lowercase codename in prose must trip the denylist (expected exit 1 + [denylist], got $ST_C1_RC)" >&2
      echo "$ST_C1_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C2_RC" -ne 1 ] || ! printf '%s' "$ST_C2_OUT" | grep -q '\[denylist\]'; then
      echo "self-test: FAIL (c2) — capitalized codename in prose must trip the denylist (expected exit 1 + [denylist], got $ST_C2_RC)" >&2
      echo "$ST_C2_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C3_RC" -ne 1 ] || ! printf '%s' "$ST_C3_OUT" | grep -q '\[denylist\]'; then
      echo "self-test: FAIL (c3) — codename inside a file path must trip the denylist (expected exit 1 + [denylist], got $ST_C3_RC)" >&2
      echo "$ST_C3_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C4_RC" -ne 1 ] || ! printf '%s' "$ST_C4_OUT" | grep -q '\[denylist\]'; then
      echo "self-test: FAIL (c4) — codename inside an identifier must trip the denylist (expected exit 1 + [denylist], got $ST_C4_RC)" >&2
      echo "$ST_C4_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C5_RC" -ne 1 ] || ! printf '%s' "$ST_C5_OUT" | grep -q '\[denylist\]'; then
      echo "self-test: FAIL (c5) — codename at end-of-line must trip the denylist (expected exit 1 + [denylist], got $ST_C5_RC)" >&2
      echo "$ST_C5_OUT" >&2
      FAIL=1
    fi
    # c6-c8: the generic "<word> breaker" idiom must NOT trip (PR #91 class)
    if [ "$ST_C6_RC" -ne 0 ]; then
      echo "self-test: FAIL (c6) — generic '<word> breaker' prose must NOT trip (nl-issue [47]), expected exit 0, got $ST_C6_RC" >&2
      echo "$ST_C6_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C7_RC" -ne 0 ]; then
      echo "self-test: FAIL (c7) — generic '<word>-breaker' prose must NOT trip (nl-issue [47]), expected exit 0, got $ST_C7_RC" >&2
      echo "$ST_C7_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C8_RC" -ne 0 ]; then
      echo "self-test: FAIL (c8) — capitalized '<Word> Breaker' prose must NOT trip (scan is -i; nl-issue [47]), expected exit 0, got $ST_C8_RC" >&2
      echo "$ST_C8_OUT" >&2
      FAIL=1
    fi
    # c9: clean control — guards against an "everything matches" pathology
    # (e.g. an invalid ERE degrading grep, or an over-broad new pattern).
    if [ "$ST_C9_RC" -ne 0 ]; then
      echo "self-test: FAIL (c9) — clean control file must pass with the full real denylist, expected exit 0, got $ST_C9_RC" >&2
      echo "$ST_C9_OUT" >&2
      FAIL=1
    fi
  fi

  # ---- Machine-local secret-layer assertion (nl-issue [25] / GAP-56) ----
  if [ "$ST_D_SKIP" -eq 1 ]; then
    echo "self-test: SKIP (d) — machine-local ~/.claude/business-patterns.d layer absent or repo checkout not reachable (expected on CI runners)" >&2
  elif [ "$ST_D_RC" -eq 0 ]; then
    echo "self-test: FAIL (d) — a machine-local secret-layer pattern matches tracked file(s) in this repo; the relocated literal (or another local-layer secret) has re-entered the tree:" >&2
    echo "$ST_D_OUT" >&2
    FAIL=1
  elif [ "$ST_D_RC" -ne 1 ]; then
    echo "self-test: FAIL (d) — git grep errored (exit $ST_D_RC) while checking the machine-local secret layer against the tree:" >&2
    echo "$ST_D_OUT" >&2
    FAIL=1
  fi

  if [ "$FAIL" -eq 0 ]; then
    echo "self-test: OK"
    exit 0
  fi
  exit 1
fi

# ---------- repo discovery -----------------------------------------------

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$REPO_ROOT" ]; then
  # Not in a git repo — silent no-op.
  exit 0
fi

DENYLIST_FILE="$REPO_ROOT/adapters/claude-code/patterns/harness-denylist.txt"
if [ ! -f "$DENYLIST_FILE" ]; then
  echo "harness-hygiene-scan: denylist not found at $DENYLIST_FILE — skipping (this is expected before Phase 2 deploy)" >&2
  exit 0
fi

# ---------- build the regex patterns file grep will read ------------------
# We strip comments and blank lines so grep -f only sees real patterns.
PATTERNS_TMP=$(mktemp)
trap 'rm -f "$PATTERNS_TMP"' EXIT

awk '
  # skip blank lines and comment-only lines
  /^[[:space:]]*$/ { next }
  /^[[:space:]]*#/ { next }
  { print }
' "$DENYLIST_FILE" > "$PATTERNS_TMP"

# If every line of the denylist was blank/comment, there is nothing to match.
if [ ! -s "$PATTERNS_TMP" ]; then
  exit 0
fi

# ---------- Layer 2: heuristic detection ---------------------------------
#
# check_heuristics() — invoked per file after the denylist scan. Detects
# project-specific content shapes the literal denylist cannot catch.
#
# Two sub-checks:
#   (a) project-internal file-path shapes (e.g., `app/api/v1/users/`,
#       `src/components/MyComponent.tsx`, `supabase/migrations/<14>_<slug>.sql`)
#   (b) repeated capitalized-term clusters: 3+ occurrences of the same
#       `[A-Z][a-z]{4,15}` token within a single file, EXCLUDING tokens in
#       the NL-vocabulary allowlist
#
# Both sub-checks are SKIPPED for files inside known NL-prefix paths.
# See `is_path_shape_exempt` below for the authoritative list — broadly:
# `adapters/`, `principles/`, `patterns/`, `templates/`, `evals/`,
# `.github/`, `docs/`, the synced `~/.claude/` mirror, and well-known
# root prose files (README, CONTRIBUTING, LICENSE, etc.).
#
# Rationale: NL's own documentation legitimately (a) cites path-shapes
# in prose AND (b) discusses domain vocabulary terms repeatedly in the
# same file (e.g., a doc about Acceptance Scenarios says "Acceptance"
# many times). Maintaining an exhaustive vocabulary allowlist for every
# doc-domain term would not converge; the path-prefix exemption is the
# cleaner mechanism. Files OUTSIDE these prefixes (project-instance
# content, downstream consumer code, instance fixtures) face full
# scrutiny.
#
# Args: $1 = repo-relative path, $2 = absolute path
# Side-effects: appends matches to $MATCHES_TMP, increments $MATCH_COUNT
# Returns: 0 always (caller continues regardless).

# NL vocabulary allowlist for cluster detection. Tokens here will not
# trigger the cluster heuristic even if they appear 3+ times in a single
# file. Case-insensitive match. Add new tokens here if a legitimate term
# triggers false positives in practice (typically a JS/TS built-in or
# harness primitive that downstream consumer code uses heavily).
#
# Note: NL's own documentation files are exempted from cluster detection
# entirely via the path-prefix exemption in check_heuristics(); this
# allowlist is for the surviving scan surface (downstream consumer code,
# instance project files), where common JS/TS built-ins might still
# legitimately appear 3+ times.
NL_VOCAB_ALLOWLIST="Neural|Lace|Claude|Anthropic|Build|Doctrine|Generation|Pattern|Mechanism|Status|Mode|Plan|Phase|Hook|Agent|Skill|Decision|Discovery|Backlog|Promise|Object|Array|String|Boolean|Number|Function|Error|Component|Module|Project|Session|Source|Target|Update|Create|Action|Result|Verdict|Worker|Builder|Reviewer|Verifier|Method|Output|Input|Origin|Master|Branch|Commit"

# Returns 0 if the heuristic checks should be SKIPPED for this file
# (file lives inside an NL-prefix path where prose mentions of paths
# AND repeated domain vocabulary are legitimate). Returns 1 if the
# heuristic should run.
#
# Rationale: NL's harness repo is documentation-dense. A doc about
# "Acceptance Scenarios" mentions "Acceptance" 16 times; a rule about
# "Trust" mentions Trust dozens of times; a plan about kanban mentions
# "Kanban" repeatedly. Maintaining an exhaustive vocabulary allowlist
# would not converge. The path-prefix exemption is the cleaner mechanism:
# NL-internal directories are exempt; downstream consumer code (the
# scanner's actual target audience) faces full scrutiny.
is_path_shape_exempt() {
  local path="$1"
  case "$path" in
    # NL-internal harness directories — these legitimately cite paths
    # AND discuss domain vocabulary repeatedly in prose.
    adapters/*|adapters) return 0 ;;
    principles/*|principles) return 0 ;;
    patterns/*|patterns) return 0 ;;
    templates/*|templates) return 0 ;;
    evals/*|evals) return 0 ;;
    .github/*|.github) return 0 ;;
    docs/*|docs) return 0 ;;
    # Build Doctrine integration directories (added 2026-05-05 per
    # Tranche 0b migration). The doctrine layer's vocabulary (Tranche,
    # Engineering, Catalog, Curator, Adversarial, Findings, Mechanical,
    # Orchestrator, Architecture, etc.) is repetitive prose by design;
    # exempting these directories matches the same logic as exempting
    # adapters/ and principles/. Templates dir holds default content
    # that ships with NL and is part of the harness layer, not
    # project-instance content.
    build-doctrine/*|build-doctrine) return 0 ;;
    build-doctrine-templates/*|build-doctrine-templates) return 0 ;;
    build-doctrine-orchestrator/*|build-doctrine-orchestrator) return 0 ;;
    # Conversation-Tree UI module (NL's own product code under neural-lace/).
    # Its domain vocabulary (Dispatch, State, Context, Content, Node, Branch)
    # is repetitive BY DESIGN — the module is literally a tracker of the
    # Dispatch conversation-tree state, so the Layer-2 cluster heuristic
    # false-positives on every file. Structural path-prefix exemption per
    # harness-hygiene.md "How to add false-positive exemptions"; same logic
    # as adapters/ and build-doctrine/. (workstreams-ui, formerly
    # conversation-tree-ui — both exempted during the 2026-05-30 rename window.)
    neural-lace/workstreams-ui/*|neural-lace/workstreams-ui) return 0 ;;
    neural-lace/conversation-tree-ui/*|neural-lace/conversation-tree-ui) return 0 ;;
    # The synced `~/.claude/` mirror (when scanning that tree directly).
    *.claude/*|*/.claude/*) return 0 ;;
    # NL-root prose files (README, CONTRIBUTING, LICENSE, SETUP,
    # CODE_OF_CONDUCT, CHANGELOG) — these are documentation, not
    # project-instance content.
    # .gitattributes added 2026-07-06 (GAP-55): its explanatory comments
    # legitimately repeat platform terms (cluster-heuristic FP); the
    # Layer-1 denylist still scans it.
    README.md|README|CONTRIBUTING.md|LICENSE|LICENSE.md|SETUP.md|CODE_OF_CONDUCT.md|CHANGELOG.md|SECURITY.md|.gitattributes) return 0 ;;
    # `.pr-description.md` is a per-PR transient file consumed by
    # `gh pr create --body-file` (canonical convention per
    # `adapters/claude-code/git-hooks/pre-push-pr-template.sh`). It
    # naturally repeats PR-shape domain vocabulary (Template, Inline,
    # Check, Summary, Mechanism) and discusses paths inside the PR. Same
    # logic as the other root-level prose-file exemptions above.
    .pr-description.md) return 0 ;;
  esac
  return 1
}

check_heuristics() {
  local rel_path="$1"
  local abs_path="$2"

  # NL-prefix paths are exempt from BOTH heuristic sub-checks. NL prose
  # legitimately cites path-shapes AND discusses domain vocabulary
  # repeatedly. See the function-header comment for the full rationale.
  if is_path_shape_exempt "$rel_path"; then
    return 0
  fi

  # ---- (a) project-internal file-path shapes ----
  # Three high-signal path-shape regexes (POSIX ERE — no \d / \w):
  #   - app/api/v<digits>/<slug>/
  #   - src/components/<PascalCase>.tsx
  #   - supabase/migrations/<14-digit>_<slug>.sql
  local heur_pattern='(app/api/v[0-9]+/[a-zA-Z0-9_-]+/)|(src/components/[A-Z][a-zA-Z0-9_]+\.tsx)|(supabase/migrations/[0-9]{14}_[a-zA-Z0-9_-]+\.sql)'
  if heur_out=$(grep -EnIH "$heur_pattern" "$abs_path" 2>/dev/null); then
    while IFS= read -r match_line; do
      [ -z "$match_line" ] && continue
      rest="${match_line#$abs_path:}"
      lineno="${rest%%:*}"
      content="${rest#*:}"
      if [ "${#content}" -gt 120 ]; then
        content="${content:0:117}..."
      fi
      printf '[heuristic] %s\n' "$rel_path:$lineno: $content" >> "$MATCHES_TMP"
      MATCH_COUNT=$((MATCH_COUNT + 1))
    done <<< "$heur_out"
  fi

  # ---- (b) repeated capitalized-term clusters ----
  # Find tokens [A-Z][a-z]{4,15} appearing 3+ times in this file, where
  # NONE of the occurrences match the NL vocabulary allowlist (case-insensitive).
  # Strategy:
  #   1. Extract all [A-Z][a-z]{4,15} tokens from the file.
  #   2. Filter out allowlisted tokens (case-insensitive).
  #   3. Sort + uniq -c to count each remaining token.
  #   4. Keep tokens with count >= 3.
  #   5. For each, find the first line in the file where it appears and
  #      report it.
  local tokens
  tokens=$(grep -oE '[A-Z][a-z]{4,15}' "$abs_path" 2>/dev/null \
    | grep -ivE "^($NL_VOCAB_ALLOWLIST)$" \
    | sort \
    | uniq -c \
    | awk '$1 >= 3 { print $2 }')

  if [ -n "$tokens" ]; then
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      # Locate first occurrence of the token (use word-boundary-ish match).
      first_hit=$(grep -nE "\\b$tok\\b" "$abs_path" 2>/dev/null | head -n 1)
      [ -z "$first_hit" ] && continue
      lineno="${first_hit%%:*}"
      content="${first_hit#*:}"
      if [ "${#content}" -gt 120 ]; then
        content="${content:0:117}..."
      fi
      count=$(grep -oE "\\b$tok\\b" "$abs_path" 2>/dev/null | wc -l | tr -d ' ')
      printf '[heuristic] %s:%s: repeated term "%s" (x%s): %s\n' \
        "$rel_path" "$lineno" "$tok" "$count" "$content" >> "$MATCHES_TMP"
      MATCH_COUNT=$((MATCH_COUNT + 1))
    done <<< "$tokens"
  fi

  return 0
}

# ---------- exemption check ----------------------------------------------

# Returns 0 if the path should be skipped, 1 otherwise.
is_exempt() {
  local path="$1"

  # The denylist file itself (matches would be infinite)
  case "$path" in
    adapters/claude-code/patterns/harness-denylist.txt) return 0 ;;
  esac

  # Harness-hygiene rule files and scanner internals — these files legitimately
  # name the forbidden patterns in order to document or enforce them. Scanning
  # them would be a self-match loop.
  case "$path" in
    principles/harness-hygiene.md) return 0 ;;
    adapters/claude-code/rules/harness-hygiene.md) return 0 ;;
    adapters/claude-code/doctrine/harness-hygiene-full.md) return 0 ;;
    principles/forward-compatibility.md) return 0 ;;
    adapters/claude-code/git-hooks/pre-commit) return 0 ;;
    adapters/claude-code/hooks/harness-hygiene-scan.sh) return 0 ;;
    adapters/claude-code/hooks/decisions-index-gate.sh) return 0 ;;
  esac

  # SECRET-SCAN-CI-BACKSTOP-01 fixture files. These deliberately contain
  # AWS's own public documentation placeholder access-key ID
  # (AKIAIOSFODNN7EXAMPLE — never a live credential) so the CI-backstop
  # oracle can be proven locally against a real flagless-shape pattern
  # match, matching pre-push-scan.sh's AKIA[0-9A-Z]{16} regex by design.
  # Same class as sensitive-patterns.local.example (hooks/pre-push-scan.sh
  # header) — a fixture that intentionally names the pattern it tests.
  case "$path" in
    adapters/claude-code/tests/secret-backstop-fixture-check.sh) return 0 ;;
    docs/plans/secret-scan-ci-backstop-skip.md) return 0 ;;
  esac

  # Instance-specific operations tooling exemptions.
  #
  # These files are intentionally named after the specific downstream product
  # they monitor. They live in neural-lace per the operator's placement
  # directive (orchestrator integration via the generic external-monitor
  # SessionStart surfacer requires the probe + runbook + plan to be
  # co-located with the harness mirror). They are NOT generic harness-kit
  # files; they ARE operations tooling for one specific deployment.
  #
  # The surfacer hook itself (`external-monitor-alert-surfacer.sh`) is generic
  # by design and does NOT need exemption — it reads alerts from any
  # configured directory.
  case "$path" in
    tools/circuit-health-probe.sh) return 0 ;;
    docs/operations/circuit-health-monitor-*.md) return 0 ;;
    docs/plans/circuit-prod-health-monitor.md) return 0 ;;
    docs/plans/archive/circuit-prod-health-monitor.md) return 0 ;;
  esac

  # Workstreams UI (formerly conversation-tree-ui) web client — the operator's
  # own machine-state tracker GUI, co-located with the harness under the same
  # placement directive as the circuit-* operations tooling above. Its
  # repo-grouping block DERIVES the Repo -> Project tree from the operator's
  # REAL git remotes on THIS machine (PROJECT_REPO_DEFAULT / PROJECT_REPOS_MULTI
  # / REPO_ORDER), so it legitimately names the operator's accounts + repos —
  # that mapping IS the feature, and it is overridable per-machine via the
  # served `S.repoMap` or a node's own `.repo` field. NOT a generic harness-kit
  # surface; instance-specific operator tooling, exactly the category the
  # circuit-* exemptions cover. Layer-2 heuristics (path-shape / capitalized-
  # cluster detection) STILL scan these files for NEW leak shapes — only the
  # literal operator-identifier denylist is exempted for this subtree.
  case "$path" in
    neural-lace/workstreams-ui/web/*) return 0 ;;
    neural-lace/conversation-tree-ui/web/*) return 0 ;;
    # scripts/ extension (2026-07-06, GAP-55 sweep, operator triage rubric):
    # the seed/backfill scripts under scripts/ name the operator's projects
    # for the same reason web/ does — the Repo -> Project mapping IS the
    # feature. Same subtree, same class, same Layer-2-still-scans posture.
    neural-lace/workstreams-ui/scripts/*) return 0 ;;
    neural-lace/conversation-tree-ui/scripts/*) return 0 ;;
  esac

  # Public-by-design repo-architecture documentation (operator directive
  # 2026-07-06, GAP-55 triage rubric: benign -> exempt with provenance note;
  # genuinely-private -> redact, which was done separately in the same
  # commit). These specific committed docs DOCUMENT this repo's own
  # two-remote architecture, PR trail, and machine estate — the org/account
  # names and downstream-product references ARE their subject matter, and
  # the operator ruled the mirror public by design (docs/backlog.md
  # HARNESS-GAP-55). File-by-file on purpose: NEW docs are NOT exempt and
  # face the full denylist. The two synthetic-ci entries carry their
  # archive/ twins so plan-lifecycle archiving does not un-exempt them.
  case "$path" in
    docs/discoveries/2026-05-27-neural-lace-fork-deep-dive-and-sync-strategy.md) return 0 ;;
    docs/discoveries/2026-05-30-conv-tree-work-first-reframe-design.md) return 0 ;;
    docs/discoveries/2026-06-02-pt-personal-fork-reconcile-and-adr-renumber.md) return 0 ;;
    docs/discoveries/2026-06-03-workstreams-tree-design-misread-and-repo-tier.md) return 0 ;;
    docs/decisions/039-conv-tree-reconciliation-over-interception.md) return 0 ;;
    docs/plans/archive/ci-server-side-enforcement-2026-05-23.md) return 0 ;;
    docs/plans/archive/git-bestpractices-9-item-initiative-2026-05-29.md) return 0 ;;
    docs/plans/archive/neural-lace-mirror-automation-evidence.md) return 0 ;;
    docs/plans/archive/scope-gate-rebase-exemption.md) return 0 ;;
    docs/plans/archive/windows-scope-gate-drive-letter-fix.md) return 0 ;;
    docs/plans/archive/workstreams-phase-1-2.md) return 0 ;;
    docs/plans/archive/workstreams-phase-3.md) return 0 ;;
    docs/plans/archive/worktree-spawn-primitive.md) return 0 ;;
    docs/plans/archive/workstreams-ui-status-surface-redesign-2026-06-11-evidence/tasks-10-11.evidence.md) return 0 ;;
    docs/plans/nl-overhaul-synthetic-ci-2026-07.md) return 0 ;;
    docs/plans/nl-overhaul-synthetic-ci-2026-07-evidence.md) return 0 ;;
    docs/plans/archive/nl-overhaul-synthetic-ci-2026-07.md) return 0 ;;
    docs/plans/archive/nl-overhaul-synthetic-ci-2026-07-evidence.md) return 0 ;;
  esac

  # Directory-prefix exemptions
  #
  # NOTE: docs/plans/ is NOT exempt. Neural Lace now commits its own
  # development plans (not downstream-project plans), so plan files
  # are subject to the same hygiene checks as any other committed file.
  #
  # decisions/reviews/sessions: directory-level exempt ONLY for paths
  # that are NOT allow-listed by .gitignore. Allow-listed paths are:
  #   - docs/decisions/NNN-*.md  (3-digit prefix)
  #   - docs/reviews/YYYY-MM-DD-*.md
  #   - docs/sessions/YYYY-MM-DD-*.md
  # Allow-listed files ship in the harness repo and must pass hygiene.
  # Non-allow-listed paths (instance artifacts, drafts) remain exempt.
  case "$path" in
    docs/decisions/[0-9][0-9][0-9]-*.md) ;; # NOT exempt — fall through
    docs/reviews/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;; # NOT exempt
    docs/sessions/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;; # NOT exempt
    docs/decisions/*|docs/decisions) return 0 ;;
    docs/reviews/*|docs/reviews|docs/sessions/*|docs/sessions) return 0 ;;
  esac

  case "$path" in
    SCRATCHPAD.md|*/SCRATCHPAD.md) return 0 ;;
  esac

  # Filename-suffix exemptions (example/placeholder files)
  case "$path" in
    *.example|*.example.json|*.example.sh|*.example.txt|*.example.md) return 0 ;;
  esac

  return 1
}

# ---------- file-list assembly -------------------------------------------

MODE="staged"
FILE_LIST_TMP=$(mktemp)
# extend trap: preserve removal of PATTERNS_TMP + also remove FILE_LIST_TMP
trap 'rm -f "$PATTERNS_TMP" "$FILE_LIST_TMP"' EXIT

if [ "${1:-}" = "--full-tree" ]; then
  MODE="full-tree"
  (cd "$REPO_ROOT" && git ls-files -z) > "$FILE_LIST_TMP"
elif [ "$#" -gt 0 ]; then
  MODE="files"
  # Pass each argv as null-terminated so filenames with spaces survive.
  for arg in "$@"; do
    printf '%s\0' "$arg"
  done > "$FILE_LIST_TMP"
else
  # Default: staged files for pre-commit
  (cd "$REPO_ROOT" && git diff --cached --name-only -z --diff-filter=ACMR) > "$FILE_LIST_TMP"
fi

if [ ! -s "$FILE_LIST_TMP" ]; then
  exit 0
fi

# ---------- scan each file -----------------------------------------------

MATCH_COUNT=0
WAIVED_COUNT=0
MATCHES_TMP=$(mktemp)
trap 'rm -f "$PATTERNS_TMP" "$FILE_LIST_TMP" "$MATCHES_TMP"' EXIT

# Structured-waiver files (F.5 audit row 12 / ADR 059 D4). Computed once per
# run; state dir resolves relative to REPO_ROOT so pre-commit invocations
# (which run with cwd=REPO_ROOT) and the self-test's own tmp repos agree.
HHS_STATE_DIR="${CLAUDE_STATE_DIR:-$REPO_ROOT/.claude/state}"
HHS_WAIVED_FILES_TMP=$(mktemp)
trap 'rm -f "$PATTERNS_TMP" "$FILE_LIST_TMP" "$MATCHES_TMP" "$HHS_WAIVED_FILES_TMP"' EXIT
_hhs_waived_files "$HHS_STATE_DIR" > "$HHS_WAIVED_FILES_TMP" 2>/dev/null || true

_hhs_is_waived() {
  local path="$1"
  [ -s "$HHS_WAIVED_FILES_TMP" ] || return 1
  grep -qFx "$path" "$HHS_WAIVED_FILES_TMP" 2>/dev/null
}

# Read the null-delimited file list.
while IFS= read -r -d '' rel_path; do
  [ -z "$rel_path" ] && continue

  # Resolve to absolute path for reading
  if [ "${rel_path:0:1}" = "/" ]; then
    abs_path="$rel_path"
    # For exemption check, try to make it relative to REPO_ROOT
    case "$abs_path" in
      "$REPO_ROOT"/*) check_path="${abs_path#$REPO_ROOT/}" ;;
      *) check_path="$abs_path" ;;
    esac
  else
    abs_path="$REPO_ROOT/$rel_path"
    check_path="$rel_path"
  fi

  # Skip missing files (e.g., deleted from working tree but staged before amend)
  [ -f "$abs_path" ] || continue

  # Skip exempt paths
  if is_exempt "$check_path"; then
    continue
  fi

  # Skip files covered by a fresh, purpose-clause-valid structured waiver
  # (F.5 audit row 12 / ADR 059 D4) — per-file, per-run, distinct from the
  # durable exempt-list above.
  if _hhs_is_waived "$check_path"; then
    WAIVED_COUNT=$((WAIVED_COUNT + 1))
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "harness-hygiene-scan" "waiver" "file=$check_path"
    continue
  fi

  # ---- Layer 1: denylist scan ----
  # Run grep with:
  #   -i   case-insensitive
  #   -E   extended regex
  #   -n   line numbers
  #   -I   skip binary files
  #   -H   always print filename
  #   -f   patterns from file
  # Output: <filename>:<line>:<content>
  if grep_out=$(grep -iEnIHf "$PATTERNS_TMP" "$abs_path" 2>/dev/null); then
    # Replace the absolute path prefix with the repo-relative path in the output
    # so reports are readable and stable across clones.
    while IFS= read -r match_line; do
      [ -z "$match_line" ] && continue
      # match_line looks like: /abs/path:LINE:content
      # Strip the abs path + colon, then prepend the relative path.
      rest="${match_line#$abs_path:}"
      # Pattern that matched is not reported by grep -f; we surface the line
      # and let the user see which denylist entry caught it.
      lineno="${rest%%:*}"
      content="${rest#*:}"
      # Truncate content to 120 chars
      if [ "${#content}" -gt 120 ]; then
        content="${content:0:117}..."
      fi
      printf '[denylist] %s\n' "$check_path:$lineno: $content" >> "$MATCHES_TMP"
      MATCH_COUNT=$((MATCH_COUNT + 1))
    done <<< "$grep_out"
  fi

  # ---- Layer 2: heuristic detection ----
  check_heuristics "$check_path" "$abs_path"
done < "$FILE_LIST_TMP"

# ---------- report -------------------------------------------------------

if [ "$MATCH_COUNT" -eq 0 ]; then
  exit 0
fi

if [ "$MODE" = "full-tree" ]; then
  header="HARNESS HYGIENE SCAN — FULL TREE — $MATCH_COUNT MATCHES"
else
  header="HARNESS HYGIENE SCAN — BLOCKED"
fi

{
  echo ""
  echo "================================================================"
  echo "$header"
  echo "================================================================"
  echo ""
  echo "The following content matches patterns in the harness denylist."
  echo "Harness repos must not ship personal/business identifiers. Clean"
  echo "these up, or add the file to the scanner exemption list if the"
  echo "match is legitimate and durable."
  echo ""
  cat "$MATCHES_TMP"
  echo ""
  echo "Hatch (cost: suppresses matches on ONLY the named file(s), this run,"
  echo "ledger-logged — never a blanket suppression of the whole scan):"
  echo "  A genuine NOVEL false-positive (not a known-legitimate file worth"
  echo "  a durable exemption) gets a fresh (<1h) structured waiver naming"
  echo "  BOTH purpose clauses AND the file(s) it covers:"
  echo "    mkdir -p $HHS_STATE_DIR && \\"
  echo "    { printf 'Purpose: this gate exists to prevent <X>\\n'; \\"
  echo "      printf 'Because: <Y>\\n'; \\"
  echo "      printf 'Files: <repo-relative-path> [<repo-relative-path> ...]\\n'; \\"
  echo "    } > $HHS_STATE_DIR/harness-hygiene-waiver-\$(date +%s).txt"
  echo "  Re-run the commit after writing the waiver."
  echo ""
  echo "Durable remedy: fix the content, or add the file to is_exempt() in this"
  echo "scanner (with a comment naming the exemption class) and stage both in the"
  echo "same commit. (git commit --no-verify skips only the git-native hook layer,"
  echo "cannot bypass this scan's PreToolUse wiring, and is prohibited without"
  echo "operator say-so — constitution §7.)"
  echo "Denylist: adapters/claude-code/patterns/harness-denylist.txt"
  echo "Rule: principles/harness-hygiene.md"
  echo "================================================================"
} >&2

exit 1
