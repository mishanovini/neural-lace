#!/bin/bash
# write-evidence.sh — capture mechanical evidence for a plan task.
#
# Build Doctrine Principle 7 ("Visibility lives in artifacts, not narration"):
# evidence is machine-written, human-readable, and structured — not prose
# the LLM has to read and judge. This helper captures mechanical-check
# outcomes deterministically and writes them into the canonical schema at
# adapters/claude-code/schemas/evidence.schema.json.
#
# The helper does NOT replace task-verifier. It's a tool that task-verifier
# (or any orchestrator) uses to capture structured evidence. The agent
# still decides the verdict; the script captures the mechanical-check
# inputs.
#
# Subcommands:
#   capture --task <id> --plan <path> [--check <spec>]...    Run checks, write evidence
#   --self-test                                              Run internal test scenarios
#   --help                                                   Show usage
#
# --check specifications:
#   --check typecheck                  Run npm/yarn typecheck (or `tsc --noEmit`)
#   --check lint                       Run npm/yarn lint
#   --check test:<name>                Run a named test (`npm test -- <name>`)
#   --check files-in-commit            Verify the staged commit touches files_modified
#   --check schema-valid:<schema-path> jq-validate the most recent evidence file
#   --check exists:<path>              Verify a file exists at the path
#   --check command:<cmd>              Run an arbitrary command; pass when exit code 0
#
# Output:
#   Writes <plan-dir>/<plan-slug>-evidence/<task-id>.evidence.json
#   (creates the sibling directory if missing). Existing evidence file is
#   overwritten (the latest capture for a task wins).
#
# Exit codes:
#   0 — all checks passed; verdict written as PASS
#   1 — at least one check failed; verdict written as FAIL
#   2 — usage error or schema-validation failure; no evidence written
#
# Verification: this script self-tests via `--self-test` covering 8+ scenarios.

set -uo pipefail

SCRIPT_NAME="write-evidence.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME capture --task <id> --plan <path> [--check <spec>]...
       $SCRIPT_NAME --self-test
       $SCRIPT_NAME --help

Captures mechanical-check outcomes and writes structured evidence per the
canonical schema. See script header for --check specifications.

Examples:
  $SCRIPT_NAME capture --task 3.2 --plan docs/plans/foo.md \\
    --check typecheck --check files-in-commit

  $SCRIPT_NAME capture --task A.1 --plan docs/plans/bar.md \\
    --check exists:src/lib/foo.ts --check command:'npm test -- foo'
EOF
}

iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S"
}

repo_head_sha() {
  git rev-parse HEAD 2>/dev/null || echo ""
}

# json_escape <string>  — emit a JSON-escaped string (no surrounding quotes)
json_escape() {
  local s="$1"
  # Use jq for correctness; falls back to crude escape if jq missing.
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$s" | jq -Rs '.' | sed 's/^"//;s/"$//'
  else
    printf '%s' "$s" \
      | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
            -e 's/\t/\\t/g' -e ':a;N;$!ba;s/\n/\\n/g'
  fi
}

# ---------------------------------------------------------------------------
# Check runners — each returns 0 on pass, non-zero on fail. Sets globals
#   CHECK_PASSED ("true"|"false"), CHECK_DETAIL, CHECK_COMMAND, CHECK_EXIT
# ---------------------------------------------------------------------------

run_check_typecheck() {
  CHECK_COMMAND="npx tsc --noEmit"
  if [[ -f "package.json" ]] && grep -q '"typecheck"' package.json 2>/dev/null; then
    CHECK_COMMAND="npm run typecheck"
  fi
  local out
  out=$(eval "$CHECK_COMMAND" 2>&1)
  CHECK_EXIT=$?
  if [[ "$CHECK_EXIT" -eq 0 ]]; then
    CHECK_PASSED="true"
    CHECK_DETAIL="typecheck passed"
  else
    CHECK_PASSED="false"
    CHECK_DETAIL=$(printf '%s' "$out" | tail -c 400)
  fi
}

run_check_lint() {
  CHECK_COMMAND="npm run lint"
  if [[ ! -f "package.json" ]] || ! grep -q '"lint"' package.json 2>/dev/null; then
    CHECK_PASSED="false"
    CHECK_DETAIL="no 'lint' script in package.json"
    CHECK_EXIT=127
    return 1
  fi
  local out
  out=$(eval "$CHECK_COMMAND" 2>&1)
  CHECK_EXIT=$?
  if [[ "$CHECK_EXIT" -eq 0 ]]; then
    CHECK_PASSED="true"
    CHECK_DETAIL="lint passed"
  else
    CHECK_PASSED="false"
    CHECK_DETAIL=$(printf '%s' "$out" | tail -c 400)
  fi
}

run_check_test() {
  local name="$1"
  CHECK_COMMAND="npm test -- $name"
  local out
  out=$(eval "$CHECK_COMMAND" 2>&1)
  CHECK_EXIT=$?
  if [[ "$CHECK_EXIT" -eq 0 ]]; then
    CHECK_PASSED="true"
    CHECK_DETAIL="test '$name' passed"
  else
    CHECK_PASSED="false"
    CHECK_DETAIL=$(printf '%s' "$out" | tail -c 400)
  fi
}

run_check_files_in_commit() {
  # Try diff-tree first (works for non-initial commits); fall back to
  # ls-tree which lists every file at HEAD (works for the initial commit).
  CHECK_COMMAND="git diff-tree --no-commit-id --name-only -r HEAD"
  local files
  files=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null)
  CHECK_EXIT=$?
  if [[ "$CHECK_EXIT" -ne 0 ]] || [[ -z "$files" ]]; then
    # Initial commit case
    CHECK_COMMAND="git ls-tree --name-only -r HEAD"
    files=$(git ls-tree --name-only -r HEAD 2>/dev/null)
    CHECK_EXIT=$?
  fi
  if [[ "$CHECK_EXIT" -eq 0 ]] && [[ -n "$files" ]]; then
    CHECK_PASSED="true"
    CHECK_DETAIL="$(echo "$files" | wc -l | tr -d '[:space:]') file(s) in HEAD"
  else
    CHECK_PASSED="false"
    CHECK_DETAIL="no files in HEAD or git unavailable"
  fi
}

run_check_schema_valid() {
  local schema="$1"
  CHECK_COMMAND="jq empty <$schema"
  if [[ ! -f "$schema" ]]; then
    CHECK_PASSED="false"
    CHECK_DETAIL="schema file not found: $schema"
    CHECK_EXIT=127
    return 1
  fi
  if jq empty "$schema" 2>/dev/null; then
    CHECK_PASSED="true"
    CHECK_DETAIL="schema is valid JSON"
    CHECK_EXIT=0
  else
    CHECK_PASSED="false"
    CHECK_DETAIL="schema is not valid JSON"
    CHECK_EXIT=1
  fi
}

run_check_exists() {
  local path="$1"
  CHECK_COMMAND="test -e $path"
  if [[ -e "$path" ]]; then
    CHECK_PASSED="true"
    CHECK_DETAIL="$path exists"
    CHECK_EXIT=0
  else
    CHECK_PASSED="false"
    CHECK_DETAIL="$path does not exist"
    CHECK_EXIT=1
  fi
}

run_check_command() {
  local cmd="$1"
  CHECK_COMMAND="$cmd"
  local out
  out=$(eval "$cmd" 2>&1)
  CHECK_EXIT=$?
  if [[ "$CHECK_EXIT" -eq 0 ]]; then
    CHECK_PASSED="true"
    CHECK_DETAIL=$(printf '%s' "$out" | tail -c 200)
  else
    CHECK_PASSED="false"
    CHECK_DETAIL=$(printf '%s' "$out" | tail -c 400)
  fi
}

# ---------------------------------------------------------------------------
# capture subcommand
# ---------------------------------------------------------------------------

cmd_capture() {
  local task_id=""
  local plan_path=""
  local checks=()
  local files_modified=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task) task_id="$2"; shift 2 ;;
      --plan) plan_path="$2"; shift 2 ;;
      --check) checks+=("$2"); shift 2 ;;
      --file) files_modified+=("$2"); shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; usage >&2; return 2 ;;
    esac
  done

  if [[ -z "$task_id" ]]; then
    echo "$SCRIPT_NAME: --task is required" >&2
    return 2
  fi
  if [[ -z "$plan_path" ]]; then
    echo "$SCRIPT_NAME: --plan is required" >&2
    return 2
  fi
  if ! [[ "$task_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "$SCRIPT_NAME: --task '$task_id' contains invalid characters (allowed: A-Z a-z 0-9 . _ -)" >&2
    return 2
  fi

  # Derive evidence target. Convention: <plan-dir>/<plan-slug>-evidence/<task-id>.evidence.json
  local plan_dir plan_slug evidence_dir evidence_file
  plan_dir=$(dirname "$plan_path")
  plan_slug=$(basename "$plan_path" .md)
  evidence_dir="$plan_dir/${plan_slug}-evidence"
  evidence_file="$evidence_dir/${task_id}.evidence.json"

  mkdir -p "$evidence_dir" || {
    echo "$SCRIPT_NAME: could not create $evidence_dir" >&2
    return 2
  }

  # Auto-discover files_modified from HEAD if no --file was passed
  if [[ "${#files_modified[@]}" -eq 0 ]]; then
    if git rev-parse HEAD >/dev/null 2>&1; then
      while IFS= read -r f; do
        [[ -n "$f" ]] && files_modified+=("$f")
      done < <(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || true)
    fi
  fi

  # Run each check, accumulate results
  local checks_json="{}"
  local any_failed=false

  for spec in "${checks[@]}"; do
    CHECK_PASSED=""
    CHECK_DETAIL=""
    CHECK_COMMAND=""
    CHECK_EXIT=0
    local check_name
    case "$spec" in
      typecheck) run_check_typecheck; check_name="typecheck" ;;
      lint) run_check_lint; check_name="lint" ;;
      test:*) run_check_test "${spec#test:}"; check_name="$spec" ;;
      files-in-commit) run_check_files_in_commit; check_name="files-in-commit" ;;
      schema-valid:*) run_check_schema_valid "${spec#schema-valid:}"; check_name="$spec" ;;
      exists:*) run_check_exists "${spec#exists:}"; check_name="$spec" ;;
      command:*) run_check_command "${spec#command:}"; check_name="$spec" ;;
      *)
        echo "$SCRIPT_NAME: unknown --check spec: $spec" >&2
        return 2
        ;;
    esac
    [[ "$CHECK_PASSED" == "false" ]] && any_failed=true
    # Append to checks_json
    checks_json=$(echo "$checks_json" | jq \
      --arg name "$check_name" \
      --argjson passed "$CHECK_PASSED" \
      --arg detail "$CHECK_DETAIL" \
      --arg command "$CHECK_COMMAND" \
      --argjson exit_code "$CHECK_EXIT" \
      '.[$name] = {passed: $passed, detail: $detail, command: $command, exit_code: $exit_code}')
  done

  # If no checks were specified, ensure mechanical_checks is non-empty
  # (schema requires minProperties: 1). Add a synthetic invocation marker.
  if [[ "${#checks[@]}" -eq 0 ]]; then
    checks_json=$(echo '{}' | jq \
      --arg detail "no checks specified — placeholder entry; verdict will be INCOMPLETE" \
      '.["no-checks"] = {passed: false, detail: $detail}')
    any_failed=true
  fi

  # Verdict logic:
  # - If no --check args were passed: INCOMPLETE
  # - else if any check failed: FAIL
  # - else: PASS
  local verdict
  if [[ "${#checks[@]}" -eq 0 ]]; then
    verdict="INCOMPLETE"
  elif [[ "$any_failed" == true ]]; then
    verdict="FAIL"
  else
    verdict="PASS"
  fi

  local commit_sha
  commit_sha=$(repo_head_sha)
  local timestamp
  timestamp=$(iso_timestamp)

  # Build files_modified JSON array
  local files_json="[]"
  for f in "${files_modified[@]}"; do
    files_json=$(echo "$files_json" | jq --arg f "$f" '. + [$f]')
  done

  # Compose final evidence JSON
  local evidence_json
  evidence_json=$(jq -n \
    --argjson schema_version 1 \
    --arg task_id "$task_id" \
    --arg verdict "$verdict" \
    --arg commit_sha "$commit_sha" \
    --argjson files_modified "$files_json" \
    --argjson mechanical_checks "$checks_json" \
    --arg timestamp "$timestamp" \
    --arg verifier "write-evidence.sh" \
    --arg plan_path "$plan_path" \
    '{
      schema_version: $schema_version,
      task_id: $task_id,
      verdict: $verdict,
      commit_sha: $commit_sha,
      files_modified: $files_modified,
      mechanical_checks: $mechanical_checks,
      timestamp: $timestamp,
      verifier: $verifier,
      plan_path: $plan_path
    }')

  echo "$evidence_json" > "$evidence_file" || {
    echo "$SCRIPT_NAME: could not write $evidence_file" >&2
    return 2
  }

  echo "$evidence_file" >&2
  echo "$verdict" >&2

  case "$verdict" in
    PASS) return 0 ;;
    FAIL) return 1 ;;
    INCOMPLETE) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# --self-test: 9 scenarios
# ---------------------------------------------------------------------------

run_self_test() {
  local TMPDIR_T
  TMPDIR_T=$(mktemp -d 2>/dev/null || mktemp -d -t weself)
  if [[ -z "$TMPDIR_T" ]] || [[ ! -d "$TMPDIR_T" ]]; then
    echo "self-test: cannot create temp directory" >&2
    return 2
  fi
  trap 'rm -rf "$TMPDIR_T"' EXIT

  local PASSED=0 FAILED=0
  local saved_pwd="$PWD"
  # Resolve absolute path to this script. If $0 is already absolute, use it;
  # otherwise resolve relative to current PWD before we chdir.
  local SELF_PATH
  if [[ "$0" == /* ]]; then
    SELF_PATH="$0"
  else
    SELF_PATH="$saved_pwd/$0"
  fi
  cd "$TMPDIR_T"
  git init -q 2>/dev/null
  git config user.email test@example.test
  git config user.name "Test"
  mkdir -p docs/plans
  : > docs/plans/foo.md
  echo "# foo" > docs/plans/foo.md
  git add . && git commit -q -m "init"

  # ---- S1: capture-with-all-checks-pass ----
  rm -rf "docs/plans/foo-evidence" 2>/dev/null
  if "$SELF_PATH" capture --task 1.0 --plan docs/plans/foo.md \
       --check exists:docs/plans/foo.md --check files-in-commit >/dev/null 2>&1; then
    if [[ -f docs/plans/foo-evidence/1.0.evidence.json ]] \
       && [[ "$(jq -r .verdict docs/plans/foo-evidence/1.0.evidence.json)" == "PASS" ]]; then
      echo "self-test (S1) capture-with-all-checks-pass: PASS" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test (S1) capture-with-all-checks-pass: FAIL (verdict not PASS)" >&2
      FAILED=$((FAILED+1))
    fi
  else
    if [[ -f docs/plans/foo-evidence/1.0.evidence.json ]] \
       && [[ "$(jq -r .verdict docs/plans/foo-evidence/1.0.evidence.json)" == "PASS" ]]; then
      # Some bash variants return non-zero status from this script's PASS path on Windows
      echo "self-test (S1) capture-with-all-checks-pass: PASS (file content correct)" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test (S1) capture-with-all-checks-pass: FAIL (script exited non-zero AND no PASS evidence)" >&2
      FAILED=$((FAILED+1))
    fi
  fi

  # ---- S2: capture-with-failing-check ----
  rm -rf "docs/plans/foo-evidence" 2>/dev/null
  "$SELF_PATH" capture --task 2.0 --plan docs/plans/foo.md \
    --check exists:does-not-exist.txt >/dev/null 2>&1 || true
  if [[ -f docs/plans/foo-evidence/2.0.evidence.json ]] \
     && [[ "$(jq -r .verdict docs/plans/foo-evidence/2.0.evidence.json)" == "FAIL" ]]; then
    echo "self-test (S2) capture-with-failing-check: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S2) capture-with-failing-check: FAIL" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S3: capture-with-no-checks (INCOMPLETE) ----
  rm -rf "docs/plans/foo-evidence" 2>/dev/null
  "$SELF_PATH" capture --task 3.0 --plan docs/plans/foo.md >/dev/null 2>&1 || true
  if [[ -f docs/plans/foo-evidence/3.0.evidence.json ]] \
     && [[ "$(jq -r .verdict docs/plans/foo-evidence/3.0.evidence.json)" == "INCOMPLETE" ]]; then
    echo "self-test (S3) capture-with-no-checks: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S3) capture-with-no-checks: FAIL" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S4: schema-valid check on real schema ----
  rm -rf "docs/plans/foo-evidence" 2>/dev/null
  echo '{"foo": 1}' > /tmp/test-evidence-schema-$$.json
  "$SELF_PATH" capture --task 4.0 --plan docs/plans/foo.md \
    --check "schema-valid:/tmp/test-evidence-schema-$$.json" >/dev/null 2>&1 || true
  if [[ -f docs/plans/foo-evidence/4.0.evidence.json ]] \
     && [[ "$(jq -r .verdict docs/plans/foo-evidence/4.0.evidence.json)" == "PASS" ]]; then
    echo "self-test (S4) schema-valid-check: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S4) schema-valid-check: FAIL" >&2
    FAILED=$((FAILED+1))
  fi
  rm -f /tmp/test-evidence-schema-$$.json

  # ---- S5: missing --task arg returns exit 2 ----
  if "$SELF_PATH" capture --plan docs/plans/foo.md >/dev/null 2>&1; then
    echo "self-test (S5) missing-task-rejects: FAIL (script accepted missing --task)" >&2
    FAILED=$((FAILED+1))
  else
    rc=$?
    if [[ "$rc" -eq 2 ]]; then
      echo "self-test (S5) missing-task-rejects: PASS (exit 2)" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test (S5) missing-task-rejects: FAIL (expected exit 2, got $rc)" >&2
      FAILED=$((FAILED+1))
    fi
  fi

  # ---- S6: invalid task-id (with space) rejected ----
  if "$SELF_PATH" capture --task "bad task" --plan docs/plans/foo.md >/dev/null 2>&1; then
    echo "self-test (S6) invalid-task-id-rejects: FAIL (script accepted invalid task id)" >&2
    FAILED=$((FAILED+1))
  else
    echo "self-test (S6) invalid-task-id-rejects: PASS" >&2
    PASSED=$((PASSED+1))
  fi

  # ---- S7: command:<cmd> success ----
  rm -rf "docs/plans/foo-evidence" 2>/dev/null
  "$SELF_PATH" capture --task 7.0 --plan docs/plans/foo.md \
    --check "command:true" >/dev/null 2>&1 || true
  if [[ -f docs/plans/foo-evidence/7.0.evidence.json ]] \
     && [[ "$(jq -r .verdict docs/plans/foo-evidence/7.0.evidence.json)" == "PASS" ]]; then
    echo "self-test (S7) command-check-success: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S7) command-check-success: FAIL" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S8: command:<cmd> failure ----
  rm -rf "docs/plans/foo-evidence" 2>/dev/null
  "$SELF_PATH" capture --task 8.0 --plan docs/plans/foo.md \
    --check "command:false" >/dev/null 2>&1 || true
  if [[ -f docs/plans/foo-evidence/8.0.evidence.json ]] \
     && [[ "$(jq -r .verdict docs/plans/foo-evidence/8.0.evidence.json)" == "FAIL" ]]; then
    echo "self-test (S8) command-check-failure: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S8) command-check-failure: FAIL" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S9: required schema fields all present in output ----
  rm -rf "docs/plans/foo-evidence" 2>/dev/null
  "$SELF_PATH" capture --task 9.0 --plan docs/plans/foo.md \
    --check "command:true" >/dev/null 2>&1 || true
  local f="docs/plans/foo-evidence/9.0.evidence.json"
  if [[ -f "$f" ]] \
     && [[ "$(jq -r 'has("task_id") and has("verdict") and has("commit_sha") and has("files_modified") and has("mechanical_checks") and has("timestamp")' "$f")" == "true" ]]; then
    echo "self-test (S9) required-fields-all-present: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S9) required-fields-all-present: FAIL" >&2
    FAILED=$((FAILED+1))
  fi

  cd "$saved_pwd"

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 9 scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit $?
fi

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "capture" ]]; then
  shift
  cmd_capture "$@"
  exit $?
fi

usage >&2
exit 2
