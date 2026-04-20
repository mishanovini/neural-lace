#!/bin/bash
# no-test-skip-gate.sh
#
# PreToolUse hook on Bash (git commit) that blocks commits adding new
# .skip() calls in test files unless the skip line references an issue
# number (#NNN or github.com/.*/issues/NNN).
#
# The rule: "skipped tests are worse than no tests" — see
# ~/.claude/rules/testing.md "No Skipped Tests" section.
#
# A test that skips under some condition looks like coverage but isn't.
# It silently passes anything when the skip fires, which is exactly the
# vaporware failure mode the harness is designed to prevent.
#
# Exit codes:
#   0 — commit allowed
#   1 — commit blocked (stderr explains)

set -e

INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || echo "")
  fi
fi

# Only care about git commit commands
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || echo "")

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Only trigger on git commit
if ! echo "$COMMAND" | grep -qE '(^|[[:space:]])git[[:space:]]+commit'; then
  exit 0
fi

# Find repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi

# Get staged diff for test files
STAGED_TEST_FILES=$(git diff --cached --name-only --diff-filter=AM 2>/dev/null | grep -E '\.(spec|test)\.(ts|tsx|js|jsx|mjs)$' || true)

if [[ -z "$STAGED_TEST_FILES" ]]; then
  exit 0
fi

# Scan staged diff for NEW skip lines (lines starting with +)
VIOLATIONS=""

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Extract only added lines from the staged diff
  ADDED=$(git diff --cached "$file" 2>/dev/null | grep -E '^\+[^+]' || true)

  # Patterns that count as a skip:
  #   test.skip(, it.skip(, describe.skip(, .skip(
  #   xtest(, xit(, xdescribe(
  # We don't block .only( here (that's a separate rule, covered elsewhere)
  SKIP_LINES=$(echo "$ADDED" | grep -nE '(\b(test|it|describe)\.skip\(|\bx(test|it|describe)\()' || true)

  if [[ -z "$SKIP_LINES" ]]; then
    continue
  fi

  # For each skip line, check if it (or context around it) references an issue number
  while IFS= read -r skip_line; do
    [[ -z "$skip_line" ]] && continue

    # Accept if line contains #NNN or issues/NNN
    if echo "$skip_line" | grep -qE '(#[0-9]+|issues/[0-9]+)'; then
      continue
    fi

    VIOLATIONS="${VIOLATIONS}${file}: ${skip_line}\n"
  done <<< "$SKIP_LINES"
done <<< "$STAGED_TEST_FILES"

if [[ -z "$VIOLATIONS" ]]; then
  exit 0
fi

cat >&2 <<MSG
BLOCKED: no-test-skip-gate

This commit adds new test skip calls without an issue-number reference:

$(echo -e "$VIOLATIONS")

Skipped tests are worse than no tests — they create the illusion of
coverage while silently passing anything. See ~/.claude/rules/testing.md
"No Skipped Tests" for the full rationale.

To unblock, choose ONE:

(A) REMOVE the skip. Make the test actually work. If the blocker is
    missing data (e.g., "no reps in the org"), seed the data inline:

    const sessionRes = await page.request.get('/api/auth/session');
    const { org_id: orgId } = await sessionRes.json();
    const createRes = await page.request.post('/api/reps', {
      data: { org_id: orgId, name: 'E2E Test Rep', email: '...' },
    });
    const rep = await createRes.json();

    Then use the rep for the test, and clean up in a finally block with
    PATCH is_active=false.

(B) If the skip is genuinely required because of a known upstream bug
    or third-party constraint that cannot be worked around, add an
    issue reference inline:

      test.skip('Blocked by #123 — upstream API rate-limits test accounts');

    The gate accepts #NNN or issues/NNN in the skip line. Create the
    issue first if it doesn't exist.

(C) If you are completely stuck and cannot figure out how to test the
    feature, STOP and surface the blocker to the user so we can come up
    with a solution together. Do not paper over with a skip.
MSG

exit 1
