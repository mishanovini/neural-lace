#!/bin/bash
# discovery-surfacer.sh
#
# SessionStart hook that scans `docs/discoveries/` in the current working
# directory for files at `Status: pending` and surfaces them as a system
# reminder so the decision-maker (the user, the next agent turn) sees
# pending discoveries waiting for resolution.
#
# This is the surfacing half of the discovery protocol shipped in
# ~/.claude/rules/discovery-protocol.md. The capture half lives in the
# extended `bug-persistence-gate.sh` (which now treats
# `docs/discoveries/YYYY-MM-DD-*.md` as legitimate persistence alongside
# `docs/backlog.md` and `docs/reviews/`).
#
# Design notes:
# - Reads JSON on stdin per the Claude Code SessionStart hook contract,
#   but the payload is unused — the hook acts on the working directory.
# - On any unrecoverable error (missing dir, no pending files), exits 0
#   silently. Surfacing is informational; never block session start.
# - For each pending discovery, extracts title, type, date,
#   originating_context, decision_needed (frontmatter), and a brief
#   excerpt of the Recommendation section (body).
# - Output is plain stdout text — the same convention used by other
#   SessionStart hooks in this harness (see effort-policy-warn.sh and
#   the inline commands in settings.json.template).
#
# Self-test: invoke with --self-test to exercise four scenarios.

set -u

# -------- Utility: pull a YAML frontmatter scalar value --------
# Reads a single-line `key: value` from the first 30 lines (covers the
# YAML frontmatter region). Strips surrounding quotes if present.
fm_value() {
  local file="$1"
  local key="$2"
  head -n 30 "$file" 2>/dev/null \
    | grep -iE "^${key}:[[:space:]]*" \
    | head -n 1 \
    | sed -E "s/^[^:]+:[[:space:]]*//; s/^['\"](.*)['\"]\$/\1/"
}

# -------- Utility: detect frontmatter presence --------
# Returns 0 if the file starts with `---` on line 1 (YAML frontmatter
# block) — i.e. it's a structured discovery file. Otherwise returns 1.
has_frontmatter() {
  local file="$1"
  [ -f "$file" ] || return 1
  local first
  first=$(head -n 1 "$file" 2>/dev/null)
  [ "$first" = "---" ]
}

# -------- Utility: extract Recommendation section excerpt --------
# Looks for `## Recommendation` (or `### Recommendation`) in the body
# and returns up to ~200 chars of the following content (one paragraph).
extract_recommendation() {
  local file="$1"
  awk '
    BEGIN { in_section = 0; out = "" }
    /^#{2,3}[[:space:]]+Recommendation[[:space:]]*$/ { in_section = 1; next }
    /^#{1,3}[[:space:]]/ {
      if (in_section) { exit }
    }
    {
      if (in_section) {
        # Strip leading whitespace; collapse multiple spaces.
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line == "") {
          if (out != "") next
        } else {
          out = (out == "" ? line : out " " line)
        }
        if (length(out) >= 200) { exit }
      }
    }
    END { print substr(out, 1, 200) }
  ' "$file" 2>/dev/null
}

# -------- Core surfacing logic --------
# Args (for testability):
#   $1 = working directory to scan (defaults to $PWD)
# Writes the system-reminder block to stdout. Exits 0 always.
surface_discoveries() {
  local cwd="${1:-$PWD}"
  local discoveries_dir="$cwd/docs/discoveries"

  # If the directory doesn't exist, exit silently. This is the common
  # case in projects that haven't adopted the protocol yet.
  if [ ! -d "$discoveries_dir" ]; then
    return 0
  fi

  # Collect pending discovery files. We use a deterministic sort so
  # multiple pending discoveries are surfaced in date-then-name order.
  local pending_files=()
  local f base status_val
  for f in "$discoveries_dir"/*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    # Filter to the YYYY-MM-DD-*.md naming convention so README.md or
    # other narrative files in the directory are excluded.
    case "$base" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;;
      *) continue ;;
    esac

    # Skip files without frontmatter — they are not valid discoveries.
    if ! has_frontmatter "$f"; then
      echo "[discovery-surfacer] skipping $base (no frontmatter)" >&2
      continue
    fi

    # Read status. Defensive default: missing status field is treated
    # as `pending` so a malformed-but-real discovery doesn't get hidden.
    status_val=$(fm_value "$f" "status" 2>/dev/null)
    status_val=$(echo "$status_val" | tr '[:upper:]' '[:lower:]')

    if [ -z "$status_val" ] || [ "$status_val" = "pending" ]; then
      pending_files+=("$f")
    fi
  done

  # Empty (no pending discoveries) -> silent.
  if [ "${#pending_files[@]}" -eq 0 ]; then
    return 0
  fi

  # Sort the file list so output order is stable across runs.
  local sorted_files=()
  while IFS= read -r line; do
    [ -n "$line" ] && sorted_files+=("$line")
  done < <(printf '%s\n' "${pending_files[@]}" | sort)

  # Emit the system-reminder block.
  local count="${#sorted_files[@]}"
  echo "[discovery-surfacer] $count pending discoveries require attention:"
  echo ""

  local title type_val date_val origin decision rec
  for f in "${sorted_files[@]}"; do
    base=$(basename "$f")
    title=$(fm_value "$f" "title")
    type_val=$(fm_value "$f" "type")
    date_val=$(fm_value "$f" "date")
    origin=$(fm_value "$f" "originating_context")
    decision=$(fm_value "$f" "decision_needed")
    rec=$(extract_recommendation "$f")

    # Fallbacks so the block is always readable even when frontmatter
    # is partial.
    [ -z "$title" ] && title="(untitled — see file)"
    [ -z "$type_val" ] && type_val="(unspecified)"
    [ -z "$date_val" ] && date_val="(undated)"
    [ -z "$origin" ] && origin="(see file)"
    [ -z "$decision" ] && decision="(see file)"
    if [ -z "$rec" ]; then
      rec="(see file)"
    elif [ ${#rec} -ge 200 ]; then
      rec="${rec}…"
    fi

    # Truncate decision_needed to first 200 chars.
    if [ ${#decision} -gt 200 ]; then
      decision="${decision:0:200}…"
    fi

    echo "  • $title (type: $type_val, date: $date_val)"
    echo "    Originating context: $origin"
    echo "    Decision needed: $decision"
    echo "    Recommendation (excerpt): $rec"
    echo "    File: docs/discoveries/$base"
    echo ""
  done

  echo "These discoveries surfaced in prior sessions and are awaiting decision."
  echo "Per ~/.claude/rules/discovery-protocol.md, options: (a) review and decide"
  echo "inline; (b) auto-apply the recommendation if reversible; (c) defer"
  echo "explicitly via Status: superseded or Status: rejected."
}

# -------- Self-test --------
run_self_test() {
  local tmp failures=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t discsfc)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  run_scenario() {
    local label="$1" expect_output="$2" project_dir="$3" out
    out=$(surface_discoveries "$project_dir" 2>/dev/null)
    if [ "$expect_output" = "yes" ]; then
      if [ -z "$out" ]; then
        echo "FAIL: [$label] expected output but got none" >&2
        failures=$((failures + 1))
      else
        echo "PASS: [$label] surfaced as expected"
      fi
    elif [ "$expect_output" = "named" ]; then
      # Caller passed an additional 4th argument: the title we expect.
      local expected_title="$4"
      if [ -z "$out" ]; then
        echo "FAIL: [$label] expected output but got none" >&2
        failures=$((failures + 1))
      elif ! echo "$out" | grep -qF "$expected_title"; then
        echo "FAIL: [$label] output did not name '$expected_title':" >&2
        echo "$out" | head -n 5 | sed 's/^/    /' >&2
        failures=$((failures + 1))
      else
        echo "PASS: [$label] surfaced and named '$expected_title'"
      fi
    else
      if [ -n "$out" ]; then
        echo "FAIL: [$label] expected silence but got: $out" >&2
        failures=$((failures + 1))
      else
        echo "PASS: [$label] silent as expected"
      fi
    fi
  }

  # ---- Scenario 1: no docs/discoveries directory at all ----
  local s1="$tmp/no-discoveries"
  mkdir -p "$s1"
  run_scenario "no-directory" no "$s1"

  # ---- Scenario 2: directory exists but empty ----
  local s2="$tmp/empty-discoveries"
  mkdir -p "$s2/docs/discoveries"
  run_scenario "empty-directory" no "$s2"

  # ---- Scenario 3: directory has 2 files, both Status: decided ----
  local s3="$tmp/all-decided"
  mkdir -p "$s3/docs/discoveries"
  cat > "$s3/docs/discoveries/2026-05-03-already-decided.md" <<'EOF'
---
title: Already-decided discovery
date: 2026-05-03
type: process
status: decided
auto_applied: true
originating_context: test fixture
decision_needed: n/a — auto-applied
---

## What was discovered
Test content.

## Recommendation
Should not surface.
EOF
  cat > "$s3/docs/discoveries/2026-05-03-also-implemented.md" <<'EOF'
---
title: Implemented discovery
date: 2026-05-03
type: architectural-learning
status: implemented
auto_applied: false
originating_context: test fixture
decision_needed: n/a
---

## What was discovered
More test content.

## Recommendation
Also should not surface.
EOF
  run_scenario "all-decided" no "$s3"

  # ---- Scenario 4: directory has 1 file with Status: pending ----
  local s4="$tmp/has-pending"
  mkdir -p "$s4/docs/discoveries"
  cat > "$s4/docs/discoveries/2026-05-03-needs-decision.md" <<'EOF'
---
title: Needs-decision discovery
date: 2026-05-03
type: scope-expansion
status: pending
auto_applied: false
originating_context: test fixture for self-test
decision_needed: Should we adopt approach X or approach Y?
predicted_downstream:
  - docs/plans/example.md
---

## What was discovered
Self-test content describing what surfaced.

## Why it matters
Without resolution, future sessions will rediscover this.

## Options
- A: do X
- B: do Y

## Recommendation
Adopt approach Y because it preserves backward compatibility with the
existing capture pathway and avoids the migration cost of approach X.

## Decision
EOF
  run_scenario "has-pending" named "$s4" "Needs-decision discovery"

  # ---- Bonus scenario 5: file matching name pattern but no frontmatter ----
  local s5="$tmp/no-fm"
  mkdir -p "$s5/docs/discoveries"
  cat > "$s5/docs/discoveries/2026-05-03-no-frontmatter.md" <<'EOF'
This file matches the naming pattern but has no frontmatter so it
should be skipped.
EOF
  run_scenario "no-frontmatter-skipped" no "$s5"

  # ---- Bonus scenario 6: missing status field defaults to pending ----
  local s6="$tmp/missing-status"
  mkdir -p "$s6/docs/discoveries"
  cat > "$s6/docs/discoveries/2026-05-03-missing-status.md" <<'EOF'
---
title: Missing-status discovery
date: 2026-05-03
type: process
originating_context: defensive default test
decision_needed: Should we treat missing status as pending?
---

## Recommendation
Yes — surface so the user can correct the frontmatter.
EOF
  run_scenario "missing-status-defaults-pending" named "$s6" "Missing-status discovery"

  if [ "$failures" -eq 0 ]; then
    echo ""
    echo "SELF-TEST: all scenarios passed (4/4 required + 2 bonus)"
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
# contract) but we don't need to parse it — the hook acts on the
# working directory.
if [ ! -t 0 ]; then
  cat >/dev/null 2>&1 || true
fi

surface_discoveries "$PWD"
exit 0
