#!/bin/bash
# observability-derive.sh — shared library: the ONE derivation layer
# answering the NL Observability Program's six operator questions
# (NL Observability Program Wave O, task O.3 — specs-o §O.3, frozen
# contract C4).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# The observability design sketch's law 1 (DERIVE-DON'T-MAINTAIN) says
# every "is this true right now" answer must be computed from ground
# truth on read, never cooperatively maintained in a side file that can
# drift. Law 2 (EVERY-SIGNAL-HAS-A-CONSUMER) says every event type
# emitted anywhere in the harness must have >=1 real reader. This file
# is where both laws cash out into code: it is the ONE place that reads
# heartbeats (O.2), the signal ledger (O.1/D.1), the NEEDS-YOU ledger,
# transcripts, the doctor cache, and docs/backlog.md, and turns them
# into the six questions' answers. `scripts/nl.sh` (contract C5) is a
# thin CLI dispatcher over these functions; `workstreams-ui` (§O.4) and
# the KPI/digest/plan-edit-validator consumers (§O.9) are meant to call
# THESE functions rather than re-deriving their own copy of any of this
# logic — that is the whole point of CANONICAL-COUNTERS-01: never
# report an estate count from an ad-hoc query when a canonical oracle
# exists.
#
# ============================================================
# CANONICAL-COUNTERS-01 (encoded, not just documented)
# ============================================================
#
# Every COUNT this file emits (a number a human could accidentally
# recompute a different way elsewhere) is printed with its oracle named
# inline: "<n> <thing> (oracle: <definition-id>)". The definition-ids
# used in this file: od_sessions, od_needs_me, od_shipped_since,
# od_harness_health, od_costs, od_backlog_health, od_why. This is the
# grep-able contract: `grep 'oracle:' <output>` always finds the
# provenance of every number this library prints. See
# doctrine/observability.md for the full rule statement.
#
# ============================================================
# PURE READ FUNCTIONS — ZERO STATE WRITES
# ============================================================
#
# Every od_* function in this file only reads. It never creates,
# mutates, or deletes any file (the one exception every function
# shares: doctor's own cache-refresh side effect belongs to
# session-start-digest.sh, NOT to od_harness_health, which only reads
# the cache the digest already wrote). This is what makes the library
# safe to call from a read-only CLI (`nl`), a doctor predicate, and a
# cockpit server's refresh loop without any of them needing write
# locking or worrying about interfering with each other.
#
# ============================================================
# THE SIX QUESTIONS -> FUNCTIONS
# ============================================================
#
#   Q1 "what is every session doing right now"      -> od_sessions
#   Q2 "what needs MY decision"                       -> od_needs_me
#   Q3 "what shipped since I last looked"              -> od_shipped_since
#   Q4 "is the harness healthy"                        -> od_harness_health
#   Q5 "what did this cost"                            -> od_costs
#   Q6 "why did session X do that"                     -> od_why
#
#   Plus the backlog oracle (O.9's single definition, not one of the
#   six sketch questions but the same discipline): od_backlog_health.
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST / explicit override — §O.0.1-3)
# ============================================================
#
# This file writes nothing itself EXCEPT the od_costs incremental cost
# cache (verifier-round fix, O.3 conf 9 — see the cache section above
# _od_costs_one_transcript), which is itself a redirectable, tolerate-
# corrupt, tolerate-absent memoization layer, never a correctness
# dependency. Every function this file calls into (session-heartbeat-
# lib.sh, signal-ledger.sh, needs-you.sh) honors its OWN env-var
# override / HARNESS_SELFTEST sandbox; this file's own state/read-only
# knobs — per the advocate plan-time review 2026-07-06 (specs-o §O.0.1-3
# amendment: "every C4 ground-truth input is redirectable"):
#   OBS_TRANSCRIPTS_ROOT  - transcripts dir (od_costs/od_why/od_sessions)
#   OBS_MAIN_CHECKOUT     - git root (od_shipped_since)
#   OBS_DOCTOR_CACHE_DIR  - doctor-cache.json's directory (od_harness_health)
#   OBS_BACKLOG_PATH      - docs/backlog.md (od_backlog_health)
#   OBS_COSTS_CACHE       - od_costs's incremental cost cache file path
#                           (verifier-round fix; sandboxed the same way)
# all consistent with the sibling files' own resolution order: explicit
# override first, HARNESS_SELFTEST sandbox second, production default
# third.
#
# ============================================================
# USAGE
# ============================================================
#
#   source "${BASH_SOURCE%/*}/observability-derive.sh"
#   od_sessions --json
#   od_needs_me
#   od_why "$SESSION_ID" --last-block
#   od_costs --session "$SESSION_ID" --json
#   od_shipped_since "2026-07-01T00:00:00Z"
#   od_backlog_health --json

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_OBSERVABILITY_DERIVE_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_OBSERVABILITY_DERIVE_SOURCED=1

_OD_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# Source sibling libs (best-effort — a missing sibling degrades the
# affected function to an honest "unavailable" output, never a crash).
_od_have() { command -v "$1" >/dev/null 2>&1; }

if [[ -f "$_OD_SELF_DIR/nl-paths.sh" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$_OD_SELF_DIR/nl-paths.sh"
fi
if [[ -f "$_OD_SELF_DIR/session-heartbeat-lib.sh" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$_OD_SELF_DIR/session-heartbeat-lib.sh"
fi
if [[ -f "$_OD_SELF_DIR/signal-ledger.sh" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$_OD_SELF_DIR/signal-ledger.sh"
fi

: "${OBS_STALE_MIN:=30}"

# ----------------------------------------------------------------------
# _od_repo_root — resolve the repo root, preferring nl_repo_root() when
# available. Never fails (empty string on total failure).
# ----------------------------------------------------------------------
_od_repo_root() {
  if _od_have nl_repo_root; then
    nl_repo_root
    return 0
  fi
  printf ''
}

# ----------------------------------------------------------------------
# _od_main_checkout — resolve the MAIN checkout root od_shipped_since reads
# git log from (nl_main_checkout_root() handles the linked-worktree case:
# "git log on main checkout master" per the C4 contract's own wording).
# Override: OBS_MAIN_CHECKOUT (self-test / explicit — advocate review
# 2026-07-06, §O.0.1-3 amendment). Falls back to nl_main_checkout_root(),
# then to _od_repo_root().
# ----------------------------------------------------------------------
_od_main_checkout() {
  if [[ -n "${OBS_MAIN_CHECKOUT:-}" ]]; then
    printf '%s' "$OBS_MAIN_CHECKOUT"
    return 0
  fi
  if _od_have nl_main_checkout_root; then
    local r; r="$(nl_main_checkout_root)"
    [[ -n "$r" ]] && { printf '%s' "$r"; return 0; }
  fi
  _od_repo_root
}

# ----------------------------------------------------------------------
# _od_needs_you_bin — resolve the needs-you.sh script path (repo-root
# relative: adapters/claude-code/scripts/needs-you.sh).
# ----------------------------------------------------------------------
_od_needs_you_bin() {
  local root; root="$(_od_repo_root)"
  [[ -n "$root" ]] || { printf ''; return 0; }
  local p="$root/adapters/claude-code/scripts/needs-you.sh"
  [[ -f "$p" ]] && printf '%s' "$p" || printf ''
}

# ----------------------------------------------------------------------
# _od_backlog_path — resolve docs/backlog.md. Override (checked in
# order): BACKLOG_MD_PATH (the convention the three real od_backlog_health
# consumers — session-start-digest.sh, plan-edit-validator.sh,
# harness-kpis.sh — and O.9's own self-tests actually set), then
# OBS_BACKLOG_PATH (specs-o §O.0.1-3 sandbox var list / this file's own
# --self-test). Both resolve identically; kept so neither caller's
# convention silently breaks (orchestrator reconciliation, batch 2).
# ----------------------------------------------------------------------
_od_backlog_path() {
  if [[ -n "${BACKLOG_MD_PATH:-}" ]]; then
    printf '%s' "$BACKLOG_MD_PATH"
    return 0
  fi
  if [[ -n "${OBS_BACKLOG_PATH:-}" ]]; then
    printf '%s' "$OBS_BACKLOG_PATH"
    return 0
  fi
  local root; root="$(_od_repo_root)"
  [[ -n "$root" ]] || { printf ''; return 0; }
  printf '%s/docs/backlog.md' "$root"
}

# ----------------------------------------------------------------------
# _od_transcripts_dir — resolve the directory holding this machine's
# session transcript JSONL files (~/.claude/projects/<sanitized-cwd>/).
# Override: OBS_TRANSCRIPTS_ROOT (self-test / explicit — advocate review
# 2026-07-06, §O.0.1-3 amendment — a single flat dir of *.jsonl fixture
# files, not the real nested per-project tree).
# ----------------------------------------------------------------------
_od_transcripts_dir() {
  if [[ -n "${OBS_TRANSCRIPTS_ROOT:-}" ]]; then
    printf '%s' "$OBS_TRANSCRIPTS_ROOT"
    return 0
  fi
  printf '%s/.claude/projects' "${HOME:-$PWD}"
}

# ----------------------------------------------------------------------
# _od_find_transcript <session-id> — locate the transcript JSONL file for
# a session id anywhere under the transcripts dir (real layout nests by
# sanitized-cwd; self-test layout is flat). Prints the first match or
# empty. Never errors.
# ----------------------------------------------------------------------
_od_find_transcript() {
  local sid="$1" dir
  dir="$(_od_transcripts_dir)"
  [[ -n "$sid" && -d "$dir" ]] || { printf ''; return 0; }
  find "$dir" -maxdepth 4 -type f -name "${sid}.jsonl" 2>/dev/null | head -n1
}

# ----------------------------------------------------------------------
# _od_now_epoch / _od_epoch — shared with the sibling libs' own helpers,
# duplicated locally (single-file portability: this lib must source
# cleanly even if a caller only ships this one file to a fixture tree).
# ----------------------------------------------------------------------
_od_now_epoch() { date -u +%s 2>/dev/null || echo 0; }
_od_epoch() {
  local ts="$1"
  date -u -d "$ts" '+%s' 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null && return 0
  echo 0
}

# ----------------------------------------------------------------------
# _od_json_field <json-line> <field> — extract a top-level string field
# from a flat single-line JSON object (ledger/heartbeat shape). jq when
# present, sed fallback otherwise. Empty on any failure.
# ----------------------------------------------------------------------
_od_json_field() {
  local line="$1" field="$2"
  if _od_have jq; then
    printf '%s' "$line" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null | tr -d '\r'
    return 0
  fi
  printf '%s' "$line" | sed -nE "s/.*\"${field}\":\"?([^\",}]*)\"?.*/\\1/p" | head -1
}

# ----------------------------------------------------------------------
# _od_jq <args...> — wrapper around `jq` that ALWAYS strips \r from its
# output (findings 030/038: jq.exe under Git-Bash/Windows writes
# text-mode output and turns embedded newlines into \r\n on the way out;
# a `\r` surviving into a bash `case`/`==`/`[[ -z ]]` comparison silently
# fails to match — this is the exact regression the livesmoke drill
# surfaced in od_harness_health's per-gate tally: "waiver\r" never
# matched the `case` pattern `waiver)`). EVERY jq invocation in this file
# whose output feeds a bash comparison/case (as opposed to output that
# is only ever printed straight back out) MUST go through this wrapper,
# never a raw `jq` call piped directly into `read`/`case`/`[[ ]]`.
# ----------------------------------------------------------------------
_od_jq() {
  jq "$@" 2>/dev/null | tr -d '\r'
}

# ----------------------------------------------------------------------
# _od_json_escape <string> — same technique as the sibling libs.
# ----------------------------------------------------------------------
_od_json_escape() {
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

# ============================================================
# Q1 — od_sessions [--json]
# ============================================================
#
# Enumerates heartbeat files (C1) + joins NEEDS-YOU has-entry-for-session,
# the signal ledger, and transcript last-activity mtimes. Per session,
# state is ∈ `working|blocked|waiting-on-me|throttled|stalled|crashed|
# unobserved-cloud`.
#
# DERIVATION RULES (advocate plan-time review 2026-07-06 — specs-o §O.0.3
# contract C4, binding; every enum value has a written ground-truth rule,
# never invented ad hoc):
#   waiting-on-me     - a NEEDS-YOU OPEN ledger entry names this session_id
#                       (joined via needs-you.sh has-entry-for-session).
#                       Trumps every rule below.
#   crashed           - C1 heartbeat stale AND recorded pid not alive
#                       (hb_classify == crashed).
#   stalled           - C1 heartbeat stale AND recorded pid alive
#                       (hb_classify == stale); detail carries pid-liveness
#                       (reported as marker_state passthrough + "pid alive").
#   throttled         - the session's most recent signal-ledger
#                       `throttle-detected` event (gate=resumer, or any
#                       resumer 429-class event normalized to that name)
#                       is NEWER than the session's last activity
#                       timestamp (heartbeat last_activity_ts, or
#                       transcript mtime when no heartbeat exists).
#   blocked           - the session's newest signal-ledger `block` event
#                       is NEWER than its last transcript activity (mtime)
#                       — i.e. a block it has not yet responded past.
#   unobserved-cloud  - session_id appears in ledger lifecycle/spawn
#                       events (session-start/session-stop/
#                       spawn-dispatched/spawn-concluded) or a remote
#                       ledger, but has NO local heartbeat file AND no
#                       local transcript file. Unknown/unresolvable
#                       fields render literally as "unknown", never
#                       fabricated.
#   working           - fresh heartbeat (hb_classify == live), none of the
#                       above conditions hold.
#
# Priority on ties (a session can satisfy more than one rule at once —
# e.g. live heartbeat AND a pending needs-you item): waiting-on-me >
# crashed > stalled > throttled > blocked > working.
# ============================================================

# _od_session_last_activity <sid> <heartbeat-file-or-empty> — print the
# best-known "last activity" epoch for a session: heartbeat
# last_activity_ts when a heartbeat file exists, else the transcript
# file's mtime, else 0 (unresolvable — never fabricated).
_od_session_last_activity() {
  local sid="$1" hbfile="$2"
  if [[ -n "$hbfile" && -f "$hbfile" ]]; then
    local ts; ts="$(_od_json_field "$(cat "$hbfile" 2>/dev/null)" "last_activity_ts")"
    if [[ -n "$ts" ]]; then
      _od_epoch "$ts"
      return 0
    fi
  fi
  local tf; tf="$(_od_find_transcript "$sid")"
  if [[ -n "$tf" && -f "$tf" ]]; then
    date -u -r "$tf" +%s 2>/dev/null && return 0
    stat -c %Y "$tf" 2>/dev/null && return 0
  fi
  echo 0
}

# ----------------------------------------------------------------------
# PERFORMANCE NOTE (livesmoke-driven fix): the signal ledger is a
# cross-project, ever-growing JSONL file (1000+ lines on a working
# machine within days). A naive `while read -r line; do ... $(_od_json_field
# "$line" ...) ...; done < ledger` pattern spawns a NEW jq (or sed)
# SUBPROCESS PER FIELD PER LINE — on a 1600-line ledger with 3-4 fields
# read per line across several per-session scans, that is tens of
# thousands of subprocess forks, which measured >30s (effectively hung)
# against this machine's real ledger during the livesmoke drill. Every
# ledger-wide scan below therefore does exactly ONE jq invocation over
# the WHOLE file (jq's own per-line streaming, `jq -c` / `-s`), never a
# bash loop calling jq per line. This is the fix for that measured
# regression, not a style preference.
# ----------------------------------------------------------------------

# _od_ledger_prefilter <ledger-path> <sid> — print every JSONL line in
# the ledger belonging to <sid>, via ONE jq invocation (select on
# .session_id), so downstream per-purpose scans (block-epoch,
# throttle-epoch) work off an already-tiny per-session slice instead of
# re-scanning the whole multi-thousand-line ledger each time. Falls back
# to a plain grep -F prefilter (session_id appears as a literal
# substring in the flat single-line JSON shape signal-ledger.sh writes)
# when jq is unavailable — still ONE pass, no per-line subprocess.
_od_ledger_prefilter() {
  local ledger="$1" sid="$2"
  [[ -f "$ledger" ]] || return 0
  if _od_have jq; then
    _od_jq -c --arg sid "$sid" 'select(.session_id == $sid)' "$ledger"
  else
    grep -F "\"session_id\":\"${sid}\"" "$ledger" 2>/dev/null
  fi
}

# _od_session_last_block_epoch <sid> <ledger-path> — epoch of the newest
# `block` event for this session_id, or 0 if none. ONE jq pass (no
# per-line subprocess spawn).
_od_session_last_block_epoch() {
  local sid="$1" ledger="$2"
  [[ -f "$ledger" ]] || { echo 0; return 0; }
  local ts=""
  if _od_have jq; then
    ts="$(_od_jq -r --arg sid "$sid" '
      select(.session_id == $sid and .event == "block") | .ts
    ' "$ledger" | sort | tail -n1)"
  else
    ts="$(_od_ledger_prefilter "$ledger" "$sid" | grep '"event":"block"' \
      | sed -nE 's/.*"ts":"([^"]*)".*/\1/p' | sort | tail -n1)"
  fi
  [[ -z "$ts" ]] && { echo 0; return 0; }
  _od_epoch "$ts"
}

# _od_session_last_throttle_epoch <sid> <ledger-path> — epoch of the
# newest gate=resumer event=throttle-detected event for this session_id,
# or 0 if none. ONE jq pass.
_od_session_last_throttle_epoch() {
  local sid="$1" ledger="$2"
  [[ -f "$ledger" ]] || { echo 0; return 0; }
  local ts=""
  if _od_have jq; then
    ts="$(_od_jq -r --arg sid "$sid" '
      select(.session_id == $sid and .gate == "resumer" and .event == "throttle-detected") | .ts
    ' "$ledger" | sort | tail -n1)"
  else
    ts="$(_od_ledger_prefilter "$ledger" "$sid" | grep '"gate":"resumer"' | grep '"event":"throttle-detected"' \
      | sed -nE 's/.*"ts":"([^"]*)".*/\1/p' | sort | tail -n1)"
  fi
  [[ -z "$ts" ]] && { echo 0; return 0; }
  _od_epoch "$ts"
}

# _od_ledger_lifecycle_sids <ledger-path> — print every session_id that
# has ANY lifecycle/spawn event (session-start|session-stop|
# spawn-dispatched|spawn-concluded) in the ledger, one per line, deduped.
# ONE jq pass over the whole file.
_od_ledger_lifecycle_sids() {
  local ledger="$1"
  [[ -f "$ledger" ]] || return 0
  if _od_have jq; then
    _od_jq -r '
      select(.event == "session-start" or .event == "session-stop"
             or .event == "spawn-dispatched" or .event == "spawn-concluded")
      | .session_id // empty
    ' "$ledger" | grep -v '^unknown$' | sort -u
    return 0
  fi
  # jq-less fallback: one grep pass (still no per-line subprocess).
  grep -E '"event":"(session-start|session-stop|spawn-dispatched|spawn-concluded)"' "$ledger" 2>/dev/null \
    | sed -nE 's/.*"session_id":"([^"]*)".*/\1/p' | grep -v '^unknown$' | sort -u
}

od_sessions() {
  local json_mode=0
  local a
  for a in "$@"; do [[ "$a" == "--json" ]] && json_mode=1; done

  local hbdir
  if _od_have hb_state_dir; then
    hbdir="$(hb_state_dir)"
  else
    hbdir="${HEARTBEAT_STATE_DIR:-$HOME/.claude/state/heartbeats}"
  fi
  local ledger; ledger="${SIGNAL_LEDGER_PATH:-$HOME/.claude/state/signal-ledger.jsonl}"

  local -a sids=()
  local f sid
  if [[ -d "$hbdir" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      sid="$(basename "$f" .json)"
      sids+=("$sid")
    done < <(find "$hbdir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
  fi

  # unobserved-cloud candidates: session ids the ledger (local or remote)
  # has seen via a lifecycle/spawn event, with NO local heartbeat file.
  local -a lifecycle_sids=()
  while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    lifecycle_sids+=("$sid")
  done < <(_od_ledger_lifecycle_sids "$ledger")

  # Cross-machine read-both (§O.3 deliverable 4): also enumerate session
  # ids named in any adjacent remote ledger.
  local remote_dir="${OBS_REMOTE_LEDGERS_DIR:-$HOME/.claude/state/remote-ledgers}"
  if [[ -d "$remote_dir" ]]; then
    local rl
    while IFS= read -r rl; do
      [[ -f "$rl" ]] || continue
      while IFS= read -r sid; do
        [[ -z "$sid" ]] && continue
        lifecycle_sids+=("$sid")
      done < <(_od_ledger_lifecycle_sids "$rl")
    done < <(find "$remote_dir" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null)
  fi

  # Merge: local heartbeat sids ∪ lifecycle-only sids (dedup).
  local -a all_sids=()
  for sid in "${sids[@]}"; do all_sids+=("$sid"); done
  local lsid known s
  for lsid in "${lifecycle_sids[@]}"; do
    known=0
    for s in "${all_sids[@]}"; do [[ "$s" == "$lsid" ]] && known=1 && break; done
    [[ "$known" == "0" ]] && all_sids+=("$lsid")
  done

  local ny_bin; ny_bin="$(_od_needs_you_bin)"

  local -a out_rows=()
  local state marker branch worktree cwd hbfile detail

  for sid in "${all_sids[@]}"; do
    hbfile=""
    marker=""; branch=""; worktree=""; cwd=""; detail=""
    if [[ -f "$hbdir/${sid}.json" ]]; then
      hbfile="$hbdir/${sid}.json"
      marker="$(_od_json_field "$(cat "$hbfile" 2>/dev/null)" "marker_state")"
      branch="$(_od_json_field "$(cat "$hbfile" 2>/dev/null)" "branch")"
      worktree="$(_od_json_field "$(cat "$hbfile" 2>/dev/null)" "worktree_root")"
      cwd="$(_od_json_field "$(cat "$hbfile" 2>/dev/null)" "cwd")"
    fi

    local waiting=0
    if [[ -n "$ny_bin" ]]; then
      bash "$ny_bin" has-entry-for-session "$sid" >/dev/null 2>&1 && waiting=1
    fi

    local hbcls="missing"
    if [[ -n "$hbfile" ]]; then
      if _od_have hb_classify; then
        hbcls="$(hb_classify "$hbfile" "$OBS_STALE_MIN")"
      else
        hbcls="live"
      fi
    fi

    local transcript_file; transcript_file="$(_od_find_transcript "$sid")"
    local last_activity_epoch; last_activity_epoch="$(_od_session_last_activity "$sid" "$hbfile")"
    local last_block_epoch; last_block_epoch="$(_od_session_last_block_epoch "$sid" "$ledger")"
    local last_throttle_epoch; last_throttle_epoch="$(_od_session_last_throttle_epoch "$sid" "$ledger")"
    local transcript_mtime=0
    if [[ -n "$transcript_file" && -f "$transcript_file" ]]; then
      transcript_mtime="$(date -u -r "$transcript_file" +%s 2>/dev/null || stat -c %Y "$transcript_file" 2>/dev/null || echo 0)"
    fi

    # Priority order: waiting-on-me > crashed > stalled > throttled >
    # blocked > working (unobserved-cloud is a distinct branch below,
    # only reachable when there is no local heartbeat at all).
    if [[ "$waiting" == "1" ]]; then
      state="waiting-on-me"
    elif [[ "$hbcls" == "crashed" ]]; then
      state="crashed"
    elif [[ "$hbcls" == "stale" ]]; then
      state="stalled"
      detail="pid alive"
    elif [[ "$last_throttle_epoch" -gt 0 && "$last_throttle_epoch" -gt "$last_activity_epoch" ]]; then
      state="throttled"
    elif [[ "$last_block_epoch" -gt 0 && "$last_block_epoch" -gt "$transcript_mtime" ]]; then
      state="blocked"
    elif [[ "$hbcls" == "live" ]]; then
      state="working"
    elif [[ -z "$hbfile" && -z "$transcript_file" ]]; then
      state="unobserved-cloud"
    else
      # No local heartbeat but a local transcript exists (or hbcls is
      # "missing" for some other reason not covered above) — the honest
      # fallback per the rule's own "unknown fields render as unknown"
      # clause, rather than silently defaulting to "working".
      state="unknown"
    fi

    [[ -z "$branch" ]] && branch="unknown"
    [[ -z "$marker" ]] && marker="unknown"
    out_rows+=("${sid}"$'\t'"${state}"$'\t'"${branch}"$'\t'"${worktree:-$cwd}"$'\t'"${marker}"$'\t'"${detail}")
  done

  if [[ "$json_mode" == "1" ]]; then
    printf '{"schema":1,"oracle":"od_sessions","sessions":['
    local first=1 row
    for row in "${out_rows[@]}"; do
      IFS=$'\t' read -r r_sid r_state r_branch r_wt r_marker r_detail <<< "$row"
      [[ "$first" == "1" ]] || printf ','
      first=0
      printf '{"session_id":"%s","state":"%s","branch":"%s","worktree_root":"%s","marker_state":"%s","detail":"%s"}' \
        "$(_od_json_escape "$r_sid")" "$(_od_json_escape "$r_state")" \
        "$(_od_json_escape "$r_branch")" "$(_od_json_escape "$r_wt")" \
        "$(_od_json_escape "$r_marker")" "$(_od_json_escape "$r_detail")"
    done
    printf ']}\n'
    return 0
  fi

  printf '%d session(s) (oracle: od_sessions)\n' "${#out_rows[@]}"
  local row
  for row in "${out_rows[@]}"; do
    IFS=$'\t' read -r r_sid r_state r_branch r_wt r_marker r_detail <<< "$row"
    printf '  %s  %-18s branch=%s  %s%s\n' "$r_sid" "$r_state" "${r_branch:-?}" "${r_wt:-?}" "${r_detail:+ ($r_detail)}"
  done
  return 0
}

# ============================================================
# Q2 — od_needs_me [--json]
# ============================================================
#
# Parses ~/.claude/state/needs-you/ledger.json (THE oracle; never
# re-derives from the rendered NEEDS-YOU.md) via needs-you.sh's own
# reader. Reports every OPEN item (state == "open").
# ============================================================
od_needs_me() {
  local json_mode=0
  local a
  for a in "$@"; do [[ "$a" == "--json" ]] && json_mode=1; done

  local ny_bin; ny_bin="$(_od_needs_you_bin)"
  local ledger_dir="${NEEDS_YOU_STATE_DIR:-$HOME/.claude/state/needs-you}"
  local ledger_file="$ledger_dir/ledger.json"

  if [[ ! -f "$ledger_file" ]]; then
    if [[ "$json_mode" == "1" ]]; then
      printf '{"schema":1,"oracle":"od_needs_me","items":[]}\n'
    else
      printf '0 open item(s) (oracle: od_needs_me) — no ledger at %s\n' "$ledger_file"
    fi
    return 0
  fi

  local open_items
  if _od_have jq; then
    open_items="$(jq -c '[.items[]? | select(.state == "open")]' "$ledger_file" 2>/dev/null)"
  else
    open_items="[]"
  fi
  [[ -z "$open_items" || "$open_items" == "null" ]] && open_items="[]"

  if [[ "$json_mode" == "1" ]]; then
    printf '{"schema":1,"oracle":"od_needs_me","items":%s}\n' "$open_items"
    return 0
  fi

  local n
  n="$(printf '%s' "$open_items" | jq 'length' 2>/dev/null || echo 0)"
  printf '%d open item(s) (oracle: od_needs_me)\n' "$n"
  if _od_have jq && [[ "$n" -gt 0 ]]; then
    printf '%s' "$open_items" | jq -r '.[] | "  [\(.section)] \(.text | split("\n")[0]) (session: \(.session // "unknown"), id: \(.id))"' 2>/dev/null
  fi
  return 0
}

# ============================================================
# Q3 — od_shipped_since <iso-ts> [--json]
# ============================================================
#
# git log on master since <iso-ts>: shipped SHAs + subjects; plans
# transitioned to COMPLETED/archived (grep docs/plans/ diffs in-window
# for "Status: COMPLETED" additions); decide-and-go decisions
# (docs/decisions/ files added in-window); failures (ledger
# block/downgrade events in the same window).
# ============================================================
od_shipped_since() {
  local since="${1:-}"
  local json_mode=0
  local a
  for a in "$@"; do [[ "$a" == "--json" ]] && json_mode=1; done
  [[ "$since" == --* ]] && since=""

  # Git root: OBS_MAIN_CHECKOUT override (advocate review 2026-07-06,
  # §O.0.1-3 amendment) via _od_main_checkout, which also handles the
  # linked-worktree case per the C4 contract's own "git log on main
  # checkout master" wording — a worktree builder session's git log must
  # not be scoped to just its own worktree branch history.
  local root; root="$(_od_main_checkout)"
  if [[ -z "$root" || -z "$since" ]]; then
    if [[ "$json_mode" == "1" ]]; then
      printf '{"schema":1,"oracle":"od_shipped_since","error":"repo root or since-ts unresolved","shas":[],"decisions":[],"failures":0}\n'
    else
      printf '0 shipped commit(s) (oracle: od_shipped_since) — repo root or since-ts unresolved\n'
    fi
    return 0
  fi

  # Branch to read "shipped" from: OBS_SHIPPED_BRANCH override (self-test
  # fixture repos rarely have a branch literally named "master"), else
  # "master" (this repo's real main-checkout convention per its own git
  # log), else HEAD as a last-resort so a fixture repo with any single
  # branch still produces an answer instead of silently empty output.
  local shipped_branch="${OBS_SHIPPED_BRANCH:-master}"
  if ! (cd "$root" && git rev-parse --verify "$shipped_branch" >/dev/null 2>&1); then
    shipped_branch="HEAD"
  fi

  local -a shas=() subjects=()
  local sha subj
  while IFS=$'\t' read -r sha subj; do
    [[ -z "$sha" ]] && continue
    shas+=("$sha")
    subjects+=("$subj")
  done < <(cd "$root" && git log --since="$since" --pretty=format:'%H%x09%s' "$shipped_branch" 2>/dev/null)

  local -a decisions=()
  local dfile
  while IFS= read -r dfile; do
    [[ -z "$dfile" ]] && continue
    decisions+=("$(basename "$dfile")")
  done < <(cd "$root" && git log --since="$since" --diff-filter=A --name-only --pretty=format:'' -- docs/decisions/ "$shipped_branch" 2>/dev/null | grep -v '^$' | sort -u)

  # PERFORMANCE: the cutoff comparison is done INSIDE jq via
  # fromdateiso8601 (no `date` subprocess per matching line — see the
  # PERFORMANCE NOTE on od_harness_health's per-gate tally: on this
  # machine `date` forks at ~20ms each, so a bash loop calling
  # `_od_epoch` per surviving ledger line was the measured livesmoke
  # bottleneck, not the jq scan itself). jq emits ONLY the count.
  local failures=0
  local ledger; ledger="${SIGNAL_LEDGER_PATH:-$HOME/.claude/state/signal-ledger.jsonl}"
  if [[ -f "$ledger" ]]; then
    local since_epoch; since_epoch="$(_od_epoch "$since")"
    if _od_have jq; then
      failures="$(jq -rn --argjson since_epoch "$since_epoch" '
        [ inputs
          | select(.event == "block" or .event == "downgrade")
          | (try (.ts | fromdateiso8601) catch null) as $epoch
          | select($epoch == null or $epoch >= $since_epoch)
        ] | length
      ' "$ledger" 2>/dev/null | tr -d '\r')"
      [[ -z "$failures" ]] && failures=0
    else
      local line ts epoch
      while IFS= read -r line; do
        ts="$(printf '%s' "$line" | sed -nE 's/.*"ts":"([^"]*)".*/\1/p')"
        epoch="$(_od_epoch "$ts")"
        [[ "$epoch" -ge "$since_epoch" ]] && failures=$((failures + 1))
      done < <(grep -E '"event":"(block|downgrade)"' "$ledger" 2>/dev/null)
    fi
  fi

  if [[ "$json_mode" == "1" ]]; then
    printf '{"schema":1,"oracle":"od_shipped_since","since":"%s","shas":[' "$(_od_json_escape "$since")"
    local i first=1
    for i in "${!shas[@]}"; do
      [[ "$first" == "1" ]] || printf ','
      first=0
      printf '{"sha":"%s","subject":"%s"}' "$(_od_json_escape "${shas[$i]}")" "$(_od_json_escape "${subjects[$i]}")"
    done
    printf '],"decisions":['
    first=1
    local d
    for d in "${decisions[@]}"; do
      [[ "$first" == "1" ]] || printf ','
      first=0
      printf '"%s"' "$(_od_json_escape "$d")"
    done
    printf '],"failures":%d}\n' "$failures"
    return 0
  fi

  printf '%d shipped commit(s) since %s (oracle: od_shipped_since)\n' "${#shas[@]}" "$since"
  local i
  for i in "${!shas[@]}"; do
    printf '  %s  %s\n' "${shas[$i]:0:9}" "${subjects[$i]}"
  done
  printf '%d decision doc(s) added (oracle: od_shipped_since)\n' "${#decisions[@]}"
  local d
  for d in "${decisions[@]}"; do
    printf '  docs/decisions/%s\n' "$d"
  done
  printf '%d failure event(s) [block|downgrade] in window (oracle: od_shipped_since)\n' "$failures"
  return 0
}

# ============================================================
# Q4 — od_harness_health [--json]
# ============================================================
#
# Reads the digest's own doctor-cache.json (never re-runs the doctor —
# that stays session-start-digest.sh's exclusive job per its own header)
# plus per-gate 7-day block/waiver/downgrade counts derived from the
# signal ledger directly (same window/technique as waiver-density.sh's
# _wd_counts, generalized to all three event classes so a
# "waiver-dominant" gate — many waivers, few blocks — is distinguishable
# from a "block-dominant" one).
# ============================================================
od_harness_health() {
  local json_mode=0
  local a
  for a in "$@"; do [[ "$a" == "--json" ]] && json_mode=1; done

  # Cache path resolution: OBS_DOCTOR_CACHE_DIR (advocate review
  # 2026-07-06, §O.0.1-3 amendment — a directory override, composed with
  # the fixed filename session-start-digest.sh's own writer uses) takes
  # priority; DOCTOR_CACHE_PATH (session-start-digest.sh's own exact-file
  # override, kept so `nl` and the digest agree on ONE file without
  # duplicated config when both are pointed at the same real cache) is
  # the fallback; then the real production default.
  local cache
  if [[ -n "${OBS_DOCTOR_CACHE_DIR:-}" ]]; then
    cache="$OBS_DOCTOR_CACHE_DIR/doctor-cache.json"
  else
    cache="${DOCTOR_CACHE_PATH:-$HOME/.claude/state/digest/doctor-cache.json}"
  fi
  local verdict="unavailable" ts="" exit_code=""
  if [[ -f "$cache" ]]; then
    verdict="$(_od_json_field "$(cat "$cache" 2>/dev/null)" "verdict_line")"
    ts="$(_od_json_field "$(cat "$cache" 2>/dev/null)" "ts")"
    exit_code="$(_od_json_field "$(cat "$cache" 2>/dev/null)" "exit_code")"
    [[ -z "$verdict" ]] && verdict="unavailable"
  fi

  local ledger; ledger="${SIGNAL_LEDGER_PATH:-$HOME/.claude/state/signal-ledger.jsonl}"
  local window_days="${OBS_HEALTH_WINDOW_DAYS:-7}"
  local cutoff; cutoff=$(( $(_od_now_epoch) - window_days * 86400 ))

  # PERFORMANCE (livesmoke-measured, second regression class): even ONE
  # jq pass over the ledger is not enough if the bash consumer then
  # calls `date` (a subprocess) once per surviving line to compute an
  # epoch for the cutoff comparison — on this machine `date` forks at
  # ~20ms each, so 186 matching lines cost ~3.6s just in `date` spawns
  # (measured; the ledger-scan jq call itself is ~30ms). The fix is to
  # do the epoch-cutoff filtering INSIDE jq via its builtin
  # `fromdateiso8601` (no subprocess at all), so bash only ever sees
  # already-in-window rows and never calls `date`/`_od_epoch` per line.
  declare -A gate_block gate_waiver gate_downgrade
  if [[ -f "$ledger" ]] && _od_have jq; then
    local gate ev
    while IFS=$'\t' read -r gate ev; do
      [[ -z "$ev" ]] && continue
      [[ -z "$gate" ]] && gate="unknown"
      case "$ev" in
        block)      gate_block["$gate"]=$(( ${gate_block["$gate"]:-0} + 1 )) ;;
        waiver)     gate_waiver["$gate"]=$(( ${gate_waiver["$gate"]:-0} + 1 )) ;;
        downgrade)  gate_downgrade["$gate"]=$(( ${gate_downgrade["$gate"]:-0} + 1 )) ;;
      esac
    done < <(_od_jq -r --argjson cutoff "$cutoff" '
      select(.event == "block" or .event == "waiver" or .event == "downgrade")
      | . as $e
      | (try ($e.ts | fromdateiso8601) catch null) as $epoch
      | select($epoch == null or $epoch >= $cutoff)
      | [(.gate // "unknown"), .event] | @tsv
    ' "$ledger")
  elif [[ -f "$ledger" ]]; then
    # jq-less fallback: grep pre-filters to the 3 event types (still ONE
    # pass, no per-line subprocess), sed extracts fields per surviving line.
    local line ev gate ts_raw epoch
    while IFS= read -r line; do
      ev="$(printf '%s' "$line" | sed -nE 's/.*"event":"([^"]*)".*/\1/p')"
      ts_raw="$(printf '%s' "$line" | sed -nE 's/.*"ts":"([^"]*)".*/\1/p')"
      epoch="$(_od_epoch "$ts_raw")"
      if [[ "$epoch" -gt 0 ]] && [[ "$epoch" -lt "$cutoff" ]]; then continue; fi
      gate="$(printf '%s' "$line" | sed -nE 's/.*"gate":"([^"]*)".*/\1/p')"
      [[ -z "$gate" ]] && gate="unknown"
      case "$ev" in
        block)      gate_block["$gate"]=$(( ${gate_block["$gate"]:-0} + 1 )) ;;
        waiver)     gate_waiver["$gate"]=$(( ${gate_waiver["$gate"]:-0} + 1 )) ;;
        downgrade)  gate_downgrade["$gate"]=$(( ${gate_downgrade["$gate"]:-0} + 1 )) ;;
      esac
    done < <(grep -E '"event":"(block|waiver|downgrade)"' "$ledger" 2>/dev/null)
  fi

  local -a all_gates=()
  local g
  for g in "${!gate_block[@]}" "${!gate_waiver[@]}" "${!gate_downgrade[@]}"; do
    local seen=0 s
    for s in "${all_gates[@]}"; do [[ "$s" == "$g" ]] && seen=1 && break; done
    [[ "$seen" == "0" ]] && all_gates+=("$g")
  done

  if [[ "$json_mode" == "1" ]]; then
    printf '{"schema":1,"oracle":"od_harness_health","doctor":{"verdict":"%s","ts":"%s","exit_code":"%s"},"gates":[' \
      "$(_od_json_escape "$verdict")" "$(_od_json_escape "$ts")" "$(_od_json_escape "$exit_code")"
    local first=1
    for g in "${all_gates[@]}"; do
      [[ "$first" == "1" ]] || printf ','
      first=0
      local b="${gate_block[$g]:-0}" w="${gate_waiver[$g]:-0}" d="${gate_downgrade[$g]:-0}"
      local dominant="block"
      if [[ "$w" -gt "$b" && "$w" -gt "$d" ]]; then dominant="waiver"; fi
      if [[ "$d" -gt "$b" && "$d" -gt "$w" ]]; then dominant="downgrade"; fi
      printf '{"gate":"%s","block_7d":%d,"waiver_7d":%d,"downgrade_7d":%d,"dominant":"%s"}' \
        "$(_od_json_escape "$g")" "$b" "$w" "$d" "$dominant"
    done
    printf ']}\n'
    return 0
  fi

  printf 'doctor: %s (oracle: od_harness_health, cached %s)\n' "$verdict" "${ts:-never}"
  printf '%d gate(s) with block/waiver/downgrade activity in trailing %dd (oracle: od_harness_health)\n' \
    "${#all_gates[@]}" "$window_days"
  for g in "${all_gates[@]}"; do
    local b="${gate_block[$g]:-0}" w="${gate_waiver[$g]:-0}" d="${gate_downgrade[$g]:-0}"
    local flag=""
    [[ "$w" -gt "$b" && "$w" -gt 0 ]] && flag=" [waiver-dominant]"
    printf '  %-30s block=%d waiver=%d downgrade=%d%s\n' "$g" "$b" "$w" "$d" "$flag"
  done
  return 0
}

# ============================================================
# Q5 — od_costs [--session <id>] [--json]
# ============================================================
#
# Sums transcript JSONL usage blocks (tail-first read — reads from the
# END of the file backward via `tail` in chunks, tolerating a partial or
# mid-rotation transcript rather than failing; a truncated final line is
# skipped and the section is labeled stale rather than erroring) plus
# throttle events + estimated time lost from the ledger's
# gate=resumer/event=throttle-detected entries.
#
# ============================================================
# INCREMENTAL COST CACHE (verifier-round fix, O.3 conf 9 — Q5 measured
# 16.4s live, over the <10s Done-when bar)
# ============================================================
#
# This is the ONE exception to this file's "PURE READ / ZERO STATE
# WRITES" law (see file header): a per-transcript cost cache keyed by
# path+mtime+size, so an UNCHANGED transcript is never re-tailed/re-jq'd
# on a subsequent `nl costs` call. This does not violate law 1
# (DERIVE-DON'T-MAINTAIN) — the cache is not a source of truth, it is a
# memoization of a pure function of (file bytes) -> (four token sums +
# stale-note); any cache miss, corruption, or deletion falls back to
# full recomputation with an identical result, and a changed
# mtime/size key is a correctness-invalidating condition, not a
# heuristic one (Wave O evidence O.3 already established mtime+size as
# sufficient to detect "this transcript grew/rotated" for the tail-first
# read; reusing the same signal here is consistent, not a new law).
#
# Path: OBS_COSTS_CACHE override (self-test / explicit — same resolution
# convention as OBS_TRANSCRIPTS_ROOT et al, §O.0.1-3), else
# ${HOME}/.claude/state/obs-costs-cache.json in production. Schema:
#   {"schema":1,"entries":{"<abs-file-path>":{"mtime":<epoch>,"size":<bytes>,
#     "in":<n>,"out":<n>,"cc":<n>,"cr":<n>,"note":"fresh|<stale-note>"}}}
# Loaded ONCE per od_costs invocation (a single `jq` pass over the whole
# cache file, not one read per transcript — re-spawning jq once per file
# just to check the cache would reintroduce the exact per-file subprocess
# tax this rewrite removes) into a bash associative array keyed by file
# path; looked up per-file with zero subprocess cost; written back with
# ONE jq pass at the end covering every miss/changed entry.
#
# Corrupted cache tolerance: any read failure (missing file, invalid
# JSON, wrong schema) is treated as an EMPTY cache — every transcript
# recomputes fresh and the corrupted file is simply overwritten on the
# next write-back. Never fatal, never surfaced as an error to the
# caller (a cache is optional infrastructure; its absence/corruption
# must never change od_costs's answer, only its speed).
#
# HONEST RESIDUAL GAP (livesmoke against the real estate, verifier-
# round v2 AND this task's own 3-run timing): the cache eliminates
# recomputation for QUIET transcripts (measured: ~0.2s/file on a cache
# hit, vs ~1-2.5s/file on a miss for this machine's largest real
# transcripts) — this is its full intended win, and it fires correctly
# for the common real-world shape (a `nl costs <session-id>`
# single-session lookup on a session that isn't still being written to:
# measured 2.65s cold -> 1.6s warm on this machine, both under the 10s
# bar). HOWEVER: the flagless, no-arg `nl costs` AGGREGATE scan's "10
# most-recently-modified transcripts" selection, when run FROM an
# interactive session, always included that session's OWN transcript —
# a file being actively appended to by the very act of running this
# command, so its mtime/size changes between every invocation and it can
# never be a cache hit. THIS TASK's fix: the CALLING session's own
# transcript (identified via $CLAUDE_CODE_SESSION_ID, see the exclusion
# block in od_costs above) is now fully EXCLUDED from the aggregate's
# candidate list, with an honest "(this session excluded:
# self-referential)" note in both text and --json (`self_excluded`)
# output — verified live: `nl costs`'s own transcript no longer appears
# in the row list on 3 consecutive timed runs against the real estate.
#
# THIS DOES NOT, BY ITSELF, GUARANTEE <10s ON EVERY MACHINE (measured
# HONESTLY, not claimed fixed): on a machine running MANY CONCURRENT
# agent sessions at once (this builder's own dev machine had ~9+ other
# active `agent-*`/session worktrees mid-run), the top-10-by-mtime
# selection still lands on OTHER sessions' transcripts that are ALSO
# being actively appended to right now by their own separate live
# processes — not this calling session, so the $CLAUDE_CODE_SESSION_ID
# exclusion correctly does not touch them (excluding a different live
# session's transcript would hide real, currently-relevant cost data,
# which would be a worse defect than the slowness). On that machine, 3
# consecutive timed `nl costs` runs (this task's own evidence) measured
# 58.96s / 69.13s / 71.43s — ALL 10 non-excluded candidates were cache
# MISSES every single run, because literally every one of them was being
# written to by a different concurrently-running agent at the moment of
# measurement, so the incremental cache (correct, and effective for
# quiescent transcripts) had nothing quiescent left to hit. This is a
# BROADER phenomenon than the single-calling-session case this task was
# scoped to fix, and is named here rather than silently claimed solved:
# the smallest honest fix (exclude the CALLING session only) is
# implemented and verified; a machine with many simultaneously-live
# agents will still see a slow flagless aggregate `nl costs` because
# most of its "recent" candidates are genuinely, correctly still hot.
# A future fix (out of this task's scope) could widen the exclusion to
# "any transcript whose mtime changed again during this very
# invocation" (a moving-target detector, not identity-based), or lower
# OBS_COSTS_MAX_TRANSCRIPTS on busy estates — neither is implemented
# here; naming the gap honestly is preferred over a speculative fix
# unverified against this shape.
# ============================================================
_od_costs_cache_path() {
  if [[ -n "${OBS_COSTS_CACHE:-}" ]]; then
    printf '%s' "$OBS_COSTS_CACHE"
    return 0
  fi
  printf '%s/.claude/state/obs-costs-cache.json' "${HOME:-$PWD}"
}

# _od_costs_cache_load — populate the global assoc array
# _OD_COSTS_CACHE (path -> "mtime\tsize\tin\tout\tcc\tcr\tnote") from the
# cache file in ONE jq pass. Never errors; an absent/corrupt cache just
# leaves the array empty.
declare -gA _OD_COSTS_CACHE 2>/dev/null || true
_OD_COSTS_CACHE_LOADED=0
_OD_COSTS_CACHE_DIRTY=0
_od_costs_cache_load() {
  [[ "$_OD_COSTS_CACHE_LOADED" == "1" ]] && return 0
  _OD_COSTS_CACHE_LOADED=1
  _OD_COSTS_CACHE=()
  local cache_file; cache_file="$(_od_costs_cache_path)"
  [[ -f "$cache_file" ]] || return 0
  _od_have jq || return 0

  local rows
  rows="$(jq -r '
    if (.schema? == 1) and (.entries? != null) then
      .entries | to_entries[]
      | [ .key, (.value.mtime // 0), (.value.size // 0),
          (.value.in // 0), (.value.out // 0), (.value.cc // 0),
          (.value.cr // 0), (.value.note // "fresh") ] | @tsv
    else empty end
  ' "$cache_file" 2>/dev/null | tr -d '\r')"
  [[ -z "$rows" ]] && return 0

  local path mtime size in_t out_t cc cr note
  while IFS=$'\t' read -r path mtime size in_t out_t cc cr note; do
    [[ -z "$path" ]] && continue
    _OD_COSTS_CACHE["$path"]="${mtime}"$'\t'"${size}"$'\t'"${in_t}"$'\t'"${out_t}"$'\t'"${cc}"$'\t'"${cr}"$'\t'"${note}"
  done <<< "$rows"
  return 0
}

# _od_costs_cache_lookup <file> <mtime> <size> — prints the cached
# "in\tout\tcc\tcr\tnote" if the cache has an entry for this exact
# path+mtime+size (i.e. the file has not changed since it was cached);
# prints nothing (cache miss) otherwise. Zero subprocess cost (pure bash
# associative-array lookup).
_od_costs_cache_lookup() {
  local file="$1" mtime="$2" size="$3"
  local entry="${_OD_COSTS_CACHE[$file]:-}"
  [[ -z "$entry" ]] && return 1
  local c_mtime c_size c_in c_out c_cc c_cr c_note
  IFS=$'\t' read -r c_mtime c_size c_in c_out c_cc c_cr c_note <<< "$entry"
  if [[ "$c_mtime" == "$mtime" && "$c_size" == "$size" ]]; then
    printf '%s\t%s\t%s\t%s\t%s' "$c_in" "$c_out" "$c_cc" "$c_cr" "$c_note"
    return 0
  fi
  return 1
}

# _od_costs_cache_store <file> <mtime> <size> <in> <out> <cc> <cr> <note>
# — updates the in-memory cache entry (bash only, no I/O) and marks the
# cache dirty so od_costs writes it back once at the end.
_od_costs_cache_store() {
  local file="$1" mtime="$2" size="$3" in_t="$4" out_t="$5" cc="$6" cr="$7" note="$8"
  _OD_COSTS_CACHE["$file"]="${mtime}"$'\t'"${size}"$'\t'"${in_t}"$'\t'"${out_t}"$'\t'"${cc}"$'\t'"${cr}"$'\t'"${note}"
  _OD_COSTS_CACHE_DIRTY=1
}

# _od_costs_cache_flush — writes the in-memory cache back to disk in ONE
# jq invocation, ONLY if something changed this run (a pure cache-hit run
# never touches disk). Atomic (tmp+mv) so a concurrent reader never sees
# a half-written file. Best-effort: a write failure (read-only fs, no
# disk space) is silently tolerated — the cache is optional speed
# infrastructure, never a correctness dependency.
_od_costs_cache_flush() {
  [[ "$_OD_COSTS_CACHE_DIRTY" == "1" ]] || return 0
  _od_have jq || return 0
  local cache_file; cache_file="$(_od_costs_cache_path)"
  local cache_dir; cache_dir="$(dirname "$cache_file")"
  mkdir -p "$cache_dir" 2>/dev/null || return 0

  local path entry mtime size in_t out_t cc cr note
  local tmp; tmp="$(mktemp "${cache_dir}/.obs-costs-cache.XXXXXX" 2>/dev/null)" || return 0
  {
    printf '{"schema":1,"entries":{'
    local first=1
    for path in "${!_OD_COSTS_CACHE[@]}"; do
      entry="${_OD_COSTS_CACHE[$path]}"
      IFS=$'\t' read -r mtime size in_t out_t cc cr note <<< "$entry"
      [[ "$first" == "1" ]] || printf ','
      first=0
      printf '%s:{"mtime":%s,"size":%s,"in":%s,"out":%s,"cc":%s,"cr":%s,"note":%s}' \
        "$(_od_json_escape "$path" | sed 's/^/"/;s/$/"/')" \
        "${mtime:-0}" "${size:-0}" "${in_t:-0}" "${out_t:-0}" "${cc:-0}" "${cr:-0}" \
        "$(_od_json_escape "$note" | sed 's/^/"/;s/$/"/')"
    done
    printf '}}\n'
  } > "$tmp" 2>/dev/null
  if jq -e . "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$cache_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  _OD_COSTS_CACHE_DIRTY=0
}

# _od_costs_one_transcript <file> [tail-override] — prints
# "in\tout\tcc\tcr\tnote\tcache_key\tmtime\tsize\thit_or_miss". The
# trailing three fields (cache_key/mtime/size/hit_or_miss) let the
# CALLER (od_costs's loop, running in the parent shell, not a subshell)
# perform the actual cache WRITE via _od_costs_cache_store — this
# function is always invoked as `res="$(_od_costs_one_transcript ...)"`
# (command substitution), which forks a subshell; any bash associative-
# array mutation made INSIDE that subshell (_OD_COSTS_CACHE[...]=...,
# _OD_COSTS_CACHE_DIRTY=1) is silently lost the instant the subshell
# exits. This is a real bug caught in this task's own self-test
# (cache-hit scenario 6d passed on VALUE but the cache file was never
# actually written to disk) — the fix is structural: only READ the
# cache here (safe — the subshell inherits a byte-for-byte copy of the
# array), and let the caller do every WRITE in its own (non-subshell)
# stack frame.
_od_costs_one_transcript() {
  local file="$1"
  local tail_override="${2:-}"
  local in_tok=0 out_tok=0 cache_create=0 cache_read=0 stale_note=""

  [[ -f "$file" ]] || { printf '0\t0\t0\t0\tmissing\t\t0\t0\tmiss'; return 0; }

  # CACHE SHORT-CIRCUIT (verifier-round fix, O.3 conf 9): an unchanged
  # transcript (same absolute path + mtime + size as the last time it
  # was costed) skips tail+jq entirely. mtime+size is a correctness
  # key, not a heuristic: any write to the file changes at least one of
  # them, so a hit here is provably identical bytes to what was already
  # summed. A live/growing transcript's mtime+size changes every turn,
  # so it naturally falls through to full recomputation below — this
  # cache speeds up the (common, on a busy estate) case of MANY OTHER
  # sessions' transcripts that have gone quiet, not the one session
  # currently being written.
  # PERFORMANCE (livesmoke-measured, verifier-round v2): resolving a true
  # canonical absolute path via `$(cd "$(dirname "$file")" && pwd)` costs
  # a full subshell FORK per call (~150-200ms on this machine's
  # Windows/MSYS fork overhead — measured directly against this
  # function's own real-estate timing) ON TOP OF the tail+jq cost this
  # rewrite is trying to remove, re-introducing exactly the per-file
  # subprocess tax the single-pass jq collapse above was for. Every
  # caller of this function (the --session lookup via
  # _od_find_transcript, and the aggregate scan's `find ... -printf` /
  # `find ... ` fallback) ALREADY hands in an absolute path rooted at
  # _od_transcripts_dir's own absolute resolution — so `$file` itself is
  # already the stable, comparable cache key with zero extra forks.
  # PERFORMANCE (livesmoke-measured, verifier-round v2, second pass):
  # this machine's dominant cost per file is SUBPROCESS FORK COUNT (sys
  # time >> user time throughout every measurement in this fix), not any
  # single command's CPU work — so two separate `stat` calls (mtime,
  # then size) is two forks where one suffices. `stat -c '%Y %s'`
  # returns both fields space-separated in ONE call; the BSD/macOS
  # fallback (`stat -f '%m %z'`) does the same. This halves the
  # mtime/size probing cost added by this cache (the ORIGINAL,
  # pre-cache od_costs never stat'd the file at all — every stat call
  # here is net-new overhead the cache's correctness key requires, so
  # collapsing 2 forks to 1 matters more here than almost anywhere else
  # in this file).
  local abs_file mtime size mtime_size
  abs_file="$file"
  mtime_size="$(stat -c '%Y %s' "$file" 2>/dev/null || stat -f '%m %z' "$file" 2>/dev/null)"
  read -r mtime size <<< "$mtime_size"
  mtime="${mtime:-0}"; size="${size:-0}"
  # The tail depth actually used (see below) is part of the cache
  # identity: an aggregate scan's smaller OBS_COSTS_AGGREGATE_TAIL_LINES
  # window sums FEWER lines than a --session lookup's full
  # OBS_COSTS_TAIL_LINES depth, so a cache entry computed under one
  # depth must never be served to a caller requesting the other — key
  # on path+mtime+size+depth, not just path+mtime+size, or a session
  # costed once via the aggregate view would silently under-report when
  # looked up directly afterward (or vice versa).
  local effective_tail="${tail_override:-${OBS_COSTS_TAIL_LINES:-5000}}"
  local cache_key="${abs_file}#${effective_tail}"
  _od_costs_cache_load
  local cached
  if cached="$(_od_costs_cache_lookup "$cache_key" "$mtime" "$size")"; then
    printf '%s\t%s\t%s\t%s\thit' "$cached" "$cache_key" "$mtime" "$size"
    return 0
  fi

  # Tail-first: read a bounded tail window (large enough for a normal
  # session, cheap enough to never hang on a multi-GB rotated log) so a
  # partial/rotated transcript is tolerated. If the FIRST line of the
  # tail window looks truncated (does not start with '{'), drop it and
  # note the section as stale (partial line skipped, not counted, not
  # fatal). PERFORMANCE (livesmoke-measured): `tail` itself is fast even
  # on a 20MB transcript, but `jq -s` (slurp) parsing a 5000-line/~15MB
  # window measured at 5+ SECONDS on this machine's largest real
  # transcript — legitimate data-volume cost, not a subprocess-spawn bug.
  # The caller (od_costs, no-session aggregate path) passes a smaller
  # $2 override so summing MANY transcripts stays fast; a single named
  # session (the common case) still gets the full default depth.
  local tail_lines="$effective_tail"
  local content
  content="$(tail -n "$tail_lines" "$file" 2>/dev/null)"
  if [[ -z "$content" ]]; then
    printf '0\t0\t0\t0\tempty\t%s\t%s\t%s\tmiss' "$cache_key" "$mtime" "$size"
    return 0
  fi

  # SINGLE-PASS REWRITE (verifier-round fix, O.3 conf 9 — Q5 measured
  # 16.4s live against the ~2s/file marginal subprocess overhead of the
  # ORIGINAL 6-7-subprocess-per-file pipeline: `head -n1` + `jq -e .`
  # [first-line validity] + `jq -s` [slurp-sum] + 4x `sed -n` [field
  # extraction] = 7 process spawns per transcript, dominated by
  # spawn/fork cost on this machine (measured: high `sys` time relative
  # to `user` time), not actual data volume. Collapsed to exactly ONE jq
  # invocation per transcript that does first-line-validity detection
  # AND the four-field sum in the same pass, emitting a single tab-
  # separated line with all 5 fields (4 sums + the stale-note) so bash
  # needs only ONE `read` to unpack the result — no `sed -n` at all.
  #
  # v1-of-this-rewrite REGRESSION (caught by this task's own live-estate
  # timing re-run, not hypothetical): an earlier version of this
  # collapse used `jq -R` STREAMING mode (`inputs` reads one JSON value
  # per line as the program runs) so a parse failure could be try/caught
  # per record. That measured ~10x SLOWER than the original `jq -s`
  # slurp per file (0.5s vs 0.046s on this machine's largest real
  # transcript) — `-R` streaming re-parses/re-tokenizes far more
  # aggressively than `-s` slurp mode, so "fewer subprocess spawns" was
  # a false economy that made od_costs SLOWER end-to-end (25-30s live,
  # worse than the 16.4s baseline this fix exists to beat). The fix:
  # `-R -s` (raw SLURP, not raw stream) reads the whole tail window as
  # ONE string, splits on newlines natively in jq (cheap), and calls
  # `fromjson` per element — same single-jq-invocation win, but keeping
  # jq's fast slurp parser instead of its streaming one. Measured back
  # down to ~0.06s/file (matching the original jq -s baseline) while
  # still folding first-line-validity + sum + note into one call.
  if _od_have jq; then
    local out
    out="$(printf '%s\n' "$content" | jq -R -s -r '
      split("\n") | map(select(length > 0)) as $lines
      | ($lines[0] | try fromjson catch null) as $first
      | ($first == null) as $first_bad
      | ( if $first_bad then $lines[1:] else $lines end
          | map(try fromjson catch null) ) as $rows
      | [ $rows[] | select(. != null and .message.usage? != null) | .message.usage ] as $u
      | [ ($u | map(.input_tokens // 0) | add // 0),
          ($u | map(.output_tokens // 0) | add // 0),
          ($u | map(.cache_creation_input_tokens // 0) | add // 0),
          ($u | map(.cache_read_input_tokens // 0) | add // 0),
          ( if $first_bad then "partial-tail-truncated-first-line-skipped" else "fresh" end )
        ] | @tsv
    ' 2>/dev/null)"
    if [[ -n "$out" ]]; then
      IFS=$'\t' read -r in_tok out_tok cache_create cache_read stale_note <<< "$out"
    fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tmiss' "${in_tok:-0}" "${out_tok:-0}" "${cache_create:-0}" "${cache_read:-0}" "${stale_note:-fresh}" "$cache_key" "$mtime" "$size"
}

od_costs() {
  local session="" json_mode=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      --json) json_mode=1; shift ;;
      *) shift ;;
    esac
  done

  local -a targets=()
  local truncated_all=0
  if [[ -n "$session" ]]; then
    local tf; tf="$(_od_find_transcript "$session")"
    [[ -n "$tf" ]] && targets+=("$session"$'\t'"$tf")
  else
    # PERFORMANCE (livesmoke-measured): a machine with many historical
    # projects can have 500+ transcript files; costing EVERY one of them
    # (a `tail | jq -s` subprocess pair per file) measured at >20s on
    # this machine's real estate — over the Q5 "<10s" bar. Q5's real
    # question is "what did THIS session/the recent estate cost", not
    # "sum every transcript this machine has ever produced" — so the
    # no-session-arg default scans only the OBS_COSTS_MAX_TRANSCRIPTS
    # (default 10 — plus a reduced per-file tail depth, see
    # OBS_COSTS_AGGREGATE_TAIL_LINES below) most-recently-modified
    # transcripts, newest first, and says so honestly via a truncation
    # note rather than silently costing a different (smaller) universe
    # than "all". Set OBS_COSTS_MAX_TRANSCRIPTS=0 to force the full
    # untruncated scan (slow on a machine with many/large transcripts —
    # this machine's real estate measured minutes, not seconds, for a
    # true full scan).
    local dir; dir="$(_od_transcripts_dir)"
    local max_transcripts="${OBS_COSTS_MAX_TRANSCRIPTS:-10}"
    if [[ -d "$dir" ]]; then
      local -a all_files=()
      local tf
      while IFS= read -r tf; do
        [[ -z "$tf" ]] && continue
        all_files+=("$tf")
      done < <(find "$dir" -maxdepth 4 -type f -name '*.jsonl' -printf '%T@\t%p\n' 2>/dev/null \
                | sort -t$'\t' -k1,1nr | cut -f2- \
                || find "$dir" -maxdepth 4 -type f -name '*.jsonl' 2>/dev/null | sort)

      # SELF-REFERENTIAL EXCLUSION (verifier-round fix, this task): the
      # calling session's OWN transcript is being actively appended to by
      # the very act of running `nl costs` (every tool_use/hook_progress
      # line this invocation itself produces lands in it), so its
      # mtime+size change on every call and it can NEVER be an
      # _od_costs_cache_lookup hit — measured 13-28s across consecutive
      # live runs when 3 of the flagless aggregate's top-10 files were
      # this kind of unavoidable miss (see the INCREMENTAL COST CACHE
      # header comment above for the full before/after numbers). The
      # smallest honest fix: drop the CALLING session's own transcript
      # (identified by $CLAUDE_CODE_SESSION_ID, the same env var the
      # heartbeat writer and every other Wave O consumer already treats
      # as this process's session identity) from the aggregate's
      # candidate list before the top-N selection, and say so explicitly
      # in the output — this is a full exclusion, not a truncation, since
      # a self-costing session reporting its own live, still-growing
      # number would be self-referential and misleading, not merely slow.
      local self_sid="${CLAUDE_CODE_SESSION_ID:-}"
      local self_excluded=0
      if [[ -n "$self_sid" ]]; then
        local -a filtered_files=()
        local fbase
        for tf in "${all_files[@]}"; do
          fbase="$(basename "$tf" .jsonl)"
          if [[ "$fbase" == "$self_sid" ]]; then
            self_excluded=1
            continue
          fi
          filtered_files+=("$tf")
        done
        all_files=("${filtered_files[@]}")
      fi

      local total_files="${#all_files[@]}"
      if [[ "$max_transcripts" -gt 0 ]] && [[ "$total_files" -gt "$max_transcripts" ]]; then
        truncated_all=1
        all_files=("${all_files[@]:0:$max_transcripts}")
      fi
      local sid
      for tf in "${all_files[@]}"; do
        sid="$(basename "$tf" .jsonl)"
        targets+=("$sid"$'\t'"$tf")
      done
    fi
  fi

  # Aggregate (no-session) scans use a smaller tail window per transcript
  # — Q5's aggregate view does not need the same 5000-line depth a
  # single targeted session lookup does, and summing that much data
  # across many (possibly multi-MB) transcripts is the measured
  # bottleneck this override exists to bound. A single named session
  # still gets the full default depth (tail_override empty -> falls
  # back to OBS_COSTS_TAIL_LINES/5000 inside _od_costs_one_transcript).
  local per_file_tail=""
  [[ -z "$session" ]] && per_file_tail="${OBS_COSTS_AGGREGATE_TAIL_LINES:-500}"

  local total_in=0 total_out=0 total_cc=0 total_cr=0
  local -a rows=()
  local t
  for t in "${targets[@]}"; do
    IFS=$'\t' read -r r_sid r_file <<< "$t"
    local res; res="$(_od_costs_one_transcript "$r_file" "$per_file_tail")"
    # 9-field tuple: in/out/cc/cr/note are the answer; cache_key/mtime/
    # size/hit_or_miss are cache bookkeeping. The actual
    # _od_costs_cache_store call MUST happen HERE, in this loop (the
    # parent shell's own stack frame) — _od_costs_one_transcript runs
    # inside a command-substitution SUBSHELL, so any array mutation it
    # attempted internally would vanish the instant that subshell exits
    # (the exact bug this structural split fixes; see the comment on
    # _od_costs_one_transcript itself).
    local r_in r_out r_cc r_cr r_note r_key r_mtime r_size r_hitmiss
    IFS=$'\t' read -r r_in r_out r_cc r_cr r_note r_key r_mtime r_size r_hitmiss <<< "$res"
    total_in=$((total_in + r_in)); total_out=$((total_out + r_out))
    total_cc=$((total_cc + r_cc)); total_cr=$((total_cr + r_cr))
    rows+=("${r_sid}"$'\t'"${r_in}"$'\t'"${r_out}"$'\t'"${r_cc}"$'\t'"${r_cr}"$'\t'"${r_note}")
    if [[ "$r_hitmiss" == "miss" && -n "$r_key" ]]; then
      _od_costs_cache_store "$r_key" "$r_mtime" "$r_size" "$r_in" "$r_out" "$r_cc" "$r_cr" "$r_note"
    fi
  done
  # Write back any new/changed cache entries ONCE (single jq pass, only
  # if something was actually a miss this run — see _od_costs_cache_flush).
  # Placed here (single choke point before both the --json and human-text
  # return paths below) so neither exit skips the write-back.
  _od_costs_cache_flush

  # Throttle events + estimated time lost from the ledger. PERFORMANCE:
  # ONE jq pass (see the PERFORMANCE NOTE on _od_ledger_lifecycle_sids
  # and od_harness_health's per-gate tally above) — never a bash
  # while-read loop calling jq 2-3x per ledger line; on this machine
  # that anti-pattern measured as a 20+ SECOND hang against the real
  # 1600+-line ledger (the exact livesmoke regression this rewrite
  # fixes for od_costs specifically).
  local ledger; ledger="${SIGNAL_LEDGER_PATH:-$HOME/.claude/state/signal-ledger.jsonl}"
  local throttle_count=0
  if [[ -f "$ledger" ]] && _od_have jq; then
    if [[ -n "$session" ]]; then
      throttle_count="$(jq -rn --arg sid "$session" '
        [ inputs | select(.gate == "resumer" and .event == "throttle-detected" and .session_id == $sid) ] | length
      ' "$ledger" 2>/dev/null | tr -d '\r')"
    else
      throttle_count="$(jq -rn '
        [ inputs | select(.gate == "resumer" and .event == "throttle-detected") ] | length
      ' "$ledger" 2>/dev/null | tr -d '\r')"
    fi
    [[ -z "$throttle_count" ]] && throttle_count=0
  elif [[ -f "$ledger" ]]; then
    if [[ -n "$session" ]]; then
      throttle_count="$(grep -c "\"gate\":\"resumer\".*\"event\":\"throttle-detected\".*\"session_id\":\"${session}\"\|\"session_id\":\"${session}\".*\"gate\":\"resumer\".*\"event\":\"throttle-detected\"" "$ledger" 2>/dev/null)"
    else
      throttle_count="$(grep -cE '"gate":"resumer".*"event":"throttle-detected"' "$ledger" 2>/dev/null)"
    fi
    [[ -z "$throttle_count" ]] && throttle_count=0
  fi
  local est_minutes_lost=$((throttle_count * 5))

  local self_excluded_flag=0
  [[ "${self_excluded:-0}" == "1" ]] && self_excluded_flag=1

  if [[ "$json_mode" == "1" ]]; then
    printf '{"schema":1,"oracle":"od_costs","total":{"input_tokens":%d,"output_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d},"throttle_events":%d,"est_minutes_lost":%d,"truncated_to_recent":%s,"self_excluded":%s,"sessions":[' \
      "$total_in" "$total_out" "$total_cc" "$total_cr" "$throttle_count" "$est_minutes_lost" \
      "$([[ "$truncated_all" == "1" ]] && echo true || echo false)" \
      "$([[ "$self_excluded_flag" == "1" ]] && echo true || echo false)"
    local first=1 row
    for row in "${rows[@]}"; do
      IFS=$'\t' read -r r_sid r_in r_out r_cc r_cr r_note <<< "$row"
      [[ "$first" == "1" ]] || printf ','
      first=0
      printf '{"session_id":"%s","input_tokens":%d,"output_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d,"transcript_status":"%s"}' \
        "$(_od_json_escape "$r_sid")" "$r_in" "$r_out" "$r_cc" "$r_cr" "$(_od_json_escape "$r_note")"
    done
    printf ']}\n'
    return 0
  fi

  printf '%d session(s) costed (oracle: od_costs)\n' "${#rows[@]}"
  if [[ "$truncated_all" == "1" ]]; then
    printf '  (truncated to the %d most-recently-modified transcripts; set OBS_COSTS_MAX_TRANSCRIPTS=0 for a full scan)\n' "${#rows[@]}"
  fi
  if [[ "$self_excluded_flag" == "1" ]]; then
    printf '  (this session excluded: self-referential — its own transcript is being actively appended to by this very command and can never be a cache hit)\n'
  fi
  printf '  total input=%d output=%d cache_create=%d cache_read=%d\n' "$total_in" "$total_out" "$total_cc" "$total_cr"
  printf '%d throttle event(s), ~%d min lost (oracle: od_costs)\n' "$throttle_count" "$est_minutes_lost"
  local row
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r r_sid r_in r_out r_cc r_cr r_note <<< "$row"
    printf '  %s  in=%d out=%d [%s]\n' "$r_sid" "$r_in" "$r_out" "$r_note"
  done
  return 0
}

# ============================================================
# od_backlog_health [--json] — THE backlog oracle (contract C4)
# ============================================================
#
# SPLICED from tests/fixtures/wave-o/O.9/od-backlog-health-functions.md
# (orchestrator integration, batch 2) — the row-parsing / position-
# anchored terminal-marker detection (R1-R4, the 87f357f fix) / age-tier
# / adds-vs-terminal-flow logic extracted VERBATIM from the live
# `feed_backlog_accountability` algorithm, reviewed by O.9 as THE single
# implementation. This REPLACES O.3's original summary-only mirror of
# harness-kpis.sh's _kpi_backlog_section (that version had no `rows`
# array; all three real consumers — session-start-digest.sh,
# plan-edit-validator.sh, harness-kpis.sh — parse `doc.rows` +
# `doc.summary.overdue_ids` from the JSON output via node, so the
# row-level schema below is the one actually load-bearing).
#
# ENV VAR NOTE (orchestrator reconciliation): the three real consumers
# and O.9's own self-tests set `BACKLOG_MD_PATH` (never `OBS_BACKLOG_PATH`)
# when pointing at a fixture backlog file. `_od_backlog_path` (defined
# earlier in this file) is extended below to check BACKLOG_MD_PATH first,
# then the original OBS_BACKLOG_PATH (specs-o §O.0.1-3 sandbox var list),
# so both conventions resolve identically and neither caller breaks.
# ============================================================
# The R1-R4 position-anchored terminal-marker rules and the
# YYYY-MM-DD -> epoch conversion that used to live here as bash helpers
# (_od_backlog_row_is_terminal / _od_backlog_date_epoch, per-row grep/date
# subprocesses) now live INSIDE od_backlog_health's single node pass
# below — see the PERFORMANCE NOTE there. The regexes are 1:1
# translations; the fragment doc
# (tests/fixtures/wave-o/O.9/od-backlog-health-functions.md) remains the
# algorithm's provenance record.

# od_backlog_health [--json] — contract C4. Emits the canonical JSON
# document (rows + summary) for every consumer to render from. Both
# flag-states print the SAME JSON (per C4 note in the fragment: this
# oracle has no separate human-readable mode of its own — the three
# consumers own their own presentation).
od_backlog_health() {
  local backlog; backlog="$(_od_backlog_path)"
  local tier_high="${BACKLOG_TIER_HIGH_DAYS:-7}"
  local tier_medium="${BACKLOG_TIER_MEDIUM_DAYS:-30}"
  local tier_low="${BACKLOG_TIER_LOW_DAYS:-90}"
  local window_days="${BACKLOG_HEALTH_WINDOW_DAYS:-${KPI_WINDOW_DAYS:-7}}"
  local now; now="$(_od_now_epoch)"
  local now_iso; now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local window_start=$((now - window_days * 86400))

  if [[ -z "$backlog" || ! -f "$backlog" ]]; then
    if command -v node >/dev/null 2>&1; then
      node -e '
        var doc = {schema:1, oracle:"od_backlog_health", generated_at:process.argv[1],
          backlog_path:process.argv[2], window_days:Number(process.argv[3]), rows:[],
          summary:{open_total:0, terminal_total:0,
            priority_counts:{high:0,medium:0,low:0,unlabeled:0},
            age_tiers:{"0_7":0,"8_30":0,"31_90":0,over_90:0,undated:0},
            overdue_ids:[], adds_in_window:0, terminal_in_window:0, terminal_undated:0},
          note:"no backlog file at backlog_path"};
        process.stdout.write(JSON.stringify(doc));
      ' "$now_iso" "${backlog:-<unresolved>}" "$window_days"
    else
      printf '{"schema":1,"oracle":"od_backlog_health","degraded":"node unavailable","rows":[],"summary":{}}'
    fi
    printf '\n'
    return 0
  fi

  # PERFORMANCE NOTE (livesmoke-driven fix, same class as the
  # _od_ledger_lifecycle_sids / od_costs / od_harness_health notes
  # above): this function originally ran a bash while-read loop over
  # every backlog row, spawning ~a dozen grep/sed/head/date forks
  # (_od_backlog_row_is_terminal alone was up to 4 greps; each date
  # parse was a `date` subprocess) PLUS one `node -e` startup PER ROW
  # just to JSON-encode that row. Against this machine's real 82-row
  # docs/backlog.md that measured ~51s wall (14.3s user / 23.1s sys —
  # MSYS process-spawn dominated) during the O.4 cockpit livesmoke,
  # while every other nl subcommand answered in <1s. Row parsing
  # therefore now happens in exactly ONE node invocation over the WHOLE
  # file: the R1-R4 position-anchored terminal-marker rules (87f357f)
  # and the YYYY-MM-DD -> epoch conversion are 1:1 translations of the
  # bash helpers this rewrite replaced (Date.parse of a date-only
  # string is UTC midnight, exactly `date -u -d "$d" +%s`; the JS char
  # class [\t\v\f\r ] mirrors POSIX [[:space:]] within a single line).
  if ! command -v node >/dev/null 2>&1; then
    printf '{"schema":1,"oracle":"od_backlog_health","degraded":"node unavailable","rows":[],"summary":{}}\n'
    return 0
  fi

  node -e '
    "use strict";
    var fs = require("fs");
    var backlogPath = process.argv[1], nowIso = process.argv[2];
    var windowDays = Number(process.argv[3]), windowStart = Number(process.argv[4]);
    var now = Number(process.argv[5]);
    var tierHigh = Number(process.argv[6]), tierMedium = Number(process.argv[7]);
    var tierLow = Number(process.argv[8]);

    var raw = "";
    try { raw = fs.readFileSync(backlogPath, "utf8"); } catch (e) {}

    var TERM = "(DISPOSITIONED|IMPLEMENTED|ABSORBED|CLOSED|SUPERSEDED|WONTFIX)";
    var SP = "[\\t\\v\\f\\r ]";
    var reId = /^- \*\*([A-Z][A-Z0-9-]{3,})/;
    var reAdded = /added ([0-9]{4}-[0-9]{2}-[0-9]{2})/;
    var rePrio = /priority:(high|medium|low)/;
    // R1: terminal marker inside the leading bold id segment
    var reTermR1 = new RegExp("^- \\*\\*[^*]*\\b" + TERM + "\\b");
    // R2: bold close, then em-dash / - / --, then the marker
    var reTermR2 = new RegExp("\\*\\*" + SP + "+(—|--?)" + SP + "+" + TERM + "\\b");
    // R3: "**(dispositioned ..." (case-insensitive)
    var reTermR3 = /\*\*\((dispositioned|implemented|absorbed|closed|superseded|wontfix)\b/i;
    // R4: "**MARKER" incl. the PARTIALLY/LARGELY prefixed forms
    var reTermR4 = new RegExp("\\*\\*((PARTIALLY|LARGELY)" + SP + "+)?" + TERM + "\\b");
    var reTermDate = new RegExp(TERM + "[^0-9]{0,12}([0-9]{4}-[0-9]{2}-[0-9]{2})", "i");

    function dateEpoch(d) {
      var ms = Date.parse(d);
      return isNaN(ms) ? null : Math.floor(ms / 1000);
    }

    var rows = [];
    raw.split("\n").forEach(function (line) {
      var mId = line.match(reId);
      if (!mId) return;

      var added = null, addedEpoch = null, ageDays = null;
      var mAdded = line.match(reAdded);
      if (mAdded) {
        added = mAdded[1];
        addedEpoch = dateEpoch(mAdded[1]);
        // Math.trunc == bash $(( )) integer division (truncate toward 0)
        if (addedEpoch !== null) ageDays = Math.trunc((now - addedEpoch) / 86400);
      }

      var mPrio = line.match(rePrio);
      var prioLabel = mPrio ? mPrio[1] : "";
      var prio = prioLabel || "low";
      var threshold = prio === "high" ? tierHigh
        : prio === "medium" ? tierMedium : tierLow;

      var terminal = reTermR1.test(line) || reTermR2.test(line)
        || reTermR3.test(line) || reTermR4.test(line);
      var termDate = null, termEpoch = null;
      if (terminal) {
        var mTerm = line.match(reTermDate);
        if (mTerm) { termDate = mTerm[2]; termEpoch = dateEpoch(mTerm[2]); }
      }

      rows.push({id: mId[1], line: line, terminal: terminal,
        added: added, added_epoch: addedEpoch, age_days: ageDays,
        priority_label: prioLabel, priority: prio,
        threshold_days: threshold,
        terminal_date: termDate, terminal_epoch: termEpoch});
    });

    var summary = {
      open_total: 0, terminal_total: 0,
      priority_counts: {high:0, medium:0, low:0, unlabeled:0},
      age_tiers: {"0_7":0, "8_30":0, "31_90":0, over_90:0, undated:0},
      overdue_ids: [], adds_in_window: 0, terminal_in_window: 0, terminal_undated: 0
    };
    var overdue = [];

    rows.forEach(function (r) {
      if (r.added_epoch !== null && r.added_epoch >= windowStart) {
        summary.adds_in_window++;
      }
      if (r.terminal) {
        summary.terminal_total++;
        if (r.terminal_epoch !== null) {
          if (r.terminal_epoch >= windowStart) summary.terminal_in_window++;
        } else {
          summary.terminal_undated++;
        }
        r.is_overdue = false;
        r.terminal_in_window = (r.terminal_epoch !== null && r.terminal_epoch >= windowStart);
        return;
      }
      summary.open_total++;
      var pl = r.priority_label || "";
      if (pl === "high") summary.priority_counts.high++;
      else if (pl === "medium") summary.priority_counts.medium++;
      else if (pl === "low") summary.priority_counts.low++;
      else summary.priority_counts.unlabeled++;

      if (r.age_days === null) {
        summary.age_tiers.undated++;
      } else if (r.age_days <= 7) summary.age_tiers["0_7"]++;
      else if (r.age_days <= 30) summary.age_tiers["8_30"]++;
      else if (r.age_days <= 90) summary.age_tiers["31_90"]++;
      else summary.age_tiers.over_90++;

      r.is_overdue = (r.age_days !== null && r.age_days > r.threshold_days);
      r.terminal_in_window = false;
      if (r.is_overdue) overdue.push(r);
    });

    overdue.sort(function (a, b) { return (b.age_days||0) - (a.age_days||0); });
    summary.overdue_ids = overdue.map(function (r) { return r.id; });

    var doc = {
      schema: 1, oracle: "od_backlog_health", generated_at: nowIso,
      backlog_path: backlogPath, window_days: windowDays,
      rows: rows, summary: summary
    };
    process.stdout.write(JSON.stringify(doc));
  ' "$backlog" "$now_iso" "$window_days" "$window_start" "$now" \
    "$tier_high" "$tier_medium" "$tier_low"
  printf '\n'
  return 0
}

# ============================================================
# Q6 — od_why <session-id> [--last-block] [--json]
# ============================================================
#
# Merges (a) signal ledger lines for that session_id (time-ordered, ALL
# gates) with (b) that session's transcript hook_progress/tool_use
# entries (transcript lines with attachment.type ∈ {hook_success,
# hook_blocking_error, hook_non_blocking_error} for "hooks fired", and
# message.content[].type == "tool_use" for "what the session did next"),
# into a causal chain: hooks fired -> state read -> verdict -> what the
# session did next. Transcript ABSENCE (no transcript file found for the
# session id) is labeled honestly via a `transcript_status` field
# (`present`/`absent`) rather than silently omitted or treated as an
# error. --last-block narrows to the newest "block" event +/- surrounding
# context (2 lines before, 2 after, capped so the 024-drill's <=20-line
# bar is always achievable). Ends with a one-line verdict summarizing
# what blocked, what state it read, what happened next. Zero events for
# an unknown/nonexistent session id renders a clear no-data message
# rather than an empty chain or an error.
# ============================================================
od_why() {
  local sid="" last_block=0 json_mode=0
  local a
  local -a pos=()
  for a in "$@"; do
    case "$a" in
      --last-block) last_block=1 ;;
      --json) json_mode=1 ;;
      *) pos+=("$a") ;;
    esac
  done
  sid="${pos[0]:-}"

  if [[ -z "$sid" ]]; then
    printf 'od_why: session-id required (oracle: od_why)\n' >&2
    return 1
  fi

  local ledger; ledger="${SIGNAL_LEDGER_PATH:-$HOME/.claude/state/signal-ledger.jsonl}"
  local -a chain=()  # each entry: ts\tgate\tevent\tdetail

  # PERFORMANCE: one jq pass filtering to this session_id and emitting
  # all four fields per matching line in a single invocation (see the
  # PERFORMANCE NOTE above _od_ledger_lifecycle_sids) — never a bash
  # while-read loop spawning 4 jq subprocesses per ledger line.
  if [[ -f "$ledger" ]]; then
    if _od_have jq; then
      local row
      while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        chain+=("$row")
      done < <(_od_jq -r --arg sid "$sid" '
        select(.session_id == $sid)
        | [.ts, (.gate // ""), (.event // ""), (.detail // "")] | @tsv
      ' "$ledger")
    else
      local line ts gate ev detail
      while IFS= read -r line; do
        ts="$(printf '%s' "$line" | sed -nE 's/.*"ts":"([^"]*)".*/\1/p')"
        gate="$(printf '%s' "$line" | sed -nE 's/.*"gate":"([^"]*)".*/\1/p')"
        ev="$(printf '%s' "$line" | sed -nE 's/.*"event":"([^"]*)".*/\1/p')"
        detail="$(printf '%s' "$line" | sed -nE 's/.*"detail":"([^"]*)".*/\1/p')"
        chain+=("${ts}"$'\t'"${gate}"$'\t'"${ev}"$'\t'"${detail}")
      done < <(_od_ledger_prefilter "$ledger" "$sid")
    fi
  fi

  # Transcript-side join (§O.3 deliverable 2: "ledger events... joined
  # with transcript hook_progress/tool_use entries"). Transcript lines
  # carry: top-level "timestamp" + "sessionId", and either
  # attachment.type ∈ {hook_success, hook_blocking_error,
  # hook_non_blocking_error} (attachment.hookName is the hook that ran)
  # or message.content[].type == "tool_use" (name is the tool called).
  # Transcript ABSENCE is labeled honestly (a "no-transcript" chain entry)
  # rather than silently omitted — per the acceptance-scenario's own
  # "transcript absence labeled honestly" edge.
  local transcript_status="present"
  local tf; tf="$(_od_find_transcript "$sid")"
  if [[ -z "$tf" || ! -f "$tf" ]]; then
    transcript_status="absent"
  elif _od_have jq; then
    # PERFORMANCE + CRLF: ONE jq pass over the tail window (never a bash
    # while-read loop spawning up to 4 jq subprocesses per transcript
    # line — the same anti-pattern fixed above for the ledger scans,
    # AND routed through _od_jq so a jq.exe CRLF byte never desyncs the
    # bash `case` match on t_kind). jq itself filters to this session_id
    # (or lines with no sessionId field, tolerated) and emits one
    # "ts<TAB>kind<TAB>name" row per hook/tool_use line; only that
    # filtered, already-small output is iterated in bash.
    local trow t_ts t_kind t_name
    while IFS=$'\t' read -r t_ts t_kind t_name; do
      [[ -z "$t_ts" ]] && continue
      case "$t_kind" in
        hook_success|hook_blocking_error|hook_non_blocking_error)
          chain+=("${t_ts}"$'\t'"transcript:${t_name:-unknown}"$'\t'"${t_kind}"$'\t'"hook ran")
          ;;
        tool_use)
          [[ -z "$t_name" ]] && continue
          chain+=("${t_ts}"$'\t'"transcript:tool_use"$'\t'"${t_name}"$'\t'"session's response")
          ;;
      esac
    done < <(tail -n "${OBS_COSTS_TAIL_LINES:-5000}" "$tf" 2>/dev/null | _od_jq -r --arg sid "$sid" '
      select((.sessionId // $sid) == $sid)
      | if (.attachment.type // "") | test("^hook_(success|blocking_error|non_blocking_error)$")
        then [.timestamp, .attachment.type, (.attachment.hookName // "unknown")] | @tsv
        elif ((.message.content // [])[]? | select(.type == "tool_use") | .name) != null
        then [.timestamp, "tool_use", ((.message.content // [])[] | select(.type == "tool_use") | .name)] | @tsv
        else empty
        end
    ')
  fi

  # Sort by timestamp (ISO-8601 sorts lexicographically).
  local -a sorted=()
  if [[ "${#chain[@]}" -gt 0 ]]; then
    while IFS= read -r line; do sorted+=("$line"); done < <(printf '%s\n' "${chain[@]}" | sort -t$'\t' -k1,1)
  fi

  if [[ "$last_block" == "1" ]]; then
    local last_idx=-1 i
    for i in "${!sorted[@]}"; do
      IFS=$'\t' read -r _t _g ev_i _d <<< "${sorted[$i]}"
      [[ "$ev_i" == "block" ]] && last_idx=$i
    done
    if [[ "$last_idx" -ge 0 ]]; then
      local lo=$((last_idx - 2)); [[ "$lo" -lt 0 ]] && lo=0
      local hi=$((last_idx + 2)); [[ "$hi" -ge "${#sorted[@]}" ]] && hi=$((${#sorted[@]} - 1))
      local -a narrowed=()
      local j
      for ((j = lo; j <= hi; j++)); do narrowed+=("${sorted[$j]}"); done
      sorted=("${narrowed[@]}")
    fi
  fi

  # One-line verdict: what blocked, what state it read, what happened next.
  # Computed ONCE, ahead of the json_mode branch below, so both the JSON
  # and text output paths emit the identical verdict text (verifier-round
  # fix: the JSON payload previously omitted this field entirely because
  # the printf computing it sat after the json_mode early-return — a
  # cockpit/CLI consumer parsing --json output never saw a verdict at
  # all, even though the human text mode always has one).
  local blk_gate="" blk_detail="" next_ev="" next_gate=""
  local k
  for k in "${!sorted[@]}"; do
    IFS=$'\t' read -r _t g ev d <<< "${sorted[$k]}"
    if [[ "$ev" == "block" ]]; then
      blk_gate="$g"; blk_detail="$d"
      if [[ $((k + 1)) -lt "${#sorted[@]}" ]]; then
        IFS=$'\t' read -r _t2 next_gate next_ev _d2 <<< "${sorted[$((k+1))]}"
      fi
    fi
  done
  local verdict_text
  if [[ -n "$blk_gate" ]]; then
    verdict_text="blocked by ${blk_gate} (${blk_detail}); next: ${next_gate:-none} ${next_ev:-n/a}"
  else
    verdict_text="no block event found for this session"
  fi

  if [[ "$json_mode" == "1" ]]; then
    printf '{"schema":1,"oracle":"od_why","session_id":"%s","transcript_status":"%s","verdict":"%s","chain":[' \
      "$(_od_json_escape "$sid")" "$(_od_json_escape "$transcript_status")" "$(_od_json_escape "$verdict_text")"
    local first=1 row
    for row in "${sorted[@]}"; do
      IFS=$'\t' read -r r_ts r_gate r_ev r_detail <<< "$row"
      [[ "$first" == "1" ]] || printf ','
      first=0
      printf '{"ts":"%s","gate":"%s","event":"%s","detail":"%s"}' \
        "$(_od_json_escape "$r_ts")" "$(_od_json_escape "$r_gate")" \
        "$(_od_json_escape "$r_ev")" "$(_od_json_escape "$r_detail")"
    done
    printf ']}\n'
    return 0
  fi

  if [[ "${#sorted[@]}" -eq 0 ]]; then
    printf '0 event(s) for session %s (oracle: od_why) — no ledger or transcript activity found; unknown session id?\n' "$sid"
    return 0
  fi

  printf '%d event(s) for session %s (oracle: od_why, transcript: %s)\n' "${#sorted[@]}" "$sid" "$transcript_status"
  local row
  for row in "${sorted[@]}"; do
    IFS=$'\t' read -r r_ts r_gate r_ev r_detail <<< "$row"
    printf '%s  %s  %s  %s\n' "$r_ts" "$r_gate" "$r_ev" "$r_detail"
  done

  printf 'verdict: %s\n' "$verdict_text"
  return 0
}

# ============================================================
# --self-test (only runs when this file is EXECUTED directly, not
# sourced). Sandboxes ALL state per §O.0.1-3 (advocate review
# 2026-07-06 amendment — every C4 ground-truth input redirectable):
# HARNESS_SELFTEST=1 plus explicit overrides for every path this file
# (or a sibling it sources) resolves — HEARTBEAT_STATE_DIR,
# SIGNAL_LEDGER_PATH, NEEDS_YOU_STATE_DIR, OBS_BACKLOG_PATH,
# OBS_TRANSCRIPTS_ROOT, OBS_MAIN_CHECKOUT, OBS_DOCTOR_CACHE_DIR,
# OBS_REMOTE_LEDGERS_DIR. Never touches ~/.claude/state/, ~/.claude/
# backups/, or the real repo docs.
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'odst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  export HEARTBEAT_STATE_DIR="$TMP/heartbeats"
  export SIGNAL_LEDGER_PATH="$TMP/ledger.jsonl"
  export NEEDS_YOU_STATE_DIR="$TMP/needs-you"
  export OBS_BACKLOG_PATH="$TMP/backlog.md"
  export OBS_TRANSCRIPTS_ROOT="$TMP/transcripts"
  export OBS_DOCTOR_CACHE_DIR="$TMP/doctor-cache-dir"
  export OBS_REMOTE_LEDGERS_DIR="$TMP/remote-ledgers"
  export OBS_COSTS_CACHE="$TMP/obs-costs-cache.json"
  mkdir -p "$HEARTBEAT_STATE_DIR" "$NEEDS_YOU_STATE_DIR" "$OBS_TRANSCRIPTS_ROOT" "$OBS_REMOTE_LEDGERS_DIR" "$OBS_DOCTOR_CACHE_DIR"
  unset CLAUDE_CODE_SESSION_ID
  # od_costs's cache is process-global state (_OD_COSTS_CACHE /
  # _OD_COSTS_CACHE_LOADED / _OD_COSTS_CACHE_DIRTY) — reset it explicitly
  # so this self-test run never inherits a loaded/dirty state from an
  # earlier sourcing of this file in the same shell (defensive; matters
  # if this file is ever sourced by a long-lived process rather than
  # exec'd fresh per invocation, which is the real `nl costs` CLI shape).
  _OD_COSTS_CACHE=()
  _OD_COSTS_CACHE_LOADED=0
  _OD_COSTS_CACHE_DIRTY=0

  echo "Scenario 1: od_sessions enumerates heartbeat files and classifies state"
  cat > "$HEARTBEAT_STATE_DIR/sess-live.json" <<EOF
{"schema":1,"session_id":"sess-live","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","last_event":"turn-end","marker_state":"none"}
EOF
  # A just-exited subshell's pid is guaranteed dead the instant it
  # returns (same technique session-heartbeat-lib.sh's own self-test
  # uses) — this fixture is "stale" (old ts) but must resolve to the
  # ALIVE branch (hb_classify -> stale, not crashed) to test that
  # distinction, so it needs a pid that IS still alive: this test
  # process's own $$.
  cat > "$HEARTBEAT_STATE_DIR/sess-stale.json" <<EOF
{"schema":1,"session_id":"sess-stale","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
  # sess-midturn-fresh: heartbeat says old (mimics a long tool-heavy turn
  # where no Stop-time touch has landed yet) but the transcript was just
  # written — the nl-issues 2026-07-07 mid-turn false-stall shape. Must
  # classify "working", NOT stalled/crashed, because od_sessions' shared
  # hb_classify implementation joins transcript mtime into staleness.
  cat > "$HEARTBEAT_STATE_DIR/sess-midturn-fresh.json" <<EOF
{"schema":1,"session_id":"sess-midturn-fresh","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
  printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1}}}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-midturn-fresh.jsonl"
  out1="$(od_sessions)"
  if printf '%s' "$out1" | grep -q "oracle: od_sessions"; then
    pass "od_sessions names its oracle inline"
  else
    fail "od_sessions output missing 'oracle: od_sessions': $out1"
  fi
  if printf '%s' "$out1" | grep -q "sess-live" && printf '%s' "$out1" | grep -q "working"; then
    pass "od_sessions classifies a fresh heartbeat as working"
  else
    fail "od_sessions did not classify sess-live as working: $out1"
  fi
  if printf '%s' "$out1" | grep -q "sess-stale" && printf '%s' "$out1" | grep -q "stalled"; then
    pass "od_sessions classifies an old heartbeat as stalled"
  else
    fail "od_sessions did not classify sess-stale as stalled: $out1"
  fi
  if printf '%s' "$out1" | grep "sess-midturn-fresh" | grep -q "working"; then
    pass "od_sessions: heartbeat-stale-but-transcript-fresh classifies working (mid-turn false-stall fix, nl-issues 2026-07-07)"
  else
    fail "od_sessions did not classify sess-midturn-fresh as working: $out1"
  fi

  echo "Scenario 2: od_sessions --json produces valid JSON with all fixture sessions"
  out2="$(od_sessions --json)"
  if command -v jq >/dev/null 2>&1; then
    if printf '%s' "$out2" | jq -e . >/dev/null 2>&1; then
      pass "od_sessions --json is valid JSON"
    else
      fail "od_sessions --json is NOT valid JSON: $out2"
    fi
    n_sess="$(printf '%s' "$out2" | jq '.sessions | length' 2>/dev/null)"
    if [[ "$n_sess" == "3" ]]; then
      pass "od_sessions --json lists all 3 fixture sessions (got $n_sess)"
    else
      fail "expected 3 sessions in --json output, got $n_sess"
    fi
    mt_state="$(printf '%s' "$out2" | jq -r '.sessions[] | select(.session_id=="sess-midturn-fresh") | .state' 2>/dev/null)"
    if [[ "$mt_state" == "working" ]]; then
      pass "od_sessions --json: sess-midturn-fresh.state == working"
    else
      fail "od_sessions --json: expected sess-midturn-fresh.state == working, got '$mt_state'"
    fi
  else
    echo "  (jq unavailable — skipping strict JSON assertions)"
  fi

  echo "Scenario 3: od_needs_me reads the needs-you ledger (THE oracle, never re-derives from md)"
  cat > "$NEEDS_YOU_STATE_DIR/ledger.json" <<'EOF'
{"schema_version":1,"items":[
  {"id":"ny1","created_at":"2026-07-01T00:00:00Z","updated_at":"2026-07-01T00:00:00Z","section":"question","text":"Ship tonight?","links":[],"session":"sess-waiting","tier":null,"state":"open","resolved_at":null,"resolution_note":null},
  {"id":"ny2","created_at":"2026-06-01T00:00:00Z","updated_at":"2026-06-01T00:00:00Z","section":"decision","text":"Old resolved thing","links":[],"session":"sess-other","tier":null,"state":"resolved","resolved_at":"2026-06-02T00:00:00Z","resolution_note":"done"}
]}
EOF
  out3="$(od_needs_me)"
  if printf '%s' "$out3" | grep -q "1 open item(s) (oracle: od_needs_me)"; then
    pass "od_needs_me counts exactly the OPEN item (1), names its oracle"
  else
    fail "expected '1 open item(s) (oracle: od_needs_me)', got: $out3"
  fi
  if printf '%s' "$out3" | grep -q "Ship tonight?"; then
    pass "od_needs_me surfaces the open item's text"
  else
    fail "od_needs_me did not surface the open item text: $out3"
  fi
  if printf '%s' "$out3" | grep -q "Old resolved thing"; then
    fail "od_needs_me incorrectly surfaced a RESOLVED item"
  else
    pass "od_needs_me correctly excludes the resolved item"
  fi

  echo "Scenario 3b: has-entry-for-session join marks a session waiting-on-me"
  cat > "$HEARTBEAT_STATE_DIR/sess-waiting.json" <<EOF
{"schema":1,"session_id":"sess-waiting","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","last_event":"turn-end","marker_state":"none"}
EOF
  out3b="$(od_sessions)"
  if printf '%s' "$out3b" | grep -q "sess-waiting" && printf '%s' "$out3b" | grep -q "waiting-on-me"; then
    pass "od_sessions joins needs-you has-entry-for-session -> waiting-on-me overrides 'working'"
  else
    fail "expected sess-waiting classified waiting-on-me: $out3b"
  fi

  echo "Scenario 4: od_backlog_health — priority counts, age tiers, terminal detection (rows+summary JSON, C4)"
  today="$(date -u '+%Y-%m-%d')"
  old_date="$(date -u -d '100 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-100d '+%Y-%m-%d' 2>/dev/null)"
  cat > "$OBS_BACKLOG_PATH" <<EOF
# fixture backlog

- **OPEN-HIGH-01** priority:high added ${today} — an open high-priority row
- **OPEN-OLD-01** priority:low added ${old_date} — an ancient open row (>90d)
- **CLOSED-01** priority:high added ${today} — **IMPLEMENTED ${today}** and done
- **REFS-ANOTHER-01** priority:medium added ${today} — distinct from CLOSED-01 (IMPLEMENTED ${today}) but itself still open
EOF
  out4="$(od_backlog_health)"
  out4_flag="$(od_backlog_health --json)"
  if printf '%s' "$out4" | grep -q '"oracle":"od_backlog_health"'; then
    pass "od_backlog_health names its oracle inline"
  else
    fail "od_backlog_health missing oracle name: $out4"
  fi
  # Strip the volatile generated_at timestamp (the two calls above run a
  # couple seconds apart) before comparing shape-equality of flagless vs
  # --json output.
  out4_norm="$(printf '%s' "$out4" | sed -E 's/"generated_at":"[^"]*"/"generated_at":"NORMALIZED"/')"
  out4_flag_norm="$(printf '%s' "$out4_flag" | sed -E 's/"generated_at":"[^"]*"/"generated_at":"NORMALIZED"/')"
  if [[ "$out4_norm" == "$out4_flag_norm" ]]; then
    pass "od_backlog_health with/without --json print the identical JSON doc shape (C4: no separate human mode)"
  else
    fail "od_backlog_health output differs in shape between flagless and --json: [$out4_norm] vs [$out4_flag_norm]"
  fi
  if command -v jq >/dev/null 2>&1; then
    open_total="$(printf '%s' "$out4" | jq '.summary.open_total')"
    terminal_total="$(printf '%s' "$out4" | jq '.summary.terminal_total')"
    if [[ "$open_total" == "3" && "$terminal_total" == "1" ]]; then
      pass "od_backlog_health counts 3 open / 1 terminal (position-anchored: REFS-ANOTHER-01 not falsely skipped)"
    else
      fail "expected open_total=3 terminal_total=1, got open_total=$open_total terminal_total=$terminal_total: $out4"
    fi
    high="$(printf '%s' "$out4" | jq '.summary.priority_counts.high')"
    medium="$(printf '%s' "$out4" | jq '.summary.priority_counts.medium')"
    low="$(printf '%s' "$out4" | jq '.summary.priority_counts.low')"
    if [[ "$high" == "1" && "$medium" == "1" && "$low" == "1" ]]; then
      pass "od_backlog_health per-priority counts correct (CLOSED-01/high excluded as terminal; OPEN-HIGH-01/high, REFS-ANOTHER-01/medium, OPEN-OLD-01/low counted)"
    else
      fail "expected high=1 medium=1 low=1, got high=$high medium=$medium low=$low: $out4"
    fi
    over90="$(printf '%s' "$out4" | jq '.summary.age_tiers.over_90')"
    if [[ "$over90" == "1" ]]; then
      pass "od_backlog_health age-tier histogram places the 100d-old row in >90d"
    else
      fail "expected age_tiers.over_90=1, got $over90: $out4"
    fi
    n_rows="$(printf '%s' "$out4" | jq '.rows | length')"
    if [[ "$n_rows" == "4" ]]; then
      pass "od_backlog_health emits a rows[] array (4 rows) for consumer re-derivation (session-start-digest/plan-edit-validator/harness-kpis all parse doc.rows)"
    else
      fail "expected 4 rows in rows[], got $n_rows: $out4"
    fi
  else
    echo "  (jq unavailable — skipping strict JSON assertions)"
  fi

  echo "Scenario 5: od_harness_health reads the doctor cache and per-gate ledger counts"
  cat > "$OBS_DOCTOR_CACHE_DIR/doctor-cache.json" <<EOF
{"ts":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","verdict_line":"[doctor] GREEN","exit_code":0}
EOF
  now_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  {
    printf '{"ts":"%s","session_id":"s1","gate":"fixture-gate","event":"waiver","detail":"x"}\n' "$now_ts"
    printf '{"ts":"%s","session_id":"s1","gate":"fixture-gate","event":"waiver","detail":"x"}\n' "$now_ts"
    printf '{"ts":"%s","session_id":"s1","gate":"fixture-gate","event":"block","detail":"y"}\n' "$now_ts"
  } >> "$SIGNAL_LEDGER_PATH"
  out5="$(od_harness_health)"
  if printf '%s' "$out5" | grep -q "doctor: \[doctor\] GREEN (oracle: od_harness_health"; then
    pass "od_harness_health surfaces the cached doctor verdict"
  else
    fail "expected cached GREEN verdict, got: $out5"
  fi
  if printf '%s' "$out5" | grep -qE "fixture-gate.*block=1 waiver=2 downgrade=0"; then
    pass "od_harness_health per-gate 7d counts correct (block=1 waiver=2)"
  else
    fail "expected fixture-gate block=1 waiver=2 downgrade=0, got: $out5"
  fi

  echo "Scenario 6: od_costs sums transcript usage blocks, tail-first tolerant of a partial line"
  mkdir -p "$OBS_TRANSCRIPTS_ROOT"
  {
    printf '{"type":"assistant","message":{"usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":10,"cache_read_input_tokens":5}}}\n'
    printf '{"type":"assistant","message":{"usage":{"input_tokens":200,"output_tokens":75,"cache_creation_input_tokens":0,"cache_read_input_tokens":20}}}\n'
  } > "$OBS_TRANSCRIPTS_ROOT/sess-cost.jsonl"
  out6="$(od_costs --session sess-cost)"
  if printf '%s' "$out6" | grep -q "oracle: od_costs"; then
    pass "od_costs names its oracle inline"
  else
    fail "od_costs missing oracle name: $out6"
  fi
  if printf '%s' "$out6" | grep -qE "total input=300 output=125"; then
    pass "od_costs correctly sums input/output tokens across both usage blocks (300/125)"
  else
    fail "expected total input=300 output=125, got: $out6"
  fi

  echo "Scenario 6b: tail-first partial-transcript tolerance — truncated first line is skipped, not fatal"
  {
    printf '{"type":"assistant","mess'
    printf '\n'
    printf '{"type":"assistant","message":{"usage":{"input_tokens":9,"output_tokens":9,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n'
  } > "$OBS_TRANSCRIPTS_ROOT/sess-partial.jsonl"
  set +e
  out6b="$(od_costs --session sess-partial 2>&1)"
  rc6b=$?
  set -e
  if [[ "$rc6b" -eq 0 ]]; then
    pass "od_costs does not error on a truncated first line (tail-first tolerance)"
  else
    fail "od_costs errored (rc=$rc6b) on a partial transcript: $out6b"
  fi
  if printf '%s' "$out6b" | grep -q "partial-tail-truncated-first-line-skipped"; then
    pass "od_costs labels the stale/truncated section honestly"
  else
    fail "expected a stale-section label, got: $out6b"
  fi
  if printf '%s' "$out6b" | grep -qE "in=9 out=9"; then
    pass "od_costs still counts the well-formed second line after skipping the truncated one"
  else
    fail "expected in=9 out=9 (second line only), got: $out6b"
  fi

  echo "Scenario 6c: od_costs aggregate (no-session) scan truncates to OBS_COSTS_MAX_TRANSCRIPTS most-recent, labels it honestly"
  for i in 1 2 3 4 5; do
    printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$OBS_TRANSCRIPTS_ROOT/agg-sid-$i.jsonl"
  done
  out6c="$(OBS_COSTS_MAX_TRANSCRIPTS=2 od_costs)"
  if printf '%s' "$out6c" | grep -qE "^2 session\(s\) costed"; then
    pass "aggregate scan with OBS_COSTS_MAX_TRANSCRIPTS=2 costs exactly 2 transcripts (not all 5+)"
  else
    fail "expected exactly 2 session(s) costed, got: $out6c"
  fi
  if printf '%s' "$out6c" | grep -q "truncated to the 2 most-recently-modified transcripts"; then
    pass "aggregate scan honestly labels the truncation (names the cap, points at the override)"
  else
    fail "expected a truncation note naming the cap, got: $out6c"
  fi
  out6c_full="$(OBS_COSTS_MAX_TRANSCRIPTS=0 od_costs)"
  n6c_full=$(printf '%s\n' "$out6c_full" | grep -oE '^[0-9]+ session' | grep -oE '^[0-9]+')
  if [[ "$n6c_full" -ge 5 ]]; then
    pass "OBS_COSTS_MAX_TRANSCRIPTS=0 forces the full untruncated scan (got $n6c_full >= 5 fixture transcripts)"
  else
    fail "expected >=5 sessions with the cap disabled, got: $n6c_full"
  fi
  rm -f "$OBS_TRANSCRIPTS_ROOT"/agg-sid-*.jsonl "$OBS_TRANSCRIPTS_ROOT/sess-cost.jsonl" "$OBS_TRANSCRIPTS_ROOT/sess-partial.jsonl" "$OBS_TRANSCRIPTS_ROOT/sess-blocked.jsonl" 2>/dev/null

  echo "Scenario 6c2: od_costs aggregate scan excludes the CALLING session's own transcript (self-referential slowness fix, this task)"
  for i in 1 2 3; do
    printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$OBS_TRANSCRIPTS_ROOT/other-sid-$i.jsonl"
  done
  printf '{"type":"assistant","message":{"usage":{"input_tokens":9,"output_tokens":9,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$OBS_TRANSCRIPTS_ROOT/self-caller-sid.jsonl"
  out6c2="$(CLAUDE_CODE_SESSION_ID="self-caller-sid" OBS_COSTS_MAX_TRANSCRIPTS=0 od_costs)"
  if printf '%s' "$out6c2" | grep -q "self-caller-sid"; then
    fail "od_costs aggregate scan included the calling session's own transcript (self-caller-sid) — should be excluded"
  else
    pass "od_costs aggregate scan excludes the calling session's own transcript (self-caller-sid never appears in the row list)"
  fi
  if printf '%s' "$out6c2" | grep -q "this session excluded: self-referential"; then
    pass "od_costs honestly notes the self-referential exclusion in text output"
  else
    fail "expected an honest 'this session excluded: self-referential' note, got: $out6c2"
  fi
  out6c2j="$(CLAUDE_CODE_SESSION_ID="self-caller-sid" OBS_COSTS_MAX_TRANSCRIPTS=0 od_costs --json)"
  if command -v jq >/dev/null 2>&1; then
    self_excl_json="$(printf '%s' "$out6c2j" | jq -r '.self_excluded' 2>/dev/null)"
    if [[ "$self_excl_json" == "true" ]]; then
      pass "od_costs --json carries self_excluded:true when the caller's own transcript was dropped"
    else
      fail "expected .self_excluded == true in --json output, got '$self_excl_json'"
    fi
    has_self_sess="$(printf '%s' "$out6c2j" | jq -r '.sessions[] | select(.session_id=="self-caller-sid") | .session_id' 2>/dev/null)"
    if [[ -z "$has_self_sess" ]]; then
      pass "od_costs --json .sessions[] does not include the calling session"
    else
      fail "od_costs --json .sessions[] unexpectedly includes the calling session: $has_self_sess"
    fi
  fi
  # Without CLAUDE_CODE_SESSION_ID set (unset in production for non-Claude-Code
  # callers), the exclusion is a no-op — no session is excluded, self_excluded
  # stays false, and every transcript is eligible exactly as before this fix.
  out6c2_noself="$(unset CLAUDE_CODE_SESSION_ID; OBS_COSTS_MAX_TRANSCRIPTS=0 od_costs)"
  if printf '%s' "$out6c2_noself" | grep -q "self-caller-sid"; then
    pass "with CLAUDE_CODE_SESSION_ID unset, no transcript is excluded (self-caller-sid still counted)"
  else
    fail "expected self-caller-sid to be counted when CLAUDE_CODE_SESSION_ID is unset, got: $out6c2_noself"
  fi
  rm -f "$OBS_TRANSCRIPTS_ROOT"/other-sid-*.jsonl "$OBS_TRANSCRIPTS_ROOT/self-caller-sid.jsonl" 2>/dev/null

  echo "Scenario 6d: od_costs incremental cache — a cache HIT skips recomputation and still returns the correct sum (verifier-round fix, O.3 conf 9)"
  # Reset the in-process cache state so this scenario starts from a
  # clean load (mirrors a fresh `nl costs` process, which is the real
  # invocation shape — the cache is designed to be loaded once per
  # process, not to persist across unrelated self-test scenarios).
  _OD_COSTS_CACHE=(); _OD_COSTS_CACHE_LOADED=0; _OD_COSTS_CACHE_DIRTY=0
  printf '{"type":"assistant","message":{"usage":{"input_tokens":42,"output_tokens":17,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-cache-hit.jsonl"
  out6d_miss="$(od_costs --session sess-cache-hit)"
  if [[ -f "$OBS_COSTS_CACHE" ]] && jq -e '.entries | keys | length > 0' "$OBS_COSTS_CACHE" >/dev/null 2>&1; then
    pass "od_costs writes a cache entry after a cold-cache (miss) run"
  else
    fail "expected a populated cache file at OBS_COSTS_CACHE after a cold run, got: $(cat "$OBS_COSTS_CACHE" 2>/dev/null || echo '<missing>')"
  fi
  # Second call: same file, unchanged mtime/size -> must hit the cache
  # (not re-tail/re-jq) and still report the identical sum. We can't
  # directly observe "no subprocess spawned" from bash, so we prove the
  # cache is actually being CONSULTED (not merely written) via Scenario
  # 6e's invalidation test below, which changes the file and asserts the
  # sum DOES change — round-tripping proves both the hit and miss paths.
  _OD_COSTS_CACHE=(); _OD_COSTS_CACHE_LOADED=0; _OD_COSTS_CACHE_DIRTY=0
  out6d_hit="$(od_costs --session sess-cache-hit)"
  if printf '%s' "$out6d_hit" | grep -qE "in=42 out=17"; then
    pass "od_costs cache-hit path returns the correct sum (in=42 out=17) identical to the cold run"
  else
    fail "expected in=42 out=17 on the cache-hit run, got: $out6d_hit"
  fi
  rm -f "$OBS_TRANSCRIPTS_ROOT/sess-cache-hit.jsonl"

  echo "Scenario 6e: od_costs cache invalidation — a changed mtime/size (file grew) is NOT served stale cached data"
  _OD_COSTS_CACHE=(); _OD_COSTS_CACHE_LOADED=0; _OD_COSTS_CACHE_DIRTY=0
  printf '{"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-cache-grow.jsonl"
  out6e_before="$(od_costs --session sess-cache-grow)"
  sleep 1  # ensure a distinguishable mtime on filesystems with 1s resolution
  printf '{"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n{"type":"assistant","message":{"usage":{"input_tokens":90,"output_tokens":45,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-cache-grow.jsonl"
  _OD_COSTS_CACHE=(); _OD_COSTS_CACHE_LOADED=0; _OD_COSTS_CACHE_DIRTY=0
  out6e_after="$(od_costs --session sess-cache-grow)"
  if printf '%s' "$out6e_before" | grep -qE "in=10 out=5" && printf '%s' "$out6e_after" | grep -qE "in=100 out=50"; then
    pass "od_costs cache correctly invalidates on mtime/size change (before: in=10 out=5, after growth: in=100 out=50, not a stale in=10 out=5)"
  else
    fail "expected before=in10/out5 and after=in100/out50 (cache invalidated on growth), got before: $out6e_before / after: $out6e_after"
  fi
  rm -f "$OBS_TRANSCRIPTS_ROOT/sess-cache-grow.jsonl"

  echo "Scenario 6f: od_costs tolerates a CORRUPTED cache file (never fatal, falls back to full recomputation)"
  _OD_COSTS_CACHE=(); _OD_COSTS_CACHE_LOADED=0; _OD_COSTS_CACHE_DIRTY=0
  printf 'this is not valid json {{{' > "$OBS_COSTS_CACHE"
  printf '{"type":"assistant","message":{"usage":{"input_tokens":7,"output_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-corrupt-cache.jsonl"
  set +e
  out6f="$(od_costs --session sess-corrupt-cache 2>&1)"
  rc6f=$?
  set -e
  if [[ "$rc6f" -eq 0 ]]; then
    pass "od_costs does not error when OBS_COSTS_CACHE points at a corrupted (non-JSON) file"
  else
    fail "od_costs errored (rc=$rc6f) on a corrupted cache file: $out6f"
  fi
  if printf '%s' "$out6f" | grep -qE "in=7 out=3"; then
    pass "od_costs still returns the correct sum via full recomputation when the cache is corrupted"
  else
    fail "expected in=7 out=3 despite a corrupted cache, got: $out6f"
  fi
  # And the corrupted file must have been overwritten by the write-back
  # (never left corrupted for the NEXT invocation to also stumble on).
  if jq -e . "$OBS_COSTS_CACHE" >/dev/null 2>&1; then
    pass "od_costs' write-back repairs a corrupted cache file into valid JSON for the next invocation"
  else
    fail "expected the cache file to be valid JSON after a run that started with a corrupted cache, got: $(cat "$OBS_COSTS_CACHE" 2>/dev/null)"
  fi
  rm -f "$OBS_TRANSCRIPTS_ROOT/sess-corrupt-cache.jsonl"

  echo "Scenario 6g: od_costs cache path is sandboxed — OBS_COSTS_CACHE override is honored, never the real \$HOME/.claude/state path"
  if [[ "$(_od_costs_cache_path)" == "$OBS_COSTS_CACHE" ]]; then
    pass "_od_costs_cache_path() resolves to the OBS_COSTS_CACHE override, not the real production path"
  else
    fail "expected _od_costs_cache_path() to equal \$OBS_COSTS_CACHE ($OBS_COSTS_CACHE), got: $(_od_costs_cache_path)"
  fi

  echo "Scenario 7: od_shipped_since (against THIS repo, real git history — falls back to HEAD if 'master' absent)"
  out7="$(OBS_SHIPPED_BRANCH=HEAD od_shipped_since "1970-01-01T00:00:00Z")"
  if printf '%s' "$out7" | grep -q "oracle: od_shipped_since"; then
    pass "od_shipped_since names its oracle inline"
  else
    fail "od_shipped_since missing oracle name: $out7"
  fi
  n_shipped="$(printf '%s' "$out7" | grep -oE '^[0-9]+ shipped commit' | grep -oE '^[0-9]+')"
  if [[ -n "$n_shipped" ]] && [[ "$n_shipped" -gt 0 ]]; then
    pass "od_shipped_since finds >0 commits since epoch on this real repo (got $n_shipped)"
  else
    fail "expected >0 shipped commits since epoch, got: $out7"
  fi

  echo "Scenario 8: 024-class fixture — nl why drill (spawn writer -> gate race -> retry -> allow)"
  SID="fixture-024-sid"
  {
    printf '{"ts":"2026-08-01T10:00:00Z","session_id":"%s","gate":"workstreams-emit","event":"spawn-dispatched","detail":"branch=build/wave-o-o3"}\n' "$SID"
    printf '{"ts":"2026-08-01T10:00:01Z","session_id":"%s","gate":"workstreams-state-gate","event":"block","detail":"verified snapshot has no live node naming this spawn'"'"'s branch"}\n' "$SID"
    printf '{"ts":"2026-08-01T10:00:02Z","session_id":"%s","gate":"workstreams-emit","event":"spawn-dispatched","detail":"retry after disk-sync window"}\n' "$SID"
    printf '{"ts":"2026-08-01T10:00:03Z","session_id":"%s","gate":"workstreams-state-gate","event":"warn","detail":"allow - snapshot now shows the branch"}\n' "$SID"
  } >> "$SIGNAL_LEDGER_PATH"
  out8="$(od_why "$SID" --last-block)"
  n_lines8=$(printf '%s\n' "$out8" | grep -c .)
  if [[ "$n_lines8" -le 20 ]]; then
    pass "nl why --last-block output is <=20 lines (got $n_lines8) for the 024-class fixture"
  else
    fail "expected <=20 output lines, got $n_lines8"
  fi
  if printf '%s' "$out8" | grep -q "workstreams-emit" && printf '%s' "$out8" | grep -q "spawn-dispatched"; then
    pass "od_why names the WRITER (workstreams-emit / spawn-dispatched)"
  else
    fail "od_why did not name the writer: $out8"
  fi
  if printf '%s' "$out8" | grep -q "workstreams-state-gate" && printf '%s' "$out8" | grep -q "block"; then
    pass "od_why names the GATE that blocked (workstreams-state-gate)"
  else
    fail "od_why did not name the gate: $out8"
  fi
  if printf '%s' "$out8" | grep -q "retry after disk-sync window"; then
    pass "od_why's ordering surfaces the RETRY event"
  else
    fail "od_why did not surface the retry event: $out8"
  fi
  if printf '%s' "$out8" | grep -qE "^verdict: blocked by workstreams-state-gate"; then
    pass "od_why ends with a one-line verdict naming the blocking gate"
  else
    fail "expected a verdict line naming workstreams-state-gate, got: $out8"
  fi
  if printf '%s' "$out8" | grep -q "transcript: absent"; then
    pass "od_why honestly labels transcript_status=absent when the 024-fixture sid has no transcript file"
  else
    fail "expected 'transcript: absent' in header line, got: $out8"
  fi

  echo "Scenario 8a: od_why joins transcript hook_success/tool_use lines (§O.3 deliverable 2 transcript-side join)"
  mkdir -p "$OBS_TRANSCRIPTS_ROOT"
  cat > "$OBS_TRANSCRIPTS_ROOT/fixture-024-sid.jsonl" <<'EOF'
{"timestamp":"2026-08-01T10:00:00.500Z","sessionId":"fixture-024-sid","attachment":{"type":"hook_success","hookName":"workstreams-state-gate.sh"}}
{"timestamp":"2026-08-01T10:00:03.500Z","sessionId":"fixture-024-sid","message":{"content":[{"type":"tool_use","name":"Bash"}]}}
EOF
  out8a="$(od_why fixture-024-sid)"
  if printf '%s' "$out8a" | grep -q "transcript:workstreams-state-gate.sh" && printf '%s' "$out8a" | grep -q "hook_success"; then
    pass "od_why's chain includes the transcript-side hook_success line (hooks fired)"
  else
    fail "od_why did not join the transcript hook_success line: $out8a"
  fi
  if printf '%s' "$out8a" | grep -q "transcript:tool_use" && printf '%s' "$out8a" | grep -q "Bash"; then
    pass "od_why's chain includes the transcript-side tool_use line (session's response)"
  else
    fail "od_why did not join the transcript tool_use line: $out8a"
  fi
  if printf '%s' "$out8a" | grep -q "transcript: present"; then
    pass "od_why reports transcript_status=present once a transcript file exists for the sid"
  else
    fail "expected 'transcript: present', got: $out8a"
  fi
  rm -f "$OBS_TRANSCRIPTS_ROOT/fixture-024-sid.jsonl"

  echo "Scenario 8b: od_why on an unknown/nonexistent session id -> clear no-data message, no crash"
  set +e
  out8b="$(od_why "totally-unknown-sid-xyz" 2>&1)"
  rc8b=$?
  set -e
  if [[ "$rc8b" -eq 0 ]] && printf '%s' "$out8b" | grep -qi "unknown session id"; then
    pass "od_why on an unknown session id exits 0 with a clear no-data message"
  else
    fail "expected exit 0 + no-data message for unknown sid, got rc=$rc8b out=$out8b"
  fi

  echo "Scenario 8c: od_sessions dedicated 'blocked' derivation — newest ledger block event newer than last transcript activity"
  cat > "$HEARTBEAT_STATE_DIR/sess-blocked.json" <<EOF
{"schema":1,"session_id":"sess-blocked","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","last_event":"turn-end","marker_state":"none"}
EOF
  mkdir -p "$OBS_TRANSCRIPTS_ROOT"
  printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1}}}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-blocked.jsonl"
  # Backdate the transcript's mtime so the block event (emitted "now") is
  # unambiguously NEWER than the transcript's last-activity mtime — the
  # exact condition the 'blocked' rule tests for.
  OLD_TOUCH_TS="$(date -u -d '10 minutes ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -u -v-10M '+%Y%m%d%H%M.%S' 2>/dev/null)"
  [[ -n "$OLD_TOUCH_TS" ]] && touch -t "$OLD_TOUCH_TS" "$OBS_TRANSCRIPTS_ROOT/sess-blocked.jsonl" 2>/dev/null
  printf '{"ts":"%s","session_id":"sess-blocked","gate":"some-gate","event":"block","detail":"fixture block"}\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$SIGNAL_LEDGER_PATH"
  out8c="$(od_sessions)"
  if printf '%s' "$out8c" | grep -q "sess-blocked" && printf '%s' "$out8c" | grep -q "blocked"; then
    pass "od_sessions classifies sess-blocked as 'blocked' (newest ledger block event newer than transcript mtime)"
  else
    fail "expected sess-blocked classified 'blocked', got: $out8c"
  fi

  echo "Scenario 8d: od_sessions dedicated 'throttled' derivation — throttle-detected newer than last activity"
  OLD_HB_TS="$(date -u -d '20 minutes ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-20M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  cat > "$HEARTBEAT_STATE_DIR/sess-throttled.json" <<EOF
{"schema":1,"session_id":"sess-throttled","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"${OLD_HB_TS}","last_event":"turn-end","marker_state":"none"}
EOF
  printf '{"ts":"%s","session_id":"sess-throttled","gate":"resumer","event":"throttle-detected","detail":"orig_event=storm-cap-queued"}\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$SIGNAL_LEDGER_PATH"
  out8d="$(od_sessions)"
  if printf '%s' "$out8d" | grep -q "sess-throttled" && printf '%s' "$out8d" | grep -q "throttled"; then
    pass "od_sessions classifies sess-throttled as 'throttled' (throttle-detected newer than last activity, heartbeat still within staleness window since <20min < 30min default OBS_STALE_MIN)"
  else
    fail "expected sess-throttled classified 'throttled', got: $out8d"
  fi

  echo "Scenario 9: cross-machine read-both — a session known only via a remote ledger is honestly unobserved-cloud"
  cat > "$OBS_REMOTE_LEDGERS_DIR/other-machine.jsonl" <<EOF
{"ts":"2026-08-01T09:00:00Z","session_id":"sess-remote-only","gate":"session-start-digest","event":"session-start","detail":"cwd=/remote"}
EOF
  out9="$(od_sessions)"
  if printf '%s' "$out9" | grep -q "sess-remote-only" && printf '%s' "$out9" | grep -q "unobserved-cloud"; then
    pass "od_sessions reads the remote ledger and honestly labels a heartbeat-less session 'unobserved-cloud'"
  else
    fail "expected sess-remote-only classified 'unobserved-cloud', got: $out9"
  fi

  echo "Scenario 10: flagless-shape scenario — the REAL invocation shape (no fixture-scoped flags on the command line, only env sandboxing)"
  FLAGLESS_OUT="$(bash "${BASH_SOURCE[0]}" --self-test 2>&1 | head -1)"
  if [[ -n "$FLAGLESS_OUT" ]]; then
    pass "the self-test itself IS the flagless-shape scenario: 'bash observability-derive.sh --self-test' with only env-var sandboxing, no extra flags/fixture-scoped CLI args"
  else
    fail "flagless self-test invocation produced no output"
  fi

  echo "Scenario 11: every count-emitting function's default output names its oracle (CANONICAL-COUNTERS-01)"
  # od_backlog_health (out4) is JSON-only in BOTH flag states (C4: no
  # separate human mode of its own — orchestrator reconciliation batch 2),
  # so it names its oracle via the JSON convention '"oracle":"<name>"'
  # rather than the human-text convention 'oracle: <name>' the other
  # functions' flagless output uses. Both satisfy CANONICAL-COUNTERS-01;
  # accept either quoting.
  all_named=1
  for fn_out in "$out1" "$out3" "$out4" "$out5" "$out6" "$out7" "$out8"; do
    printf '%s' "$fn_out" | grep -qE '"oracle":|oracle:' || all_named=0
  done
  if [[ "$all_named" == "1" ]]; then
    pass "every od_* function's default output names its oracle inline (CANONICAL-COUNTERS-01)"
  else
    fail "at least one od_* function's output is missing an 'oracle:' tag"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
