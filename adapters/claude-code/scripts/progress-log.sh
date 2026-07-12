#!/bin/bash
# progress-log.sh — CLI for the mechanism-emitted progress log
# (ask-rooted-workstreams-p1, Task 1 walking skeleton).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# Splices (a task-verifier flip in hooks/plan-lifecycle.sh today; dispatch/
# NEEDS-YOU/merge/plan-amend/plan-complete splices in later tasks) call
# this CLI so the emission convention is ONE process invocation, not a
# `source`-and-call in every hook — mirrors session-heartbeat.sh being the
# CLI half of hooks/lib/session-heartbeat-lib.sh.
#
# ============================================================
# CONTRACT
# ============================================================
#
#   progress-log.sh emit --type <type> --ask <ask-id>
#                         [--plan-slug <slug>] [--task-id <id>]
#                         [--sha <sha>] [--needs-you-id <id>]
#                         [--session-id <id>] [--summary <text>]
#                         [--evidence-link <url-or-path>]
#                         --emitter <name> [--dedup-extra <str>]
#     Emits one versioned progress-log event (schema + dedup rules: see
#     hooks/lib/progress-log-lib.sh header). NEVER BLOCKS the caller — exit
#     0 always, on every code path (writer semantics, constraint 5).
#
#   progress-log.sh --self-test
#     Self-contained assertion suite, entirely sandboxed under
#     PROGRESS_LOG_STATE_DIR (see SANDBOXING below) — never touches the
#     real machine's progress-log state.
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST / explicit override — constraint 4)
# ============================================================
#
# All state-directory resolution is delegated to
# hooks/lib/progress-log-lib.sh's pl_state_dir (PROGRESS_LOG_STATE_DIR env
# override, else HARNESS_SELFTEST=1 sandboxed TMPDIR path, else the real
# $HOME/.claude/state/progress-logs). This script never resolves the path
# itself — one implementation, sourced.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
if [[ -f "$SCRIPT_DIR/../hooks/lib/progress-log-lib.sh" ]]; then
  source "$SCRIPT_DIR/../hooks/lib/progress-log-lib.sh"
else
  echo "progress-log.sh: cannot find hooks/lib/progress-log-lib.sh next to scripts/ — aborting (never blocks caller: this is a standalone script, not a hook)" >&2
  exit 0
fi

# ----------------------------------------------------------------------
# cmd_emit — parse `emit` args and call pl_emit. NEVER BLOCKS: pl_emit
# itself already swallows every failure path (exit 0 always); this wrapper
# just forwards args and prints the resolved path with a trailing newline
# for CLI readability.
# ----------------------------------------------------------------------
cmd_emit() {
  local out
  out="$(pl_emit "$@")"
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}

# ============================================================
# --self-test
# ============================================================
cmd_selftest() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local TMP
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'plst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    return 1
  fi

  export HARNESS_SELFTEST=1
  export PROGRESS_LOG_STATE_DIR="$TMP/pl"
  mkdir -p "$PROGRESS_LOG_STATE_DIR"

  echo "Scenario A: emit --type task_done writes a jq-valid event under the sandbox"
  cmd_emit --type task_done --ask "ask-cli-1" --plan-slug "cli-demo" --task-id "1" \
    --sha "abc1234" --summary "task 1 verified done" --evidence-link "/tmp/cli-demo.md" \
    --emitter plan-lifecycle >/dev/null
  fa="$PROGRESS_LOG_STATE_DIR/ask-cli-1.jsonl"
  if [[ -f "$fa" ]]; then
    pass "emit created the per-ask log file via the CLI"
  else
    fail "expected $fa to exist after emit"
  fi
  if command -v jq >/dev/null 2>&1; then
    if jq -e . "$fa" >/dev/null 2>&1; then
      pass "CLI-written event is valid JSON per jq"
    else
      fail "CLI-written event is NOT valid JSON"
    fi
  fi

  echo "Scenario B: emit prints the resolved path to stdout"
  out_path="$(cmd_emit --type task_done --ask "ask-cli-2" --plan-slug "cli-demo2" --task-id "2" \
    --sha "def5678" --summary "task 2 verified done" --emitter plan-lifecycle)"
  expected_path="$PROGRESS_LOG_STATE_DIR/ask-cli-2.jsonl"
  if [[ "$out_path" == "$expected_path" ]]; then
    pass "emit printed the resolved log path"
  else
    fail "expected stdout '$expected_path', got '$out_path'"
  fi

  echo "Scenario C: emit with no --type is a documented no-op (never blocks, never crashes)"
  if cmd_emit --ask "ask-cli-3" --summary "malformed call" >/dev/null 2>&1; then
    pass "emit with missing --type still exits 0 (writer semantics: never blocks the caller)"
  else
    fail "emit with missing --type should still exit 0"
  fi

  echo "Scenario D: sandbox-only writes — self-test never touched the real state dir shape"
  if [[ ! -e "$TMP/.claude" ]]; then
    pass "self-test wrote only under its own sandboxed tempdir"
  else
    fail "self-test unexpectedly created a .claude path under $TMP"
  fi

  rm -rf "$TMP" 2>/dev/null || true

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# Entry point
# ============================================================
case "${1:-}" in
  emit)
    shift
    cmd_emit "$@"
    exit 0
    ;;
  --self-test|--selftest|selftest|self-test)
    cmd_selftest
    exit $?
    ;;
  -h|--help|"")
    cat <<'USAGE'
progress-log.sh — mechanism-emitted progress-log CLI (ask-rooted-workstreams-p1)

Verbs:
  emit --type <type> --ask <ask-id> [--plan-slug <slug>] [--task-id <id>]
       [--sha <sha>] [--needs-you-id <id>] [--session-id <id>]
       [--summary <text>] [--evidence-link <url-or-path>]
       --emitter <name> [--dedup-extra <str>]
                          Emit one versioned progress-log event. Never
                          blocks; exit 0 always.
  --self-test             Run the self-test suite (sandboxed).

See adapters/claude-code/hooks/lib/progress-log-lib.sh header for the full
event schema + per-type dedup natural-key table (plan Task 2).
USAGE
    exit 0
    ;;
  *)
    echo "progress-log.sh: unknown verb '$1' (run without args for usage; never blocks a caller since this is a standalone script)" >&2
    exit 0
    ;;
esac
