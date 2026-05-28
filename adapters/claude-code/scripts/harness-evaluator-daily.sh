#!/usr/bin/env bash
# harness-evaluator-daily.sh
#
# Daily 5-PM-cron wrapper around harness-evaluator.sh.
# Per Misha 2026-05-28:
#   - Run `harness-evaluator.sh --mode daily`
#   - If the resulting packet surfaces high-severity drift, write a JSON
#     alert marker to ~/.claude/state/external-monitor-alerts/ so the
#     `external-monitor-alert-surfacer.sh` SessionStart hook surfaces it
#     on the next interactive Code session (the "Dispatch wakeup"
#     transport — no ntfy.sh / no phone / no email).
#
# This is the orchestration glue for #34's "Dispatch-wakeup notification
# for high-severity drift". The actual evaluator (System 2 of PR #34)
# is on master at adapters/claude-code/scripts/harness-evaluator.sh —
# this wrapper handles the post-run severity check + alert-emit.
#
# Composing the chain: cron → this script → harness-evaluator → packet
# → severity check → external-monitor-alert-surfacer marker → next
# session SessionStart surfaces the marker.
#
# Severity detection heuristics (best-effort against markdown packet):
#   - "severity: high" (any case), "high-severity", or " HIGH " in headers
#   - "P0" (priority zero) markers
#   - "CRITICAL" in headers
#   - "BLOCKED" or "BLOCKER" in headers
# Tunable via env: SEVERITY_PATTERNS="<pipe-delimited regex>"
#
# Marker format follows external-monitor-alert-surfacer.sh's contract:
#   JSON file at ~/.claude/state/external-monitor-alerts/<ISO>.json
#   containing started_at, source, packet_path, severity_hits[],
#   high_severity_count, summary.
# Acking the marker (sibling .acked file) prevents re-surfacing.
#
# Usage:
#   harness-evaluator-daily.sh                  # default flow
#   harness-evaluator-daily.sh --dry-run        # run + report; don't emit alert
#   harness-evaluator-daily.sh --self-test      # exercise rubric

set -uo pipefail

DRY_RUN=0
ALERT_DIR_DEFAULT="${HOME}/.claude/state/external-monitor-alerts"
ALERT_DIR="${HARNESS_DAILY_ALERT_DIR:-$ALERT_DIR_DEFAULT}"
HARNESS_EVAL_PATH_DEFAULT="$HOME/.claude/scripts/harness-evaluator.sh"
HARNESS_EVAL_PATH="${HARNESS_EVAL_PATH:-$HARNESS_EVAL_PATH_DEFAULT}"
# Permissive regex; both num + denom share the noise so signal is preserved.
SEVERITY_PATTERNS="${SEVERITY_PATTERNS:-severity:[[:space:]]*high|high-severity|^#+ .*HIGH |^#+ .*CRITICAL|^#+ .*BLOCKED|^#+ .*BLOCKER|\bP0\b}"

DO_SELF_TEST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --alert-dir) ALERT_DIR="$2"; shift 2 ;;
    --self-test) DO_SELF_TEST=1; shift ;;
    --help|-h) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 1 ;;
  esac
done

run_self_test() {
  local tmp
  tmp=$(mktemp -d -t harness-daily-test.XXXXXX 2>/dev/null) || tmp="/tmp/harness-daily-test.$$"
  mkdir -p "$tmp"
  local failures=0

  # --- Scenario 1: packet with high-severity → marker emitted ---
  local pkt1="$tmp/pkt-high.md"
  cat > "$pkt1" <<'EOF'
# Daily Eval 2026-05-28

## Section 1 — Bypass tally
severity: high — 5 acceptance-waivers in 24h

## Section 2 — P0 items
CRITICAL — chronic-stale plan tax

EOF
  HARNESS_DAILY_ALERT_DIR="$tmp/alerts1" detect_severity_and_emit "$pkt1"
  if ls "$tmp/alerts1"/*.json >/dev/null 2>&1; then
    echo "  PASS high-severity-emits-marker"
  else
    echo "  FAIL high-severity-emits-marker (no marker written)" >&2
    failures=$((failures + 1))
  fi

  # --- Scenario 2: packet without high-severity → no marker ---
  local pkt2="$tmp/pkt-clean.md"
  cat > "$pkt2" <<'EOF'
# Daily Eval 2026-05-28

## Section 1 — Bypass tally
0 bypass events; everything tracking healthy.

EOF
  mkdir -p "$tmp/alerts2"
  HARNESS_DAILY_ALERT_DIR="$tmp/alerts2" detect_severity_and_emit "$pkt2"
  local cnt
  cnt=$(ls "$tmp/alerts2"/*.json 2>/dev/null | wc -l | tr -d '[:space:]')
  if [ "${cnt:-0}" = "0" ]; then
    echo "  PASS clean-packet-no-marker"
  else
    echo "  FAIL clean-packet-no-marker (got $cnt markers)" >&2
    failures=$((failures + 1))
  fi

  # --- Scenario 3: P0 in header counts ---
  local pkt3="$tmp/pkt-p0.md"
  cat > "$pkt3" <<'EOF'
# Daily Eval

## P0 items needing attention
- Something urgent
EOF
  mkdir -p "$tmp/alerts3"
  HARNESS_DAILY_ALERT_DIR="$tmp/alerts3" detect_severity_and_emit "$pkt3"
  if ls "$tmp/alerts3"/*.json >/dev/null 2>&1; then
    echo "  PASS P0-marker-counted"
  else
    echo "  FAIL P0-marker-counted (no marker)" >&2
    failures=$((failures + 1))
  fi

  # --- Scenario 4: marker JSON is well-formed ---
  if command -v jq >/dev/null 2>&1; then
    local last
    last=$(ls -1 "$tmp/alerts1"/*.json 2>/dev/null | head -1)
    if [ -n "$last" ] && jq empty "$last" >/dev/null 2>&1; then
      echo "  PASS marker-is-valid-json"
    else
      echo "  FAIL marker-is-valid-json" >&2
      failures=$((failures + 1))
    fi
  else
    echo "  SKIP marker-is-valid-json (jq not available)"
  fi

  rm -rf "$tmp"
  if [ "$failures" -eq 0 ]; then
    echo ""
    echo "SELF-TEST: all scenarios passed (3-4/3-4 depending on jq)"
    return 0
  fi
  echo ""
  echo "SELF-TEST: $failures scenario(s) failed" >&2
  return 1
}

detect_severity_and_emit() {
  local packet="$1"
  [ -f "$packet" ] || { echo "[harness-daily] packet not found: $packet" >&2; return 1; }
  local hits
  hits=$(grep -iE "$SEVERITY_PATTERNS" "$packet" 2>/dev/null | head -20)
  if [ -z "$hits" ]; then
    echo "[harness-daily] no high-severity items in $packet — no Dispatch wakeup needed"
    return 0
  fi
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[harness-daily] DRY-RUN: would emit alert for these severity hits:"
    echo "$hits"
    return 0
  fi
  local dir="${HARNESS_DAILY_ALERT_DIR:-$ALERT_DIR}"
  mkdir -p "$dir"
  local ts iso
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local out="$dir/harness-daily-${ts}.json"
  local hit_count
  hit_count=$(printf '%s\n' "$hits" | wc -l | tr -d '[:space:]')
  local hits_json
  if command -v jq >/dev/null 2>&1; then
    hits_json=$(printf '%s\n' "$hits" | jq -R . | jq -s .)
  else
    # Cheap fallback — escape quotes and wrap
    hits_json=$(printf '%s\n' "$hits" | sed 's/"/\\"/g' | awk 'BEGIN{print "["}{print "  \""$0"\","}END{print "  null]"}')
  fi
  cat > "$out" <<EOF
{
  "started_at": "$iso",
  "source": "harness-evaluator-daily.sh",
  "packet_path": "$packet",
  "high_severity_count": $hit_count,
  "severity_hits": $hits_json,
  "summary": "High-severity drift detected in $hit_count items — see packet for context. Dispatch wakeup: surface this on next interactive Code session via external-monitor-alert-surfacer.sh."
}
EOF
  echo "[harness-daily] wrote alert marker: $out ($hit_count hits)"
}

# Find today's packet from harness-evaluator
find_today_packet() {
  local cwd="$1"
  local today
  today=$(date +%Y-%m-%d)
  local p1="$cwd/.claude/state/harness-eval/${today}-harness-self-eval.md"
  local p2="$cwd/docs/reviews/${today}-harness-self-eval.md"
  [ -f "$p1" ] && { echo "$p1"; return 0; }
  [ -f "$p2" ] && { echo "$p2"; return 0; }
  # Fallback to most recent packet of any date
  ls -1t "$cwd/.claude/state/harness-eval/"*.md 2>/dev/null | head -1
}

# --- Normal flow: invoke evaluator + check severity + emit marker ---
main() {
  # Run the evaluator (delegate to whatever's on $HARNESS_EVAL_PATH)
  if [ ! -f "$HARNESS_EVAL_PATH" ]; then
    echo "[harness-daily] FATAL: evaluator not found at $HARNESS_EVAL_PATH" >&2
    exit 1
  fi
  echo "[harness-daily] running evaluator: $HARNESS_EVAL_PATH --mode daily"
  bash "$HARNESS_EVAL_PATH" --mode daily 2>&1 | tail -10 || {
    echo "[harness-daily] WARNING: evaluator exited non-zero" >&2
  }
  local packet
  packet=$(find_today_packet "$PWD")
  if [ -z "$packet" ]; then
    echo "[harness-daily] WARNING: no packet found after evaluator run; skipping severity check" >&2
    exit 0
  fi
  echo "[harness-daily] checking severity in: $packet"
  detect_severity_and_emit "$packet"
  echo "[harness-daily] DONE"
}

if [ "$DO_SELF_TEST" = "1" ]; then
  run_self_test
  exit $?
fi
main
exit 0
