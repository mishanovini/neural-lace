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

  # T1 perf fix (2026-07-28, same class as the janitor's, measured live):
  # the section-by-section render forked jq ~34 times plus two command
  # substitutions PER ROW (_eb_age_str/_eb_short are pure bash, but `$()`
  # forks a subshell regardless) — ~70 forks ≈ 38.6s wall on this machine
  # under load, missing the <30s outcome metric on the READ path. The
  # ENTIRE brief now renders in ONE jq program (age + truncation computed
  # jq-side, mirroring _eb_age_str/_eb_short's exact output formats, which
  # stay for the no-jq path and other callers). One fork ≈ seconds.
  local now_epoch; now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
  jq -r --argjson maxn "$max_rows" --argjson now "$now_epoch" '
    def agestr(ts):
      if (ts // "") == "" then "unknown"
      else ((ts | try fromdateiso8601 catch null) as $e |
        if $e == null then "unknown"
        else (([$now - $e, 0] | max) as $d | ($d / 60 | floor) as $m |
          if $m < 60 then "\($m)m ago"
          elif $m < 1440 then "\($m / 60 | floor)h ago"
          else "\($m / 1440 | floor)d ago" end)
        end)
      end;
    def short(mx): (. // "") | if length <= mx then . else .[0:mx-3] + "..." end;
    def more(total): if total > $maxn then ["  ... +\(total - $maxn) more"] else [] end;
    (.sessions // []) as $ss | (.asks // []) as $asks |
    (.orphaned_worktrees // []) as $owt | (.orphaned_branches // []) as $obr |
    (
      ["ESTATE BRIEF — generated \(.generated_at // "unknown") (\(agestr(.generated_at))) — \(.machine // "unknown")", ""]
      + ["RUNNING (\($ss | length) sessions: \([$ss[] | select(.classify == "live")] | length) live, \([$ss[] | select(.classify == "stale")] | length) stale, \([$ss[] | select(.classify == "throttled")] | length) throttled, \([$ss[] | select(.classify == "crashed")] | length) crashed, \([$ss[] | select(.classify != "live" and .classify != "stale" and .classify != "throttled" and .classify != "crashed")] | length) unknown)"]
      + (if ($ss | length) == 0 then ["  (none)"] else
          [$ss[:$maxn][] | "  \((.session_id // "")[0:12]) | \((.classify + "         ")[0:9]) | branch=\(.branch // "") | \(.last_event // "") (\(agestr(.last_activity_ts))) | wt=\(.worktree_root | short(40))"]
          + more($ss | length)
        end)
      + [""]
      + ["ASKED (\($asks | length) active)\(if .asks_degraded == true then " [DEGRADED: ask-registry unreadable or jq missing]" else "" end)"]
      + (if ($asks | length) == 0 then ["  (none)"] else
          [$asks[:$maxn][] | "  \(.ask_id) | \(.summary | short(70)) | \(.project // "")"]
          + more($asks | length)
        end)
      + [""]
      + ["ORPHANED WORKTREES (\($owt | length) found — no live heartbeat)"]
      + (if ($owt | length) == 0 then ["  (none)"] else
          [$owt[:$maxn][] | "  \(.path | short(55)) | branch=\(.branch // "unknown") | \(.repo | short(30))"]
          + more($owt | length)
        end)
      + [""]
      + ["ORPHANED BRANCHES (\($obr | length) found — no worktree)"]
      + (if ($obr | length) == 0 then ["  (none)"] else
          [$obr[:$maxn][] | "  \(.repo | short(30)) | \(.branch) | last commit \(.last_commit_age_days // "?" | tostring)d ago"]
          + more($obr | length)
        end)
      + [""]
      + ["COUNTS",
         "  bash.exe: \(.process_counts.bash_count) | claude.exe: \(.process_counts.claude_count) | worktrees: \(.worktrees | length) (across \(.repos_scanned | length) repos) | signal-ledger tail: \(.signal_ledger_tail | length) lines",
         "  degraded sections: \(
           ([if .sessions_degraded == true then "heartbeats" else empty end,
             if .process_counts.degraded == true then "process_counts" else empty end,
             if .worktrees_degraded == true then "worktrees" else empty end,
             if .signal_ledger_degraded == true then "signal_ledger" else empty end,
             if .asks_degraded == true then "asks" else empty end]) as $f |
           if ($f | length) == 0 then "none" else ($f | join(",")) end)"]
    ) | .[]
  ' "$snap"
  return 0
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
