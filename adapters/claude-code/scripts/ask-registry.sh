#!/bin/bash
# ask-registry.sh — ask registry CLI (ask-rooted-workstreams-p1).
#
# ============================================================
# WHY THIS EXISTS / STATUS
# ============================================================
#
# THIS IS A TASK 1 WALKING-SKELETON STUB, not the finished registry. Task 1
# needs a way to hand-register one ask entry so the skeleton's single event
# (a task-verifier flip -> task_done) resolves to a real `ask_id` end to
# end. Task 8 REPLACES/EXTENDS this file with the full contract:
# attach-session / link-plan / set-status / merge / override-project, the
# heuristic+haiku summarizer, the best-effort in-repo mirror
# (docs/asks/ask-registry.jsonl via nl_main_checkout_root), and its own
# --self-test battery (concurrency, from-worktree fixture, summarizer
# quality). Only `register` (and a read-only `list` convenience verb for
# this task's own Prove-it walkthrough) exist here.
#
# ============================================================
# CONTRACT (Task 1 subset)
# ============================================================
#
#   ask-registry.sh register --ask-id <id> --summary <text>
#                             [--repo <path>] [--project <name>]
#     Appends one registry record (JSONL, append-only) to
#     ask_state_dir()/ask-registry.jsonl and best-effort emits an
#     `ask_registered` progress-log event via scripts/progress-log.sh.
#     NEVER BLOCKS: exit 0 always (writer semantics, constraint 5).
#     --ask-id is REQUIRED here (Task 1 hand-registration) — Task 8 adds
#     automatic id generation + the first-prompt capture splice.
#
#   ask-registry.sh list
#     Read-only: prints the registry file's raw JSONL lines (or nothing if
#     absent). Convenience verb for this task's own manual verification;
#     Task 11's server-side reader is the real consumer going forward.
#
#   ask-registry.sh --self-test
#     Self-contained assertion suite, sandboxed under ASK_REGISTRY_STATE_DIR
#     (see SANDBOXING below).
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST / explicit override — constraint 4)
# ============================================================
#
# Resolution order for the ask-registry state directory (the FILE itself is
# always "<dir>/ask-registry.jsonl", matching the plan's literal path
# `~/.claude/state/ask-registry.jsonl`):
#   1. ASK_REGISTRY_STATE_DIR env var, if set.
#   2. HARNESS_SELFTEST=1 and ASK_REGISTRY_STATE_DIR unset -> a sandboxed
#      dir under ${TMPDIR:-/tmp}/ask-registry-selftest/<pid>/.
#   3. Default: $HOME/.claude/state/ — the real, production, cross-project
#      state dir (matches heartbeats/needs-you/progress-log convention).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
if [[ -f "$SCRIPT_DIR/../hooks/lib/progress-log-lib.sh" ]]; then
  source "$SCRIPT_DIR/../hooks/lib/progress-log-lib.sh"
fi

# ----------------------------------------------------------------------
# ar_state_dir — resolve the ask-registry state directory per the order
# above. Always prints a non-empty path; never fails.
# ----------------------------------------------------------------------
ar_state_dir() {
  if [[ -n "${ASK_REGISTRY_STATE_DIR:-}" ]]; then
    printf '%s' "$ASK_REGISTRY_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/ask-registry-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state' "${HOME:-$PWD}"
  return 0
}

ar_registry_file() { printf '%s/ask-registry.jsonl' "$(ar_state_dir)"; }

# Same escaper as progress-log-lib.sh's _pl_json_escape (duplicated locally
# per this repo's single-file-portability convention — see
# session-heartbeat-lib.sh's header for the rationale).
_ar_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  local nl=$'\n' cr=$'\r' tab=$'\t'
  s="${s//$nl/\\n}"
  s="${s//$cr/\\r}"
  s="${s//$tab/\\t}"
  s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# cmd_register — parse --ask-id/--summary/--repo/--project, append a
# registry record, best-effort emit `ask_registered`. NEVER BLOCKS.
# ----------------------------------------------------------------------
cmd_register() {
  local ask_id="" summary="" repo="" project=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --summary) summary="${2:-}"; shift 2 ;;
      --repo) repo="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$ask_id" ]]; then
    echo "ask-registry.sh register: --ask-id is required (Task 1 hand-registration stub; never blocks caller)" >&2
    return 0
  fi

  [[ -n "$repo" ]] || repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$project" ]] || project="$(basename "${repo:-unknown}")"

  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')"

  local f dir
  f="$(ar_registry_file)"
  dir="$(dirname "$f")"
  mkdir -p "$dir" 2>/dev/null || { return 0; }

  local ask_esc summary_esc repo_esc project_esc
  ask_esc="$(_ar_json_escape "$ask_id")"
  summary_esc="$(_ar_json_escape "$summary")"
  repo_esc="$(_ar_json_escape "$repo")"
  project_esc="$(_ar_json_escape "$project")"

  local json
  json="$(printf '{"ask_id":"%s","summary":"%s","repo":"%s","project":"%s","status":"active","ts":"%s"}' \
    "$ask_esc" "$summary_esc" "$repo_esc" "$project_esc" "$ts")"

  printf '%s\n' "$json" >> "$f" 2>/dev/null || { return 0; }

  # Best-effort ask_registered emission (Task 1: progress-log-lib.sh may be
  # unavailable in a stripped-down invocation context; never fail register
  # over a missing sibling lib).
  if command -v pl_emit >/dev/null 2>&1; then
    pl_emit --type ask_registered --ask "$ask_id" --summary "$summary" \
      --emitter ask-registry >/dev/null 2>&1 || true
  fi

  printf '%s' "$f"
  return 0
}

cmd_list() {
  local f
  f="$(ar_registry_file)"
  [[ -f "$f" ]] && cat "$f"
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
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'arst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    return 1
  fi

  export HARNESS_SELFTEST=1
  export ASK_REGISTRY_STATE_DIR="$TMP/ar"
  export PROGRESS_LOG_STATE_DIR="$TMP/pl"
  mkdir -p "$ASK_REGISTRY_STATE_DIR" "$PROGRESS_LOG_STATE_DIR"

  echo "Scenario A: register writes a jq-valid registry record"
  cmd_register --ask-id "ask-selftest-1" --summary "skeleton test" --project "demo" >/dev/null
  local f="$ASK_REGISTRY_STATE_DIR/ask-registry.jsonl"
  if [[ -f "$f" ]]; then
    pass "register created ask-registry.jsonl under the sandbox"
  else
    fail "expected $f to exist after register"
  fi
  if command -v jq >/dev/null 2>&1; then
    if jq -e . "$f" >/dev/null 2>&1; then
      pass "written record is valid JSON (jq)"
    else
      fail "written record is NOT valid JSON"
    fi
    local ask_v summary_v status_v
    ask_v="$(jq -r '.ask_id' "$f" 2>/dev/null | tr -d '\r')"
    summary_v="$(jq -r '.summary' "$f" 2>/dev/null | tr -d '\r')"
    status_v="$(jq -r '.status' "$f" 2>/dev/null | tr -d '\r')"
    if [[ "$ask_v" == "ask-selftest-1" && "$summary_v" == "skeleton test" && "$status_v" == "active" ]]; then
      pass "fields round-trip (ask_id, summary, status=active)"
    else
      fail "field mismatch: ask_id=$ask_v summary=$summary_v status=$status_v"
    fi
  fi

  echo "Scenario B: register with no --ask-id is a documented no-op (never blocks)"
  if cmd_register --summary "missing id" >/dev/null 2>&1; then
    pass "register with missing --ask-id still returns success (writer semantics)"
  else
    fail "register with missing --ask-id should still exit 0"
  fi

  echo "Scenario C: register best-effort emits an ask_registered progress-log event"
  local plf="$PROGRESS_LOG_STATE_DIR/ask-selftest-1.jsonl"
  if [[ -f "$plf" ]] && grep -q '"type":"ask_registered"' "$plf"; then
    pass "register emitted an ask_registered progress-log event"
  else
    fail "expected an ask_registered event at $plf"
  fi

  echo "Scenario D: list prints the raw registry contents"
  local out
  out="$(cmd_list)"
  if printf '%s' "$out" | grep -q "ask-selftest-1"; then
    pass "list prints the registered entry"
  else
    fail "list did not print the registered entry"
  fi

  echo "Scenario E: sandbox-only writes"
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
  register)
    shift
    cmd_register "$@"
    exit 0
    ;;
  list)
    shift
    cmd_list "$@"
    exit 0
    ;;
  --self-test|--selftest|selftest|self-test)
    cmd_selftest
    exit $?
    ;;
  -h|--help|"")
    cat <<'USAGE'
ask-registry.sh — ask registry CLI (TASK 1 WALKING-SKELETON STUB — Task 8
replaces this with the full attach-session/link-plan/set-status/merge
contract + summarizer + in-repo mirror).

Verbs:
  register --ask-id <id> --summary <text> [--repo <path>] [--project <name>]
                          Append one registry record + best-effort emit
                          ask_registered. Never blocks; exit 0 always.
  list                    Print the raw registry JSONL (read-only).
  --self-test             Run the self-test suite (sandboxed).
USAGE
    exit 0
    ;;
  *)
    echo "ask-registry.sh: unknown verb '$1' (run without args for usage; never blocks a caller since this is a standalone script)" >&2
    exit 0
    ;;
esac
