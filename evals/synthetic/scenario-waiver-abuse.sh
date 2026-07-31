#!/usr/bin/env bash
# Synthetic Scenario: waiver-abuse
#
# Exercises work-integrity-gate.sh's shared waiver-validation unit,
# `_wig_check_waiver` (ADR 059 D4 "same shape everywhere": fresh <1h +
# substantive non-empty first line, honored identically by every waiver
# family this hook reads). Two abuse shapes must be REJECTED and one
# legitimate shape must be HONORED:
#
#   (bad 1) stale waiver: a substantive, non-empty waiver file older than
#           1 hour -> NOT honored (echoes NO_WAIVER; the `-newermt '1 hour
#           ago'` freshness filter excludes it entirely).
#   (bad 2) empty-reason waiver: a fresh (<1h) waiver file with zero
#           non-whitespace content -> NOT honored as a clean pass
#           (echoes EMPTY_WAIVER, distinct from a valid waiver, so callers
#           fall through to the block).
#   (good)  fresh (<1h) waiver file with a substantive first line ->
#           HONORED (echoes VALID_WAIVER:<path>).
#
# Extraction method: `_wig_check_waiver` is a small function that cannot
# be invoked standalone by sourcing work-integrity-gate.sh directly --
# that file unconditionally falls through to `_wig_main` (a real `exit`)
# when sourced with no `--self-test` arg. This scenario therefore extracts
# the function's CURRENT source text verbatim (sed, by its own def/end
# markers) from the live file at run time and sources only that -- proof
# against the real unit, not a hand-copied duplicate that could drift.
# It ALSO sources lib/waiver-purpose-clause.sh first, exactly as the live
# hook does (work-integrity-gate.sh:95): since ADR 058 D5 pin (f) /
# specs-e §E.10 item 2, `_wig_check_waiver` calls `waiver_has_purpose_clauses`
# from that lib, so the extracted function has that dependency.
#
# Expected (post-pin-f taxonomy): stale -> NO_WAIVER; empty-reason ->
# EMPTY_WAIVER; fresh substantive but MISSING the two purpose clauses ->
# WEAK_WAIVER (the pin-f abuse shape); fresh substantive WITH both purpose
# clauses -> VALID_WAIVER:<path> (honored).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WIG="$NL_ROOT/adapters/claude-code/hooks/work-integrity-gate.sh"

if [[ ! -f "$WIG" ]]; then
  echo "FAIL: work-integrity-gate.sh not found at $WIG"
  exit 1
fi

FAILS=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Extract _wig_check_waiver's current source verbatim (function def
# through its closing brace) from the live hook file.
EXTRACTED="$TMP/wig-check-waiver-extracted.sh"
sed -n '/^_wig_check_waiver()[[:space:]]*{/,/^}/p' "$WIG" > "$EXTRACTED"

if ! grep -q '^_wig_check_waiver()' "$EXTRACTED"; then
  echo "FAIL: could not extract _wig_check_waiver from $WIG (function signature not found -- has it been renamed?)"
  exit 1
fi

# Source the purpose-clause lib first (the live hook does this at
# work-integrity-gate.sh:95): pin (f) made _wig_check_waiver depend on
# waiver_has_purpose_clauses. Sourcing only the extracted function without
# its lib dependency is not "proof against the real unit" -- the real unit
# runs with the lib loaded.
PURPOSE_LIB="$NL_ROOT/adapters/claude-code/hooks/lib/waiver-purpose-clause.sh"
if [[ ! -f "$PURPOSE_LIB" ]]; then
  echo "FAIL: waiver-purpose-clause.sh not found at $PURPOSE_LIB (pin-f dependency of _wig_check_waiver)"
  exit 1
fi
# shellcheck disable=SC1090
source "$PURPOSE_LIB"

# shellcheck disable=SC1090
source "$EXTRACTED"

_backdate() {
  local file="$1" spec="$2"
  touch -d "$spec" "$file" 2>/dev/null \
    || touch -t "$(date -d "$spec" +%Y%m%d%H%M 2>/dev/null || echo 197001010000)" "$file" 2>/dev/null \
    || true
}

STATE_DIR="$TMP/.claude/state"
mkdir -p "$STATE_DIR"

# ---- Bad case 1: stale (>1h) substantive waiver -> NOT honored ----
STALE_FILE="$STATE_DIR/work-integrity-waiver-stale-slug-1000.txt"
echo "This waiver is substantive but was written over an hour ago." > "$STALE_FILE"
_backdate "$STALE_FILE" "2 hours ago"

RESULT=$(_wig_check_waiver "stale-slug" "work-integrity-waiver" "$STATE_DIR")
if [[ "$RESULT" == "NO_WAIVER" ]]; then
  echo "PASS: stale (>1h) waiver was correctly rejected (result=$RESULT)"
else
  echo "FAIL: stale (>1h) waiver should have been rejected as NO_WAIVER (result=$RESULT)"
  FAILS=$((FAILS + 1))
fi

# ---- Bad case 2: fresh but empty-reason waiver -> NOT honored as valid ----
EMPTY_FILE="$STATE_DIR/work-integrity-waiver-empty-slug-2000.txt"
: > "$EMPTY_FILE"

RESULT=$(_wig_check_waiver "empty-slug" "work-integrity-waiver" "$STATE_DIR")
if [[ "$RESULT" == "EMPTY_WAIVER" ]]; then
  echo "PASS: fresh empty-reason waiver was correctly rejected as EMPTY_WAIVER (result=$RESULT)"
else
  echo "FAIL: fresh empty-reason waiver should have been rejected as EMPTY_WAIVER (result=$RESULT)"
  FAILS=$((FAILS + 1))
fi

# ---- Bad case 3 (pin-f): fresh + substantive but MISSING the two purpose
#      clauses -> NOT honored as a clean pass (WEAK_WAIVER). This is the
#      abuse shape ADR 058 D5 pin (f) added: a substantive-looking waiver
#      that never engages the gate's purpose. ----
WEAK_FILE="$STATE_DIR/work-integrity-waiver-weak-slug-2500.txt"
echo "Open tasks legitimately continue in another session per the program's orchestrator plan." > "$WEAK_FILE"

RESULT=$(_wig_check_waiver "weak-slug" "work-integrity-waiver" "$STATE_DIR")
if [[ "$RESULT" == "WEAK_WAIVER:${WEAK_FILE}" ]]; then
  echo "PASS: fresh substantive waiver LACKING purpose clauses was correctly downgraded (result=$RESULT)"
else
  echo "FAIL: fresh substantive-but-no-purpose-clause waiver should be WEAK_WAIVER:${WEAK_FILE} (result=$RESULT)"
  FAILS=$((FAILS + 1))
fi

# ---- Good case: fresh (<1h) waiver, substantive, WITH both pin-f purpose
#      clauses -> honored (VALID_WAIVER:<path>). ----
FRESH_FILE="$STATE_DIR/work-integrity-waiver-fresh-slug-3000.txt"
cat > "$FRESH_FILE" <<'WAIVER'
This gate exists to prevent a session from ending with a touched plan's work silently dropped.
That does not apply here because the open tasks are future-wave work in a multi-session orchestrator program, legitimately continuing in another session.
WAIVER

RESULT=$(_wig_check_waiver "fresh-slug" "work-integrity-waiver" "$STATE_DIR")
if [[ "$RESULT" == "VALID_WAIVER:${FRESH_FILE}" ]]; then
  echo "PASS: fresh substantive waiver with purpose clauses was correctly honored (result=$RESULT)"
else
  echo "FAIL: fresh substantive waiver with purpose clauses should have been honored as VALID_WAIVER:${FRESH_FILE} (result=$RESULT)"
  FAILS=$((FAILS + 1))
fi

if [[ "$FAILS" -eq 0 ]]; then
  echo "scenario-waiver-abuse: ALL PASSED"
  exit 0
fi
echo "scenario-waiver-abuse: $FAILS FAILURE(S)"
exit 1
