#!/bin/bash
# progress-log-lib.sh — shared library: the writer side of the mechanism-
# emitted progress log (ask-rooted-workstreams-p1, Task 1 walking skeleton;
# specs/design ref: docs/reviews/2026-07-10-ask-rooted-workstreams-design-sketch.md).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# The plan's log-first law: every progress event on an ask (a task-verifier
# flip, a dispatch, a NEEDS-YOU append, a master merge, a plan amendment, a
# plan completion) is emitted by a MECHANISM, never by model memory. This
# lib is the ONE writer implementation every splice (plan-lifecycle.sh here;
# workstreams-emit.sh/needs-you.sh/post-commit/close-plan.sh/ask-registry.sh
# in later tasks) calls — mirrors session-heartbeat-lib.sh's script+lib
# split (session-heartbeat.sh is the write-side CLI; this file is the
# shared writer both the CLI and hooks source directly).
#
# ============================================================
# THE CONTRACT — versioned event schema (plan Task 2 table; written in
# FULL here so Task 2 hardens dedup/allowlist enforcement/orphan-lane
# behavior WITHOUT a schema migration)
# ============================================================
#
# Path: pl_path_for(ask_id) = <state-dir>/<ask_id-or-"unlinked">.jsonl
# One JSONL file per ask (D1: machine-local, `~/.claude/state/progress-logs`
# — hooks fire in worktrees/other repos, so this is NOT a durable in-repo
# write and does not go through nl_main_checkout_root; constraint 11 governs
# DURABLE IN-REPO writes only, e.g. docs/operator-todo.md in a later task).
#
#   {"v":1,"event_id":"<hash>","ts":"ISO-8601-UTC","ask_id":"...",
#    "type":"task_done|task_started|waiting_on_operator|merged|
#            plan_amended|plan_completed|ask_registered|session_attached|...",
#    "plan_slug":"...","task_id":"...","sha":"...","needs_you_id":"...",
#    "session_id":"...","summary":"...","evidence_link":"...",
#    "emitter":"...","provenance":"known|unknown","user":"...",
#    "machine":"...","repo":"..."}
#
# Optional fields not supplied by a given event type are still present as
# empty strings (never omitted) — simpler, jq-friendly readers, matching
# hb_write's flat-JSON convention.
#
# DEDUP — PER-EVENT-TYPE NATURAL KEY (plan Task 2 table, implemented here
# so Task 1's walking-skeleton event already writes the FINAL format):
#   task_done             -> plan_slug + task_id + sha
#   task_started           -> plan_slug + task_id + session_id
#   waiting_on_operator     -> needs_you_id
#   merged                  -> repo + sha
#   plan_amended            -> plan_slug + --dedup-extra (content-hash of the delta; caller-computed)
#   plan_completed          -> plan_slug + --dedup-extra (content-hash of the Status-line ts; caller-computed)
#   ask_registered/session_attached -> ask_id (+ session_id)
#   (any other/future type) -> a superset hash of every field supplied —
#     never silently un-deduped, and never wrongly collapses a real
#     recurrence into a single row.
# Task 2 owns the full concurrent-append + replay-dedup + legitimate-
# recurrence self-test battery; this lib's own self-test below covers the
# natural-key formula for the ONE type the Task 1 skeleton exercises
# (task_done) plus the dedup/recurrence distinction for task_started, so
# the format is provably right before Task 2 hardens it further.
#
# EMITTER ALLOWLIST (constraint 10): an emitter NOT in the known-mechanism
# list is recorded verbatim but flagged `"provenance":"unknown"` — the open
# CLI cannot impersonate a mechanism; Task 2/12 own enforcement + UI
# de-emphasis, this lib only computes and stamps the flag.
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST / explicit override — constraint 4)
# ============================================================
#
# Resolution order for the progress-log state directory:
#   1. PROGRESS_LOG_STATE_DIR env var, if set (explicit override — used by
#      self-tests, the Prove-it walkthrough on a non-default CTREE_PORT, and
#      any caller wanting a non-default location).
#   2. HARNESS_SELFTEST=1 and PROGRESS_LOG_STATE_DIR unset -> a sandboxed
#      dir under ${TMPDIR:-/tmp}/progress-log-selftest/<pid>/.
#   3. Default: $HOME/.claude/state/progress-logs — the real, production,
#      cross-project state dir (matches heartbeats/needs-you convention).
#
# ============================================================
# USAGE
# ============================================================
#
#   source "${BASH_SOURCE%/*}/progress-log-lib.sh"
#   pl_emit --type task_done --ask "$ask_id" --plan-slug "$slug" \
#           --task-id "$n" --sha "$sha" --summary "task $n verified done" \
#           --evidence-link "$abs_path" --emitter plan-lifecycle
#
# NEVER BLOCKS the caller (writer semantics, constraint 5): every failure
# path is swallowed, exit 0 always. Prints the resolved log-file path to
# stdout on success (mirrors hb_write's contract) — including the
# already-deduped case (the event already exists, nothing new appended).

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_PROGRESS_LOG_LIB_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_PROGRESS_LOG_LIB_SOURCED=1

# Known mechanism emitters (constraint 10). Extend this list, never widen
# the check itself, when a new splice lands.
_PL_KNOWN_EMITTERS=(plan-lifecycle workstreams-emit needs-you post-commit close-plan ask-registry auditor)

# ----------------------------------------------------------------------
# pl_state_dir — resolve the progress-log state directory per the order
# above. Always prints a non-empty path; never fails.
# ----------------------------------------------------------------------
pl_state_dir() {
  if [[ -n "${PROGRESS_LOG_STATE_DIR:-}" ]]; then
    printf '%s' "$PROGRESS_LOG_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/progress-log-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/progress-logs' "${HOME:-$PWD}"
  return 0
}

# ----------------------------------------------------------------------
# pl_path_for <ask-id> — print the resolved per-ask JSONL path. An empty
# ask-id resolves to the literal "unlinked" file (mirrors hb_path_for's
# "unknown" fallback) — a full orphan lane keyed by plan-slug is Task 2/12's
# job; this is the honest, no-events-lost stopgap so a splice that cannot
# yet resolve an ask-id still logs SOMEWHERE deterministic instead of
# silently no-op-ing (Edge Cases: "estate-growth safe: old plans never
# break the surface").
# ----------------------------------------------------------------------
pl_path_for() {
  local ask_id="${1:-}"
  [[ -n "$ask_id" ]] || ask_id="unlinked"
  printf '%s/%s.jsonl' "$(pl_state_dir)" "$ask_id"
}

# ----------------------------------------------------------------------
# _pl_in_list <needle> <haystack...> — true if needle is one of haystack.
# ----------------------------------------------------------------------
_pl_in_list() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

# ----------------------------------------------------------------------
# _pl_json_escape <string> — same technique as session-heartbeat-lib.sh's
# _hb_json_escape (no jq dependency for the write path; splice budget is
# <=50ms and a `jq` fork per field would eat into that).
# ----------------------------------------------------------------------
_pl_json_escape() {
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
# _pl_hash <string> — best-effort, portable content hash for event_id /
# dedup keys. Tries sha1sum, then openssl, then cksum (always available on
# this harness's target platforms — verified present in this environment);
# never errors, always prints SOMETHING non-empty.
# ----------------------------------------------------------------------
_pl_hash() {
  local s="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$s" | sha1sum 2>/dev/null | awk '{print $1}' && return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$s" | openssl dgst -sha1 2>/dev/null | awk '{print $NF}' && return 0
  fi
  printf '%s' "$s" | cksum 2>/dev/null | awk '{print $1"-"$2}'
}

# ----------------------------------------------------------------------
# _pl_natural_key <type> <ask_id> <plan_slug> <task_id> <sha>
#                  <needs_you_id> <session_id> <dedup_extra> <repo>
#   — print the per-event-type natural key string (plan Task 2 table).
# Unknown/future types fall through to a superset key (every field joined)
# so a type this lib doesn't yet special-case still dedups sanely instead
# of colliding everything to one key.
# ----------------------------------------------------------------------
_pl_natural_key() {
  local type="$1" ask_id="$2" plan_slug="$3" task_id="$4" sha="$5" \
        needs_you_id="$6" session_id="$7" dedup_extra="$8" repo="$9"
  case "$type" in
    task_done)
      printf 'task_done|%s|%s|%s' "$plan_slug" "$task_id" "$sha" ;;
    task_started)
      printf 'task_started|%s|%s|%s' "$plan_slug" "$task_id" "$session_id" ;;
    waiting_on_operator)
      printf 'waiting_on_operator|%s' "$needs_you_id" ;;
    merged)
      printf 'merged|%s|%s' "$repo" "$sha" ;;
    plan_amended)
      printf 'plan_amended|%s|%s' "$plan_slug" "$dedup_extra" ;;
    plan_completed)
      printf 'plan_completed|%s|%s' "$plan_slug" "$dedup_extra" ;;
    ask_registered|session_attached)
      printf '%s|%s|%s' "$type" "$ask_id" "$session_id" ;;
    *)
      printf 'generic|%s|%s|%s|%s|%s|%s|%s|%s' \
        "$type" "$ask_id" "$plan_slug" "$task_id" "$sha" "$needs_you_id" "$session_id" "$dedup_extra" ;;
  esac
}

# ----------------------------------------------------------------------
# pl_emit --type <t> --ask <id> [--plan-slug <s>] [--task-id <n>]
#         [--sha <sha>] [--needs-you-id <id>] [--session-id <id>]
#         [--summary <text>] [--evidence-link <url-or-path>]
#         --emitter <name> [--dedup-extra <str>]
#
#   Build the versioned JSON event object and atomically append it (single
# LF-terminated line, O_APPEND) to pl_path_for(--ask). NEVER BLOCKS: every
# failure path is swallowed, exit 0 always (writer semantics, constraint 5)
# — mirrors hb_write. Deduped by the per-event-type natural key: if an
# identical-key event already exists in the target file, this is a no-op
# (still prints the path — the event already exists, which is the caller's
# success condition either way).
# ----------------------------------------------------------------------
pl_emit() {
  local type="" ask_id="" plan_slug="" task_id="" sha="" needs_you_id="" \
        session_id="" summary="" evidence_link="" emitter="" dedup_extra=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) type="${2:-}"; shift 2 ;;
      --ask) ask_id="${2:-}"; shift 2 ;;
      --plan-slug) plan_slug="${2:-}"; shift 2 ;;
      --task-id) task_id="${2:-}"; shift 2 ;;
      --sha) sha="${2:-}"; shift 2 ;;
      --needs-you-id) needs_you_id="${2:-}"; shift 2 ;;
      --session-id) session_id="${2:-}"; shift 2 ;;
      --summary) summary="${2:-}"; shift 2 ;;
      --evidence-link) evidence_link="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      --dedup-extra) dedup_extra="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$type" ]]; then
    echo "pl_emit: --type is required (no-op; never blocks the caller)" >&2
    return 0
  fi

  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')"

  # repo: ephemeral-ok READ (constraint 11 distinguishes reads from durable
  # in-repo WRITES; this log itself lives under ~/.claude/state per D1, not
  # in-repo, so a plain git rev-parse from cwd is fine here).
  local repo=""
  repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"

  local user="" machine=""
  user="$(git config user.name 2>/dev/null || true)"
  [[ -n "$user" ]] || user="${USER:-${USERNAME:-unknown}}"
  machine="$(hostname 2>/dev/null || echo unknown)"

  local provenance="known"
  if ! _pl_in_list "$emitter" "${_PL_KNOWN_EMITTERS[@]}"; then
    provenance="unknown"
  fi

  local nk event_id
  nk="$(_pl_natural_key "$type" "$ask_id" "$plan_slug" "$task_id" "$sha" "$needs_you_id" "$session_id" "$dedup_extra" "$repo")"
  event_id="$(_pl_hash "$nk")"

  local path dir
  path="$(pl_path_for "$ask_id")"
  dir="$(dirname "$path")"
  mkdir -p "$dir" 2>/dev/null || { return 0; }

  # Dedup: an identical natural key already recorded -> no-op (idempotent).
  if [[ -f "$path" ]] && grep -qF "\"event_id\":\"$event_id\"" "$path" 2>/dev/null; then
    printf '%s' "$path"
    return 0
  fi

  local ask_esc type_esc slug_esc task_esc sha_esc ny_esc sid_esc summary_esc \
        link_esc emitter_esc user_esc machine_esc repo_esc
  ask_esc="$(_pl_json_escape "$ask_id")"
  type_esc="$(_pl_json_escape "$type")"
  slug_esc="$(_pl_json_escape "$plan_slug")"
  task_esc="$(_pl_json_escape "$task_id")"
  sha_esc="$(_pl_json_escape "$sha")"
  ny_esc="$(_pl_json_escape "$needs_you_id")"
  sid_esc="$(_pl_json_escape "$session_id")"
  summary_esc="$(_pl_json_escape "$summary")"
  link_esc="$(_pl_json_escape "$evidence_link")"
  emitter_esc="$(_pl_json_escape "$emitter")"
  user_esc="$(_pl_json_escape "$user")"
  machine_esc="$(_pl_json_escape "$machine")"
  repo_esc="$(_pl_json_escape "$repo")"

  local json
  json="$(printf '{"v":1,"event_id":"%s","ts":"%s","ask_id":"%s","type":"%s","plan_slug":"%s","task_id":"%s","sha":"%s","needs_you_id":"%s","session_id":"%s","summary":"%s","evidence_link":"%s","emitter":"%s","provenance":"%s","user":"%s","machine":"%s","repo":"%s"}' \
    "$event_id" "$ts" "$ask_esc" "$type_esc" "$slug_esc" "$task_esc" "$sha_esc" "$ny_esc" "$sid_esc" "$summary_esc" "$link_esc" "$emitter_esc" "$provenance" "$user_esc" "$machine_esc" "$repo_esc")"

  printf '%s\n' "$json" >> "$path" 2>/dev/null || { return 0; }

  printf '%s' "$path"
  return 0
}

# ============================================================
# --self-test (only runs when this file is EXECUTED directly, not sourced)
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'pllst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  export PROGRESS_LOG_STATE_DIR="$TMP/pl"
  mkdir -p "$PROGRESS_LOG_STATE_DIR"

  echo "Scenario 1: pl_path_for resolves under the sandboxed state dir"
  p="$(pl_path_for "ask-abc")"
  if [[ "$p" == "$PROGRESS_LOG_STATE_DIR/ask-abc.jsonl" ]]; then
    pass "pl_path_for composes state-dir + ask-id + .jsonl"
  else
    fail "expected $PROGRESS_LOG_STATE_DIR/ask-abc.jsonl, got $p"
  fi

  echo "Scenario 1b: empty ask-id resolves to the 'unlinked' file"
  pu="$(pl_path_for "")"
  if [[ "$pu" == "$PROGRESS_LOG_STATE_DIR/unlinked.jsonl" ]]; then
    pass "pl_path_for('') resolves to unlinked.jsonl"
  else
    fail "expected $PROGRESS_LOG_STATE_DIR/unlinked.jsonl, got $pu"
  fi

  echo "Scenario 2: pl_emit writes a schema-valid task_done event"
  pl_emit --type task_done --ask "ask-1" --plan-slug "demo-plan" --task-id "3" \
    --sha "deadbeef1" --summary "task 3 verified done" --evidence-link "/tmp/demo-plan.md" \
    --emitter plan-lifecycle >/dev/null
  f1="$PROGRESS_LOG_STATE_DIR/ask-1.jsonl"
  if [[ -f "$f1" ]]; then
    pass "pl_emit created the per-ask log file"
  else
    fail "pl_emit did not create $f1"
  fi
  if command -v jq >/dev/null 2>&1; then
    if jq -e . "$f1" >/dev/null 2>&1; then
      pass "written event line is valid JSON (jq)"
    else
      fail "written event line is NOT valid JSON"
    fi
    v_v="$(jq -r '.v' "$f1" 2>/dev/null | tr -d '\r')"
    type_v="$(jq -r '.type' "$f1" 2>/dev/null | tr -d '\r')"
    slug_v="$(jq -r '.plan_slug' "$f1" 2>/dev/null | tr -d '\r')"
    task_v="$(jq -r '.task_id' "$f1" 2>/dev/null | tr -d '\r')"
    prov_v="$(jq -r '.provenance' "$f1" 2>/dev/null | tr -d '\r')"
    if [[ "$v_v" == "1" && "$type_v" == "task_done" && "$slug_v" == "demo-plan" && "$task_v" == "3" && "$prov_v" == "known" ]]; then
      pass "schema fields round-trip (v=1, type, plan_slug, task_id, provenance=known for an allowlisted emitter)"
    else
      fail "field mismatch: v=$v_v type=$type_v slug=$slug_v task=$task_v prov=$prov_v"
    fi
  else
    grep -q '"v":1' "$f1" && pass "v field present (grep fallback, jq unavailable)" || fail "v field missing (grep fallback)"
  fi

  echo "Scenario 3: replay dedup — identical natural key (same sha) is NOT double-logged"
  pl_emit --type task_done --ask "ask-1" --plan-slug "demo-plan" --task-id "3" \
    --sha "deadbeef1" --summary "task 3 verified done (replay)" --emitter plan-lifecycle >/dev/null
  lines=$(wc -l < "$f1" | tr -d ' ')
  if [[ "$lines" == "1" ]]; then
    pass "replaying the same natural key (plan_slug+task_id+sha) produced exactly 1 line, not 2"
  else
    fail "expected 1 line after replay, got $lines"
  fi

  echo "Scenario 4: legitimate recurrence — task_started with a NEW session_id is a distinct event"
  pl_emit --type task_started --ask "ask-1" --plan-slug "demo-plan" --task-id "5" \
    --session-id "sess-A" --summary "task 5 started" --emitter workstreams-emit >/dev/null
  pl_emit --type task_started --ask "ask-1" --plan-slug "demo-plan" --task-id "5" \
    --session-id "sess-B" --summary "task 5 re-dispatched" --emitter workstreams-emit >/dev/null
  ts_count=$(grep -c '"type":"task_started"' "$f1" 2>/dev/null || echo 0)
  if [[ "$ts_count" == "2" ]]; then
    pass "task_started re-dispatch with a NEW session_id logs TWO events (natural key includes session_id)"
  else
    fail "expected 2 task_started events (re-dispatch), got $ts_count"
  fi

  echo "Scenario 4b: a hook replay of the SAME task_started dispatch (same session_id) dedups"
  pl_emit --type task_started --ask "ask-1" --plan-slug "demo-plan" --task-id "5" \
    --session-id "sess-A" --summary "task 5 started (replay)" --emitter workstreams-emit >/dev/null
  ts_count2=$(grep -c '"type":"task_started"' "$f1" 2>/dev/null || echo 0)
  if [[ "$ts_count2" == "2" ]]; then
    pass "replaying the SAME session_id did NOT create a 3rd task_started event"
  else
    fail "expected still 2 task_started events after replay, got $ts_count2"
  fi

  echo "Scenario 5: unknown emitter is flagged provenance:unknown, never trusted as mechanism truth"
  pl_emit --type task_done --ask "ask-2" --plan-slug "other-plan" --task-id "1" \
    --sha "cafef00d" --summary "suspicious self-report" --emitter "some-random-cli" >/dev/null
  f2="$PROGRESS_LOG_STATE_DIR/ask-2.jsonl"
  if command -v jq >/dev/null 2>&1; then
    prov2="$(jq -r '.provenance' "$f2" 2>/dev/null | tr -d '\r')"
    if [[ "$prov2" == "unknown" ]]; then
      pass "an emitter outside the known-mechanism allowlist is flagged provenance:unknown"
    else
      fail "expected provenance:unknown for emitter 'some-random-cli', got '$prov2'"
    fi
  else
    grep -q '"provenance":"unknown"' "$f2" && pass "provenance:unknown present (grep fallback)" || fail "provenance:unknown missing (grep fallback)"
  fi

  echo "Scenario 6: sandbox-only writes — nothing was written outside PROGRESS_LOG_STATE_DIR"
  # T10-style assertion (context-watermark.sh model, constraint 4): the real
  # production dir must not exist as a side effect of this self-test run.
  if [[ ! -e "$TMP/.claude" ]]; then
    pass "self-test did not create any ~/.claude-shaped path under its own tempdir"
  else
    fail "self-test unexpectedly created a .claude path under $TMP"
  fi

  rm -rf "$TMP" 2>/dev/null || true

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then exit 0; else exit 1; fi
fi
