#!/bin/bash
# harness-hygiene-weekly.sh — Hygiene-2 PR 3 (Component 5)
#
# Weekly cron wrapper that runs three structural hygiene checks across the
# harness repo and surfaces findings via the external-monitor-alert
# mechanism (the same Dispatch-wakeup transport that
# harness-evaluator-daily.sh uses).
#
# Three checks:
#   1. CLAUDE.md size — compare line count to the 200-line ceiling.
#   2. Rules cross-file duplication — scan rules/*.md for 5+ matching
#      consecutive words shared between any two files (signals body
#      duplication that should be a pointer instead).
#   3. INDEX.md ↔ rules/ sync — invoke evals/golden/rules-index-coverage.sh
#      (the existing golden test) and report on FAIL.
#
# Findings are written to .claude/state/harness-hygiene-weekly.log and,
# when any finding fires, an alert marker is written to
# ~/.claude/state/external-monitor-alerts/ which the
# external-monitor-alert-surfacer.sh SessionStart hook then surfaces at
# the next interactive session.
#
# Installer: install-weekly-hygiene-task.ps1 (sibling) registers this
# script as a Windows Scheduled Task with weekly cadence.
#
# Usage:
#   harness-hygiene-weekly.sh              # run from repo root
#   harness-hygiene-weekly.sh /path/to/repo
#   harness-hygiene-weekly.sh --self-test
#
# Exit codes:
#   0 — completed (whether or not findings fired)
#   1 — internal error (missing tools, etc.)

set -u

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
log_to_state() {
  local repo_root="$1"
  local message="$2"
  local logfile="$repo_root/.claude/state/harness-hygiene-weekly.log"
  mkdir -p "$(dirname "$logfile")" 2>/dev/null || true
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  printf '%s | %s\n' "$ts" "$message" >> "$logfile" 2>/dev/null || true
}

write_alert_marker() {
  local title="$1"
  local detail="$2"
  local alert_dir="$HOME/.claude/state/external-monitor-alerts"
  mkdir -p "$alert_dir" 2>/dev/null || true
  local ts
  ts=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo "unknown")
  local ts_iso
  ts_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  local alert_file="$alert_dir/harness-hygiene-weekly-${ts}.json"
  # Escape any double quotes in detail for JSON
  local detail_escaped
  detail_escaped=$(printf '%s' "$detail" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 1500)
  cat > "$alert_file" 2>/dev/null <<JSON
{
  "started_at": "$ts_iso",
  "source": "harness-hygiene-weekly.sh",
  "title": "$title",
  "summary": "$detail_escaped"
}
JSON
}

# ----------------------------------------------------------------------------
# Check 1: CLAUDE.md size
# ----------------------------------------------------------------------------
check_claude_md_size() {
  local repo_root="$1"
  local threshold="${CLAUDE_MD_HYGIENE_SIZE_THRESHOLD:-200}"
  local target="$repo_root/adapters/claude-code/CLAUDE.md"
  if [[ ! -f "$target" ]]; then
    return 0
  fi
  local lines
  lines=$(wc -l < "$target" 2>/dev/null | tr -d '[:space:]')
  [[ -z "$lines" ]] && return 0
  if [[ "$lines" -gt "$threshold" ]]; then
    printf 'SIZE: CLAUDE.md is %s lines (threshold %s). Extract bodies to rules/<name>.md.\n' "$lines" "$threshold"
  fi
}

# ----------------------------------------------------------------------------
# Check 2: cross-file duplication in rules/
# Sample-based: for each rule file, take a 5-word window from a representative
# substantive line (the first non-heading line with >40 chars), then grep for
# it in every other rule file. Cheap and false-positive-tolerant.
# ----------------------------------------------------------------------------
check_rules_cross_duplication() {
  local repo_root="$1"
  local rules_dir="$repo_root/adapters/claude-code/rules"
  [[ ! -d "$rules_dir" ]] && return 0
  local rule_file other_file basename other_base
  for rule_file in "$rules_dir"/*.md; do
    [[ -f "$rule_file" ]] || continue
    basename=$(basename "$rule_file")
    [[ "$basename" == "INDEX.md" ]] && continue
    # Pick a representative substantive line (skip headings, code blocks, links)
    local sample
    sample=$(grep -v -E '^#|^```|^\[|^---|^$|^- |^>' "$rule_file" 2>/dev/null \
      | awk 'length($0) > 40 { print; exit }')
    [[ -z "$sample" ]] && continue
    # Extract first ~5-word window
    local window
    window=$(printf '%s' "$sample" | awk '{ for (i=1; i<=5 && i<=NF; i++) printf "%s ", $i; print "" }' | sed 's/ *$//')
    [[ "${#window}" -lt 25 ]] && continue
    for other_file in "$rules_dir"/*.md; do
      [[ -f "$other_file" ]] || continue
      [[ "$other_file" == "$rule_file" ]] && continue
      other_base=$(basename "$other_file")
      [[ "$other_base" == "INDEX.md" ]] && continue
      if grep -F -q -- "$window" "$other_file" 2>/dev/null; then
        printf 'DUPLICATION: 5-word window from %s also appears in %s — review whether both files own the same body or one should reference the other. Window: "%s"\n' "$basename" "$other_base" "$window"
        return 0
      fi
    done
  done
}

# ----------------------------------------------------------------------------
# Check 3: INDEX.md ↔ rules/ sync via existing golden test
# ----------------------------------------------------------------------------
check_index_sync() {
  local repo_root="$1"
  local golden="$repo_root/evals/golden/rules-index-coverage.sh"
  if [[ ! -f "$golden" ]]; then
    printf 'INDEX-SYNC: golden test not found at %s\n' "$golden"
    return 0
  fi
  if ! bash "$golden" >/dev/null 2>&1; then
    printf 'INDEX-SYNC: evals/golden/rules-index-coverage.sh FAILED — INDEX.md is out of sync with rules/*.md. Run the script directly for the specific delta.\n'
  fi
}

# ----------------------------------------------------------------------------
# Self-test (minimal — exercises each check's no-op path on a temp dir)
# ----------------------------------------------------------------------------
if [[ "${1:-}" = "--self-test" ]]; then
  PASS=0; FAIL=0
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t hhwst)
  # shellcheck disable=SC2064
  trap "rm -rf '$TMP'" EXIT

  # Scenario 1: empty repo dir => all checks no-op
  out=$(check_claude_md_size "$TMP" 2>&1)
  if [[ -z "$out" ]]; then echo "PASS  s1 size no-op on empty repo"; PASS=$((PASS+1));
  else echo "FAIL  s1 unexpected output: $out"; FAIL=$((FAIL+1)); fi

  out=$(check_rules_cross_duplication "$TMP" 2>&1)
  if [[ -z "$out" ]]; then echo "PASS  s2 dup no-op on empty repo"; PASS=$((PASS+1));
  else echo "FAIL  s2 unexpected output: $out"; FAIL=$((FAIL+1)); fi

  out=$(check_index_sync "$TMP" 2>&1)
  # No golden script in tmp => message is "INDEX-SYNC: golden test not found"
  if echo "$out" | grep -qF "golden test not found"; then echo "PASS  s3 index-sync no-golden message"; PASS=$((PASS+1));
  else echo "FAIL  s3 unexpected output: $out"; FAIL=$((FAIL+1)); fi

  # Scenario 4: CLAUDE.md > threshold
  mkdir -p "$TMP/adapters/claude-code"
  printf 'line %s\n' {1..250} > "$TMP/adapters/claude-code/CLAUDE.md"
  out=$(check_claude_md_size "$TMP" 2>&1)
  if echo "$out" | grep -qE "^SIZE: CLAUDE.md is 25[01]"; then echo "PASS  s4 size threshold exceeded fires"; PASS=$((PASS+1));
  else echo "FAIL  s4 unexpected output: $out"; FAIL=$((FAIL+1)); fi

  # Scenario 5: CLAUDE.md under threshold
  printf 'line %s\n' {1..50} > "$TMP/adapters/claude-code/CLAUDE.md"
  out=$(check_claude_md_size "$TMP" 2>&1)
  if [[ -z "$out" ]]; then echo "PASS  s5 size under threshold silent"; PASS=$((PASS+1));
  else echo "FAIL  s5 unexpected output: $out"; FAIL=$((FAIL+1)); fi

  echo ""
  echo "Result: $PASS passed, $FAIL failed"
  [[ "$FAIL" -gt 0 ]] && exit 1
  exit 0
fi

# ----------------------------------------------------------------------------
# Live path
# ----------------------------------------------------------------------------
REPO_ROOT="${1:-$PWD}"
if [[ ! -d "$REPO_ROOT" ]]; then
  echo "[harness-hygiene-weekly] repo path not a directory: $REPO_ROOT" >&2
  exit 1
fi

log_to_state "$REPO_ROOT" "harness-hygiene-weekly run started"

FINDINGS=""
sz=$(check_claude_md_size "$REPO_ROOT")
[[ -n "$sz" ]] && FINDINGS+="$sz"$'\n'

dp=$(check_rules_cross_duplication "$REPO_ROOT")
[[ -n "$dp" ]] && FINDINGS+="$dp"$'\n'

ix=$(check_index_sync "$REPO_ROOT")
[[ -n "$ix" ]] && FINDINGS+="$ix"$'\n'

if [[ -z "$FINDINGS" ]]; then
  log_to_state "$REPO_ROOT" "harness-hygiene-weekly: no findings"
  echo "[harness-hygiene-weekly] no findings — all checks PASS"
  exit 0
fi

# Findings present — log + surface
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  log_to_state "$REPO_ROOT" "FINDING: $f"
done <<< "$FINDINGS"

write_alert_marker "Harness hygiene weekly findings" "$FINDINGS"

echo "[harness-hygiene-weekly] findings written to .claude/state/harness-hygiene-weekly.log and alert marker emitted:" >&2
printf '%s' "$FINDINGS" | sed 's/^/  /' >&2

exit 0
