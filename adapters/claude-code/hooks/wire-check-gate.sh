#!/bin/bash
# wire-check-gate.sh — 2026-05-11
#
# PreToolUse Edit/Write hook that blocks a plan-file checkbox flip on a
# Verification: full task unless the session's evidence file (or
# structured .evidence.json artifact) contains proof that the task's
# "Prove it works" scenario was actually exercised.
#
# Plan-time companion: `plan-reviewer.sh` Check 13 enforces that
# Verification: full tasks declare three sub-blocks under the task
# line: `**Prove it works:**`, `**Wire checks:**`, `**Integration
# points:**`. Once those are authored, this hook is the runtime
# enforcement that the scenario was actually run before the checkbox
# can flip.
#
# The hook does NOT execute the scenario itself. It verifies that the
# session-end artifact substrate contains evidence the scenario was
# executed:
#
#   Acceptable proof shapes (any ONE satisfies):
#
#     1. The companion prose evidence file `<plan>-evidence.md` contains
#        a section for the task ID with a `Wire check executed:` or
#        `Prove-it-works run:` block (>= 80 non-whitespace chars).
#
#     2. The structured artifact at
#        `<plan-dir>/<plan-slug>-evidence/<task-id>.evidence.json` has
#        a `runtime_evidence` array with at least one entry whose
#        `type` is one of: playwright|curl|test|file, AND the same
#        artifact's `mechanical_checks` array contains at least one
#        entry with `passed: true`. (Lightweight: presence + truthy
#        passed flag satisfies the contract.)
#
#     3. The evidence file or task section contains the canonical
#        carve-out `Wire check: n/a — <one-sentence justification
#        >= 30 chars>` (used when the plan-time author authored a
#        full-level task whose runtime exercise is genuinely
#        impossible at build time, e.g. an environment variable
#        gating a third-party callback).
#
# Fast-path exits (silent pass):
#   - Tool is not Edit/Write/MultiEdit
#   - file_path is not a plan file under docs/plans/
#   - file_path ends with -evidence.md (companion file edits)
#   - The edit is not a checkbox flip (old contains "- [ ]"
#     and new contains "- [x]")
#   - The flipped task's line declares `Verification: mechanical`
#     or `Verification: contract` (those levels are exempt; the
#     mechanical-evidence substrate is the authority there)
#   - The flipped task line does NOT contain a `**Prove it works:**`
#     sub-block under it AND has no Tier A runtime keyword
#     (non-integration task — Check 13 also doesn't fire)
#
# Exit codes:
#   0 — edit allowed (not our concern OR wire-check evidence present)
#   1 — edit blocked (full-level integration task missing wire-check evidence)
#
# Self-test: `bash wire-check-gate.sh --self-test` exercises 6 scenarios.

set -u

# ============================================================
# --self-test
# ============================================================

if [[ "${1:-}" == "--self-test" ]]; then
  TMPDIR_SELFTEST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_SELFTEST"' EXIT
  SCRIPT="${BASH_SOURCE[0]}"
  FAILED=0

  # Helper: write a synthetic plan file containing a full-level task
  # with the three sub-blocks under it.
  write_plan_with_full_task() {
    local plan_path="$1"
    cat > "$plan_path" <<'PLAN_EOF'
# Plan: Wire-check-gate test fixture
Status: ACTIVE

## Tasks

- [ ] 1. Build the duplicate flow end-to-end — Verification: full
  **Prove it works:**
  1. Open /campaigns
  2. Click Duplicate; confirm new row appears
  **Wire checks:**
  - Click → POST /api/campaigns/duplicate
  **Integration points:**
  - Endpoint verified via curl POST returns 200.

PLAN_EOF
  }

  # Helper: build a tool-input JSON for an Edit operation flipping task 1
  build_flip_input() {
    local plan_path="$1"
    cat <<JSON
{"file_path":"$plan_path","old_string":"- [ ] 1. Build the duplicate flow end-to-end","new_string":"- [x] 1. Build the duplicate flow end-to-end"}
JSON
  }

  # Scenario (w1): flip blocked when no evidence at all — expect FAIL
  PLAN_W1="$TMPDIR_SELFTEST/w1/docs/plans/foo.md"
  mkdir -p "$(dirname "$PLAN_W1")"
  write_plan_with_full_task "$PLAN_W1"
  INPUT_W1=$(build_flip_input "$PLAN_W1")
  if echo "$INPUT_W1" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w1) no-evidence-blocks-flip: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (w1) no-evidence-blocks-flip: FAIL (expected — flip blocked)" >&2
  fi

  # Scenario (w2): flip allowed when prose evidence file has Wire check executed — expect PASS
  PLAN_W2="$TMPDIR_SELFTEST/w2/docs/plans/foo.md"
  mkdir -p "$(dirname "$PLAN_W2")"
  write_plan_with_full_task "$PLAN_W2"
  EVIDENCE_W2="${PLAN_W2%.md}-evidence.md"
  cat > "$EVIDENCE_W2" <<'EVI_EOF'
Task ID: 1
Wire check executed:
  Step 1: Opened /campaigns in chromium browser (200 OK).
  Step 2: Clicked Duplicate button on row 1.
  Step 3: Confirmed new row appeared at top with "(Copy)" suffix.
  Network log: POST /api/campaigns/duplicate -> 200, payload {id: 42}.
EVI_EOF
  INPUT_W2=$(build_flip_input "$PLAN_W2")
  if echo "$INPUT_W2" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w2) prose-wire-check-allows-flip: PASS (expected)" >&2
  else
    echo "self-test (w2) prose-wire-check-allows-flip: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (w3): flip allowed when structured .evidence.json has runtime_evidence + passed check — expect PASS
  PLAN_W3="$TMPDIR_SELFTEST/w3/docs/plans/foo.md"
  mkdir -p "$(dirname "$PLAN_W3")"
  write_plan_with_full_task "$PLAN_W3"
  ARTIFACT_DIR_W3="$TMPDIR_SELFTEST/w3/docs/plans/foo-evidence"
  mkdir -p "$ARTIFACT_DIR_W3"
  cat > "$ARTIFACT_DIR_W3/1.evidence.json" <<'JSON_EOF'
{
  "task_id": "1",
  "verdict": "PASS",
  "commit_sha": "abc123",
  "files_modified": ["src/app/campaigns/page.tsx"],
  "mechanical_checks": [{"name": "playwright duplicate flow", "passed": true, "command": "npx playwright test campaigns-duplicate.spec.ts"}],
  "runtime_evidence": [{"type": "playwright", "ref": "tests/e2e/campaigns-duplicate.spec.ts", "outcome": "PASS"}],
  "timestamp": "2026-05-11T00:00:00Z"
}
JSON_EOF
  INPUT_W3=$(build_flip_input "$PLAN_W3")
  if echo "$INPUT_W3" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w3) structured-artifact-allows-flip: PASS (expected)" >&2
  else
    echo "self-test (w3) structured-artifact-allows-flip: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (w4): flip allowed when canonical carve-out used — expect PASS
  PLAN_W4="$TMPDIR_SELFTEST/w4/docs/plans/foo.md"
  mkdir -p "$(dirname "$PLAN_W4")"
  write_plan_with_full_task "$PLAN_W4"
  EVIDENCE_W4="${PLAN_W4%.md}-evidence.md"
  cat > "$EVIDENCE_W4" <<'EVI_EOF'
Task ID: 1
Wire check: n/a — third-party OAuth callback cannot be exercised at build time; covered by post-deploy smoke test.
EVI_EOF
  INPUT_W4=$(build_flip_input "$PLAN_W4")
  if echo "$INPUT_W4" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w4) carveout-allows-flip: PASS (expected)" >&2
  else
    echo "self-test (w4) carveout-allows-flip: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (w5): mechanical-level task — gate is silent pass (out of scope)
  PLAN_W5="$TMPDIR_SELFTEST/w5/docs/plans/foo.md"
  mkdir -p "$(dirname "$PLAN_W5")"
  cat > "$PLAN_W5" <<'PLAN_EOF'
# Plan: mechanical task test
Status: ACTIVE

## Tasks
- [ ] 1. Author the new hook file at hooks/foo.sh — Verification: mechanical
PLAN_EOF
  INPUT_W5='{"file_path":"'$PLAN_W5'","old_string":"- [ ] 1. Author the new hook file at hooks/foo.sh","new_string":"- [x] 1. Author the new hook file at hooks/foo.sh"}'
  if echo "$INPUT_W5" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w5) mechanical-level-exempt: PASS (expected)" >&2
  else
    echo "self-test (w5) mechanical-level-exempt: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (w6): edit is not a checkbox flip — gate is silent pass
  PLAN_W6="$TMPDIR_SELFTEST/w6/docs/plans/foo.md"
  mkdir -p "$(dirname "$PLAN_W6")"
  write_plan_with_full_task "$PLAN_W6"
  INPUT_W6='{"file_path":"'$PLAN_W6'","old_string":"Status: ACTIVE","new_string":"Status: COMPLETED"}'
  if echo "$INPUT_W6" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w6) non-checkbox-edit-exempt: PASS (expected)" >&2
  else
    echo "self-test (w6) non-checkbox-edit-exempt: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  if [[ $FAILED -eq 0 ]]; then
    echo "wire-check-gate --self-test: all scenarios matched expectations" >&2
    exit 0
  else
    echo "wire-check-gate --self-test: one or more scenarios failed" >&2
    exit 1
  fi
fi

# ============================================================
# Normal hook execution
# ============================================================

INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || echo "")
  fi
fi

# Nothing to check — silent pass
if [[ -z "$INPUT" ]]; then
  exit 0
fi

# Extract file_path
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // .tool_input.file_path // empty' 2>/dev/null || echo "")
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Not a plan file — pass through
if [[ "$FILE_PATH" != *docs/plans/* ]]; then
  exit 0
fi

# Companion evidence file — pass through
if [[ "$FILE_PATH" == *-evidence.md ]]; then
  exit 0
fi

# Extract the strings being swapped
NEW_STRING=$(echo "$INPUT" | jq -r '.new_string // .tool_input.new_string // empty' 2>/dev/null || echo "")
OLD_STRING=$(echo "$INPUT" | jq -r '.old_string // .tool_input.old_string // empty' 2>/dev/null || echo "")

# Not a checkbox flip — pass through
if [[ "$OLD_STRING" != *"- [ ]"* ]] || [[ "$NEW_STRING" != *"- [x]"* ]]; then
  exit 0
fi

# Identify the flipped task line and ID
FLIPPED_LINE=$(echo "$NEW_STRING" | grep -m1 '^[[:space:]]*- \[x\]' || echo "")
if [[ -z "$FLIPPED_LINE" ]]; then
  # Couldn't parse — let other hooks handle
  exit 0
fi

TASK_ID=$(echo "$FLIPPED_LINE" | sed -nE 's/^[[:space:]]*- \[x\][[:space:]]+([A-Z0-9]+(\.[0-9]+)*)\.?[[:space:]].*/\1/p' | head -1)
if [[ -z "$TASK_ID" ]]; then
  # Couldn't parse a task ID — pass through
  exit 0
fi

# Verification-level exemption: mechanical / contract tasks skip the gate.
# We look at the flipped line itself; the new_string contains it verbatim.
if echo "$FLIPPED_LINE" | grep -qE 'Verification:[[:space:]]+(mechanical|contract)\b'; then
  exit 0
fi

# If the plan file doesn't exist (race / new file write), pass through.
# plan-edit-validator handles the broader "is this edit authorized" check.
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Identify if the task in the plan file has a **Prove it works:** sub-block.
# This is the structural signal Check 13 enforces at plan time. If the
# sub-block is absent in the plan, the task is not integration-bearing
# (e.g., a quick docs-only task within a multi-task plan) and the gate
# is silent. Check 13 has already rejected the plan if it should have
# the sub-block; this hook's responsibility is the runtime evidence.
PLAN_TASK_LINENO=$(grep -nE "^- \[[ xX]\][[:space:]]+${TASK_ID}\." "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1)
if [[ -z "$PLAN_TASK_LINENO" ]]; then
  # Couldn't find the task in the plan file — could be a complex format
  # variation. Pass through to avoid false-positive blocks.
  exit 0
fi

# Extract task body up to the next task line or `## ` heading
TASK_BODY=$(awk -v start="$PLAN_TASK_LINENO" '
  NR == start { next }
  NR > start {
    if ($0 ~ /^## /) exit
    if ($0 ~ /^- \[[ xX]\]/) exit
    print
  }
' "$FILE_PATH" 2>/dev/null)

# If no Prove-it-works sub-block in the plan, the task is non-integration.
# Silent pass — the gate's scope is integration tasks only.
if ! printf '%s' "$TASK_BODY" | grep -qE '^\s*\*\*Prove it works:\*\*'; then
  exit 0
fi

# ============================================================
# Look for acceptable proof in the evidence substrate
# ============================================================

EVIDENCE_FILE="${FILE_PATH%.md}-evidence.md"
PLAN_DIR=$(dirname "$FILE_PATH")
PLAN_SLUG=$(basename "$FILE_PATH" .md)
ARTIFACT_DIR="${PLAN_DIR}/${PLAN_SLUG}-evidence"
ARTIFACT_PATH="${ARTIFACT_DIR}/${TASK_ID}.evidence.json"

PROOF_FOUND=0

# Proof shape 1: prose evidence file `Wire check executed:` or
# `Prove-it-works run:` block under this task's ID section.
if [[ -f "$EVIDENCE_FILE" ]]; then
  TASK_SECTION=$(awk -v id="$TASK_ID" '
    /^Task ID:/ {
      if (in_section) exit
      if ($0 ~ "Task ID:[[:space:]]*" id "[[:space:]]*$") { in_section = 1 }
    }
    in_section { print }
  ' "$EVIDENCE_FILE" 2>/dev/null)

  if [[ -n "$TASK_SECTION" ]]; then
    # Check for Wire check executed: / Prove-it-works run: block substance
    PROOF_BLOCK=$(printf '%s' "$TASK_SECTION" | awk '
      /^(Wire check executed:|Prove-it-works run:)/ { in_block = 1; next }
      in_block && /^[A-Z][a-zA-Z ]+:/ { exit }
      in_block { print }
    ')
    if [[ -n "$PROOF_BLOCK" ]]; then
      PROOF_NON_WS=$(printf '%s' "$PROOF_BLOCK" | tr -d '[:space:]' | wc -c | tr -cd '[:digit:]')
      PROOF_NON_WS=${PROOF_NON_WS:-0}
      if [[ $PROOF_NON_WS -ge 80 ]]; then
        PROOF_FOUND=1
      fi
    fi

    # Check for canonical carve-out: `Wire check: n/a — <reason>`
    if [[ $PROOF_FOUND -eq 0 ]]; then
      CARVEOUT_LINE=$(printf '%s' "$TASK_SECTION" | grep -E '^Wire check:[[:space:]]+n/a[[:space:]]+(—|--|-)' | head -1)
      if [[ -n "$CARVEOUT_LINE" ]]; then
        CARVEOUT_REASON=$(printf '%s' "$CARVEOUT_LINE" | sed -E 's/^Wire check:[[:space:]]+n\/a[[:space:]]+(—|--|-)[[:space:]]*//')
        CARVEOUT_NON_WS=$(printf '%s' "$CARVEOUT_REASON" | tr -d '[:space:]' | wc -c | tr -cd '[:digit:]')
        CARVEOUT_NON_WS=${CARVEOUT_NON_WS:-0}
        if [[ $CARVEOUT_NON_WS -ge 30 ]]; then
          PROOF_FOUND=1
        fi
      fi
    fi
  fi
fi

# Proof shape 2: structured .evidence.json with runtime_evidence + passed check
if [[ $PROOF_FOUND -eq 0 ]] && [[ -f "$ARTIFACT_PATH" ]]; then
  # jq -e returns non-zero if predicate fails; use || true to inspect
  RUNTIME_EV_COUNT=$(jq -r '(.runtime_evidence // []) | length' "$ARTIFACT_PATH" 2>/dev/null || echo "0")
  PASSED_CHECK_COUNT=$(jq -r '[(.mechanical_checks // [])[] | select(.passed == true)] | length' "$ARTIFACT_PATH" 2>/dev/null || echo "0")
  if [[ "$RUNTIME_EV_COUNT" =~ ^[0-9]+$ ]] && [[ $RUNTIME_EV_COUNT -ge 1 ]] && \
     [[ "$PASSED_CHECK_COUNT" =~ ^[0-9]+$ ]] && [[ $PASSED_CHECK_COUNT -ge 1 ]]; then
    PROOF_FOUND=1
  fi
fi

if [[ $PROOF_FOUND -eq 1 ]]; then
  exit 0
fi

# ============================================================
# No acceptable proof found — block
# ============================================================

cat >&2 <<MSG
BLOCKED: wire-check-gate

Task $TASK_ID is a Verification: full integration task. Its plan-time
"Prove it works:" scenario must be executed before the checkbox can flip.

No acceptable proof was found in either:
  - $EVIDENCE_FILE
  - $ARTIFACT_PATH

This task requires integration verification. Run the "Prove it works"
scenario before marking complete.

Acceptable proof shapes (any one is sufficient):

  1. Prose evidence file with a "Wire check executed:" or
     "Prove-it-works run:" block (>= 80 chars substantive content)
     under the task's "Task ID: $TASK_ID" section.

  2. Structured artifact at $ARTIFACT_PATH with:
       - runtime_evidence: at least 1 entry
       - mechanical_checks: at least 1 entry with passed: true

  3. Canonical carve-out in the prose evidence file under this task:
       Wire check: n/a — <one-sentence justification >= 30 chars>
     (Use ONLY when the scenario is genuinely impossible at build time,
     e.g., third-party OAuth callback gated by environment.)

See ~/.claude/rules/planning.md "Integration Verification — Every
Full-Level Task Must Prove It Works" for the full protocol.
MSG

exit 1
