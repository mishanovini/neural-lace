#!/bin/bash
# goal-extraction-on-prompt.sh — UserPromptSubmit hook (A1 — Generation 6 mechanism)
#
# Fires on every user prompt. Detects the FIRST user message of a session by
# checking whether `.claude/state/user-goals/<session-id>.json` already exists.
# On the first message, deterministically extracts imperative verbs from the
# user's verbatim text and writes them — together with a SHA-256 of the raw
# message — to the goal file. The agent never edits this file; tampering is
# detected by goal-coverage-on-stop.sh, which re-derives the SHA from the
# JSONL transcript and compares.
#
# WHY THIS EXISTS
# ===============
# A5 (deferral-counter) catches the agent leaking deferral phrases into the
# transcript and forces them into the user-visible final message. A3
# (transcript-lie-detector) catches self-contradictions within session. A7
# (imperative-evidence-linker) catches strong imperatives in user messages
# without matching tool-call evidence. NONE of them anchor on a single
# immutable artifact at session start that records "what the user actually
# asked for in their first message" — the highest-signal moment in the
# session.
#
# A1 closes that gap. It captures the user's first message verbatim (via
# SHA-256) and an extracted goal list at the moment of submission. The
# extraction is deterministic regex (no LLM call in v1) so the file is
# reproducible. The agent cannot rewrite history once the file exists; the
# goal-coverage Stop hook reads it + the tool-call ledger and produces a
# coverage section the agent must paste verbatim into its final message.
#
# DESIGN
# ======
# 1. Read JSON input from stdin (Claude Code passes `{prompt, session_id, ...}`).
# 2. Resolve session_id; pick a goal file path under
#    `.claude/state/user-goals/<session-id>.json` relative to PWD (project root).
# 3. If the goal file already exists, this is NOT the first user message; exit 0.
# 4. Extract goals with deterministic regex from the user's verbatim text.
# 5. Compute SHA-256 of the raw text.
# 6. Write the goal file as JSON: {session_id, first_message_text_sha256,
#    extracted_at, goals: [{verb, context, raw_clause}, ...]}.
# 7. Exit 0 (UserPromptSubmit hooks should never block — this is observation
#    only).
#
# Action verbs we extract (matched as regex word-boundary):
#   test, run, fix, build, implement, deploy, verify, check, validate,
#   loop, iterate, find, review, ship, merge, continue
#
# Strong-imperative triggers (lowest acceptance threshold):
#   must, need to, have to, required to, please
#
# A "goal" is one matching verb + ~15 chars of trailing object context. The
# raw_clause field stores the verb and what immediately follows so the
# coverage hook can correlate.
#
# ESCAPE HATCH
# ============
# GOAL_EXTRACTION_DISABLE=1 in env makes the hook a no-op (mirrors the other
# adversarial hooks). Used during harness-development sessions where editing
# the verb list itself would self-trigger.
#
# Reads-only operations from the agent side:
# - The agent CANNOT edit this file via Edit/Write because plan-edit-validator
#   et al. only restrict plan files; however, integrity is enforced by the
#   sibling Stop hook re-deriving the SHA from the JSONL transcript (which the
#   agent cannot edit). If the SHA differs from what's in the file, the file
#   was tampered.

set -u

# ============================================================
# --self-test: run the hook against the fixture
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" = "--self-test" ]]; then
  FIXTURE_DIR=""
  for candidate in \
    "$SCRIPT_DIR/../tests/goal-extraction" \
    "$HOME/claude-projects/neural-lace/adapters/claude-code/tests/goal-extraction" \
    "$HOME/.claude/tests/goal-extraction"; do
    if [[ -d "$candidate" ]]; then
      FIXTURE_DIR="$candidate"
      break
    fi
  done
  if [[ -z "$FIXTURE_DIR" ]]; then
    echo "ERROR: cannot find goal-extraction fixture directory" >&2
    exit 2
  fi

  PASS=0
  FAIL=0

  # Test 1: extract from fixture-first-message.txt and compare against
  # fixture-extracted-goals.json (verb list match — extracted_at and SHA
  # are time/content-keyed so we compare structure only).
  TMP_OUT=$(mktemp /tmp/a1-self-test.XXXXXX)
  TMP_STATE=$(mktemp -d /tmp/a1-state.XXXXXX)
  trap "rm -f $TMP_OUT; rm -rf $TMP_STATE" EXIT

  # Synthesize stdin JSON for the hook
  FIRST_MSG=$(cat "$FIXTURE_DIR/fixture-first-message.txt")
  STDIN_JSON=$(jq -n \
    --arg p "$FIRST_MSG" \
    --arg sid "self-test-session-id-001" \
    --arg cwd "$TMP_STATE" \
    '{prompt: $p, session_id: $sid, cwd: $cwd}')

  # Run hook
  echo "$STDIN_JSON" | bash "${BASH_SOURCE[0]}" > "$TMP_OUT" 2>&1
  hook_exit=$?

  GOAL_FILE="$TMP_STATE/.claude/state/user-goals/self-test-session-id-001.json"
  if [[ "$hook_exit" -eq 0 ]] && [[ -f "$GOAL_FILE" ]]; then
    # Verify shape: required keys + at least 4 extracted goals
    GOAL_COUNT=$(jq '.goals | length' "$GOAL_FILE" 2>/dev/null || echo 0)
    HAS_SHA=$(jq -r '.first_message_text_sha256 // ""' "$GOAL_FILE" 2>/dev/null)
    HAS_SID=$(jq -r '.session_id // ""' "$GOAL_FILE" 2>/dev/null)
    EXPECTED_GOALS=$(jq '.goals | length' "$FIXTURE_DIR/fixture-extracted-goals.json" 2>/dev/null || echo 0)

    if [[ "$GOAL_COUNT" -ge "$EXPECTED_GOALS" ]] && [[ -n "$HAS_SHA" ]] && [[ "$HAS_SID" = "self-test-session-id-001" ]]; then
      # Verify each expected verb appears in extracted goals
      # Strip CR (Git Bash on Windows emits CRLF from sort -u) before comparing
      EXPECTED_VERBS=$(jq -r '.goals[].verb' "$FIXTURE_DIR/fixture-extracted-goals.json" | sort -u | LC_ALL=C tr -d '\r')
      ACTUAL_VERBS=$(jq -r '.goals[].verb' "$GOAL_FILE" | sort -u | LC_ALL=C tr -d '\r')
      MISSING=""
      for v in $EXPECTED_VERBS; do
        if ! echo "$ACTUAL_VERBS" | LC_ALL=C grep -F -q -x "$v"; then
          MISSING="$MISSING $v"
        fi
      done
      if [[ -z "$MISSING" ]]; then
        echo "PASS  extract-first-message-produces-expected-goals (extracted $GOAL_COUNT goals, all expected verbs present)"
        PASS=$((PASS+1))
      else
        echo "FAIL  extract-first-message-produces-expected-goals (missing verbs:$MISSING)"
        FAIL=$((FAIL+1))
      fi
    else
      echo "FAIL  extract-first-message-produces-expected-goals (shape wrong: count=$GOAL_COUNT sha=$HAS_SHA sid=$HAS_SID)"
      FAIL=$((FAIL+1))
    fi
  else
    echo "FAIL  extract-first-message-produces-expected-goals (hook exit=$hook_exit, goal file missing)"
    FAIL=$((FAIL+1))
  fi

  # Test 2: second invocation with existing goal file should be a no-op
  # (no rewrite); verify the file mtime/content is unchanged.
  if [[ -f "$GOAL_FILE" ]]; then
    BEFORE=$(sha256sum "$GOAL_FILE" | awk '{print $1}')
    DIFF_MSG="A totally different message that should not change anything."
    STDIN_JSON2=$(jq -n \
      --arg p "$DIFF_MSG" \
      --arg sid "self-test-session-id-001" \
      --arg cwd "$TMP_STATE" \
      '{prompt: $p, session_id: $sid, cwd: $cwd}')
    echo "$STDIN_JSON2" | bash "${BASH_SOURCE[0]}" > /dev/null 2>&1
    AFTER=$(sha256sum "$GOAL_FILE" | awk '{print $1}')
    if [[ "$BEFORE" = "$AFTER" ]]; then
      echo "PASS  second-invocation-is-noop (goal file unchanged)"
      PASS=$((PASS+1))
    else
      echo "FAIL  second-invocation-is-noop (goal file was rewritten)"
      FAIL=$((FAIL+1))
    fi
  fi

  echo ""
  echo "Result: $PASS passed, $FAIL failed"
  if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
  exit 0
fi

# ============================================================
# Normal path — read stdin and run the extraction
# ============================================================
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi

# Without a payload, this is a no-op.
if [[ -z "$INPUT" ]]; then
  exit 0
fi

# Need jq for parsing. Without it, no-op.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Need sha256sum for the integrity hash. Without it, no-op.
if ! command -v sha256sum >/dev/null 2>&1; then
  exit 0
fi

# Escape hatch
if [[ "${GOAL_EXTRACTION_DISABLE:-0}" = "1" ]]; then
  exit 0
fi

PROMPT=$(echo "$INPUT" | jq -r '.prompt // .user_prompt // .message // empty' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .session.id // empty' 2>/dev/null || echo "")
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

if [[ -z "$PROMPT" ]] || [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

# Resolve the project root for the goal-state directory.
# Priority: cwd from input -> $PWD.
if [[ -z "$CWD" ]] || [[ ! -d "$CWD" ]]; then
  CWD="$PWD"
fi

GOAL_DIR="$CWD/.claude/state/user-goals"
GOAL_FILE="$GOAL_DIR/$SESSION_ID.json"

# If the goal file already exists, this is NOT the first user message — exit.
if [[ -f "$GOAL_FILE" ]]; then
  exit 0
fi

mkdir -p "$GOAL_DIR" 2>/dev/null || exit 0

# ============================================================
# Compute SHA-256 of the raw user prompt
# ============================================================
SHA=$(printf '%s' "$PROMPT" | sha256sum | awk '{print $1}')

# ============================================================
# Deterministic regex extraction
#
# We look for two classes of triggers:
# 1. Strong imperatives (must, need to, have to, required to, please)
#    followed within a small window by an action verb.
# 2. Bare action verbs at clause boundaries.
#
# Action verbs: test, run, fix, build, implement, deploy, verify, check,
#   validate, loop, iterate, find, review, ship, merge, continue.
#
# For each match we capture:
#   - verb (lowercased)
#   - context (~15 chars after the verb, trimmed at clause boundary)
#   - raw_clause (verb + context, lightly normalized)
# ============================================================

VERBS_ALT='test|run|fix|build|implement|deploy|verify|check|validate|loop|iterate|find|review|ship|merge|continue'

# Normalize: strip newlines, collapse whitespace, but keep clause-ending
# punctuation so we can split.
NORM=$(printf '%s' "$PROMPT" \
  | LC_ALL=C tr '\n' ' ' \
  | LC_ALL=C tr -s ' ')

# Split into clauses on .!?;,
CLAUSES=$(printf '%s' "$NORM" | LC_ALL=C tr '.!?;,' '\n')

# Build goals JSON array. We walk each clause, search for a verb match,
# and emit one entry per match. We dedupe by (verb, normalized-context).
TMP_GOALS=$(mktemp /tmp/a1-goals.XXXXXX)
TMP_SEEN=$(mktemp /tmp/a1-seen.XXXXXX)
# shellcheck disable=SC2064
trap "rm -f $TMP_GOALS $TMP_SEEN" EXIT

# Use bash regex to extract verb+context from each clause.
# Match the FIRST verb hit per clause (precision over recall — multiple
# verbs in one clause usually re-state the same goal).
echo "$CLAUSES" | while IFS= read -r clause; do
  # Trim
  clause="${clause# }"
  clause="${clause% }"
  [[ -z "$clause" ]] && continue

  # Lowercase a working copy for matching only (preserve original for
  # raw_clause display).
  lc=$(printf '%s' "$clause" | LC_ALL=C tr '[:upper:]' '[:lower:]')

  # Walk through ALL matches in the clause (one clause can legitimately
  # carry multiple distinct goals: "test, run iter-2, fix the bugs").
  remaining="$lc"
  remaining_orig="$clause"
  # Loop guard
  guard=0
  while [[ -n "$remaining" ]] && [[ $guard -lt 12 ]]; do
    guard=$((guard+1))
    # Find the position of the first verb match
    if [[ ! "$remaining" =~ (^|[^a-zA-Z])($VERBS_ALT)([^a-zA-Z]|$) ]]; then
      break
    fi
    matched_verb="${BASH_REMATCH[2]}"
    # Locate the verb position in `remaining` (case-insensitive, word-bounded).
    # We search via grep -boi for a single occurrence; bash regex doesn't expose
    # offsets natively. Use a portable awk approach.
    pos=$(printf '%s' "$remaining" | LC_ALL=C awk -v v="$matched_verb" '
      BEGIN { IGNORECASE=1 }
      {
        n = length($0)
        for (i=1; i<=n; i++) {
          # word boundary check
          before = (i==1) ? "" : substr($0, i-1, 1)
          after  = (i+length(v)-1==n) ? "" : substr($0, i+length(v), 1)
          before_ok = (before == "" || before !~ /[A-Za-z]/)
          after_ok  = (after  == "" || after  !~ /[A-Za-z]/)
          if (before_ok && after_ok && tolower(substr($0, i, length(v))) == v) {
            print i-1
            exit
          }
        }
        print -1
      }')
    if [[ -z "$pos" ]] || [[ "$pos" -lt 0 ]]; then
      break
    fi

    # Slice context (~15 chars after the verb in the original clause)
    verb_len=${#matched_verb}
    end_pos=$((pos + verb_len))
    raw_after="${remaining_orig:$end_pos:60}"
    # Trim leading whitespace
    raw_after=$(printf '%s' "$raw_after" | LC_ALL=C sed -e 's/^[[:space:]]*//')
    # Take up to 30 chars
    context="${raw_after:0:30}"
    # Trim trailing whitespace
    context=$(printf '%s' "$context" | LC_ALL=C sed -e 's/[[:space:]]*$//')

    # raw_clause display: original verb + trimmed context, normalized
    raw_clause_display="${matched_verb} ${context}"
    # Collapse repeated whitespace
    raw_clause_display=$(printf '%s' "$raw_clause_display" | LC_ALL=C tr -s ' ')
    raw_clause_display="${raw_clause_display% }"

    # Dedupe key: lowercase verb + lowercase first 30 chars of context
    seen_key="${matched_verb}|$(printf '%s' "$context" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    if ! LC_ALL=C grep -F -q -x "$seen_key" "$TMP_SEEN" 2>/dev/null; then
      echo "$seen_key" >> "$TMP_SEEN"
      # Emit JSON line for this goal (jq will assemble the array).
      jq -n \
        --arg verb "$matched_verb" \
        --arg ctx "$context" \
        --arg raw "$raw_clause_display" \
        '{verb: $verb, context: $ctx, raw_clause: $raw}' >> "$TMP_GOALS"
    fi

    # Advance past this verb
    advance=$((pos + verb_len))
    remaining="${remaining:$advance}"
    remaining_orig="${remaining_orig:$advance}"
  done
done

# Assemble final goals array (preserving order)
GOALS_ARRAY="[]"
if [[ -s "$TMP_GOALS" ]]; then
  GOALS_ARRAY=$(jq -s '.' "$TMP_GOALS" 2>/dev/null || echo "[]")
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

# Write the goal file as a single JSON document
jq -n \
  --arg sid "$SESSION_ID" \
  --arg sha "$SHA" \
  --arg ts "$NOW" \
  --argjson goals "$GOALS_ARRAY" \
  '{session_id: $sid, first_message_text_sha256: $sha, extracted_at: $ts, goals: $goals}' \
  > "$GOAL_FILE" 2>/dev/null || exit 0

exit 0
