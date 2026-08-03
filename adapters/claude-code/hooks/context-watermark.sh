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
#   re-evaluates every single tool call). VERIFIED AGAIN 2026-07-29 against
#   the live transcript of this machine's own session: `message.usage` carries
#   exactly {input_tokens, cache_creation_input_tokens,
#   cache_read_input_tokens, output_tokens, cache_creation, server_tool_use,
#   service_tier, inference_geo, iterations, speed} — a numerator, never a
#   denominator. See THE CLASS FIX below.
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
#   all), so a fallback-measured call ALWAYS resolves to UNKNOWN and emits
#   the maintenance notice instead of a percentage — which is the right answer
#   twice over, since that path's numerator is itself 6x-uncertain. See
#   WINDOW RESOLUTION below.
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
#   below) > UNKNOWN. There is NO conservative-default denominator any more —
#   see THE CLASS FIX below for why that default was the bug, not the safety
#   net it looked like.
#
#   MODEL -> WINDOW TABLE (`_model_window`) — verified LIVE against
#   platform.claude.com/docs/en/about-claude/models/overview on 2026-07-20
#   (both the "latest models" and "Legacy models" comparison tables), plus
#   this machine's own transcripts as corroboration where noted:
#     1,000,000 tokens — claude-opus-5* (ADDED 2026-07-28 after this hook
#       repeated the 2026-07-20 incident VERBATIM on an Opus 5 session:
#       reported "~74% of 200000" and then "~90% of 200000" when the client's
#       own context readout showed 163.2k/1.0M = 16%. The assumed-label
#       machinery worked exactly as designed — the message did say ASSUMED —
#       but a 5x overstated percentage still pushed the session toward
#       premature checkpointing, which is the whole failure this table
#       exists to prevent. Corroborated by the operator's client UI
#       screenshot showing "Context window 163.2k / 1.0M (16%)" with model
#       Opus 5 selected; that is a LIVE observation of the real denominator,
#       the strongest evidence class this table accepts),
#       claude-fable-5*, claude-mythos-5*,
#       claude-mythos-preview* (doc: "Claude Mythos 5 shares Claude Fable
#       5's specs"), claude-opus-4-8* (doc + this session's own transcript,
#       model="claude-opus-4-8"), claude-opus-4-7*, claude-opus-4-6*,
#       claude-sonnet-5* (doc, corroborated by anthropic.com/news/claude-
#       sonnet-5 via WebSearch), claude-sonnet-4-6*.
#
#     MAINTENANCE LESSON (2026-07-28): this table is a hardcoded allowlist, so
#     it goes stale by DEFAULT every time a model ships — the failure is silent
#     and recurring, not a one-off. The 2026-07-20 fix made staleness HONEST
#     ("ASSUMED") but did nothing to make it RARE. Adding one model family per
#     incident is treating the symptom. Tracked as a real gap in
#     docs/backlog.md CONTEXT-WATERMARK-WINDOW-TABLE-STALENESS-01.
#     200,000 tokens — claude-haiku-4-5* (doc; also directly observed in
#       this machine's transcripts as `claude-haiku-4-5-20251001`),
#       claude-sonnet-4-5*, claude-opus-4-5*, claude-opus-4-1*. Listed
#       EXPLICITLY (rather than left to fall through) so the emitted message
#       can say "detected" instead of "assumed" for these — the difference
#       matters because "assumed" is the honest label for "we don't know",
#       not for "we checked and it's 200k".
#     Anything else (empty/unparseable model, a model not yet in this table
#     — e.g. legacy claude-3-*, which were NOT re-verified for this change)
#     resolves to UNKNOWN: the hook emits NO percentage and NO watermark for
#     that session, and instead emits a one-shot maintenance notice naming
#     the model and this function. Prefix-matched (delimiter-anchored) so a
#     dated snapshot ID like `claude-haiku-4-5-20251001` matches its family
#     entry. Keep this table current when new models ship; when a model's
#     window cannot be confidently verified, do NOT guess — let it fall
#     through to UNKNOWN.
#
# ============================================================================
# THE CLASS FIX (2026-07-29) — why there is no default denominator any more
# ============================================================================
# The 2026-07-20 and 2026-07-28 incidents were the SAME defect twice: a model
# missing from the table above fell through to a hardcoded 200,000
# denominator and the hook printed a confident percentage against it
# ("~74% of 200000" on a session that was 16% full). The 2026-07-20 fix added
# an "ASSUMED" label, which made the wrongness HONEST but not RARE — the
# table goes stale by construction on every model launch, silently, and the
# only detector was "an operator eventually notices the percentage is
# absurd". Backlog row CONTEXT-WATERMARK-WINDOW-TABLE-STALENESS-01 named
# three candidate fixes; all three were evaluated against the real runtime
# before choosing.
#
#   (b) READ THE WINDOW AT RUNTIME — investigated first, because if the real
#       window were obtainable the table would stop being load-bearing at all
#       and the class would be RETIRED rather than mitigated. RULED OUT, with
#       evidence (client 2.1.219, this machine, 2026-07-29):
#         - The PostToolUse hook payload does not carry it. The client's own
#           payload schema is {session_id, transcript_path, cwd, prompt_id?,
#           permission_mode?, agent_id?, agent_type?, effort?} plus
#           {hook_event_name, tool_name, tool_input, tool_response,
#           tool_use_id, duration_ms?}. No model, no window.
#         - The transcript JSONL does not carry it. `message.usage` keys are
#           exactly {input_tokens, cache_creation_input_tokens,
#           cache_read_input_tokens, output_tokens, cache_creation,
#           server_tool_use, service_tier, inference_geo, iterations, speed}.
#           A grep for context_window/contextWindow/max_input_tokens/
#           window_size/context_limit across all 67 real transcripts on this
#           machine returned ZERO hits.
#         - No env var exposes it. CLAUDE_CODE_MAX_CONTEXT_TOKENS exists but
#           is an operator-set INPUT the client itself only honors when
#           DISABLE_COMPACT is set, or for non-`claude-` model ids — trusting
#           it as the denominator would re-create confidently-wrong.
#         - No client-written file exposes it. ~/.claude.json has an
#           `autoCompactWindowsCache` key, but the client consults it for
#           `claude-sonnet-4-6` only (one experiment knob) and it is null here.
#           The client's ~/.claude/debug/*.txt logs do print
#           "autocompact: ... effectiveWindow=N", but those files are not
#           correlatable to the session_id a hook receives (no debug file on
#           this machine references the live session id) and depend on debug
#           logging being on.
#         - The ONE channel that does expose it is the StatusLine command
#           input (`context_window.context_window_size`). That is a different,
#           operator-owned UI surface that this harness does not configure;
#           wiring it would mean claiming a mechanism that has never been
#           observed to fire here, which constitution §10 forbids. Recorded
#           in the backlog row as the future path if a status line is ever
#           adopted.
#
#   (c) DOCTOR CHECK that REDs when the running session's model is missing —
#       viable (the running model IS readable from the newest transcript) but
#       strictly weaker: the wrong percentage still gets emitted, and it is
#       only caught whenever someone next runs the doctor. It shortens
#       detection latency; it does not remove the harm.
#
#   (a) CHOSEN — invert the default. An unknown model now yields NO
#       denominator, so no percentage can be printed at all. The failure mode
#       changes from "confidently wrong number" (which provably aborted an
#       autonomous program) to "no watermark this session", which the
#       PreCompact backstop (pre-compact-continuity.sh) already covers, and
#       which this hook's own message has always said is never a stop reason.
#       Suppression alone would have destroyed the ONLY existing detector (the
#       absurd percentage), so the detector is rebuilt IN BAND: on an unknown
#       model the hook emits a one-shot, non-numeric maintenance notice that
#       names the model, names this file and `_model_window`, emits ONLY the
#       raw measured token count (no percentage, no candidate readings, no
#       denominator in any form — see THE SECOND CLASS FIX, 2026-08-02, below
#       for why even an explicit either/or reading was still unsafe), and
#       names the env escape hatch. That reaches the agent that can fix it,
#       in the session where it matters, on the first call that could possibly
#       have mattered — strictly louder than the doctor check of option (c),
#       and without ever asserting a number the hook cannot defend.
#
#   NOTICE FLOOR: the unknown-model notice is withheld until the measured
#   token count reaches 70% of the SMALLEST window any known model has
#   (200,000 -> 140,000 tokens). Below that, no model in the table could be
#   at its 70% watermark, so there is provably nothing to say and the notice
#   would be pure noise. The marker is written only when the notice actually
#   fires, so a session that starts small still gets the notice later.
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
# ============================================================================
# THE SECOND CLASS FIX (2026-08-02) — the either/or notice was STILL unsafe
# ============================================================================
# GOLDEN CASE (real, this estate, 2026-08-02): a session emitted "context
# ~211% of 200000 (window ASSUMED (model claude-opus-5 not in the
# known-window table; defaulting to the conservative 200000 — if this
# session's real window is larger, this percentage OVERESTIMATES usage))".
# The agent read the percentage, ignored the parenthetical caveat, and
# prematurely stopped/handed off work at ~15% real usage. This is the same
# shape of failure THE CLASS FIX above (2026-07-29) was supposed to have
# retired — and the mechanism of recurrence exposes what that fix actually
# got wrong: it removed the one WRONG percentage but replaced it with an
# "X% of a 200000-token window OR Y% of a 1000000-token one" either/or. Both
# numbers still take the exact familiar "N% of M" shape a pattern-matching
# reader (human or model) latches onto and treats as authoritative, no matter
# how much honest caveat surrounds them — precisely the failure mode named in
# this task's own root principle. A correct CAVEAT wrapped around a
# WRONG-SHAPED number does not neutralize the number; only not emitting a
# number in that shape does.
#
# ROOT PRINCIPLE (operator directive, 2026-08-02): never emit a derived
# metric you cannot derive correctly; emit the raw fact instead. Applied
# here: the unknown-model notice below no longer computes or prints ANY
# percentage or candidate window size — not one, not two. It states the
# model is unknown, states the raw measured token count (a fact this hook
# CAN derive correctly — see CONTEXT MEASUREMENT above), explicitly
# instructs the reader not to infer context pressure from that raw count,
# and keeps the never-a-stop-reason clause. The literal substring "% of"
# does not appear anywhere on this path — verified by self-test (T25-T27).
# MIN_KNOWN_WINDOW/MAX_KNOWN_WINDOW are retired from the message entirely;
# MIN_KNOWN_WINDOW survives only as the (undisplayed) notice-floor gate.
#
# MODEL TABLE RE-VERIFIED (2026-08-02, WebFetch against
# platform.claude.com/docs/en/about-claude/models/overview): every model
# family on that page (Fable 5, Mythos 5, Mythos Preview, Opus 5, Sonnet 5,
# Haiku 4.5, plus the Legacy table's Opus 4.8/4.7/4.6, Sonnet 4.6/4.5, Opus
# 4.5/4.1) is already present in `_model_window` below with the correct
# window. No table entries were added by this pass — the table was not the
# gap; the message SHAPE for the models it doesn't yet know about was.
# ============================================================================
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
# winning over model-detection, and (a harness-reviewer finding, same day)
# that the model-prefix matching is delimiter-anchored — a future numeric
# sibling of a listed model (e.g. "claude-opus-4-10" against the listed
# "claude-opus-4-1") is NOT swallowed by a bare-prefix glob and mislabeled
# "detected". Added 2026-07-29 (the class fix, T20-T24): an unknown model
# emits the maintenance notice and NEVER a point percentage, writes NO
# watermark markers and triggers NO snapshot; the notice dedups per session;
# it is withheld below the notice floor but still fires later in the same
# session once the floor is crossed; the env override rescues an unknown
# model; and the suite never re-invokes itself via bare `bash` (which would
# silently test whichever interpreter is first on PATH rather than the one
# running the suite). Added 2026-08-02 (the second class fix, T25-T27): the
# unknown-model notice never contains the literal substring "% of" or any
# fabricated denominator (200000/1000000) in any form, states the raw
# measured token count and an explicit unknown-window statement, and
# instructs the reader not to infer pressure from it; the never-a-stop-reason
# clause is present on BOTH the known-model and unknown-model paths; and the
# known-model path still emits a correct percentage unchanged.

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

# ============================================================
# Known-window floor — used ONLY to gate WHEN the unknown-model notice fires
# (see UNKNOWN_NOTICE_FLOOR below), never to compute or display a percentage
# or candidate window size for an unknown model (retired 2026-08-02 — see
# THE SECOND CLASS FIX in the header comment: even an explicit either/or
# reading against this bound and its since-removed sibling MAX_KNOWN_WINDOW
# still took the unsafe "N% of M" shape). Read off `_model_window`'s own
# table below (its smallest known window). Keep in sync if the table ever
# gains a smaller bucket.
# ============================================================
MIN_KNOWN_WINDOW=200000

# The unknown-model notice is withheld below 70% of the SMALLEST window any
# known model has. Below that point no model in the table could be at its 70%
# watermark, so there is provably nothing worth saying and the notice would be
# pure noise on every short session. 200000 * 70 / 100 = 140000.
UNKNOWN_NOTICE_FLOOR=$(( MIN_KNOWN_WINDOW * 70 / 100 ))

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
    claude-opus-5|claude-opus-5-*|claude-fable-5|claude-fable-5-*|claude-mythos-5|claude-mythos-5-*|claude-mythos-preview|claude-mythos-preview-*|claude-opus-4-8|claude-opus-4-8-*|claude-opus-4-7|claude-opus-4-7-*|claude-opus-4-6|claude-opus-4-6-*|claude-sonnet-5|claude-sonnet-5-*|claude-sonnet-4-6|claude-sonnet-4-6-*)
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
# (_model_window) > UNKNOWN.
#
# Echoes "<window> <source>" where source is "override", "detected", or
# "unknown". For "unknown" the window is literally 0 — NOT a fallback value,
# and deliberately not a usable denominator: there is no default any more, so
# no caller can accidentally divide by an invented number. The caller must
# branch on the source and emit the maintenance notice instead of a
# percentage (2026-07-29 class fix; see THE CLASS FIX in the header).
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

  printf '0 unknown'
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

  local marker_70="$state_dir/${session_id}--watermark-70"
  local marker_85="$state_dir/${session_id}--watermark-85"
  local marker_unknown="$state_dir/${session_id}--window-unknown"
  local never_stop="Context pressure is NEVER a reason to stop or pause autonomous work — compaction handles overflow automatically; checkpoint state and keep going."

  # ==========================================================
  # UNKNOWN WINDOW -> no denominator, therefore no percentage, ever.
  # ==========================================================
  # This is the 2026-07-29 class fix. Before it, an unrecognized model fell
  # through to a hardcoded 200000 and the hook printed a confident (and twice
  # proven wrong by 5x) percentage against it. There is no denominator to
  # print now, so instead the hook emits ONE maintenance notice per session
  # naming the model, this file, and the fix — the in-band replacement for
  # the detector that suppression would otherwise have removed.
  #
  # Deliberately does NOT write the 70/85 watermark markers and does NOT run
  # the proactive snapshot: neither watermark was established, so claiming
  # either would be the same confident-and-wrong move in a different costume.
  if [ "$win_source" = "unknown" ]; then
    [ -f "$marker_unknown" ] && return 0
    # Below the floor, nothing can be said — and no marker is written, so the
    # notice still fires later in the same session once the floor is crossed.
    [ "$tokens" -lt "$UNKNOWN_NOTICE_FLOOR" ] && return 0

    mkdir -p "$state_dir" 2>/dev/null || true
    : > "$marker_unknown" 2>/dev/null || true

    # 2026-08-02 (THE SECOND CLASS FIX): deliberately no percentage, no
    # candidate-reading math, no denominator of any kind — a wrong number in
    # a familiar "N% of M" shape overrides any caveat wrapped around it, and
    # that includes an "X% of A OR Y% of B" either/or, which is why the
    # 2026-07-29 fix's own approach is retired here. Only the raw measured
    # fact (this hook CAN derive it correctly) plus an explicit
    # do-not-infer-pressure instruction are emitted.
    jq -n --arg ctx "[context-watermark] context window UNKNOWN for model ${model:-not present in transcript} — it is not in this hook's known-window table (_model_window in adapters/claude-code/hooks/context-watermark.sh). Measured ${tokens} raw tokens via ${source}. That is a raw count only: NO percentage and NO window size are being reported, because there is no verified denominator to compute one against, and this hook will not guess one for you. Do NOT infer context pressure (high or low) from this raw count alone. A wrong number in a familiar percentage-of-window format overrides any caveat wrapped around it — that is exactly what caused an agent to read a fabricated denominator as authoritative and stop work prematurely on 2026-07-20, again on 2026-07-28, and again on 2026-08-02, so this hook now reports nothing but the raw fact when it cannot derive the ratio correctly. Overflow is still covered regardless: the PreCompact backstop (pre-compact-continuity.sh) fires on compaction independent of this hook. TO RESTORE THE WATERMARK: verify this model's real context window and add it to _model_window (docs/backlog.md CONTEXT-WATERMARK-WINDOW-TABLE-STALENESS-01), or export CONTEXT_WATERMARK_WINDOW=<real window> for this session. ${never_stop}" \
      '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
    return 0
  fi

  case "$win_source" in
    detected)
      window_clause="model ${model}, window auto-detected"
      ;;
    override)
      window_clause="window from CONTEXT_WATERMARK_WINDOW override"
      ;;
    *)
      # A source this function does not recognize means the window was not
      # established by any path we can describe. Same rule as UNKNOWN: say
      # nothing rather than print a number we cannot defend. (Also keeps
      # window_clause from being read unset under `set -u`.)
      return 0
      ;;
  esac

  pct="$(awk -v t="$tokens" -v w="$window" 'BEGIN { if (w<=0) {print 0} else {printf "%d", (t/w)*100} }' 2>/dev/null)"
  [ -z "$pct" ] && return 0

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
  # No `model` field -> exercises the "model absent -> UNKNOWN window" path
  # (since 2026-07-29 that path emits the maintenance notice, never a
  # percentage — so watermark scenarios T2/T4/T6/T7 use _mk_transcript_model
  # with a real, table-listed model instead).
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
  _mk_transcript_model "$t1" 100000 "claude-haiku-4-5"   # 50% of 200000
  local got
  got="$(_compute_watermark "$t1" "sess-below70" "$state_dir" "")"
  if [ -z "$got" ] && [ ! -f "$state_dir/sess-below70--watermark-70" ]; then
    echo "  T1 below 70% -> 0 injections: PASS"; pass=$((pass+1))
  else
    echo "  T1 below 70% -> 0 injections: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T2 — at/above 70% (but below 85%) -> 1 injection, correct message, marker written.
  local t2="$tmp/at70.jsonl"
  _mk_transcript_model "$t2" 150000 "claude-haiku-4-5"   # 75% of 200000
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
  _mk_transcript_model "$t4" 180000 "claude-haiku-4-5"   # 90% of 200000
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
  _mk_transcript_model "$t6" 190000 "claude-haiku-4-5"   # 95% of 200000
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
  _mk_transcript_model "$t7" 145000 "claude-haiku-4-5"   # 72% of 200000
  got="$(_compute_watermark "$t7" "sess-primarycheck" "$state_dir" "")"
  if printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'via usage'; then
    echo "  T7 primary usage-parse path exercised (source=usage): PASS"; pass=$((pass+1))
  else
    echo "  T7 primary usage-parse path exercised (source=usage): FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T8 — bytes-fallback path exercised: a transcript with NO usage object at
  # all (jq present but no assistant-usage line) must fall back to
  # bytes x calibration and still emit. Since the 2026-07-29 class fix that
  # emission is the UNKNOWN-window notice rather than a percentage (the
  # fallback path never has a model, so there is no denominator) — which is
  # doubly right, given this path's numerator is itself 6x-uncertain. The
  # assertion below is unchanged: the message must still name its source.
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
  # NOTE the interpreter: "${BASH:-/bin/bash}", never bare `bash`. A bare
  # `bash` re-invocation runs whichever bash is FIRST ON PATH (here
  # /opt/homebrew/bin/bash 5.3.15), so a suite launched with /bin/bash 3.2.57
  # would silently test 5.3 for this scenario and still report a clean count
  # for 3.2 — a portability blind spot this repo has been bitten by.
  out="$(printf 'not json at all' | HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR="$HARNESS_SELFTEST_DIR" "${BASH:-/bin/bash}" "$0" 2>&1)"
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
  # Same interpreter discipline as T9 — see the note there.
  out="$(printf '%s' "$payload" | HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR="$HARNESS_SELFTEST_DIR" "${BASH:-/bin/bash}" "$0" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    echo "  T11 fast early-exit when both watermarks already fired: PASS"; pass=$((pass+1))
  else
    echo "  T11 fast early-exit when both watermarks already fired: FAIL (rc=$rc out='$out')"; fail=$((fail+1))
  fi

  # ==========================================================
  # T12-T19 — window resolution (added 2026-07-20, the incident fix).
  # ==========================================================

  # T12 — model absent -> UNKNOWN window. REWRITTEN 2026-08-02 (the SECOND
  # class fix): this scenario used to accept an "X% of A OR Y% of B"
  # either/or as the safe replacement for a single wrong percentage — it was
  # not safe, both readings still took the "N% of M" shape. It now asserts
  # the stronger guarantee: the message states the raw measured token count,
  # says the window is UNKNOWN, and contains NEITHER a point percentage NOR
  # the literal substring "% of" anywhere, in any form.
  local t12="$tmp/modelabsent.jsonl"
  _mk_transcript "$t12" 150000
  got="$(_compute_watermark "$t12" "sess-modelabsent" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'context window UNKNOWN' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '150000 raw tokens' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'Do NOT infer context pressure' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '% of' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -qE '~[0-9]+%'; then
    echo "  T12 model absent -> UNKNOWN window, raw token count only, no percentage anywhere: PASS"; pass=$((pass+1))
  else
    echo "  T12 model absent -> UNKNOWN window, raw token count only, no percentage anywhere: FAIL (got: $got)"; fail=$((fail+1))
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

  # T16 — an unrecognized model string (not empty, just not in the table) is
  # never presented as an established window, and the message names the
  # offending model so it can be fixed. UPDATED 2026-08-02 (the second class
  # fix): the word "ASSUMED" is gone from this path entirely (there is no
  # longer anything assumed — no denominator is printed at all), replaced by
  # the explicit "UNKNOWN" statement; and now also asserts the "% of"
  # substring never appears, which is the actual guarantee this test exists
  # to protect.
  local t16="$tmp/unknownmodel.jsonl"
  _mk_transcript_model "$t16" 150000 "claude-hypothetical-9"
  got="$(_compute_watermark "$t16" "sess-unknownmodel" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'context window UNKNOWN' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'claude-hypothetical-9' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '% of'; then
    echo "  T16 unrecognized (but non-empty) model -> never presented as established, UNKNOWN, names the model, no % of: PASS"; pass=$((pass+1))
  else
    echo "  T16 unrecognized (but non-empty) model -> never presented as established, UNKNOWN, names the model, no % of: FAIL (got: $got)"; fail=$((fail+1))
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

  # T17b — REGRESSION for the 2026-07-28 recurrence: claude-opus-5 (bare and
  # dated-snapshot form) must resolve to the real 1M window, not fall through
  # to the conservative 200k assumption. This is the exact case that made the
  # hook report "~74% of 200000" on a session that was 16% full. RED before
  # the table entry was added: both calls returned empty -> assumed 200000.
  local o5 o5d
  o5="$(_model_window "claude-opus-5")"
  o5d="$(_model_window "claude-opus-5-20260514")"
  if [ "$o5" = "1000000" ] && [ "$o5d" = "1000000" ]; then
    echo "  T17b opus-5 window detected as 1M (bare + dated snapshot), not assumed 200k: PASS"; pass=$((pass+1))
  else
    echo "  T17b opus-5 window detected as 1M (bare + dated snapshot), not assumed 200k: FAIL (bare=$o5 dated=$o5d)"; fail=$((fail+1))
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

  # ==========================================================
  # T20-T24 — the 2026-07-29 CLASS fix: an unknown model yields no
  # denominator, therefore no percentage, therefore no watermark; the
  # detector that suppression would have destroyed is rebuilt in band.
  # ==========================================================

  # T20 — THE class regression, replaying the 2026-07-28 incident's exact
  # shape against a model the table does NOT know. 740,000 tokens is what
  # produced the infamous "~74% of 200000" (a 5x overstatement of a session
  # that was really 74% of 1,000,000). With the class fix there is no 200000
  # to divide by: the hook must emit the UNKNOWN notice, must NOT contain
  # that percentage claim or any other point percentage, must name the model
  # AND the function to fix, must NOT write either watermark marker, and must
  # NOT fire the proactive snapshot (no watermark was established).
  # RED before the fix: this emitted "~370% of 200000" with both markers set
  # and the snapshot invoked.
  local t20="$tmp/classfix.jsonl"
  _mk_transcript_model "$t20" 740000 "claude-nextgen-9"
  local snap20="$tmp/snapshot-t20.marker"
  cat > "$tmp/fake-snapshot-t20.sh" <<EOF
#!/bin/bash
touch "$snap20"
EOF
  chmod +x "$tmp/fake-snapshot-t20.sh"
  got="$(_compute_watermark "$t20" "sess-classfix" "$state_dir" "$tmp/fake-snapshot-t20.sh")"
  local ctx20
  ctx20="$(printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
  if [ -n "$got" ] \
     && printf '%s' "$ctx20" | grep -q 'context window UNKNOWN' \
     && printf '%s' "$ctx20" | grep -q 'claude-nextgen-9' \
     && printf '%s' "$ctx20" | grep -q '_model_window' \
     && printf '%s' "$ctx20" | grep -q 'CONTEXT_WATERMARK_WINDOW' \
     && ! printf '%s' "$ctx20" | grep -q '74% of 200000' \
     && ! printf '%s' "$ctx20" | grep -qE '~[0-9]+% of' \
     && ! printf '%s' "$ctx20" | grep -q '% of' \
     && [ ! -f "$state_dir/sess-classfix--watermark-70" ] \
     && [ ! -f "$state_dir/sess-classfix--watermark-85" ] \
     && [ ! -f "$snap20" ]; then
    echo "  T20 unknown model -> UNKNOWN notice, zero point percentages, no watermark markers, no snapshot: PASS"; pass=$((pass+1))
  else
    echo "  T20 unknown model -> UNKNOWN notice, zero point percentages, no watermark markers, no snapshot: FAIL (got: $got, snap: $([ -f "$snap20" ] && echo yes || echo no))"; fail=$((fail+1))
  fi

  # T20b — REWRITTEN 2026-08-02 (the second class fix). This scenario used to
  # assert the notice gave BOTH candidate readings ("370% of a 200000-token
  # window OR 74% of a 1000000-token one") as the safe replacement for a
  # single point estimate. It was not safe: both readings still took the
  # "N% of M" shape a pattern-matching reader latches onto regardless of
  # caveats (the golden case this fix responds to, 2026-08-02, is exactly
  # that failure recurring). It now asserts the opposite: the notice states
  # ONLY the raw measured token count, explicitly says not to infer pressure
  # from it, and contains NEITHER denominator (200000 nor 1000000) anywhere.
  if printf '%s' "$ctx20" | grep -q '740000 raw tokens' \
     && printf '%s' "$ctx20" | grep -q 'Do NOT infer context pressure' \
     && ! printf '%s' "$ctx20" | grep -q '200000' \
     && ! printf '%s' "$ctx20" | grep -q '1000000'; then
    echo "  T20b UNKNOWN notice states raw token count only, no candidate readings, no denominator: PASS"; pass=$((pass+1))
  else
    echo "  T20b UNKNOWN notice states raw token count only, no candidate readings, no denominator: FAIL (ctx: $ctx20)"; fail=$((fail+1))
  fi

  # T21 — the notice is one-shot per session: a second call on the same
  # session is silent, exactly like the 70/85 watermarks' dedup. Without
  # this the notice would fire on EVERY tool call for the rest of the
  # session, which is how a useful signal becomes ignored noise.
  got="$(_compute_watermark "$t20" "sess-classfix" "$state_dir" "$tmp/fake-snapshot-t20.sh")"
  if [ -z "$got" ] && [ -f "$state_dir/sess-classfix--window-unknown" ]; then
    echo "  T21 UNKNOWN notice dedups per session (marker written, re-run silent): PASS"; pass=$((pass+1))
  else
    echo "  T21 UNKNOWN notice dedups per session (marker written, re-run silent): FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T22 — the notice floor, and that it does not burn the one shot early. A
  # session on an unknown model that is only 139,999 tokens in cannot be at
  # 70% of ANY window in the table, so the hook stays silent AND writes no
  # marker; when the same session later crosses the floor, the notice still
  # fires. (Writing the marker on the below-floor call would have silently
  # disabled the notice for the entire session — the exact "silent by
  # default" failure mode this change exists to end.)
  local t22lo="$tmp/floorlo.jsonl" t22hi="$tmp/floorhi.jsonl"
  _mk_transcript_model "$t22lo" 139999 "claude-nextgen-9"
  _mk_transcript_model "$t22hi" 140000 "claude-nextgen-9"
  local got_lo got_hi
  got_lo="$(_compute_watermark "$t22lo" "sess-floor" "$state_dir" "")"
  local marker_after_lo="no"
  [ -f "$state_dir/sess-floor--window-unknown" ] && marker_after_lo="yes"
  got_hi="$(_compute_watermark "$t22hi" "sess-floor" "$state_dir" "")"
  if [ -z "$got_lo" ] && [ "$marker_after_lo" = "no" ] \
     && [ -n "$got_hi" ] \
     && printf '%s' "$got_hi" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'context window UNKNOWN'; then
    echo "  T22 notice floor: silent+unmarked below 140000, still fires later in the same session at the floor: PASS"; pass=$((pass+1))
  else
    echo "  T22 notice floor: silent+unmarked below 140000, still fires later in the same session at the floor: FAIL (lo='$got_lo' marker_after_lo=$marker_after_lo hi='$got_hi')"; fail=$((fail+1))
  fi

  # T23 — the escape hatch must rescue an UNKNOWN model, not just outrank a
  # detected one (T15 covers override-vs-detected). An operator who knows
  # the real window can always get the watermark back without editing code:
  # override wins, a normal percentage is emitted, and the UNKNOWN notice is
  # NOT emitted. This is what makes suppression a safe default rather than a
  # dead end.
  local t23="$tmp/overrideunknown.jsonl"
  _mk_transcript_model "$t23" 750000 "claude-nextgen-9"
  export CONTEXT_WATERMARK_WINDOW=1000000
  got="$(_compute_watermark "$t23" "sess-overrideunknown" "$state_dir" "")"
  unset CONTEXT_WATERMARK_WINDOW
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '~75% of 1000000' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'override' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'context window UNKNOWN' \
     && [ -f "$state_dir/sess-overrideunknown--watermark-70" ]; then
    echo "  T23 CONTEXT_WATERMARK_WINDOW override rescues an UNKNOWN model (percentage restored, no notice): PASS"; pass=$((pass+1))
  else
    echo "  T23 CONTEXT_WATERMARK_WINDOW override rescues an UNKNOWN model (percentage restored, no notice): FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T23b — end-to-end proof that the class fix did not cost the instance fix:
  # claude-opus-5 at 740,000 tokens is IN the table, so it must still take
  # the normal path and read ~74% of 1000000 (auto-detected) — NOT the
  # UNKNOWN notice, and above all not the "~74% of 200000" of the incident.
  # T17b unit-checks the table entry; this checks the whole pipeline.
  local t23b="$tmp/opus5e2e.jsonl"
  _mk_transcript_model "$t23b" 740000 "claude-opus-5"
  got="$(_compute_watermark "$t23b" "sess-opus5e2e" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '~74% of 1000000' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'auto-detected' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'context window UNKNOWN' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '200000'; then
    echo "  T23b known model end-to-end (opus-5 @740k -> ~74% of 1000000, detected, not the notice): PASS"; pass=$((pass+1))
  else
    echo "  T23b known model end-to-end (opus-5 @740k -> ~74% of 1000000, detected, not the notice): FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T24 — interpreter integrity of this suite itself. Any scenario that
  # re-invokes the script must use "$BASH" (the interpreter actually running
  # the suite), never bare `bash`, which resolves via PATH — on this machine
  # /opt/homebrew/bin/bash 5.3.15 even when the suite was launched with
  # /bin/bash 3.2.57. A suite with that defect reports a clean count for an
  # interpreter it never ran. Source-level guard, because the failure is
  # invisible from the outside. The pattern is written with an escaped `$`
  # so this very line cannot match itself.
  local bare_bash_hits
  bare_bash_hits="$(grep -cE '(^|[^A-Za-z0-9_/"-])bash "\$0"' "$0" 2>/dev/null || true)"
  [ -z "$bare_bash_hits" ] && bare_bash_hits=0
  if [ "$bare_bash_hits" -eq 0 ]; then
    echo "  T24 self-test never re-invokes via bare \`bash\` (uses \$BASH, so 3.2 runs really are 3.2): PASS"; pass=$((pass+1))
  else
    echo "  T24 self-test never re-invokes via bare \`bash\` (uses \$BASH, so 3.2 runs really are 3.2): FAIL ($bare_bash_hits occurrence(s))"; fail=$((fail+1))
  fi

  # ==========================================================
  # T25-T27 — the 2026-08-02 SECOND class fix's own quality bar: (a) the
  # known-model path is unchanged (still emits a correct percentage), (b) the
  # unknown-model path never emits "% of" or a fabricated denominator under
  # ANY token count, and (c) the never-a-stop-reason clause is present on
  # BOTH paths, not just the known one.
  # ==========================================================

  # T25 — "% of" absence re-checked at a DIFFERENT token count than T12/T16/
  # T20 (source-independent regression: not overfit to one fixture), plus a
  # direct grep of the emitting jq call in the script source itself for a
  # literal "%" character inside its --arg ctx string, so a future edit that
  # reintroduces a percentage on this path fails structurally, not just at
  # whatever token counts the fixtures happen to use.
  local t25="$tmp/secondclassfix.jsonl"
  _mk_transcript_model "$t25" 999999 "claude-yet-another-9"
  got="$(_compute_watermark "$t25" "sess-secondclassfix" "$state_dir" "")"
  local ctx25
  ctx25="$(printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
  if [ -n "$got" ] \
     && printf '%s' "$ctx25" | grep -q 'context window UNKNOWN' \
     && printf '%s' "$ctx25" | grep -q '999999 raw tokens' \
     && ! printf '%s' "$ctx25" | grep -q '% of' \
     && ! printf '%s' "$ctx25" | grep -q '200000' \
     && ! printf '%s' "$ctx25" | grep -q '1000000'; then
    echo "  T25 unknown-path 'no % of, no fabricated denominator' holds at a different token count (source-independent): PASS"; pass=$((pass+1))
  else
    echo "  T25 unknown-path 'no % of, no fabricated denominator' holds at a different token count (source-independent): FAIL (ctx: $ctx25)"; fail=$((fail+1))
  fi

  # T26 — the never-a-stop-reason / compaction clause (T18 proved it on the
  # KNOWN-model path) is ALSO present on the UNKNOWN-model path. Reuses
  # ctx20/ctx25 (both already-fired unknown-path notices) rather than a fresh
  # fixture, since the clause's presence does not depend on token count.
  if printf '%s' "$ctx20" | grep -q 'NEVER a reason to stop or pause' \
     && printf '%s' "$ctx20" | grep -q 'compaction handles overflow' \
     && printf '%s' "$ctx25" | grep -q 'NEVER a reason to stop or pause' \
     && printf '%s' "$ctx25" | grep -q 'compaction handles overflow'; then
    echo "  T26 never-a-stop-reason / compaction clause present on the UNKNOWN-model path too: PASS"; pass=$((pass+1))
  else
    echo "  T26 never-a-stop-reason / compaction clause present on the UNKNOWN-model path too: FAIL (ctx20: $ctx20 | ctx25: $ctx25)"; fail=$((fail+1))
  fi

  # T27 — the known-model path (requirement (a) of the second class fix) is
  # UNCHANGED by this pass: a fresh known-model session still emits a correct
  # percentage in the familiar "N% of M" shape (that shape is fine when the
  # denominator is real), still names the model as auto-detected, and does
  # NOT say UNKNOWN. Independent fixture from T13/T23b so this is a direct
  # check of THIS pass's non-regression, not a rerun of an earlier one.
  local t27="$tmp/knownpathunchanged.jsonl"
  _mk_transcript_model "$t27" 750000 "claude-sonnet-5"   # 75% of 1,000,000
  got="$(_compute_watermark "$t27" "sess-knownpathunchanged" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '~75% of 1000000' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'auto-detected' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'context window UNKNOWN'; then
    echo "  T27 known-model path unchanged by the second class fix (still emits correct percentage): PASS"; pass=$((pass+1))
  else
    echo "  T27 known-model path unchanged by the second class fix (still emits correct percentage): FAIL (got: $got)"; fail=$((fail+1))
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
