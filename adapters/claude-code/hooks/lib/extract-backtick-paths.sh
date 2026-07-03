#!/bin/bash
# extract-backtick-paths.sh — shared helper (NL Overhaul Wave D, §D.0.7 fix)
#
# PROVEN duplicated bug (scope-enforcement-gate.sh:1536-1538 and
# spec-freeze-gate.sh:193-197): `tmp="${line#*\`}"; extracted="${tmp%%\`*}"`
# captures only the FIRST backtick-quoted token on a bullet line. A bullet
# naming two files — `- \`a/b.ts\` and \`c/d.ts\` — description` — silently
# dropped the second path from SECTION_ENTRIES, so scope-enforcement and
# spec-freeze both under-counted a plan's declared scope on multi-path
# bullets (the plan's In-flight one-file-per-bullet workaround existed only
# because of this bug; it becomes unnecessary once every caller sources
# this lib, though existing one-file-per-bullet lines stay valid).
#
# Contract:
#   extract_backtick_paths <line>
#     Loops ALL backtick pairs in <line> and prints every enclosed token,
#     one per line, on stdout. If <line> has no backtick pairs at all,
#     prints nothing (callers fall back to their own plain-path parsing —
#     this helper only owns the backtick-token extraction, not the
#     "line had no backticks" branch, since that branch differs slightly
#     between callers, e.g. em-dash/hyphen splitting).
#
#   Odd/unterminated backtick handling: an unmatched trailing backtick
#   (odd count) is ignored for its dangling half — only complete pairs
#   emit a token. This matches the pre-fix single-extraction behavior for
#   the well-formed case and fails safe (emits fewer, never garbage) for
#   malformed input.
#
# Usage (from a hooks/*.sh caller):
#   SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SELF_DIR/lib/extract-backtick-paths.sh"
#   while IFS= read -r tok; do
#     SECTION_ENTRIES+=("$tok")
#   done < <(extract_backtick_paths "$line")

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_EXTRACT_BACKTICK_PATHS_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_EXTRACT_BACKTICK_PATHS_SOURCED=1

extract_backtick_paths() {
  local line="$1"
  local rest="$line"
  local token

  while [[ "$rest" == *'`'* ]]; do
    # Everything after the next opening backtick.
    rest="${rest#*\`}"
    # No closing backtick left -> dangling half; stop (fail safe).
    [[ "$rest" == *'`'* ]] || break
    token="${rest%%\`*}"
    # Advance past the closing backtick for the next iteration.
    rest="${rest#*\`}"
    [[ -n "$token" ]] && printf '%s\n' "$token"
  done
}

# ============================================================
# --self-test
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  out="$(extract_backtick_paths 'adapters/claude-code/hooks/foo.sh — some description')"
  if [[ -z "$out" ]]; then
    pass "no-backticks line emits nothing"
  else
    fail "expected empty output, got [$out]"
  fi

  out="$(extract_backtick_paths "- \`adapters/claude-code/hooks/foo.sh\` — desc")"
  if [[ "$out" == "adapters/claude-code/hooks/foo.sh" ]]; then
    pass "single backtick pair extracts one token"
  else
    fail "expected single token, got [$out]"
  fi

  out="$(extract_backtick_paths "- \`a/b.ts\` and \`c/d.ts\` — two-file bullet")"
  n=$(printf '%s\n' "$out" | grep -c .)
  if [[ "$n" == "2" ]] && printf '%s' "$out" | grep -qx 'a/b.ts' && printf '%s' "$out" | grep -qx 'c/d.ts'; then
    pass "multi-path bullet extracts BOTH tokens (the §D.0.7 fix)"
  else
    fail "expected 2 tokens (a/b.ts, c/d.ts), got [$out]"
  fi

  out="$(extract_backtick_paths "- \`x/y.ts\`, \`p/q.ts\`, \`m/n.ts\` — three-file bullet")"
  n=$(printf '%s\n' "$out" | grep -c .)
  if [[ "$n" == "3" ]]; then
    pass "three backtick pairs extract three tokens"
  else
    fail "expected 3 tokens, got $n: [$out]"
  fi

  out="$(extract_backtick_paths "- \`unterminated.ts and no closing tick")"
  if [[ -z "$out" ]]; then
    pass "unterminated backtick (odd count) fails safe: no garbage token"
  else
    fail "expected empty output for unterminated backtick, got [$out]"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
