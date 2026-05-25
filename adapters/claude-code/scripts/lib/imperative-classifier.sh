#!/usr/bin/env bash
# imperative-classifier.sh — shared helpers for classifying imperative-mood asks
# from user messages mined out of Claude Code transcripts.
#
# This is a library — source it; do not invoke directly.
#
# Two surfaces:
#   1. `imperative_match <text>` — returns 0 if text contains an imperative trigger
#      phrase; outputs the matched trigger to stdout.
#   2. `classify_ask <text>` — emits one of: explicit-task | recommendation |
#      aspirational | dropped-suggestion | quote-not-ask.
#
# Both are heuristic. False positives are expected; v1 surfaces them in
# Misha's weekly review (per docs/plans/drift-backlog-and-harness-evaluator.md
# Decisions Log).

set -u

# Imperative-trigger regex. Case-insensitive. Captures the trigger word/phrase.
# Ordered roughly by signal strength (most specific first).
_IMP_TRIGGERS='(i want you to|i need you to|please [a-z]+|we should|we need to|let'\''s (build|do|add|fix|ship|create|implement|wire|add)|make sure (you )?|don'\''t forget to|remember to|you (should|need to|must|have to)|can you (please )?|could you (please )?|next time|going forward|from now on|always [a-z]+|never [a-z]+|build (a |an |the )|add (a |an |the )|fix (a |an |the )|ship (a |an |the )|create (a |an |the )|implement (a |an |the )|wire (in |up )|set up (a |an |the )|make (a |an |the )|write (a |an |the )|generate (a |an |the )|kill (a |an |the )|remove (a |an |the )|delete (a |an |the )|rename (a |an |the )|refactor (a |an |the )|move (a |an |the )|update (a |an |the ))'

imperative_match() {
  local text="$1"
  # Single-line regex match; outputs the first matched phrase.
  local match
  match=$(printf '%s\n' "$text" | grep -oiE "$_IMP_TRIGGERS" 2>/dev/null | head -1)
  if [[ -n "$match" ]]; then
    printf '%s\n' "$match"
    return 0
  fi
  return 1
}

# Classify an imperative ask. Heuristic.
#
# - explicit-task: "build X", "fix Y", "add Z" — has a verb + clear noun phrase
# - recommendation: "we should consider", "ideally", "might want to"
# - aspirational: "going forward", "from now on", "always"
# - dropped-suggestion: trigger appears but in a context like "I tried X but
#   we should also Y" — surface for manual review
# - quote-not-ask: trigger appears inside double-quotes (Misha quoting himself
#   or someone else, not issuing a new ask)
classify_ask() {
  local text="$1"
  # Heuristic 1: if the trigger appears INSIDE matching double quotes,
  # it's likely a quote rather than a fresh ask. Cheap check.
  if printf '%s\n' "$text" | grep -qE '"[^"]*(we should|please|i want you to|make sure)[^"]*"' 2>/dev/null; then
    printf '%s\n' "quote-not-ask"
    return 0
  fi
  # Heuristic 2: aspirational markers
  if printf '%s\n' "$text" | grep -qiE '(going forward|from now on|always (always )?[a-z]+|never [a-z]+|in future|next time)' 2>/dev/null; then
    printf '%s\n' "aspirational"
    return 0
  fi
  # Heuristic 3: recommendation markers
  if printf '%s\n' "$text" | grep -qiE '(we should consider|ideally|might want to|would be nice|nice to have|in theory)' 2>/dev/null; then
    printf '%s\n' "recommendation"
    return 0
  fi
  # Heuristic 4: dropped-suggestion markers ("also", "btw", "by the way")
  if printf '%s\n' "$text" | grep -qiE '(^|[.;])\s*(also|btw|by the way|oh and|one more thing|side note)\s+' 2>/dev/null; then
    printf '%s\n' "dropped-suggestion"
    return 0
  fi
  # Default: explicit-task
  printf '%s\n' "explicit-task"
}

# Normalize ask text for dedup-by-hash. Lowercase, collapse whitespace, strip
# punctuation, take first 200 chars. The hash answers "did Misha say the same
# thing twice"; we want lexical near-duplicates to collide.
normalize_ask() {
  local text="$1"
  printf '%s\n' "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -d '[:punct:]' \
    | tr -s '[:space:]' ' ' \
    | cut -c1-200
}
