#!/usr/bin/env bash
# run-all.sh — synthetic-session-runner (NL Overhaul task E.4, ADR 058 D7)
#
# Runs every scenario-*.sh in this directory and reports PASS/FAIL per
# scenario plus a final summary line. Each scenario is a self-contained
# golden test (mktemp -d fixture, HARNESS_SELFTEST=1) that exercises a
# real harness gate against a synthetic bad-case AND a paired good-case,
# asserting the gate BLOCKS the bad case and ALLOWS the good case.
#
# Scenarios listed in deferred.txt are SKIPPED (not run) with a
# SKIPPED-deferred line naming the reason from that file. This lets the
# runner ship ahead of the Wave-D gates those scenarios exercise (per the
# E.4 dispatch's explicit STABLE-SUBSET scope: three of the eight golden
# scenarios named in the parent plan's task E.4 line — false-DONE,
# marker-missing, waiver-abuse — test session-honesty-gate /
# continuation-enforcer wiring that lands in Wave D and is out of scope
# for this scaffold).
#
# Per-scenario timeout: 120s (matches the timeout harness-doctor.sh uses
# for its own --self-test sweep of hooks that declare --self-test).
#
# Exit code: 0 iff every non-deferred scenario passes. Non-zero otherwise.
#
# Usage:
#   bash evals/synthetic/run-all.sh
#
# CI wiring (the E.4 design-skip companion plan) invokes this exact
# command weekly + on-demand against the program branch.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFERRED_FILE="$SCRIPT_DIR/deferred.txt"
TIMEOUT_SECS=120

PASSED=0
FAILED=0
SKIPPED=0
FAIL_NAMES=()

# Build the deferred-name -> reason map (if the file exists).
declare -A DEFERRED_REASON=()
if [[ -f "$DEFERRED_FILE" ]]; then
  while IFS= read -r line; do
    # Skip blank lines and comment lines (#-prefixed)
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    # Format: <scenario-basename-without-.sh> — <reason>
    name="${line%%—*}"
    reason="${line#*—}"
    name="$(echo "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    reason="$(echo "$reason" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$name" ]] && continue
    DEFERRED_REASON["$name"]="$reason"
  done < "$DEFERRED_FILE"
fi

# Enumerate scenario-*.sh files that exist on disk, sorted for
# deterministic ordering.
mapfile -t EXISTING_SCENARIOS < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -name 'scenario-*.sh' | sort)

if [[ "${#EXISTING_SCENARIOS[@]}" -eq 0 && "${#DEFERRED_REASON[@]}" -eq 0 ]]; then
  echo "run-all: no scenario-*.sh files found in $SCRIPT_DIR and deferred.txt is empty" >&2
  exit 1
fi

# Union of (a) scenario basenames that exist on disk and (b) scenario
# basenames listed in deferred.txt (which may not yet exist on disk —
# a deferred scenario is deliberately unbuilt, not merely disabled).
# Deduplicated + sorted so the report is deterministic regardless of
# whether a deferred name also happens to have a stub file present.
declare -A SEEN=()
ALL_BASENAMES=()
for scenario_path in "${EXISTING_SCENARIOS[@]}"; do
  base="$(basename "$scenario_path" .sh)"
  [[ -n "${SEEN[$base]:-}" ]] && continue
  SEEN["$base"]=1
  ALL_BASENAMES+=("$base")
done
for base in "${!DEFERRED_REASON[@]}"; do
  [[ -n "${SEEN[$base]:-}" ]] && continue
  SEEN["$base"]=1
  ALL_BASENAMES+=("$base")
done
mapfile -t ALL_BASENAMES < <(printf '%s\n' "${ALL_BASENAMES[@]}" | sort)

for base in "${ALL_BASENAMES[@]}"; do
  if [[ -n "${DEFERRED_REASON[$base]:-}" ]]; then
    echo "SKIPPED-deferred: $base — ${DEFERRED_REASON[$base]}"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  scenario_path="$SCRIPT_DIR/$base.sh"
  echo "--- running $base ---"
  if timeout "$TIMEOUT_SECS" bash "$scenario_path"; then
    echo "PASS: $base"
    PASSED=$((PASSED + 1))
  else
    rc=$?
    echo "FAIL: $base (exit $rc)"
    FAILED=$((FAILED + 1))
    FAIL_NAMES+=("$base")
  fi
  echo ""
done

echo "=== summary ==="
echo "passed:  $PASSED"
echo "failed:  $FAILED"
echo "skipped: $SKIPPED (deferred)"
if [[ "$FAILED" -gt 0 ]]; then
  echo "failing scenarios: ${FAIL_NAMES[*]}"
  exit 1
fi
exit 0
