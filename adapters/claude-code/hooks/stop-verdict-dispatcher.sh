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
#
# ============================================================
# FUNCTIONAL-LINK check (Wave F, task F.L — operator directive 2026-07-05,
# nl-issue ledger golden scenario: Claude presented a dead file link)
# ============================================================
# WARN-ONLY, never contributes to the block/gap verdict above and never
# participates in cycle-counting/DONE-refusal (it is not a member gate's
# --report gap; it is a pure side-channel ledger warn). Parses the FINAL
# assistant message of the Stop transcript for markdown links
# `[text](target)`, skipping:
#   - http(s):// and mailto: targets (external, always "resolve")
#   - "#" anchors (in-page, not a file link)
#   - any link whose OPENING `[` falls inside an inline code span
#     (an even number of unescaped backticks precede it on the same line)
#     or inside a fenced code block (``` ... ``` — tracked line-by-line)
# For every remaining target, resolves against, in order:
#   (a) the session's cwd (may be a worktree — the common case for a
#       worker session)
#   (b) the MAIN checkout root (nl_main_checkout_root(), lib/nl-paths.sh)
#       — a worktree-relative link to a file that only exists in the main
#       checkout (e.g. NEEDS-YOU.md, gitignored per-checkout state) must
#       still resolve OK; this is the scenario this check exists to
#       distinguish from a genuinely dead link.
# Neither resolves => emit a signal-ledger "warn" event (gate name
# "stop-verdict-dispatcher", detail names the exact dead target) plus a
# stderr notice whose remediation is pin-d compliant: "give the absolute
# path instead" (copy-pasteable framing — the model's own next message can
# just do that). This NEVER blocks (exit code / verdict untouched) and
# NEVER appears in the combined block message above (only in ledger +
# stderr side-channel), so it cannot itself cause the DONE-refusal or
# cycle-counting paths to fire.
#
# FP expectation (documented per constitution §10 — this is a WARN, not a
# blocking gate, so the bar is lower, but still named): a link that is
# CORRECT but points at a file the current checkout genuinely lacks (e.g.
# a stale reference to a file deleted by a concurrent session between the
# link being written and this Stop firing) will false-positive-warn; this
# is accepted because (1) it never blocks, (2) the remediation ("give the
# absolute path instead") is harmless even when the link was transiently
# correct, and (3) the alternative (resolving against a live network
# fetch, e.g. a GitHub blob URL) is out of scope for a local mechanical
# check. Retirement condition: if this warn's false-positive rate proves
# high in the ledger (E.3-style rate visibility, feed_ledger_summary), the
# remedy is to add more resolution roots (e.g. a configured list of
# additional checkout-relative roots), not to remove the check.

set -u

SCRIPT_NAME="stop-verdict-dispatcher.sh"
_SVD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$_SVD_DIR/lib/signal-ledger.sh"
# shellcheck disable=SC1091
source "$_SVD_DIR/lib/stop-hook-retry-guard.sh"
# shellcheck disable=SC1091
source "$_SVD_DIR/lib/nl-paths.sh"

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
# _svd_resolve_end_manifest <repo_root>
#   Resolve end-manifest.sh: repo-relative (adapters/claude-code/scripts/)
#   first, then the live-mirror (~/.claude/scripts/) fallback — same
#   resolution order as _svd_resolve_needs_you above. Echoes the resolved
#   path or empty (tolerate-absent: a tree without E.12 installed simply
#   never gets manifest write/validate folded into the verdict).
# ----------------------------------------------------------------------
_svd_resolve_end_manifest() {
  local repo_root="$1" ems=""
  if [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/scripts/end-manifest.sh" ]]; then
    ems="${repo_root}/adapters/claude-code/scripts/end-manifest.sh"
  elif [[ -f "${HOME:-}/.claude/scripts/end-manifest.sh" ]]; then
    ems="${HOME}/.claude/scripts/end-manifest.sh"
  fi
  printf '%s' "$ems"
}

# ----------------------------------------------------------------------
# _svd_session_start_ref
#   NL-FINDING-036 fix: the REAL session-start boundary to pass as
#   end-manifest.sh write's --shipped-since, so "shipped this session"
#   means "reachable from HEAD but not yet on the remote-tracked baseline
#   at session start" — NOT end-manifest.sh's own hardcoded HEAD~20
#   fallback (a raw commit-count window that has nothing to do with THIS
#   session's actual start, and on any tree with >20 intervening commits
#   from OTHER sessions/PRs folds every one of their touched plans into
#   this session's shipped[] list, which is exactly what then makes
#   work-integrity-gate.sh's manifest-scoping treat unrelated plans as
#   "session-touched" — PROVEN live, see stop-verdict-dispatcher.sh's own
#   NL-FINDING-036 self-test scenario below).
#
#   Resolution order (soundest-first, mirrors the SAME convention already
#   used elsewhere in this file's sibling gate, work-integrity-gate.sh's
#   check (c) unpushed-commit count — see that file's "@{upstream} first,
#   origin/master fallback" pattern):
#     1. `@{upstream}` — the current branch's own tracked remote ref. This
#        is the actual "what has this branch shipped vs. its own remote"
#        boundary and is correct even when master itself has moved since
#        this branch forked (a merge-base against a moving origin/master
#        would otherwise silently widen as master advances).
#     2. `git merge-base HEAD origin/master` — no upstream configured
#        (e.g. a fresh local branch never pushed): the point this branch
#        diverged from master is the soundest available proxy for "session
#        start", since every commit from HEAD back to that point is, by
#        construction, work only this branch (this session's lineage) can
#        have made.
#     3. empty — neither resolves (no git, detached HEAD with no
#        origin/master, brand-new repo with one commit, etc.): the caller
#        omits --shipped-since entirely and end-manifest.sh's own
#        HEAD~20 fallback applies (pre-existing fail-open behavior,
#        unchanged for trees where no sound boundary exists at all).
# ----------------------------------------------------------------------
_svd_session_start_ref() {
  command -v git >/dev/null 2>&1 || { printf ''; return 0; }
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { printf ''; return 0; }

  if git rev-parse --verify --quiet '@{upstream}' >/dev/null 2>&1; then
    git rev-parse '@{upstream}' 2>/dev/null
    return 0
  fi
  if git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
    local mb
    mb=$(git merge-base HEAD origin/master 2>/dev/null)
    [[ -n "$mb" ]] && { printf '%s' "$mb"; return 0; }
  fi
  printf ''
}

# ----------------------------------------------------------------------
# _svd_write_and_validate_manifest <repo_root> <transcript_path> <session_id>
#   ADR 059 D6 / specs-e §E.12: the dispatcher (not a separate hook event —
#   Stop IS the session-end surface) writes THIS Stop's end-manifest, then
#   validates it, so:
#     (a) a manifest exists on disk for member gates (work-integrity-gate.sh's
#         _wig_resolve_manifest_path) to consult for manifest-scoping, and
#     (b) any FAILED validator check (fabricated SHA / missing recorded_at /
#         dirty-tree lie / marker mismatch) becomes a gap in THIS dispatcher's
#         own aggregated verdict, exactly like a member gate's --report gap.
#   Best-effort/fail-open: no end-manifest.sh on this tree, no jq, or a write
#   error => print nothing, emit no gap (member gates fall back to their own
#   transcript-derived scoping, unchanged pre-E.12 behavior). A write success
#   followed by a validate FAILURE is the only path that emits a gap line —
#   the write step itself is never gap-worthy (an empty/best-effort manifest
#   is still strictly additive over having none).
#
#   NL-FINDING-036 fix: ALWAYS derives a real --shipped-since boundary via
#   _svd_session_start_ref and passes it explicitly — this is the ONLY
#   caller of end-manifest.sh write in the live (flagless Stop-hook) path,
#   so leaving this flag unset here is precisely what let end-manifest.sh's
#   own HEAD~20 fallback silently apply in production while every prior
#   self-test scenario passed --shipped-since explicitly and never
#   exercised the dispatcher's own real call shape (see this file's
#   self-test scenario 13 below, which mirrors the exact flagless stdin
#   invocation and is the regression guard for this fix).
# ----------------------------------------------------------------------
_svd_write_and_validate_manifest() {
  local repo_root="$1" transcript_path="$2" session_id="$3"
  local ems
  ems=$(_svd_resolve_end_manifest "$repo_root")
  [[ -n "$ems" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local since_ref
  since_ref=$(_svd_session_start_ref)

  local write_args=(write --session-id "$session_id")
  [[ -n "$transcript_path" ]] && write_args+=(--transcript "$transcript_path")
  [[ -n "$since_ref" ]] && write_args+=(--shipped-since "$since_ref")
  local manifest_path
  manifest_path=$(bash "$ems" "${write_args[@]}" 2>/dev/null) || return 0
  [[ -n "$manifest_path" && -f "$manifest_path" ]] || return 0

  local -a validate_args=(validate "$manifest_path")
  [[ -n "$transcript_path" ]] && validate_args+=(--transcript "$transcript_path")
  local validate_err
  validate_err=$(bash "$ems" "${validate_args[@]}" 2>&1 >/dev/null)
  local rc=$?
  if [[ "$rc" -ne 0 ]]; then
    local fail_line
    while IFS= read -r fail_line; do
      [[ "$fail_line" == FAIL:* ]] || continue
      printf '{"gate":"end-manifest","check":"validate-failed","message":"%s"}\n' \
        "$(_svd_json_escape "$fail_line")"
    done <<< "$validate_err"
  fi
  return 0
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
    end-manifest)
      case "$check" in
        validate-failed)
          echo "Re-run 'bash scripts/end-manifest.sh validate <session-id>' locally to see the exact FAIL line (fabricated SHA / missing recorded_at / dirty-tree lie / marker mismatch); fix the underlying claim (push the SHA, actually record the unresolved item where it's claimed, commit/stash the worktree, or let the manifest regenerate with the true final marker) rather than editing the manifest by hand."
          ;;
        *)
          echo "Re-run 'bash scripts/end-manifest.sh validate <session-id>' locally to see this check's full remediation text on stderr."
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
# _svd_final_assistant_message <transcript_path>
#   Echoes the FINAL assistant message's plain text (joined text-block
#   content), or empty on any resolution/parse failure. Identical jq shape
#   to stop-hook-retry-guard.sh's own _retry_guard_final_msg_claims_done
#   (same "last assistant message, join text blocks" extraction) — kept as
#   a separate helper here (rather than reusing that function directly)
#   because that function returns a DONE-claim boolean, not the raw text;
#   duplicating the tail/jq shape is deliberate to avoid coupling this
#   check's behavior to retry-guard's own DONE-specific return contract.
# ----------------------------------------------------------------------
_svd_final_assistant_message() {
  local tp="$1"
  command -v jq >/dev/null 2>&1 || { printf ''; return 0; }
  [[ -n "$tp" && -f "$tp" ]] || { printf ''; return 0; }
  tail -n 400 "$tp" 2>/dev/null \
    | jq -c -R 'fromjson? // empty' 2>/dev/null \
    | jq -rs '
        [ .[] | select(.type=="assistant") ] | last
        | (.message.content // empty)
        | if type=="array" then [ .[] | select(.type=="text") | .text ] | join("\n")
          elif type=="string" then .
          else "" end' 2>/dev/null
}

# ----------------------------------------------------------------------
# _svd_extract_markdown_link_targets <text>
#   Prints one link TARGET per line for every markdown-style `[text](tgt)`
#   occurrence in $text, EXCLUDING any match whose opening `[` sits inside:
#     - an inline code span (an odd number of un-escaped backticks precede
#       it on the same rendered line — i.e. the `[` is the (2k+1)th
#       backtick-delimited region), or
#     - a fenced code block (a line starting with ``` or ~~~ toggles
#       "inside fence" state; every line while inside is skipped whole).
#   Processes the text LINE BY LINE (markdown links do not span lines in
#   this parser — matches the golden-scenario fixtures, which are
#   single-line links) so the fence-state and backtick-parity tracking
#   stay simple and auditable rather than a single multiline regex.
# ----------------------------------------------------------------------
_svd_extract_markdown_link_targets() {
  local text="$1"
  local in_fence=0
  local line
  while IFS= read -r line; do
    if printf '%s' "$line" | grep -qE '^[[:space:]]*(```|~~~)'; then
      in_fence=$((1 - in_fence))
      continue
    fi
    [[ "$in_fence" -eq 1 ]] && continue

    # Walk the line left-to-right, tracking backtick parity, and emit the
    # target of every [text](target) match whose `[` is at EVEN backtick
    # parity (i.e. NOT inside an inline code span).
    local remaining="$line"
    local consumed_backticks=0
    while [[ "$remaining" == *'['*']('*')'* ]]; do
      local before="${remaining%%[*}"
      local bt_here
      bt_here=$(printf '%s' "$before" | tr -cd '`' | wc -c)
      local parity=$(( (consumed_backticks + bt_here) % 2 ))

      local after_bracket="${remaining#*[}"
      # Require the very next chars to be `](` for this `[` to be a link
      # open (a bare `[` with no matching `](` is not a link at all).
      if [[ "$after_bracket" != *']('* ]]; then
        break
      fi
      local link_text_and_rest="${after_bracket%%](*}"
      local after_paren="${after_bracket#*](}"
      if [[ "$after_paren" != *')'* ]]; then
        break
      fi
      local target="${after_paren%%)*}"
      local rest="${after_paren#*)}"

      if [[ "$parity" -eq 0 ]]; then
        printf '%s\n' "$target"
      fi

      consumed_backticks=$((consumed_backticks + bt_here))
      remaining="$rest"
    done
  done <<< "$text"
}

# ----------------------------------------------------------------------
# _svd_link_target_ignorable <target>
#   True (0) for targets this check does not evaluate at all: http(s)://,
#   mailto:, and bare "#" in-page anchors (including "path#anchor" forms —
#   still ignored per spec: "http(s)/mailto/# ... ignored"; a target that
#   is JUST an anchor into the current doc is not a file-link claim).
# ----------------------------------------------------------------------
_svd_link_target_ignorable() {
  local target="$1"
  case "$target" in
    http://*|https://*|mailto:*) return 0 ;;
    '#'*) return 0 ;;
    *) return 1 ;;
  esac
}

# ----------------------------------------------------------------------
# _svd_resolve_link_target <target> <session_cwd> <main_root>
#   Resolves a (non-ignorable) link target against, in order: (a) the
#   session cwd, (b) the main checkout root. Strips a trailing "#anchor"
#   fragment before resolving (an anchor is not part of the filesystem
#   path). Absolute paths are checked directly against both roots'
#   filesystem (an absolute path either exists or it doesn't — "against
#   root" is a no-op for it, but both branches still just stat the same
#   absolute path, which is correct and cheap). Prints "ok" + the
#   resolved path if found, or "dead" on stdout if neither root resolves
#   it. Never errors.
# ----------------------------------------------------------------------
_svd_resolve_link_target() {
  local target="$1" cwd="$2" main_root="$3"
  local path="${target%%#*}"
  [[ -z "$path" ]] && { printf 'dead'; return 0; }

  local candidate
  if [[ "$path" == /* || "$path" =~ ^[A-Za-z]:[/\\] ]]; then
    if [[ -e "$path" ]]; then printf 'ok %s' "$path"; return 0; fi
    printf 'dead'; return 0
  fi

  if [[ -n "$cwd" ]]; then
    candidate="${cwd%/}/${path}"
    if [[ -e "$candidate" ]]; then printf 'ok %s' "$candidate"; return 0; fi
  fi
  if [[ -n "$main_root" ]]; then
    candidate="${main_root%/}/${path}"
    if [[ -e "$candidate" ]]; then printf 'ok %s' "$candidate"; return 0; fi
  fi
  printf 'dead'
}

# ----------------------------------------------------------------------
# _svd_functional_link_check <transcript_path> <session_cwd>
#   WARN-only (see header comment above). Extracts the final assistant
#   message, walks every non-ignorable, non-code-span markdown link
#   target, and for each unresolved one emits a signal-ledger "warn" event
#   + a stderr notice naming the exact dead target with the pin-d
#   remediation. Never writes to stdout (must never be mistaken for a
#   member gate's JSON gap line by the caller's aggregation) and never
#   returns non-zero (fail-open: a parse error here is silently "nothing
#   to warn about", never a reason to disturb the real verdict).
# ----------------------------------------------------------------------
_svd_functional_link_check() {
  local transcript_path="$1" session_cwd="$2"
  local text
  text=$(_svd_final_assistant_message "$transcript_path")
  [[ -n "$text" ]] || return 0

  local main_root=""
  command -v git >/dev/null 2>&1 && main_root=$(nl_main_checkout_root 2>/dev/null || echo "")

  local target resolution
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    _svd_link_target_ignorable "$target" && continue
    resolution=$(_svd_resolve_link_target "$target" "$session_cwd" "$main_root")
    if [[ "$resolution" == "dead" ]]; then
      local detail="dead link target: ${target} -- give the absolute path instead"
      _svd_ledger "warn" "$detail"
      {
        echo ""
        echo "---- FUNCTIONAL-LINK (WARN, non-blocking) ----"
        echo "  [dead-link] ${target}"
        echo "    -> give the absolute path instead (neither the session cwd nor the main checkout root resolved this target)."
      } >&2
    fi
  done < <(_svd_extract_markdown_link_targets "$text")
  return 0
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

  local repo_root=""
  command -v git >/dev/null 2>&1 && repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

  # FUNCTIONAL-LINK check (task F.L): WARN-only, runs independently of the
  # gap aggregation below and never contributes to all_gaps/the verdict —
  # see the header comment block above for the full mechanism. Uses the
  # session's actual cwd (captured here, before anything else in this
  # function could change directory — nothing does, but this keeps the
  # capture site unambiguous) as resolution root (a), alongside the main
  # checkout root (b) inside the helper itself.
  _svd_functional_link_check "$transcript_path" "$(pwd)"

  # ADR 059 D6 / specs-e §E.12: write + validate THIS session's end-manifest
  # BEFORE the member gates run, so work-integrity-gate.sh's manifest-scoping
  # (_wig_resolve_manifest_path) finds a manifest on disk for this Stop, and
  # any validator FAILURE is folded into the aggregated verdict below as an
  # "end-manifest" gap alongside the three member gates' own gaps.
  local all_gaps=""
  local manifest_gaps
  manifest_gaps=$(_svd_write_and_validate_manifest "$repo_root" "$transcript_path" "$session_id")
  [[ -n "$manifest_gaps" ]] && all_gaps+="${manifest_gaps}"$'\n'

  # Aggregate every member gate's --report output.
  local gate_script gate_name
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

  # repo_root was already resolved earlier in this function (used for the
  # end-manifest write/validate step above) — reused here, not recomputed.
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
    for gate_name in "end-manifest" "work-integrity-gate" "session-honesty-gate" "bug-persistence-gate"; do
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

  local reason="Stop-verdict dispatcher: ${gap_count} gap(s) found across end-manifest/work-integrity-gate/session-honesty-gate/bug-persistence-gate. See stderr for the combined verdict grouped per gate with remediation."
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
    # end-manifest.sh's own HARNESS_SELFTEST=1 convention routes its state
    # dir to a per-PID tempdir UNLESS END_MANIFEST_STATE_DIR is set
    # explicitly (SELFTEST-ORACLE-PIN-01 — mirrors work-integrity-gate.sh's
    # own _wig_resolve_manifest_path, which likewise requires this env var
    # under HARNESS_SELFTEST=1). Every scenario gets its own per-scenario
    # manifest dir so the manifest-wiring scenarios below resolve to a
    # KNOWN, per-scenario path instead of a $$-keyed one.
    export END_MANIFEST_STATE_DIR="$d/end-manifest-state"
    mkdir -p "$END_MANIFEST_STATE_DIR"
    unset RETRY_GUARD_TRANSCRIPT STOP_VERDICT_DISPATCHER_TRANSCRIPT CLAUDE_SESSION_ID
  }

  # Builds a synthetic repo with the three member gate scripts copied in
  # (self-test never depends on ambient cwd — SELFTEST-ORACLE-PIN-01) plus
  # lib/ so each member gate's own sourcing resolves. $2 (optional):
  # "with-manifest" also copies scripts/end-manifest.sh into the fixture's
  # adapters/claude-code/scripts/ layout so _svd_resolve_end_manifest's
  # repo-relative resolution finds it via `git rev-parse --show-toplevel`
  # (task E.12 wiring scenarios below need this; every pre-existing
  # scenario omits it deliberately, proving the fail-open no-manifest path
  # is unchanged).
  _build_dispatcher_repo() {
    local name="$1" variant="${2:-}"
    local repo="$tmproot/$name"
    mkdir -p "$repo/hooks/lib"
    cp "${_SVD_DIR}/work-integrity-gate.sh" "$repo/hooks/" 2>/dev/null
    cp "${_SVD_DIR}/session-honesty-gate.sh" "$repo/hooks/" 2>/dev/null
    cp "${_SVD_DIR}/bug-persistence-gate.sh" "$repo/hooks/" 2>/dev/null
    cp "${_SVD_DIR}/stop-verdict-dispatcher.sh" "$repo/hooks/" 2>/dev/null
    cp "${_SVD_DIR}"/lib/*.sh "$repo/hooks/lib/" 2>/dev/null
    if [[ "$variant" == "with-manifest" ]]; then
      # end-manifest.sh must live under the GIT REPO's own toplevel (every
      # scenario's actual git repo is $repo/repo, one level below $repo —
      # see the "REPO=$tmproot/<name>/repo" convention each scenario
      # follows below), because _svd_resolve_end_manifest resolves it
      # repo-relative to `git rev-parse --show-toplevel`, not to this
      # fixture-builder's own $repo.
      mkdir -p "$repo/repo/adapters/claude-code/scripts"
      cp "${_SVD_DIR}/../scripts/end-manifest.sh" "$repo/repo/adapters/claude-code/scripts/" 2>/dev/null
    fi
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

  # ================================================================
  # Scenario 9 (task E.12 wiring, ADR 059 D6): the dispatcher itself
  # writes THIS session's end-manifest (no other hook event does — Stop is
  # the session-end surface) so a manifest exists on disk for the member
  # gates to consult, at the path _wig_resolve_manifest_path resolves to
  # (END_MANIFEST_STATE_DIR/<sanitized-session-id>.json — this scenario's
  # own per-scenario override, exported by _setup_scenario above; mirrors
  # the live convention of ${HOME}/.claude/state/end-manifest/<id>.json
  # when neither override applies). Uses the "with-manifest" fixture
  # variant so end-manifest.sh is present under adapters/claude-code/
  # scripts/ (repo-relative resolution).
  # ================================================================
  _setup_scenario s9
  HOOKS=$(_build_dispatcher_repo s9 with-manifest)
  REPO="$tmproot/s9/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T=$(_write_transcript "$tmproot/s9" $'All good.\n\nDONE: nothing to report')
  RC=$(_run_dispatcher "$HOOKS" "$REPO" "$T" "sess-s9")
  _expect "manifest-written-clean-session-still-exits-0" "$RC" "0"
  MANIFEST_S9="${END_MANIFEST_STATE_DIR}/sess-s9.json"
  if [[ -f "$MANIFEST_S9" ]] && command -v jq >/dev/null 2>&1 && jq -e '.schema_version == 1' "$MANIFEST_S9" >/dev/null 2>&1; then
    echo "self-test (dispatcher-writes-manifest-at-session-id-path): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (dispatcher-writes-manifest-at-session-id-path): FAIL (expected ${MANIFEST_S9} to exist and be schema_version 1)" >&2
    failed=$((failed+1))
  fi
  # End-to-end proof (not just "a manifest file exists somewhere"):
  # work-integrity-gate.sh, invoked BY the dispatcher's own --report call
  # within this SAME Stop, actually found and used that manifest — its
  # own ledger line ("manifest-scoping active: <path>") is the mechanical
  # signal, written to this scenario's SIGNAL_LEDGER_PATH.
  if grep -q "manifest-scoping active" "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (work-integrity-gate-consumed-the-dispatcher-written-manifest-same-stop): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (work-integrity-gate-consumed-the-dispatcher-written-manifest-same-stop): FAIL (expected a 'manifest-scoping active' ledger line from work-integrity-gate.sh's --report invocation)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 10 (task E.12 wiring): _svd_write_and_validate_manifest folds
  # a validator FAILURE into a JSON gap line the dispatcher's aggregation
  # understands — unit-tested directly against a STUB end-manifest.sh
  # (write always "succeeds" at a fixed path; validate always fails with a
  # known FAIL: line), so this scenario is independent of any particular
  # real validator check and proves the GLUE (gap-line shape, gate name,
  # FAIL-line filtering) rather than re-proving end-manifest.sh's own
  # checks (already covered by that file's own --self-test).
  # ================================================================
  _setup_scenario s10
  STUB_DIR="$tmproot/tmpdir-s10/stub-scripts"
  mkdir -p "$STUB_DIR" "$tmproot/tmpdir-s10/state"
  STUB_MANIFEST="$tmproot/tmpdir-s10/state/stub-manifest.json"
  echo '{"schema_version":1}' > "$STUB_MANIFEST"
  cat > "$STUB_DIR/end-manifest.sh" <<STUBEOF
#!/bin/bash
case "\$1" in
  write) echo "$STUB_MANIFEST" ;;
  validate)
    echo "PASS: unrelated check" >&2
    echo "FAIL: shipped SHA deadbeef is NOT reachable from master (fabricated-SHA / not-yet-merged check)" >&2
    echo "end-manifest validate: ONE OR MORE CHECKS FAILED (\$STUB_MANIFEST)" >&2
    exit 1
    ;;
esac
STUBEOF
  chmod +x "$STUB_DIR/end-manifest.sh"
  UNIT_TEST_SCRIPT="$tmproot/tmpdir-s10/unit-test.sh"
  {
    echo '#!/bin/bash'
    echo "source '${_SVD_DIR}/lib/signal-ledger.sh' 2>/dev/null"
    echo "_svd_resolve_end_manifest() { printf '%s' '${STUB_DIR}/end-manifest.sh'; }"
    declare -f _svd_json_escape
    declare -f _svd_write_and_validate_manifest
    echo "_svd_write_and_validate_manifest '' '' 'sess-s10'"
  } > "$UNIT_TEST_SCRIPT"
  GAP_OUT=$(bash "$UNIT_TEST_SCRIPT" 2>/dev/null)
  if printf '%s' "$GAP_OUT" | grep -q '"gate":"end-manifest"' && printf '%s' "$GAP_OUT" | grep -q '"check":"validate-failed"' && printf '%s' "$GAP_OUT" | grep -q 'NOT reachable'; then
    echo "self-test (write-and-validate-manifest-folds-FAIL-line-into-gap-json): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (write-and-validate-manifest-folds-FAIL-line-into-gap-json): FAIL (got: ${GAP_OUT})" >&2
    failed=$((failed+1))
  fi
  if ! printf '%s' "$GAP_OUT" | grep -q 'PASS: unrelated check'; then
    echo "self-test (write-and-validate-manifest-never-emits-PASS-lines-as-gaps): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (write-and-validate-manifest-never-emits-PASS-lines-as-gaps): FAIL" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 11 (task E.12 wiring): no end-manifest.sh on this tree (the
  # pre-existing fixture repos built WITHOUT the "with-manifest" variant,
  # e.g. scenario 1) => _svd_write_and_validate_manifest is a silent no-op
  # (fail-open) — proves this task's change is additive, never a new
  # failure mode for a tree/session with no manifest support.
  # ================================================================
  _setup_scenario s11
  HOOKS=$(_build_dispatcher_repo s11)
  REPO="$tmproot/s11/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T=$(_write_transcript "$tmproot/s11" $'All good.\n\nDONE: nothing to report')
  RC=$(_run_dispatcher "$HOOKS" "$REPO" "$T" "sess-s11")
  _expect "no-end-manifest-sh-on-tree-still-exits-0-fail-open" "$RC" "0"
  if ! grep -q "end-manifest" "$tmproot/last-stderr.txt" 2>/dev/null; then
    echo "self-test (no-manifest-support-no-end-manifest-gap-mentioned): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (no-manifest-support-no-end-manifest-gap-mentioned): FAIL" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 12 (MANDATED, specs-e §E.12 Done-when, lines 428-430):
  # grep-assertion — no surviving Stop gate greps the TRANSCRIPT for
  # plan-touch derivation when a manifest exists for the session. This is
  # a static proof over the source, not a runtime scenario: with a
  # manifest present, work-integrity-gate.sh's _wig_main takes the
  # manifest branch (_wig_manifest_touched_plans) and the transcript-grep
  # branch (_wig_touched_plan_paths, which greps the transcript JSONL for
  # tool_use Edit/Write/Read entries) is provably unreachable in that
  # branch — i.e. is gated behind the `else` of the exact same
  # `if [[ -n "$manifest_path" ]]` this scenario asserts exists.
  # ================================================================
  if grep -qE 'if \[\[ -n "\$manifest_path" \]\]; then' "${_SVD_DIR}/work-integrity-gate.sh" \
     && grep -A3 'if \[\[ -n "\$manifest_path" \]\]; then' "${_SVD_DIR}/work-integrity-gate.sh" | grep -q '_wig_manifest_touched_plans' \
     && grep -A6 'if \[\[ -n "\$manifest_path" \]\]; then' "${_SVD_DIR}/work-integrity-gate.sh" | grep -q '_wig_touched_plan_paths'; then
    echo "self-test (grep-assertion-manifest-branch-replaces-transcript-grep-when-manifest-present): PASS (work-integrity-gate.sh: manifest_path present -> _wig_manifest_touched_plans; else -> _wig_touched_plan_paths, confirmed by source grep)" >&2
    passed=$((passed+1))
  else
    echo "self-test (grep-assertion-manifest-branch-replaces-transcript-grep-when-manifest-present): FAIL (expected the if/else branch structure gating _wig_touched_plan_paths behind absence of a manifest)" >&2
    failed=$((failed+1))
  fi
  if grep -q '_svd_write_and_validate_manifest' "${_SVD_DIR}/stop-verdict-dispatcher.sh" 2>/dev/null; then
    echo "self-test (grep-assertion-dispatcher-actually-invokes-end-manifest-write-and-validate): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (grep-assertion-dispatcher-actually-invokes-end-manifest-write-and-validate): FAIL (dispatcher no longer calls the manifest write/validate step)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 13 (NL-FINDING-036 regression guard): a synthetic session
  # that touched NOTHING must not be blocked over UNRELATED plans, when
  # invoked via the dispatcher's REAL production shape — flagless stdin
  # JSON, no --shipped-since anywhere in the caller (mirrors the exact
  # livesmoke repro: `echo '{"transcript_path":"","session_id":"..."}' |
  # bash stop-verdict-dispatcher.sh`, no extra args, no env override of
  # the shipped-since boundary). Every PRIOR scenario in this file used
  # end-manifest.sh's "with-manifest" variant only for scenarios that
  # never had >20 intervening commits, so the HEAD~20 fallback window
  # never leaked into any of them — this is precisely the gap that
  # masked the bug (self-tests exercised a correctly-scoped shape; the
  # live path fell through to end-manifest.sh's own hardcoded default).
  #
  # Fixture: a bare "origin" remote (so @{upstream}/origin/master
  # resolve), a plan committed and PUSHED as part of the origin baseline
  # (i.e. already shipped before this session started), then >20 FURTHER
  # commits on origin/master itself — each touching a DIFFERENT unrelated
  # plan with unchecked tasks — simulating "lots of other sessions/PRs
  # landed on master before this session's Stop fires". The test session
  # then fast-forwards its local branch to match origin/master (so HEAD
  # == @{upstream}, i.e. genuinely nothing of this session's own is
  # unshipped) and ends with a clean DONE: marker having touched nothing.
  # Pre-fix (no --shipped-since passed to end-manifest.sh write), the
  # HEAD~20 fallback would treat 20 of those unrelated plan-touching
  # commits as "this session's shipped work" and work-integrity-gate.sh's
  # manifest-scoping would then block on their unchecked tasks. Post-fix,
  # _svd_session_start_ref resolves @{upstream} (== HEAD, nothing
  # unshipped) so shipped[] is correctly empty and the Stop passes clean.
  # ================================================================
  _setup_scenario s13
  HOOKS=$(_build_dispatcher_repo s13 with-manifest)
  REPO="$tmproot/s13/repo"
  ORIGIN_BARE="$tmproot/s13/origin.git"
  git init -q --bare "$ORIGIN_BARE" 2>/dev/null
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    git remote add origin "$ORIGIN_BARE"; \
    echo seed > seed.txt; git add -A; git commit -q -m seed; \
    git push -q -u origin master )
  # >20 unrelated commits landing on master, each with its own unchecked
  # plan — simulates other sessions'/PRs' work accumulating before this
  # session's Stop. 22 to comfortably exceed end-manifest.sh's HEAD~20.
  i=1
  while [[ "$i" -le 22 ]]; do
    ( cd "$REPO" && \
      { echo "# Plan: unrelated-plan-${i}"; echo "Status: ACTIVE"; echo; echo "## Tasks"; echo "- [ ] U.${i} unrelated unchecked task"; } > "docs/plans/unrelated-plan-${i}.md"; \
      git add -A; git commit -q -m "unrelated work ${i} (not this session)" )
    i=$((i+1))
  done
  ( cd "$REPO" && git push -q origin master )
  # This session's own view: fast-forwarded to match origin/master exactly
  # (HEAD == @{upstream}) — nothing of THIS session's own is unshipped,
  # and this session touched none of the unrelated plans above.
  T=$(_write_transcript "$tmproot/s13" $'Investigated an unrelated question, touched nothing.\n\nDONE: nothing to report')
  RC=$(_run_dispatcher "$HOOKS" "$REPO" "$T" "sess-s13")
  _expect "NL-FINDING-036-no-touch-session-not-blocked-over-unrelated-plans-real-shape" "$RC" "0"
  if ! grep -qE "unrelated-plan-[0-9]+" "$tmproot/last-stderr.txt" 2>/dev/null; then
    echo "self-test (NL-FINDING-036-no-unrelated-plan-named-in-block-message): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (NL-FINDING-036-no-unrelated-plan-named-in-block-message): FAIL (an unrelated plan was named — HEAD~20-style leak still present)" >&2
    failed=$((failed+1))
  fi
  MANIFEST_S13="${END_MANIFEST_STATE_DIR}/sess-s13.json"
  if [[ -f "$MANIFEST_S13" ]] && command -v jq >/dev/null 2>&1 && [[ "$(jq '.shipped | length' "$MANIFEST_S13" 2>/dev/null)" == "0" ]]; then
    echo "self-test (NL-FINDING-036-manifest-shipped-array-correctly-empty-not-HEAD-tilde-20-derived): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (NL-FINDING-036-manifest-shipped-array-correctly-empty-not-HEAD-tilde-20-derived): FAIL (expected shipped[] to be empty at ${MANIFEST_S13})" >&2
    failed=$((failed+1))
  fi
  # Static proof the fix is actually wired: the dispatcher's manifest-write
  # call site now always resolves and passes --shipped-since (never relies
  # on end-manifest.sh's own hardcoded fallback in the live path).
  if grep -q '_svd_session_start_ref' "${_SVD_DIR}/stop-verdict-dispatcher.sh" 2>/dev/null \
     && grep -A2 'local write_args=(write --session-id' "${_SVD_DIR}/stop-verdict-dispatcher.sh" | grep -q -- '--shipped-since'; then
    echo "self-test (NL-FINDING-036-grep-assertion-write-call-site-passes-shipped-since): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (NL-FINDING-036-grep-assertion-write-call-site-passes-shipped-since): FAIL (expected the write_args construction to include --shipped-since)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 14 (task F.L, MANDATED GOLDEN SCENARIO): a final message that
  # links NEEDS-YOU.md from a WORKTREE cwd where only the MAIN checkout
  # has that file (real `git worktree add`, mirroring nl-paths.sh's own
  # T7 self-test technique) resolves OK via the main-checkout-root
  # fallback (b) -> NO warn ledger event for this target. Companion link
  # to a genuinely missing file in the SAME message WARNS naming it (proves
  # the check evaluates each link independently, not all-or-nothing), and
  # neither link affects the exit code (WARN-only, never blocks).
  # ================================================================
  _setup_scenario s14
  HOOKS=$(_build_dispatcher_repo s14)
  REPO="$tmproot/s14/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo "NEEDS-YOU.md" > .gitignore; git add -A; git commit -q -m seed; \
    echo seed > seed.txt; git add -A; git commit -q -m seed2; \
    echo "# NEEDS-YOU" > NEEDS-YOU.md )
  WT14="$tmproot/s14/worktree"
  git -C "$REPO" worktree add -q -b s14-wt-branch "$WT14" >/dev/null 2>&1
  # NEEDS-YOU.md is gitignored (the live convention: per-checkout state,
  # never committed) and exists ONLY in the main checkout's working copy
  # (created above, after the seed commit, so it is untracked there and
  # git-worktree-add never propagates it into the new worktree). The
  # worktree's own working copy genuinely has no such file — a CLEAN
  # worktree (no uncommitted changes of its own), so work-integrity-gate's
  # check-c (dirty-worktree-on-Stop) does not fire and this scenario
  # isolates the FUNCTIONAL-LINK behavior from unrelated gates.
  T14=$(_write_transcript "$tmproot/s14" $'Here is the status: [NEEDS-YOU.md](NEEDS-YOU.md) has the open items, but [stale ref](docs/nonexistent.md) is gone.\n\nDONE: nothing to report')
  RC14=$(_run_dispatcher "$HOOKS" "$WT14" "$T14" "sess-s14")
  _expect "golden-scenario-worktree-cwd-never-blocks" "$RC14" "0"
  if ! grep -q '"gate":"stop-verdict-dispatcher".*NEEDS-YOU\.md\|dead link target: NEEDS-YOU\.md' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (golden-scenario-NEEDS-YOU-resolves-via-main-checkout-root-no-warn): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (golden-scenario-NEEDS-YOU-resolves-via-main-checkout-root-no-warn): FAIL (NEEDS-YOU.md incorrectly flagged dead despite existing in the main checkout)" >&2
    failed=$((failed+1))
  fi
  if grep -q 'dead link target: docs/nonexistent\.md' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (golden-scenario-companion-dead-link-still-warns): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (golden-scenario-companion-dead-link-still-warns): FAIL (expected docs/nonexistent.md to be flagged dead)" >&2
    failed=$((failed+1))
  fi
  if grep -q 'give the absolute path instead' "$tmproot/last-stderr.txt" 2>/dev/null; then
    echo "self-test (golden-scenario-warn-message-is-pin-d-actionable): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (golden-scenario-warn-message-is-pin-d-actionable): FAIL (expected the pin-d remediation phrase on stderr)" >&2
    failed=$((failed+1))
  fi
  ( cd "$REPO" && git worktree remove --force "$WT14" >/dev/null 2>&1 || true; git branch -D s14-wt-branch >/dev/null 2>&1 || true )

  # ================================================================
  # Scenario 15 (task F.L): http(s)/mailto/# targets are NEVER evaluated,
  # even when the "path" would obviously not resolve as a file (proves
  # the ignore-list short-circuits before any filesystem check).
  # ================================================================
  _setup_scenario s15
  HOOKS=$(_build_dispatcher_repo s15)
  REPO="$tmproot/s15/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T15=$(_write_transcript "$tmproot/s15" $'See [docs](https://example.com/nonexistent), [mail](mailto:a@b.com), [anchor](#nope).\n\nDONE: nothing to report')
  RC15=$(_run_dispatcher "$HOOKS" "$REPO" "$T15" "sess-s15")
  _expect "http-mailto-anchor-links-never-block" "$RC15" "0"
  if ! grep -qE '"gate":"stop-verdict-dispatcher".*(example\.com|mailto:|#nope)' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (http-mailto-anchor-links-ignored-not-warned): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (http-mailto-anchor-links-ignored-not-warned): FAIL (an ignorable target was incorrectly warned on)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 16 (task F.L): a link inside an inline code span is NEVER
  # evaluated, even when its "target" is obviously not a real file —
  # proves the code-span skip (backtick-parity tracking), not just that
  # the target happens to resolve.
  # ================================================================
  _setup_scenario s16
  HOOKS=$(_build_dispatcher_repo s16)
  REPO="$tmproot/s16/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T16=$(_write_transcript "$tmproot/s16" $'Write links like this: `[text](docs/totally-fake.md)` in markdown.\n\nDONE: nothing to report')
  RC16=$(_run_dispatcher "$HOOKS" "$REPO" "$T16" "sess-s16")
  _expect "code-span-link-example-never-blocks" "$RC16" "0"
  if ! grep -q 'docs/totally-fake\.md' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (code-span-link-example-not-warned): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (code-span-link-example-not-warned): FAIL (a link inside an inline code span was incorrectly warned on)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 17 (task F.L): a WARN never appears in the combined BLOCK
  # message and never contributes to gap_count/cycle-counting — build a
  # session that has a REAL blocking gap (no marker) PLUS a dead link in
  # the same final message; the block message must list the marker-format
  # gap but must NOT fold the dead-link warn into it (separate channel).
  # ================================================================
  _setup_scenario s17
  HOOKS=$(_build_dispatcher_repo s17)
  REPO="$tmproot/s17/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T17=$(_write_transcript "$tmproot/s17" $'See [gone](docs/still-not-here.md) — trailing off with no marker at all')
  RC17=$(_run_dispatcher "$HOOKS" "$REPO" "$T17" "sess-s17")
  _expect "warn-plus-real-gap-still-blocks-on-the-real-gap" "$RC17" "2"
  if grep -q "marker-format" "$tmproot/last-stderr.txt" 2>/dev/null \
     && ! grep -q "docs/still-not-here\.md" "$tmproot/last-stdout.txt" 2>/dev/null; then
    echo "self-test (warn-channel-separate-from-block-message-and-block-json): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (warn-channel-separate-from-block-message-and-block-json): FAIL (expected the WARN to stay out of the block-JSON reason string on stdout)" >&2
    failed=$((failed+1))
  fi
  if grep -q 'dead link target: docs/still-not-here\.md' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (warn-still-ledgered-alongside-a-real-block): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (warn-still-ledgered-alongside-a-real-block): FAIL (expected the dead link to still be ledgered even though a real gap also blocked)" >&2
    failed=$((failed+1))
  fi

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
