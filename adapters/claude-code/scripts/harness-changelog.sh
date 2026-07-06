#!/bin/bash
# harness-changelog.sh — "what's new" append + digest-consumed line (Wave F,
# task F.2, §F.2b mechanism 2).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# §F.2b names the silent-auto-install gap: `session-start-auto-install.sh`
# continuously syncs harness changes from origin/master into a live machine,
# but nothing ever TOLD the operator a new capability arrived — the 2026-07-03
# nl-issue.sh landing is the named example (the operator would not have known
# about it without being told directly). This script is the machine-wide
# "what's new" ledger: any NEW operator-facing capability appends ONE line
# here at ship time; the SessionStart digest surfaces unseen entries once per
# session ("harness changes since your last session"), then marks them seen
# for THIS machine so they do not repeat forever.
#
# Machine-local by construction (same convention as nl-issue.sh): lives under
# $HOME/.claude/state/, not any single repo, so every checkout on this
# machine sees the same changelog regardless of which repo a session is
# rooted in.
#
# ============================================================
# CONTRACT
# ============================================================
#
#   harness-changelog.sh append --text "<one line: what shipped>" [--runbook <path>]
#     Append one entry to the ledger:
#       {"ts":"...","text":"...","runbook":"...","id":"<sha1-ish-stable-id>"}
#     - ts: UTC ISO-8601 (append time — this is when the entry becomes
#       visible, not necessarily the commit date).
#     - text: the argument, verbatim (JSON-escaped on disk).
#     - runbook: optional path to the runbook stub this capability shipped
#       with (empty string if none).
#     - id: a short stable id derived from `text` (first 12 hex chars of a
#       checksum) so the same entry appended twice (e.g., a re-run of a
#       release script) is idempotent — re-appending identical text is a
#       no-op, not a duplicate line.
#
#   harness-changelog.sh --digest-line
#     Print ONE line for the SessionStart digest to consume, naming the
#     count of UNSEEN entries (relative to this machine's seen-marker), or
#     NOTHING if there are zero unseen entries. Also ADVANCES the seen-marker
#     to the newest entry's id — so a subsequent call in the SAME session
#     (or a later session) does not re-report the same entries. This mirrors
#     nl-issue.sh's dedup discipline: never repeat a signal already surfaced.
#
#   harness-changelog.sh --list [--all]
#     Print every entry (human-readable), newest first. Without --all,
#     stops at the current seen-marker (i.e., shows only what's still new).
#
#   harness-changelog.sh --self-test
#     Fixture suite in a sandboxed HOME (HARNESS_SELFTEST=1). Exit 0 iff all
#     scenarios pass.
#
# ============================================================
# ENV
# ============================================================
#   HARNESS_CHANGELOG_PATH   override the ledger path (self-test / explicit)
#   HARNESS_CHANGELOG_SEEN_PATH   override the seen-marker path
#   HARNESS_SELFTEST=1       sandbox both paths under a per-PID tempdir

set -u

_HCL_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ----------------------------------------------------------------------
# _hcl_ledger_path / _hcl_seen_path — resolve state file paths.
# ----------------------------------------------------------------------
_hcl_ledger_path() {
  if [[ -n "${HARNESS_CHANGELOG_PATH:-}" ]]; then
    printf '%s' "$HARNESS_CHANGELOG_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/harness-changelog-selftest/%s/harness-changelog.jsonl' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/harness-changelog.jsonl' "${HOME:-$PWD}"
  return 0
}

_hcl_seen_path() {
  if [[ -n "${HARNESS_CHANGELOG_SEEN_PATH:-}" ]]; then
    printf '%s' "$HARNESS_CHANGELOG_SEEN_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/harness-changelog-selftest/%s/seen-marker' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/harness-changelog-seen' "${HOME:-$PWD}"
  return 0
}

# ----------------------------------------------------------------------
# _hcl_json_escape <string> — same technique as nl-issue.sh / signal-ledger.sh.
# ----------------------------------------------------------------------
_hcl_json_escape() {
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

_hcl_json_field() {
  local line="$1" field="$2"
  printf '%s' "$line" | sed -n "s/.*\"$field\":\"\\(\\([^\"\\\\]\\|\\\\.\\)*\\)\".*/\\1/p"
}

# ----------------------------------------------------------------------
# _hcl_stable_id <text> — 12-hex-char stable id derived from text, so
# re-appending identical text is idempotent. Prefers sha1sum/shasum;
# falls back to a simple cksum-based id (still stable, just not
# collision-resistant across many entries — acceptable for a low-volume
# machine-local changelog).
# ----------------------------------------------------------------------
_hcl_stable_id() {
  local text="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$text" | sha1sum | cut -c1-12
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$text" | shasum | cut -c1-12
    return 0
  fi
  printf '%s' "$text" | cksum | tr ' ' '-' | cut -c1-12
  return 0
}

# ----------------------------------------------------------------------
# _hcl_now — UTC ISO-8601 timestamp.
# ----------------------------------------------------------------------
_hcl_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ"
}

# ----------------------------------------------------------------------
# hcl_append --text <str> [--runbook <path>]
# ----------------------------------------------------------------------
hcl_append() {
  local text="" runbook=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --text) text="${2:-}"; shift 2 ;;
      --runbook) runbook="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$text" ]]; then
    echo "harness-changelog: --text is required" >&2
    return 2
  fi

  local ledger
  ledger="$(_hcl_ledger_path)"
  mkdir -p "$(dirname "$ledger")" 2>/dev/null

  local id
  id="$(_hcl_stable_id "$text")"

  # Idempotency: if an entry with this id already exists, no-op.
  if [[ -f "$ledger" ]] && grep -qF "\"id\":\"${id}\"" "$ledger" 2>/dev/null; then
    echo "harness-changelog: entry already present (id ${id}) — no-op"
    return 0
  fi

  local ts esc_text esc_runbook
  ts="$(_hcl_now)"
  esc_text="$(_hcl_json_escape "$text")"
  esc_runbook="$(_hcl_json_escape "$runbook")"

  printf '{"ts":"%s","text":"%s","runbook":"%s","id":"%s"}\n' \
    "$ts" "$esc_text" "$esc_runbook" "$id" >> "$ledger"
  echo "harness-changelog: appended (id ${id}) -> ${ledger}"
  return 0
}

# ----------------------------------------------------------------------
# hcl_digest_line — print one digest line naming unseen-entry count, or
# nothing if zero. Advances the seen-marker to the newest entry's id.
# ----------------------------------------------------------------------
hcl_digest_line() {
  local ledger seen
  ledger="$(_hcl_ledger_path)"
  seen="$(_hcl_seen_path)"

  [[ -f "$ledger" ]] || return 0

  local seen_id=""
  [[ -f "$seen" ]] && seen_id="$(head -1 "$seen" 2>/dev/null | tr -d '[:space:]')"

  local total_lines
  total_lines="$(wc -l < "$ledger" 2>/dev/null | tr -d '[:space:]')"
  [[ -z "$total_lines" || "$total_lines" -eq 0 ]] && return 0

  local unseen_count=0
  local newest_id=""
  local seen_reached=0
  if [[ -z "$seen_id" ]]; then
    unseen_count="$total_lines"
  else
    # Count lines AFTER the last occurrence of the seen id (newest-unseen
    # entries are the ones appended after the seen marker was last set).
    local line_no seen_line_no=0
    line_no=0
    while IFS= read -r line; do
      line_no=$((line_no + 1))
      if printf '%s' "$line" | grep -qF "\"id\":\"${seen_id}\""; then
        seen_line_no="$line_no"
      fi
    done < "$ledger"
    unseen_count=$((total_lines - seen_line_no))
  fi

  [[ "$unseen_count" -le 0 ]] && { newest_id="$(tail -1 "$ledger" | _hcl_extract_id_from_stdin_line)"; [[ -n "$newest_id" ]] && printf '%s\n' "$newest_id" > "$seen"; return 0; }

  newest_id="$(tail -1 "$ledger")"
  newest_id="$(printf '%s' "$newest_id" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"

  echo "harness changes since your last session: ${unseen_count} new -> harness-changelog.sh --list"

  # Advance the seen-marker to the newest entry so this does not repeat.
  [[ -n "$newest_id" ]] && printf '%s\n' "$newest_id" > "$seen"
  return 0
}

_hcl_extract_id_from_stdin_line() {
  local line
  line="$(cat)"
  printf '%s' "$line" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p'
}

# ----------------------------------------------------------------------
# hcl_list [--all]
# ----------------------------------------------------------------------
hcl_list() {
  local show_all=0
  [[ "${1:-}" == "--all" ]] && show_all=1

  local ledger seen
  ledger="$(_hcl_ledger_path)"
  seen="$(_hcl_seen_path)"
  [[ -f "$ledger" ]] || { echo "(no changelog entries)"; return 0; }

  local seen_id=""
  [[ "$show_all" -eq 0 && -f "$seen" ]] && seen_id="$(head -1 "$seen" 2>/dev/null | tr -d '[:space:]')"

  local past_seen=1
  if [[ -n "$seen_id" ]]; then
    past_seen=0
  fi

  local -a lines=()
  while IFS= read -r line; do
    lines+=("$line")
  done < "$ledger"

  local i
  for (( i=${#lines[@]}-1; i>=0; i-- )); do
    local line="${lines[$i]}"
    local ts text
    ts="$(_hcl_json_field "$line" "ts")"
    text="$(_hcl_json_field "$line" "text")"
    echo "[$ts] $text"
    if [[ -n "$seen_id" ]] && printf '%s' "$line" | grep -qF "\"id\":\"${seen_id}\""; then
      break
    fi
  done
}

# ============================================================
# --self-test
# ============================================================
run_self_test() {
  export HARNESS_SELFTEST=1
  local PASSED=0 FAILED=0
  # NOT local: the EXIT trap fires after this function's scope is gone
  # (same pattern note as manifest-check.sh / plan-edit-validator.sh).
  TMPROOT="$(mktemp -d 2>/dev/null || mktemp -d -t hclself)"
  trap 'rm -rf "$TMPROOT"' EXIT

  local LEDGER="$TMPROOT/changelog.jsonl"
  local SEEN="$TMPROOT/seen-marker"

  # S1 — append writes an entry
  OUT="$(HARNESS_CHANGELOG_PATH="$LEDGER" HARNESS_CHANGELOG_SEEN_PATH="$SEEN" bash "$0" append --text "capability A shipped" --runbook "docs/runbooks/a.md" 2>&1)"
  if [[ -f "$LEDGER" ]] && grep -q "capability A shipped" "$LEDGER"; then
    echo "self-test (s1-append-writes-entry): PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (s1-append-writes-entry): FAIL: $OUT" >&2; FAILED=$((FAILED+1))
  fi

  # S2 — re-appending identical text is idempotent (no duplicate line)
  HARNESS_CHANGELOG_PATH="$LEDGER" HARNESS_CHANGELOG_SEEN_PATH="$SEEN" bash "$0" append --text "capability A shipped" --runbook "docs/runbooks/a.md" >/dev/null 2>&1
  LINE_COUNT="$(wc -l < "$LEDGER" | tr -d '[:space:]')"
  if [[ "$LINE_COUNT" == "1" ]]; then
    echo "self-test (s2-idempotent-reappend): PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (s2-idempotent-reappend): FAIL (line count $LINE_COUNT, expected 1)" >&2; FAILED=$((FAILED+1))
  fi

  # S3 — digest-line reports 1 unseen entry when nothing has been seen yet
  rm -f "$SEEN"
  OUT3="$(HARNESS_CHANGELOG_PATH="$LEDGER" HARNESS_CHANGELOG_SEEN_PATH="$SEEN" bash "$0" --digest-line 2>&1)"
  if echo "$OUT3" | grep -q "1 new"; then
    echo "self-test (s3-digest-line-reports-unseen): PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (s3-digest-line-reports-unseen): FAIL: $OUT3" >&2; FAILED=$((FAILED+1))
  fi

  # S4 — after digest-line runs once, a second call reports NOTHING (seen-marker advanced)
  OUT4="$(HARNESS_CHANGELOG_PATH="$LEDGER" HARNESS_CHANGELOG_SEEN_PATH="$SEEN" bash "$0" --digest-line 2>&1)"
  if [[ -z "$OUT4" ]]; then
    echo "self-test (s4-digest-line-silent-after-seen): PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (s4-digest-line-silent-after-seen): FAIL: got '$OUT4'" >&2; FAILED=$((FAILED+1))
  fi

  # S5 — a NEW append after seen-marker is advanced is reported again
  HARNESS_CHANGELOG_PATH="$LEDGER" HARNESS_CHANGELOG_SEEN_PATH="$SEEN" bash "$0" append --text "capability B shipped" >/dev/null 2>&1
  OUT5="$(HARNESS_CHANGELOG_PATH="$LEDGER" HARNESS_CHANGELOG_SEEN_PATH="$SEEN" bash "$0" --digest-line 2>&1)"
  if echo "$OUT5" | grep -q "1 new"; then
    echo "self-test (s5-new-entry-reported-after-prior-seen): PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (s5-new-entry-reported-after-prior-seen): FAIL: $OUT5" >&2; FAILED=$((FAILED+1))
  fi

  # S6 — empty ledger produces no digest line
  local EMPTY_LEDGER="$TMPROOT/empty.jsonl"
  local EMPTY_SEEN="$TMPROOT/empty-seen"
  OUT6="$(HARNESS_CHANGELOG_PATH="$EMPTY_LEDGER" HARNESS_CHANGELOG_SEEN_PATH="$EMPTY_SEEN" bash "$0" --digest-line 2>&1)"
  if [[ -z "$OUT6" ]]; then
    echo "self-test (s6-empty-ledger-silent): PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (s6-empty-ledger-silent): FAIL: got '$OUT6'" >&2; FAILED=$((FAILED+1))
  fi

  # S7 — append requires --text
  OUT7="$(HARNESS_CHANGELOG_PATH="$LEDGER" HARNESS_CHANGELOG_SEEN_PATH="$SEEN" bash "$0" append 2>&1)"
  RC7=$?
  if [[ "$RC7" -ne 0 ]]; then
    echo "self-test (s7-append-requires-text): PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (s7-append-requires-text): FAIL (rc=$RC7)" >&2; FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed" >&2
  [[ "$FAILED" -gt 0 ]] && return 1
  return 0
}

# ============================================================
# main
# ============================================================
case "${1:-}" in
  --self-test)
    run_self_test
    exit $?
    ;;
  append)
    shift
    hcl_append "$@"
    exit $?
    ;;
  --digest-line)
    hcl_digest_line
    exit 0
    ;;
  --list)
    shift
    hcl_list "${1:-}"
    exit 0
    ;;
  *)
    echo "usage: harness-changelog.sh append --text <str> [--runbook <path>] | --digest-line | --list [--all] | --self-test" >&2
    exit 2
    ;;
esac
