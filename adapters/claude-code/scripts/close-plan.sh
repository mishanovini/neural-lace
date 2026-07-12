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
# reconciles backlog, flips Status via a bash write (plan-lifecycle.sh CANNOT
# fire on it — bash writes are not Edit/Write tool events), archives via its
# own inline fallback, COMMITS the closure (pathspec-limited to the plan +
# evidence paths), and auto-pushes per user's full-auto preference (per E.2).
#
# Subcommands:
#   close <plan-slug> [--no-push] [--auto]     Close the plan
#   --self-test                               Run internal test scenarios
#   --help                                    Show usage
#
# Flags:
#   --no-push   Commit only; do NOT auto-push to origin.
#   --auto      Auto-closure invocation path (R4 / ADR 036-c). Adds the
#               Closure-Contract / acceptance-artifact precondition that the
#               manual close does not require (non-exempt plans must have a
#               PASS artifact under .claude/state/acceptance/<slug>/ whose
#               plan_commit_sha matches the COMMITTED plan SHA). ALWAYS
#               implies --no-push. Used by plan-auto-closure.sh; exit 2 = HOLD
#               (precondition unmet, plan left ACTIVE).
#
# When verification fails, close-plan.sh prints the only remediation path:
# generate the missing structured evidence via write-evidence.sh capture and
# re-run. No script-level override exists. Both the legacy --force flag (removed
# 2026-05-05) and a brief CLOSE_PLAN_EMERGENCY_OVERRIDE env var experiment
# (removed 2026-05-06) became reflexive agent bypasses; "loud" is not "rare"
# for an LLM. Genuine emergencies use manual git ops (visible, several steps).
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
Usage: close-plan.sh close <plan-slug> [--no-push] [--auto]
       close-plan.sh --self-test
       close-plan.sh --help

Deterministic close-plan procedure. Routes each task per its declared
`Verification:` level (mechanical | contract | full), generates the
completion report, updates SCRATCHPAD, verifies backlog reconciliation,
flips Status to COMPLETED, archives inline (bash writes fire no PostToolUse
event, so plan-lifecycle.sh cannot do it), commits the closure (pathspec-
limited to the plan + evidence paths), and auto-pushes (unless --no-push).

--auto (R4 / ADR 036-c): the auto-closure invocation path. Adds the
Closure-Contract / acceptance-artifact precondition the manual close does
not require, and ALWAYS implies --no-push. Exit 2 = HOLD (precondition
unmet, plan left ACTIVE). Used by plan-auto-closure.sh.

Examples:
  close-plan.sh close my-plan-slug
  close-plan.sh close my-plan --no-push
  close-plan.sh close my-plan --auto       # implies --no-push + contract gate

When verification blocks, the only remediation is to generate the missing
structured evidence via write-evidence.sh capture, then re-run. There is no
script-level override (--force removed 2026-05-05; CLOSE_PLAN_EMERGENCY_OVERRIDE
removed 2026-05-06 — both became reflexive agent bypasses). Genuine emergencies
use manual git ops (edit Status, git mv to archive, git rm stale state, commit).
EOF
}

iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S"
}

# ---------------------------------------------------------------------------
# Progress-log emission: plan_completed (ask-rooted-workstreams-p1 Task 6b --
# the SIXTH emission lane / the ask lifecycle's mechanical exit).
# ---------------------------------------------------------------------------
#
# extract_ask_id_cp <plan_file> -- print the plan header's `ask-id: <token>`
# value, or empty if absent (pre-existing plans lack this field; Task 10
# adds it going forward -- an absent ask-id still gets an event via
# progress-log-lib.sh's "unlinked" orphan lane, never silently dropped;
# mirrors plan-lifecycle.sh's extract_ask_id).
extract_ask_id_cp() {
  local plan_file="$1"
  grep -E '^ask-id:[[:space:]]*[^[:space:]]+' "$plan_file" 2>/dev/null \
    | head -1 \
    | sed -E 's/^ask-id:[[:space:]]*//' \
    | awk '{print $1}'
}

# cp_compute_content_hash <string> -- portable best-effort content hash for
# --dedup-extra values (mirrors progress-log-lib.sh's private _pl_hash and
# plan-lifecycle.sh's compute_content_hash; duplicated here rather than
# sourced because this script shells out to progress-log.sh as its own CLI
# process for the emission -- the same one-process-per-emission convention
# every other splice in this plan follows).
cp_compute_content_hash() {
  local s="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$s" | sha1sum 2>/dev/null | awk '{print $1}' && return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$s" | openssl dgst -sha1 2>/dev/null | awk '{print $NF}' && return 0
  fi
  printf '%s' "$s" | cksum 2>/dev/null | awk '{print $1"-"$2}'
}

# emit_plan_completed_progress_log_event <plan_file> <slug> <close_ts>
#   Emits ONE plan_completed event from the SUCCESSFUL-CLOSE path (Task 6b).
# This fires on BOTH closure lanes -- the wired plan-auto-closure.sh
# PostToolUse hook's `close-plan.sh close <slug> --auto` invocation AND a
# manual `close-plan.sh close <slug>` run -- because both go through this
# SAME function at the SAME call site (see cmd_close below), never on a
# blocked/HOLD/usage-error return. Natural key (progress-log-lib.sh's
# _pl_natural_key): plan_slug + content-hash of the Status-line ts
# (--dedup-extra) -- <close_ts> is the timestamp of THIS Status:
# ACTIVE -> COMPLETED flip, so a re-close after a reopen (a fresh ACTIVE ->
# COMPLETED transition, necessarily at a later ts) hashes to a NEW key and
# is logged as a legitimately-distinct event, while re-running this same
# function twice for the identical close (e.g. an auditor backfill racing
# the live splice) hashes to the SAME key and dedupes (Task 2 table).
# Best-effort, never blocks the caller (constraint 5): every failure path is
# swallowed and this NEVER affects close-plan.sh's own exit code.
emit_plan_completed_progress_log_event() {
  local plan_file="$1" slug="$2" close_ts="$3"

  local progress_log_cli
  progress_log_cli="$SCRIPT_DIR/progress-log.sh"
  [[ -f "$progress_log_cli" ]] || return 0

  local ask_id
  ask_id="$(extract_ask_id_cp "$plan_file" 2>/dev/null || true)"

  local hash
  hash="$(cp_compute_content_hash "$close_ts")"

  local repo_root_abs evidence_link
  repo_root_abs=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  if [[ "$plan_file" = /* ]]; then
    evidence_link="$plan_file"
  else
    evidence_link="$repo_root_abs/$plan_file"
  fi

  bash "$progress_log_cli" emit \
    --type plan_completed \
    --ask "$ask_id" \
    --plan-slug "$slug" \
    --summary "plan $slug completed" \
    --evidence-link "$evidence_link" \
    --emitter close-plan \
    --dedup-extra "$hash" \
    >/dev/null 2>&1 || true

  return 0
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
  # LAST occurrence wins (discovery 2026-05-11-close-plan-verification-field-
  # parser-greedy): a task description may legitimately mention a level in
  # prose (e.g. "add functionality-verifier requirement for `Verification:
  # full` runtime tasks — Verification: mechanical"); the trailing field is
  # the declaration. First-occurrence parsing misclassified such tasks.
  level=$(printf '%s\n' "$block" | grep -iEo 'Verification:[[:space:]]*(mechanical|contract|full)' | tail -1 | sed -e 's/Verification:[[:space:]]*//I' | tr '[:upper:]' '[:lower:]')

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
# Auto-mode Closure-Contract precondition (R4 / ADR 036-c).
# ---------------------------------------------------------------------------
# In --auto mode (and only then) close-plan adds a SECOND gate beyond the
# per-task verification: it independently confirms the predefined Closure
# Contract artifact exists with verdict PASS and a matching plan SHA. The
# manual close trusts the operator; the unattended auto close must not.
#
# For an `acceptance-exempt: true` plan the contract IS the self-test /
# structured-evidence PASS set, which the per-task mechanical verification
# already enforces upstream — so this precondition is a no-op for exempt
# plans (returns 0). For a non-exempt plan it requires a PASS acceptance
# artifact under .claude/state/acceptance/<slug>/ matching the plan's
# COMMITTED SHA.
#
# MATCH BASIS (plan §7 pin): the artifact's `plan_commit_sha` is compared
# against `git log -n 1 --pretty=format:%H -- <plan-file>` — the plan file's
# LAST-COMMIT SHA, NOT the working tree. At auto-closure fire time the
# triggering checkbox-flip Edit is uncommitted, so the working tree differs
# from the committed plan; the PASS artifact was written against the
# committed version, and the final [ ]→[x] flip changes only task state, not
# the acceptance scenarios the artifact verified. (T11b.)
#
# Echoes one of: SATISFIED | EXEMPT | NO_ARTIFACT | STALE | FAIL
#   SATISFIED  — non-exempt; matching-SHA artifact with all verdicts PASS
#   EXEMPT     — acceptance-exempt: true; contract is self-tests (handled upstream)
#   NO_ARTIFACT— non-exempt; no artifact directory / no JSON artifacts
#   STALE      — artifacts exist but none match the committed SHA
#   FAIL       — matching-SHA artifact exists but a verdict is non-PASS
check_closure_contract_artifact() {
  local plan_file="$1"
  local slug
  slug=$(basename "$plan_file" .md)

  # Acceptance-exempt → contract satisfied by self-tests (already verified
  # per-task). The precondition does not add a second artifact gate here.
  if grep -qiE '^acceptance-exempt:[[:space:]]*true' "$plan_file" 2>/dev/null; then
    echo "EXEMPT"
    return
  fi

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="."
  local art_dir="$repo_root/.claude/state/acceptance/$slug"
  if [[ ! -d "$art_dir" ]]; then
    echo "NO_ARTIFACT"
    return
  fi

  local artifacts
  artifacts=$(find "$art_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null)
  if [[ -z "$artifacts" ]]; then
    echo "NO_ARTIFACT"
    return
  fi

  # Committed SHA of the plan file (NOT the working tree).
  local current_sha=""
  if command -v git >/dev/null 2>&1 && git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    current_sha=$(git -C "$repo_root" log -n 1 --pretty=format:'%H' -- "$plan_file" 2>/dev/null || echo "")
  fi
  [[ -z "$current_sha" ]] && current_sha="UNCOMMITTED"

  local found_matching_sha=0 found_all_pass=0 artifact
  while IFS= read -r artifact; do
    [[ -z "$artifact" ]] && continue
    [[ -f "$artifact" ]] || continue
    local artifact_sha
    artifact_sha=$(grep -oE '"plan_commit_sha"[[:space:]]*:[[:space:]]*"[^"]+"' "$artifact" 2>/dev/null | head -1 | sed -E 's/.*"plan_commit_sha"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    if [[ "$artifact_sha" == "$current_sha" ]]; then
      found_matching_sha=1
      local verdict_lines
      verdict_lines=$(grep -oE '"verdict"[[:space:]]*:[[:space:]]*"[^"]+"' "$artifact" 2>/dev/null)
      [[ -z "$verdict_lines" ]] && continue
      local has_non_pass
      has_non_pass=$(echo "$verdict_lines" | grep -vE '"verdict"[[:space:]]*:[[:space:]]*"PASS"' | head -1)
      if [[ -z "$has_non_pass" ]]; then
        found_all_pass=1
        break
      fi
    fi
  done <<< "$artifacts"

  if [[ "$found_all_pass" -eq 1 ]]; then
    echo "SATISFIED"
  elif [[ "$found_matching_sha" -eq 1 ]]; then
    echo "FAIL"
  else
    echo "STALE"
  fi
}

# ---------------------------------------------------------------------------
# Completion-criteria check (D.4 relocation from completion-criteria-gate.sh,
# a retired Stop hook). WHY relocated here, not just deleted: "intended but
# not finished" is a binary failure, not gradual drift — the eight completion
# criteria (code / tests / dev_docs / user_docs / migration / deploy /
# acceptance / stakeholder) were previously enforced by scanning a SESSION'S
# FINAL MESSAGE for a declared-shipped trigger phrase, which a differently-
# worded wrap-up could dodge entirely. Checking at CLOSE time instead is
# strictly stronger: close-plan.sh is the one mechanical choke point every
# plan MUST pass through to reach Status: COMPLETED, so there is no phrasing
# that routes around it. This also closes GAP-53 (a preview-deploy false-pass
# fell through the original gate's evidence regex, which accepted "deploy
# green" without distinguishing preview from production) — see the `deploy`
# criterion's stricter PROD_EVIDENCE_RE below.
#
# Design note: acceptance-exempt plans (harness-dev, no product user) are not
# exempted from ALL 8 criteria wholesale — they are exempted from the ones
# that assume a shipped product surface (user_docs, deploy, stakeholder) via
# the plan's own N/A-with-justification convention, same as the original
# gate's per-criterion N/A path. This function does not special-case
# acceptance-exempt; a plan that is genuinely dev-only marks those criteria
# N/A in its own Completion Criteria section, same mechanism non-exempt
# plans use for a legitimately-inapplicable criterion.

COMPLETION_CRIT_KEYS=(code tests dev_docs user_docs migration deploy acceptance stakeholder)

_completion_crit_display() {
  case "$1" in
    code)        echo "Code merged to master" ;;
    tests)       echo "Tests added" ;;
    dev_docs)    echo "Dev docs updated (ADR/architecture/runbook)" ;;
    user_docs)   echo "User docs updated (docs/support/*.mdx)" ;;
    migration)   echo "Migration applied to production" ;;
    deploy)      echo "Vercel MASTER/PRODUCTION deploy succeeded" ;;
    acceptance)  echo "Acceptance criteria verified" ;;
    stakeholder) echo "Stakeholder / team notified" ;;
    *)           echo "$1" ;;
  esac
}

_completion_crit_keyword_re() {
  case "$1" in
    code)        echo 'code merged|merged to master|code merge|code:[[:space:]]' ;;
    tests)       echo 'test' ;;
    dev_docs)    echo 'dev doc|dev-doc|developer doc|adr|architecture|runbook' ;;
    user_docs)   echo 'user doc|user-doc|support doc|support page|\.mdx|docs/support' ;;
    migration)   echo 'migration|schema' ;;
    deploy)      echo 'deploy|vercel' ;;
    acceptance)  echo 'acceptance' ;;
    stakeholder) echo 'stakeholder|notif|notified|support team|team alert' ;;
    *)           echo "$1" ;;
  esac
}

# General evidence token (SHA / #PR / @handle / URL / file-with-ext / route / artifact keyword).
COMPLETION_EVIDENCE_RE='[0-9a-f]{7,40}|#[A-Za-z0-9][A-Za-z0-9_-]*|@[A-Za-z][A-Za-z0-9_-]*|https?://|[A-Za-z0-9_./-]+\.(mdx|md|tsx?|jsx?|sql|sh|ya?ml|json|png|jpe?g|csv)|/[a-z][A-Za-z0-9_/-]+|screenshot|smoke[- ]?test|playwright|curl |migration [0-9]+|deploy[a-z]* (green|success|succeeded|verified)'

# GAP-53 fix: the `deploy` criterion additionally requires PRODUCTION/MASTER
# evidence, not just "green" — a preview-deploy line like "Vercel preview
# deploy green for PR #412" satisfies the general evidence regex above but
# must NOT satisfy the deploy criterion specifically. Require one of
# master/production/prod alongside the deploy/green language.
COMPLETION_PROD_DEPLOY_RE='(master|production|\bprod\b).*(deploy|vercel)|(deploy|vercel).*(master|production|\bprod\b)'

# Check-mark ERE (ASCII [x] plus common unicode ticks).
COMPLETION_CHECK_RE='\[[xX]\]|✓|✅|✔|☑'

# classify_completion_criterion <key> <section-text>
# Echoes: SATISFIED | NA | NOEVIDENCE | NOVERDICT | MISSING
classify_completion_criterion() {
  local key="$1" section="$2"
  local kw; kw="$(_completion_crit_keyword_re "$key")"
  local lines
  lines="$(printf '%s\n' "$section" | grep -iE "$kw" 2>/dev/null || true)"
  if [[ -z "$lines" ]]; then
    echo "MISSING"; return 0
  fi
  local saw_na=0 saw_check_noevidence=0 line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if printf '%s' "$line" | grep -iqE 'n/?a\b|not applicable' 2>/dev/null; then
      if printf '%s' "$line" | grep -iqE '(n/?a\b|not applicable).*[-—:].*[A-Za-z]{4}' 2>/dev/null; then
        echo "NA"; return 0
      else
        saw_na=1
      fi
      continue
    fi
    if printf '%s' "$line" | grep -qE "$COMPLETION_CHECK_RE" 2>/dev/null; then
      if [[ "$key" == "deploy" ]]; then
        # deploy criterion: require BOTH the general evidence token AND the
        # production/master qualifier (GAP-53).
        if printf '%s' "$line" | grep -qiE "$COMPLETION_EVIDENCE_RE" 2>/dev/null \
           && printf '%s' "$line" | grep -qiE "$COMPLETION_PROD_DEPLOY_RE" 2>/dev/null; then
          echo "SATISFIED"; return 0
        else
          saw_check_noevidence=1
        fi
      else
        if printf '%s' "$line" | grep -qiE "$COMPLETION_EVIDENCE_RE" 2>/dev/null; then
          echo "SATISFIED"; return 0
        else
          saw_check_noevidence=1
        fi
      fi
    fi
  done <<< "$lines"
  if [[ "$saw_check_noevidence" -eq 1 ]]; then echo "NOEVIDENCE"; return 0; fi
  if [[ "$saw_na" -eq 1 ]]; then echo "NOVERDICT"; return 0; fi
  echo "NOVERDICT"
}

# verify_completion_criteria <plan_file>
# Reads the plan file's own `## Completion Criteria` section (written by the
# session before invoking close-plan, or present from a prior close attempt).
# Returns 0 if all 8 criteria are SATISFIED or NA; prints unmet keys to
# stdout (space-separated "key:status" pairs) and returns 1 otherwise.
#
# Grandfathering (mirrors verify_closure_contract_recorded's convention,
# which itself mirrors plan-reviewer.sh Check 15's grandfather rule):
#   - acceptance-exempt: true plans (harness-dev, no shipped product surface)
#     are a no-op PASS unless the plan itself already declares a
#     `## Completion Criteria` section (an exempt plan CAN opt in; it is
#     never forced in — mirrors the original gate's "feature shipped"
#     trigger-phrase design, which would rarely fire on harness-dev wraps).
#   - Plans that do not declare `lifecycle-schema: v2` are grandfathered
#     (no-op PASS) — the same boundary plan-reviewer.sh's Closure Contract
#     check uses, so this does not retroactively block legacy plans
#     close-plan.sh already knows how to close.
# Non-exempt v2 plans with NO Completion Criteria section at all are
# MISSING-SECTION on every non-skipped criterion (hard block) — closure IS
# the shipment declaration for these plans; there is no separate "trigger
# phrase" to dodge.
#
# Escape hatch: CLOSE_PLAN_COMPLETION_SKIP=a,b,c — per-criterion skip,
# audit-logged to .claude/state/completion-gate-skips.log (same log the
# original Stop-hook gate used, so history is continuous across the
# relocation). No blanket disable env — close-plan.sh already has no
# script-level override philosophy (see the file header); a per-criterion,
# audit-logged skip is the sole valve, mirroring the pre-relocation gate.
verify_completion_criteria() {
  local plan_file="$1"

  # Grandfather: pre-v2 plans are not retroactively subject to this check.
  if ! grep -qE '^lifecycle-schema:[[:space:]]*v2' "$plan_file" 2>/dev/null; then
    return 0
  fi

  # acceptance-exempt plans: no-op unless they opted in with their own
  # Completion Criteria section (in which case honor whatever it declares).
  if grep -qiE '^acceptance-exempt:[[:space:]]*true' "$plan_file" 2>/dev/null \
     && ! grep -qiE '^[[:space:]]*#{2,3}[[:space:]]*completion criteria[[:space:]]*$' "$plan_file" 2>/dev/null; then
    return 0
  fi

  declare -A skip_set=()
  local raw_skip="${CLOSE_PLAN_COMPLETION_SKIP:-}"
  if [[ -n "$raw_skip" ]]; then
    local tok
    for tok in $(printf '%s' "$raw_skip" | tr ',' ' '); do
      [[ -z "$tok" ]] && continue
      skip_set["$tok"]=1
    done
  fi

  local section has_section=0
  if grep -qiE '^[[:space:]]*#{2,3}[[:space:]]*completion criteria[[:space:]]*$' "$plan_file" 2>/dev/null; then
    has_section=1
  fi
  section=$(awk '
    /^[[:space:]]*#{2,3}[[:space:]]*[Cc]ompletion [Cc]riteria[[:space:]]*$/ { inSec=1; next }
    inSec==1 && /^[[:space:]]*##[[:space:]]/ { inSec=0 }
    inSec==1 { print }
  ' "$plan_file" 2>/dev/null)

  local skiplog="${CLOSE_PLAN_COMPLETION_SKIPLOG:-.claude/state/completion-gate-skips.log}"
  local unmet="" key status
  for key in "${COMPLETION_CRIT_KEYS[@]}"; do
    if [[ -n "${skip_set[$key]:-}" ]]; then
      mkdir -p "$(dirname "$skiplog")" 2>/dev/null || true
      local ts; ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)
      printf '%s\tplan=%s\tcriterion=%s\tsource=close-plan.sh\n' "$ts" "$(basename "$plan_file" .md)" "$key" >> "$skiplog" 2>/dev/null || true
      continue
    fi
    if [[ "$has_section" -eq 0 ]]; then
      unmet="${unmet}${key}:MISSING-SECTION "
      continue
    fi
    status="$(classify_completion_criterion "$key" "$section")"
    case "$status" in
      SATISFIED|NA) ;;
      *) unmet="${unmet}${key}:${status} " ;;
    esac
  done
  unmet="${unmet% }"

  if [[ -z "$unmet" ]]; then
    return 0
  fi
  printf '%s\n' "$unmet"
  return 1
}

# ---------------------------------------------------------------------------
# PR-merge boundary check: Closure-Contract commands recorded (D.4 item 1's
# second half). Distinct from check_closure_contract_artifact() above (which
# verifies an ACTUAL PASS artifact exists for --auto mode): this instead
# verifies the plan's `## Closure Contract` section (declared at plan
# CREATION per Decision 036-b / plan-reviewer.sh Check 15) still has its four
# fields populated with real content at CLOSE time — not left as
# "[populate me ...]" template placeholders. Plan-reviewer only checks this
# at creation/edit time (PreToolUse); a plan could still be closed with a
# since-blanked or never-populated Closure Contract if nothing re-checked at
# the close boundary. This is that re-check.
#
# Grandfathered (returns 0, no-op) for plans that predate lifecycle-schema:
# v2 or declare no ## Closure Contract section at all — same grandfather
# rule plan-reviewer.sh Check 15 uses, so this does not retroactively block
# legacy plans close-plan.sh already knows how to close.
verify_closure_contract_recorded() {
  local plan_file="$1"

  if ! grep -qE '^lifecycle-schema:[[:space:]]*v2' "$plan_file" 2>/dev/null; then
    return 0
  fi
  if ! grep -qE '^## Closure Contract[[:space:]]*$' "$plan_file" 2>/dev/null; then
    return 0
  fi

  local cc_text
  cc_text=$(awk '
    /^## Closure Contract[[:space:]]*$/ { in_cc = 1; next }
    in_cc && /^## / { in_cc = 0 }
    in_cc { print }
  ' "$plan_file" 2>/dev/null)

  local non_ws
  non_ws=$(printf '%s' "$cc_text" | tr -d '[:space:]' | wc -c | tr -d '[:space:]')
  if [[ "${non_ws:-0}" -lt 20 ]]; then
    return 1
  fi

  local pat
  for pat in '\[populate me[^]]*\]' '\[populate me\]' '\[todo\]' '\btodo\b' 'tbd'; do
    if printf '%s' "$cc_text" | grep -qiE "$pat" 2>/dev/null; then
      return 1
    fi
  done

  # Must name at least a commands-that-run line and a done-when line with
  # actual content beyond the label itself (mirrors plan-reviewer's field
  # presence check).
  if ! printf '%s' "$cc_text" | grep -qiE 'commands that run.{5,}'; then
    return 1
  fi
  if ! printf '%s' "$cc_text" | grep -qiE 'done when.{5,}'; then
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
  local auto_mode=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-push) no_push=true; shift ;;
      --auto)
        # R4 (ADR 036-c): auto-closure invocation path. Adds the
        # Closure-Contract / acceptance-artifact precondition that the
        # manual close does not require, and ALWAYS implies --no-push (an
        # unattended PostToolUse-triggered close must never push to origin).
        auto_mode=true
        no_push=true
        shift ;;
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

  # 2c. Completion-criteria check (D.4 relocation from completion-criteria-
  # gate.sh — a plan cannot flip to COMPLETED with unmet completion criteria).
  # Only applies when the plan carries a `## Completion Criteria` section OR
  # the plan explicitly triggers it; a plan with NO such section AND no prior
  # attempt to declare one is treated as not-yet-accounting-for-shipment and
  # blocks, same as the original gate's MISSING-SECTION verdict. This is
  # deliberately not conditioned on a "feature shipped" trigger phrase (the
  # transcript-scanning approach the original Stop-hook used) — closure IS
  # the shipment declaration, so the check always applies at close time.
  local completion_unmet
  if ! completion_unmet=$(verify_completion_criteria "$plan_file"); then
    printf '[close-plan]   completion-criteria: FAIL (unmet: %s)\n' "$completion_unmet" >&2
    failed_tasks+=("completion-criteria:${completion_unmet// /,}")
  else
    printf '[close-plan]   completion-criteria: PASS\n' >&2
  fi

  # 2d. PR-merge boundary: Closure Contract still recorded (D.4 item 1,
  # closes GAP-53's preview-deploy false-pass surface by re-checking at
  # close, not trusting the creation-time plan-reviewer check alone).
  if ! verify_closure_contract_recorded "$plan_file"; then
    printf '[close-plan]   closure-contract-recorded: FAIL\n' >&2
    failed_tasks+=("closure-contract-recorded")
  else
    printf '[close-plan]   closure-contract-recorded: PASS (or grandfathered)\n' >&2
  fi

  # Block if any failure. The ONLY remediation path is to satisfy the check by
  # generating the missing structured evidence via write-evidence.sh. There is
  # no script-level escape hatch — neither --force (removed 2026-05-06) nor an
  # env-var override (removed 2026-05-06 after correctly being identified as
  # theater for an LLM agent: "loud" is not "rare", and a 40-char rationale is
  # not friction the agent experiences).
  #
  # Genuine emergencies (lost evidence files, substrate bugs) require manual
  # git operations: edit Status by hand, git mv to archive, git rm any stale
  # state, git commit. Several deliberate visible steps. Appropriately rare.
  if [[ ${#failed_tasks[@]} -gt 0 ]]; then
    printf '\n[close-plan] BLOCKED — %d failure(s):\n' "${#failed_tasks[@]}" >&2
    local f
    for f in "${failed_tasks[@]}"; do
      printf '  - %s\n' "$f" >&2
    done
    printf '\n[close-plan] To remediate:\n' >&2
    printf '  Generate the missing structured evidence per task and re-run close-plan.\n' >&2
    printf '\n  For each failing mechanical/contract task, run:\n' >&2
    printf '    bash ~/.claude/scripts/write-evidence.sh capture --task <id> --plan %s --check files-in-commit\n' "$slug" >&2
    printf '\n  For full-tier tasks, ensure the prose evidence-block has Verdict: PASS in the evidence file.\n' >&2
    if printf '%s\n' "${failed_tasks[@]}" | grep -q '^completion-criteria:'; then
      printf '\n  For completion-criteria failures: add/complete a "## Completion Criteria" section\n' >&2
      printf '    to the plan covering all 8 (code/tests/dev_docs/user_docs/migration/deploy/\n' >&2
      printf '    acceptance/stakeholder), each as [x] + evidence OR N/A + justification. The\n' >&2
      printf '    deploy criterion requires PRODUCTION/MASTER evidence specifically (a preview\n' >&2
      printf '    deploy does not satisfy it — GAP-53). Escape hatch: CLOSE_PLAN_COMPLETION_SKIP=\n' >&2
      printf '    <keys> for genuinely inapplicable criteria (audit-logged).\n' >&2
    fi
    if printf '%s\n' "${failed_tasks[@]}" | grep -q '^closure-contract-recorded$'; then
      printf '\n  For closure-contract-recorded failure: populate all four "## Closure Contract"\n' >&2
      printf '    fields (Commands that run / Expected outputs / On-disk artifact location /\n' >&2
      printf '    Done when) with plan-specific content — no "[populate me]" placeholders left.\n' >&2
    fi
    printf '\n[close-plan] No script-level override exists. If genuinely necessary,\n' >&2
    printf '  perform the close manually via git: edit Status, git mv to archive,\n' >&2
    printf '  git rm stale state, git commit. Visible in history. Appropriately rare.\n' >&2
    return 2
  fi

  # 2b. Auto-mode Closure-Contract precondition (R4 / ADR 036-c). ONLY in
  # --auto mode. The manual close trusts the operator; the unattended auto
  # close must independently confirm the predefined contract artifact exists
  # with verdict PASS + matching committed SHA before flipping Status. A
  # non-SATISFIED/EXEMPT result is a HOLD (exit 2): the plan stays ACTIVE,
  # nothing is half-closed; the PostToolUse caller logs the reason and no-ops.
  if [[ "$auto_mode" == true ]]; then
    local contract_state
    contract_state=$(check_closure_contract_artifact "$plan_file")
    case "$contract_state" in
      SATISFIED|EXEMPT)
        printf '[close-plan] auto: Closure Contract artifact %s\n' "$contract_state" >&2
        ;;
      *)
        printf '[close-plan] auto: HOLD — Closure Contract artifact %s for non-exempt plan %s.\n' "$contract_state" "$slug" >&2
        printf '[close-plan] auto:   Expected a PASS artifact under .claude/state/acceptance/%s/ whose plan_commit_sha matches the committed plan SHA. Plan stays ACTIVE.\n' "$slug" >&2
        return 2
        ;;
    esac
  fi

  # 3. Generate completion report.
  printf '[close-plan] generating completion report...\n' >&2
  local report
  report=$(generate_completion_report "$plan_file")
  write_completion_report "$plan_file" "$report"

  # 4. Update SCRATCHPAD.
  printf '[close-plan] updating SCRATCHPAD...\n' >&2
  update_scratchpad "$slug"

  # 5. Flip Status: ACTIVE → COMPLETED via a bash write. NOTE (comment
  # corrected 2026-06-10 per plan-lifecycle-redesign R4 finding): a bash sed
  # write is NOT an Edit/Write tool call, so it fires NO PostToolUse event —
  # plan-lifecycle.sh NEVER sees this flip, whether or not the script runs
  # inside a Claude Code session. Archival is therefore owned by step 6's
  # inline fallback in EVERY close-plan flow; plan-lifecycle.sh archives only
  # manual Edit-tool Status flips made outside this script.
  printf '[close-plan] flipping Status: ACTIVE → COMPLETED...\n' >&2
  local tmp_plan close_ts
  close_ts="$(iso_timestamp)"
  tmp_plan=$(mktemp)
  sed -e 's/^Status:[[:space:]]*ACTIVE[[:space:]]*$/Status: COMPLETED/' "$plan_file" > "$tmp_plan"
  cp "$tmp_plan" "$plan_file"
  rm -f "$tmp_plan"

  # 6. Inline archival — the SOLE archival path under close-plan (see step 5:
  # plan-lifecycle.sh cannot fire on bash writes). If the plan is still under
  # docs/plans/ (top-level, not archive) after the Status flip, move it (and
  # its sibling evidence file) ourselves. Idempotent — if the file is already
  # archived, the check is a no-op.
  local orig_plan_path="$plan_file"
  local orig_evidence_path="" archived_evidence_path=""
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
        orig_evidence_path="$evidence_file"
        archived_evidence_path="$archived_evidence"
      fi
      printf '[close-plan] archived to: %s\n' "$archived_path" >&2
      plan_file="$archived_path"
    fi
  fi

  # 7. Commit the closure so the commit captures the FLIPPED content.
  # Defect this step closes (observed twice — manual fix-ups 83c2564
  # 2026-06-08 and b27027f 2026-06-10): `git mv` stages the rename carrying
  # the PRE-flip index blob, while the sed Status flip + completion report
  # exist only in the working tree; close-plan then staged-but-never-
  # committed, so the closing session's commit landed as a rename-only
  # commit whose archived blob still read `Status: ACTIVE`. Fix: re-add the
  # moved files (refreshing the index to the flipped working-tree content)
  # and commit pathspec-limited, so unrelated staged work in the calling
  # session is never swept into the closure commit.
  if git rev-parse --git-dir >/dev/null 2>&1; then
    local -a closure_paths=()
    git add -- "$plan_file" 2>/dev/null
    closure_paths+=("$plan_file")
    if [[ -n "$archived_evidence_path" ]] && [[ -f "$archived_evidence_path" ]]; then
      git add -- "$archived_evidence_path" 2>/dev/null
      closure_paths+=("$archived_evidence_path")
    fi
    # Include pre-archival paths so the staged deletions land in the same
    # commit (only when HEAD knows them — untracked plans have no deletion).
    if [[ "$orig_plan_path" != "$plan_file" ]] && git cat-file -e "HEAD:$orig_plan_path" 2>/dev/null; then
      closure_paths+=("$orig_plan_path")
    fi
    if [[ -n "$orig_evidence_path" ]] && git cat-file -e "HEAD:$orig_evidence_path" 2>/dev/null; then
      closure_paths+=("$orig_evidence_path")
    fi
    if [[ -n "$(git status --porcelain -- "${closure_paths[@]}" 2>/dev/null)" ]]; then
      if git commit -q -m "chore(plans): close $slug (COMPLETED + completion report, archived)" -- "${closure_paths[@]}" 2>/dev/null; then
        printf '[close-plan] closure committed: %s\n' "$(git rev-parse --short HEAD 2>/dev/null)" >&2
      else
        printf '[close-plan] WARN: closure commit FAILED — stage+commit %s manually so the archived blob carries Status: COMPLETED (do NOT leave the rename-only staged state; see fix-ups 83c2564/b27027f for the failure shape).\n' "$plan_file" >&2
      fi
    fi
  fi

  # Progress-log emission: plan_completed (Task 6b -- sixth lane / the ask
  # lifecycle's mechanical exit). Fires ONLY on this successful-close path --
  # every early return above (blocked verification, auto-mode HOLD, usage
  # errors) never reaches here -- so both the auto-closure PostToolUse lane
  # and a manual close each emit exactly once, from this one call site.
  emit_plan_completed_progress_log_event "$plan_file" "$slug" "$close_ts"

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

  # Sandbox EVERY progress-log emission any closure scenario below triggers
  # (Task 6b splice; constraint 4). Every `bash "$SELF_PATH" close ...`
  # subprocess spawned by a scenario below inherits these exports, so a
  # successful synthetic closure's plan_completed event lands under THIS
  # self-test's own tempdir, never the operator's real
  # ~/.claude/state/progress-logs (mirrors plan-lifecycle.sh --self-test's
  # identical sandboxing of Task 1's task_done splice).
  export HARNESS_SELFTEST=1
  local CP_ST_PL_DIR
  CP_ST_PL_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t cpplst)
  export PROGRESS_LOG_STATE_DIR="$CP_ST_PL_DIR/progress-logs"
  mkdir -p "$PROGRESS_LOG_STATE_DIR"

  local PASSED=0 FAILED=0
  local saved_pwd="$PWD"

  printf 'close-plan.sh self-test (21 scenarios)\n\n' >&2

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

  # S7b: blocked closure prints remediation guide. Critically:
  #   - mentions write-evidence.sh capture (the only happy path)
  #   - does NOT suggest --force, --no-verify, or any env-var override
  #   - does NOT mention a CLOSE_PLAN_*_OVERRIDE env var (removed 2026-05-06)
  local s7b_out s7b_rc
  s7b_out=$(cd "$D7" && bash "$SELF_PATH" close p-force --no-push 2>&1)
  s7b_rc=$?
  if [[ $s7b_rc -eq 2 ]] \
     && printf '%s' "$s7b_out" | grep -q 'write-evidence.sh capture' \
     && ! printf '%s' "$s7b_out" | grep -qE 'use --force' \
     && ! printf '%s' "$s7b_out" | grep -qE 'CLOSE_PLAN_[A-Z_]*OVERRIDE'; then
    printf 'self-test (S7b) remediation-guide-no-escape-hatch: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7b) remediation-guide-no-escape-hatch: FAIL (rc=%s)\n' "$s7b_rc" >&2
    FAILED=$((FAILED+1))
  fi

  # S7c: env-var "override" is NOT honored. The script blocks even when an
  # arbitrary CLOSE_PLAN_EMERGENCY_OVERRIDE is set (the variable was removed
  # 2026-05-06; setting it must have no effect — the gate still blocks).
  local s7c_out s7c_rc
  s7c_out=$(cd "$D7" && CLOSE_PLAN_EMERGENCY_OVERRIDE="legitimate-looking emergency rationale that would have satisfied the prior 40-char gate" bash "$SELF_PATH" close p-force --no-push 2>&1)
  s7c_rc=$?
  if [[ $s7c_rc -eq 2 ]] \
     && printf '%s' "$s7c_out" | grep -q 'BLOCKED' \
     && [[ ! -f "$D7/docs/plans/archive/p-force.md" ]]; then
    printf 'self-test (S7c) env-var-override-not-honored: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7c) env-var-override-not-honored: FAIL (rc=%s)\n' "$s7c_rc" >&2
    FAILED=$((FAILED+1))
  fi

  # S7d: no audit-log file is created on a blocked closure (no override happened
  # → no override to log). Confirms the env-var path is fully removed, not just
  # silently ignored while still writing a stale audit entry.
  if [[ ! -f "$D7/.claude/state/close-plan-emergency-overrides.log" ]]; then
    printf 'self-test (S7d) no-override-audit-log-written: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7d) no-override-audit-log-written: FAIL\n' >&2
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

  # ----- S11: closure-commit-captures-flipped-content (regression for the
  # rename-only-commit defect; manual fix-ups 83c2564 / b27027f) -----
  local D11; D11=$(setup_synthetic_repo "S11" "p-commit")
  (
    cd "$D11" || exit 1
    cat > docs/plans/p-commit.md <<'EOF'
# Plan: P Commit
Status: ACTIVE
Backlog items absorbed: none

## Goal
closure commit must capture flipped content

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-commit.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-commit-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-commit-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-commit --no-push >/dev/null 2>&1
  )
  if ( cd "$D11" \
       && git show HEAD:docs/plans/archive/p-commit.md 2>/dev/null | grep -q '^Status: COMPLETED' \
       && git show HEAD:docs/plans/archive/p-commit.md 2>/dev/null | grep -q '^## Completion Report' \
       && [[ -z "$(git status --porcelain -- docs/plans/p-commit.md docs/plans/archive/p-commit.md)" ]] ); then
    printf 'self-test (S11) closure-commit-captures-flipped-content: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S11) closure-commit-captures-flipped-content: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D11"

  # ----- S12: inline-phrase-collision — task prose mentions `Verification:
  # full` but the trailing declaration is `Verification: mechanical`; the
  # LAST occurrence must win (discovery 2026-05-11-close-plan-verification-
  # field-parser-greedy). With only a mechanical .evidence.json present,
  # closure succeeds iff the parser picked `mechanical`. -----
  local D12; D12=$(setup_synthetic_repo "S12" "p-collide")
  (
    cd "$D12" || exit 1
    cat > docs/plans/p-collide.md <<'EOF'
# Plan: P Collide
Status: ACTIVE
Backlog items absorbed: none

## Goal
inline-phrase collision must not misclassify the verification level

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. Add requirement for `Verification: full` runtime tasks — Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-collide.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-collide-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-collide-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-collide --no-push >/dev/null 2>&1
  )
  if [[ -f "$D12/docs/plans/archive/p-collide.md" ]] \
     && grep -q '^Status: COMPLETED' "$D12/docs/plans/archive/p-collide.md"; then
    printf 'self-test (S12) inline-phrase-collision-last-occurrence-wins: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S12) inline-phrase-collision-last-occurrence-wins: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D12"

  # ----- S13: --auto on an acceptance-exempt plan with all mechanical
  # evidence present → EXEMPT precondition path → CLOSES (T6). -----
  local D13; D13=$(setup_synthetic_repo "S13" "p-auto-exempt")
  (
    cd "$D13" || exit 1
    cat > docs/plans/p-auto-exempt.md <<'EOF'
# Plan: P Auto Exempt
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-development; self-tests are the acceptance artifact.

## Goal
auto-closure on an acceptance-exempt plan via self-test evidence

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-auto-exempt.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-auto-exempt-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-auto-exempt-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-auto-exempt --auto >/dev/null 2>&1
  )
  if [[ -f "$D13/docs/plans/archive/p-auto-exempt.md" ]] \
     && grep -q '^Status: COMPLETED' "$D13/docs/plans/archive/p-auto-exempt.md"; then
    printf 'self-test (S13) auto-exempt-closes-via-selftest-evidence: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S13) auto-exempt-closes-via-selftest-evidence: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D13"

  # ----- S14: --auto on a NON-exempt plan with all tasks verified but NO
  # acceptance artifact → HOLD (exit 2) → plan stays ACTIVE, NOT closed (T3
  # primary false-positive guard at the close layer). -----
  local D14 rc14; D14=$(setup_synthetic_repo "S14" "p-auto-noart")
  (
    cd "$D14" || exit 1
    cat > docs/plans/p-auto-noart.md <<'EOF'
# Plan: P Auto NoArt
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: false

## Goal
non-exempt auto-closure must HOLD without a contract artifact

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-auto-noart.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-auto-noart-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-auto-noart-evidence/1.evidence.json
    git add . && git commit -q -m "init"
  )
  ( cd "$D14" && bash "$SELF_PATH" close p-auto-noart --auto >/dev/null 2>&1 ); rc14=$?
  if [[ "$rc14" -eq 2 ]] \
     && [[ -f "$D14/docs/plans/p-auto-noart.md" ]] \
     && grep -q '^Status: ACTIVE' "$D14/docs/plans/p-auto-noart.md" \
     && [[ ! -f "$D14/docs/plans/archive/p-auto-noart.md" ]]; then
    printf 'self-test (S14) auto-nonexempt-HOLDs-without-artifact: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S14) auto-nonexempt-HOLDs-without-artifact: FAIL (rc=%s)\n' "$rc14" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D14"

  # ----- S15: --auto on a NON-exempt plan WITH a matching-committed-SHA PASS
  # acceptance artifact → SATISFIED → CLOSES (T1 true positive at the close
  # layer; T11b SHA-match basis = committed plan SHA). -----
  local D15; D15=$(setup_synthetic_repo "S15" "p-auto-art")
  (
    cd "$D15" || exit 1
    cat > docs/plans/p-auto-art.md <<'EOF'
# Plan: P Auto Art
Status: ACTIVE
Backlog items absorbed: none
acceptance-exempt: false

## Goal
non-exempt auto-closure closes with a matching PASS artifact

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-auto-art.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-auto-art-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-auto-art-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    # Committed SHA of the plan file (the match basis the gate uses).
    plan_sha=$(git log -n 1 --pretty=format:'%H' -- docs/plans/p-auto-art.md)
    mkdir -p .claude/state/acceptance/p-auto-art
    printf '{"plan_slug":"p-auto-art","plan_commit_sha":"%s","scenarios":[{"id":"happy","verdict":"PASS"}]}\n' "$plan_sha" \
      > .claude/state/acceptance/p-auto-art/sess-1.json
    bash "$SELF_PATH" close p-auto-art --auto >/dev/null 2>&1
  )
  if [[ -f "$D15/docs/plans/archive/p-auto-art.md" ]] \
     && grep -q '^Status: COMPLETED' "$D15/docs/plans/archive/p-auto-art.md"; then
    printf 'self-test (S15) auto-nonexempt-closes-with-matching-artifact: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S15) auto-nonexempt-closes-with-matching-artifact: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D15"

  # ----- S16 (D.4): v2 plan with UNMET completion criteria (no Completion
  # Criteria section at all) → BLOCK. Locks the relocation's core behavior:
  # a plan cannot flip to COMPLETED with unmet completion criteria. -----
  local D16; D16=$(setup_synthetic_repo "S16" "p-cc-missing")
  (
    cd "$D16" || exit 1
    cat > docs/plans/p-cc-missing.md <<'EOF'
# Plan: P CC Missing
Status: ACTIVE
Backlog items absorbed: none
lifecycle-schema: v2

## Goal
test completion-criteria relocation blocks on missing section

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-cc-missing.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-cc-missing-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-cc-missing-evidence/1.evidence.json
    git add . && git commit -q -m "init"
  )
  local s16_out s16_rc
  s16_out=$(cd "$D16" && bash "$SELF_PATH" close p-cc-missing --no-push 2>&1)
  s16_rc=$?
  if [[ $s16_rc -ne 0 ]] \
     && printf '%s' "$s16_out" | grep -q 'completion-criteria' \
     && [[ ! -f "$D16/docs/plans/archive/p-cc-missing.md" ]]; then
    printf 'self-test (S16) v2-plan-missing-completion-criteria-blocks: PASS (blocked)\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S16) v2-plan-missing-completion-criteria-blocks: FAIL (rc=%s)\n' "$s16_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D16"

  # ----- S17 (D.4): v2 plan with ALL EIGHT completion criteria satisfied
  # (evidence + PRODUCTION deploy) → PASS + closes. -----
  local D17; D17=$(setup_synthetic_repo "S17" "p-cc-full")
  (
    cd "$D17" || exit 1
    cat > docs/plans/p-cc-full.md <<'EOF'
# Plan: P CC Full
Status: ACTIVE
Backlog items absorbed: none
lifecycle-schema: v2

## Goal
test completion-criteria relocation passes when all 8 satisfied

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-cc-full.md`

## Completion Criteria

- [x] Code merged to master — PR #412, commit ab12cd3
- [x] Tests added — e2e/foo.spec.ts
- [x] Dev docs updated — docs/decisions/047-foo.md (ADR)
- [x] User docs updated — docs/support/foo.mdx
- [x] Migration applied to production — migration 152 verified
- [x] Vercel MASTER deploy succeeded — deploy green for ab12cd3 on master
- [x] Acceptance criteria verified — smoke test against /foo, screenshot captured
- [x] Stakeholder notified — support team alerted in #support

## Evidence Log
EOF
    mkdir -p docs/plans/p-cc-full-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-cc-full-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-cc-full --no-push >/dev/null 2>&1
  )
  if [[ -f "$D17/docs/plans/archive/p-cc-full.md" ]] \
     && grep -q '^Status: COMPLETED' "$D17/docs/plans/archive/p-cc-full.md"; then
    printf 'self-test (S17) v2-plan-full-completion-criteria-closes: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S17) v2-plan-full-completion-criteria-closes: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D17"

  # ----- S18 (D.4, GAP-53 regression lock): v2 plan whose `deploy` criterion
  # is checked off with PREVIEW-deploy evidence only (no master/production
  # qualifier) → BLOCK. A preview deploy is not a production deploy; the
  # relocated check must not repeat the false-pass the original gate's
  # looser evidence regex allowed. -----
  local D18; D18=$(setup_synthetic_repo "S18" "p-cc-preview")
  (
    cd "$D18" || exit 1
    cat > docs/plans/p-cc-preview.md <<'EOF'
# Plan: P CC Preview
Status: ACTIVE
Backlog items absorbed: none
lifecycle-schema: v2

## Goal
test GAP-53 preview-deploy false-pass does not recur at close-plan

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-cc-preview.md`

## Completion Criteria

- [x] Code merged to master — PR #412, commit ab12cd3
- [x] Tests added — e2e/foo.spec.ts
- [x] Dev docs updated — docs/decisions/047-foo.md (ADR)
- [x] User docs updated — docs/support/foo.mdx
- [x] Migration applied to production — migration 152 verified
- [x] Vercel preview deploy succeeded — deploy green for PR #412
- [x] Acceptance criteria verified — smoke test against /foo, screenshot captured
- [x] Stakeholder notified — support team alerted in #support

## Evidence Log
EOF
    mkdir -p docs/plans/p-cc-preview-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-cc-preview-evidence/1.evidence.json
    git add . && git commit -q -m "init"
  )
  local s18_out s18_rc
  s18_out=$(cd "$D18" && bash "$SELF_PATH" close p-cc-preview --no-push 2>&1)
  s18_rc=$?
  if [[ $s18_rc -ne 0 ]] \
     && printf '%s' "$s18_out" | grep -qE 'completion-criteria.*deploy' \
     && [[ ! -f "$D18/docs/plans/archive/p-cc-preview.md" ]]; then
    printf 'self-test (S18) gap53-preview-deploy-does-not-satisfy-deploy-criterion: PASS (blocked)\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S18) gap53-preview-deploy-does-not-satisfy-deploy-criterion: FAIL (rc=%s out=%s)\n' "$s18_rc" "$s18_out" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D18"

  # ----- S19 (D.4): v2 plan with a PLACEHOLDER-ONLY Closure Contract section
  # (never populated) → BLOCK on closure-contract-recorded (PR-merge boundary
  # check). Locks that close-plan re-verifies the contract at CLOSE time, not
  # just trusting the plan-reviewer creation-time check. -----
  local D19; D19=$(setup_synthetic_repo "S19" "p-cc-contract")
  (
    cd "$D19" || exit 1
    cat > docs/plans/p-cc-contract.md <<'EOF'
# Plan: P CC Contract
Status: ACTIVE
Backlog items absorbed: none
lifecycle-schema: v2
acceptance-exempt: true
acceptance-exempt-reason: harness-development; self-tests are the acceptance artifact.

## Goal
test PR-merge boundary check blocks on an unfilled Closure Contract

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-cc-contract.md`

## Closure Contract
- **Commands that run:** [populate me — verification commands]
- **Expected outputs:** [populate me — PASS criteria]
- **On-disk artifact location:** [populate me — where the PASS artifact lands]
- **Done when:** [populate me — one-sentence closure condition]

## Evidence Log
EOF
    mkdir -p docs/plans/p-cc-contract-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-cc-contract-evidence/1.evidence.json
    git add . && git commit -q -m "init"
  )
  local s19_out s19_rc
  s19_out=$(cd "$D19" && bash "$SELF_PATH" close p-cc-contract --no-push 2>&1)
  s19_rc=$?
  if [[ $s19_rc -ne 0 ]] \
     && printf '%s' "$s19_out" | grep -q 'closure-contract-recorded' \
     && [[ ! -f "$D19/docs/plans/archive/p-cc-contract.md" ]]; then
    printf 'self-test (S19) placeholder-closure-contract-blocks-at-close: PASS (blocked)\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S19) placeholder-closure-contract-blocks-at-close: FAIL (rc=%s)\n' "$s19_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D19"

  # ----- S20 (Task 6b): plan_completed is emitted from a REAL end-to-end
  # close -- the wire check `close-plan.sh` successful-close path ->
  # `progress-log.sh emit`. -----
  local D20; D20=$(setup_synthetic_repo "S20" "p-plcomp")
  (
    cd "$D20" || exit 1
    cat > docs/plans/p-plcomp.md <<'EOF'
# Plan: P Plcomp
Status: ACTIVE
Backlog items absorbed: none
ask-id: ask-selftest-close-plan-completed

## Goal
test plan_completed emission on successful close

## Scope
- IN: x
- OUT: y

## Tasks
- [x] 1. First task. Verification: mechanical

## Files to Modify/Create
- `docs/plans/p-plcomp.md`

## Evidence Log
EOF
    mkdir -p docs/plans/p-plcomp-evidence
    printf '{"task_id":"1","verdict":"PASS"}\n' > docs/plans/p-plcomp-evidence/1.evidence.json
    git add . && git commit -q -m "init"
    bash "$SELF_PATH" close p-plcomp --no-push >/dev/null 2>&1
  )
  local S20_LOG
  S20_LOG="$PROGRESS_LOG_STATE_DIR/ask-selftest-close-plan-completed.jsonl"
  if [[ -f "$D20/docs/plans/archive/p-plcomp.md" ]] \
     && [[ -f "$S20_LOG" ]] \
     && grep -q '"type":"plan_completed"' "$S20_LOG" \
     && grep -q '"plan_slug":"p-plcomp"' "$S20_LOG" \
     && grep -q '"emitter":"close-plan"' "$S20_LOG"; then
    printf 'self-test (S20) plan-completed-emitted-on-successful-close: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S20) plan-completed-emitted-on-successful-close: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D20"

  # ----- S21 (Task 6b): plan_completed's dedup key is
  # plan_slug + content-hash of the Status-line ts (Task 2 table). Replaying
  # the IDENTICAL close_ts (e.g. an auditor backfill racing the live splice)
  # dedupes to ONE event; a LATER close at a genuinely DIFFERENT close_ts
  # (a re-close after reopen) is a legitimately-distinct SECOND event.
  # Exercises emit_plan_completed_progress_log_event directly (in-process --
  # no full close-plan.sh subprocess spawn needed to prove this natural-key
  # contract specifically). -----
  local D21; D21=$(setup_synthetic_repo "S21" "p-dedup")
  (
    cd "$D21" || exit 1
    cat > docs/plans/p-dedup.md <<'EOF'
# Plan: P Dedup
Status: ACTIVE
ask-id: ask-selftest-plcomp-dedup
EOF
    git add . && git commit -q -m "init"
  )
  local S21_LOG lines_replay lines_reclose
  S21_LOG="$PROGRESS_LOG_STATE_DIR/ask-selftest-plcomp-dedup.jsonl"
  rm -f "$S21_LOG"
  (
    cd "$D21" || exit 1
    emit_plan_completed_progress_log_event "docs/plans/p-dedup.md" "p-dedup" "2026-01-01T00:00:00Z"
    emit_plan_completed_progress_log_event "docs/plans/p-dedup.md" "p-dedup" "2026-01-01T00:00:00Z"
  )
  lines_replay=$(wc -l < "$S21_LOG" 2>/dev/null | tr -d ' ')
  (
    cd "$D21" || exit 1
    emit_plan_completed_progress_log_event "docs/plans/p-dedup.md" "p-dedup" "2026-02-02T00:00:00Z"
  )
  lines_reclose=$(wc -l < "$S21_LOG" 2>/dev/null | tr -d ' ')
  if [[ "$lines_replay" == "1" ]] && [[ "$lines_reclose" == "2" ]]; then
    printf 'self-test (S21) plan-completed-dedup-by-status-line-ts-hash: PASS (replay=1 line, re-close-after-reopen=2nd distinct line)\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S21) plan-completed-dedup-by-status-line-ts-hash: FAIL (replay_lines=%s reclose_lines=%s)\n' "$lines_replay" "$lines_reclose" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D21"

  cd "$saved_pwd"
  rm -rf "$CP_ST_PL_DIR" 2>/dev/null || true

  printf '\nself-test summary: %d passed, %d failed (of 21 scenarios)\n' "$PASSED" "$FAILED" >&2
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
