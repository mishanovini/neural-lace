#!/bin/bash
# imperative-evidence-linker.sh — Stop hook (A7 — Generation 6 mechanism)
#
# Reads the user's substantive messages from $TRANSCRIPT_PATH, extracts each
# imperative verb+object pair (the user said "run the tests", "deploy it",
# "validate the end-to-end flow"), and links each to specific tool-call
# evidence in the same session JSONL. If the user said "must run the tests"
# but no Bash invocation matching `npm test|vitest|jest|playwright|pytest`
# exists in tool-call history, this is a SKIPPED IMPERATIVE — the user asked,
# the agent didn't do it, and the agent is about to Stop.
#
# When a SKIPPED IMPERATIVE is detected, this hook BLOCKS Stop until the
# agent's last assistant message includes a `## User-imperative coverage`
# section explaining each gap. The agent CAN avoid the section by actually
# doing what the user asked — that is the desired escape.
#
# WHY THIS EXISTS
# ===============
# A3 (transcript-lie-detector) catches the agent saying "done" while its own
# transcript admits "not done" — self-contradiction within session. A5
# (deferral-counter) catches deferral phrases the agent leaks into transcript
# but hides from the final summary. Neither catches the case where the USER
# gave an imperative ("run the tests", "validate the entire flow", "test in
# production") and the agent simply never invoked the corresponding tool.
# The agent's transcript may be perfectly clean of contradictions and
# deferrals — it just silently ignored the directive.
#
# The user's imperative is the highest-leverage authorization signal in the
# session. Skipping it is the sharpest form of a broken contract — the user
# explicitly asked, and the agent never even tried. A7 catches that class
# by linking each imperative to the tool-call evidence that would honor it.
#
# DESIGN
# ======
# Pattern library lives at adapters/claude-code/data/imperative-patterns.json
# (each pattern: {verb, object_pattern, evidence}). For each user message,
# the hook scans for "strong imperative" triggers (must, need to, required
# to, have to, please) followed by a verb in the library. If a (verb,
# object) pair matches a pattern AND no tool-call event in the session
# matches the pattern's evidence regex (e.g., "Bash:npm test"), the
# imperative is recorded as a gap.
#
# The hook builds a flat tool-call ledger from $TRANSCRIPT_PATH:
#   <ToolName>:<input-summary>
# where <input-summary> is the relevant input field (Bash.command,
# Edit.file_path, Write.file_path, Read.file_path, Grep.pattern, etc.).
# Pattern.evidence regexes match against this ledger.
#
# Pass conditions (any of these):
#   - Zero gaps detected -> pass.
#   - Last assistant message contains the literal heading
#     "## User-imperative coverage" with at least one bullet line.
#   - IMPERATIVE_LINKER_DISABLE=1 in env (escape hatch for harness work)
#
# Fail mode:
#   - Session has unmatched imperatives but last message does NOT include
#     the required section -> BLOCK with verbatim imperative+gap pairs.
#
# WHY READ RAW TRANSCRIPT
# =======================
# The agent cannot edit $TRANSCRIPT_PATH mid-session. Pattern matching
# against the raw JSONL bypasses any "summary" the agent might write that
# conveniently omits the imperative. Same approach as A3/A5.

set -u

# ============================================================
# Resolve pattern library and fixture directories
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_pattern_lib() {
  for candidate in \
    "$SCRIPT_DIR/../data/imperative-patterns.json" \
    "$HOME/claude-projects/neural-lace/adapters/claude-code/data/imperative-patterns.json" \
    "$HOME/.claude/data/imperative-patterns.json"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# ============================================================
# --self-test: run the hook against the three fixtures
# ============================================================
if [[ "${1:-}" = "--self-test" ]]; then
  FIXTURE_DIR=""
  for candidate in \
    "$SCRIPT_DIR/../tests/imperative-evidence-linker" \
    "$HOME/claude-projects/neural-lace/adapters/claude-code/tests/imperative-evidence-linker" \
    "$HOME/.claude/tests/imperative-evidence-linker"; do
    if [[ -d "$candidate" ]]; then
      FIXTURE_DIR="$candidate"
      break
    fi
  done
  if [[ -z "$FIXTURE_DIR" ]]; then
    echo "ERROR: cannot find imperative-evidence-linker fixture directory" >&2
    exit 2
  fi

  PASS=0
  FAIL=0
  run_case() {
    local name="$1" expected_exit="$2" fixture="$3"
    IMPERATIVE_LINKER_TRANSCRIPT="$fixture" \
      bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
    local actual=$?
    if [[ "$actual" -eq "$expected_exit" ]]; then
      echo "PASS  $name (exit $actual)"
      PASS=$((PASS+1))
    else
      echo "FAIL  $name (expected exit $expected_exit, got $actual)"
      FAIL=$((FAIL+1))
    fi
  }
  run_case "run-tests-no-evidence-blocks"   1 "$FIXTURE_DIR/fixture-run-tests-no-evidence.jsonl"
  run_case "run-tests-with-evidence-allows" 0 "$FIXTURE_DIR/fixture-run-tests-with-evidence.jsonl"
  run_case "with-coverage-section-allows"   0 "$FIXTURE_DIR/fixture-with-coverage-section.jsonl"
  echo ""
  echo "Result: $PASS passed, $FAIL failed"
  if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
  exit 0
fi

INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi

TRANSCRIPT_PATH=""
if [[ -n "$INPUT" ]]; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
fi

# Allow direct override for self-test fixtures
if [[ -n "${IMPERATIVE_LINKER_TRANSCRIPT:-}" ]]; then
  TRANSCRIPT_PATH="$IMPERATIVE_LINKER_TRANSCRIPT"
fi

# Without a transcript or jq, this hook is a no-op.
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Escape hatch
if [[ "${IMPERATIVE_LINKER_DISABLE:-0}" = "1" ]]; then
  exit 0
fi

PATTERN_LIB=$(resolve_pattern_lib || true)
if [[ -z "$PATTERN_LIB" ]] || [[ ! -f "$PATTERN_LIB" ]]; then
  # Without the pattern library, the hook cannot do its job — silently noop.
  exit 0
fi

# ============================================================
# Window of recent user messages — last K substantive messages
# ============================================================
# K is intentionally generous; the user's stated imperatives near the start
# of an autonomous run still carry standing authorization.
USER_MESSAGE_WINDOW=${IMPERATIVE_LINKER_WINDOW:-30}

# Required section heading in last assistant message
REQUIRED_HEADING='## User-imperative coverage'

# Strong imperative trigger words. The user must use one of these AHEAD of
# the verb. This raises precision — chitchat about "running tests" doesn't
# trigger; "you must run the tests" does.
STRONG_IMPERATIVES=(
  '\bmust\b'
  '\bneed to\b'
  '\bneeds? to\b'
  '\brequired to\b'
  '\bhave to\b'
  '\bplease\b'
  '\bgo ahead and\b'
  '\bmake sure to\b'
  '\bshould\b'
)

# ============================================================
# Extract the last K user messages (text only, role=user, no tool_result)
# ============================================================
USER_MESSAGES=$(jq -rs --argjson k "$USER_MESSAGE_WINDOW" '
  [ .[]
    | select((.role == "user" or .message.role == "user") and (.type != "queue-operation"))
    | (.content // .text // .message.content // empty)
    | if type == "string" then .
      elif type == "array" then
        [ .[]
          | select(type != "object" or (.type // "") != "tool_result")
          | (.text // .content // (if type == "string" then . else "" end))
        ] | join(" ")
      else "" end
    | gsub("\n"; " ")
    | select(. != "" and (. | length) > 0)
  ]
  | .[-$k:]
  | .[]
' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

if [[ -z "$USER_MESSAGES" ]]; then
  exit 0
fi

# ============================================================
# Build a tool-call ledger from the transcript.
# Each line: <ToolName>:<input-summary>
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
# Last assistant message text (full, with newlines preserved for heading)
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
# Load pattern library into parallel arrays (Bash 3 compatible)
# ============================================================
PATTERN_COUNT=$(jq -r '.patterns | length' "$PATTERN_LIB" 2>/dev/null || echo "0")
if [[ "$PATTERN_COUNT" -eq 0 ]]; then
  exit 0
fi

PATTERN_IDS=()
PATTERN_VERBS=()
PATTERN_OBJECTS=()
PATTERN_EVIDENCES=()
i=0
while [[ $i -lt $PATTERN_COUNT ]]; do
  PATTERN_IDS+=("$(jq -r ".patterns[$i].id" "$PATTERN_LIB")")
  PATTERN_VERBS+=("$(jq -r ".patterns[$i].verb" "$PATTERN_LIB")")
  PATTERN_OBJECTS+=("$(jq -r ".patterns[$i].object_pattern" "$PATTERN_LIB")")
  PATTERN_EVIDENCES+=("$(jq -r ".patterns[$i].evidence" "$PATTERN_LIB")")
  i=$((i+1))
done

# Build a single STRONG_IMPERATIVE alternation for grep
STRONG_IMP_ALT=$(IFS='|'; echo "${STRONG_IMPERATIVES[*]}")

# ============================================================
# Scan user messages for strong imperatives + verb+object matches
# ============================================================
TMP_GAPS=$(mktemp /tmp/a7-gaps.XXXXXX)
TMP_HONORED=$(mktemp /tmp/a7-honored.XXXXXX)
trap "rm -f $TMP_GAPS $TMP_HONORED" EXIT

# Iterate user messages line by line. Each line may contain multiple
# imperatives. We split on sentence-ending punctuation so per-clause
# matching is more precise.
echo "$USER_MESSAGES" | while IFS= read -r umsg; do
  [[ -z "$umsg" ]] && continue
  # Split into clauses on sentence-ending punctuation
  clauses=$(echo "$umsg" | LC_ALL=C tr '.!?;' '\n')

  echo "$clauses" | while IFS= read -r clause; do
    [[ -z "$clause" ]] && continue
    # Quick filter: clause must contain at least one strong imperative trigger
    if ! echo "$clause" | LC_ALL=C grep -E -i -q "$STRONG_IMP_ALT" 2>/dev/null; then
      continue
    fi

    # For each pattern, check if (verb + object) appears AFTER the strong
    # imperative trigger. We approximate "after the trigger" by treating
    # the whole clause as the candidate scope — strong imperatives bind
    # tightly to following verbs in natural English.
    pi=0
    while [[ $pi -lt ${#PATTERN_VERBS[@]} ]]; do
      pid="${PATTERN_IDS[$pi]}"
      pverb="${PATTERN_VERBS[$pi]}"
      pobj="${PATTERN_OBJECTS[$pi]}"
      pevidence="${PATTERN_EVIDENCES[$pi]}"

      # Combined regex: verb followed (within ~80 chars) by object pattern
      # \b<verb>\b ... <object>
      combined="\\b(${pverb})\\b[^\\n]{0,80}(${pobj})"
      if echo "$clause" | LC_ALL=C grep -E -i -q "$combined" 2>/dev/null; then
        # Check evidence in tool ledger
        if [[ -z "$TOOL_LEDGER" ]]; then
          # No tool calls at all — every triggered imperative is a gap
          truncated="${clause:0:200}"
          [[ ${#clause} -gt 200 ]] && truncated="${truncated}..."
          printf '%s|%s|%s\n' "$pid" "$pevidence" "$truncated" >> "$TMP_GAPS"
        elif echo "$TOOL_LEDGER" | LC_ALL=C grep -E -i -q "$pevidence" 2>/dev/null; then
          truncated="${clause:0:200}"
          [[ ${#clause} -gt 200 ]] && truncated="${truncated}..."
          printf '%s|%s|%s\n' "$pid" "$pevidence" "$truncated" >> "$TMP_HONORED"
        else
          truncated="${clause:0:200}"
          [[ ${#clause} -gt 200 ]] && truncated="${truncated}..."
          printf '%s|%s|%s\n' "$pid" "$pevidence" "$truncated" >> "$TMP_GAPS"
        fi
      fi
      pi=$((pi+1))
    done
  done
done

GAP_COUNT=0
[[ -s "$TMP_GAPS" ]] && GAP_COUNT=$(wc -l < "$TMP_GAPS")

# Zero gaps -> pass.
if [[ "$GAP_COUNT" -eq 0 ]]; then
  exit 0
fi

# ============================================================
# Check whether last assistant message contains the coverage section
# ============================================================
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
# BLOCK — final message lacks the required coverage section
# ============================================================

# De-duplicate gaps by pattern ID + truncated clause (same imperative
# matched in multiple messages should count once for display purposes).
UNIQUE_GAPS=$(sort -u "$TMP_GAPS" 2>/dev/null || cat "$TMP_GAPS")
UNIQUE_COUNT=$(echo "$UNIQUE_GAPS" | wc -l)

display_gap() {
  # Each line is "<pid>|<evidence-regex>|<text-clause>". Both the evidence
  # regex and the text can contain | characters. We split on the FIRST |
  # (after pid) and the LAST | (before text). The middle is the evidence.
  awk '{
    line = $0
    p1 = index(line, "|")
    if (p1 == 0) { print "  - " line; next }
    pid = substr(line, 1, p1-1)
    rest = substr(line, p1+1)
    # Find last | in rest
    last = 0
    for (i=1; i<=length(rest); i++) {
      if (substr(rest, i, 1) == "|") last = i
    }
    if (last == 0) { print "  - [" pid "] " rest; next }
    pev = substr(rest, 1, last-1)
    text = substr(rest, last+1)
    printf "  - [%s] expected evidence /%s/ — user said: %s\n", pid, pev, text
  }'
}
GAPS_DISPLAY=$(echo "$UNIQUE_GAPS" | head -10 | display_gap)

BLOCKER_MSG="Session contains $GAP_COUNT user-imperative gap(s) (at least $UNIQUE_COUNT distinct). The user issued strong imperatives (must / need to / please / have to / etc.) that map to specific tool-call evidence in the pattern library, but no matching tool-call event exists in this session's transcript. Your final user-facing message does NOT include the required '$REQUIRED_HEADING' section. Skipping a user imperative is the sharpest form of broken contract — the user explicitly asked, and the agent never even tried. Either (a) actually run the missing tool calls now and re-attempt Stop, or (b) add the coverage section explaining each gap (why it was skipped, what the user should do, what the agent will do next). Suppress with IMPERATIVE_LINKER_DISABLE=1 only for harness-dev sessions where editing the pattern library self-triggers."

echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
echo "" >&2
echo "================================================================" >&2
echo "IMPERATIVE-EVIDENCE LINKER (A7): SESSION BLOCKED" >&2
echo "================================================================" >&2
echo "$BLOCKER_MSG" >&2
echo "" >&2
echo "Unmatched imperatives (showing first 10 of $UNIQUE_COUNT distinct):" >&2
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
exit 1
