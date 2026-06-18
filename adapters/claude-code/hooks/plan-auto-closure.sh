#!/bin/bash
# plan-auto-closure.sh
#
# PostToolUse hook (Edit|Write) implementing R4 of the plan-lifecycle
# redesign (ADR 036-c): AUTO-CLOSURE on evidence.
#
# When a task-verifier checkbox-flip Edit lands on a top-level plan file
# under docs/plans/ and that flip makes ALL of the plan's tasks `[x]`, this
# hook invokes the deterministic closure backend:
#
#     close-plan.sh close <slug> --auto --no-push
#
# close-plan.sh --auto independently confirms the predefined Closure Contract
# artifact (PASS verdict + matching COMMITTED plan SHA, or self-test evidence
# for acceptance-exempt plans) before flipping Status. If the contract is not
# satisfied, --auto exits 2 (HOLD) and the plan stays ACTIVE — nothing is
# half-closed. This hook is FIRE-AND-ANNOTATE: it logs the outcome to stderr
# and ALWAYS exits 0; a PostToolUse hook runs after the tool already
# completed, so blocking is meaningless.
#
# Correctness invariants (the traps the plan §7/§8 pin):
#
#   - SHA-MATCH BASIS = COMMITTED plan SHA, NOT the working tree. The match
#     is performed inside close-plan.sh --auto via
#     `git log -n 1 --pretty=format:%H -- <plan-file>`. At fire time the
#     triggering checkbox-flip Edit is uncommitted, so the working tree
#     differs from the committed plan; the PASS artifact was written against
#     the committed version and the final [ ]→[x] flip changes only task
#     state, not the acceptance scenarios the artifact verified.
#
#   - --no-push IS MANDATORY in auto mode (an unattended PostToolUse hook
#     silently pushing to origin is an unacceptable blast radius). --auto
#     implies --no-push; we pass both explicitly as belt-and-suspenders.
#
#   - PostToolUse CANNOT BLOCK. This hook never returns non-zero on the
#     triggering tool call. Every runtime path exits 0.
#
#   - NO DOUBLE-ARCHIVE / NO RECURSE. close-plan.sh flips Status via a bash
#     `sed` write and archives via a bash `git mv` — neither is an Edit/Write
#     TOOL call, so neither fires a PostToolUse event. Therefore (a) this
#     hook does not recurse on close-plan's own writes, and (b)
#     plan-lifecycle.sh does NOT also fire on the Status flip — close-plan's
#     inline fallback is the sole archival path under auto-closure. Verified
#     against the same invariant plan-lifecycle.sh and close-plan.sh §8 rely
#     on (bash writes fire no PostToolUse event).
#
#   - ALL TASKS MUST BE [x] AND >= 1 task must exist. A zero-task plan never
#     "completes by last-task-flip" (T8). A flip on a non-final task leaves
#     >= 1 task unchecked → no closure attempt (T9). This is the primary
#     false-positive guard at the hook layer; the artifact gate (in
#     close-plan --auto) is the second.
#
#   - IDEMPOTENT on terminal status. If the plan is already
#     COMPLETED/archived (Status != ACTIVE), close-plan --auto exits 2 and
#     this hook no-ops (T10).
#
# Target-repo resolution: like plan-lifecycle.sh, ALL git operations run
# against the repo CONTAINING the edited plan file (derived from
# tool_input.file_path), never the hook process's cwd — a session rooted in
# repo A editing a plan in sibling repo B must close B's plan, not touch A.
# close-plan.sh resolves repo root itself via git rev-parse, so we cd into
# the file's directory before invoking it.
#
# Self-test: invoke with `--self-test`. Builds synthetic git repos and
# exercises the T1-T11b no-false-positive matrix from the plan's Testing
# Strategy. Exits 0 on all scenarios matching expectations, 1 otherwise.

set -u

SCRIPT_NAME="plan-auto-closure.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- helpers ----------------------------------------------------

# Normalize a path for matching: forward slashes only.
normalize_path() {
  printf '%s' "$1" | tr '\\' '/'
}

# Locate close-plan.sh. Repo-relative first (canonical source), then the
# live mirror at ~/.claude/scripts/, then a sibling of this script.
locate_close_plan() {
  local repo_root="$1"
  local candidates=(
    "$repo_root/adapters/claude-code/scripts/close-plan.sh"
    "$HOME/.claude/scripts/close-plan.sh"
    "$SCRIPT_DIR/../scripts/close-plan.sh"
  )
  local c
  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

# Extract the Status value from a content file. Echoes uppercase token or
# empty.
extract_status_from_file() {
  awk '
    /^Status:[[:space:]]*[A-Za-z][A-Za-z0-9_-]*/ {
      sub(/^Status:[[:space:]]*/, "", $0)
      sub(/[[:space:]].*$/, "", $0)
      print toupper($0)
      exit
    }
  ' "$1" 2>/dev/null
}

# Count tasks in a plan's `## Tasks` section(s). Echoes two integers on one
# line: "<total> <unchecked>". A task is a top-level `- [ ]` / `- [x]`
# checkbox line under a heading whose title contains "Task" (case-insensitive)
# — matching the section-awareness plan-reviewer Check 1/13 use. Indented
# sub-checkboxes are NOT counted as top-level tasks (they belong to a parent).
count_tasks() {
  awk '
    BEGIN { in_tasks = 0; total = 0; unchecked = 0 }
    /^## / {
      title = $0
      sub(/^## +/, "", title)
      if (tolower(title) ~ /task/) { in_tasks = 1 } else { in_tasks = 0 }
      next
    }
    in_tasks && /^- \[[ xX]\]/ {
      total++
      if ($0 ~ /^- \[[ ]\]/) unchecked++
    }
    END { print total " " unchecked }
  ' "$1" 2>/dev/null
}

# The core decision: given a plan file path, decide whether to attempt
# auto-closure and (if so) invoke close-plan.sh --auto --no-push. Emits
# [auto-closure] diagnostics to stderr. Never returns non-zero in a way that
# would block (callers ignore the return; the hook always exits 0).
#
# Args: $1 = plan file path (absolute or relative)
process_auto_closure() {
  local file_path="$1"
  local norm
  norm=$(normalize_path "$file_path")

  # Activation guard: top-level plan markdown only. archive/ and deferred/
  # are resting places. Evidence companions never trigger closure.
  case "$norm" in
    *docs/plans/archive/*) return 0 ;;
    *docs/plans/deferred/*) return 0 ;;
    *-evidence.md) return 0 ;;
    *docs/plans/*.md) ;;
    *) return 0 ;;
  esac

  # File must exist on disk (PostToolUse runs after the write completed).
  [ -f "$file_path" ] || return 0

  local slug
  slug=$(basename "$norm" .md)

  # Resolve the repo containing the edited plan (never the process cwd).
  local file_dir repo_root
  file_dir=$(dirname "$norm")
  [ -d "$file_dir" ] || return 0
  repo_root=$(git -C "$file_dir" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -z "$repo_root" ]; then
    # Not inside a git work tree — auto-closure relies on git SHA matching
    # and inline archival; nothing safe to do. No-op.
    return 0
  fi

  # Only act on a plan whose CURRENT (post-edit, on-disk) Status is ACTIVE.
  # A terminal-status plan is already closed/archived → idempotent no-op (T10).
  local status
  status=$(extract_status_from_file "$file_path")
  if [ "$status" != "ACTIVE" ]; then
    return 0
  fi

  # Count tasks. Must have >= 1 task and ZERO unchecked (T8, T9).
  local counts total unchecked
  counts=$(count_tasks "$file_path")
  total=$(printf '%s' "$counts" | awk '{print $1}')
  unchecked=$(printf '%s' "$counts" | awk '{print $2}')
  total=${total:-0}
  unchecked=${unchecked:-0}

  if [ "$total" -eq 0 ]; then
    printf '[auto-closure] plan %s: 0 tasks; decision HOLD (zero-task plan cannot complete by last-task-flip; close manually).\n' "$slug" >&2
    return 0
  fi
  if [ "$unchecked" -gt 0 ]; then
    printf '[auto-closure] plan %s: tasks %d/%d checked (%d unchecked); decision HOLD (not all tasks complete).\n' "$slug" "$((total - unchecked))" "$total" "$unchecked" >&2
    return 0
  fi

  # All tasks checked. Hand off to close-plan.sh --auto, which performs the
  # SECOND gate (Closure-Contract artifact: PASS + matching committed SHA,
  # or self-test evidence for acceptance-exempt). --auto implies --no-push;
  # we pass both explicitly.
  local close_plan
  close_plan=$(locate_close_plan "$repo_root") || {
    printf '[auto-closure] plan %s: tasks %d/%d checked, but close-plan.sh not found; decision HOLD.\n' "$slug" "$total" "$total" >&2
    return 0
  }

  printf '[auto-closure] plan %s: tasks %d/%d checked; invoking close-plan.sh --auto --no-push (contract artifact gate next)...\n' "$slug" "$total" "$total" >&2

  # Run close-plan from inside the file's repo so its own git rev-parse
  # resolves the right root. Capture exit code; never propagate as a block.
  local cp_rc
  ( cd "$repo_root" && bash "$close_plan" close "$slug" --auto --no-push ) >&2 2>&1
  cp_rc=$?

  if [ "$cp_rc" -eq 0 ]; then
    printf '[auto-closure] plan %s: decision CLOSE — auto-closed and archived.\n' "$slug" >&2
  elif [ "$cp_rc" -eq 2 ]; then
    printf '[auto-closure] plan %s: decision HOLD — close-plan.sh returned 2 (Closure Contract artifact missing/stale/fail, or Status not ACTIVE). Plan left ACTIVE; see the [close-plan] reason above.\n' "$slug" >&2
  else
    printf '[auto-closure] plan %s: decision HOLD — close-plan.sh returned %d (unexpected). Plan left ACTIVE.\n' "$slug" "$cp_rc" >&2
  fi
  return 0
}

# ---------- self-test --------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  PASSED=0
  FAILED=0
  SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  # Build a synthetic repo with a real (committed) close-plan.sh available so
  # the auto path can run end-to-end. We copy the canonical close-plan.sh into
  # the synthetic repo's adapters/claude-code/scripts/ so locate_close_plan
  # finds it repo-relative.
  CANON_CLOSE_PLAN="$SCRIPT_DIR/../scripts/close-plan.sh"
  if [ ! -f "$CANON_CLOSE_PLAN" ]; then
    CANON_CLOSE_PLAN="$HOME/.claude/scripts/close-plan.sh"
  fi
  if [ ! -f "$CANON_CLOSE_PLAN" ]; then
    echo "self-test: cannot locate close-plan.sh to drive the auto path; aborting" >&2
    exit 1
  fi

  # mk_repo <dir>: init a synthetic repo with backlog + close-plan.sh.
  mk_repo() {
    local d="$1"
    (
      cd "$d" || exit 1
      git init -q
      git config user.email "test@example.test"
      git config user.name "Test"
      git config commit.gpgsign false
      mkdir -p docs/plans docs/plans/archive adapters/claude-code/scripts .claude/state
      cat > docs/backlog.md <<'EOF'
# Backlog
Last updated: 2026-06-15

## Open work
EOF
      cp "$CANON_CLOSE_PLAN" adapters/claude-code/scripts/close-plan.sh
    )
  }

  # ----- T1: all-checked + acceptance-exempt + mechanical evidence PASS
  #           → CLOSES (true positive; exempt contract = self-test). -----
  T1=$(mktemp -d); mk_repo "$T1"
  (
    cd "$T1" || exit 1
    cat > docs/plans/t1.md <<'EOF'
# Plan: T1
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-development; self-tests are the acceptance artifact.

## Goal
all checked + exempt + evidence → closes

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/t1.md`

## Evidence Log
EOF
    mkdir -p docs/plans/t1-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/t1-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    process_auto_closure "$PWD/docs/plans/t1.md"
  ) >/dev/null 2>&1
  # shellcheck source=/dev/null
  . /dev/null 2>/dev/null || true
  if [ -f "$T1/docs/plans/archive/t1.md" ] && grep -q '^Status: COMPLETED' "$T1/docs/plans/archive/t1.md"; then
    echo "self-test (T1) all-checked-exempt-evidence-PASS-CLOSES: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T1) all-checked-exempt-evidence-PASS-CLOSES: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T1"

  # ----- T2: one-task-unchecked + evidence present → does NOT close
  #           (primary false-positive guard at the hook layer). -----
  T2=$(mktemp -d); mk_repo "$T2"
  (
    cd "$T2" || exit 1
    cat > docs/plans/t2.md <<'EOF'
# Plan: T2
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-development; self-tests are the acceptance artifact.

## Goal
one unchecked → no close

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical
- [ ] 2. Second task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/t2.md`

## Evidence Log
EOF
    mkdir -p docs/plans/t2-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/t2-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    process_auto_closure "$PWD/docs/plans/t2.md"
  ) >/dev/null 2>&1
  if [ -f "$T2/docs/plans/t2.md" ] && grep -q '^Status: ACTIVE' "$T2/docs/plans/t2.md" \
     && [ ! -f "$T2/docs/plans/archive/t2.md" ]; then
    echo "self-test (T2) one-unchecked-does-NOT-close: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T2) one-unchecked-does-NOT-close: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T2"

  # ----- T3: non-exempt + all-checked + artifact MISSING → does NOT close. -----
  T3=$(mktemp -d); mk_repo "$T3"
  (
    cd "$T3" || exit 1
    cat > docs/plans/t3.md <<'EOF'
# Plan: T3
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: false

## Goal
non-exempt + no artifact → no close

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/t3.md`

## Evidence Log
EOF
    mkdir -p docs/plans/t3-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/t3-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    process_auto_closure "$PWD/docs/plans/t3.md"
  ) >/dev/null 2>&1
  if [ -f "$T3/docs/plans/t3.md" ] && grep -q '^Status: ACTIVE' "$T3/docs/plans/t3.md" \
     && [ ! -f "$T3/docs/plans/archive/t3.md" ]; then
    echo "self-test (T3) nonexempt-artifact-missing-does-NOT-close: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T3) nonexempt-artifact-missing-does-NOT-close: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T3"

  # ----- T4: non-exempt + all-checked + artifact STALE sha → does NOT close. -----
  T4=$(mktemp -d); mk_repo "$T4"
  (
    cd "$T4" || exit 1
    cat > docs/plans/t4.md <<'EOF'
# Plan: T4
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: false

## Goal
non-exempt + stale-sha artifact → no close

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/t4.md`

## Evidence Log
EOF
    mkdir -p docs/plans/t4-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/t4-evidence/1.evidence.json
    mkdir -p .claude/state/acceptance/t4
    printf '{"plan_slug":"t4","plan_commit_sha":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","scenarios":[{"id":"h","verdict":"PASS"}]}\n' \
      > .claude/state/acceptance/t4/sess.json
    git add . && git commit -q -m "init"
    process_auto_closure "$PWD/docs/plans/t4.md"
  ) >/dev/null 2>&1
  if [ -f "$T4/docs/plans/t4.md" ] && grep -q '^Status: ACTIVE' "$T4/docs/plans/t4.md" \
     && [ ! -f "$T4/docs/plans/archive/t4.md" ]; then
    echo "self-test (T4) nonexempt-stale-sha-does-NOT-close: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T4) nonexempt-stale-sha-does-NOT-close: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T4"

  # ----- T5: non-exempt + all-checked + artifact verdict FAIL → does NOT close. -----
  T5=$(mktemp -d); mk_repo "$T5"
  (
    cd "$T5" || exit 1
    cat > docs/plans/t5.md <<'EOF'
# Plan: T5
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: false

## Goal
non-exempt + FAIL-verdict artifact → no close

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/t5.md`

## Evidence Log
EOF
    mkdir -p docs/plans/t5-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/t5-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    plan_sha=$(git log -n 1 --pretty=format:'%H' -- docs/plans/t5.md)
    mkdir -p .claude/state/acceptance/t5
    printf '{"plan_slug":"t5","plan_commit_sha":"%s","scenarios":[{"id":"h","verdict":"FAIL"}]}\n' "$plan_sha" \
      > .claude/state/acceptance/t5/sess.json
    process_auto_closure "$PWD/docs/plans/t5.md"
  ) >/dev/null 2>&1
  if [ -f "$T5/docs/plans/t5.md" ] && grep -q '^Status: ACTIVE' "$T5/docs/plans/t5.md" \
     && [ ! -f "$T5/docs/plans/archive/t5.md" ]; then
    echo "self-test (T5) nonexempt-verdict-FAIL-does-NOT-close: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T5) nonexempt-verdict-FAIL-does-NOT-close: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T5"

  # ----- T7: exempt + all-checked + self-test evidence MISSING → does NOT
  #           close (close-plan per-task mechanical verification BLOCKS). -----
  T7=$(mktemp -d); mk_repo "$T7"
  (
    cd "$T7" || exit 1
    cat > docs/plans/t7.md <<'EOF'
# Plan: T7
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-development; self-tests are the acceptance artifact.

## Goal
exempt + missing evidence → no close

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/t7.md`

## Evidence Log
EOF
    # NO evidence dir / file — per-task mechanical verify must FAIL.
    git add . && git commit -q -m "init"
    process_auto_closure "$PWD/docs/plans/t7.md"
  ) >/dev/null 2>&1
  if [ -f "$T7/docs/plans/t7.md" ] && grep -q '^Status: ACTIVE' "$T7/docs/plans/t7.md" \
     && [ ! -f "$T7/docs/plans/archive/t7.md" ]; then
    echo "self-test (T7) exempt-evidence-missing-does-NOT-close: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T7) exempt-evidence-missing-does-NOT-close: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T7"

  # ----- T8: zero-task plan → does NOT auto-close. -----
  T8=$(mktemp -d); mk_repo "$T8"
  (
    cd "$T8" || exit 1
    cat > docs/plans/t8.md <<'EOF'
# Plan: T8
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-development; self-tests are the acceptance artifact.

## Goal
zero tasks → no auto-close

## Scope
- IN: x
- OUT: y

## Tasks

## Files to Modify/Create
- `docs/plans/t8.md`
EOF
    git add . && git commit -q -m "init"
    process_auto_closure "$PWD/docs/plans/t8.md"
  ) >/dev/null 2>&1
  if [ -f "$T8/docs/plans/t8.md" ] && grep -q '^Status: ACTIVE' "$T8/docs/plans/t8.md" \
     && [ ! -f "$T8/docs/plans/archive/t8.md" ]; then
    echo "self-test (T8) zero-task-does-NOT-auto-close: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T8) zero-task-does-NOT-auto-close: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T8"

  # ----- T9: non-final-task flip (2 of 3 checked) → no closure attempt. -----
  T9=$(mktemp -d); mk_repo "$T9"
  (
    cd "$T9" || exit 1
    cat > docs/plans/t9.md <<'EOF'
# Plan: T9
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-development; self-tests are the acceptance artifact.

## Goal
non-final flip → no closure

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First. Verification: mechanical
- [x] 2. Second. Verification: mechanical
- [ ] 3. Third. Verification: mechanical

## Files to Modify/Create
- `docs/plans/t9.md`
EOF
    git add . && git commit -q -m "init"
    process_auto_closure "$PWD/docs/plans/t9.md"
  ) >/dev/null 2>&1
  if [ -f "$T9/docs/plans/t9.md" ] && grep -q '^Status: ACTIVE' "$T9/docs/plans/t9.md" \
     && [ ! -f "$T9/docs/plans/archive/t9.md" ]; then
    echo "self-test (T9) non-final-task-flip-no-attempt: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T9) non-final-task-flip-no-attempt: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T9"

  # ----- T10: re-fire on already-COMPLETED/archived plan → idempotent no-op.
  #            (Status != ACTIVE on disk → hook no-ops before invoking close.) -----
  T10=$(mktemp -d); mk_repo "$T10"
  (
    cd "$T10" || exit 1
    cat > docs/plans/t10.md <<'EOF'
# Plan: T10
Status: COMPLETED
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-development; self-tests are the acceptance artifact.

## Goal
already completed → no-op

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First. Verification: mechanical

## Files to Modify/Create
- `docs/plans/t10.md`
EOF
    git add . && git commit -q -m "init"
    OUT=$(process_auto_closure "$PWD/docs/plans/t10.md" 2>&1)
    # No archival should occur, no [auto-closure] CLOSE line.
    printf '%s' "$OUT" > /tmp/t10out.$$ 2>/dev/null || true
  ) >/dev/null 2>&1
  if [ -f "$T10/docs/plans/t10.md" ] && [ ! -f "$T10/docs/plans/archive/t10.md" ]; then
    echo "self-test (T10) refire-on-completed-idempotent-noop: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T10) refire-on-completed-idempotent-noop: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T10"

  # ----- T11a: thin task list (1 task, trivially-satisfiable exempt contract)
  #             → CLOSES; documents that auto-closure has NO runtime guard
  #             against thinness (the guard is creation-time Check 15/16 +
  #             plan-time review). ADR 036 R1 residual, made explicit. -----
  T11a=$(mktemp -d); mk_repo "$T11a"
  (
    cd "$T11a" || exit 1
    cat > docs/plans/t11a.md <<'EOF'
# Plan: T11a
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-development; self-tests are the acceptance artifact.

## Goal
thin single-task plan auto-closes (no runtime thinness guard)

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. Trivial. Verification: mechanical

## Files to Modify/Create
- `docs/plans/t11a.md`

## Evidence Log
EOF
    mkdir -p docs/plans/t11a-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/t11a-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    process_auto_closure "$PWD/docs/plans/t11a.md"
  ) >/dev/null 2>&1
  if [ -f "$T11a/docs/plans/archive/t11a.md" ] && grep -q '^Status: COMPLETED' "$T11a/docs/plans/archive/t11a.md"; then
    echo "self-test (T11a) thin-task-list-CLOSES-guard-is-creation-time: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T11a) thin-task-list-CLOSES-guard-is-creation-time: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T11a"

  # ----- T11b: non-exempt artifact matches the plan's COMMITTED SHA while the
  #             working tree holds the uncommitted final checkbox-flip → CLOSES.
  #             Pins the §7 match basis: compare against the committed SHA, not
  #             the working tree. -----
  T11b=$(mktemp -d); mk_repo "$T11b"
  (
    cd "$T11b" || exit 1
    # Commit the plan with the final task UNCHECKED + write the artifact
    # against that committed SHA. Then flip the checkbox in the working tree
    # only (uncommitted) — mirroring the real task-verifier flip at fire time.
    cat > docs/plans/t11b.md <<'EOF'
# Plan: T11b
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: false

## Goal
artifact matches committed SHA, working tree has uncommitted flip → closes

## Scope
- IN: x
- OUT: y

## Tasks
- [ ] 1. First. Verification: mechanical

## Files to Modify/Create
- `docs/plans/t11b.md`

## Evidence Log
EOF
    mkdir -p docs/plans/t11b-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/t11b-evidence/1.evidence.json
    git add . && git commit -q -m "init (task unchecked)"
    plan_sha=$(git log -n 1 --pretty=format:'%H' -- docs/plans/t11b.md)
    mkdir -p .claude/state/acceptance/t11b
    printf '{"plan_slug":"t11b","plan_commit_sha":"%s","scenarios":[{"id":"h","verdict":"PASS"}]}\n' "$plan_sha" \
      > .claude/state/acceptance/t11b/sess.json
    # Now flip the checkbox in the WORKING TREE only (uncommitted).
    sed -e 's/^- \[ \] 1\. First\./- [x] 1. First./' docs/plans/t11b.md > docs/plans/t11b.md.tmp \
      && mv docs/plans/t11b.md.tmp docs/plans/t11b.md
    process_auto_closure "$PWD/docs/plans/t11b.md"
  ) >/dev/null 2>&1
  if [ -f "$T11b/docs/plans/archive/t11b.md" ] && grep -q '^Status: COMPLETED' "$T11b/docs/plans/archive/t11b.md"; then
    echo "self-test (T11b) committed-sha-match-uncommitted-flip-CLOSES: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T11b) committed-sha-match-uncommitted-flip-CLOSES: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T11b"

  # ----- T12: activation guard — an edit to an ARCHIVED plan never triggers. -----
  T12=$(mktemp -d); mk_repo "$T12"
  (
    cd "$T12" || exit 1
    cat > docs/plans/archive/t12.md <<'EOF'
# Plan: T12
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: x.

## Tasks
- [x] 1. First. Verification: mechanical
EOF
    git add . && git commit -q -m "init"
    process_auto_closure "$PWD/docs/plans/archive/t12.md"
  ) >/dev/null 2>&1
  # Archived plan must be untouched (still in archive/, still ACTIVE text).
  if [ -f "$T12/docs/plans/archive/t12.md" ] && grep -q '^Status: ACTIVE' "$T12/docs/plans/archive/t12.md"; then
    echo "self-test (T12) archived-plan-never-triggers: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (T12) archived-plan-never-triggers: FAIL" >&2; FAILED=$((FAILED+1))
  fi
  rm -rf "$T12"

  printf '\nself-test summary: %d passed, %d failed (of %d scenarios)\n' \
    "$PASSED" "$FAILED" "$((PASSED+FAILED))" >&2
  if [ "$FAILED" -gt 0 ]; then exit 1; fi
  exit 0
fi

# ---------- main path --------------------------------------------------

# Read the tool invocation JSON. Same dual-source pattern as plan-lifecycle.sh.
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [ -z "$INPUT" ] && [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL_NAME" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .file_path // ""' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

NORM=$(normalize_path "$FILE_PATH")
case "$NORM" in
  *docs/plans/*.md) ;;
  *) exit 0 ;;
esac

process_auto_closure "$FILE_PATH"

# PostToolUse cannot block; always allow.
exit 0
