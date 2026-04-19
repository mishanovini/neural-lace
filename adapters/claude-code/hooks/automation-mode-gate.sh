#!/bin/bash
# NEURAL-LACE-AUTOMATION-MODE-GATE v1 — pauses deploy-class Bash commands in review-before-deploy mode
#
# Purpose: PreToolUse Bash hook that reads the effective automation mode +
# matchers and BLOCKS Bash commands matching deploy-class patterns when the
# mode is "review-before-deploy".
#
# The effective config is sourced via read-local-config.sh, which applies the
# following resolution order:
#   1. $PWD/.claude/automation-mode.json (per-project override)
#   2. ~/.claude/local/automation-mode.config.json (user-global via helper)
#   3. Hardcoded fallback (mode=review-before-deploy + default matcher list)
#
# USAGE (PreToolUse Bash hook in settings.json):
#   bash ~/.claude/hooks/automation-mode-gate.sh
#
# SELF-TEST:
#   bash automation-mode-gate.sh --self-test
#
# EXIT CODES:
#   0 — pass through (full-auto mode, no match, or malformed/missing input)
#   1 — BLOCKED: command matches deploy matcher in review-before-deploy mode
#
# DESIGN NOTES:
# - Errs toward pass-through on malformed input. The gate's job is to surface
#   a review prompt, not to validate harness-plumbing correctness.
# - Matching is whole-word / prefix-aware: "git push" matches "git push origin
#   main" but NOT "my-git push-helper.sh".
# - Matchers are case-sensitive (deploy commands like "git push" are lowercase
#   in practice; case-insensitivity would expand the false-positive surface).

# ============================================================
# Resolve the hook's own absolute directory at load time, BEFORE any
# function is called. Self-test does `cd` into a temp dir; if we tried to
# resolve BASH_SOURCE[0] inside _run_gate at that point, a relative path
# would already have been invalidated by the cwd change.
# ============================================================
_NL_GATE_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd 2>/dev/null)"

# ============================================================
# Core gate logic, factored into a function so --self-test can
# invoke it repeatedly with synthesized CLAUDE_TOOL_INPUT.
# ============================================================
_run_gate() {
  # Step 1: find + source the config helper (if available)
  # Candidate locations, in precedence order:
  #   1. ~/.claude/scripts/read-local-config.sh (installed harness layout)
  #   2. <repo>/adapters/claude-code/scripts/read-local-config.sh (dev repo)
  local helper=""
  if [ -f "$HOME/.claude/scripts/read-local-config.sh" ]; then
    helper="$HOME/.claude/scripts/read-local-config.sh"
  elif [ -n "$_NL_GATE_HOOK_DIR" ] && [ -f "$_NL_GATE_HOOK_DIR/../scripts/read-local-config.sh" ]; then
    helper="$_NL_GATE_HOOK_DIR/../scripts/read-local-config.sh"
  fi

  if [ -n "$helper" ]; then
    # Reset cache so per-invocation config changes (used by self-test) are seen
    unset _NL_LOCAL_CONFIG_LOADED _NL_CONFIG_CACHE 2>/dev/null || true
    # shellcheck disable=SC1090
    source "$helper" 2>/dev/null || helper=""
  fi

  # Step 2: resolve effective mode + matchers
  # Hardcoded defaults (used if helper is absent or fails)
  local default_mode="review-before-deploy"
  local default_matchers='git push
gh pr merge
gh repo create
supabase db push
vercel deploy
npm publish'

  # Per-project override: $PWD/.claude/automation-mode.json wins, then
  # $PWD/.claude/automation-mode.config.json, then user-global via helper.
  local proj_override=""
  if [ -f "$PWD/.claude/automation-mode.json" ]; then
    proj_override="$PWD/.claude/automation-mode.json"
  elif [ -f "$PWD/.claude/automation-mode.config.json" ]; then
    proj_override="$PWD/.claude/automation-mode.config.json"
  fi

  local mode=""
  local matchers=""

  if [ -n "$proj_override" ] && command -v jq >/dev/null 2>&1; then
    mode="$(jq -r '.mode // empty' "$proj_override" 2>/dev/null | tr -d '\r')"
    matchers="$(jq -r '.deploy_matchers[]? // empty' "$proj_override" 2>/dev/null | tr -d '\r')"
  fi

  if [ -z "$mode" ] && command -v nl_automation_mode >/dev/null 2>&1; then
    mode="$(nl_automation_mode 2>/dev/null)"
  fi
  if [ -z "$matchers" ] && command -v nl_automation_matchers >/dev/null 2>&1; then
    matchers="$(nl_automation_matchers 2>/dev/null)"
  fi

  [ -z "$mode" ] && mode="$default_mode"
  [ -z "$matchers" ] && matchers="$default_matchers"

  # Step 3: non-review-before-deploy modes pass through
  if [ "$mode" != "review-before-deploy" ]; then
    return 0
  fi

  # Step 4: extract the Bash command from tool input (env var OR stdin)
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [ -z "$input" ] && [ ! -t 0 ]; then
    input="$(cat 2>/dev/null || echo "")"
  fi

  if [ -z "$input" ]; then
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi

  # Support nested (.tool_input.command) and flat (.command) shapes
  local cmd
  cmd="$(echo "$input" | jq -r '.tool_input.command // .command // ""' 2>/dev/null)"
  if [ -z "$cmd" ]; then
    return 0
  fi

  # Step 5: check each matcher against the command
  # Match semantics: matcher M is a substring that must appear at a token
  # boundary. Concretely, we pass if any of these hold:
  #   - cmd starts with "M" (optionally followed by whitespace), OR
  #   - cmd contains " M " (whole phrase in middle), OR
  #   - cmd contains " M" at end of line
  # This prevents "git push" from matching filenames like "my-git push-foo"
  # while still catching "git push origin main" and "cd /tmp && git push".
  local matched=""
  local matcher
  while IFS= read -r matcher; do
    [ -z "$matcher" ] && continue

    if [[ "$cmd" == "$matcher" || "$cmd" == "$matcher "* ]]; then
      matched="$matcher"
      break
    fi

    if [[ "$cmd" == *" $matcher "* || "$cmd" == *" $matcher" ]]; then
      matched="$matcher"
      break
    fi
  done <<< "$matchers"

  if [ -z "$matched" ]; then
    return 0
  fi

  # Step 6: matched — emit block message, return 1
  cat >&2 <<EOF
================================================================
AUTOMATION MODE — REVIEW REQUIRED
================================================================
Current mode: review-before-deploy
Command matched deploy-class matcher: $matched
Full command: $cmd

This command was blocked because your automation mode requires
a human-in-the-loop for deploy-class operations.

To approve: ask the user to approve the specific action.
To switch mode: /automation-mode full-auto  (or edit ~/.claude/local/automation-mode.config.json)
To override per-project: create <project>/.claude/automation-mode.json
================================================================
EOF
  return 1
}

# ============================================================
# Self-test — drives _run_gate with synthesized inputs
# ============================================================
_self_test() {
  local tmp_home
  tmp_home="$(mktemp -d 2>/dev/null || mktemp -d -t 'nl-automation-gate-test')"
  if [ -z "$tmp_home" ] || [ ! -d "$tmp_home" ]; then
    echo "self-test: FAIL — could not create tmp dir" >&2
    return 1
  fi

  # Snapshot + isolate HOME so the helper only sees our fake configs
  local real_home="$HOME"
  export HOME="$tmp_home"
  mkdir -p "$tmp_home/.claude/local"

  # Isolate PWD so per-project override files don't leak in from the repo
  local real_pwd="$PWD"
  local tmp_pwd
  tmp_pwd="$(mktemp -d 2>/dev/null || mktemp -d -t 'nl-automation-gate-pwd')"
  cd "$tmp_pwd" || { echo "self-test: FAIL — cd tmp_pwd" >&2; return 1; }

  local failed=0
  local fail_msg=""

  _fail() {
    failed=1
    fail_msg="$1"
  }

  # Helper: run the gate with a synthesized command JSON; return gate's rc
  _run_with_cmd() {
    local cmd="$1"
    # Build JSON safely via jq to handle quoting
    local json
    json="$(jq -nc --arg c "$cmd" '{tool_input: {command: $c}}' 2>/dev/null)"
    CLAUDE_TOOL_INPUT="$json" _run_gate >/dev/null 2>&1
    return $?
  }

  # --- Scenario 1: review-before-deploy mode with default matchers ---
  # (No config file written; helper returns its hardcoded defaults, but
  # the defaults in read-local-config.sh do NOT include "gh repo create"
  # or "npm publish". We write our own config to match the task spec.)
  cat > "$tmp_home/.claude/local/automation-mode.config.json" <<'JSON'
{
  "version": 1,
  "mode": "review-before-deploy",
  "deploy_matchers": [
    "git push",
    "gh pr merge",
    "gh repo create",
    "supabase db push",
    "vercel deploy",
    "npm publish"
  ]
}
JSON

  # Should BLOCK: git push at start
  _run_with_cmd "git push origin main"
  if [ $? -ne 1 ]; then
    _fail "review-mode: 'git push origin main' should BLOCK (exit 1)"
  fi

  # Should BLOCK: gh repo create --public foo
  _run_with_cmd "gh repo create --public foo"
  if [ $? -ne 1 ]; then
    _fail "review-mode: 'gh repo create --public foo' should BLOCK"
  fi

  # Should BLOCK: command chain with " git push" in middle
  _run_with_cmd "cd /tmp && git push origin main"
  if [ $? -ne 1 ]; then
    _fail "review-mode: 'cd /tmp && git push origin main' should BLOCK"
  fi

  # Should BLOCK: matcher at very end of command
  _run_with_cmd "cd /tmp && git push"
  if [ $? -ne 1 ]; then
    _fail "review-mode: 'cd /tmp && git push' (end-of-line) should BLOCK"
  fi

  # Should BLOCK: supabase db push (multi-word matcher)
  _run_with_cmd "supabase db push --linked"
  if [ $? -ne 1 ]; then
    _fail "review-mode: 'supabase db push --linked' should BLOCK"
  fi

  # Should PASS: benign ls
  _run_with_cmd "ls -la"
  if [ $? -ne 0 ]; then
    _fail "review-mode: 'ls -la' should PASS (exit 0)"
  fi

  # Should PASS: git status (git, but not push)
  _run_with_cmd "git status"
  if [ $? -ne 0 ]; then
    _fail "review-mode: 'git status' should PASS"
  fi

  # Should PASS: git push-like text NOT at token boundary
  _run_with_cmd "echo my-git push-helper.sh"
  if [ $? -ne 0 ]; then
    _fail "review-mode: 'echo my-git push-helper.sh' should PASS (no token-boundary match)"
  fi

  # Should PASS: empty command (harness quirk) passes through
  _run_with_cmd ""
  if [ $? -ne 0 ]; then
    _fail "review-mode: empty command should PASS"
  fi

  # --- Scenario 2: full-auto mode — every command passes ---
  cat > "$tmp_home/.claude/local/automation-mode.config.json" <<'JSON'
{
  "version": 1,
  "mode": "full-auto",
  "deploy_matchers": [
    "git push",
    "vercel deploy"
  ]
}
JSON

  _run_with_cmd "git push origin main"
  if [ $? -ne 0 ]; then
    _fail "full-auto: 'git push origin main' should PASS"
  fi

  _run_with_cmd "vercel deploy --prod"
  if [ $? -ne 0 ]; then
    _fail "full-auto: 'vercel deploy --prod' should PASS"
  fi

  _run_with_cmd "ls -la"
  if [ $? -ne 0 ]; then
    _fail "full-auto: 'ls -la' should PASS"
  fi

  # --- Scenario 3: malformed input passes through ---
  cat > "$tmp_home/.claude/local/automation-mode.config.json" <<'JSON'
{
  "version": 1,
  "mode": "review-before-deploy",
  "deploy_matchers": ["git push"]
}
JSON

  # Missing CLAUDE_TOOL_INPUT => pass through
  CLAUDE_TOOL_INPUT="" _run_gate </dev/null >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    _fail "malformed: missing CLAUDE_TOOL_INPUT should PASS"
  fi

  # Malformed JSON => pass through
  CLAUDE_TOOL_INPUT="{not valid json" _run_gate </dev/null >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    _fail "malformed: bad JSON should PASS"
  fi

  # --- Scenario 4: per-project override ---
  # Write a project-level config that enables full-auto, even though
  # user-global is review-before-deploy. Verify the project override wins.
  mkdir -p "$tmp_pwd/.claude"
  cat > "$tmp_pwd/.claude/automation-mode.json" <<'JSON'
{
  "version": 1,
  "mode": "full-auto",
  "deploy_matchers": ["git push"]
}
JSON

  _run_with_cmd "git push origin main"
  if [ $? -ne 0 ]; then
    _fail "per-project override: 'git push' should PASS (project is full-auto)"
  fi

  # Cleanup per-project override; verify user-global re-applies
  rm -rf "$tmp_pwd/.claude"

  _run_with_cmd "git push origin main"
  if [ $? -ne 1 ]; then
    _fail "after removing per-project override: 'git push' should BLOCK again"
  fi

  # --- Restore state ---
  export HOME="$real_home"
  cd "$real_pwd" || true
  rm -rf "$tmp_home" "$tmp_pwd" 2>/dev/null

  if [ "$failed" = "1" ]; then
    echo "self-test: FAIL — $fail_msg" >&2
    return 1
  fi

  echo "self-test: OK"
  return 0
}

# ============================================================
# Dispatcher
# ============================================================
case "${1:-}" in
  --self-test|self-test)
    _self_test
    exit $?
    ;;
  ""|*)
    _run_gate
    exit $?
    ;;
esac
