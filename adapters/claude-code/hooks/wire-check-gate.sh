#!/bin/bash
# wire-check-gate.sh — 2026-05-11
#
# PreToolUse Edit/Write hook that runs TWO verification modes when a
# Verification: full task's checkbox is about to flip in a plan file:
#
#   STATIC TRACE (mandatory — always runs):
#     Parses the task's `**Wire checks:**` block. For each arrow line
#     (containing `→` or `->`) it:
#       1. Extracts all backtick-quoted tokens.
#       2. Classifies tokens as file paths (exist relative to repo root)
#          vs non-file identifiers (function names, SQL fragments, API
#          routes, etc.).
#       3. Verifies each file path exists.
#       4. For each non-file token, grep-verifies the token appears in
#          at least one of the file paths in the SAME arrow.
#     An arrow with at least one file path AND all its non-file tokens
#     successfully grep-located counts as VERIFIED. An arrow that has a
#     file path but a missing file OR an unreferenced non-file token
#     counts as BROKEN. An arrow with no file path is UNVERIFIABLE
#     (skipped — but the plan-time Check 13 already requires >= 2
#     verifiable arrows).
#     Decision: any BROKEN arrow → BLOCK. < 2 VERIFIED arrows AND no
#     carve-out → BLOCK. >= 2 VERIFIED arrows → PASS (static trace OK).
#
#   RUNTIME TEST (additive — logged when present, never required):
#     Looks for `Wire check executed:` / `Prove-it-works run:` prose
#     block in `<plan>-evidence.md` (>= 80 chars) OR structured
#     `<plan-slug>-evidence/<task-id>.evidence.json` with at least one
#     runtime_evidence entry AND at least one passed mechanical_check.
#     When found, emits a `[wire-check] runtime evidence: <ref>` log
#     line to stderr alongside the static-trace PASS. When absent, the
#     static-trace PASS alone is sufficient for the flip.
#
# Carve-out: when the plan task's Wire checks block has a single
# `- n/a — <reason ≥ 30 chars>` line, static trace is skipped (no
# code chain to trace). Carve-out is plan-time-declared (Check 13
# enforces the reason length) so by the time we get here, accepting it
# is safe.
#
# Fast-path exits (silent pass):
#   - Tool is not Edit/Write/MultiEdit
#   - file_path is not a plan file under docs/plans/
#   - file_path ends with -evidence.md (companion file edits)
#   - The edit is not a checkbox flip (old contains "- [ ]" AND
#     new contains "- [x]")
#   - The flipped task's line declares `Verification: mechanical` or
#     `Verification: contract` (those levels are exempt)
#   - The plan task body lacks a `**Prove it works:**` sub-block
#     (non-integration task per Check 13)
#
# Exit codes:
#   0 — edit allowed (silent pass OR static trace passed)
#   1 — edit blocked (static trace failed: broken link, missing file,
#       or insufficient verifiable arrows without carve-out)
#
# Self-test: `bash wire-check-gate.sh --self-test` exercises 9 scenarios.

set -u

# ============================================================
# --self-test
# ============================================================

if [[ "${1:-}" == "--self-test" ]]; then
  TMPDIR_SELFTEST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_SELFTEST"' EXIT
  SCRIPT="${BASH_SOURCE[0]}"
  FAILED=0

  # Helper: initialize a git repo at $1 so `git rev-parse --show-toplevel`
  # works inside the fixture. Static trace needs a repo root to anchor
  # backtick-quoted relative paths.
  init_repo() {
    local root="$1"
    mkdir -p "$root"
    ( cd "$root" && git init -q && git config user.email t@t && git config user.name t ) || true
  }

  # Helper: write a synthetic plan file with a full-level task and
  # arbitrary Wire checks block content (caller supplies the block body).
  write_plan_with_wire_checks() {
    local plan_path="$1"
    local wire_body="$2"
    mkdir -p "$(dirname "$plan_path")"
    cat > "$plan_path" <<PLAN_HEAD
# Plan: Wire-check-gate test fixture
Status: ACTIVE

## Tasks

- [ ] 1. Build the duplicate flow end-to-end — Verification: full
  **Prove it works:**
  1. Open /campaigns
  2. Click Duplicate; confirm new row appears
  **Wire checks:**
${wire_body}
  **Integration points:**
  - Endpoint verified via curl POST returns 200.

PLAN_HEAD
  }

  build_flip_input() {
    local plan_path="$1"
    cat <<JSON
{"file_path":"$plan_path","old_string":"- [ ] 1. Build the duplicate flow end-to-end","new_string":"- [x] 1. Build the duplicate flow end-to-end — Verification: full"}
JSON
  }

  # Scenario (w1): every wire-check arrow has a file path that exists
  # AND every non-file token appears in the linked file. Expected PASS.
  ROOT_W1="$TMPDIR_SELFTEST/w1"
  init_repo "$ROOT_W1"
  mkdir -p "$ROOT_W1/src/components" "$ROOT_W1/src/lib"
  cat > "$ROOT_W1/src/components/CampaignList.tsx" <<'F'
export function CampaignList() {
  const onDuplicate = async (id: string) => {
    await fetch('/api/campaigns/duplicate', { method: 'POST', body: JSON.stringify({ id }) });
  };
  return <button onClick={() => onDuplicate('a')}>Duplicate</button>;
}
F
  cat > "$ROOT_W1/src/lib/campaigns.ts" <<'F'
export async function duplicateCampaign(id: string) {
  return db.execute('INSERT INTO campaigns (name) VALUES ($1)', [id]);
}
F
  PLAN_W1="$ROOT_W1/docs/plans/foo.md"
  write_plan_with_wire_checks "$PLAN_W1" '  - `src/components/CampaignList.tsx` `Duplicate` button → `/api/campaigns/duplicate`
  - `src/lib/campaigns.ts` `duplicateCampaign` → `INSERT INTO campaigns`'
  INPUT_W1=$(build_flip_input "$PLAN_W1")
  if echo "$INPUT_W1" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w1) static-trace-all-chains-verified: PASS (expected)" >&2
  else
    echo "self-test (w1) static-trace-all-chains-verified: FAIL (expected PASS)" >&2
    echo "$INPUT_W1" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" >&2 || true
    FAILED=1
  fi

  # Scenario (w2): file path does NOT exist — BROKEN link, expected FAIL.
  ROOT_W2="$TMPDIR_SELFTEST/w2"
  init_repo "$ROOT_W2"
  mkdir -p "$ROOT_W2/src/components"
  cat > "$ROOT_W2/src/components/CampaignList.tsx" <<'F'
export function CampaignList() { return null; }
F
  PLAN_W2="$ROOT_W2/docs/plans/foo.md"
  write_plan_with_wire_checks "$PLAN_W2" '  - `src/components/CampaignList.tsx` button → `/api/campaigns/duplicate`
  - `src/lib/MISSING-FILE.ts` `duplicateCampaign` → `INSERT INTO campaigns`'
  INPUT_W2=$(build_flip_input "$PLAN_W2")
  if echo "$INPUT_W2" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w2) static-trace-missing-file-blocks: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (w2) static-trace-missing-file-blocks: FAIL (expected — block)" >&2
  fi

  # Scenario (w3): file exists but cross-reference token NOT in file —
  # BROKEN link (renamed function?), expected FAIL.
  ROOT_W3="$TMPDIR_SELFTEST/w3"
  init_repo "$ROOT_W3"
  mkdir -p "$ROOT_W3/src/lib"
  cat > "$ROOT_W3/src/lib/campaigns.ts" <<'F'
export async function differentName(id: string) { return null; }
F
  PLAN_W3="$ROOT_W3/docs/plans/foo.md"
  write_plan_with_wire_checks "$PLAN_W3" '  - `src/lib/campaigns.ts` `duplicateCampaign` → `INSERT INTO campaigns`
  - `src/lib/campaigns.ts` returns JSON → `src/components/Foo.tsx` setState'
  INPUT_W3=$(build_flip_input "$PLAN_W3")
  if echo "$INPUT_W3" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w3) static-trace-renamed-function-blocks: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (w3) static-trace-renamed-function-blocks: FAIL (expected — block)" >&2
  fi

  # Scenario (w4): carve-out path — `n/a — <reason>` — expected PASS.
  ROOT_W4="$TMPDIR_SELFTEST/w4"
  init_repo "$ROOT_W4"
  PLAN_W4="$ROOT_W4/docs/plans/foo.md"
  write_plan_with_wire_checks "$PLAN_W4" '  - n/a — config-only task affecting build runtime; no UI→DB code chain.'
  INPUT_W4=$(build_flip_input "$PLAN_W4")
  if echo "$INPUT_W4" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w4) static-trace-carveout-allows-flip: PASS (expected)" >&2
  else
    echo "self-test (w4) static-trace-carveout-allows-flip: FAIL (expected PASS)" >&2
    echo "$INPUT_W4" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" >&2 || true
    FAILED=1
  fi

  # Scenario (w5): mechanical-level task — gate is silent pass.
  ROOT_W5="$TMPDIR_SELFTEST/w5"
  init_repo "$ROOT_W5"
  PLAN_W5="$ROOT_W5/docs/plans/foo.md"
  mkdir -p "$(dirname "$PLAN_W5")"
  cat > "$PLAN_W5" <<'PLAN_EOF'
# Plan: mechanical task test
Status: ACTIVE

## Tasks
- [ ] 1. Author the new hook file at hooks/foo.sh — Verification: mechanical
PLAN_EOF
  INPUT_W5='{"file_path":"'$PLAN_W5'","old_string":"- [ ] 1. Author the new hook file at hooks/foo.sh","new_string":"- [x] 1. Author the new hook file at hooks/foo.sh — Verification: mechanical"}'
  if echo "$INPUT_W5" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w5) mechanical-level-exempt: PASS (expected)" >&2
  else
    echo "self-test (w5) mechanical-level-exempt: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (w6): edit is not a checkbox flip — gate is silent pass.
  ROOT_W6="$TMPDIR_SELFTEST/w6"
  init_repo "$ROOT_W6"
  PLAN_W6="$ROOT_W6/docs/plans/foo.md"
  write_plan_with_wire_checks "$PLAN_W6" '  - `src/foo.tsx` → `/api/bar`'
  INPUT_W6='{"file_path":"'$PLAN_W6'","old_string":"Status: ACTIVE","new_string":"Status: COMPLETED"}'
  if echo "$INPUT_W6" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w6) non-checkbox-edit-exempt: PASS (expected)" >&2
  else
    echo "self-test (w6) non-checkbox-edit-exempt: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (w7): static trace passes AND runtime evidence file present
  # — gate emits additive log line and allows flip.
  ROOT_W7="$TMPDIR_SELFTEST/w7"
  init_repo "$ROOT_W7"
  mkdir -p "$ROOT_W7/src/components" "$ROOT_W7/src/lib"
  cat > "$ROOT_W7/src/components/Foo.tsx" <<'F'
fetch('/api/foo/bar');
F
  cat > "$ROOT_W7/src/lib/foo.ts" <<'F'
export function fooHandler() { return 'INSERT INTO foo_table'; }
F
  PLAN_W7="$ROOT_W7/docs/plans/foo.md"
  write_plan_with_wire_checks "$PLAN_W7" '  - `src/components/Foo.tsx` button → `/api/foo/bar`
  - `src/lib/foo.ts` `fooHandler` → `INSERT INTO foo_table`'
  EVIDENCE_W7="${PLAN_W7%.md}-evidence.md"
  cat > "$EVIDENCE_W7" <<'EVI_EOF'
Task ID: 1
Wire check executed:
  Step 1: Opened /campaigns in chromium (200 OK).
  Step 2: Clicked Duplicate button on row 1.
  Step 3: Confirmed new row at top with "(Copy)".
  Network log: POST /api/campaigns/duplicate -> 200.
EVI_EOF
  INPUT_W7=$(build_flip_input "$PLAN_W7")
  W7_OUT=$(echo "$INPUT_W7" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" 2>&1)
  W7_EXIT=$?
  if [[ $W7_EXIT -eq 0 ]] && echo "$W7_OUT" | grep -q '\[wire-check\] runtime evidence'; then
    echo "self-test (w7) static-pass-plus-runtime-additive: PASS (expected)" >&2
  else
    echo "self-test (w7) static-pass-plus-runtime-additive: FAIL (expected PASS w/ runtime log)" >&2
    echo "exit=$W7_EXIT" >&2
    echo "$W7_OUT" >&2
    FAILED=1
  fi

  # Scenario (w8): Wire checks block has only 1 verifiable arrow — BLOCK
  # (Check 13 requires >= 2 backtick-path arrows; the gate enforces too
  # so a plan that bypassed Check 13 — e.g., via --no-verify — is still
  # caught at runtime).
  ROOT_W8="$TMPDIR_SELFTEST/w8"
  init_repo "$ROOT_W8"
  mkdir -p "$ROOT_W8/src/components"
  cat > "$ROOT_W8/src/components/Foo.tsx" <<'F'
fetch('/api/foo');
F
  PLAN_W8="$ROOT_W8/docs/plans/foo.md"
  write_plan_with_wire_checks "$PLAN_W8" '  - `src/components/Foo.tsx` → `/api/foo`'
  INPUT_W8=$(build_flip_input "$PLAN_W8")
  if echo "$INPUT_W8" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" > /dev/null 2>&1; then
    echo "self-test (w8) only-one-arrow-blocked: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (w8) only-one-arrow-blocked: FAIL (expected — block)" >&2
  fi

  # Scenario (w9): structured .evidence.json provides runtime evidence
  # alongside static trace PASS — both logged, flip allowed.
  ROOT_W9="$TMPDIR_SELFTEST/w9"
  init_repo "$ROOT_W9"
  mkdir -p "$ROOT_W9/src/components" "$ROOT_W9/src/lib"
  cat > "$ROOT_W9/src/components/Foo.tsx" <<'F'
fetch('/api/foo/bar');
F
  cat > "$ROOT_W9/src/lib/foo.ts" <<'F'
export function fooHandler() { return 'INSERT INTO foo_table'; }
F
  PLAN_W9="$ROOT_W9/docs/plans/foo.md"
  write_plan_with_wire_checks "$PLAN_W9" '  - `src/components/Foo.tsx` → `/api/foo/bar`
  - `src/lib/foo.ts` `fooHandler` → `INSERT INTO foo_table`'
  ARTIFACT_DIR_W9="$ROOT_W9/docs/plans/foo-evidence"
  mkdir -p "$ARTIFACT_DIR_W9"
  cat > "$ARTIFACT_DIR_W9/1.evidence.json" <<'JSON_EOF'
{
  "task_id": "1",
  "verdict": "PASS",
  "commit_sha": "abc123",
  "files_modified": ["src/components/Foo.tsx"],
  "mechanical_checks": [{"name": "playwright duplicate flow", "passed": true, "command": "npx playwright test foo.spec.ts"}],
  "runtime_evidence": [{"type": "playwright", "ref": "tests/e2e/foo.spec.ts", "outcome": "PASS"}],
  "timestamp": "2026-05-11T00:00:00Z"
}
JSON_EOF
  INPUT_W9=$(build_flip_input "$PLAN_W9")
  W9_OUT=$(echo "$INPUT_W9" | CLAUDE_TOOL_NAME=Edit bash "$SCRIPT" 2>&1)
  W9_EXIT=$?
  if [[ $W9_EXIT -eq 0 ]] && echo "$W9_OUT" | grep -q '\[wire-check\] runtime evidence'; then
    echo "self-test (w9) structured-runtime-evidence-additive: PASS (expected)" >&2
  else
    echo "self-test (w9) structured-runtime-evidence-additive: FAIL (expected PASS w/ runtime log)" >&2
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

if [[ -z "$INPUT" ]]; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // .tool_input.file_path // empty' 2>/dev/null || echo "")
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

if [[ "$FILE_PATH" != *docs/plans/* ]]; then
  exit 0
fi

if [[ "$FILE_PATH" == *-evidence.md ]]; then
  exit 0
fi

NEW_STRING=$(echo "$INPUT" | jq -r '.new_string // .tool_input.new_string // empty' 2>/dev/null || echo "")
OLD_STRING=$(echo "$INPUT" | jq -r '.old_string // .tool_input.old_string // empty' 2>/dev/null || echo "")

if [[ "$OLD_STRING" != *"- [ ]"* ]] || [[ "$NEW_STRING" != *"- [x]"* ]]; then
  exit 0
fi

FLIPPED_LINE=$(echo "$NEW_STRING" | grep -m1 '^[[:space:]]*- \[x\]' || echo "")
if [[ -z "$FLIPPED_LINE" ]]; then
  exit 0
fi

TASK_ID=$(echo "$FLIPPED_LINE" | sed -nE 's/^[[:space:]]*- \[x\][[:space:]]+([A-Z0-9]+(\.[0-9]+)*)\.?[[:space:]].*/\1/p' | head -1)
if [[ -z "$TASK_ID" ]]; then
  exit 0
fi

# Verification-level exemption: mechanical / contract tasks skip the gate.
if echo "$FLIPPED_LINE" | grep -qE 'Verification:[[:space:]]+(mechanical|contract)\b'; then
  exit 0
fi

# If the plan file doesn't exist, pass through.
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Identify repo root for static-trace path resolution. Try `git
# rev-parse --show-toplevel` from the plan file's directory; fall back
# to walking up looking for `.git`; final fallback is the plan-file's
# directory (best-effort).
PLAN_DIR=$(dirname "$FILE_PATH")
REPO_ROOT=$(cd "$PLAN_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -z "$REPO_ROOT" ]] || [[ ! -d "$REPO_ROOT" ]]; then
  # Walk up looking for .git
  probe="$PLAN_DIR"
  while [[ "$probe" != "/" ]] && [[ "$probe" != "." ]]; do
    if [[ -d "$probe/.git" ]] || [[ -f "$probe/.git" ]]; then
      REPO_ROOT="$probe"
      break
    fi
    probe=$(dirname "$probe")
  done
fi
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$PLAN_DIR"
fi

# Find the task line in the plan
PLAN_TASK_LINENO=$(grep -nE "^- \[[ xX]\][[:space:]]+${TASK_ID}\." "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1)
if [[ -z "$PLAN_TASK_LINENO" ]]; then
  exit 0
fi

# Extract task body up to next task line or `## ` heading
TASK_BODY=$(awk -v start="$PLAN_TASK_LINENO" '
  NR == start { next }
  NR > start {
    if ($0 ~ /^## /) exit
    if ($0 ~ /^- \[[ xX]\]/) exit
    print
  }
' "$FILE_PATH" 2>/dev/null)

# If no Prove-it-works sub-block in the plan, the task is non-integration.
# Silent pass — Check 13 already governs which tasks need the gate.
if ! printf '%s' "$TASK_BODY" | grep -qE '^\s*\*\*Prove it works:\*\*'; then
  exit 0
fi

# Extract Wire checks block body
WIRE_BODY=$(printf '%s\n' "$TASK_BODY" | awk '
  BEGIN { in_block = 0 }
  {
    if ($0 ~ /^[[:space:]]*\*\*Wire checks:\*\*/) { in_block = 1; next }
    if (in_block && $0 ~ /^[[:space:]]*\*\*[A-Za-z][^*]+:\*\*/) { exit }
    if (in_block) print
  }
')

if [[ -z "$(printf '%s' "$WIRE_BODY" | tr -d '[:space:]')" ]]; then
  cat >&2 <<MSG
BLOCKED: wire-check-gate

Task $TASK_ID is a Verification: full integration task but its plan
file has no '**Wire checks:**' sub-block content. The static trace
cannot proceed without a declared chain.

This should have been caught at plan-creation by plan-reviewer.sh
Check 13. Re-author the plan task with a Wire checks block (or use
the 'n/a — <reason>' carve-out for tasks with no code chain).

See ~/.claude/rules/planning.md "Integration Verification".
MSG
  exit 1
fi

# Check carve-out path: `- n/a — <reason >= 30 chars>`
CARVEOUT_LINE=$(printf '%s' "$WIRE_BODY" | grep -iE '^[[:space:]]*-[[:space:]]+n/a[[:space:]]+(—|--)' | head -1)
if [[ -n "$CARVEOUT_LINE" ]]; then
  CARVEOUT_REASON=$(printf '%s' "$CARVEOUT_LINE" | sed -E 's/^[[:space:]]*-[[:space:]]+n\/a[[:space:]]+(—|--)[[:space:]]*//')
  CARVEOUT_NON_WS=$(printf '%s' "$CARVEOUT_REASON" | tr -d '[:space:]' | wc -c | tr -cd '[:digit:]')
  CARVEOUT_NON_WS=${CARVEOUT_NON_WS:-0}
  if [[ $CARVEOUT_NON_WS -ge 30 ]]; then
    echo "[wire-check] static trace skipped via carve-out: $(printf '%s' "$CARVEOUT_REASON" | head -c 100)" >&2
    # Look for additive runtime evidence even with carve-out (logged but not required)
    EVIDENCE_FILE="${FILE_PATH%.md}-evidence.md"
    if [[ -f "$EVIDENCE_FILE" ]]; then
      RUNTIME_BLOCK=$(grep -E '^(Wire check executed:|Prove-it-works run:)' "$EVIDENCE_FILE" 2>/dev/null | head -1)
      [[ -n "$RUNTIME_BLOCK" ]] && echo "[wire-check] runtime evidence (additive): $EVIDENCE_FILE" >&2
    fi
    exit 0
  fi
  # Carve-out present but reason too short — block
  cat >&2 <<MSG
BLOCKED: wire-check-gate

Task $TASK_ID has a Wire checks carve-out 'n/a — <reason>' but the
reason is only $CARVEOUT_NON_WS chars; need >= 30 chars substantive
justification of why no UI→DB code chain applies to this task.

This should have been caught at plan-creation by plan-reviewer.sh
Check 13. Lengthen the carve-out reason or replace it with real
arrow links.
MSG
  exit 1
fi

# ============================================================
# Run static trace
# ============================================================

VERIFIED_COUNT=0
BROKEN_DETAILS=""
UNVERIFIABLE_COUNT=0

# Process each arrow line
while IFS= read -r arrow_line; do
  # Must contain an arrow
  if ! printf '%s' "$arrow_line" | grep -qE '(→|->)'; then
    continue
  fi

  # Extract all backtick-quoted tokens
  TOKENS=$(printf '%s' "$arrow_line" | grep -oE '`[^`]+`' | sed 's/^`//; s/`$//')

  # Classify tokens
  FILE_TOKENS=()
  NONFILE_TOKENS=()
  MISSING_FILES=""

  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    # Strip ":functionName" suffix if present (e.g., src/foo.ts:bar)
    bare_path="${tok%%:*}"
    # Classify:
    #   - Starts with '/' → API route or absolute path; treat as non-file
    #     (these are grep-checked in the linked component file)
    #   - Contains '/' and file exists relative to REPO_ROOT → file token
    #   - Contains '/' but file does NOT exist → MISSING file (broken link)
    #   - No '/' → non-file identifier (function name, SQL fragment, etc.)
    if [[ "${bare_path:0:1}" == "/" ]]; then
      # API route or absolute URL path — non-file token
      NONFILE_TOKENS+=("$tok")
    elif [[ "$bare_path" == *"/"* ]]; then
      if [[ -f "$REPO_ROOT/$bare_path" ]]; then
        FILE_TOKENS+=("$bare_path")
        # If the token had a `:identifier` suffix, treat that identifier as
        # a non-file token to verify in the SAME file.
        if [[ "$tok" == *":"* ]]; then
          ident="${tok##*:}"
          [[ -n "$ident" ]] && NONFILE_TOKENS+=("$ident")
        fi
      else
        MISSING_FILES+="$bare_path "
      fi
    else
      NONFILE_TOKENS+=("$tok")
    fi
  done <<< "$TOKENS"

  # If any backtick-quoted path was claimed but missing → BROKEN
  if [[ -n "$MISSING_FILES" ]]; then
    BROKEN_DETAILS+="    Arrow: $(echo "$arrow_line" | sed -E 's/^[[:space:]]+//' | head -c 140)"$'\n'
    BROKEN_DETAILS+="      Missing files (relative to $REPO_ROOT): $(echo "$MISSING_FILES" | tr -s ' ')"$'\n'
    continue
  fi

  # No file path at all → unverifiable
  if [[ ${#FILE_TOKENS[@]} -eq 0 ]]; then
    UNVERIFIABLE_COUNT=$((UNVERIFIABLE_COUNT + 1))
    continue
  fi

  # For each non-file token, verify it appears in at least one of the
  # file paths in this arrow (grep -F, case-sensitive — the planner
  # quoted the exact identifier expected in the code).
  ARROW_BROKEN=0
  UNRESOLVED_TOKENS=""
  for tok in "${NONFILE_TOKENS[@]:-}"; do
    [[ -z "$tok" ]] && continue
    found_in=""
    for fp in "${FILE_TOKENS[@]}"; do
      if grep -F -q -- "$tok" "$REPO_ROOT/$fp" 2>/dev/null; then
        found_in="$fp"
        break
      fi
    done
    if [[ -z "$found_in" ]]; then
      UNRESOLVED_TOKENS+="\`$tok\` "
      ARROW_BROKEN=1
    fi
  done

  if [[ $ARROW_BROKEN -eq 1 ]]; then
    BROKEN_DETAILS+="    Arrow: $(echo "$arrow_line" | sed -E 's/^[[:space:]]+//' | head -c 140)"$'\n'
    BROKEN_DETAILS+="      Unresolved tokens (not found in $(printf '%s ' "${FILE_TOKENS[@]}")): $UNRESOLVED_TOKENS"$'\n'
    continue
  fi

  VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
done <<< "$WIRE_BODY"

# Decision
if [[ -n "$BROKEN_DETAILS" ]]; then
  cat >&2 <<MSG
BLOCKED: wire-check-gate (static trace failed)

Task $TASK_ID declares a code chain that no longer holds. The
static trace caught at least one broken link — either a file the
plan references does not exist relative to repo root '$REPO_ROOT',
or an identifier the plan claims is in a file is missing from
that file (renamed function? moved endpoint? deleted import?).

Broken arrows:
$BROKEN_DETAILS
Repair the chain (rename / restore / re-import the missing token)
or update the Wire checks block to reflect the new code shape, then
re-attempt the checkbox flip.

Static trace is the mandatory baseline — it runs on every task
completion regardless of whether a running instance was available.
Runtime evidence (executed Prove-it-works scenario) is additive when
present.

See ~/.claude/rules/planning.md "Integration Verification".
MSG
  exit 1
fi

if [[ $VERIFIED_COUNT -lt 2 ]]; then
  cat >&2 <<MSG
BLOCKED: wire-check-gate

Task $TASK_ID's Wire checks block produced only $VERIFIED_COUNT
verified arrow(s); need >= 2 for the static-trace gate. An arrow
is verified when it contains at least one backtick-quoted file
path that exists AND all other backtick-quoted tokens in the same
arrow appear in at least one of the linked files.

Total arrows found: $((VERIFIED_COUNT + UNVERIFIABLE_COUNT))
  Verified: $VERIFIED_COUNT
  Unverifiable (no file path): $UNVERIFIABLE_COUNT

Add more arrows with backtick-quoted file paths, OR (if no chain
exists for this task) use the canonical carve-out in Wire checks:
  - n/a — <reason ≥ 30 chars>

See ~/.claude/rules/planning.md "Integration Verification".
MSG
  exit 1
fi

# Static trace PASS — log and check for additive runtime evidence
echo "[wire-check] static trace PASS — $VERIFIED_COUNT arrow(s) verified" >&2

EVIDENCE_FILE="${FILE_PATH%.md}-evidence.md"
PLAN_SLUG=$(basename "$FILE_PATH" .md)
ARTIFACT_PATH="${PLAN_DIR}/${PLAN_SLUG}-evidence/${TASK_ID}.evidence.json"

if [[ -f "$EVIDENCE_FILE" ]]; then
  TASK_SECTION=$(awk -v id="$TASK_ID" '
    /^Task ID:/ {
      if (in_section) exit
      if ($0 ~ "Task ID:[[:space:]]*" id "[[:space:]]*$") { in_section = 1 }
    }
    in_section { print }
  ' "$EVIDENCE_FILE" 2>/dev/null)

  if printf '%s' "$TASK_SECTION" | grep -qE '^(Wire check executed:|Prove-it-works run:)'; then
    echo "[wire-check] runtime evidence (additive): $EVIDENCE_FILE" >&2
  fi
fi

if [[ -f "$ARTIFACT_PATH" ]]; then
  RUNTIME_EV=$(jq -r '(.runtime_evidence // []) | length' "$ARTIFACT_PATH" 2>/dev/null || echo "0")
  PASSED_CK=$(jq -r '[(.mechanical_checks // [])[] | select(.passed == true)] | length' "$ARTIFACT_PATH" 2>/dev/null || echo "0")
  if [[ "$RUNTIME_EV" =~ ^[0-9]+$ ]] && [[ $RUNTIME_EV -ge 1 ]] && \
     [[ "$PASSED_CK" =~ ^[0-9]+$ ]] && [[ $PASSED_CK -ge 1 ]]; then
    echo "[wire-check] runtime evidence (additive): $ARTIFACT_PATH ($RUNTIME_EV runtime entries, $PASSED_CK passing checks)" >&2
  fi
fi

exit 0
