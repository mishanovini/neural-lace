#!/bin/bash
# close-plan.sh — deterministic close-plan procedure (Tranche E, 2026-05-05).
#
# Replaces the existing /close-plan skill (today a wrapper around the heavy
# verification stack) with a deterministic bash script that closes plans in
# seconds with zero agent dispatches.
#
# Consumes the substrates Tranches B (mechanical evidence) and D (risk-tiered
# verification) shipped:
#   - Verification: mechanical → bash check + structured .evidence.json
#   - Verification: contract   → schema/golden-file comparison
#   - Verification: full       → existing prose-evidence path (unchanged)
#
# Generates completion report from template + commit log, updates SCRATCHPAD,
# reconciles backlog, flips Status (which triggers plan-lifecycle.sh archival),
# auto-pushes per user's full-auto preference (per E.2).
#
# Subcommands:
#   close <plan-slug> [--no-push]              Close the plan
#   --self-test                               Run internal test scenarios
#   --help                                    Show usage
#
# Flags:
#   --no-push   Commit only; do NOT auto-push to origin.
#
# When verification fails, close-plan.sh prints a remediation guide:
#   1. Happy path: generate missing structured evidence via write-evidence.sh capture
#   2. Substantive emergency: CLOSE_PLAN_EMERGENCY_OVERRIDE="<rationale>=40 chars>" env var
# The legacy --force flag is REMOVED — it became the orchestrator's reflexive bypass.
# See docs/reviews/2026-05-06-force-usage-honest-accounting.md.
#
# Exit codes:
#   0 — plan closed and Status flipped to COMPLETED
#   1 — generic failure
#   2 — usage error or hard block (failed mechanical verification, no override)
#
# Build Doctrine reference: queued-tranche-1.5.md E.1-E.3, plan
# docs/plans/architecture-simplification-tranche-e-deterministic-close-plan.md.

set -uo pipefail

SCRIPT_NAME="close-plan.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: close-plan.sh close <plan-slug> [--no-push]
       close-plan.sh --self-test
       close-plan.sh --help

Deterministic close-plan procedure. Routes each task per its declared
`Verification:` level (mechanical | contract | full), generates the
completion report, updates SCRATCHPAD, verifies backlog reconciliation,
flips Status to COMPLETED (which triggers plan-lifecycle.sh archival),
commits, and auto-pushes (unless --no-push).

Examples:
  close-plan.sh close my-plan-slug
  close-plan.sh close my-plan --no-push

When verification blocks, follow the printed remediation guide:
  - Happy path: generate the missing structured evidence
  - Emergency: CLOSE_PLAN_EMERGENCY_OVERRIDE env var (>=40-char rationale required)
EOF
}

iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S"
}

# ---------------------------------------------------------------------------
# Plan-file locator. Active first, then archive.
# ---------------------------------------------------------------------------
locate_plan_file() {
  local slug="$1"
  if [[ -f "docs/plans/$slug.md" ]]; then
    printf '%s\n' "docs/plans/$slug.md"
    return 0
  fi
  if [[ -f "docs/plans/archive/$slug.md" ]]; then
    printf '%s\n' "docs/plans/archive/$slug.md"
    return 0
  fi
  return 1
}

# Extract the `Verification:` level for a given task from a plan's task line.
# Looks at the line itself AND the immediately following indented continuation
# lines until the next top-level `- [` task or section break.
# Returns: mechanical | contract | full (default: full).
extract_verification_level() {
  local plan_file="$1"
  local task_id="$2"

  # Find the task's line + continuation block.
  awk -v tid="$task_id" '
    BEGIN { in_block = 0 }
    # Top-level task line — e.g., "- [ ] 1. Foo" or "- [x] 1.2 Foo"
    /^- \[[x ]\] / {
      if (in_block) exit
      # Match task ID at start of task body
      line = $0
      # Strip the "- [ ] " or "- [x] " prefix
      sub(/^- \[[x ]\] /, "", line)
      # Now line begins with the task id
      if (match(line, "^" tid "(\\.|\\.|\\b|[. ])") || index(line, tid " ") == 1 || index(line, tid ".") == 1) {
        in_block = 1
        print line
        next
      }
    }
    # Inside continuation: lines that are not new top-level tasks/sections
    in_block {
      if (/^- \[[x ]\] /) exit  # next task
      if (/^## /)         exit  # next section
      if (/^# /)          exit  # next chapter
      print
    }
  ' "$plan_file" > /tmp/cp-task-block-$$.txt 2>/dev/null

  local block
  block=$(cat /tmp/cp-task-block-$$.txt 2>/dev/null)
  rm -f /tmp/cp-task-block-$$.txt

  # Look for `Verification: <level>` in the task block. Case-insensitive.
  if [[ -z "$block" ]]; then
    printf 'full\n'
    return 0
  fi

  local level
  level=$(printf '%s\n' "$block" | grep -iEo 'Verification:[[:space:]]*(mechanical|contract|full)' | head -1 | sed -e 's/Verification:[[:space:]]*//I' | tr '[:upper:]' '[:lower:]')

  if [[ -z "$level" ]]; then
    printf 'full\n'
    return 0
  fi

  printf '%s\n' "$level"
}

# Extract every task-id from the plan's `## Tasks` section. Task IDs are the
# first whitespace-delimited token after `- [ ] ` or `- [x] `.
extract_task_ids() {
  local plan_file="$1"
  awk '
    /^## Tasks[[:space:]]*$/ { in_tasks = 1; next }
    in_tasks && /^## / && !/^## Tasks/ { exit }
    in_tasks && /^- \[[x ]\] / {
      line = $0
      sub(/^- \[[x ]\] /, "", line)
      # First whitespace-delimited token, with optional trailing dot
      n = split(line, parts, /[. ]/)
      if (n >= 1 && parts[1] != "") {
        print parts[1]
      }
    }
  ' "$plan_file"
}

# Locate the sibling evidence file for a plan (returns empty if absent).
locate_evidence_file() {
  local plan_file="$1"
  local plan_dir plan_slug
  plan_dir=$(dirname "$plan_file")
  plan_slug=$(basename "$plan_file" .md)
  local candidate="$plan_dir/${plan_slug}-evidence.md"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

# Locate the sibling structured-evidence directory (Tranche B convention).
locate_evidence_dir() {
  local plan_file="$1"
  local plan_dir plan_slug
  plan_dir=$(dirname "$plan_file")
  plan_slug=$(basename "$plan_file" .md)
  local candidate="$plan_dir/${plan_slug}-evidence"
  if [[ -d "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Verification routes per Tranche D
# ---------------------------------------------------------------------------

# Verification: mechanical. PASS if either (a) a structured .evidence.json
# under <evidence-dir>/<task-id>.evidence.json with verdict==PASS, OR
# (b) a one-line evidence-block in the prose evidence file with a commit-SHA
# citation referencing the task.
verify_task_mechanical() {
  local plan_file="$1"
  local task_id="$2"
  local plan_dir plan_slug
  plan_dir=$(dirname "$plan_file")
  plan_slug=$(basename "$plan_file" .md)

  # Path (a) — structured evidence
  local structured="$plan_dir/${plan_slug}-evidence/${task_id}.evidence.json"
  if [[ -f "$structured" ]]; then
    local verdict
    if command -v jq >/dev/null 2>&1; then
      verdict=$(jq -r .verdict "$structured" 2>/dev/null)
    else
      verdict=$(grep -oE '"verdict"[[:space:]]*:[[:space:]]*"[^"]+"' "$structured" \
                | sed -e 's/.*"\([^"]*\)"$/\1/')
    fi
    if [[ "$verdict" == "PASS" ]]; then
      return 0
    fi
  fi

  # Path (b) — prose evidence with commit-SHA citation
  local evidence_file
  evidence_file=$(locate_evidence_file "$plan_file") || true
  if [[ -n "${evidence_file:-}" ]] && [[ -f "$evidence_file" ]]; then
    if grep -qE "Task[[:space:]]+(ID:[[:space:]]*)?${task_id}\b" "$evidence_file" \
       && grep -qE 'commit[[:space:]:]+[0-9a-f]{7,}' "$evidence_file"; then
      return 0
    fi
  fi

  # Also accept evidence in the plan's own ## Evidence Log section.
  if grep -qE "Task[[:space:]]+(ID:[[:space:]]*)?${task_id}\b" "$plan_file" \
     && awk '/^## Evidence Log/{flag=1; next} /^## /{flag=0} flag' "$plan_file" \
        | grep -qE 'commit[[:space:]:]+[0-9a-f]{7,}'; then
    return 0
  fi

  return 1
}

# Verification: contract. PASS if a sibling .contract.json or .golden file is
# present and either (a) the task-block declares `Contract: <path>` and that
# path exists, or (b) a structured-evidence file marks PASS for this task.
verify_task_contract() {
  local plan_file="$1"
  local task_id="$2"
  local plan_dir plan_slug
  plan_dir=$(dirname "$plan_file")
  plan_slug=$(basename "$plan_file" .md)

  # If structured-evidence already PASS, accept.
  local structured="$plan_dir/${plan_slug}-evidence/${task_id}.evidence.json"
  if [[ -f "$structured" ]]; then
    local verdict
    if command -v jq >/dev/null 2>&1; then
      verdict=$(jq -r .verdict "$structured" 2>/dev/null)
    else
      verdict=$(grep -oE '"verdict"[[:space:]]*:[[:space:]]*"[^"]+"' "$structured" \
                | sed -e 's/.*"\([^"]*\)"$/\1/')
    fi
    if [[ "$verdict" == "PASS" ]]; then
      return 0
    fi
  fi

  # Try to find a `Contract:` reference in the task block.
  local block contract_ref
  block=$(awk -v tid="$task_id" '
    /^- \[[x ]\] / {
      line = $0
      sub(/^- \[[x ]\] /, "", line)
      if (index(line, tid " ") == 1 || index(line, tid ".") == 1) { in_block = 1; print line; next }
      else if (in_block) { exit }
    }
    in_block { if (/^- \[[x ]\] /) exit; if (/^## /) exit; print }
  ' "$plan_file" 2>/dev/null)

  contract_ref=$(printf '%s\n' "$block" | grep -oE 'Contract:[[:space:]]*[^[:space:]]+' | head -1 | sed -e 's/Contract:[[:space:]]*//')

  if [[ -n "$contract_ref" ]] && [[ -e "$contract_ref" ]]; then
    return 0
  fi

  # Fall through to mechanical-style evidence acceptance if the contract path
  # was not declared (legacy plans).
  verify_task_mechanical "$plan_file" "$task_id"
  return $?
}

# Verification: full. PASS if a prose evidence-block exists with `Verdict: PASS`.
verify_task_full() {
  local plan_file="$1"
  local task_id="$2"
  local evidence_file
  evidence_file=$(locate_evidence_file "$plan_file") || true

  # Search both sibling evidence file and the plan's Evidence Log section.
  local search_files=("$plan_file")
  [[ -n "${evidence_file:-}" ]] && [[ -f "$evidence_file" ]] && search_files+=("$evidence_file")

  local f
  for f in "${search_files[@]}"; do
    # Find a block that has BOTH "Task ID: <id>" (or "Task <id>") and "Verdict: PASS"
    # within the same block. Block boundaries: blank line or "Task ID:".
    if awk -v tid="$task_id" '
      BEGIN { found_id=0; found_pass=0 }
      /Task[[:space:]]+(ID:[[:space:]]*)?[A-Za-z0-9.-]+/ {
        if (found_id && found_pass) exit 0
        found_id=0; found_pass=0
        if (match($0, "Task[[:space:]]+(ID:[[:space:]]*)?" tid "([^A-Za-z0-9.-]|$)")) {
          found_id=1
        }
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
# Procedure: completion-report generator
# ---------------------------------------------------------------------------

generate_completion_report() {
  local plan_file="$1"
  local plan_slug
  plan_slug=$(basename "$plan_file" .md)

  # Files-to-modify discovery: parse the `## Files to Modify/Create` section.
  local files_section
  files_section=$(awk '
    /^## Files to Modify\/Create/ { flag=1; next }
    flag && /^## / { flag=0 }
    flag { print }
  ' "$plan_file")

  # Extract bare paths from the files section. Lines look like:
  #   `- adapters/.../foo.sh — NEW (~300 lines)`
  # We strip the leading `- ` and take the first whitespace-delimited token,
  # also handling backtick-wrapped paths: `- \`path\` — ...`
  local files_list
  files_list=$(printf '%s\n' "$files_section" \
    | grep -oE '^- [`]?[a-zA-Z0-9._/~-]+' \
    | sed -e 's/^- //' -e 's/^`//' -e 's/`$//' \
    | sort -u)

  # Run git log for commits touching those files.
  local commits=""
  if command -v git >/dev/null 2>&1; then
    if [[ -n "$files_list" ]]; then
      commits=$(printf '%s\n' "$files_list" \
        | xargs -I{} sh -c 'git log --oneline --no-merges -- "{}" 2>/dev/null' 2>/dev/null \
        | sort -u | head -30)
    fi
  fi

  # Build the report. Heredoc keeps it readable.
  local timestamp
  timestamp=$(iso_timestamp)

  cat <<EOF
## Completion Report

_Generated by close-plan.sh on ${timestamp}._

### 1. Implementation Summary

Plan: \`$plan_file\` (slug: \`$plan_slug\`).

Files touched (per plan's \`## Files to Modify/Create\`):

$(printf '%s\n' "$files_list" | sed -e 's/^/- `/' -e 's/$/`/')

Commits referencing these files:

\`\`\`
$commits
\`\`\`

Backlog items absorbed: see plan header \`Backlog items absorbed:\` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's \`## Decisions Log\` section for the inline record. Tier 2+
decisions should each have a \`docs/decisions/NNN-*.md\` record landed in
their implementing commit per \`~/.claude/rules/planning.md\`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's \`## Testing Strategy\` and \`## Evidence Log\` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
EOF
}

# Append/replace ## Completion Report section in the plan file.
write_completion_report() {
  local plan_file="$1"
  local report_text="$2"

  local tmp
  tmp=$(mktemp)

  # Strip any existing ## Completion Report section, then append fresh.
  awk '
    /^## Completion Report/ { skipping = 1; next }
    skipping && /^## / && !/^## Completion Report/ { skipping = 0 }
    !skipping { print }
  ' "$plan_file" > "$tmp"

  # Trim trailing blank lines and append the fresh report.
  local body
  body=$(cat "$tmp")
  printf '%s\n\n%s\n' "$body" "$report_text" > "$plan_file"

  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# SCRATCHPAD update
# ---------------------------------------------------------------------------
update_scratchpad() {
  local plan_slug="$1"
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="."

  local scratch="$repo_root/SCRATCHPAD.md"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

  if [[ ! -f "$scratch" ]]; then
    cat > "$scratch" <<EOF
# SCRATCHPAD

## Plan closures
Plan closed: $plan_slug ($timestamp via close-plan.sh)
EOF
    return 0
  fi

  # Append a "Plan closed: <slug>" line to the file.
  printf '\n<!-- close-plan.sh: Plan closed: %s (%s) -->\n' "$plan_slug" "$timestamp" >> "$scratch"
  return 0
}

# ---------------------------------------------------------------------------
# Backlog reconciliation check
# ---------------------------------------------------------------------------
verify_backlog_reconciled() {
  local plan_file="$1"
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="."
  local backlog="$repo_root/docs/backlog.md"

  # Extract `Backlog items absorbed:` value from the plan header.
  local absorbed_line
  absorbed_line=$(grep -E '^Backlog items absorbed:' "$plan_file" | head -1)

  if [[ -z "$absorbed_line" ]]; then
    return 0  # field absent — no reconciliation needed
  fi

  local absorbed_value
  absorbed_value=$(printf '%s\n' "$absorbed_line" | sed -e 's/^Backlog items absorbed:[[:space:]]*//' | xargs)

  if [[ -z "$absorbed_value" || "$absorbed_value" == "none" ]]; then
    return 0
  fi

  if [[ ! -f "$backlog" ]]; then
    printf 'backlog file not found: %s\n' "$backlog" >&2
    return 1
  fi

  # Split by comma; for each absorbed slug, ensure it does NOT appear in
  # an OPEN section (i.e., one of the canonical-open headings) or, if it
  # does, has a `(deferred from ` / `ABSORBED` / `(absorbed into ` marker.
  local slug fail=0
  IFS=',' read -ra slugs <<< "$absorbed_value"
  for slug in "${slugs[@]}"; do
    slug=$(printf '%s' "$slug" | xargs)
    [[ -z "$slug" ]] && continue
    # If slug doesn't appear at all, that's fine (already removed).
    if ! grep -q "$slug" "$backlog" 2>/dev/null; then
      continue
    fi
    # If it appears, it must appear with a marker OR under a closed section.
    # Find the line; check for inline marker.
    if grep -E "$slug" "$backlog" | grep -qE '\(absorbed into|\(deferred from|ABSORBED|Recently implemented|Completed|Resolved'; then
      continue
    fi
    # Otherwise check the section context around the line.
    local line_context
    line_context=$(awk -v s="$slug" '
      /^## / { sec = $0 }
      $0 ~ s { print sec }
    ' "$backlog" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$line_context" | grep -qE 'recently implemented|completed|resolved|absorbed|archive'; then
      continue
    fi
    printf 'backlog reconciliation: item "%s" still appears in an open section of %s\n' "$slug" "$backlog" >&2
    fail=1
  done

  if [[ $fail -ne 0 ]]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Main close subcommand
# ---------------------------------------------------------------------------
cmd_close() {
  local slug=""
  local no_push=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-push) no_push=true; shift ;;
      --help|-h) usage; return 0 ;;
      --force)
        printf '%s: --force flag REMOVED (2026-05-06).\n' "$SCRIPT_NAME" >&2
        printf 'Reason: see docs/reviews/2026-05-06-force-usage-honest-accounting.md\n' >&2
        printf 'When verification blocks, satisfy the check or use CLOSE_PLAN_EMERGENCY_OVERRIDE env var.\n' >&2
        return 2
        ;;
      --*) printf '%s: unknown flag: %s\n' "$SCRIPT_NAME" "$1" >&2; return 2 ;;
      *)
        if [[ -z "$slug" ]]; then
          slug="$1"; shift
        else
          printf '%s: unexpected arg: %s\n' "$SCRIPT_NAME" "$1" >&2
          return 2
        fi
        ;;
    esac
  done

  if [[ -z "$slug" ]]; then
    printf '%s: <plan-slug> is required\n' "$SCRIPT_NAME" >&2
    usage >&2
    return 2
  fi

  local plan_file
  plan_file=$(locate_plan_file "$slug") || {
    printf '%s: plan not found: docs/plans/%s.md (or archive)\n' "$SCRIPT_NAME" "$slug" >&2
    return 2
  }

  printf '[close-plan] plan: %s\n' "$plan_file" >&2

  # Check Status field. Refuse to close non-ACTIVE plans.
  local current_status
  current_status=$(grep -E '^Status:[[:space:]]*' "$plan_file" | head -1 | sed -e 's/^Status:[[:space:]]*//' | xargs)
  if [[ "$current_status" != "ACTIVE" ]]; then
    printf '%s: plan Status is %s (not ACTIVE) — refusing to close\n' "$SCRIPT_NAME" "$current_status" >&2
    return 2
  fi

  # 1. Per-task verification routing.
  printf '[close-plan] verifying tasks...\n' >&2
  local task_ids failed_tasks=()
  task_ids=$(extract_task_ids "$plan_file")

  if [[ -z "$task_ids" ]]; then
    printf '%s: no tasks found in plan\n' "$SCRIPT_NAME" >&2
    return 2
  fi

  local tid level
  while IFS= read -r tid; do
    [[ -z "$tid" ]] && continue
    level=$(extract_verification_level "$plan_file" "$tid")
    case "$level" in
      mechanical)
        if verify_task_mechanical "$plan_file" "$tid"; then
          printf '[close-plan]   task %s (mechanical): PASS\n' "$tid" >&2
        else
          printf '[close-plan]   task %s (mechanical): FAIL\n' "$tid" >&2
          failed_tasks+=("$tid:mechanical")
        fi
        ;;
      contract)
        if verify_task_contract "$plan_file" "$tid"; then
          printf '[close-plan]   task %s (contract): PASS\n' "$tid" >&2
        else
          printf '[close-plan]   task %s (contract): FAIL\n' "$tid" >&2
          failed_tasks+=("$tid:contract")
        fi
        ;;
      full|*)
        if verify_task_full "$plan_file" "$tid"; then
          printf '[close-plan]   task %s (full): PASS\n' "$tid" >&2
        else
          printf '[close-plan]   task %s (full): FAIL\n' "$tid" >&2
          failed_tasks+=("$tid:full")
        fi
        ;;
    esac
  done <<< "$task_ids"

  # 2. Verify backlog reconciliation.
  if ! verify_backlog_reconciled "$plan_file"; then
    failed_tasks+=("backlog-reconciliation")
  fi

  # Block if any failure. Remediation paths:
  #   1. Generate missing structured evidence (happy path; uses write-evidence.sh capture).
  #   2. CLOSE_PLAN_EMERGENCY_OVERRIDE env var with ≥40-char rationale (substantive emergency only).
  # The legacy --force flag is REMOVED — it became the orchestrator's reflexive bypass during
  # the 2026-05-05 architecture-simplification arc (see docs/reviews/2026-05-06-force-usage-honest-accounting.md).
  if [[ ${#failed_tasks[@]} -gt 0 ]]; then
    printf '\n[close-plan] BLOCKED — %d failure(s):\n' "${#failed_tasks[@]}" >&2
    local f
    for f in "${failed_tasks[@]}"; do
      printf '  - %s\n' "$f" >&2
    done

    # Substantive emergency override path.
    if [[ -n "${CLOSE_PLAN_EMERGENCY_OVERRIDE:-}" ]]; then
      local reason="$CLOSE_PLAN_EMERGENCY_OVERRIDE"
      local reason_len=$(printf '%s' "$reason" | tr -d '[:space:]' | wc -c)
      if [[ "$reason_len" -lt 40 ]]; then
        printf '\n[close-plan] CLOSE_PLAN_EMERGENCY_OVERRIDE rejected: rationale must be >=40 non-whitespace chars (got %d)\n' "$reason_len" >&2
        return 2
      fi
      local repo_root
      repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="."
      mkdir -p "$repo_root/.claude/state"
      local audit="$repo_root/.claude/state/close-plan-emergency-overrides.log"
      {
        printf '\n--- %s ---\n' "$(iso_timestamp)"
        printf 'Plan: %s\n' "$plan_file"
        printf 'User: %s\n' "${USER:-unknown}"
        printf 'Rationale: %s\n' "$reason"
        printf 'Failures bypassed:\n'
        for f in "${failed_tasks[@]}"; do
          printf '  - %s\n' "$f"
        done
      } >> "$audit"
      printf '\n[close-plan] EMERGENCY OVERRIDE applied (audit log: %s)\n' "$audit" >&2
      printf '[close-plan] reason: %s\n' "$reason" >&2
      printf '[close-plan] surfaced as warning in next session SCRATCHPAD.\n' >&2
    else
      # Happy path: offer generate-evidence-and-retry.
      printf '\n[close-plan] To remediate (happy path):\n' >&2
      printf '  Generate missing structured evidence per task and re-run close-plan.\n' >&2
      printf '\n  For each failing mechanical/contract task, run:\n' >&2
      printf '    bash ~/.claude/scripts/write-evidence.sh capture --task <id> --plan %s --check files-in-commit\n' "$slug" >&2
      printf '\n  For full-tier tasks, ensure prose evidence-block has Verdict: PASS in evidence file.\n' >&2
      printf '\n[close-plan] To override (substantive emergency only):\n' >&2
      printf '  CLOSE_PLAN_EMERGENCY_OVERRIDE="<rationale, >=40 non-ws chars>" close-plan.sh close %s\n' "$slug" >&2
      printf '  (overrides logged to .claude/state/close-plan-emergency-overrides.log\n' >&2
      printf '   and surfaced as warning in next session SCRATCHPAD)\n' >&2
      return 2
    fi
  fi

  # 3. Generate completion report.
  printf '[close-plan] generating completion report...\n' >&2
  local report
  report=$(generate_completion_report "$plan_file")
  write_completion_report "$plan_file" "$report"

  # 4. Update SCRATCHPAD.
  printf '[close-plan] updating SCRATCHPAD...\n' >&2
  update_scratchpad "$slug"

  # 5. Flip Status: ACTIVE → COMPLETED. This triggers plan-lifecycle.sh
  # archival (PostToolUse) when a real harness session runs the procedure;
  # in --self-test the archival is performed inline by the test scaffold.
  printf '[close-plan] flipping Status: ACTIVE → COMPLETED...\n' >&2
  local tmp_plan
  tmp_plan=$(mktemp)
  sed -e 's/^Status:[[:space:]]*ACTIVE[[:space:]]*$/Status: COMPLETED/' "$plan_file" > "$tmp_plan"
  cp "$tmp_plan" "$plan_file"
  rm -f "$tmp_plan"

  # 6. Manual archival fallback. plan-lifecycle.sh is a PostToolUse hook
  # which fires on Edit/Write tool invocations within a Claude Code session.
  # When close-plan.sh runs from within such a session, the lifecycle hook
  # fires automatically and moves the plan to docs/plans/archive/. When the
  # script runs standalone (e.g., from --self-test or direct shell invocation
  # outside a Claude Code session), there is no PostToolUse trigger; we must
  # archive ourselves to maintain the post-condition.
  #
  # Detection: if the plan is still under docs/plans/ (top-level, not archive)
  # after the Status flip, perform the move ourselves. This is idempotent —
  # if the lifecycle hook already moved it, the check is a no-op.
  if [[ "$plan_file" == docs/plans/*.md ]] && [[ "$plan_file" != docs/plans/archive/*.md ]]; then
    if [[ -f "$plan_file" ]]; then
      mkdir -p docs/plans/archive
      local archived_path="docs/plans/archive/$(basename "$plan_file")"
      # Use git mv if file is tracked; else regular mv.
      if git ls-files --error-unmatch "$plan_file" >/dev/null 2>&1; then
        git mv "$plan_file" "$archived_path" 2>/dev/null || mv "$plan_file" "$archived_path"
      else
        mv "$plan_file" "$archived_path"
      fi
      # Also move sibling evidence file if present.
      local evidence_file="${plan_file%.md}-evidence.md"
      if [[ -f "$evidence_file" ]]; then
        local archived_evidence="docs/plans/archive/$(basename "$evidence_file")"
        if git ls-files --error-unmatch "$evidence_file" >/dev/null 2>&1; then
          git mv "$evidence_file" "$archived_evidence" 2>/dev/null || mv "$evidence_file" "$archived_evidence"
        else
          mv "$evidence_file" "$archived_evidence"
        fi
      fi
      printf '[close-plan] archived to: %s\n' "$archived_path" >&2
      plan_file="$archived_path"
    fi
  fi

  printf '[close-plan] DONE: plan %s closed.\n' "$slug" >&2

  # Auto-push (per E.2) unless --no-push.
  # Inside --self-test we skip auto-push entirely (CP_SELFTEST=1 sentinel).
  if [[ "$no_push" != true ]] && [[ "${CP_SELFTEST:-0}" != "1" ]]; then
    if git rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
      local branch
      branch=$(git rev-parse --abbrev-ref HEAD)
      printf '[close-plan] auto-pushing branch %s to origin (per E.2)...\n' "$branch" >&2
      if ! git push origin "$branch" 2>/dev/null; then
        printf '[close-plan] WARN: auto-push failed; you can push manually.\n' >&2
      fi
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

# Setup a synthetic plan repo for a single self-test scenario.
# Returns: temp-dir path on stdout. Caller responsible for cleanup.
# Args: <scenario-name> <plan-slug> <plan-body-extras>
setup_synthetic_repo() {
  local scenario="$1"
  local slug="$2"
  local TMPDIR_R
  TMPDIR_R=$(mktemp -d 2>/dev/null || mktemp -d -t cpst)
  if [[ -z "$TMPDIR_R" ]] || [[ ! -d "$TMPDIR_R" ]]; then
    return 1
  fi
  (
    cd "$TMPDIR_R" || exit 1
    git init -q
    git config user.email "test@example.test"
    git config user.name "Test"
    mkdir -p docs/plans docs/plans/archive
    : > docs/backlog.md
    cat > docs/backlog.md <<EOF
# Backlog
Last updated: 2026-05-05

## Open work
EOF
  )
  printf '%s\n' "$TMPDIR_R"
}

run_self_test() {
  local SELF_PATH
  if [[ "$0" == /* ]]; then
    SELF_PATH="$0"
  else
    SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  fi
  export CP_SELFTEST=1

  local PASSED=0 FAILED=0
  local saved_pwd="$PWD"

  printf 'close-plan.sh self-test (10 scenarios)\n\n' >&2

  # ----- S1: all-mechanical-tasks-closure -----
  local D1; D1=$(setup_synthetic_repo "S1" "p-mech")
  (
    cd "$D1" || exit 1
    cat > docs/plans/p-mech.md <<'EOF'
# Plan: P Mech
Status: ACTIVE
Backlog items absorbed: none

## Goal
test mechanical closure

## Scope
- IN: nothing
- OUT: everything

## Tasks
- [x] 1. First task. Verification: mechanical
- [x] 2. Second task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-mech.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-mech-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-mech-evidence/1.evidence.json
    printf '{"task_id":"2","verdict":"PASS"}\n' > docs/plans/p-mech-evidence/2.evidence.json
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-mech --no-push >/dev/null 2>&1
  )
  if [[ -f "$D1/docs/plans/archive/p-mech.md" ]] \
     && grep -q '^Status: COMPLETED' "$D1/docs/plans/archive/p-mech.md"; then
    printf 'self-test (S1) all-mechanical-tasks-closure: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S1) all-mechanical-tasks-closure: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D1"

  # ----- S2: all-full-tasks-closure -----
  local D2; D2=$(setup_synthetic_repo "S2" "p-full")
  (
    cd "$D2" || exit 1
    cat > docs/plans/p-full.md <<'EOF'
# Plan: P Full
Status: ACTIVE
Backlog items absorbed: none

## Goal
test full closure

## Scope
- IN: nothing
- OUT: everything

## Tasks
- [x] 1. First task.
- [x] 2. Second task.

## Files to Modify/Create
- `docs/plans/p-full.md`

## Evidence Log

Task ID: 1
Verdict: PASS
commit abcdef1

Task ID: 2
Verdict: PASS
commit abcdef2
EOF
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-full --no-push >/dev/null 2>&1
  )
  if [[ -f "$D2/docs/plans/archive/p-full.md" ]] \
     && grep -q '^Status: COMPLETED' "$D2/docs/plans/archive/p-full.md"; then
    printf 'self-test (S2) all-full-tasks-closure: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S2) all-full-tasks-closure: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D2"

  # ----- S3: mixed-tier-closure -----
  local D3; D3=$(setup_synthetic_repo "S3" "p-mix")
  (
    cd "$D3" || exit 1
    cat > docs/plans/p-mix.md <<'EOF'
# Plan: P Mix
Status: ACTIVE
Backlog items absorbed: none

## Goal
test mixed closure

## Scope
- IN: nothing
- OUT: everything

## Tasks
- [x] 1. First task. Verification: mechanical
- [x] 2. Second task. Verification: full

## Files to Modify/Create
- `docs/plans/p-mix.md`

## Evidence Log

Task ID: 2
Verdict: PASS
commit cafe1234
EOF
    mkdir -p docs/plans/p-mix-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-mix-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-mix --no-push >/dev/null 2>&1
  )
  if [[ -f "$D3/docs/plans/archive/p-mix.md" ]] \
     && grep -q '^Status: COMPLETED' "$D3/docs/plans/archive/p-mix.md"; then
    printf 'self-test (S3) mixed-tier-closure: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S3) mixed-tier-closure: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D3"

  # ----- S4: missing-completion-report (procedure generates it) -----
  local D4; D4=$(setup_synthetic_repo "S4" "p-norep")
  (
    cd "$D4" || exit 1
    cat > docs/plans/p-norep.md <<'EOF'
# Plan: P Norep
Status: ACTIVE
Backlog items absorbed: none

## Goal
test report generation

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-norep.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-norep-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-norep-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-norep --no-push >/dev/null 2>&1
  )
  if [[ -f "$D4/docs/plans/archive/p-norep.md" ]] \
     && grep -q '## Completion Report' "$D4/docs/plans/archive/p-norep.md" \
     && grep -q 'Implementation Summary' "$D4/docs/plans/archive/p-norep.md"; then
    printf 'self-test (S4) missing-completion-report: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S4) missing-completion-report: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D4"

  # ----- S5: stale-SCRATCHPAD (procedure updates) -----
  local D5; D5=$(setup_synthetic_repo "S5" "p-pad")
  (
    cd "$D5" || exit 1
    cat > docs/plans/p-pad.md <<'EOF'
# Plan: P Pad
Status: ACTIVE
Backlog items absorbed: none

## Goal
test scratchpad update

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-pad.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-pad-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-pad-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-pad --no-push >/dev/null 2>&1
  )
  if [[ -f "$D5/SCRATCHPAD.md" ]] \
     && grep -q 'p-pad' "$D5/SCRATCHPAD.md"; then
    printf 'self-test (S5) stale-SCRATCHPAD: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S5) stale-SCRATCHPAD: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D5"

  # ----- S6: unreconciled-backlog (BLOCK) -----
  local D6; D6=$(setup_synthetic_repo "S6" "p-blg")
  (
    cd "$D6" || exit 1
    cat > docs/backlog.md <<'EOF'
# Backlog
Last updated: 2026-05-05

## Open work
- frob-the-widget — needs doing
EOF
    cat > docs/plans/p-blg.md <<'EOF'
# Plan: P Blg
Status: ACTIVE
Backlog items absorbed: frob-the-widget

## Goal
test backlog reconciliation

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-blg.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-blg-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-blg-evidence/1.evidence.json
    git add . && git commit -q -m "init"
  )
  local s6_out s6_rc
  s6_out=$(cd "$D6" && bash "$SELF_PATH" close p-blg --no-push 2>&1)
  s6_rc=$?
  if [[ $s6_rc -ne 0 ]] \
     && printf '%s' "$s6_out" | grep -q 'frob-the-widget'; then
    printf 'self-test (S6) unreconciled-backlog: PASS (blocked, named item)\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S6) unreconciled-backlog: FAIL (rc=%s)\n' "$s6_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D6"

  # ----- S7: --force bypass -----
  local D7; D7=$(setup_synthetic_repo "S7" "p-force")
  (
    cd "$D7" || exit 1
    cat > docs/plans/p-force.md <<'EOF'
# Plan: P Force
Status: ACTIVE
Backlog items absorbed: none

## Goal
test force bypass

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-force.md`

## Evidence Log
EOF
    # Note: no evidence file — mechanical check WILL FAIL
    git add . && git commit -q -m "init"
  )

  # S7a: --force flag is REJECTED (rejected message + exit 2)
  local s7a_out s7a_rc
  s7a_out=$(cd "$D7" && bash "$SELF_PATH" close p-force --no-push --force 2>&1)
  s7a_rc=$?
  if [[ $s7a_rc -eq 2 ]] && printf '%s' "$s7a_out" | grep -qF "REMOVED"; then
    printf 'self-test (S7a) --force-flag-rejected: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7a) --force-flag-rejected: FAIL (rc=%s)\n' "$s7a_rc" >&2
    FAILED=$((FAILED+1))
  fi

  # S7b: blocked closure prints remediation guide (NOT --force suggestion)
  local s7b_out s7b_rc
  s7b_out=$(cd "$D7" && bash "$SELF_PATH" close p-force --no-push 2>&1)
  s7b_rc=$?
  if [[ $s7b_rc -eq 2 ]] \
     && printf '%s' "$s7b_out" | grep -q 'write-evidence.sh capture' \
     && printf '%s' "$s7b_out" | grep -q 'CLOSE_PLAN_EMERGENCY_OVERRIDE' \
     && ! printf '%s' "$s7b_out" | grep -qE 'use --force'; then
    printf 'self-test (S7b) remediation-guide-printed: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7b) remediation-guide-printed: FAIL (rc=%s)\n' "$s7b_rc" >&2
    FAILED=$((FAILED+1))
  fi

  # S7c: short emergency rationale rejected (<40 non-ws chars)
  local s7c_out s7c_rc
  s7c_out=$(cd "$D7" && CLOSE_PLAN_EMERGENCY_OVERRIDE="too short" bash "$SELF_PATH" close p-force --no-push 2>&1)
  s7c_rc=$?
  if [[ $s7c_rc -eq 2 ]] && printf '%s' "$s7c_out" | grep -q 'rationale must be'; then
    printf 'self-test (S7c) short-rationale-rejected: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7c) short-rationale-rejected: FAIL (rc=%s)\n' "$s7c_rc" >&2
    FAILED=$((FAILED+1))
  fi

  # S7d: substantive emergency rationale ACCEPTED + audit-logged
  rm -rf "$D7/docs/plans/archive" 2>/dev/null
  (cd "$D7" && CLOSE_PLAN_EMERGENCY_OVERRIDE="legitimate emergency: production deploy is blocking on this; mechanical evidence backfill deferred per sec-incident response" bash "$SELF_PATH" close p-force --no-push >/dev/null 2>&1)
  if [[ -f "$D7/docs/plans/archive/p-force.md" ]] \
     && [[ -f "$D7/.claude/state/close-plan-emergency-overrides.log" ]]; then
    printf 'self-test (S7d) emergency-override-logged: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7d) emergency-override-logged: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D7"

  # ----- S8: mechanical-task-missing-evidence (BLOCK) -----
  local D8; D8=$(setup_synthetic_repo "S8" "p-noev")
  (
    cd "$D8" || exit 1
    cat > docs/plans/p-noev.md <<'EOF'
# Plan: P Noev
Status: ACTIVE
Backlog items absorbed: none

## Goal
test missing evidence

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-noev.md`

## Evidence Log
EOF
    git add . && git commit -q -m "init"
  )
  local s8_out s8_rc
  s8_out=$(cd "$D8" && bash "$SELF_PATH" close p-noev --no-push 2>&1)
  s8_rc=$?
  if [[ $s8_rc -ne 0 ]] \
     && printf '%s' "$s8_out" | grep -qE '1:mechanical|task 1.*FAIL'; then
    printf 'self-test (S8) mechanical-task-missing-evidence: PASS (blocked)\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S8) mechanical-task-missing-evidence: FAIL (rc=%s)\n' "$s8_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D8"

  # ----- S9: contract-task-schema-fail (BLOCK) -----
  local D9; D9=$(setup_synthetic_repo "S9" "p-cont")
  (
    cd "$D9" || exit 1
    cat > docs/plans/p-cont.md <<'EOF'
# Plan: P Cont
Status: ACTIVE
Backlog items absorbed: none

## Goal
test contract schema fail

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: contract Contract: schemas/missing-schema.json

## Files to Modify/Create
- `docs/plans/p-cont.md`

## Evidence Log
EOF
    git add . && git commit -q -m "init"
  )
  local s9_out s9_rc
  s9_out=$(cd "$D9" && bash "$SELF_PATH" close p-cont --no-push 2>&1)
  s9_rc=$?
  if [[ $s9_rc -ne 0 ]]; then
    printf 'self-test (S9) contract-task-schema-fail: PASS (blocked)\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S9) contract-task-schema-fail: FAIL (rc=%s)\n' "$s9_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D9"

  # ----- S10: all-PASS-archives (verifies archival fires correctly) -----
  local D10; D10=$(setup_synthetic_repo "S10" "p-arch")
  (
    cd "$D10" || exit 1
    cat > docs/plans/p-arch.md <<'EOF'
# Plan: P Arch
Status: ACTIVE
Backlog items absorbed: none

## Goal
test archival

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-arch.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-arch-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-arch-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-arch --no-push >/dev/null 2>&1
  )
  if [[ ! -f "$D10/docs/plans/p-arch.md" ]] \
     && [[ -f "$D10/docs/plans/archive/p-arch.md" ]]; then
    printf 'self-test (S10) all-PASS-archives: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S10) all-PASS-archives: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D10"

  cd "$saved_pwd"

  printf '\nself-test summary: %d passed, %d failed (of 10 scenarios)\n' "$PASSED" "$FAILED" >&2
  if [[ $FAILED -eq 0 ]]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit $?
fi

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "close" ]]; then
  shift
  cmd_close "$@"
  exit $?
fi

usage >&2
exit 2
