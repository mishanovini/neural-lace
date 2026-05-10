#!/bin/bash
# plan-status-archival-sweep.sh
#
# SessionStart hook that scans `docs/plans/*.md` (top-level only, not
# `docs/plans/archive/`) for plan files whose `Status:` field is at a
# terminal value (COMPLETED / ABANDONED / SUPERSEDED). For each match,
# performs a `git mv` (or plain `mv` for untracked files) to
# `docs/plans/archive/`, including any sibling `<slug>-evidence.md`.
#
# DEFERRED is intentionally NOT terminal. DEFERRED means "paused, will
# resume" — auto-archiving a DEFERRED plan would hide it from the next
# session that's supposed to pick it back up. Terminal = "the plan's
# life is over"; that's COMPLETED, ABANDONED, SUPERSEDED only.
#
# Why this exists. `plan-lifecycle.sh` is a PostToolUse hook on Edit/
# Write. Bash-based Status flips (e.g. `sed -i 's/^Status: ACTIVE$/
# Status: COMPLETED/' docs/plans/<slug>.md`) do NOT fire those events,
# so plans flipped via Bash get stranded in `docs/plans/`. This hook's
# next-session-start sweep catches stranded plans and archives them so
# the post-condition `plan-lifecycle.sh` is supposed to enforce
# (terminal-status plans live in archive/) holds regardless of HOW the
# Status flip happened.
#
# Latency tradeoff. Archival happens at the NEXT session start, not at
# flip time. A COMPLETED plan can sit in `docs/plans/` for the rest of
# the current session. This is acceptable: archival is housekeeping; the
# Edit-tool path (still the recommended convention) keeps zero-latency
# archival via plan-lifecycle.sh, and this sweep is the safety net for
# everything else.
#
# Cross-references:
# - hooks/plan-lifecycle.sh — the original PostToolUse archive hook
# - rules/planning.md "Plan File Lifecycle" section
# - rules/discovery-protocol.md
# - docs/discoveries/2026-05-04-sed-status-flip-bypasses-plan-lifecycle.md
#
# Self-test: invoke with --self-test to exercise five scenarios.

set -u

# -------- Utility: extract Status value from frontmatter region --------
# Plan files use a non-YAML "Status: VALUE" line near the top, NOT a
# YAML `---` block. Read the first 30 lines and find the first match.
plan_status_value() {
  local file="$1"
  head -n 30 "$file" 2>/dev/null \
    | grep -iE '^Status:[[:space:]]+' \
    | head -n 1 \
    | sed -E 's/^[Ss][Tt][Aa][Tt][Uu][Ss]:[[:space:]]+//; s/[[:space:]]+$//'
}

# -------- Utility: archive one plan file (and its evidence sibling) --------
# Args:
#   $1 = absolute path to plan file (must exist)
#   $2 = absolute path to archive directory (will be created if missing)
# Returns 0 on success, non-zero on failure.
archive_plan() {
  local plan="$1"
  local archive_dir="$2"
  local slug plans_dir base evidence

  plans_dir="$(dirname "$plan")"
  base="$(basename "$plan")"
  slug="$(basename "$plan" .md)"

  mkdir -p "$archive_dir" || return 1

  # Refuse to overwrite an existing archive entry. If a sibling already
  # exists in archive/, something has gone wrong upstream — skip and
  # surface a warning so the maintainer can investigate.
  if [ -e "$archive_dir/$base" ]; then
    echo "[plan-archival-sweep] WARNING: '$archive_dir/$base' already exists; refusing to overwrite. Manual review needed." >&2
    return 2
  fi

  # Resolve the repo root so git mv can be invoked with absolute paths.
  # If we're not inside a git repo, repo_root will be empty and we'll
  # fall through to plain mv.
  local repo_root
  repo_root=$(git -C "$plans_dir" rev-parse --show-toplevel 2>/dev/null || true)

  # Try git mv first (preserves git history) when the file is tracked.
  # Fall back to plain mv otherwise (untracked files, non-git working
  # directory).
  if [ -n "$repo_root" ] && git -C "$repo_root" ls-files --error-unmatch "$plan" >/dev/null 2>&1; then
    git -C "$repo_root" mv "$plan" "$archive_dir/$base" 2>/dev/null \
      || mv "$plan" "$archive_dir/$base" \
      || return 1
  else
    mv "$plan" "$archive_dir/$base" || return 1
  fi

  # Move sibling evidence file if it exists.
  evidence="$plans_dir/${slug}-evidence.md"
  if [ -f "$evidence" ]; then
    if [ -e "$archive_dir/${slug}-evidence.md" ]; then
      echo "[plan-archival-sweep] WARNING: evidence sibling '$archive_dir/${slug}-evidence.md' already exists; left '$evidence' in active dir." >&2
    elif [ -n "$repo_root" ] && git -C "$repo_root" ls-files --error-unmatch "$evidence" >/dev/null 2>&1; then
      git -C "$repo_root" mv "$evidence" "$archive_dir/${slug}-evidence.md" 2>/dev/null \
        || mv "$evidence" "$archive_dir/${slug}-evidence.md"
    else
      mv "$evidence" "$archive_dir/${slug}-evidence.md"
    fi
  fi

  return 0
}

# -------- Core sweep logic --------
# Args (for testability):
#   $1 = working directory to scan (defaults to $PWD)
# Writes a one-line system reminder per archived plan + a summary line.
# Exits 0 always (sweep is informational; never block session start).
sweep_plans() {
  local cwd="${1:-$PWD}"
  local plans_dir="$cwd/docs/plans"
  local archive_dir="$plans_dir/archive"

  # If the directory doesn't exist, exit silently. Common in projects
  # that don't use the planning protocol yet.
  if [ ! -d "$plans_dir" ]; then
    return 0
  fi

  local archived_count=0
  local plan base status_val rc

  for plan in "$plans_dir"/*.md; do
    [ -f "$plan" ] || continue
    base="$(basename "$plan")"

    # Skip evidence siblings — archive_plan() handles them via the
    # parent's slug.
    case "$base" in
      *-evidence.md) continue ;;
    esac

    status_val=$(plan_status_value "$plan")
    [ -n "$status_val" ] || continue

    case "$status_val" in
      COMPLETED|ABANDONED|SUPERSEDED|completed|abandoned|superseded)
        archive_plan "$plan" "$archive_dir"
        rc=$?
        if [ "$rc" -eq 0 ]; then
          echo "[plan-archival-sweep] auto-archived '$base' (Status: $status_val) → docs/plans/archive/"
          archived_count=$((archived_count + 1))
        elif [ "$rc" -eq 2 ]; then
          : # warning already emitted by archive_plan
        else
          echo "[plan-archival-sweep] WARNING: failed to archive '$base' (Status: $status_val); manual review needed" >&2
        fi
        ;;
    esac
  done

  if [ "$archived_count" -gt 0 ]; then
    echo "[plan-archival-sweep] swept $archived_count terminal-status plan(s) into docs/plans/archive/. See ~/.claude/rules/planning.md 'Plan File Lifecycle' for the convention."
  fi
}

# -------- Self-test --------
run_self_test() {
  local tmp failures=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t plnsweep)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  init_git_repo() {
    local dir="$1"
    git -C "$dir" init -q 2>/dev/null
    git -C "$dir" config user.email "test@example.test" 2>/dev/null
    git -C "$dir" config user.name "Test" 2>/dev/null
    git -C "$dir" config commit.gpgsign false 2>/dev/null
  }

  # ---- Scenario 1: no docs/plans directory ----
  local s1="$tmp/no-plans"
  mkdir -p "$s1"
  init_git_repo "$s1"
  if [ -n "$(sweep_plans "$s1" 2>&1)" ]; then
    echo "FAIL: [no-directory] expected silence" >&2; failures=$((failures + 1))
  else
    echo "PASS: [no-directory] silent as expected"
  fi

  # ---- Scenario 2: ACTIVE plan stays put ----
  local s2="$tmp/active-stays"
  mkdir -p "$s2/docs/plans"
  init_git_repo "$s2"
  cat > "$s2/docs/plans/active-plan.md" <<'EOF'
# Plan: Active
Status: ACTIVE

## Goal
Test fixture.
EOF
  git -C "$s2" add docs/plans/active-plan.md && git -C "$s2" commit -q -m "test"
  sweep_plans "$s2" >/dev/null 2>&1
  if [ -f "$s2/docs/plans/active-plan.md" ] && [ ! -d "$s2/docs/plans/archive" ]; then
    echo "PASS: [active-stays] active plan untouched"
  else
    echo "FAIL: [active-stays] active plan was disturbed" >&2; failures=$((failures + 1))
  fi

  # ---- Scenario 3: COMPLETED plan moves to archive AND git tracks the rename ----
  local s3="$tmp/completed-archives"
  mkdir -p "$s3/docs/plans"
  init_git_repo "$s3"
  cat > "$s3/docs/plans/finished-plan.md" <<'EOF'
# Plan: Finished
Status: COMPLETED

## Goal
Test fixture.
EOF
  git -C "$s3" add docs/plans/finished-plan.md && git -C "$s3" commit -q -m "test"
  local out3
  out3=$(sweep_plans "$s3" 2>&1)
  # Check git's view: a rename should be staged. `git diff --cached
  # --name-status` will report `R<num>` for renames or `D` + `A` if
  # the move fell through to plain mv.
  local git_status
  git_status=$(git -C "$s3" diff --cached --name-status 2>/dev/null)
  if [ -f "$s3/docs/plans/archive/finished-plan.md" ] \
     && [ ! -f "$s3/docs/plans/finished-plan.md" ] \
     && echo "$out3" | grep -q "auto-archived 'finished-plan.md'" \
     && echo "$git_status" | grep -qE '^R[0-9]+'; then
    echo "PASS: [completed-archives] plan moved to archive AND git tracks rename"
  else
    echo "FAIL: [completed-archives] plan not archived correctly OR git mv didn't fire" >&2
    echo "  output: $out3" >&2
    echo "  git status: $git_status" >&2
    echo "  files: $(ls -la "$s3/docs/plans/" 2>/dev/null)" >&2
    failures=$((failures + 1))
  fi

  # ---- Scenario 4: ABANDONED plan + sibling evidence both move ----
  local s4="$tmp/with-evidence"
  mkdir -p "$s4/docs/plans"
  init_git_repo "$s4"
  cat > "$s4/docs/plans/sibling-plan.md" <<'EOF'
# Plan: Sibling
Status: ABANDONED

## Goal
Test fixture.
EOF
  cat > "$s4/docs/plans/sibling-plan-evidence.md" <<'EOF'
# Evidence Log: Sibling
EOF
  git -C "$s4" add docs/plans/ && git -C "$s4" commit -q -m "test"
  sweep_plans "$s4" >/dev/null 2>&1
  if [ -f "$s4/docs/plans/archive/sibling-plan.md" ] \
     && [ -f "$s4/docs/plans/archive/sibling-plan-evidence.md" ] \
     && [ ! -f "$s4/docs/plans/sibling-plan.md" ] \
     && [ ! -f "$s4/docs/plans/sibling-plan-evidence.md" ]; then
    echo "PASS: [with-evidence] plan and evidence both archived"
  else
    echo "FAIL: [with-evidence] sibling pair did not move correctly" >&2
    failures=$((failures + 1))
  fi

  # ---- Scenario 5: untracked COMPLETED plan still gets archived ----
  local s5="$tmp/untracked-completed"
  mkdir -p "$s5/docs/plans"
  init_git_repo "$s5"
  cat > "$s5/docs/plans/untracked-plan.md" <<'EOF'
# Plan: Untracked
Status: ABANDONED

## Goal
Test fixture (never committed).
EOF
  # Note: NOT adding to git — file is untracked.
  sweep_plans "$s5" >/dev/null 2>&1
  if [ -f "$s5/docs/plans/archive/untracked-plan.md" ] \
     && [ ! -f "$s5/docs/plans/untracked-plan.md" ]; then
    echo "PASS: [untracked-completed] untracked plan archived via plain mv"
  else
    echo "FAIL: [untracked-completed] untracked plan not archived" >&2
    failures=$((failures + 1))
  fi

  # ---- Scenario 6: DEFERRED plan stays put (not terminal) ----
  local s6="$tmp/deferred-stays"
  mkdir -p "$s6/docs/plans"
  init_git_repo "$s6"
  cat > "$s6/docs/plans/paused-plan.md" <<'EOF'
# Plan: Paused
Status: DEFERRED

## Goal
Test fixture — DEFERRED is "paused, will resume", not terminal.
EOF
  git -C "$s6" add docs/plans/paused-plan.md && git -C "$s6" commit -q -m "test"
  local out6
  out6=$(sweep_plans "$s6" 2>&1)
  if [ -f "$s6/docs/plans/paused-plan.md" ] \
     && [ ! -f "$s6/docs/plans/archive/paused-plan.md" ] \
     && [ -z "$out6" ]; then
    echo "PASS: [deferred-stays] DEFERRED plan untouched (not terminal)"
  else
    echo "FAIL: [deferred-stays] DEFERRED plan was archived; should remain in active dir" >&2
    echo "  output: $out6" >&2
    echo "  files: $(ls -la "$s6/docs/plans/" 2>/dev/null)" >&2
    failures=$((failures + 1))
  fi

  if [ "$failures" -gt 0 ]; then
    echo ""
    echo "$failures self-test scenario(s) FAILED" >&2
    return 1
  fi
  echo ""
  echo "All 6 self-test scenarios PASSED"
  return 0
}

# -------- Main --------
if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

# Discard SessionStart's JSON payload from stdin (unused here).
cat > /dev/null 2>&1 || true

sweep_plans "$PWD"
exit 0
