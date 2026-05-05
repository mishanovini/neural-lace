#!/bin/bash
# settings-divergence-detector.sh
#
# SessionStart hook that compares ~/.claude/settings.json against the
# committed template at
# $HOME/claude-projects/neural-lace/adapters/claude-code/settings.json.template
# and surfaces unexpected divergences as a warning.
#
# Background. ~/.claude/settings.json is gitignored (per-machine live
# config the running session reads) and the template is committed
# (source-of-truth for install.sh and a fresh install). Convention is to
# edit BOTH in the same commit. When that convention fails, the harness's
# claimed enforcement may not match its actual enforcement on this
# machine — hooks declared in template but missing in live silently
# don't fire; hooks added to live but never landed in the template won't
# survive a fresh install.
#
# The detector does NOT fix divergence — it makes it visible at every
# session start. The reconciliation work (per-hook research to determine
# canonical state) is deferred to HARNESS-GAP-14 / Phase 1d-E. See
# discovery 2026-05-04-template-vs-live-divergence-across-other-hooks.md
# for the split-decision rationale.
#
# Cross-references:
# - rules/harness-maintenance.md (the "edit both in same commit" rule)
# - docs/backlog.md HARNESS-GAP-14 (deferred reconciliation pass)
# - docs/discoveries/2026-05-04-template-vs-live-divergence-across-other-hooks.md
#
# Self-test: invoke with --self-test to exercise four scenarios.

set -u

# Allow override for self-test
TEMPLATE_PATH="${TEMPLATE_PATH_OVERRIDE:-$HOME/claude-projects/neural-lace/adapters/claude-code/settings.json.template}"
LIVE_PATH="${LIVE_PATH_OVERRIDE:-$HOME/.claude/settings.json}"

# -------- Utility: count hook entries by event type --------
# Returns the integer length of .hooks.<event> in the JSON file, or 0
# if jq fails or the path is missing.
count_hook_entries() {
  local file="$1" event="$2"
  jq -r ".hooks.${event} // [] | length" "$file" 2>/dev/null \
    | head -n 1 \
    | grep -E '^[0-9]+$' \
    || echo 0
}

# -------- Core detection logic --------
# Args (for testability):
#   $1 = path to template
#   $2 = path to live settings
# Writes a multi-line warning if they differ; silent if identical or if
# either file is missing.
detect_divergence() {
  local template="$1"
  local live="$2"

  # Silent if either file is missing. Common when running on a machine
  # without the neural-lace repo cloned.
  if [ ! -f "$template" ] || [ ! -f "$live" ]; then
    return 0
  fi

  # Quick byte-identical check first. The fast happy path.
  if cmp -s "$template" "$live"; then
    return 0
  fi

  # Files differ. If jq isn't available we still want to surface SOME
  # signal; just less useful breakdown.
  if ! command -v jq >/dev/null 2>&1; then
    echo "[settings-divergence] template and live ~/.claude/settings.json differ. jq unavailable for breakdown."
    echo "[settings-divergence] Inspect manually: diff -u $template $live"
    echo "[settings-divergence] See HARNESS-GAP-14 in docs/backlog.md for the deferred reconciliation pass."
    return 0
  fi

  local events="PreToolUse PostToolUse Stop SessionStart UserPromptSubmit TaskCreated TaskCompleted SubagentStop SubagentStart"
  local divergent_lines=""
  local event t_count l_count

  for event in $events; do
    t_count=$(count_hook_entries "$template" "$event")
    l_count=$(count_hook_entries "$live" "$event")
    if [ "$t_count" != "$l_count" ]; then
      divergent_lines="${divergent_lines}  - ${event}: template=${t_count}, live=${l_count}"$'\n'
    fi
  done

  echo "[settings-divergence] template and live ~/.claude/settings.json differ — at least one hook is wired in only one of the two files."
  if [ -n "$divergent_lines" ]; then
    echo "[settings-divergence] Hook entry-count differs for these events:"
    printf '%s' "$divergent_lines"
  else
    echo "[settings-divergence] Hook entry counts match; divergence is in matcher/command content (not entry count)."
  fi
  echo "[settings-divergence] HARNESS-GAP-14 (docs/backlog.md) tracks the per-hook reconciliation methodology. To inspect now: diff -u <(jq -S . $template) <(jq -S . $live)"
}

# -------- Self-test --------
run_self_test() {
  local tmp failures=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t settdiv)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  # Three settings files for fixtures
  cat > "$tmp/template.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo a"}]}],
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "echo b"}]}]
  }
}
EOF
  cat > "$tmp/live-identical.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo a"}]}],
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "echo b"}]}]
  }
}
EOF
  cat > "$tmp/live-divergent.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo a"}]}],
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "echo b"}]}, {"matcher": "extra", "hooks": [{"type": "command", "command": "echo c"}]}]
  }
}
EOF

  # ---- Scenario 1: template missing ----
  local out
  out=$(detect_divergence "$tmp/no-such-template.json" "$tmp/live-identical.json" 2>&1)
  if [ -z "$out" ]; then
    echo "PASS: [template-missing] silent as expected"
  else
    echo "FAIL: [template-missing] expected silence, got: $out" >&2
    failures=$((failures + 1))
  fi

  # ---- Scenario 2: live missing ----
  out=$(detect_divergence "$tmp/template.json" "$tmp/no-such-live.json" 2>&1)
  if [ -z "$out" ]; then
    echo "PASS: [live-missing] silent as expected"
  else
    echo "FAIL: [live-missing] expected silence, got: $out" >&2
    failures=$((failures + 1))
  fi

  # ---- Scenario 3: byte-identical → silent ----
  out=$(detect_divergence "$tmp/template.json" "$tmp/live-identical.json" 2>&1)
  if [ -z "$out" ]; then
    echo "PASS: [byte-identical] silent as expected"
  else
    echo "FAIL: [byte-identical] expected silence, got: $out" >&2
    failures=$((failures + 1))
  fi

  # ---- Scenario 4: divergent (different Stop count) → warning emitted ----
  out=$(detect_divergence "$tmp/template.json" "$tmp/live-divergent.json" 2>&1)
  if echo "$out" | grep -q "settings-divergence" \
     && echo "$out" | grep -q "Stop"; then
    echo "PASS: [divergent] warning emitted naming Stop"
  else
    echo "FAIL: [divergent] expected warning naming Stop, got:" >&2
    echo "$out" | sed 's/^/    /' >&2
    failures=$((failures + 1))
  fi

  if [ "$failures" -gt 0 ]; then
    echo ""
    echo "$failures self-test scenario(s) FAILED" >&2
    return 1
  fi
  echo ""
  echo "All 4 self-test scenarios PASSED"
  return 0
}

# -------- Main --------
if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

# Discard SessionStart's JSON payload from stdin (unused).
cat > /dev/null 2>&1 || true

detect_divergence "$TEMPLATE_PATH" "$LIVE_PATH"
exit 0
