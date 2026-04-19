#!/bin/bash
# runtime-verification-executor.sh — Generation 4
#
# Parses "Runtime verification:" lines from an evidence file or section
# and EXECUTES each one. The hook verifies claims by running them, not
# by reading them.
#
# Accepted formats (one per line, prefix "Runtime verification: "):
#
#   test <test-file>::<test-name>
#     Requires the test file exists and defines a test with that name.
#     Does not run the test suite (too slow for a stop hook); just
#     verifies the named test is defined. This catches "I wrote a test"
#     claims that don't match any real test.
#
#   curl <full curl command including URL and flags>
#     Replays the curl command. FAILs if the command exits non-zero
#     or if the response contains "error" at the top level.
#     Example:
#       Runtime verification: curl -s http://localhost:3000/api/foo
#
#   sql <SELECT statement>
#     Runs the SELECT against the Supabase test project via psql.
#     Requires $SUPABASE_TEST_DB_URL or falls back to skipping with
#     a warning. FAILs if the query errors.
#     Example:
#       Runtime verification: sql SELECT count(*) FROM messages WHERE metadata IS NOT NULL
#
#   playwright <spec-file>::<test-name>
#     Verifies the spec file exists and defines a test with that name.
#     Does not run Playwright (slow); just asserts the test exists.
#
#   file <path>::<line-pattern>
#     Verifies the file exists and contains a line matching the pattern.
#     Used for "this code change is present at file:line" checks.
#
# ANY OTHER FORMAT IS REJECTED as unparseable — including bare text like
# "manual test done" or "verified in browser". That is the whole point.
#
# Usage:
#   bash runtime-verification-executor.sh <evidence-file>
#   OR
#   cat evidence.md | bash runtime-verification-executor.sh -
#
# Exit codes:
#   0 — every Runtime verification: line parsed AND executed successfully
#   1 — one or more lines failed (stderr lists each)
#   2 — input error (file missing, empty, etc.)

set -u

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <evidence-file|->" >&2
  exit 2
fi

INPUT_SRC="$1"

if [[ "$INPUT_SRC" == "-" ]]; then
  EVIDENCE=$(cat)
else
  if [[ ! -f "$INPUT_SRC" ]]; then
    echo "runtime-verification-executor: input file not found: $INPUT_SRC" >&2
    exit 2
  fi
  EVIDENCE=$(cat "$INPUT_SRC")
fi

if [[ -z "$EVIDENCE" ]]; then
  # Empty input — nothing to verify. Treat as success (the caller should
  # have its own "evidence exists" check).
  exit 0
fi

# Extract Runtime verification: lines
LINES=$(echo "$EVIDENCE" | grep -E '^Runtime verification:' || true)

if [[ -z "$LINES" ]]; then
  # No runtime-verification entries at all. The caller decides whether
  # that's acceptable (pre-stop-verifier blocks in some cases).
  exit 0
fi

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=""

while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  # Strip the "Runtime verification: " prefix
  body="${line#Runtime verification:}"
  body="${body# }"  # trim leading space

  # First token is the format type
  fmt=$(echo "$body" | awk '{print $1}')
  rest=$(echo "$body" | cut -d' ' -f2-)

  case "$fmt" in
    test|playwright)
      # Format: test <file>::<name>  OR  playwright <spec>::<name>
      #
      # Verifies the cited test (a) exists in the file, (b) is not itself
      # a skipped test, and (c) the file does not contain runtime
      # conditional skips that could silently no-op the entire suite.
      #
      # Check (c) was added to catch "vaporware tests" — tests that
      # appear to run but are runtime-skipped by conditions like
      # `test.skip(!ENV_VAR, '...')` at the top of a describe block
      # that evaluates false whenever the env var is unset. Rather than
      # re-running every test at session end (too slow), the executor
      # statically rejects any file where a named test or the enclosing
      # describe is skippable without positive proof that the skip is
      # deliberate.
      #
      # Escape hatch: annotate the skip line with
      #   // harness-allow-skip: <short reason>
      # and the check will pass. Use this for genuinely optional tests
      # (e.g. tests that require a feature flag), not for "the credential
      # isn't set yet" skips — those ARE the failure mode this guards.
      if [[ "$rest" != *"::"* ]]; then
        FAILURES+="  INVALID: '$line' — expected '$fmt <file>::<name>'"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      test_file="${rest%%::*}"
      test_name="${rest#*::}"
      if [[ ! -f "$test_file" ]]; then
        FAILURES+="  FAIL: '$line' — $fmt file not found: $test_file"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Must grep for test('<name>' OR it('<name>' (unquoted styles too)
      if ! grep -qE "(test|it)\s*\(\s*['\"]${test_name}['\"]" "$test_file" 2>/dev/null; then
        FAILURES+="  FAIL: '$line' — no test named '$test_name' in $test_file"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Check (b): the cited test itself is written as .skip(...)
      if grep -qE "(test|it)\.skip\s*\(\s*['\"]${test_name}['\"]" "$test_file" 2>/dev/null; then
        FAILURES+="  FAIL: '$line' — cited test is written as .skip() in $test_file. A skipped test cannot serve as runtime verification. Remove the .skip or pick a different test."$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Check (c): the file contains a runtime conditional skip that can
      # no-op the whole suite (e.g. test.skip(!ENV_VAR, 'reason') or
      # test.skip(process.env.X == null, ...)). Allowed only if the line
      # carries a `// harness-allow-skip:` annotation.
      conditional_skips=$(grep -nE "(test|describe|it)\.skip\s*\(\s*(!|process\.env|typeof\s+process)" "$test_file" 2>/dev/null || true)
      if [[ -n "$conditional_skips" ]]; then
        # Check each flagged line for an allow annotation on the same line
        unannotated=""
        while IFS= read -r flagged; do
          [[ -z "$flagged" ]] && continue
          if echo "$flagged" | grep -q "harness-allow-skip:"; then
            continue
          fi
          unannotated+="      $flagged"$'\n'
        done <<< "$conditional_skips"
        if [[ -n "$unannotated" ]]; then
          FAILURES+="  FAIL: '$line' — $test_file contains unannotated runtime conditional skips that can silently no-op the suite. Either remove the skip or add '// harness-allow-skip: <reason>' on the same line."$'\n'
          FAILURES+="$unannotated"
          FAIL_COUNT=$((FAIL_COUNT + 1))
          continue
        fi
      fi
      PASS_COUNT=$((PASS_COUNT + 1))
      ;;

    curl)
      # Format: curl <full command>
      # We run it with a short timeout and check exit code + response.
      #
      # SECURITY: previously this used `bash -c "curl ... $rest"` which
      # shell-interpolated the user-supplied tail. Evidence like
      # `curl http://x.com; rm -rf ~` would execute the `rm`. That was a
      # pre-stop-verifier code-execution bug. The fix: parse $rest as an
      # argv array, reject any entry containing shell metacharacters, and
      # exec curl directly (no shell).
      if [[ -z "$rest" ]]; then
        FAILURES+="  INVALID: '$line' — empty curl command"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Reject shell metacharacters that would allow command injection
      # if any future change re-introduces `bash -c`. Also rejects them
      # now to ensure the evidence is a pure curl invocation, nothing else.
      if echo "$rest" | grep -qE '[;&|`$(){}<>]|\$\(|&&|\|\|'; then
        FAILURES+="  INVALID: '$line' — curl command contains shell metacharacters (; & | \` \$ () {} <> && || \$()); evidence must be a pure curl invocation"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Split $rest on whitespace into argv (word-splitting is desired here
      # precisely because we rejected shell metacharacters above).
      # shellcheck disable=SC2206
      curl_args=($rest)
      # Force our safe flags in front regardless of what the builder wrote
      response=$(timeout 10 curl -s --max-time 8 --connect-timeout 3 "${curl_args[@]}" 2>&1)
      curl_exit=$?
      if [[ $curl_exit -ne 0 ]]; then
        FAILURES+="  FAIL: '$line' — curl exit $curl_exit: $(echo "$response" | head -c 200)"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Detect a top-level JSON error field as a failure signal
      if echo "$response" | grep -qE '^\{"error":' || echo "$response" | grep -qE '"status":\s*"error"'; then
        FAILURES+="  FAIL: '$line' — response contains error: $(echo "$response" | head -c 200)"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      PASS_COUNT=$((PASS_COUNT + 1))
      ;;

    sql)
      # Format: sql <SELECT statement>
      #
      # Previously this SKIP-ed with PASS if $SUPABASE_TEST_DB_URL or psql
      # was missing. That was a free-pass loophole: any evidence could ship
      # `sql SELECT ...` in a DB-less environment and auto-PASS. The fix:
      # missing env or missing psql is a FAIL, not a SKIP. The builder is
      # responsible for providing verification the harness can actually run.
      if [[ -z "$rest" ]]; then
        FAILURES+="  INVALID: '$line' — empty SQL statement"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      if [[ -z "${SUPABASE_TEST_DB_URL:-}" ]]; then
        FAILURES+="  FAIL: '$line' — SUPABASE_TEST_DB_URL not set. SQL verification cannot be executed. Either set the env var or use a different Runtime verification format (curl/test/playwright/file)."$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      if ! command -v psql >/dev/null 2>&1; then
        FAILURES+="  FAIL: '$line' — psql not installed. SQL verification cannot be executed. Install postgresql-client or use a different Runtime verification format."$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      if echo "$rest" | psql "$SUPABASE_TEST_DB_URL" -q >/dev/null 2>&1; then
        PASS_COUNT=$((PASS_COUNT + 1))
      else
        FAILURES+="  FAIL: '$line' — SQL statement errored against test DB"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
      ;;

    file)
      # Format: file <path>::<line-pattern>
      if [[ "$rest" != *"::"* ]]; then
        FAILURES+="  INVALID: '$line' — expected 'file <path>::<line-pattern>'"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      file_path="${rest%%::*}"
      pattern="${rest#*::}"

      # Reject trivially-matching patterns. The adversarial harness review
      # found that `file <any>::.*` trivially passes. Require that the
      # pattern contain at least 5 non-regex-meta characters to prove the
      # builder actually cited specific content.
      literal_chars=$(echo "$pattern" | tr -d '.*+?^$[](){}|\\')
      if [[ "${#literal_chars}" -lt 5 ]]; then
        FAILURES+="  INVALID: '$line' — pattern '$pattern' has fewer than 5 literal characters; specify a concrete substring of the code you claim to verify"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi

      # Reject patterns that are entirely metacharacters or would match any file
      if [[ "$pattern" == ".*" || "$pattern" == ".+" || "$pattern" == "^.*$" || "$pattern" == "^.+$" ]]; then
        FAILURES+="  INVALID: '$line' — pattern '$pattern' matches anything"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi

      if [[ ! -f "$file_path" ]]; then
        FAILURES+="  FAIL: '$line' — file not found: $file_path"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      if grep -qE "$pattern" "$file_path" 2>/dev/null; then
        PASS_COUNT=$((PASS_COUNT + 1))
      else
        FAILURES+="  FAIL: '$line' — pattern '$pattern' not found in $file_path"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
      ;;

    *)
      # Unknown format (bare text, "manual test done", etc.)
      FAILURES+="  INVALID: '$line' — unknown format '$fmt'. Accepted: test, playwright, curl, sql, file."$'\n'
      FAIL_COUNT=$((FAIL_COUNT + 1))
      ;;
  esac
done <<< "$LINES"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "" >&2
  echo "runtime-verification-executor: $FAIL_COUNT failure(s), $PASS_COUNT pass(es)" >&2
  echo "$FAILURES" >&2
  exit 1
fi

echo "runtime-verification-executor: all $PASS_COUNT verification(s) passed" >&2
exit 0
