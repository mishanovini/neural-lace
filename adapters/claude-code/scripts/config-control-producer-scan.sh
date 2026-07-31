#!/bin/bash
# config-control-producer-scan.sh
#
# Generalizes the "decorative config control" vaporware class (FM-038,
# HARNESS-GAP-45, doctrine/vaporware-prevention.md) to its INVERSE shape.
#
# The original registry-vs-callsite invariant (vaporware-prevention-full.md)
# checks one direction: does a registry entry (permission ID, feature flag)
# have an enforce-mode CONSUMER. It structurally assumes the other half --
# the PRODUCER -- is guaranteed, because a UI toggle's producer is the user
# clicking it. That assumption fails for config levers with no UI: env
# vars, CLI overrides, caller-set flags read deep in library code. Those
# can be faithfully CONSUMED (the read site is real, the branch is real)
# while having ZERO producers anywhere -- so the branch never fires in
# production. Same vaporware effect (a documented lever that does nothing),
# opposite missing half.
#
# Golden scenario (HARNESS-GAP-57, 2026-07-29): NL_PROTECTED_ORCHESTRATOR,
# documented in hooks/lib/admission-lib.sh as the tag a "protected
# downstream orchestrator" must set so its traffic isn't learned from
# during a chronic-storm period -- discovered (accountable-estate T7,
# task-verifier pass 4, D-4) to have ZERO producers anywhere in the repo:
# "all 888 live ledger rows... [carry] protected=0". Nothing in the
# existing anti-vaporware enforcement would have caught this before a
# task-verifier pass happened to read the comment narratively -- it isn't
# a registry+UI surface (functionality-auditor's remit) and no
# `Verification: full` task ever claimed "this flag governs behavior"
# (functionality-verifier's config-control protocol trigger). This script
# makes that catch mechanical and repeatable, without adding a new
# blocking PreToolUse hook (see D-2 in docs/plans/archive/
# vaporware-config-controls.md: a new gate needs a golden scenario + FP
# rate + retirement condition, constitution Sec 10; this ships as a
# standing, self-testing, deterministic sweep first -- CI/blocking wiring
# is the natural escalation once its false-positive rate is proven low
# in practice, per the fields below).
#
# ============================================================
# Classification (per consumed <PREFIX>_* var found in the scan roots):
#   PRODUCED     -- a real, standalone assignment (`VAR=` / `export VAR=`)
#                   exists somewhere in the scan roots.
#   MARKED       -- no producer, but the file(s) where it's read carry an
#                   explicit honest-status marker (the convention this
#                   script's golden scenario now uses; see MARKER_REGEX).
#   ALLOWLISTED  -- no producer, no marker, but the var has a justified
#                   entry in config/config-control-allowlist.txt (the
#                   documented-external-producer carve-out: operator-shell
#                   / self-test-only overrides where an in-repo producer
#                   is not expected by design).
#   FLAGGED      -- none of the above. A consumed lever with no proof
#                   anything, ever, sets it. This is the vaporware shape.
#
# Exit codes:
#   0 -- no FLAGGED vars.
#   1 -- at least one FLAGGED var (report lists them).
#   2 -- self-test failure.
#
# Constitution Sec 10 fields (this check, today):
#   - Golden scenario: NL_PROTECTED_ORCHESTRATOR pre-annotation state (see
#     Scenario 4 in --self-test): consumed, zero producer, zero marker,
#     zero allowlist entry -> FLAGGED. Post-annotation state (today's real
#     admission-lib.sh) -> MARKED, not flagged (Scenario 5).
#   - Expected false-positive rate: 0% against the CURRENT repo (Scenario
#     6 runs the real scan over the real hooks/ + scripts/ trees and
#     asserts zero FLAGGED; the 7 pre-existing operator-shell / self-test
#     override vars found during construction of this check -- e.g.
#     NL_CHECKOUT_OVERRIDE, NL_SPAWN_PROCESS_COUNT_OVERRIDE -- are all
#     accounted for in config/config-control-allowlist.txt with per-entry
#     justification, not blanket-suppressed). A future FP would be a var
#     that IS externally producer-only by design but lacks an allowlist
#     entry -- the fix is a one-line allowlist addition, not a code change.
#   - Retirement condition: if this scan's FLAGGED classification proves
#     wrong on a var that turns out to have a real producer this script's
#     regex can't see (e.g. a producer assigned via indirect `${!name}`
#     dereference or sourced from a non-.sh file), that recurrence is the
#     evidence to either extend the producer regex (amendment) or retire
#     the check in favor of the runtime audit-log approach HARNESS-GAP-39
#     proposes for the same "wired but never exercised" class.
#
# Doctrine: doctrine/vaporware-prevention.md / -full.md
# Failure mode: docs/failure-modes.md FM-038
# Backlog: docs/backlog.md HARNESS-GAP-57

set -u

SCRIPT="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
CC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VAR_PREFIX="${CCPS_VAR_PREFIX:-NL_}"
ALLOWLIST_FILE="${CCPS_ALLOWLIST:-$CC_DIR/config/config-control-allowlist.txt}"
# shellcheck disable=SC2206
SCAN_ROOTS=(${CCPS_SCAN_ROOTS:-"$CC_DIR/hooks" "$CC_DIR/scripts"})

MARKER_REGEX='HONEST STATUS|no producer sets|NO producer sets|not-yet-wired|NOT-YET-WIRED'

# ============================================================
# --self-test
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  FIXTURE_ROOT="$CC_DIR/tests/config-control-producer-scan"
  if [[ ! -d "$FIXTURE_ROOT" ]]; then
    echo "self-test: fixture dir missing at $FIXTURE_ROOT" >&2
    exit 2
  fi

  SELFBASH="${BASH:-bash}"
  FAILED=0

  run_scenario() {
    local name="$1" scan_dir="$2" allowlist="$3" expect_exit="$4" expect_grep="$5" label="$6"
    local actual_out actual_rc
    actual_out=$(CCPS_SCAN_ROOTS="$scan_dir" CCPS_ALLOWLIST="$allowlist" \
      "$SELFBASH" "$SCRIPT" 2>&1)
    actual_rc=$?
    if [[ "$actual_rc" -ne "$expect_exit" ]]; then
      echo "self-test ($name) [$label]: exit=$actual_rc expected=$expect_exit" >&2
      echo "--- output ---" >&2
      echo "$actual_out" >&2
      FAILED=1
      return
    fi
    if [[ -n "$expect_grep" ]] && ! printf '%s' "$actual_out" | grep -qE "$expect_grep"; then
      echo "self-test ($name) [$label]: output missing expected pattern: $expect_grep" >&2
      echo "--- output ---" >&2
      echo "$actual_out" >&2
      FAILED=1
      return
    fi
    echo "self-test ($name) [$label]: PASS" >&2
  }

  EMPTY_ALLOWLIST="$FIXTURE_ROOT/empty-allowlist.txt"

  run_scenario "produced" \
    "$FIXTURE_ROOT/produced" "$EMPTY_ALLOWLIST" 0 \
    'PRODUCED[[:space:]]+NL_FIXTURE_PRODUCED' \
    "real producer -> PRODUCED, exit 0"

  run_scenario "marked" \
    "$FIXTURE_ROOT/marked" "$EMPTY_ALLOWLIST" 0 \
    'MARKED[[:space:]]+NL_FIXTURE_MARKED' \
    "honest-status marker, no producer -> MARKED, exit 0"

  run_scenario "flagged" \
    "$FIXTURE_ROOT/flagged" "$EMPTY_ALLOWLIST" 1 \
    'FLAGGED[[:space:]]+NL_FIXTURE_FLAGGED' \
    "consumed, no producer, no marker, no allowlist -> FLAGGED, exit 1 (golden scenario: pre-fix NL_PROTECTED_ORCHESTRATOR shape)"

  run_scenario "allowlisted" \
    "$FIXTURE_ROOT/flagged" "$FIXTURE_ROOT/covering-allowlist.txt" 0 \
    'ALLOWLISTED[[:space:]]+NL_FIXTURE_FLAGGED' \
    "same var as scenario 3, now allowlisted with justification -> ALLOWLISTED, exit 0 (RED->GREEN: same fixture, only the allowlist changed)"

  run_scenario "golden-post-fix-shape" \
    "$FIXTURE_ROOT/golden-nl-protected-orchestrator-post-fix" "$EMPTY_ALLOWLIST" 0 \
    'MARKED[[:space:]]+NL_PROTECTED_ORCHESTRATOR' \
    "reproduction of the real admission-lib.sh HONEST STATUS annotation -> MARKED, exit 0"

  run_scenario "golden-pre-fix-shape" \
    "$FIXTURE_ROOT/golden-nl-protected-orchestrator-pre-fix" "$EMPTY_ALLOWLIST" 1 \
    'FLAGGED[[:space:]]+NL_PROTECTED_ORCHESTRATOR' \
    "the SAME read site with the honest-status comment stripped -> FLAGGED, exit 1 (proves the marker, not the var name, is what the scan keys on)"

  # ---- Scenario 7: the real repo, today -- must be all-clean ----
  real_out=$("$SELFBASH" "$SCRIPT" 2>&1)
  real_rc=$?
  if [[ "$real_rc" -ne 0 ]]; then
    echo "self-test (live-repo) [real hooks/+scripts/ trees must have zero FLAGGED today]: exit=$real_rc" >&2
    echo "--- output ---" >&2
    echo "$real_out" >&2
    FAILED=1
  else
    echo "self-test (live-repo) [real hooks/+scripts/ trees must have zero FLAGGED today]: PASS" >&2
  fi

  if [[ "$FAILED" -eq 0 ]]; then
    echo "all self-tests passed" >&2
    exit 0
  else
    echo "self-test failures detected" >&2
    exit 1
  fi
fi

# ============================================================
# Main scan
# ============================================================

# Proximity window (lines) within which an honest-status marker must sit,
# relative to an actual read-site, to count. File-scoped matching (no
# proximity check) was tried first and produced a real false positive:
# a file that merely DISCUSSES a var name in prose, elsewhere in a file
# that also happens to carry a marker phrase for an unrelated reason,
# would wrongly classify as MARKED. Line-proximity closes that.
MARKER_PROXIMITY="${CCPS_MARKER_PROXIMITY:-15}"

find_sh_files() {
  local r self_base
  self_base="$(basename "$SCRIPT")"
  for r in "${SCAN_ROOTS[@]}"; do
    [[ -d "$r" ]] || continue
    find "$r" -type f -name '*.sh' ! -name "$self_base" 2>/dev/null
  done
}

FILE_LIST="$(find_sh_files)"
if [[ -z "$FILE_LIST" ]]; then
  echo "config-control-producer-scan: no .sh files found under scan roots; nothing to check" >&2
  exit 0
fi

CANDIDATES="$(printf '%s\n' "$FILE_LIST" | xargs grep -ohE "\\\$\\{?${VAR_PREFIX}[A-Z0-9_]+" 2>/dev/null \
  | sed -E 's/^\$\{?//' | sort -u)"

if [[ -z "$CANDIDATES" ]]; then
  echo "config-control-producer-scan: no ${VAR_PREFIX}* vars consumed under scan roots; nothing to check" >&2
  exit 0
fi

FLAGGED_COUNT=0
REPORT_LINES=""

# marker_near_read FILE VAR -> 0 (found within proximity) or 1 (not found)
#
# The anchor is ANY mention of the var name (not just its syntactic
# `$VAR`/`${VAR` read form). This matches how this codebase actually
# documents these levers: the real admission-lib.sh honest-status
# comment sits 566 lines from the functional read site (inside a header
# block that NAMES the var), not next to it. Anchoring on the syntactic
# read alone would wrongly FLAG that real, deliberately-annotated case.
# Anchoring on "any mention" keeps the check tight (a marker must still
# sit near where the var is actually discussed) without demanding the
# annotation live at the call site.
marker_near_read() {
  local f="$1" var="$2"
  local mention_lines marker_lines rl ml
  mention_lines="$(grep -n -- "$var" "$f" 2>/dev/null | cut -d: -f1)"
  [[ -z "$mention_lines" ]] && return 1
  marker_lines="$(grep -nE "$MARKER_REGEX" "$f" 2>/dev/null | cut -d: -f1)"
  [[ -z "$marker_lines" ]] && return 1
  while IFS= read -r rl; do
    [[ -z "$rl" ]] && continue
    while IFS= read -r ml; do
      [[ -z "$ml" ]] && continue
      local diff=$((rl - ml))
      [[ $diff -lt 0 ]] && diff=$((-diff))
      if [[ "$diff" -le "$MARKER_PROXIMITY" ]]; then
        return 0
      fi
    done <<< "$marker_lines"
  done <<< "$mention_lines"
  return 1
}

while IFS= read -r var; do
  [[ -z "$var" ]] && continue

  producer_hits="$(printf '%s\n' "$FILE_LIST" | xargs grep -lE "^[[:space:]]*(export[[:space:]]+)?${var}=" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${producer_hits:-0}" -gt 0 ]]; then
    REPORT_LINES="${REPORT_LINES}PRODUCED    ${var}
"
    continue
  fi

  files_with_var="$(printf '%s\n' "$FILE_LIST" | xargs grep -l -- "$var" 2>/dev/null)"
  marker_hit=0
  if [[ -n "$files_with_var" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if marker_near_read "$f" "$var"; then
        marker_hit=1
        break
      fi
    done <<< "$files_with_var"
  fi
  if [[ "$marker_hit" -eq 1 ]]; then
    REPORT_LINES="${REPORT_LINES}MARKED      ${var}
"
    continue
  fi

  if [[ -f "$ALLOWLIST_FILE" ]] && grep -qE "^${var}[[:space:]]" "$ALLOWLIST_FILE" 2>/dev/null; then
    REPORT_LINES="${REPORT_LINES}ALLOWLISTED ${var}
"
    continue
  fi

  REPORT_LINES="${REPORT_LINES}FLAGGED     ${var}
"
  FLAGGED_COUNT=$((FLAGGED_COUNT + 1))
done <<< "$CANDIDATES"

printf '%s' "$REPORT_LINES"
echo "---"

if [[ "$FLAGGED_COUNT" -gt 0 ]]; then
  cat >&2 <<ERR_MSG

[config-control-producer-scan] ${FLAGGED_COUNT} config lever(s) consumed with ZERO producer, honest marker, or allowlist entry.

A lever in this state is read by real code and gates a real branch, but
nothing anywhere ever sets it -- the branch it guards is dead in
production even though the code faithfully implements it. This is the
producer-side mirror of a decorative config control (FM-038): instead of
"registry entry with no consumer," it's "consumer with no producer."

Fix one of:
  - Add a real producer (something that sets the var in production).
  - Add an honest-status marker comment at the read site, e.g.:
      # HONEST STATUS (<date>): no producer sets this variable anywhere
      # in the repo today -- <what would set it, and why it doesn't yet>.
  - If this is a deliberate operator-shell / self-test-only override with
    no in-repo producer expected by design, add a justified entry to
    config/config-control-allowlist.txt.

Doctrine: doctrine/vaporware-prevention.md ("Decorative config control")
Failure mode: docs/failure-modes.md FM-038
ERR_MSG
  exit 1
fi

exit 0
