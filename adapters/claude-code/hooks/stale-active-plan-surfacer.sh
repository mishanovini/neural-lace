#!/bin/bash
# stale-active-plan-surfacer.sh
#
# SessionStart hook that scans `docs/plans/*.md` (top-level only,
# excluding archive/) for plans with `Status: ACTIVE` whose last git
# commit is older than the staleness threshold (default 24 hours).
#
# When stale ACTIVE plans are found, emits a single system-reminder
# block listing each one so the operator (or next agent turn) sees
# the staleness signal at session start. Silent if no plans are stale
# (or if the cwd has no docs/plans/ at all).
#
# This is the "chronic stale plan tax" surface called out in the
# 2026-05-24 agent-incentive-structure audit (Fix #1) and the audit's
# pattern Smell-1. Misha-approved 2026-05-28 at 24-hour threshold.
#
# Reference: HARNESS-GAP-29/30/31 (designed but not yet shipped); this
# is the lightweight surfacer half — the waiver-density alarm is a
# separate Stop-hook extension and not implemented here.
#
# Design notes:
# - 24-hour staleness is intentionally tight. The audit's >14d threshold
#   was for "chronic" stale plans. Misha's 24h threshold flags ANY plan
#   open for more than a day, on the principle that closure IS the work
#   (per CLAUDE.md "What 'Done' Means for the Orchestrator").
# - Uses `git log -1 --format=%ct -- <file>` for last-touched timestamp.
#   Falls back to file mtime if git is unavailable / file untracked.
# - Override the threshold via env var STALE_ACTIVE_PLAN_HOURS (integer).
# - Emit format mirrors discovery-surfacer.sh — plain stdout text per
#   the SessionStart hook convention.
# - Self-test exercises 5 scenarios: no-plans-dir, no-active-plans,
#   one-fresh-active, one-stale-active, mixed-fresh-and-stale.

set -u

STALE_HOURS="${STALE_ACTIVE_PLAN_HOURS:-24}"
STALE_SECONDS=$((STALE_HOURS * 3600))

# -------- Detect if a plan file is Status: ACTIVE --------
# Reads the first 30 lines (covers the header block) for the Status field.
is_active() {
  local file="$1"
  head -n 30 "$file" 2>/dev/null \
    | grep -iE "^Status:[[:space:]]*ACTIVE" \
    | head -n 1 \
    | grep -q .
}

# -------- Get last-touched timestamp (seconds since epoch) --------
# Prefers git log timestamp (the authoritative "last change to this plan").
# Falls back to file mtime if git is unavailable or file isn't tracked.
last_touched() {
  local file="$1"
  local ts
  ts=$(git log -1 --format=%ct -- "$file" 2>/dev/null)
  if [ -n "$ts" ] && [ "$ts" != "0" ]; then
    echo "$ts"
    return 0
  fi
  # Fallback: file mtime
  if command -v stat >/dev/null 2>&1; then
    # GNU stat first, BSD/macOS stat second, both with explicit timestamp format
    stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null
  else
    # Last resort: empty (we'll skip this file)
    echo ""
  fi
}

# -------- Extract a one-line plan title for display --------
# Looks for "# Plan:" or first `# ` heading in the first 5 lines.
plan_title() {
  local file="$1"
  head -n 5 "$file" 2>/dev/null \
    | grep -E "^# " \
    | head -n 1 \
    | sed -E 's/^# (Plan: )?//' \
    | head -c 80
}

# -------- Format hours-ago from seconds-ago --------
hours_ago() {
  local seconds_ago="$1"
  local hours=$((seconds_ago / 3600))
  if [ "$hours" -lt 48 ]; then
    echo "${hours}h"
  else
    local days=$((hours / 24))
    echo "${days}d"
  fi
}

# -------- Scan for stale ACTIVE plans --------
surface_stale_plans() {
  local cwd="$1"
  local plans_dir="$cwd/docs/plans"
  [ -d "$plans_dir" ] || return 0

  local now
  now=$(date +%s)
  local stale_lines=""
  local stale_count=0

  for f in "$plans_dir"/*.md; do
    [ -f "$f" ] || continue
    is_active "$f" || continue
    local ts
    ts=$(last_touched "$f")
    [ -n "$ts" ] || continue
    local age=$((now - ts))
    [ "$age" -ge "$STALE_SECONDS" ] || continue
    local slug
    slug=$(basename "$f" .md)
    local title
    title=$(plan_title "$f")
    [ -n "$title" ] || title="(no title)"
    stale_lines+="  • ${slug} — ${title}"$'\n'
    stale_lines+="    last touched: $(hours_ago "$age") ago | path: docs/plans/${slug}.md"$'\n'
    stale_count=$((stale_count + 1))
  done

  if [ "$stale_count" -gt 0 ]; then
    echo ""
    echo "[stale-active-plan-surfacer] ${stale_count} ACTIVE plan(s) with no commits in >${STALE_HOURS}h:"
    printf '%s' "$stale_lines"
    echo "  Per CLAUDE.md \"What 'Done' Means for the Orchestrator\":"
    echo "  closure IS the work, not a follow-up. Either drive each to"
    echo "  Status: COMPLETED / DEFERRED / ABANDONED, OR amend with a"
    echo "  Decisions Log entry naming why ACTIVE is still appropriate."
    echo ""
  fi
}

# -------- Self-test --------
run_self_test() {
  local tmp
  tmp=$(mktemp -d -t stale-active-plan-test.XXXXXX 2>/dev/null) || tmp="/tmp/stale-active-plan-test.$$"
  mkdir -p "$tmp"
  local failures=0

  run_scenario() {
    local name="$1"
    local expect_output="$2"  # "yes" or "no"
    local match="$3"
    local cwd="$4"
    local override_hours="${5:-}"
    local out
    if [ -n "$override_hours" ]; then
      out=$(STALE_ACTIVE_PLAN_HOURS="$override_hours" bash "$0" </dev/null 2>&1 <<<"" )
    else
      out=$(surface_stale_plans "$cwd" 2>&1)
    fi
    case "$expect_output" in
      yes)
        if echo "$out" | grep -q "stale-active-plan-surfacer"; then
          if [ -n "$match" ]; then
            if echo "$out" | grep -q "$match"; then
              echo "  PASS $name"
            else
              echo "  FAIL $name (expected match '$match' not found)" >&2
              failures=$((failures + 1))
            fi
          else
            echo "  PASS $name"
          fi
        else
          echo "  FAIL $name (expected output, got none)" >&2
          failures=$((failures + 1))
        fi
        ;;
      no)
        if [ -z "$out" ]; then
          echo "  PASS $name"
        else
          echo "  FAIL $name (expected silent, got: $out)" >&2
          failures=$((failures + 1))
        fi
        ;;
    esac
  }

  # ---- Scenario 1: no docs/plans/ dir → silent ----
  local s1="$tmp/no-plans-dir"
  mkdir -p "$s1"
  run_scenario "no-plans-dir-silent" no "" "$s1"

  # ---- Scenario 2: docs/plans/ exists but no ACTIVE plans → silent ----
  local s2="$tmp/no-active"
  mkdir -p "$s2/docs/plans"
  cat > "$s2/docs/plans/completed.md" <<'EOF'
# Plan: completed thing
Status: COMPLETED

## Goal
test fixture
EOF
  run_scenario "no-active-plans-silent" no "" "$s2"

  # ---- Scenario 3: ACTIVE plan but fresh (mtime ≤ 1h) → silent ----
  local s3="$tmp/fresh-active"
  mkdir -p "$s3/docs/plans"
  cat > "$s3/docs/plans/fresh-thing.md" <<'EOF'
# Plan: fresh thing
Status: ACTIVE

## Goal
just authored
EOF
  # Use 9999-hour threshold so even a brand new file is "fresh"
  STALE_ACTIVE_PLAN_HOURS=9999
  local STALE_HOURS_SAVE=$STALE_HOURS
  STALE_HOURS=9999
  STALE_SECONDS=$((STALE_HOURS * 3600))
  local out3
  out3=$(surface_stale_plans "$s3" 2>&1)
  if [ -z "$out3" ]; then
    echo "  PASS fresh-active-silent"
  else
    echo "  FAIL fresh-active-silent (got: $out3)" >&2
    failures=$((failures + 1))
  fi
  STALE_HOURS=$STALE_HOURS_SAVE
  STALE_SECONDS=$((STALE_HOURS * 3600))

  # ---- Scenario 4: ACTIVE plan with old mtime → surfaces ----
  local s4="$tmp/stale-active"
  mkdir -p "$s4/docs/plans"
  cat > "$s4/docs/plans/old-stuck.md" <<'EOF'
# Plan: old stuck
Status: ACTIVE

## Goal
been ACTIVE for too long
EOF
  # Set mtime to 48h ago (older than the default 24h threshold)
  local old_ts
  old_ts=$(($(date +%s) - 172800))
  touch -d "@$old_ts" "$s4/docs/plans/old-stuck.md" 2>/dev/null \
    || touch -t "$(date -r "$old_ts" '+%Y%m%d%H%M.%S' 2>/dev/null)" "$s4/docs/plans/old-stuck.md" 2>/dev/null \
    || true
  local out4
  out4=$(surface_stale_plans "$s4" 2>&1)
  if echo "$out4" | grep -q "old-stuck"; then
    echo "  PASS stale-active-surfaces"
  else
    echo "  FAIL stale-active-surfaces (got: $out4)" >&2
    failures=$((failures + 1))
  fi

  # ---- Scenario 5: archive dir excluded → silent ----
  local s5="$tmp/archive-excluded"
  mkdir -p "$s5/docs/plans/archive"
  cat > "$s5/docs/plans/archive/old-archived.md" <<'EOF'
# Plan: old archived
Status: ACTIVE

## Goal
should not surface — in archive/
EOF
  old_ts=$(($(date +%s) - 172800))
  touch -d "@$old_ts" "$s5/docs/plans/archive/old-archived.md" 2>/dev/null || true
  local out5
  out5=$(surface_stale_plans "$s5" 2>&1)
  if [ -z "$out5" ]; then
    echo "  PASS archive-excluded"
  else
    echo "  FAIL archive-excluded (got: $out5)" >&2
    failures=$((failures + 1))
  fi

  rm -rf "$tmp"

  if [ "$failures" -eq 0 ]; then
    echo ""
    echo "SELF-TEST: all scenarios passed (5/5)"
    return 0
  else
    echo ""
    echo "SELF-TEST: $failures scenario(s) failed" >&2
    return 1
  fi
}

# -------- Entry point --------
if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

# Normal invocation: consume any stdin JSON payload (Claude Code hook
# contract) but we don't need to parse it — the hook acts on cwd.
if [ ! -t 0 ]; then
  cat >/dev/null 2>&1 || true
fi

surface_stale_plans "$PWD"
exit 0
