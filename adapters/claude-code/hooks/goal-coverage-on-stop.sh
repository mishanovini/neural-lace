#!/bin/bash
# goal-coverage-on-stop.sh — Stop hook (A1 — Generation 6 mechanism)
#
# Reads the user-goal file written by goal-extraction-on-prompt.sh on the
# session's first user prompt, re-derives the SHA-256 of that first message
# from $TRANSCRIPT_PATH, and compares against the stored SHA. On mismatch,
# the goal file was tampered — block with a tamper-detected message.
#
# When the SHA matches, walk each extracted goal and check execution-evidence
# in the session's tool-call ledger (parallel to A7's pattern but keyed on
# A1's verb list). For any goal lacking matching evidence, record it as a
# gap. If gaps exist AND the agent's last assistant message lacks a
# `## User-goal coverage` section with at least one bullet, BLOCK.
#
# WHY THIS EXISTS
# ===============
# A5 (deferral-counter) catches deferrals leaked into transcript and forces
# them into the user-visible final message. A3 (transcript-lie-detector)
# catches self-contradictions. A7 (imperative-evidence-linker) catches
# strong imperatives in user messages that lack execution evidence.
#
# A1 closes a different gap: it anchors goal extraction at the FIRST user
# message — the highest-signal moment in the session. The extracted file is
# checksummed (the agent cannot edit the user's first message in $TRANSCRIPT_PATH;
# any tampering with the goal file is detected). At Stop, the goal-coverage
# hook is the independent reader: it sees the goal list, the tool-call
# history, and the agent's final message. If the agent silently moved on
# without addressing a goal — and didn't say so in the user-visible final
# message — the hook blocks.
#
# DESIGN
# ======
# 1. Read JSON input from stdin. Resolve transcript_path + session_id.
# 2. Locate the goal file at `.claude/state/user-goals/<session-id>.json`
#    (search PWD; fallback to $CWD provided in input). If no file, this is
#    either a session that started before A1 was wired or a session whose
#    first message had no extractable goals — exit 0 (no gate).
# 3. Re-derive the first user message from $TRANSCRIPT_PATH (first event with
#    role=user that is plain text content, not a tool_result). Compute SHA.
# 4. If SHA mismatches the file's `first_message_text_sha256`: BLOCK with a
#    tamper-detected message naming the goal file path.
# 5. For each goal, check execution-evidence using the same tool-call ledger
#    pattern A7 uses (but with A1's verb-evidence map below).
# 6. If gaps exist AND the agent's last assistant message contains the literal
#    heading `## User-goal coverage` with at least one bullet line, allow Stop.
#    Otherwise BLOCK with the verbatim list of unmet goals.
#
# ESCAPE HATCH
# ============
# GOAL_EXTRACTION_DISABLE=1 env var (mirrors goal-extraction-on-prompt.sh).
# Suppresses all A1 enforcement for harness-development sessions that would
# self-trigger by editing the verb list itself.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# A1 verb -> required tool-call evidence regex
# ============================================================
# Each goal verb maps to a regex matched against the flat <ToolName>:<input>
# tool-call ledger. Identical pattern to A7's evidence regexes; A1 only
# handles the 16 verbs the extractor recognizes.
goal_evidence_for_verb() {
  case "$1" in
    test)        echo 'Bash:(npm[ \t]+(run[ \t]+)?test|vitest|jest|playwright|pytest|go test|cargo test|rspec|test:e2e|test:journey|test:loop)' ;;
    run)         echo '(Bash):.+' ;;
    fix)         echo '(Edit|Write|Bash):.*' ;;
    build)       echo '(Edit|Write|Bash):.*' ;;
    implement)   echo '(Edit|Write):.*' ;;
    deploy)      echo 'Bash:(git[ \t]+push|gh[ \t]+pr[ \t]+merge|vercel[ \t]+(deploy|--prod)|netlify[ \t]+deploy|fly[ \t]+deploy|railway[ \t]+up)' ;;
    verify)      echo '(Bash|Read|Grep|Glob|WebFetch):.*' ;;
    check)       echo '(Bash|Read|Grep|Glob|WebFetch):.*' ;;
    validate)    echo 'Bash:(npm[ \t]+run[ \t]+test:(e2e|journey|e2e:loop)|playwright|cypress|test:e2e|test:loop)' ;;
    loop)        echo 'Bash:(test:e2e:loop|test:loop|while[ \t]+|for[ \t]+i)' ;;
    iterate)     echo 'Bash:(test:e2e:loop|test:loop|while[ \t]+|for[ \t]+i)' ;;
    find)        echo '(Grep|Read|Bash|Glob):.*' ;;
    review)      echo '(Read|Grep|Task|Bash):.*' ;;
    ship)        echo 'Bash:(git[ \t]+push|gh[ \t]+pr[ \t]+merge|vercel[ \t]+(deploy|--prod))' ;;
    merge)       echo 'Bash:(gh[ \t]+pr[ \t]+merge|git[ \t]+merge)' ;;
    continue)    echo '(Edit|Write|Bash):.*' ;;
    *)           echo '' ;;
  esac
}

# ============================================================
# --self-test: 4 fixtures
# ============================================================
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

  # Each Stop-hook fixture is a JSONL file. We need a corresponding goal file
  # that matches the SHA of the first user message in the JSONL. Self-test
  # generates the goal file from the JSONL's first message before invoking
  # the hook. This mirrors what would happen in a real session.

  prepare_goal_file_for_fixture() {
    local fixture="$1"
    local sid="$2"
    local state_dir="$3"
    local override_sha="${4:-}"
    # Extract first user message from the fixture
    local first_user_msg
    first_user_msg=$(jq -rs '
      [ .[]
        | select(.role == "user" or .message.role == "user")
        | (.content // .text // .message.content // empty)
        | if type == "string" then .
          elif type == "array" then
            [ .[]
              | select(type != "object" or (.type // "") != "tool_result")
              | (.text // .content // (if type == "string" then . else "" end))
            ] | join(" ")
          else "" end
        | select(. != "" and (. | length) > 0)
      ]
      | if length == 0 then "" else .[0] end
    ' "$fixture" 2>/dev/null)

    local sha
    if [[ -n "$override_sha" ]]; then
      sha="$override_sha"
    else
      sha=$(printf '%s' "$first_user_msg" | sha256sum | awk '{print $1}')
    fi

    # Synthesize a goal file with verbs from a deterministic extraction.
    # We use the same regex set as the prompt hook for consistency.
    mkdir -p "$state_dir/.claude/state/user-goals"
    local goal_path="$state_dir/.claude/state/user-goals/$sid.json"

    # Hard-coded goals matching the test's intent. The verbs are the
    # 4 we expect from "Test the entire flow, run iter-2, fix the bugs,
    # and continue looping until validated."
    cat > "$goal_path" <<EOF
{
  "session_id": "$sid",
  "first_message_text_sha256": "$sha",
  "extracted_at": "2026-04-26T12:00:00Z",
  "goals": [
    {"verb": "test", "context": "the entire flow", "raw_clause": "test the entire flow"},
    {"verb": "run", "context": "iter-2", "raw_clause": "run iter-2"},
    {"verb": "fix", "context": "the bugs", "raw_clause": "fix the bugs"},
    {"verb": "continue", "context": "looping until validated", "raw_clause": "continue looping until validated"}
  ]
}
EOF
  }

  run_case() {
    local name="$1" expected_exit="$2" fixture="$3" sid="$4" override_sha="${5:-}"
    local state_dir
    state_dir=$(mktemp -d /tmp/a1-stop-state.XXXXXX)
    prepare_goal_file_for_fixture "$fixture" "$sid" "$state_dir" "$override_sha"

    GOAL_COVERAGE_TRANSCRIPT="$fixture" \
    GOAL_COVERAGE_STATE_ROOT="$state_dir" \
    GOAL_COVERAGE_SESSION_ID="$sid" \
      bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
    local actual=$?
    rm -rf "$state_dir"
    if [[ "$actual" -eq "$expected_exit" ]]; then
      echo "PASS  $name (exit $actual)"
      PASS=$((PASS+1))
    else
      echo "FAIL  $name (expected exit $expected_exit, got $actual)"
      FAIL=$((FAIL+1))
    fi
  }

  run_case "stop-no-evidence-blocks"            1 "$FIXTURE_DIR/fixture-stop-no-evidence.jsonl"        "session-no-ev"
  run_case "stop-with-evidence-allows"          0 "$FIXTURE_DIR/fixture-stop-with-evidence.jsonl"      "session-with-ev"
  run_case "stop-tampered-sha-blocks"           1 "$FIXTURE_DIR/fixture-stop-tampered.jsonl"           "session-tamper" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  run_case "stop-with-coverage-section-allows"  0 "$FIXTURE_DIR/fixture-stop-with-coverage-section.jsonl" "session-coverage"

  echo ""
  echo "Result: $PASS passed, $FAIL failed"
  if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
  exit 0
fi

# ============================================================
# Normal path
# ============================================================

# Shared retry-guard library — see lib/stop-hook-retry-guard.sh.
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/lib/stop-hook-retry-guard.sh"

INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi

TRANSCRIPT_PATH=""
SESSION_ID=""
CWD=""
if [[ -n "$INPUT" ]]; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .session.id // empty' 2>/dev/null || echo "")
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
fi

# Allow direct overrides for self-test
if [[ -n "${GOAL_COVERAGE_TRANSCRIPT:-}" ]]; then
  TRANSCRIPT_PATH="$GOAL_COVERAGE_TRANSCRIPT"
fi
if [[ -n "${GOAL_COVERAGE_SESSION_ID:-}" ]]; then
  SESSION_ID="$GOAL_COVERAGE_SESSION_ID"
fi

# Without prerequisites, no-op (parallel to A5/A7's defensive posture).
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if ! command -v sha256sum >/dev/null 2>&1; then exit 0; fi
if [[ "${GOAL_EXTRACTION_DISABLE:-0}" = "1" ]]; then exit 0; fi
if [[ -z "$SESSION_ID" ]]; then exit 0; fi

# ============================================================
# Locate the goal file
# ============================================================
STATE_ROOT="${GOAL_COVERAGE_STATE_ROOT:-${CWD:-$PWD}}"
GOAL_FILE="$STATE_ROOT/.claude/state/user-goals/$SESSION_ID.json"

# If no goal file: session pre-dates A1 wiring or first message had no
# extractable goals — exit 0 silently.
if [[ ! -f "$GOAL_FILE" ]]; then
  exit 0
fi

STORED_SHA=$(jq -r '.first_message_text_sha256 // ""' "$GOAL_FILE" 2>/dev/null)
if [[ -z "$STORED_SHA" ]]; then
  # Malformed goal file. Treat as no-op rather than block on harness bugs.
  exit 0
fi

# ============================================================
# Re-derive first user message from transcript and compute its SHA
# ============================================================
FIRST_USER_MSG=$(jq -rs '
  [ .[]
    | select(.role == "user" or .message.role == "user")
    | (.content // .text // .message.content // empty)
    | if type == "string" then .
      elif type == "array" then
        [ .[]
          | select(type != "object" or (.type // "") != "tool_result")
          | (.text // .content // (if type == "string" then . else "" end))
        ] | join(" ")
      else "" end
    | select(. != "" and (. | length) > 0)
  ]
  | if length == 0 then "" else .[0] end
' "$TRANSCRIPT_PATH" 2>/dev/null)

if [[ -z "$FIRST_USER_MSG" ]]; then
  # Empty transcript or no user messages — defer to other gates.
  exit 0
fi

DERIVED_SHA=$(printf '%s' "$FIRST_USER_MSG" | sha256sum | awk '{print $1}')

if [[ "$DERIVED_SHA" != "$STORED_SHA" ]]; then
  TAMPER_MSG="GOAL FILE TAMPERED. The SHA-256 of the user's first message in the transcript ($DERIVED_SHA) does NOT match the SHA stored in the goal file ($STORED_SHA) at $GOAL_FILE. Either the goal file was modified after creation, or the transcript first-message extraction differs from the prompt hook's view. This is a hard block: the goal-coverage gate cannot trust a tampered file. To recover: delete $GOAL_FILE and let the next session re-run goal extraction; investigate why the file was modified."
  echo "" >&2
  echo "================================================================" >&2
  echo "GOAL-COVERAGE GATE (A1): SESSION BLOCKED (TAMPER DETECTED)" >&2
  echo "================================================================" >&2
  echo "$TAMPER_MSG" >&2
  echo "" >&2
  RG_SESSION_ID_TAMPER=$(retry_guard_session_id "$INPUT")
  retry_guard_block_or_exit \
    "goal-coverage-on-stop" \
    "$RG_SESSION_ID_TAMPER" \
    "goal-coverage-tamper:${DERIVED_SHA}:${STORED_SHA}" \
    "$TAMPER_MSG" \
    "{\"result\": \"error\", \"message\": \"$TAMPER_MSG\"}" \
    1
fi

# ============================================================
# Build tool-call ledger from transcript (mirrors A7)
# ============================================================
TOOL_LEDGER=$(jq -r '
  if (.role == "assistant" or .message.role == "assistant") then
    ((.content // .message.content // empty)
     | if type == "array" then
         [ .[]
           | select(type == "object" and .type == "tool_use")
           | .name + ":" +
             (
               if .name == "Bash" then ((.input.command // "") | tostring)
               elif .name == "Edit" or .name == "Write" then ((.input.file_path // "") | tostring)
               elif .name == "Read" then ((.input.file_path // "") | tostring)
               elif .name == "Grep" then ((.input.pattern // "") | tostring)
               elif .name == "Glob" then ((.input.pattern // "") | tostring)
               elif .name == "WebFetch" then ((.input.url // "") | tostring)
               elif .name == "TodoWrite" then "todos"
               elif .name == "Task" then ((.input.description // .input.subagent_type // "") | tostring)
               else (.input | tostring)
               end
             )
         ] | .[]
       else empty end
     | gsub("\n"; " "))
  else empty end
' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

# ============================================================
# Last assistant message (full text, newlines preserved for heading)
# ============================================================
LAST_ASSISTANT=$(jq -rs '
  [ .[]
    | select(.role == "assistant" or .message.role == "assistant")
    | (.content // .text // .message.content // empty)
    | if type == "string" then .
      elif type == "array" then
        [ .[]
          | select(type == "object" and (.type // "") == "text")
          | (.text // "")
        ] | join("\n")
      else (. | tostring) end
    | select(. != "")
  ]
  | if length == 0 then "" else .[-1] end
' "$TRANSCRIPT_PATH" 2>/dev/null)

# ============================================================
# For each goal, check evidence in the ledger
# ============================================================
GOAL_COUNT=$(jq -r '.goals | length' "$GOAL_FILE" 2>/dev/null || echo 0)
if [[ "$GOAL_COUNT" -eq 0 ]]; then
  exit 0
fi

TMP_GAPS=$(mktemp /tmp/a1-cov-gaps.XXXXXX)
# shellcheck disable=SC2064
trap "rm -f $TMP_GAPS" EXIT

i=0
while [[ $i -lt $GOAL_COUNT ]]; do
  verb=$(jq -r ".goals[$i].verb" "$GOAL_FILE")
  context=$(jq -r ".goals[$i].context" "$GOAL_FILE")
  raw_clause=$(jq -r ".goals[$i].raw_clause" "$GOAL_FILE")
  i=$((i+1))

  evidence=$(goal_evidence_for_verb "$verb")
  if [[ -z "$evidence" ]]; then
    # Unknown verb — defer to the other gates rather than block here.
    continue
  fi

  if [[ -z "$TOOL_LEDGER" ]]; then
    # No tool calls at all — every goal is a gap
    printf '%s|%s|%s\n' "$verb" "$evidence" "$raw_clause" >> "$TMP_GAPS"
    continue
  fi

  if echo "$TOOL_LEDGER" | LC_ALL=C grep -E -i -q "$evidence" 2>/dev/null; then
    : # honored
  else
    printf '%s|%s|%s\n' "$verb" "$evidence" "$raw_clause" >> "$TMP_GAPS"
  fi
done

GAP_COUNT=0
[[ -s "$TMP_GAPS" ]] && GAP_COUNT=$(wc -l < "$TMP_GAPS")

if [[ "$GAP_COUNT" -eq 0 ]]; then
  exit 0
fi

# ============================================================
# Check whether last assistant message contains the coverage section
# ============================================================
REQUIRED_HEADING='## User-goal coverage'

LAST_HAS_HEADING=0
if echo "$LAST_ASSISTANT" | LC_ALL=C grep -F -q "$REQUIRED_HEADING" 2>/dev/null; then
  LAST_HAS_HEADING=1
fi

if [[ "$LAST_HAS_HEADING" -eq 1 ]]; then
  BULLETS_AFTER_HEADING=$(echo "$LAST_ASSISTANT" | awk -v h="$REQUIRED_HEADING" '
    index($0, h) { in_section=1; next }
    in_section && /^## / { in_section=0 }
    in_section && /^[[:space:]]*[-*] / { print }
  ' | wc -l)
  if [[ "$BULLETS_AFTER_HEADING" -gt 0 ]]; then
    exit 0
  fi
fi

# ============================================================
# BLOCK
# ============================================================
UNIQUE_GAPS=$(sort -u "$TMP_GAPS" 2>/dev/null || cat "$TMP_GAPS")
UNIQUE_COUNT=$(echo "$UNIQUE_GAPS" | wc -l | LC_ALL=C tr -d '[:space:]')

display_gap() {
  awk '{
    line = $0
    p1 = index(line, "|")
    if (p1 == 0) { print "  - " line; next }
    verb = substr(line, 1, p1-1)
    rest = substr(line, p1+1)
    last = 0
    for (i=1; i<=length(rest); i++) {
      if (substr(rest, i, 1) == "|") last = i
    }
    if (last == 0) { print "  - [" verb "] " rest; next }
    pev = substr(rest, 1, last-1)
    text = substr(rest, last+1)
    printf "  - [%s] expected evidence /%s/ — user said: %s\n", verb, pev, text
  }'
}
GAPS_DISPLAY=$(echo "$UNIQUE_GAPS" | head -10 | display_gap)

BLOCKER_MSG="Session contains $GAP_COUNT unmet user goal(s) (extracted from the user's verbatim FIRST message and stored at $GOAL_FILE). For each unmet goal, the verb maps to a required tool-call evidence regex; no matching tool-call event exists in this session's transcript. Your final user-facing message does NOT include the required '$REQUIRED_HEADING' section. The user's first message is the highest-signal authorization in the session — silently skipping a goal is a broken contract. Either (a) actually run the missing tool calls now and re-attempt Stop, or (b) add the coverage section to your final message explaining each gap (why it was skipped, what the user should do, what the agent will do next). Suppress with GOAL_EXTRACTION_DISABLE=1 only for harness-dev sessions where editing the verb list itself self-triggers."

echo "" >&2
echo "================================================================" >&2
echo "GOAL-COVERAGE GATE (A1): SESSION BLOCKED" >&2
echo "================================================================" >&2
echo "$BLOCKER_MSG" >&2
echo "" >&2
echo "Unmet goals (showing first 10 of $UNIQUE_COUNT distinct):" >&2
echo "$GAPS_DISPLAY" >&2
echo "" >&2
echo "Add this section to your final response (paste verbatim and fill in):" >&2
echo "" >&2
echo "    $REQUIRED_HEADING" >&2
echo "    " >&2
echo "    - <user said \"X\" -> mapped to evidence /<regex>/. I did/did not honor it because <reason>. Next action: <plan>>" >&2
echo "    - <next gap>" >&2
echo "    ..." >&2
echo "" >&2

RG_SESSION_ID_GAP=$(retry_guard_session_id "$INPUT")
RG_FAILURE_SIG="goal-coverage:${UNIQUE_COUNT}:${GAPS_DISPLAY}"
retry_guard_block_or_exit \
  "goal-coverage-on-stop" \
  "$RG_SESSION_ID_GAP" \
  "$RG_FAILURE_SIG" \
  "$BLOCKER_MSG" \
  "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}" \
  1
