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

# ============================================================
# COLD-READER-LINT check (constitution §3 amendment 53d3bee "the cold-reader
# bar", operator directive 2026-07-06/07) — follows FUNCTIONAL-LINK's exact
# precedent immediately above: WARN-ONLY, never contributes to the block/gap
# verdict, never participates in cycle-counting/DONE-refusal, never touches
# stdout (a pure signal-ledger + stderr side-channel warn).
# ============================================================
# Scans the FINAL assistant message for a §3-format "Decision needed" block
# (heuristic: a line matching /Decision needed/i, OR the compact block's own
# "My pick:"/"Reply with:" markers, OR a markdown options table — any of
# these is treated as "this message is trying to be a §3 decision block").
# For every such block found, checks the SAME two structural signals
# needs-you.sh's cold-reader lint checks for --section decision (see that
# script's _ny_lint_decision_text for the shared heuristic definitions):
#   (b) >=1 concrete artifact anchor (URL / repo-path / id-pattern / SHA)
#   (c) per-option outcome text (an outcome connective near option markers,
#       or a two-column-plus table row — skipped, not failed, if the block
#       has no option-shaped structure to check outcomes against at all)
# Missing either -> ONE combined warn ledger_emit (gate=cold-reader-lint)
# + a stderr notice, exactly mirroring FUNCTIONAL-LINK's own emission shape.
# The (a) "no-context" background/prose check needs-you.sh also runs is
# DELIBERATELY NOT duplicated here: a chat message that already contains a
# "Decision needed:" line by definition has SOME context sentence right
# there (the §3 template's own "Context: <=5 lines" field) — re-checking
# prose-length against a live chat message (as opposed to a stored ledger
# --text string) risks false-warning on legitimately terse-but-complete
# decisions more than it catches real cold-reader violations; the artifact-
# anchor and per-option-outcome checks are the two that translate cleanly.
#
# FP expectation (same bar as FUNCTIONAL-LINK): a decision block that names
# its artifact only in a PRIOR chat message (not repeated in this one) will
# false-positive-warn missing-anchor; accepted for the same three reasons
# FUNCTIONAL-LINK's own FP note gives (never blocks, remediation is
# harmless even when transiently over-cautious, and re-deriving cross-
# message context is out of scope for a single-message mechanical check).
# Retirement condition: same as FUNCTIONAL-LINK — if ledger-visible FP rate
# proves high, extend the heuristic (e.g. scan the last 2 assistant
# messages instead of 1), not remove the check.

set -u

SCRIPT_NAME="stop-verdict-dispatcher.sh"
_SVD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$_SVD_DIR/lib/signal-ledger.sh"
# shellcheck disable=SC1091
source "$_SVD_DIR/lib/stop-hook-retry-guard.sh"
# shellcheck disable=SC1091
source "$_SVD_DIR/lib/nl-paths.sh"
# shellcheck disable=SC1091
{ source "$_SVD_DIR/lib/hook-reentry-guard.sh" 2>/dev/null; } || true

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
# _svd_refire_count_path <session_id> — persistent PER-SESSION counter of
# how many times this dispatcher has fired for this session, REGARDLESS
# of gap-set/failure-signature (distinct from retry-guard's own per-
# signature cycle_count above: this counts EVERY Stop invocation for the
# session, so a session that keeps generating a DIFFERENT gap-set each
# time — which would reset cycle_count to 1 every time and never hit the
# protocol-downgrade path — is still bounded).
# ----------------------------------------------------------------------
_svd_refire_count_path() {
  local sid="$1" short
  short=$(_retry_guard_session_short "$sid" 2>/dev/null || printf '%s' "$sid" | tr -c 'a-zA-Z0-9' '_' | cut -c1-24)
  printf '%s/stop-verdict-refires-%s.count' "${RETRY_GUARD_STATE_DIR:-.claude/state}" "$short"
}

# ----------------------------------------------------------------------
# _svd_session_is_automation — 0 (true) iff THIS Stop is running inside an
# automation-spawned / re-entrant session (NL_HOOK_REENTRY=1, exported by
# session-resumer.sh into every `claude` child it spawns; or the explicit
# NL_AUTOMATION_SESSION=1 signal, provided as a forward-compatible alias
# for any future non-resumer automation launcher). A HUMAN interactive
# session sets NEITHER and is therefore NOT automation.
#
# WHY THIS EXISTS (FIX-1, adversarial review of NL-FINDING-040): the
# Stop-refire ceiling below MUST NOT weaken the ADR-059 DONE-refusal
# never-downgrade rule for human interactive sessions — that rule is a
# core §1 honesty invariant. The ceiling is therefore SCOPED to automation
# sessions only: it caps the cascade threat (the actual incident driver —
# an automation-spawned session looping and re-forking the member-gate
# chain), while leaving a human session's DONE-refusal genuinely
# never-downgraded, byte-identical to origin/master. NOTE the layering:
# _svd_main's top-of-function hook_reentry_should_suppress guard already
# EXITS 0 for a cleanly-signalled NL_HOOK_REENTRY=1 child before the
# verdict tree runs at all; this ceiling is the defense-in-depth backstop
# for an automation session that reaches the verdict tree anyway (e.g. a
# NL_AUTOMATION_SESSION signal without the full reentry early-exit, or a
# partial env-propagation case).
# ----------------------------------------------------------------------
_svd_session_is_automation() {
  [[ "${NL_HOOK_REENTRY:-0}" == "1" ]] && return 0
  [[ "${NL_AUTOMATION_SESSION:-0}" == "1" ]] && return 0
  return 1
}

# ----------------------------------------------------------------------
# _svd_stop_refire_ceiling_check <session_id> — coordinator directive
# (operator concern, spawn-cascade incident): an ABSOLUTE per-session
# ceiling on how many times this dispatcher may fire+block for ONE
# AUTOMATION-SPAWNED session, independent of the DONE-refusal / cycle-count
# logic above.
#
# HONESTY SCOPING (FIX-1): this ceiling NEVER trips for a human interactive
# session — the first thing it does is return "0" (not tripped) unless
# _svd_session_is_automation is true. For a human session the DONE-refusal
# path below therefore behaves EXACTLY as origin/master does (genuinely
# never-downgraded — the §1 honesty invariant is untouched, and no ADR-059
# amendment is needed). For an AUTOMATION session, the DONE-refusal rule is
# not a meaningful honesty signal anyway (an automation-spawned resume
# nudge is not a human making a completion claim), so a genuinely-stuck
# automation session that re-fires this dispatcher — and EVERY fire forks 3
# member-gate subprocesses + end-manifest.sh — is capped: this trades
# "never downgrade an automation child's DONE" for "never let an automation
# session hang the machine in an unbounded Stop-refire loop", which was the
# actual incident driver.
#
# SEPARATE, HARD ceiling (default 5, env RETRY_GUARD_STOP_REFIRE_CEILING;
# 0 disables). Fail-OPEN on any I/O error (never blocks the caller from
# proceeding to its normal decision tree just because the counter file
# could not be read/written).
#
# Echoes "1" (tripped — caller must force-allow) or "0" (not tripped,
# proceed normally) on stdout. Side effect: increments+persists the
# counter ONLY for automation sessions (a human session never touches the
# counter file, so a human session leaves zero on-disk footprint from this
# mechanism).
# ----------------------------------------------------------------------
_svd_stop_refire_ceiling_check() {
  local sid="$1"
  # HONESTY SCOPING (FIX-1): human interactive session ⇒ never trip, never
  # even touch the counter — DONE-refusal stays identical to origin/master.
  _svd_session_is_automation || { printf '0'; return 0; }
  local ceiling="${RETRY_GUARD_STOP_REFIRE_CEILING:-5}"
  [[ "$ceiling" =~ ^[0-9]+$ ]] || ceiling=5
  if [[ "$ceiling" -eq 0 ]]; then
    printf '0'
    return 0
  fi
  local path
  path="$(_svd_refire_count_path "$sid")"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  local count=0
  if [[ -f "$path" ]]; then
    count="$(cat "$path" 2>/dev/null || echo 0)"
    count="${count//[!0-9]/}"
    [[ -z "$count" ]] && count=0
  fi
  count=$((count + 1))
  printf '%s' "$count" > "$path" 2>/dev/null || true
  if [[ "$count" -gt "$ceiling" ]]; then
    printf '1'
  else
    printf '0'
  fi
}

# ----------------------------------------------------------------------
# _svd_refire_ceiling_clear <session_id> — resets the per-session refire
# counter. Called on a clean pass (gap_count==0) so a session that
# eventually resolves its gaps doesn't carry a stale high count into some
# LATER unrelated block sequence within the same session id.
# ----------------------------------------------------------------------
_svd_refire_ceiling_clear() {
  local sid="$1" path
  path="$(_svd_refire_count_path "$sid")"
  rm -f "$path" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# _svd_now_ms — current epoch time in milliseconds. Best-effort: falls
# back to whole-second * 1000 on a `date` build without %3N support (the
# turn-trace deltas below just become second-granular in that case, never
# an error). NL Observability Program Wave O, task O.1 (specs-o §O.1
# deliverable 2 / contract C2 turn-trace).
# ----------------------------------------------------------------------
_svd_now_ms() {
  local ms
  ms=$(date +%s%3N 2>/dev/null)
  if [[ "$ms" =~ ^[0-9]+$ ]] && [[ "${#ms}" -ge 13 ]]; then
    printf '%s' "$ms"
  else
    printf '%s000' "$(date +%s 2>/dev/null || echo 0)"
  fi
}

# ----------------------------------------------------------------------
# _SVD_TRACE_HOOKS (array of compact JSON objects, one per timed member)
# accumulated during this Stop's run, emitted as ONE turn-trace ledger
# event (contract C2) at every exit path of _svd_main. Reset per-process
# (this dispatcher never handles more than one Stop per invocation).
# ----------------------------------------------------------------------
_SVD_TRACE_HOOKS=()

# ----------------------------------------------------------------------
# _svd_trace_record <basename> <ms> <verdict>
#   Appends one compact JSON object to _SVD_TRACE_HOOKS. verdict is one of
#   allow|block|warn|n/a (contract C2's turn-trace detail shape).
# ----------------------------------------------------------------------
_svd_trace_record() {
  local name="$1" ms="$2" verdict="$3"
  if command -v jq >/dev/null 2>&1; then
    _SVD_TRACE_HOOKS+=("$(jq -cn --arg n "$name" --argjson ms "${ms:-0}" --arg v "$verdict" '{n:$n, ms:$ms, v:$v}' 2>/dev/null)")
  else
    _SVD_TRACE_HOOKS+=("{\"n\":\"$(_svd_json_escape "$name")\",\"ms\":${ms:-0},\"v\":\"$(_svd_json_escape "$verdict")\"}")
  fi
}

# ----------------------------------------------------------------------
# _svd_emit_turn_trace — builds the contract-C2 compact JSON
# ({"hooks":[...],"total_ms":N}) from _SVD_TRACE_HOOKS and emits ONE
# turn-trace ledger event. Best-effort/never fails: an empty hooks array
# (e.g. gap_count==0 fast exit before any member ran — should not happen
# in the live path since members always run before the pass/fail branch,
# but defensive regardless) still emits a valid, if empty, trace.
# ----------------------------------------------------------------------
_svd_emit_turn_trace() {
  local total_ms="${1:-0}"
  local hooks_json="[]"
  if [[ "${#_SVD_TRACE_HOOKS[@]}" -gt 0 ]]; then
    local IFS=,
    hooks_json="[${_SVD_TRACE_HOOKS[*]}]"
  fi
  local detail
  detail=$(printf '{"hooks":%s,"total_ms":%s}' "$hooks_json" "${total_ms:-0}")
  _svd_ledger "turn-trace" "$detail"
}

# ----------------------------------------------------------------------
# _svd_emit_stop_and_trace <start_ms> <verdict_detail>
#   ONE call site every exit path of _svd_main funnels through: emits the
#   session-stop lifecycle event (contract C2) + the turn-trace event
#   (contract C2 / this task's deliverable 2) together, so every Stop —
#   pass, block, or protocol-downgrade — records both exactly once.
# ----------------------------------------------------------------------
_svd_emit_stop_and_trace() {
  local start_ms="$1" verdict_detail="$2"
  local end_ms total_ms
  end_ms=$(_svd_now_ms)
  total_ms=$((end_ms - start_ms))
  [[ "$total_ms" -lt 0 ]] && total_ms=0
  _svd_ledger "session-stop" "$verdict_detail"
  _svd_emit_turn_trace "$total_ms"
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
# _svd_message_has_decision_block <text>
#   True (0) iff $text carries the constitution-§3 "Decision needed" block
#   SHAPE: a POSITIVE "Decision needed" cue line AND an options signal (a
#   "Reply with:"/"My pick:"/"Option" marker, or a markdown Options table
#   row). BOTH are required — the §3 template always pairs a "Decision
#   needed:" header (bullet 1) with an Options block (bullets 3-5), so a
#   bare "decision needed" SUBSTRING, a lone "My pick:", or an unrelated
#   data table no longer trips the check.
#
#   nl-issue [51]: the prior naive substring match ('decision needed' OR
#   'my pick:' OR any table row) false-positive-warned on ordinary prose —
#   most notably NEGATED forms like "no decision needed here" and
#   "without a decision, this ships". Two guards fix that:
#     (1) the cue is anchored to the START of a line (after optional
#         markdown emphasis / list-number / blockquote marker chars), so a
#         mid-sentence "...no decision needed here" — where the phrase is
#         not line-initial — and a line literally opening "No decision
#         needed" (the leading "No" is a letter, not an allowed marker
#         char) both fail to match; and
#     (2) an options signal is ALSO required, so negated prose that happens
#         to mention a decision without any §3 Options structure is never
#         treated as a decision block.
#   Still WARN-only: this only gates whether _svd_cold_reader_lint_check
#   proceeds to its (WARN-only) anchor/outcome checks — it never blocks and
#   never touches the exit code (see the header COLD-READER-LINT block).
# ----------------------------------------------------------------------
_svd_message_has_decision_block() {
  local text="$1"
  # (1) Positive, line-anchored "Decision needed" cue (excludes negations:
  #     a leading negation word is a letter, not an allowed marker char, so
  #     it breaks the anchor).
  printf '%s' "$text" | grep -qiE '^[[:space:]*_>#.)(0-9-]*decision needed' || return 1
  # (2) An options signal: a §3 Options-block marker or a markdown table row.
  printf '%s' "$text" | grep -qiE 'reply with:|my pick:|(^|[^[:alnum:]])options?([[:space:]]|:)|^[[:space:]]*\|.*\|.*\|'
}

# ----------------------------------------------------------------------
# _svd_text_has_artifact_anchor <text>
#   Mirrors needs-you.sh's _ny_lint_decision_text check (b): a URL, a
#   repo-path-shaped token, or an id/SHA pattern.
# ----------------------------------------------------------------------
_svd_text_has_artifact_anchor() {
  local text="$1"
  printf '%s' "$text" | grep -qE 'https?://[^[:space:]]+' && return 0
  printf '%s' "$text" | grep -qE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.[A-Za-z0-9]+' && return 0
  printf '%s' "$text" | grep -qE '[A-Za-z0-9_.-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+' && return 0
  printf '%s' "$text" | grep -qE '\b[A-Z]{2,}(-[A-Z0-9]+)*-[0-9]+\b' && return 0
  printf '%s' "$text" | grep -qE '#[0-9]+\b' && return 0
  printf '%s' "$text" | grep -qE '\b[0-9a-f]{7,40}\b' && return 0
  return 1
}

# ----------------------------------------------------------------------
# _svd_text_has_option_outcomes <text>
#   Mirrors needs-you.sh's _ny_lint_decision_text check (c): if the text
#   has option-shaped structure (Option/My pick/Reply with markers or a
#   table row), at least one outcome connective or a >=2-column table row
#   must be present. Returns 0 (pass) when there is no option structure to
#   check at all (nothing to fail against).
# ----------------------------------------------------------------------
_svd_text_has_option_outcomes() {
  local text="$1"
  printf '%s' "$text" | grep -qiE '(^|[^A-Za-z])(option|my pick|reply with)([^A-Za-z]|$)|^[[:space:]]*\|.*\|.*\|' || return 0
  printf '%s' "$text" | grep -qE -- '->|→|\bmeans\b|\btriggers?\b|\bresults? in\b|\bchanges?\b|\bhappens\b|^[[:space:]]*\|[^|]*\|[^|]*\|'
}

# ----------------------------------------------------------------------
# _svd_cold_reader_lint_check <transcript_path>
#   WARN-only (see header comment above). If the final assistant message
#   contains a §3-format decision block missing an artifact anchor or
#   per-option outcome text, emits ONE combined signal-ledger "warn" event
#   (gate cold-reader-lint) + a stderr notice. Never writes to stdout, never
#   returns non-zero — same fail-open contract as
#   _svd_functional_link_check.
# ----------------------------------------------------------------------
_svd_cold_reader_lint_check() {
  local transcript_path="$1"
  local text
  text=$(_svd_final_assistant_message "$transcript_path")
  [[ -n "$text" ]] || return 0
  _svd_message_has_decision_block "$text" || return 0

  local -a missing=()
  _svd_text_has_artifact_anchor "$text" || missing+=("no-artifact-anchor")
  _svd_text_has_option_outcomes "$text" || missing+=("no-per-option-outcomes")

  if [[ "${#missing[@]}" -gt 0 ]]; then
    local joined; joined=$(IFS=,; echo "${missing[*]}")
    local detail="cold-reader-lint: Decision needed block missing: ${joined}"
    _svd_ledger "warn" "$detail"
    {
      echo ""
      echo "---- COLD-READER-LINT (WARN, non-blocking) ----"
      echo "  [missing] ${joined}"
      echo "    -> a reader with zero session context could not act on this decision block alone (constitution §3 'the cold-reader bar', 53d3bee). Name the concrete artifact (path/URL/id) and say what changes per option."
    } >&2
  fi
  return 0
}

# ----------------------------------------------------------------------
# Main (production execution) — skipped entirely under --self-test.
# ----------------------------------------------------------------------
_svd_main() {
  local _svd_start_ms
  _svd_start_ms=$(_svd_now_ms)
  _SVD_TRACE_HOOKS=()

  local input=""
  if [[ ! -t 0 ]]; then
    input=$(cat 2>/dev/null || echo "")
  fi
  local session_id
  session_id=$(retry_guard_session_id "$input")

  # NL-FINDING-040 keystone guard: this dispatcher forks real subprocesses
  # on EVERY live Stop (the 3 member gates via _svd_run_report, end-
  # manifest.sh write+validate, needs-you.sh add on protocol-downgrade) —
  # there is no way to "run its verification logic but never spawn" because
  # the logic IS delegated via subprocess. Under NL_HOOK_REENTRY=1 (an
  # automation-spawned/re-entrant child — see lib/hook-reentry-guard.sh)
  # this dispatcher deliberately skips the whole verification+fork chain
  # and exits 0: an automation-spawned resume nudge is not the place a
  # fresh honesty/work-integrity ceremony needs to fire (the ORIGINAL
  # session's own Stop already governs that work), and letting it run
  # would re-fork 3+ member-gate processes plus end-manifest.sh on every
  # such Stop — exactly the cascade-amplifying pattern this guard exists to
  # cut off. A normal interactive session (NL_HOOK_REENTRY unset) is
  # completely unaffected.
  if command -v hook_reentry_should_suppress >/dev/null 2>&1 && hook_reentry_should_suppress; then
    hook_reentry_note "stop-verdict-dispatcher" 2>/dev/null || true
    echo "[stop-verdict-dispatcher] reentrant/automation-spawned invocation — skipping verification+fork chain (NL-FINDING-040 guard)" >&2
    exit 0
  fi

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

  # COLD-READER-LINT check (constitution §3 amendment 53d3bee): WARN-only,
  # same non-contributing shape as FUNCTIONAL-LINK immediately above — see
  # the header comment block for the full mechanism.
  _svd_cold_reader_lint_check "$transcript_path"

  # ADR 059 D6 / specs-e §E.12: write + validate THIS session's end-manifest
  # BEFORE the member gates run, so work-integrity-gate.sh's manifest-scoping
  # (_wig_resolve_manifest_path) finds a manifest on disk for this Stop, and
  # any validator FAILURE is folded into the aggregated verdict below as an
  # "end-manifest" gap alongside the three member gates' own gaps.
  local all_gaps=""
  local _svd_step_t0 _svd_step_t1
  _svd_step_t0=$(_svd_now_ms)
  local manifest_gaps
  manifest_gaps=$(_svd_write_and_validate_manifest "$repo_root" "$transcript_path" "$session_id")
  _svd_step_t1=$(_svd_now_ms)
  _svd_trace_record "end-manifest" "$((_svd_step_t1 - _svd_step_t0))" "$([[ -n "$manifest_gaps" ]] && echo "block" || echo "allow")"
  [[ -n "$manifest_gaps" ]] && all_gaps+="${manifest_gaps}"$'\n'

  # Aggregate every member gate's --report output. Each member is timed
  # individually (specs-o §O.1 deliverable 2 / contract C2: "each
  # aggregator times its own chain members via date +%s%3N deltas") and
  # recorded into _SVD_TRACE_HOOKS for the ONE turn-trace event this Stop
  # emits at its exit path below.
  local gate_script gate_name
  for gate_script in "${_SVD_MEMBER_GATES[@]}"; do
    gate_name="${gate_script%.sh}"
    _svd_step_t0=$(_svd_now_ms)
    local out
    out=$(_svd_run_report "$gate_script" "" "$transcript_path" "$session_id")
    _svd_step_t1=$(_svd_now_ms)
    _svd_trace_record "$gate_name" "$((_svd_step_t1 - _svd_step_t0))" "$([[ -n "$out" ]] && echo "block" || echo "allow")"
    [[ -n "$out" ]] && all_gaps+="${out}"$'\n'
  done

  local gap_count
  gap_count=$(printf '%s' "$all_gaps" | grep -c '^{' 2>/dev/null || echo 0)
  gap_count=$(printf '%s' "$gap_count" | tr -d '[:space:]')
  [[ -z "$gap_count" ]] && gap_count=0

  if [[ "$gap_count" -eq 0 ]]; then
    _svd_refire_ceiling_clear "$session_id"
    _svd_ledger "stop-cycle" "gaps=0 verdict=pass"
    _svd_emit_stop_and_trace "$_svd_start_ms" "verdict=pass gaps=0"
    exit 0
  fi

  # HARD PER-SESSION STOP-REFIRE CEILING (coordinator directive, spawn-
  # cascade incident; AUTOMATION-SCOPED per FIX-1): checked BEFORE the
  # DONE-refusal/cycle-count tree below. It trips ONLY for automation-
  # spawned sessions (_svd_session_is_automation) — a human interactive
  # session's DONE-refusal below is genuinely never-downgraded, identical
  # to origin/master. See _svd_stop_refire_ceiling_check's own header for
  # the full rationale. A tripped ceiling force-allows the (automation)
  # session to end: loud ledger event, stderr explanation, exit 0.
  local refire_tripped
  refire_tripped="$(_svd_stop_refire_ceiling_check "$session_id")"
  if [[ "$refire_tripped" == "1" ]]; then
    _svd_ledger "stop-cycle" "gaps=${gap_count} verdict=refire-ceiling-tripped"
    _svd_ledger "stop-refire-ceiling-tripped" "session=${session_id} (automation-spawned) exceeded ${RETRY_GUARD_STOP_REFIRE_CEILING:-5} dispatcher fires; force-allowing session end"
    cat >&2 <<MSG
================================================================
[stop-verdict-dispatcher] STOP-REFIRE CEILING TRIPPED (automation-scoped)
================================================================
This AUTOMATION-SPAWNED session's dispatcher has now fired more than
${RETRY_GUARD_STOP_REFIRE_CEILING:-5} times (regardless of whether the
gap-set changed each time, which would otherwise keep resetting the
ordinary cycle counter). To guarantee an automation session can never
hang a machine in an unbounded Stop-refire loop, it is FORCE-ALLOWED to
end now. This ceiling is AUTOMATION-ONLY — a human interactive session's
DONE-refusal is never subject to it. ${gap_count} gap(s) remain
unresolved; they are NOT recorded to unresolved-gaps.jsonl by this path
(the ceiling is a spawn breaker, not the designed protocol-downgrade —
review this session's transcript directly for what actually happened).
================================================================
MSG
    _svd_emit_stop_and_trace "$_svd_start_ms" "verdict=refire-ceiling-tripped gaps=${gap_count}"
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
    _svd_emit_block_message "$all_gaps" "$gap_count" 1 "$session_id"
    _svd_emit_stop_and_trace "$_svd_start_ms" "verdict=block-done-refusal gaps=${gap_count} cycle=${cycle_count}"
    exit 2
  fi

  if [[ "$cycle_count" -le 1 ]]; then
    # FIRST blocking Stop this session for this gap-set.
    _svd_ledger "stop-cycle" "gaps=${gap_count} cycle=${cycle_count} verdict=block-first"
    _svd_ledger "block" "combined verdict: ${gap_count} gap(s) across member gates (cycle ${cycle_count})"
    _svd_emit_block_message "$all_gaps" "$gap_count" 0 "$session_id"
    _svd_emit_stop_and_trace "$_svd_start_ms" "verdict=block-first gaps=${gap_count} cycle=${cycle_count}"
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
      # --mechanical (cockpit-roadmap-redesign Task 4, A1): a mechanical
      # dispatcher call, no live actor to retry a lint block — see
      # session-resumer.sh's identical note for why this is passed even
      # though --section inflight is not lint-checked today.
      bash "$nyu" add --section inflight \
        --text "Unresolved Stop-gate gap (${gate_f}/${check_f}): ${msg_f}" \
        --session "$session_id" --mechanical >/dev/null 2>&1 || true
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

  _svd_emit_stop_and_trace "$_svd_start_ms" "verdict=protocol-downgrade gaps=${gap_count} cycle=${cycle_count}"
  exit 0
}

# ----------------------------------------------------------------------
# _svd_write_full_verdict_file <session_id> <text>
#   nl-issue [42]: when the block-JSON reason field is truncated (see
#   _svd_emit_block_message below), the FULL combined verdict is written
#   here so the truncation note can point at a real file. Path follows
#   _svd_refire_count_path's convention (${RETRY_GUARD_STATE_DIR:-.claude/
#   state} + per-session-short filename) so the self-test's per-scenario
#   RETRY_GUARD_STATE_DIR sandboxing automatically applies. Echoes the
#   ABSOLUTE path on success, empty on any failure (best-effort: a state-
#   write failure must never break the block JSON itself).
# ----------------------------------------------------------------------
_svd_write_full_verdict_file() {
  local sid="${1:-session}" text="$2"
  local short dir path
  short=$(_retry_guard_session_short "$sid" 2>/dev/null || printf '%s' "$sid" | tr -c 'a-zA-Z0-9' '_' | cut -c1-24)
  dir="${RETRY_GUARD_STATE_DIR:-.claude/state}"
  case "$dir" in
    /*|[A-Za-z]:[/\\]*) ;;
    *) dir="${PWD}/${dir}" ;;
  esac
  mkdir -p "$dir" 2>/dev/null || { printf ''; return 0; }
  path="${dir}/stop-verdict-full-${short}.txt"
  if printf '%s\n' "$text" > "$path" 2>/dev/null; then
    printf '%s' "$path"
  else
    printf ''
  fi
  return 0
}

# ----------------------------------------------------------------------
# _svd_emit_block_message <all_gaps_jsonl> <gap_count> <is_done_refusal> \
#                         [session_id]
#   Builds and prints the ONE combined block message (ADR 059 D1), grouped
#   per gate, each gap with its pin-d remediation. Prints the Stop-hook
#   contract JSON to stdout and the human-readable stanza to stderr, then
#   returns (caller does the exit).
#
#   nl-issue [42] (two live incidents 2026-07-07): hook stderr NEVER
#   reaches the blocked session's context — the stdout JSON's reason field
#   is the ONLY text the session sees, so the combined verdict itself
#   (per-gate [gate/check] lines + pin-d remediation) is carried IN the
#   reason, bounded by STOP_VERDICT_REASON_MAX_CHARS (default 2000). On
#   truncation the reason names the dropped-gap count and the full-verdict
#   state file (_svd_write_full_verdict_file). The stderr stanza is kept
#   unchanged for humans/logs. PRESENTATION ONLY — verdict logic, cycle
#   counting, ceiling and DONE-refusal semantics are untouched.
# ----------------------------------------------------------------------
_svd_emit_block_message() {
  local all_gaps="$1" gap_count="$2" is_done_refusal="$3" session_id="${4:-}"

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

  # nl-issue [42]: build the reason from the SAME per-gate verdict the
  # stderr stanza above shows — the reason is what actually reaches the
  # blocked session. all_gaps is already grouped per gate by construction
  # (_svd_main appends end-manifest first, then each member gate's
  # --report output in _SVD_MEMBER_GATES order), so one linear pass
  # preserves the same per-gate grouping.
  local reason_max="${STOP_VERDICT_REASON_MAX_CHARS:-2000}"
  [[ "$reason_max" =~ ^[0-9]+$ ]] || reason_max=2000

  local header
  if [[ "$is_done_refusal" == "1" ]]; then
    header="Stop-verdict dispatcher BLOCKED (DONE-refusal: never downgraded): ${gap_count} gap(s) across the member Stop gates, listed below. A verification-class gap is present while the final message claims DONE: — change the marker to PAUSING:/BLOCKED: naming the gap, or actually finish the work. Fix ALL gaps (or take each named escape hatch), then re-end the turn."
  else
    header="Stop-verdict dispatcher BLOCKED (combined verdict): ${gap_count} gap(s) across the member Stop gates, listed below. Fix ALL of them (or take the named escape hatch per gap), then re-end the turn — one combined verdict, not serial whack-a-mole."
  fi

  local reason="$header" full_text="" entries_added=0 truncated=0
  local rline rgate_f rcheck_f rmsg_f entry
  while IFS= read -r rline; do
    [[ -z "$rline" ]] && continue
    if command -v jq >/dev/null 2>&1; then
      rgate_f=$(_svd_strip_cr "$(printf '%s' "$rline" | jq -r '.gate // "?"' 2>/dev/null)")
      rcheck_f=$(_svd_strip_cr "$(printf '%s' "$rline" | jq -r '.check // "?"' 2>/dev/null)")
      rmsg_f=$(_svd_strip_cr "$(printf '%s' "$rline" | jq -r '.message // ""' 2>/dev/null)")
    else
      rgate_f="?"; rcheck_f="?"; rmsg_f="$rline"
    fi
    entry=$'\n'"[${rgate_f}/${rcheck_f}] ${rmsg_f}"$'\n'"  -> $(_svd_pin_d_remediation "$rgate_f" "$rcheck_f")"
    full_text+="$entry"
    if [[ "$truncated" -eq 0 ]]; then
      if [[ $(( ${#reason} + ${#entry} )) -le "$reason_max" ]]; then
        reason+="$entry"
        entries_added=$((entries_added + 1))
      else
        truncated=1
      fi
    fi
  done <<< "$all_gaps"

  if [[ "$truncated" -eq 1 ]]; then
    local remaining=$((gap_count - entries_added))
    local full_path
    full_path=$(_svd_write_full_verdict_file "$session_id" "${header}${full_text}")
    if [[ -n "$full_path" ]]; then
      reason+=$'\n'"... and ${remaining} more gap(s) (reason capped at ${reason_max} chars) — full combined verdict: ${full_path}"
    else
      reason+=$'\n'"... and ${remaining} more gap(s) (reason capped at ${reason_max} chars; full-verdict state file could not be written) — re-run each member gate locally (bash <gate>.sh, normal mode) for the rest."
    fi
  fi

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

  # Wave O task O.1 (specs-o §O.1 deliverable 2, contract C2): the clean
  # pass path emits session-stop + exactly ONE turn-trace event, and the
  # turn-trace detail is valid nested JSON naming each member gate + a
  # numeric total_ms.
  if grep -q '"gate":"stop-verdict-dispatcher".*"event":"session-stop"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (o1-session-stop-emitted-on-clean-pass): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (o1-session-stop-emitted-on-clean-pass): FAIL (expected a stop-verdict-dispatcher/session-stop ledger line)" >&2
    failed=$((failed+1))
  fi
  TT_COUNT=$(grep -c '"event":"turn-trace"' "$SIGNAL_LEDGER_PATH" 2>/dev/null | tr -d ' ')
  if [[ "$TT_COUNT" == "1" ]]; then
    echo "self-test (o1-exactly-one-turn-trace-event-per-stop): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (o1-exactly-one-turn-trace-event-per-stop): FAIL (expected 1 turn-trace line, got ${TT_COUNT})" >&2
    failed=$((failed+1))
  fi
  if command -v jq >/dev/null 2>&1; then
    TT_LINE=$(grep '"event":"turn-trace"' "$SIGNAL_LEDGER_PATH" 2>/dev/null | tail -1)
    TT_DETAIL=$(printf '%s' "$TT_LINE" | jq -r '.detail' 2>/dev/null)
    TT_NHOOKS=$(printf '%s' "$TT_DETAIL" | jq -r '.hooks | length' 2>/dev/null)
    TT_TOTAL=$(printf '%s' "$TT_DETAIL" | jq -r '.total_ms' 2>/dev/null)
    TT_HAS_WIG=$(printf '%s' "$TT_DETAIL" | jq -r '.hooks[] | select(.n=="work-integrity-gate") | .n' 2>/dev/null)
    TT_HAS_MANIFEST=$(printf '%s' "$TT_DETAIL" | jq -r '.hooks[] | select(.n=="end-manifest") | .n' 2>/dev/null)
    if [[ "$TT_NHOOKS" -ge 3 ]] && [[ "$TT_TOTAL" =~ ^[0-9]+$ ]] && [[ "$TT_HAS_WIG" == "work-integrity-gate" ]] && [[ "$TT_HAS_MANIFEST" == "end-manifest" ]]; then
      echo "self-test (o1-turn-trace-detail-names-members-and-numeric-total-ms): PASS (hooks=${TT_NHOOKS} total_ms=${TT_TOTAL})" >&2
      passed=$((passed+1))
    else
      echo "self-test (o1-turn-trace-detail-names-members-and-numeric-total-ms): FAIL (nhooks=${TT_NHOOKS} total=${TT_TOTAL} wig=${TT_HAS_WIG} manifest=${TT_HAS_MANIFEST}, detail=${TT_DETAIL})" >&2
      failed=$((failed+1))
    fi
  fi

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
  # Wave O task O.1: the BLOCK path also emits session-stop + turn-trace
  # (not just the clean-pass path proven in Scenario 1 above), with the
  # session-stop detail naming the block verdict.
  if grep -q '"gate":"stop-verdict-dispatcher".*"event":"session-stop".*verdict=block-first' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (o1-session-stop-emitted-on-block-path-with-verdict-detail): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (o1-session-stop-emitted-on-block-path-with-verdict-detail): FAIL (expected verdict=block-first in the session-stop detail)" >&2
    failed=$((failed+1))
  fi
  if grep -q '"gate":"stop-verdict-dispatcher".*"event":"turn-trace"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (o1-turn-trace-emitted-on-block-path): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (o1-turn-trace-emitted-on-block-path): FAIL" >&2
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

  # _run_dispatcher_auto — like _run_dispatcher but exports the explicit
  # NL_AUTOMATION_SESSION=1 automation signal into the child's env (NOT
  # NL_HOOK_REENTRY, which would trip the top-of-_svd_main full-suppress
  # early-exit and never reach the verdict tree the ceiling lives in — see
  # _svd_session_is_automation's header). This is how the FIX-2 ceiling
  # scenarios below drive a session that (a) reaches the verdict tree and
  # (b) is classified automation, so the automation-scoped ceiling is
  # genuinely exercised end-to-end through the REAL script invocation.
  _run_dispatcher_auto() {
    local hooks_dir="$1" repo_cwd="$2" transcript="$3" sid="$4"
    (
      cd "$repo_cwd" || exit 99
      export STOP_VERDICT_DISPATCHER_TRANSCRIPT="$transcript"
      export CLAUDE_SESSION_ID="$sid"
      export NL_AUTOMATION_SESSION=1
      printf '{"transcript_path":"%s","session_id":"%s"}' "$transcript" "$sid" \
        | bash "$hooks_dir/stop-verdict-dispatcher.sh" >"$tmproot/last-stdout.txt" 2>"$tmproot/last-stderr.txt"
      echo $?
    )
  }

  # ================================================================
  # Scenario 18 (FIX-2a — AUTOMATION-SCOPED STOP-REFIRE CEILING): an
  # automation-spawned session (NL_AUTOMATION_SESSION=1) with a persistent
  # DONE-claim + verification-class gap blocks (exit 2) on fires 1..ceiling,
  # then FORCE-ALLOWS (exit 0) on fire ceiling+1 with the automation-scoped
  # ceiling-tripped message. Ceiling pinned to 2 so the scenario is fast
  # and deterministic. Exercised through the REAL script invocation
  # (_run_dispatcher_auto), mirroring Scenario 5's DONE-claim replication.
  # ================================================================
  _setup_scenario s18
  export RETRY_GUARD_STOP_REFIRE_CEILING=2
  HOOKS=$(_build_dispatcher_repo s18)
  REPO="$tmproot/s18/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    { echo "# Plan: s18-plan"; echo "Status: ACTIVE"; echo; echo "## Tasks"; echo "- [ ] A.1 do the thing"; } > docs/plans/s18-plan.md; \
    git add -A; git commit -q -m seed )
  TFILE="$tmproot/s18/done-transcript.jsonl"
  {
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s/docs/plans/s18-plan.md"}}]}}\n' "$REPO"
    printf '%s\n' "$(jq -cn '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Shipped everything.\n\nDONE: merged abc1234"}]}}' 2>/dev/null)"
  } > "$TFILE"
  RC1=$(_run_dispatcher_auto "$HOOKS" "$REPO" "$TFILE" "sess-s18")
  _expect "automation-ceiling-fire-1-blocks" "$RC1" "2"
  RC2=$(_run_dispatcher_auto "$HOOKS" "$REPO" "$TFILE" "sess-s18")
  _expect "automation-ceiling-fire-2-blocks" "$RC2" "2"
  RC3=$(_run_dispatcher_auto "$HOOKS" "$REPO" "$TFILE" "sess-s18")
  _expect "automation-ceiling-fire-3-force-allows-exit-0" "$RC3" "0"
  if grep -q "STOP-REFIRE CEILING TRIPPED" "$tmproot/last-stderr.txt" 2>/dev/null \
     && grep -qi "automation" "$tmproot/last-stderr.txt" 2>/dev/null \
     && grep -qi "gap(s) remain" "$tmproot/last-stderr.txt" 2>/dev/null; then
    echo "self-test (automation-ceiling-tripped-message-with-gaps-remain-count): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (automation-ceiling-tripped-message-with-gaps-remain-count): FAIL (expected automation-scoped ceiling-tripped message + gaps-remain count on stderr)" >&2
    cat "$tmproot/last-stderr.txt" 2>/dev/null >&2
    failed=$((failed+1))
  fi
  if grep -q '"event":"stop-refire-ceiling-tripped"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (automation-ceiling-tripped-ledger-event): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (automation-ceiling-tripped-ledger-event): FAIL (expected a stop-refire-ceiling-tripped ledger event)" >&2
    failed=$((failed+1))
  fi
  unset RETRY_GUARD_STOP_REFIRE_CEILING

  # ================================================================
  # Scenario 19 (FIX-2b — HUMAN SESSION NEVER FORCE-ALLOWED): the SAME
  # DONE-claim + verification-class gap, the SAME low ceiling, but a HUMAN
  # (non-automation) session — no NL_AUTOMATION_SESSION, no NL_HOOK_REENTRY.
  # It must block (exit 2) on EVERY fire, well past the ceiling count,
  # proving FIX-1: a human DONE-refusal is genuinely never-downgraded,
  # identical to origin/master. Run 4 times (ceiling is 2) — every one
  # blocks.
  # ================================================================
  _setup_scenario s19
  export RETRY_GUARD_STOP_REFIRE_CEILING=2
  HOOKS=$(_build_dispatcher_repo s19)
  REPO="$tmproot/s19/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    { echo "# Plan: s19-plan"; echo "Status: ACTIVE"; echo; echo "## Tasks"; echo "- [ ] A.1 do the thing"; } > docs/plans/s19-plan.md; \
    git add -A; git commit -q -m seed )
  TFILE="$tmproot/s19/done-transcript.jsonl"
  {
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s/docs/plans/s19-plan.md"}}]}}\n' "$REPO"
    printf '%s\n' "$(jq -cn '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Shipped everything.\n\nDONE: merged abc1234"}]}}' 2>/dev/null)"
  } > "$TFILE"
  human_all_blocked=1
  for _fire in 1 2 3 4; do
    RCx=$(_run_dispatcher "$HOOKS" "$REPO" "$TFILE" "sess-s19")
    [[ "$RCx" == "2" ]] || human_all_blocked=0
  done
  if [[ "$human_all_blocked" == "1" ]]; then
    echo "self-test (human-session-DONE-refusal-never-force-allowed-past-ceiling): PASS (exit 2 on all 4 fires, ceiling=2)" >&2
    passed=$((passed+1))
  else
    echo "self-test (human-session-DONE-refusal-never-force-allowed-past-ceiling): FAIL (a human session was force-allowed past the ceiling — FIX-1 honesty invariant violated)" >&2
    cat "$tmproot/last-stderr.txt" 2>/dev/null >&2
    failed=$((failed+1))
  fi
  # And prove the human path never even wrote the ceiling counter file
  # (zero on-disk footprint from this mechanism for a human session).
  if ! ls "$RETRY_GUARD_STATE_DIR"/stop-verdict-refires-*.count >/dev/null 2>&1; then
    echo "self-test (human-session-leaves-no-ceiling-counter-file): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (human-session-leaves-no-ceiling-counter-file): FAIL (a human session wrote a refire-counter file; the ceiling must be automation-only)" >&2
    failed=$((failed+1))
  fi
  unset RETRY_GUARD_STOP_REFIRE_CEILING

  # Scenario 20 (task cold-reader-lint, constitution §3 amendment 53d3bee):
  # a "Decision needed" block with NO artifact anchor and NO per-option
  # outcome text warns (ledger + stderr), never blocks (exit 0, no real gap
  # in this fixture).
  # ================================================================
  _setup_scenario s20
  HOOKS=$(_build_dispatcher_repo s20)
  REPO="$tmproot/s20/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T20=$(_write_transcript "$tmproot/s20" $'Decision needed: ship tonight?\nOption A or option B.\nMy pick: A.\n\nDONE: nothing to report')
  RC20=$(_run_dispatcher "$HOOKS" "$REPO" "$T20" "sess-s20")
  _expect "cold-reader-lint-warn-never-blocks" "$RC20" "0"
  if grep -q '"gate":"stop-verdict-dispatcher".*cold-reader-lint.*no-artifact-anchor' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (cold-reader-lint-anchorless-decision-block-warns): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (cold-reader-lint-anchorless-decision-block-warns): FAIL (expected a cold-reader-lint warn naming no-artifact-anchor)" >&2
    failed=$((failed+1))
  fi
  if grep -q 'no-per-option-outcomes' "$tmproot/last-stderr.txt" 2>/dev/null; then
    echo "self-test (cold-reader-lint-no-outcome-text-also-flagged): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (cold-reader-lint-no-outcome-text-also-flagged): FAIL (expected no-per-option-outcomes on stderr too)" >&2
    failed=$((failed+1))
  fi
  if grep -q "cold-reader bar" "$tmproot/last-stderr.txt" 2>/dev/null; then
    echo "self-test (cold-reader-lint-remediation-names-the-bar): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (cold-reader-lint-remediation-names-the-bar): FAIL (expected the remediation text to reference the cold-reader bar)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 21: a WELL-FORMED decision block (repo-path anchor + a table
  # whose column 2 carries per-option outcomes) never warns.
  # ================================================================
  _setup_scenario s21
  HOOKS=$(_build_dispatcher_repo s21)
  REPO="$tmproot/s21/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T21=$(_write_transcript "$tmproot/s21" $'Decision needed: ship the change in adapters/claude-code/scripts/needs-you.sh tonight?\n| Option | What happens |\n|---|---|\n| Ship | goes live now |\n| Wait | ships Monday |\nMy pick: ship.\n\nDONE: nothing to report')
  RC21=$(_run_dispatcher "$HOOKS" "$REPO" "$T21" "sess-s21")
  _expect "cold-reader-lint-well-formed-block-never-blocks" "$RC21" "0"
  if ! grep -q '"gate":"stop-verdict-dispatcher".*cold-reader-lint' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (cold-reader-lint-well-formed-block-no-warn): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (cold-reader-lint-well-formed-block-no-warn): FAIL (a well-formed decision block with an anchor + table outcomes was incorrectly warned on)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 22: ordinary prose with NO decision-block markers at all is
  # never scanned (proves the check only fires on messages that look like
  # a decision ask, matching needs-you.sh's own section-scoping precedent).
  # ================================================================
  _setup_scenario s22
  HOOKS=$(_build_dispatcher_repo s22)
  REPO="$tmproot/s22/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T22=$(_write_transcript "$tmproot/s22" $'Just shipped the fix, no decision needed here.\n\nDONE: nothing to report')
  RC22=$(_run_dispatcher "$HOOKS" "$REPO" "$T22" "sess-s22")
  _expect "cold-reader-lint-ordinary-prose-never-blocks" "$RC22" "0"
  if ! grep -q '"gate":"stop-verdict-dispatcher".*cold-reader-lint' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (cold-reader-lint-ordinary-prose-not-scanned): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (cold-reader-lint-ordinary-prose-not-scanned): FAIL (ordinary prose with no decision-block markers was incorrectly warned on)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 23: a WARN never appears in the combined BLOCK message and
  # never contributes to gap_count — a real blocking gap (no marker) PLUS
  # an anchorless decision block in the same final message still blocks on
  # the real gap, and the cold-reader-lint warn stays out of the block JSON.
  # ================================================================
  _setup_scenario s23
  HOOKS=$(_build_dispatcher_repo s23)
  REPO="$tmproot/s23/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T23=$(_write_transcript "$tmproot/s23" $'Decision needed: ship tonight?\nMy pick: yes.\n\ntrailing off with no marker at all')
  RC23=$(_run_dispatcher "$HOOKS" "$REPO" "$T23" "sess-s23")
  _expect "cold-reader-lint-warn-plus-real-gap-still-blocks-on-the-real-gap" "$RC23" "2"
  if grep -q "marker-format" "$tmproot/last-stderr.txt" 2>/dev/null \
     && ! grep -q "cold-reader-lint" "$tmproot/last-stdout.txt" 2>/dev/null; then
    echo "self-test (cold-reader-lint-warn-channel-separate-from-block-json): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (cold-reader-lint-warn-channel-separate-from-block-json): FAIL (expected the cold-reader-lint WARN to stay out of the block-JSON reason string on stdout)" >&2
    failed=$((failed+1))
  fi
  if grep -q 'cold-reader-lint' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (cold-reader-lint-warn-still-ledgered-alongside-a-real-block): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (cold-reader-lint-warn-still-ledgered-alongside-a-real-block): FAIL (expected the cold-reader-lint warn to still be ledgered even though a real gap also blocked)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 24 (nl-issue [51], task A3): _svd_message_has_decision_block
  # now requires the constitution §3 decision-block SHAPE (a line-anchored
  # "Decision needed" cue AND an options signal) and excludes NEGATED forms.
  # Two transcripts prove both directions:
  #   (b) NEGATED "decision needed" in ordinary prose ("...no decision needed
  #       here, and without a decision the job just proceeds") is NOT treated
  #       as a §3 block and therefore never warns — the exact false-positive
  #       of nl-issue [51]. RED-GREEN GUARD: against the OLD naive-substring
  #       regex this text matched 'decision needed' and warned (anchorless);
  #       the new line-anchored-cue + required-options-signal shape does not,
  #       so this assertion FAILS on the pre-fix code and PASSES post-fix.
  #   (a) a genuine, anchorless §3 block ("**Decision needed:**" + "**Reply
  #       with:**", no artifact anchor) IS still detected and DOES warn —
  #       proving the tightened matcher was not neutered into never firing.
  # ================================================================
  # ---- (b) negated "decision needed" prose must NOT warn ----
  _setup_scenario s24neg
  HOOKS=$(_build_dispatcher_repo s24neg)
  REPO="$tmproot/s24neg/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T24N=$(_write_transcript "$tmproot/s24neg" $'Rolled back the migration; there is no decision needed here, and without a decision the job just proceeds.\n\nDONE: nothing to report')
  RC24N=$(_run_dispatcher "$HOOKS" "$REPO" "$T24N" "sess-s24neg")
  _expect "cold-reader-lint-negated-decision-needed-never-blocks" "$RC24N" "0"
  if ! grep -q '"gate":"stop-verdict-dispatcher".*cold-reader-lint' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (cold-reader-lint-negated-decision-needed-not-flagged): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (cold-reader-lint-negated-decision-needed-not-flagged): FAIL (a negated 'no decision needed' in prose was incorrectly treated as a §3 decision block -- nl-issue [51] regression)" >&2
    failed=$((failed+1))
  fi
  # ---- (a) a genuine anchorless §3 block MUST still be detected + warn ----
  _setup_scenario s24pos
  HOOKS=$(_build_dispatcher_repo s24pos)
  REPO="$tmproot/s24pos/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T24P=$(_write_transcript "$tmproot/s24pos" $'**Decision needed:** cut the release tonight?\n**Reply with:** cut / hold\n\nDONE: nothing to report')
  RC24P=$(_run_dispatcher "$HOOKS" "$REPO" "$T24P" "sess-s24pos")
  _expect "cold-reader-lint-real-sec3-block-never-blocks" "$RC24P" "0"
  if grep -q '"gate":"stop-verdict-dispatcher".*cold-reader-lint.*no-artifact-anchor' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (cold-reader-lint-real-sec3-block-still-detected): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (cold-reader-lint-real-sec3-block-still-detected): FAIL (a genuine anchorless §3 'Decision needed:' + 'Reply with:' block was no longer detected -- the tightened matcher was neutered)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 25 (nl-issue [42], RED-GREEN GUARD): the block-JSON reason
  # field carries the combined verdict ITSELF — per-gate [gate/check]
  # lines + pin-d remediation — because hook stderr never reaches the
  # blocked session's context (two live incidents 2026-07-07: the session
  # saw only "see stderr" and had to guess the gap). Against the pre-fix
  # code the reason was a bare "See stderr for the combined verdict ..."
  # pointer, so every positive assertion below FAILS pre-fix and PASSES
  # post-fix, and the stale-pointer assertion proves the pointer is gone.
  # Two-gap fixture (scenario 2's shape: trigger phrase + no marker).
  # ================================================================
  _setup_scenario s25
  HOOKS=$(_build_dispatcher_repo s25)
  REPO="$tmproot/s25/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T25=$(_write_transcript "$tmproot/s25" $'We should also handle the X case. Let me flag this for follow-up.\n\ntrailing off with no marker at all')
  RC25=$(_run_dispatcher "$HOOKS" "$REPO" "$T25" "sess-s25")
  _expect "reason-carries-verdict-still-blocks" "$RC25" "2"
  if grep -q 'session-honesty-gate/marker-format' "$tmproot/last-stdout.txt" 2>/dev/null \
     && grep -q 'Append ONE line with the correct terminal marker' "$tmproot/last-stdout.txt" 2>/dev/null; then
    echo "self-test (nl-issue-42-reason-carries-per-gate-line-with-remediation): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (nl-issue-42-reason-carries-per-gate-line-with-remediation): FAIL (expected the [session-honesty-gate/marker-format...] line + its pin-d remediation INSIDE the block-JSON reason on stdout — stderr never reaches the session)" >&2
    cat "$tmproot/last-stdout.txt" 2>/dev/null >&2
    failed=$((failed+1))
  fi
  if grep -q 'bug-persistence-gate/trigger-phrases-not-persisted' "$tmproot/last-stdout.txt" 2>/dev/null; then
    echo "self-test (nl-issue-42-reason-lists-EVERY-gate-not-just-the-first): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (nl-issue-42-reason-lists-EVERY-gate-not-just-the-first): FAIL (expected the bug-persistence-gate gap in the reason too)" >&2
    failed=$((failed+1))
  fi
  if ! grep -q 'See stderr for the combined verdict' "$tmproot/last-stdout.txt" 2>/dev/null \
     && ! grep -q 'more gap(s)' "$tmproot/last-stdout.txt" 2>/dev/null; then
    echo "self-test (nl-issue-42-stale-see-stderr-pointer-gone-and-no-truncation-at-default-cap): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (nl-issue-42-stale-see-stderr-pointer-gone-and-no-truncation-at-default-cap): FAIL (reason still points at stderr, or a 2-gap verdict was truncated at the default cap)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 26 (nl-issue [42], truncation): with the reason cap pinned
  # low (STOP_VERDICT_REASON_MAX_CHARS=700 — same env-pinning technique
  # as scenario 18's ceiling), a gap list that exceeds the cap yields a
  # CAPPED reason (first entry kept, overflow entry dropped) plus an
  # "... and K more gap(s)" note naming a full-verdict state file that is
  # actually written (under this scenario's sandboxed
  # RETRY_GUARD_STATE_DIR) and contains the dropped entries.
  # ================================================================
  _setup_scenario s26
  export STOP_VERDICT_REASON_MAX_CHARS=700
  HOOKS=$(_build_dispatcher_repo s26)
  REPO="$tmproot/s26/repo"
  mkdir -p "$REPO/docs/plans"
  ( cd "$REPO" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null); \
    git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false; \
    echo seed > seed.txt; git add -A; git commit -q -m seed )
  T26=$(_write_transcript "$tmproot/s26" $'We should also handle the X case. Let me flag this for follow-up.\n\ntrailing off with no marker at all')
  RC26=$(_run_dispatcher "$HOOKS" "$REPO" "$T26" "sess-s26")
  _expect "truncated-reason-still-blocks" "$RC26" "2"
  if grep -q 'marker-format' "$tmproot/last-stdout.txt" 2>/dev/null \
     && ! grep -q 'trigger-phrases-not-persisted' "$tmproot/last-stdout.txt" 2>/dev/null \
     && grep -q 'more gap(s)' "$tmproot/last-stdout.txt" 2>/dev/null \
     && grep -q 'stop-verdict-full-' "$tmproot/last-stdout.txt" 2>/dev/null; then
    echo "self-test (nl-issue-42-truncation-caps-reason-and-names-full-verdict-file): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (nl-issue-42-truncation-caps-reason-and-names-full-verdict-file): FAIL (expected first entry kept, overflow entry dropped, and an '... and K more gap(s)' note naming stop-verdict-full-*.txt)" >&2
    cat "$tmproot/last-stdout.txt" 2>/dev/null >&2
    failed=$((failed+1))
  fi
  FULL26=$(ls "$RETRY_GUARD_STATE_DIR"/stop-verdict-full-*.txt 2>/dev/null | head -1)
  if [[ -n "$FULL26" ]] && grep -q 'marker-format' "$FULL26" 2>/dev/null \
     && grep -q 'trigger-phrases-not-persisted' "$FULL26" 2>/dev/null; then
    echo "self-test (nl-issue-42-full-verdict-state-file-written-with-ALL-gaps): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (nl-issue-42-full-verdict-state-file-written-with-ALL-gaps): FAIL (expected ${RETRY_GUARD_STATE_DIR}/stop-verdict-full-*.txt to exist and contain BOTH gaps)" >&2
    failed=$((failed+1))
  fi
  unset STOP_VERDICT_REASON_MAX_CHARS

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
