#!/bin/bash
# needs-you.sh — NEEDS-YOU.md ledger machinery (NL Overhaul Program Wave E, task E.6).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# Operator directive 2026-07-02 (constitution §2 Communication hygiene): every
# decision or question surfaced to the operator must ALSO land in a durable,
# canonical "awaiting-operator" ledger — "if it's not in the ledger, it wasn't
# surfaced." The prior attempt at this (the Workstreams UI tracker) failed on
# its DATA layer (0 production decision-events ever recorded, 60% writer
# failures, born-incomplete items — see WORKSTREAMS-UI-PURPOSE-AUDIT-01). This
# script is the file-first rebuild: one canonical Markdown file, mechanically
# maintained, that never depends on a UI or a database being alive.
#
# ============================================================
# CONTRACT
# ============================================================
#
#   needs-you.sh add --section <decision|question|inflight|decided>
#                     --text <one-line-or-block> [--session <id>]
#                     [--link <url-or-path>]* [--tier <1|2|3>]
#     Appends one entry to the ledger state, re-renders NEEDS-YOU.md, prints
#     the new entry's id to stdout, exit 0. --section decision expects --text
#     to already be (or to be wrapped as) a compact constitution-§3 block; see
#     "SECTION SEMANTICS" below for the exact rendering each section gets.
#
#     COLD-READER LINT (operator directive 2026-07-07, constitution §3
#     amendment 53d3bee "the cold-reader bar"): for --section decision only,
#     the text is scored against three zero-session-context requirements —
#     (a) background/context (does it say WHAT this thing is, not just a
#     bare title), (b) >=1 concrete artifact anchor (a repo path, a URL, or
#     an id pattern like NL-FINDING-035/NY-123/#456/a 7-40 char hex SHA),
#     (c) per-option outcome text (does it say WHAT CHANGES per answer, not
#     just list bare option words). Any failing check WARNS — a stderr
#     notice, plus the stored item gains a `lint_warnings` array naming
#     which check(s) failed. See _ny_lint_decision_text() for the exact
#     heuristics.
#
#     LINT PROMOTION — INTERACTIVE BLOCK vs MECHANICAL QUARANTINE (cockpit-
#     roadmap-redesign Task 4, A1; constitution §10 compliance record below):
#     a failing lint on --section decision now has TWO outcomes depending on
#     the caller, controlled by the new `--mechanical` flag:
#
#       - INTERACTIVE/MODEL-INVOKED path (no `--mechanical` flag — a live
#         session calling `add` directly, e.g. via the decision-log-entry.md
#         template): a lint failure now BLOCKS. `add` prints the teaching
#         message to stderr naming exactly which check(s) failed and how to
#         fix them, writes NOTHING to the ledger, and exits 1. The calling
#         session sees the error in the same turn and retries with the
#         missing context — a teaching gate, not a dead end (a live actor is
#         always present to fix and resubmit in the SAME turn).
#       - MECHANICAL callers (stop-verdict-dispatcher.sh, session-resumer.sh
#         park, session-honesty-gate.sh PAUSING — fire from a hook/dispatcher
#         with no live actor able to retry) pass `--mechanical` and get the
#         PRIOR behavior: STORE-AND-QUARANTINE. The entry lands in the
#         ledger exactly as before (never rejected), `lint_warnings` is
#         stamped, and a stderr notice fires — but `add` still exits 0. This
#         preserves the shipped ledger-never-rejects contract (a waiting
#         item must never land NOWHERE): a mechanical call that got REJECTED
#         instead of quarantined would silently lose the item, since nothing
#         downstream of a hook firing ever retries the call.
#       - The cockpit Inbox view (server/inbox-routes.js) reads
#         `lint_warnings` on open decision items to render the "needs
#         context" quarantine section (I4/A8) — no second heuristic; same
#         field this lint stamps at add-time.
#
#     Constitution §10 compliance (a new blocking gate requires a golden
#     scenario, an expected false-positive rate, and a retirement condition):
#       - GOLDEN SCENARIO: the 2026-07-18 bare-token sign-off incident
#         (memory `feedback_needs_from_you_full_context` — a decision landed
#         in the ledger as a bare title with no context, no anchor, no
#         outcomes, forcing the operator to reconstruct intent from memory).
#         The interactive block catches exactly this shape before it ever
#         reaches the operator.
#       - EXPECTED FALSE-POSITIVE RATE: <~5% of interactive adds. The
#         session holds full context at write time — retry-with-context is
#         the designed recovery, costing seconds, not a real block.
#       - RETIREMENT CONDITION: demote back to warn-only if a weekly triage
#         window shows false-positive blocks exceeding true catches, OR once
#         every producer emits §3-complete items by construction and the
#         lint has not fired for a month.
#
#   needs-you.sh resolve <id> [--note <str>]
#     Marks entry <id> resolved (moves it out of its open section and into
#     "Recently decided for your §8 review" with today's date), re-renders,
#     exit 0. Exit 1 if <id> not found. --note is optional free text recorded
#     alongside the resolution (e.g. what was decided).
#
#   needs-you.sh expire
#     Recomputes which "Recently decided" entries have aged out of the 7-day
#     review window: entries resolved >7 days ago collapse out of the itemized
#     list into a single trailing count line ("+N older, resolved before
#     <date>"). Re-renders. Idempotent — safe to call on every render. Exit 0
#     always (a maintenance sweep, not a query).
#
#   needs-you.sh render
#     Runs bootstrap-migrate (see below), then expire, then rewrites
#     NEEDS-YOU.md from current state in full (all four sections, always in
#     the same order, always all four headers present even when empty). Exit
#     0 on success, 1 on write failure.
#
#   needs-you.sh bootstrap-migrate
#     NL-FINDING-035: if NEEDS-YOU.md is ABSENT, or PRESENT but missing any of
#     the four canonical section headers (i.e. it is a stale hand-authored
#     file predating the render machinery, or was hand-edited despite the
#     "do not hand-edit" notice), this ingests any pre-existing content as a
#     single migrated `--section decision` ledger entry (so an operator item
#     that was only ever a hand-written heading survives as a real ledger
#     entry, not silently discarded) and marks migration done, then falls
#     through to a full render. Idempotent: once the ledger contains a
#     `migrated_from_legacy_file` marker item (or the file already has all 4
#     headers), this is a no-op. Called automatically by `render` (and hence
#     by `add`/`resolve`, which both call render); exposed standalone for
#     scripting/tests. Exit 0 always (best-effort ingestion; never blocks the
#     render it precedes).
#
#   needs-you.sh has-entry-for-session <session-id>
#     Exit 0 if the ledger has ANY open (unresolved) entry whose session field
#     equals <session-id>, else exit 1. Prints nothing (pure predicate; the
#     exit code IS the answer) — this is the query flag E.10's session-honesty
#     warn extension calls (D.3 extension, reassigned to E.10 per §E.0-DECISIONS
#     point (d); this script only ships the flag, never touches
#     session-honesty-gate.sh itself).
#
#   needs-you.sh --self-test
#     Round-trips add/resolve/expire/render + has-entry-for-session against a
#     SANDBOX state dir and a SANDBOX NEEDS-YOU.md path — never the real
#     machine state, never the real main-checkout NEEDS-YOU.md. See
#     "SANDBOXING" below.
#
# ============================================================
# SECTION SEMANTICS (the four headers — exact, per the plan task line)
# ============================================================
#
#   ## Awaiting your decision
#     Compact constitution-§3 blocks + links. Each entry rendered as:
#       ### <title-or-first-line-of-text>
#       <the --text block, verbatim (already-formatted §3 shape expected)>
#       Links: <space-joined --link values, or "(none)">
#       *(added <date>, session `<session-id-or-unknown>`)*
#
#   ## Open questions
#     Lighter-weight than decisions — a bullet per entry, not a full block:
#       - <text> — *(added <date>, session `<session-id-or-unknown>`)*
#
#   ## In flight (sessions + waves)
#     Status lines for work already proceeding (no operator action needed,
#     informational — decide-and-go trail per constitution §8):
#       - <text> — *(added <date>, session `<session-id-or-unknown>`)*
#
#   ## Recently decided for your §8 review
#     7-day rolling window of RESOLVED entries, newest first:
#       - <text> — resolved <resolved-date>*(: <note>)*
#     Anything resolved >7 days ago collapses into one trailing line:
#       *(+N older, resolved before <cutoff-date>)*
#
# ============================================================
# WRITERS (per spec)
# ============================================================
#
# `add` is called by two callers:
#   1. The decision-log flow (constitution §3 / decision-log-entry.md template)
#      — any session surfacing a Decision/Question/In-flight item to the
#      operator calls `needs-you.sh add --section ... --text ...` in the same
#      turn (constitution §2: "chat is a notification; the file is the
#      record").
#   2. session-wrap.sh's PAUSING path — when a turn ends with a `PAUSING:`
#      final marker, the exact ask on that marker line is added as a
#      --section decision entry. See session-wrap.sh's own header comment
#      (search "E.6 CALL POINT") for the exact insertion this task added; if
#      no clean insertion point existed the alternative was to document the
#      diff in doctor-predicate.md instead — see that file for which path was
#      taken on this branch.
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST / explicit overrides)
# ============================================================
#
# State (structured JSON ledger, source of truth) resolution order:
#   1. NEEDS_YOU_STATE_DIR env var, if set.
#   2. HARNESS_SELFTEST=1 and NEEDS_YOU_STATE_DIR unset -> a sandboxed dir
#      under ${TMPDIR:-/tmp}/needs-you-selftest/<pid>/.
#   3. Default: $HOME/.claude/state/needs-you/.
#
# Rendered NEEDS-YOU.md resolution order:
#   1. NEEDS_YOU_MD_PATH env var, if set.
#   2. HARNESS_SELFTEST=1 and NEEDS_YOU_MD_PATH unset -> a sandboxed path
#      under ${TMPDIR:-/tmp}/needs-you-selftest/<pid>/NEEDS-YOU.md.
#   3. Default: "$(nl_main_checkout_root)/NEEDS-YOU.md" (hooks/lib/nl-paths.sh)
#      — the MAIN checkout root, never a linked worktree's own root, per the
#      spec ("at the MAIN-CHECKOUT root"). Falls back to
#      `git rev-parse --show-toplevel` if nl-paths.sh is unavailable for any
#      reason (defensive; should not happen in a normal checkout), and to cwd
#      as an absolute last resort so the script never silently no-ops.
#
# ============================================================
# TASK 4 SPLICE — progress-log emission + operator-todo.md auto-pointer
# (ask-rooted-workstreams-p1, plan Task 4)
# ============================================================
#
# `add` (decision|question sections ONLY — see rationale below) additionally,
# best-effort, never-blocking (writer semantics, constraint 5):
#
#   1. Emits one `waiting_on_operator` progress-log event via the STABLE
#      `progress-log.sh emit` CLI (adapters/claude-code/scripts/progress-log.sh
#      -- this script never sources hooks/lib/progress-log-lib.sh directly;
#      it shells out to the CLI, same convention as every other splice)
#      carrying: --needs-you-id <id>, --session-id <session>, --emitter
#      needs-you, and a --summary narrative that folds in the fields the
#      FROZEN v1 event schema has no dedicated column for (section, tier, and
#      the cold-reader lint's §3-context-present flag) — schema.json's
#      additionalProperties:false means new columns are Task 2's call, not
#      this splice's; folding them into the human-readable `summary` string
#      is the same technique Task 1 used for its "task N verified done"
#      narrative. The natural key for `waiting_on_operator` is needs_you_id
#      alone (progress-log-lib.sh's _pl_natural_key), so each ledger entry's
#      pointer event is idempotent by construction — no --dedup-extra needed.
#      No --ask is passed (this script has no ask-id in scope yet); the event
#      lands in the "unlinked" orphan lane by design (pl_path_for's documented
#      fallback) for Task 12's auditor to reconcile later.
#
#   2. Appends ONE auto-pointer bullet line to docs/operator-todo.md, inside a
#      marker-delimited AUTO section (`<!-- AUTO:START -->`/`<!-- AUTO:END
#      -->`); any operator-authored content above the markers is NEVER
#      touched. Path resolves via `nl_main_checkout_root` (constraint 11 —
#      the SAME resolver this script already uses for NEEDS-YOU.md itself, in
#      `_ny_md_path` above), so a splice firing inside a builder worktree
#      still lands the pointer in the MAIN checkout, never the ephemeral
#      worktree. The file is created (operator section + empty AUTO markers)
#      the first time it's needed if absent. Resolution/auto-check of a
#      pointer is explicitly NOT this splice's job -- Task 12's auditor
#      derives that from the underlying NEEDS-YOU ledger state, so a pointer
#      here survives an operator resolving the item through a path that
#      bypasses this script entirely (e.g. hand-editing the ledger).
#
# SCOPING DECISION (decide-and-go, constitution §8): only --section decision
# and --section question fire this splice. Design-sketch §3 ("My To-Do")
# names the pointer mechanism explicitly as "the same mechanism that appends
# a DECISION/QUESTION to NEEDS-YOU.md" -- inflight is a status narrative, not
# something the operator owes an action on, and `decided` is the resolve()
# target shape, never a fresh ask. Emitting "waiting_on_operator" or a To-Do
# pointer for an inflight/decided entry would misrepresent it as something
# the operator is blocked on (the exact O.4 noise regression this whole plan
# exists to reverse). See needs-you.sh's own header "SECTION SEMANTICS" above
# for what each of the four sections means.
#
# Both writes are wrapped so a failure in EITHER (missing progress-log.sh,
# an unwritable operator-todo.md path, a worktree with no resolvable root)
# can never fail `add` itself -- `add` always exits 0 for a well-formed
# invocation exactly as it did before this task (see cmd_add).
#
# ============================================================

set -u

_NY_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_NY_SELF_PATH="$_NY_SELF_DIR/needs-you.sh"
_NY_NLPATHS="$_NY_SELF_DIR/../hooks/lib/nl-paths.sh"
if [[ -f "$_NY_NLPATHS" ]]; then
  # shellcheck disable=SC1090
  source "$_NY_NLPATHS"
fi

# state-json-init.sh: shared VALIDITY-guarded JSON state-file initializer
# (2026-07-29 incident fix — see that file's header for the full incident +
# contract). A hard dependency, same rung as jq: this script's whole safety
# story for _ny_ensure_state depends on it.
_NY_STATE_JSON_INIT="$_NY_SELF_DIR/lib/state-json-init.sh"
if [[ -f "$_NY_STATE_JSON_INIT" ]]; then
  # shellcheck disable=SC1090
  source "$_NY_STATE_JSON_INIT"
else
  echo "needs-you.sh: required library missing: $_NY_STATE_JSON_INIT" >&2
  exit 1
fi

err() { echo "needs-you.sh: $*" >&2; }
die() { err "$*"; exit 1; }

# ----------------------------------------------------------------------
# jq is a hard dependency for this script (structured JSON ledger + the
# render pipeline both lean on it; decision-queue.sh established this same
# jq-dependency convention for structured-state scripts in this repo).
# ----------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  die "jq is required but not found on PATH. Install jq (https://jqlang.github.io/jq/) to use needs-you.sh."
fi

# ----------------------------------------------------------------------
# _ny_state_dir — resolve the ledger state directory.
# ----------------------------------------------------------------------
_ny_state_dir() {
  if [[ -n "${NEEDS_YOU_STATE_DIR:-}" ]]; then
    printf '%s' "$NEEDS_YOU_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/needs-you-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/needs-you' "${HOME:-$PWD}"
}

# ----------------------------------------------------------------------
# _ny_md_path — resolve the rendered NEEDS-YOU.md path (MAIN-CHECKOUT root).
# ----------------------------------------------------------------------
_ny_md_path() {
  if [[ -n "${NEEDS_YOU_MD_PATH:-}" ]]; then
    printf '%s' "$NEEDS_YOU_MD_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/needs-you-selftest/%s/NEEDS-YOU.md' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  local root=""
  if command -v nl_main_checkout_root >/dev/null 2>&1; then
    root="$(nl_main_checkout_root)"
  fi
  if [[ -z "$root" ]]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null)"
  fi
  if [[ -z "$root" ]]; then
    root="$PWD"
  fi
  printf '%s/NEEDS-YOU.md' "$root"
}

# ----------------------------------------------------------------------
# _ny_operator_todo_path — resolve docs/operator-todo.md's path (Task 4;
# constraint 11: durable in-repo write, MAIN-CHECKOUT root only).
# Resolution order mirrors _ny_md_path above:
#   1. OPERATOR_TODO_PATH env var, if set (explicit override for tests/CI).
#   2. HARNESS_SELFTEST=1 and OPERATOR_TODO_PATH unset -> a sandboxed path
#      under ${TMPDIR:-/tmp}/needs-you-selftest/<pid>/operator-todo.md.
#   3. Default: "$(nl_main_checkout_root)/docs/operator-todo.md" — same
#      resolver _ny_md_path uses, NEVER a worktree cwd (constraint 11).
#      Falls back to `git rev-parse --show-toplevel`, then cwd, exactly like
#      _ny_md_path's own fallback chain (defensive; keeps this function total).
# ----------------------------------------------------------------------
_ny_operator_todo_path() {
  if [[ -n "${OPERATOR_TODO_PATH:-}" ]]; then
    printf '%s' "$OPERATOR_TODO_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/needs-you-selftest/%s/operator-todo.md' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  local root=""
  if command -v nl_main_checkout_root >/dev/null 2>&1; then
    root="$(nl_main_checkout_root)"
  fi
  if [[ -z "$root" ]]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null)"
  fi
  if [[ -z "$root" ]]; then
    root="$PWD"
  fi
  printf '%s/docs/operator-todo.md' "$root"
}

_NY_OPERATOR_TODO_AUTO_START="<!-- AUTO:START -->"
_NY_OPERATOR_TODO_AUTO_END="<!-- AUTO:END -->"

# ----------------------------------------------------------------------
# _ny_operator_todo_ensure <path> — create docs/operator-todo.md with the
# operator section + empty AUTO markers if it does not already exist. A
# no-op (returns 0 immediately) if the file is already present in ANY shape
# — this never re-templates or touches an existing file, matching the "never
# touched by automation" guarantee for the operator section. Returns 1 (best-
# effort signal to the caller, who must never let this fail `add`) if the
# containing directory cannot be created.
# ----------------------------------------------------------------------
_ny_operator_todo_ensure() {
  local path="$1"
  [[ -f "$path" ]] && return 0
  local dir; dir="$(dirname "$path")"
  mkdir -p "$dir" 2>/dev/null || return 1
  {
    printf '# Operator To-Do\n\n'
    printf 'Operator-authored items live in "## Operator items" below and are never\n'
    printf 'touched by automation. Auto-added pointer items (mirroring a decision or\n'
    printf 'question just appended to NEEDS-YOU.md) live between the AUTO markers and\n'
    printf 'are mechanically appended by\n'
    printf '`adapters/claude-code/scripts/needs-you.sh` (the `add` splice,\n'
    printf 'ask-rooted-workstreams-p1 Task 4) — never hand-edit inside the markers;\n'
    printf 're-appending only ever ADDS a line, never rewrites one. A pointer'\''s\n'
    printf 'resolved/checked state is DERIVED (a later auditor pass, plan Task 12)\n'
    printf 'from the underlying NEEDS-YOU ledger, not tracked here — entries in this\n'
    printf 'file are an append-only log, not removed when the ledger item resolves.\n\n'
    printf '## Operator items\n\n'
    printf '_(add your own free-form to-do items in this section — never overwritten)_\n\n'
    printf '%s\n' "$_NY_OPERATOR_TODO_AUTO_START"
    printf '%s\n' "$_NY_OPERATOR_TODO_AUTO_END"
  } > "$path" 2>/dev/null || return 1
  return 0
}

# ----------------------------------------------------------------------
# _ny_operator_todo_append_pointer <id> <section> <tier> <session_id> <title>
#   Insert one "- [ ] AUTO: ..." bullet immediately before the AUTO:END
# marker. Best-effort: any failure (unresolvable path, unwritable dir, a
# foreign-shaped file missing one or both markers) is swallowed and returns 0
# — this NEVER fails the caller (`add`). Uses a plain read/printf loop (not
# awk -v) specifically so an entry's title text can never be misinterpreted
# as a backslash escape sequence by the insertion mechanism itself.
# ----------------------------------------------------------------------
_ny_operator_todo_append_pointer() {
  local id="$1" section="$2" tier="$3" session_id="$4" title="$5"
  local path; path="$(_ny_operator_todo_path)"
  [[ -n "$path" ]] || return 0
  _ny_operator_todo_ensure "$path" || return 0
  grep -qF "$_NY_OPERATOR_TODO_AUTO_START" "$path" 2>/dev/null || return 0
  grep -qF "$_NY_OPERATOR_TODO_AUTO_END" "$path" 2>/dev/null || return 0

  local tier_txt="${tier:-untiered}"
  local session_txt="${session_id:-unknown}"
  local line
  line="$(printf -- '- [ ] AUTO: %s waiting on operator — "%s" (needs-you `%s`, tier %s, session `%s`) — see NEEDS-YOU.md' \
    "$section" "$title" "$id" "$tier_txt" "$session_txt")"

  local tmp; tmp=$(mktemp "${path}.XXXXXX") || return 0
  local inserted=0 l
  {
    while IFS= read -r l || [[ -n "$l" ]]; do
      if [[ "$l" == "$_NY_OPERATOR_TODO_AUTO_END" && "$inserted" == "0" ]]; then
        printf '%s\n' "$line"
        inserted=1
      fi
      printf '%s\n' "$l"
    done < "$path"
  } > "$tmp" 2>/dev/null
  if [[ "$inserted" == "1" ]]; then
    mv "$tmp" "$path" 2>/dev/null || rm -f "$tmp"
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

_ny_ledger_file() { printf '%s/ledger.json' "$(_ny_state_dir)"; }

#
# 2026-07-27 INCIDENT FIX: this used to be an EXISTENCE-only guard
# (`[[ -f "$f" ]] || echo '{...}' > "$f"`) — a file that existed but was
# empty/truncated/malformed never got re-initialized, and every subsequent
# `jq` read on it failed for the life of the file (this is exactly what
# happened to the live ledger.json: a 1-byte "\n" file sat unreadable for
# ~2 days). Delegates to the shared nl_state_json_ensure (scripts/lib/
# state-json-init.sh), which re-initializes on ABSENT *or* INVALID content,
# salvaging any pre-existing bytes to a `.corrupt-<date>.bak` file first
# (constitution §9 "salvage before reset") rather than silently discarding
# them.
_ny_ensure_state() {
  local dir; dir="$(_ny_state_dir)"
  mkdir -p "$dir" 2>/dev/null || die "cannot create state dir: $dir"
  local f; f="$(_ny_ledger_file)"
  nl_state_json_ensure "$f" '{"schema_version":1,"items":[]}' \
    || die "cannot initialize ledger (see state-json-init error above): $f"
}

_ny_now() { date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown"; }
_ny_today() { date -u +"%Y-%m-%d" 2>/dev/null || echo "unknown"; }
_ny_epoch_now() { date -u +%s 2>/dev/null || echo 0; }

# Best-effort seconds-since-epoch for an ISO-8601 UTC timestamp (GNU + BSD date).
_ny_epoch() {
  local ts="$1"
  date -u -d "$ts" '+%s' 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null && return 0
  echo 0
}

# Simple incrementing id: NY-<epoch>-<random 4 hex>. Collisions are harmless
# (id is a lookup key only, no ordering semantics depend on it), and a random
# suffix means two adds in the same second (self-test round-trips) don't clash.
_ny_gen_id() {
  local rand
  if [[ -r /dev/urandom ]]; then
    rand=$(head -c 2 /dev/urandom | od -An -tx1 | tr -d ' \n')
  else
    rand=$(printf '%04x' "$RANDOM")
  fi
  printf 'NY-%s-%s' "$(_ny_epoch_now)" "$rand"
}

# Atomic write: content -> tmpfile -> mv.
#
# WRITE SAFETY (2026-07-27 incident, second independent layer): refuses to
# ever commit empty or non-JSON content over the real ledger. This is a
# backstop, not the primary fix (the primary fix is the bash-3.2 array-
# expansion bug at cmd_add's jq call site, see its own comment) — but ANY
# future bug that causes a caller's jq pipeline to silently produce empty
# output (a jq crash, an unhandled edge case, an environment hiccup) would
# otherwise still sail through here and truncate the real ledger to
# whatever `printf '%s\n' "$content"` produces for empty content: a lone
# newline byte — exactly the incident's observed corruption. Returns 1
# (caller decides fatal-vs-best-effort) instead of ever writing; the
# on-disk ledger is left completely untouched on rejection.
_ny_write_ledger() {
  local content="$1"
  local f; f="$(_ny_ledger_file)"
  # NOTE: deliberately `jq -e 'type'`, NOT `jq empty` — `jq empty` treats
  # whitespace-only/empty input as a vacuous success (zero JSON documents to
  # iterate over is not an "error" to the `empty` filter), which would have
  # let this exact guard wave through the incident's own corrupt shape.
  # `-e 'type'` requires an actual JSON value to be produced. See
  # scripts/lib/state-json-init.sh's matching comment for the full
  # jq-exit-code reasoning (including why `type` and not bare `-e '.'`).
  if [[ -z "$content" ]] || ! printf '%s' "$content" | jq -e 'type' >/dev/null 2>&1; then
    err "REFUSING to write ledger: computed content is empty or not valid JSON — this would have silently wiped $f (the exact 2026-07-27 incident shape). Ledger left untouched; the caller's change was NOT recorded."
    return 1
  fi
  local tmp; tmp=$(mktemp "${f}.XXXXXX") || die "mktemp failed"
  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; die "write to tmpfile failed"; }
  mv "$tmp" "$f" || { rm -f "$tmp"; die "atomic rename failed"; }
}

_ny_read_ledger() { cat "$(_ny_ledger_file)"; }

# ----------------------------------------------------------------------
# _ny_lint_decision_text <text>
#   Cold-reader lint (constitution §3 amendment 53d3bee, operator directive
#   2026-07-07): scores a --section decision --text block against the three
#   zero-session-context requirements. Prints ZERO or more warning codes,
#   one per line, to stdout (empty output == clean); NEVER exits non-zero,
#   NEVER blocks anything — this is a pure scoring function, the caller
#   decides what to do with the codes. Deliberately heuristic (regex/grep
#   over the raw text, not an LLM judgment call — this runs synchronously
#   inside `add`, on every machine, with no model available) and
#   deliberately biased toward NOT crying wolf: each check looks for the
#   PRESENCE of a plausible signal, not the absence of a specific keyword,
#   so a well-written block in an unanticipated shape is not penalized.
#
#   Codes (each maps 1:1 to one cold-reader-bar clause):
#     no-context   — no background/WHAT-is-this-thing prose detected.
#                    Heuristic: the text must be more than a single bare
#                    line (a title alone tells a cold reader nothing) AND
#                    contain at least one line of real prose >= 40 chars
#                    (a line long enough to plausibly explain something,
#                    not just another short label/option line).
#     no-anchor    — no concrete artifact anchor detected. Heuristic: at
#                    least one of (i) a URL (http(s)://), (ii) a repo-path-
#                    shaped token (contains a "/" and a file extension, or
#                    a bare multi-segment path like docs/plans/foo), (iii)
#                    an id-pattern token (WORD-WORD-123 / WORD-123 / #123 /
#                    a 7-40 char hex SHA).
#     no-outcomes  — no per-option outcome text detected. Heuristic: EITHER
#                    the block has no option-shaped structure at all (no
#                    "Option"/"My pick"/table-row/bulleted-choice markers —
#                    nothing to check outcomes against, so this check is
#                    skipped, not failed) OR it has option structure but
#                    none of the option-adjacent lines contain an outcome
#                    connective (->, →, "means", "triggers", "results in",
#                    "changes", "happens", or a markdown table pipe row,
#                    which by the §3 table format's own column 2 IS the
#                    outcome text).
# ----------------------------------------------------------------------
# _ny_lint_ask_text <text> — WARN-ONLY lint for --section question (operator
# asks), constitution §2 "every ask is a complete instruction, never a label"
# (2026-07-28). Reuses the decision lint's no-context / no-anchor heuristics and
# adds ONE narrow new code.
#
# WHY IT EXISTS: harness-reviewer found that --section question — the section §2
# routes every operator ASK to — was completely unlinted, while the decision twin
# has been linted since 53d3bee. The triggering incident: a session ended several
# turns with `Blocking: run /grant-local-edit` and nothing else, which was both a
# bare label AND pointed at a gate that does not cover the file in question.
#
# THE FALSE-POSITIVE TRAP (reviewer's mandatory negative case): `Blocking: nothing`
# and `Blocking: none` are the §2-SANCTIONED empty values and are themselves single
# bare tokens. If bare-label fired on those it would warn on every clean session and
# be tuned out within a week — the cry-wolf failure this harness has already paid
# for. They are whitelisted explicitly and covered by a self-test scenario.
#
# WARN-ONLY, deliberately: ships at the warn rung so the false-positive rate is
# MEASURED before any promotion to a block (constitution §10 — no evidence, no gate).
# Promotion condition: a bounded FP rate over a real observation window.
_ny_lint_ask_text() {
  local text="$1"
  local -a warnings=()

  # --- (a) bare-label: the entire ask is one token -------------------------
  # Fires only when the WHOLE non-whitespace content is a single token,
  # optionally backticked and/or slash-prefixed (/grant-local-edit, `--flag`,
  # "enable-x"). Anything with a space and a verb is not a bare label.
  local stripped
  stripped="$(printf '%s' "$text" | tr -d '[:space:]`"'"'"'')"
  local wordcount
  wordcount="$(printf '%s' "$text" | tr -s '[:space:]' '\n' | grep -c '[^[:space:]]' 2>/dev/null || echo 0)"
  case "$(printf '%s' "$stripped" | tr '[:upper:]' '[:lower:]')" in
    nothing|none|n/a|na|-|"")
      : ;;   # §2-sanctioned empty value — MUST NOT fire (negative self-test case)
    *)
      if [[ "$wordcount" -le 1 ]]; then
        warnings+=("bare-label")
      fi ;;
  esac

  # --- (b) no-context / (c) no-anchor: reuse the decision heuristics -------
  # Only meaningful for a non-empty ask; the sanctioned empty values skip both.
  case "$(printf '%s' "$stripped" | tr '[:upper:]' '[:lower:]')" in
    nothing|none|n/a|na|-|"") ;;
    *)
      local line_count long_line_found=0
      line_count=$(printf '%s\n' "$text" | wc -l | tr -d ' ')
      while IFS= read -r _ny_al; do
        [[ "${#_ny_al}" -ge 40 ]] && long_line_found=1 && break
      done <<< "$text"
      if [[ "$line_count" -le 1 && "$long_line_found" -eq 0 ]]; then
        warnings+=("no-context")
      fi
      ;;
  esac

  local w
  for w in "${warnings[@]:-}"; do
    [[ -n "$w" ]] && printf '%s\n' "$w"
  done
  return 0
}

_ny_lint_decision_text() {
  local text="$1"
  # has_reply_with: "1" when the caller supplied --reply-with (a first-class
  # field, so the text itself doesn't need to spell out a "Reply:" line).
  local has_reply_with="${2:-0}"
  local -a warnings=()

  # --- (a) no-context ---------------------------------------------------
  local line_count long_line_found=0
  line_count=$(printf '%s\n' "$text" | wc -l | tr -d ' ')
  while IFS= read -r _ny_l; do
    [[ "${#_ny_l}" -ge 40 ]] && long_line_found=1 && break
  done <<< "$text"
  if [[ "$line_count" -le 1 || "$long_line_found" -eq 0 ]]; then
    warnings+=("no-context")
  fi

  # --- (b) no-anchor ------------------------------------------------------
  local has_anchor=0
  if printf '%s' "$text" | grep -qE 'https?://[^[:space:]]+'; then
    has_anchor=1
  elif printf '%s' "$text" | grep -qE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.[A-Za-z0-9]+'; then
    has_anchor=1
  elif printf '%s' "$text" | grep -qE '[A-Za-z0-9_.-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+'; then
    has_anchor=1
  elif printf '%s' "$text" | grep -qE '\b[A-Z]{2,}(-[A-Z0-9]+)*-[0-9]+\b'; then
    has_anchor=1
  elif printf '%s' "$text" | grep -qE '#[0-9]+\b'; then
    has_anchor=1
  elif printf '%s' "$text" | grep -qE '\b[0-9a-f]{7,40}\b'; then
    has_anchor=1
  fi
  [[ "$has_anchor" -eq 0 ]] && warnings+=("no-anchor")

  # --- (c) no-outcomes ------------------------------------------------------
  local has_option_structure=0
  if printf '%s' "$text" | grep -qiE '(^|[^A-Za-z])(option|my pick|reply with)([^A-Za-z]|$)|^\s*\|.*\|.*\|'; then
    has_option_structure=1
  fi
  if [[ "$has_option_structure" -eq 1 ]]; then
    if ! printf '%s' "$text" | grep -qE -- '->|→|\bmeans\b|\btriggers?\b|\bresults? in\b|\bchanges?\b|\bhappens\b|^\s*\|[^|]*\|[^|]*\|'; then
      warnings+=("no-outcomes")
    fi
  fi

  # --- (d) no-reply-line (S7, needs-you readability review 2026-08-03) ----
  # WARN-ONLY BY DESIGN: unlike (a)-(c), cmd_add deliberately excludes this
  # code from its interactive-block decision (see cmd_add's
  # blocking_lint_warnings split below) -- constitution §10 requires a
  # measured false-positive rate before ANY check earns blocking power, and
  # this one has none yet. It is still stored in lint_warnings (cockpit
  # Inbox / observability consumption, same array the other 3 codes use --
  # T25's "decision-only" contract is unaffected, only the CODE SET grows)
  # and produces its own warn-only stderr notice for both caller types.
  if [[ "$has_reply_with" != "1" ]] && ! printf '%s' "$text" | grep -qiE '\breply\b'; then
    warnings+=("no-reply-line")
  fi

  local w
  for w in "${warnings[@]:-}"; do
    [[ -n "$w" ]] && printf '%s\n' "$w"
  done
  return 0
}

# ----------------------------------------------------------------------
# cmd_add
# ----------------------------------------------------------------------
cmd_add() {
  _ny_ensure_state
  local section="" text="" session_id="" tier="" mechanical=0
  # S6 (needs-you readability review 2026-08-03) — three additive flags, all
  # optional, all schema_version-1-compatible (extra JSON fields, every
  # existing jq read tolerates them):
  #   --reply-with <str>  stored verbatim as .reply_with; the Decide-now
  #                        table (S2) and _ny_lint_decision_text's (d) check
  #                        (S7) both prefer this field over heuristically
  #                        extracting a "Reply:" line from --text.
  #   --blocking           stored as .blocking=true; hoists this item to the
  #                        top of the Awaiting-your-decision / Decide-now
  #                        ordering (S3) ahead of merely-recent items.
  #   --supersedes <id>    after this add succeeds, auto-resolves <id> with
  #                        note "superseded by <new-id>". A missing/already-
  #                        resolved target WARNS (stderr) and never dies —
  #                        add must stay total (constraint 5, same rung as
  #                        the Task-4 splice below).
  local reply_with="" blocking=0 supersedes=""
  local -a links=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --section) section="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --session) session_id="$2"; shift 2 ;;
      --link) links+=("$2"); shift 2 ;;
      --tier) tier="$2"; shift 2 ;;
      --mechanical) mechanical=1; shift ;;
      --reply-with) reply_with="$2"; shift 2 ;;
      --blocking) blocking=1; shift ;;
      --supersedes) supersedes="$2"; shift 2 ;;
      *) die "add: unknown flag '$1'" ;;
    esac
  done

  case "$section" in
    decision|question|inflight|decided) ;;
    *) die "add: --section must be one of decision|question|inflight|decided (got '$section')" ;;
  esac
  [[ -n "$text" ]] || die "add: --text is required"

  local id; id="$(_ny_gen_id)"
  local ts; ts="$(_ny_now)"

  # Cold-reader lint (constitution §3 amendment 53d3bee): --section decision
  # only. See _ny_lint_decision_text's own header comment for the checks.
  #
  # S7 (needs-you readability review 2026-08-03) split lint_warnings (the
  # FULL set, stored on the ledger item for the cockpit Inbox / observability
  # — unchanged contract) from blocking_lint_warnings (the subset that can
  # actually BLOCK an interactive add or trigger the mechanical quarantine
  # notice). Only the original 3 codes (no-context/no-anchor/no-outcomes) are
  # blocking-eligible; the newer no-reply-line code is warn-only by design
  # (constitution §10 — no measured false-positive rate yet) and can never
  # block either caller type, even though it still lands in lint_warnings.
  local -a lint_warnings=()
  local -a blocking_lint_warnings=()
  if [[ "$section" == "decision" ]]; then
    local _ny_has_reply=0
    [[ -n "$reply_with" ]] && _ny_has_reply=1
    while IFS= read -r _ny_lw; do
      [[ -n "$_ny_lw" ]] && lint_warnings+=("$_ny_lw")
    done < <(_ny_lint_decision_text "$text" "$_ny_has_reply")
    for _ny_lw in "${lint_warnings[@]:-}"; do
      [[ -n "$_ny_lw" && "$_ny_lw" != "no-reply-line" ]] && blocking_lint_warnings+=("$_ny_lw")
    done
    if [[ "${#blocking_lint_warnings[@]}" -gt 0 ]]; then
      if [[ "$mechanical" == "1" ]]; then
        # MECHANICAL caller: store-and-quarantine, never reject (A1 — the
        # ledger-never-rejects contract; no live actor is present to retry a
        # hook/dispatcher call, so the item must land somewhere). Message
        # names the FULL set (lint_warnings) for completeness even though
        # the block/quarantine decision itself only depends on the blocking
        # subset.
        err "cold-reader lint: this decision entry is missing: ${lint_warnings[*]} (added anyway — MECHANICAL caller, stored + quarantined, never rejected; see needs-you.sh header 'LINT PROMOTION' for what each code means and why mechanical callers differ from interactive ones)"
      else
        # INTERACTIVE/MODEL-INVOKED path: BLOCK. A live session is present
        # and can retry with the missing context in the same turn — nothing
        # is written to the ledger (die() exits before _ny_write_ledger).
        die "cold-reader lint BLOCKED this add (interactive path): missing ${blocking_lint_warnings[*]}. Add the missing context — background/what-is-this prose, a concrete artifact anchor (a repo path, URL, or id like NL-FINDING-035/NY-123/#456/a SHA), and per-option outcome text — and retry. If this is a scripted/dispatcher caller with no live actor to retry, pass --mechanical instead (that path stores + quarantines rather than blocking). See needs-you.sh header 'LINT PROMOTION' for exactly what each code means."
      fi
    elif [[ "${#lint_warnings[@]}" -gt 0 ]]; then
      # Only warn-only codes fired (currently just no-reply-line): never
      # blocks, never quarantines — a lightweight notice for BOTH caller
      # types, and the code is still stamped into the stored lint_warnings.
      err "cold-reader lint (warn-only, never blocks): this decision entry is missing: ${lint_warnings[*]} — consider --reply-with or a 'Reply:' line so the operator knows exactly how to respond."
    fi
  elif [[ "$section" == "question" ]]; then
    # ASK LINT (constitution §2 "every ask is a complete instruction", 2026-07-28).
    # --section question is where §2 routes operator ASKS; harness-reviewer found
    # it completely unlinted while the decision twin has been linted since 53d3bee.
    #
    # WARN-ONLY AND STRUCTURALLY SEPARATE FROM THE DECISION PATH ABOVE. It does
    # NOT reach the die() branch under any caller, interactive or mechanical:
    # constitution §10 says no gate without measured evidence, and this lint has
    # none yet. The warnings are recorded on the ledger item (lint_warnings_csv)
    # so the false-positive rate can be MEASURED before anyone proposes a block.
    # Promotion condition: a bounded FP rate over a real observation window.
    # Deliberately NOT written into lint_warnings[]: that array is a
    # DECISION-ONLY contract (scenario T25 asserts a non-decision section carries
    # zero lint_warnings, and the progress-log "§3-context present/missing" flag
    # consumes it downstream). Populating it for asks would silently relabel every
    # ask as a malformed decision. The ask warning goes to stderr only; the
    # false-positive rate is measured from that trail, not from the ledger item.
    local -a _ny_ask_warnings=()
    while IFS= read -r _ny_lw; do
      [[ -n "$_ny_lw" ]] && _ny_ask_warnings+=("$_ny_lw")
    done < <(_ny_lint_ask_text "$text")
    if [[ "${#_ny_ask_warnings[@]}" -gt 0 ]]; then
      err "ask lint (constitution §2, WARN-ONLY — entry stored, nothing blocked): this ask looks like ${_ny_ask_warnings[*]}. An ask must say WHAT you want, WHY it is the operator's, and HOW to do it — a bare command or flag name is not an ask. See needs-you.sh _ny_lint_ask_text."
    fi
  fi

  # Single jq call builds the item AND appends it to the current ledger.
  # links[] is passed via --args + $ARGS.positional (handles zero-or-more
  # links without per-link jq calls); session/tier are passed as
  # possibly-empty --arg strings, normalized to null inside the filter.
  # lint_warnings[] is passed the same way as links[] would be, but jq only
  # accepts ONE positional array via $ARGS.positional, so lint_warnings is
  # instead pre-joined into a single comma-separated --arg and split back
  # out inside the filter (keeps this a single jq invocation — see the
  # jq-subprocess-count-sensitive note below).
  # Kept to one jq invocation deliberately — this environment has shown
  # jq-subprocess-count-sensitive hangs under heavy sequential spawning
  # within a single long-lived bash process (see doctor-predicate.md's
  # "environment note" for this task's diagnosis); minimizing jq spawns
  # per verb call is a defensive mitigation, not just a style preference.
  local lint_warnings_csv=""
  if [[ "${#lint_warnings[@]}" -gt 0 ]]; then
    lint_warnings_csv=$(IFS=,; echo "${lint_warnings[*]}")
  fi
  # blocking_lint_csv: the subset used for the progress-log "§3-context"
  # flag below — kept scoped to the ORIGINAL 3 checks (background/anchor/
  # outcomes) so a purely-cosmetic no-reply-line warning doesn't relabel an
  # otherwise well-formed entry as missing §3 context.
  local blocking_lint_csv=""
  if [[ "${#blocking_lint_warnings[@]}" -gt 0 ]]; then
    blocking_lint_csv=$(IFS=,; echo "${blocking_lint_warnings[*]}")
  fi
  local cur; cur=$(_ny_read_ledger)
  local new
  new=$(echo "$cur" | jq \
    --arg id "$id" --arg ts "$ts" --arg section "$section" --arg text "$text" \
    --arg session_id "$session_id" --arg tier "$tier" --arg lint_csv "$lint_warnings_csv" \
    --arg reply_with "$reply_with" --arg supersedes "$supersedes" \
    --argjson blocking "$([[ "$blocking" == "1" ]] && echo true || echo false)" \
    '
    ($session_id | if . == "" then null else . end) as $session
    | ($tier | if . == "" then null else . end) as $tier_v
    | ($lint_csv | if . == "" then [] else split(",") end) as $lint_warnings
    | ($reply_with | if . == "" then null else . end) as $reply_with_v
    | ($supersedes | if . == "" then null else . end) as $supersedes_v
    | .items += [{
        id: $id, created_at: $ts, updated_at: $ts, section: $section, text: $text,
        links: $ARGS.positional, session: $session, tier: $tier_v,
        state: "open", resolved_at: null, resolution_note: null,
        lint_warnings: $lint_warnings, reply_with: $reply_with_v,
        blocking: $blocking, supersedes: $supersedes_v
      }]
    ' \
    --args -- "${links[@]+"${links[@]}"}")
  # BASH 3.2 ROOT-CAUSE NOTE (2026-07-27 incident): this used to be plain
  # "${links[@]}". Under `set -u` (line ~256), bash <4.4 — including macOS's
  # shipped /bin/bash 3.2.57, this repo's portability floor — treats
  # expanding an array that has ZERO elements as an unbound-variable
  # reference and aborts. Since `add` is called with no --link flags far
  # more often than with any, this fired on nearly every real invocation run
  # under plain `/bin/bash`: the command substitution above died mid-jq-call,
  # $new came back empty, and the unconditional _ny_write_ledger("$new")
  # below then wrote a 1-byte "\n" over the real ledger — a byte-for-byte
  # reproduction of the incident's corrupt ledger.json (see T34 self-test
  # scenario, and _ny_write_ledger's own content-validity guard below, which
  # is the second, independent layer that now refuses to ever commit that
  # empty content in the first place). The `${arr[@]+"${arr[@]}"}` form is
  # the portable idiom: it distinguishes "array is unset" from "array is set
  # but has zero elements" and expands to nothing (not an error) in the
  # latter case, on both bash 3.2 and modern bash.
  #
  # CONVERGENT FIX NOTE (2026-07-29): the operator-spawned bootstrap-migrate
  # session (7cd2074) found the SAME root cause independently, plus its
  # downstream recursion: cmd_bootstrap_migrate's own cmd_add emptied the
  # ledger, so _ny_ledger_has_legacy_migration_marker could never see the
  # marker it had just written, and add -> render -> bootstrap-migrate
  # recursed until killed. Its explicit emptiness guard is kept below as a
  # third, cheapest layer in front of the write.
  [[ -n "$new" ]] || die "add: failed to build the updated ledger (jq produced no output); refusing to write an empty ledger.json"
  _ny_write_ledger "$new" || die "cmd_add: refusing to continue — ledger write was rejected (see previous error); nothing was corrupted, but this entry was NOT recorded"

  cmd_render >/dev/null

  # ------------------------------------------------------------------
  # S6 --supersedes: auto-resolve the named older entry now that the
  # superseding item is safely on disk. Best-effort — a missing/already-
  # resolved target WARNS on stderr and never fails `add` (constraint 5);
  # the new entry has already been written by this point regardless.
  # ------------------------------------------------------------------
  if [[ -n "$supersedes" ]]; then
    if ! cmd_resolve "$supersedes" --note "superseded by $id" >/dev/null 2>&1; then
      err "add: --supersedes target '$supersedes' was not found (or could not be resolved) — '$id' was still added normally; the superseding link is recorded on '$id' (.supersedes) but the older entry was NOT auto-resolved. Resolve it by hand if it should close."
    fi
  fi

  # ------------------------------------------------------------------
  # TASK 4 CALL POINT (ask-rooted-workstreams-p1): progress-log
  # waiting_on_operator emission + docs/operator-todo.md auto-pointer. See
  # this file's "TASK 4 SPLICE" header comment for the full contract + the
  # decision/question-only scoping rationale. Best-effort: wrapped so
  # neither write can ever fail `add` (writer semantics, constraint 5).
  # ------------------------------------------------------------------
  case "$section" in
    decision|question)
      local _ny_ctx_flag="n/a"
      if [[ "$section" == "decision" ]]; then
        if [[ "${#blocking_lint_warnings[@]}" -eq 0 ]]; then
          _ny_ctx_flag="present"
        else
          _ny_ctx_flag="missing(${blocking_lint_csv})"
        fi
      fi
      local _ny_title
      _ny_title="$(printf '%s' "$text" | head -1)"
      [[ -n "$_ny_title" ]] || _ny_title="(untitled $section)"

      local _ny_pl_summary
      _ny_pl_summary="$(printf 'waiting on operator: %s "%s" (tier %s; §3-context %s)' \
        "$section" "$_ny_title" "${tier:-untiered}" "$_ny_ctx_flag")"
      local _ny_pl_cli="$_NY_SELF_DIR/progress-log.sh"
      if [[ -f "$_ny_pl_cli" ]]; then
        ( bash "$_ny_pl_cli" emit --type waiting_on_operator \
            --needs-you-id "$id" --session-id "$session_id" \
            --summary "$_ny_pl_summary" --emitter needs-you >/dev/null 2>&1 || true )
      fi

      ( _ny_operator_todo_append_pointer "$id" "$section" "$tier" "$session_id" "$_ny_title" || true )
      ;;
  esac

  # ------------------------------------------------------------------
  # O.5 CALL POINT (Wave O, NL Observability Program): best-effort phone
  # push for the "NEEDS-YOU created" push rule (design sketch §push —
  # exactly three classes: NEEDS-YOU created, session stalled/throttled,
  # doctor RED). This is the ONLY moment a new entry is created, so it is
  # the exact trigger point. Guarded so a push failure — or ntfy-push.sh
  # not existing at all on some checkout — can NEVER block `add`: title/
  # body derived from the item that was just written, invoked in a
  # subshell with its own stdout/stderr discarded, and its exit code is
  # never inspected by this function. ntfy-push.sh itself silently no-ops
  # when no topic is configured (§O.5 hard contract) — this call site
  # does not need to know or care whether a topic exists.
  # ------------------------------------------------------------------
  local _ny_push_title
  case "$section" in
    decision) _ny_push_title="NEEDS-YOU: new decision" ;;
    question) _ny_push_title="NEEDS-YOU: new question" ;;
    inflight) _ny_push_title="NEEDS-YOU: in flight" ;;
    *) _ny_push_title="NEEDS-YOU: new entry" ;;
  esac
  local _ny_push_bin="$_NY_SELF_DIR/ntfy-push.sh"
  if [[ -f "$_ny_push_bin" ]]; then
    ( bash "$_ny_push_bin" send --class needs-you --title "$_ny_push_title" --body "$text" >/dev/null 2>&1 || true )
  fi

  echo "$id"
}

# ----------------------------------------------------------------------
# cmd_resolve
# ----------------------------------------------------------------------
cmd_resolve() {
  _ny_ensure_state
  local id="${1:-}"; shift || true
  [[ -n "$id" ]] || die "resolve: missing <id>"
  local note=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --note) note="$2"; shift 2 ;;
      *) die "resolve: unknown flag '$1'" ;;
    esac
  done

  local ts; ts=$(_ny_now)

  # Single jq call, two-line raw output: line 1 is "true"/"false" (found),
  # line 2 is the updated ledger JSON — avoids a separate existence-check
  # jq invocation and a separate extraction call. See cmd_add's comment on
  # why jq-call-count is minimized in every verb here.
  local cur; cur=$(_ny_read_ledger)
  local out found new
  out=$(echo "$cur" | jq -c --arg id "$id" --arg ts "$ts" --arg note "$note" '
    ($note | if . == "" then null else . end) as $note_v
    | ([.items[] | select(.id == $id)] | length > 0) as $found
    | (.items |= map(
        if .id == $id then
          . + {state: "resolved", section: "decided", updated_at: $ts, resolved_at: $ts, resolution_note: $note_v}
        else . end
      )) as $updated
    | ($found | tostring), ($updated | tojson)
    ' -r)
  found="${out%%$'\n'*}"
  found="${found%$'\r'}"   # strip a trailing \r (seen on this Windows/Git-Bash jq build)
  new="${out#*$'\n'}"
  new="${new%$'\r'}"
  if [[ "$found" != "true" ]]; then
    err "resolve: not found: $id"
    return 1
  fi
  _ny_write_ledger "$new" || { err "resolve: aborting — ledger write was rejected (see previous error); $id was NOT marked resolved"; return 1; }
  cmd_render >/dev/null
}

# ----------------------------------------------------------------------
# cmd_expire — collapse "decided" items resolved >7 days ago into a count.
# Does not delete data; flags items as collapsed=true so render can filter
# them from the itemized list and fold them into the trailing count line.
# Idempotent: safe to run every render call.
# ----------------------------------------------------------------------
NY_REVIEW_WINDOW_DAYS=7

# NY_STALE_OPEN_DAYS (readability review 2026-08-03, S4): open decisions /
# questions / in-flight items older than this (by created_at for decisions,
# by the dedup group's FIRST-SEEN date for questions/inflight) render-time
# demote out of their normal section into "## Probably dead — confirm to
# close" instead of costing full-length attention forever. Render-time-only
# partition -- NO ledger mutation (cmd_render stays idempotent; re-render is
# still byte-identical apart from the Generated timestamp). One threshold
# call made decide-and-go per the review's "Open questions for the operator"
# section: 14 days is long enough that a week away doesn't demote a live
# ask, short enough that a month-old cohort collapses.
NY_STALE_OPEN_DAYS=14

cmd_expire() {
  _ny_ensure_state
  local cutoff_secs=$(( NY_REVIEW_WINDOW_DAYS * 86400 ))

  # Single jq call, no bash loop: for every resolved item with a
  # resolved_at timestamp older than the review window, set collapsed=true;
  # every other resolved item gets collapsed normalized to its current
  # value (defaulting false). Uses jq's own now/fromdateiso8601 (same
  # technique as decision-queue.sh's age_days) instead of shelling out to
  # `date` per item — both for correctness and to avoid the per-item
  # subprocess churn this rewrite exists to eliminate.
  local cur; cur=$(_ny_read_ledger)
  local new
  new=$(echo "$cur" | jq --argjson cutoff "$cutoff_secs" '
    (now) as $now
    | .items |= map(
        if .state == "resolved" and (.resolved_at // "" | length > 0) then
          ((try (.resolved_at | fromdateiso8601) catch null)) as $r
          | if ($r != null) and (($now - $r) > $cutoff) then
              . + {collapsed: true}
            else
              . + {collapsed: (.collapsed // false)}
            end
        else . end
      )
    ')
  # Best-effort per this function's own contract ("Exit 0 always — a
  # maintenance sweep, not a query"): if the write is rejected (empty/
  # invalid $new — see _ny_write_ledger's WRITE SAFETY guard), leave the
  # existing ledger untouched and just skip this pass rather than failing
  # the render pipeline that called us.
  _ny_write_ledger "$new" || err "expire: skipped this pass — ledger write was rejected (see previous error); existing ledger left untouched"
  return 0
}

# ----------------------------------------------------------------------
# render helpers
# ----------------------------------------------------------------------

# jq's @tsv escapes embedded tabs/newlines/backslashes as literal \t \n \\
# (so a multi-line --text value stays a single TSV row). Reverse that after
# `read` splits the row back into fields, so a §3 block's line breaks render
# as real line breaks again, not literal backslash-n.
#
# ORDER MATTERS (nl-issues 2026-07-29 "needs-you.sh render corrupts paths"):
# a literal backslash in the ORIGINAL text (e.g. a Windows path segment like
# "Example Co\neural-lace") is jq-@tsv-encoded as TWO backslash chars
# ("\\") immediately followed by the literal 'n' -- i.e. \\n. Unescaping \t
# and \n BEFORE restoring \\ (the previous implementation's order) makes the
# second half of that escaped backslash look exactly like a real \n newline
# token, so it got converted to an actual newline and silently ATE the 'n' --
# splitting the path mid-word ("Example Co\" / "eural-lace"). Fix:
# swap every escaped backslash out for a placeholder byte FIRST, so it can
# never be misread as half of a \t/\n token; only restore the real backslash
# at the very end, after \t/\n have already been expanded from what's left.
_ny_tsv_unescape() {
  local s="$1"
  local placeholder=$'\x01'
  s="${s//\\\\/$placeholder}"
  s="${s//\\t/$'\t'}"
  s="${s//\\n/$'\n'}"
  s="${s//$placeholder/\\}"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# Liveness check (same nl-issues entry, defect class (c) "dead references"):
# a rendered entry can point at a local file path that no longer exists by
# the time the operator reads it (e.g. a scratchpad script that aged out 10+
# days ago). This NEVER deletes or edits the ledger entry or its original
# text -- it only appends one extra informational line at render time.
# Read-only, best-effort, and deliberately narrow: a candidate that isn't
# confidently a local path (a URL, an ambiguous bare word) is left alone
# rather than risking a false "dead" claim on something that's actually fine.
# ----------------------------------------------------------------------

# _ny_local_path_candidates_from_text <text>
#   Extract local-path-shaped tokens embedded in free text: (a) Windows
#   absolute paths (C:\...) and (b) POSIX absolute paths, BOTH only inside
#   double quotes. Deliberately narrow: an unquoted scan risks matching
#   inside a URL (https://host/path/file.md), inside ordinary unquoted
#   repo-relative prose (which should use the structured links[] field
#   instead), or -- the false-positive this comment used to not warn about,
#   caught live in the real machine ledger the first time this rendered
#   against production data -- truncating an unquoted Windows path at the
#   first SPACE in a directory name ("C:\Users\operator\dev\Example Co\..."
#   has a space in "Example Co"; an unquoted, whitespace-terminated
#   match produced the truncated fragment "C:\Users\operator\dev\Example", which
#   isn't a real path at all and got wrongly flagged dead). Every real "run
#   this file" pointer actually seen in this ledger is double-quoted
#   (`bash "C:\...\foo.sh"` / `bash "/tmp/.../foo.sh"`), so scoping BOTH
#   halves to quotes matches the real shape without widening the net or
#   truncating on an embedded space. A single leading slash (not "//") on
#   the POSIX half also keeps it from matching a scheme-relative URL
#   fragment.
_ny_local_path_candidates_from_text() {
  local text="$1"
  {
    printf '%s' "$text" | grep -oE '"[A-Za-z]:\\[^"]+"' 2>/dev/null | sed -E 's/^"//; s/"$//'
    printf '%s' "$text" | grep -oE '"/[^/"][^"]*"' 2>/dev/null | sed -E 's/^"//; s/"$//'
  } | sort -u
}

# _ny_path_is_dead <path>
#   True (exit 0) iff <path> looks like a local filesystem reference (not a
#   URL) and does not exist. Absolute paths are checked as-is; anything else
#   is resolved relative to the MAIN-CHECKOUT root (nl_main_checkout_root --
#   same resolver _ny_md_path uses above) since a repo-relative path in
#   ledger text/links is always meant relative to the repo, never this
#   script's own cwd.
_ny_path_is_dead() {
  local p="$1"
  # Strip a trailing \r: jq -r on this Windows/Git-Bash build emits CRLF line
  # endings (same quirk cmd_resolve already works around below), so a path
  # read line-by-line from `jq -r '.links[]?'` via a `while read` loop picks
  # up a trailing carriage return that makes `[[ -e ... ]]` spuriously fail
  # on a file that DOES exist -- caught by self-test T38c (T34c pre-renumber; false positive on
  # a live path) before this guard was added.
  p="${p%$'\r'}"
  [[ -n "$p" ]] || return 1
  case "$p" in
    http://*|https://*) return 1 ;;
  esac
  [[ -e "$p" ]] && return 1
  local root=""
  if command -v nl_main_checkout_root >/dev/null 2>&1; then
    root="$(nl_main_checkout_root)"
  fi
  if [[ -n "$root" && -e "$root/$p" ]]; then
    return 1
  fi
  return 0
}

# _ny_liveness_note <text> [link]...
#   Scans <text> for embedded Windows-absolute-path tokens and checks every
#   passed link; returns ONE rendered annotation line naming every dead
#   reference found (or nothing at all if everything resolves / nothing
#   path-shaped was found). Never mutates its inputs.
_ny_liveness_note() {
  local text="$1"; shift
  local -a dead=()
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    _ny_path_is_dead "$p" && dead+=("$p")
  done < <(_ny_local_path_candidates_from_text "$text")
  for p in "$@"; do
    [[ -n "$p" ]] || continue
    _ny_path_is_dead "$p" && dead+=("$p")
  done
  [[ "${#dead[@]}" -eq 0 ]] && return 0
  local -a uniq_dead=()
  local seen="|" already
  for p in "${dead[@]}"; do
    case "$seen" in *"|$p|"*) already=1 ;; *) already=0 ;; esac
    if [[ "$already" == "0" ]]; then
      uniq_dead+=("$p")
      seen="${seen}${p}|"
    fi
  done
  local joined="" p2
  for p2 in "${uniq_dead[@]}"; do
    if [[ -z "$joined" ]]; then joined="$p2 [path no longer exists]"
    else joined="$joined; $p2 [path no longer exists]"
    fi
  done
  printf '_(liveness: %s)_\n' "$joined"
}

# Render a single "Awaiting your decision" block (compact §3-style).
# Single jq call (tab-joined fields) rather than one jq invocation per field —
# keeps subprocess churn down since render can iterate many items.
_ny_render_decision_block() {
  local it="$1"
  local fields text session id created links_line
  fields=$(echo "$it" | jq -r '[.text, (.session // "unknown"), .id, (.created_at | split("T")[0]), (.links // [] | if length == 0 then "(none)" else join(" ") end)] | @tsv')
  IFS=$'\t' read -r text session id created links_line <<< "$fields"
  text="$(_ny_tsv_unescape "$text")"
  # links_line went through the SAME jq @tsv escaping as text (backslashes
  # doubled) but was never unescaped -- a repo path in Links: rendered as
  # literal doubled backslashes ("C:\\Users\\...") instead of a real single
  # backslash. Same fix, same helper.
  links_line="$(_ny_tsv_unescape "$links_line")"

  # S1 (needs-you readability review 2026-08-03, Finding 1 — render-title-
  # duplication): the OLD code printed `### $(head -1 text)` and then the
  # FULL text verbatim, including that same first line — every decision
  # block's first two lines were identical walls. Fix: the title line is
  # ONLY the (markdown-heading-stripped) first line of text; the body is
  # everything AFTER that first line (tail -n +2), and is omitted entirely
  # for a single-line entry rather than printing an empty line.
  local title
  title=$(printf '%s' "$text" | head -1)
  # Strip a leading "#{1,6} " heading marker so a --text block whose first
  # line is itself "### Foo" renders as "### Foo", not "### ### Foo" (the
  # live double-hash defect the review's NY-1783716259-0a77 entry exhibited).
  title=$(printf '%s' "$title" | sed -E 's/^#{1,6}[[:space:]]+//')
  [[ -n "$title" ]] || title="(untitled decision)"

  local line_count body=""
  line_count=$(printf '%s\n' "$text" | wc -l | tr -d ' ')
  if [[ "${line_count:-0}" -gt 1 ]]; then
    body="$(printf '%s\n' "$text" | tail -n +2)"
  fi

  printf '### %s\n' "$title"
  [[ -n "$body" ]] && printf '%s\n' "$body"

  # Empty-field noise (Finding 8): suppress "Links: (none)" and a spelled-
  # out "session `unknown`" — every line here competes with the signal.
  [[ "$links_line" != "(none)" ]] && printf 'Links: %s\n' "$links_line"
  if [[ -z "$session" || "$session" == "unknown" ]]; then
    printf '*(added %s, id `%s`)*\n' "$created" "$id"
  else
    printf '*(added %s, session `%s`, id `%s`)*\n' "$created" "$session" "$id"
  fi

  local -a raw_links=()
  local _ny_rl
  while IFS= read -r _ny_rl; do
    _ny_rl="${_ny_rl%$'\r'}"
    [[ -n "$_ny_rl" ]] && raw_links+=("$_ny_rl")
  done < <(echo "$it" | jq -r '.links[]?')
  local note; note="$(_ny_liveness_note "$text" "${raw_links[@]}")"
  [[ -n "$note" ]] && printf '%s\n' "$note"
}

_ny_render_bullet() {
  local it="$1"
  local fields text session created dedup_count first_seen
  fields=$(echo "$it" | jq -r '[.text, (.session // "unknown"), (.created_at | split("T")[0]), (._dedup_count // 1), ((._first_seen // .created_at) | split("T")[0])] | @tsv')
  IFS=$'\t' read -r text session created dedup_count first_seen <<< "$fields"
  text="$(_ny_tsv_unescape "$text")"
  # Dedup collapse (nl-issues 2026-07-29, defect class (b) "duplicate
  # noise"; renormalized S5, needs-you readability review 2026-08-03):
  # cmd_render's caller groups open bullets by NORMALIZED text (volatile
  # spans like "3d ago"/"alert #12" stripped before grouping) and stamps
  # ._dedup_count == the group size, ._first_seen == the earliest member's
  # created_at, and the item itself is the NEWEST member of the group (so
  # `text`/`session`/`created` here reflect the most recent, most current
  # occurrence — not a stale first report). When the group has more than
  # one member, name the repeat count and cite when it was FIRST seen,
  # instead of silently rendering N near-identical lines.
  local _ny_session_clause=""
  [[ -n "$session" && "$session" != "unknown" ]] && _ny_session_clause=", session \`$session\`"
  if [[ "${dedup_count:-1}" -gt 1 ]]; then
    printf -- '- %s — *(added %s%s; x%s since %s)*\n' "$text" "$created" "$_ny_session_clause" "$dedup_count" "$first_seen"
  else
    printf -- '- %s — *(added %s%s)*\n' "$text" "$created" "$_ny_session_clause"
  fi

  local -a raw_links=()
  local _ny_rl
  while IFS= read -r _ny_rl; do
    _ny_rl="${_ny_rl%$'\r'}"
    [[ -n "$_ny_rl" ]] && raw_links+=("$_ny_rl")
  done < <(echo "$it" | jq -r '.links[]?')
  local note; note="$(_ny_liveness_note "$text" "${raw_links[@]}")"
  [[ -n "$note" ]] && printf '%s\n' "$note"
}

_ny_render_decided_line() {
  local it="$1"
  local fields text resolved note
  fields=$(echo "$it" | jq -r '[.text, ((.resolved_at // "") | split("T")[0]), (.resolution_note // "")] | @tsv')
  IFS=$'\t' read -r text resolved note <<< "$fields"
  text="$(_ny_tsv_unescape "$text")"
  note="$(_ny_tsv_unescape "$note")"
  if [[ -n "$note" ]]; then
    printf -- '- %s — resolved %s: %s\n' "$text" "$resolved" "$note"
  else
    printf -- '- %s — resolved %s\n' "$text" "$resolved"
  fi
}

# ----------------------------------------------------------------------
# _ny_render_decide_now_row <item-json> <row-number>  (S2, needs-you
# readability review 2026-08-03) — one row of the new "## Decide now" table
# rendered above the four canonical sections. <item-json> is one item from
# cmd_render's decide_now_rows pool (an open decision or a deduped-fresh
# open question, already carrying ._age_days from its source computation).
# Columns: # | id (short suffix) | Ask (title, <=70 chars) | Reply with
# (the .reply_with field if the caller supplied --reply-with, else a
# heuristic extraction of the first text line matching /reply/i) | Age |
# Blocking?.
# ----------------------------------------------------------------------
_ny_render_decide_now_row() {
  local it="$1" idx="$2"
  # Field separator: \x01 (NOT @tsv's tab). bash's `read` treats consecutive
  # IFS WHITESPACE characters (space/tab/newline — tab included, regardless
  # of what IFS is set to) as a SINGLE delimiter and silently drops empty
  # fields between them; reply_with is legitimately empty whenever neither
  # --reply-with nor a heuristic "reply" line was found, which with a tab
  # delimiter silently shifted every column after it left by one. \x01 is
  # not IFS-whitespace, so empty fields survive `read` intact (verified: a
  # tab-delimited row with an empty middle field reads back with age/
  # blocking shifted left by one; the same row with \x01 reads back
  # correctly). This also means these already-single-line, hash/pipe-
  # sanitized fields need no _ny_tsv_unescape pass (no @tsv backslash
  # escaping was ever applied to them).
  local fields idsuf title reply age blocking
  fields=$(echo "$it" | jq -r '
    def striphash: sub("^#{1,6}[[:space:]]+"; "");
    (.id | split("-") | last) as $idsuf
    | ((.text | split("\n")[0]) | striphash | gsub("[|]"; "/")) as $title0
    | (if ($title0 | length) > 70 then ($title0[0:69] + "…") else $title0 end) as $title
    | ((.reply_with // first(.text | split("\n")[] | select(test("reply"; "i"))) // "")) as $reply0
    | (($reply0 | gsub("[|]"; "/"))) as $reply1
    | (._age_days // 0) as $age
    | (if (.blocking // false) then "yes" else "no" end) as $blocking
    | [$idsuf, $title, $reply1, ($age | tostring), $blocking] | join("")
  ')
  fields="${fields%$'\r'}"
  IFS=$'\x01' read -r idsuf title reply age blocking <<< "$fields"
  # A heuristically-extracted line still carries its markdown/label
  # decoration ("**Reply with:**", "Reply:") — strip it down to the payload.
  # A --reply-with field (already just the payload) passes through unchanged.
  reply="$(printf '%s' "$reply" | sed -E 's/\*\*//g; s/^[[:space:]]*[Rr]eply( with)?:?[[:space:]]*//; s/[[:space:]]+$//')"
  [[ -n "$reply" ]] || reply="(see block below)"
  [[ -n "$title" ]] || title="(untitled)"
  printf '| %s | `%s` | %s | %s | %sd | %s |\n' "$idx" "$idsuf" "$title" "$reply" "$age" "$blocking"
}

# ----------------------------------------------------------------------
# _ny_render_dead_line <item-json>  (S4, needs-you readability review
# 2026-08-03) — one line of the new "## Probably dead — confirm to close"
# section. <item-json> is any open decision/question/inflight item whose
# ._age_days (decisions: since created_at; questions/inflight: since the
# dedup group's first-seen date) exceeds NY_STALE_OPEN_DAYS. This NEVER
# mutates the ledger or resolves anything itself — it is a render-time-only
# demotion (cmd_render stays idempotent); the reply affordance is advisory
# text for a human/agent to act on via the existing `resolve` verb. Display
# uses the short id SUFFIX (matches the digest's convention, e.g. `caeb`)
# but the reply affordance carries the FULL id, since `resolve <id>` still
# requires an exact match — the hard contract's ids are unchanged.
# ----------------------------------------------------------------------
_ny_render_dead_line() {
  local it="$1"
  local fields id title age
  fields=$(echo "$it" | jq -r '
    def striphash: sub("^#{1,6}[[:space:]]+"; "");
    [.id, ((.text | split("\n")[0]) | striphash | gsub("[|]"; "/")), (._age_days // 0 | tostring)] | @tsv
  ')
  IFS=$'\t' read -r id title age <<< "$fields"
  title="$(_ny_tsv_unescape "$title")"
  [[ -n "$title" ]] || title="(untitled)"
  local idsuf="${id##*-}"
  printf -- '- `%s` %s · %sd — reply `confirm dead %s` (resolves) / `still live %s` (re-promotes)\n' \
    "$idsuf" "$title" "$age" "$id" "$id"
}

# ----------------------------------------------------------------------
# NY_CANONICAL_HEADERS — the four canonical section headers, in render order.
# Shared by cmd_bootstrap_migrate (presence check) and the self-test.
# ----------------------------------------------------------------------
NY_CANONICAL_HEADERS=(
  "## Awaiting your decision"
  "## Open questions"
  "## In flight (sessions + waves)"
  "## Recently decided for your §8 review"
)

# _ny_md_has_all_headers <path> — true (exit 0) iff the file exists and
# contains all 4 canonical headers; false otherwise (absent file, or present
# but missing one or more headers — e.g. a stale hand-authored file).
_ny_md_has_all_headers() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  local h
  for h in "${NY_CANONICAL_HEADERS[@]}"; do
    grep -qF "$h" "$path" 2>/dev/null || return 1
  done
  return 0
}

# _ny_ledger_has_legacy_migration_marker — true iff the ledger already
# recorded a migrated-legacy-file item (migration is idempotent: run once).
_ny_ledger_has_legacy_migration_marker() {
  local cur; cur=$(_ny_read_ledger)
  local n
  n=$(echo "$cur" | jq '[.items[] | select(.tier == "migrated_from_legacy_file")] | length' 2>/dev/null || echo 0)
  [[ "${n:-0}" -gt 0 ]]
}

# ----------------------------------------------------------------------
# cmd_bootstrap_migrate — NL-FINDING-035. See header comment ("bootstrap-
# migrate") for the full contract. Best-effort, idempotent, never fails the
# render it precedes.
# ----------------------------------------------------------------------
cmd_bootstrap_migrate() {
  _ny_ensure_state
  local md_path; md_path="$(_ny_md_path)"

  # Already-canonical (or already-migrated): nothing to do.
  _ny_md_has_all_headers "$md_path" && return 0
  _ny_ledger_has_legacy_migration_marker && return 0

  # Absent file with an empty ledger and no prior migration: nothing to
  # migrate — a plain render (which the caller performs next) will create a
  # well-formed file from scratch. Only ingest content when the file exists
  # and actually has non-whitespace body content worth preserving.
  if [[ ! -f "$md_path" ]]; then
    return 0
  fi

  local body
  body="$(cat "$md_path" 2>/dev/null)"
  # Strip a leading "# NEEDS-YOU"-style title line (any leading-#-heading
  # whose text starts with NEEDS-YOU, matching both the "# NEEDS-YOU" and
  # "# NEEDS-YOU.md — ..." variants seen in the wild) and any blank lines
  # immediately after it, so (a) we can tell if there's any substantive
  # content left to migrate, and (b) the migrated item's TITLE (the render
  # pipeline's `head -1` of --text) is the real first content line — e.g.
  # "## [2026-07-05] Activate auto-resume daemon (E.7) ..." — rather than
  # this boilerplate banner line collapsing to "(untitled decision)".
  #
  # PORTABILITY (fixed 2026-07-29): the address-block form MUST be written
  # `1{...;}` with the trailing semicolon. BSD/macOS sed rejects `1{/re/d}`
  # with "extra characters at the end of d command" and emits NOTHING, which
  # silently collapsed `stripped` to empty and made this function return
  # early — losing every legacy operator item on macOS while passing on GNU
  # sed (self-test T18b/T18c/T19). `d;}` is the POSIX-portable spelling and
  # is accepted by both BSD sed and GNU sed. Each strip step is therefore
  # also FAILURE-CHECKED below rather than piped blind: if a strip step ever
  # errors again, we fall back to the un-stripped text, because migrating a
  # slightly-uglier title is strictly better than discarding operator content.
  local stripped="$body" _ny_trimmed
  if _ny_trimmed="$(printf '%s\n' "$body" | sed -E '1{/^# NEEDS-YOU/d;}')"; then
    stripped="$_ny_trimmed"
  fi
  if _ny_trimmed="$(printf '%s\n' "$stripped" | sed -E '/./,$!d')"; then
    stripped="$_ny_trimmed"
  fi
  if [[ -z "$(printf '%s\n' "$stripped" | grep -vE '^[[:space:]]*$')" ]]; then
    return 0
  fi

  # Ingest the stripped pre-existing body as one migrated decision entry, so
  # a hand-authored heading (e.g. an operator "## [DATE] <title>" block with
  # **Context:**/**What I need:**/**Reply:** lines) survives as a real
  # ledger item under "Awaiting your decision" instead of being silently
  # overwritten by the next render. --tier carries the
  # "migrated_from_legacy_file" marker (idempotency + provenance); it is not
  # one of the normal 1|2|3 reversibility tiers and is never interpreted as
  # such by render (render only ever prints --tier for informational
  # purposes and doesn't currently render it at all, so this is safe).
  # --mechanical: bootstrap-migrate is an automatic sweep with no live actor
  # present to retry a blocked add — arbitrary legacy prose must land in the
  # ledger regardless of cold-reader shape (A1 ledger-never-rejects; losing
  # pre-existing content here would be strictly worse than a lint warning).
  cmd_add --section decision --text "$stripped" --session "legacy-migration" \
    --tier "migrated_from_legacy_file" --mechanical >/dev/null

  return 0
}

# ----------------------------------------------------------------------
# _NY_NORMKEY_JQDEF — shared jq `def normkey: ...;` text (S5, needs-you
# readability review 2026-08-03, Finding 4). Strips VOLATILE spans from an
# item's text before dedup-grouping, so a recurring mechanical emitter
# (supervisor-tick's orphaned-worktree alert is the observed case: "last
# commit Nd ago", "alert #N", "N live/throttled session(s)") groups its
# near-identical re-reports into ONE bullet instead of N. Literal parens in
# the volatile spans are matched via a bracket class ([(]/[)]) rather than a
# backslash escape — jq string literals treat a bare `\(` as the START of
# string interpolation, not an escaped paren, so `[(]`/`[)]` is both correct
# and readable. Interpolated into both the Open-questions and In-flight jq
# pipelines below (recurring noise was observed in both sections).
# ----------------------------------------------------------------------
_NY_NORMKEY_JQDEF='def normkey:
    gsub("[0-9]+d ago"; "Nd ago")
    | gsub("alert #[0-9]+"; "alert #N")
    | gsub("[0-9]+ live/throttled session[(]s[)]"; "N live/throttled session(s)")
    | gsub("dirty=[0-9]+ file[(]s[)]"; "dirty=N file(s)")
    | gsub("unintegrated=[0-9]+ commit[(]s[)]"; "unintegrated=N commit(s)")
    | gsub("First detected [^;]*;"; "First detected ;");'

# ----------------------------------------------------------------------
# _ny_split_tagged <tagged-jsonl>  (used by cmd_render's S4 fresh/stale
# partition below).
#
# PERFORMANCE NOTE (this environment): sequential jq subprocess spawns
# inside a single long-lived bash process have been observed to HANG on
# this machine past a certain count (cmd_add's own jq-add-call comment
# notes the same class). An early draft of cmd_render's fresh/stale
# partitioning spawned ~14 jq processes per render (compute + a
# fresh-filter + a stale-filter, x3 sections, plus separate `length`
# calls) and reproducibly hung by the 2nd `add` in a row (each `add` calls
# `render` internally). Fix: each section's jq call does age-tagging AND
# emits a fresh/stale TAG prefix per line ("F\t{...}" / "S\t{...}") in ONE
# pass; the fresh/stale SPLIT itself happens here in pure bash (no
# subprocess). Counts use _ny_count_lines (grep, no subprocess spawn cost
# beyond grep itself) instead of a separate `jq length` call. This drops
# the fixed per-render jq-process count from ~14 to ~5.
#
# PORTABILITY: no `local -n` nameref (bash <4.3 — including this repo's
# macOS/bash-3.2 floor — has no namerefs at all). Sets the two GLOBAL-scope
# vars _NY_SPLIT_FRESH / _NY_SPLIT_STALE (safe: cmd_render is never
# re-entrant/concurrent within one process); the caller copies them out
# into its own locals immediately after each call.
# ----------------------------------------------------------------------
_ny_split_tagged() {
  local _ny_st_in="$1"
  _NY_SPLIT_FRESH=""; _NY_SPLIT_STALE=""
  local _ny_st_tag _ny_st_json
  while IFS=$'\t' read -r _ny_st_tag _ny_st_json; do
    [[ -z "$_ny_st_tag" ]] && continue
    if [[ "$_ny_st_tag" == "F" ]]; then
      _NY_SPLIT_FRESH+="$_ny_st_json"$'\n'
    else
      _NY_SPLIT_STALE+="$_ny_st_json"$'\n'
    fi
  done <<< "$_ny_st_in"
}

# _ny_count_lines <possibly-empty-jsonl-string> — count of non-blank lines,
# no jq subprocess (see _ny_split_tagged's PERFORMANCE NOTE above).
_ny_count_lines() {
  [[ -z "$1" ]] && { printf '0'; return; }
  printf '%s\n' "$1" | grep -c '.'
}

# ----------------------------------------------------------------------
# cmd_render — bootstrap-migrate, then expire, then rewrite NEEDS-YOU.md in
# full: the "## Decide now" summary + the four canonical sections (fresh
# items only) + "## Probably dead — confirm to close" (S2-S4, needs-you
# readability review 2026-08-03), always in the same order, always with all
# four CANONICAL headers present even when empty (the new sections are
# ADDITIVE — see _ny_md_has_all_headers's own comment for why the canonical
# four must never go missing).
# ----------------------------------------------------------------------
cmd_render() {
  _ny_ensure_state
  cmd_bootstrap_migrate
  cmd_expire

  local cur; cur=$(_ny_read_ledger)
  local md_path; md_path="$(_ny_md_path)"
  local md_dir; md_dir="$(dirname "$md_path")"
  mkdir -p "$md_dir" 2>/dev/null || die "cannot create dir for NEEDS-YOU.md: $md_dir"

  local tmp; tmp=$(mktemp "${md_path}.XXXXXX") || die "mktemp failed"

  # S3/S4: decisions — every OPEN decision gets ._age_days (jq's own `now`,
  # matching cmd_expire's existing convention — no bash/jq clock-skew risk),
  # then ONE overall order: newest-first (sort_by(.created_at)|reverse),
  # THEN a second STABLE sort hoisting .blocking==true to the top (stable
  # sort preserves the newest-first order within each blocking group — the
  # standard "sort by secondary key, then stable-sort by primary key" trick,
  # no compound key needed), then a fresh/stale TAG per S4's threshold.
  local decisions_tagged decisions_fresh decisions_stale
  decisions_tagged=$(echo "$cur" | jq -r --argjson stale "$NY_STALE_OPEN_DAYS" '
    (now) as $now
    | [.items[] | select(.section == "decision" and .state == "open")
        | . + {_age_days: (($now - (.created_at | fromdateiso8601)) / 86400 | floor)}]
    | sort_by(.created_at) | reverse
    | sort_by(if (.blocking // false) then 0 else 1 end)
    | .[]
    | (if (._age_days <= $stale) then "F" else "S" end) + "\t" + (tojson)
    ')
  _ny_split_tagged "$decisions_tagged"; decisions_fresh="$_NY_SPLIT_FRESH"; decisions_stale="$_NY_SPLIT_STALE"

  # S4/S5: questions — normalize+dedup (S5's normkey), keep the NEWEST
  # member of each group as the representative (text/session reflect the
  # most current occurrence), stamp ._first_seen (earliest member) and
  # ._dedup_count, age the GROUP by ._first_seen (a topic still being
  # actively re-reported stays "fresh" even if it started long ago; one
  # that stopped being reported goes stale), tag fresh/stale. Order stays
  # chronological (oldest-topic-first) — "questions/inflight are logs, not
  # queues" (S3's "Required generalization").
  local questions_tagged questions_fresh questions_stale
  questions_tagged=$(echo "$cur" | jq -r --argjson stale "$NY_STALE_OPEN_DAYS" "
    $_NY_NORMKEY_JQDEF
    (now) as \$now
    | [.items[] | select(.section == \"question\" and .state == \"open\")]
    | group_by(.text | normkey)
    | map(
        (sort_by(.created_at)) as \$g
        | (\$g[0].created_at) as \$fs
        | (\$g[-1] + {_dedup_count: (\$g | length), _first_seen: \$fs})
      )
    | map(. + {_age_days: ((\$now - (._first_seen | fromdateiso8601)) / 86400 | floor)})
    | sort_by(._first_seen)
    | .[]
    | (if (._age_days <= \$stale) then \"F\" else \"S\" end) + \"\t\" + (tojson)
    ")
  _ny_split_tagged "$questions_tagged"; questions_fresh="$_NY_SPLIT_FRESH"; questions_stale="$_NY_SPLIT_STALE"

  # In flight: same normalize+dedup+age+tag treatment as questions above —
  # this is the section that actually accumulated ~30 near-identical
  # unresolved stop-gate rows in production (nl-issues 2026-07-29).
  local inflight_tagged inflight_fresh inflight_stale
  inflight_tagged=$(echo "$cur" | jq -r --argjson stale "$NY_STALE_OPEN_DAYS" "
    $_NY_NORMKEY_JQDEF
    (now) as \$now
    | [.items[] | select(.section == \"inflight\" and .state == \"open\")]
    | group_by(.text | normkey)
    | map(
        (sort_by(.created_at)) as \$g
        | (\$g[0].created_at) as \$fs
        | (\$g[-1] + {_dedup_count: (\$g | length), _first_seen: \$fs})
      )
    | map(. + {_age_days: ((\$now - (._first_seen | fromdateiso8601)) / 86400 | floor)})
    | sort_by(._first_seen)
    | .[]
    | (if (._age_days <= \$stale) then \"F\" else \"S\" end) + \"\t\" + (tojson)
    ")
  _ny_split_tagged "$inflight_tagged"; inflight_fresh="$_NY_SPLIT_FRESH"; inflight_stale="$_NY_SPLIT_STALE"

  # ------------------------------------------------------------------
  # S2: Decide-now pool — fresh open decisions UNION fresh (deduped) open
  # questions, re-sorted by the SAME blocking-then-newest rule as decisions
  # above, capped at 10 rows. Slurped from the two already-fresh JSONL
  # streams (no re-querying the ledger) — ONE jq call.
  # ------------------------------------------------------------------
  local decide_now_total decide_now_rows
  decide_now_total=$(( $(_ny_count_lines "$decisions_fresh") + $(_ny_count_lines "$questions_fresh") ))
  decide_now_rows=$(printf '%s\n%s\n' "$decisions_fresh" "$questions_fresh" | jq -cs '
    sort_by(.created_at) | reverse
    | sort_by(if (.blocking // false) then 0 else 1 end)
    | .[0:10]
    | .[]
    ')

  # S4: Probably-dead pool — every stale decision/question/inflight item,
  # oldest (largest ._age_days) first. ONE jq call.
  local dead_count dead_pool
  dead_count=$(( $(_ny_count_lines "$decisions_stale") + $(_ny_count_lines "$questions_stale") + $(_ny_count_lines "$inflight_stale") ))
  dead_pool=$(printf '%s\n%s\n%s\n' "$decisions_stale" "$questions_stale" "$inflight_stale" | jq -cs 'sort_by(._age_days) | reverse | .[]')

  local questions_fresh_count
  questions_fresh_count=$(_ny_count_lines "$questions_fresh")

  {
    printf '# NEEDS-YOU\n'
    # S2's count banner replaces the old 2-line "Generated <ts>." tail — the
    # answer to "what do you need from me" is now the first screen instead
    # of buried after a boilerplate paragraph (Finding 5, missing-executive-
    # summary). The do-not-hand-edit notice survives, de-emphasized.
    printf 'Generated %s · %s decide-now · %s probably-dead · %s open question(s)\n\n' \
      "$(_ny_now)" "$decide_now_total" "$dead_count" "$questions_fresh_count"
    printf '_Canonical awaiting-operator ledger (constitution §2/§3/§8). Machine-local, mechanically maintained by `adapters/claude-code/scripts/needs-you.sh` — do not hand-edit; re-render will overwrite._\n\n'

    printf '## Decide now\n\n'
    if [[ -z "$decide_now_rows" ]]; then
      printf '_Nothing needs an answer right now._\n\n'
    else
      printf '| # | id | Ask | Reply with | Age | Blocking? |\n'
      printf '|---|------|-----------------------------------------------------------|----------------------------------|-----|-----------|\n'
      local _ny_dn_i=0
      while IFS= read -r _ny_dn_row; do
        [[ -n "$_ny_dn_row" ]] || continue
        _ny_dn_i=$((_ny_dn_i + 1))
        _ny_render_decide_now_row "$_ny_dn_row" "$_ny_dn_i"
      done <<< "$decide_now_rows"
      if [[ "${decide_now_total:-0}" -gt 10 ]]; then
        printf '\n_(showing the 10 most urgent of %s eligible; the rest are listed under their normal section below.)_\n' "$decide_now_total"
      fi
      printf '\n'
    fi

    printf '## Awaiting your decision\n\n'
    if [[ -z "$decisions_fresh" ]]; then
      printf '_None open._\n\n'
    else
      while IFS= read -r it; do
        [[ -n "$it" ]] || continue
        _ny_render_decision_block "$it"
        printf '\n'
      done <<< "$decisions_fresh"
    fi

    printf '## Open questions\n\n'
    if [[ -z "$questions_fresh" ]]; then
      printf '_None open._\n\n'
    else
      while IFS= read -r it2; do
        [[ -n "$it2" ]] || continue
        _ny_render_bullet "$it2"
      done <<< "$questions_fresh"
      printf '\n'
    fi

    printf '## In flight (sessions + waves)\n\n'
    if [[ -z "$inflight_fresh" ]]; then
      printf '_Nothing in flight._\n\n'
    else
      while IFS= read -r it3; do
        [[ -n "$it3" ]] || continue
        _ny_render_bullet "$it3"
      done <<< "$inflight_fresh"
      printf '\n'
    fi

    printf '## Probably dead — confirm to close\n\n'
    if [[ -z "$dead_pool" ]]; then
      printf '_None._\n\n'
    else
      printf 'Open more than %s days (decisions: since added; questions/in-flight: since last re-reported), or evidence says superseded. One line each.\n\n' "$NY_STALE_OPEN_DAYS"
      while IFS= read -r it5; do
        [[ -n "$it5" ]] || continue
        _ny_render_dead_line "$it5"
      done <<< "$dead_pool"
      printf '\n'
    fi

    printf '## Recently decided for your §8 review\n\n'
    local decided collapsed_n
    decided=$(echo "$cur" | jq -c '[.items[] | select(.section == "decided" and .state == "resolved" and ((.collapsed // false) == false))] | sort_by(.resolved_at) | reverse | .[]')
    collapsed_n=$(echo "$cur" | jq '[.items[] | select(.section == "decided" and .state == "resolved" and (.collapsed // false) == true)] | length')
    if [[ -z "$decided" && "$collapsed_n" == "0" ]]; then
      printf '_Nothing decided in the last %s days._\n\n' "$NY_REVIEW_WINDOW_DAYS"
    else
      if [[ -n "$decided" ]]; then
        while IFS= read -r it4; do
          [[ -n "$it4" ]] || continue
          _ny_render_decided_line "$it4"
        done <<< "$decided"
      fi
      if [[ "$collapsed_n" -gt 0 ]]; then
        local cutoff_date
        cutoff_date=$(date -u -d "@$(( $(_ny_epoch_now) - NY_REVIEW_WINDOW_DAYS * 86400 ))" +%Y-%m-%d 2>/dev/null \
          || date -u -j -f '%s' "$(( $(_ny_epoch_now) - NY_REVIEW_WINDOW_DAYS * 86400 ))" +%Y-%m-%d 2>/dev/null \
          || echo "unknown")
        printf '\n*(+%s older, resolved before %s)*\n' "$collapsed_n" "$cutoff_date"
      fi
      printf '\n'
    fi
  } > "$tmp" || { rm -f "$tmp"; die "render: write to tmpfile failed"; }

  mv "$tmp" "$md_path" || { rm -f "$tmp"; die "render: atomic rename failed"; }
}

# ----------------------------------------------------------------------
# cmd_has_entry_for_session — pure predicate, exit code is the answer.
# ----------------------------------------------------------------------
cmd_has_entry_for_session() {
  _ny_ensure_state
  local sid="${1:-}"
  [[ -n "$sid" ]] || die "has-entry-for-session: missing <session-id>"
  local cur; cur=$(_ny_read_ledger)
  local n
  n=$(echo "$cur" | jq --arg sid "$sid" '[.items[] | select(.state == "open" and .session == $sid)] | length')
  [[ "$n" -gt 0 ]]
}

# ----------------------------------------------------------------------
# --self-test
# ----------------------------------------------------------------------
cmd_selftest() {
  local sandbox; sandbox=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox/state"
  export NEEDS_YOU_MD_PATH="$sandbox/NEEDS-YOU.md"
  unset HARNESS_SELFTEST 2>/dev/null || true
  # Task 4 splice sandboxing (constraint 4): HARNESS_SELFTEST is explicitly
  # unset above (see the pre-existing comment on the prior line's intent —
  # this self-test exercises its own explicit env-var overrides rather than
  # the HARNESS_SELFTEST branch), so the progress-log CLI and the
  # operator-todo path resolver would otherwise fall through to the REAL
  # $HOME/.claude/state/progress-logs and a real-repo docs/operator-todo.md.
  # Explicit overrides keep every scenario below sandboxed; the FROM-WORKTREE
  # fixture (T30) later clears OPERATOR_TODO_PATH deliberately to exercise
  # the real nl_main_checkout_root() resolution path instead.
  export PROGRESS_LOG_STATE_DIR="$sandbox/progress-logs"
  export OPERATOR_TODO_PATH="$sandbox/operator-todo.md"
  local pass=0 fail=0
  local -a errors=()
  ok()   { pass=$((pass+1)); echo "  PASS: $1"; }
  fail_() { fail=$((fail+1)); echo "  FAIL: $1" >&2; errors+=("$1"); }

  echo "needs-you.sh self-test (sandbox: $sandbox)"

  # T1: add a decision entry, id returned, section renders. This fixture's
  # prose is deliberately terse (below the cold-reader lint's own
  # thresholds — no line >=40 chars, no in-text anchor token) since it
  # predates the lint entirely; --mechanical keeps it exercising plain
  # ledger mechanics (add/render/resolve/expire) rather than tripping the
  # NEW interactive lint-block this task adds (that path gets its own
  # dedicated fixtures at T22-T24d below).
  local id1
  id1=$(cmd_add --section decision --text $'### Ship tonight?\nTier 1 — reversible.\nMy pick: yes.' --session "sess-aaa" --link "https://example.test/pr/1" --mechanical)
  if [[ "$id1" =~ ^NY- ]]; then ok "T1 add decision returns NY- id ($id1)"; else fail_ "T1 add did not return valid id (got '$id1')"; fi

  # T2: NEEDS-YOU.md exists with all 4 headers.
  if [[ -f "$NEEDS_YOU_MD_PATH" ]]; then ok "T2 NEEDS-YOU.md created"; else fail_ "T2 NEEDS-YOU.md missing"; fi
  local headers_ok=1
  for h in "## Awaiting your decision" "## Open questions" "## In flight (sessions + waves)" "## Recently decided for your §8 review"; do
    grep -qF "$h" "$NEEDS_YOU_MD_PATH" || headers_ok=0
  done
  [[ "$headers_ok" == "1" ]] && ok "T3 all 4 section headers present" || fail_ "T3 missing one or more section headers"

  # T4: decision block rendered with §3-ish shape (title + links + session).
  if grep -q "Ship tonight?" "$NEEDS_YOU_MD_PATH" && grep -q "Links: https://example.test/pr/1" "$NEEDS_YOU_MD_PATH" \
     && grep -q 'session `sess-aaa`' "$NEEDS_YOU_MD_PATH"; then
    ok "T4 §3 decision block format (title/links/session all present)"
  else
    fail_ "T4 decision block missing expected fields"
  fi

  # T5: add a question and an inflight item, both render as bullets in their section.
  cmd_add --section question --text "Which deploy target for the new worker?" --session "sess-bbb" >/dev/null
  cmd_add --section inflight --text "Wave E batch 2 building (E.3/E.5/E.6/E.10)" --session "sess-ccc" >/dev/null
  if grep -q "Which deploy target for the new worker?" "$NEEDS_YOU_MD_PATH" \
     && grep -q "Wave E batch 2 building" "$NEEDS_YOU_MD_PATH"; then
    ok "T5 question + inflight entries rendered"
  else
    fail_ "T5 question/inflight entries not found in rendered file"
  fi

  # T6: has-entry-for-session true for a session with an open entry.
  if cmd_has_entry_for_session "sess-aaa"; then ok "T6 has-entry-for-session true (sess-aaa)"; else fail_ "T6 expected true for sess-aaa"; fi

  # T7: has-entry-for-session false for an unknown session.
  if cmd_has_entry_for_session "sess-does-not-exist"; then fail_ "T7 expected false for unknown session"; else ok "T7 has-entry-for-session false (unknown session)"; fi

  # T8: resolve the decision entry -> moves to "Recently decided", section header still present, no longer under Awaiting.
  cmd_resolve "$id1" --note "Shipped; rollback is a 1-line revert" >/dev/null
  local awaiting_block
  awaiting_block=$(awk '/^## Awaiting your decision/{flag=1;next}/^## /{flag=0}flag' "$NEEDS_YOU_MD_PATH")
  if echo "$awaiting_block" | grep -q "Ship tonight?"; then
    fail_ "T8 resolved item still appears under Awaiting your decision"
  else
    ok "T8 resolved item removed from Awaiting your decision"
  fi
  if grep -q "resolved" "$NEEDS_YOU_MD_PATH" && grep -q "Shipped; rollback is a 1-line revert" "$NEEDS_YOU_MD_PATH"; then
    ok "T8b resolved item appears in Recently decided with note"
  else
    fail_ "T8b resolved item / note not found in Recently decided section"
  fi

  # T9: has-entry-for-session now false for sess-aaa (entry no longer open).
  if cmd_has_entry_for_session "sess-aaa"; then fail_ "T9 expected false after resolve (sess-aaa no longer open)"; else ok "T9 has-entry-for-session false after resolve"; fi

  # T10: resolve unknown id -> exit 1. Subshell (not set -e toggling): cmd_resolve
  # returns (not exits) on not-found, but keeping this pattern consistent with
  # T14/T15's subshell wrapping avoids ever depending on set -e/+e state, which
  # this script never otherwise touches.
  local rc10=0
  ( cmd_resolve "NY-does-not-exist" >/dev/null 2>&1 )
  rc10=$?
  [[ "$rc10" != "0" ]] && ok "T10 resolve unknown id exits non-zero" || fail_ "T10 resolve unknown id should have failed"

  # T11: 8-day-old resolved item collapses into a count line, not itemized.
  # --mechanical: this fixture's bare-shorthand text predates the lint and
  # is not the concern of this scenario (aging/collapse, not lint).
  local id_old
  id_old=$(cmd_add --section decision --text "An old decision from last week" --session "sess-old" --mechanical)
  cmd_resolve "$id_old" --note "decided a while back" >/dev/null
  # Backdate resolved_at to 8 days ago directly in the ledger state.
  local ledger_file="$NEEDS_YOU_STATE_DIR/ledger.json"
  local old_ts
  old_ts=$(date -u -d "8 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -j -v-8d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
  local cur; cur=$(cat "$ledger_file")
  local new; new=$(echo "$cur" | jq --arg id "$id_old" --arg ts "$old_ts" '.items |= map(if .id == $id then . + {resolved_at:$ts, updated_at:$ts} else . end)')
  printf '%s\n' "$new" > "$ledger_file"
  cmd_render >/dev/null
  if grep -q "An old decision from last week" "$NEEDS_YOU_MD_PATH"; then
    fail_ "T11 8-day-old decided item still itemized (should have collapsed)"
  else
    ok "T11 8-day-old decided item no longer itemized"
  fi
  if grep -qE '\+1 older, resolved before' "$NEEDS_YOU_MD_PATH"; then
    ok "T11b collapsed count line present"
  else
    fail_ "T11b collapsed count line not found"
  fi

  # T12: a recently-resolved (today) item stays itemized alongside the collapsed count.
  if grep -q "Shipped; rollback is a 1-line revert" "$NEEDS_YOU_MD_PATH"; then
    ok "T12 recent (within-window) resolved item still itemized"
  else
    fail_ "T12 recent resolved item unexpectedly collapsed/missing"
  fi

  # T13: expire is idempotent — running it twice produces the same collapsed count.
  cmd_expire
  cmd_expire
  cmd_render >/dev/null
  local collapse_count; collapse_count=$(grep -oE '\+[0-9]+ older' "$NEEDS_YOU_MD_PATH" | grep -oE '[0-9]+' | head -1)
  [[ "$collapse_count" == "1" ]] && ok "T13 expire idempotent (collapsed count stays 1 across repeat runs)" \
    || fail_ "T13 collapsed count drifted on repeat expire (got '$collapse_count', expected 1)"

  # T14: unknown --section rejected. cmd_add's die() calls exit, but this
  # already runs inside a $(...) command substitution (its own subshell), so
  # that exit only ends the substitution — no set -e/+e toggling needed.
  local bad_out rc14
  bad_out=$(cmd_add --section bogus --text "x" 2>&1)
  rc14=$?
  [[ "$rc14" != "0" ]] && ok "T14 invalid --section rejected" || fail_ "T14 invalid --section accepted (rc=$rc14)"

  # T15: missing --text rejected.
  # Run in a subshell: cmd_add's die() calls exit, which would otherwise
  # terminate this entire self-test process rather than just the failed call.
  ( cmd_add --section question >/dev/null 2>&1 )
  local rc15=$?
  [[ "$rc15" != "0" ]] && ok "T15 missing --text rejected" || fail_ "T15 missing --text accepted"

  # T16: render is safe to call with an empty ledger (fresh sandbox) — all 4
  # headers present with "_None.../Nothing..._" placeholders, no crash.
  local sandbox2; sandbox2=$(mktemp -d)
  ( export NEEDS_YOU_STATE_DIR="$sandbox2/state"
    export NEEDS_YOU_MD_PATH="$sandbox2/NEEDS-YOU.md"
    cmd_render >/dev/null 2>&1 )
  if [[ -f "$sandbox2/NEEDS-YOU.md" ]] && grep -q "_None open._" "$sandbox2/NEEDS-YOU.md" \
     && grep -q "_Nothing in flight._" "$sandbox2/NEEDS-YOU.md" \
     && grep -q "_Nothing decided in the last 7 days._" "$sandbox2/NEEDS-YOU.md"; then
    ok "T16 render on empty ledger produces well-formed placeholders"
  else
    fail_ "T16 render on empty ledger did not produce expected placeholders"
  fi
  rm -rf "$sandbox2"

  # T17: this self-test never touched the real main-checkout NEEDS-YOU.md —
  # sanity check that our sandboxed path is NOT under nl_main_checkout_root().
  local real_root=""
  if command -v nl_main_checkout_root >/dev/null 2>&1; then
    real_root="$(nl_main_checkout_root)"
  fi
  if [[ -n "$real_root" ]]; then
    case "$NEEDS_YOU_MD_PATH" in
      "$real_root"/*|"$real_root")
        fail_ "T17 SANDBOX LEAK: NEEDS_YOU_MD_PATH ($NEEDS_YOU_MD_PATH) resolves under the real main-checkout root ($real_root)"
        ;;
      *) ok "T17 sandbox path isolated from real main-checkout root" ;;
    esac
  else
    ok "T17 sandbox path isolation: SKIP (nl_main_checkout_root unresolvable in this env)"
  fi

  rm -rf "$sandbox"

  # Task 4 splice: $sandbox (holding PROGRESS_LOG_STATE_DIR/OPERATOR_TODO_PATH)
  # was just removed above; re-point both at a fresh dir so the remaining
  # scenarios below (T18+, several of which call cmd_add --section
  # decision|question) don't silently resurrect the just-deleted path via
  # pl_emit/_ny_operator_todo_ensure's own `mkdir -p`. Cleaned up at the very
  # end of this self-test alongside sandbox6.
  local _ny_t4_sandbox; _ny_t4_sandbox=$(mktemp -d)
  export PROGRESS_LOG_STATE_DIR="$_ny_t4_sandbox/progress-logs"
  export OPERATOR_TODO_PATH="$_ny_t4_sandbox/operator-todo.md"

  # ----------------------------------------------------------------------
  # T18-T21: NL-FINDING-035 bootstrap-migrate. T18 mirrors the EXACT live
  # production shape found on the operator's machine: a stale hand-authored
  # NEEDS-YOU.md containing only an ad-hoc "## [DATE] <title>" heading (no
  # canonical section headers at all) with an EMPTY ledger — this is the
  # real invocation shape (via `render`, called by `add`/`resolve`, and
  # transitively by whatever calls those in production), not a synthetic
  # flagged/self-test-only shape.
  # ----------------------------------------------------------------------
  local sandbox3; sandbox3=$(mktemp -d)
  local legacy_body
  legacy_body=$'# NEEDS-YOU.md — the per-machine awaiting-operator ledger (E.6), same\n\n## [2026-07-05] Activate auto-resume daemon (E.7) — low urgency, one 2-min action\n**Context:** E.7 session-resumer is built + self-test 10/10 green.\n**What I need:** close the 6 dead session windows.\n**Reply:** "closed" (I register) · "register now" (accept noise) · "defer"'
  (
    export NEEDS_YOU_STATE_DIR="$sandbox3/state"
    export NEEDS_YOU_MD_PATH="$sandbox3/NEEDS-YOU.md"
    mkdir -p "$NEEDS_YOU_STATE_DIR"
    printf '%s\n' "$legacy_body" > "$NEEDS_YOU_MD_PATH"
    echo '{"schema_version":1,"items":[]}' > "$NEEDS_YOU_STATE_DIR/ledger.json"
    cmd_render >/dev/null 2>&1
  )
  local md3="$sandbox3/NEEDS-YOU.md"
  local headers_ok3=1
  for h in "${NY_CANONICAL_HEADERS[@]}"; do
    grep -qF "$h" "$md3" || headers_ok3=0
  done
  if [[ "$headers_ok3" == "1" ]]; then
    ok "T18 bootstrap-migrate: stale live-shape file gains all 4 canonical headers"
  else
    fail_ "T18 bootstrap-migrate: canonical headers still missing after render on stale live-shape file"
  fi
  if grep -q "Activate auto-resume daemon" "$md3"; then
    ok "T18b bootstrap-migrate: legacy heading content preserved as a migrated ledger entry"
  else
    fail_ "T18b bootstrap-migrate: legacy content lost, not migrated into the ledger"
  fi
  # The migrated item must render as a real "### <title>" decision block
  # under "Awaiting your decision" (i.e. countable by session-start-digest.sh
  # feed_needs_you, which counts "^### " lines in that section) — not just
  # present somewhere in the file.
  local awaiting_block3
  awaiting_block3=$(awk '/^## Awaiting your decision/{flag=1;next}/^## /{flag=0}flag' "$md3")
  if echo "$awaiting_block3" | grep -qE '^### '; then
    ok "T18c migrated legacy item counts as an open item under Awaiting your decision"
  else
    fail_ "T18c migrated legacy item did not render as a countable ### block under Awaiting your decision"
  fi

  # T19: idempotency — rendering again does not create a SECOND migrated
  # ledger item.
  #
  # HONEST AMENDMENT (S1/S8, needs-you readability review 2026-08-03): this
  # comment used to say the rendered markdown "legitimately shows the
  # migrated text twice within a single item's block — once as the '### '
  # title line, once as the body — since _ny_render_decision_block ALWAYS
  # renders title-then-full-body for every decision item" and cited that as
  # the reason idempotency must be checked against the ledger's item count,
  # not a grep-count over the file. That was CODIFYING A BUG, not a real
  # constraint: the review's Finding 1 (render-title-duplication) proved
  # every one of the live ledger's 15 open decision blocks opened with its
  # title printed twice as an identical wall of text — exactly this
  # "legitimate" shape. S1 fixed it (body = tail -n +2 of text; the title
  # line never repeats). The ledger-count assertion below is STILL the
  # right oracle for idempotency (it is a stronger check regardless), but
  # T19b now ALSO asserts the post-S1 invariant directly: the migrated
  # item's first text line appears in the rendered file EXACTLY ONCE.
  (
    export NEEDS_YOU_STATE_DIR="$sandbox3/state"
    export NEEDS_YOU_MD_PATH="$sandbox3/NEEDS-YOU.md"
    cmd_render >/dev/null 2>&1
  )
  local migrate_count3
  migrate_count3=$(jq '[.items[] | select(.tier == "migrated_from_legacy_file")] | length' "$sandbox3/state/ledger.json" 2>/dev/null || echo "?")
  [[ "$migrate_count3" == "1" ]] && ok "T19 bootstrap-migrate is idempotent (exactly 1 migrated ledger item after repeat render)" \
    || fail_ "T19 expected exactly 1 migrated ledger item after repeat render, got $migrate_count3"
  # Scoped to "## Awaiting your decision" (not grep-over-the-whole-file):
  # S2's Decide-now table LEGITIMATELY repeats a fresh item's title in its
  # own Ask column above the canonical sections — that is by design, not a
  # title-dup regression. The S1 invariant this scenario actually tests
  # (title-then-full-body no longer duplicates within ONE decision block)
  # only makes sense scoped to the block's own section.
  local awaiting_block19 title19_count
  awaiting_block19=$(awk '/^## Awaiting your decision/{flag=1;next}/^## /{flag=0}flag' "$md3")
  title19_count=$(echo "$awaiting_block19" | grep -cF "Activate auto-resume daemon")
  [[ "$title19_count" == "1" ]] && ok "T19b S1 regression: migrated item's title line appears exactly once under Awaiting your decision (not title-then-full-body)" \
    || fail_ "T19b expected the migrated title text exactly once under Awaiting your decision, found $title19_count occurrences"
  rm -rf "$sandbox3"

  # T20: absent file (no prior NEEDS-YOU.md at all) still renders cleanly
  # with all 4 headers via the SAME bootstrap-migrate + render path, no
  # spurious migrated entry (nothing to migrate).
  local sandbox4; sandbox4=$(mktemp -d)
  (
    export NEEDS_YOU_STATE_DIR="$sandbox4/state"
    export NEEDS_YOU_MD_PATH="$sandbox4/NEEDS-YOU.md"
    cmd_render >/dev/null 2>&1
  )
  local md4="$sandbox4/NEEDS-YOU.md"
  local headers_ok4=1
  for h in "${NY_CANONICAL_HEADERS[@]}"; do
    grep -qF "$h" "$md4" || headers_ok4=0
  done
  [[ "$headers_ok4" == "1" ]] && ok "T20 absent file: render still produces all 4 canonical headers" \
    || fail_ "T20 absent file: canonical headers missing after render"
  if grep -q "migrated_from_legacy_file\|legacy-migration" "$md4" 2>/dev/null; then
    fail_ "T20b absent file: spuriously created a migrated entry with nothing to migrate"
  else
    ok "T20b absent file: no spurious migrated entry created"
  fi
  rm -rf "$sandbox4"

  # T21: an already-well-formed NEEDS-YOU.md (all 4 headers present, real
  # content) is left alone by bootstrap-migrate — no double-migration of
  # already-canonical content.
  local sandbox5; sandbox5=$(mktemp -d)
  (
    export NEEDS_YOU_STATE_DIR="$sandbox5/state"
    export NEEDS_YOU_MD_PATH="$sandbox5/NEEDS-YOU.md"
    cmd_add --section question --text "Already-canonical fixture question" --session "sess-t21" >/dev/null
    cmd_render >/dev/null 2>&1
  )
  local md5="$sandbox5/NEEDS-YOU.md"
  # Scoped to "## Open questions" (not grep-over-the-whole-file): a single
  # fresh open question LEGITIMATELY appears twice now — once in the new
  # S2 Decide-now table's Ask column, once as its own bullet here — by
  # design, not a re-migration regression. The re-migration question this
  # scenario actually tests only makes sense scoped to the question's own
  # section (a spurious SECOND bullet there would be the real symptom).
  local questions_block5 q_count5
  questions_block5=$(awk '/^## Open questions/{flag=1;next}/^## /{flag=0}flag' "$md5")
  q_count5=$(echo "$questions_block5" | grep -c "Already-canonical fixture question" || true)
  [[ "$q_count5" == "1" ]] && ok "T21 well-formed file untouched by bootstrap-migrate (no re-migration)" \
    || fail_ "T21 expected exactly 1 occurrence under Open questions, got $q_count5 (possible spurious re-migration)"
  rm -rf "$sandbox5"

  # ----------------------------------------------------------------------
  # T22-T25: cold-reader lint (constitution §3 amendment 53d3bee, operator
  # directive 2026-07-07). Fresh sandbox so lint_warnings assertions aren't
  # muddied by earlier fixtures' ledger items.
  # ----------------------------------------------------------------------
  local sandbox6; sandbox6=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox6/state"
  export NEEDS_YOU_MD_PATH="$sandbox6/NEEDS-YOU.md"

  # T22: a GOOD decision entry (context prose + a repo-path anchor + a
  # §3-style Options table whose column 2 carries per-option outcome text +
  # a Reply line) gets an EMPTY lint_warnings array — no false-positive warn
  # on a well-formed block.
  #
  # HONEST AMENDMENT (S7, needs-you readability review 2026-08-03): this
  # fixture used to omit a "Reply:" line entirely — fine before S7, since
  # no-reply-line didn't exist yet. Per the review's target format, a truly
  # well-formed §3 block always names its reply tokens, so amending the
  # fixture to include one makes T22 a MORE rigorous "0 warnings" check
  # (all 4 codes clean), not a weaker one.
  local good_text
  good_text=$'### Ship the O.9 dashboard tonight?\nThe backlog KPI dashboard (adapters/claude-code/docs/kpis.md) has been green in staging for 3 days; shipping now vs Monday only changes who is on call if it regresses.\n| Option | What happens |\n|---|---|\n| Ship tonight | goes live now, I am on call |\n| Wait for Monday | ships Monday, no weekend on-call risk |\nMy pick: ship tonight. Reply with: ship tonight / wait for monday.'
  local id22
  id22=$(cmd_add --section decision --text "$good_text" --session "sess-t22")
  local lint22
  lint22=$(jq -r --arg id "$id22" '.items[] | select(.id == $id) | .lint_warnings | length' "$NEEDS_YOU_STATE_DIR/ledger.json" 2>/dev/null)
  if [[ "$lint22" == "0" ]]; then
    ok "T22 well-formed decision entry gets empty lint_warnings (no false-positive)"
  else
    fail_ "T22 expected 0 lint_warnings for a well-formed entry, got $lint22"
  fi

  # T23: an ANCHORLESS bare-shorthand decision (no path/URL/id-pattern
  # anywhere, and too short to carry real context either), added via a
  # MECHANICAL caller (--mechanical): STORE-AND-QUARANTINE — stderr carries
  # a lint notice, and the stored item's lint_warnings is non-empty and
  # specifically names no-anchor (plus no-context, since this fixture is
  # also just a bare title). Mechanical callers never get blocked (A1).
  local bad_text="Ship tonight? My pick: yes."
  local id23_out; id23_out=$(mktemp)
  local stderr23 id23
  stderr23=$(cmd_add --section decision --text "$bad_text" --session "sess-t23" --mechanical 2>&1 >"$id23_out")
  id23=$(cat "$id23_out" 2>/dev/null); rm -f "$id23_out"
  if printf '%s' "$stderr23" | grep -qi "cold-reader lint"; then
    ok "T23 anchorless bare-shorthand decision (mechanical) warns on stderr, never blocks"
  else
    fail_ "T23 expected a cold-reader lint stderr warning, got: $stderr23"
  fi
  local lint23
  lint23=$(jq -r --arg id "$id23" '.items[] | select(.id == $id) | .lint_warnings | join(",")' "$NEEDS_YOU_STATE_DIR/ledger.json" 2>/dev/null)
  if [[ "$lint23" == *"no-anchor"* ]]; then
    ok "T23b anchorless entry's stored lint_warnings names no-anchor"
  else
    fail_ "T23b expected lint_warnings to include no-anchor, got: $lint23"
  fi

  # T24: a MECHANICAL caller NEVER blocks on a lint warning — exit code is
  # still 0 even for the worst-case bare-shorthand fixture, and an id is
  # still returned (store-and-quarantine, A1).
  local rc24
  ( cmd_add --section decision --text "x" --session "sess-t24" --mechanical >/dev/null 2>&1 )
  rc24=$?
  [[ "$rc24" == "0" ]] && ok "T24 a MECHANICAL add never blocks on a lint warning (exit 0 even for the worst-case bare text)" \
    || fail_ "T24 add exited non-zero ($rc24) on a lint-only warning from a mechanical caller — must never block"

  # T24b/T24c (A1 — Lint promotion): the SAME worst-case bare text, added
  # via the INTERACTIVE/MODEL-INVOKED path (no --mechanical), BLOCKS — exit
  # non-zero, teaching message on stderr naming the missing checks, and
  # NOTHING written to the ledger (the item must not silently appear).
  local before_count24 after_count24
  before_count24=$(jq '.items | length' "$NEEDS_YOU_STATE_DIR/ledger.json" 2>/dev/null)
  local stderr24b rc24b
  stderr24b=$(cmd_add --section decision --text "x" --session "sess-t24b" 2>&1 >/dev/null)
  rc24b=$?
  [[ "$rc24b" != "0" ]] && ok "T24b an INTERACTIVE add BLOCKS on a lint warning (exit non-zero)" \
    || fail_ "T24b expected a non-zero exit for an interactive lint-blocked add, got 0"
  if printf '%s' "$stderr24b" | grep -qi "BLOCKED"; then
    ok "T24b2 the interactive block's stderr names it a BLOCK (teaching message, not a silent failure)"
  else
    fail_ "T24b2 expected a BLOCKED teaching message on stderr, got: $stderr24b"
  fi
  after_count24=$(jq '.items | length' "$NEEDS_YOU_STATE_DIR/ledger.json" 2>/dev/null)
  [[ "$before_count24" == "$after_count24" ]] && ok "T24c a blocked interactive add writes NOTHING to the ledger (count unchanged: $before_count24)" \
    || fail_ "T24c expected ledger item count unchanged ($before_count24), got $after_count24"

  # T24d: an interactive decision add that PASSES the lint (well-formed
  # text, no --mechanical needed) still succeeds normally — the block only
  # ever fires ON a lint failure, never as a blanket interactive tax.
  local rc24d
  ( cmd_add --section decision --text "$good_text" --session "sess-t24d" >/dev/null 2>&1 )
  rc24d=$?
  [[ "$rc24d" == "0" ]] && ok "T24d a well-formed interactive decision add is never blocked (exit 0)" \
    || fail_ "T24d expected exit 0 for a well-formed interactive add, got $rc24d"

  # T25: the lint is scoped to --section decision only — a question/inflight
  # entry with the same bare-shorthand shape gets no lint_warnings key
  # populated with content (empty array), proving the lint does not fire
  # outside its declared section.
  local id25
  id25=$(cmd_add --section question --text "x" --session "sess-t25")
  local lint25
  lint25=$(jq -r --arg id "$id25" '.items[] | select(.id == $id) | .lint_warnings | length' "$NEEDS_YOU_STATE_DIR/ledger.json" 2>/dev/null)
  [[ "$lint25" == "0" ]] && ok "T25 lint scoped to --section decision only (question entry gets empty lint_warnings)" \
    || fail_ "T25 expected 0 lint_warnings for a non-decision section, got $lint25"

  rm -rf "$sandbox6"

  # ----------------------------------------------------------------------
  # T26-T30: Task 4 splice (ask-rooted-workstreams-p1) — progress-log
  # waiting_on_operator emission + docs/operator-todo.md auto-pointer.
  # Fresh sandbox so line-count assertions aren't muddied by earlier
  # fixtures (T1/T22/T23 already exercised --section decision, which now
  # ALSO fires this splice).
  # ----------------------------------------------------------------------
  local sandbox7; sandbox7=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox7/state"
  export NEEDS_YOU_MD_PATH="$sandbox7/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox7/progress-logs"
  export OPERATOR_TODO_PATH="$sandbox7/operator-todo.md"

  echo "Scenario T26: --section decision fires BOTH the waiting_on_operator progress-log event AND the operator-todo.md auto-pointer"
  local good_text26
  good_text26=$'### Ship the T26 fixture?\nContext lives at adapters/claude-code/scripts/needs-you.sh, ref NL-FINDING-999.\n| Option | What happens |\n|---|---|\n| Yes | ships |\nMy pick: yes.'
  local id26
  id26=$(cmd_add --section decision --text "$good_text26" --session "sess-t26" --tier 2)
  local pl_file26="$PROGRESS_LOG_STATE_DIR/unlinked.jsonl"
  if [[ -f "$pl_file26" ]] && grep -qF "\"needs_you_id\":\"$id26\"" "$pl_file26" && grep -qF '"type":"waiting_on_operator"' "$pl_file26"; then
    ok "T26a decision add emitted a waiting_on_operator progress-log event (unlinked lane) carrying the needs-you id"
  else
    fail_ "T26a expected a waiting_on_operator event carrying needs_you_id=$id26 in $pl_file26"
  fi
  if grep -qF '§3-context present' "$pl_file26" 2>/dev/null; then
    ok "T26b well-formed decision text's progress-log summary carries §3-context present (no lint warnings)"
  else
    fail_ "T26b expected the progress-log summary to carry a §3-context present flag for a well-formed decision"
  fi
  if [[ -f "$OPERATOR_TODO_PATH" ]] && grep -qF "needs-you \`$id26\`" "$OPERATOR_TODO_PATH" \
     && grep -qF "AUTO: decision waiting on operator" "$OPERATOR_TODO_PATH"; then
    ok "T26c decision add appended an AUTO pointer bullet to docs/operator-todo.md naming the needs-you id"
  else
    fail_ "T26c expected an AUTO pointer bullet referencing needs-you \`$id26\` in $OPERATOR_TODO_PATH"
  fi

  echo "Scenario T26d: a lint-flagged (anchorless) decision's progress-log summary carries §3-context missing(...), not a false 'present' (mechanical caller — an interactive one would BLOCK before ever reaching this splice, see T24b)"
  local id26d
  id26d=$(cmd_add --section decision --text "Ship tonight? My pick: yes." --session "sess-t26d" --mechanical)
  if grep -qF "\"needs_you_id\":\"$id26d\"" "$pl_file26" 2>/dev/null && grep -q '§3-context missing(' "$pl_file26" 2>/dev/null; then
    ok "T26d anchorless decision's progress-log summary carries §3-context missing(...) (not falsely 'present')"
  else
    fail_ "T26d expected §3-context missing(...) for the anchorless decision fixture"
  fi

  echo "Scenario T27: --section inflight does NOT emit a progress-log event or an operator-todo.md pointer (scoping decision: inflight is FYI, not owed by the operator)"
  local pl_lines_before27 todo_lines_before27
  pl_lines_before27=$(wc -l < "$pl_file26" 2>/dev/null | tr -d ' ')
  todo_lines_before27=$(wc -l < "$OPERATOR_TODO_PATH" 2>/dev/null | tr -d ' ')
  local id27
  id27=$(cmd_add --section inflight --text "Some in-flight status update" --session "sess-t27")
  local pl_lines_after27 todo_lines_after27
  pl_lines_after27=$(wc -l < "$pl_file26" 2>/dev/null | tr -d ' ')
  todo_lines_after27=$(wc -l < "$OPERATOR_TODO_PATH" 2>/dev/null | tr -d ' ')
  if [[ "$pl_lines_before27" == "$pl_lines_after27" ]]; then
    ok "T27a inflight add did not append a new progress-log line to the unlinked lane"
  else
    fail_ "T27a expected unlinked.jsonl line count unchanged after inflight add (before=$pl_lines_before27 after=$pl_lines_after27)"
  fi
  if [[ "$todo_lines_before27" == "$todo_lines_after27" ]] && ! grep -q "$id27" "$OPERATOR_TODO_PATH"; then
    ok "T27b inflight add did not append an operator-todo.md pointer"
  else
    fail_ "T27b expected operator-todo.md unchanged after inflight add (before=$todo_lines_before27 after=$todo_lines_after27)"
  fi

  echo "Scenario T28: pre-existing operator-authored content above the AUTO markers survives untouched across multiple pointer appends"
  local sandbox8; sandbox8=$(mktemp -d)
  local todo8="$sandbox8/operator-todo.md"
  {
    printf '# Operator To-Do\n\n'
    printf '## Operator items\n\n'
    printf -- '- [ ] Buy more coffee for the office\n\n'
    printf '%s\n' "$_NY_OPERATOR_TODO_AUTO_START"
    printf '%s\n' "$_NY_OPERATOR_TODO_AUTO_END"
  } > "$todo8"
  (
    export NEEDS_YOU_STATE_DIR="$sandbox8/state"
    export NEEDS_YOU_MD_PATH="$sandbox8/NEEDS-YOU.md"
    export PROGRESS_LOG_STATE_DIR="$sandbox8/progress-logs"
    export OPERATOR_TODO_PATH="$todo8"
    cmd_add --section decision --text "First pointer fixture" --session "sess-t28a" --mechanical >/dev/null
    cmd_add --section question --text "Second pointer fixture" --session "sess-t28b" >/dev/null
  )
  if grep -qF "Buy more coffee for the office" "$todo8"; then
    ok "T28a pre-existing operator-authored line survives pointer appends"
  else
    fail_ "T28a operator-authored content was lost/altered by pointer appends"
  fi
  local auto_bullets28
  auto_bullets28=$(awk -v s="$_NY_OPERATOR_TODO_AUTO_START" -v e="$_NY_OPERATOR_TODO_AUTO_END" '$0==s{f=1;next}$0==e{f=0}f' "$todo8" | grep -c "^- \[ \] AUTO:")
  if [[ "$auto_bullets28" == "2" ]]; then
    ok "T28b both pointer bullets landed between the AUTO markers (2 distinct entries, none dropped/overwritten)"
  else
    fail_ "T28b expected 2 AUTO bullets between the markers, found $auto_bullets28"
  fi
  rm -rf "$sandbox8"

  echo "Scenario T29: an unwritable operator-todo.md path (parent exists as a FILE, not a dir) never fails 'add' (writer semantics, constraint 5)"
  local sandbox9; sandbox9=$(mktemp -d)
  : > "$sandbox9/blocked"
  local rc29
  (
    export NEEDS_YOU_STATE_DIR="$sandbox9/state"
    export NEEDS_YOU_MD_PATH="$sandbox9/NEEDS-YOU.md"
    export PROGRESS_LOG_STATE_DIR="$sandbox9/progress-logs"
    export OPERATOR_TODO_PATH="$sandbox9/blocked/operator-todo.md"
    cmd_add --section decision --text "Should still succeed despite a blocked operator-todo path" --session "sess-t29" --mechanical >/dev/null
  )
  rc29=$?
  if [[ "$rc29" == "0" ]]; then
    ok "T29 add still exits 0 when the operator-todo.md path is unwritable (never blocks)"
  else
    fail_ "T29 add exited non-zero ($rc29) when the operator-todo.md path was unwritable — must never block"
  fi
  rm -rf "$sandbox9"

  echo "Scenario T30: FROM-WORKTREE fixture (constraint 11) — operator-todo.md pointer resolves to the MAIN checkout, never the worktree cwd, via nl_main_checkout_root"
  (
    set -e
    local repo_dir="$sandbox7/t30-repo" wt_dir="$sandbox7/t30-wt"
    mkdir -p "$repo_dir"
    ( cd "$repo_dir" && git init -q . && git config core.hooksPath "" \
        && git config user.email "t@example.test" && git config user.name "T" \
        && echo x > f && git add f && git commit -q -m init ) >/dev/null 2>&1
    ( cd "$repo_dir" && git worktree add -q -b ny-selftest-wt "$wt_dir" ) >/dev/null 2>&1

    # Isolate ledger/progress-log state from the real machine WITHOUT
    # HARNESS_SELFTEST's short-circuit (that would skip the real
    # nl_main_checkout_root resolution this scenario exists to prove) and
    # WITHOUT OPERATOR_TODO_PATH set (clearing it IS the point: the real
    # resolver must run and decide where the pointer lands).
    local wt_ny_state="$sandbox7/t30-ny-state" wt_pl_state="$sandbox7/t30-pl-state"
    mkdir -p "$wt_ny_state" "$wt_pl_state"

    ( cd "$wt_dir" \
        && HARNESS_SELFTEST=0 \
           NEEDS_YOU_STATE_DIR="$wt_ny_state" \
           NEEDS_YOU_MD_PATH="$wt_dir/NEEDS-YOU.md" \
           PROGRESS_LOG_STATE_DIR="$wt_pl_state" \
           OPERATOR_TODO_PATH="" \
           bash "$_NY_SELF_DIR/needs-you.sh" add --section decision \
             --text "From-worktree fixture: the operator-todo pointer must land in the MAIN checkout" \
             --session "sess-t30" --mechanical >/dev/null 2>&1 )

    local expected_main="$repo_dir/docs/operator-todo.md"
    if [[ -f "$expected_main" ]] && grep -q "sess-t30" "$expected_main"; then
      echo "  PASS: T30a operator-todo.md pointer landed under the MAIN checkout ($expected_main)"
    else
      echo "  FAIL: T30a expected $expected_main to exist and reference sess-t30" >&2
      exit 1
    fi
    local leaked_in_worktree="$wt_dir/docs/operator-todo.md"
    if [[ ! -f "$leaked_in_worktree" ]]; then
      echo "  PASS: T30b operator-todo.md did NOT land under the worktree cwd ($leaked_in_worktree absent)"
    else
      echo "  FAIL: T30b operator-todo.md incorrectly landed under the worktree ($leaked_in_worktree exists)" >&2
      exit 1
    fi
    ( cd "$repo_dir" && git worktree remove --force "$wt_dir" >/dev/null 2>&1 || true )
    ( cd "$repo_dir" && git branch -D ny-selftest-wt >/dev/null 2>&1 || true )
  )
  if [[ "$?" == "0" ]]; then
    ok "T30: from-worktree operator-todo.md pointer fixture (see T30a/T30b lines above)"
  else
    fail_ "T30: from-worktree operator-todo.md pointer fixture failed (see T30a/T30b lines above)"
  fi

  rm -rf "$sandbox7" "$_ny_t4_sandbox"

  echo "Scenario T31: ASK LINT (constitution §2, 2026-07-28) — fires on bare labels, and MUST NOT fire on the sanctioned empty values"
  # The negative half is the load-bearing half. `Blocking: nothing` / `none` are
  # the §2-SANCTIONED empty values and are themselves single bare tokens; a
  # bare-label check that fired on them would warn on every clean session and be
  # tuned out within a week. harness-reviewer named this the mandatory negative
  # case when it recommended the lint (2026-07-28).
  local _ny_t31_fail=0 _ny_t31_out
  local _ny_t31_neg _ny_t31_pos
  for _ny_t31_neg in "nothing" "none" "None" "n/a"; do
    _ny_t31_out="$(_ny_lint_ask_text "$_ny_t31_neg")"
    if [[ -n "$_ny_t31_out" ]]; then
      echo "  T31 FAIL: sanctioned empty value '$_ny_t31_neg' fired the lint ($_ny_t31_out) — this is the cry-wolf failure"
      _ny_t31_fail=1
    fi
  done
  for _ny_t31_pos in "/grant-local-edit" '`/grant-local-edit`' "--no-verify"; do
    _ny_t31_out="$(_ny_lint_ask_text "$_ny_t31_pos")"
    case "$_ny_t31_out" in
      *bare-label*) : ;;
      *) echo "  T31 FAIL: bare label '$_ny_t31_pos' did NOT fire bare-label (got '$_ny_t31_out')"; _ny_t31_fail=1 ;;
    esac
  done
  # a real, complete ask must stay silent
  _ny_t31_out="$(_ny_lint_ask_text "Approve me editing your settings file to add an env block that puts Homebrew bash 5 ahead of Apple's bash 3.2 on PATH; reply yes and I will make the edit and show you the diff.")"
  if [[ -n "$_ny_t31_out" ]]; then
    echo "  T31 FAIL: a complete, well-formed ask fired the lint ($_ny_t31_out)"
    _ny_t31_fail=1
  fi
  if [[ "$_ny_t31_fail" -eq 0 ]]; then
    ok "T31: ask lint fires on bare labels, stays silent on 'nothing'/'none'/'n-a' and on complete asks"
  else
    fail_ "T31: ask-lint behavior wrong (see T31 FAIL lines above)"
  fi

  # ----------------------------------------------------------------------
  # T36-T38: nl-issues 2026-07-29 "needs-you.sh render corrupts paths" — one
  # scenario per defect class fixed in this task. Fresh sandbox: T30
  # rm -rf'd sandbox7, so a new one is needed for any cmd_add/cmd_render call.
  # ----------------------------------------------------------------------
  local sandbox10; sandbox10=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox10/state"
  export NEEDS_YOU_MD_PATH="$sandbox10/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox10/progress-logs"
  export OPERATOR_TODO_PATH="$sandbox10/operator-todo.md"

  echo "Scenario T36: escape-safe rendering — a backslash-n Windows path renders intact byte-for-byte (the reported operator incident: 'Example Co\\neural-lace' rendered split across two lines with the 'n' silently eaten)"
  local t32_text='Reference path: C:\Users\operator\dev\Example Co\neural-lace\docs\backlog.md (path check fixture)'
  cmd_add --section inflight --text "$t32_text" --session "sess-t32" >/dev/null
  cmd_render >/dev/null
  if grep -qF 'Example Co\neural-lace\docs\backlog.md' "$NEEDS_YOU_MD_PATH"; then
    ok "T36 backslash-n path rendered intact, byte-for-byte (no mid-word split, no eaten 'n')"
  else
    fail_ "T36 backslash-n path was corrupted in the rendered file (expected literal 'Example Co\\neural-lace\\docs\\backlog.md' on one line)"
  fi
  if grep -qE '^Reference path: C:\\Users\\operator\\dev\\Example Co\\$' "$NEEDS_YOU_MD_PATH"; then
    fail_ "T36b the corrupted split form (path cut off after 'Technician\\') is present — regression"
  else
    ok "T36b no corrupted split-line form present"
  fi

  echo "Scenario T37: dedup collapse — 3 identical-text inflight rows (different sessions, same gap) collapse to ONE rendered bullet naming the repeat count"
  local t33_text="Unresolved Stop-gate gap (dedup fixture): identical gap reported by 3 different sessions"
  cmd_add --section inflight --text "$t33_text" --session "sess-t33-a" >/dev/null
  cmd_add --section inflight --text "$t33_text" --session "sess-t33-b" >/dev/null
  cmd_add --section inflight --text "$t33_text" --session "sess-t33-c" >/dev/null
  cmd_render >/dev/null
  local t33_line_count
  t33_line_count=$(grep -cF "$t33_text" "$NEEDS_YOU_MD_PATH")
  if [[ "$t33_line_count" == "1" ]]; then
    ok "T37 3 identical-text inflight rows collapsed to exactly 1 rendered bullet"
  else
    fail_ "T37 expected exactly 1 rendered bullet for identical-text rows, found $t33_line_count"
  fi
  if grep -qE -- '- Unresolved Stop-gate gap \(dedup fixture\).*x3 since' "$NEEDS_YOU_MD_PATH"; then
    ok "T37b collapsed bullet names the repeat count (x3 since <first-seen-date>)"
  else
    fail_ "T37b expected an 'x3 since <date>' annotation on the collapsed bullet"
  fi

  echo "Scenario T38: dead-path annotation — an entry referencing a local path that does not exist gets a '[path no longer exists]' note, WITHOUT the original entry text being altered or dropped"
  local t34_dead_path="$sandbox10/definitely-not-a-real-file-xyz123.sh"
  local t34_text="Run the drill: bash \"$t34_dead_path\" from the main checkout (dead-path fixture)."
  cmd_add --section inflight --text "$t34_text" --session "sess-t34" >/dev/null
  cmd_render >/dev/null
  if grep -qF "$t34_text" "$NEEDS_YOU_MD_PATH"; then
    ok "T38 original entry text preserved verbatim (never deleted/altered by the liveness check)"
  else
    fail_ "T38 original entry text missing/altered in the rendered file"
  fi
  # Co-located check (not just "somewhere in the file"): the annotation must
  # appear on the line immediately after THIS entry's own bullet, naming
  # THIS entry's dead path -- a prior version of this assertion checked the
  # two greps independently and could pass by coincidence (e.g. a DIFFERENT
  # entry's annotation satisfying the "[path no longer exists]" half).
  local t34_block
  t34_block=$(grep -A1 -F "$t34_text" "$NEEDS_YOU_MD_PATH" || true)
  if printf '%s' "$t34_block" | grep -qF "path no longer exists" \
     && printf '%s' "$t34_block" | grep -qF "$t34_dead_path"; then
    ok "T38b dead-path annotation present immediately after the entry, naming the specific missing path"
  else
    fail_ "T38b expected a '[path no longer exists]' annotation naming $t34_dead_path right after the entry; got: $t34_block"
  fi
  # Negative case: a link/path that DOES exist gets no dead-path annotation.
  local t34b_text="See adapters/claude-code/scripts/needs-you.sh for the implementation (live-path fixture)."
  cmd_add --section inflight --text "$t34b_text" --session "sess-t34b" --link "adapters/claude-code/scripts/needs-you.sh" >/dev/null
  cmd_render >/dev/null
  local t34c_block
  t34c_block=$(grep -A1 -F "$t34b_text" "$NEEDS_YOU_MD_PATH" || true)
  if printf '%s' "$t34c_block" | grep -qF "path no longer exists"; then
    fail_ "T38c a live (existing) path was incorrectly flagged as dead — false positive"
  else
    ok "T38c a live path gets no dead-path annotation (no false positive)"
  fi

  rm -rf "$sandbox10"
  # T32-T35: 2026-07-27 LEDGER-CORRUPTION INCIDENT — golden-scenario recovery
  # + regression coverage. The golden fixture is the EXACT observed
  # corruption: a 1-byte ledger.json containing a single newline (this is
  # what `~/.claude/state/needs-you/ledger.json` looked like for ~2 days:
  # `[[ -f "$f" ]] ||` sees it as present, so the old guard never fired
  # again and every jq read failed forever).
  # ----------------------------------------------------------------------
  echo "Scenario T32-T35: ledger-corruption incident (2026-07-27) — recovery + regressions"

  # T32: golden fixture — a 1-byte "\n" ledger.json recovers on next render.
  local sandbox5; sandbox5=$(mktemp -d)
  (
    export NEEDS_YOU_STATE_DIR="$sandbox5/state"
    export NEEDS_YOU_MD_PATH="$sandbox5/NEEDS-YOU.md"
    mkdir -p "$NEEDS_YOU_STATE_DIR"
    printf '\n' > "$NEEDS_YOU_STATE_DIR/ledger.json"   # the EXACT incident byte sequence
    cmd_render >/dev/null 2>"$sandbox5/render-stderr.log"
  )
  local t32_ledger="$sandbox5/state/ledger.json"
  if jq -e 'type' "$t32_ledger" >/dev/null 2>&1; then
    ok "T32a corrupt (1-byte newline) ledger.json is valid JSON after the next render"
  else
    fail_ "T32a ledger.json is STILL invalid after render — corruption recovery did not fire"
  fi
  # T32b: NEEDS-YOU.md itself still comes out well-formed (downstream reader
  # recovers too, not just the ledger file in isolation).
  local t32_headers_ok=1
  for h in "${NY_CANONICAL_HEADERS[@]}"; do
    grep -qF "$h" "$sandbox5/NEEDS-YOU.md" 2>/dev/null || t32_headers_ok=0
  done
  [[ "$t32_headers_ok" == "1" ]] && ok "T32b NEEDS-YOU.md still renders all 4 canonical headers after recovering from a corrupt ledger" \
    || fail_ "T32b NEEDS-YOU.md missing headers after ledger-corruption recovery"

  # T32c: NEVER DESTROY EVIDENCE (constitution §9) — the ORIGINAL corrupt
  # bytes must be preserved verbatim in a .corrupt-<date>.bak sibling, not
  # just discarded. Asserted on the ACTUAL byte content of the backup file,
  # not on a filename pattern alone.
  local t32_bak; t32_bak=$(find "$sandbox5/state" -maxdepth 1 -name 'ledger.json.corrupt-*.bak' 2>/dev/null | head -1)
  if [[ -n "$t32_bak" && -f "$t32_bak" ]]; then
    local t32_bak_bytes; t32_bak_bytes=$(wc -c < "$t32_bak" 2>/dev/null | tr -d ' ')
    local t32_bak_content; t32_bak_content=$(cat "$t32_bak")
    if [[ "$t32_bak_bytes" == "1" && -z "$t32_bak_content" ]]; then
      ok "T32c original corrupt bytes preserved verbatim at $(basename "$t32_bak") (1 byte, matches the incident's exact newline-only content)"
    else
      fail_ "T32c backup file exists but content doesn't match the original corrupt bytes (got $t32_bak_bytes bytes)"
    fi
  else
    fail_ "T32c no ledger.json.corrupt-*.bak backup was created — corrupt bytes were DISCARDED, not salvaged"
  fi

  # T32d: loud logging — the recovery must have said something to stderr,
  # not silently swapped the file.
  if grep -qi "RECOVERED corrupt state file" "$sandbox5/render-stderr.log" 2>/dev/null; then
    ok "T32d recovery logged loudly to stderr (not a silent re-init)"
  else
    fail_ "T32d no stderr notice found for the corruption recovery"
  fi

  # T32e: the recovered ledger is not just "parses as JSON" but genuinely
  # USABLE — a subsequent add must succeed and be readable back out.
  local t32e_id
  t32e_id=$(
    export NEEDS_YOU_STATE_DIR="$sandbox5/state"
    export NEEDS_YOU_MD_PATH="$sandbox5/NEEDS-YOU.md"
    cmd_add --section question --text "T32e: post-recovery add must actually work, not just look valid" --session "sess-t32e"
  )
  local t32e_count
  t32e_count=$(jq --arg id "$t32e_id" '[.items[] | select(.id == $id)] | length' "$t32_ledger" 2>/dev/null)
  [[ "$t32e_count" == "1" ]] && ok "T32e ledger is genuinely usable post-recovery (a real add landed and reads back)" \
    || fail_ "T32e post-recovery add did not land (id=$t32e_id, count=$t32e_count)"
  rm -rf "$sandbox5"

  # T33: a VALID pre-existing ledger is left completely untouched (no
  # spurious backup, no rewrite) — the recovery path must be exclusive to
  # actually-invalid content, never firing on the healthy common case.
  local sandbox6; sandbox6=$(mktemp -d)
  (
    export NEEDS_YOU_STATE_DIR="$sandbox6/state"
    export NEEDS_YOU_MD_PATH="$sandbox6/NEEDS-YOU.md"
    mkdir -p "$NEEDS_YOU_STATE_DIR"
    printf '{"schema_version":1,"items":[]}\n' > "$NEEDS_YOU_STATE_DIR/ledger.json"
  )
  local t33_before_mtime; t33_before_mtime=$(stat -f '%m' "$sandbox6/state/ledger.json" 2>/dev/null || stat -c '%Y' "$sandbox6/state/ledger.json" 2>/dev/null)
  (
    export NEEDS_YOU_STATE_DIR="$sandbox6/state"
    export NEEDS_YOU_MD_PATH="$sandbox6/NEEDS-YOU.md"
    cmd_render >/dev/null 2>&1
  )
  local t33_bak_count; t33_bak_count=$(find "$sandbox6/state" -maxdepth 1 -name 'ledger.json.corrupt-*.bak' 2>/dev/null | wc -l | tr -d ' ')
  [[ "$t33_bak_count" == "0" ]] && ok "T33 a healthy pre-existing ledger.json is never touched by the recovery path (no spurious backup)" \
    || fail_ "T33 recovery fired on a VALID ledger — created $t33_bak_count spurious backup(s)"
  rm -rf "$sandbox6"

  # T34: BASH-3.2 REGRESSION (the actual truncating-writer mechanism this
  # incident traced to). `add` with ZERO --link flags, run under the REAL
  # /bin/bash on this machine (macOS's shipped 3.2.57 — this repo's
  # portability floor), used to crash the jq command-substitution on
  # "${links[@]}" (bash <4.4 treats expanding a zero-element array under
  # `set -u` as an unbound-variable reference) and silently write a 1-byte
  # "\n" over the ledger. Explicitly invokes /bin/bash regardless of which
  # interpreter is running THIS self-test, since re-invoking via a bare
  # `bash` would resolve to whatever is first on PATH and could silently
  # skip the interpreter this regression is about.
  if [[ -x /bin/bash ]]; then
    local sandbox7; sandbox7=$(mktemp -d)
    (
      export NEEDS_YOU_STATE_DIR="$sandbox7/state"
      export NEEDS_YOU_MD_PATH="$sandbox7/NEEDS-YOU.md"
      /bin/bash "$_NY_SELF_PATH" add --section question \
        --text "T34 regression: a zero-link add under /bin/bash 3.2 must not corrupt the ledger" \
        --session "sess-t34-bash32" \
        >"$sandbox7/t34-id.log" 2>"$sandbox7/t34-stderr.log"
    )
    local t34_ledger="$sandbox7/state/ledger.json"
    if jq -e 'type' "$t34_ledger" >/dev/null 2>&1 \
       && jq -e '.items | length == 1' "$t34_ledger" >/dev/null 2>&1; then
      ok "T34 /bin/bash 3.2: 'add' with zero --link flags leaves ledger.json valid JSON with the new item (see 2026-07-27 incident)"
    else
      fail_ "T34 /bin/bash 3.2: 'add' with zero --link flags corrupted or lost the ledger — this is the exact incident mechanism (stderr: $(cat "$sandbox7/t34-stderr.log" 2>/dev/null | tr '\n' ' '))"
    fi
    rm -rf "$sandbox7"
  else
    echo "  T34 SKIP: /bin/bash not present on this system"
  fi

  # T35: WRITE-SAFETY backstop — _ny_write_ledger must refuse to ever commit
  # empty/invalid content, independent of WHY the caller ended up with bad
  # content (defense in depth beyond the T34 root-cause fix: this catches
  # ANY future producer bug the same way).
  local sandbox8; sandbox8=$(mktemp -d)
  (
    export NEEDS_YOU_STATE_DIR="$sandbox8/state"
    export NEEDS_YOU_MD_PATH="$sandbox8/NEEDS-YOU.md"
    mkdir -p "$NEEDS_YOU_STATE_DIR"
    printf '{"schema_version":1,"items":[{"id":"NY-keepme"}]}\n' > "$NEEDS_YOU_STATE_DIR/ledger.json"
    if _ny_write_ledger "" 2>"$sandbox8/t35-stderr.log"; then
      echo "unexpected-success" > "$sandbox8/t35-rc"
    else
      echo "rejected" > "$sandbox8/t35-rc"
    fi
  )
  local t35_rc; t35_rc=$(cat "$sandbox8/t35-rc" 2>/dev/null)
  local t35_kept; t35_kept=$(grep -c "NY-keepme" "$sandbox8/state/ledger.json" 2>/dev/null || true)
  t35_kept="${t35_kept:-0}"
  if [[ "$t35_rc" == "rejected" && "$t35_kept" -ge "1" ]]; then
    ok "T35 _ny_write_ledger refuses empty content and leaves the real ledger untouched"
  else
    fail_ "T35 _ny_write_ledger accepted empty content or clobbered the existing ledger (rc=$t35_rc, kept=$t35_kept)"
  fi
  rm -rf "$sandbox8"

  # ----------------------------------------------------------------------
  # T45-T54: needs-you readability review 2026-08-03 (S1-S8) regression
  # coverage. Each fixture uses its own fresh sandbox so counts/assertions
  # aren't muddied by earlier scenarios' ledger items.
  # ----------------------------------------------------------------------

  echo "Scenario T45: S2 Decide-now table caps at 10 rows even with 12 eligible fresh decisions"
  local sandbox11; sandbox11=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox11/state"
  export NEEDS_YOU_MD_PATH="$sandbox11/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox11/pl"
  export OPERATOR_TODO_PATH="$sandbox11/todo.md"
  local _ny_i45
  for _ny_i45 in 1 2 3 4 5 6 7 8 9 10 11 12; do
    cmd_add --section decision --mechanical \
      --text "Fixture decision number $_ny_i45 for the decide-now cap test, anchor NL-FINDING-0$_ny_i45." \
      --session "sess-t45-$_ny_i45" >/dev/null
  done
  local dn_rows45
  dn_rows45=$(grep -cE '^\| [0-9]+ \| `' "$NEEDS_YOU_MD_PATH")
  [[ "$dn_rows45" == "10" ]] && ok "T45 Decide-now table caps at 10 rows (12 eligible fresh decisions added)" \
    || fail_ "T45 expected exactly 10 Decide-now rows, got $dn_rows45"
  if grep -qF 'showing the 10 most urgent of 12 eligible' "$NEEDS_YOU_MD_PATH"; then
    ok "T45b cap note names the true eligible total (12)"
  else
    fail_ "T45b expected a 'showing the 10 most urgent of 12 eligible' note"
  fi
  rm -rf "$sandbox11"

  echo "Scenario T46: S4 stale-demotion boundary — 15 days old demotes to Probably dead, 13 days old stays in Awaiting your decision (NY_STALE_OPEN_DAYS=$NY_STALE_OPEN_DAYS)"
  local sandbox12; sandbox12=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox12/state"
  export NEEDS_YOU_MD_PATH="$sandbox12/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox12/pl"
  export OPERATOR_TODO_PATH="$sandbox12/todo.md"
  local id46a id46b
  id46a=$(cmd_add --section decision --mechanical --text "Fifteen day old fixture decision for the stale-demotion boundary test." --session "sess-t46a")
  id46b=$(cmd_add --section decision --mechanical --text "Thirteen day old fixture decision for the stale-demotion boundary test." --session "sess-t46b")
  local ts15 ts13
  ts15=$(date -u -d "15 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -j -v-15d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
  ts13=$(date -u -d "13 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -j -v-13d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
  local ledger46="$NEEDS_YOU_STATE_DIR/ledger.json"
  local cur46 new46
  cur46=$(cat "$ledger46")
  new46=$(echo "$cur46" | jq --arg a "$id46a" --arg ta "$ts15" --arg b "$id46b" --arg tb "$ts13" \
    '.items |= map(if .id == $a then . + {created_at:$ta} elif .id == $b then . + {created_at:$tb} else . end)')
  printf '%s\n' "$new46" > "$ledger46"
  cmd_render >/dev/null
  local dead_block46 awaiting_block46
  dead_block46=$(awk '/^## Probably dead/{flag=1;next}/^## /{flag=0}flag' "$NEEDS_YOU_MD_PATH")
  awaiting_block46=$(awk '/^## Awaiting your decision/{flag=1;next}/^## /{flag=0}flag' "$NEEDS_YOU_MD_PATH")
  if echo "$dead_block46" | grep -q "Fifteen day old fixture"; then
    ok "T46a 15-day-old open decision demotes to Probably dead"
  else
    fail_ "T46a expected the 15-day-old fixture under Probably dead"
  fi
  if echo "$awaiting_block46" | grep -q "Thirteen day old fixture"; then
    ok "T46b 13-day-old open decision STAYS in Awaiting your decision (not yet stale)"
  else
    fail_ "T46b expected the 13-day-old fixture to remain under Awaiting your decision"
  fi
  if echo "$awaiting_block46" | grep -q "Fifteen day old fixture"; then
    fail_ "T46c 15-day-old fixture incorrectly still under Awaiting your decision"
  else
    ok "T46c 15-day-old fixture correctly absent from Awaiting your decision"
  fi
  rm -rf "$sandbox12"

  echo "Scenario T47: S5 dedup normalization collapses volatile-token variants of the same recurring alert into ONE bullet"
  local sandbox13; sandbox13=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox13/state"
  export NEEDS_YOU_MD_PATH="$sandbox13/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox13/pl"
  export OPERATOR_TODO_PATH="$sandbox13/todo.md"
  cmd_add --section inflight --text "Orphaned worktree alert: last commit 3d ago, alert #12, 2 live/throttled session(s)" --session "sess-t47-a" >/dev/null
  cmd_add --section inflight --text "Orphaned worktree alert: last commit 5d ago, alert #45, 4 live/throttled session(s)" --session "sess-t47-b" >/dev/null
  cmd_add --section inflight --text "Orphaned worktree alert: last commit 9d ago, alert #99, 1 live/throttled session(s)" --session "sess-t47-c" >/dev/null
  local inflight_block47
  inflight_block47=$(awk '/^## In flight/{flag=1;next}/^## /{flag=0}flag' "$NEEDS_YOU_MD_PATH")
  local bullets47
  bullets47=$(echo "$inflight_block47" | grep -cE '^- Orphaned worktree alert')
  [[ "$bullets47" == "1" ]] && ok "T47 3 volatile-token variants of the same alert collapse to 1 bullet" \
    || fail_ "T47 expected exactly 1 collapsed bullet, got $bullets47"
  if echo "$inflight_block47" | grep -qE 'x3 since'; then
    ok "T47b collapsed bullet names the repeat count"
  else
    fail_ "T47b expected an 'x3 since' annotation"
  fi
  rm -rf "$sandbox13"

  echo "Scenario T48: S6 --supersedes auto-resolves the named older entry"
  local sandbox14; sandbox14=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox14/state"
  export NEEDS_YOU_MD_PATH="$sandbox14/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox14/pl"
  export OPERATOR_TODO_PATH="$sandbox14/todo.md"
  local id48a id48b
  id48a=$(cmd_add --section decision --mechanical --text "Original ask that will be superseded by a follow-up decision." --session "sess-t48a")
  id48b=$(cmd_add --section decision --mechanical --text "Follow-up decision superseding the original ask." --session "sess-t48b" --supersedes "$id48a")
  local state48
  state48=$(jq -r --arg id "$id48a" '.items[] | select(.id == $id) | .state' "$NEEDS_YOU_STATE_DIR/ledger.json")
  [[ "$state48" == "resolved" ]] && ok "T48a --supersedes auto-resolves the named older entry" \
    || fail_ "T48a expected '$id48a' to be resolved, state is '$state48'"
  local note48
  note48=$(jq -r --arg id "$id48a" '.items[] | select(.id == $id) | .resolution_note' "$NEEDS_YOU_STATE_DIR/ledger.json")
  if [[ "$note48" == *"superseded by $id48b"* ]]; then
    ok "T48b resolution note names the superseding id"
  else
    fail_ "T48b expected resolution note to mention 'superseded by $id48b', got '$note48'"
  fi
  local awaiting_block48
  awaiting_block48=$(awk '/^## Awaiting your decision/{flag=1;next}/^## /{flag=0}flag' "$NEEDS_YOU_MD_PATH")
  if echo "$awaiting_block48" | grep -q "Original ask that will be superseded"; then
    fail_ "T48c superseded entry still rendered under Awaiting your decision"
  else
    ok "T48c superseded entry no longer rendered under Awaiting your decision"
  fi
  local rc48d
  ( cmd_add --section decision --mechanical --text "Add with a bogus supersedes target should still succeed." --session "sess-t48d" --supersedes "NY-does-not-exist" >/dev/null 2>&1 )
  rc48d=$?
  [[ "$rc48d" == "0" ]] && ok "T48d --supersedes with a missing target still succeeds (warn, never fails add)" \
    || fail_ "T48d expected exit 0 even with a missing --supersedes target, got $rc48d"
  rm -rf "$sandbox14"

  echo "Scenario T49: S3 --blocking hoists an OLDER item to the top of Awaiting your decision, ahead of a newer non-blocking item"
  local sandbox15; sandbox15=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox15/state"
  export NEEDS_YOU_MD_PATH="$sandbox15/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox15/pl"
  export OPERATOR_TODO_PATH="$sandbox15/todo.md"
  cmd_add --section decision --mechanical --text "Oldest fixture but marked blocking, added first." --session "sess-t49a" --blocking >/dev/null
  cmd_add --section decision --mechanical --text "Newest fixture added second, not blocking." --session "sess-t49b" >/dev/null
  local awaiting_block49 first_title49
  awaiting_block49=$(awk '/^## Awaiting your decision/{flag=1;next}/^## /{flag=0}flag' "$NEEDS_YOU_MD_PATH")
  first_title49=$(echo "$awaiting_block49" | grep -m1 '^### ')
  if [[ "$first_title49" == *"Oldest fixture but marked blocking"* ]]; then
    ok "T49 a --blocking item hoists to the top of Awaiting your decision despite being older"
  else
    fail_ "T49 expected the blocking fixture first, got: $first_title49"
  fi
  rm -rf "$sandbox15"

  echo "Scenario T50: S1 regression — a genuinely single-line decision text renders with NO duplicated/empty body line"
  local sandbox16; sandbox16=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox16/state"
  export NEEDS_YOU_MD_PATH="$sandbox16/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox16/pl"
  export OPERATOR_TODO_PATH="$sandbox16/todo.md"
  cmd_add --section decision --mechanical --text "A genuinely single line decision text with no newline anywhere in it at all." --session "sess-t50" >/dev/null
  local awaiting_block50 occurrences50
  awaiting_block50=$(awk '/^## Awaiting your decision/{flag=1;next}/^## /{flag=0}flag' "$NEEDS_YOU_MD_PATH")
  occurrences50=$(echo "$awaiting_block50" | grep -cF "A genuinely single line decision text")
  [[ "$occurrences50" == "1" ]] && ok "T50 a single-line decision text renders exactly once under Awaiting your decision (title only)" \
    || fail_ "T50 expected exactly 1 occurrence under Awaiting your decision, got $occurrences50"
  rm -rf "$sandbox16"

  echo "Scenario T51: Finding 8 empty-field noise suppressed — no 'Links: (none)' and no spelled-out 'session \`unknown\`'"
  local sandbox17; sandbox17=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox17/state"
  export NEEDS_YOU_MD_PATH="$sandbox17/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox17/pl"
  export OPERATOR_TODO_PATH="$sandbox17/todo.md"
  cmd_add --section decision --mechanical --text $'### No session, no links fixture\nThis fixture has real context prose but was added without --session or --link.' >/dev/null
  local awaiting_block51
  awaiting_block51=$(awk '/^## Awaiting your decision/{flag=1;next}/^## /{flag=0}flag' "$NEEDS_YOU_MD_PATH")
  if echo "$awaiting_block51" | grep -q "^Links:"; then
    fail_ "T51a expected no 'Links:' line for an entry with zero links"
  else
    ok "T51a 'Links: (none)' noise suppressed for a linkless entry"
  fi
  if echo "$awaiting_block51" | grep -q 'session `unknown`'; then
    fail_ "T51b expected no spelled-out 'session \`unknown\`'"
  else
    ok "T51b 'session \`unknown\`' noise suppressed"
  fi
  if echo "$awaiting_block51" | grep -qE '^\*\(added [0-9-]+, id `NY-'; then
    ok "T51c meta line still carries added-date + id when session is absent"
  else
    fail_ "T51c expected a '*(added <date>, id \`NY-...\`)*' meta line"
  fi
  rm -rf "$sandbox17"

  echo "Scenario T52: S7 no-reply-line is WARN-ONLY — never blocks the interactive path, still recorded in lint_warnings"
  local sandbox18; sandbox18=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox18/state"
  export NEEDS_YOU_MD_PATH="$sandbox18/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox18/pl"
  export OPERATOR_TODO_PATH="$sandbox18/todo.md"
  local text52 rc52 id52
  # NOTE: deliberately avoids the word "reply" anywhere in this fixture's
  # own prose (even to say it's absent) — the heuristic is a literal
  # substring/word match, so a sentence like "no reply line anywhere" would
  # itself satisfy the check it's meant to fail (caught by this fixture's
  # own dry run: T52b first failed for exactly this reason).
  text52=$'### Ship the T52 fixture tonight?\nThis has real context prose and an anchor at adapters/claude-code/scripts/needs-you.sh, with no closing instruction on how to answer.\n| Option | What happens |\n|---|---|\n| Yes | ships |\nMy pick: yes.'
  id52=$( cmd_add --section decision --text "$text52" --session "sess-t52" )
  rc52=$?
  [[ "$rc52" == "0" ]] && ok "T52a interactive add of a context/anchor/outcome-complete-but-reply-less decision succeeds (never blocks on no-reply-line alone)" \
    || fail_ "T52a expected exit 0, got $rc52"
  local lint52
  lint52=$(jq -r --arg id "$id52" '.items[] | select(.id == $id) | .lint_warnings | join(",")' "$NEEDS_YOU_STATE_DIR/ledger.json" 2>/dev/null)
  [[ "$lint52" == "no-reply-line" ]] && ok "T52b lint_warnings still records no-reply-line (observability, not a block)" \
    || fail_ "T52b expected lint_warnings == 'no-reply-line', got '$lint52'"
  local id52c lint52c
  id52c=$(cmd_add --section decision --text "$text52" --session "sess-t52c" --reply-with "yes")
  lint52c=$(jq -r --arg id "$id52c" '.items[] | select(.id == $id) | .lint_warnings | length' "$NEEDS_YOU_STATE_DIR/ledger.json" 2>/dev/null)
  [[ "$lint52c" == "0" ]] && ok "T52c --reply-with suppresses no-reply-line entirely" \
    || fail_ "T52c expected 0 lint_warnings with --reply-with supplied, got $lint52c"
  rm -rf "$sandbox18"

  echo "Scenario T53: hard contract — _ny_md_has_all_headers still passes on the new Decide-now/Probably-dead layout"
  local sandbox19; sandbox19=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox19/state"
  export NEEDS_YOU_MD_PATH="$sandbox19/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox19/pl"
  export OPERATOR_TODO_PATH="$sandbox19/todo.md"
  cmd_add --section decision --mechanical --text "Fixture to force a non-empty render for the header-invariant check." --session "sess-t53" >/dev/null
  if _ny_md_has_all_headers "$NEEDS_YOU_MD_PATH"; then
    ok "T53 _ny_md_has_all_headers still passes on the new layout (canonical 4 headers untouched)"
  else
    fail_ "T53 _ny_md_has_all_headers FAILED on the new layout — the canonical 4 headers must never go missing"
  fi
  rm -rf "$sandbox19"

  echo "Scenario T54: durable enforcement — no rendered line is an exact duplicate of its immediate predecessor (catches the render-title-duplication class generically)"
  local sandbox20; sandbox20=$(mktemp -d)
  export NEEDS_YOU_STATE_DIR="$sandbox20/state"
  export NEEDS_YOU_MD_PATH="$sandbox20/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$sandbox20/pl"
  export OPERATOR_TODO_PATH="$sandbox20/todo.md"
  cmd_add --section decision --mechanical --text $'### T54 duplicate-line regression fixture\nSome real context prose that is not the same as the title line above it.' --session "sess-t54" >/dev/null
  cmd_add --section question --text "T54 open question fixture for the duplicate-line invariant." --session "sess-t54b" >/dev/null
  if awk 'NF { if ($0 == prev) { exit 1 } prev = $0 } END { exit 0 }' "$NEEDS_YOU_MD_PATH"; then
    ok "T54 no rendered line is an exact duplicate of its immediate predecessor"
  else
    fail_ "T54 found a rendered line identical to its immediate predecessor — possible render-title-duplication regression"
  fi
  rm -rf "$sandbox20"

  echo ""
  echo "RESULT: $pass passed, $fail failed"
  if [[ "$fail" -gt 0 ]]; then
    echo "Failures:"
    printf '  - %s\n' "${errors[@]}"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# main dispatch
# ----------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
  cat <<EOF
Usage: needs-you.sh <verb> [args]

Verbs:
  add                    --section decision|question|inflight|decided --text STR
                         [--session ID] [--link URL]* [--tier 1|2|3]
                         [--mechanical] [--reply-with STR] [--blocking]
                         [--supersedes ID]
                         -> prints new entry id, exit 0. For --section
                         decision, a cold-reader-lint failure BLOCKS
                         (exit 1, nothing written) unless --mechanical is
                         passed, in which case it stores + quarantines
                         instead (see header 'LINT PROMOTION'). --reply-with
                         feeds the "## Decide now" table's Reply-with column
                         directly; --blocking hoists the item to the top of
                         its ordering; --supersedes <id> auto-resolves <id>
                         once this add succeeds (missing target -> warn,
                         never fails the add).
  resolve <id>           [--note STR] -> moves entry to "Recently decided"
  expire                 collapse >7-day-old decided items into a count
  bootstrap-migrate      migrate a stale/hand-authored NEEDS-YOU.md into the
                         ledger (NL-FINDING-035); idempotent; also runs
                         automatically at the start of every `render`
  render                 bootstrap-migrate, expire, then rewrite NEEDS-YOU.md
                         in full
  has-entry-for-session <session-id>
                         exit 0 if an OPEN entry exists for that session, else 1
  --self-test            run self-test suite (sandboxed; never touches real state)

See adapters/claude-code/scripts/needs-you.sh header comment for the full
contract and section semantics.
EOF
  exit 0
fi

case "$1" in
  add) shift; cmd_add "$@" ;;
  resolve) shift; cmd_resolve "$@" ;;
  expire) shift; cmd_expire "$@" ;;
  bootstrap-migrate) shift; cmd_bootstrap_migrate "$@" ;;
  render) shift; cmd_render "$@" ;;
  has-entry-for-session) shift; cmd_has_entry_for_session "$@" ;;
  --self-test|--selftest|selftest|self-test) cmd_selftest ;;
  *) die "unknown verb '$1' (run without args for usage)" ;;
esac
