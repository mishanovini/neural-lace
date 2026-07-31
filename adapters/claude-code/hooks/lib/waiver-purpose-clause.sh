# waiver-purpose-clause.sh — shared purpose-clause waiver validator
# (ADR 058 D5 pin f, specs-e §E.10 item 2).
#
# ============================================================
# WHAT THIS LIB DOES
# ============================================================
#
# Pin (f) requires every waiver-accepting check to validate TWO named
# clauses before honoring a waiver file as an escape hatch:
#
#   (a) "this gate exists to prevent X"      — the agent names the
#       purpose of the gate it is waiving.
#   (b) "that does not apply here because Y" — the agent names why
#       that purpose does not apply to this specific situation.
#
# Making consideration of the gate's purpose the MECHANICAL precondition
# of waiving is the point: a waiver that only proves "a file exists" or
# "a file has >=1 non-empty line" (the pre-pin-f shape every waiver
# reader in this repo used) is satisfiable by a stray `touch` or a
# one-word placeholder — exactly the documented-constraint-not-enforced
# theater class NL-FINDING-026 class 1 flagged for check (c)'s teardown
# waiver, generalized here to every waiver reader.
#
# ============================================================
# RECOGNIZED CLAUSE SHAPES
# ============================================================
#
# A waiver file satisfies pin (f) when it contains, anywhere in its
# text (case-insensitive, one or more non-whitespace characters after
# the colon on the SAME logical clause):
#
#   - a "prevent" clause:   matches /this gate exists to prevent/i
#                           OR a line starting "Purpose:" / "Prevents:"
#   - a "does not apply" clause: matches /does(n'?t| not) apply here
#                           because/i OR a line starting
#                           "Not applicable:" / "Because:"
#
# Both must be present with non-empty content following the marker.
# This is deliberately pattern-flexible (not a single rigid template)
# so existing waiver-writing muscle memory across the harness's many
# waiver call sites doesn't all need to learn one exact phrase — the
# MECHANICAL bar is "both clauses considered", not "one exact string".
#
# ============================================================
# USAGE
# ============================================================
#
#   source ".../lib/waiver-purpose-clause.sh"
#   if waiver_has_purpose_clauses "/path/to/waiver-file.txt"; then
#     ... honor the waiver ...
#   else
#     ... reject: "waiver exists but lacks the purpose-clause pair" ...
#   fi
#
# Fails CLOSED (returns 1 / false) on a missing file, empty file, or a
# file missing either clause — never silently accepts a bare-existence
# waiver. This is a NEW, STRICTER bar than the pre-pin-f behavior by
# design; callers retrofitting this lib should keep their OWN freshness
# (mtime) and non-empty checks as a pre-filter (this lib does not
# duplicate freshness logic — that stays per-caller since the mtime
# window differs by gate).

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_WAIVER_PURPOSE_CLAUSE_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_WAIVER_PURPOSE_CLAUSE_SOURCED=1

# ----------------------------------------------------------------------
# waiver_has_purpose_clauses <path>
#
# Returns 0 (true) iff the file exists, is readable, and contains BOTH
# the "prevent" clause and the "does not apply because" clause, each
# with non-empty content. Returns 1 otherwise.
# ----------------------------------------------------------------------
waiver_has_purpose_clauses() {
  local f="$1"
  [[ -f "$f" && -r "$f" ]] || return 1

  local content
  content=$(cat "$f" 2>/dev/null)
  [[ -z "$content" ]] && return 1

  local has_prevent=0 has_not_apply=0

  # Clause (a): "this gate exists to prevent X" (free-form) OR a
  # Purpose:/Prevents: labeled line with non-empty content after it.
  if printf '%s' "$content" | grep -qiE 'this (gate|check) exists to prevent[[:space:]]+[^[:space:]]'; then
    has_prevent=1
  elif printf '%s' "$content" | grep -qiE '^[[:space:]]*(purpose|prevents?)[[:space:]]*:[[:space:]]*[^[:space:]]'; then
    has_prevent=1
  fi

  # Clause (b): "that does not apply here because Y" (free-form) OR a
  # Because:/Not applicable: labeled line with non-empty content after it.
  if printf '%s' "$content" | grep -qiE "(does(nt| not) apply here because)[[:space:]]+[^[:space:]]"; then
    has_not_apply=1
  elif printf '%s' "$content" | grep -qiE '^[[:space:]]*(because|not[[:space:]]applicable)[[:space:]]*:[[:space:]]*[^[:space:]]'; then
    has_not_apply=1
  fi

  [[ "$has_prevent" -eq 1 && "$has_not_apply" -eq 1 ]]
}

# ----------------------------------------------------------------------
# waiver_purpose_clause_help <gate-purpose-example>
#
# Echoes a standard remediation stanza callers can embed in their block
# messages when a waiver exists but fails the purpose-clause bar. Keeps
# the exact required shape consistent across every gate that adopts it
# (pin d: "the exact copy-pasteable next command/edit").
# ----------------------------------------------------------------------
waiver_purpose_clause_help() {
  local example="${1:-<why this gate purpose does not apply here>}"
  cat <<EOF
A waiver file exists but does not name BOTH required clauses. Every
waiver must state (in any order, anywhere in the file):
  1. Purpose: this gate exists to prevent <X>
  2. Because: that does not apply here because <Y>
Example:
  Purpose: this gate exists to prevent unreviewed WIP from being lost
  Because: ${example}
EOF
}

# ----------------------------------------------------------------------
# --self-test
# ----------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0; FAILED=0
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t wpcst)
  trap 'rm -rf "$TMP"' EXIT

  ok() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  no() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  echo "Scenario 1: both clauses (free-form) -> valid"
  printf 'This gate exists to prevent unreviewed WIP loss.\nThat does not apply here because the work is already merged upstream.\n' > "$TMP/s1.txt"
  waiver_has_purpose_clauses "$TMP/s1.txt" && ok "free-form both clauses valid" || no "expected valid"

  echo "Scenario 2: both clauses (labeled) -> valid"
  printf 'Purpose: prevent silent data loss on teardown\nBecause: this worktree is intentionally kept for a follow-up session\n' > "$TMP/s2.txt"
  waiver_has_purpose_clauses "$TMP/s2.txt" && ok "labeled both clauses valid" || no "expected valid"

  echo "Scenario 3: only prevent-clause -> invalid"
  printf 'This gate exists to prevent unreviewed WIP loss.\n' > "$TMP/s3.txt"
  waiver_has_purpose_clauses "$TMP/s3.txt" && no "expected invalid (missing because-clause)" || ok "prevent-only rejected"

  echo "Scenario 4: only because-clause -> invalid"
  printf 'Because: this is a harness-dev fixture with no user-facing surface.\n' > "$TMP/s4.txt"
  waiver_has_purpose_clauses "$TMP/s4.txt" && no "expected invalid (missing prevent-clause)" || ok "because-only rejected"

  echo "Scenario 5: existence-only stray touch -> invalid"
  : > "$TMP/s5.txt"
  waiver_has_purpose_clauses "$TMP/s5.txt" && no "expected invalid (empty file)" || ok "empty file rejected"

  echo "Scenario 6: non-empty but no clauses -> invalid"
  printf 'ok fine whatever\n' > "$TMP/s6.txt"
  waiver_has_purpose_clauses "$TMP/s6.txt" && no "expected invalid (no clauses)" || ok "content-without-clauses rejected"

  echo "Scenario 7: missing file -> invalid"
  waiver_has_purpose_clauses "$TMP/does-not-exist.txt" && no "expected invalid (missing file)" || ok "missing file rejected"

  echo "Scenario 8: clause labels with empty content -> invalid"
  printf 'Purpose:\nBecause:\n' > "$TMP/s8.txt"
  waiver_has_purpose_clauses "$TMP/s8.txt" && no "expected invalid (empty clause content)" || ok "empty-labeled-clauses rejected"

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  [[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
fi
