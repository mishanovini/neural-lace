#!/bin/bash
# session-honesty-gate.sh — Stop hook (NL Overhaul Wave D, task D.3)
#
# Narrow, mechanical honesty check on the session's terminal marker. This
# gate ABSORBS continuation-enforcer.sh's marker-contract semantics (that
# hook retires to attic/ at D.5) and DEMOTES five other Stop-hook heuristics
# — narrate-and-wait-gate, deferral-counter, transcript-lie-detector,
# goal-coverage-on-stop, and (implicitly) any other final-message-content
# scan — to non-blocking signal-ledger warns emitted from inside this gate.
#
# Per docs/plans/nl-overhaul-program-2026-07-specs-d.md §D.3 + §D.0.9:
#
# BLOCKS ONLY on:
#   (a) the final assistant message's last non-empty line does not carry
#       EXACTLY ONE marker of DONE: / PAUSING: / BLOCKED: / CONTINUING:
#   (b) the marker is DONE while work-integrity-gate (or its pre-D.5 shim
#       names pre-stop-verifier / product-acceptance-gate) recorded a BLOCK
#       for this session strictly AFTER the last DONE-marked assistant
#       message in the transcript — flagrant self-contradiction: claiming
#       "done" after being told the work is incomplete, without changing
#       the marker.
#
# Everything else is a NON-BLOCKING signal-ledger warn:
#   - CONTINUING without a wake-mechanism token (scheduled|watchdog|cron|
#     wakeup|monitor|background task id)
#   - PAUSING without an exact-ask shape (heuristic; doctrine, not
#     mechanically decidable — constitution §8)
#   - narrate-and-wait phrasing in the tail of the final message
#   - deferral phrases (deferred, TBD, follow-up, etc.)
#   - sub-flagrant self-contradiction candidates (completion + deferral
#     language coexisting, but not a DONE-after-block flagrant case)
#   - goal-coverage misses (best-effort keyword scan; no goal-file
#     dependency — that mechanism is goal-extraction-on-prompt's remit)
#
# DESIGN PIN (operator directive, 2026-07-02 — non-negotiable, §D.0.9):
# this gate is ALWAYS satisfiable by a minimal-delta closing message of the
# shape `<MARKER>: <one line>` (+ optionally "report above stands"). It
# NEVER demands report content be re-stated, never scans for a required
# heading + bullets (unlike deferral-counter / transcript-lie-detector /
# goal-coverage-on-stop, whose heading-re-statement demand is exactly the
# anti-pattern this gate's warns must NOT reproduce). A prior block plus a
# 2-line retry that fixes the actual defect (adds/repairs the marker, or
# changes DONE to PAUSING/BLOCKED) always passes on the next attempt.
#
# Exit codes:
#   0 — session may terminate
#   2 — blocked; stderr explains, JSON {"decision":"block"} on stdout
#
# Loop safety: sources lib/stop-hook-retry-guard.sh, same as every other
# Stop hook in this chain. session-honesty-gate registers itself as a
# VERIFICATION-class hook is NOT appropriate here (it does not measure
# work-state completeness — work-integrity-gate does that); this gate's
# own retries downgrade on the normal (non-verification) path.
#
# Ledger: every block and every demoted-warn calls ledger_emit via
# lib/signal-ledger.sh (best-effort; never blocks on ledger-write failure).
#
# Sandboxing: HARNESS_SELFTEST=1 routes signal-ledger writes to a sandboxed
# path automatically (signal-ledger.sh's own contract) and this file's
# --self-test additionally overrides RETRY_GUARD_STATE_DIR + the
# unresolved-stop-hooks.log / signal-ledger read paths per-scenario so no
# self-test run ever touches real session state.
#
# Escape hatch: SESSION_HONESTY_GATE_DISABLE=1 for harness-development
# sessions that edit the marker vocabulary or this gate itself.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/stop-hook-retry-guard.sh"

# ----------------------------------------------------------------------
# marker_scan_eval <transcript-path>
#
# Core marker-contract check (absorbed from continuation-enforcer.sh).
# Sets MARKER_VERDICT (allow|block), MARKER_SIG, MARKER_MSG, MARKER_KEYWORD
# (DONE|PAUSING|BLOCKED|CONTINUING, when a single valid marker was found),
# MARKER_SUMMARY (the text after "KEYWORD: "), and MARKER_EVENT_LINE (the
# JSONL physical line number of the final assistant message, best-effort,
# used by the contradiction check below). Returns 0 for allow, 1 for block.
#
# Narrower than continuation-enforcer's floors by design (§D.3 does not
# list a substance-floor or TodoWrite check among its blocking conditions
# — those remain work-integrity-gate's / the retired hook's concern, and
# reproducing them here would violate the minimal-delta design pin).
# ----------------------------------------------------------------------
MARKER_VERDICT=""
MARKER_SIG=""
MARKER_MSG=""
MARKER_KEYWORD=""
MARKER_SUMMARY=""
MARKER_EVENT_LINE=""

marker_scan_eval() {
  local transcript="$1"
  MARKER_VERDICT="allow"
  MARKER_SIG=""
  MARKER_MSG=""
  MARKER_KEYWORD=""
  MARKER_SUMMARY=""
  MARKER_EVENT_LINE=""

  if [[ -z "$transcript" ]] || [[ ! -f "$transcript" ]]; then
    MARKER_VERDICT="allow"; return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    MARKER_VERDICT="allow"; return 0
  fi

  local final_text
  final_text=$(jq -rs '
    [ .[]
      | select((.type? == "assistant")
               or (.message?.role? == "assistant")
               or (.role? == "assistant")) ] as $a
    | if ($a | length) == 0 then ""
      else
        ($a[-1] | (.message?.content // .content // .text // "")) as $c
        | if ($c | type) == "array" then
            ([ $c[] | if type == "object" then (.text // "")
                      elif type == "string" then .
                      else "" end ] | join("\n"))
          elif ($c | type) == "string" then $c
          else ($c | tostring) end
      end
  ' "$transcript" 2>/dev/null)

  if [[ -z "$final_text" ]]; then
    MARKER_VERDICT="allow"; return 0
  fi

  local marker_re='^[[:space:]>*_`#-]*(DONE|PAUSING|BLOCKED|CONTINUING):[[:space:]]'
  local n_markers
  n_markers=$(printf '%s\n' "$final_text" | grep -cE "$marker_re" 2>/dev/null || true)
  n_markers=${n_markers//[!0-9]/}
  [[ -z "$n_markers" ]] && n_markers=0

  if [[ "$n_markers" -eq 0 ]]; then
    MARKER_VERDICT="block"
    MARKER_SIG="no-marker"
    MARKER_MSG="No DONE: / PAUSING: / BLOCKED: / CONTINUING: marker on the last line of your final message. End every turn with exactly one."
    return 1
  fi
  if [[ "$n_markers" -ge 2 ]]; then
    MARKER_VERDICT="block"
    MARKER_SIG="multi-marker"
    MARKER_MSG="Found ${n_markers} marker lines. The final response must carry EXACTLY ONE terminal-state marker — pick the one true state."
    return 1
  fi

  local last_line
  last_line=$(printf '%s\n' "$final_text" | awk 'NF{l=$0} END{print l}')
  local stripped
  stripped=$(printf '%s' "$last_line" \
    | sed -E 's/^[[:space:]>*_`#-]+//' \
    | sed -E 's/[[:space:]*_`]+$//')

  if ! printf '%s' "$stripped" | grep -qE '^(DONE|PAUSING|BLOCKED|CONTINUING):[[:space:]]'; then
    MARKER_VERDICT="block"
    MARKER_SIG="marker-not-terminal"
    MARKER_MSG="A marker exists but is not on the last non-empty line. The marker must be the terminal line."
    return 1
  fi

  MARKER_KEYWORD=$(printf '%s' "$stripped" | sed -E 's/^(DONE|PAUSING|BLOCKED|CONTINUING):.*$/\1/')
  MARKER_SUMMARY=$(printf '%s' "$stripped" | sed -E 's/^(DONE|PAUSING|BLOCKED|CONTINUING):[[:space:]]*//')

  # Best-effort: the JSONL physical line number of the final assistant
  # message, used only to order the DONE claim against block records that
  # carry a timestamp. Not load-bearing for the marker check itself.
  MARKER_EVENT_LINE=$(jq -r '
    if (.role? == "assistant" or .message?.role? == "assistant") then input_line_number else empty end
  ' "$transcript" 2>/dev/null | tail -n 1)

  MARKER_VERDICT="allow"
  return 0
}

# ----------------------------------------------------------------------
# done_contradicted_by_block <transcript-path>
#
# Flagrant self-contradiction check (§D.3 condition b): the marker is
# DONE while work-integrity-gate (or its pre-D.5 shim names) recorded a
# BLOCK for THIS session strictly after the moment of the DONE claim.
#
# Reads two independent state sources (either is sufficient to detect a
# contradiction; both are best-effort / fail-open on any parse error):
#
#   1. RETRY_GUARD_STATE_DIR/unresolved-stop-hooks.log — retry-guard's
#      downgrade audit trail. A downgrade entry means the gate blocked at
#      least RETRY_GUARD_THRESHOLD times before downgrading; that is
#      itself evidence of an in-session block. Session-scoped by the
#      short session token embedded in the log line.
#   2. The signal ledger (lib/signal-ledger.sh) — every work-integrity-gate
#      block/warn emits a ledger line with a timestamp. A "block" event
#      for work-integrity-gate / pre-stop-verifier / product-acceptance-gate
#      in this session's ledger segment is direct evidence.
#
# Because retry-guard's log and the ledger both carry wall-clock
# timestamps but the transcript marker only carries a JSONL line number,
# "after the last DONE claim" is approximated as: the block record exists
# AND the transcript's final message (the one being evaluated right now)
# is the DONE claim under test — i.e. any recorded block for this session
# from the work-integrity family is treated as "after" whenever the
# CURRENT terminal message is the DONE claim being evaluated at Stop time.
# This is deliberately conservative in the blocking direction only when
# unambiguous: a session with zero recorded blocks never contradicts.
#
# Echoes a one-line evidence string on stdout when contradicted (for the
# block message); returns 0 (contradicted) or 1 (clean / no evidence).
# ----------------------------------------------------------------------
done_contradicted_by_block() {
  local sid="$1"
  local evidence="" block_ts=""

  # Source 1: retry-guard's unresolved-stop-hooks.log (session-scoped by
  # the short token stop-hook-retry-guard.sh derives from the session id).
  local state_dir="${RETRY_GUARD_STATE_DIR:-.claude/state}"
  local log_file="${state_dir}/unresolved-stop-hooks.log"
  if [[ -f "$log_file" ]]; then
    local short
    short=$(printf '%s' "$sid" | tr -c 'a-zA-Z0-9' '_' | cut -c1-24)
    local hit
    hit=$(grep -E "hook=(work-integrity-gate|pre-stop-verifier|product-acceptance-gate)[[:space:]].*session=${short}\b" "$log_file" 2>/dev/null | tail -n 1)
    if [[ -n "$hit" ]]; then
      evidence="unresolved-stop-hooks.log: ${hit}"
      block_ts=$(printf '%s' "$hit" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' | head -1)
    fi
  fi

  # Source 2: the signal ledger — a "block" event from the work-integrity
  # family for this session.
  if [[ -z "$evidence" ]]; then
    local ledger_path=""
    if command -v _signal_ledger_path >/dev/null 2>&1; then
      ledger_path=$(_signal_ledger_path)
    fi
    if [[ -n "$ledger_path" ]] && [[ -f "$ledger_path" ]] && command -v jq >/dev/null 2>&1; then
      local hit
      hit=$(jq -c --arg sid "$sid" '
        select(.session_id == $sid)
        | select(.event == "block")
        | select(.gate == "work-integrity-gate" or .gate == "pre-stop-verifier" or .gate == "product-acceptance-gate")
      ' "$ledger_path" 2>/dev/null | tail -n 1)
      if [[ -n "$hit" ]]; then
        evidence="signal-ledger: ${hit}"
        block_ts=$(printf '%s' "$hit" | jq -r '.ts // empty' 2>/dev/null || echo "")
      fi
    fi
  fi

  if [[ -z "$evidence" ]]; then
    return 1
  fi

  # NL-FINDING-027 fix (specs-e §E.10 item 10a): a block RESOLVED via EITHER
  # of two sanctioned paths must not poison a later honest DONE:
  #
  #   (1) a currently-valid (<1h, non-empty) work-integrity waiver on disk —
  #       proof the block was resolved via the waiver valve.
  #   (2) a LATER work-integrity "pass" ledger event for this session, with
  #       a timestamp AFTER the recorded block — proof work-integrity itself
  #       re-ran clean (the actual work got done / the waiver above wasn't
  #       even needed) since the block fired. This is the interim's missing
  #       half: previously only a waiver cleared the false input; a session
  #       that just finished the work and re-ran clean had no valve at all.
  #
  # Both clear a FALSE INPUT to the honesty check; neither waives the
  # honesty assertion itself (ADR 059 D4 scoping preserved) — a session
  # whose LATEST work-integrity signal is still a block (no later pass, no
  # fresh waiver) remains genuinely contradicted.
  #
  # pin-f-doctor-exempt: this file reads work-integrity-waiver-*.txt as
  # EVIDENCE that a DIFFERENT gate's (work-integrity-gate.sh) block was
  # legitimately resolved — it is NOT this gate's own waiver escape hatch
  # (session-honesty-gate's own contract stays marker-only per §D.3's
  # design pin; a waiver never bypasses the marker requirement itself).
  # work-integrity-gate.sh already validates this waiver family's purpose
  # clauses (ADR 058 D5 pin f) at the point it is WRITTEN/HONORED; this
  # file only reads its freshness as a downstream signal.
  local _shg_wbase _shg_wdir _shg_dirs
  # Sandbox discipline (NL-FINDING-028 class): under HARNESS_SELFTEST only
  # the scenario-provided state_dir is searched — the common-dir escape
  # would leak REAL waivers into synthetic scenarios.
  _shg_dirs=("$state_dir")
  if [[ -z "${HARNESS_SELFTEST:-}" ]]; then
    _shg_wbase=$(dirname "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)")
    _shg_dirs+=("${_shg_wbase}/.claude/state")
  fi
  for _shg_wdir in "${_shg_dirs[@]}"; do
    if find "$_shg_wdir" -maxdepth 1 -type f -name 'work-integrity-waiver-*.txt' \
         -newermt '1 hour ago' -size +0c 2>/dev/null | head -1 | grep -q . ; then
      return 1
    fi
  done

  # (2) LATER work-integrity PASS check.
  if [[ -n "$block_ts" ]]; then
    local ledger_path=""
    if command -v _signal_ledger_path >/dev/null 2>&1; then
      ledger_path=$(_signal_ledger_path)
    fi
    if [[ -n "$ledger_path" ]] && [[ -f "$ledger_path" ]] && command -v jq >/dev/null 2>&1; then
      local pass_hit
      pass_hit=$(jq -c --arg sid "$sid" --arg since "$block_ts" '
        select(.session_id == $sid)
        | select(.event == "pass")
        | select(.gate == "work-integrity-gate")
        | select((.ts // "") > $since)
      ' "$ledger_path" 2>/dev/null | tail -n 1)
      if [[ -n "$pass_hit" ]]; then
        return 1
      fi
    fi
  fi

  printf '%s' "$evidence"
  return 0
}

# ----------------------------------------------------------------------
# Demoted-heuristic warns (non-blocking). Each function echoes a one-line
# detail string when it finds a signal, empty string otherwise. NEVER sets
# a verdict, NEVER blocks — only used to call ledger_emit "warn".
# ----------------------------------------------------------------------

warn_continuing_no_wake_token() {
  local keyword="$1" summary="$2"
  [[ "$keyword" != "CONTINUING" ]] && return 0
  if ! printf '%s' "$summary" | grep -qiE '(scheduled|watchdog|cron|wakeup|wake-up|monitor|background task|task[_ ]?id|task_[a-z0-9]+)'; then
    echo "CONTINUING marker lacks a wake-mechanism token (scheduled|watchdog|cron|wakeup|monitor|task id): \"${summary:0:200}\""
  fi
}

warn_pausing_no_exact_ask() {
  local keyword="$1" summary="$2"
  [[ "$keyword" != "PAUSING" ]] && return 0
  # Heuristic only: an "exact ask" shape usually contains a question mark,
  # an imperative ("reply with"/"confirm"/"choose"), or an explicit
  # decision noun. Absence is a soft signal, not proof.
  if ! printf '%s' "$summary" | grep -qiE '(\?|reply with|confirm|choose|go/no-go|approve|which (option|one)|decision needed)'; then
    echo "PAUSING marker may lack an exact-ask shape (no '?', 'reply with', 'confirm', etc.): \"${summary:0:200}\""
  fi
}

warn_narrate_and_wait() {
  local final_text="$1"
  local trailing
  trailing=$(printf '%s' "$final_text" | tail -c 600)
  local patterns=(
    'want me to (continue|proceed|go ahead|move on)'
    'would you like me to'
    'do you want me to'
    'shall I (continue|proceed|go ahead)'
    'let me know (if|when|what)'
    'awaiting (your|confirmation|approval|go)'
    'if you.?d like me to'
  )
  local p match
  for p in "${patterns[@]}"; do
    match=$(printf '%s' "$trailing" | grep -iEo "$p" | head -1)
    if [[ -n "$match" ]]; then
      echo "narrate-and-wait phrase in final-message tail: \"$match\""
      return 0
    fi
  done
  return 0
}

# ----------------------------------------------------------------------
# warn_decision_block_no_needs_you <final_text>
#
# E.6's D.3 warn extension, reassigned here per specs-e §E.10 item 11
# (single owner of session-honesty-gate edits this wave): the final
# message contains a constitution §3 decision block ("Decision needed:"
# compact format, or the legacy "PAUSING:"-adjacent decision framing) but
# NEEDS-YOU.md has no entry for this session. Calls E.6's
# `needs-you.sh has-entry-for-session <sid>` query flag when that script
# exists; TOLERATES ITS ABSENCE (E.6 may not have landed on this tree yet
# — this warn must never error or block on a missing sibling script, only
# skip silently, same tolerate-absent contract as the digest's other
# cross-task feeds).
# ----------------------------------------------------------------------
warn_decision_block_no_needs_you() {
  local final_text="$1" sid="$2"

  # Heuristic decision-block detector: constitution §3's compact format
  # opens with "Decision needed:" (case-insensitive, optionally bolded);
  # also catch the common "Reply with:" companion line the format mandates
  # so a decision block missing the exact header phrase is still caught.
  printf '%s' "$final_text" | grep -qiE '\*{0,2}Decision needed:\*{0,2}|^\*{0,2}Reply with:\*{0,2}' || return 0

  # Resolve needs-you.sh: repo-relative (adapters/claude-code/scripts/) or
  # live-mirror (~/.claude/scripts/). Absence is NOT an error — E.6 may not
  # have landed on this tree yet.
  local nyu=""
  local repo_root=""
  if command -v git >/dev/null 2>&1; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  fi
  if [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/scripts/needs-you.sh" ]]; then
    nyu="${repo_root}/adapters/claude-code/scripts/needs-you.sh"
  elif [[ -f "${HOME:-}/.claude/scripts/needs-you.sh" ]]; then
    nyu="${HOME}/.claude/scripts/needs-you.sh"
  fi
  [[ -z "$nyu" ]] && return 0   # tolerate-absent: E.6 not present on this tree

  local has_entry
  has_entry=$(bash "$nyu" has-entry-for-session "$sid" 2>/dev/null || echo "")
  if [[ "$has_entry" != "true" ]] && [[ "$has_entry" != "1" ]]; then
    echo "final message contains a decision block but NEEDS-YOU.md has no entry for this session (constitution §2 ledger requirement)"
  fi
  return 0
}

warn_deferral_phrases() {
  local final_text="$1"
  local patterns=('\bdeferred?\b' '\bTBD\b' '\bFIXME\b' 'follow-up' 'future work' 'next session' 'out of scope for this')
  local p n=0
  for p in "${patterns[@]}"; do
    if printf '%s' "$final_text" | grep -qiE "$p"; then
      n=$((n+1))
    fi
  done
  [[ "$n" -gt 0 ]] && echo "${n} deferral-phrase pattern(s) matched in final message"
  return 0
}

warn_subflagrant_contradiction() {
  local final_text="$1"
  local has_completion=0 has_deferral=0
  printf '%s' "$final_text" | grep -qiE '\b(shipped|merged|all done|tests? pass(ed|ing)?|verified)\b' && has_completion=1
  printf '%s' "$final_text" | grep -qiE '(deferred to|awaiting user|not yet (run|executed|tested)|pending (approval|review))' && has_deferral=1
  if [[ "$has_completion" -eq 1 ]] && [[ "$has_deferral" -eq 1 ]]; then
    echo "final message mixes completion language and deferral language (sub-flagrant; below the DONE-after-block bar)"
  fi
  return 0
}

warn_goal_coverage_miss() {
  local final_text="$1" keyword="$2"
  # Best-effort only: if the marker is DONE and the message never
  # mentions a concrete artifact reference (file path, SHA, PR number),
  # flag a soft goal-coverage signal. No goal-file dependency (that is
  # goal-extraction-on-prompt's mechanism, not this gate's).
  [[ "$keyword" != "DONE" ]] && return 0
  if ! printf '%s' "$final_text" | grep -qiE '([a-zA-Z0-9_./-]+\.(sh|md|ts|tsx|js|json|py|go|rb))|([0-9a-f]{7,40}\b)|(#[0-9]+\b)'; then
    echo "DONE claim names no file path, SHA, or PR number in the final message (soft goal-coverage signal)"
  fi
  return 0
}

# ----------------------------------------------------------------------
# emit_warn <detail>  — best-effort ledger_emit wrapper, silent if the
# ledger lib is unavailable (mirrors stop-hook-retry-guard.sh's own
# `command -v ledger_emit` guard).
# ----------------------------------------------------------------------
emit_warn() {
  local gate="$1" detail="$2"
  [[ -z "$detail" ]] && return 0
  if command -v ledger_emit >/dev/null 2>&1; then
    ledger_emit "$gate" "warn" "$detail"
  fi
  return 0
}

# ----------------------------------------------------------------------
# run_demoted_warns <final_text> <keyword> <summary> [<session_id>]
#
# Runs every demoted heuristic and emits a ledger "warn" for each hit.
# NEVER affects the exit code. Called on the allow path only (a message
# that already blocks on the marker-format check has nothing coherent to
# demote-scan).
# ----------------------------------------------------------------------
run_demoted_warns() {
  local final_text="$1" keyword="$2" summary="$3" sid="${4:-}"
  local d

  d=$(warn_continuing_no_wake_token "$keyword" "$summary")
  emit_warn "session-honesty-gate" "$d"

  d=$(warn_pausing_no_exact_ask "$keyword" "$summary")
  emit_warn "session-honesty-gate" "$d"

  d=$(warn_narrate_and_wait "$final_text")
  emit_warn "session-honesty-gate" "$d"

  d=$(warn_deferral_phrases "$final_text")
  emit_warn "session-honesty-gate" "$d"

  d=$(warn_subflagrant_contradiction "$final_text")
  emit_warn "session-honesty-gate" "$d"

  d=$(warn_goal_coverage_miss "$final_text" "$keyword")
  emit_warn "session-honesty-gate" "$d"

  d=$(warn_decision_block_no_needs_you "$final_text" "$sid")
  emit_warn "session-honesty-gate" "$d"
}

# ----------------------------------------------------------------------
# extract_final_text <transcript-path>  — same extraction as
# marker_scan_eval uses, exposed standalone so the demoted-warn scans (and
# --self-test) can reuse it without re-deriving MARKER_* globals.
# ----------------------------------------------------------------------
extract_final_text() {
  local transcript="$1"
  [[ -z "$transcript" ]] || [[ ! -f "$transcript" ]] && { echo ""; return 0; }
  command -v jq >/dev/null 2>&1 || { echo ""; return 0; }
  jq -rs '
    [ .[]
      | select((.type? == "assistant")
               or (.message?.role? == "assistant")
               or (.role? == "assistant")) ] as $a
    | if ($a | length) == 0 then ""
      else
        ($a[-1] | (.message?.content // .content // .text // "")) as $c
        | if ($c | type) == "array" then
            ([ $c[] | if type == "object" then (.text // "")
                      elif type == "string" then .
                      else "" end ] | join("\n"))
          elif ($c | type) == "string" then $c
          else ($c | tostring) end
      end
  ' "$transcript" 2>/dev/null
}

# ----------------------------------------------------------------------
# --self-test
# ----------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'shgst')
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  export SIGNAL_LEDGER_PATH="$TMP/ledger.jsonl"
  export RETRY_GUARD_STATE_DIR="$TMP/.claude/state"
  export RETRY_GUARD_THRESHOLD=3
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID

  jl() { # jl <file> <assistant-text>
    local f="$1" txt="$2"
    : > "$f"
    printf '%s\n' "$(jq -cn --arg t "ask" '{"type":"user","message":{"role":"user","content":[{"type":"text","text":$t}]}}')" >> "$f"
    printf '%s\n' "$(jq -cn --arg t "$txt" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":$t}]}}')" >> "$f"
  }

  ok() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  no() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  run_live() {
    # Invoke the hook's live path with a synthetic stdin JSON pointing at
    # the given transcript + session id. Captures exit code.
    local transcript="$1" sid="$2"
    local input
    input=$(jq -cn --arg t "$transcript" --arg s "$sid" '{"transcript_path":$t,"session_id":$s}')
    printf '%s' "$input" | CLAUDE_SESSION_ID="$sid" bash "${BASH_SOURCE[0]}" \
      >"$TMP/out.json" 2>"$TMP/err.txt"
    echo $?
  }

  echo "Scenario 1: no marker -> block"
  jl "$TMP/s1.jsonl" $'Let me know if you'\''d like me to continue.'
  rc=$(run_live "$TMP/s1.jsonl" "sess-1")
  [[ "$rc" == "2" ]] && ok "no marker blocks (exit 2)" || no "expected exit 2, got $rc"

  echo "Scenario 2: two markers -> block"
  jl "$TMP/s2.jsonl" $'DONE: shipped the thing here today ok\nBLOCKED: but also this other part is stuck'
  rc=$(run_live "$TMP/s2.jsonl" "sess-2")
  [[ "$rc" == "2" ]] && ok "two markers blocks (exit 2)" || no "expected exit 2, got $rc"

  echo "Scenario 3: waiting-on-operator turn ending PAUSING: <exact ask> passes"
  jl "$TMP/s3.jsonl" $'Investigated the migration.\n\nPAUSING: the migration drops the legacy column irreversibly — reply go or no-go to proceed?'
  rc=$(run_live "$TMP/s3.jsonl" "sess-3")
  [[ "$rc" == "0" ]] && ok "PAUSING with exact ask passes" || no "expected exit 0, got $rc"

  echo "Scenario 4: DONE while work-integrity-gate blocked this session (via ledger) -> fails"
  rm -f "$TMP/ledger.jsonl"
  ledger_line=$(jq -cn --arg sid "sess-4" '{"ts":"2026-07-03T10:00:00Z","session_id":$sid,"gate":"work-integrity-gate","event":"block","detail":"unchecked tasks"}')
  printf '%s\n' "$ledger_line" >> "$TMP/ledger.jsonl"
  jl "$TMP/s4.jsonl" $'All shipped.\n\nDONE: shipped everything, merged abc1234'
  rc=$(run_live "$TMP/s4.jsonl" "sess-4")
  [[ "$rc" == "2" ]] && ok "DONE while work-integrity blocked this session fails (exit 2)" || no "expected exit 2, got $rc"

  echo "Scenario 5: DONE with NO recorded block -> passes"
  rm -f "$TMP/ledger.jsonl"
  jl "$TMP/s5.jsonl" $'All shipped.\n\nDONE: shipped everything, merged abc1234'
  rc=$(run_live "$TMP/s5.jsonl" "sess-5")
  [[ "$rc" == "0" ]] && ok "clean DONE (no block record) passes" || no "expected exit 0, got $rc"

  echo "Scenario 6: CONTINUING with verified-running background work passes (+ no warn)"
  rm -f "$TMP/ledger.jsonl"
  jl "$TMP/s6.jsonl" $'Kicked off the long build.\n\nCONTINUING: background task_id bld-778 is running; scheduled watchdog will wake this session on completion'
  rc=$(run_live "$TMP/s6.jsonl" "sess-6")
  [[ "$rc" == "0" ]] && ok "CONTINUING with wake-token passes" || no "expected exit 0, got $rc"
  if [[ -f "$TMP/ledger.jsonl" ]] && grep -q "wake-mechanism token" "$TMP/ledger.jsonl"; then
    no "CONTINUING with wake-token should NOT emit the no-wake-token warn"
  else
    ok "CONTINUING with wake-token emits no wake-token warn"
  fi

  echo "Scenario 7: CONTINUING WITHOUT wake token passes (block) but warns"
  rm -f "$TMP/ledger.jsonl"
  jl "$TMP/s7.jsonl" $'Kicked off some work.\n\nCONTINUING: still working on the remaining files'
  rc=$(run_live "$TMP/s7.jsonl" "sess-7")
  [[ "$rc" == "0" ]] && ok "CONTINUING without wake-token still passes (non-blocking)" || no "expected exit 0, got $rc"
  if [[ -f "$TMP/ledger.jsonl" ]] && grep -q "wake-mechanism token" "$TMP/ledger.jsonl"; then
    ok "CONTINUING without wake-token emits a ledger warn"
  else
    no "expected a wake-mechanism-token warn in the ledger"
  fi

  echo "Scenario 8: minimal-delta retry closing passes (after a prior block)"
  rm -f "$TMP/ledger.jsonl"
  # First attempt: no marker -> block.
  jl "$TMP/retry.jsonl" $'Still working through it.'
  rc1=$(run_live "$TMP/retry.jsonl" "sess-8")
  # Retry: minimal-delta closing, exactly per the design pin.
  jl "$TMP/retry.jsonl" $'DONE: report above stands'
  rc2=$(run_live "$TMP/retry.jsonl" "sess-8")
  if [[ "$rc1" == "2" ]] && [[ "$rc2" == "0" ]]; then
    ok "minimal-delta 2-line retry closing passes after a prior block ($rc1 -> $rc2)"
  else
    no "expected 2 -> 0, got $rc1 -> $rc2"
  fi

  echo "Scenario 9: PAUSING without exact ask passes (non-blocking) but warns"
  rm -f "$TMP/ledger.jsonl"
  jl "$TMP/s9.jsonl" $'Hit a decision point.\n\nPAUSING: need to know how to proceed with the migration approach'
  rc=$(run_live "$TMP/s9.jsonl" "sess-9")
  [[ "$rc" == "0" ]] && ok "PAUSING without exact-ask shape still passes" || no "expected exit 0, got $rc"
  if [[ -f "$TMP/ledger.jsonl" ]] && grep -q "exact-ask shape" "$TMP/ledger.jsonl"; then
    ok "PAUSING without exact-ask shape emits a ledger warn"
  else
    no "expected an exact-ask-shape warn in the ledger"
  fi

  echo "Scenario 10: narrate-and-wait phrasing passes (non-blocking) but warns"
  rm -f "$TMP/ledger.jsonl"
  jl "$TMP/s10.jsonl" $'Fixed the bug.\n\nDONE: fixed the null-pointer bug in checkout, would you like me to also fix the related one?'
  rc=$(run_live "$TMP/s10.jsonl" "sess-10")
  [[ "$rc" == "0" ]] && ok "narrate-and-wait phrasing does not block" || no "expected exit 0, got $rc"
  if [[ -f "$TMP/ledger.jsonl" ]] && grep -q "narrate-and-wait" "$TMP/ledger.jsonl"; then
    ok "narrate-and-wait phrasing emits a ledger warn"
  else
    no "expected a narrate-and-wait warn in the ledger"
  fi

  echo "Scenario 11: deferral phrases pass (non-blocking) but warn"
  rm -f "$TMP/ledger.jsonl"
  jl "$TMP/s11.jsonl" $'Built the initial pass.\n\nDONE: shipped v1, polish is deferred to a follow-up session'
  rc=$(run_live "$TMP/s11.jsonl" "sess-11")
  [[ "$rc" == "0" ]] && ok "deferral phrases do not block" || no "expected exit 0, got $rc"
  if [[ -f "$TMP/ledger.jsonl" ]] && grep -q "deferral-phrase pattern" "$TMP/ledger.jsonl"; then
    ok "deferral phrases emit a ledger warn"
  else
    no "expected a deferral-phrase warn in the ledger"
  fi

  echo "Scenario 12: sub-flagrant contradiction (completion + deferral language, no recorded block) passes but warns"
  rm -f "$TMP/ledger.jsonl"
  jl "$TMP/s12.jsonl" $'All tests pass.\n\nDONE: shipped and verified; the last piece is pending review from another session'
  rc=$(run_live "$TMP/s12.jsonl" "sess-12")
  [[ "$rc" == "0" ]] && ok "sub-flagrant contradiction does not block" || no "expected exit 0, got $rc"
  if [[ -f "$TMP/ledger.jsonl" ]] && grep -q "mixes completion language" "$TMP/ledger.jsonl"; then
    ok "sub-flagrant contradiction emits a ledger warn"
  else
    no "expected a sub-flagrant-contradiction warn in the ledger"
  fi

  echo "Scenario 13: BLOCKED valid marker passes"
  rm -f "$TMP/ledger.jsonl"
  jl "$TMP/s13.jsonl" $'Hit a wall.\n\nBLOCKED: missing E2E_ADMIN_EMAIL — provide it or a sandbox with it set'
  rc=$(run_live "$TMP/s13.jsonl" "sess-13")
  [[ "$rc" == "0" ]] && ok "BLOCKED marker passes" || no "expected exit 0, got $rc"

  echo "Scenario 14: no transcript -> allow (no-op)"
  rc=$(run_live "$TMP/does-not-exist.jsonl" "sess-14")
  [[ "$rc" == "0" ]] && ok "missing transcript no-ops (exit 0)" || no "expected exit 0, got $rc"

  echo "Scenario 15: DONE-vs-block contradiction via unresolved-stop-hooks.log source"
  rm -f "$TMP/ledger.jsonl"
  mkdir -p "$RETRY_GUARD_STATE_DIR"
  {
    printf '2026-07-03T10:00:00Z\thook=work-integrity-gate\tsession=sess_15\tcount=3\tsig=abc123456789\n'
    printf '  error: plan has unchecked tasks\n\n'
  } >> "$RETRY_GUARD_STATE_DIR/unresolved-stop-hooks.log"
  jl "$TMP/s15.jsonl" $'All shipped.\n\nDONE: shipped everything, merged def5678'
  rc=$(run_live "$TMP/s15.jsonl" "sess-15")
  [[ "$rc" == "2" ]] && ok "DONE-vs-block contradiction detected via unresolved-stop-hooks.log" || no "expected exit 2, got $rc"

  echo "Scenario 15b (NL-FINDING-027 item 10a): DONE honest-block-resolve — a work-integrity block followed by a LATER work-integrity PASS for this session clears the contradiction"
  rm -f "$TMP/ledger.jsonl"
  block_line=$(jq -cn --arg sid "sess-15b" '{"ts":"2026-07-03T10:00:00Z","session_id":$sid,"gate":"work-integrity-gate","event":"block","detail":"unchecked tasks"}')
  pass_line=$(jq -cn --arg sid "sess-15b" '{"ts":"2026-07-03T10:05:00Z","session_id":$sid,"gate":"work-integrity-gate","event":"pass","detail":"session-touched checks passed at this Stop"}')
  printf '%s\n' "$block_line" >> "$TMP/ledger.jsonl"
  printf '%s\n' "$pass_line" >> "$TMP/ledger.jsonl"
  jl "$TMP/s15b.jsonl" $'Finished the remaining tasks and re-ran the checks.\n\nDONE: shipped everything, merged def9999'
  rc=$(run_live "$TMP/s15b.jsonl" "sess-15b")
  [[ "$rc" == "0" ]] && ok "DONE after block-then-LATER-pass resolves (honest block-resolve-DONE passes)" || no "expected exit 0, got $rc"

  echo "Scenario 15c (NL-FINDING-027 item 10a regression): DONE-riding — a work-integrity block with NO later pass and NO waiver still blocks (not downgradeable via a stale pass)"
  rm -f "$TMP/ledger.jsonl"
  block_line=$(jq -cn --arg sid "sess-15c" '{"ts":"2026-07-03T10:00:00Z","session_id":$sid,"gate":"work-integrity-gate","event":"block","detail":"unchecked tasks"}')
  stale_pass_line=$(jq -cn --arg sid "sess-15c" '{"ts":"2026-07-03T09:00:00Z","session_id":$sid,"gate":"work-integrity-gate","event":"pass","detail":"an EARLIER pass, before the block — must not count"}')
  printf '%s\n' "$stale_pass_line" >> "$TMP/ledger.jsonl"
  printf '%s\n' "$block_line" >> "$TMP/ledger.jsonl"
  jl "$TMP/s15c.jsonl" $'Still riding on the earlier pass.\n\nDONE: shipped everything, merged def0000'
  rc=$(run_live "$TMP/s15c.jsonl" "sess-15c")
  [[ "$rc" == "2" ]] && ok "DONE-riding on a PRE-block pass still blocks (exit 2, not downgradeable)" || no "expected exit 2, got $rc"

  echo "Scenario 15d: RETRY_GUARD_VERIFICATION_HOOKS (lib default) lists session-honesty-gate"
  if printf '%s' "$RETRY_GUARD_VERIFICATION_HOOKS" | grep -qw "session-honesty-gate"; then
    ok "retry-guard lib default RETRY_GUARD_VERIFICATION_HOOKS includes session-honesty-gate"
  else
    no "RETRY_GUARD_VERIFICATION_HOOKS='$RETRY_GUARD_VERIFICATION_HOOKS' does not list session-honesty-gate"
  fi

  echo "Scenario 15e: verification-class registration means a DONE-riding session-honesty-gate block is NOT downgradeable at the retry-guard threshold"
  rm -rf "$TMP/rg-state-15e"
  mkdir -p "$TMP/rg-state-15e"
  (
    export RETRY_GUARD_STATE_DIR="$TMP/rg-state-15e"
    export RETRY_GUARD_THRESHOLD=3
    export CLAUDE_SESSION_ID="shg-done-sess"
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"work summary\n\nDONE: shipped everything abc1234"}]}}' > "$TMP/rg-state-15e/done-transcript.jsonl"
    export RETRY_GUARD_TRANSCRIPT="$TMP/rg-state-15e/done-transcript.jsonl"
    # shellcheck disable=SC1090
    source "$(dirname "${BASH_SOURCE[0]}")/lib/stop-hook-retry-guard.sh"
    _=$(retry_guard_record "session-honesty-gate" "shg-done-sess" "no-marker")
    _=$(retry_guard_record "session-honesty-gate" "shg-done-sess" "no-marker")
    set +e
    ( retry_guard_block_or_exit "session-honesty-gate" "shg-done-sess" "no-marker" \
        "no marker on final line" \
        '{"decision":"block"}' 2 ) >"$TMP/shg-rg-out" 2>"$TMP/shg-rg-err"
    rc=$?
    set -e
    exit "$rc"
  )
  rc=$?
  [[ "$rc" == "2" ]] && ok "session-honesty-gate DONE-riding NOT downgraded at threshold (exit 2)" || no "expected exit 2, got $rc"
  if grep -q "downgrade REFUSED" "$TMP/shg-rg-err" 2>/dev/null; then
    ok "retry-guard refusal stanza names session-honesty-gate"
  else
    no "expected 'downgrade REFUSED' in retry-guard stderr"
  fi

  echo "Scenario 15f (specs-e §E.10 item 11, E.6's D.3 warn reassigned): decision block with NO needs-you.sh on this tree tolerates absence (no crash, no warn — E.6 not present)"
  rm -f "$TMP/ledger.jsonl"
  jl "$TMP/s15f.jsonl" $'Investigated the migration.\n\n**Decision needed:** pick an approach.\n\n**Reply with:** A or B.\n\nDONE: report above stands'
  rc=$(run_live "$TMP/s15f.jsonl" "sess-15f")
  [[ "$rc" == "0" ]] && ok "decision-block warn tolerates absent needs-you.sh (exit 0)" || no "expected exit 0, got $rc"

  echo "Scenario 15g: decision block + needs-you.sh present + has-entry-for-session=false -> emits the D.3 warn"
  rm -f "$TMP/ledger.jsonl"
  FAKE_NYU_DIR="$TMP/fake-scripts"
  mkdir -p "$FAKE_NYU_DIR"
  cat > "$FAKE_NYU_DIR/needs-you.sh" <<'FAKENYU'
#!/bin/bash
if [[ "${1:-}" == "has-entry-for-session" ]]; then
  echo "false"
  exit 0
fi
exit 1
FAKENYU
  chmod +x "$FAKE_NYU_DIR/needs-you.sh"
  # Fake a repo root whose adapters/claude-code/scripts/needs-you.sh resolves
  # to the stub above (git rev-parse --show-toplevel is used by the resolver;
  # simplest correct fixture is the live-mirror fallback path via HOME).
  FAKE_HOME="$TMP/fake-home-15g"
  mkdir -p "$FAKE_HOME/.claude/scripts"
  cp "$FAKE_NYU_DIR/needs-you.sh" "$FAKE_HOME/.claude/scripts/needs-you.sh"
  jl "$TMP/s15g.jsonl" $'Investigated the migration.\n\n**Decision needed:** pick an approach.\n\n**Reply with:** A or B.\n\nDONE: report above stands'
  input=$(jq -cn --arg t "$TMP/s15g.jsonl" --arg s "sess-15g" '{"transcript_path":$t,"session_id":$s}')
  printf '%s' "$input" | HOME="$FAKE_HOME" CLAUDE_SESSION_ID="sess-15g" bash "${BASH_SOURCE[0]}" >"$TMP/out15g.json" 2>"$TMP/err15g.txt"
  rc=$?
  [[ "$rc" == "0" ]] && ok "decision-block + no needs-you entry still passes (non-blocking warn)" || no "expected exit 0, got $rc"
  if [[ -f "$TMP/ledger.jsonl" ]] && grep -q "NEEDS-YOU.md has no entry" "$TMP/ledger.jsonl"; then
    ok "decision-block-no-needs-you-entry emits the D.3 warn"
  else
    no "expected a 'NEEDS-YOU.md has no entry' warn in the ledger"
  fi

  echo "Scenario 16: SESSION_HONESTY_GATE_DISABLE=1 no-ops even with no marker"
  jl "$TMP/s16.jsonl" $'trailing off with no marker at all'
  input=$(jq -cn --arg t "$TMP/s16.jsonl" --arg s "sess-16" '{"transcript_path":$t,"session_id":$s}')
  printf '%s' "$input" | SESSION_HONESTY_GATE_DISABLE=1 CLAUDE_SESSION_ID="sess-16" bash "${BASH_SOURCE[0]}" >"$TMP/out16.json" 2>"$TMP/err16.txt"
  rc=$?
  [[ "$rc" == "0" ]] && ok "SESSION_HONESTY_GATE_DISABLE=1 no-ops" || no "expected exit 0, got $rc"

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  [[ "$FAILED" == "0" ]] && exit 0 || exit 1
fi

# ----------------------------------------------------------------------
# Live Stop-hook path
# ----------------------------------------------------------------------
if [[ -n "${SESSION_HONESTY_GATE_DISABLE:-}" ]]; then
  exit 0
fi

INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi

RG_SESSION_ID=$(retry_guard_session_id "$INPUT")

TRANSCRIPT_PATH=""
if [[ -n "$INPUT" ]] && command -v jq >/dev/null 2>&1; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
fi

marker_scan_eval "$TRANSCRIPT_PATH"

if [[ "$MARKER_VERDICT" == "block" ]]; then
  cat >&2 <<MSG
================================================================
SESSION HONESTY GATE — SESSION END BLOCKED
================================================================

Every turn MUST end with EXACTLY ONE marker, alone on the LAST
non-empty line of the final response:

  DONE: <what shipped>
  PAUSING: <the decision needed + the exact question>
  BLOCKED: <the specific blocker + what would unblock it>
  CONTINUING: <verified-running background work + the wake mechanism>

Reason this is blocked:
  ${MARKER_MSG}

Minimal-delta fix: append ONE line with the correct marker (e.g.
"DONE: report above stands" or "BLOCKED: <blocker>"). This gate
never demands you restate the report — the marker line alone is
sufficient once it is correct.
================================================================
MSG

  ledger_emit_ok=0
  command -v ledger_emit >/dev/null 2>&1 && ledger_emit_ok=1
  [[ "$ledger_emit_ok" -eq 1 ]] && ledger_emit "session-honesty-gate" "block" "${MARKER_SIG}: ${MARKER_MSG}"

  retry_guard_block_or_exit \
    "session-honesty-gate" \
    "$RG_SESSION_ID" \
    "session-honesty-gate:${MARKER_SIG}" \
    "${MARKER_MSG}" \
    '{"decision": "block", "reason": "Session honesty gate: the final message lacks a single valid DONE/PAUSING/BLOCKED/CONTINUING marker on its last line. See stderr. Append exactly one honest terminal-state marker and re-end."}' \
    2
fi

# --- Marker format is valid. Check condition (b): DONE-vs-block contradiction. ---
if [[ "$MARKER_KEYWORD" == "DONE" ]]; then
  CONTRA_EVIDENCE=$(done_contradicted_by_block "$RG_SESSION_ID")
  if [[ -n "$CONTRA_EVIDENCE" ]]; then
    CONTRA_MSG="Marked DONE: but work-integrity-gate (or its pre-D.5 shim) recorded a BLOCK for this session. Evidence: ${CONTRA_EVIDENCE}"
    cat >&2 <<MSG
================================================================
SESSION HONESTY GATE — SESSION END BLOCKED (DONE-vs-BLOCK CONTRADICTION)
================================================================

${CONTRA_MSG}

This is a flagrant self-contradiction: claiming the work is DONE
while the harness's own work-state verifier told this session the
work is incomplete. Two honest resolutions:

  1. Actually finish the work so work-integrity-gate passes, then
     keep the DONE: marker.
  2. Change the marker to PAUSING:/BLOCKED: naming the specific gap
     work-integrity-gate identified.

Do not re-assert DONE: without one of the above.
================================================================
MSG
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "session-honesty-gate" "block" "done-vs-block-contradiction: ${CONTRA_EVIDENCE}"
    retry_guard_block_or_exit \
      "session-honesty-gate" \
      "$RG_SESSION_ID" \
      "session-honesty-gate:done-vs-block-contradiction" \
      "$CONTRA_MSG" \
      '{"decision": "block", "reason": "Session honesty gate: DONE: claimed while work-integrity-gate blocked this session. See stderr."}' \
      2
  fi
fi

# --- Allow path: run demoted heuristics as non-blocking ledger warns. ---
FINAL_TEXT=$(extract_final_text "$TRANSCRIPT_PATH")
if [[ -n "$FINAL_TEXT" ]]; then
  run_demoted_warns "$FINAL_TEXT" "$MARKER_KEYWORD" "$MARKER_SUMMARY" "$RG_SESSION_ID"
fi

exit 0
