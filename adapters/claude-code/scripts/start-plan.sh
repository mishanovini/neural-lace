#!/bin/bash
# start-plan.sh — deterministic task-start automation (Path A item 4, 2026-05-06).
#
# Generates the mechanical artifacts a new plan needs at kickoff:
#   1. docs/plans/<slug>.md              from plan-template.md, header populated
#   2. docs/decisions/queued-<slug>.md   empty decision queue (skippable via --no-queue)
#
# What STAYS LLM-authored: the body sections (Goal, Scope, Tasks, Files to
# Modify/Create, Assumptions, Edge Cases, Acceptance Scenarios, Testing
# Strategy). Those need domain knowledge the script does not have. The script
# only covers the deterministic scaffolding that previously required the
# orchestrator to read the template, fill in 6+ header fields by hand, create
# two files, stage them, and remember the right defaults each time.
#
# Subcommands:
#   start <slug> "<scope hint>" [flags]   Create scaffold
#   check <slug>                          Print availability ("AVAILABLE" or
#                                         where the slug already lives)
#   --self-test                           Run internal test scenarios
#   --help                                Show usage
#
# Flags:
#   --tier <1-5>                  default 1
#   --rung <0-5>                  default 0
#   --architecture <name>         default coding-harness
#   --mode <code|design|design-skip>  default code
#   --frozen                      default false (set this flag to start frozen)
#   --prd-ref <slug>              default "n/a — harness-development"
#   --execution-mode <name>       default orchestrator
#   --acceptance-exempt           default false (set flag to be exempt)
#   --acceptance-exempt-reason "<reason>"
#   --absorb-backlog "<slug,slug>"   default "none"
#   --no-queue                    skip creating the decisions queue file
#   --no-stage                    skip git add (default stages both files)
#
# Exit codes:
#   0 — scaffold created and staged
#   1 — generic failure (template missing, etc.)
#   2 — usage error or slug already taken

set -uo pipefail

SCRIPT_NAME="start-plan.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: start-plan.sh start <slug> "<scope hint>" [flags]
       start-plan.sh check <slug>
       start-plan.sh --self-test
       start-plan.sh --help

Creates the deterministic scaffold for a new plan: the plan file from
plan-template.md with header fields populated, plus an empty decision queue
at docs/decisions/queued-<slug>.md (skip with --no-queue). Body sections
remain placeholder for the orchestrator to fill in with domain knowledge.

Examples:
  start-plan.sh start auth-refactor "Move OAuth token rotation to background worker"
  start-plan.sh start gap-22-force-sweep "Sweep harness for residual --force flags" --tier 2
  start-plan.sh start widget-redesign "Replace widget grid with masonry layout" \
    --mode design --tier 3 --rung 3

The slug must be kebab-case ASCII (^[a-z][a-z0-9-]{2,59}$) and must not
collide with an existing plan (active or archive) or a queued-decisions file.

For absorbing backlog items into the new plan, pass --absorb-backlog "slug-1,slug-2".
The backlog-plan-atomicity hook still enforces that the absorbed entries are
deleted from the backlog in the same commit; start-plan.sh does NOT modify the
backlog (that is the orchestrator's responsibility, in the same commit).
EOF
}

iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S"
}

today_date() {
  date +"%Y-%m-%d"
}

# ---------------------------------------------------------------------------
# Slug validation: kebab-case, ASCII, 3-60 chars, leading lowercase letter
# ---------------------------------------------------------------------------
validate_slug() {
  local slug="$1"
  if [[ ! "$slug" =~ ^[a-z][a-z0-9-]{2,59}$ ]]; then
    printf '%s: invalid slug "%s"\n' "$SCRIPT_NAME" "$slug" >&2
    printf '  must match: ^[a-z][a-z0-9-]{2,59}$  (kebab-case, ASCII, 3-60 chars)\n' >&2
    return 2
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Slug-or-archive collision check. Searches:
#   - docs/plans/<slug>.md           (active)
#   - docs/plans/archive/<slug>.md   (archived)
#   - docs/decisions/queued-<slug>.md
# Reports the first match found; returns non-zero on collision.
# ---------------------------------------------------------------------------
check_slug_available() {
  local slug="$1"
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="."

  if [[ -f "$repo_root/docs/plans/$slug.md" ]]; then
    printf 'TAKEN — active plan exists: docs/plans/%s.md\n' "$slug"
    return 1
  fi
  if [[ -f "$repo_root/docs/plans/archive/$slug.md" ]]; then
    printf 'TAKEN — archived plan exists: docs/plans/archive/%s.md\n' "$slug"
    return 1
  fi
  if [[ -f "$repo_root/docs/decisions/queued-$slug.md" ]]; then
    printf 'TAKEN — queued decisions file exists: docs/decisions/queued-%s.md\n' "$slug"
    return 1
  fi
  printf 'AVAILABLE\n'
  return 0
}

# ---------------------------------------------------------------------------
# Slug → human-readable title. "auth-refactor" → "Auth Refactor".
# ---------------------------------------------------------------------------
slug_to_title() {
  local slug="$1"
  local out=""
  local IFS='-'
  read -ra parts <<< "$slug"
  local p
  for p in "${parts[@]}"; do
    out+="${p^} "
  done
  printf '%s\n' "${out% }"
}

# ---------------------------------------------------------------------------
# Locate plan-template.md. Repo-relative first (canonical source); then
# ~/.claude/templates/ (live mirror); fail with explicit message if neither.
# ---------------------------------------------------------------------------
locate_template() {
  local repo_root="$1"
  local repo_template="$repo_root/adapters/claude-code/templates/plan-template.md"
  local user_template="$HOME/.claude/templates/plan-template.md"

  if [[ -f "$repo_template" ]]; then
    printf '%s' "$repo_template"
    return 0
  fi
  if [[ -f "$user_template" ]]; then
    printf '%s' "$user_template"
    return 0
  fi
  printf '%s: cannot locate plan-template.md (looked in %s and %s)\n' \
    "$SCRIPT_NAME" "$repo_template" "$user_template" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Generate plan file from template. Substitutes:
#   "# Plan: [Task Title]"     →  "# Plan: <Title>"
#   header field defaults populated from flags
#   first scope IN bullet seeded with the user-provided scope hint
# ---------------------------------------------------------------------------
generate_plan_file() {
  local template_path="$1"
  local out_path="$2"
  local slug="$3"
  local scope_hint="$4"
  local title
  title=$(slug_to_title "$slug")

  local tier="${TIER:-1}"
  local rung="${RUNG:-0}"
  local arch="${ARCHITECTURE:-coding-harness}"
  local mode="${MODE:-code}"
  local frozen="${FROZEN:-false}"
  local prd_ref="${PRD_REF:-n/a — harness-development}"
  local exec_mode="${EXECUTION_MODE:-orchestrator}"
  local acc_exempt="${ACCEPTANCE_EXEMPT:-false}"
  local acc_reason="${ACCEPTANCE_EXEMPT_REASON:-}"
  local absorbed="${ABSORB_BACKLOG:-none}"

  # Compose the header block. We rebuild the top-of-file lines in one pass
  # rather than using sed -i in a loop (sed in-place varies across platforms).
  local tmp
  tmp=$(mktemp)

  # Read template, replace the title line and known scalar header fields.
  # Template comments (HTML <!-- ... -->) we keep intact for reader context;
  # they don't affect plan-reviewer.sh checks.
  awk -v title="$title" \
      -v tier="$tier" -v rung="$rung" -v arch="$arch" -v mode="$mode" \
      -v frozen="$frozen" -v prd_ref="$prd_ref" -v exec_mode="$exec_mode" \
      -v acc_exempt="$acc_exempt" -v acc_reason="$acc_reason" \
      -v absorbed="$absorbed" -v scope_hint="$scope_hint" '
    BEGIN { seen_first_in = 0 }
    /^# Plan: \[Task Title\]$/                  { print "# Plan: " title; next }
    /^Execution Mode: orchestrator$/            { print "Execution Mode: " exec_mode; next }
    /^Mode: code$/                              { print "Mode: " mode; next }
    /^Backlog items absorbed: \[none/           { print "Backlog items absorbed: " absorbed; next }
    /^acceptance-exempt: false$/                { print "acceptance-exempt: " acc_exempt; next }
    /^acceptance-exempt-reason:$/               {
      if (acc_reason != "") {
        print "acceptance-exempt-reason: " acc_reason
      } else {
        print "acceptance-exempt-reason:"
      }
      next
    }
    /^tier: <1-5>$/                             { print "tier: " tier; next }
    /^rung: <0-5>$/                             { print "rung: " rung; next }
    /^architecture: <coding-harness/            { print "architecture: " arch; next }
    /^frozen: false$/                           { print "frozen: " frozen; next }
    /^prd-ref: <slug \| n\/a — harness-development>$/ { print "prd-ref: " prd_ref; next }
    /^- IN: \[what.s included/                  {
      if (!seen_first_in) {
        print "- IN: " scope_hint
        seen_first_in = 1
        next
      }
    }
    { print }
  ' "$template_path" > "$tmp"

  # Insert a kickoff timestamp banner at the very top of the file (above the
  # title) so a future session can grep "scaffold-created:" for plan provenance.
  {
    printf '<!-- scaffold-created: %s by %s slug=%s -->\n' "$(iso_timestamp)" "$SCRIPT_NAME" "$slug"
    cat "$tmp"
  } > "$out_path"

  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Generate decisions-queue file. Minimal scaffold; LLM populates as decisions
# arise during plan execution.
# ---------------------------------------------------------------------------
generate_decisions_queue() {
  local out_path="$1"
  local slug="$2"
  local title
  title=$(slug_to_title "$slug")

  cat > "$out_path" <<EOF
# Queued Decisions — $title
<!-- scaffold-created: $(iso_timestamp) by $SCRIPT_NAME slug=$slug -->

Plan: \`docs/plans/$slug.md\`
Created: $(today_date)

This file accumulates plan-time and mid-build decisions whose direction
is reversible enough to proceed-with-recommendation but worth surfacing
to the user for async override (per ADR 027).

## Format per entry

\`\`\`
### D-NNN — <one-line description>

**Status:** awaiting / decided / superseded
**Decided:** <YYYY-MM-DD or empty>
**Surfaced to user:** <YYYY-MM-DD HH:MM via AskUserQuestion or in summary>

**Question:** <what choice needs to be made>

**Options:**
- A. <option> — <cost / benefit>
- B. <option> — <cost / benefit>

**Recommendation:** <chosen option, with one-sentence justification>

**User override (if any):** <empty until user replies>

**Decision applied at:** <commit SHA or "n/a — pending">
\`\`\`

## Decisions

(none yet)
EOF
}

# ---------------------------------------------------------------------------
# CLI flag parsing. Sets globals consumed by generate_plan_file.
# ---------------------------------------------------------------------------
parse_flags() {
  TIER=""
  RUNG=""
  ARCHITECTURE=""
  MODE=""
  FROZEN=""
  PRD_REF=""
  EXECUTION_MODE=""
  ACCEPTANCE_EXEMPT=""
  ACCEPTANCE_EXEMPT_REASON=""
  ABSORB_BACKLOG=""
  NO_QUEUE=0
  NO_STAGE=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tier)              TIER="$2"; shift 2;;
      --rung)              RUNG="$2"; shift 2;;
      --architecture)      ARCHITECTURE="$2"; shift 2;;
      --mode)              MODE="$2"; shift 2;;
      --frozen)            FROZEN="true"; shift;;
      --prd-ref)           PRD_REF="$2"; shift 2;;
      --execution-mode)    EXECUTION_MODE="$2"; shift 2;;
      --acceptance-exempt) ACCEPTANCE_EXEMPT="true"; shift;;
      --acceptance-exempt-reason) ACCEPTANCE_EXEMPT_REASON="$2"; shift 2;;
      --absorb-backlog)    ABSORB_BACKLOG="$2"; shift 2;;
      --no-queue)          NO_QUEUE=1; shift;;
      --no-stage)          NO_STAGE=1; shift;;
      *)
        printf '%s: unknown flag "%s"\n' "$SCRIPT_NAME" "$1" >&2
        return 2
        ;;
    esac
  done
  export TIER RUNG ARCHITECTURE MODE FROZEN PRD_REF EXECUTION_MODE \
    ACCEPTANCE_EXEMPT ACCEPTANCE_EXEMPT_REASON ABSORB_BACKLOG
  return 0
}

# ---------------------------------------------------------------------------
# Main `start` subcommand entry point.
# ---------------------------------------------------------------------------
start_plan() {
  local slug="${1:-}"
  shift || true
  local scope_hint="${1:-}"
  shift || true

  if [[ -z "$slug" ]]; then
    printf '%s: missing <slug>\n\n' "$SCRIPT_NAME" >&2
    usage >&2
    return 2
  fi
  if [[ -z "$scope_hint" ]]; then
    printf '%s: missing <scope hint> (one-line description)\n\n' "$SCRIPT_NAME" >&2
    usage >&2
    return 2
  fi

  validate_slug "$slug" || return 2

  if ! parse_flags "$@"; then
    return 2
  fi

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    printf '%s: not in a git repo\n' "$SCRIPT_NAME" >&2
    return 1
  }

  local availability
  availability=$(check_slug_available "$slug")
  if [[ "$availability" != "AVAILABLE" ]]; then
    printf '%s: slug collision\n  %s\n' "$SCRIPT_NAME" "$availability" >&2
    return 2
  fi

  local template_path
  template_path=$(locate_template "$repo_root") || return 1

  local plan_path="$repo_root/docs/plans/$slug.md"
  local queue_path="$repo_root/docs/decisions/queued-$slug.md"

  mkdir -p "$repo_root/docs/plans" "$repo_root/docs/decisions"

  generate_plan_file "$template_path" "$plan_path" "$slug" "$scope_hint"
  printf '%s: created %s\n' "$SCRIPT_NAME" "docs/plans/$slug.md" >&2

  if [[ "$NO_QUEUE" -eq 0 ]]; then
    generate_decisions_queue "$queue_path" "$slug"
    printf '%s: created %s\n' "$SCRIPT_NAME" "docs/decisions/queued-$slug.md" >&2
  fi

  if [[ "$NO_STAGE" -eq 0 ]]; then
    (cd "$repo_root" && git add "docs/plans/$slug.md") 2>/dev/null
    if [[ "$NO_QUEUE" -eq 0 ]]; then
      (cd "$repo_root" && git add "docs/decisions/queued-$slug.md") 2>/dev/null
    fi
    printf '%s: staged for commit (use --no-stage to skip)\n' "$SCRIPT_NAME" >&2
  fi

  printf '\n%s: scaffold ready. Next steps:\n' "$SCRIPT_NAME" >&2
  printf '  1. Edit %s to fill in Goal / Scope / Tasks / Files to Modify/Create\n' "docs/plans/$slug.md" >&2
  printf '  2. If absorbing backlog items, edit docs/backlog.md to delete them and commit together\n' >&2
  printf '  3. Commit: git commit -m "plan: %s — kickoff"\n' "$slug" >&2
  return 0
}

# ---------------------------------------------------------------------------
# Self-test scaffolding. Builds a synthetic git repo with the template, runs
# scenarios against it, asserts on file/content shape, cleans up.
# ---------------------------------------------------------------------------
setup_synthetic_repo() {
  local label="$1"
  local d
  d=$(mktemp -d -t "start-plan-${label}.XXXX")
  (
    cd "$d" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    mkdir -p docs/plans docs/decisions adapters/claude-code/templates
    # Minimal template — must contain the lines start-plan.sh substitutes.
    cat > adapters/claude-code/templates/plan-template.md <<'EOF'
# Plan: [Task Title]
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: [none | slug-1, slug-2]
acceptance-exempt: false
acceptance-exempt-reason:
tier: <1-5>
rung: <0-5>
architecture: <coding-harness | dark-factory | auto-research | orchestration | hybrid>
frozen: false
prd-ref: <slug | n/a — harness-development>

## Goal
[stub]

## Scope
- IN: [what's included]
- OUT: [excluded]

## Tasks
- [ ] 1. stub

## Files to Modify/Create
- `path` — stub
EOF
    git add . && git commit -q -m "init"
  )
  printf '%s' "$d"
}

run_self_test() {
  local PASSED=0 FAILED=0
  local SELF_PATH
  SELF_PATH="$(realpath "${BASH_SOURCE[0]}")"

  # ----- S1: happy path -----
  local D1
  D1=$(setup_synthetic_repo "S1")
  (cd "$D1" && bash "$SELF_PATH" start widget-tweak "Make the widget pop" --no-stage >/dev/null 2>&1)
  if [[ -f "$D1/docs/plans/widget-tweak.md" ]] \
     && grep -q '^# Plan: Widget Tweak$' "$D1/docs/plans/widget-tweak.md" \
     && grep -q '^Mode: code$' "$D1/docs/plans/widget-tweak.md" \
     && grep -q '^- IN: Make the widget pop$' "$D1/docs/plans/widget-tweak.md" \
     && [[ -f "$D1/docs/decisions/queued-widget-tweak.md" ]]; then
    printf 'self-test (S1) happy-path-creates-both-files: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S1) happy-path-creates-both-files: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D1"

  # ----- S2: invalid slug rejected -----
  local D2 s2_rc s2_out
  D2=$(setup_synthetic_repo "S2")
  s2_out=$(cd "$D2" && bash "$SELF_PATH" start "Invalid Slug" "scope" --no-stage 2>&1)
  s2_rc=$?
  if [[ $s2_rc -eq 2 ]] && printf '%s' "$s2_out" | grep -q 'invalid slug'; then
    printf 'self-test (S2) invalid-slug-rejected: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S2) invalid-slug-rejected: FAIL (rc=%s)\n' "$s2_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D2"

  # ----- S3: collision with active plan -----
  local D3 s3_rc s3_out
  D3=$(setup_synthetic_repo "S3")
  printf 'existing\n' > "$D3/docs/plans/foo-bar.md"
  s3_out=$(cd "$D3" && bash "$SELF_PATH" start foo-bar "scope" --no-stage 2>&1)
  s3_rc=$?
  if [[ $s3_rc -eq 2 ]] && printf '%s' "$s3_out" | grep -q 'TAKEN'; then
    printf 'self-test (S3) active-collision-detected: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S3) active-collision-detected: FAIL (rc=%s)\n' "$s3_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D3"

  # ----- S4: collision with archived plan -----
  local D4 s4_rc s4_out
  D4=$(setup_synthetic_repo "S4")
  mkdir -p "$D4/docs/plans/archive"
  printf 'archived\n' > "$D4/docs/plans/archive/legacy-plan.md"
  s4_out=$(cd "$D4" && bash "$SELF_PATH" start legacy-plan "scope" --no-stage 2>&1)
  s4_rc=$?
  if [[ $s4_rc -eq 2 ]] && printf '%s' "$s4_out" | grep -q 'archive'; then
    printf 'self-test (S4) archive-collision-detected: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S4) archive-collision-detected: FAIL (rc=%s)\n' "$s4_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D4"

  # ----- S5: --no-queue suppresses queue file -----
  local D5
  D5=$(setup_synthetic_repo "S5")
  (cd "$D5" && bash "$SELF_PATH" start no-q-test "scope" --no-queue --no-stage >/dev/null 2>&1)
  if [[ -f "$D5/docs/plans/no-q-test.md" ]] \
     && [[ ! -f "$D5/docs/decisions/queued-no-q-test.md" ]]; then
    printf 'self-test (S5) --no-queue-skips-queue: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S5) --no-queue-skips-queue: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D5"

  # ----- S6: header flags propagate -----
  local D6
  D6=$(setup_synthetic_repo "S6")
  (cd "$D6" && bash "$SELF_PATH" start design-thing "scope" \
    --tier 3 --rung 2 --mode design --architecture orchestration \
    --frozen --prd-ref some-slug --no-stage >/dev/null 2>&1)
  if [[ -f "$D6/docs/plans/design-thing.md" ]] \
     && grep -q '^tier: 3$' "$D6/docs/plans/design-thing.md" \
     && grep -q '^rung: 2$' "$D6/docs/plans/design-thing.md" \
     && grep -q '^Mode: design$' "$D6/docs/plans/design-thing.md" \
     && grep -q '^architecture: orchestration$' "$D6/docs/plans/design-thing.md" \
     && grep -q '^frozen: true$' "$D6/docs/plans/design-thing.md" \
     && grep -q '^prd-ref: some-slug$' "$D6/docs/plans/design-thing.md"; then
    printf 'self-test (S6) header-flags-propagate: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S6) header-flags-propagate: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D6"

  # ----- S7: check subcommand reports availability -----
  local D7 s7_out
  D7=$(setup_synthetic_repo "S7")
  s7_out=$(cd "$D7" && bash "$SELF_PATH" check fresh-slug 2>&1)
  if [[ "$s7_out" == "AVAILABLE" ]]; then
    printf 'self-test (S7a) check-available: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7a) check-available: FAIL (output=%q)\n' "$s7_out" >&2
    FAILED=$((FAILED+1))
  fi
  printf 'existing\n' > "$D7/docs/plans/taken-slug.md"
  s7_out=$(cd "$D7" && bash "$SELF_PATH" check taken-slug 2>&1)
  if printf '%s' "$s7_out" | grep -q '^TAKEN'; then
    printf 'self-test (S7b) check-taken: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7b) check-taken: FAIL (output=%q)\n' "$s7_out" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D7"

  # ----- S8: scaffold-created banner present -----
  local D8
  D8=$(setup_synthetic_repo "S8")
  (cd "$D8" && bash "$SELF_PATH" start banner-check "scope" --no-stage >/dev/null 2>&1)
  if [[ -f "$D8/docs/plans/banner-check.md" ]] \
     && head -1 "$D8/docs/plans/banner-check.md" | grep -q 'scaffold-created:'; then
    printf 'self-test (S8) scaffold-banner-present: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S8) scaffold-banner-present: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D8"

  printf '\nself-test summary: %d passed, %d failed (of %d scenarios)\n' \
    "$PASSED" "$FAILED" "$((PASSED+FAILED))" >&2
  if [[ "$FAILED" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Top-level dispatch.
# ---------------------------------------------------------------------------
main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    start)
      start_plan "$@"
      ;;
    check)
      local slug="${1:-}"
      if [[ -z "$slug" ]]; then
        printf '%s: missing <slug>\n' "$SCRIPT_NAME" >&2
        return 2
      fi
      validate_slug "$slug" || return 2
      check_slug_available "$slug"
      ;;
    --self-test)
      run_self_test
      ;;
    --help|-h|"")
      usage
      ;;
    *)
      printf '%s: unknown subcommand "%s"\n\n' "$SCRIPT_NAME" "$cmd" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
