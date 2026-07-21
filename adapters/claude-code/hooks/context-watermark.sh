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
#   THE SAME assistant event also carries `message.model` — parsed in the
#   SAME jq pass (see `_measure_context_tokens`) and fed to `_resolve_window`
#   to pick the DENOMINATOR, not just the numerator. Verified on this machine
#   (2026-07-20): this session's own last assistant event carried
#   `"model":"claude-opus-4-8"` alongside its usage object.
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
#   differently-calibrated machine/local config. NOTE: the bytes-fallback path
#   never has a `model` to key off (no assistant-usage line was found at
#   all), so a fallback-measured call ALWAYS resolves the conservative
#   200,000 default window, and the emitted message says so ("ASSUMED") —
#   see WINDOW RESOLUTION below.
#
# WINDOW RESOLUTION (the denominator) — added 2026-07-20 after a PROVEN
# incident: a hardcoded 200,000 denominator on a claude-opus-4-8 session (a
# real 1,000,000-token window) made this hook claim "~95% of 200000" well
# before the pause (that reading is ~190,000 tokens — 19% of the REAL 1M
# window). By the time the session paused it had reached 322,800 tokens —
# 32% of the ACTUAL window, 68% FREE — at which point the same wrong
# arithmetic would read ~161% (322,800/200,000), further reinforcing the
# false alarm. Either way, an autonomous orchestrator read the hook's output
# as authoritative capacity and PAUSED a multi-hour program, abandoning 28
# of 34 remaining work items. Recurring: the identical defect was reported
# in nl-issues.jsonl on 2026-07-18 (one session, twice ~8 minutes apart) and
# again on 2026-07-20 from a different project/session — this incident. See
# docs/lessons/2026-07-20-context-watermark-window-and-context-pressure.md
# for the full write-up.
#
#   Precedence: CONTEXT_WATERMARK_WINDOW env override (unset or non-numeric
#   -> skip, never trusted blindly) > model->window lookup (`_model_window`,
#   below) > conservative 200000 default.
#
#   MODEL -> WINDOW TABLE (`_model_window`) — verified LIVE against
#   platform.claude.com/docs/en/about-claude/models/overview on 2026-07-20
#   (both the "latest models" and "Legacy models" comparison tables), plus
#   this machine's own transcripts as corroboration where noted:
#     1,000,000 tokens — claude-fable-5*, claude-mythos-5*,
#       claude-mythos-preview* (doc: "Claude Mythos 5 shares Claude Fable
#       5's specs"), claude-opus-4-8* (doc + this session's own transcript,
#       model="claude-opus-4-8"), claude-opus-4-7*, claude-opus-4-6*,
#       claude-sonnet-5* (doc, corroborated by anthropic.com/news/claude-
#       sonnet-5 via WebSearch), claude-sonnet-4-6*.
#     200,000 tokens — claude-haiku-4-5* (doc; also directly observed in
#       this machine's transcripts as `claude-haiku-4-5-20251001`),
#       claude-sonnet-4-5*, claude-opus-4-5*, claude-opus-4-1*. Listed
#       EXPLICITLY (rather than left to fall through) so the emitted message
#       can say "detected" instead of "assumed" for these — the difference
#       matters because "assumed" is the honest label for "we don't know",
#       not for "we checked and it's 200k".
#     Anything else (empty/unparseable model, a model not yet in this table
#     — e.g. legacy claude-3-*, which were NOT re-verified for this change)
#     falls through to the conservative 200000 default AND the emitted
#     message says so explicitly ("ASSUMED") — never silently presented as
#     measured fact. Prefix-matched (trailing `*`) so a dated snapshot ID
#     like `claude-haiku-4-5-20251001` matches its family entry. Keep this
#     table current when new models ship; when a model's window cannot be
#     confidently verified, do NOT guess — let it fall through to assumed.
#
#   THRESHOLDS RECONSIDERED (kept unchanged): 70%/85% are proportions, not
#   absolute token counts, so they scale with whatever window was resolved
#   (e.g. 700k/850k of a 1M window vs. 140k/170k of a 200k window). The
#   proportional margin against each window's max_output (128k for the 1M-
#   window models, 64k for Haiku 4.5's 200k window) is comparable in both
#   cases, so the SAME percentages remain a sane checkpoint moment regardless
#   of which window was resolved — no threshold value was changed here.
#
#   NEVER A STOP REASON: this hook's nag is advisory, not authoritative
#   capacity — and even a CORRECTLY measured high watermark is never a
#   reason to pause or stop autonomous work. Compaction (see the PreCompact
#   hook `pre-compact-continuity.sh`, docs/runbooks/pre-compaction-
#   snapshots.md) handles overflow automatically; the correct response is
#   "checkpoint state now, keep going" — the emitted message says this
#   explicitly (operator directive, 2026-07-20; see also
#   doctrine/session-end-protocol.md).
#
# WATERMARKS (against the RESOLVED window — see WINDOW RESOLUTION above; was
# a hardcoded 200,000 before 2026-07-20):
#   >= 70%: inject once per watermark (dedup marker, same pattern as
#   doctrine-jit.sh) — "checkpoint state NOW per constitution §5".
#   >= 85%: inject a STRONGER nag once + proactively run
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
# watermark (0/1/2 injections), dedup on re-run, snapshot-triggered-at-85,
# both the primary usage-parse path and the bytes-fallback path, and (added
# 2026-07-20) window resolution: a large-context model detected correctly, a
# 200k model detected correctly (not just defaulted), the env override still
# winning over model-detection, an unknown/absent model falling back to the
# conservative default WHILE being labeled "ASSUMED" in the message, and (a
# harness-reviewer finding, same day) that the model-prefix matching is
# delimiter-anchored — a future numeric sibling of a listed model (e.g.
# "claude-opus-4-10" against the listed "claude-opus-4-1") is NOT swallowed
# by a bare-prefix glob and mislabeled "detected".

set -u

SCRIPT_NAME="context-watermark.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/nl-paths.sh
if [ -f "$SCRIPT_DIR/lib/nl-paths.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/nl-paths.sh" 2>/dev/null || true
fi

# CONTEXT_WATERMARK_WINDOW is the explicit escape-hatch override (highest
# precedence in _resolve_window, below) — NOT resolved to a single global
# here anymore, because the correct window now depends on which model
# produced the transcript being measured, discovered per-call. See WINDOW
# RESOLUTION in the header comment.
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

# ============================================================
# Model -> context-window lookup
# ============================================================
# Maps a model ID (as read from the transcript's `message.model`, e.g.
# "claude-opus-4-8", or a dated snapshot like "claude-haiku-4-5-20251001")
# to its real context-window size in tokens. DELIMITER-ANCHORED matching:
# each entry is "the bare ID" OR "the bare ID + literal dash" — deliberately
# NOT a bare trailing `*` glob, which would also swallow a future numeric
# sibling (e.g. "claude-opus-4-1*" would match "claude-opus-4-10" or
# "claude-opus-4-18") and silently mislabel it "detected" if that sibling
# ships with a different window (harness-reviewer finding, 2026-07-20 —
# confident-and-wrong is worse than falling through to "assumed"). See the
# header comment's WINDOW RESOLUTION section for the verification trail
# (fetched live from platform.claude.com/docs on 2026-07-20) — keep that
# comment and this table in sync when models ship/retire.
#
# Echoes the window token count and returns 0 on a match. Returns 1 with NO
# output when the model is empty or not in this table — the caller
# (_resolve_window) falls through to the conservative default and labels it
# "assumed". This function never guesses a window for an unrecognized model.
_model_window() {
  local model="$1"
  [ -n "$model" ] || return 1
  case "$model" in
    claude-fable-5|claude-fable-5-*|claude-mythos-5|claude-mythos-5-*|claude-mythos-preview|claude-mythos-preview-*|claude-opus-4-8|claude-opus-4-8-*|claude-opus-4-7|claude-opus-4-7-*|claude-opus-4-6|claude-opus-4-6-*|claude-sonnet-5|claude-sonnet-5-*|claude-sonnet-4-6|claude-sonnet-4-6-*)
      printf '1000000'
      return 0
      ;;
    claude-haiku-4-5|claude-haiku-4-5-*|claude-sonnet-4-5|claude-sonnet-4-5-*|claude-opus-4-5|claude-opus-4-5-*|claude-opus-4-1|claude-opus-4-1-*)
      printf '200000'
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ============================================================
# Window resolution (the denominator)
# ============================================================
# Precedence: explicit CONTEXT_WATERMARK_WINDOW env override (the escape
# hatch — kept; ignored if unset or not a positive integer, so a garbage env
# var can't silently zero out the math) > model-detected window
# (_model_window) > conservative 200000 default.
#
# Echoes "<window> <source>" where source is "override", "detected", or
# "assumed" — "assumed" is the ONLY case where the window was not actually
# established, and the caller's emitted message must say so explicitly (this
# is the direct fix for the proven incident: a session must never read an
# unlabeled percentage as authoritative capacity).
_resolve_window() {
  local model="${1:-}"

  if [ -n "${CONTEXT_WATERMARK_WINDOW:-}" ]; then
    case "$CONTEXT_WATERMARK_WINDOW" in
      *[!0-9]*|'') : ;;  # non-numeric override -> don't trust it, fall through
      *)
        printf '%s override' "$CONTEXT_WATERMARK_WINDOW"
        return 0
        ;;
    esac
  fi

  if [ -n "$model" ]; then
    local w
    w="$(_model_window "$model")"
    if [ -n "$w" ]; then
      printf '%s detected' "$w"
      return 0
    fi
  fi

  printf '200000 assumed'
  return 0
}

_sweep_stale_markers() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -type f -mmin +2880 -exec rm -f {} + 2>/dev/null || true
}

# ============================================================
# Context measurement
# ============================================================

# Echoes "<tokens> <source> <model>" where source is "usage" or
# "bytes-fallback", and model is the transcript's `message.model` string (the
# SAME assistant event, same jq pass — used downstream to resolve the real
# context window) or "-" when unavailable (bytes-fallback never has one: no
# assistant-usage line was found at all). Echoes nothing (measurement failed
# entirely — caller treats as "no watermark reachable", never a crash).
_measure_context_tokens() {
  local transcript="$1"
  [ -f "$transcript" ] || return 0

  # PRIMARY: parse the last assistant event's usage object (and its model).
  if command -v jq >/dev/null 2>&1; then
    local usage_line input_tokens cache_read model
    usage_line="$(tac "$transcript" 2>/dev/null | while IFS= read -r line; do
                    if printf '%s' "$line" | jq -e '.type=="assistant" and (.message.usage.input_tokens // empty) != null' >/dev/null 2>&1; then
                      printf '%s' "$line"
                      break
                    fi
                  done)"
    if [ -n "$usage_line" ]; then
      input_tokens="$(printf '%s' "$usage_line" | jq -r '.message.usage.input_tokens // 0' 2>/dev/null)"
      cache_read="$(printf '%s' "$usage_line" | jq -r '.message.usage.cache_read_input_tokens // 0' 2>/dev/null)"
      model="$(printf '%s' "$usage_line" | jq -r '.message.model // empty' 2>/dev/null)"
      [ -z "$model" ] && model="-"
      if [ -n "$input_tokens" ] && [ -n "$cache_read" ]; then
        local total
        total=$(( input_tokens + cache_read )) 2>/dev/null
        if [ -n "${total:-}" ]; then
          printf '%s usage %s' "$total" "$model"
          return 0
        fi
      fi
    fi
  fi

  # FALLBACK: bytes x calibration factor. No model available via this path.
  local size bpt tokens
  size=$(wc -c < "$transcript" 2>/dev/null | tr -d ' ')
  [ -z "$size" ] && return 0
  bpt="$(_bytes_per_token)"
  tokens="$(awk -v s="$size" -v b="$bpt" 'BEGIN { if (b <= 0) { print 0 } else { printf "%d", s / b } }' 2>/dev/null)"
  [ -z "$tokens" ] && return 0
  printf '%s bytes-fallback -' "$tokens"
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

  local measured tokens source model
  measured="$(_measure_context_tokens "$transcript")"
  [ -z "$measured" ] && return 0
  tokens="$(printf '%s' "$measured" | awk '{print $1}')"
  source="$(printf '%s' "$measured" | awk '{print $2}')"
  model="$(printf '%s' "$measured" | awk '{print $3}')"
  [ "$model" = "-" ] && model=""
  case "$tokens" in
    ''|*[!0-9]*) return 0 ;;
  esac

  local resolved window win_source window_clause pct
  resolved="$(_resolve_window "$model")"
  window="${resolved%% *}"
  win_source="${resolved##* }"
  case "$window" in
    ''|*[!0-9]*) return 0 ;;
  esac

  case "$win_source" in
    detected)
      window_clause="model ${model}, window auto-detected"
      ;;
    override)
      window_clause="window from CONTEXT_WATERMARK_WINDOW override"
      ;;
    *)
      window_clause="window ASSUMED (model ${model:-not present in transcript} not in the known-window table; defaulting to the conservative ${window} — if this session's real window is larger, this percentage OVERESTIMATES usage)"
      ;;
  esac

  pct="$(awk -v t="$tokens" -v w="$window" 'BEGIN { if (w<=0) {print 0} else {printf "%d", (t/w)*100} }' 2>/dev/null)"
  [ -z "$pct" ] && return 0

  local marker_70="$state_dir/${session_id}--watermark-70"
  local marker_85="$state_dir/${session_id}--watermark-85"
  local never_stop="Context pressure is NEVER a reason to stop or pause autonomous work — compaction handles overflow automatically; checkpoint state and keep going."

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

    jq -n --arg ctx "[context-watermark] context ~${pct}% of ${window} (${window_clause}) — measured ${tokens} tokens via ${source}. AT THE 85% MARK: checkpoint state NOW per constitution §5 (durable files, not chat) — a mechanical session-handoff snapshot has been written proactively (scripts/session-snapshot.sh); read it back after any compaction. This is your last comfortable window to persist operator directives, decisions+rationale, and pending asks in your OWN words before compaction summarizes them for you. ${never_stop}" \
      '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
    return 0
  fi

  if [ "$pct" -ge 70 ]; then
    if [ -f "$marker_70" ]; then
      return 0
    fi
    mkdir -p "$state_dir" 2>/dev/null || true
    : > "$marker_70" 2>/dev/null || true

    jq -n --arg ctx "[context-watermark] context ~${pct}% of ${window} (${window_clause}) — measured ${tokens} tokens via ${source}. checkpoint state NOW per constitution §5 while you still have room: durable files (backlog/findings/plan/review), not chat. ${never_stop}" \
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
  # No `model` field -> exercises the "model absent -> assumed default" path.
  _mk_transcript() {
    local path="$1" total="$2"
    printf '{"type":"user","session_id":"sid","message":{"role":"user","content":"hi"}}\n' > "$path"
    printf '{"type":"assistant","session_id":"sid","message":{"role":"assistant","usage":{"input_tokens":2,"cache_read_input_tokens":%d}}}\n' "$((total-2))" >> "$path"
  }

  # Helper: same as above, but with an explicit `message.model` field, for
  # exercising window auto-detection (added 2026-07-20).
  _mk_transcript_model() {
    local path="$1" total="$2" model="$3"
    printf '{"type":"user","session_id":"sid","message":{"role":"user","content":"hi"}}\n' > "$path"
    printf '{"type":"assistant","session_id":"sid","message":{"role":"assistant","model":"%s","usage":{"input_tokens":2,"cache_read_input_tokens":%d}}}\n' "$model" "$((total-2))" >> "$path"
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

  # ==========================================================
  # T12-T19 — window resolution (added 2026-07-20, the incident fix).
  # ==========================================================

  # T12 — model absent (T1-T11's fixtures never set `message.model`) ->
  # falls back to the conservative default AND the message says so
  # explicitly. This is the direct regression test for the proven incident:
  # an unlabeled percentage against a wrong denominator must never happen
  # again — "assumed" must always be spelled out when the window wasn't
  # actually established.
  local t12="$tmp/modelabsent.jsonl"
  _mk_transcript "$t12" 150000   # 75% of the assumed 200000 default
  got="$(_compute_watermark "$t12" "sess-modelabsent" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'ASSUMED' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '~75% of 200000'; then
    echo "  T12 model absent -> conservative default, message says ASSUMED: PASS"; pass=$((pass+1))
  else
    echo "  T12 model absent -> conservative default, message says ASSUMED: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T13 — large-context model (claude-opus-4-8, the model in the real
  # incident) detected -> correct pct against the 1,000,000 window, message
  # names the model and is NOT labeled assumed.
  local t13="$tmp/opus48.jsonl"
  _mk_transcript_model "$t13" 750000 "claude-opus-4-8"   # 75% of 1,000,000
  got="$(_compute_watermark "$t13" "sess-opus48" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '~75% of 1000000' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'model claude-opus-4-8' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'ASSUMED'; then
    echo "  T13 large-context model (claude-opus-4-8) detected, correct pct vs 1M, not assumed: PASS"; pass=$((pass+1))
  else
    echo "  T13 large-context model (claude-opus-4-8) detected, correct pct vs 1M, not assumed: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T13b — the exact real-incident numbers: 322,800 tokens on claude-opus-4-8
  # (1,000,000 window) is 32% — BELOW even the 70% watermark, so the hook
  # must stay completely silent (this is what should have happened live;
  # instead the old 200000-denominator code would have reported ~161%).
  local t13b="$tmp/realincident.jsonl"
  _mk_transcript_model "$t13b" 322800 "claude-opus-4-8"
  got="$(_compute_watermark "$t13b" "sess-realincident" "$state_dir" "")"
  if [ -z "$got" ]; then
    echo "  T13b real-incident numbers (322.8k/1M=32%) -> silent, no false alarm: PASS"; pass=$((pass+1))
  else
    echo "  T13b real-incident numbers (322.8k/1M=32%) -> silent, no false alarm: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T14 — a 200k model (claude-haiku-4-5, dated snapshot ID) is DETECTED
  # explicitly, not just defaulted -- message says "auto-detected", not
  # "ASSUMED", even though the resulting window value (200000) matches the
  # default.
  local t14="$tmp/haiku45.jsonl"
  _mk_transcript_model "$t14" 150000 "claude-haiku-4-5-20251001"   # 75% of 200000
  got="$(_compute_watermark "$t14" "sess-haiku45" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'model claude-haiku-4-5-20251001' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'auto-detected' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'ASSUMED'; then
    echo "  T14 200k model (claude-haiku-4-5, dated ID) detected explicitly, not assumed: PASS"; pass=$((pass+1))
  else
    echo "  T14 200k model (claude-haiku-4-5, dated ID) detected explicitly, not assumed: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T15 — CONTEXT_WATERMARK_WINDOW env override still wins over a
  # model-detected window (precedence: override > detected > assumed).
  local t15="$tmp/override.jsonl"
  _mk_transcript_model "$t15" 40000 "claude-opus-4-8"   # would be 4% at 1M
  export CONTEXT_WATERMARK_WINDOW=50000                 # forces 80% instead
  got="$(_compute_watermark "$t15" "sess-override" "$state_dir" "")"
  unset CONTEXT_WATERMARK_WINDOW
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '~80% of 50000' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'override'; then
    echo "  T15 CONTEXT_WATERMARK_WINDOW override wins over model-detected window: PASS"; pass=$((pass+1))
  else
    echo "  T15 CONTEXT_WATERMARK_WINDOW override wins over model-detected window: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T16 — an unrecognized model string (not empty, just not in the table)
  # also falls back to conservative + ASSUMED, same as absent.
  local t16="$tmp/unknownmodel.jsonl"
  _mk_transcript_model "$t16" 150000 "claude-hypothetical-9"
  got="$(_compute_watermark "$t16" "sess-unknownmodel" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'ASSUMED' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'claude-hypothetical-9'; then
    echo "  T16 unrecognized (but non-empty) model -> conservative default, ASSUMED, names the model: PASS"; pass=$((pass+1))
  else
    echo "  T16 unrecognized (but non-empty) model -> conservative default, ASSUMED, names the model: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T17 — direct unit check of _model_window's table for a representative
  # sample across both windows, plus confirming an unknown model returns
  # nothing (never guesses).
  local w
  w="$(_model_window "claude-sonnet-5")"
  local w2 w3
  w2="$(_model_window "claude-opus-4-1")"
  w3="$(_model_window "claude-does-not-exist")"
  if [ "$w" = "1000000" ] && [ "$w2" = "200000" ] && [ -z "$w3" ]; then
    echo "  T17 _model_window table spot-check (sonnet-5=1M, opus-4-1=200k, unknown=empty): PASS"; pass=$((pass+1))
  else
    echo "  T17 _model_window table spot-check (sonnet-5=1M, opus-4-1=200k, unknown=empty): FAIL (w=$w w2=$w2 w3=$w3)"; fail=$((fail+1))
  fi

  # T19 — prefix-collision guard (harness-reviewer finding, 2026-07-20): a
  # FUTURE numeric sibling that merely starts with a listed model's ID (e.g.
  # "claude-opus-4-10" or "claude-opus-4-18" starting with "claude-opus-4-1")
  # must NOT be swallowed by that entry's bare-prefix glob — it has no dash
  # delimiter after "claude-opus-4-1", so it must fall through to "unknown"
  # (empty/nonzero from _model_window, and ASSUMED end-to-end), never get
  # silently mislabeled "detected" with a possibly-wrong window. Same check
  # for a "claude-sonnet-5" sibling ("claude-sonnet-50") against the 1M
  # bucket, and confirms the LEGITIMATE dash-suffixed dated-snapshot form
  # still matches (the anchoring must not be so strict it breaks real IDs).
  local w4 w5 w6
  w4="$(_model_window "claude-opus-4-10")"
  w5="$(_model_window "claude-sonnet-50")"
  w6="$(_model_window "claude-opus-4-1-20250805")"
  if [ -z "$w4" ] && [ -z "$w5" ] && [ "$w6" = "200000" ]; then
    echo "  T19 prefix-collision guard (4-10/sonnet-50 not swallowed by 4-1/sonnet-5; dated snapshot still matches): PASS"; pass=$((pass+1))
  else
    echo "  T19 prefix-collision guard (4-10/sonnet-50 not swallowed by 4-1/sonnet-5; dated snapshot still matches): FAIL (w4=$w4 w5=$w5 w6=$w6)"; fail=$((fail+1))
  fi

  # T18 — the never-a-stop-reason clause is present in every fired message
  # (fresh session so this test is independent of any other test's dedup
  # state).
  local t18="$tmp/neverstop.jsonl"
  _mk_transcript_model "$t18" 750000 "claude-opus-4-8"
  got="$(_compute_watermark "$t18" "sess-neverstop" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'NEVER a reason to stop or pause' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'compaction handles overflow'; then
    echo "  T18 fired message carries the never-a-stop-reason / compaction clause: PASS"; pass=$((pass+1))
  else
    echo "  T18 fired message carries the never-a-stop-reason / compaction clause: FAIL (got: $got)"; fail=$((fail+1))
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
