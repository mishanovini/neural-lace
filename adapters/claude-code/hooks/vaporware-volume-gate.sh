#!/bin/bash
# vaporware-volume-gate.sh
#
# A8 of the adversarial-validation-mechanisms plan.
#
# PreToolUse hook on `Bash` that fires on `gh pr create` (and, opt-in, on
# `git push` when a PR is being prepared). Reads the cumulative branch
# state via `git diff origin/master...HEAD --numstat` and computes:
#
#   describes-behavior lines = lines added to files that describe what
#       a system would do (docs, configs, CI YAML, scripts, source).
#       File extensions: .md, .yml, .yaml, .json, .sh, .ts, .tsx, .js,
#       .jsx, plus paths under docs/ and .github/workflows/.
#
#   executes-behavior file count = files whose path or name signals an
#       artifact PRODUCED BY actually running the thing — logs,
#       screenshots, test-result JSON, loop-history dumps.
#
# If describes-behavior LINES > 200 AND executes-behavior FILE COUNT
# is 0, the gate fires the vaporware-volume warning and blocks the
# `gh pr create`. The agent (or user) can:
#
#   - Add execution-evidence files (test-run log, workflow-run artifact,
#     screenshot, etc.) and re-run.
#   - Re-title the PR with `[docs-only]` or `[no-execution]` prefix to
#     bypass the gate (the prefix becomes a permanent part of the PR
#     title and is auditable).
#
# Origin: 2026-04-26 incident — agent shipped PR #123 with 800 lines of
# docs + 174 lines of CI YAML and ZERO execution evidence, while the
# plan's own DoD said "Loop converges on master" was unchecked. The
# describing-vs-executing volume ratio caught the shape immediately
# (and caught nothing in the harness because no hook reads that ratio).
#
# Rule: rules/vaporware-prevention.md
# Plan: docs/plans/adversarial-validation-mechanisms.md (A8)
#
# Exit codes:
#   0 — command allowed (not a `gh pr create`, escape hatch present, or
#       diff doesn't match the vaporware-volume shape)
#   1 — command blocked (stderr explains and lists the file shape)

set -e

# ============================================================
# --self-test: exercise three fixture diffs
# ============================================================

if [[ "${1:-}" == "--self-test" ]]; then
  SCRIPT="${BASH_SOURCE[0]}"
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
  FIXTURE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/tests/vaporware-volume-gate"

  if [[ ! -d "$FIXTURE_DIR" ]]; then
    echo "self-test: fixture dir missing at $FIXTURE_DIR" >&2
    exit 2
  fi

  FAILED=0

  run_fixture() {
    local name="$1"
    local fixture_path="$2"
    local pr_title="$3"
    local expected_block="$4"  # 1=expect block, 0=expect allow
    local label="$5"

    if [[ ! -f "$fixture_path" ]]; then
      echo "self-test ($name): MISSING fixture $fixture_path" >&2
      FAILED=1
      return
    fi

    # Build a synthetic CLAUDE_TOOL_INPUT for `gh pr create`
    local cmd
    if [[ -n "$pr_title" ]]; then
      cmd="gh pr create --title \"$pr_title\" --body 'self-test'"
    else
      cmd="gh pr create --title 'self-test PR' --body 'self-test'"
    fi
    local input
    input=$(jq -nc --arg cmd "$cmd" '{tool_input: {command: $cmd}}')

    # Run the script with the fixture forced via env var
    local exit_code=0
    VAPORWARE_VOLUME_FIXTURE="$fixture_path" \
      bash "$SCRIPT" <<<"$input" >/dev/null 2>&1 || exit_code=$?

    if [[ "$expected_block" == "1" ]]; then
      if [[ $exit_code -ne 0 ]]; then
        echo "self-test ($name) [$label]: BLOCK (expected)" >&2
      else
        echo "self-test ($name) [$label]: ALLOW (expected BLOCK)" >&2
        FAILED=1
      fi
    else
      if [[ $exit_code -eq 0 ]]; then
        echo "self-test ($name) [$label]: ALLOW (expected)" >&2
      else
        echo "self-test ($name) [$label]: BLOCK (expected ALLOW)" >&2
        FAILED=1
      fi
    fi
  }

  run_fixture "fixture-vaporware" \
    "$FIXTURE_DIR/fixture-vaporware.txt" \
    "feat: add adversarial validation harness" \
    1 \
    "800 lines docs + 0 execution → BLOCK"

  run_fixture "fixture-real-feature" \
    "$FIXTURE_DIR/fixture-real-feature.txt" \
    "feat: implement reservation conflict detection" \
    0 \
    "feature code + test log → ALLOW"

  run_fixture "fixture-docs-only" \
    "$FIXTURE_DIR/fixture-docs-only.txt" \
    "[docs-only] document the adversarial validation harness" \
    0 \
    "vaporware shape but [docs-only] prefix → ALLOW"

  if [[ $FAILED -eq 0 ]]; then
    echo "all 3 self-tests passed" >&2
    exit 0
  else
    echo "self-test failures detected" >&2
    exit 1
  fi
fi

# ============================================================
# Main hook entry
# ============================================================

INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || echo "")
  fi
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || echo "")
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Only fire on `gh pr create`. We deliberately do NOT fire on `git push`
# because the PR title is unknown there and the escape hatch hinges on
# the title prefix. Consumers wanting push-time enforcement can layer
# the local pre-push convention separately.
if ! echo "$COMMAND" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create\b'; then
  exit 0
fi

# Also handle `gh pr edit --title` so re-titling can lift the block
# without re-creating the PR. (Allowing edit through is the right
# behavior; we just don't gate on it.)
if echo "$COMMAND" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+edit\b'; then
  exit 0
fi

# ============================================================
# Extract PR title for escape-hatch check
# ============================================================
#
# Recognized forms:
#   --title "..."
#   --title '...'
#   --title=...
#   -t "..." / -t '...' / -t=...
PR_TITLE=""
PR_TITLE=$(echo "$COMMAND" | sed -nE 's/.*--title[[:space:]]+"([^"]*)".*/\1/p' | head -1)
if [[ -z "$PR_TITLE" ]]; then
  PR_TITLE=$(echo "$COMMAND" | sed -nE "s/.*--title[[:space:]]+'([^']*)'.*/\\1/p" | head -1)
fi
if [[ -z "$PR_TITLE" ]]; then
  PR_TITLE=$(echo "$COMMAND" | sed -nE 's/.*--title=([^[:space:]]+).*/\1/p' | head -1)
fi
if [[ -z "$PR_TITLE" ]]; then
  PR_TITLE=$(echo "$COMMAND" | sed -nE 's/.*[[:space:]]-t[[:space:]]+"([^"]*)".*/\1/p' | head -1)
fi
if [[ -z "$PR_TITLE" ]]; then
  PR_TITLE=$(echo "$COMMAND" | sed -nE "s/.*[[:space:]]-t[[:space:]]+'([^']*)'.*/\\1/p" | head -1)
fi

# Escape hatch: title prefix
if [[ -n "$PR_TITLE" ]]; then
  if echo "$PR_TITLE" | grep -qiE '^[[:space:]]*\[(docs-only|no-execution)\]'; then
    exit 0
  fi
fi

# ============================================================
# Read the diff
# ============================================================

DIFF_NUMSTAT=""
if [[ -n "${VAPORWARE_VOLUME_FIXTURE:-}" ]]; then
  # Self-test path: read fixture file (already in numstat-like format)
  if [[ -f "$VAPORWARE_VOLUME_FIXTURE" ]]; then
    DIFF_NUMSTAT=$(cat "$VAPORWARE_VOLUME_FIXTURE")
  fi
else
  # Real path: read cumulative branch state.
  # Use origin/master if it exists; fall back to origin/main; fall back
  # to no-op (cannot determine base).
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [[ -z "$REPO_ROOT" ]]; then
    exit 0
  fi

  BASE_REF=""
  for candidate in origin/master origin/main master main; do
    if git -C "$REPO_ROOT" rev-parse --verify "$candidate" >/dev/null 2>&1; then
      BASE_REF="$candidate"
      break
    fi
  done

  if [[ -z "$BASE_REF" ]]; then
    # Cannot determine base; fail open
    exit 0
  fi

  DIFF_NUMSTAT=$(git -C "$REPO_ROOT" diff "$BASE_REF...HEAD" --numstat 2>/dev/null || echo "")
fi

if [[ -z "$DIFF_NUMSTAT" ]]; then
  # No diff (e.g., empty PR or already-merged branch) — nothing to gate
  exit 0
fi

# ============================================================
# Categorize files and tally lines
# ============================================================
#
# describes-behavior file extensions / paths:
#   .md, .yml, .yaml, .json, .sh, .ts, .tsx, .js, .jsx
#   plus anything under docs/, .github/workflows/, scripts/, hooks/
#
# executes-behavior file signals:
#   path contains: /loop-history/, /test-results/, /logs/, /screenshots/,
#                  /artifacts/, /coverage/, /evidence/
#   filename matches: *.log, *.png, *.jpg, *.jpeg, *.gif, *.webp,
#                     *-output.txt, *-evidence.md, *-evidence.json,
#                     *-trace.json, *-trace.txt, *.har, junit*.xml,
#                     test-results*.json, test-run-*.log
#
# Notes on the heuristic:
#   - .md files under */evidence/ or */loop-history/ count as
#     execution-evidence (they ARE the artifact), not as describes-behavior.
#   - The check is intentionally generous to "executes-behavior": a
#     single real artifact lifts the block. The point is to force the
#     agent to produce ANY external evidence; one log file is enough
#     signal that something actually ran.

DESCRIBES_LINES=0
EXECUTES_FILES=0
DESCRIBES_FILES_LIST=""

while IFS=$'\t' read -r added removed path; do
  [[ -z "$path" ]] && continue
  # Skip non-numeric (binary marked as "-" by git)
  if [[ "$added" =~ ^[0-9]+$ ]]; then
    added_num="$added"
  else
    added_num=0
  fi

  is_executes=0
  is_describes=0

  # ---- executes-behavior detection (checked first; takes precedence)
  case "$path" in
    */loop-history/*|*/test-results/*|*/logs/*|*/screenshots/*|*/artifacts/*|*/coverage/*|*/evidence/*)
      is_executes=1
      ;;
  esac

  if [[ $is_executes -eq 0 ]]; then
    case "$path" in
      *.log|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.har)
        is_executes=1
        ;;
      *-output.txt|*-evidence.md|*-evidence.json|*-trace.json|*-trace.txt)
        is_executes=1
        ;;
      junit*.xml|test-results*.json|test-run-*.log|test-run-*.txt)
        is_executes=1
        ;;
    esac
  fi

  if [[ $is_executes -eq 1 ]]; then
    EXECUTES_FILES=$((EXECUTES_FILES + 1))
    continue
  fi

  # ---- describes-behavior detection
  case "$path" in
    *.md|*.yml|*.yaml|*.json|*.sh|*.ts|*.tsx|*.js|*.jsx)
      is_describes=1
      ;;
    docs/*|.github/workflows/*|scripts/*|hooks/*|*/hooks/*|*/scripts/*)
      is_describes=1
      ;;
  esac

  if [[ $is_describes -eq 1 ]]; then
    DESCRIBES_LINES=$((DESCRIBES_LINES + added_num))
    DESCRIBES_FILES_LIST="${DESCRIBES_FILES_LIST}${path} (+${added_num})\n"
  fi
done <<< "$DIFF_NUMSTAT"

# ============================================================
# Apply the heuristic
# ============================================================

THRESHOLD_LINES=200

if (( DESCRIBES_LINES > THRESHOLD_LINES )) && (( EXECUTES_FILES == 0 )); then
  # Truncate file list if very long
  FILES_DISPLAY=$(printf '%b' "$DESCRIBES_FILES_LIST" | head -20)
  TOTAL_DESCRIBES_FILES=$(printf '%b' "$DESCRIBES_FILES_LIST" | grep -c '^.' || echo 0)
  if (( TOTAL_DESCRIBES_FILES > 20 )); then
    FILES_DISPLAY="${FILES_DISPLAY}
  ... and $((TOTAL_DESCRIBES_FILES - 20)) more"
  fi

  cat >&2 <<ERR_MSG
[vaporware-volume-gate] BLOCKED

VAPORWARE-VOLUME GATE — PR contains $DESCRIBES_LINES lines of behavior-describing content but ZERO execution-evidence artifacts. The shape:
  - $DESCRIBES_LINES lines added to .md/.yml/.json/.ts files describing how something would work
  - 0 files showing the thing actually ran (logs, results, screenshots)

Files describing behavior:
$FILES_DISPLAY

If this PR genuinely needs no execution evidence (pure docs, pure CI config, etc.), prefix the PR title with [docs-only] OR [no-execution] to bypass the gate. Otherwise add execution evidence:
  - For test-suite work: commit a test-run log
  - For CI work: a workflow-run artifact
  - For docs-of-feature: an example invocation log

To bypass without execution evidence: re-title the PR to start with [docs-only] or [no-execution].

Rule: rules/vaporware-prevention.md
Plan: docs/plans/adversarial-validation-mechanisms.md (A8)
ERR_MSG
  exit 1
fi

# All clear
exit 0
