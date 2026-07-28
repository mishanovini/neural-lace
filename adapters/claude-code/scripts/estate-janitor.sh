#!/bin/bash
# estate-janitor.sh — Accountable Estate program, T1 (docs/plans/
# accountable-estate-program-2026-07.md): the READ-ONLY estate inventory
# reducer. Corresponds to the architecture review's "Revised build order,
# Slice 1" (docs/reviews/2026-07-27-accountable-estate-architecture-review.md):
# "new janitor task reduces already-existing truth (heartbeats, process
# table, `git worktree list`, signal-ledger tail, ask-registry) into
# snapshot.json ... Zero write-path changes, zero migration."
#
# ============================================================
# WHY THIS EXISTS / WHAT IT IS NOT
# ============================================================
#
# This is NOT the janitor design's eventual accountability authority (F3:
# "flag then stop unattributable work, SLA advance, prune" — that needs a
# reviewed contract and lands in T3/T4). This is NOT the resource governor
# (F1/F2/F3: admission lib — T3). This slice does exactly one thing:
# REDUCE existing ground truth into one snapshot file. It never mutates
# anything it reads, never kills a process, never touches a worktree or
# branch, never writes to the heartbeat/ask-registry/signal-ledger stores
# it reads FROM. Per the plan's Program rule 4 ("Observe-first before
# every enforcement flip") and the operator directive in the design's
# §6b: "Nothing scheduled is ever an LLM... the ONLY scheduled work is
# deterministic bash for absence detection... + reduction to
# snapshot/brief."
#
# Sources reduced (all read-only):
#   1. Session heartbeats  — ${HEARTBEAT_STATE_DIR:-~/.claude/state/heartbeats}/*.json
#      via hooks/lib/session-heartbeat-lib.sh's hb_classify (the SAME
#      classification oracle session-heartbeat.sh/harness-doctor.sh use —
#      never a second implementation of "is this session alive").
#   2. Process table — bash.exe/claude.exe counts via hooks/lib/
#      perf-tick-snapshot.sh's pts_collect_processes (the SAME wmic-based
#      oracle P2 uses; this script sources it for the READ-ONLY collector
#      function only — it never calls pts_reap_orphans, which is a
#      mutation-capable function even though default-unarmed. Zero
#      mutation risk by construction, not by convention.)
#   3. `git worktree list --porcelain` across CONFIGURED repos (see REPO
#      LIST CONFIG below) — reduced to a worktree table + the orphaned-
#      worktree/orphaned-branch found-lists (see ORPHAN DEFINITION below).
#   4. Signal-ledger tail — ${SIGNAL_LEDGER_PATH:-~/.claude/state/signal-ledger.jsonl},
#      last N lines verbatim (already-valid JSONL per signal-ledger.sh's
#      writer contract).
#   5. Ask-registry — ${ASK_REGISTRY_STATE_DIR:-~/.claude/state}/ask-registry.jsonl,
#      folded to one row per ask_id (SIMPLIFIED fold — see ASK FOLD NOTE).
#
# ============================================================
# REPO LIST CONFIG (mirrors pr-health-snapshot.sh's active-repos.txt
# convention exactly, but this one holds ABSOLUTE LOCAL PATHS, not repo
# short-names — `git worktree list` needs a real path, not a gh owner/repo
# string)
# ============================================================
#
# Resolution order:
#   1. ESTATE_JANITOR_REPOS_CONFIG env var — an explicit path to a repo-list
#      file (self-test override, or an operator wanting a non-default
#      location).
#   2. ~/.claude/config/estate-repos.txt, if present — one absolute repo
#      root per line; blank lines and `#` comments ignored (same shape as
#      examples/active-repos.example.txt).
#   3. Fallback: just THIS repo's main checkout (nl_main_checkout_root(),
#      else nl_repo_root(), else $PWD) — so a machine with no config file
#      still gets a real, honest, single-repo inventory rather than an
#      empty one. This differs from pr-health-snapshot's "no-op until
#      configured" because THIS script's whole job is estate inventory —
#      an empty inventory on an unconfigured machine would silently fail
#      the outcome metric ("what is running... answerable from one
#      surface"), whereas pr-health-snapshot's no-op is safe (nothing to
#      report is an honest answer for a report that only ever ADDS rows).
#
# Ship an example at adapters/claude-code/examples/estate-repos.example.txt
# (copy to ~/.claude/config/estate-repos.txt and edit).
#
# ============================================================
# ORPHAN DEFINITION (mechanical, not a judgment call)
# ============================================================
#
# orphaned_worktree: a row from `git worktree list` (any configured repo,
# excluding that repo's own main/first row) for which NO heartbeat file
# resolves (via hb_classify) to "live" with a matching worktree_root
# (path-normalized — see _ej_norm_path: backslash/forward-slash and
# drive-letter-case differences are the ONLY normalization applied; this
# is not a fuzzy match). "No live owner" literally: stale/crashed/missing
# heartbeats do not count as ownership, matching the plan's own wording
# ("worktrees/branches with no live owner").
#
# orphaned_branch: a local branch (any configured repo) that is NOT the
# repo's default branch (master/main/trunk) and is NOT currently checked
# out by ANY worktree in that repo's `git worktree list` output. In this
# harness's own convention, a worktree is how a branch becomes "owned" by
# a session (spawn-worktree.sh's one-worktree-one-branch pattern) — a
# branch with no worktree has, by construction, no live session touching
# it. This is a FOUND-LIST (mechanical fact), not a delete recommendation;
# T4's closer is where "prune" lives, not here.
#
# ============================================================
# ASK FOLD NOTE (simplified — NOT the full reader contract)
# ============================================================
#
# ask-registry.sh's own header names the FULL fold contract (per-field
# last-non-empty-wins, operator-beats-auto title precedence, title-bearing
# record-type allowlist) as "Task 11/13's server-side reader... the real
# consumer going forward." Re-implementing that whole contract here (in
# bash, for a slice whose only job is a daily-brief-scale ask list) would
# be redundant machinery for a low-stakes read. This script instead runs a
# SIMPLIFIED jq fold (operator-titled summary wins over auto, else latest
# non-empty summary from created/summary_updated records only, latest
# non-empty status) — honestly labeled `asks_fold: "simplified"` in the
# snapshot so no downstream reader mistakes this for the frozen contract.
# Requires jq; degrades to `asks:[] asks_degraded:true` without it (never
# a crash, never a wrong answer presented as right).
#
# ============================================================
# DEGRADATION CONTRACT (binding — every source above)
# ============================================================
#
# Every external read (a missing dir, an absent binary, a repo that no
# longer exists on disk, wmic unavailable, jq unavailable) degrades to a
# named `*_degraded: true` field on THAT section only — it never crashes
# the whole run, and it never fabricates data. Exit code is always 0
# except an unrecoverable inability to WRITE the snapshot file itself
# (disk full, permissions) or --self-test failure.
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST / explicit overrides — house convention)
# ============================================================
#
# Every state path below has an explicit env override (used by
# --self-test AND by an operator wanting a non-default location) and an
# HARNESS_SELFTEST=1 sandboxed fallback under ${TMPDIR:-/tmp}, so
# --self-test NEVER writes to a real ~/.claude path regardless of $HOME.
# Double-guard (house pattern, workstreams-read.sh:63-68 / workstreams-
# task-binding.sh:76): the sandboxing check keys on BOTH
# HARNESS_SELFTEST=1 AND a direct `--self-test` argv, because a bare
# `bash estate-janitor.sh --self-test` evaluates env-only guards before
# the self-test body itself would have exported HARNESS_SELFTEST.
#
#   ESTATE_STATE_DIR              snapshot.json's directory
#   HEARTBEAT_STATE_DIR           (inherited contract, session-heartbeat-lib.sh)
#   SIGNAL_LEDGER_PATH            (inherited contract, signal-ledger.sh)
#   ASK_REGISTRY_STATE_DIR        (inherited contract, ask-registry.sh)
#   ESTATE_JANITOR_REPOS_CONFIG   repo-list file override
#
# ============================================================
# USAGE
# ============================================================
#   estate-janitor.sh [run]      collect everything, write snapshot.json,
#                                 print its path (default verb).
#   estate-janitor.sh --self-test
#
# Output: ${ESTATE_STATE_DIR:-~/.claude/state/estate}/snapshot.json

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
MODE="${1:-run}"

# Double-guard (house pattern) — key on BOTH the env var and a direct
# --self-test argv so a bare invocation sandboxes correctly before the
# self-test body itself exports HARNESS_SELFTEST.
if [[ "${HARNESS_SELFTEST:-0}" == "1" ]] || [[ "$MODE" == "--self-test" ]]; then
  export HARNESS_SELFTEST=1
fi

# ---- best-effort sourcing of shared oracles (never fatal if absent) -----
# shellcheck disable=SC1091
[[ -f "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" ]] && source "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null
# shellcheck disable=SC1091
[[ -f "$SCRIPT_DIR/../hooks/lib/session-heartbeat-lib.sh" ]] && source "$SCRIPT_DIR/../hooks/lib/session-heartbeat-lib.sh" 2>/dev/null
# shellcheck disable=SC1091
[[ -f "$SCRIPT_DIR/../hooks/lib/perf-tick-snapshot.sh" ]] && source "$SCRIPT_DIR/../hooks/lib/perf-tick-snapshot.sh" 2>/dev/null

# ----------------------------------------------------------------------
# _ej_json_escape <string> — same technique as every other flat-JSON
# writer in this repo (signal-ledger.sh / session-heartbeat-lib.sh).
# ----------------------------------------------------------------------
_ej_json_escape() {
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
# _ej_norm_path <path> — comparison-only normalization: backslashes ->
# forward slashes, `C:` drive prefix -> lowercased, whole string
# lowercased, trailing slash trimmed. NEVER used for display (original
# strings are always what gets written to the snapshot) — only for
# path-equality tests (heartbeat worktree_root vs `git worktree list`'s
# own path form, which disagree in exactly these two ways on Windows/
# Git-Bash — same platform quirk install-coord-sync-task.ps1's
# ConvertTo-Posix documents from the other direction).
# ----------------------------------------------------------------------
_ej_norm_path() {
  local p="$1"
  p="${p//\\//}"
  if [[ "$p" =~ ^([A-Za-z]):(.*)$ ]]; then
    local drive="${BASH_REMATCH[1],,}"
    p="/${drive}${BASH_REMATCH[2]}"
  fi
  p="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
  p="${p%/}"
  printf '%s' "$p"
}

# ----------------------------------------------------------------------
# State dir resolvers (house convention: explicit override > selftest
# sandbox > production default).
# ----------------------------------------------------------------------
ej_state_dir() {
  if [[ -n "${ESTATE_STATE_DIR:-}" ]]; then
    printf '%s' "$ESTATE_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/estate-janitor-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/estate' "${HOME:-$PWD}"
}

ej_snapshot_path() { printf '%s/snapshot.json' "$(ej_state_dir)"; }

_ej_heartbeat_dir() {
  if [[ -n "${HEARTBEAT_STATE_DIR:-}" ]]; then
    printf '%s' "$HEARTBEAT_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/heartbeat-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/heartbeats' "${HOME:-$PWD}"
}

_ej_signal_ledger_path() {
  if [[ -n "${SIGNAL_LEDGER_PATH:-}" ]]; then
    printf '%s' "$SIGNAL_LEDGER_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/signal-ledger-selftest/%s.jsonl' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/signal-ledger.jsonl' "${HOME:-$PWD}"
}

_ej_ask_registry_path() {
  local dir
  if [[ -n "${ASK_REGISTRY_STATE_DIR:-}" ]]; then
    dir="$ASK_REGISTRY_STATE_DIR"
  elif [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    dir="${TMPDIR:-/tmp}/ask-registry-selftest/$$"
  else
    dir="${HOME:-$PWD}/.claude/state"
  fi
  printf '%s/ask-registry.jsonl' "$dir"
}

# ----------------------------------------------------------------------
# _ej_resolve_repos — echoes one resolved, existing repo root per line
# (deduped, path-normalized comparison for dedup only — original form
# printed). See REPO LIST CONFIG header comment for the resolution order.
# ----------------------------------------------------------------------
_ej_resolve_repos() {
  local cfg="${ESTATE_JANITOR_REPOS_CONFIG:-$HOME/.claude/config/estate-repos.txt}"
  local -a candidates=()
  if [[ -f "$cfg" ]]; then
    local line
    while IFS= read -r line; do
      line="${line%$'\r'}"
      line="$(printf '%s' "$line" | sed -E 's/#.*$//')"
      line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [[ -n "$line" ]] && candidates+=("$line")
    done < "$cfg"
  fi
  if [[ "${#candidates[@]}" -eq 0 ]]; then
    local fallback=""
    if declare -F nl_main_checkout_root >/dev/null 2>&1; then
      fallback="$(nl_main_checkout_root 2>/dev/null || true)"
    fi
    if [[ -z "$fallback" ]] && declare -F nl_repo_root >/dev/null 2>&1; then
      fallback="$(nl_repo_root 2>/dev/null || true)"
    fi
    [[ -z "$fallback" ]] && fallback="$PWD"
    candidates+=("$fallback")
  fi
  local -A seen=()
  local c key
  for c in "${candidates[@]}"; do
    [[ -d "$c" ]] || continue
    key="$(_ej_norm_path "$c")"
    [[ -n "${seen[$key]:-}" ]] && continue
    seen["$key"]=1
    printf '%s\n' "$c"
  done
}

# ============================================================
# COLLECTORS — each populates a global JSON-fragment string + a
# corresponding *_DEGRADED flag. Never errors; always leaves valid state.
# ============================================================

EJ_SESSIONS_JSON="[]"
EJ_SESSIONS_DEGRADED="false"
EJ_LIVE_WORKTREE_KEYS_JSON=""   # internal: newline list of normalized live worktree_root keys

#
# FORK-BATCHING (PROVEN necessary at build time, not a style preference):
# a naive per-file/per-field implementation (10 field extractions x
# jq+tr, plus 10 escape calls x printf+tr, per heartbeat file) measured
# as an actual multi-minute HANG on the operator's real machine under its
# normal background load (dozens of concurrent builder sessions already
# spawning processes) — every extra fork queues behind that contention.
# This is the EXACT defect class session-heartbeat-lib.sh's own header
# already documents fixing (search "O.3 hb-perf2 fork-batching") and
# observability-derive.sh's _od_heartbeat_batch_build already solves the
# same way: ONE jq call reads every heartbeat file at once (jq accepts
# multiple file args natively), never one jq invocation per file. Only
# hb_classify (the shared liveness oracle — must not be re-implemented
# here, see file header) still runs once per file.
_ej_collect_heartbeats() {
  local dir; dir="$(_ej_heartbeat_dir)"
  if [[ ! -d "$dir" ]]; then
    EJ_SESSIONS_JSON="[]"
    EJ_SESSIONS_DEGRADED="true"
    return 0
  fi
  shopt -s nullglob
  local -a files=("$dir"/*.json)
  shopt -u nullglob
  if [[ "${#files[@]}" -eq 0 ]]; then
    EJ_SESSIONS_JSON="[]"
    EJ_SESSIONS_DEGRADED="false"   # an empty, existing dir is a legitimate "nothing running"
    EJ_LIVE_WORKTREE_KEYS_JSON=""
    return 0
  fi

  local -a rows=() live_keys=()

  if command -v jq >/dev/null 2>&1; then
    # T1 perf fix (2026-07-28, ESTATE-T1-HB-CLASSIFY-PERF-01): one bare
    # 2-arg hb_classify measured 5.8s WALL on this machine (spawn tax: a
    # per-call `find` over ~550 transcripts + per-field jq + `date` forks)
    # — 17 heartbeats = the builder's observed 96s. hb_classify's own
    # batched 7-arg contract (the od_sessions precedent documented in
    # session-heartbeat-lib.sh) eliminates every per-call fork: transcript
    # path from ONE find-built index (explicit-empty = "index proved no
    # transcript", honored by the lib), last-activity epoch from the SAME
    # batched jq pass (fromdateiso8601, never a bash `date` per file),
    # now-epoch computed once, pid pre-supplied.
    local now_epoch; now_epoch="$(date -u +%s)"
    local -A _ej_tmap=()
    if declare -F _hb_transcripts_dir >/dev/null 2>&1; then
      local _tdir _tf _tbase
      _tdir="$(_hb_transcripts_dir)"
      if [[ -n "$_tdir" && -d "$_tdir" ]]; then
        while IFS= read -r _tf; do
          _tbase="${_tf##*/}"; _tbase="${_tbase%.jsonl}"
          _ej_tmap["$_tbase"]="$_tf"
        done < <(find "$_tdir" -maxdepth 4 -type f -name '*.jsonl' 2>/dev/null)
      fi
    fi
    local tsv
    tsv="$(jq -r '[(.session_id//""),(.cwd//""),(.repo_root//""),(.worktree_root//""),(.branch//""),(.model//""),(.last_activity_ts//""),(.last_event//""),(.marker_state//""),((.pid//"")|tostring),(((.last_activity_ts//"")|if .=="" then 0 else (try fromdateiso8601 catch 0) end)|tostring)] | @tsv' "${files[@]}" 2>/dev/null)"
    local idx=0
    local sid cwd repo_root worktree_root branch model last_ts last_event marker pid last_epoch f cls pid_json
    while IFS=$'\t' read -r sid cwd repo_root worktree_root branch model last_ts last_event marker pid last_epoch; do
      # PROVEN at build time: this platform's jq emits CRLF line endings for
      # `@tsv` output (od -c confirmed a literal \r before every \n) — the
      # SAME class of quirk perf-tick-snapshot.sh's own header documents for
      # wmic CSV. Only the LAST field of each row carries it (the \r sits
      # right before the newline the `read` loop already consumes), but it
      # silently breaks any exact-match/regex check against that field
      # without ever showing up when the value is merely printed (a lone \r
      # is invisible in most renders). Strip it unconditionally — a no-op
      # when absent, cheap (parameter expansion, no fork).
      last_epoch="${last_epoch%$'\r'}"
      [[ "$last_epoch" =~ ^[0-9]+$ ]] || last_epoch=0
      f="${files[$idx]:-}"
      idx=$((idx+1))
      [[ -n "$f" ]] || continue
      if declare -F hb_classify >/dev/null 2>&1; then
        cls="$(hb_classify "$f" "" "${_ej_tmap[$sid]-}" "$sid" "$last_epoch" "$now_epoch" "$pid" 2>/dev/null)"
      else
        cls="unknown"
      fi
      [[ -n "$cls" ]] || cls="unknown"
      if [[ "$cls" == "live" && -n "$worktree_root" ]]; then
        live_keys+=("$(_ej_norm_path "$worktree_root")")
      fi
      pid_json="null"
      [[ "$pid" =~ ^[0-9]+$ ]] && pid_json="$pid"
      rows+=("$(jq -n --arg sid "$sid" --arg cls "$cls" --arg cwd "$cwd" --arg repo_root "$repo_root" \
        --arg wt "$worktree_root" --arg branch "$branch" --arg model "$model" --arg last_ts "$last_ts" \
        --arg last_event "$last_event" --arg marker "$marker" --argjson pid "$pid_json" -c \
        '{session_id:$sid,classify:$cls,cwd:$cwd,repo_root:$repo_root,worktree_root:$wt,branch:$branch,model:$model,last_activity_ts:$last_ts,last_event:$last_event,marker_state:$marker,pid:$pid}' 2>/dev/null)")
    done <<< "$tsv"
  else
    # No jq: fall back to the slower per-file grep/sed extraction (still
    # correct, just not fork-batched — jq absence is itself a rare,
    # already-degraded machine state, not the hot path this fix targets).
    local f cls sid cwd repo_root worktree_root branch model last_ts last_event marker pid
    for f in "${files[@]}"; do
      sid="$(_ej_field "$f" session_id)"; cwd="$(_ej_field "$f" cwd)"
      repo_root="$(_ej_field "$f" repo_root)"; worktree_root="$(_ej_field "$f" worktree_root)"
      branch="$(_ej_field "$f" branch)"; model="$(_ej_field "$f" model)"
      last_ts="$(_ej_field "$f" last_activity_ts)"; last_event="$(_ej_field "$f" last_event)"
      marker="$(_ej_field "$f" marker_state)"; pid="$(_ej_field "$f" pid)"
      if declare -F hb_classify >/dev/null 2>&1; then
        cls="$(hb_classify "$f" 2>/dev/null)"
      else
        cls="unknown"
      fi
      [[ -n "$cls" ]] || cls="unknown"
      if [[ "$cls" == "live" && -n "$worktree_root" ]]; then
        live_keys+=("$(_ej_norm_path "$worktree_root")")
      fi
      rows+=("$(printf '{"session_id":"%s","classify":"%s","cwd":"%s","repo_root":"%s","worktree_root":"%s","branch":"%s","model":"%s","last_activity_ts":"%s","last_event":"%s","marker_state":"%s","pid":%s}' \
        "$(_ej_json_escape "$sid")" "$(_ej_json_escape "$cls")" "$(_ej_json_escape "$cwd")" \
        "$(_ej_json_escape "$repo_root")" "$(_ej_json_escape "$worktree_root")" "$(_ej_json_escape "$branch")" \
        "$(_ej_json_escape "$model")" "$(_ej_json_escape "$last_ts")" "$(_ej_json_escape "$last_event")" \
        "$(_ej_json_escape "$marker")" "${pid:-null}")")
    done
  fi

  EJ_SESSIONS_JSON="[$(_ej_join_commas "${rows[@]:-}")]"
  EJ_SESSIONS_DEGRADED="false"
  EJ_LIVE_WORKTREE_KEYS_JSON="$(printf '%s\n' "${live_keys[@]:-}")"
}

# _ej_field <heartbeat-json-file> <field> — flat-JSON field extractor
# (same grep/sed fallback technique as session-heartbeat-lib.sh's
# _hb_field; avoids a hard jq dependency for a single-key read).
_ej_field() {
  local file="$1" field="$2"
  [[ -f "$file" ]] || { printf ''; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg f "$field" '.[$f] // empty' "$file" 2>/dev/null | tr -d '\r'
    return 0
  fi
  local line; line="$(cat "$file" 2>/dev/null | tr -d '\r')"
  printf '%s' "$line" | sed -nE "s/.*\"${field}\":\"?([^\",}]*)\"?.*/\1/p" | head -1
}

_ej_join_commas() {
  local out="" first=1 x
  for x in "$@"; do
    [[ -z "$x" ]] && continue
    if [[ "$first" == "1" ]]; then first=0; else out+=","; fi
    out+="$x"
  done
  printf '%s' "$out"
}

# ---- process counts (delegates to perf-tick-snapshot.sh's oracle) ------
EJ_BASH_COUNT=0
EJ_CLAUDE_COUNT=0
EJ_PROCESS_DEGRADED="false"
_ej_collect_process_counts() {
  if declare -F pts_collect_processes >/dev/null 2>&1; then
    pts_collect_processes
    EJ_BASH_COUNT="${PTS_BASH_COUNT:-0}"
    EJ_CLAUDE_COUNT="${PTS_CLAUDE_COUNT:-0}"
    [[ "${PTS_DEGRADED:-0}" == "1" ]] && EJ_PROCESS_DEGRADED="true" || EJ_PROCESS_DEGRADED="false"
    return 0
  fi
  # perf-tick-snapshot.sh not found alongside this script (a partial
  # install) — degrade honestly rather than duplicate its wmic parsing.
  EJ_BASH_COUNT=0
  EJ_CLAUDE_COUNT=0
  EJ_PROCESS_DEGRADED="true"
}

# ---- git worktree list across configured repos + orphan found-lists ----
EJ_WORKTREES_JSON="[]"
EJ_WORKTREES_DEGRADED="false"
EJ_ORPHAN_WORKTREES_JSON="[]"
EJ_ORPHAN_BRANCHES_JSON="[]"
EJ_REPOS_SCANNED_JSON="[]"

_ej_is_default_branch() {
  case "$1" in
    master|main|trunk) return 0 ;;
    *) return 1 ;;
  esac
}

_ej_collect_worktrees_and_orphans() {
  local -a wt_rows=() orphan_wt_rows=() orphan_br_rows=() repo_rows=()
  local any_repo=0 any_failure=0
  local -A live_keys=()
  local k
  while IFS= read -r k; do
    [[ -n "$k" ]] && live_keys["$k"]=1
  done <<< "${EJ_LIVE_WORKTREE_KEYS_JSON:-}"

  # Fork-batching (same discipline as _ej_collect_heartbeats — see that
  # function's header): "now" is computed ONCE for the whole collection,
  # not once per orphan-branch row. A real estate can carry dozens of
  # loose branches per repo; a `date` fork per row measurably compounds
  # under this machine's real contention (PROVEN at build time).
  local _ej_now_epoch; _ej_now_epoch="$(date -u +%s 2>/dev/null || echo 0)"

  local repo
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    any_repo=1
    repo_rows+=("\"$(_ej_json_escape "$repo")\"")

    if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      any_failure=1
      continue
    fi

    local porcelain
    porcelain="$(git -C "$repo" worktree list --porcelain 2>/dev/null)"
    if [[ -z "$porcelain" ]]; then
      any_failure=1
      continue
    fi

    local -A checked_out_branches=()
    local wt_path="" wt_head="" wt_branch="" wt_bare=0 wt_detached=0
    local first_row=1
    local line
    _ej_flush_wt_row() {
      [[ -z "$wt_path" ]] && return 0
      local is_main=0
      [[ "$first_row" == "1" ]] && is_main=1
      if [[ -n "$wt_branch" ]]; then
        checked_out_branches["$wt_branch"]=1
      fi
      wt_rows+=("$(printf '{"repo":"%s","path":"%s","head":"%s","branch":"%s","bare":%s,"detached":%s,"is_main":%s}' \
        "$(_ej_json_escape "$repo")" "$(_ej_json_escape "$wt_path")" "$(_ej_json_escape "$wt_head")" \
        "$(_ej_json_escape "$wt_branch")" "$([[ "$wt_bare" == 1 ]] && echo true || echo false)" \
        "$([[ "$wt_detached" == 1 ]] && echo true || echo false)" "$([[ "$is_main" == 1 ]] && echo true || echo false)")")
      if [[ "$is_main" != "1" ]]; then
        local nk; nk="$(_ej_norm_path "$wt_path")"
        if [[ -z "${live_keys[$nk]:-}" ]]; then
          orphan_wt_rows+=("$(printf '{"repo":"%s","path":"%s","branch":"%s","reason":"no_live_heartbeat"}' \
            "$(_ej_json_escape "$repo")" "$(_ej_json_escape "$wt_path")" "$(_ej_json_escape "$wt_branch")")")
        fi
      fi
      first_row=0
      wt_path=""; wt_head=""; wt_branch=""; wt_bare=0; wt_detached=0
    }
    while IFS= read -r line; do
      line="${line%$'\r'}"
      case "$line" in
        "worktree "*) _ej_flush_wt_row; wt_path="${line#worktree }" ;;
        "HEAD "*) wt_head="${line#HEAD }" ;;
        "branch "*) wt_branch="${line#branch refs/heads/}" ;;
        "bare") wt_bare=1 ;;
        "detached") wt_detached=1 ;;
        "") : ;;
      esac
    done <<< "$porcelain"
    _ej_flush_wt_row

    local br_out
    br_out="$(git -C "$repo" for-each-ref --format='%(refname:short)|%(committerdate:unix)' refs/heads/ 2>/dev/null)"
    if [[ -n "$br_out" ]]; then
      local br_line brname brts
      while IFS= read -r br_line; do
        [[ -z "$br_line" ]] && continue
        IFS='|' read -r brname brts <<< "$br_line"
        _ej_is_default_branch "$brname" && continue
        [[ -n "${checked_out_branches[$brname]:-}" ]] && continue
        local age_days=""
        if [[ "$brts" =~ ^[0-9]+$ ]]; then
          age_days=$(( (_ej_now_epoch - brts) / 86400 ))
        fi
        orphan_br_rows+=("$(printf '{"repo":"%s","branch":"%s","last_commit_epoch":%s,"last_commit_age_days":%s,"reason":"no_worktree"}' \
          "$(_ej_json_escape "$repo")" "$(_ej_json_escape "$brname")" "${brts:-null}" "${age_days:-null}")")
      done <<< "$br_out"
    fi
  done < <(_ej_resolve_repos)

  if [[ "$any_repo" -eq 0 ]]; then
    EJ_WORKTREES_DEGRADED="true"
  else
    EJ_WORKTREES_DEGRADED="$([[ "$any_failure" == "1" ]] && echo true || echo false)"
  fi
  EJ_WORKTREES_JSON="[$(_ej_join_commas "${wt_rows[@]:-}")]"
  EJ_ORPHAN_WORKTREES_JSON="[$(_ej_join_commas "${orphan_wt_rows[@]:-}")]"
  EJ_ORPHAN_BRANCHES_JSON="[$(_ej_join_commas "${orphan_br_rows[@]:-}")]"
  EJ_REPOS_SCANNED_JSON="[$(_ej_join_commas "${repo_rows[@]:-}")]"
}

# ---- signal-ledger tail (verbatim already-valid JSONL lines) -----------
EJ_LEDGER_TAIL_JSON="[]"
EJ_LEDGER_DEGRADED="false"
_ej_collect_signal_ledger_tail() {
  local n="${ESTATE_JANITOR_LEDGER_TAIL_N:-50}"
  local path; path="$(_ej_signal_ledger_path)"
  if [[ ! -f "$path" ]]; then
    EJ_LEDGER_TAIL_JSON="[]"
    EJ_LEDGER_DEGRADED="true"
    return 0
  fi
  local -a lines=()
  local raw
  while IFS= read -r raw; do
    raw="${raw%$'\r'}"
    [[ "$raw" == \{* ]] || continue
    lines+=("$raw")
  done < <(tail -n "$n" "$path" 2>/dev/null)
  EJ_LEDGER_TAIL_JSON="[$(_ej_join_commas "${lines[@]:-}")]"
  EJ_LEDGER_DEGRADED="false"
}

# ---- ask-registry, simplified fold (jq-dependent, honest degrade) -----
EJ_ASKS_JSON="[]"
EJ_ASKS_DEGRADED="false"
_ej_collect_asks() {
  local path; path="$(_ej_ask_registry_path)"
  if [[ ! -f "$path" ]] || ! command -v jq >/dev/null 2>&1; then
    EJ_ASKS_JSON="[]"
    EJ_ASKS_DEGRADED="true"
    return 0
  fi
  local out
  out="$(jq -s -c '
    group_by(.ask_id) | map(
      (map(select(.ts != null and .ts != "")) | sort_by(.ts)) as $s |
      {
        ask_id: $s[0].ask_id,
        status: ([$s[] | select((.status // "") != "")][-1].status // "active"),
        repo: ([$s[] | select(.record_type=="created")][-1].repo // ""),
        project: ([$s[] | select(.record_type=="created")][-1].project // ""),
        summary: (
          (([$s[] | select((.record_type=="created" or .record_type=="summary_updated") and .title_source=="operator" and ((.summary // "") != ""))])[-1].summary) //
          (([$s[] | select((.record_type=="created" or .record_type=="summary_updated") and ((.summary // "") != ""))])[-1].summary) // ""
        ),
        last_ts: $s[-1].ts
      }
    ) | map(select(.status=="active"))
  ' "$path" 2>/dev/null)"
  if [[ -z "$out" ]]; then
    EJ_ASKS_JSON="[]"
    EJ_ASKS_DEGRADED="true"
    return 0
  fi
  EJ_ASKS_JSON="$out"
  EJ_ASKS_DEGRADED="false"
}

# ============================================================
# WRITE SNAPSHOT
# ============================================================
ej_write_snapshot() {
  local dir file tmp
  dir="$(ej_state_dir)"
  mkdir -p "$dir" 2>/dev/null || { echo "estate-janitor.sh: cannot create state dir $dir" >&2; return 1; }
  file="$(ej_snapshot_path)"

  local ts machine
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')"
  machine="$(hostname 2>/dev/null || echo unknown)"

  local repos_source="fallback-main-checkout"
  if [[ -n "${ESTATE_JANITOR_REPOS_CONFIG:-}" && -f "${ESTATE_JANITOR_REPOS_CONFIG:-}" ]]; then
    repos_source="env-config-file"
  elif [[ -f "$HOME/.claude/config/estate-repos.txt" ]]; then
    repos_source="default-config-file"
  fi

  tmp="$(mktemp "${file}.XXXXXX" 2>/dev/null)" || { echo "estate-janitor.sh: mktemp failed" >&2; return 1; }
  printf '{"schema":1,"generated_at":"%s","machine":"%s","asks_fold":"simplified","repos_config_source":"%s","sessions":%s,"sessions_degraded":%s,"process_counts":{"bash_count":%s,"claude_count":%s,"degraded":%s},"worktrees":%s,"worktrees_degraded":%s,"orphaned_worktrees":%s,"orphaned_branches":%s,"repos_scanned":%s,"signal_ledger_tail":%s,"signal_ledger_degraded":%s,"asks":%s,"asks_degraded":%s}\n' \
    "$(_ej_json_escape "$ts")" "$(_ej_json_escape "$machine")" "$(_ej_json_escape "$repos_source")" \
    "$EJ_SESSIONS_JSON" "$EJ_SESSIONS_DEGRADED" \
    "$EJ_BASH_COUNT" "$EJ_CLAUDE_COUNT" "$EJ_PROCESS_DEGRADED" \
    "$EJ_WORKTREES_JSON" "$EJ_WORKTREES_DEGRADED" \
    "$EJ_ORPHAN_WORKTREES_JSON" "$EJ_ORPHAN_BRANCHES_JSON" "$EJ_REPOS_SCANNED_JSON" \
    "$EJ_LEDGER_TAIL_JSON" "$EJ_LEDGER_DEGRADED" \
    "$EJ_ASKS_JSON" "$EJ_ASKS_DEGRADED" \
    > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; echo "estate-janitor.sh: write failed" >&2; return 1; }
  mv "$tmp" "$file" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; echo "estate-janitor.sh: mv failed" >&2; return 1; }

  printf '%s' "$file"
  return 0
}

ej_run() {
  _ej_collect_heartbeats
  _ej_collect_process_counts
  _ej_collect_worktrees_and_orphans
  _ej_collect_signal_ledger_tail
  _ej_collect_asks
  ej_write_snapshot
}

# ============================================================
# --self-test
# ============================================================
_ej_self_test() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local T; T="$(mktemp -d 2>/dev/null || mktemp -d -t ejst)"
  if [[ -z "$T" || ! -d "$T" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi

  export ESTATE_STATE_DIR="$T/estate"
  export HEARTBEAT_STATE_DIR="$T/heartbeats"
  export SIGNAL_LEDGER_PATH="$T/signal-ledger.jsonl"
  export ASK_REGISTRY_STATE_DIR="$T"
  mkdir -p "$HEARTBEAT_STATE_DIR"

  # Fixture repo list set UP FRONT (before any ej_run call): without this,
  # _ej_resolve_repos falls back to nl_main_checkout_root(), which resolves
  # to whatever REAL neural-lace checkout this script happens to live
  # inside — on a real dev machine that can be dozens of worktrees/branches
  # (PROVEN at build time: this repo alone had 94). A self-test must never
  # depend on the ambient state of the real repo it ships in — slow,
  # non-deterministic, and not actually testing sandboxed behavior. An
  # empty, controlled synthetic repo is the baseline for every scenario
  # below; Scenario 3+ layer a second synthetic repo with real worktrees on
  # top via their own config swap.
  local base_repo="$T/baserepo"
  mkdir -p "$base_repo"
  ( cd "$base_repo" && git init -q . && git config core.hooksPath "" && git config user.email t@example.test && git config user.name T && echo x > f && git add f && git commit -q -m init ) >/dev/null 2>&1
  export ESTATE_JANITOR_REPOS_CONFIG="$T/repos.txt"
  printf '%s\n' "$base_repo" > "$ESTATE_JANITOR_REPOS_CONFIG"

  # Deterministic, instant process-count fixture (never a real wmic call —
  # perf-tick-snapshot.sh's own injection seam; a real wmic enumeration is
  # a multi-second fork PER ej_run call, and this self-test calls ej_run
  # repeatedly across scenarios).
  export PERF_TICK_PROCESS_LIST_CMD="printf 'Node,CreationDate,Name,ParentProcessId,ProcessId\nFIXTURE,20260101000000.000000-420,bash.exe,1,100\nFIXTURE,20260101000000.000000-420,claude.exe,1,200\n'"

  echo "Scenario 1: no sources present -> honest degraded snapshot, never a crash"
  local snap; snap="$(ej_run)"
  if [[ -f "$snap" ]]; then
    pass "snapshot.json written even with zero real sources present"
  else
    fail "snapshot.json was not written"
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$snap" >/dev/null 2>&1 && pass "snapshot is valid JSON (jq)" || fail "snapshot is NOT valid JSON"
  fi

  echo "Scenario 2: a live heartbeat is reflected in sessions[] with classify=live"
  local fresh_ts; fresh_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  cat > "$HEARTBEAT_STATE_DIR/sess-live.json" <<EOF
{"schema":1,"session_id":"sess-live","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x/wt-live","branch":"main","model":"sonnet","last_activity_ts":"$fresh_ts","last_event":"turn-end","marker_state":"none"}
EOF
  snap="$(ej_run)"
  if command -v jq >/dev/null 2>&1; then
    local cls; cls="$(jq -r '.sessions[] | select(.session_id=="sess-live") | .classify' "$snap")"
    [[ "$cls" == "live" ]] && pass "live heartbeat classified live in sessions[]" || fail "expected live, got '$cls'"
  fi

  echo "Scenario 3: a worktree with NO matching live heartbeat is found as orphaned_worktree"
  local synth="$T/synthrepo"
  mkdir -p "$synth"
  ( cd "$synth" && git init -q . && git config core.hooksPath "" && git config user.email t@example.test && git config user.name T && echo x > f && git add f && git commit -q -m init ) >/dev/null 2>&1
  local wt="$T/synthwt"
  ( cd "$synth" && git worktree add -q -b ej-selftest-orphan "$wt" ) >/dev/null 2>&1
  export ESTATE_JANITOR_REPOS_CONFIG="$T/repos.txt"
  printf '%s\n' "$synth" > "$ESTATE_JANITOR_REPOS_CONFIG"
  snap="$(ej_run)"
  if command -v jq >/dev/null 2>&1; then
    local found; found="$(jq -r --arg p "$wt" '.orphaned_worktrees[] | select(.path==$p) | .path' "$snap")"
    [[ -n "$found" ]] && pass "worktree with no live heartbeat found in orphaned_worktrees[]" || fail "expected $wt in orphaned_worktrees[]"
    local total; total="$(jq -r '.worktrees | length' "$snap")"
    [[ "$total" -ge 2 ]] && pass "worktrees[] includes both main + linked worktree ($total rows)" || fail "expected >=2 worktree rows, got $total"
  fi

  echo "Scenario 4: that same worktree's OWN heartbeat (worktree_root matches, classify=live) makes it NOT orphaned"
  # Use the EXACT path string git itself reports for this worktree (via the
  # snapshot's own worktrees[] from Scenario 3, NOT bash's own $wt variable)
  # as the heartbeat's worktree_root. This is the honest fixture: real
  # hb_write-authored heartbeats and real `git worktree list` both derive
  # their path strings from git's own resolution, so a self-test comparing
  # two INDEPENDENTLY-typed path strings (bash's mktemp-produced /tmp/...
  # form vs git's own C:/Users/...  form, which differ under an MSYS mount
  # translation `_ej_norm_path`'s drive-letter-only normalization cannot
  # undo) would be testing an artifact of the fixture, not the real
  # ownership-matching logic.
  local git_reported_path
  git_reported_path="$(command -v jq >/dev/null 2>&1 && jq -r --arg b "ej-selftest-orphan" '.worktrees[] | select(.branch==$b) | .path' "$snap" || true)"
  [[ -n "$git_reported_path" ]] || git_reported_path="$wt"
  cat > "$HEARTBEAT_STATE_DIR/sess-owns-wt.json" <<EOF
{"schema":1,"session_id":"sess-owns-wt","pid":$$,"cwd":"$wt","repo_root":"$synth","worktree_root":"$git_reported_path","branch":"ej-selftest-orphan","model":"sonnet","last_activity_ts":"$fresh_ts","last_event":"turn-end","marker_state":"none"}
EOF
  snap="$(ej_run)"
  if command -v jq >/dev/null 2>&1; then
    local found2; found2="$(jq -r --arg b "ej-selftest-orphan" '.orphaned_worktrees[] | select(.branch==$b) | .path' "$snap")"
    [[ -z "$found2" ]] && pass "worktree with a live-owning heartbeat is NOT in orphaned_worktrees[]" || fail "expected the ej-selftest-orphan worktree to be excluded from orphaned_worktrees[] once owned (found: $found2)"
  fi
  rm -f "$HEARTBEAT_STATE_DIR/sess-owns-wt.json"

  echo "Scenario 5: a local branch with no worktree is found as orphaned_branch; the default branch never is"
  ( cd "$synth" && git branch ej-selftest-loose-branch ) >/dev/null 2>&1
  snap="$(ej_run)"
  if command -v jq >/dev/null 2>&1; then
    local br; br="$(jq -r '.orphaned_branches[] | select(.branch=="ej-selftest-loose-branch") | .branch' "$snap")"
    [[ "$br" == "ej-selftest-loose-branch" ]] && pass "branch with no worktree found in orphaned_branches[]" || fail "expected ej-selftest-loose-branch in orphaned_branches[]"
    local defbr; defbr="$(jq -r '.orphaned_branches[] | select(.branch=="master" or .branch=="main") | .branch' "$snap")"
    [[ -z "$defbr" ]] && pass "default branch (master/main) never appears in orphaned_branches[]" || fail "default branch incorrectly flagged as orphaned"
  fi

  ( cd "$synth" && git worktree remove --force "$wt" >/dev/null 2>&1 || true )
  ( cd "$synth" && git branch -D ej-selftest-orphan ej-selftest-loose-branch >/dev/null 2>&1 || true )

  echo "Scenario 6: signal-ledger tail is embedded verbatim, capped at N, and a malformed line is skipped without crashing"
  {
    printf '{"ts":"t1","gate":"g","event":"warn","detail":"a"}\n'
    printf 'NOT-JSON-GARBAGE\n'
    printf '{"ts":"t2","gate":"g","event":"warn","detail":"b"}\n'
  } > "$SIGNAL_LEDGER_PATH"
  ESTATE_JANITOR_LEDGER_TAIL_N=10 snap="$(ESTATE_JANITOR_LEDGER_TAIL_N=10 ej_run)"
  if command -v jq >/dev/null 2>&1; then
    local n; n="$(jq -r '.signal_ledger_tail | length' "$snap")"
    [[ "$n" == "2" ]] && pass "malformed ledger line skipped; 2 valid lines embedded" || fail "expected 2 ledger tail entries, got $n"
  fi

  echo "Scenario 7: ask-registry active asks are folded and surfaced; a merged/done ask is excluded"
  cat > "$(_ej_ask_registry_path)" <<'EOF'
{"ask_id":"ask-1","record_type":"created","ts":"2026-07-01T00:00:00Z","user":"u","machine":"m","repo":"r","project":"p","summary":"first summary","verbatim_ref":"","origin_session":"","status":"active","plan_slug":"","session_id":"s1","resumed_from":"","merged_into":"","emitter":"ask-registry","title_source":"auto","candidate_id":"","classification":""}
{"ask_id":"ask-1","record_type":"summary_updated","ts":"2026-07-02T00:00:00Z","user":"u","machine":"m","repo":"","project":"","summary":"operator title wins","verbatim_ref":"","origin_session":"","status":"","plan_slug":"","session_id":"","resumed_from":"","merged_into":"","emitter":"operator-ui","title_source":"operator","candidate_id":"","classification":""}
{"ask_id":"ask-2","record_type":"created","ts":"2026-07-01T00:00:00Z","user":"u","machine":"m","repo":"r","project":"p","summary":"done ask","verbatim_ref":"","origin_session":"","status":"active","plan_slug":"","session_id":"s2","resumed_from":"","merged_into":"","emitter":"ask-registry","title_source":"auto","candidate_id":"","classification":""}
{"ask_id":"ask-2","record_type":"status_change","ts":"2026-07-02T00:00:00Z","user":"u","machine":"m","repo":"","project":"","summary":"","verbatim_ref":"","origin_session":"","status":"done","plan_slug":"","session_id":"","resumed_from":"","merged_into":"","emitter":"auditor","title_source":"","candidate_id":"","classification":""}
EOF
  snap="$(ej_run)"
  if command -v jq >/dev/null 2>&1; then
    local s1; s1="$(jq -r '.asks[] | select(.ask_id=="ask-1") | .summary' "$snap")"
    [[ "$s1" == "operator title wins" ]] && pass "operator-sourced title wins over auto (fold precedence)" || fail "expected 'operator title wins', got '$s1'"
    local n2; n2="$(jq -r '[.asks[] | select(.ask_id=="ask-2")] | length' "$snap")"
    [[ "$n2" == "0" ]] && pass "a done ask is excluded from the active asks[] list" || fail "ask-2 (status=done) should be excluded, found $n2"
  fi

  echo "Scenario 8: jq absence degrades asks honestly (asks_degraded=true, never a crash) — simulated via a bogus registry path"
  ( export ASK_REGISTRY_STATE_DIR="$T/does-not-exist"; ej_run > "$T/snap8path" )
  local snap8; snap8="$(cat "$T/snap8path")"
  if command -v jq >/dev/null 2>&1; then
    local deg; deg="$(jq -r '.asks_degraded' "$snap8")"
    [[ "$deg" == "true" ]] && pass "missing ask-registry file degrades honestly (asks_degraded=true)" || fail "expected asks_degraded=true, got $deg"
  fi

  echo "Scenario 9: --self-test never touches the REAL production ~/.claude paths"
  [[ "$ESTATE_STATE_DIR" == "$T/estate" ]] && pass "sandboxed under tempdir, not \$HOME/.claude" || fail "ESTATE_STATE_DIR leaked outside sandbox"

  rm -rf "$T" 2>/dev/null || true
  unset ESTATE_STATE_DIR HEARTBEAT_STATE_DIR SIGNAL_LEDGER_PATH ASK_REGISTRY_STATE_DIR ESTATE_JANITOR_REPOS_CONFIG PERF_TICK_PROCESS_LIST_CMD

  echo ""
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed"
  if [[ "$FAILED" -eq 0 ]]; then
    echo "self-test: OK"
    exit 0
  else
    echo "self-test: $FAILED failed"
    exit 1
  fi
}

# Only dispatch when EXECUTED directly (house convention, matches
# nl-paths.sh / session-heartbeat-lib.sh) — lets another script `source`
# this file to reuse its collector functions without triggering a run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "$MODE" in
    --self-test) _ej_self_test ;;
    run) ej_run ;;
    *) echo "Usage: estate-janitor.sh [run|--self-test]" >&2; exit 2 ;;
  esac
fi
