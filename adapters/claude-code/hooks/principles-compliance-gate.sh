#!/bin/bash
# principles-compliance-gate.sh — Stop hook (companion to rules/principles.md)
#
# WHAT THIS IS (and the honest limit on what it can be)
# =====================================================
# Misha asked for a "pre-send gate": a hook that intercepts every outbound
# message to the user and refuses to send it if it matches a known
# operating-rule violation pattern.
#
# That literal mechanism is NOT POSSIBLE in Claude Code. Assistant->user
# messages are not a tool call and fire no hook; there is no pre-send /
# PostMessage hook event. This is the same residual gap documented in
# rules/vaporware-prevention.md ("Claude Code has no PostMessage hook").
#
# The closest REAL mechanical surface is a Stop hook that reads the
# agent-uneditable transcript ($TRANSCRIPT_PATH) and scans the FINAL
# assistant message — the end-of-effort text the user actually reads — for
# operating-rule anti-patterns. It cannot block BEFORE send; it blocks (in
# block-mode) at session end, forcing a revision before the turn closes.
# In warn-mode (the default) it never blocks — it logs.
#
# This is the family of Gen-6 narrative-integrity Stop hooks
# (transcript-lie-detector.sh, deferral-counter.sh, goal-coverage-on-stop.sh).
#
# WHAT IT DETECTS (final assistant message only)
# ==============================================
#   Rule 4 — false-binary framings   ("wire-or-retire", "defer-or-fix")        [block-eligible]
#   Rule 5 — "done"/"shipped" claim without a merge SHA or "master" reference  [block-eligible]
#   Rule 7 — future-tense promise without a named mechanism token              [block-eligible]
#   Rule 3 — multi-option question posed to the user (possible — can't judge   [WARN-ONLY, never blocks]
#            whether one option is "clearly principled"; too heuristic to block)
#   CRED   — credential-asking patterns ("I need your VERCEL_TOKEN",            [WARN-ONLY, never blocks]
#            "please paste your GH token") without a documented-source carve-out.
#            Companion to rules/information-architecture.md + the CLAUDE.md
#            "## Credentials Reference" section. The credential-reference doc at
#            ~/.claude/local/credentials-reference.md is the established convention;
#            asking for credentials that are already documented there is the
#            orphaned-content failure mode harness-hygiene-2 closes. Warn-only
#            because the carve-out logic is heuristic (a sentence MENTIONING a
#            token name might be documenting the convention rather than asking).
#
# Per Decision Principle 6 ("mechanical where reliable; advisory where
# heuristic"): Rule 3 detection is intentionally warn-only even in block-mode,
# because "is one option clearly principled?" is not mechanically decidable.
#
# MODE
# ====
#   warn  (default) — log every detection to the warn-log, exit 0 (never block).
#   block          — block-eligible detections route through the retry-guard
#                    (blocks, with the standard 3-retry downgrade). Rule 3 still warn-only
#                    BUT in block-mode R3 detections also write an in-band notification
#                    alert marker to ~/.claude/state/external-monitor-alerts/
#                    so the SessionStart `external-monitor-alert-surfacer.sh` hook
#                    surfaces the warning at the next interactive session — per
#                    Misha 2026-05-28: ambiguous R3 hits stay warn (no block) but
#                    DO need an in-band notification surface (not just stderr the
#                    agent never reads). Per the in-band-friction principle.
# Resolution order: PRINCIPLES_GATE_MODE env  >  ~/.claude/local/principles-gate-mode file  >  "warn".
# Flipped to block 2026-05-28 after warn-log review showed R4/R5/R7 firings are
# high-signal real anti-patterns, R3 firings are legitimate decision-surfacing
# (kept warn-only with in-band notification).
#
# ESCAPE HATCH
# ============
#   PRINCIPLES_GATE_DISABLE=1   — no-op (for harness-dev sessions that edit
#                                 the patterns themselves, e.g. this very file).
#
# SELF-TEST
# =========
#   principles-compliance-gate.sh --self-test
#
# EXIT CODES
#   0 — allowed (always, in warn-mode; or no block-eligible detection in block-mode)
#   1 — blocked (block-mode only, block-eligible detection, retry-guard not yet downgraded)

set -u

# ----------------------------------------------------------------------------
# Detection core — sets the globals R3 R4 R5 R7 and appends to DETECTION_LINES.
# Operates on the single string passed as $1 (the last assistant message).
# Pure function of its input; no I/O. Reused by both the live path and --self-test.
# ----------------------------------------------------------------------------
detect_violations() {
  local msg="$1"
  R3=0; R4=0; R5=0; R7=0; CRED=0
  DETECTION_LINES=""

  local lc
  lc=$(printf '%s' "$msg" | tr '[:upper:]' '[:lower:]')

  # --- Rule 4: false-binary framings (high signal) ---
  local r4_pats=(
    'wire[ -]?or[ -]?retire'
    'retire[ -]?or[ -]?wire'
    'defer[ -]?or[ -]?fix'
    'fix[ -]?or[ -]?defer'
    '(defer|retire|abandon|bulk-defer)( it| them)?,? (or|/|vs\.?) (wire|fix|complete)'
    'accept( the)? friction,? (or|/) (fix|defer)'
  )
  # DETECTION_LINES fields are TAB-separated: RULE<tab>description<tab>label.
  # A short stable label is logged (NOT the raw regex, whose '|' alternations
  # would otherwise collide with any delimiter and mangle the audit log).
  local p
  for p in "${r4_pats[@]}"; do
    if printf '%s' "$lc" | grep -E -q -- "$p" 2>/dev/null; then
      R4=$((R4+1))
      DETECTION_LINES+=$'RULE4\tfalse-binary framing (Rule 4)\tfalse-binary-framing'$'\n'
    fi
  done

  # --- Rule 5: completion claim without merge SHA or "master" reference ---
  # Strong completion-claim phrases only (avoid matching the bare word "done").
  local r5_claim='(\bshipped\b|merged to master|\bis (now )?(done|complete|live|shipped)\b|\bfully (done|complete|shipped)\b|\b(work|task|feature|plan|it) is (done|complete|shipped)\b|\bmarked (it )?(done|complete)\b)'
  if printf '%s' "$lc" | grep -E -q -- "$r5_claim" 2>/dev/null; then
    # Exempt if the message cites durable state: a 7-40 char hex SHA, OR the
    # word "master", OR an explicit merge/PR-merged token.
    local has_sha=0 has_master=0 has_merge=0
    printf '%s' "$lc" | grep -E -q -- '\b[0-9a-f]{7,40}\b' 2>/dev/null && has_sha=1
    printf '%s' "$lc" | grep -F -q -- 'master' 2>/dev/null && has_master=1
    printf '%s' "$lc" | grep -E -q -- '(merged|pr merged|pull request merged|landed on master)' 2>/dev/null && has_merge=1
    if [[ "$has_sha" -eq 0 && "$has_master" -eq 0 && "$has_merge" -eq 0 ]]; then
      R5=$((R5+1))
      DETECTION_LINES+=$'RULE5\tcompletion claim without merge SHA / master reference (Rule 5)\tdone-without-sha'$'\n'
    fi
  fi

  # --- Rule 7: future-tense promise without a named mechanism ---
  local r7_promise='(i.?ll relay|i.?ll keep (you )?(posted|updated|tracking)|i.?ll follow up|i.?ll follow-up|i.?ll alert|i.?ll notify|i.?ll monitor|i.?ll continue to (post|monitor|track|update)|i.?ll keep (an eye|monitoring)|going forward,? i.?ll|i will keep (you )?(posted|updated|tracking))'
  if printf '%s' "$lc" | grep -E -q -- "$r7_promise" 2>/dev/null; then
    # Exempt if a real triggering mechanism is named in the same message.
    local mech='(cron|schedul|scheduledtask|schedulewakeup|wake[- ]?up|fireat|\bhook\b|tracker|on disk|notification|ntfy|polling|/loop|croncreate|remotetrigger|pushnotification)'
    if ! printf '%s' "$lc" | grep -E -q -- "$mech" 2>/dev/null; then
      R7=$((R7+1))
      DETECTION_LINES+=$'RULE7\tfuture-tense promise without a named triggering mechanism (Rule 7)\tpromise-without-mechanism'$'\n'
    fi
  fi

  # --- CRED: credential-asking patterns (WARN-ONLY, heuristic) ---
  # Targets the orphaned-content failure mode: agent asks operator for a
  # credential that is already configured per ~/.claude/local/credentials-reference.md.
  # Patterns are conservative (high-confidence credential-asking shapes only).
  # Carve-out: if the message ALSO references the credentials-reference doc OR
  # names a specific canonical source location (`.env.local`, `gh auth`, `vercel
  # env pull`, etc.), treat as documentation rather than asking.
  local cred_pats=(
    'i need (your |the |a )?(vercel_token|github_token|gh_token|gh pat|github pat|anthropic_api_key|openai_api_key|supabase_(access_)?token|stripe_(secret_)?key|twilio_(auth_)?token|resend_api_key)'
    '(please |could you |can you )?(give|provide|share|paste|send) (me )?(a |your |the )?(github |gh |vercel |aws |stripe |openai |anthropic |supabase |twilio |resend )?(token|api key|credential|secret|pat|access token|password)\b'
    'i.?ll need (a |your |the )?(github |gh |vercel |aws |stripe |openai |anthropic |supabase |twilio |resend )?(token|api key|credential|secret|pat|access token|password)\b'
    'you.?ll need to (give|provide|share|paste|send) (me )?(a |your |the )?(github |gh |vercel |aws |stripe |openai |anthropic |supabase |twilio |resend )?(token|api key|credential|secret|pat|access token|password)\b'
    "what.?s (your |the )?(vercel|gh|github|aws|stripe|openai|anthropic|supabase|twilio|resend)('s)? (token|key|api key|pat|credential)"
    '(paste|enter|type) (your |the )?(vercel_token|github_token|gh_token|anthropic_api_key|openai_api_key|supabase_access_token|stripe_secret_key|twilio_auth_token|resend_api_key)( here|.)'
  )
  local cred_pat
  for cred_pat in "${cred_pats[@]}"; do
    if printf '%s' "$lc" | grep -E -q -- "$cred_pat" 2>/dev/null; then
      # Carve-out: documentation rather than asking. If the message references
      # the credentials-reference doc OR names a canonical source location, the
      # message is most likely documenting where the credential lives — skip.
      local has_carveout=0
      local carveout='(credentials?[- ]reference|\.env\.local|\.env\.example|gh auth (status|switch|login)|vercel env pull|~/\.supabase/tokens|~/\.claude\.json|claude login|local/credentials-reference\.md|already (configured|authenticated|cached)|canonical (location|source))'
      printf '%s' "$lc" | grep -E -q -- "$carveout" 2>/dev/null && has_carveout=1
      if [[ "$has_carveout" -eq 0 ]]; then
        CRED=$((CRED+1))
        DETECTION_LINES+=$'CRED\tcredential-asking pattern without credentials-reference carve-out\tcredential-asking-no-carveout'$'\n'
        break
      fi
    fi
  done

  # --- Rule 3: multi-option question posed to the user (WARN-ONLY, heuristic) ---
  # Cannot judge whether one option is "clearly principled"; flagged for review only.
  if printf '%s' "$msg" | grep -F -q '?' 2>/dev/null; then
    local r3_pats=(
      'option [a-d]\b'
      'option [1-4]\b'
      '\(1\)[^?]{0,160}\(2\)'
      '\b1\)[^?]{0,160}\b2\)'
      'should i [^?]{1,80} or [^?]{1,80}\?'
      'would you (like|prefer) [^?]{1,80} or [^?]{1,80}\?'
      'do you want (me to )?[^?]{1,80} or [^?]{1,80}\?'
    )
    for p in "${r3_pats[@]}"; do
      if printf '%s' "$lc" | grep -E -q -- "$p" 2>/dev/null; then
        R3=$((R3+1))
        DETECTION_LINES+=$'RULE3\tpossible multi-option question (Rule 3; heuristic, warn-only)\tmulti-option-question'$'\n'
        break
      fi
    done
  fi
}

# ----------------------------------------------------------------------------
# --self-test — inline fixtures, no external files.
# ----------------------------------------------------------------------------
if [[ "${1:-}" = "--self-test" ]]; then
  PASS=0; FAIL=0
  check() {
    local name="$1" expect_rule="$2" expect_count="$3"; shift 3
    local msg="$1"
    detect_violations "$msg"
    local actual
    case "$expect_rule" in
      R3) actual=$R3;; R4) actual=$R4;; R5) actual=$R5;; R7) actual=$R7;;
      CRED) actual=$CRED;;
      TOTAL) actual=$((R3+R4+R5+R7+CRED));;
    esac
    if [[ "$actual" -eq "$expect_count" ]]; then
      echo "PASS  $name ($expect_rule=$actual)"; PASS=$((PASS+1))
    else
      echo "FAIL  $name (expected $expect_rule=$expect_count, got $actual)"; FAIL=$((FAIL+1))
    fi
  }

  check "clean message has zero detections"        TOTAL 0 \
    "All four tasks shipped. Merged to master at a1b2c3d. principles.md is live."
  check "rule4 wire-or-retire detected"            R4 1 \
    "We can wire-or-retire this dangling component — which do you prefer?"
  check "rule4 defer-or-fix detected"              R4 1 \
    "The options are defer-or-fix; I lean fix."
  check "rule5 done without SHA detected"          R5 1 \
    "The feature is done and the work is complete."
  check "rule5 done WITH sha exempt"               R5 0 \
    "The feature is done — merged to master at deadbeef1."
  check "rule5 done WITH master word exempt"       R5 0 \
    "Shipped. It is now live on master."
  check "rule7 promise without mechanism detected" R7 1 \
    "I'll keep you posted as the long-running task makes progress."
  check "rule7 promise WITH mechanism exempt"      R7 0 \
    "I'll keep you posted — I scheduled a ScheduleWakeup to re-check in 20 min."
  check "rule3 multi-option question detected"     R3 1 \
    "Should I merge PR #7 now or wait for review? Let me know."
  check "rule3 plain statement not flagged"        R3 0 \
    "I merged PR #7 after confirming the checks were green."

  # CRED: credential-asking patterns
  check "cred ask vercel token detected"           CRED 1 \
    "I need your VERCEL_TOKEN to pull the env vars."
  check "cred ask paste github token detected"     CRED 1 \
    "Please paste your GitHub PAT so I can authenticate."
  check "cred carveout reference doc exempt"       CRED 0 \
    "I need your VERCEL_TOKEN — but per credentials-reference, it should already be cached via vercel login."
  check "cred carveout env.local exempt"           CRED 0 \
    "Please paste your token... actually, the convention is .env.local — let me check there first."
  check "cred plain operational text not flagged"  CRED 0 \
    "I switched gh auth to the canonical user for the mirror push."
  check "cred ai-feature mention not flagged"      CRED 0 \
    "The Anthropic API key is set in .env.local per the project convention."

  echo ""
  echo "Result: $PASS passed, $FAIL failed"
  [[ "$FAIL" -gt 0 ]] && exit 1
  exit 0
fi

# ----------------------------------------------------------------------------
# Live path
# ----------------------------------------------------------------------------

# Shared retry-guard library (for block-mode downgrade-after-3).
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/lib/stop-hook-retry-guard.sh" 2>/dev/null || true

INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi
RG_SESSION_ID=""
if command -v retry_guard_session_id >/dev/null 2>&1; then
  RG_SESSION_ID=$(retry_guard_session_id "$INPUT")
fi

# Escape hatch
if [[ "${PRINCIPLES_GATE_DISABLE:-0}" = "1" ]]; then
  exit 0
fi

# Resolve transcript
TRANSCRIPT_PATH=""
if [[ -n "$INPUT" ]]; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
fi
if [[ -n "${PRINCIPLES_GATE_TRANSCRIPT:-}" ]]; then
  TRANSCRIPT_PATH="$PRINCIPLES_GATE_TRANSCRIPT"
fi
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Resolve mode
MODE="${PRINCIPLES_GATE_MODE:-}"
if [[ -z "$MODE" ]] && [[ -f "$HOME/.claude/local/principles-gate-mode" ]]; then
  MODE=$(tr -d '[:space:]' < "$HOME/.claude/local/principles-gate-mode" 2>/dev/null || echo "")
fi
[[ -z "$MODE" ]] && MODE="warn"
[[ "$MODE" != "block" ]] && MODE="warn"

# Extract the LAST assistant message (full text, robust to internal newlines via base64).
LAST_B64=$(jq -r '
  select(.role == "assistant" or .message.role == "assistant")
  | (.content // .text // .message.content // empty)
  | (if type == "string" then .
     elif type == "array" then ([.[] | (.text // .content // "")] | join("\n"))
     else (. | tostring) end)
  | @base64
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1)
if [[ -z "$LAST_B64" ]]; then
  exit 0
fi
LAST_ASSISTANT=$(printf '%s' "$LAST_B64" | base64 -d 2>/dev/null || echo "")
if [[ -z "$LAST_ASSISTANT" ]]; then
  exit 0
fi

detect_violations "$LAST_ASSISTANT"

TOTAL=$((R3 + R4 + R5 + R7 + CRED))
BLOCK_ELIGIBLE=$((R4 + R5 + R7))   # Rule 3 + CRED are intentionally NOT block-eligible.

# Always emit a machine-readable summary line to stderr.
echo "[principles-gate] mode=$MODE R3=$R3 R4=$R4 R5=$R5 R7=$R7 CRED=$CRED total=$TOTAL" >&2

# In-band CRED notification: when a credential-asking pattern is detected (any
# mode), surface a one-line stderr reminder pointing at the credentials-reference
# doc. This is in-band friction: the agent sees the reminder at Stop time and
# can revise before re-attempting. CRED is warn-only — never blocks — so the
# reminder is the entire mechanism.
if [[ "$CRED" -gt 0 ]]; then
  echo "[principles-gate] CRED: detected credential-asking pattern. Consult ~/.claude/local/credentials-reference.md BEFORE asking the operator for tokens/keys/credentials. The reference names the established convention for this machine (vercel login cache, gh auth status, ~/.supabase/tokens, .env.local per project). Per CLAUDE.md '## Credentials Reference' and rules/information-architecture.md." >&2
fi

# Log every detection to the warn-log (append).
LOG_FILE="${PRINCIPLES_GATE_LOG:-$HOME/.claude/state/principles-gate-warnings.log}"
if [[ "$TOTAL" -gt 0 ]]; then
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  SID="${RG_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"
  SNIPPET=$(printf '%s' "$LAST_ASSISTANT" | tr '\n' ' ' | head -c 240)
  while IFS=$'\t' read -r rule desc label; do
    [[ -z "$rule" ]] && continue
    printf '%s | mode=%s | session=%s | %s | %s | match=%s | snippet=%s\n' \
      "$TS" "$MODE" "$SID" "$rule" "$desc" "$label" "$SNIPPET" >> "$LOG_FILE" 2>/dev/null || true
  done <<< "$DETECTION_LINES"
  echo "[principles-gate] logged $TOTAL detection(s) to $LOG_FILE" >&2
fi

# Warn-mode: never block.
if [[ "$MODE" = "warn" ]]; then
  exit 0
fi

# Block-mode in-band notification for Rule 3 (warn-only, but surface via
# external-monitor-alert at next session start per the wired
# external-monitor-alert-surfacer.sh hook). Misha 2026-05-28: R3 stays warn-only
# because "is one option clearly principled" is heuristic, but the warning needs
# in-band surface (not just stderr the agent never reads).
if [[ "$R3" -gt 0 ]] && [[ "$MODE" = "block" ]]; then
  ALERT_DIR="${PRINCIPLES_GATE_ALERT_DIR:-$HOME/.claude/state/external-monitor-alerts}"
  mkdir -p "$ALERT_DIR" 2>/dev/null || true
  TS_ALERT=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo "unknown")
  TS_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  SID_ALERT="${RG_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"
  SNIPPET_ALERT=$(printf '%s' "$LAST_ASSISTANT" | tr '\n' ' ' | head -c 240 | sed 's/"/\\"/g')
  ALERT_FILE="$ALERT_DIR/principles-gate-r3-${TS_ALERT}-${SID_ALERT}.json"
  cat > "$ALERT_FILE" 2>/dev/null <<JSON
{
  "started_at": "$TS_ISO",
  "source": "principles-compliance-gate.sh",
  "rule": "R3",
  "session_id": "$SID_ALERT",
  "detection_count": $R3,
  "summary": "Rule 3 (possible multi-option question) flagged $R3 time(s) in the final assistant message. Heuristic — review whether one option was clearly principled and could have been taken without surfacing to Misha. See ~/.claude/state/principles-gate-warnings.log for the matched line.",
  "snippet": "$SNIPPET_ALERT"
}
JSON
  echo "[principles-gate] R3 in-band notification: wrote $ALERT_FILE" >&2
fi

# Block-mode: block only on block-eligible detections (Rule 4/5/7). Rule 3 stays warn.
if [[ "$BLOCK_ELIGIBLE" -eq 0 ]]; then
  exit 0
fi

BLOCKER_MSG="principles-compliance-gate: your final message matched $BLOCK_ELIGIBLE operating-rule anti-pattern(s) (Rule 4 false-binary=$R4, Rule 5 done-without-SHA=$R5, Rule 7 promise-without-mechanism=$R7). Revise per ~/.claude/rules/constitution.md, then re-attempt Stop. See $LOG_FILE for the matched lines. Suppress with PRINCIPLES_GATE_DISABLE=1 for harness-dev sessions editing the patterns themselves."

if command -v retry_guard_block_or_exit >/dev/null 2>&1; then
  RG_FAILURE_SIG="principles-gate:R4=$R4:R5=$R5:R7=$R7"
  retry_guard_block_or_exit \
    "principles-compliance-gate" \
    "$RG_SESSION_ID" \
    "$RG_FAILURE_SIG" \
    "$BLOCKER_MSG" \
    "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}" \
    1
else
  echo "$BLOCKER_MSG" >&2
  exit 1
fi
