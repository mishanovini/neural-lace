#!/bin/bash
# pre-compact-continuity.sh — PreCompact hook (matchers: auto + manual), Wave E
# task E.9b.
#
# WHY THIS EXISTS: E.9a (context-watermark.sh) is the early warning while the
# model still has room to act; this hook is the BACKSTOP for when discipline
# slipped anyway and compaction is happening RIGHT NOW. It (1) runs the
# mechanical, zero-token session-snapshot script so the exact execution state
# survives compaction regardless of what the summary keeps, and (2) emits
# summarizer instructions naming ALL SIX normative preserve-list categories
# EXPLICITLY, by their verbatim plan-task names, in priority order.
#
# ============================================================
# MECHANISM PIN (constitution §1 — no unverified mechanism claims)
# ============================================================
# The spec requires empirically verifying which PreCompact emission channel
# actually reaches the summarizer on THIS Claude Code version (2.1.197,
# confirmed via a live transcript on this machine) before relying on it.
#
# ATTEMPTED VERIFICATION: this builder is NOT the orchestrator — wiring this
# hook into settings.json.template (and therefore triggering a REAL PreCompact
# event through the live hook chain) is explicitly out of scope for this task
# (§E.0.1: template wiring is orchestrator-only, lands at §E.W). A live probe
# analogous to the C.2 doctrine-jit precedent (which used a disposable
# sub-agent session performing a real Edit/Write to trigger PostToolUse) has
# no equivalent cheap form here: PreCompact fires only on an ACTUAL compaction
# (auto-triggered near the real context limit, or the manual `/compact`
# command), and this machine has no standalone `claude -p` CLI (desktop-host-
# managed auth only — same constraint C.2's probe notes recorded). Triggering
# a real compaction against THIS build session to test the channel would risk
# destroying this session's own context mid-build for an unrelated task's
# benefit — not a proportionate probe cost, and not reversible if it goes
# wrong (constitution §8: pause only for genuine irreversibility — this
# qualifies, and the correct response to an irreversible probe cost is to NOT
# take it and instead build the documented-safe fallback).
#
# THEREFORE, per the spec's own fallback clause ("If NO honored channel
# exists, the fallback IS the design"): this hook EMITS THROUGH BOTH candidate
# channels (belt-and-suspenders — emitting extra text through an channel that
# turns out to be unhonored costs nothing) AND treats the snapshot-file +
# existing SessionStart echo path as the RELIED-UPON mechanism, because that
# other half is independently PROVEN already-live (see below) rather than
# theorized:
#
#   (a) plain stdout — HYPOTHESIZED to reach the summarizer's context on
#       PreCompact specifically (unverified this version; Claude Code's
#       general hook-output convention makes stdout visible in the
#       transcript, but whether the COMPACTION SUMMARIZER step itself reads
#       PreCompact stdout as an instruction, vs. it being purely a
#       transcript/log artifact, is NOT verified here).
#   (b) hookSpecificOutput.additionalContext — HYPOTHESIZED for the same
#       reason; this is the sanctioned channel for PostToolUse/UserPromptSubmit
#       (doctrine-jit.sh, gh-account-blindness-hint.sh — both C.2-probe-
#       PROVEN for THOSE events), but PreCompact's own additionalContext
#       consumption is not independently probed by this builder.
#   (c) snapshot file + existing SessionStart `matcher: "compact"` echo — this
#       IS PROVEN already live in this repo: `settings.json.template` line
#       ~456 wires a SessionStart hook on `matcher: "compact"` (fires on
#       exactly the post-compaction resume) that echoes plain stdout
#       instructing the model to read SCRATCHPAD.md / the ACTIVE plan / the
#       backlog — SessionStart stdout-as-context IS the established, working
#       mechanism this harness already depends on for post-compact recovery
#       (this is a DIFFERENT, downstream hook event from PreCompact itself,
#       which is exactly why it survives being the reliable half: it fires
#       fresh, after compaction completes, independent of whether anything
#       PreCompact-side was honored). This hook's session-snapshot.sh write
#       is the file that recovery path should be pointed at next (see the
#       "orchestrator TODO" note below) so the ALREADY-WORKING echo picks up
#       the SIX-CATEGORY instructions and mechanical state THIS hook wrote,
#       not just SCRATCHPAD/plan/backlog as it does today.
#
# honest_status (mirrored verbatim in this task's manifest-entry.json
# fragment): "PreCompact additionalContext/stdout channel HYPOTHESIZED
# (unverified this Claude Code version — no cheap live-probe form available
# to a non-orchestrator builder); snapshot-file + SessionStart compact-recovery
# echo (chain #1, already wired) is PROVEN as the reliable fallback surface.
# Orchestrator TODO at §E.W: extend the existing SessionStart `matcher:
# "compact"` echo to also read back this hook's session-handoff snapshot file
# and its six-category instructions, closing the loop even if (a)/(b) are
# refuted by a future live probe."
#
# ============================================================
# Behavior
# ============================================================
# 1. Read PreCompact JSON from stdin (`transcript_path`, `session_id`,
#    `trigger` — "auto" or "manual"). Missing/malformed -> exit 0 silently
#    (informational hook; PreCompact firing is not something to ever block).
# 2. Run scripts/session-snapshot.sh <transcript_path> — mechanical,
#    zero-token. The instructions below are written at the TOP of that same
#    snapshot file (the (c) fallback-is-the-design half) in addition to being
#    emitted through (a)/(b).
# 3. Emit the six-category summarizer instructions through both (a) stdout
#    and (b) hookSpecificOutput.additionalContext.
# 4. ALWAYS exit 0.
#
# Self-test: per-category grep (all six category names present in the
# emitted instruction string), fires on both auto+manual matchers (this hook
# does not itself branch on trigger value — it behaves identically for both,
# which the self-test asserts directly), snapshot file exists + contains the
# instructions block at its top + the mechanical members of categories 3/5.

set -u

SCRIPT_NAME="pre-compact-continuity.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/nl-paths.sh
if [ -f "$SCRIPT_DIR/lib/nl-paths.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/nl-paths.sh" 2>/dev/null || true
fi
# shellcheck source=lib/signal-ledger.sh
if [ -f "$SCRIPT_DIR/lib/signal-ledger.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/signal-ledger.sh" 2>/dev/null || true
fi

_SNAPSHOT_SCRIPT_DEFAULT="$SCRIPT_DIR/../scripts/session-snapshot.sh"

_state_dir() {
  if [ "${HARNESS_SELFTEST:-0}" = "1" ] && [ -n "${HARNESS_SELFTEST_DIR:-}" ]; then
    printf '%s/state/session-handoff' "$HARNESS_SELFTEST_DIR"
    return 0
  fi
  printf '%s/.claude/state/session-handoff' "$HOME"
}

# The six NORMATIVE preserve-list categories, VERBATIM per the plan
# (docs/plans/nl-overhaul-program-2026-07.md, E.9 task row) and specs-e §E.9,
# priority order. Kept as a single function so both the live path and the
# self-test build the identical string (no drift between what fires and what
# is tested).
_six_category_instructions() {
  cat <<'CATEGORIES'
COMPACTION IS HAPPENING NOW. The summary you are about to produce MUST preserve
the following SIX categories, in this priority order (NORMATIVE preserve-list,
NL Overhaul Program E.9 — dropping any of these is a compaction defect, not an
acceptable trade-off):

(1) operator directives given this session, verbatim intent — do not paraphrase
    away the operator's own words where they set scope, priority, or a hard
    constraint.
(2) decisions made + rationale — every decision taken this session and WHY,
    not just the outcome.
(3) exact execution state — branch/HEAD, committed-vs-uncommitted, in-flight
    background work with report-back ids, and the specific next action. (A
    mechanical snapshot of this category has been written to a session-handoff
    file — see below — read it back; do not reconstruct it from memory alone.)
(4) hard-learned constraints/lessons — anything discovered the hard way this
    session that would otherwise be relearned at cost.
(5) pending asks in BOTH directions — awaiting-operator (open questions,
    decisions posed) AND operator-awaiting (things the operator asked of you
    that are still outstanding).
(6) verified-vs-claimed status per work item — do not upgrade a claimed state
    to a verified one during summarization; keep the distinction.
CATEGORIES
}

# ============================================================
# Core (used by both live path and self-test)
#
# Args: $1 = transcript path, $2 = session_id, $3 = snapshot_script path,
#       $4 = trigger ("auto"/"manual"/empty)
# Side effect: runs the snapshot script (writing/prepending instructions to
# its output file). Prints the combined stdout+JSON emission (both channels)
# to stdout, for the self-test / caller to inspect. Always returns 0.
# ============================================================
_run_precompact() {
  local transcript="$1" session_id="$2" snapshot_script="$3" trigger="${4:-}"

  # ---- WAVE-O O.1 EMIT: session-compact (contract C2) --------------------
  # ONE marked lifecycle-event emit call, per specs-o §O.1 deliverable 2.
  # Never blocks: ledger_emit's own contract; guarded by command -v so a
  # tree where signal-ledger.sh failed to source is still a silent no-op.
  if command -v ledger_emit >/dev/null 2>&1; then
    ledger_emit "pre-compact-continuity" "session-compact" "trigger=${trigger:-unknown}"
  fi
  # ---- END WAVE-O O.1 EMIT -------------------------------------------------

  local instructions header body
  instructions="$(_six_category_instructions)"
  header="[pre-compact-continuity] trigger=${trigger:-unknown} session=${session_id:-unknown}"

  # (2) Mechanical snapshot — pure shell, zero model tokens.
  local snapshot_path=""
  if [ -n "$snapshot_script" ] && [ -f "$snapshot_script" ] && [ -n "$transcript" ]; then
    bash "$snapshot_script" "$transcript" >/dev/null 2>&1 || true
    if [ -n "$session_id" ]; then
      snapshot_path="$(_state_dir)/${session_id}.md"
    fi
  fi

  # Fallback-is-the-design half (c): prepend the instructions block at the
  # TOP of the snapshot file itself, so the existing SessionStart
  # `matcher: "compact"` echo (which already tells the resumed session to
  # read SCRATCHPAD.md / the plan / the backlog) has this file available with
  # the six-category instructions sitting at its head, independent of whether
  # channels (a)/(b) below are ever honored by the PreCompact summarizer.
  if [ -n "$snapshot_path" ] && [ -f "$snapshot_path" ]; then
    local tmp_prepend
    tmp_prepend="$(mktemp 2>/dev/null || printf '%s.tmp' "$snapshot_path")"
    {
      echo "<!-- pre-compact-continuity: summarizer instructions (six-category preserve-list) -->"
      echo ""
      printf '%s\n' "$instructions"
      echo ""
      echo "---"
      echo ""
      cat "$snapshot_path"
    } > "$tmp_prepend" 2>/dev/null && mv "$tmp_prepend" "$snapshot_path" 2>/dev/null || true
  fi

  # (a) stdout — HYPOTHESIZED channel for this event; see MECHANISM PIN above.
  echo "$header"
  echo ""
  printf '%s\n' "$instructions"
  if [ -n "$snapshot_path" ]; then
    echo ""
    echo "Mechanical session-handoff snapshot written to: ${snapshot_path}"
  fi

  # (b) hookSpecificOutput.additionalContext — HYPOTHESIZED channel for this
  # event; see MECHANISM PIN above. Emitted as a second, independent form so
  # whichever channel this Claude Code version actually honors gets it.
  if command -v jq >/dev/null 2>&1; then
    local ctx
    ctx="$(printf '%s\n\n%s' "$header" "$instructions")"
    if [ -n "$snapshot_path" ]; then
      ctx="$(printf '%s\n\nMechanical session-handoff snapshot written to: %s' "$ctx" "$snapshot_path")"
    fi
    jq -n --arg ctx "$ctx" \
      '{hookSpecificOutput:{hookEventName:"PreCompact", additionalContext:$ctx}}'
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

  local transcript session_id trigger
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  trigger="$(printf '%s' "$input" | jq -r '.trigger // empty' 2>/dev/null)"

  _run_precompact "$transcript" "$session_id" "$_SNAPSHOT_SCRIPT_DEFAULT" "$trigger"
  exit 0
}

# ============================================================
# Self-test
# ============================================================
_self_test() {
  local pass=0 fail=0
  local tmp
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t precompact)"

  export HARNESS_SELFTEST=1
  export HARNESS_SELFTEST_DIR="$tmp/sandbox"
  mkdir -p "$HARNESS_SELFTEST_DIR"

  local transcript="$tmp/sess-fixture.jsonl"
  printf '{"type":"user","session_id":"sess-pc-1","message":{"role":"user","content":"hi"}}\n' > "$transcript"
  printf '{"type":"assistant","session_id":"sess-pc-1","message":{"role":"assistant","usage":{"input_tokens":2,"cache_read_input_tokens":100}}}\n' >> "$transcript"

  # Use the REAL session-snapshot.sh (already built this task) as the
  # snapshot script under test, but pointed at a fixture repo so its output
  # is deterministic and its categories 3/5 mechanical members are populated.
  local snapshot_script="$SCRIPT_DIR/../scripts/session-snapshot.sh"

  local repo="$tmp/fixture-repo"
  mkdir -p "$repo/docs/plans"
  ( cd "$repo" && git init -q . && git config core.hooksPath "" && git config user.email "t@example.test" && git config user.name "T" \
      && echo hi > README.md && git add README.md && git commit -q -m init ) >/dev/null 2>&1
  cat > "$repo/docs/plans/fixture-plan.md" <<'PLAN'
Status: ACTIVE

- [ ] Task A
PLAN
  cat > "$repo/NEEDS-YOU.md" <<'NY'
## Awaiting your decision
- fixture pending item
NY
  export SESSION_SNAPSHOT_MAIN_ROOT="$repo"

  # T1 — auto matcher: per-category grep, all six category names present.
  local out
  out="$(_run_precompact "$transcript" "sess-pc-1" "$snapshot_script" "auto")"
  local cat_ok=1
  for label in \
    "operator directives given this session" \
    "decisions made + rationale" \
    "exact execution state" \
    "hard-learned constraints/lessons" \
    "pending asks in BOTH directions" \
    "verified-vs-claimed status per work item"; do
    if ! printf '%s' "$out" | grep -qF "$label"; then
      cat_ok=0
      echo "    missing category label: $label"
    fi
  done
  if [ "$cat_ok" -eq 1 ]; then
    echo "  T1 all six category names present (auto trigger): PASS"; pass=$((pass+1))
  else
    echo "  T1 all six category names present (auto trigger): FAIL"; fail=$((fail+1))
  fi

  # T2 — manual matcher: identical category coverage (hook does not
  # discriminate on trigger value for the instruction content). Uses its OWN
  # fixture transcript (distinct session_id embedded) so session-snapshot.sh's
  # content-derived session-id agrees with the session_id argument passed
  # here — otherwise it would silently overwrite T1's sess-pc-1.md instead of
  # writing sess-pc-2.md (session-snapshot.sh derives its id from the
  # transcript's OWN session_id field, not from its caller's argument, by
  # design — see session-snapshot.sh's header).
  local transcript2="$tmp/sess-fixture-2.jsonl"
  printf '{"type":"user","session_id":"sess-pc-2","message":{"role":"user","content":"hi"}}\n' > "$transcript2"
  printf '{"type":"assistant","session_id":"sess-pc-2","message":{"role":"assistant","usage":{"input_tokens":2,"cache_read_input_tokens":100}}}\n' >> "$transcript2"
  out="$(_run_precompact "$transcript2" "sess-pc-2" "$snapshot_script" "manual")"
  cat_ok=1
  for label in \
    "operator directives given this session" \
    "decisions made + rationale" \
    "exact execution state" \
    "hard-learned constraints/lessons" \
    "pending asks in BOTH directions" \
    "verified-vs-claimed status per work item"; do
    printf '%s' "$out" | grep -qF "$label" || cat_ok=0
  done
  if [ "$cat_ok" -eq 1 ]; then
    echo "  T2 all six category names present (manual trigger): PASS"; pass=$((pass+1))
  else
    echo "  T2 all six category names present (manual trigger): FAIL"; fail=$((fail+1))
  fi

  # T3 — snapshot file exists after the run.
  local snap_path
  snap_path="$(_state_dir)/sess-pc-1.md"
  if [ -f "$snap_path" ]; then
    echo "  T3 snapshot file exists after PreCompact run: PASS"; pass=$((pass+1))
  else
    echo "  T3 snapshot file exists after PreCompact run: FAIL (expected $snap_path)"; fail=$((fail+1))
  fi

  # T4 — snapshot file contains the mechanical members of category 3 (git
  # branch/HEAD/status) from the fixture session.
  if grep -q '^- Branch:' "$snap_path" && grep -q '^- HEAD:' "$snap_path"; then
    echo "  T4 snapshot contains category-3 mechanical members: PASS"; pass=$((pass+1))
  else
    echo "  T4 snapshot contains category-3 mechanical members: FAIL"; fail=$((fail+1))
  fi

  # T5 — snapshot file contains the mechanical members of category 5
  # (pending NEEDS-YOU content) from the fixture session.
  if grep -q 'fixture pending item' "$snap_path"; then
    echo "  T5 snapshot contains category-5 mechanical members: PASS"; pass=$((pass+1))
  else
    echo "  T5 snapshot contains category-5 mechanical members: FAIL"; fail=$((fail+1))
  fi

  # T6 — instructions are embedded at the TOP of the snapshot file (the
  # fallback-is-the-design (c) channel), so even if (a)/(b) are refuted, the
  # existing SessionStart compact-recovery echo pointed at this file would
  # see them first.
  local first_line
  first_line="$(head -1 "$snap_path")"
  if printf '%s' "$first_line" | grep -q 'pre-compact-continuity: summarizer instructions'; then
    echo "  T6 instructions embedded at TOP of snapshot file: PASS"; pass=$((pass+1))
  else
    echo "  T6 instructions embedded at TOP of snapshot file: FAIL (first line: $first_line)"; fail=$((fail+1))
  fi

  # T7 — idempotent: running PreCompact twice for the SAME session does not
  # duplicate the instructions block (re-run overwrites via session-snapshot's
  # own idempotency + this hook re-prepending once per run onto the FRESH
  # snapshot, not onto an already-prepended one).
  _run_precompact "$transcript" "sess-pc-1" "$snapshot_script" "auto" >/dev/null
  local header_count
  header_count="$(grep -c 'pre-compact-continuity: summarizer instructions' "$snap_path")"
  if [ "$header_count" -eq 1 ]; then
    echo "  T7 idempotent re-run (no duplicate instruction block): PASS"; pass=$((pass+1))
  else
    echo "  T7 idempotent re-run (no duplicate instruction block): FAIL (header_count=$header_count)"; fail=$((fail+1))
  fi

  # T8 — hookSpecificOutput.additionalContext (channel b) is valid JSON and
  # carries hookEventName PreCompact. jq -n pretty-prints multi-line, so
  # extract from the LAST line beginning with "{" through end-of-output
  # (the JSON blob is always the final thing _run_precompact emits).
  local json_blob
  json_blob="$(printf '%s' "$out" | awk '/^\{$/{p=1} p{print}')"
  if [ -n "$json_blob" ] && printf '%s' "$json_blob" | jq -e . >/dev/null 2>&1 \
     && printf '%s' "$json_blob" | jq -r '.hookSpecificOutput.hookEventName' | grep -q '^PreCompact$'; then
    echo "  T8 channel (b) additionalContext valid JSON, correct hookEventName: PASS"; pass=$((pass+1))
  else
    echo "  T8 channel (b) additionalContext valid JSON, correct hookEventName: FAIL (json_blob: $json_blob)"; fail=$((fail+1))
  fi

  # T9 — malformed stdin at the live-entry layer -> exit 0.
  local rc live_out
  live_out="$(printf 'not json' | HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR="$HARNESS_SELFTEST_DIR" bash "$0" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$live_out" ]; then
    echo "  T9 malformed stdin -> exit 0 silent: PASS"; pass=$((pass+1))
  else
    echo "  T9 malformed stdin -> exit 0 silent: FAIL (rc=$rc out='$live_out')"; fail=$((fail+1))
  fi

  # T10 — markers/snapshot sandboxed under HARNESS_SELFTEST_DIR.
  if [[ "$snap_path" == "$HARNESS_SELFTEST_DIR"* ]]; then
    echo "  T10 snapshot output sandboxed under HARNESS_SELFTEST_DIR: PASS"; pass=$((pass+1))
  else
    echo "  T10 snapshot output sandboxed under HARNESS_SELFTEST_DIR: FAIL (path=$snap_path)"; fail=$((fail+1))
  fi

  # T11 (Wave O task O.1, contract C2): _run_precompact emits exactly one
  # session-compact ledger event per invocation, carrying the trigger value
  # in its detail. Sandboxed via SIGNAL_LEDGER_PATH per signal-ledger.sh's
  # own contract (never touches the real machine ledger).
  local t11_ledger="$tmp/t11-ledger.jsonl"
  ( export SIGNAL_LEDGER_PATH="$t11_ledger"; \
    _run_precompact "$transcript" "sess-pc-1" "$snapshot_script" "auto" >/dev/null )
  if [[ -f "$t11_ledger" ]] && grep -q '"gate":"pre-compact-continuity".*"event":"session-compact"' "$t11_ledger" 2>/dev/null; then
    echo "  T11 session-compact ledger event emitted (contract C2): PASS"; pass=$((pass+1))
  else
    echo "  T11 session-compact ledger event emitted (contract C2): FAIL (expected a pre-compact-continuity/session-compact line in $t11_ledger)"; fail=$((fail+1))
  fi
  if grep -q 'trigger=auto' "$t11_ledger" 2>/dev/null; then
    echo "  T11b session-compact detail carries the trigger value: PASS"; pass=$((pass+1))
  else
    echo "  T11b session-compact detail carries the trigger value: FAIL"; fail=$((fail+1))
  fi
  local t11_count
  t11_count=$(grep -c '"event":"session-compact"' "$t11_ledger" 2>/dev/null | tr -d ' ')
  [[ -z "$t11_count" ]] && t11_count=0
  if [[ "$t11_count" == "1" ]]; then
    echo "  T11c exactly one session-compact event per invocation: PASS"; pass=$((pass+1))
  else
    echo "  T11c exactly one session-compact event per invocation: FAIL (got $t11_count)"; fail=$((fail+1))
  fi

  # T12 (Wave O task O.1, specs-o §O.0.1 rule 4 — flagless-shape mandate):
  # invokes the REAL PreCompact entry path (bash "$0", stdin JSON, no CLI
  # flags — the exact production invocation shape a live PreCompact event
  # gives this hook) with only env-var sandboxing (HARNESS_SELFTEST_DIR +
  # SIGNAL_LEDGER_PATH), and asserts the session-compact ledger event lands
  # via that real subprocess path (not merely via the internal
  # _run_precompact function call T1-T11 above use).
  local t12_ledger="$tmp/t12-ledger.jsonl"
  local t12_transcript="$tmp/sess-fixture-t12.jsonl"
  printf '{"type":"user","session_id":"sess-pc-t12","message":{"role":"user","content":"hi"}}\n' > "$t12_transcript"
  printf '%s\n' "$(printf '{"transcript_path":"%s","session_id":"sess-pc-t12","trigger":"auto"}' "$t12_transcript")" \
    | HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR="$HARNESS_SELFTEST_DIR" SIGNAL_LEDGER_PATH="$t12_ledger" bash "$0" >/dev/null 2>&1
  if [[ -f "$t12_ledger" ]] && grep -q '"gate":"pre-compact-continuity".*"event":"session-compact"' "$t12_ledger" 2>/dev/null; then
    echo "  T12 real flagless PreCompact invocation emits session-compact: PASS"; pass=$((pass+1))
  else
    echo "  T12 real flagless PreCompact invocation emits session-compact: FAIL (expected a line in $t12_ledger)"; fail=$((fail+1))
  fi

  unset SESSION_SNAPSHOT_MAIN_ROOT
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
pre-compact-continuity.sh — PreCompact backstop (Wave E E.9b).

  pre-compact-continuity.sh        Read JSON on stdin (transcript_path,
                                    session_id, trigger), run the mechanical
                                    snapshot script, emit six-category
                                    summarizer instructions via stdout +
                                    hookSpecificOutput.additionalContext (both
                                    channels — see MECHANISM PIN header note)
                                    and prepend them to the snapshot file.
  pre-compact-continuity.sh --self-test   Run self-test suite.
USAGE
    exit 2
    ;;
  "") _run_live ;;
  *)
    echo "pre-compact-continuity.sh: unknown argument '$1'" >&2
    exit 2
    ;;
esac
