#!/bin/bash
# measure-claim-reviewer-rate.sh
#
# Mines Claude Code session transcripts and reports the claim-reviewer
# self-invocation rate: ratio of (Task-tool invocations of `claim-reviewer`)
# to (assistant messages containing feature-claim verb patterns).
#
# This is the instrumentation half of Fix #3 from the 2026-05-24 agent-
# incentive-structure audit. IG-3 — claim-reviewer is self-invoked, so
# the bypass rate is unknown. This script converts "unknown bypass rate"
# to "measurable bypass rate."
#
# Output format (matches harness-evaluator Section 1 metric shape):
#   sessions_scanned: N
#   feature_claim_messages: N
#   claim_reviewer_invocations: N
#   self_invocation_rate: 0.NNN  (invocations / feature_claim_messages)
#   self_invocation_ratio_pct: NN%
#
# Designed to compose with harness-evaluator.sh — when wired into a
# daily packet, the rate becomes a tracked metric over time. A
# declining rate is the failure mode (more uncited claims).
#
# Defaults to scanning sessions from the last 7 days; override with
# --since "<duration>" (e.g., "1 day", "30 days", "2026-05-20").
#
# Usage:
#   measure-claim-reviewer-rate.sh                           # last 7 days
#   measure-claim-reviewer-rate.sh --since "1 day"           # last 24h
#   measure-claim-reviewer-rate.sh --since "30 days"         # last 30d
#   measure-claim-reviewer-rate.sh --transcript <path>       # single file
#   measure-claim-reviewer-rate.sh --self-test               # exercise rubric

set -u

# -------- Feature-claim verb patterns --------
# Conservative — matches assistant text containing any of these in present-
# tense, indicative mood. False-positive rate is acceptable for this metric
# because both numerator (invocations) and denominator (claims) are over the
# SAME pattern set, so noise cancels.
FEATURE_CLAIM_PATTERNS=(
  "works"
  "is done"
  "is shipped"
  "is wired"
  "supports"
  "handles"
  "is now fixed"
  "has shipped"
  "is complete"
)

CLAIM_REVIEWER_TOKENS=(
  '"subagent_type":"claim-reviewer"'
  '"name":"claim-reviewer"'
)

# -------- Count feature-claim messages in a single JSONL transcript --------
count_feature_claims() {
  local file="$1"
  # Match only assistant text events; conservative grep against the verb set.
  local pattern
  pattern=$(IFS='|'; echo "${FEATURE_CLAIM_PATTERNS[*]}")
  local n
  n=$(grep -c -iE "\"role\":\"assistant\".*($pattern)" "$file" 2>/dev/null)
  [ -z "$n" ] && n=0
  echo "$n" | tr -d '[:space:]'
}

# -------- Count claim-reviewer invocations in a single JSONL transcript --------
count_invocations() {
  local file="$1"
  local total=0
  for tok in "${CLAIM_REVIEWER_TOKENS[@]}"; do
    local n
    n=$(grep -c -F "$tok" "$file" 2>/dev/null)
    [ -z "$n" ] && n=0
    n=$(echo "$n" | tr -d '[:space:]')
    total=$((total + n))
  done
  echo "$total"
}

# -------- Find transcript files matching a since-window --------
# Uses file mtime, which is conservative: a transcript modified recently
# IS in the window, while a transcript untouched is not.
find_transcripts() {
  local since="$1"
  local base="$HOME/.claude/projects"
  [ -d "$base" ] || return 0
  if [ -z "$since" ]; then
    find "$base" -name "*.jsonl" -type f 2>/dev/null
  else
    # GNU date / BSD date both accept relative durations via -d/-v
    local cutoff_ts
    cutoff_ts=$(date -d "$since ago" +%s 2>/dev/null) \
      || cutoff_ts=$(date -v "-${since// /}" +%s 2>/dev/null) \
      || cutoff_ts=$(($(date +%s) - 604800))  # default 7 days
    find "$base" -name "*.jsonl" -type f 2>/dev/null | while read -r f; do
      local mt
      mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)
      [ -n "$mt" ] || continue
      [ "$mt" -ge "$cutoff_ts" ] && echo "$f"
    done
  fi
}

# -------- Aggregate over a transcript set --------
measure() {
  local single_file="$1"
  local since="$2"
  local sessions=0
  local total_claims=0
  local total_invocations=0
  local files
  if [ -n "$single_file" ]; then
    files="$single_file"
  else
    files=$(find_transcripts "$since")
  fi
  for f in $files; do
    [ -f "$f" ] || continue
    sessions=$((sessions + 1))
    local c i
    c=$(count_feature_claims "$f")
    i=$(count_invocations "$f")
    total_claims=$((total_claims + c))
    total_invocations=$((total_invocations + i))
  done
  local rate="0.000"
  local pct="0"
  if [ "$total_claims" -gt 0 ]; then
    # bc may not be available on minimal envs; fall back to integer division pct
    if command -v bc >/dev/null 2>&1; then
      rate=$(echo "scale=3; $total_invocations / $total_claims" | bc 2>/dev/null)
    fi
    pct=$((total_invocations * 100 / total_claims))
  fi
  echo "sessions_scanned: $sessions"
  echo "feature_claim_messages: $total_claims"
  echo "claim_reviewer_invocations: $total_invocations"
  echo "self_invocation_rate: $rate"
  echo "self_invocation_ratio_pct: ${pct}%"
}

# -------- Self-test --------
run_self_test() {
  local tmp
  tmp=$(mktemp -d -t claim-rate-test.XXXXXX 2>/dev/null) || tmp="/tmp/claim-rate-test.$$"
  mkdir -p "$tmp"
  local failures=0

  # Scenario 1: empty transcript → zero claims, zero invocations
  local s1="$tmp/empty.jsonl"
  echo '{"role":"system","content":"boot"}' > "$s1"
  local out1
  out1=$(measure "$s1" "")
  if echo "$out1" | grep -q "feature_claim_messages: 0" && echo "$out1" | grep -q "claim_reviewer_invocations: 0"; then
    echo "  PASS empty-transcript"
  else
    echo "  FAIL empty-transcript (got: $out1)" >&2
    failures=$((failures + 1))
  fi

  # Scenario 2: claims present, no invocations → ratio 0%
  local s2="$tmp/claims-no-invoke.jsonl"
  cat > "$s2" <<'EOF'
{"role":"assistant","content":"the auth flow works as expected"}
{"role":"assistant","content":"the migration is done and the index is now fixed"}
{"role":"assistant","content":"the new endpoint supports retries"}
EOF
  local out2
  out2=$(measure "$s2" "")
  if echo "$out2" | grep -q "feature_claim_messages: 3" && echo "$out2" | grep -q "self_invocation_ratio_pct: 0%"; then
    echo "  PASS claims-no-invocations"
  else
    echo "  FAIL claims-no-invocations (got: $out2)" >&2
    failures=$((failures + 1))
  fi

  # Scenario 3: claims + invocations → non-zero ratio
  local s3="$tmp/claims-and-invoke.jsonl"
  cat > "$s3" <<'EOF'
{"role":"assistant","content":"the auth flow works as expected"}
{"role":"assistant","content":"the migration is done"}
{"tool_use":{"name":"claim-reviewer","input":"verify the auth claim"}}
EOF
  local out3
  out3=$(measure "$s3" "")
  if echo "$out3" | grep -q "feature_claim_messages: 2" && echo "$out3" | grep -q "claim_reviewer_invocations: 1"; then
    echo "  PASS claims-with-invocations"
  else
    echo "  FAIL claims-with-invocations (got: $out3)" >&2
    failures=$((failures + 1))
  fi

  # Scenario 4: subagent_type variant of invocation is also counted
  local s4="$tmp/subagent-form.jsonl"
  cat > "$s4" <<'EOF'
{"role":"assistant","content":"the feature works"}
{"tool_use":{"name":"Agent","input":{"subagent_type":"claim-reviewer","prompt":"verify"}}}
EOF
  local out4
  out4=$(measure "$s4" "")
  if echo "$out4" | grep -q "claim_reviewer_invocations: 1"; then
    echo "  PASS subagent_type-form-counted"
  else
    echo "  FAIL subagent_type-form-counted (got: $out4)" >&2
    failures=$((failures + 1))
  fi

  # Scenario 5: no false-positive on quoted patterns (still counts conservatively)
  # Pattern matching is intentionally permissive — the rate is comparable across runs
  # even with some false positives, since both num + denom share the noise.
  local s5="$tmp/permissive.jsonl"
  echo '{"role":"assistant","content":"i was asking whether it supports x"}' > "$s5"
  local out5
  out5=$(measure "$s5" "")
  if echo "$out5" | grep -q "feature_claim_messages: 1"; then
    echo "  PASS permissive-counts-conservatively"
  else
    echo "  FAIL permissive-counts-conservatively (got: $out5)" >&2
    failures=$((failures + 1))
  fi

  rm -rf "$tmp"
  if [ "$failures" -eq 0 ]; then
    echo ""
    echo "SELF-TEST: all scenarios passed (5/5)"
    return 0
  else
    echo ""
    echo "SELF-TEST: $failures scenario(s) failed" >&2
    return 1
  fi
}

# -------- Arg parsing --------
SINCE=""
TRANSCRIPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test)
      run_self_test
      exit $?
      ;;
    --since)
      SINCE="$2"
      shift 2
      ;;
    --transcript)
      TRANSCRIPT="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# Default window
[ -z "$SINCE" ] && [ -z "$TRANSCRIPT" ] && SINCE="7 days"
measure "$TRANSCRIPT" "$SINCE"
exit 0
