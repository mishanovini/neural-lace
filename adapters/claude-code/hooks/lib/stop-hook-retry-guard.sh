# stop-hook-retry-guard.sh — shared library for Stop hooks to detect and
# break out of infinite "block / re-prompt / block" loops.
#
# ============================================================
# THE PROBLEM
# ============================================================
#
# Stop hooks block session termination by exiting non-zero. When a Stop
# hook fails for a reason the session cannot resolve in-loop (e.g.,
# acceptance artifacts for plans the session never touched, an
# environmental failure in the runtime advocate, a transcript-derived
# claim the session cannot retract), Claude Code re-prompts the agent
# with the hook output, the agent stands by, the next Stop attempt
# fires the hook again with the same input, the same block fires, and
# the session loops forever between "Hook re-prompted" and "Standing by."
#
# The agent has no way to make progress — the failure is not addressable
# from within the session — but the harness keeps blocking on it.
# Enforcement turns into a denial-of-service against the agent.
#
# ============================================================
# THE FIX (this library)
# ============================================================
#
# Each blocking Stop hook calls `retry_guard_block_or_exit` at the point
# it would normally exit non-zero. The function:
#
#   1. Computes a failure SIGNATURE (caller-supplied; typically the
#      block reason or a deterministic hash of it).
#   2. Reads a per-session counter file at
#      .claude/state/stop-hook-retries-<hook>-<session-short>.txt.
#   3. Checks whether (a) the failure signature is the same as last time
#      AND (b) the current git HEAD is the same as last time. If both
#      match, increments the counter; otherwise resets to 1.
#   4. If the counter reaches a threshold (default 3, configurable via
#      RETRY_GUARD_THRESHOLD), DOWNGRADES the block: writes an entry to
#      .claude/state/unresolved-stop-hooks.log naming the hook, the
#      session, the failure signature, and the error message; emits a
#      warning to stderr; and exits 0 so the session may terminate.
#   5. Otherwise BLOCKS as the hook intended: emits the hook's
#      block-stdout JSON (caller-supplied), prints the hook's
#      block-stderr message, and exits with the hook's chosen exit code
#      (default 2, or 1 for hooks using the `{"result":"error"}` JSON).
#
# A new commit between retries (HEAD changed) resets the counter — the
# session IS making progress, even if not on this specific gate.
# A different failure signature also resets the counter — it's a
# different problem.
#
# ============================================================
# PER-SESSION ISOLATION
# ============================================================
#
# The counter is keyed on CLAUDE_SESSION_ID (or a fallback derived from
# transcript_path / PPID) so a fresh session starts at zero. Files
# older than 24 hours are swept on each invocation to prevent disk
# clutter from old sessions.
#
# ============================================================
# AUDIT TRAIL
# ============================================================
#
# Every downgrade appends one record to
# .claude/state/unresolved-stop-hooks.log:
#
#   2026-05-09T14:22:31Z  hook=product-acceptance-gate  session=abc123ef
#     count=3  sig=9f2a0c1b...
#     error: <one-line excerpt of the original block message>
#
# The next session reads the log on start (via a SessionStart hook,
# wired separately) and surfaces the unresolved gap so the agent can
# address it with full context — not the panic of an in-flight loop.
#
# ============================================================
# USAGE
# ============================================================
#
# At the top of a Stop hook, after stdin parsing:
#
#   source "${BASH_SOURCE%/*}/lib/stop-hook-retry-guard.sh"
#   RG_SESSION_ID=$(retry_guard_session_id "$INPUT")  # $INPUT is JSON if any
#
# At a block point, instead of `exit 2`:
#
#   retry_guard_block_or_exit \
#     "product-acceptance-gate" \
#     "$RG_SESSION_ID" \
#     "$BLOCKERS" \
#     "$BLOCK_REASON_ONELINE" \
#     "$BLOCK_STDOUT_JSON" \
#     2
#
# Function never returns: it either exits 0 (downgrade) or exits with
# the chosen code (still blocking). The caller is finished after the
# call.
#
# At a successful no-op exit, optionally call:
#
#   retry_guard_clear "product-acceptance-gate" "$RG_SESSION_ID"
#
# This removes the counter file so the next failure starts fresh.
# (Not strictly required: the counter only fires on identical failures,
# so a passing run followed by a different failure auto-resets via the
# signature comparison.)

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_STOP_HOOK_RETRY_GUARD_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_STOP_HOOK_RETRY_GUARD_SOURCED=1

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------
: "${RETRY_GUARD_THRESHOLD:=3}"
: "${RETRY_GUARD_STATE_DIR:=.claude/state}"
: "${RETRY_GUARD_SWEEP_AGE_HOURS:=24}"

# ----------------------------------------------------------------------
# retry_guard_session_id [ <input-json> ]
#
# Derive a stable per-session identifier. Resolution order:
#   1. CLAUDE_SESSION_ID env var (Claude Code sets this for hooks)
#   2. .session_id field of the input JSON (if provided and parsable)
#   3. SHA-1 of transcript_path field of input JSON
#   4. PPID of the calling process
#
# Echoes the resolved id (full string). Callers typically truncate via
# the internal _retry_guard_session_short helper.
# ----------------------------------------------------------------------
retry_guard_session_id() {
  local input="${1:-}"
  local sid=""

  if [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
    echo "$CLAUDE_SESSION_ID"
    return 0
  fi

  if [[ -n "$input" ]] && command -v jq >/dev/null 2>&1; then
    sid=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null || echo "")
    if [[ -n "$sid" ]] && [[ "$sid" != "null" ]]; then
      echo "$sid"
      return 0
    fi
    local tpath
    tpath=$(echo "$input" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
    if [[ -n "$tpath" ]] && [[ "$tpath" != "null" ]]; then
      _retry_guard_hash "$tpath"
      return 0
    fi
  fi

  echo "ppid_${PPID:-$$}"
}

# ----------------------------------------------------------------------
# Internal: short session token (for filename use)
# ----------------------------------------------------------------------
_retry_guard_session_short() {
  local sid="$1"
  printf '%s' "$sid" | tr -c 'a-zA-Z0-9' '_' | cut -c1-24
}

# ----------------------------------------------------------------------
# Internal: SHA-1 of stdin or arg, first 12 chars
# ----------------------------------------------------------------------
_retry_guard_hash() {
  local input="$1"
  local h=""
  if command -v sha1sum >/dev/null 2>&1; then
    h=$(printf '%s' "$input" | sha1sum 2>/dev/null | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    h=$(printf '%s' "$input" | shasum 2>/dev/null | awk '{print $1}')
  elif command -v openssl >/dev/null 2>&1; then
    h=$(printf '%s' "$input" | openssl sha1 2>/dev/null | awk '{print $NF}')
  fi
  if [[ -z "$h" ]]; then
    # Fallback: best-effort character-class digest
    h=$(printf '%s' "$input" | tr -c 'a-zA-Z0-9' '_' | head -c 24)
  fi
  printf '%s' "${h:0:12}"
}

# ----------------------------------------------------------------------
# Internal: current git HEAD (or NONE)
# ----------------------------------------------------------------------
_retry_guard_current_sha() {
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local sha
    sha=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [[ -n "$sha" ]]; then
      printf '%s' "$sha"
      return 0
    fi
  fi
  printf 'NONE'
}

# ----------------------------------------------------------------------
# Internal: counter file path for (hook, session)
# ----------------------------------------------------------------------
_retry_guard_counter_path() {
  local hook_name="$1"
  local sid="$2"
  local short
  short=$(_retry_guard_session_short "$sid")
  printf '%s/stop-hook-retries-%s-%s.txt' \
    "$RETRY_GUARD_STATE_DIR" "$hook_name" "$short"
}

# ----------------------------------------------------------------------
# Internal: sweep counter files older than RETRY_GUARD_SWEEP_AGE_HOURS.
# Best-effort; silent on failure.
# ----------------------------------------------------------------------
_retry_guard_sweep_old() {
  [[ -d "$RETRY_GUARD_STATE_DIR" ]] || return 0
  find "$RETRY_GUARD_STATE_DIR" -maxdepth 1 \
    -name 'stop-hook-retries-*.txt' \
    -type f \
    -mmin "+$((RETRY_GUARD_SWEEP_AGE_HOURS * 60))" \
    -delete 2>/dev/null || true
}

# ----------------------------------------------------------------------
# retry_guard_clear <hook-name> <session-id>
#
# Remove the counter file for this (hook, session). Call after a
# successful no-block run (optional — see usage notes above).
# ----------------------------------------------------------------------
retry_guard_clear() {
  local hook_name="$1"
  local sid="$2"
  local cf
  cf=$(_retry_guard_counter_path "$hook_name" "$sid")
  rm -f "$cf" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# retry_guard_record <hook-name> <session-id> <failure-sig>
#
# Increment-or-reset the counter. Echoes the new count to stdout.
# Side effect: writes the counter file.
#
# Reset-to-1 conditions:
#   - failure signature differs from previous
#   - current git HEAD differs from previous (and HEAD is known)
#
# Otherwise increments by 1.
# ----------------------------------------------------------------------
retry_guard_record() {
  local hook_name="$1"
  local sid="$2"
  local failure_sig="$3"

  mkdir -p "$RETRY_GUARD_STATE_DIR" 2>/dev/null || true
  _retry_guard_sweep_old

  local sig_hash
  sig_hash=$(_retry_guard_hash "$failure_sig")
  local current_sha
  current_sha=$(_retry_guard_current_sha)
  local cf
  cf=$(_retry_guard_counter_path "$hook_name" "$sid")

  local prev_sig="" prev_sha="" prev_count=0
  if [[ -f "$cf" ]]; then
    IFS='|' read -r prev_sig prev_sha prev_count < "$cf" 2>/dev/null || true
    [[ -z "$prev_count" ]] && prev_count=0
    # Strip non-digits defensively
    prev_count="${prev_count//[!0-9]/}"
    [[ -z "$prev_count" ]] && prev_count=0
  fi

  local new_count
  if [[ "$prev_sig" != "$sig_hash" ]]; then
    new_count=1
  elif [[ "$current_sha" != "NONE" ]] && [[ -n "$prev_sha" ]] && [[ "$prev_sha" != "$current_sha" ]]; then
    new_count=1
  else
    new_count=$((prev_count + 1))
  fi

  printf '%s|%s|%d\n' "$sig_hash" "$current_sha" "$new_count" > "$cf"
  printf '%d' "$new_count"
}

# ----------------------------------------------------------------------
# retry_guard_log_unresolved <hook-name> <session-id> <count> <failure-sig> <error-msg>
#
# Append an audit-trail entry to .claude/state/unresolved-stop-hooks.log
# describing a downgrade event.
# ----------------------------------------------------------------------
retry_guard_log_unresolved() {
  local hook_name="$1"
  local sid="$2"
  local count="$3"
  local failure_sig="$4"
  local error_msg="$5"

  mkdir -p "$RETRY_GUARD_STATE_DIR" 2>/dev/null || true
  local log_file="${RETRY_GUARD_STATE_DIR}/unresolved-stop-hooks.log"
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)
  local short
  short=$(_retry_guard_session_short "$sid")
  local sig_hash
  sig_hash=$(_retry_guard_hash "$failure_sig")

  # Squash the error message to single-line (control chars / newlines
  # turn into spaces, then collapse whitespace, then trim to ~600 chars).
  local err_oneline
  err_oneline=$(printf '%s' "$error_msg" | tr '\r\n\t' '   ' | tr -s ' ' | cut -c1-600)

  {
    printf '%s\thook=%s\tsession=%s\tcount=%d\tsig=%s\n' \
      "$timestamp" "$hook_name" "$short" "$count" "$sig_hash"
    printf '  error: %s\n' "$err_oneline"
    printf '\n'
  } >> "$log_file" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# retry_guard_block_or_exit <hook-name> <session-id> <failure-sig> \
#                           <error-msg-oneline> <block-stdout-json> \
#                           [<block-exit-code>]
#
# The main entry point. Records the failure, decides whether to
# downgrade, and exits accordingly. NEVER RETURNS.
#
# Behavior:
#   - count < threshold: prints block_stdout_json on stdout if non-empty,
#     emits a brief stderr note showing the count, exits with
#     block_exit_code (default 2).
#   - count >= threshold: logs to unresolved-stop-hooks.log, prints a
#     downgrade-warning stanza to stderr (so the user sees what was
#     skipped and why), and exits 0.
#
# The threshold is RETRY_GUARD_THRESHOLD (default 3, env-overridable).
# ----------------------------------------------------------------------
retry_guard_block_or_exit() {
  local hook_name="$1"
  local sid="$2"
  local failure_sig="$3"
  local error_msg="$4"
  local block_stdout="${5:-}"
  local block_exit="${6:-2}"

  local count
  count=$(retry_guard_record "$hook_name" "$sid" "$failure_sig")

  if (( count >= RETRY_GUARD_THRESHOLD )); then
    retry_guard_log_unresolved "$hook_name" "$sid" "$count" "$failure_sig" "$error_msg"
    local short
    short=$(_retry_guard_session_short "$sid")
    cat >&2 <<EOF

================================================================
[retry-guard] ${hook_name} BLOCK DOWNGRADED TO WARN
================================================================
This hook would normally block session termination, but the same
failure has now occurred ${count} times in this session with no
new commits between retries. To prevent an infinite Stop-hook
loop, the block is downgraded to a warning and the session is
allowed to exit.

Original block reason (one-line excerpt):
  ${error_msg}

Logged to: ${RETRY_GUARD_STATE_DIR}/unresolved-stop-hooks.log
The next session can review unresolved gaps and address them
with full context, instead of looping in-flight.

Reset paths (any of these clears the counter for this gate):
  - Make a new commit (auto-resets on next run)
  - Address the underlying failure so the gate PASSes
  - Remove the counter file:
      ${RETRY_GUARD_STATE_DIR}/stop-hook-retries-${hook_name}-${short}.txt
================================================================
EOF
    exit 0
  fi

  if [[ -n "$block_stdout" ]]; then
    printf '%s\n' "$block_stdout"
  fi
  local remaining=$((RETRY_GUARD_THRESHOLD - count))
  printf '[retry-guard] %s: identical-failure count %d of %d. After %d more, the block downgrades to warn (logged to %s/unresolved-stop-hooks.log) so the session can exit.\n' \
    "$hook_name" "$count" "$RETRY_GUARD_THRESHOLD" "$remaining" "$RETRY_GUARD_STATE_DIR" >&2
  exit "$block_exit"
}

# ============================================================
# --self-test
# ============================================================
#
# Bash 3.2-compatible self-test exercising the library's behaviors.
# Runs in a temporary directory so it doesn't affect repo state.
#
# Invocation:
#   bash adapters/claude-code/hooks/lib/stop-hook-retry-guard.sh --self-test
#
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'rgst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  cd "$TMP" || { echo "could not cd to TMP" >&2; exit 1; }
  git init -q 2>/dev/null
  git config user.email "selftest@example.test" 2>/dev/null
  git config user.name  "Self Test"            2>/dev/null
  : > seed.txt
  git add seed.txt && git commit -q -m "seed" 2>/dev/null

  # Reset env to controlled values
  export RETRY_GUARD_STATE_DIR=".claude/state"
  export RETRY_GUARD_THRESHOLD=3
  unset CLAUDE_SESSION_ID

  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  echo "Scenario 1: same failure increments count 1->2->3, downgrades at 3"
  export CLAUDE_SESSION_ID="sess-A"
  rm -rf .claude/state
  c1=$(retry_guard_record "test-hook" "sess-A" "same-failure")
  c2=$(retry_guard_record "test-hook" "sess-A" "same-failure")
  c3=$(retry_guard_record "test-hook" "sess-A" "same-failure")
  if [[ "$c1" == "1" ]] && [[ "$c2" == "2" ]] && [[ "$c3" == "3" ]]; then
    pass "increment 1->2->3 on same failure (got $c1, $c2, $c3)"
  else
    fail "expected 1,2,3 got $c1,$c2,$c3"
  fi

  echo "Scenario 2: different failure resets to 1"
  c4=$(retry_guard_record "test-hook" "sess-A" "DIFFERENT-failure")
  if [[ "$c4" == "1" ]]; then
    pass "different signature resets count (got $c4)"
  else
    fail "expected 1 got $c4"
  fi

  echo "Scenario 3: new commit resets counter"
  rm -rf .claude/state
  _=$(retry_guard_record "test-hook" "sess-A" "same-failure")
  _=$(retry_guard_record "test-hook" "sess-A" "same-failure")
  echo "x" > new.txt && git add new.txt && git commit -q -m "new" 2>/dev/null
  c5=$(retry_guard_record "test-hook" "sess-A" "same-failure")
  if [[ "$c5" == "1" ]]; then
    pass "new commit resets count to 1 (got $c5)"
  else
    fail "expected 1 got $c5"
  fi

  echo "Scenario 4: different session has its own counter"
  rm -rf .claude/state
  _=$(retry_guard_record "test-hook" "sess-A" "shared-failure")
  _=$(retry_guard_record "test-hook" "sess-A" "shared-failure")
  cB=$(retry_guard_record "test-hook" "sess-B" "shared-failure")
  if [[ "$cB" == "1" ]]; then
    pass "different session_id starts at 1 (got $cB)"
  else
    fail "expected 1 got $cB"
  fi

  echo "Scenario 5: retry_guard_clear removes counter"
  rm -rf .claude/state
  _=$(retry_guard_record "test-hook" "sess-A" "x")
  _=$(retry_guard_record "test-hook" "sess-A" "x")
  retry_guard_clear "test-hook" "sess-A"
  cleared=$(retry_guard_record "test-hook" "sess-A" "x")
  if [[ "$cleared" == "1" ]]; then
    pass "retry_guard_clear removes counter (post-clear count=$cleared)"
  else
    fail "expected post-clear count=1 got $cleared"
  fi

  echo "Scenario 6: block_or_exit downgrades at threshold (exits 0)"
  rm -rf .claude/state
  # Two records to seed the counter
  _=$(retry_guard_record "test-hook" "sess-X" "stuck")
  _=$(retry_guard_record "test-hook" "sess-X" "stuck")
  # Now the third call should hit threshold and exit 0
  set +e
  ( retry_guard_block_or_exit "test-hook" "sess-X" "stuck" \
      "the same gate is failing" \
      '{"decision":"block"}' 2 ) >/tmp/rg-out 2>/tmp/rg-err
  rc=$?
  set -e
  if [[ "$rc" == "0" ]]; then
    pass "downgrade exits 0 (got $rc)"
  else
    fail "expected exit 0, got $rc"
  fi
  if grep -q "BLOCK DOWNGRADED TO WARN" /tmp/rg-err; then
    pass "downgrade prints warning stanza to stderr"
  else
    fail "downgrade stderr missing warning stanza"
  fi
  if [[ -f .claude/state/unresolved-stop-hooks.log ]] && \
     grep -q "hook=test-hook" .claude/state/unresolved-stop-hooks.log; then
    pass "downgrade writes unresolved-stop-hooks.log entry"
  else
    fail "downgrade did not write log"
  fi

  echo "Scenario 7: block_or_exit blocks before threshold (exits 2)"
  rm -rf .claude/state
  set +e
  ( retry_guard_block_or_exit "test-hook" "sess-Y" "fresh" \
      "fresh failure" \
      '{"decision":"block"}' 2 ) >/tmp/rg-out 2>/tmp/rg-err
  rc=$?
  set -e
  if [[ "$rc" == "2" ]]; then
    pass "first failure exits with block code 2 (got $rc)"
  else
    fail "expected exit 2, got $rc"
  fi
  if grep -q '"decision":"block"' /tmp/rg-out; then
    pass "first failure prints block JSON on stdout"
  else
    fail "first failure missing block JSON on stdout"
  fi

  echo "Scenario 8: block_or_exit honors custom exit code (1 for legacy result-error)"
  rm -rf .claude/state
  set +e
  ( retry_guard_block_or_exit "test-hook" "sess-Z" "x" \
      "legacy block" \
      '{"result":"error"}' 1 ) >/tmp/rg-out 2>/tmp/rg-err
  rc=$?
  set -e
  if [[ "$rc" == "1" ]]; then
    pass "exit code 1 honored for legacy block style (got $rc)"
  else
    fail "expected exit 1, got $rc"
  fi

  echo "Scenario 9: session_id resolution from JSON input"
  unset CLAUDE_SESSION_ID
  resolved=$(retry_guard_session_id '{"session_id":"abc-123","transcript_path":"/tmp/x.jsonl"}')
  if [[ "$resolved" == "abc-123" ]]; then
    pass "session_id parsed from JSON input"
  else
    fail "expected abc-123 got $resolved"
  fi

  echo "Scenario 10: session_id falls back to transcript hash"
  unset CLAUDE_SESSION_ID
  resolved=$(retry_guard_session_id '{"transcript_path":"/tmp/x.jsonl"}')
  # Hash is non-empty, deterministic length 12
  if [[ -n "$resolved" ]] && [[ ${#resolved} -le 24 ]]; then
    pass "transcript_path fallback yields non-empty token"
  else
    fail "transcript fallback failed: '$resolved'"
  fi

  echo "Scenario 11: env CLAUDE_SESSION_ID wins over JSON"
  export CLAUDE_SESSION_ID="env-wins"
  resolved=$(retry_guard_session_id '{"session_id":"abc-123"}')
  if [[ "$resolved" == "env-wins" ]]; then
    pass "env CLAUDE_SESSION_ID takes precedence"
  else
    fail "expected env-wins got $resolved"
  fi
  unset CLAUDE_SESSION_ID

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
