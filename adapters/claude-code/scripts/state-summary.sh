#!/bin/bash
# state-summary.sh — derive SCRATCHPAD state mechanically from primary sources.
#
# Per user direction 2026-05-06: SCRATCHPAD must stop being LLM-authored
# source-of-truth. Make derived sections AUTOMATIC, leave clearly-bounded LLM
# synthesis sections for genuine judgment work.
#
# Subcommands:
#   derive          Output the full derived SCRATCHPAD to stdout
#   apply           Update SCRATCHPAD derived-sections in place;
#                   preserve LLM-authored sections (between demarcation markers)
#   --self-test     Run internal test scenarios
#   --help          Show usage
#
# Demarcation markers in SCRATCHPAD:
#   <!-- ===== DERIVED — DO NOT EDIT MANUALLY (state-summary.sh apply) ===== -->
#   ...derived content...
#   <!-- ===== END DERIVED ===== -->
#
#   <!-- ===== LLM SYNTHESIS — orchestrator authors below; preserved by apply ===== -->
#   ...synthesis content...
#   <!-- ===== END LLM SYNTHESIS ===== -->
#
# Exit codes:
#   0 — success
#   1 — generic failure
#   2 — usage error

set -u

usage() {
  cat <<EOF
state-summary.sh — derive SCRATCHPAD state from primary sources

Usage:
  state-summary.sh derive          Output derived SCRATCHPAD to stdout
  state-summary.sh apply           Update SCRATCHPAD; preserve LLM sections
  state-summary.sh --self-test     Run internal scenarios
  state-summary.sh --help

Behavior: derive reads primary sources (active plans, git log, backlog, queues,
discoveries) and emits a SCRATCHPAD-shaped view. apply writes the derived
sections into SCRATCHPAD in place, leaving LLM-authored synthesis sections
between demarcation markers untouched.
EOF
}

# Find repo root via git rev-parse (handles worktrees, where .git is a file not a dir)
find_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# ----- Primary-source extractors -----

active_plans() {
  local repo="$1"
  if ! ls "$repo/docs/plans"/*.md >/dev/null 2>&1; then
    return 0
  fi
  for f in "$repo/docs/plans"/*.md; do
    [ -f "$f" ] || continue
    local status
    status=$(head -10 "$f" 2>/dev/null | grep -E '^Status:[[:space:]]*ACTIVE' | head -1)
    if [ -n "$status" ]; then
      local slug
      slug=$(basename "$f" .md)
      local title
      title=$(head -1 "$f" 2>/dev/null | sed 's/^# *//')
      local task_count
      task_count=$(grep -cE '^- \[[ x]\]' "$f" 2>/dev/null || echo 0)
      local checked
      checked=$(grep -cE '^- \[x\]' "$f" 2>/dev/null || echo 0)
      printf -- '- %s — %s (%s/%s tasks)\n' "$slug" "$title" "$checked" "$task_count"
    fi
  done
}

archived_this_session() {
  local repo="$1"
  cd "$repo"
  # Archives via git mv to docs/plans/archive/ in last 4 hours
  git log --since="4 hours ago" --pretty=format: --name-status 2>/dev/null \
    | grep -E '^R[0-9]*[[:space:]]+docs/plans/[^/]+\.md[[:space:]]+docs/plans/archive/[^/]+\.md$' \
    | awk '{print $3}' | xargs -I {} basename {} .md 2>/dev/null | sort -u \
    | sed 's/^/- /'
}

recent_commits() {
  local repo="$1"
  local hours="${2:-4}"
  cd "$repo"
  git log --since="$hours hours ago" --pretty=format:'- `%h` %s' 2>/dev/null | head -20
}

open_backlog_pickups() {
  local repo="$1"
  local backlog="$repo/docs/backlog.md"
  [ -f "$backlog" ] || return 0
  # Extract HARNESS-GAP-NN entries from "Open work" sections, prefer 5 most-recent-numbered
  awk '
    /^## Open work/ { in_open = 1; next }
    /^## / && in_open { in_open = 0 }
    in_open && /^- \*\*HARNESS-GAP-/ {
      # Trim long lines to first 200 chars for readability
      line = $0
      if (length(line) > 200) line = substr(line, 1, 200) "..."
      print line
    }
  ' "$backlog" 2>/dev/null | head -10
}

queued_decisions_unanswered() {
  local repo="$1"
  if ! ls "$repo/docs/decisions/queued-"*.md >/dev/null 2>&1; then
    return 0
  fi
  for f in "$repo/docs/decisions/queued-"*.md; do
    [ -f "$f" ] || continue
    # Count entries with empty "User override (if any):" field — i.e., orchestrator proceeded with recommendation
    local total
    total=$(grep -cE '^\*\*User override \(if any\):\*\*[[:space:]]*$' "$f" 2>/dev/null || echo 0)
    if [ "$total" -gt 0 ]; then
      printf -- '- `%s` — %d unanswered decision(s)\n' "$(basename "$f")" "$total"
    fi
  done
}

pending_discoveries() {
  local repo="$1"
  if ! ls "$repo/docs/discoveries"/*.md >/dev/null 2>&1; then
    return 0
  fi
  for f in "$repo/docs/discoveries"/*.md; do
    [ -f "$f" ] || continue
    local status
    status=$(head -30 "$f" 2>/dev/null | grep -E '^status:[[:space:]]' | head -1 | awk '{print $2}')
    if [ "$status" = "pending" ]; then
      local title
      title=$(head -30 "$f" 2>/dev/null | grep -E '^title:[[:space:]]' | head -1 | sed 's/^title:[[:space:]]*//')
      printf -- '- `%s` — %s\n' "$(basename "$f")" "$title"
    fi
  done
}

current_branch() {
  local repo="$1"
  cd "$repo"
  git branch --show-current 2>/dev/null
}

# ----- Derive -----

cmd_derive() {
  local repo="$1"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat <<EOF
<!-- ===== DERIVED — DO NOT EDIT MANUALLY (state-summary.sh apply) ===== -->
<!-- Generated: ${now} -->

## Current State (derived)

Branch: \`$(current_branch "$repo")\`. State extracted from primary sources at ${now}.

## Active Plans

EOF
  local plans
  plans=$(active_plans "$repo")
  if [ -n "$plans" ]; then
    echo "$plans"
  else
    echo "_None — master is clean._"
  fi

  cat <<EOF

## Plans Archived Recently (last 4 hours)

EOF
  local archived
  archived=$(archived_this_session "$repo")
  if [ -n "$archived" ]; then
    echo "$archived"
  else
    echo "_None._"
  fi

  cat <<EOF

## Recent Commits (last 4 hours)

EOF
  local commits
  commits=$(recent_commits "$repo" 4)
  if [ -n "$commits" ]; then
    echo "$commits"
  else
    echo "_None._"
  fi

  cat <<EOF

## Open Backlog Pickups (HARNESS-GAP entries)

EOF
  local pickups
  pickups=$(open_backlog_pickups "$repo")
  if [ -n "$pickups" ]; then
    echo "$pickups"
  else
    echo "_None visible in standard \"Open work\" sections._"
  fi

  cat <<EOF

## Queued Decisions Awaiting Override

EOF
  local queues
  queues=$(queued_decisions_unanswered "$repo")
  if [ -n "$queues" ]; then
    echo "$queues"
    echo ""
    echo "_Override by editing the queue file's \"User override (if any):\" lines or replying with overrides._"
  else
    echo "_No open decision queues with unanswered entries._"
  fi

  cat <<EOF

## Pending Discoveries

EOF
  local pendings
  pendings=$(pending_discoveries "$repo")
  if [ -n "$pendings" ]; then
    echo "$pendings"
  else
    echo "_None._"
  fi

  cat <<EOF

<!-- ===== END DERIVED ===== -->
EOF
}

# ----- Apply -----

cmd_apply() {
  local repo="$1"
  local scratchpad="$repo/SCRATCHPAD.md"

  # Compute new derived block
  local derived
  derived=$(cmd_derive "$repo")

  # Determine LLM section preservation strategy:
  # If SCRATCHPAD has the demarcation markers, replace ONLY the DERIVED block.
  # If not, prepend the DERIVED block + add an empty LLM SYNTHESIS section.
  if [ ! -f "$scratchpad" ]; then
    cat > "$scratchpad" <<EOF
# SCRATCHPAD — derived view + LLM synthesis

${derived}

<!-- ===== LLM SYNTHESIS — orchestrator authors below; preserved by apply ===== -->

## Synthesis (LLM-authored)

_Add session-specific judgment commentary here. Replaced by orchestrator at session end with: what should the next session be paying special attention to that the derived view doesn't capture? Any nuance the data alone wouldn't communicate?_

## What's Next (LLM-tagged from derived data)

_Order the open backlog pickups + active plans + queued decisions by priority, with one-line rationale per item. Auto-derived items + LLM-added priority judgment._

<!-- ===== END LLM SYNTHESIS ===== -->
EOF
    printf '[state-summary] created SCRATCHPAD.md with derived + synthesis scaffolding\n' >&2
    return 0
  fi

  # SCRATCHPAD exists. Check for existing markers.
  if grep -q '^<!-- ===== DERIVED' "$scratchpad" \
     && grep -q '^<!-- ===== END DERIVED' "$scratchpad"; then
    # Replace the DERIVED block in place.
    local tmp="${scratchpad}.tmp"
    awk -v derived="$derived" '
      /^<!-- ===== DERIVED/ { in_derived = 1; print derived; next }
      /^<!-- ===== END DERIVED/ { in_derived = 0; next }
      !in_derived { print }
    ' "$scratchpad" > "$tmp"
    mv "$tmp" "$scratchpad"
    printf '[state-summary] updated DERIVED block in SCRATCHPAD.md (LLM SYNTHESIS preserved)\n' >&2
  else
    # No markers found. Prepend a derived block, leave existing content as LLM synthesis.
    local tmp="${scratchpad}.tmp"
    {
      echo "$derived"
      echo ""
      echo "<!-- ===== LLM SYNTHESIS — orchestrator authors below; preserved by apply ===== -->"
      echo ""
      cat "$scratchpad"
      echo ""
      echo "<!-- ===== END LLM SYNTHESIS ===== -->"
    } > "$tmp"
    mv "$tmp" "$scratchpad"
    printf '[state-summary] migrated SCRATCHPAD.md to derived + synthesis layout\n' >&2
  fi
}

# ----- Self-test -----

cmd_self_test() {
  local TMPROOT
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t state-summary)
  trap 'rm -rf "$TMPROOT"' EXIT
  local PASSED=0 FAILED=0

  cd "$TMPROOT"
  git init -q .
  git config user.email "test@example.test"
  git config user.name "Test"
  mkdir -p docs/plans docs/plans/archive docs/decisions docs/discoveries

  # Setup primary-source fixtures
  cat > docs/plans/test-active.md <<'EOF'
# Plan: Test Active

Status: ACTIVE

## Tasks

- [x] 1. Done
- [ ] 2. Pending
EOF

  cat > docs/backlog.md <<'EOF'
# Backlog

## Open work

- **HARNESS-GAP-99** — Test gap one.
- **HARNESS-GAP-100** — Test gap two.
EOF

  cat > docs/decisions/queued-tranche-test.md <<'EOF'
# Queued Decisions — Test

### T.1 — Test decision

**Recommendation:** Option A.

**User override (if any):**

EOF

  cat > docs/discoveries/test-pending.md <<'EOF'
---
title: Test pending discovery
status: pending
---
EOF

  git add . && git commit -q -m "init"

  # ---- S1: derive produces all sections
  local s1_out
  s1_out=$(cmd_derive "$TMPROOT" 2>&1)
  if printf '%s' "$s1_out" | grep -q '## Active Plans' \
     && printf '%s' "$s1_out" | grep -q 'test-active' \
     && printf '%s' "$s1_out" | grep -q 'HARNESS-GAP-99' \
     && printf '%s' "$s1_out" | grep -q 'queued-tranche-test.md' \
     && printf '%s' "$s1_out" | grep -q 'test-pending.md'; then
    echo "self-test (S1) derive-all-sections: PASS"
    PASSED=$((PASSED+1))
  else
    echo "self-test (S1) derive-all-sections: FAIL"
    FAILED=$((FAILED+1))
  fi

  # ---- S2: apply creates SCRATCHPAD with markers
  rm -f SCRATCHPAD.md
  cmd_apply "$TMPROOT" >/dev/null 2>&1
  if [ -f SCRATCHPAD.md ] \
     && grep -q '===== DERIVED' SCRATCHPAD.md \
     && grep -q '===== END DERIVED' SCRATCHPAD.md \
     && grep -q '===== LLM SYNTHESIS' SCRATCHPAD.md; then
    echo "self-test (S2) apply-creates-scratchpad: PASS"
    PASSED=$((PASSED+1))
  else
    echo "self-test (S2) apply-creates-scratchpad: FAIL"
    FAILED=$((FAILED+1))
  fi

  # ---- S3: apply preserves LLM section content
  cat > SCRATCHPAD.md <<'EOF'
<!-- ===== DERIVED — DO NOT EDIT MANUALLY (state-summary.sh apply) ===== -->
old derived content
<!-- ===== END DERIVED ===== -->

<!-- ===== LLM SYNTHESIS — orchestrator authors below; preserved by apply ===== -->

## Synthesis (LLM-authored)

PRESERVE_THIS_TOKEN_42

<!-- ===== END LLM SYNTHESIS ===== -->
EOF
  cmd_apply "$TMPROOT" >/dev/null 2>&1
  if grep -q 'PRESERVE_THIS_TOKEN_42' SCRATCHPAD.md \
     && grep -q '## Active Plans' SCRATCHPAD.md \
     && ! grep -q 'old derived content' SCRATCHPAD.md; then
    echo "self-test (S3) apply-preserves-llm-section: PASS"
    PASSED=$((PASSED+1))
  else
    echo "self-test (S3) apply-preserves-llm-section: FAIL"
    FAILED=$((FAILED+1))
  fi

  # ---- S4: master clean (no active plans) shows "None"
  rm docs/plans/test-active.md
  git add . && git commit -q -m "remove active plan"
  local s4_out
  s4_out=$(cmd_derive "$TMPROOT" 2>&1)
  if printf '%s' "$s4_out" | grep -q '_None — master is clean._'; then
    echo "self-test (S4) clean-master-shows-none: PASS"
    PASSED=$((PASSED+1))
  else
    echo "self-test (S4) clean-master-shows-none: FAIL"
    FAILED=$((FAILED+1))
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed (of $((PASSED + FAILED)) scenarios)"
  if [ "$FAILED" -gt 0 ]; then exit 1; fi
  exit 0
}

# ----- Main -----

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

case "$1" in
  --help|-h) usage; exit 0 ;;
  --self-test) cmd_self_test ;;
  derive)
    REPO="$(find_repo_root)" || { echo "state-summary: not in a git repo" >&2; exit 2; }
    cmd_derive "$REPO"
    ;;
  apply)
    REPO="$(find_repo_root)" || { echo "state-summary: not in a git repo" >&2; exit 2; }
    cmd_apply "$REPO"
    ;;
  *)
    echo "state-summary: unknown subcommand: $1" >&2
    usage
    exit 2
    ;;
esac
