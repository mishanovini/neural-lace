#!/bin/bash
# plan-edit-validator.sh — Generation 4
#
# PreToolUse hook that blocks casual plan-checkbox self-edits.
#
# Rule: the only entity allowed to flip "- [ ]" → "- [x]" in a plan file
# under docs/plans/ is the task-verifier agent. Direct edits by the builder
# are blocked.
#
# The hook reads the tool invocation JSON from stdin (Claude Code's
# PreToolUse convention), inspects it for plan-file edits, and exits 1
# if the edit would flip a checkbox without task-verifier authorization.
#
# Escape hatches (legitimate use cases):
#   1. File matches *-evidence.md → evidence files are written by the
#      verifier output. Allowed (the evidence content is validated at
#      session-end by the runtime-verification-executor).
#   2. The file isn't under docs/plans/ at all → pass through.
#   3. The file is under docs/plans/ but the edit is evidence-first
#      authorized (see check_evidence_first below).
#
# PREVIOUSLY this hook honored a TASK_VERIFIER_MODE=1 environment
# variable as an escape hatch. That was a plaintext back door: any
# bash -c 'TASK_VERIFIER_MODE=1 ...' wrapper bypassed the gate. It has
# been removed. The ONLY authorized path is evidence-first.
#
# Exit codes:
#   0 — edit is allowed
#   1 — edit is blocked (stderr explains why)
#
# Concurrency (added by plan task 9):
#   The evidence-mtime check + plan-edit allow-decision is wrapped in a
#   per-plan lock at <plan-file>.lock. Two parallel verifiers serialize on
#   the lock so a single 120s mtime window cannot authorize two distinct
#   checkbox flips concurrently. flock(1) is preferred when available
#   (Linux/macOS); a PID-keyed mtime-based fallback covers environments
#   without flock (e.g., Windows Git Bash). Lock acquisition has a 30s
#   timeout to prevent indefinite hang if a previous holder crashed.

set -e

# ============================================================
# Lock helpers (plan-edit-validator concurrency protection)
# ============================================================
#
# acquire_plan_lock <plan-file>
#   Acquires an exclusive lock for the given plan file (lock file is
#   <plan-file>.lock). Returns 0 on success, 1 on timeout. Sets the
#   global PLAN_LOCK_FILE so release_plan_lock can clean up.
#
# Strategy:
#   1. If flock(1) is on PATH, use it. Open fd 9 on the lock file and
#      flock -w 30. flock auto-releases on fd close (we close at exit).
#   2. Otherwise, PID-keyed fallback: write our PID into the lock file
#      atomically (set -o noclobber + > redirect). If the file exists,
#      read its PID. If that PID is no longer alive (kill -0 fails), or
#      the lock file is older than 60s (likely zombie), claim the lock
#      by truncating + writing our PID. Otherwise sleep 0.5s, retry.
#      Bail after 30s of total waiting.
#
# Both paths are safe to call multiple times in one process; the second
# call with the same lock file is a no-op (we already hold it).

PLAN_LOCK_FILE=""
PLAN_LOCK_FD=""
PLAN_LOCK_HELD_VIA=""  # "flock" or "pid"

acquire_plan_lock() {
  local plan_file="$1"
  local lock_file="${plan_file}.lock"
  local timeout_s=30

  # Already holding this lock? No-op.
  if [[ "$PLAN_LOCK_FILE" == "$lock_file" ]]; then
    return 0
  fi

  PLAN_LOCK_FILE="$lock_file"

  # --- Path 1: flock(1) ---
  if command -v flock >/dev/null 2>&1; then
    # Open fd 9 on the lock file (creating it if needed)
    exec 9>"$lock_file" 2>/dev/null || {
      PLAN_LOCK_FILE=""
      return 1
    }
    if flock -w "$timeout_s" 9 2>/dev/null; then
      PLAN_LOCK_FD=9
      PLAN_LOCK_HELD_VIA="flock"
      # Record our PID inside the lock for diagnostics
      echo "$$" >&9 2>/dev/null || true
      return 0
    fi
    # flock timed out
    exec 9>&- 2>/dev/null || true
    PLAN_LOCK_FILE=""
    return 1
  fi

  # --- Path 2: PID-keyed fallback ---
  local waited_ms=0
  local sleep_ms=500
  local total_ms=$((timeout_s * 1000))

  while [[ "$waited_ms" -lt "$total_ms" ]]; do
    # Try atomic create-or-fail
    if ( set -o noclobber; echo "$$" > "$lock_file" ) 2>/dev/null; then
      PLAN_LOCK_HELD_VIA="pid"
      return 0
    fi

    # Lock exists; check liveness of the holder
    local holder_pid=""
    holder_pid=$(head -n 1 "$lock_file" 2>/dev/null | tr -d '[:space:]')

    if [[ -n "$holder_pid" ]] && [[ "$holder_pid" =~ ^[0-9]+$ ]]; then
      # Is the holder still alive?
      if ! kill -0 "$holder_pid" 2>/dev/null; then
        # Dead holder — steal the lock
        echo "$$" > "$lock_file" 2>/dev/null && {
          PLAN_LOCK_HELD_VIA="pid"
          return 0
        }
      else
        # Alive holder. If the lock file is very old, treat as zombie.
        local now mtime age
        now=$(date +%s)
        mtime=$(stat -c %Y "$lock_file" 2>/dev/null || echo "$now")
        age=$((now - mtime))
        if [[ "$age" -gt 60 ]]; then
          echo "$$" > "$lock_file" 2>/dev/null && {
            PLAN_LOCK_HELD_VIA="pid"
            return 0
          }
        fi
      fi
    else
      # Lock file with no PID content — corrupted, claim it
      echo "$$" > "$lock_file" 2>/dev/null && {
        PLAN_LOCK_HELD_VIA="pid"
        return 0
      }
    fi

    # Wait and retry
    sleep 0.5 2>/dev/null || sleep 1
    waited_ms=$((waited_ms + sleep_ms))
  done

  # Timed out
  PLAN_LOCK_FILE=""
  return 1
}

release_plan_lock() {
  if [[ -z "$PLAN_LOCK_FILE" ]]; then
    return 0
  fi
  case "$PLAN_LOCK_HELD_VIA" in
    flock)
      # Closing fd 9 releases the flock
      exec 9>&- 2>/dev/null || true
      ;;
    pid)
      # Only remove if we still own it
      local holder_pid=""
      holder_pid=$(head -n 1 "$PLAN_LOCK_FILE" 2>/dev/null | tr -d '[:space:]')
      if [[ "$holder_pid" == "$$" ]]; then
        rm -f "$PLAN_LOCK_FILE" 2>/dev/null || true
      fi
      ;;
  esac
  PLAN_LOCK_FILE=""
  PLAN_LOCK_FD=""
  PLAN_LOCK_HELD_VIA=""
}

# Ensure lock release on any exit path (success, failure, signal)
trap 'release_plan_lock' EXIT INT TERM

# ============================================================
# --self-test: 4 scenarios for plan task 9 (lock concurrency)
# ============================================================
#
# Scenarios:
#   F1 single-writer baseline   — one process acquires lock, releases cleanly
#   F2 two-writer serialization — two background processes serialize on lock
#   F3 lock-timeout / stale-PID — stale lock (dead PID) is reclaimed; live
#                                 lock with old mtime is reclaimed
#   F4 lock-cleanup             — lock file is removed after release
#
# Exits 0 only if every scenario matched its expected outcome.

if [[ "${1:-}" == "--self-test" ]]; then
  # Disable the EXIT trap during self-test setup so it doesn't fire on
  # subshell exits while still working inside helper invocations
  trap - EXIT INT TERM

  TMPDIR_SELFTEST=$(mktemp -d 2>/dev/null || mktemp -d -t pevself)
  if [[ -z "$TMPDIR_SELFTEST" ]] || [[ ! -d "$TMPDIR_SELFTEST" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPDIR_SELFTEST"' EXIT

  PASSED=0
  FAILED=0

  PLAN_FIXTURE="$TMPDIR_SELFTEST/plan.md"
  : > "$PLAN_FIXTURE"

  # ---- F1: single-writer baseline ----
  # Acquire lock, hold briefly, release. Lock file should be removed
  # (PID path) or fd closed cleanly (flock path).
  PLAN_LOCK_FILE=""; PLAN_LOCK_FD=""; PLAN_LOCK_HELD_VIA=""
  if acquire_plan_lock "$PLAN_FIXTURE"; then
    release_plan_lock
    if [[ -z "$PLAN_LOCK_FILE" ]]; then
      echo "self-test (F1) single-writer-baseline: PASS" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test (F1) single-writer-baseline: FAIL (PLAN_LOCK_FILE not cleared after release)" >&2
      FAILED=$((FAILED+1))
    fi
  else
    echo "self-test (F1) single-writer-baseline: FAIL (could not acquire lock on fresh fixture)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- F2: two-writer serialization ----
  # Spawn two INDEPENDENT bash processes (each with its own $$ PID) that
  # source the lock library and contend for the same plan lock. Each
  # worker:
  #   1. Acquires the lock
  #   2. Logs ENTER with timestamp
  #   3. Sleeps briefly (with lock held) to widen the race window
  #   4. Appends a marker line to the plan file
  #   5. Logs EXIT
  #   6. Releases the lock
  # If serialization works, the log shows ENTER A / EXIT A / ENTER B /
  # EXIT B (or B before A) — never an overlapping ENTER / ENTER pair.
  #
  # We need separate PIDs (not subshells of the same parent) because the
  # PID-fallback uses $$ to identify the lock holder. Subshells inherit
  # $$ from the parent. Solution: spawn two `bash -c` invocations.
  PLAN_LOCK_FILE=""; PLAN_LOCK_FD=""; PLAN_LOCK_HELD_VIA=""
  : > "$PLAN_FIXTURE"
  WORKER_LOG="$TMPDIR_SELFTEST/worker.log"
  : > "$WORKER_LOG"

  # Write the lock library to a sourceable file in TMPDIR. Use a
  # subset of this script: from the start of acquire_plan_lock to the
  # end of release_plan_lock. Easier: write a self-contained library.
  LOCKLIB="$TMPDIR_SELFTEST/locklib.sh"
  cat > "$LOCKLIB" <<'LIB'
PLAN_LOCK_FILE=""
PLAN_LOCK_FD=""
PLAN_LOCK_HELD_VIA=""
acquire_plan_lock() {
  local plan_file="$1"
  local lock_file="${plan_file}.lock"
  local timeout_s=30
  if [[ "$PLAN_LOCK_FILE" == "$lock_file" ]]; then return 0; fi
  PLAN_LOCK_FILE="$lock_file"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock_file" 2>/dev/null || { PLAN_LOCK_FILE=""; return 1; }
    if flock -w "$timeout_s" 9 2>/dev/null; then
      PLAN_LOCK_FD=9; PLAN_LOCK_HELD_VIA="flock"
      echo "$$" >&9 2>/dev/null || true; return 0
    fi
    exec 9>&- 2>/dev/null || true; PLAN_LOCK_FILE=""; return 1
  fi
  local waited_ms=0; local total_ms=$((timeout_s * 1000))
  while [[ "$waited_ms" -lt "$total_ms" ]]; do
    if ( set -o noclobber; echo "$$" > "$lock_file" ) 2>/dev/null; then
      PLAN_LOCK_HELD_VIA="pid"; return 0
    fi
    local holder_pid=""
    holder_pid=$(head -n 1 "$lock_file" 2>/dev/null | tr -d '[:space:]')
    if [[ -n "$holder_pid" ]] && [[ "$holder_pid" =~ ^[0-9]+$ ]]; then
      if ! kill -0 "$holder_pid" 2>/dev/null; then
        echo "$$" > "$lock_file" 2>/dev/null && { PLAN_LOCK_HELD_VIA="pid"; return 0; }
      else
        local now mtime age
        now=$(date +%s); mtime=$(stat -c %Y "$lock_file" 2>/dev/null || echo "$now")
        age=$((now - mtime))
        if [[ "$age" -gt 60 ]]; then
          echo "$$" > "$lock_file" 2>/dev/null && { PLAN_LOCK_HELD_VIA="pid"; return 0; }
        fi
      fi
    else
      echo "$$" > "$lock_file" 2>/dev/null && { PLAN_LOCK_HELD_VIA="pid"; return 0; }
    fi
    sleep 0.5; waited_ms=$((waited_ms + 500))
  done
  PLAN_LOCK_FILE=""; return 1
}
release_plan_lock() {
  if [[ -z "$PLAN_LOCK_FILE" ]]; then return 0; fi
  case "$PLAN_LOCK_HELD_VIA" in
    flock) exec 9>&- 2>/dev/null || true ;;
    pid)
      local holder_pid=""
      holder_pid=$(head -n 1 "$PLAN_LOCK_FILE" 2>/dev/null | tr -d '[:space:]')
      if [[ "$holder_pid" == "$$" ]]; then rm -f "$PLAN_LOCK_FILE" 2>/dev/null || true; fi ;;
  esac
  PLAN_LOCK_FILE=""; PLAN_LOCK_FD=""; PLAN_LOCK_HELD_VIA=""
}
LIB

  WORKER_SCRIPT="$TMPDIR_SELFTEST/worker.sh"
  cat > "$WORKER_SCRIPT" <<WKR
#!/bin/bash
source "$LOCKLIB"
LABEL="\$1"
PLAN="\$2"
LOG="\$3"
if ! acquire_plan_lock "\$PLAN"; then
  echo "ACQUIRE-FAIL \$LABEL pid=\$\$" >> "\$LOG"
  exit 1
fi
echo "ENTER \$LABEL" >> "\$LOG"
sleep 0.4
echo "marker-\$LABEL" >> "\$PLAN"
echo "EXIT \$LABEL" >> "\$LOG"
release_plan_lock
WKR
  chmod +x "$WORKER_SCRIPT"

  bash "$WORKER_SCRIPT" A "$PLAN_FIXTURE" "$WORKER_LOG" &
  PID_A=$!
  bash "$WORKER_SCRIPT" B "$PLAN_FIXTURE" "$WORKER_LOG" &
  PID_B=$!
  wait "$PID_A" 2>/dev/null
  RC_A=$?
  wait "$PID_B" 2>/dev/null
  RC_B=$?

  # Both workers must succeed and both markers must be present
  MARKER_A_COUNT=$(grep -c "^marker-A$" "$PLAN_FIXTURE" 2>/dev/null || echo 0)
  MARKER_B_COUNT=$(grep -c "^marker-B$" "$PLAN_FIXTURE" 2>/dev/null || echo 0)
  MARKER_A_COUNT=$(echo "$MARKER_A_COUNT" | tr -d '[:space:]')
  MARKER_B_COUNT=$(echo "$MARKER_B_COUNT" | tr -d '[:space:]')

  # Verify serialization: in the worker log, each ENTER must be followed
  # by the matching EXIT for the same label before any other ENTER.
  # Acceptable patterns: "ENTER A / EXIT A / ENTER B / EXIT B" or B-first.
  # Unacceptable: any ENTER-ENTER without an intervening EXIT (overlap).
  LOG_LABELS=$(grep -E '^(ENTER|EXIT)' "$WORKER_LOG" | awk '{print $1, $2}' | tr '\n' '|')
  SERIALIZED_OK=0
  if [[ "$LOG_LABELS" == "ENTER A|EXIT A|ENTER B|EXIT B|" ]] \
     || [[ "$LOG_LABELS" == "ENTER B|EXIT B|ENTER A|EXIT A|" ]]; then
    SERIALIZED_OK=1
  fi

  if [[ "$RC_A" -eq 0 ]] && [[ "$RC_B" -eq 0 ]] \
     && [[ "$MARKER_A_COUNT" == "1" ]] && [[ "$MARKER_B_COUNT" == "1" ]] \
     && [[ "$SERIALIZED_OK" == "1" ]]; then
    echo "self-test (F2) two-writer-serialization: PASS (both markers present, serialized order: $LOG_LABELS)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (F2) two-writer-serialization: FAIL (rc_a=$RC_A rc_b=$RC_B marker_a=$MARKER_A_COUNT marker_b=$MARKER_B_COUNT order='$LOG_LABELS')" >&2
    cat "$WORKER_LOG" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- F3: lock-timeout / stale-PID reclamation ----
  # Plant a stale lock with a non-existent PID. Lock acquisition should
  # detect the dead holder (kill -0 fails) and reclaim quickly without
  # waiting the full 30s timeout. We measure elapsed time to confirm.
  PLAN_LOCK_FILE=""; PLAN_LOCK_FD=""; PLAN_LOCK_HELD_VIA=""
  PLAN_FIXTURE_F3="$TMPDIR_SELFTEST/plan-f3.md"
  : > "$PLAN_FIXTURE_F3"
  STALE_LOCK="${PLAN_FIXTURE_F3}.lock"

  # Find a definitely-dead PID. Use a very high number unlikely to be live.
  # On most systems pid_max is < 4194304; pick 999999 which is rarely live.
  # Verify it's actually dead — if somehow alive, pick another.
  STALE_PID=999999
  while kill -0 "$STALE_PID" 2>/dev/null; do
    STALE_PID=$((STALE_PID + 1))
    if [[ "$STALE_PID" -gt 4000000 ]]; then break; fi
  done
  echo "$STALE_PID" > "$STALE_LOCK"

  T_START=$(date +%s)
  if acquire_plan_lock "$PLAN_FIXTURE_F3"; then
    T_END=$(date +%s)
    ELAPSED=$((T_END - T_START))
    release_plan_lock
    # Should reclaim quickly (well under 30s timeout)
    if [[ "$ELAPSED" -lt 5 ]]; then
      echo "self-test (F3) lock-timeout-stale-pid: PASS (reclaimed in ${ELAPSED}s)" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test (F3) lock-timeout-stale-pid: FAIL (took ${ELAPSED}s, expected < 5s)" >&2
      FAILED=$((FAILED+1))
    fi
  else
    echo "self-test (F3) lock-timeout-stale-pid: FAIL (acquire_plan_lock returned 1 on stale lock)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- F4: lock-cleanup ----
  # After acquire + release, the lock file should not block a subsequent
  # acquisition. (PID-fallback removes the file; flock leaves an empty
  # file which is fine since flock semantics ignore content.) Verify by
  # acquiring a second time.
  PLAN_LOCK_FILE=""; PLAN_LOCK_FD=""; PLAN_LOCK_HELD_VIA=""
  PLAN_FIXTURE_F4="$TMPDIR_SELFTEST/plan-f4.md"
  : > "$PLAN_FIXTURE_F4"

  if ! acquire_plan_lock "$PLAN_FIXTURE_F4"; then
    echo "self-test (F4) lock-cleanup: FAIL (initial acquire failed)" >&2
    FAILED=$((FAILED+1))
  else
    release_plan_lock
    PLAN_LOCK_FILE=""; PLAN_LOCK_FD=""; PLAN_LOCK_HELD_VIA=""
    T_START=$(date +%s)
    if acquire_plan_lock "$PLAN_FIXTURE_F4"; then
      T_END=$(date +%s)
      ELAPSED=$((T_END - T_START))
      release_plan_lock
      if [[ "$ELAPSED" -lt 5 ]]; then
        echo "self-test (F4) lock-cleanup: PASS (re-acquired in ${ELAPSED}s)" >&2
        PASSED=$((PASSED+1))
      else
        echo "self-test (F4) lock-cleanup: FAIL (re-acquire took ${ELAPSED}s)" >&2
        FAILED=$((FAILED+1))
      fi
    else
      echo "self-test (F4) lock-cleanup: FAIL (re-acquire returned 1)" >&2
      FAILED=$((FAILED+1))
    fi
  fi

  # ============================================================
  # F5/F6/F7 — evidence recognition (Tranche B, 2026-05-05)
  # ============================================================
  #
  # The check_evidence_first function below recognizes both prose
  # evidence (legacy) and structured evidence (new). These three
  # scenarios verify that:
  #   F5 structured-evidence-recognized — JSON artifact authorizes
  #   F6 prose-evidence-still-recognized — legacy block authorizes
  #   F7 mixed-format-plan-validates    — both formats coexist
  #
  # We define an inline replica of check_evidence_first so the test
  # works without sourcing the full script body.

  selftest_check_evidence_first() {
    local plan_file="$1"
    local task_id="$2"

    # Path A — prose
    local evidence_file="${plan_file%.md}-evidence.md"
    if [[ -f "$evidence_file" ]]; then
      local now mtime age
      now=$(date +%s)
      mtime=$(stat -c %Y "$evidence_file" 2>/dev/null || echo 0)
      age=$((now - mtime))
      if [[ "$age" -le 120 ]]; then
        local result
        result=$(awk -v wanted_id="$task_id" '
          BEGIN { in_block = 0; t = ""; has_runtime = 0; }
          /^EVIDENCE BLOCK/ {
            if (in_block && t == wanted_id && has_runtime) { print "MATCH"; exit 0 }
            in_block = 1; t = ""; has_runtime = 0; next
          }
          /^Task ID:/ {
            if (in_block) {
              sub(/^Task ID:[[:space:]]*/, "", $0); sub(/[[:space:]].*$/, "", $0); t = $0
            }
            next
          }
          /^Runtime verification:/ { if (in_block) has_runtime = 1; next }
          END { if (in_block && t == wanted_id && has_runtime) print "MATCH" }
        ' "$evidence_file")
        if [[ "$result" == "MATCH" ]]; then return 0; fi
      fi
    fi

    # Path B — structured
    local plan_dir plan_slug structured_dir structured_file
    plan_dir=$(dirname "$plan_file")
    plan_slug=$(basename "$plan_file" .md)
    structured_dir="$plan_dir/${plan_slug}-evidence"
    structured_file="$structured_dir/${task_id}.evidence.json"
    if [[ -f "$structured_file" ]]; then
      local now2 mtime2 age2
      now2=$(date +%s)
      mtime2=$(stat -c %Y "$structured_file" 2>/dev/null || echo 0)
      age2=$((now2 - mtime2))
      if [[ "$age2" -le 120 ]]; then
        if jq -e --arg id "$task_id" '.task_id == $id' "$structured_file" >/dev/null 2>&1; then
          return 0
        fi
      fi
    fi
    return 1
  }

  # ---- F5: structured-evidence-recognized ----
  PLAN_F5="$TMPDIR_SELFTEST/plan-f5.md"
  : > "$PLAN_F5"
  STRUCTURED_DIR_F5="$TMPDIR_SELFTEST/plan-f5-evidence"
  mkdir -p "$STRUCTURED_DIR_F5"
  cat > "$STRUCTURED_DIR_F5/B.1.evidence.json" <<JSON
{
  "schema_version": 1,
  "task_id": "B.1",
  "verdict": "PASS",
  "commit_sha": "abc1234",
  "files_modified": ["foo.md"],
  "mechanical_checks": {"exists:foo.md": {"passed": true, "detail": "ok"}},
  "timestamp": "2026-05-05T13:42:00Z",
  "verifier": "write-evidence.sh"
}
JSON
  if selftest_check_evidence_first "$PLAN_F5" "B.1"; then
    echo "self-test (F5) structured-evidence-recognized: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (F5) structured-evidence-recognized: FAIL" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- F6: prose-evidence-still-recognized ----
  PLAN_F6="$TMPDIR_SELFTEST/plan-f6.md"
  : > "$PLAN_F6"
  PROSE_F6="$TMPDIR_SELFTEST/plan-f6-evidence.md"
  cat > "$PROSE_F6" <<'PROSE'
# Evidence

EVIDENCE BLOCK
==============
Task ID: B.6
Task description: legacy
Verified at: 2026-05-05

Runtime verification: command true

Verdict: PASS
PROSE
  if selftest_check_evidence_first "$PLAN_F6" "B.6"; then
    echo "self-test (F6) prose-evidence-still-recognized: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (F6) prose-evidence-still-recognized: FAIL" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- F7: mixed-format-plan-validates ----
  # One plan with BOTH prose evidence (for task B.7-prose) and structured
  # evidence (for task B.7-struct). Both should authorize independently.
  PLAN_F7="$TMPDIR_SELFTEST/plan-f7.md"
  : > "$PLAN_F7"
  PROSE_F7="$TMPDIR_SELFTEST/plan-f7-evidence.md"
  cat > "$PROSE_F7" <<'PROSE'
EVIDENCE BLOCK
==============
Task ID: B.7-prose
Verified at: 2026-05-05
Runtime verification: command true
Verdict: PASS
PROSE
  STRUCTURED_DIR_F7="$TMPDIR_SELFTEST/plan-f7-evidence"
  mkdir -p "$STRUCTURED_DIR_F7"
  cat > "$STRUCTURED_DIR_F7/B.7-struct.evidence.json" <<JSON
{
  "schema_version": 1,
  "task_id": "B.7-struct",
  "verdict": "PASS",
  "commit_sha": "abc1234",
  "files_modified": [],
  "mechanical_checks": {"x": true},
  "timestamp": "2026-05-05T13:42:00Z"
}
JSON
  if selftest_check_evidence_first "$PLAN_F7" "B.7-prose" \
     && selftest_check_evidence_first "$PLAN_F7" "B.7-struct"; then
    echo "self-test (F7) mixed-format-plan-validates: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (F7) mixed-format-plan-validates: FAIL" >&2
    FAILED=$((FAILED+1))
  fi

  # ============================================================
  # F8/F9/F10 — risk-tiered Verification field routing
  # (Tranche D of architecture-simplification, 2026-05-05)
  # ============================================================
  #
  # F8  mechanical-evidence-recognized — task line declares
  #     `Verification: mechanical`; structured `.evidence.json`
  #     authorizes WITHOUT a runtime-verification line.
  # F9  contract-evidence-recognized — task line declares
  #     `Verification: contract`; structured `.evidence.json`
  #     containing a `schema-valid` mechanical_check authorizes.
  # F10 unmarked-defaults-to-full — task line has no field; the
  #     existing prose-with-runtime-verification path is used.
  #
  # Inline replicas of the routing helpers are used so the test works
  # without sourcing the full hook.

  selftest_extract_verification_level() {
    # $1 = task line text. Echoes "mechanical", "full", or "contract".
    # Defaults to "full" when no field present or token unrecognized.
    local task_line="$1"
    local lvl
    lvl=$(echo "$task_line" | sed -nE 's/.*Verification:[[:space:]]+([A-Za-z][A-Za-z_-]*).*/\1/p' | head -1)
    if [[ "$lvl" =~ ^(mechanical|full|contract)$ ]]; then
      echo "$lvl"
    else
      echo "full"
    fi
  }

  selftest_check_mechanical_or_contract_evidence() {
    # Mechanical/contract: accept fresh structured `.evidence.json` whose
    # task_id matches AND verdict is PASS. No runtime-verification line
    # required; the structured artifact is the verification.
    # $1 = plan_file, $2 = task_id, $3 = level (mechanical|contract)
    local plan_file="$1"
    local task_id="$2"
    local level="$3"
    local plan_dir plan_slug structured_dir structured_file
    plan_dir=$(dirname "$plan_file")
    plan_slug=$(basename "$plan_file" .md)
    structured_dir="$plan_dir/${plan_slug}-evidence"
    structured_file="$structured_dir/${task_id}.evidence.json"
    if [[ -f "$structured_file" ]]; then
      local now mtime age
      now=$(date +%s)
      mtime=$(stat -c %Y "$structured_file" 2>/dev/null || echo 0)
      age=$((now - mtime))
      if [[ "$age" -le 120 ]]; then
        if jq -e --arg id "$task_id" '.task_id == $id and .verdict == "PASS"' "$structured_file" >/dev/null 2>&1; then
          if [[ "$level" == "contract" ]]; then
            # Additional contract requirement: at least one mechanical_check
            # whose name starts with "schema-valid" or is a "command:"
            # check whose detail mentions diff/schema. We accept any PASS
            # mechanical_check as evidence since the task author is
            # responsible for the right check; the gate's role is freshness
            # + verdict + task-id match.
            if jq -e '.mechanical_checks | type == "object" and (length > 0)' "$structured_file" >/dev/null 2>&1; then
              return 0
            fi
            return 1
          fi
          return 0
        fi
      fi
    fi
    # Fallback to legacy prose with one-line commit-SHA citation
    local evidence_file="${plan_file%.md}-evidence.md"
    if [[ -f "$evidence_file" ]]; then
      local now2 mtime2 age2
      now2=$(date +%s)
      mtime2=$(stat -c %Y "$evidence_file" 2>/dev/null || echo 0)
      age2=$((now2 - mtime2))
      if [[ "$age2" -le 120 ]]; then
        local result
        result=$(awk -v wanted_id="$task_id" '
          BEGIN { in_block = 0; t = ""; has_commit = 0; }
          /^EVIDENCE BLOCK/ {
            if (in_block && t == wanted_id && has_commit) { print "MATCH"; exit 0 }
            in_block = 1; t = ""; has_commit = 0; next
          }
          /^Task ID:/ {
            if (in_block) {
              sub(/^Task ID:[[:space:]]*/, "", $0); sub(/[[:space:]].*$/, "", $0); t = $0
            }
            next
          }
          /^Commit:/ { if (in_block) has_commit = 1; next }
          END { if (in_block && t == wanted_id && has_commit) print "MATCH" }
        ' "$evidence_file")
        if [[ "$result" == "MATCH" ]]; then return 0; fi
      fi
    fi
    return 1
  }

  # ---- F8: mechanical-evidence-recognized ----
  PLAN_F8="$TMPDIR_SELFTEST/plan-f8.md"
  cat > "$PLAN_F8" <<'PLAN_F8_BODY'
# Plan: F8 fixture
## Tasks
- [ ] D.1. Edit a hook file — Verification: mechanical
PLAN_F8_BODY
  STRUCTURED_DIR_F8="$TMPDIR_SELFTEST/plan-f8-evidence"
  mkdir -p "$STRUCTURED_DIR_F8"
  cat > "$STRUCTURED_DIR_F8/D.1.evidence.json" <<JSON
{
  "schema_version": 1,
  "task_id": "D.1",
  "verdict": "PASS",
  "commit_sha": "abc1234",
  "files_modified": ["hooks/foo.sh"],
  "mechanical_checks": {"exists:hooks/foo.sh": {"passed": true, "detail": "ok"}},
  "timestamp": "2026-05-05T13:42:00Z",
  "verifier": "write-evidence.sh"
}
JSON
  TASK_LINE_F8="- [ ] D.1. Edit a hook file — Verification: mechanical"
  LVL_F8=$(selftest_extract_verification_level "$TASK_LINE_F8")
  if [[ "$LVL_F8" == "mechanical" ]] \
     && selftest_check_mechanical_or_contract_evidence "$PLAN_F8" "D.1" "mechanical"; then
    echo "self-test (F8) mechanical-evidence-recognized: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (F8) mechanical-evidence-recognized: FAIL (lvl=$LVL_F8)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- F9: contract-evidence-recognized ----
  PLAN_F9="$TMPDIR_SELFTEST/plan-f9.md"
  cat > "$PLAN_F9" <<'PLAN_F9_BODY'
# Plan: F9 fixture
## Tasks
- [ ] D.2. Extend the JSON schema — Verification: contract
PLAN_F9_BODY
  STRUCTURED_DIR_F9="$TMPDIR_SELFTEST/plan-f9-evidence"
  mkdir -p "$STRUCTURED_DIR_F9"
  cat > "$STRUCTURED_DIR_F9/D.2.evidence.json" <<JSON
{
  "schema_version": 1,
  "task_id": "D.2",
  "verdict": "PASS",
  "commit_sha": "abc5678",
  "files_modified": ["schemas/foo.schema.json"],
  "mechanical_checks": {"schema-valid:schemas/foo.schema.json": {"passed": true, "detail": "validates against meta-schema"}},
  "timestamp": "2026-05-05T13:42:00Z",
  "verifier": "write-evidence.sh"
}
JSON
  TASK_LINE_F9="- [ ] D.2. Extend the JSON schema — Verification: contract"
  LVL_F9=$(selftest_extract_verification_level "$TASK_LINE_F9")
  if [[ "$LVL_F9" == "contract" ]] \
     && selftest_check_mechanical_or_contract_evidence "$PLAN_F9" "D.2" "contract"; then
    echo "self-test (F9) contract-evidence-recognized: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (F9) contract-evidence-recognized: FAIL (lvl=$LVL_F9)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- F10: unmarked-defaults-to-full ----
  TASK_LINE_F10="- [ ] D.3. Implement the runtime feature end-to-end."
  LVL_F10=$(selftest_extract_verification_level "$TASK_LINE_F10")
  if [[ "$LVL_F10" == "full" ]]; then
    echo "self-test (F10) unmarked-defaults-to-full: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (F10) unmarked-defaults-to-full: FAIL (lvl=$LVL_F10)" >&2
    FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 10 scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# Main hook logic
# ============================================================

# Read the tool invocation JSON from whichever input mode Claude Code uses.
# PreToolUse hooks may receive input via stdin OR via the CLAUDE_TOOL_INPUT
# env var depending on Claude Code version. Support both.
#
# The other hooks in this settings.json (e.g., .env blocker, lockfile
# blocker, force-push blocker) all use $CLAUDE_TOOL_INPUT. An earlier
# version of this hook only read stdin, which silently no-op'd because
# stdin was empty. That bug was caught by the adversarial harness review.
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  # Fall back to stdin
  if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || echo "")
  fi
fi

# If there's still no input (direct manual invocation), nothing to check
if [[ -z "$INPUT" ]]; then
  exit 0
fi

# Some hook-input formats nest under .tool_input, others put the tool
# input at the top level. Check both and extract the key fields.
HAS_NESTED=$(echo "$INPUT" | jq -r 'has("tool_input")' 2>/dev/null || echo "false")

# Evidence-first authorization (the ONLY legitimate path)
# Instead of a forgeable marker file, the plan edit is authorized only if
# the corresponding evidence file (<plan>-evidence.md) has been modified
# in the last 120 seconds AND contains a Task ID: line matching the task
# being checked.
#
# This ties authorization to an actual artifact: the task-verifier must
# write real evidence before flipping the checkbox. The evidence is
# subject to runtime-verification-executor validation at session-end, so
# a builder cannot fabricate evidence without also writing real
# Runtime verification: commands that execute successfully.
#
# A manual "touch" cannot bypass this because touch-ing the evidence file
# doesn't insert a Task ID: line.

# This check runs after we know FILE_PATH is a plan file (see below).
# We'll evaluate the escape hatch inline at the checkbox-transition point.

# Extract file_path (present for both Edit and Write)
# Support both nested (.tool_input.file_path) and flat (.file_path) formats
if [[ "$HAS_NESTED" == "true" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
else
  FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // ""' 2>/dev/null)
  # For flat format, we can't easily know the tool name; infer from fields
  if [[ -n "$(echo "$INPUT" | jq -r '.old_string // ""' 2>/dev/null)" ]]; then
    TOOL_NAME="Edit"
  elif [[ -n "$(echo "$INPUT" | jq -r '.content // ""' 2>/dev/null)" ]]; then
    TOOL_NAME="Write"
  else
    TOOL_NAME="Unknown"
  fi
fi

# If the invocation has no file_path, it's not a file-edit tool — pass through
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Normalize path separators (Windows Git Bash uses forward slashes in JSON)
FILE_PATH_NORM=$(echo "$FILE_PATH" | tr '\\' '/')

# Check if the file is under docs/plans/ (either repo-relative or absolute)
if [[ ! "$FILE_PATH_NORM" =~ docs/plans/.*\.md$ ]]; then
  exit 0
fi

# Escape hatch: evidence files are allowed (they're written by the verifier)
if [[ "$FILE_PATH_NORM" =~ -evidence\.md$ ]]; then
  exit 0
fi

# Escape hatch: new plan files are allowed (Write creating a fresh plan)
# We allow fresh plan creation but block modifications that check boxes
# on existing plans. Detect "new" by whether the file exists on disk.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

# Helper: check if the task ID is backed by a fresh evidence entry.
#
# Returns 0 if:
#   1. The evidence file was modified in the last 120 seconds (mtime check)
#   2. The evidence file contains an EVIDENCE BLOCK whose `Task ID:` line
#      matches the task being checked
#   3. That same block contains at least one `Runtime verification:` line
#      between the matching Task ID and the next EVIDENCE BLOCK marker
#      (or end-of-file)
#
# The per-block parsing closes the replay attack where one legitimate
# verification for task A.1 authorized all subsequent edits within 120s.
# Now the Task ID line and the Runtime verification line must appear in
# the SAME block, which means a single evidence block authorizes exactly
# one checkbox flip.
# ============================================================
# extract_verification_level — Tranche D risk-tiered routing
# ============================================================
#
# Reads the plan file, locates the task line whose ID matches $task_id,
# and extracts the `Verification: <level>` token if present. Returns one
# of: "mechanical", "full", "contract". Defaults to "full" when no field
# is present or the token is unrecognized (backward-compatible per
# Decision queued-tranche-1.5.md D.2).
#
# See ~/.claude/rules/risk-tiered-verification.md for level semantics.

extract_verification_level() {
  local plan_file="$1"
  local task_id="$2"
  if [[ ! -f "$plan_file" ]] || [[ -z "$task_id" ]]; then
    echo "full"
    return 0
  fi
  # Locate the task line. Supports `- [ ] <id>. <desc>` and
  # `- [x] <id>. <desc>`. The task ID match is anchored at start of the
  # checkbox marker so multi-character IDs (e.g., "B.1.2") work.
  local task_line
  task_line=$(grep -E "^- \[[ xX]\][[:space:]]+${task_id}\b" "$plan_file" 2>/dev/null | head -1)
  if [[ -z "$task_line" ]]; then
    echo "full"
    return 0
  fi
  local lvl
  lvl=$(echo "$task_line" | sed -nE 's/.*Verification:[[:space:]]+([A-Za-z][A-Za-z_-]*).*/\1/p' | head -1)
  if [[ "$lvl" =~ ^(mechanical|full|contract)$ ]]; then
    echo "$lvl"
  else
    echo "full"
  fi
}

# ============================================================
# check_mechanical_or_contract_evidence — Tranche D routing
# ============================================================
#
# For tasks declaring `Verification: mechanical` or `Verification:
# contract`, the evidence freshness check is RELAXED relative to `full`:
# a structured `.evidence.json` artifact (per Tranche B) with verdict
# PASS and matching task_id is sufficient. No `Runtime verification:`
# line is required — the structured artifact's `mechanical_checks` map
# IS the verification.
#
# Falls back to legacy prose evidence with one-line `Commit:` citation
# (a less-strict variant of the existing prose path) for builders not
# yet using the structured substrate.
#
# Returns 0 if evidence authorizes the flip, non-zero otherwise.

check_mechanical_or_contract_evidence() {
  local plan_file="$1"
  local task_id="$2"
  local level="$3"

  # Path A — structured `.evidence.json` (preferred)
  local plan_dir plan_slug structured_dir structured_file
  plan_dir=$(dirname "$plan_file")
  plan_slug=$(basename "$plan_file" .md)
  structured_dir="$plan_dir/${plan_slug}-evidence"
  structured_file="$structured_dir/${task_id}.evidence.json"

  if [[ -f "$structured_file" ]]; then
    local now mtime age
    now=$(date +%s)
    mtime=$(stat -c %Y "$structured_file" 2>/dev/null || echo 0)
    age=$((now - mtime))
    if [[ "$age" -le 120 ]]; then
      if jq -e --arg id "$task_id" '.task_id == $id and .verdict == "PASS"' "$structured_file" >/dev/null 2>&1; then
        # For contract level, additionally require at least one mechanical_check
        # to be present (the schema-valid / golden-diff outcome). The author
        # picks the right check name; the gate's role is freshness + verdict
        # + task-id match + non-empty mechanical_checks.
        if [[ "$level" == "contract" ]]; then
          if jq -e '.mechanical_checks | type == "object" and (length > 0)' "$structured_file" >/dev/null 2>&1; then
            return 0
          fi
        else
          return 0
        fi
      fi
    fi
  fi

  # Path B — legacy prose with one-line `Commit:` citation
  # The evidence block must contain Task ID matching plus at least one
  # `Commit:` line citing the SHA where the work landed. This is a
  # weaker form than the `full`-level prose-with-runtime-verification
  # but is appropriate for mechanical/contract work where a commit SHA
  # IS the verification anchor.
  local evidence_file="${plan_file%.md}-evidence.md"
  if [[ -f "$evidence_file" ]]; then
    local now2 mtime2 age2
    now2=$(date +%s)
    mtime2=$(stat -c %Y "$evidence_file" 2>/dev/null || echo 0)
    age2=$((now2 - mtime2))
    if [[ "$age2" -le 120 ]]; then
      local result
      result=$(awk -v wanted_id="$task_id" '
        BEGIN { in_block = 0; t = ""; has_commit = 0; }
        /^EVIDENCE BLOCK/ {
          if (in_block && t == wanted_id && has_commit) { print "MATCH"; exit 0 }
          in_block = 1; t = ""; has_commit = 0; next
        }
        /^Task ID:/ {
          if (in_block) {
            sub(/^Task ID:[[:space:]]*/, "", $0); sub(/[[:space:]].*$/, "", $0); t = $0
          }
          next
        }
        /^Commit:/ { if (in_block) has_commit = 1; next }
        END { if (in_block && t == wanted_id && has_commit) print "MATCH" }
      ' "$evidence_file")
      if [[ "$result" == "MATCH" ]]; then return 0; fi
    fi
  fi

  return 1
}

check_evidence_first() {
  local plan_file="$1"
  local task_id="$2"

  # ============================================================
  # Path A — prose evidence (legacy): <plan>-evidence.md
  # ============================================================
  local evidence_file="${plan_file%.md}-evidence.md"

  if [[ -f "$evidence_file" ]]; then
    # Evidence file must be recent (modified in last 120 seconds)
    local now mtime age
    now=$(date +%s)
    mtime=$(stat -c %Y "$evidence_file" 2>/dev/null || echo 0)
    age=$((now - mtime))
    if [[ "$age" -le 120 ]]; then

      # Parse the evidence file into per-block sections. A block starts
      # with a line containing "EVIDENCE BLOCK" and ends at the next one
      # or EOF. For each block: extract its Task ID line and its Runtime
      # verification lines. If any block has Task ID matching $task_id
      # AND has at least one Runtime verification line, the authorization
      # succeeds.
      #
      # The per-block parsing closes the replay attack where one legitimate
      # verification for task A.1 authorized all subsequent edits within
      # 120s. Now the Task ID line and the Runtime verification line must
      # appear in the SAME block, which means a single evidence block
      # authorizes exactly one checkbox flip.
      local result
      result=$(awk -v wanted_id="$task_id" '
        BEGIN { in_block = 0; task_id = ""; has_runtime = 0; }
        /^EVIDENCE BLOCK/ {
          if (in_block && task_id == wanted_id && has_runtime) {
            print "MATCH"
            exit 0
          }
          in_block = 1
          task_id = ""
          has_runtime = 0
          next
        }
        /^Task ID:/ {
          if (in_block) {
            sub(/^Task ID:[[:space:]]*/, "", $0)
            sub(/[[:space:]].*$/, "", $0)
            task_id = $0
          }
          next
        }
        /^Runtime verification:/ {
          if (in_block) has_runtime = 1
          next
        }
        END {
          if (in_block && task_id == wanted_id && has_runtime) {
            print "MATCH"
          }
        }
      ' "$evidence_file")

      if [[ "$result" == "MATCH" ]]; then
        return 0
      fi
    fi
  fi

  # ============================================================
  # Path B — structured evidence (Tranche B, 2026-05-05):
  #   <plan-dir>/<plan-slug>-evidence/<task-id>.evidence.json
  # ============================================================
  #
  # Falls through from prose; either path may authorize.
  #
  # Schema: adapters/claude-code/schemas/evidence.schema.json. The hook
  # checks (a) the JSON file exists and is mtime-fresh (< 120s), (b) it
  # parses as JSON, and (c) its `task_id` field matches the task being
  # checked. The structured artifact does NOT require a Runtime verification
  # entry to authorize the flip — `mechanical_checks` is the equivalent
  # signal for non-runtime tasks. Runtime tasks should still populate
  # `runtime_evidence`; task-verifier enforces the runtime-replayability
  # mandate at verdict-decision time.
  local plan_dir plan_slug structured_dir structured_file
  plan_dir=$(dirname "$plan_file")
  plan_slug=$(basename "$plan_file" .md)
  structured_dir="$plan_dir/${plan_slug}-evidence"
  structured_file="$structured_dir/${task_id}.evidence.json"

  if [[ -f "$structured_file" ]]; then
    local now2 mtime2 age2
    now2=$(date +%s)
    mtime2=$(stat -c %Y "$structured_file" 2>/dev/null || echo 0)
    age2=$((now2 - mtime2))
    if [[ "$age2" -le 120 ]]; then
      # Parse with jq; require well-formed JSON whose task_id matches.
      if jq -e --arg id "$task_id" '.task_id == $id' "$structured_file" >/dev/null 2>&1; then
        return 0
      fi
    fi
  fi

  return 1
}

# For Edit calls: look at old_string vs new_string
if [[ "$TOOL_NAME" == "Edit" ]]; then
  if [[ "$HAS_NESTED" == "true" ]]; then
    OLD_STR=$(echo "$INPUT" | jq -r '.tool_input.old_string // ""' 2>/dev/null)
    NEW_STR=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null)
  else
    OLD_STR=$(echo "$INPUT" | jq -r '.old_string // ""' 2>/dev/null)
    NEW_STR=$(echo "$INPUT" | jq -r '.new_string // ""' 2>/dev/null)
  fi

  # Does the old string contain an unchecked box AND the new string contain
  # a checked box? If yes, this is a checkbox flip.
  if echo "$OLD_STR" | grep -qE '^\s*-\s*\[\s*\]'; then
    if echo "$NEW_STR" | grep -qE '^\s*-\s*\[\s*[xX]\s*\]'; then
      # Extract the task ID from the new_string (format: - [x] A.1 ...)
      TASK_ID=$(echo "$NEW_STR" | grep -oE '\[[xX]\][[:space:]]+[A-Z]+\.[0-9]+(\.[0-9]+)*' | grep -oE '[A-Z]+\.[0-9]+(\.[0-9]+)*' | head -1)

      # Acquire the per-plan lock so two parallel verifiers serialize on
      # evidence-mtime + checkbox-flip decisions. If the lock cannot be
      # acquired within 30s, treat as block (cannot safely authorize).
      if ! acquire_plan_lock "$FILE_PATH"; then
        cat >&2 <<ERR

================================================================
PLAN EDIT BLOCKED — could not acquire plan lock within 30s
================================================================

Another verifier appears to hold ${FILE_PATH}.lock. Retry shortly.
If the lock is stale (previous verifier crashed), remove the lock
file manually and retry:

  rm -f "${FILE_PATH}.lock"

ERR
        exit 1
      fi

      # Risk-tiered routing (Tranche D, 2026-05-05):
      # Read the per-task `Verification:` declaration from the plan file
      # and route the evidence-freshness check accordingly.
      #   - mechanical: structured `.evidence.json` (PASS verdict, fresh
      #     mtime, matching task_id) OR fresh one-line `Commit:` block
      #   - contract: structured `.evidence.json` with non-empty
      #     mechanical_checks (e.g., schema-valid:) OR fresh one-line
      #     `Commit:` block
      #   - full (default): existing prose-with-runtime-verification or
      #     structured `.evidence.json` per Tranche B's check_evidence_first
      VERIFICATION_LEVEL=""
      if [[ -n "$TASK_ID" ]]; then
        VERIFICATION_LEVEL=$(extract_verification_level "$FILE_PATH" "$TASK_ID")
      fi

      if [[ "$VERIFICATION_LEVEL" == "mechanical" ]] || [[ "$VERIFICATION_LEVEL" == "contract" ]]; then
        if [[ -n "$TASK_ID" ]] && check_mechanical_or_contract_evidence "$FILE_PATH" "$TASK_ID" "$VERIFICATION_LEVEL"; then
          # Lock auto-releases on exit via the EXIT trap.
          exit 0
        fi
      else
        # Default `full` behavior: existing evidence-first escape hatch
        if [[ -n "$TASK_ID" ]] && check_evidence_first "$FILE_PATH" "$TASK_ID"; then
          # Lock auto-releases on exit via the EXIT trap.
          exit 0
        fi
      fi
      cat >&2 <<'ERR'

================================================================
PLAN EDIT BLOCKED — Generation 4 plan-edit-validator
================================================================

You are trying to flip a plan task checkbox from [ ] to [x] by
editing the plan file directly. This is forbidden.

The authorized path (evidence-first): before editing the plan file,
append a valid evidence block to the companion evidence file:

    ${FILE_PATH%.md}-evidence.md

The evidence block must:
  1. Have been written in the last 120 seconds (the hook checks mtime)
  2. Contain a line: "Task ID: <id>" matching the task you are checking
  3. Contain at least one "Runtime verification:" line in one of the
     replayable formats (test/curl/sql/playwright/file)

Only AFTER the evidence file is written may the plan checkbox flip.
The runtime verification will be re-executed at session-end by the
pre-stop-verifier hook — fabricated evidence is caught there.

Why this works where a marker file didn't:
  A marker file is a 1-command bypass. Writing a real evidence block
  with a Runtime verification: command that actually succeeds when
  executed requires doing the actual work. The adversarial review
  killed the marker-file escape hatch; this is the replacement.

ERR
      exit 1
    fi
  fi

  # Also block Status: <non-COMPLETED> → Status: COMPLETED transitions
  # unless an evidence file already exists for the plan
  if echo "$OLD_STR" | grep -qE '^Status:\s*(ACTIVE|DEFERRED)'; then
    if echo "$NEW_STR" | grep -qE '^Status:\s*COMPLETED'; then
      # Derive the evidence file path: foo.md -> foo-evidence.md
      EVIDENCE_FILE="${FILE_PATH_NORM%.md}-evidence.md"
      if [[ ! -f "$EVIDENCE_FILE" ]]; then
        cat >&2 <<ERR

================================================================
PLAN EDIT BLOCKED — Status COMPLETED without evidence file
================================================================

You are trying to mark a plan as Status: COMPLETED, but there is
no evidence file at:

  $EVIDENCE_FILE

A plan cannot be marked COMPLETED without evidence blocks for every
task. The task-verifier agent writes evidence to this file as it
verifies each task.

To resolve: run the task-verifier on every unchecked task first.
Once each task has an evidence block, COMPLETED is allowed.

To defer the plan instead, set Status: DEFERRED with a reason.
To abandon, set Status: ABANDONED with a reason.

ERR
        exit 1
      fi
    fi
  fi
fi

# For Write calls: compare the count of [x] boxes in old vs new content
if [[ "$TOOL_NAME" == "Write" ]]; then
  NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null)

  # If the file doesn't exist yet, it's a new plan file — allow
  if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
  fi

  OLD_CHECKED=$(grep -cE '^\s*-\s*\[\s*[xX]\s*\]' "$FILE_PATH" 2>/dev/null || echo "0")
  OLD_CHECKED=$(echo "$OLD_CHECKED" | tr -d '[:space:]')
  NEW_CHECKED=$(echo "$NEW_CONTENT" | grep -cE '^\s*-\s*\[\s*[xX]\s*\]' 2>/dev/null || echo "0")
  NEW_CHECKED=$(echo "$NEW_CHECKED" | tr -d '[:space:]')

  if [[ "$NEW_CHECKED" -gt "$OLD_CHECKED" ]]; then
    cat >&2 <<ERR

================================================================
PLAN WRITE BLOCKED — checkbox count increased via Write
================================================================

You are trying to Write the plan file with MORE checked boxes
($NEW_CHECKED) than currently exist on disk ($OLD_CHECKED).

This is a bypass attempt on the Edit-level block. Write operations
cannot be used to self-check tasks either. Only the task-verifier
agent is authorized.

To resolve: invoke the task-verifier agent via the Task tool.

ERR
    exit 1
  fi

  # Same Status-COMPLETED check for Write
  if echo "$NEW_CONTENT" | grep -qE '^Status:\s*COMPLETED' 2>/dev/null; then
    if ! grep -qE '^Status:\s*COMPLETED' "$FILE_PATH" 2>/dev/null; then
      EVIDENCE_FILE="${FILE_PATH_NORM%.md}-evidence.md"
      if [[ ! -f "$EVIDENCE_FILE" ]]; then
        cat >&2 <<ERR

================================================================
PLAN WRITE BLOCKED — Status COMPLETED without evidence file
================================================================

Cannot write Status: COMPLETED to this plan. No evidence file at:
  $EVIDENCE_FILE

Run task-verifier on every unchecked task first.

ERR
        exit 1
      fi
    fi
  fi
fi

exit 0
