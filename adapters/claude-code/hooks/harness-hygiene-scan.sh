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
#   - docs/plans/, docs/decisions/, docs/reviews/, docs/sessions/
#     (gitignored in the harness repo; defense-in-depth if force-added)
#   - SCRATCHPAD.md (gitignored working memory)
#   - Any file matching *.example, *.example.json, *.example.sh
#     (placeholders are supposed to look placeholder-ish)
#
# EXIT CODES
#   0 — no matches (or denylist missing / not in a git repo — silent no-op)
#   1 — one or more matches detected

set -u

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

  # Case 3: dirty content in an exempt directory (docs/plans/) should NOT match.
  # Closes harness-reviewer finding F5 — verify exemption logic actually runs.
  mkdir -p "$TMPDIR_ST/docs/plans"
  EXEMPT_PLAN="$TMPDIR_ST/docs/plans/foo.md"
  printf '%s\n' 'this plan mentions FORBIDDEN_TOKEN as part of documenting it' > "$EXEMPT_PLAN"

  # Case 4: dirty content in an exempt rule file should NOT match.
  mkdir -p "$TMPDIR_ST/adapters/claude-code/rules"
  EXEMPT_RULE="$TMPDIR_ST/adapters/claude-code/rules/harness-hygiene.md"
  printf '%s\n' 'harness-hygiene rule documents FORBIDDEN_TOKEN as a denylist example' > "$EXEMPT_RULE"

  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  # Invoke from the tmp repo so REPO_ROOT resolves to $TMPDIR_ST.
  # Pass relative paths so the exemption logic sees the repo-relative path,
  # matching how staged paths appear in pre-commit mode.
  set +e
  ST_DIRTY_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_DIRTY_RC=$?
  ST_CLEAN_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "clean.txt" 2>&1)
  ST_CLEAN_RC=$?
  ST_EXEMPT_PLAN_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/plans/foo.md" 2>&1)
  ST_EXEMPT_PLAN_RC=$?
  ST_EXEMPT_RULE_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "adapters/claude-code/rules/harness-hygiene.md" 2>&1)
  ST_EXEMPT_RULE_RC=$?
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
  if [ "$ST_EXEMPT_PLAN_RC" -ne 0 ]; then
    echo "self-test: FAIL — expected exit 0 on exempt docs/plans/ file, got $ST_EXEMPT_PLAN_RC" >&2
    echo "(exemption logic did not trigger; scanner would have blocked a docs/plans/ file)" >&2
    echo "output was:" >&2
    echo "$ST_EXEMPT_PLAN_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_EXEMPT_RULE_RC" -ne 0 ]; then
    echo "self-test: FAIL — expected exit 0 on exempt rules/harness-hygiene.md, got $ST_EXEMPT_RULE_RC" >&2
    echo "(exemption logic did not trigger; scanner would have blocked a harness-hygiene rule file)" >&2
    echo "output was:" >&2
    echo "$ST_EXEMPT_RULE_OUT" >&2
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
    principles/forward-compatibility.md) return 0 ;;
    adapters/claude-code/git-hooks/pre-commit) return 0 ;;
    adapters/claude-code/hooks/harness-hygiene-scan.sh) return 0 ;;
    adapters/claude-code/hooks/decisions-index-gate.sh) return 0 ;;
  esac

  # Directory-prefix exemptions (gitignored in the harness repo; defense-in-depth)
  case "$path" in
    docs/plans/*|docs/plans|docs/decisions/*|docs/decisions) return 0 ;;
    docs/reviews/*|docs/reviews|docs/sessions/*|docs/sessions) return 0 ;;
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
MATCHES_TMP=$(mktemp)
trap 'rm -f "$PATTERNS_TMP" "$FILE_LIST_TMP" "$MATCHES_TMP"' EXIT

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
      printf '%s\n' "$check_path:$lineno: $content" >> "$MATCHES_TMP"
      MATCH_COUNT=$((MATCH_COUNT + 1))
    done <<< "$grep_out"
  fi
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
  echo "match is legitimate."
  echo ""
  cat "$MATCHES_TMP"
  echo ""
  echo "To bypass (not recommended): git commit --no-verify"
  echo "Denylist: adapters/claude-code/patterns/harness-denylist.txt"
  echo "Rule: principles/harness-hygiene.md"
  echo "================================================================"
} >&2

exit 1
