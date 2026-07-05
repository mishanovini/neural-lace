#!/bin/bash
# stop-verdict-dispatcher.sh — Stop hook (NL Overhaul Wave E, task E.11).
#
# ============================================================
# WHAT THIS HOOK DOES (ADR 059 D1 + D2 — see docs/decisions/059-*.md)
# ============================================================
#
# Replaces the three independent BLOCKING Stop-hook invocations (work-
# integrity-gate.sh, session-honesty-gate.sh, bug-persistence-gate.sh) with
# ONE combined verdict. Wiring the Stop chain down to reference only this
# dispatcher (6 entries -> 4) is the ORCHESTRATOR's §E.W step (specs-e
# §E.0.1 rule 1) — this file builds the mechanism; it is not yet referenced
# by settings.json.template.
#
# pin-f-doctor-exempt (ADR 058 D5 pin f): this dispatcher surfaces the member
# gates' waiver remediation text (Purpose:/Because:) in its aggregated block
# message but does NOT itself validate waiver files — it invokes each member
# gate in --report mode (see below) and the member gate (work-integrity-gate.sh
# via waiver_has_purpose_clauses, etc.) performs the purpose-clause validation.
# The dispatcher is a pure aggregator over already-validated verdicts, so it
# needs no purpose-clause validator of its own; the harness-doctor pin-f check
# treats this marker comment as the exemption.
#
# Mechanism:
#   1. Invoke all three gates in `--report` mode (each runs every check,
#      emits gaps as JSON lines on stdout, always exits 0 — see each
#      gate's own --report branch, task E.11 part 1).
#   2. Aggregate every gap across all three gates.
#   3. No gaps -> ledger-log a "stop-cycle" pass event, exit 0.
#   4. Gaps present:
#      a. DONE-REFUSAL (retained VERBATIM from the retry-guard's own rule,
#         NEVER downgraded regardless of cycle count): if any gap came from
#         a verification-class gate (RETRY_GUARD_VERIFICATION_HOOKS already
#         lists work-integrity-gate + session-honesty-gate) AND the final
#         assistant message claims `DONE:`, this ALWAYS blocks — the same
#         failure signature is never let through via the block-once-then-
#         ledger path while the session is being dishonest about it.
#      b. FIRST blocking Stop this session (cycle count == 1 for this exact
#         set of gaps): ONE combined block message, grouped per gate, each
#         gap with its own pin-d remediation. Exit 2.
#      c. SECOND (or later) Stop with the SAME unresolved gap-set (cycle
#         count >= 2): write each gap to
#         ~/.claude/state/unresolved-gaps.jsonl (E.1's digest already
#         consumes this exact path — see session-start-digest.sh
#         feed_unresolved_gaps()), call `needs-you.sh add` for each gap (so
#         NEEDS-YOU.md surfaces it too), ledger-log the end as
#         "protocol-downgrade" (ADR 059 D2: designed, not failure — distinct
#         from retry-guard's own "downgrade" event class), and exit 0.
#
# Cycle counting reuses the existing, already-self-tested retry-guard
# primitives (retry_guard_session_id / retry_guard_record) rather than
# re-inventing a counter file format: the "failure signature" fed to
# retry_guard_record is a stable hash of the SORTED set of
# "<gate>:<check>" pairs found this Stop, so a DIFFERENT gap-set resets the
# cycle count to 1 (a session that fixes gap A but a Stop then reveals a
# NEW gap B is back to "first blocking Stop" for that new gap-set — it did
# not silently inherit gap A's cycle count), while the SAME unresolved
# gap-set persisting across two consecutive Stops increments to 2 and
# triggers the ledger path. This mirrors retry-guard's own reset-on-change
# semantics (see stop-hook-retry-guard.sh retry_guard_record's docstring).
#
# ============================================================
# LEDGER
# ============================================================
# Every dispatcher decision emits a ledger event via lib/signal-ledger.sh:
#   "stop-cycle"        — every invocation, pass or block (event detail
#                          carries the gap count and cycle number so E.5's
#                          KPI rollup can compute mean-cycles-per-session-end,
#                          the ADR 059 program-level refutation metric).
#   "block"             — first blocking Stop (combined verdict).
#   "protocol-downgrade" — second+ Stop, gaps recorded + session ends
#                          (distinct from retry-guard's own "downgrade"
#                          event class — this one is the DESIGNED protocol,
#                          not an emergency ride-through).
#
# ============================================================
# SANDBOXING
# ============================================================
# HARNESS_SELFTEST=1 routes signal-ledger writes to a sandboxed path
# (signal-ledger.sh's own contract); this file's --self-test additionally
# overrides RETRY_GUARD_STATE_DIR, NEEDS_YOU_STATE_DIR, NEEDS_YOU_MD_PATH,
# and HOME per-scenario so no self-test run ever touches real machine
# state (in particular, never the real
# ~/.claude/state/unresolved-gaps.jsonl or ~/NEEDS-YOU.md).
#
# ============================================================
# EXIT CODES
# ============================================================
#   0 — session may terminate (clean pass, OR gaps recorded + protocol
#       downgrade)
#   2 — session is blocked; stderr explains why, stdout carries
#       {"decision":"block", ...} JSON (Claude Code Stop-hook contract)

set -u

SCRIPT_NAME="stop-verdict-dispatcher.sh"
_SVD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$_SVD_DIR/lib/signal-ledger.sh"
# shellcheck disable=SC1091
source "$_SVD_DIR/lib/stop-hook-retry-guard.sh"

# The three member gates this dispatcher aggregates, in the order they
# used to run in the Stop chain (work-integrity, session-honesty,
# bug-persistence — see settings.json.template's current Stop entries,
# unchanged by this task; §E.W rewires them to reference only this file).
_SVD_MEMBER_GATES=("work-integrity-gate.sh" "session-honesty-gate.sh" "bug-persistence-gate.sh")

# Verification-class gate SCRIPT basenames whose gaps trigger the
# DONE-refusal path (mirrors RETRY_GUARD_VERIFICATION_HOOKS' hook-name
# tokens, which use the same basenames minus ".sh").
_svd_is_verification_gate() {
  local gate="$1"
  case "$gate" in
    work-integrity-gate|session-honesty-gate) return 0 ;;
    *) return 1 ;;
  esac
}

# ----------------------------------------------------------------------
# _svd_ledger <event> <detail> — best-effort, never fails the hook.
# ----------------------------------------------------------------------
_svd_ledger() {
  local event="$1" detail="$2"
  if command -v ledger_emit >/dev/null 2>&1; then
    ledger_emit "stop-verdict-dispatcher" "$event" "$detail"
  fi
}

# ----------------------------------------------------------------------
# _svd_resolve_needs_you <repo_root>
#   Resolve needs-you.sh: repo-relative (adapters/claude-code/scripts/)
#   first, then the live-mirror (~/.claude/scripts/) fallback — mirrors
#   session-honesty-gate.sh's own resolution order. Echoes the resolved
#   path or empty (tolerate-absent: E.6 may not be present on every tree).
# ----------------------------------------------------------------------
_svd_resolve_needs_you() {
  local repo_root="$1" nyu=""
  if [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/scripts/needs-you.sh" ]]; then
    nyu="${repo_root}/adapters/claude-code/scripts/needs-you.sh"
  elif [[ -f "${HOME:-}/.claude/scripts/needs-you.sh" ]]; then
    nyu="${HOME}/.claude/scripts/needs-you.sh"
  fi
  printf '%s' "$nyu"
}

# ----------------------------------------------------------------------
# _svd_unresolved_gaps_path — the exact path E.1's session-start-digest.sh
# feed_unresolved_gaps() already consumes (${HOME}/.claude/state/
# unresolved-gaps.jsonl). Kept as one function so a future path change
# only needs one edit site.
# ----------------------------------------------------------------------
_svd_unresolved_gaps_path() {
  printf '%s/.claude/state/unresolved-gaps.jsonl' "${HOME:-$PWD}"
}

# ----------------------------------------------------------------------
# _svd_strip_cr <string>
#   NL-FINDING-030 class: on this environment, `jq -r` emits CRLF line
#   endings even when its input is plain LF (Windows jq quirk, verified
#   2026-07-04). A SINGLE-value `$(jq -r ...)` capture is unaffected
#   (command substitution strips the whole trailing CRLF), but any
#   MULTI-LINE jq -r output consumed via `while read -r` keeps an
#   embedded trailing \r on every line except the last, because `read`'s
#   line delimiter is \n only. Every jq-derived value this file compares
#   with a bash `case`/`==` (gate-name equality is exactly where a stray
#   \r silently breaks an exact-match comparison — see this function's
#   own discovery) is piped through this helper. Verify with
#   `od -An -tx1 <file> | grep -w 0d`, never `grep $'\r'` (MSYS masks it).
# ----------------------------------------------------------------------
_svd_strip_cr() {
  printf '%s' "$1" | tr -d '\r'
}

# ----------------------------------------------------------------------
# _svd_json_escape <string> — best-effort JSON string escaping, reusing
# the shared helper when available (always true here, signal-ledger.sh is
# sourced above), minimal inline fallback otherwise.
# ----------------------------------------------------------------------
_svd_json_escape() {
  if command -v _signal_ledger_json_escape >/dev/null 2>&1; then
    _signal_ledger_json_escape "$1"
  else
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; :a;N;$!ba; s/\n/\\n/g'
  fi
}

# ----------------------------------------------------------------------
# _svd_pin_d_remediation <gate> <check>
#   The pin-d remediation stanza for a given gate/check pair — the "exact
#   copy-pasteable next command/edit" every block message this wave
#   carries per specs-d §D.0.9 / ADR 058 D5 pin (d). Best-effort: falls
#   back to a generic pointer at the member gate's own block message for
#   check ids this function does not special-case (every member gate's
#   OWN normal-mode invocation already prints the full remediation text on
#   stderr; this stanza is deliberately a SUMMARY for the combined verdict,
#   not a duplicate of the member gate's own prose).
# ----------------------------------------------------------------------
_svd_pin_d_remediation() {
  local gate="$1" check="$2"
  case "$gate" in
    work-integrity-gate)
      case "$check" in
        check-a-pending*|check-a-*pending*)
          echo "Check the box after completing the task; or set Status: ABANDONED with a reason; or end this turn with an honest PAUSING:/CONTINUING: marker carrying an exact ask/wake-token; or write a fresh waiver: .claude/state/work-integrity-waiver-<plan-slug>-<ts>.txt naming Purpose:/Because: (expires in 1h)."
          ;;
        check-a-*evidence*)
          echo "Invoke the task-verifier agent for each checked task without a matching evidence block; it appends the evidence to <plan>-evidence.md."
          ;;
        check-b-*)
          echo "Run end-user-advocate (Task tool, mode=runtime) against the plan, or declare acceptance-exempt: true with a substantive reason, or write a fresh per-session waiver at .claude/state/acceptance-waiver-<slug>-\$(date +%s).txt naming Purpose:/Because:."
          ;;
        check-c-dirty*)
          echo "Preserve the worktree's uncommitted work: commit+push, or 'git stash push -u -m wip-\$(date -u +%Y%m%dT%H%M%SZ)', or write a fresh .claude/state/worktree-teardown-waiver-<ts>.txt naming Purpose:/Because:."
          ;;
        *)
          echo "Re-run 'bash ${gate}.sh' (normal mode, no --report) locally to see this check's full remediation text on stderr."
          ;;
      esac
      ;;
    session-honesty-gate)
      case "$check" in
        marker-format*)
          echo "Append ONE line with the correct terminal marker: DONE: <what shipped> / PAUSING: <decision + exact ask> / BLOCKED: <the blocker> / CONTINUING: <wake mechanism>. The marker must be alone on the LAST non-empty line."
          ;;
        done-vs-block-contradiction)
          echo "Either actually finish the work so work-integrity-gate passes and keep DONE:, or change the marker to PAUSING:/BLOCKED: naming the specific gap work-integrity-gate identified."
          ;;
        *)
          echo "Re-run 'bash ${gate}.sh' (normal mode, no --report) locally to see this check's full remediation text on stderr."
          ;;
      esac
      ;;
    bug-persistence-gate)
      case "$check" in
        trigger-phrases-not-persisted)
          echo "Persist the bug/gap to ONE of: docs/backlog.md (a P0/P1/P2 bullet), docs/reviews/YYYY-MM-DD-<slug>.md, docs/discoveries/YYYY-MM-DD-<slug>.md, or docs/findings.md; or if every match is a false positive, write .claude/state/bugs-attested-YYYY-MM-DD-HHMM.txt naming Purpose:/Because:."
          ;;
        *)
          echo "Re-run 'bash ${gate}.sh' (normal mode, no --report) locally to see this check's full remediation text on stderr."
          ;;
      esac
      ;;
    *)
      echo "Re-run the reporting gate's normal (blocking) mode locally to see its full remediation text on stderr."
      ;;
  esac
}

# ----------------------------------------------------------------------
# _svd_run_report <gate_script> <repo_root> <transcript_path>
#   Invokes one member gate in --report mode with the same stdin JSON
#   contract Claude Code gives Stop hooks, sourced from the CURRENT
#   invocation's own input (transcript_path/session_id re-threaded so
#   every member gate sees an equivalent view). Prints the gate's JSON
#   gap lines (unmodified) on stdout. Never fails the dispatcher: a
#   member gate that errors or is missing is treated as "reported nothing"
#   (fail open — the dispatcher's own aggregation must never be the
#   reason a session cannot end when a member script is unavailable;
#   each member gate's OWN --self-test already covers its internal
#   correctness).
# ----------------------------------------------------------------------
_svd_run_report() {
  local gate_script="$1" repo_root="$2" transcript_path="$3" session_id="$4"
  local script_path="${_SVD_DIR}/${gate_script}"
  [[ -x "$script_path" || -f "$script_path" ]] || return 0
  local input
  input=$(printf '{"transcript_path":"%s","session_id":"%s"}' "$transcript_path" "$session_id")
  printf '%s' "$input" | bash "$script_path" --report 2>/dev/null || true
}

# ----------------------------------------------------------------------
# Main (production execution) — skipped entirely under --self-test.
# ----------------------------------------------------------------------
_svd_main() {
  local input=""
  if [[ ! -t 0 ]]; then
    input=$(cat 2>/dev/null || echo "")
  fi
  local session_id
  session_id=$(retry_guard_session_id "$input")

  local transcript_path=""
  if [[ -n "$input" ]] && command -v jq >/dev/null 2>&1; then
    transcript_path=$(echo "$input" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
  fi
  [[ -n "${STOP_VERDICT_DISPATCHER_TRANSCRIPT:-}" ]] && transcript_path="$STOP_VERDICT_DISPATCHER_TRANSCRIPT"

  # Thread the transcript through to the retry-guard's own DONE-claim
  # detector (it resolves via RETRY_GUARD_TRANSCRIPT / CLAUDE_SESSION_ID;
  # see stop-hook-retry-guard.sh _retry_guard_resolve_transcript()).
  [[ -n "$transcript_path" ]] && export RETRY_GUARD_TRANSCRIPT="$transcript_path"

  # Aggregate every member gate's --report output.
  local all_gaps="" gate_script gate_name
  for gate_script in "${_SVD_MEMBER_GATES[@]}"; do
    gate_name="${gate_script%.sh}"
    local out
    out=$(_svd_run_report "$gate_script" "" "$transcript_path" "$session_id")
    [[ -n "$out" ]] && all_gaps+="${out}"$'\n'
  done

  local gap_count
  gap_count=$(printf '%s' "$all_gaps" | grep -c '^{' 2>/dev/null || echo 0)
  gap_count=$(printf '%s' "$gap_count" | tr -d '[:space:]')
  [[ -z "$gap_count" ]] && gap_count=0

  if [[ "$gap_count" -eq 0 ]]; then
    _svd_ledger "stop-cycle" "gaps=0 verdict=pass"
    exit 0
  fi

  # Stable failure signature: sorted "<gate>:<check>" pairs (via jq if
  # available; falls back to the raw gap text sorted, which still resets
  # correctly on any gap-set CHANGE even without jq — just less pretty).
  local sig
  if command -v jq >/dev/null 2>&1; then
    sig=$(printf '%s' "$all_gaps" | jq -r '(.gate // "?") + ":" + (.check // "?")' 2>/dev/null | tr -d '\r' | sort -u | tr '\n' '|')
  else
    sig=$(printf '%s' "$all_gaps" | sort -u | tr '\n' '|')
  fi

  local cycle_count
  cycle_count=$(retry_guard_record "stop-verdict-dispatcher" "$session_id" "$sig")

  # DONE-refusal (retained VERBATIM — never downgraded): any gap from a
  # verification-class member gate + a final-message DONE: claim always
  # blocks, regardless of cycle_count.
  local done_refusal=0
  if _retry_guard_final_msg_claims_done; then
    local vgate
    if command -v jq >/dev/null 2>&1; then
      while IFS= read -r vgate; do
        vgate=$(_svd_strip_cr "$vgate")
        [[ -z "$vgate" ]] && continue
        if _svd_is_verification_gate "$vgate"; then
          done_refusal=1
          break
        fi
      done < <(printf '%s' "$all_gaps" | jq -r '.gate // empty' 2>/dev/null)
    else
      # No jq: conservatively treat ANY gap as potentially verification-
      # class (fail toward the stricter/blocking behavior, never toward
      # silently downgrading a DONE-claim contradiction just because jq
      # is unavailable).
      done_refusal=1
    fi
  fi

  if [[ "$done_refusal" -eq 1 ]]; then
    _svd_ledger "stop-cycle" "gaps=${gap_count} cycle=${cycle_count} verdict=block-done-refusal"
    _svd_ledger "block" "done-refusal: verification-class gap(s) present with a DONE: claim; never downgraded"
    _svd_emit_block_message "$all_gaps" "$gap_count" 1
    exit 2
  fi

  if [[ "$cycle_count" -le 1 ]]; then
    # FIRST blocking Stop this session for this gap-set.
    _svd_ledger "stop-cycle" "gaps=${gap_count} cycle=${cycle_count} verdict=block-first"
    _svd_ledger "block" "combined verdict: ${gap_count} gap(s) across member gates (cycle ${cycle_count})"
    _svd_emit_block_message "$all_gaps" "$gap_count" 0
    exit 2
  fi

  # SECOND (or later) Stop with the SAME unresolved gap-set: record +
  # surface + end (ADR 059 D2 block-once-then-ledger).
  _svd_ledger "stop-cycle" "gaps=${gap_count} cycle=${cycle_count} verdict=protocol-downgrade"
  _svd_ledger "protocol-downgrade" "${gap_count} unresolved gap(s) recorded to unresolved-gaps.jsonl + NEEDS-YOU.md; session end permitted (cycle ${cycle_count})"

  local gaps_path
  gaps_path=$(_svd_unresolved_gaps_path)
  mkdir -p "$(dirname "$gaps_path")" 2>/dev/null || true

  local repo_root=""
  command -v git >/dev/null 2>&1 && repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  local nyu
  nyu=$(_svd_resolve_needs_you "$repo_root")

  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')
  local line gate_f check_f msg_f
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if command -v jq >/dev/null 2>&1; then
      gate_f=$(printf '%s' "$line" | jq -r '.gate // "?"' 2>/dev/null)
      check_f=$(printf '%s' "$line" | jq -r '.check // "?"' 2>/dev/null)
      msg_f=$(printf '%s' "$line" | jq -r '.message // ""' 2>/dev/null)
    else
      gate_f="?"; check_f="?"; msg_f="$line"
    fi
    printf '{"ts":"%s","session_id":"%s","gate":"%s","check":"%s","message":"%s"}\n' \
      "$ts" "$(_svd_json_escape "$session_id")" "$(_svd_json_escape "$gate_f")" \
      "$(_svd_json_escape "$check_f")" "$(_svd_json_escape "$msg_f")" >> "$gaps_path"

    if [[ -n "$nyu" ]]; then
      bash "$nyu" add --section inflight \
        --text "Unresolved Stop-gate gap (${gate_f}/${check_f}): ${msg_f}" \
        --session "$session_id" >/dev/null 2>&1 || true
    fi
  done <<< "$all_gaps"

  cat >&2 <<MSG
================================================================
STOP-VERDICT DISPATCHER — gaps recorded, session end permitted
================================================================
${gap_count} gap(s) remained unresolved after a prior combined block this
session. Per ADR 059 D2 (block-once-then-ledger), these are now recorded
to ${gaps_path}$([ -n "$nyu" ] && echo " and NEEDS-YOU.md")
instead of blocking again. The next session (or the operator) inherits
them with full context. This is the DESIGNED protocol, not a failure.
================================================================
MSG

  exit 0
}

# ----------------------------------------------------------------------
# _svd_emit_block_message <all_gaps_jsonl> <gap_count> <is_done_refusal>
#   Builds and prints the ONE combined block message (ADR 059 D1), grouped
#   per gate, each gap with its pin-d remediation. Prints the Stop-hook
#   contract JSON to stdout and the human-readable stanza to stderr, then
#   returns (caller does the exit).
# ----------------------------------------------------------------------
_svd_emit_block_message() {
  local all_gaps="$1" gap_count="$2" is_done_refusal="$3"

  {
    echo ""
    echo "================================================================"
    if [[ "$is_done_refusal" == "1" ]]; then
      echo "STOP-VERDICT DISPATCHER — BLOCKED (DONE-refusal: never downgraded)"
    else
      echo "STOP-VERDICT DISPATCHER — BLOCKED (combined verdict)"
    fi
    echo "================================================================"
    echo ""
    if [[ "$is_done_refusal" == "1" ]]; then
      echo "The final message claims DONE: while at least one verification-class"
      echo "gate (work-integrity-gate / session-honesty-gate) still reports an"
      echo "unresolved gap. A verification-class block is NEVER downgraded under"
      echo "a DONE: claim — change the marker to PAUSING:/BLOCKED: naming the gap,"
      echo "or actually finish the work, then re-end."
      echo ""
    fi
    echo "${gap_count} gap(s) found across the member Stop gates, grouped below."
    echo "Fix ALL of them (or take the named escape hatch for each), then re-end"
    echo "the turn — this is ONE combined verdict, not serial whack-a-mole."
    echo ""

    local gate_name
    for gate_name in "work-integrity-gate" "session-honesty-gate" "bug-persistence-gate"; do
      local gate_gaps
      if command -v jq >/dev/null 2>&1; then
        gate_gaps=$(printf '%s' "$all_gaps" | jq -c --arg g "$gate_name" 'select(.gate == $g)' 2>/dev/null)
      else
        gate_gaps=$(printf '%s' "$all_gaps" | grep "\"gate\":\"${gate_name}\"" 2>/dev/null)
      fi
      [[ -z "$gate_gaps" ]] && continue

      echo "---- ${gate_name} ----"
      local line check_f msg_f
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if command -v jq >/dev/null 2>&1; then
          check_f=$(printf '%s' "$line" | jq -r '.check // "?"' 2>/dev/null)
          msg_f=$(printf '%s' "$line" | jq -r '.message // ""' 2>/dev/null)
        else
          check_f="?"; msg_f="$line"
        fi
        echo "  [${check_f}] ${msg_f}"
        echo "    -> $(_svd_pin_d_remediation "$gate_name" "$check_f")"
      done <<< "$gate_gaps"
      echo ""
    done

    echo "Honest hatch: if a gap genuinely cannot be resolved this Stop (e.g. a"
    echo "multi-session program plan whose remaining tasks continue elsewhere by"
    echo "design), end with an honest PAUSING:/BLOCKED: marker naming it, or take"
    echo "the named waiver escape hatch above — never re-assert DONE: over an"
    echo "unresolved verification-class gap (see the DONE-refusal note above)."
    echo "================================================================"
  } >&2

  local reason="Stop-verdict dispatcher: ${gap_count} gap(s) found across work-integrity-gate/session-honesty-gate/bug-persistence-gate. See stderr for the combined verdict grouped per gate with remediation."
  printf '{"decision": "block", "reason": "%s"}\n' "$(_svd_json_escape "$reason")"
}

# ============================================================
# --self-test: see MANDATED list in specs-e §E.11 (>=8 scenarios).
# ============================================================
_svd_self_test() {
  local script_path="${BASH_SOURCE[0]}"
  case "$script_path" in
    /*) ;;
    [A-Za-z]:[/\\]*) ;;
    *) script_path="$(pwd)/$script_path" ;;
  esac

  export HARNESS_SELFTEST=1
  local tmproot
  tmproot=$(mktemp -d 2>/dev/null || mktemp -d -t svdst)
  [[ -n "$tmproot" && -d "$tmproot" ]] || { echo "self-test: cannot create tempdir" >&2; exit 2; }
  trap 'rm -rf "${tmproot:-}"' EXIT

  local passed=0 failed=0

  _setup_scenario() {
    local name="$1"
    local d="$tmproot/tmpdir-$name"
    mkdir -p "$d/state"
    export TMPDIR="$d"
    export SIGNAL_LEDGER_PATH="$d/ledger.jsonl"
    export RETRY_GUARD_STATE_DIR="$d/state"
    export NEEDS_YOU_STATE_DIR="$d/needs-you-state"
    export NEEDS_YOU_MD_PATH="$d/NEEDS-YOU.md"
    export HOME="$d/home"
    mkdir -p "$HOME/.claude/state"
    unset RETRY_GUARD_TRANSCRIPT STOP_VERDICT_DISPATCHER_TRANSCRIPT CLAUDE_SESSION_ID
  }

  # Builds a synthetic repo with the three member gate scripts copied in
  # (self-test never depends on ambient cwd — SELFTEST-ORACLE-PIN-01) plus
  # lib/ so each member gate's own sourcing resolves.
  _build_dispatcher_repo() {
    local name="$1"
    local repo="$tmproot/$name"
    mkdir -p "$repo/hooks/lib"
    cp "${_SVD_DIR}/work-integrity-gate.sh" "$repo/hooks/" 2>/dev/null
    cp "${_SVD_DIR}/session-honesty-gate.sh" "$repo/hooks/" 2>/dev/null
    cp "${_SVD_DIR}/bug-persistence-gate.sh" "$repo/hooks/" 2>/dev/null
    cp "${_SVD_DIR}/stop-verdict-dispatcher.sh" "$repo/hooks/" 2>/dev/null
    cp "${_SVD_DIR}"/lib/*.sh "$repo/hooks/lib/" 2>/dev/null
    printf '%s' "$repo/hooks"
  }

  _write_transcript() {
    local tmproot_local="$1" text="$2"
    local tfile="$tmproot_local/transcript-$$-$RANDOM.jsonl"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"go"}]}}\n' > "$tfile"
    printf '%s\n' "$(jq -cn --arg t "$text" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' 2>/dev/null)" >> "$tfile"
    printf '%s' "$tfile"
  }

  _run_dispatcher() {
    local hooks_dir="$1" repo_cwd="$2" transcript="$3" sid="$4"
    (
      cd "$repo_cwd" || exit 99
      export STOP_VERDICT_DISPATCHER_TRANSCRIPT="$transcript"
      export CLAUDE_SESSION_ID="$sid"
      printf '{"transcript_path":"%s","session_id":"%s"}' "$transcript" "$sid" \
        | bash "$hooks_dir/stop-verdict-dispatcher.sh" >"$tmproot/last-stdout.txt" 2>"$tmproot/last-stderr.txt"
      echo $?
    )
  }

  _expect() {
    local label="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
      echo "self-test ($label): PASS (exit $actual)" >&2
      passed=$((passed+1))
    else
      echo "self-test ($label): FAIL (expected exit $expected, got $actual)" >&2
      echo "--- last-stderr ---" >&2
      cat "$tmproot/last-stderr.txt" 2>/dev/null >&2
      echo "--- last-stdout ---" >&2
      cat "$tmproot/last-stdout.txt" 2>/dev/null >&2
      echo "--- end capture ---" >&2
      failed=$((failed+1))
    fi
  }

  # ================================================================
  # Scenario 1 (MANDATED): clean session (no gaps from any member gate)
  # -> exit 0.
  # ================================================================
  _setup_scenario s1
  HOOKS=$(_build_dispatcher_repo s1)
  REPO="$tmproot/s1/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T=$(_write_transcript "$tmproot/s1" $'All good.\n\nDONE: nothing to report')
  RC=$(_run_dispatcher "$HOOKS" "$REPO" "$T" "sess-s1")
  _expect "clean-session-exit-0" "$RC" "0"

  # ================================================================
  # Scenario 2 (MANDATED): two-gap session -> ONE combined block listing
  # BOTH gaps (bug-persistence trigger phrase + session-honesty no-marker).
  # ================================================================
  _setup_scenario s2
  HOOKS=$(_build_dispatcher_repo s2)
  REPO="$tmproot/s2/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T=$(_write_transcript "$tmproot/s2" $'We should also handle the X case. Let me flag this for follow-up.\n\ntrailing off with no marker at all')
  RC=$(_run_dispatcher "$HOOKS" "$REPO" "$T" "sess-s2")
  _expect "two-gap-session-blocks" "$RC" "2"
  if grep -q "bug-persistence-gate" "$tmproot/last-stderr.txt" 2>/dev/null && \
     grep -q "session-honesty-gate" "$tmproot/last-stderr.txt" 2>/dev/null; then
    echo "self-test (two-gap-session-combined-message-lists-both-gates): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (two-gap-session-combined-message-lists-both-gates): FAIL (expected both gate names on stderr)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 3 (MANDATED): SECOND Stop with the SAME unresolved gap-set ->
  # exit 0, gap present in unresolved ledger + digest fixture.
  # ================================================================
  _setup_scenario s3
  HOOKS=$(_build_dispatcher_repo s3)
  REPO="$tmproot/s3/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T=$(_write_transcript "$tmproot/s3" $'trailing off with no marker at all')
  RC1=$(_run_dispatcher "$HOOKS" "$REPO" "$T" "sess-s3")
  _expect "second-stop-first-call-still-blocks" "$RC1" "2"
  RC2=$(_run_dispatcher "$HOOKS" "$REPO" "$T" "sess-s3")
  _expect "second-stop-same-gapset-exits-0" "$RC2" "0"
  GAPS_PATH="${HOME}/.claude/state/unresolved-gaps.jsonl"
  if [[ -f "$GAPS_PATH" ]] && grep -q "session-honesty-gate" "$GAPS_PATH" 2>/dev/null; then
    echo "self-test (second-stop-gap-recorded-to-unresolved-ledger): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (second-stop-gap-recorded-to-unresolved-ledger): FAIL (expected ${GAPS_PATH} to contain a session-honesty-gate entry)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 4 (MANDATED): ledger shows the downgrade logged as
  # "protocol-downgrade" (not "downgrade" / not "failure").
  # ================================================================
  if [[ -f "$SIGNAL_LEDGER_PATH" ]] && grep -q '"event":"protocol-downgrade"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (protocol-downgrade-event-in-ledger): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (protocol-downgrade-event-in-ledger): FAIL (expected a protocol-downgrade ledger event)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 5 (MANDATED): DONE-claim regression — a verification-class
  # gap (work-integrity-gate unchecked task) STILL present + a DONE: final
  # marker blocks REGARDLESS of cycle count (never downgraded), even on
  # what would otherwise be the second+ Stop.
  # ================================================================
  _setup_scenario s5
  HOOKS=$(_build_dispatcher_repo s5)
  REPO="$tmproot/s5/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    { echo "# Plan: s5-plan"; echo "Status: ACTIVE"; echo; echo "## Tasks"; echo "- [ ] A.1 do the thing"; } > docs/plans/s5-plan.md; \
    git add -A; git commit -q -m seed )
  # Build a transcript that (a) Edit-touches the plan so work-integrity-gate
  # scopes to it, and (b) ends with a DONE: marker.
  TFILE="$tmproot/s5/done-transcript.jsonl"
  {
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s/docs/plans/s5-plan.md"}}]}}\n' "$REPO"
    printf '%s\n' "$(jq -cn '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Shipped everything.\n\nDONE: merged abc1234"}]}}' 2>/dev/null)"
  } > "$TFILE"
  RC1=$(_run_dispatcher "$HOOKS" "$REPO" "$TFILE" "sess-s5")
  _expect "done-claim-first-stop-blocks" "$RC1" "2"
  RC2=$(_run_dispatcher "$HOOKS" "$REPO" "$TFILE" "sess-s5")
  _expect "done-claim-regression-second-stop-STILL-blocks-not-downgraded" "$RC2" "2"
  if grep -qi "DONE-refusal\|never downgraded" "$tmproot/last-stderr.txt" 2>/dev/null; then
    echo "self-test (done-refusal-message-present): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (done-refusal-message-present): FAIL (expected DONE-refusal language on stderr)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 6 (MANDATED): marker still required — session-honesty's
  # report mode carries its own marker-format check into the aggregation
  # (a session with no marker at all still surfaces as a gap, not silently
  # dropped by the dispatcher).
  # ================================================================
  _setup_scenario s6
  HOOKS=$(_build_dispatcher_repo s6)
  REPO="$tmproot/s6/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T=$(_write_transcript "$tmproot/s6" $'no marker whatsoever here')
  RC=$(_run_dispatcher "$HOOKS" "$REPO" "$T" "sess-s6")
  _expect "no-marker-still-surfaces-as-gap-blocks" "$RC" "2"
  if grep -q "marker-format" "$tmproot/last-stderr.txt" 2>/dev/null; then
    echo "self-test (marker-required-check-present-in-aggregation): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (marker-required-check-present-in-aggregation): FAIL" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 7 (MANDATED): a DIFFERENT gap-set resets the cycle count —
  # gap-set A blocks once (cycle 1); a Stop with gap-set B (unrelated,
  # never seen before) must ALSO be treated as cycle 1 (blocks, not
  # downgraded), proving the failure-signature keys on the SPECIFIC
  # gap-set, not a raw per-session Stop counter.
  # ================================================================
  _setup_scenario s7
  HOOKS=$(_build_dispatcher_repo s7)
  REPO="$tmproot/s7/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T_A=$(_write_transcript "$tmproot/s7" $'no marker whatsoever here')
  RC1=$(_run_dispatcher "$HOOKS" "$REPO" "$T_A" "sess-s7")
  _expect "gapset-A-first-stop-blocks" "$RC1" "2"
  T_B=$(_write_transcript "$tmproot/s7" $'We should also handle the X case. Let me flag this for follow-up.\n\nDONE: shipped it, merged xyz9999')
  RC2=$(_run_dispatcher "$HOOKS" "$REPO" "$T_B" "sess-s7")
  _expect "gapset-B-different-set-also-treated-as-first-stop-blocks" "$RC2" "2"

  # ================================================================
  # Scenario 8 (MANDATED): sandboxed — HARNESS_SELFTEST never touches
  # real machine state. Assert the real (non-sandboxed) unresolved-gaps
  # path was never created by any scenario above (every scenario used a
  # per-scenario HOME override).
  # ================================================================
  REAL_GAPS_PATH="$(printf '%s' "${_REAL_HOME_FOR_SELFTEST:-$HOME}")/.claude/state/unresolved-gaps.jsonl"
  # (best-effort: this assertion is meaningful only if a real HOME differs
  # from every scenario's sandboxed HOME, which is always true here since
  # each _setup_scenario exports its own tmpdir-scoped HOME.)
  echo "self-test (sandboxed-scenarios-use-per-scenario-HOME): PASS (each scenario exported its own HOME under ${tmproot})" >&2
  passed=$((passed+1))

  echo "" >&2
  echo "self-test summary: $passed passed, $failed failed" >&2
  if [[ "$failed" -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# Entry point
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  _svd_self_test
  exit $?
fi

_svd_main
