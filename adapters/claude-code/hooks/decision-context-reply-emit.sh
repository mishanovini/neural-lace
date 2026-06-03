#!/bin/bash
# decision-context-reply-emit.sh — UserPromptSubmit WRITER for the
# decision-context-gate (Task 6 of docs/plans/decision-context-gate-2026-05-29.md;
# referenced by Plan Section E + decision-context.md Pattern + ADR 047).
#
# Classification: WRITER hook on UserPromptSubmit, NOT a gate. It MUST NEVER
# block the user's prompt — every runtime path exits 0. Emission failures are
# isolated and logged; facade-down events land in
# `~/.claude/state/decision-context/fallback.jsonl` for Task 8's drainer.
# (gate-respect.md: writer hooks do not block; same posture as
# conversation-tree-emit.sh and goal-extraction-on-prompt.sh.)
#
# What this hook does:
#   On every user prompt submission, scans the prompt for references to OPEN
#   decision-context items in the conversation-tree state. A reference is
#   either (a) a literal occurrence of an open item's `item_id` or its node's
#   `node_id` (case-sensitive token match), or (b) a case-insensitive
#   substring match of the item's `details.reply_with` phrase (set by the
#   Task 4 Stop hook when emitting `item-details-set` for the rich payload).
#
#   For each matched OPEN item, emits via the state.js facade:
#     - `answered`     (kind == 'decision' or 'question')
#     - `action-done`  (kind == 'action')
#   If the prompt also carries follow-up text after the matched phrase, an
#   additional `item-details-set` event is emitted with `details = { response_text: ... }`
#   so the resolution prose is captured on the item.
#
#   Items that are NOT open (checked, deferred, backlogged) OR whose node is
#   `archived` / `concluded` are explicitly skipped — a stale reference to a
#   resolved/archived item is silently ignored (ST10).
#
# Idempotency:
#   `event_id` is deterministic per (item_id, sha1(prompt)) so a re-fire on
#   the same prompt produces the SAME event_id, which the facade dedupes
#   per ADR-032 §2 (per-file idempotency on event_id). ST6 locks this.
#
# Failure isolation:
#   All errors -> log to ~/.claude/logs/decision-context-reply-emit.log and
#   exit 0. On facade write failure, append the event line to
#   ~/.claude/state/decision-context/fallback.jsonl (Task 8 drains).

set -uo pipefail

MODE="${1:-}"

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/decision-context-reply-emit.log"
FALLBACK_DIR="$HOME/.claude/state/decision-context"
FALLBACK_FILE="$FALLBACK_DIR/fallback.jsonl"

_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "${MODE:-?}" "$*" >>"$LOG_FILE" 2>/dev/null || true
}
_die_safe() { _log "isolated error: $*"; exit 0; }
trap '_die_safe "uncaught (line $LINENO)"' ERR

_have() { command -v "$1" >/dev/null 2>&1; }

# sha1 of stdin (mirrors conversation-tree-emit.sh helper)
_sha1() {
  if _have sha1sum; then sha1sum | cut -d' ' -f1
  elif _have shasum; then shasum -a 1 | cut -d' ' -f1
  else cksum | tr -d ' ' ; fi
}

# Resolve state-library + state file paths — copy of conversation-tree-emit.sh's
# resolver pattern (attribution: state-lib resolver pattern adapted from
# conversation-tree-emit.sh _resolve_state_lib / _resolve_gui_state_path /
# _resolve_gate_state_path / _main_repo_root, ~/.claude/hooks/conversation-tree-emit.sh
# lines 106-176 — kept byte-identical-in-behavior so writer and gate agree).

_fallback_conv_tree_path() {
  local leaf="$1"
  local base="${CONV_TREE_MAIN_CHECKOUT:-$HOME/claude-projects/neural-lace}"
  # UI module renamed conversation-tree-ui -> workstreams-ui (2026-06); prefer
  # the new name, keep the old as back-compat fallback.
  local d cand
  for d in workstreams-ui conversation-tree-ui; do
    for cand in "$base/neural-lace/$d/$leaf" "$base/$d/$leaf"; do
      if [[ -e "$cand" ]]; then printf '%s' "$cand"; return 0; fi
    done
  done
  printf '%s' "$base/neural-lace/workstreams-ui/$leaf"
}

_resolve_state_lib() {
  if [[ -n "${CONV_TREE_STATE_LIB:-}" ]]; then printf '%s' "$CONV_TREE_STATE_LIB"; return 0; fi
  local root=""
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    local cand="$root/neural-lace/conversation-tree-ui/state/state.js"
    if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
    cand="$root/conversation-tree-ui/state/state.js"
    if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
  fi
  _fallback_conv_tree_path "state/state.js"
}

_main_repo_root() {
  local gcd
  gcd=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  [[ -z "$gcd" ]] && return 1
  local d
  d=$(cd "$(dirname "$gcd")" 2>/dev/null && pwd) || return 1
  printf '%s' "$d"
}

_resolve_gui_state_path() {
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then printf '%s' "$CONV_TREE_STATE_PATH"; return 0; fi
  local mr
  if mr=$(_main_repo_root) && [[ -n "$mr" ]]; then
    local c="$mr/neural-lace/conversation-tree-ui/state/tree-state.json"
    if [[ -f "$mr/neural-lace/conversation-tree-ui/state/state.js" ]]; then printf '%s' "$c"; return 0; fi
    c="$mr/conversation-tree-ui/state/tree-state.json"
    if [[ -f "$mr/conversation-tree-ui/state/state.js" ]]; then printf '%s' "$c"; return 0; fi
  fi
  _fallback_conv_tree_path "state/tree-state.json"
}

_resolve_gate_state_path() {
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then printf '%s' "$CONV_TREE_STATE_PATH"; return 0; fi
  local root=""
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    local proj="$root/.claude/state/conversation-tree/tree-state.json"
    if [[ -f "$proj" ]]; then printf '%s' "$proj"; return 0; fi
  fi
  if [[ -n "$root" ]]; then
    printf '%s' "$root/.claude/state/conversation-tree/tree-state.json"; return 0
  fi
  printf '%s' "$HOME/.claude/state/conversation-tree/global/tree-state.json"
}

# Read JSON input from stdin (UserPromptSubmit passes {prompt, session_id, cwd, ...}).
_read_stdin() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]] && [[ ! -t 0 ]]; then input=$(cat 2>/dev/null || echo ""); fi
  printf '%s' "$input"
}

# Append an event line (as compact JSON) to the fallback.jsonl queue. Used when
# the state.js facade write fails (broken state-lib path, missing node, etc.).
# Task 8's decision-context-replay.sh drains this queue on next SessionStart.
_fallback_write() {
  local ev_json="$1" sink="$2"
  mkdir -p "$FALLBACK_DIR" 2>/dev/null || true
  # Wrap with target sink path so the replay drainer knows where to re-emit.
  local line
  line=$(printf '{"sink":%s,"event":%s,"queued_at":%s}\n' \
    "$(jq -nc --arg s "$sink" '$s' 2>/dev/null || echo "\"\"")" \
    "$ev_json" \
    "$(jq -nc --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" '$t' 2>/dev/null || echo "\"\"")" \
    )
  printf '%s' "$line" >>"$FALLBACK_FILE" 2>/dev/null || true
}

# Core logic: read snapshot, find open items, detect references in prompt,
# emit events via the facade. All in ONE node subprocess so a single read of
# the snapshot is consistent with the emit set (no race between two reads).
# Returns on stdout: a status summary line. Always exits node 0.
_scan_and_emit() {
  local lib="$1" sink="$2" prompt="$3" prompt_sha="$4"
  _have node || { _log "node unavailable — cannot scan"; return 0; }
  [[ -z "$lib" || ! -f "$lib" ]] && { _log "state-lib missing at $lib — fallback queue"; return 1; }
  mkdir -p "$(dirname "$sink")" 2>/dev/null || true

  local emit_out
  emit_out=$(node -e '
    "use strict";
    var libPath = process.argv[1];
    var sink    = process.argv[2];
    var prompt  = process.argv[3];
    var promptSha = process.argv[4];
    var s;
    try { s = require(libPath); } catch (e) { process.stdout.write("LIBERR:" + (e && e.message || e)); process.exit(0); }
    var st;
    try { st = s.readState({ statePath: sink }); } catch (e) { process.stdout.write("READERR:" + (e && e.message || e)); process.exit(0); }
    var snap = (st && st.snapshot) || { nodes: [] };
    var nodes = snap.nodes || [];

    // Token boundary regex helper — case-sensitive literal id match.
    function escRe(t) { return t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
    function tokenMatch(text, token) {
      if (!token) return false;
      var re = new RegExp("(^|[^A-Za-z0-9_-])" + escRe(token) + "(?:[^A-Za-z0-9_-]|$)");
      return re.test(text);
    }
    // Case-insensitive substring match for reply_with phrases (looser by design).
    function phraseMatch(text, phrase) {
      if (!phrase) return null;
      var lc = String(text).toLowerCase();
      var pc = String(phrase).toLowerCase();
      var idx = lc.indexOf(pc);
      if (idx < 0) return null;
      return { idx: idx, len: phrase.length };
    }
    // Extract follow-up response text after the matched phrase or id.
    // Strategy: take everything after the match through the end of the prompt,
    // trimmed and capped at 2000 chars. If the result is empty (the user only
    // typed the trigger phrase), return null.
    function followUp(text, start, len) {
      if (start < 0) return null;
      var tail = text.slice(start + len).replace(/^[\s\.,;:!?\-]+/, "").replace(/\s+$/, "");
      if (!tail) return null;
      return tail.length > 2000 ? tail.slice(0, 2000) : tail;
    }

    var ok = 0, skipped = 0, matched = [], errors = [];

    for (var ni = 0; ni < nodes.length; ni++) {
      var node = nodes[ni];
      if (!node || node.state === "archived" || node.state === "concluded") continue;
      var items = node.items || [];
      for (var ii = 0; ii < items.length; ii++) {
        var it = items[ii];
        if (!it) continue;
        // Open = not checked AND not deferred AND not backlogged.
        if (it.checked) continue;
        if (it.deferred) continue;
        if (it.backlogged) continue;

        var nodeId = node.node_id;
        var itemId = it.item_id;
        var kind   = it.kind; // decision | question | action
        var reply  = (it.details && typeof it.details === "object" && typeof it.details.reply_with === "string")
          ? it.details.reply_with : null;

        var hit = null;
        // (a) literal item_id token match — preferred (more specific)
        if (itemId && tokenMatch(prompt, itemId)) {
          var idx = prompt.indexOf(itemId);
          hit = { kind: "id", text: itemId, idx: idx, len: itemId.length };
        }
        // (b) literal node_id token match
        if (!hit && nodeId && tokenMatch(prompt, nodeId)) {
          var idx2 = prompt.indexOf(nodeId);
          hit = { kind: "id", text: nodeId, idx: idx2, len: nodeId.length };
        }
        // (c) reply_with phrase (case-insensitive substring) — most permissive
        if (!hit && reply) {
          var pm = phraseMatch(prompt, reply);
          if (pm) hit = { kind: "phrase", text: reply, idx: pm.idx, len: pm.len };
        }

        if (!hit) continue;

        // Determine event type by kind.
        var evType = (kind === "action") ? "action-done" : "answered";

        // Deterministic event_id: dcre-<type-tag>-<sha1(item_id|promptSha)[0:24]>
        var crypto = require("crypto");
        var idHash = crypto.createHash("sha1")
          .update(String(itemId) + "|" + String(promptSha))
          .digest("hex").slice(0, 24);
        var evTag = (evType === "action-done") ? "ad" : "an";
        var eventId = "dcre-" + evTag + "-" + idHash;

        var ev = {
          event_id: eventId,
          type: evType,
          node_id: nodeId,
          item_id: itemId,
          actor: "dispatch"
        };

        try {
          s.appendEvent(ev, { statePath: sink });
          ok++;
          matched.push({ node_id: nodeId, item_id: itemId, type: evType, via: hit.kind });
        } catch (e) {
          skipped++;
          errors.push({ ev: ev, err: String(e && e.message || e) });
        }

        // Optional follow-up response text -> item-details-set.
        var rt = followUp(prompt, hit.idx, hit.len);
        if (rt) {
          var detailsHash = crypto.createHash("sha1")
            .update(String(itemId) + "|" + String(promptSha) + "|details")
            .digest("hex").slice(0, 24);
          var dEv = {
            event_id: "dcre-ds-" + detailsHash,
            type: "item-details-set",
            node_id: nodeId,
            item_id: itemId,
            details: { response_text: rt },
            actor: "dispatch"
          };
          try {
            s.appendEvent(dEv, { statePath: sink });
            ok++;
          } catch (e) {
            skipped++;
            errors.push({ ev: dEv, err: String(e && e.message || e) });
          }
        }
      }
    }

    process.stdout.write(JSON.stringify({ ok: ok, skipped: skipped, matched: matched, errors: errors }));
    process.exit(0);
  ' "$lib" "$sink" "$prompt" "$prompt_sha" 2>>"$LOG_FILE")
  local rc=$?
  _log "scan sink=$sink result=$emit_out rc=$rc"

  # If emit_out is an error sentinel, signal caller to fall back.
  case "$emit_out" in
    LIBERR:*|READERR:*|"") return 1 ;;
  esac

  # If any items were skipped due to per-event errors, write them to fallback.
  # Parse JSON via node to get the errors[] list.
  if printf '%s' "$emit_out" | grep -q '"skipped":0'; then
    : # clean run
  else
    local err_count
    err_count=$(printf '%s' "$emit_out" | node -e '
      try { var o = JSON.parse(require("fs").readFileSync(0, "utf8")); process.stdout.write(String((o.errors||[]).length)); }
      catch (e) { process.stdout.write("0"); }
    ' 2>/dev/null || echo 0)
    if [[ "$err_count" != "0" && "$err_count" != "" ]]; then
      # Drain errors into fallback queue.
      printf '%s' "$emit_out" | node -e '
        try {
          var o = JSON.parse(require("fs").readFileSync(0, "utf8"));
          var es = o.errors || [];
          for (var i = 0; i < es.length; i++) {
            process.stdout.write(JSON.stringify(es[i].ev) + "\n");
          }
        } catch (e) {}
      ' 2>/dev/null | while IFS= read -r ev_line; do
        [[ -z "$ev_line" ]] && continue
        _fallback_write "$ev_line" "$sink"
      done
    fi
  fi

  return 0
}

# ============================================================================
# Mode: default (UserPromptSubmit)
# ============================================================================
_run_default() {
  local input; input=$(_read_stdin)
  [[ -z "$input" ]] && exit 0
  _have jq || { _log "jq unavailable — cannot parse UserPromptSubmit input"; exit 0; }

  local prompt
  prompt=$(printf '%s' "$input" | jq -r '.prompt // .user_prompt // .message // empty' 2>/dev/null || echo "")
  [[ -z "$prompt" ]] && exit 0   # no prompt -> nothing to scan

  # sha1 of prompt — feeds the deterministic event_id so re-fires dedupe.
  local prompt_sha
  prompt_sha=$(printf '%s' "$prompt" | _sha1)

  local lib; lib=$(_resolve_state_lib)

  # Dual-sink emit: GUI STATE_FILE + §5-resolved gate path (same idempotent
  # event_id makes a coincidentally-equal double-write a per-file no-op).
  # CONV_TREE_STATE_PATH overrides to a single explicit sink (self-test).
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then
    if ! _scan_and_emit "$lib" "$CONV_TREE_STATE_PATH" "$prompt" "$prompt_sha"; then
      # Facade unavailable -> fallback queue (we don't know which item matched,
      # so write a single sentinel record noting the failure for audit).
      _fallback_write '{"type":"_facade_down_sentinel","reason":"state-lib-unreachable"}' "$CONV_TREE_STATE_PATH"
    fi
    exit 0
  fi

  local gui gate
  gui=$(_resolve_gui_state_path)
  gate=$(_resolve_gate_state_path)
  local any_ok=0
  if [[ -n "$gui" ]]; then
    if _scan_and_emit "$lib" "$gui" "$prompt" "$prompt_sha"; then any_ok=1; fi
  fi
  if [[ -n "$gate" && "$gate" != "$gui" ]]; then
    if _scan_and_emit "$lib" "$gate" "$prompt" "$prompt_sha"; then any_ok=1; fi
  fi
  if [[ "$any_ok" -eq 0 ]]; then
    # All sinks failed -> fallback sentinel so the operator + replay drainer
    # see we couldn't reach the facade.
    _fallback_write '{"type":"_facade_down_sentinel","reason":"all-sinks-failed"}' "${gui:-${gate:-}}"
  fi

  exit 0
}

# ============================================================================
# Mode: --self-test
# ============================================================================
_self_test() {
  trap - ERR
  local pass=0 fail=0 tmp
  tmp=$(mktemp -d 2>/dev/null || echo "/tmp/dcre-st-$$"); mkdir -p "$tmp"
  local LIB; LIB=$(CONV_TREE_STATE_LIB="${CONV_TREE_STATE_LIB:-}" _resolve_state_lib)
  if [[ ! -f "$LIB" ]]; then echo "self-test: cannot locate state library ($LIB)"; echo "self-test: FAIL"; exit 1; fi
  export CONV_TREE_STATE_LIB="$LIB"
  local SELF; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  # Use a private fallback file per self-test run so we don't pollute the live one.
  local SAVED_FALLBACK_DIR="$FALLBACK_DIR"
  local SAVED_FALLBACK_FILE="$FALLBACK_FILE"
  export _DCRE_SELFTEST_FB_DIR="$tmp/fallback-dir"
  export _DCRE_SELFTEST_FB_FILE="$_DCRE_SELFTEST_FB_DIR/fallback.jsonl"

  _ck() { if [[ "$2" == "$3" ]]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (got '$2' want '$3')"; fail=$((fail+1)); fi; }

  # Helper: seed a state file with one branch + one item of given kind, optional
  # reply_with via item-details-set. Idempotency-safe: distinct event_ids.
  _seed() {
    local sp="$1" node_id="$2" node_title="$3" item_id="$4" kind="$5" reply_with="$6" item_state="${7:-open}"
    node -e '
      var s = require(process.argv[1]);
      var sp = process.argv[2];
      var nodeId = process.argv[3], nodeTitle = process.argv[4];
      var itemId = process.argv[5], kind = process.argv[6];
      var reply = process.argv[7];
      var itemState = process.argv[8];
      var raisedType = kind === "action" ? "action-added" : (kind === "question" ? "question-raised" : "decision-raised");
      s.appendEvent({event_id:"seed-bo-"+nodeId, type:"branch-opened", node_id:nodeId, parent_id:null, title:nodeTitle, actor:"gui"}, {statePath: sp});
      s.appendEvent({event_id:"seed-it-"+itemId, type:raisedType, node_id:nodeId, item_id:itemId, text:"seed-text", actor:"gui"}, {statePath: sp});
      if (reply) {
        s.appendEvent({event_id:"seed-ds-"+itemId, type:"item-details-set", node_id:nodeId, item_id:itemId, details:{reply_with: reply}, actor:"gui"}, {statePath: sp});
      }
      if (itemState === "checked") {
        var doneType = kind === "action" ? "action-done" : "answered";
        s.appendEvent({event_id:"seed-dn-"+itemId, type:doneType, node_id:nodeId, item_id:itemId, actor:"gui"}, {statePath: sp});
      } else if (itemState === "archived-node") {
        s.appendEvent({event_id:"seed-ar-"+nodeId, type:"archived", node_id:nodeId, actor:"gui"}, {statePath: sp});
      }
    ' "$LIB" "$sp" "$node_id" "$node_title" "$item_id" "$kind" "$reply_with" "$item_state" 2>/dev/null
  }

  # Helper: count events of given type in state file.
  _count() {
    node -e '
      try {
        var s = require(process.argv[1]);
        var st = s.readState({statePath: process.argv[2]});
        var t = process.argv[3];
        process.stdout.write(String(st.events.filter(function(e){return e.type===t}).length));
      } catch (e) { process.stdout.write("ERR"); }
    ' "$LIB" "$1" "$2" 2>/dev/null
  }

  # Helper: check whether item is checked.
  _is_checked() {
    node -e '
      try {
        var s = require(process.argv[1]);
        var st = s.readState({statePath: process.argv[2]});
        var iid = process.argv[3];
        var found = "MISSING";
        for (var ni = 0; ni < st.snapshot.nodes.length; ni++) {
          var node = st.snapshot.nodes[ni];
          for (var ii = 0; ii < (node.items||[]).length; ii++) {
            if (node.items[ii].item_id === iid) {
              found = node.items[ii].checked ? "Y" : "N";
            }
          }
        }
        process.stdout.write(found);
      } catch (e) { process.stdout.write("ERR"); }
    ' "$LIB" "$1" "$2" 2>/dev/null
  }

  # Helper: get response_text from item.details (set via item-details-set).
  _resp_text() {
    node -e '
      try {
        var s = require(process.argv[1]);
        var st = s.readState({statePath: process.argv[2]});
        var iid = process.argv[3];
        var rt = "";
        for (var ni = 0; ni < st.snapshot.nodes.length; ni++) {
          var node = st.snapshot.nodes[ni];
          for (var ii = 0; ii < (node.items||[]).length; ii++) {
            if (node.items[ii].item_id === iid && node.items[ii].details && node.items[ii].details.response_text) {
              rt = node.items[ii].details.response_text;
            }
          }
        }
        process.stdout.write(rt);
      } catch (e) { process.stdout.write("ERR"); }
    ' "$LIB" "$1" "$2" 2>/dev/null
  }

  # Helper: run the hook with given prompt against given state path.
  _run() {
    local sp="$1" prompt="$2"
    CONV_TREE_STATE_PATH="$sp" CLAUDE_SESSION_ID="sess-dcre-st" \
      bash "$SELF" <<<"$(jq -nc --arg p "$prompt" '{prompt: $p, session_id: "sess-dcre-st"}')" >/dev/null 2>&1
  }

  # ===========================================================================
  # ST1: No tree-state available -> exit 0 silent no-op (broken lib path)
  local sp1="$tmp/st-1.json" rc1
  CONV_TREE_STATE_PATH="$sp1" CONV_TREE_STATE_LIB="$tmp/does-not-exist.js" \
    bash "$SELF" <<<'{"prompt":"hello world","session_id":"sess-dcre-st-1"}' >/dev/null 2>&1
  rc1=$?
  _ck "ST1 broken state-lib -> exit 0 silent no-op" "$rc1" "0"

  # ===========================================================================
  # ST2: Open decision item, prompt contains item_id literal -> `answered` emitted
  local sp2="$tmp/st-2.json"
  _seed "$sp2" "br-st2" "Branch ST2" "DEC-ST2-001" "decision" ""
  _run "$sp2" "I want to go with option A for DEC-ST2-001 please"
  _ck "ST2 decision id-literal -> answered emitted" "$(_count "$sp2" answered)" "1"
  _ck "ST2 decision id-literal -> item checked" "$(_is_checked "$sp2" "DEC-ST2-001")" "Y"

  # ===========================================================================
  # ST3: Open question item, prompt contains reply_with phrase (case-insensitive)
  local sp3="$tmp/st-3.json"
  _seed "$sp3" "br-st3" "Branch ST3" "Q-ST3-001" "question" "go with the BLUE one"
  _run "$sp3" "OK, Go With The Blue One — that fits the brand"
  _ck "ST3 question reply_with phrase (case-insensitive) -> answered emitted" "$(_count "$sp3" answered)" "1"

  # ===========================================================================
  # ST4: Open action item, prompt contains item_id -> `action-done` (NOT answered)
  local sp4="$tmp/st-4.json"
  _seed "$sp4" "br-st4" "Branch ST4" "ACT-ST4-001" "action" ""
  _run "$sp4" "Done — finished ACT-ST4-001 last night"
  _ck "ST4 action id-literal -> action-done emitted" "$(_count "$sp4" action-done)" "1"
  _ck "ST4 action id-literal -> answered NOT emitted" "$(_count "$sp4" answered)" "0"

  # ===========================================================================
  # ST5: reply_with phrase + follow-up text -> answered + item-details-set
  local sp5="$tmp/st-5.json"
  _seed "$sp5" "br-st5" "Branch ST5" "DEC-ST5-001" "decision" "use postgres"
  _run "$sp5" "use postgres because it's already authenticated and the team knows it"
  _ck "ST5 reply_with + follow-up -> answered" "$(_count "$sp5" answered)" "1"
  _ck "ST5 reply_with + follow-up -> item-details-set" "$(_count "$sp5" item-details-set)" "2"   # 1 seed + 1 new
  local rt5; rt5=$(_resp_text "$sp5" "DEC-ST5-001")
  if [[ "$rt5" == *"because it's already authenticated"* ]]; then echo "PASS: ST5 response_text captured"; pass=$((pass+1));
  else echo "FAIL: ST5 response_text (got '$rt5')"; fail=$((fail+1)); fi

  # ===========================================================================
  # ST6: Idempotency — 3 invocations with the same prompt/state -> 1 event per item
  local sp6="$tmp/st-6.json"
  _seed "$sp6" "br-st6" "Branch ST6" "DEC-ST6-001" "decision" ""
  for _r in 1 2 3; do _run "$sp6" "I pick DEC-ST6-001 — go with it"; done
  _ck "ST6 idempotent 3-fire same prompt -> exactly 1 answered event" "$(_count "$sp6" answered)" "1"

  # ===========================================================================
  # ST7: Facade-down (broken state-lib) -> exit 0 + fallback.jsonl written
  local sp7="$tmp/st-7.json" rc7
  # Seed a real state file first so the resolver could find SOMETHING, but
  # pass a broken lib so the node require fails inside _scan_and_emit.
  _seed "$sp7" "br-st7" "Branch ST7" "DEC-ST7-001" "decision" ""
  rm -rf "$tmp/fb-st7"
  CONV_TREE_STATE_PATH="$sp7" CONV_TREE_STATE_LIB="$tmp/missing-lib.js" \
    HOME="$tmp/fakehome-st7" \
    bash "$SELF" <<<'{"prompt":"refer to DEC-ST7-001","session_id":"sess-st7"}' >/dev/null 2>&1
  rc7=$?
  local fb_st7="$tmp/fakehome-st7/.claude/state/decision-context/fallback.jsonl"
  if [[ "$rc7" -eq 0 && -f "$fb_st7" ]]; then
    echo "PASS: ST7 facade-down -> exit 0 + fallback.jsonl written"; pass=$((pass+1))
  else
    echo "FAIL: ST7 facade-down (rc=$rc7, fb-exists=$([ -f "$fb_st7" ] && echo y || echo n))"; fail=$((fail+1))
  fi

  # ===========================================================================
  # ST8: No matching open items -> exit 0 silent
  local sp8="$tmp/st-8.json" rc8
  _seed "$sp8" "br-st8" "Branch ST8" "DEC-ST8-001" "decision" "exact phrase"
  CONV_TREE_STATE_PATH="$sp8" CLAUDE_SESSION_ID="sess-st8" \
    bash "$SELF" <<<'{"prompt":"a totally unrelated chat about lunch","session_id":"sess-st8"}' >/dev/null 2>&1
  rc8=$?
  _ck "ST8 no match -> exit 0" "$rc8" "0"
  _ck "ST8 no match -> NO answered event" "$(_count "$sp8" answered)" "0"
  _ck "ST8 no match -> NO action-done event" "$(_count "$sp8" action-done)" "0"

  # ===========================================================================
  # ST9: Multiple open items, prompt mentions a subset -> events only for mentioned
  local sp9="$tmp/st-9.json"
  _seed "$sp9" "br-st9a" "Branch ST9a" "DEC-ST9-001" "decision" ""
  _seed "$sp9" "br-st9b" "Branch ST9b" "DEC-ST9-002" "decision" ""
  _seed "$sp9" "br-st9c" "Branch ST9c" "DEC-ST9-003" "decision" ""
  _run "$sp9" "I'll handle DEC-ST9-001 and DEC-ST9-003 now"
  _ck "ST9 multi-match -> 2 answered events (not 3)" "$(_count "$sp9" answered)" "2"

  # ===========================================================================
  # ST10: Stale archived item — prompt mentions its id -> NO event emitted
  local sp10="$tmp/st-10.json"
  _seed "$sp10" "br-st10" "Branch ST10" "DEC-ST10-001" "decision" "" "archived-node"
  _run "$sp10" "still working on DEC-ST10-001"
  _ck "ST10 archived node -> NO answered event" "$(_count "$sp10" answered)" "0"

  # Also verify a checked item is skipped (related case).
  local sp10b="$tmp/st-10b.json"
  _seed "$sp10b" "br-st10b" "Branch ST10b" "DEC-ST10B-001" "decision" "" "checked"
  _run "$sp10b" "follow-up on DEC-ST10B-001"
  # Seed already produced 1 `answered`. Re-running must not add another.
  _ck "ST10b already-checked item -> still exactly 1 answered (no double-fire)" "$(_count "$sp10b" answered)" "1"

  # ===========================================================================
  # Summary
  local total=$((pass + fail))
  if [[ $fail -eq 0 ]]; then
    echo "self-test: OK $pass/$total"
    exit 0
  else
    echo "self-test: FAIL $pass/$total ($fail failed)"
    exit 1
  fi
}

# ============================================================================
# Entry point
# ============================================================================
case "$MODE" in
  --self-test) _self_test ;;
  *) _run_default ;;
esac
