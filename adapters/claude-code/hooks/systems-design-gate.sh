#!/bin/bash
# systems-design-gate.sh — Generation 5
#
# PreToolUse hook that blocks Edit/Write operations on design-mode files
# unless a valid plan with Mode: design (or Mode: design-skip) exists.
#
# Design-mode files: CI/CD workflows, migrations, infrastructure config,
# deployment scripts. See DESIGN_MODE_PATTERNS below for the full list.
#
# The gate exists because design-mode work historically shipped with
# shallow planning that caused hours of downstream debugging. The gate
# enforces the pattern: write the systems-engineering analysis FIRST,
# then implement. It can't be skipped without leaving an audit trail
# (the Mode: design-skip escape hatch requires a minimal plan file
# justifying the skip).
#
# Escape hatches (legitimate cases):
#   1. The target file is not design-mode → pass through.
#   2. The edit is to a plan file itself → pass through (handled by
#      plan-edit-validator.sh).
#   3. The edit is to the evidence file or docs → pass through.
#   4. An active plan with `Mode: design` AND `Status: ACTIVE` exists
#      in docs/plans/ → pass through (trust plan-reviewer.sh to have
#      enforced section completeness).
#   5. An active plan with `Mode: design-skip` AND `Status: ACTIVE`
#      exists in docs/plans/ AND it references the file being edited
#      in a "Why design-skip" section → pass through.
#
# Exit codes:
#   0 — edit is allowed
#   1 — edit is blocked (stderr explains why + how to unblock)

set -e

# ============================================================
# Input loading — support both CLAUDE_TOOL_INPUT and stdin
# ============================================================
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || echo "")
  fi
fi

if [[ -z "$INPUT" ]]; then
  exit 0
fi

# ============================================================
# Extract target file
# ============================================================
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // .tool_input.file_path // empty' 2>/dev/null || echo "")

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# ============================================================
# Fast-path: pass-through for files the gate doesn't care about
# ============================================================

# Plan files themselves (handled by plan-edit-validator.sh)
case "$FILE_PATH" in
  */docs/plans/*) exit 0 ;;
esac

# Evidence files
case "$FILE_PATH" in
  *-evidence.md) exit 0 ;;
esac

# Docs
case "$FILE_PATH" in
  */docs/*) exit 0 ;;
  *.md) exit 0 ;;
esac

# ============================================================
# Design-mode file patterns
# ============================================================
#
# Match against the target file path. If none match, this isn't a
# design-mode file and the gate doesn't apply.

IS_DESIGN_MODE=0

# Normalize path separators for consistent matching (Windows Git Bash
# can emit backslashes in JSON). We work off forward-slash form.
NORM_PATH=$(echo "$FILE_PATH" | tr '\\' '/')

# GitHub Actions workflows
if [[ "$NORM_PATH" == *"/.github/workflows/"*".yml" ]] || \
   [[ "$NORM_PATH" == *"/.github/workflows/"*".yaml" ]]; then
  IS_DESIGN_MODE=1
fi

# Infrastructure config files (root-of-project, not inside node_modules etc.)
case "$NORM_PATH" in
  */vercel.json) IS_DESIGN_MODE=1 ;;
  */railway.toml) IS_DESIGN_MODE=1 ;;
  */fly.toml) IS_DESIGN_MODE=1 ;;
  */Dockerfile) IS_DESIGN_MODE=1 ;;
  */Dockerfile.*) IS_DESIGN_MODE=1 ;;
  */docker-compose.yml) IS_DESIGN_MODE=1 ;;
  */docker-compose.yaml) IS_DESIGN_MODE=1 ;;
  */docker-compose.*.yml) IS_DESIGN_MODE=1 ;;
  */.dockerignore) IS_DESIGN_MODE=1 ;;
esac

# Migrations
if [[ "$NORM_PATH" == *"/supabase/migrations/"*".sql" ]] || \
   [[ "$NORM_PATH" == *"/prisma/migrations/"* ]] || \
   [[ "$NORM_PATH" == *"/db/migrations/"*".sql" ]] || \
   [[ "$NORM_PATH" == *"/database/migrations/"*".sql" ]]; then
  IS_DESIGN_MODE=1
fi

# Terraform
case "$NORM_PATH" in
  */terraform/*.tf) IS_DESIGN_MODE=1 ;;
  */infra/*.tf) IS_DESIGN_MODE=1 ;;
  *.tfvars) IS_DESIGN_MODE=1 ;;
esac

# Deploy / migrate scripts (pattern: scripts/ + deploy|migrate name)
if [[ "$NORM_PATH" == *"/scripts/deploy"* ]] || \
   [[ "$NORM_PATH" == *"/scripts/migrate"* ]] || \
   [[ "$NORM_PATH" == *"/scripts/provision"* ]]; then
  IS_DESIGN_MODE=1
fi

# Nginx / reverse proxy config
case "$NORM_PATH" in
  */nginx.conf) IS_DESIGN_MODE=1 ;;
  */nginx/*.conf) IS_DESIGN_MODE=1 ;;
  */Caddyfile) IS_DESIGN_MODE=1 ;;
esac

# Not a design-mode file — pass through
if [[ $IS_DESIGN_MODE -eq 0 ]]; then
  exit 0
fi

# ============================================================
# Design-mode file detected. Look for an active design-mode plan.
# ============================================================
#
# Walk up from the target file until we find a docs/plans/ directory.
# This handles repos where the file lives under a sub-path.

# Start search directory: directory containing the target file
SEARCH_DIR=$(dirname "$NORM_PATH")

# Walk up to find the repo root (marked by .git or docs/plans/)
REPO_ROOT=""
CURRENT="$SEARCH_DIR"
while [[ "$CURRENT" != "/" && "$CURRENT" != "." && -n "$CURRENT" ]]; do
  if [[ -d "$CURRENT/.git" ]] || [[ -d "$CURRENT/docs/plans" ]]; then
    REPO_ROOT="$CURRENT"
    break
  fi
  PARENT=$(dirname "$CURRENT")
  if [[ "$PARENT" == "$CURRENT" ]]; then
    break
  fi
  CURRENT="$PARENT"
done

if [[ -z "$REPO_ROOT" ]] || [[ ! -d "$REPO_ROOT/docs/plans" ]]; then
  cat >&2 <<MSG
BLOCKED: systems-design-gate

Target file is a design-mode file:
  $FILE_PATH

But no docs/plans/ directory was found walking up from this file.
Design-mode work requires a plan in docs/plans/ with:
  Mode: design
  Status: ACTIVE

Create the plan first. Use ~/.claude/templates/plan-template.md with
Mode: design and fill the 10 Systems Engineering Analysis sections.
See ~/.claude/rules/design-mode-planning.md for the full protocol.

If this edit is genuinely not system-design work (e.g., one-line typo
fix in a Dockerfile comment), create a Mode: design-skip plan with a
one-sentence justification — that records your judgment for audit.
MSG
  exit 1
fi

# ============================================================
# Scan docs/plans/ for an active design-mode plan
# ============================================================

ACTIVE_DESIGN_PLAN=""
ACTIVE_SKIP_PLAN=""

for PLAN in "$REPO_ROOT"/docs/plans/*.md; do
  [[ -f "$PLAN" ]] || continue

  # Extract Mode and Status from the plan header. Headers look like:
  #   Mode: design
  #   Status: ACTIVE
  # Use awk so we don't get fooled by "Mode:" appearing later in prose.
  MODE_LINE=$(awk '/^Mode:/ { print; exit }' "$PLAN" 2>/dev/null || echo "")
  STATUS_LINE=$(awk '/^Status:/ { print; exit }' "$PLAN" 2>/dev/null || echo "")

  # Extract the value after the colon, trimming whitespace
  MODE=$(echo "$MODE_LINE" | sed -E 's/^Mode:[[:space:]]*//' | awk '{print $1}')
  STATUS=$(echo "$STATUS_LINE" | sed -E 's/^Status:[[:space:]]*//' | awk '{print $1}')

  # Only interested in ACTIVE plans
  if [[ "$STATUS" != "ACTIVE" ]]; then
    continue
  fi

  if [[ "$MODE" == "design" ]]; then
    ACTIVE_DESIGN_PLAN="$PLAN"
    break
  fi

  if [[ "$MODE" == "design-skip" ]]; then
    # Check that this skip plan references the file being edited. We
    # look for the target file's basename or relative path in the
    # plan's content.
    FILE_BASENAME=$(basename "$NORM_PATH")
    if grep -q -F "$FILE_BASENAME" "$PLAN" 2>/dev/null; then
      ACTIVE_SKIP_PLAN="$PLAN"
    fi
  fi
done

# Found an active Mode: design plan — allow
if [[ -n "$ACTIVE_DESIGN_PLAN" ]]; then
  exit 0
fi

# Found a design-skip plan that references this file — allow
if [[ -n "$ACTIVE_SKIP_PLAN" ]]; then
  exit 0
fi

# ============================================================
# No valid plan found — block with guidance
# ============================================================

cat >&2 <<MSG
BLOCKED: systems-design-gate

Target file is a design-mode file:
  $FILE_PATH

Design-mode files require a written systems-engineering plan BEFORE
implementation. See ~/.claude/rules/design-mode-planning.md for why.

No active plan with \`Mode: design\` (or \`Mode: design-skip\` referencing
this file) was found under:
  $REPO_ROOT/docs/plans/

To unblock, choose ONE:

Option A — Full design-mode plan (recommended for substantive changes):
  1. Copy ~/.claude/templates/plan-template.md to docs/plans/<slug>.md
  2. Set header: Mode: design, Status: ACTIVE
  3. Fill the 10 Systems Engineering Analysis sections (not placeholder text)
  4. Invoke the systems-designer agent to review; iterate until PASS
  5. Then retry the edit

Option B — design-skip plan (only for trivial changes):
  1. Create docs/plans/<slug>-skip.md with:
       Mode: design-skip
       Status: ACTIVE
       ## Why design-skip
       <one-sentence specific justification, naming $FILE_BASENAME>
       ## Change
       <one-line description of what you're editing>
  2. Commit. Retry the edit.

Option B is AUDITED — the skip plan lives in the repo, so the judgment
call is visible in git history. Don't use it to route around legitimate
design work. Trivial-change examples: version bump in a workflow,
typo in a Dockerfile comment, renaming a variable in a migration
that's already been applied.

If you think this file shouldn't trigger the gate (pattern is too broad),
update ~/.claude/hooks/systems-design-gate.sh to refine the pattern.
MSG
exit 1
