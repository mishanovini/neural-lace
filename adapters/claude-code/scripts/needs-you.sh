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
#     which check(s) failed — but NEVER blocks: `add` always exits 0 for a
#     well-formed invocation, lint or no lint. The ledger's availability
#     invocation, lint or no lint. The ledger's availability outranks its
#     tidiness; see _ny_lint_decision_text() for the exact heuristics.
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

set -u

_NY_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_NY_NLPATHS="$_NY_SELF_DIR/../hooks/lib/nl-paths.sh"
if [[ -f "$_NY_NLPATHS" ]]; then
  # shellcheck disable=SC1090
  source "$_NY_NLPATHS"
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

_ny_ledger_file() { printf '%s/ledger.json' "$(_ny_state_dir)"; }

_ny_ensure_state() {
  local dir; dir="$(_ny_state_dir)"
  mkdir -p "$dir" 2>/dev/null || die "cannot create state dir: $dir"
  local f; f="$(_ny_ledger_file)"
  [[ -f "$f" ]] || echo '{"schema_version":1,"items":[]}' > "$f"
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
_ny_write_ledger() {
  local content="$1"
  local f; f="$(_ny_ledger_file)"
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
_ny_lint_decision_text() {
  local text="$1"
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
  local section="" text="" session_id="" tier=""
  local -a links=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --section) section="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --session) session_id="$2"; shift 2 ;;
      --link) links+=("$2"); shift 2 ;;
      --tier) tier="$2"; shift 2 ;;
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
  # only. WARN-only — never blocks add, never touches $?. See
  # _ny_lint_decision_text's own header comment for the three checks.
  local -a lint_warnings=()
  if [[ "$section" == "decision" ]]; then
    while IFS= read -r _ny_lw; do
      [[ -n "$_ny_lw" ]] && lint_warnings+=("$_ny_lw")
    done < <(_ny_lint_decision_text "$text")
    if [[ "${#lint_warnings[@]}" -gt 0 ]]; then
      err "cold-reader lint: this decision entry is missing: ${lint_warnings[*]} (added anyway — the ledger's availability outranks its lint; see needs-you.sh header 'COLD-READER LINT' for what each code means)"
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
  local cur; cur=$(_ny_read_ledger)
  local new
  new=$(echo "$cur" | jq \
    --arg id "$id" --arg ts "$ts" --arg section "$section" --arg text "$text" \
    --arg session_id "$session_id" --arg tier "$tier" --arg lint_csv "$lint_warnings_csv" \
    '
    ($session_id | if . == "" then null else . end) as $session
    | ($tier | if . == "" then null else . end) as $tier_v
    | ($lint_csv | if . == "" then [] else split(",") end) as $lint_warnings
    | .items += [{
        id: $id, created_at: $ts, updated_at: $ts, section: $section, text: $text,
        links: $ARGS.positional, session: $session, tier: $tier_v,
        state: "open", resolved_at: null, resolution_note: null,
        lint_warnings: $lint_warnings
      }]
    ' \
    --args -- "${links[@]}")
  _ny_write_ledger "$new"

  cmd_render >/dev/null

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
  _ny_write_ledger "$new"
  cmd_render >/dev/null
}

# ----------------------------------------------------------------------
# cmd_expire — collapse "decided" items resolved >7 days ago into a count.
# Does not delete data; flags items as collapsed=true so render can filter
# them from the itemized list and fold them into the trailing count line.
# Idempotent: safe to run every render call.
# ----------------------------------------------------------------------
NY_REVIEW_WINDOW_DAYS=7

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
  _ny_write_ledger "$new"
}

# ----------------------------------------------------------------------
# render helpers
# ----------------------------------------------------------------------

# jq's @tsv escapes embedded tabs/newlines/backslashes as literal \t \n \\
# (so a multi-line --text value stays a single TSV row). Reverse that after
# `read` splits the row back into fields, so a §3 block's line breaks render
# as real line breaks again, not literal backslash-n.
_ny_tsv_unescape() {
  local s="$1"
  s="${s//\\t/$'\t'}"
  s="${s//\\n/$'\n'}"
  s="${s//\\\\/\\}"
  printf '%s' "$s"
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
  local title
  title=$(printf '%s' "$text" | head -1)
  [[ -n "$title" ]] || title="(untitled decision)"
  printf '### %s\n' "$title"
  printf '%s\n' "$text"
  printf 'Links: %s\n' "$links_line"
  printf '*(added %s, session `%s`, id `%s`)*\n' "$created" "$session" "$id"
}

_ny_render_bullet() {
  local it="$1"
  local fields text session created
  fields=$(echo "$it" | jq -r '[.text, (.session // "unknown"), (.created_at | split("T")[0])] | @tsv')
  IFS=$'\t' read -r text session created <<< "$fields"
  text="$(_ny_tsv_unescape "$text")"
  printf -- '- %s — *(added %s, session `%s`)*\n' "$text" "$created" "$session"
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
  local stripped
  stripped="$(printf '%s\n' "$body" | sed -E '1{/^# NEEDS-YOU/d}' | sed -E '/./,$!d')"
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
  cmd_add --section decision --text "$stripped" --session "legacy-migration" \
    --tier "migrated_from_legacy_file" >/dev/null

  return 0
}

# ----------------------------------------------------------------------
# cmd_render — bootstrap-migrate, then expire, then rewrite NEEDS-YOU.md in
# full (4 sections, always).
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

  {
    printf '# NEEDS-YOU\n\n'
    printf 'Canonical awaiting-operator ledger (constitution §2/§3/§8). Machine-local, '
    printf 'mechanically maintained by `adapters/claude-code/scripts/needs-you.sh` — do not\n'
    printf 'hand-edit; re-render will overwrite. Generated %s.\n\n' "$(_ny_now)"

    printf '## Awaiting your decision\n\n'
    local decisions dcount
    decisions=$(echo "$cur" | jq -c '.items[] | select(.section == "decision" and .state == "open")')
    if [[ -z "$decisions" ]]; then
      printf '_None open._\n\n'
    else
      while IFS= read -r it; do
        [[ -n "$it" ]] || continue
        _ny_render_decision_block "$it"
        printf '\n'
      done <<< "$decisions"
    fi

    printf '## Open questions\n\n'
    local questions
    questions=$(echo "$cur" | jq -c '.items[] | select(.section == "question" and .state == "open")')
    if [[ -z "$questions" ]]; then
      printf '_None open._\n\n'
    else
      while IFS= read -r it2; do
        [[ -n "$it2" ]] || continue
        _ny_render_bullet "$it2"
      done <<< "$questions"
      printf '\n'
    fi

    printf '## In flight (sessions + waves)\n\n'
    local inflight
    inflight=$(echo "$cur" | jq -c '.items[] | select(.section == "inflight" and .state == "open")')
    if [[ -z "$inflight" ]]; then
      printf '_Nothing in flight._\n\n'
    else
      while IFS= read -r it3; do
        [[ -n "$it3" ]] || continue
        _ny_render_bullet "$it3"
      done <<< "$inflight"
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
  local pass=0 fail=0
  local -a errors=()
  ok()   { pass=$((pass+1)); echo "  PASS: $1"; }
  fail_() { fail=$((fail+1)); echo "  FAIL: $1" >&2; errors+=("$1"); }

  echo "needs-you.sh self-test (sandbox: $sandbox)"

  # T1: add a decision entry, id returned, section renders.
  local id1
  id1=$(cmd_add --section decision --text $'### Ship tonight?\nTier 1 — reversible.\nMy pick: yes.' --session "sess-aaa" --link "https://example.test/pr/1")
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
  local id_old
  id_old=$(cmd_add --section decision --text "An old decision from last week" --session "sess-old")
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
  # ledger item. (Note: the rendered markdown itself legitimately shows the
  # migrated text twice within a single item's block — once as the "### "
  # title line, once as the body — since _ny_render_decision_block always
  # renders title-then-full-body for every decision item, migrated or not;
  # see T4's "Ship tonight?" fixture for the same non-migration-related
  # shape. So idempotency must be asserted against the LEDGER's item count,
  # not a grep-count over the rendered file.)
  (
    export NEEDS_YOU_STATE_DIR="$sandbox3/state"
    export NEEDS_YOU_MD_PATH="$sandbox3/NEEDS-YOU.md"
    cmd_render >/dev/null 2>&1
  )
  local migrate_count3
  migrate_count3=$(jq '[.items[] | select(.tier == "migrated_from_legacy_file")] | length' "$sandbox3/state/ledger.json" 2>/dev/null || echo "?")
  [[ "$migrate_count3" == "1" ]] && ok "T19 bootstrap-migrate is idempotent (exactly 1 migrated ledger item after repeat render)" \
    || fail_ "T19 expected exactly 1 migrated ledger item after repeat render, got $migrate_count3"
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
  local q_count5
  q_count5=$(grep -c "Already-canonical fixture question" "$md5" || true)
  [[ "$q_count5" == "1" ]] && ok "T21 well-formed file untouched by bootstrap-migrate (no re-migration)" \
    || fail_ "T21 expected exactly 1 occurrence, got $q_count5 (possible spurious re-migration)"
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
  # §3-style Options table whose column 2 carries per-option outcome text)
  # gets an EMPTY lint_warnings array — no false-positive warn on a
  # well-formed block.
  local good_text
  good_text=$'### Ship the O.9 dashboard tonight?\nThe backlog KPI dashboard (adapters/claude-code/docs/kpis.md) has been green in staging for 3 days; shipping now vs Monday only changes who is on call if it regresses.\n| Option | What happens |\n|---|---|\n| Ship tonight | goes live now, I am on call |\n| Wait for Monday | ships Monday, no weekend on-call risk |\nMy pick: ship tonight.'
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
  # anywhere, and too short to carry real context either) WARNS: stderr
  # carries a lint notice, and the stored item's lint_warnings is non-empty
  # and specifically names no-anchor (plus no-context, since this fixture
  # is also just a bare title).
  local bad_text="Ship tonight? My pick: yes."
  local id23_out; id23_out=$(mktemp)
  local stderr23 id23
  stderr23=$(cmd_add --section decision --text "$bad_text" --session "sess-t23" 2>&1 >"$id23_out")
  id23=$(cat "$id23_out" 2>/dev/null); rm -f "$id23_out"
  if printf '%s' "$stderr23" | grep -qi "cold-reader lint"; then
    ok "T23 anchorless bare-shorthand decision warns on stderr"
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

  # T24: `add` NEVER blocks on a lint warning — exit code is still 0 even
  # for the worst-case bare-shorthand fixture from T23, and an id is still
  # returned (the ledger's availability outranks its lint).
  local rc24
  ( cmd_add --section decision --text "x" --session "sess-t24" >/dev/null 2>&1 )
  rc24=$?
  [[ "$rc24" == "0" ]] && ok "T24 add never blocks on a lint warning (exit 0 even for the worst-case bare text)" \
    || fail_ "T24 add exited non-zero ($rc24) on a lint-only warning — must never block"

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
                         -> prints new entry id, exit 0
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
