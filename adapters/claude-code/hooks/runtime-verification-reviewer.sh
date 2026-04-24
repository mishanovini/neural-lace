#!/bin/bash
# runtime-verification-reviewer.sh — Generation 4
#
# Mechanical correspondence check between Runtime verification entries and
# the files modified by the task they verify. Called by pre-stop-verifier
# right after runtime-verification-executor.sh. While the executor verifies
# that commands EXECUTE successfully, this reviewer verifies that they
# CORRESPOND to the task's claimed changes.
#
# It reads the evidence file and for each task-evidence block:
#   1. Extracts the "Task ID" and "Files modified" (if present)
#   2. Extracts the "Runtime verification:" lines
#   3. For each verification line, checks that it references a file or URL
#      that relates to the task's modified files
#
# This closes the gap identified by the harness-reviewer: curl to
# /api/health passing the executor doesn't mean it actually touches the
# route the task modified. The reviewer cross-checks that curl URL paths
# match modified route files, sql tables match modified migrations, etc.
#
# Usage:
#   bash runtime-verification-reviewer.sh <plan-file> <evidence-file>
#
# Exit codes:
#   0 — all verification entries correspond to their tasks
#   1 — at least one correspondence failure
#   2 — input error

set -u

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <plan-file> <evidence-file>" >&2
  exit 2
fi

PLAN_FILE="$1"
EVIDENCE_FILE="$2"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "runtime-verification-reviewer: plan file not found: $PLAN_FILE" >&2
  exit 2
fi
if [[ ! -f "$EVIDENCE_FILE" ]]; then
  # No evidence file = nothing to review. Defer to pre-stop-verifier's
  # other checks to decide if that's an error.
  exit 0
fi

# Extract the set of files modified by tasks. We use git log's files-changed
# list for the plan's execution window. Because we don't know the exact
# commit range, we use recent commits (last 20) as a heuristic scope.
#
# Exclusions:
#   - blank lines (commit boundaries from --pretty=format:)
#   - any file with `evidence` in its path (the plan's own evidence file)
#   - anything under `docs/plans/` including the archive subdirectory
#     (`docs/plans/archive/*`). Plan files and archived plan files are
#     NOT runtime-relevant — edits to them don't change application
#     behavior, so they shouldn't count toward correspondence checks.
MODIFIED_FILES=$(git log --name-only --pretty=format: -20 2>/dev/null | grep -vE '^$|evidence|docs/plans(/archive)?/' | sort -u || true)

if [[ -z "$MODIFIED_FILES" ]]; then
  # Not a git repo or no modifications — nothing to correspond against
  exit 0
fi

# Parse Runtime verification entries from evidence
VERIF_LINES=$(grep -E '^Runtime verification:' "$EVIDENCE_FILE" 2>/dev/null || true)
if [[ -z "$VERIF_LINES" ]]; then
  # No verification entries to check — defer to executor/pre-stop for that
  exit 0
fi

FINDINGS=""
FINDING_COUNT=0

add_finding() {
  FINDINGS+="  * $1"$'\n'
  FINDING_COUNT=$((FINDING_COUNT + 1))
}

# Check each verification line for correspondence
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  body="${line#Runtime verification:}"
  body="${body# }"
  fmt=$(echo "$body" | awk '{print $1}')
  rest=$(echo "$body" | cut -d' ' -f2-)

  case "$fmt" in
    curl)
      # Extract URL from the curl command (best-effort)
      url=$(echo "$rest" | grep -oE 'https?://[^[:space:]]+' | head -1)
      if [[ -z "$url" ]]; then
        add_finding "curl entry has no URL: '$line'"
        continue
      fi
      # Extract route path from the URL (everything after hostname)
      route=$(echo "$url" | sed -E 's|https?://[^/]+||' | sed -E 's|\?.*$||')
      if [[ -z "$route" || "$route" == "/" ]]; then
        add_finding "curl hits root URL (no correspondence): '$line'"
        continue
      fi
      # Check if any modified file path contains the route path components
      route_stem=$(echo "$route" | sed -E 's|^/||; s|/$||')
      # Reject common non-corresponding routes
      if [[ "$route_stem" =~ ^(api/)?health$|^(api/)?status$|^(api/)?ping$ ]]; then
        add_finding "curl hits health/status/ping endpoint (not corresponding): '$line'"
        continue
      fi
      # Look for the route path in modified files
      found=0
      while IFS= read -r mod_file; do
        if echo "$mod_file" | grep -qE "$(echo "$route_stem" | sed 's|/|/|g')"; then
          found=1
          break
        fi
      done <<< "$MODIFIED_FILES"
      if [[ "$found" -eq 0 ]]; then
        add_finding "curl route '$route' does not match any recently-modified file: '$line'"
      fi
      ;;

    sql)
      # Extract table names (FROM/INTO/UPDATE followed by an identifier)
      tables=$(echo "$rest" | grep -oiE '(FROM|INTO|UPDATE)[[:space:]]+[a-z_][a-z0-9_]*' | awk '{print tolower($2)}' | sort -u)
      if [[ -z "$tables" ]]; then
        add_finding "sql entry has no FROM/INTO/UPDATE clause: '$line'"
        continue
      fi
      # Check for trivially-passing queries like "SELECT 1 FROM x LIMIT 1"
      if echo "$rest" | grep -qiE '^SELECT[[:space:]]+1[[:space:]]+FROM[[:space:]]+[^[:space:]]+[[:space:]]+LIMIT[[:space:]]+1'; then
        add_finding "sql is trivially passing (SELECT 1 ... LIMIT 1): '$line'"
        continue
      fi
      # Check if any table matches a modified migration file
      found=0
      migration_files=$(echo "$MODIFIED_FILES" | grep -E '^supabase/migrations/.*\.sql$' || true)
      if [[ -n "$migration_files" ]]; then
        while IFS= read -r mig; do
          [[ -z "$mig" ]] && continue
          [[ -f "$mig" ]] || continue
          for tbl in $tables; do
            if grep -qiE "(TABLE|INTO|ALTER[[:space:]]+TABLE)[[:space:]]+${tbl}\b" "$mig" 2>/dev/null; then
              found=1
              break 2
            fi
          done
        done <<< "$migration_files"
      fi
      if [[ "$found" -eq 0 ]] && [[ -n "$migration_files" ]]; then
        add_finding "sql tables ($tables) do not match any table in recent migrations: '$line'"
      fi
      ;;

    test|playwright)
      # Format: test <file>::<name>
      test_file="${rest%%::*}"
      [[ -f "$test_file" ]] || continue  # executor already caught missing files
      # Check if the test file imports from any modified src file
      imports=$(grep -E "from[[:space:]]+['\"][^'\"]+['\"]" "$test_file" 2>/dev/null | grep -oE "['\"][^'\"]+['\"]" | tr -d "'\"")
      if [[ -z "$imports" ]]; then
        add_finding "$fmt file has no imports: '$line'"
        continue
      fi
      # Look for at least one import pointing at a modified src file
      found=0
      while IFS= read -r imp; do
        [[ -z "$imp" ]] && continue
        # Strip leading ./, ../, @/, ~/
        imp_clean=$(echo "$imp" | sed -E 's|^(\.\./)+||; s|^\./||; s|^[@~]/|src/|')
        if echo "$MODIFIED_FILES" | grep -qE "/${imp_clean}\.(ts|tsx|js|jsx)$|^${imp_clean}\.(ts|tsx|js|jsx)$"; then
          found=1
          break
        fi
      done <<< "$imports"
      if [[ "$found" -eq 0 ]]; then
        add_finding "$fmt file does not import any recently-modified source file: '$line'"
      fi
      ;;

    file)
      file_path="${rest%%::*}"
      # Check if this file was actually modified recently
      if ! echo "$MODIFIED_FILES" | grep -qxF "$file_path"; then
        add_finding "file entry points at a file not recently modified: '$line'"
      fi
      ;;
  esac
done <<< "$VERIF_LINES"

if [[ "$FINDING_COUNT" -gt 0 ]]; then
  echo "" >&2
  echo "================================================================" >&2
  echo "RUNTIME VERIFICATION REVIEW: $FINDING_COUNT correspondence failure(s)" >&2
  echo "================================================================" >&2
  echo "" >&2
  echo "$FINDINGS" >&2
  echo "Correspondence rule: every Runtime verification: command must actually" >&2
  echo "exercise the code path modified by the task it claims to verify. A curl" >&2
  echo "to /api/health does not verify a fix to /api/example." >&2
  echo "" >&2
  echo "To resolve: rewrite each flagged verification command to target the" >&2
  echo "modified file(s) directly. If the modified file is a route, the curl" >&2
  echo "URL must hit that route. If it's a migration, the SQL must reference" >&2
  echo "the migrated table non-trivially." >&2
  echo "" >&2
  exit 1
fi

echo "runtime-verification-reviewer: all entries correspond to modified files" >&2
exit 0
