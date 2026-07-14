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
#   task_started           -> plan_slug + task_id + session_id + --dedup-extra
#     (2026-07-14 ask-splice review panel, Finding 2: the caller's
#     session_id is the DISPATCHING orchestrator's CLAUDE_SESSION_ID, which
#     is INVARIANT across every dispatch it makes -- a within-session
#     re-dispatch of a failed task therefore has an identical plan_slug+
#     task_id+session_id triple and was being silently dropped, violating
#     this row's own "re-dispatch = new child session" recurrence rule.
#     workstreams-emit.sh's `_emit_dispatch_provenance` now passes a coarse
#     per-dispatch wall-clock time-bucket as --dedup-extra: fine enough that
#     a genuine re-dispatch seconds/minutes later is a NEW event, coarse
#     enough that a true same-dispatch double-fire replay still dedups.)
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
# The versioned schema above is machine-checked in
# adapters/claude-code/schemas/progress-log-event.schema.json (Task 2) —
# an ALLOWLIST schema (additionalProperties:false) so a future field added
# here without a schema update is a self-test-visible drift, not silent.
#
# ============================================================
# WRITER HARDENING — concurrent-write safety (Task 2)
# ============================================================
#
# pl_emit's dedup check ("does this natural key already exist?") and its
# append are two separate operations; without protection, two PROCESSES
# emitting the identical natural key at nearly the same instant (e.g. a
# live splice racing the Task 12 auditor's backfill of the same event —
# an explicitly named scenario in the plan's Behavioral Contracts) could
# both pass the check before either appends, producing two lines for one
# natural key. `_pl_acquire_lock`/`_pl_release_lock` wrap that critical
# section in a `mkdir`-based mutex: `mkdir` is atomic even on Windows/NTFS
# via Git Bash, so this needs no `flock`/`lockfile` binary (neither is
# reliably present on this harness's Windows target). The lock spins for a
# small bounded budget (~150ms) and then PROCEEDS UNLOCKED rather than
# hang the caller (writer semantics, constraint 5: never blocks) — under
# that rare fallback the worst case is the pre-hardening behavior (a
# possible duplicate line for one natural key), never a hang or a lost
# write. A crashed holder simply leaves a stale lock directory that the
# NEXT caller's bounded spin times out past — no manual cleanup needed.
#
# pl_emit releases the lock via EXPLICIT `_pl_release_lock` calls at each
# of its own return points, NOT a `trap ... RETURN`. That was the first
# design and it broke a caller: bash's RETURN trap, once set inside a
# called function, is NOT scoped to that function alone — it persists and
# re-fires on the NEXT function return anywhere up the call stack (verified
# empirically). Concretely, `ask-registry.sh`'s cmd_register calls pl_emit,
# and the leaked trap re-fired on cmd_register's OWN unrelated `return`,
# referencing pl_emit's already-torn-down local `path` -> "path: unbound
# variable" under `set -u`. Explicit release calls are more verbose but
# immune to that whole class of bug.
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
# _pl_sanitize_ask_id <raw-ask-id> — print a filesystem-SAFE single-path-
# component derived from the raw ask-id. This is the SECURITY BOUNDARY that
# protects EVERY emitter (plan-lifecycle, workstreams-emit, needs-you,
# post-commit, close-plan, ask-registry, auditor) at once: it lives in the
# shared lib, not in any one caller, so no caller can forget it. Without it,
# pl_path_for would compose <state-dir>/<ask_id>.jsonl from an unsanitized
# ask_id, and a `/`- or `..`-bearing ask_id (e.g. `../../evil`) would write
# OUTSIDE the state dir — a path-traversal write primitive.
#
# Guarantee: the returned string contains NO path separator (`/` or `\`) and
# NO `..` run, so pl_path_for's `<dir>/<result>.jsonl` is ALWAYS a single
# path component directly under <dir> — categorically unable to escape.
#   1. Empty raw -> the documented "unlinked" orphan-lane file (unchanged
#      behavior; a splice that cannot yet resolve an ask-id still logs
#      somewhere deterministic).
#   2. Otherwise allowlist-normalize: every char outside [A-Za-z0-9._-]
#      (crucially the separators / and \, plus whitespace/control) -> `_`.
#      A legitimate registry ask-id (e.g. `ask-20260710-workstreams-rebuild`)
#      is entirely in the allowlist and passes through UNCHANGED — no
#      regression for the real-world id shape.
#   3. Collapse any residual `..` run (belt-and-suspenders: already harmless
#      once separators are gone, but keeps the filename unambiguous).
#   4. Degenerate results (`.`, `_`, or empty after the above) -> a
#      deterministic `sanitized-<hash-of-RAW>` token so two DISTINCT bad ids
#      still get DISTINCT files (never silently merged) while staying a
#      single safe component.
# Uses only bash parameter expansion (no fork) so it stays within the splice
# budget (<=50ms), matching pl_emit's no-jq-on-the-write-path convention.
# ----------------------------------------------------------------------
_pl_sanitize_ask_id() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    printf 'unlinked'
    return 0
  fi
  local s="${raw//[!A-Za-z0-9._-]/_}"
  while [[ "$s" == *..* ]]; do s="${s//../_}"; done
  if [[ -z "$s" || "$s" == "." || "$s" == "_" ]]; then
    s="sanitized-$(_pl_hash "$raw")"
  fi
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# pl_path_for <ask-id> — print the resolved per-ask JSONL path. The ask-id
# is run through _pl_sanitize_ask_id first (see above), so the result is
# ALWAYS a single path component under pl_state_dir — a `/`- or `..`-bearing
# ask-id can never escape the state directory. An empty ask-id resolves to
# the literal "unlinked" file (mirrors hb_path_for's "unknown" fallback) — a
# full orphan lane keyed by plan-slug is Task 2/12's job; this is the honest,
# no-events-lost stopgap so a splice that cannot yet resolve an ask-id still
# logs SOMEWHERE deterministic instead of silently no-op-ing (Edge Cases:
# "estate-growth safe: old plans never break the surface").
# ----------------------------------------------------------------------
pl_path_for() {
  local ask_id
  ask_id="$(_pl_sanitize_ask_id "${1:-}")"
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
      # dedup_extra carries the caller's per-dispatch discriminator (see the
      # DEDUP header comment above, Finding 2) -- included so an invariant
      # dispatching session_id no longer collapses a genuine re-dispatch.
      printf 'task_started|%s|%s|%s|%s' "$plan_slug" "$task_id" "$session_id" "$dedup_extra" ;;
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
# _pl_acquire_lock <path> — best-effort inter-PROCESS mutex over the
# dedup-check+append critical section for <path>'s per-ask log file (Task 2
# writer hardening; see header). Uses `mkdir "<path>.lock"` as the mutex
# primitive (atomic create-if-absent on every target filesystem this
# harness runs on, no extra binary required). Returns 0 if the lock was
# acquired (caller must release it), 1 if the bounded spin budget (~150ms:
# 30 tries * 5ms) was exhausted first (caller proceeds UNLOCKED — never
# blocks indefinitely, constraint 5).
# ----------------------------------------------------------------------
_pl_acquire_lock() {
  local path="$1"
  local lockdir="${path}.lock"
  local i=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    i=$((i + 1))
    if [[ $i -ge 30 ]]; then
      return 1
    fi
    sleep 0.005 2>/dev/null || sleep 1
  done
  return 0
}

# ----------------------------------------------------------------------
# _pl_release_lock <path> — release a lock previously acquired by
# _pl_acquire_lock for the same <path>. ONLY call this when
# _pl_acquire_lock returned 0 for this same path in this process — calling
# it after a failed/timed-out acquire would delete another holder's lock
# and defeat mutual exclusion.
# ----------------------------------------------------------------------
_pl_release_lock() {
  local path="$1"
  rmdir "${path}.lock" 2>/dev/null || true
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

  # Writer hardening (Task 2): serialize the dedup-check+append critical
  # section across concurrent PROCESSES so a live splice racing an auditor
  # backfill (or two hook replays) of the SAME natural key cannot both slip
  # past the check and double-append. Deliberately NOT using `trap ...
  # RETURN` here: bash's RETURN trap, once set inside a called function,
  # is NOT scoped to that function alone — it persists and re-fires on the
  # NEXT function return anywhere up the call stack (verified empirically;
  # this bit ask-registry.sh's cmd_register with "path: unbound variable"
  # under `set -u` when pl_emit's trap leaked into cmd_register's own
  # unrelated `return`). Explicit release calls at each exit point below
  # are more verbose but immune to that whole class of bug. locked=1 only
  # when the lock was actually acquired — releasing a lock we don't hold
  # would delete another holder's mutex (see _pl_release_lock).
  local locked=0
  _pl_acquire_lock "$path" && locked=1

  # Dedup: an identical natural key already recorded -> no-op (idempotent).
  if [[ -f "$path" ]] && grep -qF "\"event_id\":\"$event_id\"" "$path" 2>/dev/null; then
    [[ "$locked" == "1" ]] && _pl_release_lock "$path"
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

  printf '%s\n' "$json" >> "$path" 2>/dev/null || { [[ "$locked" == "1" ]] && _pl_release_lock "$path"; return 0; }

  [[ "$locked" == "1" ]] && _pl_release_lock "$path"
  printf '%s' "$path"
  return 0
}

# ============================================================
# SESSION CLASSIFICATION (ask-rooted-workstreams-p1, Task 9) — the ONE
# shared predicate a spawned/builder/sub-agent session is told apart from
# an operator-origin session. Task 9's automatic-capture guard
# (hooks/workstreams-read.sh, hooks/session-start-digest.sh) and Task
# 17(c)'s doctor capture-completeness predicate BOTH call
# `pl_classify_session` — population parity by construction: the doctor
# must count exactly the population the guard excludes, and a
# re-derivation in two places is exactly the drift review round 1 flagged
# (systems Minor 8). Do not copy this logic elsewhere; source this file and
# call the function.
# ============================================================

# ----------------------------------------------------------------------
# _pl_dispatch_provenance_dir — resolve the Task 3 dispatch-provenance
# marker directory. IDENTICAL resolution order to
# scripts/dispatch-provenance.sh's own `_dp_state_dir` (same env var, same
# HARNESS_SELFTEST_DIR fallback shape) so a caller that sandboxes one
# sandboxes the other automatically — no separate wiring needed in tests.
# ----------------------------------------------------------------------
_pl_dispatch_provenance_dir() {
  if [[ -n "${DISPATCH_PROVENANCE_STATE_DIR:-}" ]]; then
    printf '%s' "$DISPATCH_PROVENANCE_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/state/dispatch-provenance' "${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}/dispatch-provenance-selftest/$$}"
    return 0
  fi
  printf '%s/.claude/state/dispatch-provenance' "${HOME:-$PWD}"
}

# ----------------------------------------------------------------------
# _pl_marker_field <file> <field> — best-effort single-field extraction
# from a one-line dispatch-provenance marker JSON object, no jq dependency
# (same sed technique hooks/workstreams-read.sh already uses for
# `session_id`). Prints empty on any failure; never errors.
# ----------------------------------------------------------------------
_pl_marker_field() {
  local file="$1" field="$2"
  [[ -f "$file" ]] || { printf ''; return 0; }
  sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" 2>/dev/null | head -n1
}

# ----------------------------------------------------------------------
# _pl_marker_field_from_line <line> <field> — the SAME extraction as
# _pl_marker_field above, but operating on an ALREADY-READ line and using
# ONLY bash parameter expansion. Result is returned in the global
# `_PL_MARKER_FIELD_OUT`, NOT printed — deliberately: capturing a printed
# value with `$(...)` command substitution FORKS A SUBSHELL, which would
# reintroduce exactly the per-marker fork cost this exists to remove. Call
# it as a bare statement and read the global:
#
#     _pl_marker_field_from_line "$line" worktree_path
#     wt="$_PL_MARKER_FIELD_OUT"
#
# TOTAL FORKS: ZERO (vs _pl_marker_field's `sed | head` = ~2 per call).
#
# WHY THIS EXISTS (FINDING 1, 2026-07-14 ask-splice review panel): the
# marker scan in pl_classify_session below runs on the SESSION HOT PATH
# (every SessionStart + first UserPromptSubmit). Bounding that scan to the
# newest N markers alone is NOT enough — for the COMMON case (an operator
# session whose cwd matches NOTHING) the loop still visits every one of
# those N markers and, at ~2 forks each via _pl_marker_field, would pay
# ~2N synchronous subprocess spawns (brutally slow on this harness's
# Windows/Git-Bash target, where a fork is ~10s of ms).
#
# _pl_marker_field is deliberately left in place, unchanged: it is the
# convenient file-oriented form and hooks/harness-doctor.sh calls it (for
# `session_id` / `cwd`) OFF the hot path, where 2 forks per call is fine.
#
# Both forms are best-effort and never error: an absent field, a malformed
# line, or an empty input all yield empty.
# ----------------------------------------------------------------------
_pl_marker_field_from_line() {
  _PL_MARKER_FIELD_OUT=""
  local line="${1:-}" field="${2:-}"
  [[ -z "$line" || -z "$field" ]] && return 0
  local needle="\"${field}\":\""
  # Field absent -> the prefix-strip is a no-op and leaves `line` intact.
  local rest="${line#*$needle}"
  [[ "$rest" == "$line" ]] && return 0
  # Value runs to the next `"` (marker values are written by
  # dispatch-provenance.sh's _dp_json_escape, which escapes any embedded
  # quote — so the first bare `"` is genuinely the value's end).
  _PL_MARKER_FIELD_OUT="${rest%%\"*}"
  return 0
}

# ----------------------------------------------------------------------
# pl_classify_session [--cwd <path>] [--dispatch-provenance-dir <dir>]
#
# Classifies the CURRENT (or --cwd-overridden) session as SPAWNED
# (builder/sub-agent/dispatched-worktree) or operator-origin, per the
# plan's review-round-1 MECHANICAL PREDICATE:
#   (a) the resolved cwd sits inside a `.claude/worktrees/<slug>` pool —
#       the layout scripts/spawn-worktree.sh, the `--worktree` CLI flag,
#       and the desktop app's per-task isolation all create
#       ($MAIN/.claude/worktrees/<slug>), OR
#   (b) a Task 3 dispatch-provenance marker
#       (~/.claude/state/dispatch-provenance/*.json — scripts/
#       dispatch-provenance.sh's `write` verb, called from
#       hooks/workstreams-emit.sh's --on-builder-dispatch/--on-spawn
#       splices) whose `worktree_path` field equals, or is a path-ancestor
#       of, the resolved cwd, AND whose `worktree_path` is ITSELF inside a
#       `.claude/worktrees/` pool (see Finding 3 note below).
# (a) is the PRIMARY practical signal (nearly every spawn lands under the
# worktrees pool); (b) is ADDITIONAL, not sole (many dispatch call sites
# cannot see the child's worktree path at PreToolUse time and record an
# honest empty `worktree_path` — see dispatch-provenance.sh's own header —
# so a marker match is a bonus resolution: it never triggers SPAWNED for a
# cwd that (a) wouldn't already cover on its own; its real value is
# resolving `marker_ask` when (a) has already matched, since (a) alone
# yields "spawned" with an EMPTY ask_id — see self-test Scenario 12).
#
# FINDING 3 (2026-07-14 ask-splice review panel): a marker's `worktree_path`
# used to be honored verbatim regardless of shape. A cross-repo
# `mcp__ccd_session__spawn_task` dispatch (documented estate workflow) can
# supply a `cwd` override that is a bare PROJECT ROOT, not a
# `.claude/worktrees/<slug>` child — recording THAT as `worktree_path` meant
# a LATER, wholly unrelated operator session that merely happens to work at
# that same root (or a subdirectory of it) matched this ancestor predicate
# and was misclassified SPAWNED, silently dropping its opening ask. The
# guard below requires a marker's `worktree_path` to itself sit inside a
# `.claude/worktrees/` pool before it can contribute to classification at
# all — the writer side (workstreams-emit.sh's `_emit_dispatch_provenance`)
# also now refuses to record a non-pool cwd as `--worktree` in the first
# place (defense in depth: this guard still protects against a
# pre-existing/stale marker written before that writer-side fix landed).
#
# Prints exactly one line to stdout:
#   "spawned <ask_id>"   — ask_id is the DISPATCHING ask resolved from a
#                          matching marker, or empty if classified spawned
#                          via (a) alone with no resolvable marker.
#   "operator"           — not spawned.
# Returns 0 when SPAWNED, 1 when operator-origin. NEVER ERRORS: an
# unresolvable cwd, a missing marker dir, or a malformed marker file all
# fall through to "operator" — the safer default (a false "operator" lets
# a spawned session register one spurious ask an operator can dismiss; a
# false "spawned" would silently DROP a genuine operator ask and break the
# zero-ceremony capture guarantee — asymmetric costs, so ties resolve
# toward NOT suppressing capture).
# ----------------------------------------------------------------------
pl_classify_session() {
  local cwd="" dp_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd) cwd="${2:-}"; shift 2 ;;
      --dispatch-provenance-dir) dp_dir="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$cwd" ]] || cwd="${PWD:-}"
  [[ -n "$dp_dir" ]] || dp_dir="$(_pl_dispatch_provenance_dir)"

  # Normalize separators: a Windows-shaped cwd (backslash-separated, e.g.
  # from a hook's stdin JSON `cwd` field) must match the pool substring
  # exactly as reliably as a Git-Bash-shaped forward-slash path.
  local norm="${cwd//\\//}"

  local pool_hit=1
  case "$norm" in
    */.claude/worktrees/*) pool_hit=0 ;;
  esac

  local marker_ask=""
  if [[ -d "$dp_dir" ]]; then
    # FINDING 1 (2026-07-14 ask-splice review panel): markers are written
    # per plan-rooted dispatch and (absent dispatch-provenance.sh's own
    # write-time prune, which this fix also adds) accumulate without bound
    # as the estate ages. This function runs on the SESSION HOT PATH (every
    # SessionStart + first UserPromptSubmit), so the previous "fork ~2
    # subprocesses per marker (_pl_marker_field) across the ENTIRE
    # directory" scan paid synchronous, ever-growing latency (precedent:
    # session-start-digest.sh already backgrounds an analogous unbounded
    # heartbeat-reap scan, measured ~11s). The fix is BOTH halves -- either
    # alone is insufficient:
    #   (i)  BOUND the population: build a "<ts_compact>\t<path>" index with
    #        pure parameter expansion (zero forks), then fork exactly ONE
    #        `sort | head | cut` pipeline to take the newest
    #        PL_DISPATCH_PROVENANCE_SCAN_LIMIT (default 200) markers by the
    #        dispatch timestamp embedded in their filename
    #        (dispatch-provenance.sh names them `<key>__<ts_compact>.json`).
    #   (ii) Make the PER-MARKER cost ZERO forks: read each single-line
    #        marker with the `read` BUILTIN and slice fields out with
    #        _pl_marker_field_from_line (parameter expansion only). Without
    #        (ii), the COMMON case -- an operator session matching NOTHING --
    #        still visits all N markers and pays ~2N forks.
    # Net: the whole scan is 3 forks, flat, regardless of estate age. A
    # genuinely live child-worktree marker is always among the newest few,
    # so the bound never mis-classifies a real spawn (self-test Scenario 16).
    local scan_limit="${PL_DISPATCH_PROVENANCE_SCAN_LIMIT:-200}"
    local f base ts idx=""
    for f in "$dp_dir"/*.json; do
      [[ -f "$f" ]] || continue
      base="${f##*/}"
      ts="${base%.json}"; ts="${ts##*__}"
      [[ "$ts" =~ ^[0-9]+$ ]] || ts="0"
      idx="${idx}${ts}"$'\t'"${f}"$'\n'
    done
    if [[ -n "$idx" ]]; then
      local newest line wt
      newest="$(printf '%s' "$idx" | sort -r -t $'\t' -k1,1 | head -n "$scan_limit" | cut -f2-)"
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        # `read` builtin: no fork. Markers are single-line JSON objects.
        line=""
        IFS= read -r line <"$f" 2>/dev/null || true
        [[ -z "$line" ]] && continue
        # Bare call + read the out-global: a `$(...)` capture here would
        # fork a subshell per marker and defeat the whole point.
        _pl_marker_field_from_line "$line" worktree_path
        wt="$_PL_MARKER_FIELD_OUT"
        [[ -z "$wt" ]] && continue
        # A Windows path was written through _dp_json_escape, which doubles
        # backslashes -- undo that before normalizing separators, or
        # `C:\\Users` would normalize to `C://Users` and never match.
        wt="${wt//\\\\/\\}"
        wt="${wt//\\//}"
        # FINDING 3: only ever honor a marker whose worktree_path is
        # ITSELF inside a `.claude/worktrees/` pool (see header note above)
        # -- never let a bare project-root (or any other non-pool) marker
        # path contribute to classification.
        case "$wt" in
          */.claude/worktrees/*) ;;
          *) continue ;;
        esac
        if [[ "$norm" == "$wt" || "$norm" == "$wt"/* ]]; then
          _pl_marker_field_from_line "$line" ask_id
          marker_ask="$_PL_MARKER_FIELD_OUT"
          [[ -n "$marker_ask" ]] && break
        fi
      done <<<"$newest"
    fi
  fi

  if [[ "$pool_hit" == "0" || -n "$marker_ask" ]]; then
    printf 'spawned %s\n' "$marker_ask"
    return 0
  fi
  printf 'operator\n'
  return 1
}

# ----------------------------------------------------------------------
# pl_ask_id_for_session <session-id>
#
# Deterministic ask-id derivation for the automatic-capture mechanism
# (Task 9): the SAME session-id always derives the SAME ask-id. Claude
# Code keeps `session_id` stable across `--resume` (the resumed session
# continues the identical transcript file under the identical id), so a
# resumed session's SessionStart splice re-derives the EXACT ask-id its
# first-prompt splice minted at registration time — no marker file, no
# registry lookup, no race: "resume attaches without duplicate" falls out
# of this function alone. Empty session-id -> empty (nothing to derive;
# caller must skip). Uses `_pl_hash` (already portable: sha1sum, then
# openssl, then cksum) so no new external dependency is introduced.
# ----------------------------------------------------------------------
pl_ask_id_for_session() {
  local sid="${1:-}"
  [[ -z "$sid" ]] && { printf ''; return 0; }
  printf 'ask-auto-%s' "$(_pl_hash "$sid" | cut -c1-16)"
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

  echo "Scenario 1c: SECURITY — a path-traversal / separator-bearing ask-id CANNOT escape the state dir (pl_path_for sanitizes; the resolved path's parent is ALWAYS exactly pl_state_dir)"
  state_dir_resolved="$(pl_state_dir)"
  traversal_ok=1
  # Each of these, if composed unsanitized as <dir>/<id>.jsonl, would
  # traverse OUT of the state dir (../.. climbs above it; a/b/c writes into
  # a nested subtree; a leading / is an absolute-path attempt).
  for evil in "../../evil" "a/b/c" "/etc/passwd" "foo/../../../bar" '..\..\evil' ".." "."; do
    resolved="$(pl_path_for "$evil")"
    parent="$(dirname "$resolved")"
    if [[ "$parent" != "$state_dir_resolved" ]]; then
      fail "ask-id '$evil' ESCAPED: resolved parent '$parent' != state dir '$state_dir_resolved' (resolved=$resolved)"
      traversal_ok=0
    fi
    case "$resolved" in
      *.jsonl) : ;;
      *) fail "ask-id '$evil' did not resolve to a .jsonl file: $resolved"; traversal_ok=0 ;;
    esac
  done
  [[ "$traversal_ok" == "1" ]] && pass "every path-traversal ask-id ('../../evil', 'a/b/c', '/etc/passwd', 'foo/../../../bar', backslash variant, '..', '.') stays a single component directly under pl_state_dir"

  echo "Scenario 1d: sanitizer preserves a legitimate registry ask-id UNCHANGED (no regression for the real id shape) and actually WRITES the traversal event inside the state dir, not outside it"
  legit="$(pl_path_for "ask-20260710-workstreams-rebuild")"
  if [[ "$legit" == "$PROGRESS_LOG_STATE_DIR/ask-20260710-workstreams-rebuild.jsonl" ]]; then
    pass "a legitimate ask-id passes through the sanitizer byte-for-byte unchanged"
  else
    fail "legitimate ask-id was altered by the sanitizer: got $legit"
  fi
  # Emit-level proof: a real emit with a traversal ask-id must land a file
  # UNDER the state dir (the sanitized name) and create NOTHING outside it.
  pl_emit --type task_done --ask "../../evil" --plan-slug "sec-plan" --task-id "1" \
    --sha "secsha1" --summary "traversal attempt" --emitter plan-lifecycle >/dev/null 2>&1
  escaped_hits=$(find "$TMP" -name 'evil.jsonl' 2>/dev/null | wc -l | tr -d ' ')
  under_state=$(find "$PROGRESS_LOG_STATE_DIR" -maxdepth 1 -name '*evil*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$escaped_hits" == "0" ]] && [[ "$under_state" -ge "1" ]]; then
    pass "emit('../../evil') created a sanitized log file INSIDE the state dir and NO literal 'evil.jsonl' anywhere (no separator survived to traverse)"
  else
    fail "traversal emit misbehaved: literal-evil.jsonl hits=$escaped_hits (want 0), sanitized-under-state=$under_state (want >=1)"
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

  echo "Scenario 4c (Finding 2 fix, lib-level): task_started with the IDENTICAL session_id but a DIFFERENT --dedup-extra is a distinct event -- this is the exact mechanism workstreams-emit.sh's _emit_dispatch_provenance now relies on, since its session_id is the DISPATCHING (parent) session and is invariant across every dispatch it makes"
  pl_emit --type task_started --ask "ask-1" --plan-slug "demo-plan" --task-id "6" \
    --session-id "sess-parent-invariant" --dedup-extra "1000" --summary "task 6 dispatched" --emitter workstreams-emit >/dev/null
  pl_emit --type task_started --ask "ask-1" --plan-slug "demo-plan" --task-id "6" \
    --session-id "sess-parent-invariant" --dedup-extra "2000" --summary "task 6 re-dispatched" --emitter workstreams-emit >/dev/null
  ts_count4c=$(grep -c '"plan_slug":"demo-plan".*"task_id":"6"' "$f1" 2>/dev/null || echo 0)
  if [[ "$ts_count4c" == "2" ]]; then
    pass "SAME session_id + DIFFERENT dedup_extra logs TWO task_started events (re-dispatch preserved even when session_id can't vary)"
  else
    fail "expected 2 task_started events for task 6 (same session_id, different dedup_extra), got $ts_count4c"
  fi

  echo "Scenario 4d: task_started with the IDENTICAL session_id AND IDENTICAL --dedup-extra still dedups (a true double-fire replay, not a new dispatch)"
  pl_emit --type task_started --ask "ask-1" --plan-slug "demo-plan" --task-id "6" \
    --session-id "sess-parent-invariant" --dedup-extra "2000" --summary "task 6 re-dispatched (replay)" --emitter workstreams-emit >/dev/null
  ts_count4d=$(grep -c '"plan_slug":"demo-plan".*"task_id":"6"' "$f1" 2>/dev/null || echo 0)
  if [[ "$ts_count4d" == "2" ]]; then
    pass "SAME session_id + SAME dedup_extra did NOT create a 3rd task_started event for task 6"
  else
    fail "expected still 2 task_started events for task 6 after an identical-dedup_extra replay, got $ts_count4d"
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

  echo "Scenario 7: concurrent-append — DISTINCT natural keys from parallel processes all land intact, no interleaving/corruption"
  conc_ask="ask-concurrent-1"
  conc_file="$PROGRESS_LOG_STATE_DIR/$conc_ask.jsonl"
  n_conc=10
  conc_pids=()
  for i in $(seq 1 $n_conc); do
    pl_emit --type task_done --ask "$conc_ask" --plan-slug "conc-plan" --task-id "$i" \
      --sha "sha-$i" --summary "task $i verified done (concurrent)" --emitter plan-lifecycle >/dev/null 2>&1 &
    conc_pids+=("$!")
  done
  for p in "${conc_pids[@]}"; do wait "$p" 2>/dev/null; done
  conc_lines=$(wc -l < "$conc_file" 2>/dev/null | tr -d ' ')
  if [[ "$conc_lines" == "$n_conc" ]]; then
    pass "$n_conc concurrent distinct-key emits (separate processes) produced exactly $n_conc lines — no drops, no merges"
  else
    fail "expected $n_conc lines after concurrent distinct-key emits, got '$conc_lines'"
  fi
  if command -v jq >/dev/null 2>&1; then
    conc_bad=0
    while IFS= read -r line; do
      printf '%s' "$line" | jq -e . >/dev/null 2>&1 || conc_bad=$((conc_bad + 1))
    done < "$conc_file"
    if [[ "$conc_bad" == "0" ]]; then
      pass "every concurrently-written line independently parses as valid JSON (no torn/interleaved writes)"
    else
      fail "$conc_bad line(s) failed JSON validation after concurrent writes (torn/interleaved append)"
    fi
  fi

  echo "Scenario 8: concurrent-append race — MULTIPLE PROCESSES emitting the IDENTICAL natural key dedup to exactly one line (writer-hardening mkdir-lock)"
  race_ask="ask-race-1"
  race_file="$PROGRESS_LOG_STATE_DIR/$race_ask.jsonl"
  race_barrier="$TMP/race-barrier"
  rm -f "$race_barrier" 2>/dev/null
  n_race=6
  race_pids=()
  for i in $(seq 1 $n_race); do
    (
      # Busy-wait for a shared barrier file so every racer starts as close
      # to simultaneously as possible — maximizes odds of exercising the
      # lock's actual contention path rather than accidentally serializing
      # through process-start jitter alone.
      tries=0
      while [[ ! -f "$race_barrier" ]] && [[ $tries -lt 2000 ]]; do
        sleep 0.001 2>/dev/null || true
        tries=$((tries + 1))
      done
      pl_emit --type task_done --ask "$race_ask" --plan-slug "race-plan" --task-id "9" \
        --sha "racesha1" --summary "racer $i" --emitter plan-lifecycle >/dev/null 2>&1
    ) &
    race_pids+=("$!")
  done
  sleep 0.05
  : > "$race_barrier"
  for p in "${race_pids[@]}"; do wait "$p" 2>/dev/null; done
  race_lines=$(wc -l < "$race_file" 2>/dev/null | tr -d ' ')
  if [[ "$race_lines" == "1" ]]; then
    pass "$n_race racing processes emitting the IDENTICAL natural key produced exactly 1 line (mkdir-lock hardening holds under contention)"
  else
    fail "expected 1 line after $n_race concurrent identical-key emits, got '$race_lines'"
  fi

  echo "Scenario 9: CRLF-safety — embedded CR/LF/tab in field values never leak raw control bytes; the log file's own line terminator stays bare LF (repo pins eol=lf; MSYS text tools can mask CRLF, so this check uses 'od -tx1' hex bytes, not grep/cat, per the harness CRLF doctrine)"
  crlf_ask="ask-crlf-1"
  crlf_file="$PROGRESS_LOG_STATE_DIR/$crlf_ask.jsonl"
  crlf_summary=$'line-one\r\nline-two\ttabbed'
  pl_emit --type task_done --ask "$crlf_ask" --plan-slug "crlf-plan" --task-id "1" \
    --sha "crlfsha1" --summary "$crlf_summary" --emitter plan-lifecycle >/dev/null 2>&1
  if [[ -f "$crlf_file" ]]; then
    cr_bytes=$(od -An -tx1 "$crlf_file" 2>/dev/null | tr -s ' ' '\n' | grep -c '^0d$')
    if [[ "$cr_bytes" == "0" ]]; then
      pass "no raw CR (0x0d) byte anywhere in the written line — the embedded \\r in --summary was escaped, not leaked; no CRLF line terminator either"
    else
      fail "found $cr_bytes raw CR (0x0d) byte(s) in $crlf_file — CRLF leaked into a supposedly LF-only progress-log file"
    fi
    if grep -qF '\r\n' "$crlf_file" 2>/dev/null && grep -qF '\t' "$crlf_file" 2>/dev/null; then
      pass "embedded CR/LF/tab in --summary were escaped into the JSON string as literal \\\\r\\\\n\\\\t tokens, not silently dropped"
    else
      fail "expected escaped \\\\r\\\\n\\\\t literals in the written event; the field may have been mangled or dropped"
    fi
  else
    fail "expected $crlf_file to exist after the CRLF-safety emit"
  fi

  echo "Scenario 10: emitted event's field set matches the versioned schema's allowlist exactly (schemas/progress-log-event.schema.json — additionalProperties:false)"
  schema_file="$(cd "${BASH_SOURCE%/*}/../../schemas" 2>/dev/null && pwd)/progress-log-event.schema.json"
  if command -v jq >/dev/null 2>&1 && [[ -f "$schema_file" ]] && [[ -f "$crlf_file" ]]; then
    schema_fields="$(jq -r '.properties | keys | sort | join(",")' "$schema_file" 2>/dev/null)"
    # crlf_file has exactly one line (Scenario 9's single emit) — safe to
    # read as one JSON object; $f1 by this point has 3 accumulated lines
    # from earlier scenarios and would make jq print one keys-set per line.
    event_fields="$(jq -r 'keys | sort | join(",")' "$crlf_file" 2>/dev/null)"
    if [[ -n "$schema_fields" ]] && [[ "$schema_fields" == "$event_fields" ]]; then
      pass "emitted event fields == schema properties exactly (no undocumented field drift)"
    else
      fail "schema/event field mismatch — schema=[$schema_fields] event=[$event_fields]"
    fi
  else
    fail "cannot verify schema field parity: jq or $schema_file unavailable in this environment"
  fi

  echo "Scenario 11: pl_classify_session — operator cwd (not under a worktrees pool, no marker) classifies operator"
  DP_DIR_T11="$TMP/dispatch-provenance-t11"; mkdir -p "$DP_DIR_T11"
  out11="$(pl_classify_session --cwd "$TMP/some/ordinary/repo" --dispatch-provenance-dir "$DP_DIR_T11")"
  rc11=$?
  if [[ "$rc11" == "1" && "$out11" == "operator" ]]; then
    pass "ordinary cwd + empty marker dir -> operator (rc=1)"
  else
    fail "expected rc=1/'operator', got rc=$rc11 out='$out11'"
  fi

  echo "Scenario 12: pl_classify_session — cwd under a .claude/worktrees/<slug> pool classifies spawned (predicate a) even with no marker"
  out12="$(pl_classify_session --cwd "$TMP/main/.claude/worktrees/agent-xyz" --dispatch-provenance-dir "$DP_DIR_T11")"
  rc12=$?
  if [[ "$rc12" == "0" && "$out12" == "spawned " ]]; then
    pass "cwd under .claude/worktrees/ -> spawned with empty ask_id (rc=0)"
  else
    fail "expected rc=0/'spawned ' (empty ask_id), got rc=$rc12 out='$out12'"
  fi

  echo "Scenario 12b: pl_classify_session — a Windows backslash-separated cwd under the pool still classifies spawned (separator-agnostic)"
  out12b="$(pl_classify_session --cwd 'C:\Users\x\main\.claude\worktrees\agent-xyz' --dispatch-provenance-dir "$DP_DIR_T11")"
  rc12b=$?
  if [[ "$rc12b" == "0" ]]; then
    pass "backslash-separated pool cwd still classifies spawned"
  else
    fail "expected rc=0 for a backslash-separated pool cwd, got rc=$rc12b out='$out12b'"
  fi

  echo "Scenario 13: pl_classify_session — a POOL-SHAPED cwd matching a dispatch-provenance marker's worktree_path classifies spawned AND resolves the dispatching ask_id (predicate b enriches predicate a with the ask_id — see Finding 3 note: predicate b's worktree_path must ALSO be pool-shaped, updated 2026-07-14)"
  DP_DIR_T13="$TMP/dispatch-provenance-t13"; mkdir -p "$DP_DIR_T13"
  printf '{"v":1,"ts":"2026-07-11T00:00:00Z","ask_id":"ask-dispatcher-1","plan_slug":"demo","task_id":"9","session_id":"sess-parent","child_id":"ss-child","worktree_path":"%s"}\n' \
    "$TMP/main13/.claude/worktrees/childwt" >"$DP_DIR_T13/marker1__20260711000000.json"
  out13="$(pl_classify_session --cwd "$TMP/main13/.claude/worktrees/childwt" --dispatch-provenance-dir "$DP_DIR_T13")"
  rc13=$?
  if [[ "$rc13" == "0" && "$out13" == "spawned ask-dispatcher-1" ]]; then
    pass "marker-matched pool-shaped cwd -> spawned with the dispatching ask_id resolved"
  else
    fail "expected rc=0/'spawned ask-dispatcher-1', got rc=$rc13 out='$out13'"
  fi

  echo "Scenario 13b: pl_classify_session — a cwd INSIDE the marker's worktree (subdirectory) also matches (path-ancestor, not exact-only)"
  out13b="$(pl_classify_session --cwd "$TMP/main13/.claude/worktrees/childwt/sub/dir" --dispatch-provenance-dir "$DP_DIR_T13")"
  rc13b=$?
  if [[ "$rc13b" == "0" && "$out13b" == "spawned ask-dispatcher-1" ]]; then
    pass "subdirectory of a marker's worktree_path also matches (path-ancestor match)"
  else
    fail "expected rc=0/'spawned ask-dispatcher-1', got rc=$rc13b out='$out13b'"
  fi

  echo "Scenario 13c: pl_classify_session — an UNRESOLVED marker (empty worktree_path, the honest PreToolUse gap) never false-matches an unrelated cwd"
  printf '{"v":1,"ts":"2026-07-11T00:00:01Z","ask_id":"ask-unresolved-1","plan_slug":"demo","task_id":"2","session_id":"sess-parent2","child_id":"ss-child2","worktree_path":""}\n' \
    >"$DP_DIR_T13/marker2__20260711000001.json"
  out13c="$(pl_classify_session --cwd "$TMP/some/totally/unrelated/path" --dispatch-provenance-dir "$DP_DIR_T13")"
  rc13c=$?
  if [[ "$rc13c" == "1" && "$out13c" == "operator" ]]; then
    pass "an UNRESOLVED (empty worktree_path) marker never matches an unrelated cwd"
  else
    fail "expected rc=1/'operator', got rc=$rc13c out='$out13c'"
  fi

  echo "Scenario 13d (FINDING 3 REGRESSION, 2026-07-14 review panel): a marker whose worktree_path is a BARE PROJECT ROOT (not itself under .claude/worktrees/ -- the exact shape a cross-repo spawn_task cwd override produces) must NEVER classify a later cwd match as spawned"
  DP_DIR_T13D="$TMP/dispatch-provenance-t13d"; mkdir -p "$DP_DIR_T13D"
  printf '{"v":1,"ts":"2026-07-11T00:00:02Z","ask_id":"ask-crossrepo-1","plan_slug":"demo","task_id":"4","session_id":"sess-parent3","child_id":"ss-child3","worktree_path":"%s"}\n' \
    "$TMP/some/other-project-root" >"$DP_DIR_T13D/marker3__20260711000002.json"
  out13d="$(pl_classify_session --cwd "$TMP/some/other-project-root" --dispatch-provenance-dir "$DP_DIR_T13D")"
  rc13d=$?
  if [[ "$rc13d" == "1" && "$out13d" == "operator" ]]; then
    pass "a non-pool (bare project-root) marker never triggers spawned for an EXACT cwd match -- an unrelated later operator session at that same root is safely classified operator, not silently dropped"
  else
    fail "expected rc=1/'operator' for a non-pool marker's project-root cwd, got rc=$rc13d out='$out13d'"
  fi

  echo "Scenario 13e: same non-pool marker, a SUBDIRECTORY of the project root also must not match (path-ancestor variant of the Finding 3 regression)"
  out13e="$(pl_classify_session --cwd "$TMP/some/other-project-root/some/subdir" --dispatch-provenance-dir "$DP_DIR_T13D")"
  rc13e=$?
  if [[ "$rc13e" == "1" && "$out13e" == "operator" ]]; then
    pass "a subdirectory of a non-pool marker's project-root also classifies operator, not spawned"
  else
    fail "expected rc=1/'operator' for a subdirectory of a non-pool marker's project-root, got rc=$rc13e out='$out13e'"
  fi

  echo "Scenario 14: pl_ask_id_for_session — deterministic (same session_id -> same ask_id every call)"
  aid14a="$(pl_ask_id_for_session "sess-determinism-check")"
  aid14b="$(pl_ask_id_for_session "sess-determinism-check")"
  if [[ -n "$aid14a" && "$aid14a" == "$aid14b" ]]; then
    pass "pl_ask_id_for_session is deterministic across repeated calls ($aid14a)"
  else
    fail "expected two identical non-empty derivations, got '$aid14a' vs '$aid14b'"
  fi

  echo "Scenario 14b: pl_ask_id_for_session — distinct session ids derive distinct ask ids"
  aid14c="$(pl_ask_id_for_session "sess-other-session")"
  if [[ "$aid14a" != "$aid14c" ]]; then
    pass "distinct session_ids derive distinct ask_ids ($aid14a != $aid14c)"
  else
    fail "expected distinct derivations, both were '$aid14a'"
  fi

  echo "Scenario 14c: pl_ask_id_for_session — empty session_id derives empty (no fabricated ask)"
  aid14d="$(pl_ask_id_for_session "")"
  if [[ -z "$aid14d" ]]; then
    pass "empty session_id derives empty ask_id, never a fabricated value"
  else
    fail "expected empty derivation for empty session_id, got '$aid14d'"
  fi

  echo "Scenario 15: pl_classify_session — DISPATCH_PROVENANCE_STATE_DIR env resolution matches scripts/dispatch-provenance.sh's own (population-parity plumbing, not just the predicate logic)"
  DP_ENV_T15="$TMP/dispatch-provenance-env-t15"; mkdir -p "$DP_ENV_T15"
  printf '{"v":1,"ts":"2026-07-11T00:00:02Z","ask_id":"ask-env-1","plan_slug":"demo","task_id":"1","session_id":"s","child_id":"c","worktree_path":"%s"}\n' \
    "$TMP/env-root/.claude/worktrees/env-wt" >"$DP_ENV_T15/m__20260711000002.json"
  out15="$(DISPATCH_PROVENANCE_STATE_DIR="$DP_ENV_T15" pl_classify_session --cwd "$TMP/env-root/.claude/worktrees/env-wt")"
  rc15=$?
  if [[ "$rc15" == "0" && "$out15" == "spawned ask-env-1" ]]; then
    pass "DISPATCH_PROVENANCE_STATE_DIR env override resolves without an explicit --dispatch-provenance-dir flag"
  else
    fail "expected rc=0/'spawned ask-env-1' via env-only override, got rc=$rc15 out='$out15'"
  fi

  echo "Scenario 16 (FINDING 1 REGRESSION, 2026-07-14 review panel): pl_classify_session scans only the newest PL_DISPATCH_PROVENANCE_SCAN_LIMIT markers, not the entire (potentially unbounded) dispatch-provenance directory"
  # NOTE on what is asserted here. Both target cwds below are pool-shaped
  # (post-Finding-3, ONLY a `.claude/worktrees/` marker can ever match), so
  # predicate (a) alone already makes both classify `spawned` regardless of
  # any marker. The signal the SCAN actually controls is therefore the
  # RESOLVED ASK_ID: a marker inside the scan window resolves it
  # ("spawned <ask_id>"); a marker outside the window is never read, so the
  # ask_id comes back EMPTY ("spawned "). That is the precise, non-vacuous
  # observable for "was this marker scanned or not".
  DP_DIR_T16="$TMP/dispatch-provenance-t16"; mkdir -p "$DP_DIR_T16"
  T16_STALE_WT="$TMP/main16/.claude/worktrees/stale-target"
  T16_LIVE_WT="$TMP/main16/.claude/worktrees/live-target"
  # 500 unrelated, non-matching dummy markers with sequential embedded
  # timestamps -- enough to fill the default 200-wide window several times
  # over, so the stale marker below genuinely falls outside it.
  for i in $(seq 1 500); do
    ts16=$(printf '2020%010d' "$i")
    printf '{"v":1,"ts":"x","ask_id":"ask-dummy-%s","plan_slug":"d","task_id":"1","session_id":"s","child_id":"c","worktree_path":"%s"}\n' \
      "$i" "$TMP/main16/.claude/worktrees/dummy-$i" >"$DP_DIR_T16/dummy${i}__${ts16}.json"
  done
  # The OLDEST marker of all 502 -- an EXHAUSTIVE scan would read it and
  # resolve its ask_id; a bounded newest-N scan (default 200) must never
  # reach it.
  printf '{"v":1,"ts":"x","ask_id":"ask-stale-match","plan_slug":"d","task_id":"1","session_id":"s","child_id":"c","worktree_path":"%s"}\n' \
    "$T16_STALE_WT" >"$DP_DIR_T16/stalematch__00000000000001.json"
  # The NEWEST marker of all 502 -- must still be found (bounded != broken).
  printf '{"v":1,"ts":"x","ask_id":"ask-live-match","plan_slug":"d","task_id":"1","session_id":"s","child_id":"c","worktree_path":"%s"}\n' \
    "$T16_LIVE_WT" >"$DP_DIR_T16/livematch__99999999999999.json"

  out16a="$(pl_classify_session --cwd "$T16_STALE_WT" --dispatch-provenance-dir "$DP_DIR_T16")"
  rc16a=$?
  if [[ "$rc16a" == "0" && "$out16a" == "spawned " ]]; then
    pass "the oldest-of-502 marker (outside the bounded newest-N window) was NEVER READ -- its ask_id is unresolved (empty), direct proof the scan is bounded and not O(directory size)"
  else
    fail "expected rc=0/'spawned ' (empty ask_id: marker outside the bounded scan window must not be read; an unbounded scan would have resolved 'ask-stale-match'), got rc=$rc16a out='$out16a'"
  fi

  out16b="$(pl_classify_session --cwd "$T16_LIVE_WT" --dispatch-provenance-dir "$DP_DIR_T16")"
  rc16b=$?
  if [[ "$rc16b" == "0" && "$out16b" == "spawned ask-live-match" ]]; then
    pass "the newest-of-502 marker IS still read and its ask_id resolved, despite the directory holding 500+ markers (the bound preserves correctness for a genuinely live child worktree)"
  else
    fail "expected rc=0/'spawned ask-live-match' for the newest marker in a 502-marker directory, got rc=$rc16b out='$out16b'"
  fi

  echo "Scenario 16b: an explicit PL_DISPATCH_PROVENANCE_SCAN_LIMIT override widens the window -- confirms 16a's exclusion is the scan LIMIT doing its job, not an unrelated bug"
  out16c="$(PL_DISPATCH_PROVENANCE_SCAN_LIMIT=1000 pl_classify_session --cwd "$T16_STALE_WT" --dispatch-provenance-dir "$DP_DIR_T16")"
  rc16c=$?
  if [[ "$rc16c" == "0" && "$out16c" == "spawned ask-stale-match" ]]; then
    pass "widening PL_DISPATCH_PROVENANCE_SCAN_LIMIT past the directory size DOES resolve the oldest marker's ask_id -- so 16a's empty ask_id is provably the bound, not a broken matcher"
  else
    fail "expected rc=0/'spawned ask-stale-match' with an explicitly widened scan limit, got rc=$rc16c out='$out16c'"
  fi

  rm -rf "$TMP" 2>/dev/null || true

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then exit 0; else exit 1; fi
fi
