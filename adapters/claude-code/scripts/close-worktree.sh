#!/bin/bash
# close-worktree.sh — deterministic closer for the "worktree/builder" work-item
# type (accountable-estate T4, generalizing the close-plan.sh pattern).
#
# design docs/designs/accountable-estate-2026-07-27.md §6c:
#   "Closure is a phase of the work, not cleanup afterwards. Every work-item
#    type gets a deterministic CLOSER script (the close-plan.sh pattern
#    generalized — seconds, no agent discretion): builder items close via
#    verify -> merge (through the merge lock below) -> worktree remove ->
#    branch delete (or explicit preserve+reason) -> ledger transition to
#    done(outcome-link) -> done event. A work item without a closer receipt
#    cannot reach `done`."
#
# HONEST SCOPE NARROWING vs the design paragraph above (state this, don't
# hide it — same discipline admission-lib.sh's header uses for T3):
#   - "through the merge lock" names T5 (estate merge lock + single
#     deterministic merge script), which is NOT YET BUILT. This closer does
#     NOT invent T5's job. It checks whether the branch is ALREADY integrated
#     (ancestor of a resolved base ref) — if not, it refuses and requires
#     either an out-of-band merge (today's PR flow) first, or an EXPLICIT
#     --keep-branch --reason (the design's own "or explicit preserve+reason"
#     escape valve). When T5 lands, its merge script is the thing this
#     closer's integration check should call BEFORE the ancestor check,
#     in the same commit that closes T5.
#   - "ledger transition to done(outcome-link)" names the full obligation
#     store from T2/P1, which is also not built. The closed REGISTRATION
#     record (estate-registration-lib.sh's reg_close, called via
#     spawn-worktree.sh --remove below) IS a real, on-disk done-record today
#     — slug/path/branch/plan/task/who + closed_at/disposition — just not
#     yet consumed by a broader obligation-store view. That gap is named,
#     not invented away.
#
# Verify step: this closer requires EITHER (a) --plan/--task naming a task
# whose evidence carries `Task ID: <task> ... Verdict: PASS` (mirroring
# close-plan.sh's verify_task_full acceptance shape), OR (b) an explicit
# --verified flag (the caller vouches; recorded on the closed registration as
# `verify_mode`). No silent third path — same "no script-level override"
# philosophy close-plan.sh's own header commits to.
#
# Usage:
#   close-worktree.sh close <slug> --plan <plan-slug> --task <task-id> [options]
#   close-worktree.sh close <slug> --verified [options]
#   close-worktree.sh --self-test
#   close-worktree.sh --help
#
# Options:
#   --repo <path>          main checkout to operate on (default: cwd)
#   --keep-branch          explicit preserve — required alongside --reason
#                          when the branch is not yet integrated
#   --reason <text>        required with --keep-branch (the design's "explicit
#                          preserve+reason"); recorded as the disposition
#   --force                pass through to spawn-worktree.sh --remove for an
#                          otherwise-clean-by-git-status worktree that still
#                          carries ignored/scratch noise (same meaning as
#                          that script's own --force; NEVER auto-applied)
#   --quiet                suppress narration
#
# Exit codes:
#   0  closed (or a --remove no-op because nothing was registered)
#   1  generic failure (spawn-worktree.sh --remove itself failed)
#   2  usage error OR a hard block (no verification, unintegrated branch with
#      no --keep-branch --reason, dirty worktree with no --force)
#   3  --self-test failure
set -u

SCRIPT_NAME="close-worktree.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

usage() {
  sed -n '2,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

log() { [ "${QUIET:-0}" = 1 ] || echo "$@" >&2; }

# ---------------------------------------------------------------------------
# Verify step — mirrors close-plan.sh's verify_task_full acceptance shape
# (duplicated, not sourced: close-plan.sh's function is private to that
# script's own CLI process, the same one-helper-per-caller convention that
# script's own header already uses for cp_compute_content_hash).
# ---------------------------------------------------------------------------
_cw_locate_plan_file() {
  local slug="$1"
  if [[ -f "docs/plans/$slug.md" ]]; then printf '%s\n' "docs/plans/$slug.md"; return 0; fi
  if [[ -f "docs/plans/archive/$slug.md" ]]; then printf '%s\n' "docs/plans/archive/$slug.md"; return 0; fi
  return 1
}

_cw_verify_task_pass() {
  local plan_slug="$1" task_id="$2"
  local plan_file; plan_file="$(_cw_locate_plan_file "$plan_slug")" || return 1
  local plan_dir; plan_dir="$(dirname "$plan_file")"
  local evidence_file="$plan_dir/${plan_slug}-evidence.md"

  local search_files=("$plan_file")
  [[ -f "$evidence_file" ]] && search_files+=("$evidence_file")

  local f
  for f in "${search_files[@]}"; do
    if awk -v tid="$task_id" '
      BEGIN { found_id=0; found_pass=0 }
      /Task[[:space:]]+(ID:[[:space:]]*)?[A-Za-z0-9.-]+/ {
        if (found_id && found_pass) exit 0
        found_id=0; found_pass=0
        if (match($0, "Task[[:space:]]+(ID:[[:space:]]*)?" tid "([^A-Za-z0-9.-]|$)")) { found_id=1 }
      }
      found_id && /Verdict:[[:space:]]*PASS/ { found_pass=1 }
      END { exit (found_id && found_pass) ? 0 : 1 }
    ' "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Integration check — is the branch already an ancestor of a resolved base?
# Mirrors worktree-hygiene-sweep.sh's own resolve_base + is-ancestor idiom
# (four candidate refs, not just one — an origin/master that lags a local
# merge must not false-refuse).
# ---------------------------------------------------------------------------
_cw_is_integrated() {
  local repo="$1" branch="$2" alt
  for alt in origin/master origin/main master main; do
    if git -C "$repo" rev-parse --verify --quiet "$alt" >/dev/null 2>&1; then
      if git -C "$repo" merge-base --is-ancestor "refs/heads/$branch" "$alt" 2>/dev/null; then
        return 0
      fi
    fi
  done
  return 1
}

_cw_scrub_reason() {
  # Same conservative whitelist as estate-registration-lib.sh's _reg_scrub —
  # a --reason ends up inside the closed registration's disposition field.
  local v="$1"
  v="${v//[^A-Za-z0-9._ -]/}"
  v="${v// /-}"
  printf '%s' "${v:0:64}"
}

# ---------------------------------------------------------------------------
# close subcommand
# ---------------------------------------------------------------------------
cmd_close() {
  local slug="" repo="" plan="" task="" verified=0 keep_branch=0 reason="" force=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) shift; repo="${1:-}" ;;
      --plan) shift; plan="${1:-}" ;;
      --task) shift; task="${1:-}" ;;
      --verified) verified=1 ;;
      --keep-branch) keep_branch=1 ;;
      --reason) shift; reason="${1:-}" ;;
      --force) force=1 ;;
      --quiet) QUIET=1 ;;
      --*) echo "$SCRIPT_NAME: unknown flag: $1" >&2; return 2 ;;
      *)
        if [[ -z "$slug" ]]; then slug="$1"; else echo "$SCRIPT_NAME: unexpected arg: $1" >&2; return 2; fi
        ;;
    esac
    shift
  done

  [[ -n "$slug" ]] || { echo "$SCRIPT_NAME: close requires a <slug>" >&2; return 2; }
  repo="${repo:-$(pwd)}"
  local main; main="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "$SCRIPT_NAME: --repo is not a usable git repo: $repo" >&2; return 2; }

  local wt="$main/.claude/worktrees/$slug"
  if ! git -C "$main" worktree list --porcelain | grep -qxF "worktree $wt"; then
    log "$SCRIPT_NAME: no registered worktree at $wt — nothing to close"
    return 0
  fi

  # --- 1. VERIFY ---
  if [[ -n "$plan" && -n "$task" ]]; then
    if ! _cw_verify_task_pass "$plan" "$task"; then
      echo "$SCRIPT_NAME: BLOCKED — no 'Task ID: $task ... Verdict: PASS' evidence found for plan '$plan'." >&2
      echo "  Remediation: get task-verifier to PASS the task first, or re-run with --verified to explicitly vouch." >&2
      return 2
    fi
    log "$SCRIPT_NAME: verify OK — plan=$plan task=$task has a PASS evidence block"
  elif [[ "$verified" == "1" ]]; then
    log "$SCRIPT_NAME: verify OK — caller passed --verified (explicit vouch, no plan/task evidence checked)"
  else
    echo "$SCRIPT_NAME: BLOCKED — no verification. Pass --plan <slug> --task <id> naming a task-verifier" >&2
    echo "  PASS evidence block, or --verified to explicitly vouch (recorded on the closed registration)." >&2
    echo "  No script-level default exists — a work item without a closer receipt cannot reach done." >&2
    return 2
  fi

  # --- 2. INTEGRATION (merge, or explicit preserve+reason) ---
  local branch; branch="$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null || echo "")"
  local disposition=""
  if [[ -n "$branch" ]] && _cw_is_integrated "$main" "$branch"; then
    disposition="merged"
    log "$SCRIPT_NAME: integration OK — branch $branch is already an ancestor of a resolved base ref"
  elif [[ "$keep_branch" == "1" ]]; then
    if [[ -z "$reason" ]]; then
      echo "$SCRIPT_NAME: BLOCKED — --keep-branch requires --reason <text> (design's 'explicit preserve+reason')." >&2
      return 2
    fi
    # NOTE: the disposition string round-trips through
    # estate-registration-lib.sh's reg_close -> _reg_scrub, whose whitelist
    # is [A-Za-z0-9._-] — NO COLON. A "preserved:<reason>" separator would be
    # silently stripped to "preservedreason" by that scrub (found by this
    # self-test, not assumed) — use a hyphen join instead, which survives.
    disposition="preserved-$(_cw_scrub_reason "$reason")"
    log "$SCRIPT_NAME: integration EXPLICITLY WAIVED — branch $branch kept, reason: $reason"
  else
    echo "$SCRIPT_NAME: BLOCKED — branch '$branch' is not yet integrated into master/main." >&2
    echo "  This closer does not merge (T5's merge lock owns that; not yet built)." >&2
    echo "  Either merge it first (existing PR flow) and re-run, or re-run with" >&2
    echo "  --keep-branch --reason '<why>' to explicitly preserve it unmerged." >&2
    return 2
  fi

  # --- 3/4/5. worktree remove -> branch delete/preserve -> registration close ---
  # Delegated to spawn-worktree.sh --remove, which already implements: refuse
  # on uncommitted changes unless --force, safe branch delete (`branch -d`,
  # never -D — unique unmerged work is never lost even if our integration
  # check above were somehow wrong), and (T4) the no-orphan DE-registration
  # via estate-registration-lib.sh's reg_close. One mechanical sequence, not
  # re-implemented here — the same DRY instinct close-plan.sh's own inline
  # archival step documents choosing.
  local rm_args=(--remove "$slug" --repo "$main" --disposition "$disposition")
  [[ "$force" == "1" ]] && rm_args+=(--force)
  [[ "${QUIET:-0}" == "1" ]] && rm_args+=(--quiet)

  if ! bash "$SCRIPT_DIR/spawn-worktree.sh" "${rm_args[@]}"; then
    echo "$SCRIPT_NAME: spawn-worktree.sh --remove failed for $slug (dirty worktree? re-run with --force after checking git status)" >&2
    return 1
  fi

  log "$SCRIPT_NAME: CLOSED $slug (disposition: $disposition)"
  return 0
}

# ---------------------------------------------------------------------------
# --self-test
# ---------------------------------------------------------------------------
_cw_self_test() {
  local PASS=0 FAIL=0
  pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
  fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }

  local T; T="$(mktemp -d 2>/dev/null)" || { echo "cannot mktemp"; return 1; }
  export HARNESS_SELFTEST=1
  export REG_STATE_DIR="$T/estate"   # pin, same reasoning as spawn-worktree.sh's own suite

  local R="$T/repo"
  git init -q -b master "$R"
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name t
  echo base > "$R/f.txt"; git -C "$R" add f.txt
  git -C "$R" -c commit.gpgsign=false commit -qm base

  local sw="$SCRIPT_DIR/spawn-worktree.sh"

  echo "Scenario 1: closing an unregistered slug is a no-op (rc 0)"
  bash "${BASH_SOURCE[0]}" close never-created --repo "$R" --verified --quiet
  local rc=$?
  [[ "$rc" == "0" ]] && pass "rc 0 for a slug with no registered worktree" || fail "rc $rc"

  echo "Scenario 2: no --plan/--task and no --verified -> BLOCKED (exit 2), worktree untouched"
  bash "$sw" wt-a --type commits --repo "$R" --apply --print-cd >/dev/null 2>&1
  bash "${BASH_SOURCE[0]}" close wt-a --repo "$R" --quiet
  rc=$?
  [[ "$rc" == "2" ]] && pass "unverified close refused (exit 2)" || fail "expected 2, got $rc"
  [[ -d "$R/.claude/worktrees/wt-a" ]] && pass "worktree left in place after the refusal" || fail "worktree removed despite the refusal"

  echo "Scenario 3: --verified + already-integrated branch (no new commits) -> closes cleanly, disposition=merged"
  bash "${BASH_SOURCE[0]}" close wt-a --repo "$R" --verified --quiet
  rc=$?
  [[ "$rc" == "0" ]] && pass "verified + integrated branch closes (exit 0)" || fail "expected 0, got $rc"
  [[ ! -d "$R/.claude/worktrees/wt-a" ]] && pass "worktree removed" || fail "worktree still present"
  local closedf="$REG_STATE_DIR/registrations/closed/wt-a.json"
  [[ -f "$closedf" ]] && pass "registration closed" || fail "no closed registration at $closedf"
  grep -q '"disposition":"merged"' "$closedf" 2>/dev/null && pass "disposition recorded as merged" || fail "disposition wrong: $(cat "$closedf" 2>/dev/null)"

  echo "Scenario 4: unintegrated branch, no --keep-branch -> BLOCKED (exit 2), branch+worktree untouched"
  bash "$sw" wt-b --type commits --repo "$R" --apply --print-cd >/dev/null 2>&1
  echo unique > "$R/.claude/worktrees/wt-b/u.txt"
  git -C "$R/.claude/worktrees/wt-b" add u.txt
  git -C "$R/.claude/worktrees/wt-b" -c commit.gpgsign=false commit -qm "unique work"
  bash "${BASH_SOURCE[0]}" close wt-b --repo "$R" --verified --quiet
  rc=$?
  [[ "$rc" == "2" ]] && pass "unintegrated branch with no --keep-branch refused (exit 2)" || fail "expected 2, got $rc"
  [[ -d "$R/.claude/worktrees/wt-b" ]] && pass "worktree left in place" || fail "worktree removed despite the refusal"

  echo "Scenario 5: unintegrated branch + --keep-branch with NO --reason -> BLOCKED (exit 2)"
  bash "${BASH_SOURCE[0]}" close wt-b --repo "$R" --verified --keep-branch --quiet
  rc=$?
  [[ "$rc" == "2" ]] && pass "--keep-branch with no --reason refused (exit 2)" || fail "expected 2, got $rc"

  echo "Scenario 6: unintegrated branch + --keep-branch --reason '<why>' -> closes, branch preserved, disposition names the reason"
  bash "${BASH_SOURCE[0]}" close wt-b --repo "$R" --verified --keep-branch --reason "operator wants to review this diff" --quiet
  rc=$?
  [[ "$rc" == "0" ]] && pass "explicit preserve+reason closes (exit 0)" || fail "expected 0, got $rc"
  [[ ! -d "$R/.claude/worktrees/wt-b" ]] && pass "worktree removed" || fail "worktree still present"
  git -C "$R" rev-parse --verify --quiet refs/heads/session/wt-b >/dev/null 2>&1 \
    && pass "branch PRESERVED (unmerged work never lost)" || fail "branch was deleted despite --keep-branch"
  local closedb="$REG_STATE_DIR/registrations/closed/wt-b.json"
  grep -q '"disposition":"preserved-operator-wants-to-review-this-diff"' "$closedb" 2>/dev/null \
    && pass "disposition names the preserve reason" || fail "disposition wrong: $(cat "$closedb" 2>/dev/null)"

  echo "Scenario 7: --plan/--task verify path — PASS evidence accepted, missing evidence refused"
  mkdir -p "$T/planrepo/docs/plans"
  cat > "$T/planrepo/docs/plans/demo-plan.md" <<'EOF'
# Plan - demo

## Evidence Log

Task ID: T9
Verdict: PASS
EOF
  bash "$sw" wt-c --type commits --repo "$R" --apply --print-cd >/dev/null 2>&1
  ( cd "$T/planrepo" && bash "${BASH_SOURCE[0]}" close wt-c --repo "$R" --plan demo-plan --task T9 --quiet )
  rc=$?
  [[ "$rc" == "0" ]] && pass "plan/task PASS evidence accepted, closes cleanly" || fail "expected 0, got $rc"

  bash "$sw" wt-d --type commits --repo "$R" --apply --print-cd >/dev/null 2>&1
  ( cd "$T/planrepo" && bash "${BASH_SOURCE[0]}" close wt-d --repo "$R" --plan demo-plan --task T-NONEXISTENT --quiet )
  rc=$?
  [[ "$rc" == "2" ]] && pass "plan/task with NO PASS evidence for that task id refused (exit 2)" || fail "expected 2, got $rc"
  [[ -d "$R/.claude/worktrees/wt-d" ]] && pass "worktree left in place after the unverified plan/task refusal" || fail "worktree removed despite the refusal"

  rm -rf "$T"
  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [[ "$FAIL" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
case "${1:-}" in
  close) shift; cmd_close "$@"; exit $? ;;
  --self-test) _cw_self_test; exit $? ;;
  --help|-h) usage; exit 0 ;;
  "") usage >&2; exit 2 ;;
  *) echo "$SCRIPT_NAME: unknown subcommand: $1" >&2; usage >&2; exit 2 ;;
esac
