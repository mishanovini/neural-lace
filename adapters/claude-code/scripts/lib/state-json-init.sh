#!/usr/bin/env bash
# state-json-init.sh — shared VALIDITY-guarded JSON state-file initializer.
#
# This is a library — source it; do not invoke directly.
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# Incident (2026-07-27): ~/.claude/state/needs-you/ledger.json — the
# canonical "what is waiting on the operator" ledger — sat as a 1-byte file
# containing a single newline for roughly two days. GET /api/inbox returned
# `{"ok":false,"error":"ledger.json is not valid JSON: Unexpected end of
# JSON input"}` the entire time; the cockpit rendered it as a confident
# "nothing on your list."
#
# Root cause: needs-you.sh's own lazy-init guard tested EXISTENCE, not
# VALIDITY —
#     [[ -f "$f" ]] || echo '{"schema_version":1,"items":[]}' > "$f"
# — so once ANY process left a present-but-unparseable file behind, the
# guard never fired again and every subsequent `jq` read failed forever.
# The truncating write itself was traced to a separate, now-fixed bug (see
# needs-you.sh cmd_add's `--args -- "${links[@]}"` fix and its header note
# "WRITE SAFETY" / "BASH 3.2" for the full mechanism) — but the existence-
# only guard is why the damage was PERMANENT instead of self-healing on the
# next write.
#
# This helper is the class-level fix: replace "does the file exist" with
# "does the file exist AND parse as JSON" everywhere a JSON ledger/state
# file is lazily initialized, harness-wide — not just in needs-you.sh.
#
# ============================================================
# CONTRACT
# ============================================================
#
#   nl_state_json_ensure <file> <default-json>
#     Ensures <file> exists and is parseable JSON, mkdir -p'ing its parent
#     directory first. Three cases:
#       1. ABSENT            -> write <default-json>, exit 0.
#       2. PRESENT + VALID   -> no-op (this is the common, fast path), exit 0.
#       3. PRESENT + INVALID (empty, truncated, or unparseable JSON) ->
#          SALVAGE first (constitution §9 "salvage before reset" — never
#          destroy evidence): copy the original bytes to
#          "<file>.corrupt-<UTC-date>.bak" (a numeric suffix is appended if
#          that path is already taken, e.g. two corruptions on the same
#          calendar day), print a loud stderr notice naming exactly what
#          happened and where the evidence went, THEN write <default-json>.
#          Exit 0 (recovery completed).
#     Exit 1 only on a genuine write failure (unwritable directory, mktemp
#     failure, etc.) — the same class of failure callers already treat as
#     fatal via their own die().
#
#     The write itself is always tmp-file-then-atomic-mv (never a direct
#     truncating `>` onto the real path), so a crash mid-write can never
#     leave the target file torn.
#
# ============================================================
# PORTABILITY FLOOR
# ============================================================
#
# bash 3.2-safe (this repo's hard constraint — macOS ships /bin/bash 3.2.57,
# no declare -A, no ${var^^}, no GNU-only sed -i, no `date -d`). Requires
# `jq` (already a hard dependency of every caller of this helper) and `cp`,
# `mkdir`, `mktemp`, `mv`, `date` — all POSIX/BSD-and-GNU-compatible calls
# only.
#
# ============================================================

set -u

# nl_state_json_ensure <file> <default-json>
nl_state_json_ensure() {
  local file="$1" default_json="$2"

  if [[ -z "$file" ]]; then
    echo "state-json-init: nl_state_json_ensure called with empty file path" >&2
    return 1
  fi

  local dir; dir="$(dirname "$file")"
  mkdir -p "$dir" 2>/dev/null || {
    echo "state-json-init: cannot create parent dir for $file: $dir" >&2
    return 1
  }

  if [[ ! -f "$file" ]]; then
    _nl_sji_write_default "$file" "$default_json" && return 0
    return 1
  fi

  # Present — validate. DELIBERATELY NOT `jq empty` here: `jq empty` on a
  # whitespace-only file (a 0-byte file, or the incident's exact 1-byte
  # "\n") is jq's streaming parser seeing ZERO JSON documents, which `empty`
  # treats as a trivial, vacuous success (exit 0) — it would have called
  # the incident's own corrupt file "valid" and never recovered it. `jq -e
  # "type"` is the correct test: it requires jq to actually PRODUCE a JSON
  # value (any type, including top-level `false`/`null`, which `-e` alone
  # would otherwise mistreat as "invalid" via its truthiness rule — `type`
  # maps every value to a truthy type-name string, sidestepping that) and
  # fails with a distinct nonzero exit for both "no input" (whitespace/empty
  # — exit 4) and "malformed input" (parse error — exit 5). Verified
  # against exactly this incident's fixture during development.
  if jq -e 'type' "$file" >/dev/null 2>&1; then
    return 0   # present AND valid — no-op, the common/fast path.
  fi

  # Invalid: salvage the original bytes BEFORE resetting (constitution §9,
  # "salvage before reset" — a silent re-init that discards real operator
  # state is a worse bug than the corruption it's fixing).
  local today; today="$(date -u +%Y-%m-%d 2>/dev/null)"
  [[ -n "$today" ]] || today="unknown-date"
  local bak="${file}.corrupt-${today}.bak"
  local n=2
  while [[ -e "$bak" ]]; do
    bak="${file}.corrupt-${today}-${n}.bak"
    n=$((n + 1))
  done
  cp "$file" "$bak" 2>/dev/null

  local size_desc
  size_desc="$(wc -c < "$file" 2>/dev/null | tr -d ' ')"
  echo "state-json-init: RECOVERED corrupt state file $file (was present but invalid JSON — ${size_desc:-?} byte(s), empty-or-unparseable). Original bytes preserved at $bak. Resetting to default skeleton. This file was silently unreadable by every jq-based reader until this call — check $bak for what may have been lost." >&2

  _nl_sji_write_default "$file" "$default_json" && return 0
  return 1
}

# _nl_sji_write_default <file> <content> — atomic tmp-then-mv write. Internal.
_nl_sji_write_default() {
  local file="$1" content="$2"
  local tmp
  tmp=$(mktemp "${file}.XXXXXX" 2>/dev/null) || {
    echo "state-json-init: mktemp failed for $file" >&2
    return 1
  }
  printf '%s\n' "$content" > "$tmp" 2>/dev/null || {
    rm -f "$tmp"
    echo "state-json-init: write to tmpfile failed for $file" >&2
    return 1
  }
  mv "$tmp" "$file" 2>/dev/null || {
    rm -f "$tmp"
    echo "state-json-init: atomic rename failed for $file" >&2
    return 1
  }
  return 0
}
