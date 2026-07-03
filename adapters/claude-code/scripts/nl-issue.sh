#!/bin/bash
# nl-issue.sh — cross-project NL self-improvement capture loop (Wave E, task E.8).
#
# ============================================================
# WHY THIS EXISTS (NL Overhaul Program Wave E, task E.8)
# ============================================================
#
# The 2026-07-01 effectiveness audit found harness-friction feedback scattered
# across channels nobody reviewed (a calibration file with 0 uses ever, a
# harness-evaluator run once, monitor alerts 0% acked). This script is the ONE
# capture point: any session, in ANY project, on this machine, appends a
# one-line friction/idea note to a single machine-wide JSONL ledger. It is
# machine-local by construction (lives under $HOME/.claude/state/), which is
# what makes it cross-project — every checkout on this machine writes to the
# same file regardless of which repo the session is rooted in.
#
# The constitution §5 pointer that tells sessions to use this script already
# landed (adapters/claude-code/rules/constitution.md, "Harness friction or
# defects noticed in ANY project: one line via `nl-issue.sh "<what>"`") — this
# task builds the script + skill the pointer refers to, and does NOT re-edit
# the constitution.
#
# ============================================================
# CONTRACT
# ============================================================
#
#   nl-issue.sh "<one line of text>"
#     Append one entry to the ledger:
#       {"ts":"...","project":"...","session":"...","text":"...","count":1,
#        "triage_status":"untriaged","triage_ref":"","triaged_ts":""}
#     - ts: UTC ISO-8601.
#     - project: basename of `git rev-parse --show-toplevel` for the CURRENT
#       cwd, or basename of cwd if not inside a git repo.
#     - session: $CLAUDE_SESSION_ID if set, else "unknown".
#     - text: the argument, verbatim (JSON-escaped on disk).
#     - Dedup: if an UNTRIAGED entry with byte-identical `text` AND the same
#       `project` exists with `ts` within the last 24h, that entry's `count`
#       is incremented in place instead of appending a new line (rewrites the
#       ledger; see _nli_rewrite_line). Triaged entries are never merged into
#       (a re-report after triage is a genuinely new occurrence).
#
#   nl-issue.sh --list [--untriaged]
#     Print the ledger, one line of human-readable summary per entry
#     (`[<n>] <triage_status> <project> <ts> (xN) <text>`), `<n>` being the
#     1-based line number in the ledger file (the index --triage stamps by).
#     --untriaged filters to triage_status == "untriaged" only.
#
#   nl-issue.sh --triage <n> <backlog|task|wontfix> <ref-or-reason>
#     Stamp entry number <n> (1-based, as printed by --list) IN PLACE:
#       triage_status = "backlog" | "task" | "wontfix"
#       triage_ref    = "<ref-or-reason>"
#       triaged_ts    = now (UTC ISO-8601)
#     Rewrites the ledger file with that one line replaced; every other line
#     byte-identical.
#
#   nl-issue.sh --digest-feed
#     Print ONE line for E.1's digest to consume, or NOTHING if there is
#     nothing to say (0 untriaged). See "DIGEST FEED CONTRACT" below.
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST)
# ============================================================
#
# Resolution order for the ledger path:
#   1. NL_ISSUES_PATH env var, if set (explicit override; used by --self-test
#      and by anything that wants a non-default location).
#   2. HARNESS_SELFTEST=1 and NL_ISSUES_PATH unset -> a sandboxed path under
#      ${TMPDIR:-/tmp}/nl-issues-selftest/<pid>.jsonl.
#   3. Default: $HOME/.claude/state/nl-issues.jsonl.
#
# The backlog file the escalation path appends to resolves the same way via
# NL_ISSUES_BACKLOG_PATH (falls back to the repo's docs/backlog.md, resolved
# via hooks/lib/nl-paths.sh's nl_repo_root — never ambient cwd guessing).
#
# ============================================================
# DIGEST FEED CONTRACT (consumed by E.1 session-start-digest.sh)
# ============================================================
#
# `nl-issue.sh --digest-feed` prints:
#   - NOTHING if the ledger is absent, empty, or has 0 untriaged entries
#     (E.1 "tolerate absent file" + "quiet feeds emit nothing" rules).
#   - Otherwise ONE line:
#       "<count> untriaged nl-issue(s), oldest <age>d old -> nl-issue.sh --list --untriaged"
#     and, when the escalation threshold is crossed (>5 untriaged OR oldest
#     untriaged entry >7 days old), a SECOND line prefixed "ESCALATION:" plus
#     (as a side effect, not to stdout) an idempotent backlog append of
#     `NL-ISSUES-TRIAGE-<yyyymmdd>` (today's date) to the resolved backlog
#     file — idempotent by grepping for that exact ID before appending, so
#     re-running --digest-feed the same day never duplicates the entry.
#   - E.1 is expected to prefix its own icon/feed-name per its own line-economy
#     rule; this script's job ends at supplying the count/age/escalation text.
#
# ============================================================

set -u

_NLI_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# nl-paths.sh lives under hooks/lib relative to this script's own location
# (adapters/claude-code/scripts/ -> adapters/claude-code/hooks/lib/).
_NLI_NLPATHS="$_NLI_SELF_DIR/../hooks/lib/nl-paths.sh"
if [[ -f "$_NLI_NLPATHS" ]]; then
  # shellcheck disable=SC1090
  source "$_NLI_NLPATHS"
fi

# ----------------------------------------------------------------------
# _nli_ledger_path — resolve the nl-issues ledger file path.
# ----------------------------------------------------------------------
_nli_ledger_path() {
  if [[ -n "${NL_ISSUES_PATH:-}" ]]; then
    printf '%s' "$NL_ISSUES_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/nl-issues-selftest/%s.jsonl' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/nl-issues.jsonl' "${HOME:-$PWD}"
  return 0
}

# ----------------------------------------------------------------------
# _nli_backlog_path — resolve the backlog file the escalation path appends
# to. NL_ISSUES_BACKLOG_PATH wins (self-test / explicit override); else the
# repo's docs/backlog.md via nl_repo_root(); else empty (no-op, never error).
# ----------------------------------------------------------------------
_nli_backlog_path() {
  if [[ -n "${NL_ISSUES_BACKLOG_PATH:-}" ]]; then
    printf '%s' "$NL_ISSUES_BACKLOG_PATH"
    return 0
  fi
  if command -v nl_repo_root >/dev/null 2>&1; then
    local root
    root="$(nl_repo_root)"
    if [[ -n "$root" ]]; then
      printf '%s/docs/backlog.md' "$root"
      return 0
    fi
  fi
  printf ''
  return 0
}

# ----------------------------------------------------------------------
# _nli_json_escape <string> — same technique as signal-ledger.sh (no jq dep).
# ----------------------------------------------------------------------
_nli_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  local nl=$'\n' cr=$'\r' tab=$'\t'
  s="${s//$nl/\\n}"
  s="${s//$cr/\\r}"
  s="${s//$tab/\\t}"
  s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# _nli_json_field <json-line> <field> — extract a top-level string field's
# RAW (still-escaped) value from a JSONL line without a jq dependency.
# Assumes the flat, single-line, no-nested-object shape this script itself
# writes (safe: we control every writer of this file).
# ----------------------------------------------------------------------
_nli_json_field() {
  local line="$1" field="$2"
  # Match "field":"....(unescaped-quote)" — a small state machine would be
  # more correct for pathological input, but every value we write already
  # ran through _nli_json_escape, so an unescaped " never appears inside a
  # value; this sed is exact for this file's own writer.
  printf '%s' "$line" | sed -n "s/.*\"$field\":\"\\(\\([^\"\\\\]\\|\\\\.\\)*\\)\".*/\\1/p"
}

# ----------------------------------------------------------------------
# _nli_json_num_field <json-line> <field> — extract a top-level BARE
# (unquoted) numeric field's value from a JSONL line, e.g. "count":3. This
# script only ever writes "count" as a bare integer, never a quoted string,
# so _nli_json_field (which only matches quoted string values) never
# extracts it — this is the companion extractor for that field shape.
# ----------------------------------------------------------------------
_nli_json_num_field() {
  local line="$1" field="$2"
  printf '%s' "$line" | sed -n "s/.*\"$field\":\\([0-9][0-9]*\\).*/\\1/p"
}

# _nli_json_unescape <string> — reverse of _nli_json_escape, for display.
_nli_json_unescape() {
  local s="$1"
  s="${s//\\n/$'\n'}"
  s="${s//\\r/$'\r'}"
  s="${s//\\t/$'\t'}"
  s="${s//\\\"/\"}"
  s="${s//\\\\/\\}"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# _nli_project_name — basename of git toplevel for CWD, else basename of CWD.
# ----------------------------------------------------------------------
_nli_project_name() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$top" ]]; then
    basename "$top"
  else
    basename "$PWD"
  fi
}

# ----------------------------------------------------------------------
# _nli_now — UTC ISO-8601 timestamp.
# ----------------------------------------------------------------------
_nli_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown'
}

# ----------------------------------------------------------------------
# _nli_epoch <iso-ts> — best-effort seconds-since-epoch for an ISO-8601 UTC
# timestamp produced by _nli_now. Prints 0 on failure (never errors).
# ----------------------------------------------------------------------
_nli_epoch() {
  local ts="$1"
  date -u -d "$ts" '+%s' 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null || echo 0
}

# ----------------------------------------------------------------------
# nli_append <text> — the append/dedup verb.
# ----------------------------------------------------------------------
nli_append() {
  local text="$1"
  local path
  path="$(_nli_ledger_path)"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true

  local project session now_ts now_epoch
  project="$(_nli_project_name)"
  session="${CLAUDE_SESSION_ID:-unknown}"
  now_ts="$(_nli_now)"
  now_epoch="$(_nli_epoch "$now_ts")"

  # Dedup: scan existing UNTRIAGED lines for byte-identical text + same
  # project within the last 24h; if found, rewrite that line with count++.
  if [[ -f "$path" ]]; then
    local line_no=0 found_no="" found_line="" found_count=1
    while IFS= read -r line; do
      line_no=$((line_no+1))
      [[ -z "$line" ]] && continue
      local l_status l_project l_text_esc l_ts
      l_status="$(_nli_json_field "$line" "triage_status")"
      [[ "$l_status" != "untriaged" ]] && continue
      l_project="$(_nli_json_field "$line" "project")"
      [[ "$l_project" != "$project" ]] && continue
      l_text_esc="$(_nli_json_field "$line" "text")"
      local text_esc
      text_esc="$(_nli_json_escape "$text")"
      [[ "$l_text_esc" != "$text_esc" ]] && continue
      l_ts="$(_nli_json_field "$line" "ts")"
      local l_epoch age
      l_epoch="$(_nli_epoch "$l_ts")"
      age=$(( now_epoch - l_epoch ))
      if [[ "$l_epoch" -gt 0 && "$age" -ge 0 && "$age" -lt 86400 ]]; then
        found_no="$line_no"
        found_line="$line"
        local l_count
        l_count="$(_nli_json_num_field "$line" "count")"
        [[ -z "$l_count" || ! "$l_count" =~ ^[0-9]+$ ]] && l_count=1
        found_count=$((l_count+1))
        break
      fi
    done < "$path"

    if [[ -n "$found_no" ]]; then
      local new_line
      new_line="$(printf '{"ts":"%s","project":"%s","session":"%s","text":"%s","count":%s,"triage_status":"untriaged","triage_ref":"","triaged_ts":""}' \
        "$now_ts" "$(_nli_json_escape "$project")" "$(_nli_json_escape "$session")" \
        "$(_nli_json_escape "$text")" "$found_count")"
      _nli_replace_line "$path" "$found_no" "$new_line"
      echo "nl-issue: dedup (count=$found_count) -> $path"
      return 0
    fi
  fi

  local line
  line="$(printf '{"ts":"%s","project":"%s","session":"%s","text":"%s","count":1,"triage_status":"untriaged","triage_ref":"","triaged_ts":""}' \
    "$now_ts" "$(_nli_json_escape "$project")" "$(_nli_json_escape "$session")" "$(_nli_json_escape "$text")")"
  printf '%s\n' "$line" >> "$path"
  echo "nl-issue: recorded -> $path"
  return 0
}

# ----------------------------------------------------------------------
# _nli_replace_line <path> <1-based-line-no> <new-line> — rewrite exactly
# one line of a file in place via a temp file + mv (atomic-ish, portable).
# ----------------------------------------------------------------------
_nli_replace_line() {
  local path="$1" line_no="$2" new_line="$3"
  local tmp
  tmp="$(mktemp "${path}.XXXXXX" 2>/dev/null || echo "${path}.tmp$$")"
  local n=0
  while IFS= read -r existing || [[ -n "$existing" ]]; do
    n=$((n+1))
    if [[ "$n" == "$line_no" ]]; then
      printf '%s\n' "$new_line"
    else
      printf '%s\n' "$existing"
    fi
  done < "$path" > "$tmp"
  mv "$tmp" "$path"
}

# ----------------------------------------------------------------------
# nli_list [--untriaged] — human-readable listing.
# ----------------------------------------------------------------------
nli_list() {
  local filter="${1:-}"
  local path
  path="$(_nli_ledger_path)"
  if [[ ! -f "$path" ]]; then
    return 0
  fi
  local n=0
  while IFS= read -r line; do
    n=$((n+1))
    [[ -z "$line" ]] && continue
    local status project ts text count
    status="$(_nli_json_field "$line" "triage_status")"
    if [[ "$filter" == "--untriaged" && "$status" != "untriaged" ]]; then
      continue
    fi
    project="$(_nli_json_field "$line" "project")"
    ts="$(_nli_json_field "$line" "ts")"
    text="$(_nli_json_unescape "$(_nli_json_field "$line" "text")")"
    count="$(_nli_json_num_field "$line" "count")"
    [[ -z "$count" ]] && count=1
    printf '[%d] %s %s %s (x%s) %s\n' "$n" "$status" "$project" "$ts" "$count" "$text"
  done < "$path"
  return 0
}

# ----------------------------------------------------------------------
# nli_triage <n> <backlog|task|wontfix> <ref-or-reason>
# ----------------------------------------------------------------------
nli_triage() {
  local n="$1" kind="$2" ref="$3"
  local path
  path="$(_nli_ledger_path)"
  if [[ ! -f "$path" ]]; then
    echo "nl-issue: no ledger at $path" >&2
    return 1
  fi
  if [[ ! "$n" =~ ^[0-9]+$ ]] || [[ "$n" -lt 1 ]]; then
    echo "nl-issue: invalid entry number '$n'" >&2
    return 1
  fi
  case "$kind" in
    backlog|task|wontfix) ;;
    *) echo "nl-issue: invalid triage kind '$kind' (want backlog|task|wontfix)" >&2; return 1 ;;
  esac

  local total
  total="$(wc -l < "$path" 2>/dev/null | tr -d ' ')"
  if [[ "$n" -gt "$total" ]]; then
    echo "nl-issue: entry $n does not exist (ledger has $total entries)" >&2
    return 1
  fi

  local target_line
  target_line="$(sed -n "${n}p" "$path")"
  if [[ -z "$target_line" ]]; then
    echo "nl-issue: entry $n does not exist" >&2
    return 1
  fi

  local ts project session text count
  ts="$(_nli_json_field "$target_line" "ts")"
  project="$(_nli_json_field "$target_line" "project")"
  session="$(_nli_json_field "$target_line" "session")"
  text="$(_nli_json_field "$target_line" "text")"
  count="$(_nli_json_num_field "$target_line" "count")"
  [[ -z "$count" ]] && count=1

  local new_line
  new_line="$(printf '{"ts":"%s","project":"%s","session":"%s","text":"%s","count":%s,"triage_status":"%s","triage_ref":"%s","triaged_ts":"%s"}' \
    "$ts" "$project" "$session" "$text" "$count" "$kind" "$(_nli_json_escape "$ref")" "$(_nli_now)")"
  _nli_replace_line "$path" "$n" "$new_line"
  echo "nl-issue: entry $n stamped $kind ($ref)"
  return 0
}

# ----------------------------------------------------------------------
# _nli_backlog_append_escalation <untriaged-count> <oldest-age-days>
#
# Idempotent (grep for the exact dated ID before appending) backlog entry.
# Never errors if the backlog path is unresolvable — best-effort, writer
# semantics (mirrors ledger_emit's "never blocks" contract).
# ----------------------------------------------------------------------
_nli_backlog_append_escalation() {
  local untriaged="$1" oldest_age="$2"
  local backlog
  backlog="$(_nli_backlog_path)"
  [[ -z "$backlog" ]] && return 0
  [[ -f "$backlog" ]] || return 0

  local today id
  today="$(date -u '+%Y%m%d' 2>/dev/null || echo 'unknown')"
  id="NL-ISSUES-TRIAGE-${today}"

  if grep -q "$id" "$backlog" 2>/dev/null; then
    return 0
  fi

  {
    printf '\n## %s — nl-issue triage escalation (auto-filed)\n\n' "$id"
    printf '**Severity:** P3 (nagging, not blocking)\n'
    printf '**Trigger:** %s untriaged nl-issue entries (threshold >5) or oldest untriaged entry is %sd old (threshold >7d).\n' "$untriaged" "$oldest_age"
    printf '**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.\n'
    printf '**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).\n'
  } >> "$backlog"
  return 0
}

# ----------------------------------------------------------------------
# nli_digest_feed — the E.1-consumed feed line(s).
# ----------------------------------------------------------------------
nli_digest_feed() {
  local path
  path="$(_nli_ledger_path)"
  [[ -f "$path" ]] || return 0

  local now_epoch
  now_epoch="$(_nli_epoch "$(_nli_now)")"

  local untriaged=0 oldest_epoch="" oldest_age_days=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local status ts
    status="$(_nli_json_field "$line" "triage_status")"
    [[ "$status" != "untriaged" ]] && continue
    untriaged=$((untriaged+1))
    ts="$(_nli_json_field "$line" "ts")"
    local ep
    ep="$(_nli_epoch "$ts")"
    if [[ -z "$oldest_epoch" ]] || [[ "$ep" -lt "$oldest_epoch" ]]; then
      oldest_epoch="$ep"
    fi
  done < "$path"

  [[ "$untriaged" -eq 0 ]] && return 0

  if [[ -n "$oldest_epoch" && "$oldest_epoch" -gt 0 ]]; then
    oldest_age_days=$(( (now_epoch - oldest_epoch) / 86400 ))
  fi

  printf '%s untriaged nl-issue(s), oldest %sd old -> nl-issue.sh --list --untriaged\n' "$untriaged" "$oldest_age_days"

  if [[ "$untriaged" -gt 5 ]] || [[ "$oldest_age_days" -gt 7 ]]; then
    printf 'ESCALATION: nl-issue backlog needs triage (%s untriaged, oldest %sd) -> nl-issue.sh --list --untriaged\n' "$untriaged" "$oldest_age_days"
    _nli_backlog_append_escalation "$untriaged" "$oldest_age_days"
  fi
  return 0
}

# ============================================================
# CLI dispatch (only when executed directly, not sourced)
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test)
      : # handled below, after function defs, via a dedicated block
      ;;
    --list)
      nli_list "${2:-}"
      exit 0
      ;;
    --triage)
      nli_triage "${2:-}" "${3:-}" "${4:-}"
      exit $?
      ;;
    --digest-feed)
      nli_digest_feed
      exit 0
      ;;
    "")
      echo "usage: nl-issue.sh \"<one line>\" | --list [--untriaged] | --triage <n> <backlog|task|wontfix> <ref-or-reason> | --digest-feed" >&2
      exit 1
      ;;
    *)
      nli_append "$1"
      exit $?
      ;;
  esac
fi

# ============================================================
# --self-test
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'nlist')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  echo "self-test: nl-issue.sh"

  # ------------------------------------------------------------
  # Scenario 1: append then --list shows one untriaged entry.
  # ------------------------------------------------------------
  echo "Scenario 1: append + --list round-trip"
  LEDGER1="$TMP/s1.jsonl"
  ( export NL_ISSUES_PATH="$LEDGER1"; bash "$SELF_ABS" "first friction note" >/dev/null )
  if [[ -f "$LEDGER1" ]] && grep -q '"text":"first friction note"' "$LEDGER1"; then
    pass "append wrote the entry"
  else
    fail "append did not write expected entry to $LEDGER1"
  fi
  LIST1="$( export NL_ISSUES_PATH="$LEDGER1"; bash "$SELF_ABS" --list )"
  if printf '%s' "$LIST1" | grep -q "first friction note" && printf '%s' "$LIST1" | grep -q "untriaged"; then
    pass "--list shows the entry as untriaged"
  else
    fail "--list did not show expected entry: $LIST1"
  fi

  # ------------------------------------------------------------
  # Scenario 2: byte-identical text within 24h dedups (count++).
  # ------------------------------------------------------------
  echo "Scenario 2: 24h dedup increments count instead of appending"
  LEDGER2="$TMP/s2.jsonl"
  ( export NL_ISSUES_PATH="$LEDGER2"; bash "$SELF_ABS" "dup me" >/dev/null )
  ( export NL_ISSUES_PATH="$LEDGER2"; bash "$SELF_ABS" "dup me" >/dev/null )
  ( export NL_ISSUES_PATH="$LEDGER2"; bash "$SELF_ABS" "dup me" >/dev/null )
  n_lines=$(wc -l < "$LEDGER2" 2>/dev/null | tr -d ' ')
  if [[ "$n_lines" == "1" ]]; then
    pass "three identical appends within 24h produced ONE line (got $n_lines)"
  else
    fail "expected 1 line after 3 dup appends, got $n_lines"
  fi
  if grep -q '"count":3' "$LEDGER2"; then
    pass "count incremented to 3"
  else
    fail "expected count:3 in $(cat "$LEDGER2" 2>/dev/null)"
  fi
  # Different text does NOT dedup.
  ( export NL_ISSUES_PATH="$LEDGER2"; bash "$SELF_ABS" "different note" >/dev/null )
  n_lines2=$(wc -l < "$LEDGER2" 2>/dev/null | tr -d ' ')
  if [[ "$n_lines2" == "2" ]]; then
    pass "distinct text appends as a NEW line (got $n_lines2 total)"
  else
    fail "expected 2 lines after distinct append, got $n_lines2"
  fi

  # ------------------------------------------------------------
  # Scenario 3: dedup does NOT merge into an already-triaged entry.
  # ------------------------------------------------------------
  echo "Scenario 3: triaged entries are not merged into by a re-report"
  LEDGER3="$TMP/s3.jsonl"
  ( export NL_ISSUES_PATH="$LEDGER3"; bash "$SELF_ABS" "recurring issue" >/dev/null )
  ( export NL_ISSUES_PATH="$LEDGER3"; bash "$SELF_ABS" --triage 1 wontfix "not reproducible" >/dev/null )
  ( export NL_ISSUES_PATH="$LEDGER3"; bash "$SELF_ABS" "recurring issue" >/dev/null )
  n_lines3=$(wc -l < "$LEDGER3" 2>/dev/null | tr -d ' ')
  if [[ "$n_lines3" == "2" ]]; then
    pass "re-report after triage creates a NEW untriaged line (got $n_lines3 total)"
  else
    fail "expected 2 lines (1 triaged + 1 new untriaged), got $n_lines3"
  fi

  # ------------------------------------------------------------
  # Scenario 4: --triage stamps the entry in place, other lines untouched.
  # ------------------------------------------------------------
  echo "Scenario 4: --triage round-trip stamps status/ref/triaged_ts in place"
  LEDGER4="$TMP/s4.jsonl"
  ( export NL_ISSUES_PATH="$LEDGER4"; bash "$SELF_ABS" "issue A" >/dev/null )
  ( export NL_ISSUES_PATH="$LEDGER4"; bash "$SELF_ABS" "issue B" >/dev/null )
  ( export NL_ISSUES_PATH="$LEDGER4"; bash "$SELF_ABS" --triage 1 backlog "BACKLOG-REF-42" >/dev/null )
  if grep -q '"triage_status":"backlog"' "$LEDGER4" && grep -q '"triage_ref":"BACKLOG-REF-42"' "$LEDGER4"; then
    pass "--triage stamped status + ref on entry 1"
  else
    fail "--triage did not stamp expected fields: $(cat "$LEDGER4")"
  fi
  if grep -q '"text":"issue B"' "$LEDGER4" && grep '"text":"issue B"' "$LEDGER4" | grep -q '"triage_status":"untriaged"'; then
    pass "entry 2 (issue B) left untouched as untriaged"
  else
    fail "entry 2 was unexpectedly modified: $(cat "$LEDGER4")"
  fi
  UNTRIAGED4="$( export NL_ISSUES_PATH="$LEDGER4"; bash "$SELF_ABS" --list --untriaged )"
  if printf '%s' "$UNTRIAGED4" | grep -q "issue B" && ! printf '%s' "$UNTRIAGED4" | grep -q "issue A"; then
    pass "--list --untriaged filters out the triaged entry"
  else
    fail "--list --untriaged did not filter correctly: $UNTRIAGED4"
  fi

  # ------------------------------------------------------------
  # Scenario 5: cross-project proof — append from a mktemp cwd OUTSIDE the
  # repo and assert the project field differs from this repo's own name.
  # ------------------------------------------------------------
  echo "Scenario 5: cross-project proof (append from outside-repo mktemp cwd)"
  OUTSIDE_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'nliout')
  REPO_PROJECT_NAME="$(basename "$(git -C "$(dirname "$SELF_ABS")" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")"
  LEDGER5="$TMP/s5.jsonl"
  ( cd "$OUTSIDE_DIR" && NL_ISSUES_PATH="$LEDGER5" bash "$SELF_ABS" "friction from an unrelated project" >/dev/null )
  OUTSIDE_PROJECT_NAME="$(basename "$OUTSIDE_DIR")"
  if grep -q "\"project\":\"$OUTSIDE_PROJECT_NAME\"" "$LEDGER5"; then
    pass "entry's project field == basename of the mktemp cwd ($OUTSIDE_PROJECT_NAME)"
  else
    fail "expected project field '$OUTSIDE_PROJECT_NAME' in $(cat "$LEDGER5")"
  fi
  if ! grep -q "\"project\":\"$REPO_PROJECT_NAME\"" "$LEDGER5"; then
    pass "project field differs from the neural-lace repo's own project name ($REPO_PROJECT_NAME)"
  else
    fail "project field unexpectedly matched the repo name ($REPO_PROJECT_NAME) — cross-project proof failed"
  fi
  rm -rf "$OUTSIDE_DIR" 2>/dev/null || true

  # ------------------------------------------------------------
  # Scenario 6: session field picks up $CLAUDE_SESSION_ID when set, else
  # "unknown".
  # ------------------------------------------------------------
  echo "Scenario 6: session field resolution"
  LEDGER6="$TMP/s6.jsonl"
  ( export NL_ISSUES_PATH="$LEDGER6"; unset CLAUDE_SESSION_ID; bash "$SELF_ABS" "no session set" >/dev/null )
  if grep -q '"session":"unknown"' "$LEDGER6"; then
    pass "session defaults to 'unknown' when CLAUDE_SESSION_ID unset"
  else
    fail "expected session:unknown in $(cat "$LEDGER6")"
  fi
  LEDGER6B="$TMP/s6b.jsonl"
  ( export NL_ISSUES_PATH="$LEDGER6B"; export CLAUDE_SESSION_ID="sess-xyz"; bash "$SELF_ABS" "with session set" >/dev/null )
  if grep -q '"session":"sess-xyz"' "$LEDGER6B"; then
    pass "session picks up \$CLAUDE_SESSION_ID when set"
  else
    fail "expected session:sess-xyz in $(cat "$LEDGER6B")"
  fi

  # ------------------------------------------------------------
  # Scenario 7: digest feed silent when 0 untriaged / absent ledger.
  # ------------------------------------------------------------
  echo "Scenario 7: digest feed emits nothing for absent/empty/all-triaged ledger"
  MISSING_LEDGER="$TMP/does-not-exist.jsonl"
  OUT7A="$( export NL_ISSUES_PATH="$MISSING_LEDGER"; bash "$SELF_ABS" --digest-feed )"
  if [[ -z "$OUT7A" ]]; then
    pass "absent ledger -> no digest output"
  else
    fail "expected empty digest output for absent ledger, got: $OUT7A"
  fi
  LEDGER7="$TMP/s7.jsonl"
  ( export NL_ISSUES_PATH="$LEDGER7"; bash "$SELF_ABS" "will be triaged" >/dev/null )
  ( export NL_ISSUES_PATH="$LEDGER7"; bash "$SELF_ABS" --triage 1 wontfix "n/a" >/dev/null )
  OUT7B="$( export NL_ISSUES_PATH="$LEDGER7"; bash "$SELF_ABS" --digest-feed )"
  if [[ -z "$OUT7B" ]]; then
    pass "all-triaged ledger -> no digest output"
  else
    fail "expected empty digest output for all-triaged ledger, got: $OUT7B"
  fi

  # ------------------------------------------------------------
  # Scenario 8: digest feed non-escalation line under threshold (<=5
  # untriaged, oldest <=7d) — count/age line present, no ESCALATION line, no
  # backlog append.
  # ------------------------------------------------------------
  echo "Scenario 8: digest feed under-threshold line (no escalation)"
  LEDGER8="$TMP/s8.jsonl"
  BACKLOG8="$TMP/backlog8.md"
  printf '# fixture backlog\n' > "$BACKLOG8"
  for i in 1 2 3; do
    ( export NL_ISSUES_PATH="$LEDGER8"; bash "$SELF_ABS" "under-threshold issue $i" >/dev/null )
  done
  OUT8="$( export NL_ISSUES_PATH="$LEDGER8" NL_ISSUES_BACKLOG_PATH="$BACKLOG8"; bash "$SELF_ABS" --digest-feed )"
  if printf '%s' "$OUT8" | grep -q "^3 untriaged"; then
    pass "under-threshold feed line reports correct count (3)"
  else
    fail "expected '3 untriaged...' line, got: $OUT8"
  fi
  if ! printf '%s' "$OUT8" | grep -q "ESCALATION"; then
    pass "no ESCALATION line under threshold"
  else
    fail "unexpected ESCALATION line under threshold: $OUT8"
  fi
  if ! grep -q "NL-ISSUES-TRIAGE-" "$BACKLOG8"; then
    pass "no backlog append under threshold"
  else
    fail "unexpected backlog append under threshold: $(cat "$BACKLOG8")"
  fi

  # ------------------------------------------------------------
  # Scenario 9: escalation fixture — 6 untriaged entries -> ESCALATION line
  # + idempotent backlog entry in a SANDBOX copy of the backlog.
  # ------------------------------------------------------------
  echo "Scenario 9: escalation fixture (6 untriaged -> backlog line in sandbox copy)"
  LEDGER9="$TMP/s9.jsonl"
  BACKLOG9="$TMP/backlog9.md"
  printf '# fixture backlog\n' > "$BACKLOG9"
  for i in 1 2 3 4 5 6; do
    ( export NL_ISSUES_PATH="$LEDGER9"; bash "$SELF_ABS" "escalation issue $i" >/dev/null )
  done
  OUT9="$( export NL_ISSUES_PATH="$LEDGER9" NL_ISSUES_BACKLOG_PATH="$BACKLOG9"; bash "$SELF_ABS" --digest-feed )"
  if printf '%s' "$OUT9" | grep -q "^6 untriaged"; then
    pass "escalation feed line reports correct count (6)"
  else
    fail "expected '6 untriaged...' line, got: $OUT9"
  fi
  if printf '%s' "$OUT9" | grep -q "ESCALATION"; then
    pass "ESCALATION line present for 6 untriaged (>5 threshold)"
  else
    fail "expected an ESCALATION line, got: $OUT9"
  fi
  TODAY_ID="NL-ISSUES-TRIAGE-$(date -u '+%Y%m%d')"
  if grep -q "$TODAY_ID" "$BACKLOG9"; then
    pass "idempotent backlog entry $TODAY_ID appended to the SANDBOX backlog copy"
  else
    fail "expected $TODAY_ID in sandbox backlog, got: $(cat "$BACKLOG9")"
  fi
  # Re-run --digest-feed: must NOT duplicate the entry (idempotence).
  ( export NL_ISSUES_PATH="$LEDGER9" NL_ISSUES_BACKLOG_PATH="$BACKLOG9"; bash "$SELF_ABS" --digest-feed >/dev/null )
  DUP_COUNT=$(grep -c "$TODAY_ID" "$BACKLOG9" 2>/dev/null | tr -d ' ')
  if [[ "$DUP_COUNT" == "1" ]]; then
    pass "re-running --digest-feed the same day does not duplicate the backlog entry"
  else
    fail "expected exactly 1 occurrence of $TODAY_ID after re-run, got $DUP_COUNT"
  fi
  # Confirm the REAL (non-sandbox) backlog was never touched by this scenario.
  REAL_BACKLOG_HITS=0
  if command -v nl_repo_root >/dev/null 2>&1; then
    REAL_ROOT="$(nl_repo_root)"
    if [[ -n "$REAL_ROOT" && -f "$REAL_ROOT/docs/backlog.md" ]]; then
      REAL_BACKLOG_HITS=$(grep -c "$TODAY_ID" "$REAL_ROOT/docs/backlog.md" 2>/dev/null | tr -d ' ')
    fi
  fi
  if [[ "${REAL_BACKLOG_HITS:-0}" == "0" ]]; then
    pass "the real repo docs/backlog.md was NOT touched by the sandboxed escalation test"
  else
    fail "the REAL docs/backlog.md was unexpectedly modified by the self-test"
  fi

  # ------------------------------------------------------------
  # Scenario 10: oldest-age escalation path (>7d) independent of count.
  # ------------------------------------------------------------
  echo "Scenario 10: oldest-age >7d triggers escalation even with few entries"
  LEDGER10="$TMP/s10.jsonl"
  BACKLOG10="$TMP/backlog10.md"
  printf '# fixture backlog\n' > "$BACKLOG10"
  OLD_TS="$(date -u -d '10 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-10d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  if [[ -n "$OLD_TS" ]]; then
    printf '{"ts":"%s","project":"fixture-proj","session":"unknown","text":"stale issue","count":1,"triage_status":"untriaged","triage_ref":"","triaged_ts":""}\n' "$OLD_TS" > "$LEDGER10"
    OUT10="$( export NL_ISSUES_PATH="$LEDGER10" NL_ISSUES_BACKLOG_PATH="$BACKLOG10"; bash "$SELF_ABS" --digest-feed )"
    if printf '%s' "$OUT10" | grep -q "ESCALATION"; then
      pass "a single 10-day-old untriaged entry triggers ESCALATION on age alone"
    else
      fail "expected ESCALATION for a 10-day-old single entry, got: $OUT10"
    fi
  else
    echo "  ok   Scenario 10 SKIP (date arithmetic unsupported in this environment)"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
