#!/bin/bash
# stalled-work-surfacer.sh — SessionStart hook
#
# Makes silently-stalled background work IMPOSSIBLE to forget.
#
# Originating failure (2026-06-13): a background Workflow (wf_b0ebc82b-7e1) ran 3
# of its 4 agents, then the 4th (synthesis) started and never returned. The task
# died. Nothing told the orchestrator — background workflows only notify on
# COMPLETION, so a stall is invisible — and the orchestrator kept telling the
# operator "it's running in the background, it'll auto-resume me." It wasn't, and
# it didn't. The operator caught it. Misha's directive: "We CANNOT have a system
# that allows activity like that to simply stall and be forgotten" + "what do we
# do with real lessons?" — encode them (diagnosis.md "After Every Failure: Encode
# the Fix"; principles.md Rule 6 preemptive-over-symptom). This hook is that encode.
#
# Mechanism: at every session start, scan recent background-Workflow journals for
# the STALL SIGNATURE and surface each so it is seen, never silently dropped.
#
# STALL SIGNATURE (per workflow run's journal.jsonl):
#   (count of "type":"started" agent events)  >  (count of "type":"result" events)
#   AND the journal's last-modified time is older than STALLED_WORK_STALE_MIN
#       (default 10 min — distinguishes "stalled" from "actively running")
#   AND no sibling <run>/.stall-acked marker (operator/agent already recovered it)
#   AND the journal is within STALLED_WORK_LOOKBACK_MIN (default 48h — don't
#       resurrect ancient runs).
# A COMPLETED run has started==result (every agent returned) → never flagged.
# A RUNNING run has started>result but a FRESH mtime → not yet stalled, not flagged.
#
# To stop a recovered stall from re-surfacing: `touch <run-dir>/.stall-acked`.
#
# Exits 0 ALWAYS (informational; never blocks session start). Silent when nothing
# is stalled or no workflow journals exist.
#
# Self-test: --self-test exercises stalled / completed / still-running / acked / none.

set -u

STALE_MIN="${STALLED_WORK_STALE_MIN:-10}"
LOOKBACK_MIN="${STALLED_WORK_LOOKBACK_MIN:-2880}"   # 48h
# Roots to scan (override for self-test). Default: all workflow runs under the
# Claude projects tree on this machine.
SCAN_ROOT="${STALLED_WORK_SCAN_ROOT:-$HOME/.claude/projects}"

now=$(date +%s 2>/dev/null) || exit 0

# Emit one block per stalled run. Returns count via global STALL_COUNT.
scan() {
  STALL_COUNT=0
  local journal dir mt age started result runid script hint
  # find journals; tolerate none
  while IFS= read -r journal; do
    [ -f "$journal" ] || continue
    dir="$(dirname "$journal")"
    [ -f "$dir/.stall-acked" ] && continue
    mt=$(stat -c %Y "$journal" 2>/dev/null || stat -f %m "$journal" 2>/dev/null) || continue
    age=$(( (now - mt) / 60 ))                       # minutes since last activity
    [ "$age" -lt "$STALE_MIN" ] && continue          # still active → not stalled
    [ "$age" -gt "$LOOKBACK_MIN" ] && continue       # too old → out of window
    started=$(grep -c '"type"[[:space:]]*:[[:space:]]*"started"' "$journal" 2>/dev/null || echo 0)
    result=$(grep -c '"type"[[:space:]]*:[[:space:]]*"result"' "$journal" 2>/dev/null || echo 0)
    # STALL: an agent started but never produced a result.
    if [ "${started:-0}" -gt "${result:-0}" ]; then
      runid="$(basename "$dir")"
      if [ "$STALL_COUNT" -eq 0 ]; then
        echo "[stalled-work] Background work STALLED and was never completed — recover or it is lost:"
      fi
      # best-effort: find the script for resume
      script="$(ls "$dir"/../../workflows/scripts/*"${runid#wf_}"*.js 2>/dev/null | head -n1)"
      echo "  • run ${runid}: ${started} agent(s) started, only ${result} returned (1+ stalled) | last activity ${age} min ago"
      echo "      dir: ${dir}"
      [ -n "$script" ] && echo "      resume: Workflow({scriptPath: \"${script}\", resumeFromRunId: \"${runid}\"})  (completed agents return cached)"
      echo "      recover: completed agents' results are in ${dir}/journal.jsonl (type:result); synthesize the rest in the foreground, then: touch ${dir}/.stall-acked"
      STALL_COUNT=$((STALL_COUNT+1))
    fi
  done < <(find "$SCAN_ROOT" -type f -path '*/subagents/workflows/*/journal.jsonl' 2>/dev/null)
}

run() {
  # (1) Stalled background WORKFLOWS (journal started>result + stale mtime).
  local did_workflow_note=0
  if [ -d "$SCAN_ROOT" ]; then
    scan
    if [ "${STALL_COUNT:-0}" -gt 0 ]; then
      echo "  Per ~/.claude/doctrine/background-work-tracking.md: a launched background task is a tracked"
      echo "  obligation until its result is consumed. Never report it 'running' without checking it."
      did_workflow_note=1
    fi
  fi
  # (2) Stalled background AGENTS (per-agent heartbeat watchdog — the interim
  #     Pattern from docs/lessons/2026-07-14-background-agent-heartbeat-watchdog.md).
  local agent_hb; agent_hb="$(dirname "$0")/../scripts/agent-heartbeat.sh"
  [ -f "$agent_hb" ] || agent_hb="$HOME/.claude/scripts/agent-heartbeat.sh"
  if [ -f "$agent_hb" ]; then
    local agentout; agentout="$(bash "$agent_hb" watch 2>/dev/null)"
    if [ -n "$agentout" ]; then
      printf '%s\n' "$agentout"
      [ "$did_workflow_note" -eq 0 ] && echo "  Per ~/.claude/doctrine/background-work-tracking.md: a launched background task is a tracked obligation until its result is consumed."
    fi
  fi
  exit 0
}

# ============================ SELF-TEST ============================
self_test() {
  local tmp pass=0 fail=0 out
  tmp="$(mktemp -d)"
  mkrun() { # $1=runid  $2=started  $3=result  $4=age_min  [$5=acked]
    local d="$tmp/projects/p/s/subagents/workflows/$1"
    mkdir -p "$d"
    : > "$d/journal.jsonl"
    local i
    for ((i=0;i<$2;i++)); do echo '{"type":"started","agentId":"a'"$i"'"}' >> "$d/journal.jsonl"; done
    for ((i=0;i<$3;i++)); do echo '{"type":"result","agentId":"a'"$i"'"}' >> "$d/journal.jsonl"; done
    [ "${5:-}" = "acked" ] && touch "$d/.stall-acked"
    # set mtime to $4 minutes ago
    local secs=$(( $4 * 60 ))
    touch -d "@$(( $(date +%s) - secs ))" "$d/journal.jsonl" 2>/dev/null \
      || touch -t "$(date -d "@$(( $(date +%s) - secs ))" +%Y%m%d%H%M.%S 2>/dev/null)" "$d/journal.jsonl" 2>/dev/null || true
  }
  # Sandbox the agent-heartbeat namespace too, so run() step (2) never scans the
  # real ~/.claude/state/heartbeats/agents and pollutes these workflow scenarios.
  mkdir -p "$tmp/hb/agents"
  run_scan() { STALLED_WORK_SCAN_ROOT="$tmp/projects" STALLED_WORK_STALE_MIN=10 HEARTBEAT_STATE_DIR="$tmp/hb" bash "$0" </dev/null 2>/dev/null; }

  # T1 stalled: 4 started, 3 result, 30 min old → surfaced
  mkrun wf_stall 4 3 30
  out="$(run_scan)"
  if echo "$out" | grep -q "wf_stall"; then echo "T1 stalled-surfaced: PASS"; pass=$((pass+1)); else echo "T1 stalled-surfaced: FAIL"; fail=$((fail+1)); fi

  # T2 completed: 4 started, 4 result, 30 min old → NOT surfaced
  mkrun wf_done 4 4 30
  out="$(run_scan)"
  if ! echo "$out" | grep -q "wf_done"; then echo "T2 completed-not-surfaced: PASS"; pass=$((pass+1)); else echo "T2 completed-not-surfaced: FAIL"; fail=$((fail+1)); fi

  # T3 still-running: 4 started, 3 result, but 2 min old (fresh) → NOT surfaced
  mkrun wf_running 4 3 2
  out="$(run_scan)"
  if ! echo "$out" | grep -q "wf_running"; then echo "T3 fresh-not-surfaced: PASS"; pass=$((pass+1)); else echo "T3 fresh-not-surfaced: FAIL"; fail=$((fail+1)); fi

  # T4 acked stall: 4 started, 3 result, 30 min old, .stall-acked → NOT surfaced
  mkrun wf_acked 4 3 30 acked
  out="$(run_scan)"
  if ! echo "$out" | grep -q "wf_acked"; then echo "T4 acked-suppressed: PASS"; pass=$((pass+1)); else echo "T4 acked-suppressed: FAIL"; fail=$((fail+1)); fi

  # T5 no workflows at all (and empty agent namespace) → silent
  out="$(STALLED_WORK_SCAN_ROOT="$tmp/empty" HEARTBEAT_STATE_DIR="$tmp/hb" bash "$0" </dev/null 2>/dev/null)"
  if [ -z "$out" ]; then echo "T5 no-workflows-silent: PASS"; pass=$((pass+1)); else echo "T5 no-workflows-silent: FAIL"; fail=$((fail+1)); fi

  # T6 stalled AGENT (heartbeat 40 min old) surfaces through the surfacer's step (2)
  local old6=$(( $(date +%s) - 40*60 ))
  printf '{"schema":"agent-heartbeat/v1","agent_id":"agent-wedged","step":"committed","note":"hung","ts":%s,"pid":1,"long":false}\n' "$old6" > "$tmp/hb/agents/agent-wedged.json"
  out="$(run_scan)"
  if echo "$out" | grep -q "agent-wedged"; then echo "T6 stalled-agent-surfaced: PASS"; pass=$((pass+1)); else echo "T6 stalled-agent-surfaced: FAIL"; fail=$((fail+1)); fi
  rm -f "$tmp/hb/agents/agent-wedged.json"

  rm -rf "$tmp"
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
run
