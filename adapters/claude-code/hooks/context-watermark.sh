#!/bin/bash
# context-watermark.sh — PostToolUse hook (matcher: all tools), Wave E task E.9a.
#
# WHY THIS EXISTS: the E.9b PreCompact backstop only fires once compaction is
# ALREADY happening — by definition too late for the model to act on its own
# context. This hook is the EARLY WARNING: it fires on every tool call, cheaply
# estimates how full the context window is, and injects an actionable nag
# BEFORE the brink so the model still has room to checkpoint state per
# constitution §5 (persist bugs/decisions/gaps to their durable file NOW,
# not later). Two watermarks: ~70% ("checkpoint soon, you have room") and ~85%
# ("checkpoint NOW" + proactively runs the zero-cost mechanical snapshot script
# so SOMETHING durable exists even if the model does not act on the nag).
#
# CONTEXT MEASUREMENT:
#   PRIMARY (exact, platform-exposed): parse the transcript JSONL's LAST
#   assistant event and read `message.usage.input_tokens +
#   message.usage.cache_read_input_tokens` — this is literally what the
#   platform billed/served as this turn's context, no estimation involved.
#   Verified empirically against a real, live transcript on this machine
#   (2026-07-03): a session's last assistant event carried
#   `{"input_tokens":2,"cache_creation_input_tokens":286,
#     "cache_read_input_tokens":334057,...}` — input_tokens+cache_read_input_tokens
#   (334059) is the correct "how much context is this turn sitting on" figure
#   (cache_creation_input_tokens is NEW context being written to cache this
#   turn, already counted once it becomes cache_read on the NEXT turn — so it
#   is deliberately excluded to avoid double-counting across turns; the first
#   turn after a big write may under-count slightly by that turn's own
#   creation amount, a documented, harmless one-turn lag since the watermark
#   re-evaluates every single tool call).
#
#   FALLBACK (proxy, used only when PRIMARY is unavailable — no jq, transcript
#   unreadable/unparseable, or no assistant event with a usage object yet):
#   transcript file size in bytes × a calibration factor giving an estimated
#   token count. CALIBRATION: measured against a real, live transcript on this
#   machine (2026-07-03) — session 463ee722-0f20-44b2-8595-ee21ace0ea0c.jsonl,
#   2,144,380 bytes, last-assistant-event tokens (input+cache_read) = 334,059
#   -> 6.4192 bytes/token. A SECOND real transcript on the same machine
#   (0e7de6bd-c36a-428d-8944-5e891c81e33d.jsonl, 622,106 bytes / 403,809
#   tokens = 1.54 bytes/token) and a THIRD (8c65ba66...jsonl, 433,028 bytes /
#   419,704 tokens = 1.03 bytes/token) disagreed by up to 6x — bytes-per-token
#   varies heavily with content mix (prose vs. code/diffs) AND is further
#   confounded by prior compactions shrinking the transcript file while
#   `usage` keeps reflecting the model's actual (summarized) context. This is
#   exactly why bytes-based sizing is FALLBACK ONLY, never primary: it is
#   directionally useful (a huge file is never a small context) but not
#   remotely precise. Default factor below uses the FIRST measurement (this
#   repo's own transcript, most representative of this harness's actual usage
#   pattern); override via CONTEXT_WATERMARK_BYTES_PER_TOKEN for a
#   differently-calibrated machine/local config.
#
# WATERMARKS (against a 200,000-token context window):
#   >= 70% (140,000 tokens): inject once per watermark (dedup marker, same
#   pattern as doctrine-jit.sh) — "checkpoint state NOW per constitution §5".
#   >= 85% (170,000 tokens): inject a STRONGER nag once + proactively run
#   scripts/session-snapshot.sh (pure shell, zero model tokens) so a durable
#   handoff snapshot exists regardless of whether the model acts on the nag.
#
# EARLY-EXIT FAST PATH: this fires on EVERY tool call (matcher: all), so the
# common case (below 70%, or both watermarks already fired+deduped this
# session) must be cheap. Order of cheap checks before any transcript parsing:
#   1. stdin/CLAUDE_TOOL_INPUT present and valid JSON -> else exit 0 instantly.
#   2. transcript_path present and the file exists -> else exit 0 instantly.
#   3. BOTH per-session markers already present (70 AND 85 both fired) -> exit
#      0 instantly (nothing left this hook could ever do this session).
# Only past those does it read/parse the transcript.
#
# THIS IS A WRITER/INFORMATIONAL HOOK: every code path exits 0. A PostToolUse
# watermark nag must never break the triggering tool call.
#
# Self-test: --self-test exercises fixture transcripts below/at/above each
# watermark (0/1/2 injections), dedup on re-run, snapshot-triggered-at-85, and
# both the primary usage-parse path and the bytes-fallback path.

set -u

SCRIPT_NAME="context-watermark.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/nl-paths.sh
if [ -f "$SCRIPT_DIR/lib/nl-paths.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/nl-paths.sh" 2>/dev/null || true
fi

CONTEXT_WINDOW_TOKENS="${CONTEXT_WATERMARK_WINDOW:-200000}"
# Calibration factor — see header comment for the measurement. Overridable
# per-machine via local config (env var takes precedence; a
# ~/.claude/local/context-watermark-bytes-per-token file is also honored so a
# machine can persist its own calibration without an env var in every shell).
DEFAULT_BYTES_PER_TOKEN="6.4192"

_bytes_per_token() {
  if [ -n "${CONTEXT_WATERMARK_BYTES_PER_TOKEN:-}" ]; then
    printf '%s' "$CONTEXT_WATERMARK_BYTES_PER_TOKEN"
    return 0
  fi
  local cfg="$HOME/.claude/local/context-watermark-bytes-per-token"
  if [ -f "$cfg" ]; then
    local v
    v="$(head -1 "$cfg" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$v" ]; then
      printf '%s' "$v"
      return 0
    fi
  fi
  printf '%s' "$DEFAULT_BYTES_PER_TOKEN"
}

_state_dir() {
  if [ "${HARNESS_SELFTEST:-0}" = "1" ] && [ -n "${HARNESS_SELFTEST_DIR:-}" ]; then
    printf '%s/state/context-watermark' "$HARNESS_SELFTEST_DIR"
    return 0
  fi
  printf '%s/.claude/state/context-watermark' "$HOME"
}

_sweep_stale_markers() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -type f -mmin +2880 -exec rm -f {} + 2>/dev/null || true
}

# ============================================================
# Context measurement
# ============================================================

# Echoes "<tokens> <source>" where source is "usage" or "bytes-fallback", or
# echoes nothing (measurement failed entirely — caller treats as "no watermark
# reachable", never a crash).
_measure_context_tokens() {
  local transcript="$1"
  [ -f "$transcript" ] || return 0

  # PRIMARY: parse the last assistant event's usage object.
  if command -v jq >/dev/null 2>&1; then
    local usage_line input_tokens cache_read
    usage_line="$(tac "$transcript" 2>/dev/null | while IFS= read -r line; do
                    if printf '%s' "$line" | jq -e '.type=="assistant" and (.message.usage.input_tokens // empty) != null' >/dev/null 2>&1; then
                      printf '%s' "$line"
                      break
                    fi
                  done)"
    if [ -n "$usage_line" ]; then
      input_tokens="$(printf '%s' "$usage_line" | jq -r '.message.usage.input_tokens // 0' 2>/dev/null)"
      cache_read="$(printf '%s' "$usage_line" | jq -r '.message.usage.cache_read_input_tokens // 0' 2>/dev/null)"
      if [ -n "$input_tokens" ] && [ -n "$cache_read" ]; then
        local total
        total=$(( input_tokens + cache_read )) 2>/dev/null
        if [ -n "${total:-}" ]; then
          printf '%s usage' "$total"
          return 0
        fi
      fi
    fi
  fi

  # FALLBACK: bytes x calibration factor.
  local size bpt tokens
  size=$(wc -c < "$transcript" 2>/dev/null | tr -d ' ')
  [ -z "$size" ] && return 0
  bpt="$(_bytes_per_token)"
  tokens="$(awk -v s="$size" -v b="$bpt" 'BEGIN { if (b <= 0) { print 0 } else { printf "%d", s / b } }' 2>/dev/null)"
  [ -z "$tokens" ] && return 0
  printf '%s bytes-fallback' "$tokens"
  return 0
}

# ============================================================
# Core watermark logic (used by both live path and self-test)
#
# Args: $1 = transcript path, $2 = session_id, $3 = state_dir, $4 = repo_root
#       (for the proactive snapshot run at >=85%; empty is fine — snapshot
#       degrades gracefully)
# Echoes the additionalContext JSON blob on a fire (at most one per call —
# the higher watermark wins if both newly cross in the same call, matching
# the "≥85% subsumes ≥70%'s message with a stronger nag" spec intent).
# Side effects: writes per-session marker(s); at >=85% (first time only),
# invokes session-snapshot.sh.
# ============================================================
_compute_watermark() {
  local transcript="$1" session_id="$2" state_dir="$3" snapshot_script="$4"

  [ -n "$transcript" ] || return 0
  [ -n "$session_id" ] || return 0

  local measured tokens source pct
  measured="$(_measure_context_tokens "$transcript")"
  [ -z "$measured" ] && return 0
  tokens="${measured%% *}"
  source="${measured##* }"
  case "$tokens" in
    ''|*[!0-9]*) return 0 ;;
  esac

  pct="$(awk -v t="$tokens" -v w="$CONTEXT_WINDOW_TOKENS" 'BEGIN { if (w<=0) {print 0} else {printf "%d", (t/w)*100} }' 2>/dev/null)"
  [ -z "$pct" ] && return 0

  local marker_70="$state_dir/${session_id}--watermark-70"
  local marker_85="$state_dir/${session_id}--watermark-85"

  if [ "$pct" -ge 85 ]; then
    if [ -f "$marker_85" ]; then
      return 0
    fi
    mkdir -p "$state_dir" 2>/dev/null || true
    : > "$marker_70" 2>/dev/null || true
    : > "$marker_85" 2>/dev/null || true

    # Proactive zero-cost snapshot (pure shell — safe to run unconditionally).
    if [ -n "$snapshot_script" ] && [ -f "$snapshot_script" ]; then
      bash "$snapshot_script" "$transcript" >/dev/null 2>&1 || true
    fi

    jq -n --arg ctx "[context-watermark] context ~${pct}% of ${CONTEXT_WINDOW_TOKENS} (measured: ${tokens} tokens via ${source}) — AT THE 85% MARK: checkpoint state NOW per constitution §5 (durable files, not chat) — a mechanical session-handoff snapshot has been written proactively (scripts/session-snapshot.sh); read it back after any compaction. This is your last comfortable window to persist operator directives, decisions+rationale, and pending asks in your OWN words before compaction summarizes them for you." \
      '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
    return 0
  fi

  if [ "$pct" -ge 70 ]; then
    if [ -f "$marker_70" ]; then
      return 0
    fi
    mkdir -p "$state_dir" 2>/dev/null || true
    : > "$marker_70" 2>/dev/null || true

    jq -n --arg ctx "[context-watermark] context ~${pct}% of ${CONTEXT_WINDOW_TOKENS} (measured: ${tokens} tokens via ${source}) — checkpoint state NOW per constitution §5 while you still have room: durable files (backlog/findings/plan/review), not chat." \
      '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
    return 0
  fi

  return 0
}

# ============================================================
# Live entry path
# ============================================================
_run_live() {
  local input
  input="${CLAUDE_TOOL_INPUT:-}"
  if [ -z "$input" ] && [ ! -t 0 ]; then
    input="$(cat 2>/dev/null || echo "")"
  fi
  [ -z "$input" ] && exit 0

  command -v jq >/dev/null 2>&1 || exit 0
  jq -e . >/dev/null 2>&1 <<<"$input" || exit 0

  local transcript session_id
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"

  [ -z "$transcript" ] && exit 0
  [ ! -f "$transcript" ] && exit 0
  [ -z "$session_id" ] && exit 0

  local state_dir
  state_dir="$(_state_dir)"
  _sweep_stale_markers "$state_dir"

  # Fast early-exit: both watermarks already fired -> nothing left to do.
  if [ -f "$state_dir/${session_id}--watermark-70" ] && [ -f "$state_dir/${session_id}--watermark-85" ]; then
    exit 0
  fi

  local snapshot_script=""
  if [ -f "$SCRIPT_DIR/../scripts/session-snapshot.sh" ]; then
    snapshot_script="$SCRIPT_DIR/../scripts/session-snapshot.sh"
  fi

  _compute_watermark "$transcript" "$session_id" "$state_dir" "$snapshot_script"
  exit 0
}

# ============================================================
# Self-test
# ============================================================
_self_test() {
  local pass=0 fail=0
  local tmp
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t ctxwatermark)"

  export HARNESS_SELFTEST=1
  export HARNESS_SELFTEST_DIR="$tmp/sandbox"
  mkdir -p "$HARNESS_SELFTEST_DIR"

  local state_dir
  state_dir="$(_state_dir)"

  # Helper: build a fixture transcript whose last assistant event carries a
  # given usage total (input_tokens + cache_read_input_tokens split 2/rest).
  _mk_transcript() {
    local path="$1" total="$2"
    printf '{"type":"user","session_id":"sid","message":{"role":"user","content":"hi"}}\n' > "$path"
    printf '{"type":"assistant","session_id":"sid","message":{"role":"assistant","usage":{"input_tokens":2,"cache_read_input_tokens":%d}}}\n' "$((total-2))" >> "$path"
  }

  # T1 — below 70% -> 0 injections.
  local t1="$tmp/below70.jsonl"
  _mk_transcript "$t1" 100000   # 50%
  local got
  got="$(_compute_watermark "$t1" "sess-below70" "$state_dir" "")"
  if [ -z "$got" ] && [ ! -f "$state_dir/sess-below70--watermark-70" ]; then
    echo "  T1 below 70% -> 0 injections: PASS"; pass=$((pass+1))
  else
    echo "  T1 below 70% -> 0 injections: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T2 — at/above 70% (but below 85%) -> 1 injection, correct message, marker written.
  local t2="$tmp/at70.jsonl"
  _mk_transcript "$t2" 150000   # 75%
  got="$(_compute_watermark "$t2" "sess-at70" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -e . >/dev/null 2>&1 \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'checkpoint state NOW per constitution' \
     && [ -f "$state_dir/sess-at70--watermark-70" ] \
     && [ ! -f "$state_dir/sess-at70--watermark-85" ]; then
    echo "  T2 at 70% (below 85%) -> 1 injection + marker: PASS"; pass=$((pass+1))
  else
    echo "  T2 at 70% (below 85%) -> 1 injection + marker: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T3 — same session, still at 75% on next call -> dedup, silent.
  got="$(_compute_watermark "$t2" "sess-at70" "$state_dir" "")"
  if [ -z "$got" ]; then
    echo "  T3 dedup same watermark same session -> silent: PASS"; pass=$((pass+1))
  else
    echo "  T3 dedup same watermark same session -> silent: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T4 — above 85% -> 2 total injections across the session's lifetime (70
  # marker AND 85 marker both get written even if 70 never fired standalone
  # first), stronger message, snapshot invoked.
  local t4="$tmp/at85.jsonl"
  _mk_transcript "$t4" 180000   # 90%
  local snap_marker="$tmp/snapshot-ran.marker"
  cat > "$tmp/fake-snapshot.sh" <<EOF
#!/bin/bash
touch "$snap_marker"
EOF
  chmod +x "$tmp/fake-snapshot.sh"
  got="$(_compute_watermark "$t4" "sess-at85" "$state_dir" "$tmp/fake-snapshot.sh")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'AT THE 85% MARK' \
     && [ -f "$state_dir/sess-at85--watermark-70" ] \
     && [ -f "$state_dir/sess-at85--watermark-85" ] \
     && [ -f "$snap_marker" ]; then
    echo "  T4 at 85% -> stronger nag + both markers + snapshot invoked: PASS"; pass=$((pass+1))
  else
    echo "  T4 at 85% -> stronger nag + both markers + snapshot invoked: FAIL (got: $got, snap: $([ -f "$snap_marker" ] && echo yes || echo no))"; fail=$((fail+1))
  fi

  # T5 — same session, still >=85% on next call -> dedup, silent, snapshot NOT
  # re-invoked.
  rm -f "$snap_marker"
  got="$(_compute_watermark "$t4" "sess-at85" "$state_dir" "$tmp/fake-snapshot.sh")"
  if [ -z "$got" ] && [ ! -f "$snap_marker" ]; then
    echo "  T5 dedup at 85% on re-run -> silent, no re-snapshot: PASS"; pass=$((pass+1))
  else
    echo "  T5 dedup at 85% on re-run -> silent, no re-snapshot: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T6 — a FRESH session that starts already above 85% (never crossed 70
  # standalone) still gets exactly ONE injection (the 85% message, not two
  # separate fires) — "0/1/2 injections" means per-session total count across
  # the watermark's lifetime is bounded at 2 (one 70, one 85), never that a
  # single call can emit two blobs.
  local t6="$tmp/direct85.jsonl"
  _mk_transcript "$t6" 190000
  got="$(_compute_watermark "$t6" "sess-direct85" "$state_dir" "")"
  local blob_count
  blob_count="$(printf '%s' "$got" | grep -c 'hookSpecificOutput' || true)"
  if [ "$blob_count" -eq 1 ] && printf '%s' "$got" | grep -q 'AT THE 85% MARK'; then
    echo "  T6 direct-to-85% session -> exactly one (strong) injection this call: PASS"; pass=$((pass+1))
  else
    echo "  T6 direct-to-85% session -> exactly one (strong) injection this call: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T7 — primary usage-parse path exercised (T1-T6 already used it); confirm
  # explicitly the "source" tag says usage.
  local t7="$tmp/primarycheck.jsonl"
  _mk_transcript "$t7" 145000
  got="$(_compute_watermark "$t7" "sess-primarycheck" "$state_dir" "")"
  if printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'via usage'; then
    echo "  T7 primary usage-parse path exercised (source=usage): PASS"; pass=$((pass+1))
  else
    echo "  T7 primary usage-parse path exercised (source=usage): FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T8 — bytes-fallback path exercised: a transcript with NO usage object at
  # all (jq present but no assistant-usage line) must fall back to
  # bytes x calibration and still watermark correctly.
  local t8="$tmp/nofallback.jsonl"
  printf '{"type":"user","session_id":"sid","message":{"role":"user","content":"hi, no usage here"}}\n' > "$t8"
  # Pad the file to a known size so we can compute an expected pct.
  local bpt target_bytes
  bpt="$DEFAULT_BYTES_PER_TOKEN"
  # Target ~75% (150000 tokens) worth of bytes under the default calibration.
  target_bytes="$(awk -v b="$bpt" 'BEGIN { printf "%d", 150000*b }')"
  # shellcheck disable=SC2183
  printf '%*s' "$target_bytes" '' | tr ' ' 'x' >> "$t8"
  got="$(_compute_watermark "$t8" "sess-bytesfallback" "$state_dir" "")"
  if [ -n "$got" ] && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'via bytes-fallback'; then
    echo "  T8 bytes-fallback path exercised (no usage object -> fallback fires): PASS"; pass=$((pass+1))
  else
    echo "  T8 bytes-fallback path exercised (no usage object -> fallback fires): FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T9 — malformed / missing stdin at the live-entry layer -> exit 0, no output.
  local rc out
  out="$(printf 'not json at all' | HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR="$HARNESS_SELFTEST_DIR" bash "$0" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    echo "  T9 malformed stdin -> exit 0 silent: PASS"; pass=$((pass+1))
  else
    echo "  T9 malformed stdin -> exit 0 silent: FAIL (rc=$rc out='$out')"; fail=$((fail+1))
  fi

  # T10 — markers sandboxed under HARNESS_SELFTEST_DIR, never production.
  if [[ "$state_dir" == "$HARNESS_SELFTEST_DIR"* ]]; then
    echo "  T10 markers sandboxed (state_dir under HARNESS_SELFTEST_DIR): PASS"; pass=$((pass+1))
  else
    echo "  T10 markers sandboxed (state_dir under HARNESS_SELFTEST_DIR): FAIL (state_dir=$state_dir)"; fail=$((fail+1))
  fi

  # T11 — fast early-exit: both markers present -> live path exits 0 with NO
  # transcript parsing at all (simulate via the live entry, both markers
  # pre-seeded).
  mkdir -p "$state_dir"
  : > "$state_dir/sess-bothset--watermark-70"
  : > "$state_dir/sess-bothset--watermark-85"
  local payload
  payload=$(jq -n --arg t "$t2" --arg s "sess-bothset" '{transcript_path:$t, session_id:$s}')
  out="$(printf '%s' "$payload" | HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR="$HARNESS_SELFTEST_DIR" bash "$0" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    echo "  T11 fast early-exit when both watermarks already fired: PASS"; pass=$((pass+1))
  else
    echo "  T11 fast early-exit when both watermarks already fired: FAIL (rc=$rc out='$out')"; fail=$((fail+1))
  fi

  rm -rf "$tmp" 2>/dev/null
  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return "$fail"
}

# ============================================================
# Entry point
# ============================================================
case "${1:-}" in
  --self-test) _self_test; exit $? ;;
  -h|--help)
    cat <<USAGE >&2
context-watermark.sh — PostToolUse early-warning context watermark (Wave E E.9a).

  context-watermark.sh             Read JSON on stdin, emit additionalContext
                                    nag at 70%/85% context watermarks (dedup
                                    per session), proactively snapshot at 85%.
  context-watermark.sh --self-test Run self-test suite.
USAGE
    exit 2
    ;;
  "") _run_live ;;
  *)
    echo "context-watermark.sh: unknown argument '$1'" >&2
    exit 2
    ;;
esac
