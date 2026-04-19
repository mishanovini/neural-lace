#!/bin/bash
# NEURAL-LACE-REVIEW-FINDING-FIX-GATE v1 — enforces Rule 4: review-finding fixes update review file
#
# Classification: Mechanism (hook-enforced pre-commit blocker)
#
# Rule 4 (Document Freshness System): when a commit message references one
# or more review-finding IDs (tokens matching `[A-Z]{2,10}-[0-9]{1,4}` that
# actually appear in a `docs/reviews/*.md` file), require at least one
# `docs/reviews/*.md` file to ALSO be staged in the same commit — so the
# finding's status row (e.g., `Fixed: <SHA>`) can be updated atomically
# with the fix.
#
# This prevents the common failure mode where a fix commit claims to
# address UX-E04 but the review document still shows it as open.
#
# BEHAVIOR
#   1. No `.git/COMMIT_EDITMSG` or empty message    → ALLOW (can't classify)
#   2. Message has no <TAG>-NNN tokens              → ALLOW
#   3. No `docs/reviews/*.md` files exist in repo   → ALLOW (nothing to check)
#   4. Tokens exist but none appear in any review   → ALLOW (false-positive
#                                                     tokens like PR-123)
#   5. Real finding IDs AND no review file staged   → BLOCK (exit 1)
#   6. Real finding IDs AND >=1 review file staged  → ALLOW
#
# Token format: the regex `[A-Z]{2,10}-[A-Z]?[0-9]{1,4}` (with effective word
# boundaries provided by grep's default behavior on surrounding non-word chars)
# is permissive enough to cover common conventions (UX-E04, CONTENT-042,
# AUDIT-7, P1-12, etc.) while still rejecting arbitrary words. The optional
# single letter between the hyphen and digits handles "E04"-style IDs where
# the letter denotes a category within the review. Tokens are cross-checked
# against actual review files to filter false positives.
#
# Token-in-review detection: we search `docs/reviews/*.md` for tokens
# appearing as a standalone identifier. We accept matches anywhere the
# token appears bounded by non-word characters (start-of-line, pipe, space,
# parens, etc.) — this covers table rows, headings, and prose references.
#
# INVOCATION
#   1. Pre-commit chain:   review-finding-fix-gate.sh
#                          (no args — reads `.git/COMMIT_EDITMSG` + staged files)
#   2. Self-test:          review-finding-fix-gate.sh --self-test
#                          (runs internal assertions, prints OK/FAIL, exits)
#
# EXIT CODES
#   0 — allowed
#   1 — blocked (finding IDs referenced but no review file staged)

set -u

# ---------- self-test ----------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  (
    cd "$TMPDIR_ST" || exit 1
    git init -q . >/dev/null 2>&1
    git config user.email "selftest@example.test"
    git config user.name "selftest"
    mkdir -p docs/reviews
    echo "placeholder" > README.md
    # Seed a review file with a finding row
    cat > docs/reviews/2026-04-18-initial-audit.md <<'MD'
# Initial audit

| ID | Finding | Status |
|---|---|---|
| UX-E04 | Missing empty state on dashboard | Open |
| UX-E05 | Button contrast too low | Open |
MD
    git add README.md docs/reviews/2026-04-18-initial-audit.md
    git commit -q -m "init" >/dev/null 2>&1
  ) || { echo "self-test: FAIL — repo init failed" >&2; exit 1; }

  run_case() {
    local label="$1"; local expected_rc="$2"; local setup_fn="$3"
    (
      cd "$TMPDIR_ST" || exit 99
      # Reset any staged state
      git reset -q >/dev/null 2>&1
      # Restore tracked files in case a case modified them
      git checkout -q -- . 2>/dev/null || true
      # Clear any prior commit message
      mkdir -p .git
      : > .git/COMMIT_EDITMSG
      $setup_fn
    )
    set +e
    local out
    out=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" 2>&1)
    local rc=$?
    set -e
    if [ "$rc" -ne "$expected_rc" ]; then
      echo "self-test: FAIL — case '$label' expected rc=$expected_rc, got rc=$rc" >&2
      echo "  output was:" >&2
      printf '    %s\n' "$out" >&2
      return 1
    fi
    echo "self-test: case '$label' OK (rc=$rc)"
    return 0
  }

  # (a) commit message references UX-E04 (matches review), no review file staged → BLOCK
  setup_a_finding_no_review() {
    printf 'fix: address UX-E04 missing empty state\n' > .git/COMMIT_EDITMSG
    echo "unrelated" >> README.md
    git add README.md
  }

  # (b) commit message references UX-E04, review file staged → ALLOW
  setup_b_finding_with_review() {
    printf 'fix: address UX-E04 missing empty state\n' > .git/COMMIT_EDITMSG
    echo "unrelated" >> README.md
    # Update the review file and stage it
    sed -i.bak 's/UX-E04 | Missing empty state on dashboard | Open/UX-E04 | Missing empty state on dashboard | Fixed: abc123/' docs/reviews/2026-04-18-initial-audit.md
    rm -f docs/reviews/2026-04-18-initial-audit.md.bak
    git add README.md docs/reviews/2026-04-18-initial-audit.md
  }

  # (c) commit message references ABC-999 (token not in any review) → ALLOW
  setup_c_token_not_in_review() {
    printf 'chore: follow up on PR-1234 and ABC-999 tokens\n' > .git/COMMIT_EDITMSG
    echo "unrelated" >> README.md
    git add README.md
  }

  # (d) commit message has no finding-ID pattern → ALLOW
  setup_d_no_pattern() {
    printf 'feat: add a new feature\n' > .git/COMMIT_EDITMSG
    echo "unrelated" >> README.md
    git add README.md
  }

  FAIL=0
  run_case "a: finding referenced without review file" 1 setup_a_finding_no_review || FAIL=1
  run_case "b: finding referenced with review file"    0 setup_b_finding_with_review || FAIL=1
  run_case "c: token not in any review file"           0 setup_c_token_not_in_review || FAIL=1
  run_case "d: no finding-ID pattern in message"       0 setup_d_no_pattern || FAIL=1

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

# ---------- read commit message ------------------------------------------

COMMIT_MSG_FILE="$REPO_ROOT/.git/COMMIT_EDITMSG"
if [ ! -f "$COMMIT_MSG_FILE" ]; then
  exit 0
fi

COMMIT_MSG=$(cat "$COMMIT_MSG_FILE" 2>/dev/null || true)
if [ -z "$COMMIT_MSG" ]; then
  exit 0
fi

# ---------- extract finding-ID-like tokens from message ------------------

# Regex: [A-Z]{2,10}-[A-Z]?[0-9]{1,4}. grep -oE extracts matches; the
# surrounding non-word characters in natural commit messages act as de facto
# boundaries. Avoid \b because its behavior with hyphens varies across
# grep implementations (git-bash on Windows treats - as a word separator).
TOKENS_RAW=$(printf '%s' "$COMMIT_MSG" | grep -oE '[A-Z]{2,10}-[A-Z]?[0-9]{1,4}' 2>/dev/null | sort -u || true)

if [ -z "$TOKENS_RAW" ]; then
  exit 0
fi

# ---------- check which tokens actually appear in review files -----------

REVIEWS_DIR="$REPO_ROOT/docs/reviews"
if [ ! -d "$REVIEWS_DIR" ]; then
  # No reviews directory — nothing to enforce against.
  exit 0
fi

# Gather all review files.
REVIEW_FILES=()
while IFS= read -r -d '' f; do
  REVIEW_FILES+=("$f")
done < <(find "$REVIEWS_DIR" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)

if [ "${#REVIEW_FILES[@]}" -eq 0 ]; then
  # No review files — nothing to enforce against.
  exit 0
fi

# For each token, check if it appears in any review file. We use grep -F
# (fixed-string match) without -w because -w treats hyphens as word
# separators on some grep implementations (notably git-bash on Windows),
# which would cause false negatives. Plain substring match is acceptable:
# a collision would require a review file to contain the exact token as
# a substring of a longer identifier (e.g., review has "UX-E040" and
# commit references "UX-E04"), which is rare and a ~false positive on
# this gate is preferable to false-negative silent drift.
REAL_FINDINGS=""   # newline-separated list of confirmed-real tokens
while IFS= read -r token; do
  [ -n "$token" ] || continue
  if grep -F -- "$token" "${REVIEW_FILES[@]}" >/dev/null 2>&1; then
    REAL_FINDINGS="${REAL_FINDINGS}${token}"$'\n'
  fi
done <<< "$TOKENS_RAW"

if [ -z "$REAL_FINDINGS" ]; then
  # All tokens were false positives (e.g., PR-1234 with no matching review).
  exit 0
fi

# ---------- check staged files for any review file ----------------------

STAGED_LIST_TMP=$(mktemp)
trap 'rm -f "$STAGED_LIST_TMP"' EXIT

( cd "$REPO_ROOT" && git diff --cached --name-only -z --diff-filter=ACMR ) > "$STAGED_LIST_TMP" 2>/dev/null || true

REVIEW_FILE_STAGED=0
if [ -s "$STAGED_LIST_TMP" ]; then
  mapfile -d '' -t STAGED < "$STAGED_LIST_TMP"
  for p in "${STAGED[@]}"; do
    case "$p" in
      docs/reviews/*.md)
        REVIEW_FILE_STAGED=1
        break
        ;;
    esac
  done
fi

if [ "$REVIEW_FILE_STAGED" -eq 1 ]; then
  exit 0
fi

# ---------- BLOCK --------------------------------------------------------

{
  echo ""
  echo "================================================================"
  echo "REVIEW-FINDING-FIX GATE — BLOCKED"
  echo "================================================================"
  echo ""
  echo "Commit message references review finding(s) that appear in existing"
  echo "docs/reviews/*.md file(s), but no review file is staged in this commit:"
  echo ""
  printf '%s' "$REAL_FINDINGS" | sed 's/^/  - /'
  echo ""
  echo "When a commit fixes a review finding, the review document must be"
  echo "updated in the SAME commit to mark the finding's status (e.g.,"
  echo "'Fixed: <commit-SHA>'). Otherwise the review stays visually open"
  echo "forever and future sessions re-flag the same finding."
  echo ""
  echo "To fix:"
  echo "  1. Open the review file containing the finding (docs/reviews/...)"
  echo "  2. Update the status column / row for the referenced finding(s)"
  echo "  3. git add docs/reviews/<file>.md"
  echo "  4. Re-run the commit"
  echo ""
  echo "If the commit legitimately does NOT close the finding (partial work,"
  echo "unrelated mention), remove the finding ID from the commit message"
  echo "or stage the review file with an updated status note."
  echo ""
  echo "To bypass (not recommended): git commit --no-verify"
  echo "================================================================"
} >&2
exit 1
