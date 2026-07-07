#!/bin/bash
# ntfy-push.sh — phone-notification push for exactly three interrupt-worthy
# classes (NL Observability Program Wave O, task O.5).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# The 2026-07-04 observability design sketch names push as one of three
# surfaces (ledger, cockpit, push) and restricts it to exactly three classes
# the operator actually wants an interrupt for: a new NEEDS-YOU entry, a
# session gone stalled/throttled, and the harness doctor going RED. Every
# other event class stays cockpit/digest-only — push is a scarce, trusted
# channel, not a firehose. This script is the whole push surface: sending
# (`send`), the poll-and-decide loop that finds push-worthy state (`scan`),
# and a self-test that proves the contract (including the negative — no
# other class can reach the network) without ever making a real HTTP call.
#
# ============================================================
# CONTRACT
# ============================================================
#
#   ntfy-push.sh send --class <needs-you|stalled|doctor-red> --title <t> --body <b>
#     Sends one ntfy.sh push. Reads the topic from
#     ${NTFY_TOPIC_FILE:-$HOME/.claude/local/ntfy-topic} (first line, trimmed).
#     - Topic file absent/empty -> SILENT no-op, exit 0. This is a hard
#       contract (§O.5 spec): the operator has not provided a topic yet, and
#       the program must never block, warn, or fail because of that — it
#       just doesn't push until the topic exists. No network attempt is made.
#     - --class not one of the three allowed values -> exit 1, and — this is
#       the other hard contract, tested as a negative — NO network attempt is
#       made for an unknown class, ever, even if a topic is configured.
#     - Known class + topic present -> POSTs to https://ntfy.sh/<topic> (curl,
#       overridable via NTFY_CURL_CMD for tests — see SELF-TEST below).
#       Best-effort: a curl failure (network down, ntfy.sh unreachable) is
#       logged to stderr and does not change the caller's exit code path in a
#       way that could block anything upstream (`send` itself still exits
#       with curl's rc so callers CAN check it, but nothing in this repo
#       treats that as fatal — see needs-you.sh's guarded call).
#
#   ntfy-push.sh scan
#     Looks for push-worthy state since the last scan and sends one push per
#     newly-found item, deduped forever via
#     ${NTFY_STATE_DIR:-$HOME/.claude/state/ntfy}/sent.jsonl (one line per
#     item-id ever pushed; an item recreated with a fresh id pushes again,
#     but the same id never pushes twice). Three sources, each best-effort
#     and independently degradable:
#       1. needs-you: new OPEN entries in the needs-you ledger
#          (${NEEDS_YOU_STATE_DIR:-$HOME/.claude/state/needs-you}/ledger.json)
#          not yet in sent.jsonl -> class needs-you, item-id = the NY-... id.
#       2. stalled/throttled sessions: via `hb_classify`
#          (hooks/lib/session-heartbeat-lib.sh) over
#          ${HEARTBEAT_STATE_DIR:-$HOME/.claude/state/heartbeats}/*.json WHEN
#          THAT LIB IS PRESENT (O.2 batch-1 sibling task; this script sources
#          it optionally and degrades to "0 sessions checked" — not an error
#          — when it is not yet on disk; see the "soft dependency" note below).
#          -> class stalled, item-id = "<session_id>@<last_activity_ts>" (a
#          session that goes fresh then stale again is a NEW item-id, so it
#          re-pushes — correct: that is a second stall, not the same one).
#       3. doctor RED transition: reads
#          ${DOCTOR_CACHE_PATH:-$HOME/.claude/state/digest/doctor-cache.json}
#          ({ts,verdict_line,exit_code} — the exact schema
#          session-start-digest.sh's refresh_doctor_cache writes) and compares
#          exit_code to the LAST SEEN exit_code recorded in
#          ${NTFY_STATE_DIR:-...}/last-doctor-exit-code — pushes class
#          doctor-red only on a 0-or-absent -> nonzero TRANSITION (never on
#          every scan while it stays red — that would spam), item-id =
#          "doctor@<ts>". Updates last-doctor-exit-code every scan regardless
#          of whether a push fired.
#     Never blocks: every source is wrapped so a missing file, a missing
#     optional lib, or a malformed line is skipped, not fatal. Exit 0 always.
#
#   ntfy-push.sh --self-test
#     Sandboxed (NTFY_STATE_DIR/NTFY_TOPIC_FILE/NEEDS_YOU_STATE_DIR/
#     HEARTBEAT_STATE_DIR/DOCTOR_CACHE_PATH all pointed at a mktemp sandbox);
#     network mocked via NTFY_CURL_CMD (a shell command string invoked in
#     place of the real curl call — receives the same argv sequence a real
#     curl invocation would build, so the self-test can assert on it without
#     ever touching the network). See "SELF-TEST DESIGN" below.
#
# ============================================================
# SOFT DEPENDENCY: hooks/lib/session-heartbeat-lib.sh (O.2)
# ============================================================
#
# O.2 (session-heartbeat + hb_classify) is a batch-1 sibling task building in
# parallel in its own worktree/branch — it is not on disk yet when this task
# is built. `scan`'s stalled/throttled source sources
# hooks/lib/session-heartbeat-lib.sh IF PRESENT and calls `hb_classify` if
# the function exists; when the file is absent (or present but the function
# isn't defined — e.g. mid-integration), the stalled/throttled source is
# skipped entirely (0 sessions checked, no error, no push) and `scan`'s
# output says so explicitly. This is a real, disclosed gap — not invented
# convention-guessing about what O.2's lib will look like — the orchestrator
# re-verifies this source once O.2 merges (see report-back "orchestrator
# TODO").
#
# ============================================================
# SECURITY LINE (absolute — constitution §9 / §O.0.1-9)
# ============================================================
#
# The ntfy topic is a capability token: anyone who knows it can push to (and,
# depending on ntfy.sh server config, read from) that topic. It must NEVER
# appear in this repo, its docs, its fixtures, its tests, or any report a
# session writes — the personal mirror of this repo is PUBLIC. This script
# reads the topic ONLY from a file path (never a CLI flag, never an
# inline default, never a fixture literal), and no code path in this file or
# its self-test ever echoes, logs, or asserts on the topic's actual value —
# only on whether push WAS or WAS NOT attempted.
#
# ============================================================
# SELF-TEST DESIGN (network mock)
# ============================================================
#
# NTFY_CURL_CMD, if set, replaces the literal `curl` binary name in the send
# path: send builds its argv normally (topic URL, title/body headers/body)
# and executes "$NTFY_CURL_CMD" "${curl_args[@]}" instead of
# `curl "${curl_args[@]}"`. The self-test points NTFY_CURL_CMD at a small
# recorder script (a mktemp file) that appends its argv to a log file and
# exits 0 — so self-test assertions are "did the recorder get invoked with
# the right shape" (proves the send path fires for legit classes) and,
# separately, "did the recorder NOT get invoked" (proves the negative: no
# network attempt for an unknown class, and no network attempt when the
# topic file is absent). This is the same *_CMD override convention
# gh-account-blindness-hint.sh established for mocking an external command
# in a self-test.
#
# ============================================================

set -u

_NTFY_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

err() { echo "ntfy-push.sh: $*" >&2; }

# ----------------------------------------------------------------------
# jq is used for the needs-you ledger scan and doctor-cache parsing (both
# JSON); every other repo script touching structured JSON state (needs-you.sh,
# decision-queue.sh) treats jq as a hard dependency for the same reason —
# hand-rolled JSON parsing of a ledger is exactly the class of bug this repo
# has been bitten by before.
# ----------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not found on PATH. Install jq (https://jqlang.github.io/jq/) to use ntfy-push.sh."
  exit 1
fi

# ----------------------------------------------------------------------
# Path resolvers (env override > HARNESS_SELFTEST sandbox > real default) —
# mirrors needs-you.sh's _ny_state_dir pattern for consistency.
# ----------------------------------------------------------------------
_ntfy_topic_file() {
  if [[ -n "${NTFY_TOPIC_FILE:-}" ]]; then
    printf '%s' "$NTFY_TOPIC_FILE"
    return 0
  fi
  printf '%s/.claude/local/ntfy-topic' "${HOME:-$PWD}"
}

_ntfy_state_dir() {
  if [[ -n "${NTFY_STATE_DIR:-}" ]]; then
    printf '%s' "$NTFY_STATE_DIR"
    return 0
  fi
  printf '%s/.claude/state/ntfy' "${HOME:-$PWD}"
}

_ntfy_sent_file() { printf '%s/sent.jsonl' "$(_ntfy_state_dir)"; }
_ntfy_last_doctor_file() { printf '%s/last-doctor-exit-code' "$(_ntfy_state_dir)"; }

_needs_you_ledger_file() {
  local dir="${NEEDS_YOU_STATE_DIR:-${HOME:-$PWD}/.claude/state/needs-you}"
  printf '%s/ledger.json' "$dir"
}

_heartbeat_state_dir() {
  printf '%s' "${HEARTBEAT_STATE_DIR:-${HOME:-$PWD}/.claude/state/heartbeats}"
}

_doctor_cache_file() {
  printf '%s' "${DOCTOR_CACHE_PATH:-${HOME:-$PWD}/.claude/state/digest/doctor-cache.json}"
}

_ntfy_ensure_state() {
  local dir; dir="$(_ntfy_state_dir)"
  mkdir -p "$dir" 2>/dev/null || true
  local sent; sent="$(_ntfy_sent_file)"
  [[ -f "$sent" ]] || : > "$sent" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# _ntfy_read_topic — first non-empty line of the topic file, trimmed.
# Prints nothing (empty string) if the file is absent/empty — caller checks
# for that and no-ops. Never prints anything ELSE about the topic (no
# logging of its value anywhere in this script).
# ----------------------------------------------------------------------
_ntfy_read_topic() {
  local f; f="$(_ntfy_topic_file)"
  [[ -f "$f" ]] || return 0
  local line
  line="$(head -n1 "$f" 2>/dev/null)"
  # trim surrounding whitespace/CR
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  line="${line%$'\r'}"
  printf '%s' "$line"
}

# ----------------------------------------------------------------------
# _ntfy_already_sent <item-id> — exit 0 if item-id already in sent.jsonl.
# ----------------------------------------------------------------------
_ntfy_already_sent() {
  local id="$1"
  local sent; sent="$(_ntfy_sent_file)"
  [[ -f "$sent" ]] || return 1
  grep -qF "\"id\":\"$id\"" "$sent" 2>/dev/null
}

_ntfy_mark_sent() {
  local id="$1" class="$2"
  _ntfy_ensure_state
  local sent; sent="$(_ntfy_sent_file)"
  printf '{"id":"%s","class":"%s","ts":"%s"}\n' "$id" "$class" "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo unknown)" >> "$sent"
}

# _ntfy_topic_present — exit 0 iff a real topic is configured. `scan`'s
# sources use this to decide whether to mark an item sent: if no topic is
# configured yet, cmd_send silently no-ops (hard contract), and marking the
# item sent anyway would permanently burn it — the moment the operator
# finally supplies a topic (NEEDS-YOU ask open), every item that arrived
# before that moment would never push, because dedup would already show it
# as "sent". Gating on topic-presence keeps items pending (re-checked every
# scan) until a push can genuinely occur.
_ntfy_topic_present() {
  [[ -n "$(_ntfy_read_topic)" ]]
}

# ----------------------------------------------------------------------
# cmd_send — the ONE code path that talks (or would talk) to the network.
# ----------------------------------------------------------------------
_NTFY_ALLOWED_CLASSES="needs-you stalled doctor-red"

cmd_send() {
  local class="" title="" body=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --class) class="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      --body) body="$2"; shift 2 ;;
      *) err "send: unknown flag '$1'"; return 1 ;;
    esac
  done

  # HARD CONTRACT (negative, self-tested): an unknown --class is rejected
  # with exit 1 and — critically — this check happens BEFORE any topic read
  # or network attempt. No class outside the allow-list can ever reach curl.
  case " $_NTFY_ALLOWED_CLASSES " in
    *" $class "*) ;;
    *)
      err "send: unknown --class '$class' (must be one of: $_NTFY_ALLOWED_CLASSES) — no push attempted"
      return 1
      ;;
  esac

  [[ -n "$title" ]] || { err "send: --title is required"; return 1; }

  # HARD CONTRACT: topic absent/empty -> silent no-op, exit 0, NO network
  # attempt. The operator has not provided a topic yet (NEEDS-YOU ask open);
  # this program never blocks or warns on that — it just stays quiet.
  local topic; topic="$(_ntfy_read_topic)"
  if [[ -z "$topic" ]]; then
    return 0
  fi

  local url="https://ntfy.sh/${topic}"
  local priority="default"
  case "$class" in
    doctor-red) priority="high" ;;
    stalled) priority="high" ;;
    needs-you) priority="default" ;;
  esac

  local curl_bin="${NTFY_CURL_CMD:-curl}"
  # shellcheck disable=SC2086
  $curl_bin -s -o /dev/null -w '%{http_code}' \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -H "Tags: ${class}" \
    -d "${body}" \
    "$url" >/dev/null 2>&1
  return $?
}

# ----------------------------------------------------------------------
# scan sources
# ----------------------------------------------------------------------

# Source 1: needs-you — new OPEN ledger entries.
_scan_needs_you() {
  local f; f="$(_needs_you_ledger_file)"
  [[ -f "$f" ]] || { echo "  needs-you: 0 checked (ledger not found: $f)"; return 0; }
  local ids
  ids="$(jq -r '.items[]? | select(.state == "open") | .id' "$f" 2>/dev/null || true)"
  local n_checked=0 n_pushed=0
  local id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    n_checked=$((n_checked+1))
    if ! _ntfy_already_sent "$id" && _ntfy_topic_present; then
      local text
      text="$(jq -r --arg id "$id" '.items[] | select(.id == $id) | .text' "$f" 2>/dev/null | head -1)"
      [[ -n "$text" ]] || text="(no text)"
      cmd_send --class needs-you --title "NEEDS-YOU: new entry" --body "$text" || true
      _ntfy_mark_sent "$id" "needs-you"
      n_pushed=$((n_pushed+1))
    fi
  done <<< "$ids"
  if _ntfy_topic_present; then
    echo "  needs-you: $n_checked open entries checked, $n_pushed pushed"
  else
    echo "  needs-you: $n_checked open entries checked, 0 pushed (no topic configured yet — items stay pending)"
  fi
}

# Source 2: stalled/throttled sessions — soft dependency on O.2's
# session-heartbeat-lib.sh (hb_classify). Degrades gracefully when absent.
_scan_stalled() {
  local lib="$_NTFY_SELF_DIR/../hooks/lib/session-heartbeat-lib.sh"
  if [[ ! -f "$lib" ]]; then
    echo "  stalled: 0 checked (session-heartbeat-lib.sh not present yet — O.2 not merged; skipped, not an error)"
    return 0
  fi
  # shellcheck disable=SC1090
  source "$lib" 2>/dev/null || true
  if ! command -v hb_classify >/dev/null 2>&1; then
    echo "  stalled: 0 checked (hb_classify not defined in session-heartbeat-lib.sh — skipped, not an error)"
    return 0
  fi
  local hbdir; hbdir="$(_heartbeat_state_dir)"
  if [[ ! -d "$hbdir" ]]; then
    echo "  stalled: 0 checked (heartbeat state dir not found: $hbdir)"
    return 0
  fi
  local n_checked=0 n_pushed=0
  local f
  for f in "$hbdir"/*.json; do
    [[ -f "$f" ]] || continue
    n_checked=$((n_checked+1))
    local state; state="$(hb_classify "$f" 2>/dev/null || echo "")"
    if [[ "$state" == "stalled" || "$state" == "throttled" ]]; then
      local sid last_ts
      sid="$(jq -r '.session_id // "unknown"' "$f" 2>/dev/null)"
      last_ts="$(jq -r '.last_activity_ts // "unknown"' "$f" 2>/dev/null)"
      local item_id="${sid}@${last_ts}"
      if ! _ntfy_already_sent "$item_id" && _ntfy_topic_present; then
        cmd_send --class stalled --title "Session $state" --body "Session $sid last active $last_ts" || true
        _ntfy_mark_sent "$item_id" "stalled"
        n_pushed=$((n_pushed+1))
      fi
    fi
  done
  if _ntfy_topic_present; then
    echo "  stalled: $n_checked sessions checked, $n_pushed pushed"
  else
    echo "  stalled: $n_checked sessions checked, 0 pushed (no topic configured yet — items stay pending)"
  fi
}

# Source 3: doctor RED transition — push only on 0/absent -> nonzero.
_scan_doctor() {
  local cache; cache="$(_doctor_cache_file)"
  if [[ ! -f "$cache" ]]; then
    echo "  doctor-red: 0 checked (no doctor cache yet: $cache)"
    return 0
  fi
  local exit_code ts
  exit_code="$(jq -r '.exit_code // 0' "$cache" 2>/dev/null)"
  ts="$(jq -r '.ts // "unknown"' "$cache" 2>/dev/null)"
  [[ "$exit_code" =~ ^-?[0-9]+$ ]] || exit_code=0

  local last_file; last_file="$(_ntfy_last_doctor_file)"
  local last_code=0
  [[ -f "$last_file" ]] && last_code="$(cat "$last_file" 2>/dev/null || echo 0)"
  [[ "$last_code" =~ ^-?[0-9]+$ ]] || last_code=0

  local n_pushed=0
  if [[ "$last_code" == "0" && "$exit_code" != "0" ]]; then
    local verdict; verdict="$(jq -r '.verdict_line // "[doctor] FAILED"' "$cache" 2>/dev/null)"
    local item_id="doctor@${ts}"
    if ! _ntfy_already_sent "$item_id" && _ntfy_topic_present; then
      cmd_send --class doctor-red --title "Harness doctor RED" --body "$verdict" || true
      _ntfy_mark_sent "$item_id" "doctor-red"
      n_pushed=1
    fi
  fi
  _ntfy_ensure_state
  printf '%s' "$exit_code" > "$last_file" 2>/dev/null || true
  echo "  doctor-red: cached exit_code=$exit_code (was $last_code), $n_pushed pushed"
}

cmd_scan() {
  _ntfy_ensure_state
  echo "ntfy-push.sh scan:"
  _scan_needs_you
  _scan_stalled
  _scan_doctor
  return 0
}

# ----------------------------------------------------------------------
# --self-test
# ----------------------------------------------------------------------
cmd_selftest() {
  local sandbox; sandbox=$(mktemp -d)
  export NTFY_STATE_DIR="$sandbox/ntfy-state"
  export NTFY_TOPIC_FILE="$sandbox/ntfy-topic"
  export NEEDS_YOU_STATE_DIR="$sandbox/needs-you-state"
  export HEARTBEAT_STATE_DIR="$sandbox/heartbeats"
  export DOCTOR_CACHE_PATH="$sandbox/doctor-cache.json"
  unset HARNESS_SELFTEST 2>/dev/null || true

  local recorder="$sandbox/curl-recorder.sh"
  local recorder_log="$sandbox/curl-calls.log"
  cat > "$recorder" <<'RECEOF'
#!/bin/bash
echo "CALL: $*" >> "__LOG__"
exit 0
RECEOF
  # Substitute the real log path (avoids quoting the sandbox path into the
  # heredoc verbatim in a way that could break on spaces — this repo's path
  # historically contains a space, "Pocket Technician").
  sed -i "s#__LOG__#$recorder_log#" "$recorder" 2>/dev/null || \
    { local tmp; tmp=$(mktemp); sed "s#__LOG__#$recorder_log#" "$recorder" > "$tmp"; mv "$tmp" "$recorder"; }
  chmod +x "$recorder"
  export NTFY_CURL_CMD="$recorder"
  : > "$recorder_log"

  local pass=0 fail=0
  local -a errors=()
  ok()   { pass=$((pass+1)); echo "  PASS: $1"; }
  fail_() { fail=$((fail+1)); echo "  FAIL: $1" >&2; errors+=("$1"); }

  echo "ntfy-push.sh self-test (sandbox: $sandbox)"

  # ------------------------------------------------------------------
  # T1: topic-absent -> silent no-op, exit 0, NO network attempt. This is
  # the REAL flagless invocation shape: no topic file has been created
  # (mirrors the actual current machine state — the operator has not
  # supplied a topic yet).
  # ------------------------------------------------------------------
  : > "$recorder_log"
  local rc1
  cmd_send --class needs-you --title "test" --body "test body" >/dev/null 2>&1
  rc1=$?
  if [[ "$rc1" == "0" ]]; then ok "T1 topic-absent send exits 0"; else fail_ "T1 topic-absent send exit code was $rc1, expected 0"; fi
  if [[ ! -s "$recorder_log" ]]; then ok "T1b topic-absent: no network attempt recorded"; else fail_ "T1b topic-absent send unexpectedly invoked the network recorder: $(cat "$recorder_log")"; fi

  # ------------------------------------------------------------------
  # T2: UNKNOWN --class -> exit 1, NO network attempt (the negative
  # contract — tested BEFORE a topic exists, so this also proves the
  # class-check happens ahead of / independent of topic presence).
  # ------------------------------------------------------------------
  : > "$recorder_log"
  local rc2
  cmd_send --class bogus-class --title "test" --body "test" >/dev/null 2>&1
  rc2=$?
  if [[ "$rc2" != "0" ]]; then ok "T2 unknown --class rejected (exit $rc2)"; else fail_ "T2 unknown --class accepted (exit 0)"; fi
  if [[ ! -s "$recorder_log" ]]; then ok "T2b unknown --class: no network attempt recorded"; else fail_ "T2b unknown --class unexpectedly invoked the network recorder"; fi

  # Now provide a topic for the remaining "known class, topic present" tests.
  echo "selftest-fixture-topic-do-not-use" > "$NTFY_TOPIC_FILE"

  # ------------------------------------------------------------------
  # T3-T5: each of the three allowed classes sends (recorder invoked once
  # each), with the right Tags/Priority header shape.
  # ------------------------------------------------------------------
  : > "$recorder_log"
  cmd_send --class needs-you --title "NY test" --body "ny body" >/dev/null 2>&1
  if grep -q "Tags: needs-you" "$recorder_log" 2>/dev/null; then ok "T3 class=needs-you invokes network with Tags: needs-you"; else fail_ "T3 needs-you send did not record expected Tags header"; fi

  : > "$recorder_log"
  cmd_send --class stalled --title "Stalled test" --body "stalled body" >/dev/null 2>&1
  if grep -q "Tags: stalled" "$recorder_log" 2>/dev/null && grep -q "Priority: high" "$recorder_log" 2>/dev/null; then
    ok "T4 class=stalled invokes network with Tags: stalled, Priority: high"
  else
    fail_ "T4 stalled send did not record expected headers"
  fi

  : > "$recorder_log"
  cmd_send --class doctor-red --title "Doctor test" --body "doctor body" >/dev/null 2>&1
  if grep -q "Tags: doctor-red" "$recorder_log" 2>/dev/null && grep -q "Priority: high" "$recorder_log" 2>/dev/null; then
    ok "T5 class=doctor-red invokes network with Tags: doctor-red, Priority: high"
  else
    fail_ "T5 doctor-red send did not record expected headers"
  fi

  # ------------------------------------------------------------------
  # T6: unknown class STILL rejected even with a topic present (the
  # negative holds regardless of topic state — no class outside the
  # allow-list can ever reach push).
  # ------------------------------------------------------------------
  : > "$recorder_log"
  local rc6
  cmd_send --class totally-not-a-class --title "x" --body "y" >/dev/null 2>&1
  rc6=$?
  if [[ "$rc6" != "0" ]] && [[ ! -s "$recorder_log" ]]; then
    ok "T6 unknown class rejected with topic present too (no network attempt)"
  else
    fail_ "T6 expected non-zero exit + no network attempt with topic present (rc=$rc6, log-size=$(wc -c < "$recorder_log" 2>/dev/null))"
  fi

  # ------------------------------------------------------------------
  # T7: scan / needs-you source — a seeded open ledger entry gets pushed
  # exactly once; a second scan does not re-push (dedup via sent.jsonl).
  # ------------------------------------------------------------------
  mkdir -p "$NEEDS_YOU_STATE_DIR"
  cat > "$NEEDS_YOU_STATE_DIR/ledger.json" <<'JSONEOF'
{"schema_version":1,"items":[{"id":"NY-1111-aaaa","state":"open","section":"decision","text":"Ship the thing?"}]}
JSONEOF
  : > "$recorder_log"
  cmd_scan >/dev/null 2>&1
  local first_calls; first_calls=$(grep -c "^CALL:" "$recorder_log" 2>/dev/null); first_calls="${first_calls:-0}"
  : > "$recorder_log"
  cmd_scan >/dev/null 2>&1
  local second_calls; second_calls=$(grep -c "^CALL:" "$recorder_log" 2>/dev/null); second_calls="${second_calls:-0}"
  if [[ "$first_calls" -ge "1" ]]; then ok "T7 scan pushes a seeded new NEEDS-YOU entry (network invoked $first_calls time(s))"; else fail_ "T7 scan did not push for a seeded open NEEDS-YOU entry"; fi
  if [[ "$second_calls" == "0" ]]; then ok "T7b scan dedups — second scan of same entry does not re-push"; else fail_ "T7b scan re-pushed an already-sent item ($second_calls network call(s) on repeat scan)"; fi

  # ------------------------------------------------------------------
  # T8: scan / stalled source — session-heartbeat-lib.sh absent (real
  # current state: O.2 not merged into this worktree) -> 0 checked, no
  # error, scan still exits 0.
  # ------------------------------------------------------------------
  local scan_out8 rc8
  scan_out8=$(cmd_scan 2>&1)
  rc8=$?
  if [[ "$rc8" == "0" ]] && echo "$scan_out8" | grep -q "stalled: 0 checked"; then
    ok "T8 scan degrades gracefully when session-heartbeat-lib.sh is absent (0 checked, exit 0)"
  else
    fail_ "T8 scan did not degrade gracefully for the missing-heartbeat-lib case (rc=$rc8)"
  fi

  # ------------------------------------------------------------------
  # T9: scan / doctor source — RED transition (0 -> nonzero) pushes
  # exactly once; staying RED on a repeat scan does not re-push.
  # ------------------------------------------------------------------
  mkdir -p "$(dirname "$DOCTOR_CACHE_PATH")"
  printf '{"ts":"2026-07-06T00:00:00Z","verdict_line":"[doctor] GREEN — 7 checks passed","exit_code":0}\n' > "$DOCTOR_CACHE_PATH"
  cmd_scan >/dev/null 2>&1   # seed last-doctor-exit-code = 0
  : > "$recorder_log"
  printf '{"ts":"2026-07-06T01:00:00Z","verdict_line":"[doctor] FAILED — 2 red","exit_code":1}\n' > "$DOCTOR_CACHE_PATH"
  cmd_scan >/dev/null 2>&1
  local doctor_calls_first; doctor_calls_first=$(grep -c "Tags: doctor-red" "$recorder_log" 2>/dev/null); doctor_calls_first="${doctor_calls_first:-0}"
  if [[ "$doctor_calls_first" -ge "1" ]]; then ok "T9 scan pushes on doctor 0->nonzero RED transition"; else fail_ "T9 scan did not push on doctor RED transition"; fi
  : > "$recorder_log"
  cmd_scan >/dev/null 2>&1   # still RED, same ts -> same item-id -> should NOT re-push
  local doctor_calls_second; doctor_calls_second=$(grep -c "Tags: doctor-red" "$recorder_log" 2>/dev/null); doctor_calls_second="${doctor_calls_second:-0}"
  if [[ "$doctor_calls_second" == "0" ]]; then ok "T9b scan does not re-push while doctor stays RED (same cache ts)"; else fail_ "T9b scan re-pushed doctor-red $doctor_calls_second time(s) while staying RED"; fi

  # ------------------------------------------------------------------
  # T10: doctor RED -> GREEN -> RED again (a genuinely new cache ts) DOES
  # push again (a fresh incident, not a repeat of the same one).
  # ------------------------------------------------------------------
  printf '{"ts":"2026-07-06T02:00:00Z","verdict_line":"[doctor] GREEN — recovered","exit_code":0}\n' > "$DOCTOR_CACHE_PATH"
  cmd_scan >/dev/null 2>&1
  : > "$recorder_log"
  printf '{"ts":"2026-07-06T03:00:00Z","verdict_line":"[doctor] FAILED again — 1 red","exit_code":1}\n' > "$DOCTOR_CACHE_PATH"
  cmd_scan >/dev/null 2>&1
  local doctor_calls_third; doctor_calls_third=$(grep -c "Tags: doctor-red" "$recorder_log" 2>/dev/null); doctor_calls_third="${doctor_calls_third:-0}"
  if [[ "$doctor_calls_third" -ge "1" ]]; then ok "T10 a fresh RED incident (new transition) pushes again"; else fail_ "T10 a fresh RED transition after recovery did not push"; fi

  # ------------------------------------------------------------------
  # T11: --self-test never touched the real HOME state (sandbox leak
  # check) — mirrors needs-you.sh's T17 discipline.
  # ------------------------------------------------------------------
  local real_ntfy_state="${HOME:-}/.claude/state/ntfy"
  case "$NTFY_STATE_DIR" in
    "$real_ntfy_state"|"$real_ntfy_state"/*)
      fail_ "T11 SANDBOX LEAK: NTFY_STATE_DIR ($NTFY_STATE_DIR) resolves under the real HOME state dir"
      ;;
    *) ok "T11 sandbox NTFY_STATE_DIR isolated from real HOME state" ;;
  esac

  # ------------------------------------------------------------------
  # T12: flagless-shape scenario — invoke `scan` exactly as production
  # will (no extra CLI flags, only env-var sandboxing, per §O.0.1-4).
  # This mirrors the exact call the scan-tick-wiring fragment appends to
  # the 5-min heartbeat tick wrapper .cmd: `ntfy-push.sh scan` with no
  # arguments beyond that.
  # ------------------------------------------------------------------
  local rc12
  bash "$_NTFY_SELF_DIR/ntfy-push.sh" scan >/dev/null 2>&1
  rc12=$?
  if [[ "$rc12" == "0" ]]; then
    ok "T12 flagless real-shape invocation ('ntfy-push.sh scan', env-sandboxed only) exits 0"
  else
    fail_ "T12 flagless real-shape invocation exited $rc12, expected 0"
  fi

  # ------------------------------------------------------------------
  # T13: regression — scanning with NO topic configured must NOT burn the
  # item-ids it finds. If dedup marked an item "sent" while cmd_send was
  # actually a silent no-op (no topic), that item would never push once
  # the operator finally supplies a topic (this exact bug was caught and
  # fixed while building this task: an earlier version called
  # _ntfy_mark_sent unconditionally after cmd_send, so a topic-absent scan
  # against the real needs-you ledger permanently marked live NEEDS-YOU
  # entries as "already sent"). Fresh sandbox, topic file REMOVED (the
  # real current machine state) — a seeded open ledger entry must still be
  # reported as pending (unpushed), and MUST push once a topic is added.
  # ------------------------------------------------------------------
  rm -f "$NTFY_TOPIC_FILE"
  local sandbox13; sandbox13=$(mktemp -d)
  (
    export NTFY_STATE_DIR="$sandbox13/ntfy-state"
    export NTFY_TOPIC_FILE="$sandbox13/no-topic-here"
    export NEEDS_YOU_STATE_DIR="$sandbox13/needs-you-state"
    export NTFY_CURL_CMD="$recorder"
    mkdir -p "$NEEDS_YOU_STATE_DIR"
    cat > "$NEEDS_YOU_STATE_DIR/ledger.json" <<'JSONEOF'
{"schema_version":1,"items":[{"id":"NY-2222-bbbb","state":"open","section":"decision","text":"Topic-absent regression fixture"}]}
JSONEOF
    : > "$recorder_log"
    cmd_scan >/dev/null 2>&1
    cmd_scan >/dev/null 2>&1   # a second topic-absent scan too — still must not burn it
  )
  local calls13; calls13=$(grep -c "^CALL:" "$recorder_log" 2>/dev/null); calls13="${calls13:-0}"
  if [[ "$calls13" == "0" ]]; then
    ok "T13 topic-absent scan makes no network attempt for a pending NEEDS-YOU item"
  else
    fail_ "T13 topic-absent scan unexpectedly invoked the network ($calls13 call(s))"
  fi
  # Now add a topic and scan again in the SAME sandbox: the item must push
  # now (it was never marked sent while the topic was absent).
  (
    export NTFY_STATE_DIR="$sandbox13/ntfy-state"
    export NTFY_TOPIC_FILE="$sandbox13/no-topic-here"
    export NEEDS_YOU_STATE_DIR="$sandbox13/needs-you-state"
    export NTFY_CURL_CMD="$recorder"
    echo "fixture-topic" > "$NTFY_TOPIC_FILE"
    : > "$recorder_log"
    cmd_scan >/dev/null 2>&1
  )
  local calls13b; calls13b=$(grep -c "^CALL:" "$recorder_log" 2>/dev/null); calls13b="${calls13b:-0}"
  if [[ "$calls13b" -ge "1" ]]; then
    ok "T13b once a topic is configured, the previously-pending item pushes (not permanently burned)"
  else
    fail_ "T13b item that was pending during topic-absent scans did not push after a topic was added"
  fi
  rm -rf "$sandbox13"

  rm -rf "$sandbox"

  echo ""
  echo "RESULT: $pass passed, $fail failed"
  if [[ "$fail" -gt 0 ]]; then
    echo "Failures:"
    printf '  - %s\n' "${errors[@]}"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# main dispatch
# ----------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
  cat <<EOF
Usage: ntfy-push.sh <verb> [args]

Verbs:
  send --class <needs-you|stalled|doctor-red> --title <t> --body <b>
                          send one push. Topic absent -> silent no-op (exit
                          0, no network). Unknown --class -> exit 1, no
                          network attempt (hard contract, both directions).
  scan                    poll needs-you/heartbeats/doctor-cache for new
                          push-worthy items, dedup via sent.jsonl, exit 0
                          always.
  --self-test             run self-test suite (sandboxed; network mocked via
                          NTFY_CURL_CMD; never touches the real network or
                          real HOME state).

See adapters/claude-code/scripts/ntfy-push.sh header comment for the full
contract, the security line (the topic is a capability token — never in
this repo/docs/fixtures/chat), and the O.2 soft-dependency note.
EOF
  exit 0
fi

case "$1" in
  send) shift; cmd_send "$@" ;;
  scan) shift; cmd_scan "$@" ;;
  --self-test|--selftest|selftest|self-test) cmd_selftest ;;
  *) err "unknown verb '$1' (run without args for usage)"; exit 1 ;;
esac
