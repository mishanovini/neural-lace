#!/bin/bash
# pre-commit-tdd-gate.sh — Generation 4
#
# Blocks commits that ship runtime code without meaningful tests.
# This is the single most important mechanical enforcement in the harness.
#
# Five layers:
#
#   Layer 1: NEW runtime files require matching test files
#     - New API routes: require tests/api/<flat>.test.ts
#     - New pages: require a Playwright spec
#     - New Trigger tasks: require a trigger or journey test
#     - New migrations: require embedded DO block OR tests/migrations/<name>.test.ts
#
#   Layer 2: MODIFIED runtime files require a test that references the file
#     - src/app/**, src/lib/**, src/trigger/**, src/components/**
#     - If the diff has non-whitespace, non-comment changes AND no test
#       file references the modified file's basename, BLOCK.
#     - This catches the Gen 3 failure mode where fixing .limit(1) in
#       handleConversation required no test.
#
#   Layer 3: Integration-tier test files cannot use mocks
#     - tests/api/**, tests/integration/**, tests/journey/**, tests/playwright/**
#     - Block vi.mock, jest.mock, vi.spyOn, jest.spyOn, createMock*, MockSupabase
#     - Unit tests (tests/unit/**) remain free to mock.
#
#   Layer 4: Test files cannot consist only of trivial assertions
#     - Count expect() calls and count trivial ones (toBeDefined, toBeTruthy,
#       not.toThrow, toBe(true/false)).
#     - If all expects are trivial AND nonzero, BLOCK.
#
#   Layer 5: Silent-skip tests are forbidden (2026-04-15)
#     - Rejects staged test lines that introduce .skip(!CRED, ...) or
#       .skip(process.env.X, ...) or .skipIf(...) patterns.
#     - Escape hatch: `// harness-allow-skip: <reason>` on the same line
#       opts in. Use for genuinely optional tests (feature-flag gated),
#       not for "credential isn't set yet" skips.
#     - Caught after discovering platform-admin.spec.ts had been silently
#       skipping every run since it was committed, because
#       test.skip(!TEST_ADMIN_EMAIL, '...') evaluates at test-setup time
#       and skipped the entire describe whenever the env var was unset.
#       Result: the impersonation bug (Failure 2 in 2026-04-14 postmortem)
#       was NOT caught by the existing playwright suite that appeared to
#       cover it.
#
# Escape hatch: --no-verify is blocked by the Bash PreToolUse hook in
# settings.json, so this gate cannot be bypassed under the normal
# workflow.
#
# Exit codes:
#   0 — commit is allowed
#   1 — commit is blocked (stderr explains which layer fired)

set -e

# ============================================================
# Environment
# ============================================================

# Runtime directories under src/ where code changes require test coverage.
# These are the directories the four postmortem failures all touched.
RUNTIME_DIRS_REGEX='^src/(app|lib|trigger|components|middleware)'

# Test directories where mocks are BANNED.
INTEGRATION_TEST_DIRS_REGEX='^tests/(api|integration|journey|playwright)/'

# ============================================================
# Pre-flight
# ============================================================

STAGED=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
if [[ -z "$STAGED" ]]; then
  exit 0
fi

BLOCKERS=""

# ============================================================
# Helpers
# ============================================================

check_test_exists() {
  local test_path="$1"
  [[ -f "$test_path" ]] && return 0
  git diff --cached --name-only 2>/dev/null | grep -qx "$test_path" && return 0
  return 1
}

# Does the diff of this file contain any non-whitespace, non-comment changes?
# We strip lines that are only whitespace/comments from the diff and check
# if anything remains. This avoids blocking commits that only fix indentation
# or tweak a comment.
has_meaningful_changes() {
  local file="$1"
  local diff
  diff=$(git diff --cached -U0 -- "$file" 2>/dev/null | grep -E '^[+-]' | grep -vE '^[+-]{3}')
  # Strip whitespace-only and comment-only added/removed lines
  local meaningful
  meaningful=$(echo "$diff" | grep -vE '^[+-]\s*$' | grep -vE '^[+-]\s*//' | grep -vE '^[+-]\s*/\*' | grep -vE '^[+-]\s*\*' | grep -vE '^[+-]\s*\*/')
  [[ -n "$meaningful" ]]
}

# Does any test file reference the modified runtime file?
# Matches by the **full relative path** (without extension), not just the
# basename. This is stricter than the Gen 4 first-draft version, which
# matched by basename stem — a fatal weakness because all `page.tsx` files
# share the stem `page`, so one Playwright spec with `await page.goto(...)`
# would match every dashboard page simultaneously.
#
# Match patterns (using the full relative path as anchor):
#   import { ... } from '../../../src/app/(dashboard)/contacts/page'
#   import { ... } from '@/app/(dashboard)/contacts/page'
#   import { ... } from '~/app/(dashboard)/contacts/page'
#
# Also accepts:
#   A test file that lives at a path matching the runtime file's directory
#   (e.g., tests/api/contacts.test.ts for src/app/api/contacts/route.ts)
test_references_file() {
  local runtime_file="$1"
  local rel_path
  # Strip leading src/ to get the relative module path
  rel_path=$(echo "$runtime_file" | sed -E 's|^src/||; s/\.(ts|tsx)$//')
  # Escape parentheses for grep (route groups use (group))
  local rel_path_esc
  rel_path_esc=$(echo "$rel_path" | sed 's|[(){}]|.|g')

  # Look in any test file (staged or existing) for a reference to the
  # full relative path.
  local found
  found=$(find tests/ -type f \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.spec.ts' -o -name '*.spec.tsx' \) 2>/dev/null \
     | xargs grep -lE "from[[:space:]]+['\"][^'\"]*${rel_path_esc}['\"]" 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then
    return 0
  fi

  # Also accept if a staged test file mentions the full relative path
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    [[ -f "$t" ]] || continue
    if grep -qE "from[[:space:]]+['\"][^'\"]*${rel_path_esc}['\"]" "$t" 2>/dev/null; then
      return 0
    fi
  done < <(git diff --cached --name-only 2>/dev/null | grep -E '^tests/.*\.(test|spec)\.tsx?$')

  return 1
}

# ============================================================
# Layer 1 + 2: Runtime file coverage
# ============================================================

NEW_FILES=""
MODIFIED_FILES=""

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Skip test files, types, and scripts — they don't need their own tests
  [[ "$file" =~ ^tests/ ]] && continue
  [[ "$file" =~ \.d\.ts$ ]] && continue
  [[ "$file" =~ ^scripts/ ]] && continue
  [[ "$file" =~ ^src/types/ ]] && continue

  is_new=0
  if git diff --cached --diff-filter=A --name-only 2>/dev/null | grep -qx "$file"; then
    is_new=1
  fi

  # New API route handlers
  if [[ "$file" =~ ^src/app/api/.+/route\.ts$ ]]; then
    NEW_FILES+="$file"$'\n'
    continue
  fi

  # New pages
  if [[ "$file" =~ ^src/app/.+/page\.tsx$ ]] && [[ "$is_new" -eq 1 ]]; then
    NEW_FILES+="$file"$'\n'
    continue
  fi

  # New Trigger.dev task files
  if [[ "$file" =~ ^src/trigger/.+\.ts$ ]] && [[ ! "$file" =~ index\.ts$ ]] && [[ "$is_new" -eq 1 ]]; then
    NEW_FILES+="$file"$'\n'
    continue
  fi

  # New migrations
  if [[ "$file" =~ ^supabase/migrations/.+\.sql$ ]] && [[ "$is_new" -eq 1 ]]; then
    NEW_FILES+="$file"$'\n'
    continue
  fi

  # MODIFIED runtime files under src/
  if [[ "$file" =~ $RUNTIME_DIRS_REGEX ]] && [[ "$file" =~ \.(ts|tsx)$ ]] && [[ "$is_new" -eq 0 ]]; then
    # Only flag if the diff has meaningful (non-whitespace, non-comment) changes
    if has_meaningful_changes "$file"; then
      MODIFIED_FILES+="$file"$'\n'
    fi
    continue
  fi
done <<< "$STAGED"

# Check new files against expected test paths (existing behavior).
if [[ -n "$NEW_FILES" ]]; then
  MISSING_TESTS=""
  MISSING_COUNT=0

  while IFS= read -r runtime_file; do
    [[ -z "$runtime_file" ]] && continue

    found=0
    expected_tests=""

    if [[ "$runtime_file" =~ ^src/app/api/(.+)/route\.ts$ ]]; then
      route_path="${BASH_REMATCH[1]}"
      flat_name=$(echo "$route_path" | tr '/' '-' | tr -d '[]')
      for candidate in \
        "tests/api/${flat_name}.test.ts" \
        "tests/api/$(basename "$route_path").test.ts" \
        "tests/api/${flat_name}.spec.ts"
      do
        expected_tests+="  $candidate"$'\n'
        if check_test_exists "$candidate"; then found=1; break; fi
      done
      if [[ "$found" -eq 0 ]]; then
        if git grep -lq "/api/${route_path//[\[\]]/}" -- 'tests/api/*.test.ts' 'tests/api/*.spec.ts' 2>/dev/null; then
          found=1
        fi
      fi
    fi

    if [[ "$runtime_file" =~ ^src/app/(.+)/page\.tsx$ ]]; then
      page_route="${BASH_REMATCH[1]}"
      clean_route=$(echo "$page_route" | sed -E 's|\([^/)]+\)/||g')
      flat_name=$(echo "$clean_route" | tr '/' '-' | tr -d '[]')
      for candidate in \
        "tests/playwright/${flat_name}.spec.ts" \
        "tests/playwright/journeys/${flat_name}.spec.ts"
      do
        expected_tests+="  $candidate"$'\n'
        if check_test_exists "$candidate"; then found=1; break; fi
      done
      if [[ "$found" -eq 0 ]]; then
        if git grep -lq "'/${clean_route}'" -- 'tests/playwright/**/*.spec.ts' 2>/dev/null; then
          found=1
        fi
      fi
    fi

    if [[ "$runtime_file" =~ ^src/trigger/(.+)\.ts$ ]]; then
      task_file="${BASH_REMATCH[1]}"
      flat_name=$(echo "$task_file" | tr '/' '-')
      for candidate in \
        "tests/trigger/${flat_name}.test.ts" \
        "tests/journey/scenarios/${flat_name}.test.ts"
      do
        expected_tests+="  $candidate"$'\n'
        if check_test_exists "$candidate"; then found=1; break; fi
      done
    fi

    if [[ "$runtime_file" =~ ^supabase/migrations/(.+)\.sql$ ]]; then
      migration_name="${BASH_REMATCH[1]}"
      if git diff --cached "$runtime_file" 2>/dev/null | grep -qE 'DO \$\$.*(RAISE|ASSERT)'; then
        found=1
      else
        expected_tests+="  tests/migrations/${migration_name}.test.ts"$'\n'
        expected_tests+="  OR: embed a DO \$\$...RAISE EXCEPTION...\$\$ verification block"$'\n'
        if check_test_exists "tests/migrations/${migration_name}.test.ts"; then found=1; fi
      fi
    fi

    if [[ "$found" -eq 0 ]]; then
      MISSING_TESTS+="  * $runtime_file (new file, no test found)"$'\n'
      MISSING_TESTS+="${expected_tests}"
      MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
  done <<< "$NEW_FILES"

  if [[ "$MISSING_COUNT" -gt 0 ]]; then
    BLOCKERS+="LAYER 1: New runtime files without tests ($MISSING_COUNT)"$'\n'
    BLOCKERS+="$MISSING_TESTS"$'\n'
  fi
fi

# Check modified files against "is there any test that references this file".
if [[ -n "$MODIFIED_FILES" ]]; then
  MISSING_MOD=""
  MISSING_MOD_COUNT=0

  while IFS= read -r runtime_file; do
    [[ -z "$runtime_file" ]] && continue
    if ! test_references_file "$runtime_file"; then
      MISSING_MOD+="  * $runtime_file"$'\n'
      MISSING_MOD_COUNT=$((MISSING_MOD_COUNT + 1))
    fi
  done <<< "$MODIFIED_FILES"

  if [[ "$MISSING_MOD_COUNT" -gt 0 ]]; then
    BLOCKERS+="LAYER 2: Modified runtime files with no referring test ($MISSING_MOD_COUNT)"$'\n'
    BLOCKERS+="$MISSING_MOD"$'\n'
    BLOCKERS+="  To resolve: add a test file under tests/ that imports from the modified file(s),"$'\n'
    BLOCKERS+="  OR modify an existing test that references it. The test must exercise the changed code path."$'\n'$'\n'
  fi
fi

# ============================================================
# Layer 3: Mock ban in integration-tier test files
# ============================================================

MOCK_VIOLATIONS=""
MOCK_COUNT=0

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ "$file" =~ $INTEGRATION_TEST_DIRS_REGEX ]] || continue
  [[ -f "$file" ]] || continue

  # Scan the staged content for mock patterns
  violations=$(grep -nE 'vi\.mock\(|jest\.mock\(|vi\.spyOn\(|jest\.spyOn\(|createMockClient|createMockSupabase|MockSupabase|from\s+['"'"'"][^'"'"'"]*tests/(mocks|fakes)' "$file" 2>/dev/null || true)
  if [[ -n "$violations" ]]; then
    MOCK_VIOLATIONS+="  * $file"$'\n'
    while IFS= read -r line; do
      MOCK_VIOLATIONS+="      $line"$'\n'
    done <<< "$violations"
    MOCK_COUNT=$((MOCK_COUNT + 1))
  fi
done <<< "$STAGED"

if [[ "$MOCK_COUNT" -gt 0 ]]; then
  BLOCKERS+="LAYER 3: Integration-tier tests using mocks ($MOCK_COUNT file(s))"$'\n'
  BLOCKERS+="$MOCK_VIOLATIONS"$'\n'
  BLOCKERS+="  Mocks are banned in tests/api/, tests/integration/, tests/journey/, tests/playwright/."$'\n'
  BLOCKERS+="  These tiers must hit real infrastructure (real Supabase test project, real APIs)."$'\n'
  BLOCKERS+="  A mocked test would accept any column/field and would have missed the messages.metadata failure."$'\n'
  BLOCKERS+="  If you need mocks, move the test to tests/unit/ where mocking is allowed."$'\n'$'\n'
fi

# ============================================================
# Layer 4: Trivial-assertion ban in test files
# ============================================================
#
# A test file is rejected if ALL its expect() calls are trivial assertions.
# Trivial = toBeDefined, toBeTruthy, not.toThrow, toBe(true/false), toEqual(true/false).
# If at least one expect() call asserts on a real value, the file is OK.
# This catches the "write a test to pass the TDD gate" workaround.

TRIVIAL_VIOLATIONS=""
TRIVIAL_COUNT=0

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ "$file" =~ \.(test|spec)\.(ts|tsx)$ ]] || continue
  [[ -f "$file" ]] || continue

  # Only apply to NEW test files (modifications to existing tests can reasonably tighten an existing trivial assertion)
  if ! git diff --cached --diff-filter=A --name-only 2>/dev/null | grep -qx "$file"; then
    continue
  fi

  total_expects=$(grep -cE '\bexpect\s*\(' "$file" 2>/dev/null || echo "0")
  total_expects=$(echo "$total_expects" | tr -d '[:space:]')
  [[ "$total_expects" -eq 0 ]] && continue

  trivial_expects=$(grep -cE '\.toBeDefined\(\)|\.toBeTruthy\(\)|\.not\.toThrow\(\)|\.toBe\(\s*true\s*\)|\.toBe\(\s*false\s*\)|\.toEqual\(\s*true\s*\)|\.toEqual\(\s*false\s*\)' "$file" 2>/dev/null || echo "0")
  trivial_expects=$(echo "$trivial_expects" | tr -d '[:space:]')

  real_expects=$((total_expects - trivial_expects))

  if [[ "$real_expects" -le 0 ]]; then
    TRIVIAL_VIOLATIONS+="  * $file: $total_expects expect() calls, all trivial"$'\n'
    TRIVIAL_COUNT=$((TRIVIAL_COUNT + 1))
  fi
done <<< "$STAGED"

if [[ "$TRIVIAL_COUNT" -gt 0 ]]; then
  BLOCKERS+="LAYER 4: Test files with only trivial assertions ($TRIVIAL_COUNT)"$'\n'
  BLOCKERS+="$TRIVIAL_VIOLATIONS"$'\n'
  BLOCKERS+="  A test whose only assertions are .toBeDefined() / .toBeTruthy() /"$'\n'
  BLOCKERS+="  .not.toThrow() / .toBe(true|false) is not testing behavior — it's"$'\n'
  BLOCKERS+="  testing that code compiles. Add at least one expect() that asserts a"$'\n'
  BLOCKERS+="  real return value, DB state, HTTP response, or DOM state."$'\n'$'\n'
fi

# ============================================================
# Layer 5: Silent-skip ban in staged test files
# ============================================================
#
# Rejects staged test lines that introduce runtime conditional skips:
#   test.skip(!CRED, '...')          ← runtime evaluates the negation
#   test.skip(process.env.X, '...')  ← runtime reads the env var
#   test.skipIf(!CRED)               ← vitest skipIf with a condition
#
# Plus unconditional .skip( on new test definitions:
#   test.skip('name', () => { ... })
#   describe.skip('group', () => { ... })
#   it.skip('case', () => { ... })
#
# Escape hatch: annotate the line with
#   // harness-allow-skip: <short reason>
# Use this for genuinely optional tests (e.g. a test that needs a
# feature flag that legitimately may not be enabled in all environments),
# NOT for "the credential isn't wired up yet" skips — those ARE the
# failure mode this layer guards.
#
# The 2026-04-14 impersonation bug (Failure 2) shipped because
# platform-admin.spec.ts ran `test.skip(!TEST_ADMIN_EMAIL, '...')` at
# the top of a describe block, and the env var was never set, so every
# test in the describe silently no-op'd every run. The test file looked
# like coverage. It wasn't.

SKIP_VIOLATIONS=""
SKIP_COUNT=0

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ "$file" =~ \.(test|spec)\.(ts|tsx)$ ]] || continue
  [[ -f "$file" ]] || continue

  # Extract added lines from the staged diff (lines starting with +, excluding +++)
  added=$(git diff --cached -U0 -- "$file" 2>/dev/null | grep -E '^\+' | grep -vE '^\+{3}')
  [[ -z "$added" ]] && continue

  # Two patterns: runtime-conditional skip, and unconditional .skip defining a test
  # Pattern A: runtime-conditional — (test|describe|it).skip(!... | process.env... | typeof process...)
  # Pattern B: unconditional test definition as .skip — (test|describe|it).skip\(\s*['"]
  # Note: test.skipIf() and test.fails() don't run normally either — add them.
  suspect=$(echo "$added" | grep -nE "(test|describe|it)\.(skip|skipIf|fails)\s*\(\s*(!|process\.env|typeof\s+process|['\"])" || true)
  [[ -z "$suspect" ]] && continue

  # For each suspect line, allow if `harness-allow-skip:` appears in it
  unannotated=""
  while IFS= read -r susp_line; do
    [[ -z "$susp_line" ]] && continue
    if echo "$susp_line" | grep -q "harness-allow-skip:"; then
      continue
    fi
    unannotated+="      $susp_line"$'\n'
  done <<< "$suspect"

  if [[ -n "$unannotated" ]]; then
    SKIP_VIOLATIONS+="  * $file"$'\n'
    SKIP_VIOLATIONS+="$unannotated"
    SKIP_COUNT=$((SKIP_COUNT + 1))
  fi
done <<< "$STAGED"

if [[ "$SKIP_COUNT" -gt 0 ]]; then
  BLOCKERS+="LAYER 5: New test code introduces silent-skip patterns ($SKIP_COUNT file(s))"$'\n'
  BLOCKERS+="$SKIP_VIOLATIONS"$'\n'
  BLOCKERS+="  Silent-skip tests are vaporware: they exist, they look like coverage,"$'\n'
  BLOCKERS+="  and they never actually run. The 2026-04-14 impersonation bug shipped"$'\n'
  BLOCKERS+="  because tests/playwright/journeys/platform-admin.spec.ts skipped itself"$'\n'
  BLOCKERS+="  whenever TEST_ADMIN_EMAIL was unset — which was always."$'\n'
  BLOCKERS+=""$'\n'
  BLOCKERS+="  To resolve: either"$'\n'
  BLOCKERS+="    1. Remove the .skip / .skipIf / .fails call entirely. Tests should"$'\n'
  BLOCKERS+="       run, period. If the environment is missing, the test should FAIL"$'\n'
  BLOCKERS+="       (loudly) so the missing env is visible."$'\n'
  BLOCKERS+="    2. If the skip is genuinely deliberate (e.g. a test for a feature"$'\n'
  BLOCKERS+="       flag that isn't always on), add a same-line comment:"$'\n'
  BLOCKERS+="         test.skip(!FLAG, 'waiting on infra-123'); // harness-allow-skip: feature flag gated"$'\n'
  BLOCKERS+=""$'\n'
fi

# ============================================================
# Report
# ============================================================

if [[ -n "$BLOCKERS" ]]; then
  echo "" >&2
  echo "================================================================" >&2
  echo "COMMIT BLOCKED — Generation 4 TDD gate" >&2
  echo "================================================================" >&2
  echo "" >&2
  echo "$BLOCKERS" >&2
  echo "Why this gate exists:" >&2
  echo "  ~/.claude/docs/../rules/vaporware-prevention.md documents the four" >&2
  echo "  failures that motivated these layers. Each layer blocks a specific" >&2
  echo "  workaround that was used to ship broken code." >&2
  echo "" >&2
  echo "To resolve: address each blocker above. Do not --no-verify." >&2
  echo "" >&2
  exit 1
fi

exit 0
