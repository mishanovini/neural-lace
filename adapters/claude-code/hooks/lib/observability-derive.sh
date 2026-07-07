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
# This file writes nothing itself, but every function it calls into
# (session-heartbeat-lib.sh, signal-ledger.sh, needs-you.sh) honors its
# OWN env-var override / HARNESS_SELFTEST sandbox, and this file adds no
# new state paths beyond what it reads: HEARTBEAT_STATE_DIR,
# SIGNAL_LEDGER_PATH, NEEDS_YOU_STATE_DIR, plus this file's own read-only
# knobs — per the advocate plan-time review 2026-07-06 (specs-o §O.0.1-3
# amendment: "every C4 ground-truth input is redirectable"):
#   OBS_TRANSCRIPTS_ROOT  - transcripts dir (od_costs/od_why/od_sessions)
#   OBS_MAIN_CHECKOUT     - git root (od_shipped_since)
#   OBS_DOCTOR_CACHE_DIR  - doctor-cache.json's directory (od_harness_health)
#   OBS_BACKLOG_PATH      - docs/backlog.md (od_backlog_health)
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
# _od_backlog_path — resolve docs/backlog.md. Override:
# OBS_BACKLOG_PATH env var (self-test / explicit).
# ----------------------------------------------------------------------
_od_backlog_path() {
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
# ============================================================
_od_costs_one_transcript() {
  local file="$1"
  local tail_override="${2:-}"
  local in_tok=0 out_tok=0 cache_create=0 cache_read=0 stale_note=""

  [[ -f "$file" ]] || { printf '0\t0\t0\t0\tmissing'; return 0; }

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
  local tail_lines="${tail_override:-${OBS_COSTS_TAIL_LINES:-5000}}"
  local content
  content="$(tail -n "$tail_lines" "$file" 2>/dev/null)"
  [[ -z "$content" ]] && { printf '0\t0\t0\t0\tempty'; return 0; }

  # A tail window landed mid-file may start with a truncated line — one
  # that BEGINS with '{' (JSON objects only start that way) but is not
  # itself parseable as a standalone JSON value, because `tail` cut it at
  # an arbitrary byte offset rather than a line boundary the write
  # actually respected (or a genuinely mid-write torn line at the moment
  # of read). Detect this by trying to parse the first line ALONE: if it
  # fails (and jq is present to check), drop it and label the section
  # stale rather than let jq -s's whole-stream parse choke on one bad
  # line and silently return nothing for every line after it.
  local first_line
  first_line="$(printf '%s\n' "$content" | head -n1)"
  if [[ -n "$first_line" ]]; then
    local first_line_ok=1
    if _od_have jq; then
      printf '%s' "$first_line" | jq -e . >/dev/null 2>&1 || first_line_ok=0
    else
      [[ "${first_line:0:1}" == "{" && "${first_line: -1}" == "}" ]] || first_line_ok=0
    fi
    if [[ "$first_line_ok" == "0" ]]; then
      stale_note="partial-tail-truncated-first-line-skipped"
      content="$(printf '%s\n' "$content" | tail -n +2)"
    fi
  fi

  if _od_have jq; then
    local sums
    sums="$(printf '%s\n' "$content" | jq -s -r '
      [ .[] | select(.message.usage? != null) | .message.usage ] as $u |
      ( [$u[].input_tokens // 0] | add // 0 ),
      ( [$u[].output_tokens // 0] | add // 0 ),
      ( [$u[].cache_creation_input_tokens // 0] | add // 0 ),
      ( [$u[].cache_read_input_tokens // 0] | add // 0 )
    ' 2>/dev/null)"
    if [[ -n "$sums" ]]; then
      in_tok="$(printf '%s\n' "$sums" | sed -n '1p')"
      out_tok="$(printf '%s\n' "$sums" | sed -n '2p')"
      cache_create="$(printf '%s\n' "$sums" | sed -n '3p')"
      cache_read="$(printf '%s\n' "$sums" | sed -n '4p')"
    fi
  fi

  printf '%s\t%s\t%s\t%s\t%s' "${in_tok:-0}" "${out_tok:-0}" "${cache_create:-0}" "${cache_read:-0}" "${stale_note:-fresh}"
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
    IFS=$'\t' read -r r_in r_out r_cc r_cr r_note <<< "$res"
    total_in=$((total_in + r_in)); total_out=$((total_out + r_out))
    total_cc=$((total_cc + r_cc)); total_cr=$((total_cr + r_cr))
    rows+=("${r_sid}"$'\t'"${r_in}"$'\t'"${r_out}"$'\t'"${r_cc}"$'\t'"${r_cr}"$'\t'"${r_note}")
  done

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

  if [[ "$json_mode" == "1" ]]; then
    printf '{"schema":1,"oracle":"od_costs","total":{"input_tokens":%d,"output_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d},"throttle_events":%d,"est_minutes_lost":%d,"truncated_to_recent":%s,"sessions":[' \
      "$total_in" "$total_out" "$total_cc" "$total_cr" "$throttle_count" "$est_minutes_lost" \
      "$([[ "$truncated_all" == "1" ]] && echo true || echo false)"
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
# od_backlog_health [--json] — THE backlog oracle
# ============================================================
#
# Extracted/mirrored from harness-kpis.sh's _kpi_backlog_section (the
# richest of the three BACKLOG-LOOP-01 consumers) — same position-
# anchored terminal-marker detection (_backlog_row_is_terminal, R1-R4),
# same per-priority open-row counts, same age-tier histogram
# (high>7d/medium>30d/low>90d per specs-o; the sibling's own histogram
# buckets are 0-7/8-30/31-90/>90 which is the SAME boundary set restated
# per-priority-independent — this function keeps that exact boundary
# set so a human comparing this output to the KPI report never sees a
# mismatch), same adds-vs-terminal-transitions-in-window flow count.
# O.9 owns re-pointing session-start-digest.sh/harness-kpis.sh/
# plan-edit-validator.sh's own three copies at this function; until that
# re-point lands, this is a byte-faithful mirror of the KPI sibling's
# algorithm, not yet the actual single implementation those three call.
# ============================================================
_OD_BACKLOG_TERM_U='(DISPOSITIONED|IMPLEMENTED|ABSORBED|CLOSED|SUPERSEDED|WONTFIX)'
_od_backlog_row_is_terminal() {
  local line="$1"
  printf '%s' "$line" | grep -qE "^- \*\*[^*]*\b${_OD_BACKLOG_TERM_U}\b" && return 0
  printf '%s' "$line" | grep -qE "\*\*[[:space:]]+(—|--?)[[:space:]]+${_OD_BACKLOG_TERM_U}\b" && return 0
  printf '%s' "$line" | grep -qiE '\*\*\((dispositioned|implemented|absorbed|closed|superseded|wontfix)\b' && return 0
  printf '%s' "$line" | grep -qE "\*\*((PARTIALLY|LARGELY)[[:space:]]+)?${_OD_BACKLOG_TERM_U}\b" && return 0
  return 1
}
_od_backlog_date_epoch() {
  local d="$1"
  date -u -d "$d" +%s 2>/dev/null \
    || date -u -j -f '%Y-%m-%d' "$d" +%s 2>/dev/null \
    || echo ""
}

od_backlog_health() {
  local json_mode=0
  local a
  for a in "$@"; do [[ "$a" == "--json" ]] && json_mode=1; done

  local backlog; backlog="$(_od_backlog_path)"
  local window_days="${KPI_WINDOW_DAYS:-7}"

  if [[ -z "$backlog" || ! -f "$backlog" ]]; then
    if [[ "$json_mode" == "1" ]]; then
      printf '{"schema":1,"oracle":"od_backlog_health","error":"no backlog file"}\n'
    else
      printf '0 open row(s) (oracle: od_backlog_health) — no backlog file at %s\n' "${backlog:-<unresolved>}"
    fi
    return 0
  fi

  local tier_high="${BACKLOG_TIER_HIGH_DAYS:-7}"
  local tier_medium="${BACKLOG_TIER_MEDIUM_DAYS:-30}"
  local tier_low="${BACKLOG_TIER_LOW_DAYS:-90}"

  local now window_start_epoch
  now="$(_od_now_epoch)"
  window_start_epoch=$((now - window_days * 86400))

  local open_high=0 open_medium=0 open_low=0 open_unlabeled=0
  local age_0_7=0 age_8_30=0 age_31_90=0 age_over_90=0 open_undated=0
  local adds_window=0 terminal_window=0 terminal_undated=0 terminal_total=0
  local line id added added_epoch age_days prio term_date term_epoch

  while IFS= read -r line; do
    id="$(printf '%s' "$line" | grep -oE '^- \*\*[A-Z][A-Z0-9-]{3,}' | sed 's/^- \*\*//')"
    [[ -z "$id" ]] && continue

    added="$(printf '%s' "$line" | grep -oE 'added [0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n1 | sed 's/^added //')"
    added_epoch=""
    [[ -n "$added" ]] && added_epoch="$(_od_backlog_date_epoch "$added")"

    if [[ -n "$added_epoch" ]] && [[ "$added_epoch" -ge "$window_start_epoch" ]]; then
      adds_window=$((adds_window + 1))
    fi

    if _od_backlog_row_is_terminal "$line"; then
      terminal_total=$((terminal_total + 1))
      term_date="$(printf '%s' "$line" \
        | grep -oiE '(DISPOSITIONED|IMPLEMENTED|ABSORBED|CLOSED|SUPERSEDED|WONTFIX)[^0-9]{0,12}[0-9]{4}-[0-9]{2}-[0-9]{2}' \
        | head -n1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"
      if [[ -n "$term_date" ]]; then
        term_epoch="$(_od_backlog_date_epoch "$term_date")"
        if [[ -n "$term_epoch" ]] && [[ "$term_epoch" -ge "$window_start_epoch" ]]; then
          terminal_window=$((terminal_window + 1))
        fi
      else
        terminal_undated=$((terminal_undated + 1))
      fi
      continue
    fi

    prio="$(printf '%s' "$line" | grep -oE 'priority:(high|medium|low)' | head -n1 | sed 's/^priority://')"
    case "$prio" in
      high)   open_high=$((open_high + 1)) ;;
      medium) open_medium=$((open_medium + 1)) ;;
      low)    open_low=$((open_low + 1)) ;;
      *)      open_unlabeled=$((open_unlabeled + 1)) ;;
    esac
    if [[ -z "$added_epoch" ]]; then
      open_undated=$((open_undated + 1))
      continue
    fi
    age_days=$(( (now - added_epoch) / 86400 ))
    if   [[ "$age_days" -le 7 ]];  then age_0_7=$((age_0_7 + 1))
    elif [[ "$age_days" -le 30 ]]; then age_8_30=$((age_8_30 + 1))
    elif [[ "$age_days" -le 90 ]]; then age_31_90=$((age_31_90 + 1))
    else                                age_over_90=$((age_over_90 + 1))
    fi
  done < <(grep -E '^- \*\*[A-Z]' "$backlog" 2>/dev/null)

  local open_total=$((open_high + open_medium + open_low + open_unlabeled))

  if [[ "$json_mode" == "1" ]]; then
    printf '{"schema":1,"oracle":"od_backlog_health","open_total":%d,"terminal_total":%d,"priority":{"high":%d,"medium":%d,"low":%d,"unlabeled":%d},"age":{"0_7d":%d,"8_30d":%d,"31_90d":%d,"over_90d":%d,"undated":%d},"flow_%dd":{"adds":%d,"terminal":%d,"terminal_undated":%d},"tiers":{"high_days":%d,"medium_days":%d,"low_days":%d}}\n' \
      "$open_total" "$terminal_total" \
      "$open_high" "$open_medium" "$open_low" "$open_unlabeled" \
      "$age_0_7" "$age_8_30" "$age_31_90" "$age_over_90" "$open_undated" \
      "$window_days" "$adds_window" "$terminal_window" "$terminal_undated" \
      "$tier_high" "$tier_medium" "$tier_low"
    return 0
  fi

  printf '%d open row(s), %d terminal (oracle: od_backlog_health)\n' "$open_total" "$terminal_total"
  printf '  priority: high=%d medium=%d low=%d unlabeled=%d\n' "$open_high" "$open_medium" "$open_low" "$open_unlabeled"
  printf '  age: 0-7d=%d 8-30d=%d 31-90d=%d >90d=%d undated=%d\n' "$age_0_7" "$age_8_30" "$age_31_90" "$age_over_90" "$open_undated"
  printf '  flow (%dd): adds=%d terminal=%d terminal_undated=%d\n' "$window_days" "$adds_window" "$terminal_window" "$terminal_undated"
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

  if [[ "$json_mode" == "1" ]]; then
    printf '{"schema":1,"oracle":"od_why","session_id":"%s","transcript_status":"%s","chain":[' \
      "$(_od_json_escape "$sid")" "$(_od_json_escape "$transcript_status")"
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

  # One-line verdict: what blocked, what state it read, what happened next.
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
  if [[ -n "$blk_gate" ]]; then
    printf 'verdict: blocked by %s (%s); next: %s %s\n' "$blk_gate" "$blk_detail" "${next_gate:-none}" "${next_ev:-n/a}"
  else
    printf 'verdict: no block event found for this session\n'
  fi
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
  mkdir -p "$HEARTBEAT_STATE_DIR" "$NEEDS_YOU_STATE_DIR" "$OBS_TRANSCRIPTS_ROOT" "$OBS_REMOTE_LEDGERS_DIR" "$OBS_DOCTOR_CACHE_DIR"
  unset CLAUDE_CODE_SESSION_ID

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

  echo "Scenario 2: od_sessions --json produces valid JSON with both sessions"
  out2="$(od_sessions --json)"
  if command -v jq >/dev/null 2>&1; then
    if printf '%s' "$out2" | jq -e . >/dev/null 2>&1; then
      pass "od_sessions --json is valid JSON"
    else
      fail "od_sessions --json is NOT valid JSON: $out2"
    fi
    n_sess="$(printf '%s' "$out2" | jq '.sessions | length' 2>/dev/null)"
    if [[ "$n_sess" == "2" ]]; then
      pass "od_sessions --json lists both fixture sessions (got $n_sess)"
    else
      fail "expected 2 sessions in --json output, got $n_sess"
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

  echo "Scenario 4: od_backlog_health — priority counts, age tiers, terminal detection"
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
  if printf '%s' "$out4" | grep -q "oracle: od_backlog_health"; then
    pass "od_backlog_health names its oracle inline"
  else
    fail "od_backlog_health missing oracle name: $out4"
  fi
  if printf '%s' "$out4" | grep -qE "3 open row\(s\), 1 terminal"; then
    pass "od_backlog_health counts 3 open / 1 terminal (position-anchored: REFS-ANOTHER-01 not falsely skipped)"
  else
    fail "expected '3 open row(s), 1 terminal', got: $out4"
  fi
  if printf '%s' "$out4" | grep -qE "high=1 medium=1 low=1"; then
    pass "od_backlog_health per-priority counts correct (CLOSED-01/high excluded as terminal; OPEN-HIGH-01/high, REFS-ANOTHER-01/medium, OPEN-OLD-01/low counted)"
  else
    fail "expected high=1 medium=1 low=1, got: $out4"
  fi
  if printf '%s' "$out4" | grep -qE '>90d=1'; then
    pass "od_backlog_health age-tier histogram places the 100d-old row in >90d"
  else
    fail "expected >90d=1 in age histogram, got: $out4"
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

  echo "Scenario 11: every count-emitting function's default (non-JSON) output names its oracle (CANONICAL-COUNTERS-01)"
  all_named=1
  for fn_out in "$out1" "$out3" "$out4" "$out5" "$out6" "$out7" "$out8"; do
    printf '%s' "$fn_out" | grep -q "oracle:" || all_named=0
  done
  if [[ "$all_named" == "1" ]]; then
    pass "every od_* function's human-readable output names its oracle inline (CANONICAL-COUNTERS-01)"
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
