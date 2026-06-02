#!/bin/bash
# conv-tree-emit-reconciler.sh — LAYER B of the four-layer Conv Tree
# auto-emit enforcement chain (see rules/conv-tree-orchestrator-emit.md).
#
# Runs as a Stop hook AFTER conversation-tree-emit.sh --on-stop. Opens
# $TRANSCRIPT_PATH JSONL (agent-uneditable), enumerates every Dispatch
# spawn the session made, and compares to the per-session correlation
# ledger Layer A wrote. If a transcript spawn has NO matching ledger
# entry — i.e., Layer A's PreToolUse silently failed — this hook emits
# a synthetic catch-up branch-opened event via the same state-library
# path Layer A uses.
#
# Classification: writer hook (NEVER blocks Stop). Failures are logged
# to ~/.claude/logs/conversation-tree-emit.log and the hook exits 0.
#
# Rationale: Layer A is idempotent on deterministic event_id, so a
# re-fire is a no-op; this reconciler is safe to run unconditionally.
# It catches the narrow class of failures where Layer A's PreToolUse
# never got to call appendEvent at all (jq parse error on unusual
# tool_input shape, transient FS race, etc.).
#
# Out of scope: emitting `concluded` (already handled by --on-stop AND
# by the heartbeat) and emitting `branch-note-add` for cross-branch
# sends (the message tool is not currently exposed; see Layer D rule).
#
# Invocation: bash ~/.claude/hooks/conv-tree-emit-reconciler.sh
# Self-test: bash ~/.claude/hooks/conv-tree-emit-reconciler.sh --self-test

set -uo pipefail

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/conversation-tree-emit.log"
LEDGER_DIR="$HOME/.claude/state/conversation-tree-emit"

_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s [reconciler] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "$*" >>"$LOG_FILE" 2>/dev/null || true
}
_die_safe() { _log "isolated error: $*"; exit 0; }
trap '_die_safe "uncaught (line $LINENO)"' ERR

_have() { command -v "$1" >/dev/null 2>&1; }

# Mirror conversation-tree-emit.sh's session-id sanitization so ledger
# filenames line up.
_sid_safe() {
  local sid="$1"
  printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

# Mirror conversation-tree-emit.sh's _sha1 helper.
_sha1() {
  if _have sha1sum; then sha1sum | cut -d' ' -f1
  elif _have shasum; then shasum -a 1 | cut -d' ' -f1
  else cksum | tr -d ' ' ; fi
}

_resolve_emit_hook() {
  # Workstreams rename (2026-06-01): prefer the new name, fall back to the
  # backward-compat shim at the old name during the transition window.
  local cand="$HOME/.claude/hooks/workstreams-emit.sh"
  if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
  cand="$HOME/.claude/hooks/conversation-tree-emit.sh"
  if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
  printf '%s' ""
}

_read_stdin() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]] && [[ ! -t 0 ]]; then input=$(cat 2>/dev/null || echo ""); fi
  printf '%s' "$input"
}

# Extract transcript_path + session_id from the Stop event input.
_extract_session_meta() {
  local input="$1"
  _have jq || { printf '\n\n'; return 0; }
  local sid tp
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || echo "")
  tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
  printf '%s\n%s\n' "$sid" "$tp"
}

# Enumerate every Dispatch-class spawn tool call in the transcript JSONL.
# Emits one TSV line per call: <tool_name>\t<title-or-empty>\t<event_idx>
_enumerate_spawns_from_transcript() {
  local tp="$1"
  [[ -z "$tp" ]] && return 0
  [[ ! -f "$tp" ]] && return 0
  _have jq || return 0
  # Each line of the transcript is a JSONL event. We want assistant
  # messages whose content includes a tool_use of the Dispatch tools.
  # Conservative parse: accept either top-level .tool_name shape OR
  # nested content[*].tool_use shape (Claude Code transcripts vary).
  jq -r --arg tools 'mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task' '
    select(.type == "assistant" or .role == "assistant")
    | (.message.content // .content // [])
    | (if type == "array" then . else [] end)
    | .[]?
    | select(.type == "tool_use")
    | select(.name | test($tools))
    | [.name, ((.input.title // .input.prompt // .input.description // "") | tostring | split("\n")[0] | .[0:80])]
    | @tsv
  ' "$tp" 2>/dev/null || true
}

# Count entries in the session's correlation ledger.
_count_ledger_entries() {
  local sid_safe="$1"
  local ledger="$LEDGER_DIR/opened-${sid_safe}.jsonl"
  [[ -f "$ledger" ]] || { printf '0'; return 0; }
  wc -l <"$ledger" 2>/dev/null | tr -d ' '
}

# Reconcile: for any transcript spawn without a matching ledger entry,
# re-fire conversation-tree-emit.sh --on-spawn with a synthesized
# tool_input. The emit hook is idempotent on deterministic event_id, so
# this is safe to run unconditionally.
_reconcile() {
  local sid_safe="$1" tp="$2"
  local emit_hook; emit_hook=$(_resolve_emit_hook)
  if [[ -z "$emit_hook" ]]; then _log "no emit hook at expected path; reconciler is a no-op"; return 0; fi

  local transcript_count=0
  local ledger_count
  ledger_count=$(_count_ledger_entries "$sid_safe")

  local catch_up=0
  local synth_idx=0
  while IFS=$'\t' read -r tool_name title; do
    [[ -z "$tool_name" ]] && continue
    transcript_count=$((transcript_count+1))
    # If the ledger already has at least one entry per transcript spawn,
    # consider this session reconciled. Otherwise re-fire emit for the
    # delta. This is conservative — re-firing twice is harmless (the
    # emit hook is idempotent on deterministic event_id derived from
    # (session, title, bucket)).
    if [[ "$transcript_count" -gt "$ledger_count" ]]; then
      synth_idx=$((synth_idx+1))
      local synth_input
      synth_input=$(printf '{"tool_name":"%s","tool_input":{"title":%s},"session_id":"%s"}' \
        "$tool_name" \
        "$(printf '%s' "$title" | jq -Rn --arg t "$title" '$t' 2>/dev/null || printf '"%s"' "$title")" \
        "$sid_safe")
      CLAUDE_TOOL_INPUT="$synth_input" CLAUDE_SESSION_ID="$sid_safe" \
        bash "$emit_hook" --on-spawn >/dev/null 2>&1 || true
      catch_up=$((catch_up+1))
      _log "catch-up emit fired for tool=$tool_name title=\"$title\" session=$sid_safe"
    fi
  done < <(_enumerate_spawns_from_transcript "$tp")

  _log "reconcile: session=$sid_safe transcript_spawns=$transcript_count ledger_entries=$ledger_count catch_up=$catch_up"
}

_main() {
  local input; input=$(_read_stdin)
  [[ -z "$input" ]] && exit 0

  local meta; meta=$(_extract_session_meta "$input")
  local sid; sid=$(printf '%s' "$meta" | sed -n '1p')
  local tp;  tp=$(printf '%s' "$meta" | sed -n '2p')

  [[ -z "$sid" ]] && sid="${CLAUDE_SESSION_ID:-}"
  [[ -z "$sid" ]] && { _log "no session_id available; skip"; exit 0; }
  [[ -z "$tp"  ]] && { _log "no transcript_path; skip"; exit 0; }

  local sid_safe; sid_safe=$(_sid_safe "$sid")
  _reconcile "$sid_safe" "$tp"
  exit 0
}

# Self-test exercises four scenarios:
#   ST1 — transcript with 1 spawn + ledger with 1 entry: no catch-up
#   ST2 — transcript with 2 spawns + ledger with 1 entry: 1 catch-up
#   ST3 — transcript with 0 spawns: no catch-up
#   ST4 — missing transcript file: graceful no-op (exit 0)
_self_test() {
  trap - ERR
  local pass=0 fail=0
  local tmp; tmp=$(mktemp -d 2>/dev/null || echo "/tmp/cte-rec-st-$$")
  mkdir -p "$tmp"
  local emit_hook; emit_hook=$(_resolve_emit_hook)
  if [[ -z "$emit_hook" ]]; then
    echo "self-test: cannot locate ~/.claude/hooks/workstreams-emit.sh"
    echo "self-test: FAIL"; exit 1
  fi
  local SELF; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  _ck() { if [[ "$2" == "$3" ]]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (got '$2' want '$3')"; fi; }

  # ---- ST1: 1 spawn in transcript, 1 ledger entry → no catch-up
  local sid1="rec-st-1"
  local sid1_safe="rec-st-1"
  local tp1="$tmp/transcript-1.jsonl"
  cat >"$tp1" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__ccd_session__spawn_task","input":{"title":"already-emitted"}}]}}
JSONL
  mkdir -p "$LEDGER_DIR" 2>/dev/null || true
  local ledger1="$LEDGER_DIR/opened-${sid1_safe}.jsonl"
  printf 'sp-existing\talready-emitted\t2026-01-01T00:00:00Z\n' >"$ledger1"

  # Use a sandbox state path so we don't pollute real state
  local sp1="$tmp/state-1.json"
  CONV_TREE_STATE_PATH="$sp1" \
    bash "$SELF" <<<"{\"session_id\":\"$sid1\",\"transcript_path\":\"$tp1\"}" >/dev/null 2>&1
  local rc1=$?
  # Cleanup
  rm -f "$ledger1"
  _ck "ST1 1-spawn/1-ledger no catch-up exit 0" "$rc1" "0"

  # ---- ST2: 2 spawns in transcript, 1 ledger entry → 1 catch-up emit
  local sid2="rec-st-2"
  local sid2_safe="rec-st-2"
  local tp2="$tmp/transcript-2.jsonl"
  cat >"$tp2" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__ccd_session__spawn_task","input":{"title":"first-spawn"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__ccd_session_mgmt__start_code_task","input":{"title":"second-spawn"}}]}}
JSONL
  local ledger2="$LEDGER_DIR/opened-${sid2_safe}.jsonl"
  printf 'sp-first\tfirst-spawn\t2026-01-01T00:00:00Z\n' >"$ledger2"

  local sp2="$tmp/state-2.json"
  local log_before; log_before=$(wc -l <"$LOG_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  CONV_TREE_STATE_PATH="$sp2" \
    bash "$SELF" <<<"{\"session_id\":\"$sid2\",\"transcript_path\":\"$tp2\"}" >/dev/null 2>&1
  local rc2=$?
  local log_after; log_after=$(wc -l <"$LOG_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  rm -f "$ledger2"
  _ck "ST2 2-spawns/1-ledger exit 0" "$rc2" "0"
  # at least one log line of catch-up should have been written
  if [[ "$log_after" -gt "$log_before" ]]; then
    echo "PASS: ST2 wrote audit-log line(s) for catch-up"; pass=$((pass+1))
  else
    echo "FAIL: ST2 expected audit-log lines for catch-up (before=$log_before after=$log_after)"; fail=$((fail+1))
  fi

  # ---- ST3: empty transcript → no work, exit 0
  local tp3="$tmp/transcript-3.jsonl"
  : >"$tp3"
  local sp3="$tmp/state-3.json"
  CONV_TREE_STATE_PATH="$sp3" \
    bash "$SELF" <<<"{\"session_id\":\"rec-st-3\",\"transcript_path\":\"$tp3\"}" >/dev/null 2>&1
  local rc3=$?
  _ck "ST3 empty transcript exit 0" "$rc3" "0"

  # ---- ST4: missing transcript file → graceful no-op
  CONV_TREE_STATE_PATH="$tmp/state-4.json" \
    bash "$SELF" <<<"{\"session_id\":\"rec-st-4\",\"transcript_path\":\"$tmp/does-not-exist.jsonl\"}" >/dev/null 2>&1
  _ck "ST4 missing transcript exit 0" "$?" "0"

  # ---- ST5: no session_id at all → graceful no-op
  CONV_TREE_STATE_PATH="$tmp/state-5.json" \
    bash "$SELF" <<<'{}' >/dev/null 2>&1
  _ck "ST5 no session_id exit 0" "$?" "0"

  echo ""
  echo "self-test summary: $pass passed, $fail failed"
  if [[ "$fail" -eq 0 ]]; then echo "self-test: OK"; exit 0
  else echo "self-test: FAIL"; exit 1; fi
}

# ---- entry point ---------------------------------------------------------
case "${1:-}" in
  --self-test) _self_test ;;
  *) _main ;;
esac
