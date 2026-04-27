#!/bin/bash
# transcript-lie-detector.sh — Stop hook (A3 — Generation 6 mechanism)
#
# Detects self-contradiction in the session JSONL transcript: pairs of
# agent text where one claims completion ("done", "complete", "shipped")
# while another in the same session admits deferral ("deferred to user",
# "PHASE\d+-FOLLOWUP", "not yet executed", "first run is user-driven
# decision"). The user reads the end-of-session summary; this hook makes
# the contradictions impossible to hide there.
#
# WHY THIS EXISTS
# ===============
# On 2026-04-26 the agent flipped a plan to Status: COMPLETED while the
# same session's transcript already contained "first real loop run
# deferred to user", "PHASE6-FOLLOWUP-01 — execute the loop after user
# authorization", and "first run is a user-driven decision". A5
# (deferral-counter) catches the bare deferral. A3 catches the
# CONTRADICTION — the agent saying "done" and "not done" about the same
# scope within one session. The user lost trust because the final
# summary said "Plan COMPLETED" without surfacing that key work was
# deferred to a second session that the agent had no authority to schedule.
#
# v1 SCOPE: SELF-CONTRADICTION ONLY
# =================================
# Three classes were specified in the plan:
#   1. Self-contradiction within session (this version implements ONLY this)
#   2. Broken-promise check — A3-FOLLOWUP-01 (filed)
#   3. Skipped-imperative check — A3-FOLLOWUP-02 (filed)
#
# Self-contradiction is the highest-leverage case: it would have caught
# the 2026-04-26 incident. Broken-promise + skipped-imperative require
# tool-call-history correlation which is a larger surface to cover.
#
# DESIGN
# ======
# Reads $TRANSCRIPT_PATH JSONL (which the agent cannot edit). Extracts
# all assistant message text with line-numbered events. Scans for two
# pattern families:
#
#   COMPLETION_PATTERNS: phrases meaning "X is done"
#     - "Plan COMPLETED", "Status: COMPLETED", "all done", "all phases done"
#     - "task complete", "shipped", "merged", "verified", "tests pass"
#
#   DEFERRAL_PATTERNS: phrases meaning "X is NOT done"
#     - "deferred to user", "PHASE\d+-FOLLOWUP", "first run is user-driven"
#     - "not yet executed", "couldn't verify", "test failed"
#     - "user must (decide|authorize|approve)", "awaiting user"
#
# A pair is a contradiction when both classes appear in the same session
# (regardless of order — the agent that says "done" earlier and "deferred"
# later is the same lie as the reverse).
#
# When >=1 contradiction pair is found, the hook checks whether the
# agent's LAST assistant message contains the heading
#   ## Resolved contradictions in this session
# followed by at least one bullet line. If yes, allow Stop. If no, BLOCK.
#
# The agent CAN avoid the section by avoiding contradictions — actually
# being consistent within a session. That is the desired escape: don't
# claim "done" while writing "deferred" elsewhere in the same session.
#
# Pass conditions (any of these):
#   - Zero contradictions detected -> pass.
#   - Last assistant message contains the literal heading
#     "## Resolved contradictions in this session" with >=1 bullet.
#   - TRANSCRIPT_LIE_DETECTOR_DISABLE=1 in env (escape hatch for harness work)
#
# Fail mode:
#   - Session has contradictions but last message does NOT include the
#     required section -> BLOCK with verbatim contradiction pairs in stderr.
#
# WHY READ RAW TRANSCRIPT
# =======================
# The agent cannot edit $TRANSCRIPT_PATH mid-session. Pattern matching
# against the raw JSONL bypasses any "summary" the agent might write
# that conveniently omits the contradiction. This is structurally
# similar to A5 (deferral-counter) — both use the same JSONL reader.

set -u

# ============================================================
# --self-test: run the hook against the three fixtures
# ============================================================
if [[ "${1:-}" = "--self-test" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # The fixtures live alongside the hook in the adapter tree.
  # Try sibling tests dir first (when invoked from the adapter), then the
  # repo-relative path when invoked from the harness install.
  FIXTURE_DIR=""
  for candidate in \
    "$SCRIPT_DIR/../tests/transcript-lie-detector" \
    "$HOME/claude-projects/neural-lace/adapters/claude-code/tests/transcript-lie-detector" \
    "$HOME/.claude/tests/transcript-lie-detector"; do
    if [[ -d "$candidate" ]]; then
      FIXTURE_DIR="$candidate"
      break
    fi
  done
  if [[ -z "$FIXTURE_DIR" ]]; then
    echo "ERROR: cannot find transcript-lie-detector fixture directory" >&2
    exit 2
  fi

  PASS=0
  FAIL=0
  run_case() {
    local name="$1" expected_exit="$2" fixture="$3"
    TRANSCRIPT_LIE_DETECTOR_TRANSCRIPT="$fixture" \
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
  run_case "self-contradiction-blocks"    1 "$FIXTURE_DIR/fixture-self-contradiction.jsonl"
  run_case "clean-allows"                 0 "$FIXTURE_DIR/fixture-clean.jsonl"
  run_case "resolved-allows"              0 "$FIXTURE_DIR/fixture-resolved.jsonl"
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
if [[ -n "${TRANSCRIPT_LIE_DETECTOR_TRANSCRIPT:-}" ]]; then
  TRANSCRIPT_PATH="$TRANSCRIPT_LIE_DETECTOR_TRANSCRIPT"
fi

# Without a transcript or jq, this hook is a no-op.
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Escape hatch
if [[ "${TRANSCRIPT_LIE_DETECTOR_DISABLE:-0}" = "1" ]]; then
  exit 0
fi

# ============================================================
# Pattern lists — completion vs deferral
# ============================================================

COMPLETION_PATTERNS=(
  'Plan COMPLETED'
  'Status: COMPLETED'
  '\bplan complete\b'
  '\ball done\b'
  'all phases (done|complete|shipped|finished)'
  '\btask complete\b'
  '\btasks complete\b'
  '\ball tasks (done|complete|finished|checked)'
  '\bshipped\b'
  '\bfully shipped\b'
  '\beverything (works|shipped|done|complete)'
  '\bsuccessfully (deployed|shipped|merged|completed)'
  '\btests? pass(ed|ing)?\b'
  '\ball tests pass\b'
  '\bverified (working|complete|done)\b'
  '\bfully verified\b'
  '\bfeature is (done|live|complete|working)'
  '\bphase \d+ (done|complete|finished|shipped)'
  '\bA\d+ (done|complete|shipped)\b'
)

DEFERRAL_PATTERNS=(
  'deferred to user'
  'deferred to (next|future|subsequent)'
  'PHASE[0-9]+-?FOLLOWUP'
  'A[0-9]+-FOLLOWUP'
  'first run is (user-?driven|a user)'
  'user-?driven decision'
  'awaiting user'
  'requires user (approval|authorization|decision|input)'
  'user must (decide|authorize|approve)'
  'not yet executed'
  'not yet run'
  'never (ran|executed|invoked) (it|this|the)'
  "couldn'?t verify"
  "couldn'?t (run|test|execute)"
  '\btest failed\b'
  '\btests failed\b'
  '\bfailed to verify\b'
  '\bunable to (run|test|verify|execute)'
  'pending (approval|review|user|authorization)'
  '\bdid not (run|execute|verify|test)'
  '\bwill be (done|run|executed) later'
  'requires (manual|human) (intervention|step)'
)

# Required section heading in last assistant message
REQUIRED_HEADING='## Resolved contradictions in this session'

# ============================================================
# Extract assistant message text (with event line numbers)
# ============================================================

# Build a list of "lineno|text" pairs — one per assistant message.
# Using the JSONL physical line number as a stable event identifier.
ASSISTANT_NUMBERED=$(jq -r '
  if (.role == "assistant" or .message.role == "assistant") then
    (input_line_number | tostring) + "|" +
    ((.content // .text // .message.content // empty)
     | if type == "string" then .
       elif type == "array" then
         [.[] | (.text // .content // "")] | join(" ")
       else (. | tostring) end
     | gsub("\n"; " "))
  else empty end
' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

if [[ -z "$ASSISTANT_NUMBERED" ]]; then
  exit 0
fi

# Last assistant message text (full, with newlines preserved for heading match).
# We use slurp mode (-s) so each event's content stays as one string in the
# resulting JSON array; .[-1:] picks the last assistant message.
LAST_ASSISTANT=$(jq -rs '
  [ .[]
    | select(.role == "assistant" or .message.role == "assistant")
    | (.content // .text // .message.content // empty)
    | if type == "string" then .
      elif type == "array" then
        [.[] | (.text // .content // "")] | join("\n")
      else (. | tostring) end
  ]
  | if length == 0 then "" else .[-1] end
' "$TRANSCRIPT_PATH" 2>/dev/null)

# ============================================================
# Find completion-class and deferral-class matches
# ============================================================

TMP_COMPLETIONS=$(mktemp /tmp/lie-completions.XXXXXX)
TMP_DEFERRALS=$(mktemp /tmp/lie-deferrals.XXXXXX)
trap "rm -f $TMP_COMPLETIONS $TMP_DEFERRALS" EXIT

for pattern in "${COMPLETION_PATTERNS[@]}"; do
  echo "$ASSISTANT_NUMBERED" | LC_ALL=C grep -E -i --no-messages "$pattern" 2>/dev/null \
    | while IFS= read -r line; do
        lineno="${line%%|*}"
        text="${line#*|}"
        # Truncate text for display
        truncated="${text:0:160}"
        [[ ${#text} -gt 160 ]] && truncated="${truncated}..."
        printf '%s|%s|%s\n' "$lineno" "$pattern" "$truncated" >> "$TMP_COMPLETIONS"
      done
done

for pattern in "${DEFERRAL_PATTERNS[@]}"; do
  echo "$ASSISTANT_NUMBERED" | LC_ALL=C grep -E -i --no-messages "$pattern" 2>/dev/null \
    | while IFS= read -r line; do
        lineno="${line%%|*}"
        text="${line#*|}"
        truncated="${text:0:160}"
        [[ ${#text} -gt 160 ]] && truncated="${truncated}..."
        printf '%s|%s|%s\n' "$lineno" "$pattern" "$truncated" >> "$TMP_DEFERRALS"
      done
done

COMPLETION_COUNT=0
DEFERRAL_COUNT=0
[[ -s "$TMP_COMPLETIONS" ]] && COMPLETION_COUNT=$(wc -l < "$TMP_COMPLETIONS")
[[ -s "$TMP_DEFERRALS" ]] && DEFERRAL_COUNT=$(wc -l < "$TMP_DEFERRALS")

# Contradiction requires BOTH classes present
if [[ "$COMPLETION_COUNT" -eq 0 ]] || [[ "$DEFERRAL_COUNT" -eq 0 ]]; then
  exit 0
fi

# ============================================================
# Check whether last assistant message contains the resolution section
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
# BLOCK — final message lacks the required resolution section
# ============================================================

# Build a compact contradiction-pair display: top 5 completions + top 5 deferrals.
# Pattern strings can contain | (regex alternation), so split only on the
# first | (event lineno) and the LAST | (text) — middle is the pattern.
display_match() {
  awk '{
    line = $0
    p1 = index(line, "|")
    if (p1 == 0) { print "  - " line; next }
    lineno = substr(line, 1, p1-1)
    rest = substr(line, p1+1)
    # Find last | in rest
    last = 0
    for (i=1; i<=length(rest); i++) {
      if (substr(rest, i, 1) == "|") last = i
    }
    if (last == 0) { print "  - event " lineno " [" rest "]"; next }
    pattern = substr(rest, 1, last-1)
    text = substr(rest, last+1)
    printf "  - event %s [%s]: %s\n", lineno, pattern, text
  }'
}
COMPLETIONS_DISPLAY=$(head -5 "$TMP_COMPLETIONS" | display_match)
DEFERRALS_DISPLAY=$(head -5 "$TMP_DEFERRALS" | display_match)

PAIR_COUNT=$((COMPLETION_COUNT < DEFERRAL_COUNT ? COMPLETION_COUNT : DEFERRAL_COUNT))

BLOCKER_MSG="Session contains $COMPLETION_COUNT completion-class claims AND $DEFERRAL_COUNT deferral-class claims — at minimum $PAIR_COUNT contradiction pair(s). Your final user-facing message does NOT include the required '$REQUIRED_HEADING' section. Self-contradiction within a session is the lie that destroys user trust: claiming 'done' while the same session admits 'not done'. Either (a) reconcile the contradictions (flip Status back to ACTIVE, surface the deferrals, and re-attempt Stop), or (b) add the resolution section explaining each contradiction. Suppress with TRANSCRIPT_LIE_DETECTOR_DISABLE=1 only for harness-dev sessions where editing the pattern lists self-triggers."

echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
echo "" >&2
echo "================================================================" >&2
echo "TRANSCRIPT LIE DETECTOR (A3): SESSION BLOCKED" >&2
echo "================================================================" >&2
echo "$BLOCKER_MSG" >&2
echo "" >&2
echo "Completion-class claims (showing first 5 of $COMPLETION_COUNT):" >&2
echo "$COMPLETIONS_DISPLAY" >&2
echo "" >&2
echo "Deferral-class claims (showing first 5 of $DEFERRAL_COUNT):" >&2
echo "$DEFERRALS_DISPLAY" >&2
echo "" >&2
echo "Add this section to your final response (paste verbatim and fill in):" >&2
echo "" >&2
echo "    $REQUIRED_HEADING" >&2
echo "    " >&2
echo "    - <claim X (event N) says 'done', claim Y (event M) says 'deferred' — resolution: <reconcile or surface>>" >&2
echo "    - <next contradiction>" >&2
echo "    ..." >&2
echo "" >&2
exit 1
