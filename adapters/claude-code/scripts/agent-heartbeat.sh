#!/bin/bash
# agent-heartbeat.sh — per-AGENT liveness heartbeat writer + watchdog.
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
# Lesson docs/lessons/2026-07-14-background-agent-heartbeat-watchdog.md: a
# background agent committed its work then HUNG; the orchestrator, polling the
# agent's 0-byte output file, could not tell "wedged" from "busy" and idled
# ~5 hours. Absence of output != absence of life. The fix is to INVERT the
# signal — the agent PUSHES a {step,note,ts} heartbeat at each milestone, and a
# watchdog flags any agent whose heartbeat has gone stale. A truly hung agent
# CANNOT heartbeat, so the STOPPING of the heartbeat is the clean hang signal
# where the stopping of output is not (Erlang OTP / systemd WatchdogSec= /
# k8s liveness / Chandra-Toueg <>P).
#
# HONEST SCOPE (constitution §10 — no theater): the true Mechanism is a runtime
# auto-heartbeat inside Anthropic's Agent/Workflow runtime, which is NOT in this
# repo. This ships the INTERIM PATTERN: dispatched agents CALL `emit` at their
# milestones (per the dispatch convention in doctrine/background-work-tracking.md),
# and `watch` (wired into stalled-work-surfacer.sh) flags stale ones. Detection
# therefore covers agents that emitted at least one heartbeat then stopped — the
# worked-then-wedged class the 2026-07-14 lesson exemplifies (conditional on the
# emit convention being followed by future dispatches; the lesson's own agent
# predated it and emitted nothing). Agents that never emit are out of this
# mechanism's reach (workflows are separately covered by stalled-work-surfacer.sh's
# started>result signature).
#
# The session-level equivalent is session-heartbeat.sh (frozen schema C1); this
# is deliberately a SEPARATE agent-scoped namespace (heartbeats/agents/<id>.json)
# so agent heartbeats do NOT pollute the session board (nl status / od_sessions)
# and the session-resumer never tries to `claude --resume` a subagent.
#
# ============================================================
# CONTRACT
# ============================================================
#   agent-heartbeat.sh emit --agent <id> [--step <s>] [--note <n>] [--long]
#       Atomically writes heartbeats/agents/<id>.json. NEVER BLOCKS (exit 0
#       always) — a liveness tick is observability, not enforcement. --long
#       marks the NEXT step as expected-slow, tripling that agent's own
#       staleness grace so a legitimately long step does not cry wolf.
#
#   agent-heartbeat.sh conclude --agent <id>
#       The agent's FINAL milestone on clean completion — removes its heartbeat so
#       a concluded agent is never surfaced as stalled (a hung agent that never
#       concludes ages out and IS surfaced). NEVER BLOCKS (exit 0).
#
#   agent-heartbeat.sh watch [--json] [--stale-min N]
#       Scans heartbeats/agents/*.json; prints each STALLED agent (age past
#       threshold; threshold = N (default 20) or 3N when the last beat set
#       long=true) with its last step/note/age. `.ack` sibling suppresses.
#       Exit 0 always.
#
#   agent-heartbeat.sh reap [--max-age-min N]
#       Removes agent heartbeat files older than N minutes (default 1440 = 24h)
#       so the board does not accumulate dead agents. Exit 0.
#
#   agent-heartbeat.sh --self-test
#
# SANDBOXING: honors HEARTBEAT_STATE_DIR (shared with session-heartbeat-lib.sh).
# The agent namespace is always <state-dir>/agents/.
set -uo pipefail

: "${AGENT_HB_STALE_MIN:=20}"     # default watchdog threshold (minutes)
: "${AGENT_HB_REAP_MIN:=1440}"    # default reap age (minutes)

hb_state_dir() {
  if [[ -n "${HEARTBEAT_STATE_DIR:-}" ]]; then printf '%s' "$HEARTBEAT_STATE_DIR"; return 0; fi
  printf '%s' "${HOME}/.claude/state/heartbeats"
}
agents_dir() { printf '%s/agents' "$(hb_state_dir)"; }

_now() { date -u +%s 2>/dev/null || echo 0; }

# --- json field pluck (string or number), tolerant of our own flat writer ----
_pluck() { # <file> <key>
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1
}
_pluck_num() { # <file> <key>
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null | head -1
}
_pluck_bool() { # <file> <key>
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$1" 2>/dev/null | head -1
}

# --- minimal JSON string escape (backslash, quote, strip control chars) ------
_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037'; }

cmd_emit() {
  local agent="" step="" note="" long="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="${2:-}"; shift 2 ;;
      --step)  step="${2:-}";  shift 2 ;;
      --note)  note="${2:-}";  shift 2 ;;
      --long)  long="true";    shift ;;
      *) shift ;;
    esac
  done
  [[ -z "$agent" ]] && return 0                      # never block; nothing to do
  # sanitize the id for use as a filename (no path traversal)
  local safe; safe="$(printf '%s' "$agent" | tr -c 'A-Za-z0-9._-' '_')"
  [[ -z "$safe" ]] && return 0
  local dir; dir="$(agents_dir)"
  mkdir -p "$dir" 2>/dev/null || return 0
  local path="$dir/$safe.json"
  local ts pid; ts="$(_now)"; pid="${AGENT_HB_PID:-$$}"
  local json
  json="$(printf '{"schema":"agent-heartbeat/v1","agent_id":"%s","step":"%s","note":"%s","ts":%s,"pid":%s,"long":%s}' \
    "$(_esc "$agent")" "$(_esc "$step")" "$(_esc "$note")" "$ts" "$pid" "$long")"
  local tmp; tmp="$(mktemp "${path}.XXXXXX" 2>/dev/null)" || return 0
  printf '%s\n' "$json" > "$tmp" 2>/dev/null && mv "$tmp" "$path" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

cmd_watch() {
  local json_out="false" stale_min="$AGENT_HB_STALE_MIN"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_out="true"; shift ;;
      --stale-min) stale_min="${2:-$AGENT_HB_STALE_MIN}"; shift 2 ;;
      *) shift ;;
    esac
  done
  local dir; dir="$(agents_dir)"
  [[ -d "$dir" ]] || return 0
  local now; now="$(_now)"
  local found=0 f
  for f in "$dir"/*.json; do
    [[ -e "$f" ]] || continue
    [[ -e "${f%.json}.ack" ]] && continue           # acked stalls are suppressed
    local id step note ts long thr age
    id="$(_pluck "$f" agent_id)"; step="$(_pluck "$f" step)"; note="$(_pluck "$f" note)"
    ts="$(_pluck_num "$f" ts)"; long="$(_pluck_bool "$f" long)"
    # ts fallback → file mtime (stat is the most portable on MSYS/Git Bash), so a
    # corrupt ts still ages out; 0 if even that fails, which reads as maximally stale
    # (absence must never read as fresh — the lesson's core point).
    [[ -z "$ts" ]] && ts="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
    thr=$(( stale_min * 60 ))
    [[ "$long" == "true" ]] && thr=$(( thr * 3 ))
    age=$(( now - ts ))
    if [[ "$age" -gt "$thr" ]]; then
      found=$((found+1))
      local amin=$(( age / 60 ))
      if [[ "$json_out" == "true" ]]; then
        printf '{"agent_id":"%s","step":"%s","note":"%s","age_min":%s,"stalled":true}\n' \
          "$(_esc "$id")" "$(_esc "$step")" "$(_esc "$note")" "$amin"
      else
        local long_lbl=""; [[ "$long" == "true" ]] && long_lbl=", long-grace 3x"
        [[ "$found" -eq 1 ]] && echo "[agent-watchdog] Background agent(s) STALLED — no heartbeat past threshold; ping (SendMessage) or kill+salvage:"
        echo "  • ${id:-<unknown>}: last step '${step:-?}'${note:+ ($note)} — ${amin} min stale (threshold ${stale_min}m${long_lbl})"
        echo "      ack once handled: touch ${f%.json}.ack"
      fi
    fi
  done
  return 0
}

cmd_conclude() {
  # Terminal beat — the agent's FINAL milestone on clean completion. Removes its
  # heartbeat so `watch` never surfaces a concluded agent as stalled (mirrors the
  # workflow half's started==result "never flagged" semantics). A hung agent that
  # never concludes ages out and IS surfaced — which is the whole point.
  local agent=""
  while [[ $# -gt 0 ]]; do case "$1" in --agent) agent="${2:-}"; shift 2 ;; *) shift ;; esac; done
  [[ -z "$agent" ]] && return 0
  local safe; safe="$(printf '%s' "$agent" | tr -c 'A-Za-z0-9._-' '_')"
  [[ -z "$safe" ]] && return 0
  local dir; dir="$(agents_dir)"
  rm -f "$dir/$safe.json" "$dir/$safe.ack" 2>/dev/null
  return 0
}

cmd_reap() {
  local max_min="$AGENT_HB_REAP_MIN"
  while [[ $# -gt 0 ]]; do
    case "$1" in --max-age-min) max_min="${2:-$AGENT_HB_REAP_MIN}"; shift 2 ;; *) shift ;; esac
  done
  local dir; dir="$(agents_dir)"
  [[ -d "$dir" ]] || return 0
  local now f ts; now="$(_now)"
  for f in "$dir"/*.json; do
    [[ -e "$f" ]] || continue
    ts="$(_pluck_num "$f" ts)"; [[ -z "$ts" ]] && ts="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
    if [[ $(( (now - ts) / 60 )) -gt "$max_min" ]]; then
      rm -f "$f" "${f%.json}.ack" 2>/dev/null
    fi
  done
  return 0
}

run_self_test() {
  local tmp; tmp="$(mktemp -d 2>/dev/null)" || { echo "mktemp FAIL"; exit 1; }
  export HEARTBEAT_STATE_DIR="$tmp/hb"
  local pass=0 fail=0
  _ok() { if eval "$2"; then echo "  ok   $1"; pass=$((pass+1)); else echo "  FAIL $1"; fail=$((fail+1)); fi; }

  # 1. emit writes into the agents/ namespace (NOT the session board root)
  cmd_emit --agent "agent-alpha" --step "started" --note "boot"
  _ok "emit writes heartbeats/agents/agent-alpha.json"        '[[ -f "$tmp/hb/agents/agent-alpha.json" ]]'
  _ok "emit does NOT write into the session board root"       '[[ -z "$(ls "$tmp/hb"/*.json 2>/dev/null)" ]]'
  _ok "emitted json carries schema+step+ts"                   'grep -q "agent-heartbeat/v1" "$tmp/hb/agents/agent-alpha.json" && grep -q "\"step\":\"started\"" "$tmp/hb/agents/agent-alpha.json"'

  # 2. fresh agent → NOT stalled
  _ok "fresh agent not surfaced by watch"                     '[[ -z "$(cmd_watch)" ]]'

  # NOTE: assertions capture "$(cmd_watch)" and glob-match — never `cmd_watch | grep`,
  # because grep -q closes the pipe on first match and SIGPIPEs the still-iterating
  # producer, which `set -o pipefail` would then report as a spurious failure.

  # 3. stale agent → surfaced. Backdate ts by 40 min (> 20m default).
  local old=$(( $(date -u +%s) - 40*60 ))
  printf '{"schema":"agent-heartbeat/v1","agent_id":"agent-hung","step":"committed","note":"then wedged","ts":%s,"pid":1,"long":false}\n' "$old" > "$tmp/hb/agents/agent-hung.json"
  _ok "stale agent surfaced by watch"                         '[[ "$(cmd_watch)" == *agent-hung* ]]'
  _ok "stale agent reports its last step"                     '[[ "$(cmd_watch)" == *committed* ]]'

  # 4. long=true triples the grace: same 40-min age is UNDER 3x20=60m → NOT stalled
  printf '{"schema":"agent-heartbeat/v1","agent_id":"agent-longstep","step":"npm ci","note":"slow","ts":%s,"pid":1,"long":true}\n' "$old" > "$tmp/hb/agents/agent-longstep.json"
  _ok "long-step agent within 3x grace not surfaced"          '[[ "$(cmd_watch)" != *agent-longstep* ]]'

  # 5. .ack suppresses a stalled agent
  touch "$tmp/hb/agents/agent-hung.ack"
  _ok "acked stall suppressed"                                '[[ "$(cmd_watch)" != *agent-hung* ]]'
  rm -f "$tmp/hb/agents/agent-hung.ack"

  # 6. corrupt ts falls back to file mtime (still ages out, never silently fresh)
  printf '{"schema":"agent-heartbeat/v1","agent_id":"agent-badts","step":"x","note":"","ts":,"pid":1,"long":false}\n' > "$tmp/hb/agents/agent-badts.json"
  touch -d "@$old" "$tmp/hb/agents/agent-badts.json" 2>/dev/null   # $old = 40 min ago (epoch)
  _ok "corrupt-ts agent ages out via mtime fallback"          '[[ "$(cmd_watch)" == *agent-badts* ]]'

  # 6b. conclude removes a stale agent's heartbeat → never surfaced (completion signal)
  printf '{"schema":"agent-heartbeat/v1","agent_id":"agent-done","step":"finished","note":"","ts":%s,"pid":1,"long":false}\n' "$old" > "$tmp/hb/agents/agent-done.json"
  cmd_conclude --agent "agent-done"
  _ok "conclude removes the heartbeat file"                   '[[ ! -f "$tmp/hb/agents/agent-done.json" ]]'
  _ok "concluded agent not surfaced by watch"                '[[ "$(cmd_watch)" != *agent-done* ]]'

  # 6c. threshold boundary at 20m: 19m under → fresh, 21m over → stale
  local t19 t21; t19=$(( $(date -u +%s) - 19*60 )); t21=$(( $(date -u +%s) - 21*60 ))
  printf '{"schema":"agent-heartbeat/v1","agent_id":"agent-19m","step":"x","note":"","ts":%s,"pid":1,"long":false}\n' "$t19" > "$tmp/hb/agents/agent-19m.json"
  printf '{"schema":"agent-heartbeat/v1","agent_id":"agent-21m","step":"x","note":"","ts":%s,"pid":1,"long":false}\n' "$t21" > "$tmp/hb/agents/agent-21m.json"
  _ok "19m agent under 20m threshold not surfaced"           '[[ "$(cmd_watch)" != *agent-19m* ]]'
  _ok "21m agent over 20m threshold surfaced"                '[[ "$(cmd_watch)" == *agent-21m* ]]'
  rm -f "$tmp/hb/agents/agent-19m.json" "$tmp/hb/agents/agent-21m.json"

  # 6d. path-traversal: --agent "../../evil" is sanitized to stay inside agents/
  cmd_emit --agent "../../evil" --step x
  _ok "traversal id sanitized into agents/ namespace"        '[[ -f "$tmp/hb/agents/.._.._evil.json" ]]'
  _ok "traversal wrote nothing outside agents/"              '[[ ! -e "$tmp/hb/evil.json" && ! -e "$tmp/evil.json" && ! -e "$tmp/hb/agents/../../evil.json" ]]'
  rm -f "$tmp/hb/agents/.._.._evil.json"

  # 7. reap prunes old files
  cmd_reap --max-age-min 30
  _ok "reap removed the 40-min-old hung agent"                '[[ ! -f "$tmp/hb/agents/agent-hung.json" ]]'
  _ok "reap kept the fresh alpha agent"                       '[[ -f "$tmp/hb/agents/agent-alpha.json" ]]'

  # 8. empty namespace → silent
  local e; e="$(mktemp -d)"; _ok "no agents → watch silent"   '[[ -z "$(HEARTBEAT_STATE_DIR="$e/x" cmd_watch)" ]]'

  # 9. emit never blocks on a missing --agent
  _ok "emit with no --agent is a no-op exit 0"                'cmd_emit --step x; [[ $? -eq 0 ]]'

  rm -rf "$tmp" "$e" 2>/dev/null
  echo ""
  echo "agent-heartbeat self-test: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]]
}

main() {
  local verb="${1:-}"; shift || true
  case "$verb" in
    emit)     cmd_emit "$@" ;;
    conclude) cmd_conclude "$@" ;;
    watch)    cmd_watch "$@" ;;
    reap)     cmd_reap "$@" ;;
    --self-test) run_self_test ;;
    --help|"") sed -n '2,60p' "$0"; ;;
    *) echo "unknown verb: $verb (emit|conclude|watch|reap|--self-test)" >&2; return 0 ;;
  esac
}
main "$@"
