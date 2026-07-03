#!/bin/bash
# continuation-enforcer.sh — Stop hook
#
# Enforces ~/.claude/doctrine/session-end-protocol.md: every session MUST end
# its turn with EXACTLY ONE machine-readable marker — DONE: / PAUSING: /
# BLOCKED: — alone on the last non-empty line of its final response.
#
# This makes the model's terminal intent explicit and auditable instead of
# trailing off mid-work and forcing the operator to babysit. It is the
# positive-declaration counterpart to narrate-and-wait-gate.sh: that gate
# catches permission-seeking trail-off; this gate requires a committed,
# checkable terminal-state assertion.
#
# Checks (in order):
#   1. No transcript / no jq                      -> no-op exit 0
#   2. CONTINUATION_ENFORCER_DISABLE=1            -> no-op exit 0
#   3. Zero markers in the final assistant message -> BLOCK
#   4. Two or more marker lines (contradiction)    -> BLOCK
#   5. Single marker but not on the last line      -> BLOCK
#   6. Marker format-invalid (summary below floor) -> BLOCK
#   7. DONE: but last TodoWrite has incomplete items -> BLOCK (lists them)
#   8. PAUSING: / BLOCKED: reason below substance floor -> BLOCK
#   9. Valid marker, all cross-checks pass         -> allow exit 0
#
# Substance floors (non-whitespace chars of the summary):
#   DONE     >= 10   (a concrete one-line "what shipped")
#   PAUSING  >= 20   (specific decision + the input needed)
#   BLOCKED  >= 20   (specific blocker + what unblocks it)
#
# Exit codes:
#   0 — session may terminate
#   2 — blocked; stderr explains, JSON {"decision":"block"} on stdout
#
# Loop safety: sources lib/stop-hook-retry-guard.sh. After 3 identical
# failures with no new commits the block downgrades to a warn and the gap
# is logged to .claude/state/unresolved-stop-hooks.log.
#
# Escape hatch: CONTINUATION_ENFORCER_DISABLE=1 for harness-development
# sessions that edit the marker vocabulary itself.

set -u

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/lib/stop-hook-retry-guard.sh"

# ----------------------------------------------------------------------
# Core evaluation, factored so --self-test can drive it with a transcript
# path directly. Echoes nothing; sets EVAL_VERDICT / EVAL_SIG / EVAL_MSG /
# EVAL_KEYWORD globals. Returns 0 for allow, 1 for block.
# ----------------------------------------------------------------------
EVAL_VERDICT=""
EVAL_SIG=""
EVAL_MSG=""

continuation_eval() {
  local transcript="$1"
  EVAL_VERDICT="allow"
  EVAL_SIG=""
  EVAL_MSG=""

  if [[ -z "$transcript" ]] || [[ ! -f "$transcript" ]]; then
    EVAL_VERDICT="allow"; return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    EVAL_VERDICT="allow"; return 0
  fi

  # --- Final assistant message text ---
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
    # No assistant message extractable -> do not block on a blank scan.
    EVAL_VERDICT="allow"; return 0
  fi

  # --- Marker line scan ---
  local marker_re='^[[:space:]>*_`#-]*(DONE|PAUSING|BLOCKED):[[:space:]]'
  local n_markers
  n_markers=$(printf '%s\n' "$final_text" | grep -cE "$marker_re" 2>/dev/null || true)
  n_markers=${n_markers//[!0-9]/}
  [[ -z "$n_markers" ]] && n_markers=0

  if [[ "$n_markers" -eq 0 ]]; then
    EVAL_VERDICT="block"
    EVAL_SIG="no-marker"
    EVAL_MSG="No DONE: / PAUSING: / BLOCKED: marker on the last line of your final message."
    return 1
  fi
  if [[ "$n_markers" -ge 2 ]]; then
    EVAL_VERDICT="block"
    EVAL_SIG="multi-marker"
    EVAL_MSG="Found ${n_markers} marker lines. The final response must carry EXACTLY ONE terminal-state marker — pick the one true state."
    return 1
  fi

  # --- The single marker must be the last non-empty line ---
  local last_line
  last_line=$(printf '%s\n' "$final_text" | awk 'NF{l=$0} END{print l}')
  local stripped
  stripped=$(printf '%s' "$last_line" \
    | sed -E 's/^[[:space:]>*_`#-]+//' \
    | sed -E 's/[[:space:]*_`]+$//')

  if ! printf '%s' "$stripped" | grep -qE '^(DONE|PAUSING|BLOCKED):[[:space:]]'; then
    EVAL_VERDICT="block"
    EVAL_SIG="marker-not-terminal"
    EVAL_MSG="A marker exists but is not on the last non-empty line. The marker must be the terminal line so the operator (and this hook) see it where they look."
    return 1
  fi

  local keyword summary
  keyword=$(printf '%s' "$stripped" | sed -E 's/^(DONE|PAUSING|BLOCKED):.*$/\1/')
  summary=$(printf '%s' "$stripped" | sed -E 's/^(DONE|PAUSING|BLOCKED):[[:space:]]*//')
  local nws
  nws=$(printf '%s' "$summary" | tr -d '[:space:]' | wc -c | tr -d ' ')
  [[ -z "$nws" ]] && nws=0

  local floor=10
  case "$keyword" in
    PAUSING|BLOCKED) floor=20 ;;
    DONE) floor=10 ;;
  esac

  if [[ "$nws" -lt "$floor" ]]; then
    EVAL_VERDICT="block"
    EVAL_SIG="format-invalid-${keyword}"
    if [[ "$keyword" == "PAUSING" ]]; then
      EVAL_MSG="PAUSING: requires a SPECIFIC reason AND what user input is needed (>=${floor} non-ws chars). Got ${nws}. State the decision that is the user's to make and the exact question that unblocks you."
    elif [[ "$keyword" == "BLOCKED" ]]; then
      EVAL_MSG="BLOCKED: requires a SPECIFIC blocker AND what would unblock it (>=${floor} non-ws chars). Got ${nws}. Name the missing resource and what a future session needs to proceed."
    else
      EVAL_MSG="DONE: requires a concrete one-line summary of what shipped (>=${floor} non-ws chars). Got ${nws}. Name the artifact / commit / plan, not just 'done'."
    fi
    return 1
  fi

  # --- DONE / TodoWrite consistency ---
  if [[ "$keyword" == "DONE" ]]; then
    local todos
    todos=$(jq -c -s '
      [ .[]
        | (.message?.content // .content // [])
        | if type=="array" then .[] else empty end
        | select(type=="object" and (.type? == "tool_use") and (.name? == "TodoWrite"))
        | (.input?.todos // [])
      ] | if length==0 then null else .[-1] end
    ' "$transcript" 2>/dev/null || echo "null")

    if [[ -n "$todos" ]] && [[ "$todos" != "null" ]]; then
      local n_incomplete
      n_incomplete=$(printf '%s' "$todos" | jq -r '[ .[]? | select(.status != "completed") ] | length' 2>/dev/null || echo 0)
      n_incomplete=${n_incomplete//[!0-9]/}
      [[ -z "$n_incomplete" ]] && n_incomplete=0
      if [[ "$n_incomplete" -gt 0 ]]; then
        local list
        list=$(printf '%s' "$todos" | jq -r '.[]? | select(.status != "completed") | "  - [\(.status)] \(.content)"' 2>/dev/null | head -20)
        EVAL_VERDICT="block"
        EVAL_SIG="done-with-incomplete-todos"
        EVAL_MSG=$(printf 'Marked DONE: but the last TodoWrite has %s incomplete item(s):\n%s\nComplete them (then DONE:) or change the marker to PAUSING:/BLOCKED: with an honest explanation of why they cannot be finished now.' "$n_incomplete" "$list")
        return 1
      fi
    fi
  fi

  EVAL_VERDICT="allow"
  return 0
}

# ----------------------------------------------------------------------
# --self-test
# ----------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'cest')
  trap 'rm -rf "$TMP"' EXIT

  jl() { # build a JSONL transcript: jl <file> <assistant-text> [todos-json]
    local f="$1" txt="$2" todos="${3:-}"
    : > "$f"
    printf '%s\n' "$(jq -cn --arg t "ask" '{"type":"user","message":{"role":"user","content":[{"type":"text","text":$t}]}}')" >> "$f"
    if [[ -n "$todos" ]]; then
      printf '%s\n' "$(jq -cn --argjson td "$todos" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"TodoWrite","input":{"todos":$td}}]}}')" >> "$f"
    fi
    printf '%s\n' "$(jq -cn --arg t "$txt" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":$t}]}}')" >> "$f"
  }

  ok() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  no() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  run() { continuation_eval "$1"; echo "$EVAL_VERDICT"; }

  echo "Scenario 1: DONE valid, all todos completed -> allow"
  jl "$TMP/s1.jsonl" $'Shipped the thing.\n\nDONE: shipped continuation-enforcer.sh + rule, self-test green, merged abc1234' \
     '[{"content":"build hook","status":"completed","activeForm":"building"}]'
  [[ "$(run "$TMP/s1.jsonl")" == "allow" ]] && ok "DONE valid allows" || no "DONE valid should allow"

  echo "Scenario 2: DONE but incomplete TodoWrite -> block"
  jl "$TMP/s2.jsonl" $'All set.\n\nDONE: everything shipped and verified end to end' \
     '[{"content":"build hook","status":"completed","activeForm":"b"},{"content":"wire settings","status":"in_progress","activeForm":"w"}]'
  continuation_eval "$TMP/s2.jsonl"
  if [[ "$EVAL_VERDICT" == "block" && "$EVAL_SIG" == "done-with-incomplete-todos" ]]; then ok "DONE+incomplete-todo blocks"; else no "expected done-with-incomplete-todos block, got $EVAL_VERDICT/$EVAL_SIG"; fi

  echo "Scenario 3: PAUSING valid (substantive) -> allow"
  jl "$TMP/s3.jsonl" $'Need a call here.\n\nPAUSING: the migration drops the legacy column irreversibly — need your explicit go/no-go before applying to production'
  [[ "$(run "$TMP/s3.jsonl")" == "allow" ]] && ok "PAUSING substantive allows" || no "PAUSING substantive should allow"

  echo "Scenario 4: PAUSING without reason (too short) -> block"
  jl "$TMP/s4.jsonl" $'Waiting.\n\nPAUSING: need input'
  continuation_eval "$TMP/s4.jsonl"
  if [[ "$EVAL_VERDICT" == "block" && "$EVAL_SIG" == "format-invalid-PAUSING" ]]; then ok "PAUSING thin blocks"; else no "expected format-invalid-PAUSING, got $EVAL_VERDICT/$EVAL_SIG"; fi

  echo "Scenario 5: no marker at all -> block"
  jl "$TMP/s5.jsonl" $'Let me know if you'\''d like me to continue with phase 2.'
  continuation_eval "$TMP/s5.jsonl"
  if [[ "$EVAL_VERDICT" == "block" && "$EVAL_SIG" == "no-marker" ]]; then ok "no-marker blocks"; else no "expected no-marker, got $EVAL_VERDICT/$EVAL_SIG"; fi

  echo "Scenario 6: BLOCKED valid -> allow"
  jl "$TMP/s6.jsonl" $'Hit a wall.\n\nBLOCKED: e2e suite needs E2E_ADMIN_EMAIL which is unset here — provide it or a sandbox with it set to finish Task 4'
  [[ "$(run "$TMP/s6.jsonl")" == "allow" ]] && ok "BLOCKED valid allows" || no "BLOCKED valid should allow"

  echo "Scenario 7: two markers (contradiction) -> block"
  jl "$TMP/s7.jsonl" $'DONE: shipped the main thing here ok\nBLOCKED: but the e2e environment is missing the admin credential entirely'
  continuation_eval "$TMP/s7.jsonl"
  if [[ "$EVAL_VERDICT" == "block" && "$EVAL_SIG" == "multi-marker" ]]; then ok "multi-marker blocks"; else no "expected multi-marker, got $EVAL_VERDICT/$EVAL_SIG"; fi

  echo "Scenario 8: single marker but not on last line -> block"
  jl "$TMP/s8.jsonl" $'DONE: shipped everything that was in scope here\n\nThanks, talk soon!'
  continuation_eval "$TMP/s8.jsonl"
  if [[ "$EVAL_VERDICT" == "block" && "$EVAL_SIG" == "marker-not-terminal" ]]; then ok "marker-not-terminal blocks"; else no "expected marker-not-terminal, got $EVAL_VERDICT/$EVAL_SIG"; fi

  echo "Scenario 9: no transcript -> allow (no-op)"
  [[ "$(run "$TMP/does-not-exist.jsonl")" == "allow" ]] && ok "missing transcript no-ops" || no "missing transcript should allow"

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  [[ "$FAILED" == "0" ]] && exit 0 || exit 1
fi

# ----------------------------------------------------------------------
# Live Stop-hook path
# ----------------------------------------------------------------------
if [[ -n "${CONTINUATION_ENFORCER_DISABLE:-}" ]]; then
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

continuation_eval "$TRANSCRIPT_PATH"

if [[ "$EVAL_VERDICT" == "allow" ]]; then
  exit 0
fi

cat >&2 <<MSG
================================================================
CONTINUATION ENFORCER — SESSION END BLOCKED
================================================================

Per ~/.claude/doctrine/session-end-protocol.md, every session MUST end
its turn with EXACTLY ONE marker, alone on the LAST non-empty line of
its final response:

  DONE: <one-line summary of what shipped>
  PAUSING: <the user decision needed + the exact question>
  BLOCKED: <the specific blocker + what would unblock it>

Reason this is blocked:
  ${EVAL_MSG}

What to do:
  - If your declared work is genuinely complete AND no TodoWrite item
    is incomplete, append:  DONE: <concrete what-shipped>
  - If you are waiting on a non-delegable user decision, append:
    PAUSING: <the decision + the specific input you need>
  - If you hit a real blocker outside your control, append:
    BLOCKED: <the specific blocker + what unblocks it>
  - If there is MORE declared work and no blocker, do NOT add a
    marker — keep working. There is no marker for a no-reason pause;
    that is the narrate-and-wait failure (see narrate-and-wait-gate).

Do not rephrase a trail-off. Commit to one honest terminal state.
================================================================
MSG

retry_guard_block_or_exit \
  "continuation-enforcer" \
  "$RG_SESSION_ID" \
  "continuation-enforcer:${EVAL_SIG}" \
  "${EVAL_MSG}" \
  '{"decision": "block", "reason": "Continuation enforcer: the final message lacks a single valid DONE/PAUSING/BLOCKED marker on its last line (or a marker cross-check failed). See stderr. Append exactly one honest terminal-state marker and re-end, or keep working if there is more declared work."}' \
  2
