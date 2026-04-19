#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# orchestrate.sh — Multi-Agent Autonomous Pipeline for Claude Code
#
# Architecture:
#   Orchestrator (this script) → Builder Agent → Verifier Agent
#   Builder stages code + writes evidence. CANNOT commit.
#   Verifier runs real verification. CANNOT commit.
#   Orchestrator owns ALL commits after verifier PASS + gate checks.
#
# Usage:
#   ./orchestrate.sh "feature description"
#   ./orchestrate.sh --file feature-spec.md
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_RETRIES=3
DEV_SERVER_URL="${DEV_SERVER_URL:-http://localhost:3000}"
LOG_DIR="$SCRIPT_DIR/.claude/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROMPTS_DIR="$SCRIPT_DIR/.claude/pipeline-prompts"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

mkdir -p "$LOG_DIR" "$PROMPTS_DIR"

# ── Input ──
if [ $# -eq 0 ]; then
  echo -e "${RED}Usage: ./orchestrate.sh \"feature description\"${NC}"
  echo -e "       ./orchestrate.sh --file feature-spec.md"
  exit 1
fi

if [ "$1" = "--file" ] && [ -n "${2:-}" ]; then
  FEATURE_DESC=$(cat "$2")
else
  FEATURE_DESC="$*"
fi

echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Claude Code Multi-Agent Pipeline${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Feature:${NC} $FEATURE_DESC"
echo ""

# ── Preflight ──
echo -e "${YELLOW}Preflight checks...${NC}"

if ! command -v claude &> /dev/null; then
  echo -e "${RED}ERROR: 'claude' CLI not found.${NC}"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo -e "${RED}ERROR: 'jq' not found. Install with: winget install jqlang.jq${NC}"
  exit 1
fi

if ! curl -sf "$DEV_SERVER_URL" > /dev/null 2>&1; then
  echo -e "${YELLOW}WARNING: Dev server not responding at $DEV_SERVER_URL. UI verification may fail.${NC}"
else
  echo -e "${GREEN}Dev server responding at $DEV_SERVER_URL${NC}"
fi

if [ -n "$(git status --porcelain)" ]; then
  echo -e "${YELLOW}WARNING: Working directory not clean. Stashing untracked files.${NC}"
  git status --short
  git stash --include-untracked > /dev/null 2>&1 || true
  echo ""
fi

echo -e "${GREEN}Preflight done.${NC}"
echo ""

# ═══════════════════════════════════════════════════
# PHASE 1: DECOMPOSITION
# ═══════════════════════════════════════════════════
echo -e "${BOLD}═══ Phase 1: Task Decomposition ═══${NC}"

cat > "$PROMPTS_DIR/decompose.txt" << 'DECOMPOSE_EOF'
You are a task decomposition agent for the project under development (typically a Next.js / Supabase / Trigger.dev application).

Given this feature request, decompose it into the SMALLEST independently-verifiable tasks.

Rules:
1. Each task changes either backend OR frontend, never both (unless <20 lines total)
2. Backend tasks come before frontend tasks that depend on them
3. Database migrations come before API endpoints that use them
4. Each task has a CONCRETE verification — an exact command, not "check that it works"
5. Each task identifies impact on existing data (orgs/users created before this feature)
6. Do NOT include files_likely_touched — touched files are determined after implementation

Output ONLY valid JSON array, no markdown, no explanation:
[
  {
    "id": 1,
    "task": "Clear description of what to build",
    "verification": {
      "type": "api|ui|db_query|unit_test",
      "command": "exact shell command to verify",
      "expected": "what success looks like",
      "selector": "CSS selector if UI verification (optional)"
    },
    "existing_data_impact": "What existing orgs/data need — or 'none'"
  }
]
DECOMPOSE_EOF

echo "$FEATURE_DESC" >> "$PROMPTS_DIR/decompose.txt"

# Run decomposition
claude -p "$(cat "$PROMPTS_DIR/decompose.txt")" 2>/dev/null > /tmp/pipeline-raw.txt

# Extract JSON from the response (may have surrounding text)
if ! python3 -c "
import json, re, sys
text = open('/tmp/pipeline-raw.txt').read()
match = re.search(r'\[[\s\S]*\]', text)
if match:
    data = json.loads(match.group())
    json.dump(data, sys.stdout, indent=2)
else:
    sys.exit(1)
" > /tmp/pipeline-tasks.json 2>/dev/null; then
  echo -e "${RED}ERROR: Failed to parse task JSON from decomposition.${NC}"
  echo "Raw output:"
  cat /tmp/pipeline-raw.txt
  exit 1
fi

TASK_COUNT=$(jq length /tmp/pipeline-tasks.json)
echo -e "${GREEN}Decomposed into ${BOLD}$TASK_COUNT${NC}${GREEN} tasks:${NC}"
echo ""

for i in $(seq 0 $((TASK_COUNT - 1))); do
  TASK_DESC=$(jq -r ".[$i].task" /tmp/pipeline-tasks.json)
  VERIFY_TYPE=$(jq -r ".[$i].verification.type" /tmp/pipeline-tasks.json)
  echo -e "  ${CYAN}[$((i+1))]${NC} $TASK_DESC ${YELLOW}(verify: $VERIFY_TYPE)${NC}"
done
echo ""

# ═══════════════════════════════════════════════════
# PHASE 2: BUILD → VERIFY LOOP
# ═══════════════════════════════════════════════════
echo -e "${BOLD}═══ Phase 2: Build → Verify Pipeline ═══${NC}"
echo ""

COMPLETED=0
FAILED_TASKS=()

for i in $(seq 0 $((TASK_COUNT - 1))); do
  TASK=$(jq -r ".[$i]" /tmp/pipeline-tasks.json)
  TASK_DESC=$(echo "$TASK" | jq -r '.task')
  VERIFY_TYPE=$(echo "$TASK" | jq -r '.verification.type')
  VERIFY_CMD=$(echo "$TASK" | jq -r '.verification.command')
  VERIFY_EXPECT=$(echo "$TASK" | jq -r '.verification.expected')
  VERIFY_SELECTOR=$(echo "$TASK" | jq -r '.verification.selector // empty')
  EXISTING_CHECK=$(echo "$TASK" | jq -r '.existing_data_impact')
  TASK_LOG="$LOG_DIR/task-$((i+1))-$TIMESTAMP.log"

  echo -e "${BOLD}═══ Task $((i+1))/$TASK_COUNT ═══${NC}"
  echo -e "${CYAN}$TASK_DESC${NC}"
  echo -e "  Verify: $VERIFY_TYPE → $VERIFY_CMD"
  echo -e "  Existing data: $EXISTING_CHECK"
  echo ""

  ATTEMPT=0
  PASSED=false
  rm -f /tmp/pipeline-feedback.txt

  while [ $ATTEMPT -lt $MAX_RETRIES ] && [ "$PASSED" = false ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo -e "  ${YELLOW}Attempt $ATTEMPT/$MAX_RETRIES${NC}"

    # ── BUILDER PHASE ──
    echo -e "  ${CYAN}[Builder]${NC} Implementing..."

    FEEDBACK=$(cat /tmp/pipeline-feedback.txt 2>/dev/null || echo "None — first attempt")

    cat > "$PROMPTS_DIR/builder.txt" << BUILDER_EOF
You are the BUILDER agent in an autonomous pipeline. You implement code changes and stage them. You CANNOT commit — the orchestrator script commits after a separate verifier approves.

## Your Task
$TASK_DESC

## Existing Data Impact
$EXISTING_CHECK
Handle this explicitly — existing rows MUST have defaults or NULL handling.

## Verification That Will Run Against Your Work
Type: $VERIFY_TYPE
Command: $VERIFY_CMD
Expected: $VERIFY_EXPECT

## Previous Attempt Feedback
$FEEDBACK

## Required Steps
1. Implement the task completely — trace every data path from source to render
2. Stage ALL changed files: git add <files>
3. Write evidence to .claude/evidence.md:

### Files Changed
- file.ts: what changed and why

### Data Flow
[DB column] → [API endpoint field] → [component prop] → [JSX expression]

### Existing Data
[Query ran] → [Result] → [How code handles NULL/missing]

### Pre-Mortem
Most likely failure: ___
Second most likely: ___

## Rules
- Do NOT run git commit
- Do NOT skip the evidence file
- If uncertain about data shape, run curl/query BEFORE writing code
- For UI elements behind conditions, verify the condition is satisfiable
BUILDER_EOF

    claude -p "$(cat "$PROMPTS_DIR/builder.txt")" >> "$TASK_LOG" 2>&1

    echo -e "  ${CYAN}[Builder]${NC} Done. Running orchestrator gates..."

    # ═══ ORCHESTRATOR GATES (mechanical, no LLM) ═══

    GATE_FAILED=false
    GATE_WARNINGS=""

    # Gate 1: Evidence file exists and isn't empty
    if [ ! -s .claude/evidence.md ]; then
      echo -e "  ${RED}[Gate 1]${NC} FAIL: No evidence file written"
      echo "FAIL: You did not write .claude/evidence.md. This is required. Write it documenting your data flow, existing data handling, and pre-mortem." > /tmp/pipeline-feedback.txt
      GATE_FAILED=true
    else
      echo -e "  ${GREEN}[Gate 1]${NC} Evidence file exists"
    fi

    # Gate 2: Something was actually staged
    if [ "$GATE_FAILED" = false ]; then
      STAGED=$(git diff --cached --name-only)
      if [ -z "$STAGED" ]; then
        echo -e "  ${RED}[Gate 2]${NC} FAIL: No files staged"
        echo "FAIL: You did not stage any files with git add. Stage your changes." > /tmp/pipeline-feedback.txt
        GATE_FAILED=true
      else
        STAGED_COUNT=$(echo "$STAGED" | wc -l)
        echo -e "  ${GREEN}[Gate 2]${NC} $STAGED_COUNT file(s) staged"
      fi
    fi

    # Gate 3: No unstaged modifications (forgot to add a file)
    if [ "$GATE_FAILED" = false ]; then
      UNSTAGED=$(git diff --name-only)
      if [ -n "$UNSTAGED" ]; then
        echo -e "  ${RED}[Gate 3]${NC} FAIL: Modified but unstaged files: $UNSTAGED"
        echo "FAIL: You modified these files but forgot to stage them: $UNSTAGED. Run git add on all changed files." > /tmp/pipeline-feedback.txt
        GATE_FAILED=true
      else
        echo -e "  ${GREEN}[Gate 3]${NC} No unstaged modifications"
      fi
    fi

    # Gate 4: TypeScript compiles
    if [ "$GATE_FAILED" = false ]; then
      if ! npx tsc --noEmit > /tmp/tsc-output.txt 2>&1; then
        echo -e "  ${RED}[Gate 4]${NC} FAIL: TypeScript errors"
        cat /tmp/tsc-output.txt | head -10
        echo "FAIL: TypeScript compilation errors. Fix them:\n$(cat /tmp/tsc-output.txt | head -20)" > /tmp/pipeline-feedback.txt
        git reset HEAD . > /dev/null 2>&1
        GATE_FAILED=true
      else
        echo -e "  ${GREEN}[Gate 4]${NC} TypeScript compiles"
      fi
    fi

    # Gate 5: No secrets staged
    if [ "$GATE_FAILED" = false ]; then
      if git diff --cached --name-only | grep -qE '\.env|credentials|secrets|\.key$|\.pem$'; then
        echo -e "  ${RED}[Gate 5]${NC} FAIL: Sensitive file staged"
        echo "FAIL: You staged a sensitive file (.env, credentials, etc). Remove it from staging." > /tmp/pipeline-feedback.txt
        git reset HEAD . > /dev/null 2>&1
        GATE_FAILED=true
      else
        echo -e "  ${GREEN}[Gate 5]${NC} No secrets staged"
      fi
    fi

    # Gate 6: Every staged file mentioned in evidence (soft warning)
    if [ "$GATE_FAILED" = false ]; then
      EVIDENCE_CONTENT=$(cat .claude/evidence.md 2>/dev/null)
      UNMENTIONED=""
      while IFS= read -r f; do
        BASENAME=$(basename "$f")
        if ! echo "$EVIDENCE_CONTENT" | grep -q "$BASENAME"; then
          UNMENTIONED="$UNMENTIONED $f"
        fi
      done <<< "$STAGED"
      if [ -n "$UNMENTIONED" ]; then
        echo -e "  ${YELLOW}[Gate 6]${NC} WARNING: Files staged but not in evidence:$UNMENTIONED"
        GATE_WARNINGS="$GATE_WARNINGS\nWARNING: These staged files are not mentioned in evidence.md:$UNMENTIONED"
      else
        echo -e "  ${GREEN}[Gate 6]${NC} All staged files documented in evidence"
      fi
    fi

    # Gate 7: New imports reference existing files (soft warning)
    if [ "$GATE_FAILED" = false ]; then
      IMPORT_WARNINGS=""
      while IFS= read -r line; do
        SOURCE=$(echo "$line" | sed "s/.*from ['\"]\\(.*\\)['\"].*/\\1/" | sed 's/@\//src\//')
        if [ -n "$SOURCE" ] && [[ "$SOURCE" != http* ]] && [[ "$SOURCE" != @* ]]; then
          # Check if file exists (try .ts, .tsx, /index.ts, /index.tsx)
          FOUND=false
          for ext in "" ".ts" ".tsx" "/index.ts" "/index.tsx"; do
            if [ -f "${SOURCE}${ext}" ]; then FOUND=true; break; fi
          done
          if [ "$FOUND" = false ]; then
            IMPORT_WARNINGS="$IMPORT_WARNINGS\n  $SOURCE"
          fi
        fi
      done < <(git diff --cached -U0 | grep "^+.*import.*from" | grep -v "^+++" || true)
      if [ -n "$IMPORT_WARNINGS" ]; then
        echo -e "  ${YELLOW}[Gate 7]${NC} WARNING: Possibly broken imports:$IMPORT_WARNINGS"
        GATE_WARNINGS="$GATE_WARNINGS\nWARNING: These imports may reference non-existent files:$IMPORT_WARNINGS"
      else
        echo -e "  ${GREEN}[Gate 7]${NC} Import chain looks valid"
      fi
    fi

    # If hard gate failed, reset and retry
    if [ "$GATE_FAILED" = true ]; then
      git reset HEAD . > /dev/null 2>&1
      git checkout -- . > /dev/null 2>&1
      echo ""
      continue
    fi

    # ── VERIFIER PHASE ──
    echo -e "  ${CYAN}[Verifier]${NC} Reviewing and verifying..."

    DIFF=$(git diff --cached)
    EVIDENCE=$(cat .claude/evidence.md 2>/dev/null)

    cat > "$PROMPTS_DIR/verifier.txt" << VERIFIER_EOF
You are the VERIFIER agent. You are adversarial — your purpose is to catch incomplete or broken implementations BEFORE they are committed. You CANNOT commit or modify code. You ONLY output PASS or FAIL.

## Original Task
$TASK_DESC

## Existing Data Impact
$EXISTING_CHECK

## Orchestrator Gate Warnings
$GATE_WARNINGS

## Staged Diff
\`\`\`
$DIFF
\`\`\`

## Builder's Evidence
$EVIDENCE

## Mandatory Verification Steps

### Step 1: Run the specified verification
Command: $VERIFY_CMD
Expected: $VERIFY_EXPECT
Run it now. If it fails, output FAIL immediately.

### Step 2: Data path trace
For EVERY new variable/prop in JSX in the diff:
- Confirm the API returns that field (run curl if needed)
- Confirm the component receives it as a prop
- Confirm conditional rendering is satisfiable with real data

### Step 3: Existing data check
$EXISTING_CHECK
If not 'none', run a query or API call to confirm existing records work.

### Step 4: UI visibility (if applicable)
Selector: $VERIFY_SELECTOR
If provided and dev server is running, run:
  node scripts/verify-ui.mjs $DEV_SERVER_URL/[page] '$VERIFY_SELECTOR'

### Step 5: Pre-mortem review
Read the builder's pre-mortem. Is there a MORE likely failure they missed?

## Output
EXACTLY one of:

PASS: [one sentence what was verified]
COMMIT_MSG: [commit message for the orchestrator to use]

OR

FAIL:
- [Problem 1: what's broken and what the fix is]
- [Problem 2: ...]
VERIFIER_EOF

    VERIFIER_OUTPUT=$(claude -p "$(cat "$PROMPTS_DIR/verifier.txt")" 2>&1 | tee -a "$TASK_LOG")

    # Parse verifier output
    if echo "$VERIFIER_OUTPUT" | grep -q "^PASS:"; then
      COMMIT_MSG=$(echo "$VERIFIER_OUTPUT" | grep "^COMMIT_MSG:" | sed 's/^COMMIT_MSG: //' || echo "feat: $TASK_DESC")

      # ═══ ORCHESTRATOR COMMITS (the only entity that can) ═══
      git commit -m "$COMMIT_MSG

Co-Authored-By: Claude Code Pipeline <noreply@anthropic.com>" > /dev/null 2>&1

      echo -e "  ${GREEN}✅ Verified and committed${NC}"
      echo -e "  ${GREEN}   $COMMIT_MSG${NC}"
      PASSED=true
      COMPLETED=$((COMPLETED + 1))
      rm -f /tmp/pipeline-feedback.txt .claude/evidence.md

    else
      echo -e "  ${RED}❌ Failed verification${NC}"
      echo "$VERIFIER_OUTPUT" | grep -A 20 "FAIL" | head -15 > /tmp/pipeline-feedback.txt
      echo ""
      cat /tmp/pipeline-feedback.txt | sed 's/^/    /'
      echo ""

      # Reset for retry
      git reset HEAD . > /dev/null 2>&1
      git checkout -- . > /dev/null 2>&1
    fi
  done

  if [ "$PASSED" = false ]; then
    echo -e "  ${RED}🛑 Task failed after $MAX_RETRIES attempts.${NC}"
    FAILED_TASKS+=("Task $((i+1)): $TASK_DESC")
    echo ""
    echo -e "${YELLOW}Skip this task and continue? (y/N)${NC}"
    read -p "  " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      break
    fi
    git reset HEAD . > /dev/null 2>&1
    git checkout -- . > /dev/null 2>&1
  fi

  echo ""
done

# ═══════════════════════════════════════════════════
# PHASE 3: SUMMARY
# ═══════════════════════════════════════════════════
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Pipeline Complete${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Completed:${NC} $COMPLETED/$TASK_COUNT tasks"

if [ ${#FAILED_TASKS[@]} -gt 0 ]; then
  echo -e "  ${RED}Failed:${NC}"
  for ft in "${FAILED_TASKS[@]}"; do
    echo -e "    - $ft"
  done
fi

echo ""
echo -e "  ${CYAN}Logs:${NC} $LOG_DIR/"
echo -e "  ${CYAN}Commits:${NC}"
git log --oneline -"$COMPLETED" 2>/dev/null | sed 's/^/    /'
echo ""
