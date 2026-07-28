#!/bin/bash
# estate-brief.sh — Accountable Estate program, T1 (docs/plans/
# accountable-estate-program-2026-07.md): renders estate-janitor.sh's
# snapshot.json into a SCANNABLE TEXT BRIEF. This script IS the outcome
# metric's surface: "what is running and who asked... answerable from
# ONE surface in <30s" (plan T1) / "Daily brief (generated artifact, <=1
# screen): running now... your asks with deadlines... cost+throughput
# counters" (docs/designs/accountable-estate-2026-07-27.md §4).
#
# House law (design §6b directive): "lists, no paragraphs." Every section
# below is a flat list, capped for scannability (ESTATE_BRIEF_MAX_ROWS,
# default 20 per section — a "+N more" line covers the rest so a
# 94-worktree estate still renders as ONE screen, not a wall of text).
#
# ============================================================
# USAGE
# ============================================================
#   estate-brief.sh [--snapshot <path>] [--write]
#     Renders the brief to stdout. --snapshot overrides the snapshot.json
#     path (default: ${ESTATE_STATE_DIR:-~/.claude/state/estate}/snapshot.json).
#     --write ALSO persists the identical rendered text to
#     <snapshot-dir>/brief.txt (the file a scheduled task/operator reads
#     without re-running anything).
#   estate-brief.sh --self-test
#
# ============================================================
# DEGRADATION CONTRACT
# ============================================================
# A missing/unreadable snapshot, a missing jq binary, or a malformed
# snapshot field all render an HONEST placeholder line for that section
# (never a crash, never fabricated data). Exit code is always 0 except
# --self-test failure.
#
# ============================================================
# SANDBOXING
# ============================================================
#   ESTATE_STATE_DIR   snapshot.json's directory (inherited contract,
#                       estate-janitor.sh) — also where brief.txt lands.
#   ESTATE_SNAPSHOT_PATH  explicit override for the snapshot file itself
#                       (self-test uses this to point at a fixture).
#
# Double-guard (house pattern, see estate-janitor.sh's own header for the
# full rationale): keys on BOTH HARNESS_SELFTEST=1 and a direct
# --self-test argv.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
MODE="${1:-brief}"

if [[ "${HARNESS_SELFTEST:-0}" == "1" ]] || [[ "$MODE" == "--self-test" ]]; then
  export HARNESS_SELFTEST=1
fi

_eb_state_dir() {
  if [[ -n "${ESTATE_STATE_DIR:-}" ]]; then
    printf '%s' "$ESTATE_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/estate-janitor-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/estate' "${HOME:-$PWD}"
}

_eb_snapshot_path() {
  if [[ -n "${ESTATE_SNAPSHOT_PATH:-}" ]]; then
    printf '%s' "$ESTATE_SNAPSHOT_PATH"
    return 0
  fi
  printf '%s/snapshot.json' "$(_eb_state_dir)"
}

# ----------------------------------------------------------------------
# _eb_age_str <iso-ts> — "Nm ago" / "Nh ago" / "Nd ago", or "unknown" on
# any parse failure. Never errors.
# ----------------------------------------------------------------------
_eb_age_str() {
  local ts="$1"
  [[ -n "$ts" ]] || { printf 'unknown'; return 0; }
  local epoch
  epoch="$(date -u -d "$ts" '+%s' 2>/dev/null)"
  if [[ -z "$epoch" ]]; then
    epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null)"
  fi
  [[ -n "$epoch" && "$epoch" =~ ^[0-9]+$ ]] || { printf 'unknown'; return 0; }
  local now; now="$(date -u +%s 2>/dev/null || echo 0)"
  local diff=$(( now - epoch ))
  [[ "$diff" -lt 0 ]] && diff=0
  local mins=$(( diff / 60 ))
  if [[ "$mins" -lt 60 ]]; then
    printf '%dm ago' "$mins"
  elif [[ "$mins" -lt 1440 ]]; then
    printf '%dh ago' "$(( mins / 60 ))"
  else
    printf '%dd ago' "$(( mins / 1440 ))"
  fi
}

# _eb_short <string> <maxlen> — truncate with "..." for scannability.
_eb_short() {
  local s="$1" max="${2:-60}"
  [[ "${#s}" -le "$max" ]] && { printf '%s' "$s"; return 0; }
  printf '%s...' "${s:0:$((max-3))}"
}

_eb_render() {
  local snap; snap="$(_eb_snapshot_path)"
  local max_rows="${ESTATE_BRIEF_MAX_ROWS:-20}"

  if [[ ! -f "$snap" ]]; then
    printf 'ESTATE BRIEF — no snapshot found at %s\n' "$snap"
    printf '  Run: estate-janitor.sh run   (then re-run this brief)\n'
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ESTATE BRIEF — jq is not available; cannot render structured brief.\n'
    printf '  Raw snapshot: %s\n' "$snap"
    return 0
  fi
  if ! jq -e . "$snap" >/dev/null 2>&1; then
    printf 'ESTATE BRIEF — snapshot at %s is not valid JSON (write may be in progress); try again.\n' "$snap"
    return 0
  fi

  local generated_at machine
  generated_at="$(jq -r '.generated_at // "unknown"' "$snap")"
  machine="$(jq -r '.machine // "unknown"' "$snap")"
  local age; age="$(_eb_age_str "$generated_at")"

  printf 'ESTATE BRIEF — generated %s (%s) — %s\n' "$generated_at" "$age" "$machine"
  printf '\n'

  # ---- RUNNING ----
  local n_sessions n_live n_stale n_throttled n_crashed n_unknown
  n_sessions="$(jq -r '.sessions | length' "$snap")"
  n_live="$(jq -r '[.sessions[] | select(.classify=="live")] | length' "$snap")"
  n_stale="$(jq -r '[.sessions[] | select(.classify=="stale")] | length' "$snap")"
  n_throttled="$(jq -r '[.sessions[] | select(.classify=="throttled")] | length' "$snap")"
  n_crashed="$(jq -r '[.sessions[] | select(.classify=="crashed")] | length' "$snap")"
  n_unknown="$(jq -r '[.sessions[] | select(.classify!="live" and .classify!="stale" and .classify!="throttled" and .classify!="crashed")] | length' "$snap")"
  printf 'RUNNING (%s sessions: %s live, %s stale, %s throttled, %s crashed, %s unknown)\n' \
    "$n_sessions" "$n_live" "$n_stale" "$n_throttled" "$n_crashed" "$n_unknown"
  if [[ "$n_sessions" -eq 0 ]]; then
    printf '  (none)\n'
  else
    local line sid cls branch last_event last_ts wt
    while IFS=$'\t' read -r sid cls branch wt last_event last_ts; do
      # PROVEN at build time (od -c on this platform's jq @tsv output): jq
      # emits a CRLF line ending, so the LAST field of every row carries a
      # trailing \r that is invisible when printed but breaks any exact
      # match against that field. Strip unconditionally (no-op if absent).
      last_ts="${last_ts%$'\r'}"
      printf '  %s | %-9s | branch=%s | %s (%s) | wt=%s\n' \
        "${sid:0:12}" "$cls" "$branch" "$last_event" "$(_eb_age_str "$last_ts")" "$(_eb_short "$wt" 40)"
    done < <(jq -r --argjson n "$max_rows" '.sessions[:$n][] | [.session_id,.classify,.branch,.worktree_root,.last_event,.last_activity_ts] | @tsv' "$snap")
    if [[ "$n_sessions" -gt "$max_rows" ]]; then
      printf '  ... +%s more\n' "$(( n_sessions - max_rows ))"
    fi
  fi
  printf '\n'

  # ---- ASKED ----
  local n_asks; n_asks="$(jq -r '.asks | length' "$snap")"
  local asks_degraded; asks_degraded="$(jq -r '.asks_degraded' "$snap")"
  printf 'ASKED (%s active)%s\n' "$n_asks" "$([[ "$asks_degraded" == "true" ]] && echo ' [DEGRADED: ask-registry unreadable or jq missing]' || echo '')"
  if [[ "$n_asks" -eq 0 ]]; then
    printf '  (none)\n'
  else
    local ask_id summary project
    while IFS=$'\t' read -r ask_id summary project; do
      project="${project%$'\r'}"   # jq @tsv CRLF quirk — see RUNNING section comment
      printf '  %s | %s | %s\n' "$ask_id" "$(_eb_short "$summary" 70)" "$project"
    done < <(jq -r --argjson n "$max_rows" '.asks[:$n][] | [.ask_id,.summary,.project] | @tsv' "$snap")
    if [[ "$n_asks" -gt "$max_rows" ]]; then
      printf '  ... +%s more\n' "$(( n_asks - max_rows ))"
    fi
  fi
  printf '\n'

  # ---- ORPHANED WORKTREES ----
  local n_owt; n_owt="$(jq -r '.orphaned_worktrees | length' "$snap")"
  printf 'ORPHANED WORKTREES (%s found — no live heartbeat)\n' "$n_owt"
  if [[ "$n_owt" -eq 0 ]]; then
    printf '  (none)\n'
  else
    local repo path branch
    while IFS=$'\t' read -r repo path branch; do
      branch="${branch%$'\r'}"   # jq @tsv CRLF quirk — see RUNNING section comment
      printf '  %s | branch=%s | %s\n' "$(_eb_short "$path" 55)" "$branch" "$(_eb_short "$repo" 30)"
    done < <(jq -r --argjson n "$max_rows" '.orphaned_worktrees[:$n][] | [.repo,.path,.branch] | @tsv' "$snap")
    if [[ "$n_owt" -gt "$max_rows" ]]; then
      printf '  ... +%s more\n' "$(( n_owt - max_rows ))"
    fi
  fi
  printf '\n'

  # ---- ORPHANED BRANCHES ----
  local n_obr; n_obr="$(jq -r '.orphaned_branches | length' "$snap")"
  printf 'ORPHANED BRANCHES (%s found — no worktree)\n' "$n_obr"
  if [[ "$n_obr" -eq 0 ]]; then
    printf '  (none)\n'
  else
    local repo branch age_days
    while IFS=$'\t' read -r repo branch age_days; do
      age_days="${age_days%$'\r'}"   # jq @tsv CRLF quirk — see RUNNING section comment
      printf '  %s | %s | last commit %sd ago\n' "$(_eb_short "$repo" 30)" "$branch" "${age_days:-?}"
    done < <(jq -r --argjson n "$max_rows" '.orphaned_branches[:$n][] | [.repo,.branch,(.last_commit_age_days|tostring)] | @tsv' "$snap")
    if [[ "$n_obr" -gt "$max_rows" ]]; then
      printf '  ... +%s more\n' "$(( n_obr - max_rows ))"
    fi
  fi
  printf '\n'

  # ---- COUNTS ----
  local bash_count claude_count proc_degraded wt_total wt_degraded repos_n ledger_n ledger_degraded
  bash_count="$(jq -r '.process_counts.bash_count' "$snap")"
  claude_count="$(jq -r '.process_counts.claude_count' "$snap")"
  proc_degraded="$(jq -r '.process_counts.degraded' "$snap")"
  wt_total="$(jq -r '.worktrees | length' "$snap")"
  wt_degraded="$(jq -r '.worktrees_degraded' "$snap")"
  repos_n="$(jq -r '.repos_scanned | length' "$snap")"
  ledger_n="$(jq -r '.signal_ledger_tail | length' "$snap")"
  ledger_degraded="$(jq -r '.signal_ledger_degraded' "$snap")"
  printf 'COUNTS\n'
  printf '  bash.exe: %s | claude.exe: %s | worktrees: %s (across %s repos) | signal-ledger tail: %s lines\n' \
    "$bash_count" "$claude_count" "$wt_total" "$repos_n" "$ledger_n"

  local -a degraded_flags=()
  [[ "$(jq -r '.sessions_degraded' "$snap")" == "true" ]] && degraded_flags+=("heartbeats")
  [[ "$proc_degraded" == "true" ]] && degraded_flags+=("process_counts")
  [[ "$wt_degraded" == "true" ]] && degraded_flags+=("worktrees")
  [[ "$ledger_degraded" == "true" ]] && degraded_flags+=("signal_ledger")
  [[ "$asks_degraded" == "true" ]] && degraded_flags+=("asks")
  if [[ "${#degraded_flags[@]}" -eq 0 ]]; then
    printf '  degraded sections: none\n'
  else
    printf '  degraded sections: %s\n' "$(printf '%s,' "${degraded_flags[@]}" | sed 's/,$//')"
  fi
}

_eb_run() {
  local out
  out="$(_eb_render)"
  printf '%s\n' "$out"
  if [[ "${_EB_WRITE:-0}" == "1" ]]; then
    local dir; dir="$(_eb_state_dir)"
    mkdir -p "$dir" 2>/dev/null || true
    printf '%s\n' "$out" > "$dir/brief.txt" 2>/dev/null || true
  fi
}

# ============================================================
# --self-test
# ============================================================
_eb_self_test() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local T; T="$(mktemp -d 2>/dev/null || mktemp -d -t ebst)"
  export ESTATE_STATE_DIR="$T/estate"
  mkdir -p "$ESTATE_STATE_DIR"
  export ESTATE_SNAPSHOT_PATH="$ESTATE_STATE_DIR/snapshot.json"

  echo "Scenario 1: missing snapshot -> honest placeholder, never a crash"
  rm -f "$ESTATE_SNAPSHOT_PATH"
  local out1; out1="$(_eb_render)"
  if [[ "$out1" == *"no snapshot found"* ]]; then
    pass "missing snapshot renders an honest placeholder line"
  else
    fail "expected a 'no snapshot found' line, got: $out1"
  fi

  echo "Scenario 2: malformed JSON -> honest placeholder, never a crash"
  printf 'NOT VALID JSON{{{' > "$ESTATE_SNAPSHOT_PATH"
  local out2; out2="$(_eb_render)"
  if [[ "$out2" == *"not valid JSON"* ]]; then
    pass "malformed snapshot renders an honest placeholder line"
  else
    fail "expected a 'not valid JSON' line, got: $out2"
  fi

  echo "Scenario 3: a full fixture snapshot renders all sections with correct counts"
  cat > "$ESTATE_SNAPSHOT_PATH" <<'EOF'
{"schema":1,"generated_at":"2026-01-01T00:00:00Z","machine":"testhost","asks_fold":"simplified","repos_config_source":"default-config-file",
"sessions":[{"session_id":"sess-abc123456789","classify":"live","cwd":"/x","repo_root":"/x","worktree_root":"/x/wt","branch":"build/foo","model":"sonnet","last_activity_ts":"2026-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none","pid":1}],
"sessions_degraded":false,
"process_counts":{"bash_count":5,"claude_count":3,"degraded":false},
"worktrees":[{"repo":"/x","path":"/x/wt","head":"h","branch":"build/foo","bare":false,"detached":false,"is_main":false}],
"worktrees_degraded":false,
"orphaned_worktrees":[{"repo":"/x","path":"/x/wt-orphan","branch":"build/orphan","reason":"no_live_heartbeat"}],
"orphaned_branches":[{"repo":"/x","branch":"loose-branch","last_commit_epoch":1,"last_commit_age_days":42,"reason":"no_worktree"}],
"repos_scanned":["/x"],
"signal_ledger_tail":[{"ts":"t","gate":"g","event":"warn","detail":"d"}],
"signal_ledger_degraded":false,
"asks":[{"ask_id":"ask-xyz","summary":"Fix the thing that broke","project":"neural-lace","repo":"/x","status":"active","last_ts":"t"}],
"asks_degraded":false}
EOF
  local out3; out3="$(_eb_render)"
  [[ "$out3" == *"RUNNING (1 sessions: 1 live"* ]] && pass "RUNNING section counts 1 live session" || fail "RUNNING section count mismatch: $out3"
  [[ "$out3" == *"build/foo"* ]] && pass "session row shows the branch" || fail "session row missing branch"
  [[ "$out3" == *"ASKED (1 active)"* ]] && pass "ASKED section counts 1 active ask" || fail "ASKED count mismatch"
  [[ "$out3" == *"Fix the thing that broke"* ]] && pass "ask row shows the summary" || fail "ask row missing summary"
  [[ "$out3" == *"ORPHANED WORKTREES (1 found"* ]] && pass "orphaned worktree count correct" || fail "orphaned worktree count mismatch"
  [[ "$out3" == *"wt-orphan"* ]] && pass "orphaned worktree row shows the path" || fail "orphaned worktree row missing path"
  [[ "$out3" == *"ORPHANED BRANCHES (1 found"* ]] && pass "orphaned branch count correct" || fail "orphaned branch count mismatch"
  [[ "$out3" == *"loose-branch"* && "$out3" == *"42d ago"* ]] && pass "orphaned branch row shows branch + age" || fail "orphaned branch row missing branch/age"
  [[ "$out3" == *"bash.exe: 5"* && "$out3" == *"claude.exe: 3"* ]] && pass "COUNTS section shows process counts" || fail "COUNTS section mismatch"
  [[ "$out3" == *"degraded sections: none"* ]] && pass "no degraded sections reported when all flags are false" || fail "expected 'degraded sections: none'"

  echo "Scenario 4: a degraded snapshot surfaces which sections are degraded"
  cat > "$ESTATE_SNAPSHOT_PATH" <<'EOF'
{"schema":1,"generated_at":"2026-01-01T00:00:00Z","machine":"testhost","asks_fold":"simplified","repos_config_source":"fallback-main-checkout",
"sessions":[],"sessions_degraded":true,
"process_counts":{"bash_count":0,"claude_count":0,"degraded":true},
"worktrees":[],"worktrees_degraded":true,
"orphaned_worktrees":[],"orphaned_branches":[],"repos_scanned":[],
"signal_ledger_tail":[],"signal_ledger_degraded":true,
"asks":[],"asks_degraded":true}
EOF
  local out4; out4="$(_eb_render)"
  if [[ "$out4" == *"degraded sections:"* && "$out4" == *"heartbeats"* && "$out4" == *"process_counts"* && "$out4" == *"worktrees"* && "$out4" == *"signal_ledger"* && "$out4" == *"asks"* ]]; then
    pass "every degraded source is named in the degraded-sections line"
  else
    fail "expected all 5 degraded flags named, got: $out4"
  fi
  [[ "$out4" == *"[DEGRADED: ask-registry unreadable"* ]] && pass "ASKED section itself flags its own degradation inline" || fail "ASKED section did not flag degradation inline"

  echo "Scenario 5: --write persists the identical rendered text to brief.txt"
  _EB_WRITE=1 _eb_run >/dev/null
  if [[ -f "$ESTATE_STATE_DIR/brief.txt" ]] && grep -q "ESTATE BRIEF" "$ESTATE_STATE_DIR/brief.txt"; then
    pass "--write persists the rendered brief to brief.txt"
  else
    fail "brief.txt was not written or missing expected content"
  fi

  echo "Scenario 6: row cap keeps the brief scannable on a large estate (ESTATE_BRIEF_MAX_ROWS)"
  {
    printf '{"schema":1,"generated_at":"2026-01-01T00:00:00Z","machine":"testhost","asks_fold":"simplified","repos_config_source":"x",\n'
    printf '"sessions":[],"sessions_degraded":false,"process_counts":{"bash_count":0,"claude_count":0,"degraded":false},\n'
    printf '"worktrees":[],"worktrees_degraded":false,\n'
    printf '"orphaned_worktrees":['
    local i first=1
    for i in $(seq 1 30); do
      [[ "$first" == "1" ]] && first=0 || printf ','
      printf '{"repo":"/x","path":"/x/wt%d","branch":"b%d","reason":"no_live_heartbeat"}' "$i" "$i"
    done
    printf '],"orphaned_branches":[],"repos_scanned":["/x"],"signal_ledger_tail":[],"signal_ledger_degraded":false,"asks":[],"asks_degraded":false}\n'
  } | tr -d '\n' > "$ESTATE_SNAPSHOT_PATH"
  local out6; out6="$(ESTATE_BRIEF_MAX_ROWS=10 _eb_render)"
  [[ "$out6" == *"ORPHANED WORKTREES (30 found"* ]] && pass "full count (30) reported in the section header even though rows are capped" || fail "expected count 30 in header"
  [[ "$out6" == *"+20 more"* ]] && pass "capped display shows a '+N more' line (10 shown, 20 remaining)" || fail "expected '+20 more' line"

  rm -rf "$T" 2>/dev/null || true
  unset ESTATE_STATE_DIR ESTATE_SNAPSHOT_PATH

  echo ""
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed"
  if [[ "$FAILED" -eq 0 ]]; then
    echo "self-test: OK"
    exit 0
  else
    echo "self-test: $FAILED failed"
    exit 1
  fi
}

case "$MODE" in
  --self-test)
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
      _eb_self_test
    fi
    ;;
  --write)
    _EB_WRITE=1 _eb_run
    ;;
  brief|"")
    _eb_run
    ;;
  *)
    echo "Usage: estate-brief.sh [brief|--write|--self-test]" >&2
    exit 2
    ;;
esac
