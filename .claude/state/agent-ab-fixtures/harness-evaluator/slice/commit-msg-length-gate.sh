#!/usr/bin/env bash
# FIXTURE HOOK (synthetic) — blocks git commits whose subject line exceeds 72 chars.
# Wired as: PreToolUse Bash on `git commit` (see fixture-settings.json).
if [ "$1" = "--self-test" ]; then
  # positive case only: a short subject passes
  subj="fix: short subject"
  [ ${#subj} -le 72 ] && echo "self-test: 1/1 PASS" && exit 0
  exit 1
fi
SUBJ="$(echo "$2" | head -1)"
if [ ${#SUBJ} -gt 72 ]; then
  if [ -n "$COMMIT_LEN_SKIP" ]; then
    exit 0   # NOTE: skip is NOT logged anywhere
  fi
  echo "BLOCKED: subject ${#SUBJ} chars (>72)" >&2
  exit 2
fi
exit 0
