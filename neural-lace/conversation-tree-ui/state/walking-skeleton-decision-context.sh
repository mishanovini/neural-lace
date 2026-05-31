#!/bin/bash
# walking-skeleton-decision-context.sh — Task 10 of
# docs/plans/decision-context-gate-2026-05-29.md.
#
# # Walking Skeleton — end-to-end fence -> tree -> reply -> resolved
#
# This script demonstrates the full decision-context round-trip against
# the SAME state file the LIVE GUI watches, then restores the live state
# to its pre-demo bytes. The demonstration artifacts (pre-snapshot +
# final-state capture) are retained as evidence; the live state file is
# restored at exit so the GUI's observable state is unchanged.
#
# # Stages
#
#   1. Backup     — atomically copy the live tree-state.json to a sibling
#                   `tree-state.before-ws.json` and validate parses-as-JSON.
#   2. Fence-emit — invoke ~/.claude/hooks/decision-context-gate.sh with
#                   a synthetic transcript carrying a well-formed
#                   `::: decision id=WS-1 ...` fence. Expect exit 0; the
#                   live state file must now contain `decision-raised`
#                   AND `item-details-set` events for WS-1.
#   3. Reply-emit — invoke ~/.claude/hooks/decision-context-reply-emit.sh
#                   with a synthetic UserPromptSubmit JSON whose `.prompt`
#                   contains the `reply_with` phrase. Expect the live
#                   state file to gain an `answered` event for WS-1's
#                   item.
#   4. Snapshot   — copy the live state file to a sibling
#                   `walking-skeleton-final-state.json` (the evidence the
#                   round-trip succeeded). Optional: if the GUI is
#                   reachable at 127.0.0.1:7733 BEFORE the restore, take
#                   an `/api/state` snapshot too.
#   5. Restore    — copy `tree-state.before-ws.json` back over the live
#                   `tree-state.json` so the GUI's observable state is
#                   bit-identical to pre-run.
#
# Cleanup-on-failure (trap EXIT) ensures the restore happens even if any
# stage fails mid-script. Re-running is safe: each invocation uses a
# fresh tmp dir for synthetic transcripts and snapshots, and the live
# state file is restored from backup at exit.
#
# # Walking-skeleton evidence (retained next to state.js):
#   - tree-state.before-ws.json    snapshot at script start
#   - walking-skeleton-final-state.json   snapshot after fence+reply
#   - walking-skeleton-api-state.json     (optional) GUI's /api/state
#                                         response while WS-1 is visible

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the LIVE state file location. The script may live in a worktree
# (which doesn't carry tree-state.json — it's gitignored on the main repo).
# Mirror conversation-tree-emit.sh's _resolve_gui_state_path logic by using
# the parent of `git rev-parse --git-common-dir` as the main repo root.
_resolve_live_state() {
  local main_repo gcd
  gcd=$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null) || gcd=""
  if [[ -n "$gcd" ]]; then
    main_repo=$(cd "$SCRIPT_DIR" && cd "$(dirname "$gcd")" 2>/dev/null && pwd) || main_repo=""
  fi
  if [[ -n "$main_repo" ]]; then
    local nested="$main_repo/neural-lace/conversation-tree-ui/state/tree-state.json"
    local flat="$main_repo/conversation-tree-ui/state/tree-state.json"
    if [[ -e "$nested" ]]; then printf '%s' "$nested"; return 0; fi
    if [[ -e "$flat" ]]; then printf '%s' "$flat"; return 0; fi
  fi
  # Fall back to sibling of state.js (works when run from the main repo's path).
  printf '%s' "$SCRIPT_DIR/tree-state.json"
}

LIVE_STATE="$(_resolve_live_state)"
LIVE_STATE_DIR="$(dirname "$LIVE_STATE")"
LIVE_LIB="$LIVE_STATE_DIR/state.js"
BACKUP_FILE="$LIVE_STATE_DIR/tree-state.before-ws.json"
FINAL_FILE="$LIVE_STATE_DIR/walking-skeleton-final-state.json"
API_STATE_FILE="$LIVE_STATE_DIR/walking-skeleton-api-state.json"

GATE_HOOK="$HOME/.claude/hooks/decision-context-gate.sh"
REPLY_HOOK="$HOME/.claude/hooks/decision-context-reply-emit.sh"

# Synthetic-run artifacts go in a fresh tmp dir per invocation.
TMP_DIR="$(mktemp -d 2>/dev/null || echo "/tmp/ws-dc-$$")"

# Items the script created that should persist as evidence (NOT removed
# in cleanup): BACKUP_FILE, FINAL_FILE, optionally API_STATE_FILE.
# The TMP_DIR is removed at exit.

RESTORE_NEEDED=0

_log() {
  printf '[walking-skeleton] %s\n' "$*" >&2
}

_cleanup() {
  local rc=$?
  # Restore live state if we made a backup.
  if [[ "$RESTORE_NEEDED" -eq 1 ]] && [[ -f "$BACKUP_FILE" ]]; then
    if cp "$BACKUP_FILE" "$LIVE_STATE" 2>/dev/null; then
      _log "RESTORE: live state restored from $BACKUP_FILE"
    else
      _log "RESTORE FAILED — backup is at $BACKUP_FILE; manual recovery: cp '$BACKUP_FILE' '$LIVE_STATE'"
    fi
  fi
  rm -rf "$TMP_DIR" 2>/dev/null || true
  exit "$rc"
}
trap _cleanup EXIT INT TERM

_die() {
  _log "FAIL: $*"
  exit 1
}

# ---------- pre-flight checks ----------------------------------------------
[[ -f "$LIVE_STATE" ]] || _die "live state file missing at $LIVE_STATE"
[[ -f "$LIVE_LIB" ]]   || _die "state.js missing at $LIVE_LIB"
[[ -x "$GATE_HOOK" ]] || [[ -r "$GATE_HOOK" ]] || _die "gate hook missing at $GATE_HOOK"
[[ -x "$REPLY_HOOK" ]] || [[ -r "$REPLY_HOOK" ]] || _die "reply hook missing at $REPLY_HOOK"
command -v node >/dev/null 2>&1 || _die "node unavailable"
command -v jq   >/dev/null 2>&1 || _die "jq unavailable"

# ---------- Stage 1: backup ------------------------------------------------
_log "stage 1/5: backup live state -> $BACKUP_FILE"
cp "$LIVE_STATE" "$BACKUP_FILE" || _die "cp backup failed"
RESTORE_NEEDED=1
# Validate the backup parses as JSON (so we never restore garbage).
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));' "$BACKUP_FILE" \
  || _die "backup not valid JSON; aborting"

# ---------- Stage 1.5: pre-seed the WS-1 branch via the facade --------------
# The gate emits `decision-raised` with node_id="dc-decision-WS-1", which the
# reducer rejects silently if no `branch-opened` already exists for that
# node_id (per state/reducer.js `decision-raised` arm — `findNode` is
# required). The gate does NOT emit `branch-opened` ahead of the fence
# events; that orchestration is the caller's responsibility. For the
# Walking Skeleton, we pre-seed the branch via the facade BEFORE invoking
# the gate so the fence's decision-raised + item-details-set land on a
# resolvable node and the reducer surfaces the item in snapshot.nodes[]
# (which the reply hook reads).
_log "stage 1.5/5: pre-seed WS-1 branch via state.js facade"
WS1_NODE_ID="dc-decision-WS-1"
PRESEED_OUT=$(node -e '
  var s = require(process.argv[1]);
  s.appendBranchOpened(
    { id: process.argv[2], parentId: null, title: "Walking Skeleton WS-1 (demo)" },
    { statePath: process.argv[3] }
  );
  process.stdout.write("seeded");
' "$LIVE_LIB" "$WS1_NODE_ID" "$LIVE_STATE" 2>"$TMP_DIR/preseed.err") || _die "preseed failed: $(cat "$TMP_DIR/preseed.err")"
[[ "$PRESEED_OUT" == "seeded" ]] || _die "preseed unexpected output: $PRESEED_OUT"

# ---------- Stage 2: synthesize transcript with well-formed fence ----------
_log "stage 2/5: emit WS-1 decision via gate hook"

TRANSCRIPT="$TMP_DIR/ws-transcript.jsonl"
ASSISTANT_TEXT=$(cat <<'FENCE'
For the walking-skeleton demo, which approach should the v1 store take?

::: decision id=WS-1 urgency=low
**Title:** Walking Skeleton decision
**About:** Pick a path for the WS demo — round-trip lock-in.
**Background:** Demonstrates the fence -> tree -> reply -> resolved cycle end-to-end live.
**Question:** Which option should the walking-skeleton round-trip target?
**Why not decide alone:** Affects the demo's reply phrase + downstream evidence shape.
**Options:**
1. **Option A** (key=a)
   **What it does:** Targets path A; the canonical demo route.
   **Risk:** None; this is a demo with restore on exit.
   **Reversibility cost:** free
   **Cost:** low
2. **Option B** (key=b)
   **What it does:** Targets path B; alternate demo route.
   **Risk:** None; demo with restore on exit.
   **Reversibility cost:** free
   **Cost:** low
**Recommendation:**
  **Option key:** a
  **Reasoning:** Demo always picks A for deterministic reply matching.
**Reply with:** go with option A
:::
FENCE
)

# JSONL transcript: a user message, then the assistant message with the fence.
jq -nc --arg t "begin demo" '{role:"user", content:$t}' >"$TRANSCRIPT"
jq -nc --arg t "$ASSISTANT_TEXT" '{role:"assistant", content:$t}' >>"$TRANSCRIPT"

# Invoke the gate hook with the live state file as the explicit single sink.
# The gate's stdin is the Stop-hook event JSON pointing at the transcript.
GATE_STDIN=$(jq -nc --arg p "$TRANSCRIPT" '{transcript_path:$p, session_id:"ws-demo"}')

GATE_STDERR="$TMP_DIR/gate.stderr"
set +e
CONV_TREE_STATE_PATH="$LIVE_STATE" \
  bash "$GATE_HOOK" <<<"$GATE_STDIN" 2>"$GATE_STDERR"
GATE_RC=$?
set -e

if [[ "$GATE_RC" -ne 0 ]]; then
  _log "PARTIAL: gate hook returned exit $GATE_RC"
  _log "gate stderr (first 30 lines):"
  head -30 "$GATE_STDERR" >&2 || true
  _die "gate hook did not allow Stop on a well-formed fence"
fi
_log "  gate hook exited 0"

# Verify the live state now contains the fence-emitted events.
WS1_AFTER_FENCE=$(node -e '
  var s = require(process.argv[1]);
  var st = s.readState({ statePath: process.argv[2] });
  var dr = st.events.filter(function(e){
    return e.type === "decision-raised" && /WS-1/.test(JSON.stringify(e));
  }).length;
  var ids = st.events.filter(function(e){
    return e.type === "item-details-set" && /WS-1/.test(JSON.stringify(e));
  }).length;
  process.stdout.write(JSON.stringify({decision_raised: dr, item_details_set: ids}));
' "$LIVE_LIB" "$LIVE_STATE" 2>"$TMP_DIR/verify1.err")

_log "  events after fence-emit: $WS1_AFTER_FENCE"
DR_COUNT=$(printf '%s' "$WS1_AFTER_FENCE" | jq -r '.decision_raised // 0')
IDS_COUNT=$(printf '%s' "$WS1_AFTER_FENCE" | jq -r '.item_details_set // 0')
if [[ "$DR_COUNT" -lt 1 ]] || [[ "$IDS_COUNT" -lt 1 ]]; then
  _log "PARTIAL: expected decision-raised>=1 AND item-details-set>=1 for WS-1; got $WS1_AFTER_FENCE"
  _die "fence-emit did not land the expected events"
fi

# Extract the actual item_id the gate emitted so the reply phrase can match
# via reply_with phrase regardless of internal item-id format.
ITEM_ID=$(node -e '
  var s = require(process.argv[1]);
  var st = s.readState({ statePath: process.argv[2] });
  for (var i = st.events.length - 1; i >= 0; i--) {
    var e = st.events[i];
    if (e.type === "decision-raised" && /WS-1/.test(JSON.stringify(e))) {
      process.stdout.write(String(e.item_id || ""));
      break;
    }
  }
' "$LIVE_LIB" "$LIVE_STATE" 2>/dev/null)
_log "  WS-1 item_id: $ITEM_ID"

# ---------- Stage 3: reply via UserPromptSubmit ----------------------------
_log "stage 3/5: emit WS-1 reply via reply-emit hook"

# The fence declared `Reply with: go with option A` — the reply hook does
# a case-insensitive substring match on this phrase against `.prompt`.
REPLY_PROMPT="Yes, go with option A — that's the canonical demo route."
REPLY_STDIN=$(jq -nc --arg pr "$REPLY_PROMPT" '{prompt:$pr, session_id:"ws-demo"}')

REPLY_STDERR="$TMP_DIR/reply.stderr"
set +e
CONV_TREE_STATE_PATH="$LIVE_STATE" \
  bash "$REPLY_HOOK" <<<"$REPLY_STDIN" 2>"$REPLY_STDERR"
REPLY_RC=$?
set -e

if [[ "$REPLY_RC" -ne 0 ]]; then
  _log "  reply hook exited $REPLY_RC (writer-hook never blocks; this is unexpected)"
  head -20 "$REPLY_STDERR" >&2 || true
  _die "reply hook returned non-zero"
fi
_log "  reply hook exited 0"

# Verify the live state now contains the answered event for WS-1's item.
WS1_AFTER_REPLY=$(node -e '
  var s = require(process.argv[1]);
  var st = s.readState({ statePath: process.argv[2] });
  var ans = st.events.filter(function(e){
    return e.type === "answered" && /WS-1/.test(JSON.stringify(e));
  }).length;
  process.stdout.write(JSON.stringify({answered: ans}));
' "$LIVE_LIB" "$LIVE_STATE" 2>"$TMP_DIR/verify2.err")
_log "  events after reply-emit: $WS1_AFTER_REPLY"
ANS_COUNT=$(printf '%s' "$WS1_AFTER_REPLY" | jq -r '.answered // 0')
if [[ "$ANS_COUNT" -lt 1 ]]; then
  _die "reply-emit did not land an answered event for WS-1"
fi

# ---------- Stage 4: snapshot the final state ------------------------------
_log "stage 4/5: snapshot final state -> $FINAL_FILE"
cp "$LIVE_STATE" "$FINAL_FILE" || _die "snapshot copy failed"

# Optional: capture /api/state from the GUI BEFORE we restore, so the
# evidence includes the GUI's view of WS-1 in nodes[].
GUI_RESULT="SKIPPED"
if curl -sf -m 2 http://127.0.0.1:7733/api/health >/dev/null 2>&1; then
  if curl -sf -m 3 http://127.0.0.1:7733/api/state >"$API_STATE_FILE" 2>/dev/null; then
    # Check WS-1 made it into nodes[]
    WS1_IN_NODES=$(node -e '
      var fs = require("fs");
      var j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      var nodes = (j && j.snapshot && j.snapshot.nodes) || j.nodes || [];
      var hit = 0;
      for (var i = 0; i < nodes.length; i++) {
        if (/WS-1/.test(JSON.stringify(nodes[i]))) hit++;
      }
      process.stdout.write(String(hit));
    ' "$API_STATE_FILE" 2>/dev/null || echo "0")
    if [[ "$WS1_IN_NODES" -ge 1 ]]; then
      GUI_RESULT="CONFIRMED (WS-1 visible in /api/state nodes[])"
    else
      GUI_RESULT="REACHABLE-BUT-WS1-NOT-IN-NODES"
    fi
  else
    GUI_RESULT="REACHABLE-BUT-API-STATE-FAILED"
  fi
else
  GUI_RESULT="NOT-REACHABLE"
fi
_log "  GUI confirmation: $GUI_RESULT"

# ---------- Stage 5: cleanup trap will restore -----------------------------
_log "stage 5/5: restore live state on exit (trap)"

# Compose final summary line.
echo
echo "WALKING SKELETON: PASS — WS-1 decision-raised + item-details-set + answered events confirmed in state file at $LIVE_STATE"
echo "  pre-snapshot:       $BACKUP_FILE"
echo "  post-snapshot:      $FINAL_FILE"
echo "  GUI /api/state:     $API_STATE_FILE ($GUI_RESULT)"
echo "  events: decision-raised=$DR_COUNT  item-details-set=$IDS_COUNT  answered=$ANS_COUNT"
echo "  item_id:            $ITEM_ID"
echo

exit 0
