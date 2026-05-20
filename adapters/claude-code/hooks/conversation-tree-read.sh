#!/bin/bash
# conversation-tree-read.sh — Dispatch-side READER for the Conversation-Tree
# UI file-mediated state contract (ADR-031 r7 / ADR-032). The mirror image of
# conversation-tree-emit.sh: the emit hook WRITES branch lifecycle events into
# the state file as Dispatch works; THIS hook READS the operator's GUI-authored
# responses back out and injects them into the orchestrator's next turn so the
# loop closes.
#
# Classification: READER hook, NOT a gate. It NEVER blocks a prompt. Every
# runtime path exits 0. Failures are isolated and logged to
# ~/.claude/logs/conv-tree-read.log; a reader malfunction must never interfere
# with the operator's chat message (gate-respect.md: reader hooks do not block).
#
# Invocation:
#   (no arg)     UserPromptSubmit. Reads new operator-authored GUI events via
#                the frozen A2 facade since this session's read cursor, formats
#                them, and emits a UserPromptSubmit `additionalContext` JSON
#                object on stdout so the orchestrator sees the operator's GUI
#                responses as if they were typed in chat. exit 0 + empty stdout
#                is a clean no-op (Claude Code UserPromptSubmit contract).
#   --self-test  Exercises cursor / filter / cold-start / truncation / text-
#                extraction / failure-isolation + an end-to-end slice against
#                temp state files. Prints `self-test: OK` / `self-test: FAIL`.
#                Exit 0 / 1.
#
# Output contract (UserPromptSubmit): on exit 0, stdout is injected into the
# turn's context. We emit the explicit structured form so the injection is
# unambiguous and version-stable:
#   {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit",
#    "additionalContext":"<block>"}}
# Empty stdout => no context added, prompt proceeds normally.
#
# Source of truth: the GUI server runs from the operator's MAIN checkout and
# POSTs operator events through the frozen A2 appendEvent (actor forced to
# "gui"). The reader resolves the SAME main-checkout state file the emit hook's
# GUI sink targets (parity), reads ONLY through the frozen A2 facade
# (readState) — never raw JSON — and surfaces ONLY actor=="gui" events of the
# operator-response allowlist. The orchestrator's own actor=="dispatch" writes
# (including the emit hook's branch-opened/concluded and the orchestrator's own
# `answered`) are never echoed back.
#
# Out of scope (do not change here): the GUI (server.js/web — the inline-
# response UI is the v1.1 session's), the A2 state library (frozen — called,
# never modified), the emit hook, the conv-tree gates, the ADR-032 §2 enum
# (this reader keys off the EXISTING enum + forward-compat names; it never
# extends schema.js).

set -uo pipefail

MODE="${1:-}"

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/conv-tree-read.log"
CURSOR_DIR_DEFAULT="$HOME/.claude/state/conv-tree-read"

# ---- failure isolation -----------------------------------------------------
# Any unexpected error in the runtime path logs and exits 0. The operator's
# prompt must never be impacted by a reader-hook malfunction.
_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "${MODE:-read}" "$*" >>"$LOG_FILE" 2>/dev/null || true
}
_die_safe() { _log "isolated error: $*"; exit 0; }
trap '_die_safe "uncaught (line $LINENO)"' ERR

_have() { command -v "$1" >/dev/null 2>&1; }

# Resolve the state-library entry module (state.js). Byte-identical resolution
# order to conversation-tree-emit.sh::_resolve_state_lib so reader and writer
# agree on the facade module.
_resolve_state_lib() {
  if [[ -n "${CONV_TREE_STATE_LIB:-}" ]]; then printf '%s' "$CONV_TREE_STATE_LIB"; return 0; fi
  local root=""
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    local cand="$root/neural-lace/conversation-tree-ui/state/state.js"
    if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
    cand="$root/conversation-tree-ui/state/state.js"
    if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
  fi
  printf '%s' "$HOME/claude-projects/neural-lace/neural-lace/conversation-tree-ui/state/state.js"
}

# The MAIN repo checkout (NOT a worktree) — parent of git-common-dir. The
# operator runs ONE GUI server from the main checkout; its appendEvent writes
# the main checkout's module tree-state.json. A worktree-rooted reader must
# read THAT file or it never sees the operator's responses. Identical
# discipline to conversation-tree-emit.sh::_main_repo_root.
_main_repo_root() {
  local gcd
  gcd=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  [[ -z "$gcd" ]] && return 1
  local d
  d=$(cd "$(dirname "$gcd")" 2>/dev/null && pwd) || return 1
  printf '%s' "$d"
}

# GUI state file the operator's single GUI server writes (stateLib.STATE_FILE
# resolved against the MAIN checkout). Byte-identical to
# conversation-tree-emit.sh::_resolve_gui_state_path so the reader reads
# exactly what the GUI server wrote. CONV_TREE_STATE_PATH overrides (self-test).
_resolve_gui_state_path() {
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then printf '%s' "$CONV_TREE_STATE_PATH"; return 0; fi
  local mr
  if mr=$(_main_repo_root) && [[ -n "$mr" ]]; then
    local c="$mr/neural-lace/conversation-tree-ui/state/tree-state.json"
    if [[ -f "$mr/neural-lace/conversation-tree-ui/state/state.js" ]]; then printf '%s' "$c"; return 0; fi
    c="$mr/conversation-tree-ui/state/tree-state.json"
    if [[ -f "$mr/conversation-tree-ui/state/state.js" ]]; then printf '%s' "$c"; return 0; fi
  fi
  printf '%s' "$HOME/claude-projects/neural-lace/neural-lace/conversation-tree-ui/state/tree-state.json"
}

_read_stdin() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]] && [[ ! -t 0 ]]; then input=$(cat 2>/dev/null || echo ""); fi
  printf '%s' "$input"
}

# Session id: CLAUDE_SESSION_ID, else a fast non-jq extraction of
# "session_id":"..." from the stdin JSON, else ppid. No jq in the hot path
# (jq startup is ~50-100ms on Windows git-bash and the fast-path must stay
# cheap). Sanitized to a filesystem-safe token (same shape as the emit hook).
_session_id() {
  local sid="${CLAUDE_SESSION_ID:-}"
  if [[ -z "$sid" ]] && [[ -n "${1:-}" ]]; then
    sid=$(printf '%s' "$1" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  fi
  [[ -z "$sid" ]] && sid="ppid-${PPID:-$$}"
  printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

# ---- the reader program ----------------------------------------------------
# One node invocation does everything: read state via the FROZEN facade, read
# the per-session cursor, select new actor=="gui" response-allowlist events,
# resolve node/item titles from the snapshot, format the block, atomically
# advance the cursor, print the UserPromptSubmit additionalContext JSON (or
# nothing). Kept in a tempfile rather than `node -e` so the JSON-building logic
# stays readable and quoting-safe.
_reader_js() {
  cat <<'NODEJS'
'use strict';
// argv: libPath statePath cursorFile maxStr coldWindowMinStr
var libPath = process.argv[2];
var statePath = process.argv[3];
var cursorFile = process.argv[4];
var MAX = parseInt(process.argv[5], 10); if (!(MAX > 0)) MAX = 12;
var COLD_MIN = parseInt(process.argv[6], 10); if (!(COLD_MIN >= 0)) COLD_MIN = 120;

var fs = require('fs');
var path = require('path');

function done(noOutputReason) {
  // exit 0, no stdout => clean UserPromptSubmit no-op
  if (noOutputReason) process.stderr.write('[conv-tree-read] ' + noOutputReason + '\n');
  process.exit(0);
}

var stateLib;
try { stateLib = require(libPath); }
catch (e) { return done('state lib unavailable: ' + (e && e.message || e)); }

var st;
try { st = stateLib.readState({ statePath: statePath }); }
catch (e) {
  // torn / schema-too-new / unreadable => surface nothing, never crash
  return done('readState failed (' + (e && e.message || e) + ')');
}
if (!st || !Array.isArray(st.events)) return done('no events array');

var events = st.events;
var snapshot = (st && st.snapshot) || { nodes: [] };
var nodes = (snapshot && Array.isArray(snapshot.nodes)) ? snapshot.nodes : [];

// Operator-response allowlist: the REAL ADR-032 §2 enum types that represent
// the operator communicating to the orchestrator via the GUI, PLUS forward-
// compat names from the brief (harmless if never emitted; if v1.1 extends the
// enum with them they are caught automatically).
var RESPONSE_TYPES = {
  'answered': 1, 'action-done': 1, 'annotated': 1, 'contested': 1,
  'contest-resolved': 1, 'deferred': 1, 'defer-cleared': 1, 'backlog-added': 1,
  // v1.1.2 item 35: explicit "Send to Dispatch" from the GUI's staged-note pane.
  'branch-note-add': 1,
  // forward-compat (not in the frozen enum today):
  'action-responded': 1, 'action-noted-via-gui': 1, 'question-answered': 1,
  'decision-made': 1
};

// ---- cursor ---------------------------------------------------------------
var lastSeen = null;
try {
  if (fs.existsSync(cursorFile)) {
    var cj = JSON.parse(fs.readFileSync(cursorFile, 'utf8'));
    if (cj && typeof cj.last_event_id === 'string' && cj.last_event_id) lastSeen = cj.last_event_id;
  }
} catch (e) { lastSeen = null; /* corrupt cursor => cold start */ }

if (events.length === 0) {
  // Nothing in the log at all — leave cursor as-is, no-op.
  return done('empty event log');
}

var candidates;
var coldStart = false;
if (lastSeen) {
  var idx = -1;
  for (var i = 0; i < events.length; i++) {
    if (events[i] && events[i].event_id === lastSeen) { idx = i; break; }
  }
  if (idx >= 0) {
    candidates = events.slice(idx + 1);          // everything after the cursor
  } else {
    coldStart = true;                            // cursor compacted away => cold start
  }
} else {
  coldStart = true;                              // no cursor file => cold start
}

if (coldStart) {
  // Cold start: bound the backlog by time so turn 1 is not flooded with a
  // month of history. Events older than the window are intentionally not
  // surfaced (brief: "skip events older than some threshold").
  var cutoff = Date.now() - COLD_MIN * 60 * 1000;
  candidates = events.filter(function (e) {
    if (!e || typeof e.ts !== 'string') return false;
    var t = Date.parse(e.ts);
    return isFinite(t) && t >= cutoff;
  });
}

// The new cursor is ALWAYS the last event in the log — we have now "seen"
// every event up to here; non-response / dispatch events advance the cursor
// too so the scan stays O(new) and nothing re-surfaces.
var newCursor = events[events.length - 1].event_id;

// ---- select operator-response events --------------------------------------
var responses = candidates.filter(function (e) {
  return e && e.actor === 'gui' && RESPONSE_TYPES[e.type] === 1;
});

// advance cursor (atomic) regardless of whether anything is surfaced
function writeCursor() {
  try {
    fs.mkdirSync(path.dirname(cursorFile), { recursive: true });
    var tmp = cursorFile + '.tmp-' + process.pid;
    fs.writeFileSync(tmp, JSON.stringify({
      last_event_id: newCursor,
      updated_at: new Date().toISOString()
    }));
    fs.renameSync(tmp, cursorFile);
  } catch (e) { process.stderr.write('[conv-tree-read] cursor write failed: ' + (e && e.message || e) + '\n'); }
}

if (responses.length === 0) { writeCursor(); return done('no new operator responses'); }

// truncate to the most-recent MAX, keep an "older not shown" count
var truncatedCount = 0;
if (responses.length > MAX) {
  truncatedCount = responses.length - MAX;
  responses = responses.slice(-MAX);
}

// ---- resolve node/item titles from the snapshot ---------------------------
var nodeById = {};
for (var n = 0; n < nodes.length; n++) { if (nodes[n] && nodes[n].node_id) nodeById[nodes[n].node_id] = nodes[n]; }

function itemOf(node, itemId) {
  if (!node || !Array.isArray(node.items) || !itemId) return null;
  for (var k = 0; k < node.items.length; k++) {
    if (node.items[k] && node.items[k].item_id === itemId) return node.items[k];
  }
  return null;
}

function responseText(e, item) {
  if (e.type === 'annotated') return (typeof e.text === 'string' && e.text) ? e.text : '(annotation, no text)';
  if (e.type === 'contested') return (typeof e.note === 'string' && e.note) ? e.note
    : (typeof e.text === 'string' && e.text ? e.text : '(contested — no note)');
  var cands = ['response', 'text', 'note_text', 'note', 'answer', 'comment', 'body', 'message'];
  for (var i = 0; i < cands.length; i++) {
    var v = e[cands[i]];
    if (typeof v === 'string' && v.trim()) return v;
  }
  // no free text — synthesize a faithful description from the event type
  switch (e.type) {
    case 'action-done':       return '(marked the action complete)';
    case 'answered':          return '(answered — no free-text response attached)';
    case 'deferred':          return '(deferred' + (e.scheduled_for ? ' to ' + e.scheduled_for : '') + ')';
    case 'defer-cleared':     return '(cleared the deferral)';
    case 'contest-resolved':  return '(resolved' + (e.resolution ? ': ' + e.resolution : '') + ')';
    case 'backlog-added':     return (typeof e.text === 'string' && e.text) ? e.text : '(added a backlog item)';
    case 'branch-note-add':   return (typeof e.note_text === 'string' && e.note_text) ? e.note_text : '(sent an empty branch note)';
    default:                  return '(' + e.type + ')';
  }
}

var lines = [];
lines.push('[CONVERSATION-TREE GUI RESPONSES — the operator replied to the items below via the Conversation Tree GUI since your last turn. Treat each as if the operator just said it to you in chat, and act on it.]');
lines.push('');
for (var r = 0; r < responses.length; r++) {
  var e = responses[r];
  var node = nodeById[e.node_id];
  var nodeTitle = (node && node.title) ? node.title : (e.node_id || '(unknown branch)');
  var item = itemOf(node, e.item_id);
  lines.push((r + 1) + '. Branch: ' + nodeTitle + '  [node_id=' + (e.node_id || '?') + ']');
  if (e.item_id) {
    var itemText = item && item.text ? item.text : e.item_id;
    var kind = item && item.kind ? item.kind : 'item';
    lines.push('   Item (' + kind + '): ' + itemText + '  [item_id=' + e.item_id + ']');
  }
  lines.push('   Operator response: ' + responseText(e, item));
  lines.push('   (via GUI event "' + e.type + '" · ' + (e.ts || 'unknown time') + ')');
  lines.push('');
}
if (truncatedCount > 0) {
  lines.push('(… plus ' + truncatedCount + ' older GUI response(s) not shown — open the Conversation Tree GUI to review the full set.)');
}

var block = lines.join('\n');
var payload = {
  hookSpecificOutput: {
    hookEventName: 'UserPromptSubmit',
    additionalContext: block
  }
};

writeCursor();
process.stdout.write(JSON.stringify(payload));
process.exit(0);
NODEJS
}

# ============================================================================
# Mode: (default) UserPromptSubmit read
# ============================================================================
_run_read() {
  _have node || { _log "node unavailable — no-op"; exit 0; }
  local input; input=$(_read_stdin)
  local sid; sid=$(_session_id "$input")
  local statef; statef=$(_resolve_gui_state_path)
  local lib;    lib=$(_resolve_state_lib)
  local cdir="${CONV_TREE_READ_CURSOR_DIR:-$CURSOR_DIR_DEFAULT}"
  local cursor="$cdir/$sid.json"
  local maxn="${CONV_TREE_READ_MAX:-12}"
  local cold="${CONV_TREE_READ_COLD_WINDOW_MIN:-120}"

  # State file genuinely absent (GUI never ran) -> silent no-op without even
  # spinning node (keeps the hot path trivial when the GUI is not in use).
  if [[ ! -e "$statef" ]]; then _log "state file absent ($statef) — no-op"; exit 0; fi

  # mtime fast-path. The GUI mutates the state file (via atomic rename) ONLY
  # when the operator acts. We advance the cursor (writing the cursor file)
  # AFTER reading. So if the cursor file is STRICTLY newer than the state
  # file, nothing has been written to state since we last advanced — there is
  # definitively nothing new and we can no-op WITHOUT spinning node (~450ms
  # node+facade cost on Windows -> ~5ms stat compare). Conservative: only skip
  # when the cursor is strictly newer (`-nt`); equal-mtime or state-newer
  # falls through to node so a same-second write is never missed. First run
  # (no cursor) always falls through (cold-start must run).
  if [[ -f "$cursor" && "$cursor" -nt "$statef" ]]; then
    _log "fast-path: cursor newer than state ($sid) — no new events, no-op"
    exit 0
  fi

  local js; js=$(mktemp 2>/dev/null || echo "/tmp/ctr-$$.js")
  _reader_js >"$js" 2>/dev/null || { _log "could not stage reader js"; exit 0; }
  # node prints either the additionalContext JSON or nothing; pass straight
  # through. stderr is diagnostic only (captured to the log).
  node "$js" "$lib" "$statef" "$cursor" "$maxn" "$cold" 2>>"$LOG_FILE" || _log "reader node exited non-zero (isolated)"
  rm -f "$js" 2>/dev/null || true
  exit 0
}

# ============================================================================
# Mode: --self-test
# ============================================================================
_self_test() {
  trap - ERR
  local pass=0 fail=0 tmp
  tmp=$(mktemp -d 2>/dev/null || echo "/tmp/ctr-st-$$"); mkdir -p "$tmp"
  local LIB; LIB=$(_resolve_state_lib)
  if [[ ! -f "$LIB" ]]; then echo "self-test: cannot locate state library ($LIB)"; echo "self-test: FAIL"; exit 1; fi
  _have node || { echo "self-test: node unavailable"; echo "self-test: FAIL"; exit 1; }
  local SELF; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  local CDIR="$tmp/cursors"; mkdir -p "$CDIR"

  # append one event through the FROZEN facade (the only legal writer)
  _append() { # statePath jsonEvent
    node -e 'var s=require(process.argv[1]);try{s.appendEvent(JSON.parse(process.argv[3]),{statePath:process.argv[2]});process.stdout.write("OK")}catch(e){process.stdout.write("ERR:"+(e&&e.message||e))}' "$LIB" "$1" "$2" 2>/dev/null
  }
  # fire the reader (non-self-test path) with synthetic UserPromptSubmit stdin
  _fire() { # statePath session [extraEnv...]
    local sp="$1" sess="$2"
    printf '{"prompt":"hello","session_id":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit"}' "$sess" "$tmp" \
      | CONV_TREE_STATE_PATH="$sp" CONV_TREE_STATE_LIB="${CONV_TREE_STATE_LIB_OVERRIDE:-$LIB}" \
        CONV_TREE_READ_CURSOR_DIR="$CDIR" CONV_TREE_READ_MAX="${MAXOV:-12}" \
        CONV_TREE_READ_COLD_WINDOW_MIN="${COLDOV:-120}" CLAUDE_SESSION_ID="$sess" \
        bash "$SELF" 2>/dev/null
  }
  _ck() { if [[ "$2" == "$3" ]]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (got '$2' want '$3')"; fail=$((fail+1)); fi; }
  _ck_has() { if printf '%s' "$2" | grep -qF -- "$3"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (missing '$3' in: $(printf '%s' "$2" | head -c 200))"; fail=$((fail+1)); fi; }
  _ck_empty() { if [[ -z "${2//[[:space:]]/}" ]]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (expected empty, got: $(printf '%s' "$2" | head -c 200))"; fail=$((fail+1)); fi; }

  local sp out

  # R1 fresh cursor + 1 recent GUI answered+response -> surfaced
  sp="$tmp/r1.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nA","parent_id":null,"title":"Branch Alpha","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"question-raised","node_id":"nA","item_id":"qA","text":"What pricing model?","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"answered","node_id":"nA","item_id":"qA","actor":"gui","response":"go with usage-based tiered"}' >/dev/null
  out=$(_fire "$sp" sess-r1)
  _ck_has "R1 fresh cursor surfaces GUI answered" "$out" "CONVERSATION-TREE GUI RESPONSES"
  _ck_has "R1 contains the operator response text" "$out" "go with usage-based tiered"
  _ck_has "R1 resolves node title from snapshot" "$out" "Branch Alpha"
  _ck_has "R1 resolves item text from snapshot" "$out" "What pricing model?"

  # R2 cursor file created at the last event_id
  if [[ -f "$CDIR/sess-r1.json" ]]; then echo "PASS: R2 cursor file created"; pass=$((pass+1)); else echo "FAIL: R2 cursor file missing"; fail=$((fail+1)); fi

  # R3 immediate re-fire, no new events -> empty stdout (idempotent no-op)
  out=$(_fire "$sp" sess-r1)
  _ck_empty "R3 re-fire with no new events is a no-op" "$out"

  # R4 mid-stream cursor: add a new GUI action-done -> only the new one surfaces
  _append "$sp" '{"type":"action-added","node_id":"nA","item_id":"aA","text":"Ship the reader","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"action-done","node_id":"nA","item_id":"aA","actor":"gui","response":"done, verified locally"}' >/dev/null
  out=$(_fire "$sp" sess-r1)
  _ck_has "R4 mid-stream cursor surfaces the new action-done" "$out" "done, verified locally"
  if printf '%s' "$out" | grep -qF "go with usage-based tiered"; then echo "FAIL: R4 must NOT re-surface the old answered"; fail=$((fail+1)); else echo "PASS: R4 old event not re-surfaced"; pass=$((pass+1)); fi

  # R5 dispatch-actor answered -> NOT surfaced (load-bearing actor exclusion)
  sp="$tmp/r5.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nD","parent_id":null,"title":"Disp","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"answered","node_id":"nD","item_id":"x","actor":"dispatch"}' >/dev/null
  out=$(_fire "$sp" sess-r5)
  _ck_empty "R5 dispatch-actor answered is excluded" "$out"

  # R6 GUI housekeeping (reordered) -> NOT surfaced (type allowlist)
  sp="$tmp/r6.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nH","parent_id":null,"title":"HK","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"reordered","scope":"actions:global","ordered_ids":["a","b"],"actor":"gui"}' >/dev/null
  out=$(_fire "$sp" sess-r6)
  _ck_empty "R6 GUI housekeeping reordered is excluded" "$out"

  # R7 GUI annotated -> surfaced with .text extraction
  sp="$tmp/r7.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nN","parent_id":null,"title":"NoteBranch","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"annotated","node_id":"nN","text":"please prioritise the migration path","actor":"gui"}' >/dev/null
  out=$(_fire "$sp" sess-r7)
  _ck_has "R7 annotated .text extracted" "$out" "please prioritise the migration path"

  # R8 GUI contested -> surfaced with .note extraction
  sp="$tmp/r8.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nC","parent_id":null,"title":"ContestB","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"action-added","node_id":"nC","item_id":"cI","text":"Claimed done item","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"contested","node_id":"nC","item_id":"cI","direction":"dispatch-done-you-disputed","note":"this is not actually done, the button still 404s","actor":"gui"}' >/dev/null
  out=$(_fire "$sp" sess-r8)
  _ck_has "R8 contested .note extracted" "$out" "the button still 404s"

  # R9 missing state file -> exit 0, empty stdout
  out=$(_fire "$tmp/does-not-exist.json" sess-r9)
  _ck_empty "R9 missing state file is a silent no-op" "$out"

  # R10 malformed state file -> exit 0, empty, no crash
  sp="$tmp/r10.json"; printf '{ this is not json ' >"$sp"
  out=$(_fire "$sp" sess-r10)
  _ck_empty "R10 malformed state file is a silent no-op" "$out"

  # R11 large backlog -> truncate to MAX, truncation notice, cursor advances.
  # kept = slice(-12) of resp 1..17 => resp 6..17 ; dropped = resp 1..5.
  sp="$tmp/r11.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nL","parent_id":null,"title":"Lots","actor":"dispatch"}' >/dev/null
  local j
  for j in $(seq 1 17); do
    _append "$sp" "{\"type\":\"annotated\",\"node_id\":\"nL\",\"text\":\"respnum-$j-end\",\"actor\":\"gui\"}" >/dev/null
  done
  export MAXOV=12
  out=$(_fire "$sp" sess-r11)
  _ck_has "R11 large backlog emits truncation notice" "$out" "older GUI response(s) not shown"
  _ck_has "R11 truncation count is N-MAX (17-12=5)" "$out" "plus 5 older"
  _ck_has "R11 keeps the most-recent response (resp 17)" "$out" "respnum-17-end"
  _ck_has "R11 keeps the boundary kept response (resp 6)" "$out" "respnum-6-end"
  if printf '%s' "$out" | grep -qF "respnum-5-end"; then echo "FAIL: R11 should have dropped resp 5 (beyond MAX)"; fail=$((fail+1)); else echo "PASS: R11 dropped responses older than the most-recent MAX"; pass=$((pass+1)); fi
  out=$(_fire "$sp" sess-r11)
  _ck_empty "R11 cursor advanced past the whole backlog (re-fire empty)" "$out"
  unset MAXOV

  # R12 cold-start window: an OLD gui response is NOT surfaced; a recent one is
  sp="$tmp/r12.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nW","parent_id":null,"title":"Win","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"annotated","node_id":"nW","text":"ANCIENT note from days ago","actor":"gui","ts":"2026-05-10T00:00:00.000Z"}' >/dev/null
  _append "$sp" '{"type":"annotated","node_id":"nW","text":"FRESH note just now","actor":"gui"}' >/dev/null
  export COLDOV=120
  out=$(_fire "$sp" sess-r12)
  unset COLDOV
  _ck_has "R12 cold-start surfaces the recent response" "$out" "FRESH note just now"
  if printf '%s' "$out" | grep -qF "ANCIENT note from days ago"; then echo "FAIL: R12 must window-exclude the ancient response"; fail=$((fail+1)); else echo "PASS: R12 cold-start excludes out-of-window response"; pass=$((pass+1)); fi

  # R13 cursor advances past non-response events (only dispatch concluded added)
  sp="$tmp/r13.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nP","parent_id":null,"title":"Prog","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"annotated","node_id":"nP","text":"first gui reply","actor":"gui"}' >/dev/null
  out=$(_fire "$sp" sess-r13)
  _ck_has "R13 first gui reply surfaced" "$out" "first gui reply"
  _append "$sp" '{"type":"concluded","node_id":"nP","actor":"dispatch"}' >/dev/null
  out=$(_fire "$sp" sess-r13)
  _ck_empty "R13 dispatch concluded does not surface and cursor advanced" "$out"
  _append "$sp" '{"type":"annotated","node_id":"nP","text":"second gui reply after concluded","actor":"gui"}' >/dev/null
  out=$(_fire "$sp" sess-r13)
  _ck_has "R13 next gui reply surfaces alone (cursor was past the concluded)" "$out" "second gui reply after concluded"
  if printf '%s' "$out" | grep -qF "first gui reply"; then echo "FAIL: R13 must not re-surface the first reply"; fail=$((fail+1)); else echo "PASS: R13 no re-surface across non-response events"; pass=$((pass+1)); fi

  # R14 item-kind label rendered for an item-bearing GUI response
  sp="$tmp/r14.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nK","parent_id":null,"title":"KindBranch","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"question-raised","node_id":"nK","item_id":"kQ","text":"Which deploy target?","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"answered","node_id":"nK","item_id":"kQ","actor":"gui","response":"prod"}' >/dev/null
  out=$(_fire "$sp" sess-r14)
  _ck_has "R14 item kind label rendered (question)" "$out" "Item (question):"
  _ck_has "R14 item_id rendered" "$out" "item_id=kQ"

  # R15 failure isolation: broken state-lib path -> exit 0, empty
  sp="$tmp/r15.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nF","parent_id":null,"title":"Iso","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"annotated","node_id":"nF","text":"should not appear","actor":"gui"}' >/dev/null
  export CONV_TREE_STATE_LIB_OVERRIDE="$tmp/nope.js"
  out=$(_fire "$sp" sess-r15)
  unset CONV_TREE_STATE_LIB_OVERRIDE
  _ck_empty "R15 broken state-lib path is a silent no-op" "$out"

  # R16 END-TO-END walking skeleton: GUI answered+response -> valid
  #     UserPromptSubmit additionalContext JSON containing the response
  sp="$tmp/r16.json"
  _append "$sp" '{"type":"branch-opened","node_id":"e2e","parent_id":null,"title":"E2E Branch","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"question-raised","node_id":"e2e","item_id":"e2eq","text":"Approve the rollout?","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"answered","node_id":"e2e","item_id":"e2eq","actor":"gui","response":"approved, ship to prod tonight"}' >/dev/null
  out=$(_fire "$sp" sess-e2e)
  local hen ac
  hen=$(printf '%s' "$out" | node -e 'var d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{var j=JSON.parse(d);process.stdout.write(j.hookSpecificOutput&&j.hookSpecificOutput.hookEventName||"")}catch(e){process.stdout.write("PARSEERR")}})' 2>/dev/null)
  ac=$(printf '%s' "$out" | node -e 'var d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{var j=JSON.parse(d);process.stdout.write(j.hookSpecificOutput&&j.hookSpecificOutput.additionalContext||"")}catch(e){process.stdout.write("PARSEERR")}})' 2>/dev/null)
  _ck "R16 e2e stdout is valid JSON, hookEventName==UserPromptSubmit" "$hen" "UserPromptSubmit"
  _ck_has "R16 e2e additionalContext carries the operator response" "$ac" "approved, ship to prod tonight"

  # R17 stdout is ONLY the JSON object (single line, parses cleanly)
  if printf '%s' "$out" | node -e 'var d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{JSON.parse(d);process.exit(0)}catch(e){process.exit(1)}})' 2>/dev/null; then
    echo "PASS: R17 stdout is exactly one valid JSON object"; pass=$((pass+1))
  else echo "FAIL: R17 stdout is not clean JSON"; fail=$((fail+1)); fi

  # R18 idempotent re-fire of the e2e -> empty (cursor advanced)
  out=$(_fire "$sp" sess-e2e)
  _ck_empty "R18 e2e re-fire is idempotent no-op" "$out"

  # R19 mtime fast-path: with NO new event, a re-fire must NOT spin node, so
  # the cursor file is NOT rewritten -> its mtime is unchanged. Deterministic
  # proof the perf fast-path engaged (cursor newer than state => skip node).
  sp="$tmp/r19.json"
  _append "$sp" '{"type":"branch-opened","node_id":"nFp","parent_id":null,"title":"FP","actor":"dispatch"}' >/dev/null
  _append "$sp" '{"type":"annotated","node_id":"nFp","text":"fp first reply","actor":"gui"}' >/dev/null
  out=$(_fire "$sp" sess-r19); : "$out"
  local cm0 cm1 cm2
  cm0=$(stat -c %Y "$CDIR/sess-r19.json" 2>/dev/null || echo 0)
  sleep 1.1
  out=$(_fire "$sp" sess-r19)
  cm1=$(stat -c %Y "$CDIR/sess-r19.json" 2>/dev/null || echo 0)
  _ck_empty "R19 fast-path re-fire is empty" "$out"
  if [[ "$cm0" == "$cm1" ]]; then echo "PASS: R19 fast-path skipped node (cursor mtime unchanged)"; pass=$((pass+1)); else echo "FAIL: R19 cursor was rewritten ($cm0 -> $cm1) — node ran, fast-path missed"; fail=$((fail+1)); fi

  # R20 fast-path correctly NOT taken when a new event arrived: state becomes
  # newer than cursor -> node runs -> cursor is rewritten (mtime advances).
  _append "$sp" '{"type":"annotated","node_id":"nFp","text":"fp second reply","actor":"gui"}' >/dev/null
  out=$(_fire "$sp" sess-r19)
  cm2=$(stat -c %Y "$CDIR/sess-r19.json" 2>/dev/null || echo 0)
  _ck_has "R20 new event after fast-path is surfaced" "$out" "fp second reply"
  if [[ "$cm2" != "$cm1" ]]; then echo "PASS: R20 node ran on new event (cursor mtime advanced)"; pass=$((pass+1)); else echo "FAIL: R20 cursor not advanced — new event would be missed next turn"; fail=$((fail+1)); fi

  rm -rf "$tmp" 2>/dev/null || true
  echo "self-test: $pass passed, $fail failed"
  if [[ $fail -eq 0 ]]; then echo "self-test: OK"; exit 0; else echo "self-test: FAIL"; exit 1; fi
}

# ============================================================================
# Dispatch
# ============================================================================
case "$MODE" in
  --self-test) _self_test ;;
  ""|--read)   _run_read ;;
  *)
    # Unknown mode: never block the prompt (reader, not gate).
    _log "invoked with unknown mode '${MODE:-}' — no-op"
    exit 0
    ;;
esac
