#!/bin/bash
# effort-policy-warn.sh
#
# SessionStart hook that warns when the configured effort level is below the
# policy minimum declared by either a project-level or user-level policy file.
#
# Lookup order (first match wins):
#   1. ./.claude/effort-policy.json           (project-level, highest priority)
#   2. ~/.claude/local/effort-policy.json     (user-level fallback)
#   3. no policy => silent (exit 0)
#
# Effort source detection (first non-empty wins):
#   1. $CLAUDE_CODE_EFFORT_LEVEL env var
#   2. .effortLevel field from ~/.claude/settings.json
#   3. treated as "unknown" => warn, since we cannot confirm compliance
#
# Ordering: low < medium < high < xhigh < max. Max is the top level.
#
# Non-blocking: always exits 0. Emits warnings on stderr only.
#
# Self-test: invoke with --self-test to exercise several scenarios.

set -u

# -------- Utility: rank an effort level to a comparable integer --------
effort_rank() {
  case "${1:-}" in
    low)    echo 1 ;;
    medium) echo 2 ;;
    high)   echo 3 ;;
    xhigh)  echo 4 ;;
    max)    echo 5 ;;
    *)      echo 0 ;;   # unknown / unset
  esac
}

# -------- Utility: read minimum_effort_level from a policy file --------
read_policy_minimum() {
  local file="$1"
  [ -f "$file" ] || { echo ""; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r '.minimum_effort_level // empty' "$file" 2>/dev/null
  else
    grep -oE '"minimum_effort_level"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" \
      | sed -E 's/.*"([^"]*)"$/\1/'
  fi
}

# -------- Core policy check --------
# Prints warning to stderr if the effective level is below the minimum.
# Takes optional explicit args for testing; otherwise reads real environment.
check_policy() {
  local project_policy="${1:-./.claude/effort-policy.json}"
  local user_policy="${2:-$HOME/.claude/local/effort-policy.json}"
  local env_effort="${3:-${CLAUDE_CODE_EFFORT_LEVEL:-}}"
  local settings_json="${4:-$HOME/.claude/settings.json}"

  # 1. Resolve policy minimum
  local minimum="" source=""
  if [ -f "$project_policy" ]; then
    minimum=$(read_policy_minimum "$project_policy")
    source="project ($project_policy)"
  elif [ -f "$user_policy" ]; then
    minimum=$(read_policy_minimum "$user_policy")
    source="user ($user_policy)"
  fi

  # No policy? Stay silent.
  if [ -z "$minimum" ]; then
    return 0
  fi

  # 2. Resolve configured effort
  local current=""
  if [ -n "$env_effort" ]; then
    current="$env_effort"
  elif [ -f "$settings_json" ] && command -v jq >/dev/null 2>&1; then
    current=$(jq -r '.effortLevel // empty' "$settings_json" 2>/dev/null)
  fi

  local min_rank cur_rank
  min_rank=$(effort_rank "$minimum")
  cur_rank=$(effort_rank "$current")

  # 3. Compare and warn
  if [ "$min_rank" -eq 0 ]; then
    echo "effort-policy-warn: policy file has unrecognized minimum_effort_level='$minimum' (source: $source)" >&2
    return 0
  fi

  if [ "$cur_rank" -eq 0 ]; then
    echo "effort-policy-warn: policy source $source requires minimum_effort_level='$minimum' but the current effort level could not be determined (env CLAUDE_CODE_EFFORT_LEVEL unset and no .effortLevel in settings.json). Run /effort $minimum to set the session level, or edit ~/.claude/settings.json." >&2
    return 0
  fi

  if [ "$cur_rank" -lt "$min_rank" ]; then
    echo "effort-policy-warn: current effort level '$current' is below policy minimum '$minimum' (source: $source). Run /effort $minimum to raise the session level, or update ~/.claude/settings.json effortLevel." >&2
  fi
}

# -------- Self-test --------
run_self_test() {
  local tmp failures=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t efp)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  local project_dir="$tmp/project"
  local user_dir="$tmp/user"
  mkdir -p "$project_dir/.claude" "$user_dir"

  local proj_pol="$project_dir/.claude/effort-policy.json"
  local user_pol="$user_dir/effort-policy.json"
  local settings="$tmp/settings.json"

  run_scenario() {
    local label="$1" expect_warn="$2" out
    shift 2
    out=$(check_policy "$@" 2>&1 >/dev/null)
    if [ "$expect_warn" = "yes" ]; then
      if [ -z "$out" ]; then
        echo "FAIL: [$label] expected warning but got none" >&2
        failures=$((failures + 1))
      else
        echo "PASS: [$label] warned as expected"
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

  # Scenario 1: no policy anywhere => silent
  run_scenario "no-policy" no \
    "$tmp/nope.json" "$tmp/nope2.json" "" "$tmp/no-settings.json"

  # Scenario 2: user policy xhigh, env=high => warn
  echo '{"minimum_effort_level":"xhigh"}' > "$user_pol"
  run_scenario "user-xhigh-env-high" yes \
    "$tmp/nope.json" "$user_pol" "high" "$tmp/no-settings.json"

  # Scenario 3: user policy xhigh, env=xhigh => silent
  run_scenario "user-xhigh-env-xhigh" no \
    "$tmp/nope.json" "$user_pol" "xhigh" "$tmp/no-settings.json"

  # Scenario 4: user policy xhigh, env=max => silent (max >= xhigh)
  run_scenario "user-xhigh-env-max" no \
    "$tmp/nope.json" "$user_pol" "max" "$tmp/no-settings.json"

  # Scenario 5: project overrides user (project=max, user=low) with env=high => warn
  echo '{"minimum_effort_level":"max"}' > "$proj_pol"
  echo '{"minimum_effort_level":"low"}' > "$user_pol"
  run_scenario "project-overrides-user" yes \
    "$proj_pol" "$user_pol" "high" "$tmp/no-settings.json"

  # Scenario 6: env unset, settings.json effortLevel=medium, policy=high => warn
  echo '{"effortLevel":"medium"}' > "$settings"
  echo '{"minimum_effort_level":"high"}' > "$user_pol"
  rm -f "$proj_pol"
  run_scenario "settings-fallback-below" yes \
    "$tmp/nope.json" "$user_pol" "" "$settings"

  # Scenario 7: env unset, settings.json effortLevel=xhigh, policy=high => silent
  echo '{"effortLevel":"xhigh"}' > "$settings"
  run_scenario "settings-fallback-above" no \
    "$tmp/nope.json" "$user_pol" "" "$settings"

  # Scenario 8: env unset, no settings.json => warn about unknown current
  run_scenario "unknown-current" yes \
    "$tmp/nope.json" "$user_pol" "" "$tmp/no-settings.json"

  # Scenario 9: policy=max, env=xhigh => warn (max is strictly above xhigh)
  echo '{"minimum_effort_level":"max"}' > "$user_pol"
  run_scenario "policy-max-env-xhigh" yes \
    "$tmp/nope.json" "$user_pol" "xhigh" "$tmp/no-settings.json"

  # Scenario 10: policy=max, env=max => silent
  run_scenario "policy-max-env-max" no \
    "$tmp/nope.json" "$user_pol" "max" "$tmp/no-settings.json"

  if [ "$failures" -eq 0 ]; then
    echo "SELF-TEST: all scenarios passed"
    return 0
  else
    echo "SELF-TEST: $failures scenario(s) failed" >&2
    return 1
  fi
}

# -------- Entry point --------
if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

# Normal invocation: consume any stdin JSON payload (Claude Code hook contract)
# but we don't need to parse it — the hook acts on environment + filesystem.
if [ ! -t 0 ]; then
  cat >/dev/null 2>&1 || true
fi

check_policy
exit 0
