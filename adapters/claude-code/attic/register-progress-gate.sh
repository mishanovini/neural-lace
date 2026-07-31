#!/bin/bash
# register-progress-gate.sh — Stop hook
#
# The anti-babysitting gate. It makes the precise failure of 2026-06-13
# structurally impossible: a WORKING session that ends by re-emitting an
# "awaiting Misha" list as if it were progress, having advanced nothing.
#
# Misha's complaint, verbatim: "report completion against [the register] —
# not 'awaiting Misha' lists." Stating ownership in prose guarantees
# nothing; only a Mechanism holds. This is that Mechanism.
#
# It BLOCKS session end when ALL of these hold:
#   1. The session was a WORKING session (transcript shows tool use:
#      Edit/Write/Bash/Agent) — pure conversational turns are exempt.
#   2. The FINAL assistant message carries the "awaiting-Misha" signature.
#   3. The FINAL message carries NO completion-evidence token (commit
#      SHA-near-verb, merged/pushed/committed/deployed/shipped, self-test,
#      PASS, a "DONE:" marker, "PR #NNN merged/opened", "RWR-NN" advance,
#      "preserved on origin", "→ master").
#   4. No fresh per-item blocker recorded
#      (.claude/state/register-blocker-*.txt, < 1h, >= 1 substantive line).
#
# In words: if you did work you'll have an evidence token and pass; if
# you're genuinely blocked you name the specific blocker and pass; the ONLY
# thing that blocks is ending a working session with an awaiting-list and
# nothing advanced and no named blocker — i.e. babysitting.
#
# Composes with register-surfacer.sh (SessionStart half), narrate-and-wait
# -gate.sh, pre-stop-verifier.sh. Uses lib/stop-hook-retry-guard.sh for the
# 3-retry downgrade-to-warn loop-break.
#
# Escape hatches: .claude/state/register-blocker-<ts>.txt (fresh);
# REGISTER_GATE_DISABLE=1; mode REGISTER_GATE_MODE env >
# ~/.claude/local/register-gate-mode file > "block".
#
# Self-test: --self-test exercises block/allow scenarios.

set -u
HOOK_NAME="register-progress-gate"

EVIDENCE_RE='merged|pushed|committed|commit [0-9a-f]{7}|deployed|shipped|self-test|[0-9]+/[0-9]+ (pass|green)|\bPASS\b|DONE:|RWR-[0-9]|PR #[0-9]+ (merged|opened|open|squash)|→ master|ancestor of|preserved on origin'
AWAIT_RE='awaiting (you|misha|your)|waiting on (you|your)|blocked on your|needs your (decision|input|call)|for you to decide|pending your|your call|decisions? await|await(ing)? (his|misha)|still (need|awaiting) from (you|misha)'

_json_str() { printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 | sed -E "s/.*:[[:space:]]*\"([^\"]*)\".*/\1/"; }

# Final assistant message text. EC-2: prefer a PRECISE jq extraction of the
# LAST assistant-role message (the proven pr-health-snapshot-gate pattern) so we
# never match a tool_result's "text" field; fall back to a jq-free best-effort
# scan only when jq is unavailable.
final_msg() {
  local t="$1" b64
  if command -v jq >/dev/null 2>&1; then
    b64=$(jq -r '
      select(.role == "assistant" or .message.role == "assistant")
      | (.content // .text // .message.content // empty)
      | (if type == "string" then .
         elif type == "array" then ([.[] | select(type=="object" and (.type//"")=="text") | (.text // "")] | join("\n"))
         else (. | tostring) end)
      | select(. != "")
      | @base64
    ' "$t" 2>/dev/null | tail -n 1)
    if [ -n "$b64" ]; then printf '%s' "$b64" | base64 --decode 2>/dev/null; return; fi
  fi
  # jq-free fallback (best-effort; may include tool_result text)
  tail -n 400 "$t" 2>/dev/null \
    | grep -oE '"text"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' \
    | tail -n 12 \
    | sed -E 's/^"text"[[:space:]]*:[[:space:]]*"//; s/"$//' \
    | sed -E 's/\\n/ /g; s/\\"/"/g'
}

# EC-1: did the session ACTUALLY advance work this session? A real git
# commit/push tool_use means the session is not babysitting by definition —
# even if the final message forgot to cite it. Precision matters here, so this
# is jq-only (reads tool_use .input.command, NOT loose prose); without jq we
# skip this allow-path and fall back to the final-message-only logic (which is
# stricter, i.e. the safe direction). Returns 0 if advanced.
session_advanced_in_transcript() {
  local t="$1" cmds
  command -v jq >/dev/null 2>&1 || return 1
  cmds=$(jq -r '
    (.message.content // .content // empty)
    | if type=="array"
      then (.[] | select(type=="object" and (.type//"")=="tool_use") | (.input.command // .input.cmd // empty))
      else empty end
  ' "$t" 2>/dev/null)
  printf '%s' "$cmds" | grep -qE 'git[[:space:]]+(commit|push)([[:space:]]|$)' && return 0
  return 1
}

blocker_fresh() {
  local dir="${1:-.claude/state}" f now mt age
  [ -d "$dir" ] || return 1
  now=$(date +%s 2>/dev/null) || return 1
  for f in "$dir"/register-blocker-*.txt; do
    [ -f "$f" ] || continue
    grep -qE '[^[:space:]]' "$f" || continue
    mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) || continue
    age=$(( now - mt ))
    [ "$age" -ge 0 ] && [ "$age" -le 3600 ] && return 0
  done
  return 1
}

run() {
  [ "${REGISTER_GATE_DISABLE:-}" = "1" ] && exit 0
  local mode="${REGISTER_GATE_MODE:-}"
  if [ -z "$mode" ] && [ -f "$HOME/.claude/local/register-gate-mode" ]; then
    mode="$(head -n1 "$HOME/.claude/local/register-gate-mode" 2>/dev/null | tr -d '\r')"
  fi
  mode="${mode:-block}"

  local input transcript
  input="$(cat 2>/dev/null || true)"
  transcript="$(_json_str "$input" transcript_path)"
  [ -z "$transcript" ] && transcript="$(_json_str "$input" transcriptPath)"
  { [ -z "$transcript" ] || [ ! -f "$transcript" ]; } && exit 0   # never block blind

  # 1) working session?
  grep -qE '"(name|tool_name)"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit|Bash|PowerShell|Agent|NotebookEdit)"' "$transcript" 2>/dev/null || exit 0

  local final; final="$(final_msg "$transcript")"
  [ -z "$final" ] && exit 0

  # 3) completion evidence in the final message → advanced + reported → allow
  printf '%s' "$final" | grep -qiE "$EVIDENCE_RE" && exit 0
  # 2) awaiting signature present? if not, out of scope → allow
  printf '%s' "$final" | grep -qiE "$AWAIT_RE" || exit 0
  # EC-1) transcript shows a real git commit/push this session → the session
  #       advanced work; it is NOT babysitting even if the final message did not
  #       cite it. Allow, but NUDGE toward the report-it discipline.
  if session_advanced_in_transcript "$transcript"; then
    echo "[register-progress-gate] note: this session committed/pushed work but the final message did not cite it. Allowing — but cite the commit/PR/RWR-NN in your report so progress is visible to the operator." >&2
    exit 0
  fi
  # 4) fresh named blocker → allow
  blocker_fresh ".claude/state" && exit 0

  local err="Register-progress gate: this WORKING session is ending with an 'awaiting you' list but shows no completion evidence (no commit/PR/merge/deploy/self-test/RWR-NN advance) and no specific named blocker. Re-listing awaiting-Misha items is not progress. Either advance a register item (cite the evidence in your final message), OR record a specific blocker at .claude/state/register-blocker-<ts>.txt naming the exact item and why it genuinely needs the user."

  if [ "$mode" != "block" ]; then echo "[register-progress-gate] WARN: $err" >&2; exit 0; fi

  local rg="${BASH_SOURCE[0]%/*}/lib/stop-hook-retry-guard.sh"
  if [ -f "$rg" ]; then
    # shellcheck source=/dev/null
    source "$rg"
    local sid; sid="$(retry_guard_session_id "$input")"
    retry_guard_block_or_exit "$HOOK_NAME" "$sid" "awaiting-list-no-progress" \
      "$err" \
      '{"decision": "block", "reason": "Register-progress gate: working session ending with an awaiting-Misha list but no completion evidence and no named blocker. Advance a register item (cite evidence) or record a specific blocker. See stderr."}' \
      2
    exit 0
  else
    printf '%s\n' '{"decision":"block","reason":"Register-progress gate: advance a register item or record a specific blocker. See stderr."}'
    echo "$err" >&2; exit 2
  fi
}

# ============================ SELF-TEST ============================
self_test() {
  local tmp pass=0 fail=0 rc out self
  self="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
  tmp="$(mktemp -d)"
  mk_transcript() { # $1=file  $2=hasTool(y/n)  $3=finalText
    local f="$1"
    : > "$f"
    [ "$2" = "y" ] && echo '{"type":"tool_use","name":"Edit","input":{}}' >> "$f"
    printf '{"role":"assistant","content":[{"type":"text","text":"%s"}]}\n' "$3" >> "$f"
  }
  payload() { printf '{"transcript_path":"%s","session_id":"selftest-%s-%s"}' "$1" "$$" "$RANDOM"; }

  # T1 BLOCK: working + awaiting-list + no evidence + no blocker
  local t1="$tmp/t1.jsonl"; mk_transcript "$t1" y "Here is everything that is awaiting you and blocked on your decisions. Nothing else to report."
  rc=0; out="$(cd "$tmp" && payload "$t1" | bash "$self" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 2 ]; then echo "T1 working+awaiting+no-evidence => BLOCK: PASS"; pass=$((pass+1)); else echo "T1 => BLOCK: FAIL (rc=$rc)"; fail=$((fail+1)); fi

  # T2 ALLOW: working + awaiting BUT has evidence (merged/pushed)
  local t2="$tmp/t2.jsonl"; mk_transcript "$t2" y "Merged PR #500 to master and pushed; a few items remain awaiting you."
  rc=0; out="$(cd "$tmp" && payload "$t2" | bash "$self" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then echo "T2 working+awaiting+evidence => ALLOW: PASS"; pass=$((pass+1)); else echo "T2 => ALLOW: FAIL (rc=$rc)"; fail=$((fail+1)); fi

  # T3 ALLOW: working, no awaiting signature
  local t3="$tmp/t3.jsonl"; mk_transcript "$t3" y "I built the feature and the tests cover the edge cases."
  rc=0; out="$(cd "$tmp" && payload "$t3" | bash "$self" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then echo "T3 working+no-awaiting => ALLOW: PASS"; pass=$((pass+1)); else echo "T3 => ALLOW: FAIL (rc=$rc)"; fail=$((fail+1)); fi

  # T4 ALLOW: conversational (no tool use) even with awaiting-list
  local t4="$tmp/t4.jsonl"; mk_transcript "$t4" n "Here is the list of items awaiting you and your decisions."
  rc=0; out="$(cd "$tmp" && payload "$t4" | bash "$self" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then echo "T4 conversational => ALLOW: PASS"; pass=$((pass+1)); else echo "T4 => ALLOW: FAIL (rc=$rc)"; fail=$((fail+1)); fi

  # T5 ALLOW: working + awaiting + no evidence BUT fresh blocker file
  local t5="$tmp/t5.jsonl"; mk_transcript "$t5" y "These items are awaiting you and blocked on your decisions."
  mkdir -p "$tmp/.claude/state"; echo "RWR-23 A2P resubmit genuinely needs Misha to paste into Twilio (no API auth available)." > "$tmp/.claude/state/register-blocker-now.txt"
  rc=0; out="$(cd "$tmp" && payload "$t5" | bash "$self" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then echo "T5 awaiting+named-blocker => ALLOW: PASS"; pass=$((pass+1)); else echo "T5 => ALLOW: FAIL (rc=$rc)"; fail=$((fail+1)); fi

  # T6 ALLOW: disable env
  rc=0; out="$(cd "$tmp" && REGISTER_GATE_DISABLE=1 payload "$t1" | REGISTER_GATE_DISABLE=1 bash "$self" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then echo "T6 disable-env => ALLOW: PASS"; pass=$((pass+1)); else echo "T6 => ALLOW: FAIL (rc=$rc)"; fail=$((fail+1)); fi

  # T7 WARN-mode never blocks (working+awaiting+no-evidence but mode=warn)
  rc=0; out="$(cd "$tmp" && rm -f .claude/state/register-blocker-*.txt; REGISTER_GATE_MODE=warn payload "$t1" | REGISTER_GATE_MODE=warn bash "$self" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then echo "T7 warn-mode => ALLOW: PASS"; pass=$((pass+1)); else echo "T7 => ALLOW: FAIL (rc=$rc)"; fail=$((fail+1)); fi

  # T8 EC-1: awaiting + no FINAL-message evidence, BUT a real git commit tool_use
  # in the transcript => session advanced => ALLOW (nudge). Guards the
  # false-positive that would block a session that did work but reported poorly.
  local t8="$tmp/t8.jsonl"
  : > "$t8"
  echo '{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"git commit -m fix"}}]}' >> "$t8"
  echo '{"role":"assistant","content":[{"type":"text","text":"These items remain awaiting you and blocked on your decisions."}]}' >> "$t8"
  rc=0; out="$(cd "$tmp" && payload "$t8" | bash "$self" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then echo "T8 awaiting+no-final-evidence+transcript-commit => ALLOW: PASS"; pass=$((pass+1)); else echo "T8 => ALLOW: FAIL (rc=$rc)"; fail=$((fail+1)); fi

  # T9 EC-2: precise last-ASSISTANT-message extraction. A tool_result earlier in
  # the transcript contains an awaiting phrase; the final ASSISTANT message has
  # neither awaiting nor evidence. The gate must read the assistant message
  # (=> no awaiting => ALLOW), NOT the tool_result (which would wrongly block).
  local t9="$tmp/t9.jsonl"
  : > "$t9"
  echo '{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{}}]}' >> "$t9"
  echo '{"role":"user","content":[{"type":"tool_result","content":[{"type":"text","text":"the list shows everything awaiting you and blocked on your decisions"}]}]}' >> "$t9"
  echo '{"role":"assistant","content":[{"type":"text","text":"I made some internal changes to the helper."}]}' >> "$t9"
  rc=0; out="$(cd "$tmp" && payload "$t9" | bash "$self" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then echo "T9 precise-extraction-ignores-tool_result => ALLOW: PASS"; pass=$((pass+1)); else echo "T9 => ALLOW: FAIL (rc=$rc)"; fail=$((fail+1)); fi

  # T10 EC-2 regression: ensure T1's hard-block STILL fires with jq precise
  # extraction (no commit anywhere, awaiting in the real assistant message).
  rc=0; out="$(cd "$tmp" && payload "$t1" | bash "$self" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 2 ]; then echo "T10 babysitting-still-blocks-with-jq => BLOCK: PASS"; pass=$((pass+1)); else echo "T10 => BLOCK: FAIL (rc=$rc)"; fail=$((fail+1)); fi

  rm -rf "$tmp"
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
run
