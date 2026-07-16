#!/bin/bash
# dispatch-provenance.sh — writer CLI for the DISPATCH-PROVENANCE MARKER
# (ask-rooted-workstreams-p1, Task 3: "Dispatch emission splice").
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# Task 9's spawned-session classification guard needs a signal beyond "cwd
# is under .claude/worktrees/": a marker recorded AT DISPATCH TIME that
# pre-attaches a soon-to-exist child session to the DISPATCHING ask, so a
# spawned session can ATTACH instead of registering a brand-new ask
# (plan Edge Cases: "Builder/sub-agent sessions: never register asks; they
# attach via dispatch provenance"). Verified 2026-07-10: neither
# scripts/spawn-worktree.sh nor scripts/nl.sh writes any such marker today —
# this script is the ONE writer; Task 9 is the (future, out-of-scope-here)
# reader.
#
# adapters/claude-code/hooks/workstreams-emit.sh's --on-builder-dispatch
# (PreToolUse Task|Agent|Workflow) and --on-spawn (PreToolUse
# mcp__ccd_session__spawn_task | mcp__ccd_session_mgmt__start_code_task)
# splices are the ONLY callers of this CLI (see their
# `_emit_dispatch_provenance` helper) — mirrors the progress-log.sh /
# hooks/lib/progress-log-lib.sh script+lib split so the marker FORMAT has
# one implementation, callable as its own OS process (consistent with every
# other splice-calls-a-standalone-CLI convention in this plan).
#
# ============================================================
# CONTRACT (Task 9 depends on this exact shape — do not rename a field
# without updating Task 9's reader once it lands)
# ============================================================
#
#   dispatch-provenance.sh write --ask <id> --plan-slug <slug>
#                                 --task-id <id> --session-id <dispatching-sid>
#                                 --child-id <synthetic-child-node-id>
#                                 [--worktree <path>]
#     Writes ONE JSON marker file under the state dir (see SANDBOXING),
#     named `<sanitized-worktree-or-UNRESOLVED>__<dispatch-ts-compact>.json`
#     — best-effort "keyed by target worktree path + dispatch ts" per the
#     plan's Task 3 spec. Fields:
#       {v, ts, ask_id, plan_slug, task_id, session_id, child_id,
#        worktree_path}
#     `worktree_path` is "" when --worktree was not supplied. THIS IS AN
#     HONEST GAP, not a guess: the true child worktree path is not visible
#     to a PreToolUse hook for the generic Task/Agent/Workflow dispatch
#     surface — harness/SDK isolation ("isolation: worktree") creates the
#     worktree as part of EXECUTING the tool call and only returns the path
#     in the PostToolUse result. See workstreams-emit.sh's
#     `_emit_dispatch_provenance` header comment for the full reasoning and
#     which callers CAN supply --worktree (the spawn_task `cwd` override,
#     and only when that hint is itself a `.claude/worktrees/` pool path —
#     see that header's FINDING 3 note).
#     NEVER BLOCKS the caller: every failure path is swallowed, exit 0 on
#     every code path (writer semantics, plan constraint 5).
#     After writing, prunes the marker directory (FINDING 1, 2026-07-14
#     review panel — see `_dp_prune`'s own header below): deletes markers
#     older than DISPATCH_PROVENANCE_TTL_DAYS (default 14), then caps the
#     survivors to the newest DISPATCH_PROVENANCE_MAX_MARKERS (default
#     200). Keeps progress-log-lib.sh's `pl_classify_session` scan (which
#     reads this same directory on every SessionStart/first prompt) from
#     paying unbounded latency as the estate ages.
#
#   dispatch-provenance.sh --self-test
#     Self-contained assertion suite, entirely sandboxed (see SANDBOXING) —
#     never touches the real machine's dispatch-provenance state.
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST / explicit override — constraint 4)
# ============================================================
#
# Resolution order for the state directory:
#   1. DISPATCH_PROVENANCE_STATE_DIR env var, if set (explicit override —
#      used by workstreams-emit.sh's own self-test, which sets
#      HARNESS_SELFTEST_DIR and exports it to every child `bash "$SELF"`
#      process; this script also honors HARNESS_SELFTEST_DIR directly so it
#      sandboxes correctly even when invoked standalone).
#   2. HARNESS_SELFTEST=1 and DISPATCH_PROVENANCE_STATE_DIR unset -> a
#      sandboxed dir under HARNESS_SELFTEST_DIR (or a PID-scoped tmp path).
#   3. Default: $HOME/.claude/state/dispatch-provenance — the real,
#      production, cross-project state dir (matches progress-logs/
#      ask-registry.jsonl/needs-you convention).

set -u

# ----------------------------------------------------------------------
# _dp_state_dir — resolve the dispatch-provenance state directory. Always
# prints a non-empty path; never fails.
# ----------------------------------------------------------------------
_dp_state_dir() {
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
# _dp_sanitize <raw> — filesystem-safe single path component for the marker
# filename (same allowlist technique as progress-log-lib.sh's
# _pl_sanitize_ask_id — every char outside [A-Za-z0-9._-] -> `_`). Empty raw
# -> the literal "UNRESOLVED" token (the honest not-yet-known worktree case,
# never a guess).
# ----------------------------------------------------------------------
_dp_sanitize() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    printf 'UNRESOLVED'
    return 0
  fi
  local s="${raw//[!A-Za-z0-9._-]/_}"
  [[ -z "$s" ]] && s="UNRESOLVED"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# _dp_json_escape <string> — same technique as progress-log-lib.sh's
# _pl_json_escape (no jq dependency on the write path).
# ----------------------------------------------------------------------
_dp_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  local nl=$'\n' cr=$'\r' tab=$'\t'
  s="${s//$nl/\\n}"
  s="${s//$cr/\\r}"
  s="${s//$tab/\\t}"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# _dp_prune <dir> — bound the marker directory's growth (FINDING 1,
# 2026-07-14 ask-splice review panel). Markers are written per plan-rooted
# dispatch and were NEVER pruned, so progress-log-lib.sh's
# pl_classify_session -- which runs on every SessionStart and first
# UserPromptSubmit -- paid unbounded, ever-growing, fork-heavy synchronous
# latency as the estate aged (precedent: session-start-digest.sh already
# BACKGROUNDS an analogous heartbeat-reap scan for this identical
# anti-pattern). Runs at the end of every `write`, so the directory is
# self-bounding without a separate cron/reap process. Best-effort, NEVER
# BLOCKS the caller (writer semantics): every failure here is swallowed.
#
#   TTL pass:  delete any marker whose embedded ts_compact is older than
#              DISPATCH_PROVENANCE_TTL_DAYS (default 14).
#   CAP pass:  of what survives, keep only the newest
#              DISPATCH_PROVENANCE_MAX_MARKERS (default 200) by
#              ts_compact; delete the rest.
#
# Timestamps are parsed from the FILENAME (not mtime) -- same convention
# install.sh's prune_stale_backups already uses ("parse the timestamp from
# the directory name, not mtime, which is unreliable"), and it also lets
# the TTL comparison be a pure STRING compare: ts_compact is a fixed-width
# 14-digit YYYYMMDDHHMMSS (from `date -u '+%Y-%m-%dT%H:%M:%SZ' | tr -cd
# '0-9'`), so lexicographic order IS chronological order. That matters:
# this prune runs inside a PreToolUse-dispatched hook, so it must not fork
# per marker (a `date` call per file would make the prune itself the
# fork-heavy hot-path cost Finding 1 exists to remove). Total forks here:
# ONE `date` for the cutoff + ONE `sort` for the cap pass, flat.
# A marker whose filename doesn't carry a recognizable numeric ts_compact
# (any foreign or malformed file in this dir) is never touched by either
# pass -- caution favors leaking over misdeleting.
# ----------------------------------------------------------------------
_dp_prune() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  local ttl_days="${DISPATCH_PROVENANCE_TTL_DAYS:-14}"
  local max_markers="${DISPATCH_PROVENANCE_MAX_MARKERS:-200}"

  # Cutoff as a 14-digit compact stamp (ONE fork). Bail out silently if the
  # platform's `date` can't do relative arithmetic -- never block a write.
  local cutoff_compact
  cutoff_compact="$(date -u -d "${ttl_days} days ago" '+%Y%m%d%H%M%S' 2>/dev/null \
    || date -u -v-"${ttl_days}"d '+%Y%m%d%H%M%S' 2>/dev/null || echo "")"

  local f base ts
  local entries="" count=0

  # ---- TTL pass (zero forks: fixed-width lexicographic compare) ----
  if [[ -n "$cutoff_compact" ]]; then
    for f in "$dir"/*.json; do
      [[ -f "$f" ]] || continue
      base="${f##*/}"
      base="${base%.json}"
      ts="${base##*__}"
      # Only a full 14-digit stamp is comparable against the cutoff; a
      # shorter/garbled one is left alone (never misdelete).
      [[ "$ts" =~ ^[0-9]{14}$ ]] || continue
      if [[ "$ts" < "$cutoff_compact" ]]; then
        rm -f "$f" 2>/dev/null || true
      fi
    done
  fi

  # ---- CAP pass (re-glob: the TTL pass above may have deleted some) ----
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    base="${f##*/}"
    base="${base%.json}"
    ts="${base##*__}"
    [[ "$ts" =~ ^[0-9]{8,}$ ]] || continue
    entries="${entries}${ts}"$'\t'"${f}"$'\n'
    count=$((count + 1))
  done
  [[ "$count" -le "$max_markers" ]] && return 0

  local i=0 ts_s path_s
  while IFS=$'\t' read -r ts_s path_s; do
    [[ -n "$ts_s" ]] || continue
    i=$((i + 1))
    if [[ "$i" -gt "$max_markers" ]]; then
      rm -f "$path_s" 2>/dev/null || true
    fi
  done < <(printf '%s' "$entries" | sort -r -t $'\t' -k1,1)
  return 0
}

# ----------------------------------------------------------------------
# cmd_write — parse `write` args and emit ONE marker file. Never blocks:
# every failure path returns 0 without printing (mirrors pl_emit).
# ----------------------------------------------------------------------
cmd_write() {
  local ask="" plan_slug="" task_id="" session_id="" child_id="" worktree=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask) ask="${2:-}"; shift 2 ;;
      --plan-slug) plan_slug="${2:-}"; shift 2 ;;
      --task-id) task_id="${2:-}"; shift 2 ;;
      --session-id) session_id="${2:-}"; shift 2 ;;
      --child-id) child_id="${2:-}"; shift 2 ;;
      --worktree) worktree="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local dir; dir="$(_dp_state_dir)"
  mkdir -p "$dir" 2>/dev/null || return 0

  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  local ts_compact; ts_compact="$(printf '%s' "$ts" | tr -cd '0-9')"
  [[ -z "$ts_compact" ]] && ts_compact="$$"

  local wt_key; wt_key="$(_dp_sanitize "$worktree")"
  local fname="${wt_key}__${ts_compact}.json"
  local path="$dir/$fname"

  local ask_e slug_e task_e sid_e child_e wt_e
  ask_e="$(_dp_json_escape "$ask")"
  slug_e="$(_dp_json_escape "$plan_slug")"
  task_e="$(_dp_json_escape "$task_id")"
  sid_e="$(_dp_json_escape "$session_id")"
  child_e="$(_dp_json_escape "$child_id")"
  wt_e="$(_dp_json_escape "$worktree")"

  local json
  json="$(printf '{"v":1,"ts":"%s","ask_id":"%s","plan_slug":"%s","task_id":"%s","session_id":"%s","child_id":"%s","worktree_path":"%s"}' \
    "$ts" "$ask_e" "$slug_e" "$task_e" "$sid_e" "$child_e" "$wt_e")"

  printf '%s\n' "$json" >"$path" 2>/dev/null || return 0

  # FINDING 1 fix (2026-07-14 review panel): bound the directory's growth
  # on every write so it never accumulates unboundedly (see _dp_prune
  # above). Best-effort/non-fatal -- a prune failure never blocks the
  # caller or suppresses the just-written path below.
  _dp_prune "$dir" 2>/dev/null || true

  printf '%s\n' "$path"
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
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'dpst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    return 1
  fi

  export HARNESS_SELFTEST=1
  export DISPATCH_PROVENANCE_STATE_DIR="$TMP/dp"
  mkdir -p "$DISPATCH_PROVENANCE_STATE_DIR"

  echo "Scenario A: write with --worktree creates a marker keyed by the sanitized worktree path + a ts, with every field round-tripping"
  local out_a
  out_a="$(cmd_write --ask "ask-1" --plan-slug "demo-plan" --task-id "3" \
    --session-id "sess-A" --child-id "ss-childA" --worktree "/tmp/repo/.claude/worktrees/agent-abc")"
  if [[ -f "$out_a" ]]; then
    pass "write printed a path to an existing marker file"
  else
    fail "expected write to print an existing file path, got '$out_a'"
  fi
  case "$(basename "$out_a" 2>/dev/null || echo)" in
    _tmp_repo_.claude_worktrees_agent-abc__*) pass "marker filename is keyed by the sanitized worktree path" ;;
    *) fail "marker filename does not carry the sanitized worktree path: $(basename "$out_a" 2>/dev/null)" ;;
  esac
  if command -v jq >/dev/null 2>&1; then
    if jq -e . "$out_a" >/dev/null 2>&1; then pass "marker is valid JSON"; else fail "marker is NOT valid JSON"; fi
    wtv="$(jq -r '.worktree_path' "$out_a" 2>/dev/null | tr -d '\r')"
    [[ "$wtv" == "/tmp/repo/.claude/worktrees/agent-abc" ]] && pass "worktree_path round-trips unescaped" || fail "worktree_path mismatch: '$wtv'"
    askv="$(jq -r '.ask_id' "$out_a" 2>/dev/null | tr -d '\r')"
    slugv="$(jq -r '.plan_slug' "$out_a" 2>/dev/null | tr -d '\r')"
    taskv="$(jq -r '.task_id' "$out_a" 2>/dev/null | tr -d '\r')"
    sidv="$(jq -r '.session_id' "$out_a" 2>/dev/null | tr -d '\r')"
    childv="$(jq -r '.child_id' "$out_a" 2>/dev/null | tr -d '\r')"
    if [[ "$askv" == "ask-1" && "$slugv" == "demo-plan" && "$taskv" == "3" && "$sidv" == "sess-A" && "$childv" == "ss-childA" ]]; then
      pass "ask_id/plan_slug/task_id/session_id/child_id all round-trip"
    else
      fail "field mismatch: ask=$askv slug=$slugv task=$taskv sid=$sidv child=$childv"
    fi
  fi

  echo "Scenario B: write WITHOUT --worktree is the HONEST unresolved case -- filename says UNRESOLVED, worktree_path is empty, never a guess"
  local out_b
  out_b="$(cmd_write --ask "ask-2" --plan-slug "demo-plan-2" --task-id "5" \
    --session-id "sess-B" --child-id "ss-childB")"
  case "$(basename "$out_b" 2>/dev/null || echo)" in
    UNRESOLVED__*) pass "marker filename honestly says UNRESOLVED when no worktree hint was supplied" ;;
    *) fail "expected UNRESOLVED-prefixed filename, got $(basename "$out_b" 2>/dev/null)" ;;
  esac
  if command -v jq >/dev/null 2>&1; then
    wtv2="$(jq -r '.worktree_path' "$out_b" 2>/dev/null | tr -d '\r')"
    [[ "$wtv2" == "" ]] && pass "worktree_path is the empty string, not a guessed value" || fail "worktree_path should be empty, got '$wtv2'"
  fi

  echo "Scenario C: two writes (same ask, different dispatch ts) land as TWO DISTINCT marker files -- a re-dispatch is a new dispatch, never silently collapsed"
  sleep 1.1 2>/dev/null || true
  local out_c
  out_c="$(cmd_write --ask "ask-2" --plan-slug "demo-plan-2" --task-id "5" \
    --session-id "sess-B2" --child-id "ss-childB2")"
  if [[ "$out_b" != "$out_c" ]]; then
    pass "distinct dispatch timestamps produced distinct marker files"
  else
    fail "expected two distinct marker files, got the same path twice: $out_b"
  fi

  echo "Scenario D: sandbox-only writes -- self-test never touched a real ~/.claude-shaped path"
  if [[ ! -e "$TMP/.claude" ]]; then
    pass "self-test wrote only under its own sandboxed tempdir"
  else
    fail "self-test unexpectedly created a .claude path under $TMP"
  fi

  echo "Scenario E: never blocks -- a write with NO args still exits 0 and does not crash"
  if cmd_write >/dev/null 2>&1; then
    pass "write with no args still exits 0 (writer semantics: never blocks the caller)"
  else
    fail "write with no args should still exit 0"
  fi

  echo "Scenario F (FINDING 1 REGRESSION, 2026-07-14 review panel): a marker older than DISPATCH_PROVENANCE_TTL_DAYS is pruned by the very next write"
  local old_ts_human old_ts_compact stale_marker
  old_ts_human="$(date -u -d '20 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-20d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  old_ts_compact="$(printf '%s' "$old_ts_human" | tr -cd '0-9')"
  stale_marker="$DISPATCH_PROVENANCE_STATE_DIR/stalewt__${old_ts_compact}.json"
  printf '{"v":1,"ts":"%s","ask_id":"ask-stale","plan_slug":"p","task_id":"1","session_id":"s","child_id":"c","worktree_path":""}\n' \
    "$old_ts_human" >"$stale_marker"
  if [[ ! -f "$stale_marker" ]]; then
    fail "Scenario F setup: could not create the stale fixture marker"
  else
    cmd_write --ask "ask-fresh-f" --plan-slug "p" --task-id "2" --session-id "s2" --child-id "c2" >/dev/null
    if [[ -f "$stale_marker" ]]; then
      fail "Scenario F: a marker older than the default 14-day TTL (fixture is 20 days old) survived a subsequent write -- prune did not fire"
    else
      pass "a marker older than DISPATCH_PROVENANCE_TTL_DAYS (default 14d; fixture 20d old) was pruned by the next write"
    fi
  fi

  echo "Scenario G (FINDING 1 REGRESSION): DISPATCH_PROVENANCE_MAX_MARKERS caps the directory to the newest N markers, regardless of TTL"
  local capdir="$TMP/dp-cap"; mkdir -p "$capdir"
  local now_epoch_g; now_epoch_g=$(date -u +%s 2>/dev/null)
  local ig eg human_g ts_g
  for ig in $(seq 1 15); do
    eg=$(( now_epoch_g - ig ))
    human_g="$(date -u -d "@$eg" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -r "$eg" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
    ts_g="$(printf '%s' "$human_g" | tr -cd '0-9')"
    printf '{"v":1,"ts":"%s","ask_id":"ask-g-%s","plan_slug":"p","task_id":"1","session_id":"s","child_id":"c","worktree_path":""}\n' \
      "$human_g" "$ig" >"$capdir/capwt${ig}__${ts_g}.json"
  done
  local precount_g; precount_g=$(ls "$capdir"/*.json 2>/dev/null | wc -l | tr -d ' ')
  ( export DISPATCH_PROVENANCE_STATE_DIR="$capdir"
    export DISPATCH_PROVENANCE_MAX_MARKERS=5
    cmd_write --ask "ask-g-new" --plan-slug "p" --task-id "2" --session-id "s-new" --child-id "c-new" >/dev/null )
  local postcount_g; postcount_g=$(ls "$capdir"/*.json 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$precount_g" == "15" && "$postcount_g" == "5" ]]; then
    pass "cap pass pruned a 16-marker directory down to the newest 5 (DISPATCH_PROVENANCE_MAX_MARKERS override)"
  else
    fail "expected 15 markers pre-write and 5 post-write (cap=5), got pre=$precount_g post=$postcount_g"
  fi
  local survivors_ok=1 isv
  for isv in 1 2 3 4; do
    ls "$capdir"/capwt${isv}__*.json >/dev/null 2>&1 || survivors_ok=0
  done
  for isv in 5 6 7 8 9 10 11 12 13 14 15; do
    if ls "$capdir"/capwt${isv}__*.json >/dev/null 2>&1; then survivors_ok=0; fi
  done
  if [[ "$survivors_ok" == "1" ]]; then
    pass "the cap pass kept exactly the newest 4 pre-existing markers and pruned the older 11 (plus the brand-new 5th)"
  else
    fail "cap pass did not keep exactly the expected newest pre-existing markers"
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
  write)
    shift
    cmd_write "$@"
    exit 0
    ;;
  --self-test|--selftest|selftest|self-test)
    cmd_selftest
    exit $?
    ;;
  -h|--help|"")
    cat <<'USAGE'
dispatch-provenance.sh — DISPATCH-PROVENANCE MARKER writer CLI
(ask-rooted-workstreams-p1, Task 3)

Verbs:
  write --ask <id> --plan-slug <slug> --task-id <id>
        --session-id <dispatching-session-id> --child-id <synthetic-node-id>
        [--worktree <path>]
                          Write ONE dispatch-provenance marker file. Never
                          blocks; exit 0 always. Prints the written path.
  --self-test             Run the self-test suite (sandboxed).

See adapters/claude-code/hooks/workstreams-emit.sh's `_emit_dispatch_provenance`
for the caller (the --on-builder-dispatch / --on-spawn splices) and this
file's own header for the full marker schema Task 9's guard reads.
USAGE
    exit 0
    ;;
  *)
    echo "dispatch-provenance.sh: unknown verb '$1' (run without args for usage; never blocks a caller since this is a standalone script)" >&2
    exit 0
    ;;
esac
