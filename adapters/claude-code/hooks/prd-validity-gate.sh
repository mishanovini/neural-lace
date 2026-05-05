#!/bin/bash
# prd-validity-gate.sh — Phase 1d-C-2 (C1), 2026-05-04
#
# PreToolUse hook that blocks plan creation/edit when the plan's `prd-ref:`
# header field resolves to a missing or incomplete `docs/prd.md`.
#
# Rule (mechanism, Build Doctrine §6 C1): every plan that intends to ship
# product-user-visible work must reference a Product Requirements Document
# (PRD) with 7 required sections: Problem, Scenarios, Functional,
# Non-functional, Success metrics, Out-of-scope, Open questions. Each
# section must have ≥ 30 non-whitespace chars of substantive content.
#
# Trigger:
#   PreToolUse on tool_name == "Write". Only fires when the target file
#   matches `docs/plans/<slug>.md` (top-level, not archive/). Pass-through
#   on non-Write tool calls and non-plan-file Write calls.
#
# Carve-out:
#   `prd-ref: n/a — harness-development` (exact match — em-dash, exact
#   phrasing) bypasses the PRD check entirely. Mirrors the
#   acceptance-exempt convention.
#
# Logic:
#   1. Read tool_input.file_path. If not docs/plans/<slug>.md, allow.
#   2. Read plan content from tool_input.content (or fall back to file
#      on disk if it already exists).
#   3. Extract `prd-ref:` field from first 30 lines.
#   4. If missing → ALLOW with WARN (Check 10 in plan-reviewer.sh enforces).
#   5. If `n/a — harness-development` (exact) → ALLOW.
#   6. Else resolve to <repo-root>/docs/prd.md:
#      - If missing → BLOCK (name path + point at template).
#      - If exists → verify all 7 sections present + each ≥ 30 non-ws chars.
#      - On any failure → BLOCK with the failing section name(s).
#   7. On PASS, ALLOW + recommend invoking `prd-validity-reviewer` for
#      substance review.
#
# Single PRD per project (Decision 015):
#   The PRD lives at `docs/prd.md` (single canonical path), NOT
#   `docs/prd/<slug>.md` per Build Doctrine §6 default. SCRATCHPAD-locked.
#
# Exit codes:
#   0 — allow (plan write proceeds)
#   1 — block (stderr explains why)
#   2 — input parse error (passes through to allow; we don't lock up the
#       session on hook bugs)

# ============================================================
# Helper: normalize a path (forward-slash, repo-relative)
# ============================================================
_normalize_path() {
  local p="$1"
  # Convert backslashes to forward slashes (Windows compatibility)
  p="${p//\\//}"
  printf '%s' "$p"
}

# ============================================================
# Helper: is this a top-level docs/plans/<slug>.md file?
# Returns 0 (true) if matches, 1 otherwise.
# ============================================================
_is_top_level_plan() {
  local p
  p=$(_normalize_path "$1")
  # Strip any leading directory prefix to find the docs/plans/ portion
  case "$p" in
    *docs/plans/archive/*) return 1 ;;
    *docs/plans/*.md)
      # Confirm exactly one path segment between docs/plans/ and .md
      local tail="${p##*docs/plans/}"
      case "$tail" in
        */*) return 1 ;;  # has another / so it's nested
        *.md) return 0 ;;
      esac
      return 1
      ;;
    *) return 1 ;;
  esac
}

# ============================================================
# Helper: extract `prd-ref:` value from plan content
# Reads from stdin. Echoes the value (or empty if missing).
# Searches first 30 lines only.
# ============================================================
_extract_prd_ref() {
  awk 'NR<=30 && /^prd-ref:[[:space:]]/ {
    sub(/^prd-ref:[[:space:]]*/, "")
    sub(/[[:space:]]+$/, "")
    print
    exit
  }'
}

# ============================================================
# Helper: locate repo root from a plan file path
# Walks up from the file's directory looking for .git or docs/plans/.
# Echoes the root path (or empty if not found).
# ============================================================
_find_repo_root() {
  local start_dir="$1"
  local current="$start_dir"
  while [[ -n "$current" ]] && [[ "$current" != "/" ]] && [[ "$current" != "." ]]; do
    if [[ -d "$current/.git" ]] || [[ -d "$current/docs/plans" ]]; then
      printf '%s' "$current"
      return 0
    fi
    local parent
    parent=$(dirname "$current")
    [[ "$parent" == "$current" ]] && break
    current="$parent"
  done
  return 1
}

# ============================================================
# Helper: check a single PRD section for presence + substance.
# $1 = PRD file path, $2 = section name (canonical, e.g., "Problem")
# Returns 0 if section is present and substantive, 1 otherwise.
# Sets _SECTION_FAIL_REASON on failure.
#
# Section name matching: case-insensitive prefix match on the heading
# word. So "## Functional" matches "Functional", "Functional requirements",
# etc. "## Success metrics" matches "Success metrics", "Success Metrics", etc.
# ============================================================
_SECTION_FAIL_REASON=""
_check_prd_section() {
  local prd_file="$1"
  local canonical="$2"

  # Find a heading line that case-insensitively starts with "## <canonical>"
  # We use awk + tolower for case-insensitive match.
  local heading_line
  heading_line=$(awk -v want="$canonical" '
    BEGIN { want_lc = tolower(want) }
    /^## / {
      heading = $0
      sub(/^## /, "", heading)
      heading_lc = tolower(heading)
      # Match if heading starts with the canonical name as a whole word
      n = length(want_lc)
      if (substr(heading_lc, 1, n) == want_lc) {
        # Next char must be space, end-of-line, or punctuation (not letter)
        next_ch = substr(heading_lc, n + 1, 1)
        if (next_ch == "" || next_ch == " " || next_ch == "\t" || next_ch == "s" || next_ch == ":") {
          # "s" tolerates "Scenarios" being matched by "Scenario" if ever swapped
          print NR
          exit
        }
      }
    }
  ' "$prd_file" 2>/dev/null)

  if [[ -z "$heading_line" ]]; then
    _SECTION_FAIL_REASON="missing section '## $canonical'"
    return 1
  fi

  # Extract body: lines after heading up to next ## heading or EOF
  local body
  body=$(awk -v start="$heading_line" '
    NR == start { next }
    NR > start {
      if ($0 ~ /^## /) exit
      print
    }
  ' "$prd_file" 2>/dev/null | awk '
    /<!--/ { in_comment = 1 }
    !in_comment { print }
    /-->/ { in_comment = 0 }
  ')

  # Count non-whitespace chars
  local non_ws_count
  non_ws_count=$(printf '%s' "$body" | tr -d '[:space:]' | wc -c | tr -cd '[:digit:]')
  non_ws_count=${non_ws_count:-0}

  if [[ "$non_ws_count" -lt 30 ]]; then
    _SECTION_FAIL_REASON="section '## $canonical' has only $non_ws_count non-whitespace chars (need >= 30)"
    return 1
  fi

  # Placeholder-only check
  local stripped="$body"
  stripped=$(printf '%s' "$stripped" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')
  for pat in '\[populate me\]' '\[todo\]' 'todo' '\.\.\.' '\[tbd\]' 'tbd'; do
    stripped=$(printf '%s' "$stripped" | sed -E "s|${pat}||g")
  done
  stripped=$(printf '%s' "$stripped" | sed -E 's|[[:space:]]*[-*][[:space:]]*||g; s|[][(){}:;,.!?"`'"'"']||g')
  stripped=$(printf '%s' "$stripped" | tr -d '[:space:]')

  if [[ -z "$stripped" ]]; then
    _SECTION_FAIL_REASON="section '## $canonical' contains only placeholder text (e.g., '[populate me]', 'TODO')"
    return 1
  fi

  return 0
}

# ============================================================
# Helper: validate PRD file (all 7 sections present + substantive).
# $1 = PRD file path. Returns 0 if PRD is valid, 1 otherwise.
# Sets _PRD_FAIL_REASONS (newline-separated) on failure.
# ============================================================
_PRD_FAIL_REASONS=""
_validate_prd() {
  local prd_file="$1"
  local sections=("Problem" "Scenarios" "Functional" "Non-functional" "Success metrics" "Out-of-scope" "Open questions")
  _PRD_FAIL_REASONS=""
  local fail_count=0
  for sec in "${sections[@]}"; do
    if ! _check_prd_section "$prd_file" "$sec"; then
      if [[ -z "$_PRD_FAIL_REASONS" ]]; then
        _PRD_FAIL_REASONS="$_SECTION_FAIL_REASON"
      else
        _PRD_FAIL_REASONS="${_PRD_FAIL_REASONS}
$_SECTION_FAIL_REASON"
      fi
      fail_count=$((fail_count + 1))
    fi
  done
  if [[ "$fail_count" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ============================================================
# --self-test handler (six scenarios)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ ! -f "$SELF_TEST_HOOK" ]]; then
    echo "self-test: cannot resolve own path" >&2
    exit 2
  fi

  PASSED=0
  FAILED=0
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t prd-validity)
  if [[ -z "$TMPROOT" ]] || [[ ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  # Helper: prepare a synthetic repo with optional PRD + a target plan file.
  # Args: $1 = scenario label
  #       $2 = plan content (will be written to docs/plans/test-plan.md)
  #       $3 = PRD content (empty = no PRD); written to docs/prd.md
  # Returns hook's exit code by echoing it.
  _run_scenario() {
    local label="$1" plan_body="$2" prd_body="$3"
    local repo="$TMPROOT/$label"
    mkdir -p "$repo/docs/plans"
    # Initialize as a git repo so _find_repo_root finds it
    (cd "$repo" && git init -q 2>/dev/null || true)

    if [[ -n "$prd_body" ]]; then
      printf '%s' "$prd_body" > "$repo/docs/prd.md"
    fi

    local plan_path="$repo/docs/plans/test-plan.md"
    # The hook reads from tool_input.content first, then falls back to disk.
    # For these tests we pass content via JSON so the disk doesn't matter,
    # but write it to disk too for the fallback path coverage.
    printf '%s' "$plan_body" > "$plan_path"

    # Construct PreToolUse JSON input
    local plan_path_escaped
    plan_path_escaped=$(printf '%s' "$plan_path" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local plan_body_escaped
    plan_body_escaped=$(printf '%s' "$plan_body" | jq -Rs . 2>/dev/null || printf '""')

    local input
    input=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s}}' \
      "$plan_path_escaped" "$plan_body_escaped")

    printf '%s' "$input" | bash "$SELF_TEST_HOOK" >"$repo/stdout.txt" 2>"$repo/stderr.txt"
    echo $?
  }

  # PRD content with all 7 sections, each ≥ 30 non-ws chars
  PRD_GOOD='# Product Requirements Document

## Problem
The widget pricing tool is currently confusing for new users who do not understand the relationship between base price and modifiers. They consistently abandon the form at step three.

## Scenarios
Scenario A: a new user opens the pricing form, enters their org details, and reaches the modifier step. Scenario B: an existing user updates their pricing for a returning customer.

## Functional
The system shall provide a simplified pricing form with inline help text. It shall validate org input before allowing the user to proceed to modifiers. It shall persist drafts.

## Non-functional
The form shall load in under 500ms. It shall meet WCAG AA contrast requirements. It shall work in Safari, Chrome, and Firefox latest two versions.

## Success metrics
Form completion rate increases from 38% to 60% within 30 days. Average time-to-complete decreases from 4 minutes to 2.5 minutes. Drop-off at step three falls below 10%.

## Out-of-scope
Mobile-first redesign is not in scope. Bulk pricing import is not in scope. Multi-currency support is deferred to a future release.

## Open questions
What is the right default for the modifier dropdown? Should we A/B test the help-text variants? Who owns the support documentation update?
'

  PRD_MISSING_FUNCTIONAL='# Product Requirements Document

## Problem
The widget pricing tool is currently confusing for new users who do not understand the relationship between base price and modifiers.

## Scenarios
Scenario A: a new user opens the pricing form, enters their org details, and reaches the modifier step.

## Non-functional
The form shall load in under 500ms. It shall meet WCAG AA contrast requirements.

## Success metrics
Form completion rate increases from 38% to 60% within 30 days.

## Out-of-scope
Mobile-first redesign is not in scope. Bulk pricing import is not in scope.

## Open questions
What is the right default for the modifier dropdown?
'

  PRD_PLACEHOLDER_METRICS='# Product Requirements Document

## Problem
The widget pricing tool is currently confusing for new users who do not understand the relationship between base price and modifiers.

## Scenarios
Scenario A: a new user opens the pricing form, enters their org details, and reaches the modifier step.

## Functional
The system shall provide a simplified pricing form with inline help text and validation.

## Non-functional
The form shall load in under 500ms. It shall meet WCAG AA contrast requirements.

## Success metrics
[populate me]

## Out-of-scope
Mobile-first redesign is not in scope. Bulk pricing import is not in scope.

## Open questions
What is the right default for the modifier dropdown?
'

  PLAN_WITH_PRD_REF='# Plan: real feature
Status: ACTIVE
Mode: code
prd-ref: simplified-pricing-form

## Goal
Build the simplified pricing form per the PRD.

## Tasks
- [ ] 1. build it.
'

  PLAN_HARNESS_DEV='# Plan: harness-internal
Status: ACTIVE
Mode: code
prd-ref: n/a — harness-development

## Goal
Internal harness work.

## Tasks
- [ ] 1. test
'

  PLAN_NO_PRD_REF='# Plan: missing prd-ref
Status: ACTIVE
Mode: code

## Goal
Some work that lacks a prd-ref.

## Tasks
- [ ] 1. test
'

  # ---- Scenario 1: PASS-with-PRD ----
  RC=$(_run_scenario s1 "$PLAN_WITH_PRD_REF" "$PRD_GOOD")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (1) PASS-with-PRD: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (1) PASS-with-PRD: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s1/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 2: PASS-with-harness-dev-carveout ----
  RC=$(_run_scenario s2 "$PLAN_HARNESS_DEV" "")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (2) PASS-with-harness-dev-carveout: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (2) PASS-with-harness-dev-carveout: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s2/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 3: ALLOW-no-prd-ref (with WARN) ----
  # Per logic step 3: missing prd-ref is ALLOWED (Check 10 in plan-reviewer
  # catches it). Hook should exit 0 with a warning on stderr.
  RC=$(_run_scenario s3 "$PLAN_NO_PRD_REF" "")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (3) ALLOW-no-prd-ref-with-WARN: PASS (rc=$RC, expected 0; warns expected)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (3) ALLOW-no-prd-ref-with-WARN: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s3/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 4: FAIL-prd-file-missing ----
  # plan has prd-ref: real-feature but no docs/prd.md exists
  RC=$(_run_scenario s4 "$PLAN_WITH_PRD_REF" "")
  if [[ "$RC" == "1" ]]; then
    echo "self-test (4) FAIL-prd-file-missing: PASS (rc=$RC, expected 1; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (4) FAIL-prd-file-missing: FAIL (rc=$RC, expected 1)" >&2
    cat "$TMPROOT/s4/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 5: FAIL-prd-section-missing ----
  RC=$(_run_scenario s5 "$PLAN_WITH_PRD_REF" "$PRD_MISSING_FUNCTIONAL")
  if [[ "$RC" == "1" ]]; then
    echo "self-test (5) FAIL-prd-section-missing: PASS (rc=$RC, expected 1; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (5) FAIL-prd-section-missing: FAIL (rc=$RC, expected 1)" >&2
    cat "$TMPROOT/s5/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 6: FAIL-prd-section-placeholder ----
  RC=$(_run_scenario s6 "$PLAN_WITH_PRD_REF" "$PRD_PLACEHOLDER_METRICS")
  if [[ "$RC" == "1" ]]; then
    echo "self-test (6) FAIL-prd-section-placeholder: PASS (rc=$RC, expected 1; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (6) FAIL-prd-section-placeholder: FAIL (rc=$RC, expected 1)" >&2
    cat "$TMPROOT/s6/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 6 scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# Main hook logic
# ============================================================

# --- Read tool input (env var OR stdin, supporting both Claude Code shapes) ---
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]] && [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi
if [[ -z "$INPUT" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  # Without jq we can't safely parse — pass through (errs toward allow).
  exit 0
fi

# Tool name must be Write
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
if [[ "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# Extract file_path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .file_path // ""' 2>/dev/null)
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Only fire on top-level plan files
if ! _is_top_level_plan "$FILE_PATH"; then
  exit 0
fi

# Read plan content. Prefer tool_input.content (the about-to-be-written
# content); fall back to disk if not provided.
PLAN_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_content // .content // ""' 2>/dev/null)
if [[ -z "$PLAN_CONTENT" ]] && [[ -f "$FILE_PATH" ]]; then
  PLAN_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")
fi
if [[ -z "$PLAN_CONTENT" ]]; then
  # Nothing to validate — pass through.
  exit 0
fi

# Extract prd-ref field from first 30 lines
PRD_REF=$(printf '%s' "$PLAN_CONTENT" | _extract_prd_ref)

# Logic step 3: missing prd-ref → ALLOW with WARN (Check 10 catches it)
if [[ -z "$PRD_REF" ]]; then
  echo "[prd-validity] plan=$FILE_PATH prd-ref=<missing> verdict=ALLOW-WARN reason=missing-prd-ref-field-deferred-to-plan-reviewer-Check-10" >&2
  exit 0
fi

# Logic step 4: harness-dev carve-out (exact match — em-dash, exact phrasing)
if [[ "$PRD_REF" == "n/a — harness-development" ]]; then
  echo "[prd-validity] plan=$FILE_PATH prd-ref=harness-dev-carveout verdict=ALLOW" >&2
  exit 0
fi

# Logic step 5: resolve to docs/prd.md
# Find repo root from the plan file's directory.
PLAN_DIR=$(dirname "$FILE_PATH")
REPO_ROOT=$(_find_repo_root "$PLAN_DIR" 2>/dev/null || echo "")
if [[ -z "$REPO_ROOT" ]]; then
  # Can't find repo — pass through (errs toward allow on hook bug).
  echo "[prd-validity] plan=$FILE_PATH prd-ref=$PRD_REF verdict=ALLOW reason=cannot-find-repo-root" >&2
  exit 0
fi

PRD_PATH="$REPO_ROOT/docs/prd.md"

# Step 6a: PRD file missing
if [[ ! -f "$PRD_PATH" ]]; then
  {
    echo "================================================================"
    echo "PRD-VALIDITY GATE — PLAN BLOCKED"
    echo "================================================================"
    echo ""
    echo "Plan declares prd-ref: $PRD_REF"
    echo "But the PRD file is missing at: $PRD_PATH"
    echo ""
    echo "Required: a Product Requirements Document at docs/prd.md with"
    echo "7 sections: Problem, Scenarios, Functional, Non-functional,"
    echo "Success metrics, Out-of-scope, Open questions. Each section"
    echo "must have >= 30 non-whitespace chars of substantive content."
    echo ""
    echo "Options:"
    echo "  1. Create docs/prd.md from the template at"
    echo "     ~/.claude/templates/prd-template.md"
    echo "  2. If this plan does not need a PRD (harness-internal work),"
    echo "     change prd-ref to: n/a — harness-development"
    echo ""
    echo "[prd-validity] plan=$FILE_PATH prd-ref=$PRD_REF verdict=FAIL reason=prd-file-missing path=$PRD_PATH"
    echo "================================================================"
  } >&2
  exit 1
fi

# Step 6b/7: validate the PRD
if ! _validate_prd "$PRD_PATH"; then
  {
    echo "================================================================"
    echo "PRD-VALIDITY GATE — PLAN BLOCKED"
    echo "================================================================"
    echo ""
    echo "Plan declares prd-ref: $PRD_REF"
    echo "PRD file exists at: $PRD_PATH"
    echo "But the PRD has section problems:"
    echo ""
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "  • $line"
    done <<< "$_PRD_FAIL_REASONS"
    echo ""
    echo "Required: 7 sections (Problem, Scenarios, Functional,"
    echo "Non-functional, Success metrics, Out-of-scope, Open questions),"
    echo "each with >= 30 non-whitespace chars of substantive content."
    echo "See template at ~/.claude/templates/prd-template.md."
    echo ""
    echo "[prd-validity] plan=$FILE_PATH prd-ref=$PRD_REF verdict=FAIL reason=prd-sections-incomplete path=$PRD_PATH"
    echo "================================================================"
  } >&2
  exit 1
fi

# Step 8: PASS — emit structured stderr + recommend substance review
echo "[prd-validity] plan=$FILE_PATH prd-ref=$PRD_REF verdict=PASS sections=7/7 path=$PRD_PATH" >&2
echo "[prd-validity] Recommended after mechanical fixes: invoke 'prd-validity-reviewer' agent for substance review." >&2

exit 0
