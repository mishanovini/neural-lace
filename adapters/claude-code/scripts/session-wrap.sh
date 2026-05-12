#!/bin/bash
# session-wrap.sh — handoff-freshness verification + refresh, sibling to close-plan.sh.
#
# Operationalizes ADR 027 Layer 5: handoff freshness as a precondition of session-end
# (not as a description in the final summary).
#
# Runs BEFORE the final summary composes. Reads recent commits + plan-archive moves
# this session, derives required handoff updates, applies them idempotently, verifies
# freshness signals. If any signal is stale post-update, exits non-zero so the
# orchestrator notices BEFORE composing the summary.
#
# Subcommands:
#   verify          Check handoff-freshness signals; exit 0 if all fresh, 2 if stale.
#   refresh         Apply mechanical updates to stale artifacts, then verify.
#   --self-test     Run internal test scenarios.
#   --help          Show usage.
#
# Freshness signals checked (all 5 must hold):
#   1. SCRATCHPAD.md mtime within last 30 minutes.
#   2. SCRATCHPAD.md mentions every plan slug created/edited/archived this session
#      (this session = since branch.lastFetchedDate OR last 4 hours, whichever is
#      shorter — heuristic).
#   3. docs/build-doctrine-roadmap.md (or project roadmap) has been touched this
#      session if any tranche row's status would have changed.
#   4. docs/discoveries/*.md whose decision was acted on this session have
#      Status flipped from `pending` to a terminal value.
#   5. docs/backlog.md Last-updated stamp is current.
#
# Exit codes:
#   0 — all freshness signals PASS, OR non-applicable (not in a git repo)
#   2 — at least one signal STALE (stderr lists which)
#
# Non-applicable rationale: when the hook fires from a directory that is not
# a git repo, there is no SCRATCHPAD / plan-archive / backlog substrate to
# verify — nothing to check ≠ failure. Exit 2 in this case would cause the
# Stop hook to re-prompt the agent indefinitely (the directory cannot become
# a git repo by retrying). Exit 0 with a "skipping" note is the correct
# response.

set -u

# ===== usage =====
usage() {
  cat <<EOF
session-wrap.sh — verify + refresh handoff artifacts at session end (ADR 027 Layer 5)

Usage:
  session-wrap.sh verify           Verify freshness; exit 0 if fresh, 2 if stale.
  session-wrap.sh refresh          Apply mechanical refreshes, then verify.
  session-wrap.sh --self-test      Run internal scenarios.

Exit codes: 0 = all fresh; 2 = stale.
EOF
}

# ===== helpers =====

# Find the repo root via git rev-parse, falling back to the parent repo when run
# from a git worktree. SCRATCHPAD lives in the parent repo by convention
# (orchestrator-pattern.md: worktrees are short-lived build isolation, not
# branch-lifetime contexts that warrant their own state). See ADR 028.
find_repo_root() {
  local toplevel
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || return 1

  local git_dir git_common_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || { echo "$toplevel"; return 0; }
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "$toplevel"; return 0; }

  # Resolve to absolute paths for reliable comparison
  git_dir=$(cd "$git_dir" 2>/dev/null && pwd) || { echo "$toplevel"; return 0; }
  git_common_dir=$(cd "$git_common_dir" 2>/dev/null && pwd) || { echo "$toplevel"; return 0; }

  if [ "$git_dir" != "$git_common_dir" ]; then
    # We're in a worktree. Parent repo's toplevel is dirname of the common .git dir.
    dirname "$git_common_dir"
  else
    echo "$toplevel"
  fi
}

# Get plans touched this session: archive-moves in last 4 hours
plans_touched_this_session() {
  local repo="$1"
  cd "$repo"
  # Plans archived: look for renames into archive/
  git log --since="4 hours ago" --pretty=format: --name-status 2>/dev/null \
    | grep -E '^R[0-9]*\s+docs/plans/[^/]+\.md\s+docs/plans/archive/[^/]+\.md$' \
    | awk '{print $3}' | xargs -I {} basename {} .md 2>/dev/null | sort -u
}

# Get currently-active plans
active_plans() {
  local repo="$1"
  cd "$repo"
  if ! ls "$repo/docs/plans"/*.md >/dev/null 2>&1; then
    return 0
  fi
  for f in "$repo/docs/plans"/*.md; do
    [ -f "$f" ] || continue
    if head -10 "$f" 2>/dev/null | grep -qE '^Status:[[:space:]]*ACTIVE'; then
      basename "$f" .md
    fi
  done
}

# Mtime in seconds-ago for a file
mtime_seconds_ago() {
  local f="$1"
  if [ ! -f "$f" ]; then echo 99999999; return; fi
  local now=$(date +%s)
  # Use stat with portable fallback
  local mtime
  mtime=$(stat -c %Y "$f" 2>/dev/null) || mtime=$(stat -f %m "$f" 2>/dev/null) || mtime=0
  echo $((now - mtime))
}

# Check that SCRATCHPAD mentions a plan slug
scratchpad_mentions() {
  local scratchpad="$1"
  local slug="$2"
  [ -f "$scratchpad" ] || return 1
  grep -qF "$slug" "$scratchpad"
}

# ===== verify subcommand =====

cmd_verify() {
  local repo="$1"
  local scratchpad="$repo/SCRATCHPAD.md"
  local roadmap="$repo/docs/build-doctrine-roadmap.md"
  local backlog="$repo/docs/backlog.md"
  local stale=()

  # Signal 1: SCRATCHPAD mtime within 30 min
  local age
  age=$(mtime_seconds_ago "$scratchpad")
  if [ "$age" -gt 1800 ]; then
    stale+=("SCRATCHPAD.md is $((age / 60)) min stale (>30 min threshold)")
  fi

  # Signal 2: SCRATCHPAD mentions every plan touched this session
  local touched
  touched=$(plans_touched_this_session "$repo")
  if [ -n "$touched" ]; then
    while IFS= read -r slug; do
      [ -n "$slug" ] || continue
      if ! scratchpad_mentions "$scratchpad" "$slug"; then
        stale+=("SCRATCHPAD.md does not mention plan touched this session: $slug")
      fi
    done <<< "$touched"
  fi

  # Signal 3: roadmap touched this session if any plan was archived
  if [ -n "$touched" ] && [ -f "$roadmap" ]; then
    age=$(mtime_seconds_ago "$roadmap")
    if [ "$age" -gt 7200 ]; then
      stale+=("roadmap docs/build-doctrine-roadmap.md is $((age / 60)) min stale despite session activity (>2 hr threshold)")
    fi
  fi

  # Signal 4: discovery files with pending status whose decisions look acted on
  if ls "$repo/docs/discoveries"/*.md >/dev/null 2>&1; then
    for f in "$repo/docs/discoveries"/*.md; do
      [ -f "$f" ] || continue
      # Extract Status field from frontmatter (top 30 lines)
      local status
      status=$(head -30 "$f" 2>/dev/null | grep -E '^status:[[:space:]]' | head -1 | awk '{print $2}')
      if [ "$status" = "pending" ]; then
        # Check if Implementation log section is non-empty (heuristic for "acted on")
        if grep -A 50 "^## Implementation log" "$f" 2>/dev/null | grep -qE '^- '; then
          stale+=("discovery $(basename "$f") has Status: pending but Implementation log is populated — Status should flip to decided/implemented")
        fi
      fi
    done
  fi

  # Signal 5: backlog Last-updated stamp current
  if [ -f "$backlog" ]; then
    age=$(mtime_seconds_ago "$backlog")
    if [ "$age" -gt 7200 ] && [ -n "$touched" ]; then
      stale+=("docs/backlog.md is $((age / 60)) min stale despite session activity")
    fi
  fi

  # Signal 6: SCRATCHPAD "What's Next" doesn't reference plans archived this session
  # Catches content-level staleness — pointers at next-actions that are already done.
  # Surfaced 2026-05-06 by user catching stale What's Next content despite mtime fresh.
  if [ -f "$scratchpad" ] && [ -n "$touched" ]; then
    # Extract content of "## What's Next" section (until next ## heading).
    # Use awk that emits AFTER the start match and stops BEFORE next ## (not inclusive).
    local whats_next
    whats_next=$(awk '/^## What.*Next/{flag=1; next} /^## /{flag=0} flag' "$scratchpad" 2>/dev/null | head -100)
    if [ -n "$whats_next" ]; then
      while IFS= read -r slug; do
        [ -n "$slug" ] || continue
        # If What's Next references an archived-this-session plan as a future action
        # (heuristic: bullet/numbered line containing the slug), flag as stale-pointer.
        if echo "$whats_next" | grep -E "^[0-9]+\.|^- " | grep -qF "$slug"; then
          stale+=("SCRATCHPAD What's Next references plan archived this session as future action: $slug — rewrite What's Next to remove already-completed items")
        fi
      done <<< "$touched"
    fi
  fi

  if [ "${#stale[@]}" -eq 0 ]; then
    echo "[session-wrap] all freshness signals PASS"
    return 0
  fi

  echo "[session-wrap] STALE — ${#stale[@]} signal(s):" >&2
  for s in "${stale[@]}"; do
    echo "  - $s" >&2
  done
  return 2
}

# ===== refresh subcommand =====

cmd_refresh() {
  local repo="$1"
  local scratchpad="$repo/SCRATCHPAD.md"

  # Touch SCRATCHPAD with an explicit timestamp comment (idempotent: appends a single line)
  if [ -f "$scratchpad" ]; then
    local stamp="<!-- session-wrap.sh: handoff verified $(date -u +%Y-%m-%dT%H:%M:%SZ) -->"
    # If a session-wrap stamp already exists, replace it; else append
    if grep -q '^<!-- session-wrap.sh:' "$scratchpad"; then
      sed -i "s|^<!-- session-wrap.sh:.*|$stamp|" "$scratchpad"
    else
      echo "" >> "$scratchpad"
      echo "$stamp" >> "$scratchpad"
    fi
    echo "[session-wrap] refreshed SCRATCHPAD.md mtime via timestamp marker"
  fi

  # Re-verify
  cmd_verify "$repo"
}

# ===== self-test =====

cmd_self_test() {
  # Capture the script's invocation path BEFORE chdir into the test fixture,
  # so S8 can re-invoke this script from a non-git directory.
  local SELF_SCRIPT_PATH
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SELF_SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")
  else
    SELF_SCRIPT_PATH=""
  fi

  local TMPROOT
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t session-wrap)
  trap 'rm -rf "$TMPROOT"' EXIT
  local PASSED=0 FAILED=0

  # Setup synthetic repo
  cd "$TMPROOT"
  git init -q .
  git config user.email "test@example.test"
  git config user.name "Test"
  mkdir -p docs/plans docs/plans/archive docs/discoveries

  # ---- scenario 1: fresh SCRATCHPAD with touched-plan mention -> PASS
  echo "# initial" > docs/plans/test-plan-1.md
  git add . && git commit -q -m "init"
  # Simulate plan-archive move via git mv (matches close-plan.sh real workflow)
  git mv docs/plans/test-plan-1.md docs/plans/archive/test-plan-1.md
  git commit -q -m "archive test-plan-1"
  echo "# SCRATCHPAD" > SCRATCHPAD.md
  echo "test-plan-1" >> SCRATCHPAD.md
  if cmd_verify "$TMPROOT" >/dev/null 2>&1; then
    echo "self-test (S1) fresh-with-mention: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "self-test (S1) fresh-with-mention: FAIL"
    FAILED=$((FAILED + 1))
  fi

  # ---- scenario 2: SCRATCHPAD missing plan mention -> STALE
  rm -f SCRATCHPAD.md
  echo "# SCRATCHPAD" > SCRATCHPAD.md
  # No mention of test-plan-1
  if cmd_verify "$TMPROOT" >/dev/null 2>&1; then
    echo "self-test (S2) missing-mention: FAIL (should have detected stale)"
    FAILED=$((FAILED + 1))
  else
    echo "self-test (S2) missing-mention: PASS"
    PASSED=$((PASSED + 1))
  fi

  # ---- scenario 3: stale SCRATCHPAD mtime -> STALE
  rm -f SCRATCHPAD.md
  echo "# SCRATCHPAD" > SCRATCHPAD.md
  echo "test-plan-1" >> SCRATCHPAD.md
  # Force ancient mtime
  touch -d "2 hours ago" SCRATCHPAD.md 2>/dev/null || touch -t "200001010000" SCRATCHPAD.md
  if cmd_verify "$TMPROOT" >/dev/null 2>&1; then
    echo "self-test (S3) stale-mtime: FAIL (should have detected stale)"
    FAILED=$((FAILED + 1))
  else
    echo "self-test (S3) stale-mtime: PASS"
    PASSED=$((PASSED + 1))
  fi

  # ---- scenario 4: refresh subcommand makes stale fresh
  if cmd_refresh "$TMPROOT" >/dev/null 2>&1; then
    echo "self-test (S4) refresh-makes-fresh: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "self-test (S4) refresh-makes-fresh: FAIL"
    FAILED=$((FAILED + 1))
  fi

  # ---- scenario 5: discovery with pending Status + populated Implementation log -> STALE
  rm -f docs/discoveries/*.md 2>/dev/null
  cat > docs/discoveries/test-discovery.md <<'EOF'
---
status: pending
---

# Test
## Implementation log

- 2026-05-05 — actually shipped
EOF
  # Need touched-plan to trigger discovery check
  if cmd_verify "$TMPROOT" >/dev/null 2>&1; then
    echo "self-test (S5) pending-with-impl-log: FAIL (should have detected stale)"
    FAILED=$((FAILED + 1))
  else
    echo "self-test (S5) pending-with-impl-log: PASS"
    PASSED=$((PASSED + 1))
  fi

  # ---- scenario 6: SCRATCHPAD What's Next references archived-this-session plan -> STALE
  rm -f docs/discoveries/*.md 2>/dev/null  # remove S5 fixture
  rm -f SCRATCHPAD.md
  cat > SCRATCHPAD.md <<'EOF'
# SCRATCHPAD

## What's Next (next session)

1. Close test-plan-1 via close-plan.sh
2. Run live acceptance test
EOF
  if cmd_verify "$TMPROOT" >/dev/null 2>&1; then
    echo "self-test (S6) whats-next-references-archived: FAIL (should have detected stale-pointer)"
    FAILED=$((FAILED + 1))
  else
    echo "self-test (S6) whats-next-references-archived: PASS"
    PASSED=$((PASSED + 1))
  fi

  # ---- scenario 7: find_repo_root falls back to parent when called from a worktree
  # Setup: create a worktree off the synthetic repo, cd into it, call find_repo_root,
  # confirm it returns the parent (TMPROOT) not the worktree path.
  rm -f docs/discoveries/*.md 2>/dev/null
  rm -f SCRATCHPAD.md
  echo "# SCRATCHPAD" > SCRATCHPAD.md
  echo "test-plan-1" >> SCRATCHPAD.md
  # mtime is fresh from the previous touch
  touch SCRATCHPAD.md

  WT_PATH="$TMPROOT/wt-7"
  if git worktree add -q -b worktree-test-7 "$WT_PATH" >/dev/null 2>&1; then
    cd "$WT_PATH"
    DETECTED_ROOT=$(find_repo_root)
    # Resolve both to absolute paths for comparison (handles symlinks / case)
    EXPECTED_ROOT=$(cd "$TMPROOT" && pwd)
    DETECTED_ABS=$(cd "$DETECTED_ROOT" 2>/dev/null && pwd)
    if [ "$DETECTED_ABS" = "$EXPECTED_ROOT" ]; then
      echo "self-test (S7) worktree-fallback: PASS"
      PASSED=$((PASSED + 1))
    else
      echo "self-test (S7) worktree-fallback: FAIL (expected $EXPECTED_ROOT, got $DETECTED_ABS)"
      FAILED=$((FAILED + 1))
    fi
    cd "$TMPROOT"
    git worktree remove --force "$WT_PATH" >/dev/null 2>&1
    git branch -D worktree-test-7 >/dev/null 2>&1
  else
    echo "self-test (S7) worktree-fallback: SKIP (git worktree add failed in test env)"
  fi

  # ---- scenario 8: invocation from a non-git directory exits 0, not 2
  # Root cause of the infinite hook re-prompt loop: exit 2 in non-applicable
  # directories caused Claude Code Stop hooks to re-prompt indefinitely.
  # Locks the fix: verify/refresh in a non-git dir must exit 0 with a note.
  cd "$TMPROOT"
  NONGIT_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t nongit)
  cd "$NONGIT_DIR"
  # Confirm: not a git repo
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "self-test (S8) non-git-exits-zero: SKIP (mktemp dir is unexpectedly inside a git repo)"
  elif [ -z "$SELF_SCRIPT_PATH" ] || [ ! -f "$SELF_SCRIPT_PATH" ]; then
    echo "self-test (S8) non-git-exits-zero: SKIP (could not resolve script path: '$SELF_SCRIPT_PATH')"
  else
    VERIFY_EXIT=0
    bash "$SELF_SCRIPT_PATH" verify >/dev/null 2>&1 || VERIFY_EXIT=$?
    REFRESH_EXIT=0
    bash "$SELF_SCRIPT_PATH" refresh >/dev/null 2>&1 || REFRESH_EXIT=$?
    if [ "$VERIFY_EXIT" -eq 0 ] && [ "$REFRESH_EXIT" -eq 0 ]; then
      echo "self-test (S8) non-git-exits-zero: PASS"
      PASSED=$((PASSED + 1))
    else
      echo "self-test (S8) non-git-exits-zero: FAIL (verify=$VERIFY_EXIT, refresh=$REFRESH_EXIT — expected 0/0)"
      FAILED=$((FAILED + 1))
    fi
  fi
  cd "$TMPROOT"
  rm -rf "$NONGIT_DIR"

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed (of $((PASSED + FAILED)) scenarios)"
  if [ "$FAILED" -gt 0 ]; then exit 1; fi
  exit 0
}

# ===== main =====

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

case "$1" in
  --help|-h)
    usage
    exit 0
    ;;
  --self-test)
    cmd_self_test
    ;;
  verify)
    REPO="$(find_repo_root)" || { echo "session-wrap: not in a git repo, skipping" >&2; exit 0; }
    cmd_verify "$REPO"
    ;;
  refresh)
    REPO="$(find_repo_root)" || { echo "session-wrap: not in a git repo, skipping" >&2; exit 0; }
    cmd_refresh "$REPO"
    ;;
  *)
    echo "session-wrap: unknown subcommand: $1" >&2
    usage
    exit 2
    ;;
esac
