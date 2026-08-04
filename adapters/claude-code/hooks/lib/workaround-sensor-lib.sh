#!/bin/bash
# workaround-sensor-lib.sh — shared library: the operator's
# workaround-as-sensor law, mechanized.
#
# ============================================================
# WHY THIS EXISTS (Gate Philosophy Law, R3.4, harness-execution-redesign-
# 2026-08 Task 2 — deferred remainder)
# ============================================================
#
# Operator's law: "a gate generating workarounds is a defective gate."
# Every gate retrofitted under gate-contract-lib.sh names a sanctioned
# ESCAPE (the fourth structured field — see that lib's own header) for the
# rare case a block genuinely does not apply. USING that escape is itself a
# signal: a gate whose escape hatch fires often is either mis-tuned (too
# many false positives) or its enforcement is being routed around. This lib
# is the append-only sensor that makes escape-hatch USE observable without
# asking any agent to remember a separate "log the bypass" step — a caller
# that already emits the escape via gate-contract-lib.sh's gc_escape_used
# gets the ledger row for free.
#
# ============================================================
# THE CONTRACT
# ============================================================
#
#   ws_record <gate> <bypass_kind> <command_fingerprint> [detail]
#
#     gate                 - the gate name recording the bypass (free text;
#                            by convention the same string the gate uses
#                            elsewhere, e.g. "concurrent-ownership-gate").
#     bypass_kind          - the kind of escape exercised (free text, not a
#                            hard allow-list — callers introduce a new kind
#                            without a lib change; existing gates' escape
#                            kinds today: "waiver" (structured purpose-
#                            clause file), "env-override", "manual-unblock").
#     command_fingerprint  - a short, stable identifier for the bypassed
#                            operation, CALLER-SUPPLIED. This lib does NOT
#                            hash it (sha1sum/md5sum/cksum are all external
#                            binaries — a spawn on what must stay a spawn-
#                            free hot path); pass a short truncated command
#                            string, a waiver target, or any other stable
#                            label the caller already has in hand.
#     detail                - optional free-text detail. May contain
#                            quotes, backslashes, or newlines; ws_record
#                            escapes it correctly regardless.
#
#   Appends ONE line of JSON to the ledger:
#     {"ts":"2026-08-02T12:00:00Z","gate":"<gate>","session":"<sid>",
#      "bypass_kind":"<kind>","command_fingerprint":"<fp>","detail":"<d>"}
#
#   NEVER BLOCKS. Every code path returns 0 (or does not affect the
#   caller's exit path) — recording a workaround is observability, not
#   enforcement. Mirrors lib/signal-ledger.sh's own never-blocks contract
#   (a sibling, general-purpose gate-event ledger this file deliberately
#   does NOT reuse — see "why a separate ledger" below).
#
# ============================================================
# SPAWN-FREE HOT PATH (explicit build constraint, dispatch note)
# ============================================================
#
# ws_record uses ONLY bash builtins on its normal (directory-already-
# exists) path: `printf '%(...)T' -1` for the timestamp (bash's own
# strftime, no `date` fork), parameter-expansion string substitution for
# JSON escaping (no `tr`/`sed`), and `>>` redirection to append (no
# `cat`/`tee`). The escaping helper is called via command substitution
# (a bash subshell fork, not an external-process spawn) — the same
# pattern lib/signal-ledger.sh already uses; the hard constraint this file
# honors literally is "no jq/git," not "no bash forks at all." The ONE
# unavoidable external call is `mkdir -p` on the ledger's FIRST-EVER write
# in a given state directory (mkdir has no bash-builtin equivalent) — this
# only runs when the target directory does not already exist, so every
# subsequent call on an already-provisioned machine pays zero forks.
# Self-test scenario "zero-spawn-hot-path" proves this mechanically: it
# pre-creates the target directory, then breaks PATH entirely and confirms
# ws_record still succeeds and appends a correct line — no external binary
# (mkdir included) is reachable in that scenario, so success is only
# possible if the write path used nothing but bash builtins + forks.
#
# ============================================================
# WHY A SEPARATE LEDGER (not lib/signal-ledger.sh's existing "waiver" event)
# ============================================================
#
# signal-ledger.sh already carries a generic {ts,session_id,gate,event,
# detail} shape with a "waiver" event some gates already call at their own
# waiver-honored site (e.g. concurrent-ownership-gate-body.sh's
# _guard_slug). That ledger answers "did a gate-event of any registered
# class fire." This lib answers a narrower, purpose-built question the
# operator's law needs a DEDICATED, schema-stable field for:
# command_fingerprint — the specific operation a bypass targeted, so a
# future consumer can compute workaround-RATE per gate (blocks/day vs.
# escapes/day) without parsing free-text `detail` strings. Both ledgers
# may legitimately fire for the same real-world event (a gate can call
# both ledger_emit and ws_record at its waiver-honored site) — they are
# complementary observability, not competing ones.
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST) + SESSION ID
# ============================================================
#
# Same conventions as lib/signal-ledger.sh:
#   1. WORKAROUND_SENSOR_LEDGER_PATH env var, if set — explicit override
#      (used by self-tests and by any caller wanting a non-default path).
#   2. HARNESS_SELFTEST=1 and no override — sandboxed path under
#      ${TMPDIR:-/tmp}/workaround-sensor-selftest/<pid>.jsonl.
#   3. Default: $HOME/.claude/state/workaround-sensor.jsonl.
#   session — $CLAUDE_CODE_SESSION_ID env var if set, else the literal
#   string "unknown".
#
# ============================================================
# USAGE
# ============================================================
#
#   source "${BASH_SOURCE%/*}/lib/workaround-sensor-lib.sh"
#   ws_record "concurrent-ownership-gate" "waiver" "target=feat/foo-bar"
#
# Reading back: ws_tail 20   /   ws_tail 20 "$SOME_PATH"
#
# CALLER WIRING (deliberately NOT done by this task — see
# gate-contract-lib.sh's gc_escape_used and this task's build report): each
# of the five retrofitted gates' own waiver-honored call sites (e.g.
# concurrent-ownership-gate-body.sh's `_guard_slug`, which already calls a
# generic `ledger_emit ... "waiver" ...`) would need a small follow-up edit
# to ALSO call `gc_escape_used <gate> <kind> <fingerprint>` at that same
# site for "no separate discipline required" to be literally true
# end-to-end. This file + gc_escape_used are the ready-to-call mechanism;
# the five gates' body files are explicitly out of this task's scope.

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_WORKAROUND_SENSOR_LIB_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_WORKAROUND_SENSOR_LIB_SOURCED=1

# Resolved ONCE, at load time — before any caller (or this file's own
# --self-test scenarios) has a chance to `cd` elsewhere. `${BASH_SOURCE[0]}`
# is only reliably resolvable relative to the CURRENT directory at the
# moment it is read; a function that re-derives it AFTER a `cd` (even a
# subshell `cd`, since BASH_SOURCE[0] itself is a static string, not
# re-evaluated per-subshell) can silently resolve to nothing. Same fix
# harness-hygiene-scan.sh's own `_HHS_SELF_DIR` already applies.
_WS_LIB_ABS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ----------------------------------------------------------------------
# _workaround_sensor_path — resolve the ledger file path per the order
# documented above. Always prints a non-empty path; never fails.
# ----------------------------------------------------------------------
_workaround_sensor_path() {
  if [[ -n "${WORKAROUND_SENSOR_LEDGER_PATH:-}" ]]; then
    printf '%s' "$WORKAROUND_SENSOR_LEDGER_PATH"
    return 0
  fi

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/workaround-sensor-selftest/%s.jsonl' "${TMPDIR:-/tmp}" "${$}"
    return 0
  fi

  printf '%s/.claude/state/workaround-sensor.jsonl' "${HOME:-$PWD}"
  return 0
}

# ----------------------------------------------------------------------
# _workaround_sensor_json_escape <string>
#
# Escape a string for embedding inside a JSON double-quoted value, no jq
# dependency, no `tr`/`sed` spawn. Handles: backslash, double-quote,
# newline, carriage-return, tab. Printed to stdout WITHOUT the surrounding
# quotes — the caller adds those. Unlike lib/signal-ledger.sh's equivalent,
# this does NOT additionally strip other ASCII control characters via
# `tr` (that would cost a fork on every field, every call) — known,
# accepted limitation: a caller passing raw control bytes other than
# \n/\r/\t gets a technically-invalid-but-JSONL-line-preserving result.
# Real callers pass short identifiers/fingerprints/prose, never raw
# control bytes, so this has not been a problem for the sibling lib in
# practice either.
# ----------------------------------------------------------------------
_workaround_sensor_json_escape() {
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
# ws_record <gate> <bypass_kind> <command_fingerprint> [detail]
#
# Append one JSON line to the resolved ledger. NEVER fails the calling
# hook — every error path is swallowed. Returns 0 always.
# ----------------------------------------------------------------------
ws_record() {
  local gate="${1:-}"
  local bypass_kind="${2:-}"
  local fingerprint="${3:-}"
  local detail="${4:-}"

  # A record with no gate name and no bypass kind is not useful; still
  # never error — just no-op quietly (defensive; real callers always
  # supply both).
  if [[ -z "$gate" && -z "$bypass_kind" ]]; then
    return 0
  fi

  local ts
  printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null || ts="unknown"
  local sid="${CLAUDE_CODE_SESSION_ID:-unknown}"

  local gate_esc kind_esc fp_esc detail_esc sid_esc
  gate_esc="$(_workaround_sensor_json_escape "$gate")"
  kind_esc="$(_workaround_sensor_json_escape "$bypass_kind")"
  fp_esc="$(_workaround_sensor_json_escape "$fingerprint")"
  detail_esc="$(_workaround_sensor_json_escape "$detail")"
  sid_esc="$(_workaround_sensor_json_escape "$sid")"

  local line
  line="$(printf '{"ts":"%s","gate":"%s","session":"%s","bypass_kind":"%s","command_fingerprint":"%s","detail":"%s"}' \
    "$ts" "$gate_esc" "$sid_esc" "$kind_esc" "$fp_esc" "$detail_esc")"

  local path dir
  path="$(_workaround_sensor_path)"
  dir="${path%/*}"
  [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null || true
  printf '%s\n' "$line" >> "$path" 2>/dev/null || true

  return 0
}

# ----------------------------------------------------------------------
# ws_tail [<n>] [<path>]
#
# Print the last <n> (default 20) lines of the resolved ledger (or an
# explicit <path> if given). Prints nothing (not an error) if the ledger
# does not exist yet. Never fails.
# ----------------------------------------------------------------------
ws_tail() {
  local n="${1:-20}"
  local path="${2:-}"
  [[ -z "$path" ]] && path="$(_workaround_sensor_path)"
  [[ -f "$path" ]] || return 0
  tail -n "$n" "$path" 2>/dev/null || true
  return 0
}

# ============================================================
# Escape-obligation tracking (Defect 4, harness safety fix 2026-08-04 —
# amendment to the hygiene-gate incident fix)
# ============================================================
#
# WHY THIS EXISTS: the incident this ledger's own header already tells
# (four self-authored `bypass_kind=waiver-file` rows against
# harness-hygiene-scan, no operator turn, unnoticed for a day) showed
# that an append-only audit log is not a deterrent — an agent pays
# NOTHING for using an escape, so it rationally takes it. This section
# wires escapes onto the SAME accountability rail
# `lib/review-chain-lib.sh`'s `rc_open_verify_obligations` /
# `rc_wip_limit_decision` already built for merge-without-verify
# obligations (gated-pipeline-master-2026-08 Task 25 / OD-022): an open
# obligation that must be NAMED in the session's terminal DONE/CONTINUING
# marker or the Stop chain blocks (see stop-verdict-dispatcher.sh's
# `_svd_escape_naming_check`, which reuses `ws_open_escape_obligations`
# below rather than re-implementing the ledger read).
#
# HONESTY CONSTRAINT (stated here, not just in the caller): on a
# single-user machine an agent runs as the SAME principal as the
# operator, so it can forge any file the operator could write — an
# `escape-obligation-ack-*.txt` marker is exactly as self-issuable as the
# ledger row it is meant to acknowledge. This mechanism does NOT make an
# escape "impossible to self-serve" — it makes a self-served escape
# IMPOSSIBLE TO HIDE: it is visible in the SAME turn it is used (the
# calling gate prints a NOTICE at its ws_record call site), it is
# obligation-tracked (this section), and it blocks the session's own
# Stop until named, fixed, or acknowledged. That is the honest,
# achievable claim; nothing stronger is claimed anywhere in this file.
#
# OBLIGATION LIFECYCLE: a {gate, session} pair OPENS an obligation the
# moment `ws_record` writes ANY row for that pair with a non-empty
# bypass_kind. It CLOSES (per-gate) via exactly one of:
#   (a) FIXED — every file= fingerprint that gate/session recorded now
#       re-scans clean. Only mechanically verifiable for
#       gate=="harness-hygiene-scan" today (the one caller with a
#       `--check <file>` re-verification mode this lib knows how to
#       drive honestly) — see `_ws_escape_gate_fixed`. Any other gate's
#       escapes cannot be auto-verified fixed and fall through to (b).
#   (b) ACKNOWLEDGED — a durable (no TTL — an operator sign-off is a
#       record, not a rate-limited hatch) `escape-obligation-ack-*.txt`
#       marker in the SAME directory the ledger lives in, naming the gate
#       (`Acknowledged-Gate: <gate>`), the EXACT session it applies to
#       (`Acknowledged-Session: <session_id>` — required; see C5 fix note
#       on `_ws_escape_ack_exists`, an ack with no session binding used to
#       close every future session's obligation for that gate, forever),
#       plus a substantive (>=20 non-whitespace chars, not a placeholder)
#       `Acknowledged-By-Operator:` clause. Same self-issuability
#       disclosure as above.
# An obligation that is neither fixed nor acknowledged stays OPEN
# indefinitely for that session — naming it in a terminal marker
# satisfies THAT Stop's naming requirement (transparency, not closure);
# a LATER Stop in the same session re-evaluates fresh and gaps again if
# still open and still unnamed (the shared block-once-then-downgrade
# cycle in stop-verdict-dispatcher.sh is what prevents this from being an
# infinite nag, not a closure of the obligation itself).
# ============================================================

# _ws_escape_ack_exists <gate> <session_id>
# Returns 0 iff a fresh-or-not escape-obligation-ack marker in the
# ledger's own directory names BOTH this gate AND this exact session
# (`Acknowledged-Session:`, exact match) with a non-placeholder
# Acknowledged-By-Operator clause. See HONESTY CONSTRAINT above.
#
# C5 fix (harness-review 2026-08-04, unscoped-ack): before this fix, an
# ack marker named ONLY the gate — one ack file, once written (by anyone,
# for any reason), closed EVERY obligation for that gate, for EVERY
# session, FOREVER (the marker carries no expiry). A stale ack from an
# unrelated incident weeks ago would silently neutralize a brand-new,
# never-reviewed escape in today's session. The `Acknowledged-Session:`
# binding makes an ack apply to exactly the session it names — an ack
# written for session A can never close an obligation opened in session B,
# and REUSING an old ack for a new session requires a NEW marker (i.e., a
# fresh, visible, ledger-adjacent act — see the SAME honest self-
# issuability disclosure as the operator-waiver marker: this is not a
# cryptographic binding, it is a legibility/cost raise, same as every
# other "raise the cost of self-service" mechanism in this fix).
_ws_escape_ack_exists() {
  local gate="$1" session_id="$2"
  [[ -z "$gate" || -z "$session_id" ]] && return 1
  local dir; dir="$(dirname "$(_workaround_sensor_path)")"
  [[ -d "$dir" ]] || return 1
  local f line content stripped
  for f in "$dir"/escape-obligation-ack-*.txt; do
    [[ -f "$f" ]] || continue
    # `-i` + `-F` together SIGABRTs on this machine's grep (same pathology
    # already documented in scripts/nl-maintenance.sh) — use a plain ERE
    # instead, case-insensitive on the label only (the gate name / session
    # id VALUES are matched case-sensitively, same as every other
    # gate-name/session-id comparison in this harness).
    grep -qE "^[[:space:]]*[Aa]cknowledged-[Gg]ate[[:space:]]*:[[:space:]]*${gate}[[:space:]]*\$" "$f" 2>/dev/null || continue
    grep -qE "^[[:space:]]*[Aa]cknowledged-[Ss]ession[[:space:]]*:[[:space:]]*${session_id}[[:space:]]*\$" "$f" 2>/dev/null || continue
    line=$(grep -iE '^[[:space:]]*acknowledged-by-operator[[:space:]]*:' "$f" 2>/dev/null | head -1)
    [[ -z "$line" ]] && continue
    content=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[Aa]cknowledged-[Bb]y-[Oo]perator[[:space:]]*:[[:space:]]*//')
    stripped=$(printf '%s' "$content" | tr -d '[:space:]')
    [[ "${#stripped}" -ge 20 ]] && return 0
  done
  return 1
}

# _ws_escape_gate_fixed <gate> <file> [<file> ...]
# Returns 0 iff EVERY named file now re-scans clean for that gate. Only
# implemented for gate=="harness-hygiene-scan" (the one caller this lib
# knows how to honestly re-verify via its own `--check <file>` mode,
# whose output shape it can recognize) — any other gate returns 1
# (cannot verify fixed), which correctly falls through to requiring an
# ACK, never a silent auto-close for a gate this lib does not understand.
#
# C4 fix (harness-review 2026-08-04, fail-open on absence): harness-
# hygiene-scan.sh's `--check` mode SKIPS a missing file entirely from its
# scan (same as the enforce path), so `--check` on a file that no longer
# exists reports "would-pass (0 matches)" — indistinguishable, by output
# text alone, from a genuinely re-scanned-clean file. Without an explicit
# existence check, DELETING the waived file would silently CLOSE the
# obligation (the content is gone, but so is any proof it was ever fixed
# rather than just hidden). Every named file must exist on disk BEFORE
# `--check` is even invoked; a missing file makes the WHOLE call return
# "not fixed" (fails closed toward requiring an ACK), never "fixed".
_ws_escape_gate_fixed() {
  local gate="$1"; shift
  [[ "$gate" == "harness-hygiene-scan" ]] || return 1
  [[ "$#" -gt 0 ]] || return 1
  local hook="${_WS_LIB_ABS_DIR}/../harness-hygiene-scan.sh"
  [[ -f "$hook" ]] || return 1
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$repo_root" ]] || return 1
  local f out abs_f
  for f in "$@"; do
    [[ -n "$f" ]] || continue
    case "$f" in
      /*) abs_f="$f" ;;
      *) abs_f="$repo_root/$f" ;;
    esac
    [[ -f "$abs_f" ]] || return 1
    out=$(bash "$hook" --check "$f" 2>&1)
    case "$out" in
      *would-pass*) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# ws_open_escape_obligations <session_id>
# Scans the ledger for rows with session==<session_id> and a non-empty
# bypass_kind (every escape THIS session used). For each DISTINCT gate,
# the obligation is OPEN unless closed per the lifecycle above. Sets
# WS_OPEN_ESCAPE_GATES (bash array, sorted unique gate names) and
# WS_OPEN_ESCAPE_GATES_COUNT; echoes one gate per line. rc 0 always
# (read-only query — same convention as rc_open_verify_obligations).
ws_open_escape_obligations() {
  local session_id="$1"
  WS_OPEN_ESCAPE_GATES=()
  WS_OPEN_ESCAPE_GATES_COUNT=0
  [[ -z "$session_id" ]] && return 0
  local path; path="$(_workaround_sensor_path)"
  [[ -f "$path" ]] || return 0

  local lines; lines=$(cat "$path" 2>/dev/null)
  [[ -z "$lines" ]] && return 0

  local gates
  gates=$(printf '%s\n' "$lines" | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local sess kind gate
    sess=$(printf '%s' "$line" | sed -E 's/.*"session":"([^"]*)".*/\1/')
    [[ "$sess" == "$session_id" ]] || continue
    kind=$(printf '%s' "$line" | sed -E 's/.*"bypass_kind":"([^"]*)".*/\1/')
    [[ -z "$kind" ]] && continue
    gate=$(printf '%s' "$line" | sed -E 's/.*"gate":"([^"]*)".*/\1/')
    [[ -z "$gate" ]] && continue
    printf '%s\n' "$gate"
  done | LC_ALL=C sort -u)
  [[ -z "$gates" ]] && return 0

  local gate
  while IFS= read -r gate; do
    [[ -z "$gate" ]] && continue
    if _ws_escape_ack_exists "$gate" "$session_id"; then
      continue
    fi

    local files=() fp
    while IFS= read -r fp; do
      [[ -z "$fp" ]] && continue
      case "$fp" in file=*) files+=("${fp#file=}") ;; esac
    done < <(printf '%s\n' "$lines" | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local sess g cf
      sess=$(printf '%s' "$line" | sed -E 's/.*"session":"([^"]*)".*/\1/')
      [[ "$sess" == "$session_id" ]] || continue
      g=$(printf '%s' "$line" | sed -E 's/.*"gate":"([^"]*)".*/\1/')
      [[ "$g" == "$gate" ]] || continue
      cf=$(printf '%s' "$line" | sed -E 's/.*"command_fingerprint":"([^"]*)".*/\1/')
      printf '%s\n' "$cf"
    done)

    if [[ "${#files[@]}" -gt 0 ]] && _ws_escape_gate_fixed "$gate" "${files[@]}"; then
      continue
    fi

    WS_OPEN_ESCAPE_GATES+=("$gate")
    printf '%s\n' "$gate"
  done <<< "$gates"
  WS_OPEN_ESCAPE_GATES_COUNT="${#WS_OPEN_ESCAPE_GATES[@]}"
  return 0
}

# ============================================================
# --self-test
# ============================================================
#
# Only runs when this file is EXECUTED directly (not sourced). Sandboxes
# every write via HARNESS_SELFTEST=1 + an explicit
# WORKAROUND_SENSOR_LEDGER_PATH so the self-test never touches a real
# machine's ledger regardless of HOME.
#
# Invocation:
#   bash adapters/claude-code/hooks/lib/workaround-sensor-lib.sh --self-test
#
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'wsst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  LEDGER="$TMP/ledger.jsonl"
  export WORKAROUND_SENSOR_LEDGER_PATH="$LEDGER"
  unset CLAUDE_CODE_SESSION_ID

  _valid_json_line() {
    local line="$1"
    if command -v jq >/dev/null 2>&1; then
      printf '%s' "$line" | jq -e . >/dev/null 2>&1
      return $?
    fi
    [[ "$line" == \{*\} ]] || return 1
    printf '%s' "$line" | grep -q '"ts"' || return 1
    printf '%s' "$line" | grep -q '"gate"' || return 1
    printf '%s' "$line" | grep -q '"session"' || return 1
    printf '%s' "$line" | grep -q '"bypass_kind"' || return 1
    printf '%s' "$line" | grep -q '"command_fingerprint"' || return 1
    return 0
  }

  echo "Scenario 1: one record appends one valid JSON line with all five"
  echo "required fields (ts, gate, session, bypass_kind, command_fingerprint)"
  rm -f "$LEDGER"
  ws_record "test-gate" "waiver" "fp-abc123" "a detail"
  n_lines=$(wc -l < "$LEDGER" 2>/dev/null | tr -d ' ')
  if [[ "$n_lines" == "1" ]]; then
    pass "one record produced one line (got $n_lines)"
  else
    fail "expected 1 line, got $n_lines"
  fi
  LINE1="$(cat "$LEDGER")"
  if _valid_json_line "$LINE1"; then
    pass "emitted line is valid JSON carrying all five required fields"
  else
    fail "emitted line missing a required field or is not valid JSON: $LINE1"
  fi
  if printf '%s' "$LINE1" | grep -q '"gate":"test-gate"' \
     && printf '%s' "$LINE1" | grep -q '"bypass_kind":"waiver"' \
     && printf '%s' "$LINE1" | grep -q '"command_fingerprint":"fp-abc123"'; then
    pass "field values round-trip verbatim (gate/bypass_kind/command_fingerprint)"
  else
    fail "field values did not round-trip: $LINE1"
  fi

  echo "Scenario 2: multiple records APPEND (not overwrite)"
  rm -f "$LEDGER"
  ws_record "gate-a" "waiver" "fp-1"
  ws_record "gate-b" "env-override" "fp-2"
  ws_record "gate-c" "manual-unblock" "fp-3"
  n_lines2=$(wc -l < "$LEDGER" 2>/dev/null | tr -d ' ')
  if [[ "$n_lines2" == "3" ]]; then
    pass "three ws_record calls produced three lines (got $n_lines2)"
  else
    fail "expected 3 lines, got $n_lines2"
  fi
  if grep -q '"gate":"gate-a"' "$LEDGER" && grep -q '"gate":"gate-b"' "$LEDGER" \
     && grep -q '"gate":"gate-c"' "$LEDGER"; then
    pass "all three gate names present verbatim"
  else
    fail "one or more gate names missing from the ledger"
  fi

  echo "Scenario 3: quotes/backslashes/newlines in detail escape correctly"
  rm -f "$LEDGER"
  ws_record "quote-gate" "waiver" "fp-x" 'she said "hi" and used a \backslash\ then
a second line'
  LINE3="$(cat "$LEDGER")"
  if _valid_json_line "$LINE3"; then
    pass "line with quotes/backslash/newline in detail is still valid JSON"
  else
    fail "line with quotes/backslash/newline is NOT valid JSON: $LINE3"
  fi
  if command -v jq >/dev/null 2>&1; then
    roundtrip="$(printf '%s' "$LINE3" | jq -r '.detail' 2>/dev/null | tr -d '\r')"
    expected='she said "hi" and used a \backslash\ then
a second line'
    if [[ "$roundtrip" == "$expected" ]]; then
      pass "detail round-trips through jq to the original string"
    else
      fail "round-trip mismatch: got [$roundtrip]"
    fi
  else
    echo "  (jq unavailable — skipping strict round-trip assertion)"
  fi

  echo "Scenario 4: HARNESS_SELFTEST sandbox honored when the explicit"
  echo "override is unset"
  (
    unset WORKAROUND_SENSOR_LEDGER_PATH
    export HARNESS_SELFTEST=1
    export TMPDIR="$TMP/sandboxed-tmp"
    mkdir -p "$TMPDIR"
    resolved="$(_workaround_sensor_path)"
    case "$resolved" in
      "$TMPDIR"/workaround-sensor-selftest/*) exit 0 ;;
      *) exit 1 ;;
    esac
  )
  if [[ $? -eq 0 ]]; then
    pass "HARNESS_SELFTEST=1 with no override resolves under the TMPDIR sandbox"
  else
    fail "HARNESS_SELFTEST sandbox path resolution did not match expected shape"
  fi
  (
    unset WORKAROUND_SENSOR_LEDGER_PATH
    export HARNESS_SELFTEST=1
    resolved="$(_workaround_sensor_path)"
    [[ "$resolved" != "$HOME/.claude/state/workaround-sensor.jsonl" ]]
  )
  if [[ $? -eq 0 ]]; then
    pass "sandbox path never equals the production ledger path"
  else
    fail "sandbox path incorrectly resolved to the production ledger path"
  fi

  echo "Scenario 5: ws_record never fails the caller even when the target"
  echo "path is unwritable"
  BLOCKER="$TMP/blocker-file"
  : > "$BLOCKER"
  (
    export WORKAROUND_SENSOR_LEDGER_PATH="$BLOCKER/subdir/ledger.jsonl"
    set +e
    ws_record "unwritable-gate" "waiver" "fp-x" "should not crash"
    rc=$?
    set -e
    exit $rc
  )
  if [[ $? -eq 0 ]]; then
    pass "ws_record returns 0 even when the target path is unwritable"
  else
    fail "ws_record propagated a non-zero exit on an unwritable path"
  fi

  echo "Scenario 6: both gate and bypass_kind empty is a quiet no-op"
  rm -f "$LEDGER"
  ws_record "" "" "fp-orphan"
  if [[ ! -s "$LEDGER" ]]; then
    pass "empty gate + empty bypass_kind wrote nothing"
  else
    fail "expected no write, got: $(cat "$LEDGER" 2>/dev/null)"
  fi

  echo "Scenario 7 (build constraint): zero-spawn hot path — pre-create the"
  echo "target directory, break PATH entirely, confirm ws_record still"
  echo "succeeds (proves no external binary, mkdir included, is reachable"
  echo "or needed on the append-to-existing-dir path)"
  NOSPAWN_DIR="$TMP/nospawn"
  mkdir -p "$NOSPAWN_DIR"
  NOSPAWN_LEDGER="$NOSPAWN_DIR/ledger.jsonl"
  (
    export WORKAROUND_SENSOR_LEDGER_PATH="$NOSPAWN_LEDGER"
    export PATH="$TMP/definitely-not-a-real-path-$$"
    set +e
    ws_record "nospawn-gate" "waiver" "fp-nospawn" "no external binary reachable"
    rc=$?
    set -e
    exit $rc
  )
  RC7=$?
  if [[ "$RC7" -eq 0 ]] && [[ -f "$NOSPAWN_LEDGER" ]] \
     && grep -q '"gate":"nospawn-gate"' "$NOSPAWN_LEDGER" 2>/dev/null; then
    pass "ws_record succeeded with PATH broken and the dir pre-existing (zero-spawn hot path confirmed)"
  else
    fail "ws_record failed or produced no line with PATH broken (rc=$RC7)"
  fi

  echo "Scenario 8: ws_tail returns the last n lines, most recent last-N"
  rm -f "$LEDGER"
  for i in 1 2 3 4 5; do
    ws_record "tail-gate" "waiver" "fp-$i" "entry-$i"
  done
  tail2="$(ws_tail 2 "$LEDGER")"
  n_tail_lines=$(printf '%s\n' "$tail2" | grep -c .)
  if [[ "$n_tail_lines" == "2" ]] \
     && printf '%s' "$tail2" | grep -q 'entry-5' \
     && printf '%s' "$tail2" | grep -q 'entry-4'; then
    pass "ws_tail 2 returns exactly the 2 most-recent entries (4 and 5)"
  else
    fail "ws_tail did not return the expected most-recent entries (got: $tail2)"
  fi

  echo "Scenario 9: session field resolves from CLAUDE_CODE_SESSION_ID"
  rm -f "$LEDGER"
  (
    export CLAUDE_CODE_SESSION_ID="sess-xyz"
    ws_record "session-gate" "waiver" "fp-s"
  )
  if grep -q '"session":"sess-xyz"' "$LEDGER" 2>/dev/null; then
    pass "session field carries CLAUDE_CODE_SESSION_ID when set"
  else
    fail "session field did not pick up CLAUDE_CODE_SESSION_ID"
  fi
  rm -f "$LEDGER"
  ws_record "session-gate2" "waiver" "fp-s2"
  if grep -q '"session":"unknown"' "$LEDGER" 2>/dev/null; then
    pass "session field defaults to 'unknown' when CLAUDE_CODE_SESSION_ID is unset"
  else
    fail "session field did not default to 'unknown'"
  fi

  # ============================================================
  # Scenarios 10-16: escape-obligation tracking (Defect 4)
  # ============================================================

  echo "Scenario 10: ws_open_escape_obligations — no ledger rows for the"
  echo "given session -> zero open obligations"
  rm -f "$LEDGER"
  ws_record "gate-x" "waiver" "fp-other" ""
  ws_open_escape_obligations "sess-nomatch" > "$TMP/open10.txt"; OPEN10="$(cat "$TMP/open10.txt")"
  if [[ "$WS_OPEN_ESCAPE_GATES_COUNT" == "0" ]]; then
    pass "no rows for this session -> 0 open obligations"
  else
    fail "expected 0 open obligations, got $WS_OPEN_ESCAPE_GATES_COUNT (out=[$OPEN10])"
  fi

  echo "Scenario 11: a fresh escape row for a session -> that gate is OPEN"
  rm -f "$LEDGER"
  CLAUDE_CODE_SESSION_ID="sess-11" ws_record "concurrent-ownership-gate" "waiver" "target=feat/foo"
  ws_open_escape_obligations "sess-11" > "$TMP/open11.txt"; OPEN11="$(cat "$TMP/open11.txt")"
  if [[ "$WS_OPEN_ESCAPE_GATES_COUNT" == "1" ]] && [[ "$OPEN11" == "concurrent-ownership-gate" ]]; then
    pass "one escape row -> one open obligation naming the right gate"
  else
    fail "expected 1 open obligation 'concurrent-ownership-gate', got count=$WS_OPEN_ESCAPE_GATES_COUNT out=[$OPEN11]"
  fi

  echo "Scenario 12: escape-obligation-ack-*.txt naming the gate + THIS"
  echo "session + a substantive Acknowledged-By-Operator clause -> CLOSES"
  echo "the obligation"
  rm -f "$LEDGER"
  CLAUDE_CODE_SESSION_ID="sess-12" ws_record "concurrent-ownership-gate" "waiver" "target=feat/bar"
  LEDGER_DIR="$(dirname "$LEDGER")"
  {
    echo "Acknowledged-Gate: concurrent-ownership-gate"
    echo "Acknowledged-Session: sess-12"
    echo "Acknowledged-By-Operator: yes I reviewed this in chat and it is fine to proceed"
  } > "$LEDGER_DIR/escape-obligation-ack-s12.txt"
  ws_open_escape_obligations "sess-12" > "$TMP/open12.txt"; OPEN12="$(cat "$TMP/open12.txt")"
  rm -f "$LEDGER_DIR/escape-obligation-ack-s12.txt"
  if [[ "$WS_OPEN_ESCAPE_GATES_COUNT" == "0" ]]; then
    pass "acknowledged gate (correct session) -> 0 open obligations"
  else
    fail "expected acknowledgment to close the obligation, got count=$WS_OPEN_ESCAPE_GATES_COUNT out=[$OPEN12]"
  fi

  echo "Scenario 12b (C5 fix, harness-review 2026-08-04): the SAME"
  echo "well-formed ack (gate + substantive clause) but bound to a"
  echo "DIFFERENT session -> does NOT close THIS session's obligation."
  echo "Before the fix, an ack naming only the gate closed every future"
  echo "session's obligation for that gate, forever."
  rm -f "$LEDGER"
  CLAUDE_CODE_SESSION_ID="sess-12c" ws_record "concurrent-ownership-gate" "waiver" "target=feat/bar2"
  LEDGER_DIR="$(dirname "$LEDGER")"
  {
    echo "Acknowledged-Gate: concurrent-ownership-gate"
    echo "Acknowledged-Session: sess-SOME-OTHER-SESSION"
    echo "Acknowledged-By-Operator: yes I reviewed this in chat and it is fine to proceed"
  } > "$LEDGER_DIR/escape-obligation-ack-s12c.txt"
  ws_open_escape_obligations "sess-12c" > "$TMP/open12c.txt"; OPEN12C="$(cat "$TMP/open12c.txt")"
  rm -f "$LEDGER_DIR/escape-obligation-ack-s12c.txt"
  if [[ "$WS_OPEN_ESCAPE_GATES_COUNT" == "1" ]]; then
    pass "a foreign-session ack does NOT close this session's obligation (C5 fix)"
  else
    fail "expected a foreign-session ack to leave the obligation OPEN, got count=$WS_OPEN_ESCAPE_GATES_COUNT out=[$OPEN12C]"
  fi

  echo "Scenario 13: a placeholder Acknowledged-By-Operator clause"
  echo "(<20 chars), correct gate + correct session, does NOT close the"
  echo "obligation"
  rm -f "$LEDGER"
  CLAUDE_CODE_SESSION_ID="sess-13" ws_record "concurrent-ownership-gate" "waiver" "target=feat/baz"
  LEDGER_DIR="$(dirname "$LEDGER")"
  {
    echo "Acknowledged-Gate: concurrent-ownership-gate"
    echo "Acknowledged-Session: sess-13"
    echo "Acknowledged-By-Operator: yes"
  } > "$LEDGER_DIR/escape-obligation-ack-s13.txt"
  ws_open_escape_obligations "sess-13" > "$TMP/open13.txt"; OPEN13="$(cat "$TMP/open13.txt")"
  rm -f "$LEDGER_DIR/escape-obligation-ack-s13.txt"
  if [[ "$WS_OPEN_ESCAPE_GATES_COUNT" == "1" ]]; then
    pass "placeholder acknowledgment does not close the obligation"
  else
    fail "expected the obligation to stay open with a placeholder ack, got count=$WS_OPEN_ESCAPE_GATES_COUNT"
  fi

  echo "Scenario 14: FIXED auto-close for gate==harness-hygiene-scan — a"
  echo "file that now scans clean via --check closes without needing an ack;"
  echo "a file that still matches does NOT auto-close"
  F14_REPO="$TMP/fixed-repo"
  mkdir -p "$F14_REPO/adapters/claude-code/patterns"
  printf '%s\n' '# test denylist' 'SOME_SECRET_TOKEN' > "$F14_REPO/adapters/claude-code/patterns/harness-denylist.txt"
  ( cd "$F14_REPO" && git init -q . >/dev/null 2>&1 && git config user.email t@example.com && git config user.name T )
  printf 'nothing bad here\n' > "$F14_REPO/clean14.txt"
  FIXED14_OK=1
  ( cd "$F14_REPO" && _ws_escape_gate_fixed "harness-hygiene-scan" "clean14.txt" ) || FIXED14_OK=0
  if [[ "$FIXED14_OK" == "1" ]]; then
    pass "_ws_escape_gate_fixed recognizes a clean file as fixed for harness-hygiene-scan"
  else
    fail "_ws_escape_gate_fixed did not recognize a clean file as fixed"
  fi
  printf 'this still has SOME_SECRET_TOKEN in it\n' > "$F14_REPO/dirty14.txt"
  FIXED14_NEG_OK=1
  ( cd "$F14_REPO" && _ws_escape_gate_fixed "harness-hygiene-scan" "dirty14.txt" ) && FIXED14_NEG_OK=0
  if [[ "$FIXED14_NEG_OK" == "1" ]]; then
    pass "_ws_escape_gate_fixed correctly reports NOT fixed for a file that still matches"
  else
    fail "_ws_escape_gate_fixed wrongly reported a still-matching file as fixed"
  fi

  echo "Scenario 14b (C4 fix, harness-review 2026-08-04): a file that no"
  echo "longer EXISTS must NOT be treated as fixed. --check silently skips"
  echo "a missing path and reports would-pass (0 matches) — indistinguishable"
  echo "from genuinely clean, so deleting the waived file used to silently"
  echo "close the obligation."
  rm -f "$F14_REPO/gone14.txt"
  FIXED14B_NEG_OK=1
  ( cd "$F14_REPO" && _ws_escape_gate_fixed "harness-hygiene-scan" "gone14.txt" ) && FIXED14B_NEG_OK=0
  if [[ "$FIXED14B_NEG_OK" == "1" ]]; then
    pass "_ws_escape_gate_fixed correctly reports NOT fixed for a missing file (fail-closed on absence)"
  else
    fail "_ws_escape_gate_fixed wrongly treated a MISSING file as fixed (C4 regression)"
  fi

  echo "Scenario 15: a gate OTHER than harness-hygiene-scan can never be"
  echo "auto-verified fixed (fails closed toward requiring an ack)"
  if _ws_escape_gate_fixed "concurrent-ownership-gate" "some/file.txt"; then
    fail "_ws_escape_gate_fixed must return 1 (not fixed) for a gate it cannot re-verify"
  else
    pass "unrecognized gate correctly falls through to 'cannot verify fixed'"
  fi

  echo "Scenario 16: distinct sessions do not leak obligations into each other"
  rm -f "$LEDGER"
  CLAUDE_CODE_SESSION_ID="sess-16a" ws_record "concurrent-ownership-gate" "waiver" "target=a"
  ws_open_escape_obligations "sess-16b" > "$TMP/open16.txt"; OPEN16="$(cat "$TMP/open16.txt")"
  if [[ "$WS_OPEN_ESCAPE_GATES_COUNT" == "0" ]]; then
    pass "a different session's escape rows do not open an obligation for THIS session"
  else
    fail "expected 0 open obligations for an unrelated session, got $WS_OPEN_ESCAPE_GATES_COUNT"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
