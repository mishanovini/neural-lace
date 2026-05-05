#!/bin/bash
# spawned-task-result-surfacer.sh
#
# SessionStart hook that scans `.claude/state/spawned-task-results/` in the
# current working directory for unread spawn-task result JSON files and
# surfaces them as a system-reminder so the orchestrator (or the user)
# sees results from previously-dispatched spawn-tasks before further work
# begins.
#
# This is the surfacing half of the spawn-task-report-back protocol. The
# capture half is owned by the spawn-task workflow itself: when a spawned
# task completes, it writes a JSON artifact at
# `.claude/state/spawned-task-results/<task-id>.json`. When the result is
# observed and acknowledged, an `<task-id>.json.acked` sibling file is
# created, which suppresses re-surfacing.
#
# Design notes:
# - Mirrors `discovery-surfacer.sh` exactly in shape (SessionStart hook,
#   silent-when-empty, exit-0-always, --self-test flag).
# - Reads JSON on stdin per the Claude Code SessionStart hook contract,
#   but the payload is unused — the hook acts on the working directory.
# - On any unrecoverable error (missing dir, no unread files), exits 0
#   silently. Surfacing is informational; never block session start.
# - For each unread result, extracts task_id, summary, branch, commits,
#   ended_at from the JSON. Uses `jq` if available, otherwise falls back
#   to grep/sed.
# - Output is plain stdout text — the same convention used by other
#   SessionStart hooks in this harness (see discovery-surfacer.sh and
#   the inline commands in settings.json.template).
#
# Self-test: invoke with --self-test to exercise five scenarios.

set -u

# -------- Utility: extract a top-level JSON scalar field --------
# Args: $1 = file path, $2 = field name.
# Prefers jq when available; falls back to grep/sed for the common
# `"key": "value"` shape. Returns empty string on failure (caller handles).
json_field() {
  local file="$1"
  local key="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null
  else
    # Best-effort: match `"key"\s*:\s*"value"` and emit value with
    # surrounding quotes stripped. Multi-line JSON is fine because we
    # only look at lines containing the literal key.
    grep -E "\"${key}\"[[:space:]]*:" "$file" 2>/dev/null \
      | head -n 1 \
      | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"?//; s/\"?[[:space:]]*,?[[:space:]]*$//"
  fi
}

# -------- Utility: extract a JSON array field as space-separated values --------
# Args: $1 = file path, $2 = field name (must be an array of strings).
# Prefers jq. Falls back to a simple bracket-content extractor.
json_array_field() {
  local file="$1"
  local key="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // [] | join(" ")' "$file" 2>/dev/null
  else
    # Best-effort: pull the bracketed body after the key, strip quotes
    # and commas. Not robust against deeply-nested arrays but adequate
    # for the array-of-string shape spawn-task results use.
    awk -v key="$key" '
      BEGIN { found = 0; out = "" }
      {
        if (!found && index($0, "\"" key "\"") > 0) {
          # Capture from this line onward until we close the array.
          line = $0
          # Strip up to the opening bracket.
          sub(/.*\[/, "", line)
          if (index(line, "]") > 0) {
            sub(/\].*/, "", line)
            out = line
            found = 1
            exit
          } else {
            out = line
            found = 1
          }
          next
        }
        if (found) {
          line = $0
          if (index(line, "]") > 0) {
            sub(/\].*/, "", line)
            out = out " " line
            exit
          }
          out = out " " line
        }
      }
      END {
        # Normalize: strip quotes, commas, surrounding whitespace.
        gsub(/"/, "", out)
        gsub(/,/, " ", out)
        gsub(/[[:space:]]+/, " ", out)
        sub(/^[[:space:]]+/, "", out)
        sub(/[[:space:]]+$/, "", out)
        print out
      }
    ' "$file" 2>/dev/null
  fi
}

# -------- Utility: detect whether a file is well-formed JSON --------
# Returns 0 if valid (or jq unavailable + file looks JSON-ish), 1 otherwise.
# When jq is unavailable, applies a minimal heuristic: file starts with
# `{` and ends with `}` after stripping trailing whitespace.
is_valid_json() {
  local file="$1"
  [ -f "$file" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq empty "$file" >/dev/null 2>&1
    return $?
  fi
  # Fallback heuristic: first non-whitespace char `{` and last `}`.
  local first last
  first=$(awk 'NF { print substr($0, 1, 1); exit }' "$file" 2>/dev/null)
  last=$(awk 'NF { line = $0 } END { if (line) print substr(line, length(line), 1) }' "$file" 2>/dev/null)
  [ "$first" = "{" ] && [ "$last" = "}" ]
}

# -------- Core surfacing logic --------
# Args (for testability):
#   $1 = working directory to scan (defaults to $PWD)
# Writes the system-reminder block to stdout. Exits 0 always.
surface_spawned_task_results() {
  local cwd="${1:-$PWD}"
  local results_dir="$cwd/.claude/state/spawned-task-results"

  # If the directory doesn't exist, exit silently. This is the common
  # case in projects that haven't dispatched any spawn-tasks yet.
  if [ ! -d "$results_dir" ]; then
    return 0
  fi

  # Collect unread result files: *.json without a sibling *.json.acked.
  local unread_files=()
  local f base
  for f in "$results_dir"/*.json; do
    [ -f "$f" ] || continue
    # Skip the .acked files themselves (they end in .json.acked which
    # also matches *.json globbing only if we don't filter — but glob
    # on *.json doesn't match *.json.acked, so this is a defensive
    # check for double-suffixed filenames).
    case "$f" in
      *.json.acked) continue ;;
    esac

    # Skip if .acked sibling exists.
    if [ -f "${f}.acked" ]; then
      continue
    fi

    # Validate JSON; emit a stderr warning and skip on malformed.
    if ! is_valid_json "$f"; then
      base=$(basename "$f")
      echo "[spawned-task-surfacer] skipping $base (malformed JSON)" >&2
      continue
    fi

    unread_files+=("$f")
  done

  # Empty (no unread results) -> silent.
  if [ "${#unread_files[@]}" -eq 0 ]; then
    return 0
  fi

  # Sort the file list so output order is stable across runs.
  local sorted_files=()
  while IFS= read -r line; do
    [ -n "$line" ] && sorted_files+=("$line")
  done < <(printf '%s\n' "${unread_files[@]}" | sort)

  # Emit the system-reminder block.
  local count="${#sorted_files[@]}"
  echo "[spawned-task-surfacer] $count unread spawned-task result(s) require attention:"
  echo ""

  local task_id summary branch commits ended_at
  for f in "${sorted_files[@]}"; do
    base=$(basename "$f")
    task_id=$(json_field "$f" "task_id")
    summary=$(json_field "$f" "summary")
    branch=$(json_field "$f" "branch")
    commits=$(json_array_field "$f" "commits")
    ended_at=$(json_field "$f" "ended_at")

    # Fallbacks so the block is always readable even when fields are
    # partial.
    [ -z "$task_id" ] && task_id="(unknown)"
    [ -z "$summary" ] && summary="(no summary provided)"
    [ -z "$branch" ] && branch="(no branch recorded)"
    [ -z "$commits" ] && commits="(no commits recorded)"
    [ -z "$ended_at" ] && ended_at="(no end time recorded)"

    # Truncate summary to ~200 chars for the surface.
    if [ ${#summary} -gt 200 ]; then
      summary="${summary:0:200}…"
    fi

    echo "  • Task: $task_id (ended: $ended_at)"
    echo "    Summary: $summary"
    echo "    Branch: $branch"
    echo "    Commits: $commits"
    echo "    File: .claude/state/spawned-task-results/$base"
    echo ""
  done

  echo "These spawned-task results have not yet been acknowledged. Per the"
  echo "spawn-task-report-back protocol: review each result, then mark it"
  echo "acknowledged by creating a sibling file with .acked suffix, e.g.:"
  echo "  touch .claude/state/spawned-task-results/<task-id>.json.acked"
}

# -------- Self-test --------
run_self_test() {
  local tmp failures=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t stsfc)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  run_scenario() {
    local label="$1" expect_output="$2" project_dir="$3" out
    out=$(surface_spawned_task_results "$project_dir" 2>/dev/null)
    if [ "$expect_output" = "yes" ]; then
      if [ -z "$out" ]; then
        echo "FAIL: [$label] expected output but got none" >&2
        failures=$((failures + 1))
      else
        echo "PASS: [$label] surfaced as expected"
      fi
    elif [ "$expect_output" = "named" ]; then
      # Caller passed an additional 4th argument: the task_id we expect.
      local expected_id="$4"
      if [ -z "$out" ]; then
        echo "FAIL: [$label] expected output but got none" >&2
        failures=$((failures + 1))
      elif ! echo "$out" | grep -qF "$expected_id"; then
        echo "FAIL: [$label] output did not name '$expected_id':" >&2
        echo "$out" | head -n 5 | sed 's/^/    /' >&2
        failures=$((failures + 1))
      else
        echo "PASS: [$label] surfaced and named '$expected_id'"
      fi
    else
      if [ -n "$out" ]; then
        echo "FAIL: [$label] expected silence but got: $out" >&2
        failures=$((failures + 1))
      else
        echo "PASS: [$label] silent as expected"
      fi
    fi
  }

  # ---- Scenario 1: no .claude/state/spawned-task-results directory ----
  local s1="$tmp/no-results-dir"
  mkdir -p "$s1"
  run_scenario "no-directory" no "$s1"

  # ---- Scenario 2: directory exists but empty ----
  local s2="$tmp/empty-results-dir"
  mkdir -p "$s2/.claude/state/spawned-task-results"
  run_scenario "empty-directory" no "$s2"

  # ---- Scenario 3: all results have .acked siblings ----
  local s3="$tmp/all-acked"
  mkdir -p "$s3/.claude/state/spawned-task-results"
  cat > "$s3/.claude/state/spawned-task-results/task-001.json" <<'EOF'
{
  "task_id": "task-001",
  "summary": "Already-acknowledged result",
  "branch": "feat/example",
  "commits": ["abc1234"],
  "ended_at": "2026-05-04T12:00:00Z"
}
EOF
  touch "$s3/.claude/state/spawned-task-results/task-001.json.acked"
  cat > "$s3/.claude/state/spawned-task-results/task-002.json" <<'EOF'
{
  "task_id": "task-002",
  "summary": "Also acknowledged",
  "branch": "feat/another",
  "commits": ["def5678"],
  "ended_at": "2026-05-04T13:00:00Z"
}
EOF
  touch "$s3/.claude/state/spawned-task-results/task-002.json.acked"
  run_scenario "all-acked" no "$s3"

  # ---- Scenario 4: one result without .acked sibling ----
  local s4="$tmp/has-unread"
  mkdir -p "$s4/.claude/state/spawned-task-results"
  cat > "$s4/.claude/state/spawned-task-results/task-099.json" <<'EOF'
{
  "task_id": "task-099-needs-review",
  "summary": "Self-test fixture: this result has no .acked sibling and should be surfaced.",
  "branch": "feat/spawn-task-report-back",
  "commits": ["aacca63", "f41980b"],
  "ended_at": "2026-05-05T10:30:00Z"
}
EOF
  run_scenario "has-unread" named "$s4" "task-099-needs-review"

  # ---- Scenario 5: malformed JSON file alongside one valid unread file ----
  local s5="$tmp/mixed-malformed-and-valid"
  mkdir -p "$s5/.claude/state/spawned-task-results"
  # Valid file
  cat > "$s5/.claude/state/spawned-task-results/task-100.json" <<'EOF'
{
  "task_id": "task-100-valid",
  "summary": "Valid result that should still surface despite a sibling malformed file.",
  "branch": "feat/example",
  "commits": ["1234567"],
  "ended_at": "2026-05-05T11:00:00Z"
}
EOF
  # Malformed file (missing closing brace + invalid JSON)
  cat > "$s5/.claude/state/spawned-task-results/task-101.json" <<'EOF'
{ this is not valid json
EOF
  # Capture stderr too so we can confirm the malformed-skip warning fires.
  local stderr_capture out
  stderr_capture=$(mktemp)
  out=$(surface_spawned_task_results "$s5" 2>"$stderr_capture")
  if echo "$out" | grep -qF "task-100-valid"; then
    echo "PASS: [malformed-and-valid] surfaced valid result"
  else
    echo "FAIL: [malformed-and-valid] valid result not surfaced" >&2
    failures=$((failures + 1))
  fi
  if grep -qF "skipping task-101.json (malformed JSON)" "$stderr_capture"; then
    echo "PASS: [malformed-and-valid] emitted stderr warning for malformed file"
  else
    echo "FAIL: [malformed-and-valid] missing stderr warning for malformed file" >&2
    echo "    stderr was:" >&2
    cat "$stderr_capture" | sed 's/^/    /' >&2
    failures=$((failures + 1))
  fi
  rm -f "$stderr_capture"

  if [ "$failures" -eq 0 ]; then
    echo ""
    echo "SELF-TEST: all scenarios passed (5/5 required)"
    return 0
  else
    echo ""
    echo "SELF-TEST: $failures scenario(s) failed" >&2
    return 1
  fi
}

# -------- Entry point --------
if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

# Normal invocation: consume any stdin JSON payload (Claude Code hook
# contract) but we don't need to parse it — the hook acts on the
# working directory.
if [ ! -t 0 ]; then
  cat >/dev/null 2>&1 || true
fi

surface_spawned_task_results "$PWD"
exit 0
