#!/bin/bash
# conversation-tree-extract-pending.sh — Claude-side Stop hook that auto-extracts
# pending items from the orchestrator's final assistant message into the
# Conversation-Tree UI (ADR-038; harvested from the stranded Gap 5 design in
# docs/reviews/2026-05-20-conv-tree-session-harness-gaps.md).
#
# Classification: WRITER hook, NOT a gate. It NEVER blocks Stop. Every runtime
# path exits 0. Extraction failures are isolated and logged to
# ~/.claude/logs/conversation-tree-extract-pending.log; they must never break
# the orchestrator (gate-respect.md: writer hooks do not block anything). This
# mirrors conversation-tree-emit.sh exactly.
#
# It does NOT reimplement appendEvent — it pipes JSON payloads to the sibling
# conversation-tree-emit.sh --emit-branch / --emit-item modes (shipped 2026-05-21,
# v1.1.5). All state writes stay behind the single frozen state-library facade.
#
# ----------------------------------------------------------------------------
# Marker convention (ADR-038 D1 — the parser contract):
#
#   A SECTION HEADER is a line, alone on its own line, matching (case-insensitive,
#   optional trailing colon) one of — optionally bold-wrapped (`**…**`) or as a
#   markdown heading (`## …`):
#       Questions for Misha     -> item kind `question`
#       Action items for Misha  -> item kind `action`
#       Decisions for Misha     -> item kind `decision`
#
#   ITEMS are the bullet/numbered list immediately following the header:
#       `- `, `* `, `+ `, `1. `, or `1) `. An item runs until the next list
#       marker, the next section header, a horizontal rule, or a blank-line gap.
#       A non-list, non-blank line after an item is captured as a wrapped
#       continuation of that item (multi-line items captured whole).
#
#   The section ends at the next header, a horizontal rule (`---`/`***`/`___`),
#   a blank line, or end-of-message. Prose mentions of these phrases mid-sentence
#   are deliberately NOT extracted (the header must be anchored to its own line).
#
# Anchor resolution (ADR-038 D3):
#   1. If the per-session ledger (CONV_TREE_LEDGER_DIR, default
#      ~/.claude/state/conversation-tree-emit/opened-<sid>.jsonl) records a branch
#      this session opened (a Dispatch spawn occurred), anchor items to the last
#      such branch.
#   2. Else, ensure a per-session conversation-root branch exists:
#      `--emit-branch` a `sess-<sid-hash>` node, titled from the session's first
#      task, parented under the project/global root (the same _project_root logic
#      conversation-tree-emit.sh uses), then anchor items under it.
#
#   NOTE / known deviation from the ADR-038 D3 sketch: this hook is wired AFTER
#   `conversation-tree-emit.sh --on-stop`, which conclude-and-clears the ledger.
#   In that ordering the ledger is gone by the time this runs, so the else-branch
#   (a self-created `sess-<sid-hash>` conversation-root) is the path that fires in
#   practice. That is also the more correct model: the ledger records branches the
#   session SPAWNED (child Dispatch sessions), not "this session," and attaching
#   unchecked items to an already-concluded spawn branch would be semantically
#   wrong. The ledger-first path is retained for the (rare) case this hook runs
#   before --on-stop. Linking a session's own node back to the parent-created
#   spawn branch needs a session->node correlation map the child cannot derive
#   from its own sid today (ADR-038 D3 open question); that is a future extension.
#
# Idempotency (ADR-038 D4): item_id = sha1(session_id | kind | normalized_text),
# where normalized_text is whitespace-collapsed + lowercased, so re-firing on the
# same content is a per-file no-op (the state facade dedupes by event_id). Only the
# FINAL assistant message of the turn is scanned — Stop fires per turn boundary, so
# each turn's surfacing is caught exactly once.
#
# Invocation modes:
#   (no arg)     Stop hook. Reads $TRANSCRIPT_PATH / stdin, extracts, emits.
#   --self-test  Exercises false-positive / false-negative / normal-extract /
#                idempotency / normalization / multi-line / ledger-anchor /
#                writer-isolation paths against temp state files. Prints
#                `self-test: OK` / `self-test: FAIL`. Exit 0 / 1.
#
# Env overrides (testing): CONV_TREE_STATE_PATH (single explicit emit sink, passed
# through to the emit hook), CONV_TREE_STATE_LIB (state-library module),
# CONV_TREE_LEDGER_DIR (ledger directory).

set -uo pipefail

MODE="${1:-}"

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/conversation-tree-extract-pending.log"
LEDGER_DIR="${CONV_TREE_LEDGER_DIR:-$HOME/.claude/state/conversation-tree-emit}"

# ---- failure isolation -----------------------------------------------------
_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "${MODE:-stop}" "$*" >>"$LOG_FILE" 2>/dev/null || true
}
_die_safe() { _log "isolated error: $*"; exit 0; }
trap '_die_safe "uncaught (line $LINENO)"' ERR

# ---- shared helpers (mirrored from conversation-tree-emit.sh for consistency)
_have() { command -v "$1" >/dev/null 2>&1; }

_sha1() {
  if _have sha1sum; then sha1sum | cut -d' ' -f1
  elif _have shasum; then shasum -a 1 | cut -d' ' -f1
  else cksum | tr -d ' ' ; fi
}

_read_stdin() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]] && [[ ! -t 0 ]]; then input=$(cat 2>/dev/null || echo ""); fi
  printf '%s' "$input"
}

_session_id() {
  local sid="${CLAUDE_SESSION_ID:-}"
  if [[ -z "$sid" ]] && [[ -n "${1:-}" ]]; then
    sid=$(printf '%s' "$1" | jq -r '.session_id // .session.session_id // empty' 2>/dev/null || echo "")
  fi
  [[ -z "$sid" ]] && sid="ppid-${PPID:-$$}"
  printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

# Project/global root node from cwd — byte-identical to conversation-tree-emit.sh
# so a root this hook ensures coincides with the one the spawn hook creates.
_project_root() {
  local cwd="${PWD:-$(pwd 2>/dev/null || echo)}"
  local slug=""
  case "$cwd" in
    */claude-projects/*)
      slug="${cwd#*/claude-projects/}"
      slug="${slug%%/*}"
      ;;
  esac
  if [[ -n "$slug" ]]; then
    local safe
    safe=$(printf '%s' "$slug" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')
    [[ -z "$safe" ]] && safe="project"
    printf 'proj-%s\t%s' "$safe" "$slug"
  else
    printf 'global\tglobal'
  fi
}

# Resolve the state-library module (for --self-test verification only — the
# runtime path delegates all writes to the emit hook, which resolves its own).
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

# Sibling emit hook — the single write path (never reimplement appendEvent).
_emit_hook() {
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/conversation-tree-emit.sh"
}

# ---- the marker parser (node — robust JSONL + regex) -----------------------
# Reads a transcript JSONL path, isolates the FINAL assistant message, parses
# the ADR-038 D1 sections, and prints {"title":<first-task>,"items":[{kind,text}]}.
_extract() {
  local transcript="$1"
  _have node || { printf '{"title":"","items":[]}'; return 0; }
  local js; js=$(mktemp 2>/dev/null || echo "/tmp/cte-extract-$$.js")
  cat >"$js" <<'NODEEOF'
'use strict';
(function () {
  var fs = require('fs');
  var tp = process.argv[2];
  function out(o) { process.stdout.write(JSON.stringify(o)); }
  var txt;
  try { txt = fs.readFileSync(tp, 'utf8'); } catch (e) { out({ title: '', items: [] }); return; }

  function extractText(c) {
    if (c == null) return '';
    if (typeof c === 'string') return c;
    if (Array.isArray(c)) {
      return c.filter(function (b) { return b && b.type === 'text' && typeof b.text === 'string'; })
              .map(function (b) { return b.text; }).join('\n');
    }
    return '';
  }

  var lines = txt.split('\n');
  var lastAssistant = '';
  var firstTask = '';
  for (var i = 0; i < lines.length; i++) {
    var ln = lines[i]; if (!ln.trim()) continue;
    var j; try { j = JSON.parse(ln); } catch (e) { continue; }
    var role = (j.message && j.message.role) || j.role
      || (j.type === 'assistant' ? 'assistant' : (j.type === 'user' ? 'user' : null));
    if (role === 'assistant') {
      var at = extractText(j.message ? j.message.content : j.content);
      if (at && at.trim()) lastAssistant = at;   // last assistant message wins
    }
    if (!firstTask) {
      if (j.type === 'queue-operation' && j.operation === 'enqueue' && j.content) {
        var ql = String(j.content).split('\n').filter(function (x) { return x.trim(); });
        if (ql.length) firstTask = ql[0].trim();
      } else if (role === 'user') {
        var ut = extractText(j.message ? j.message.content : j.content).trim();
        if (ut && ut[0] !== '<') {                // skip system-injected wrappers
          firstTask = (ut.split('\n')[0] || '').trim();
        }
      }
    }
  }

  function classify(line) {
    var s = line.replace(/^\s*>*\s*/, '').trim();
    if (/^(?:#{1,6}\s*)?\*{0,2}\s*questions?\s+for\s+misha\s*\*{0,2}\s*:?\s*$/i.test(s)) return 'question';
    if (/^(?:#{1,6}\s*)?\*{0,2}\s*action\s+items?\s+for\s+misha\s*\*{0,2}\s*:?\s*$/i.test(s)) return 'action';
    if (/^(?:#{1,6}\s*)?\*{0,2}\s*decisions?\s+for\s+misha\s*\*{0,2}\s*:?\s*$/i.test(s)) return 'decision';
    return null;
  }
  function isHR(s) { return /^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/.test(s); }
  var itemRe = /^\s*(?:[-*+]|\d+[.)])\s+(\S.*)$/;

  var alines = lastAssistant.split('\n');
  var items = [];
  var cur = null;     // current section kind
  var curIdx = -1;    // index of the item currently being built (for wrapping)
  for (var k = 0; k < alines.length; k++) {
    var raw = alines[k];
    var kind = classify(raw);
    if (kind) { cur = kind; curIdx = -1; continue; }
    if (!cur) continue;
    if (!raw.trim()) { cur = null; curIdx = -1; continue; }   // blank-line gap
    if (isHR(raw)) { cur = null; curIdx = -1; continue; }     // horizontal rule
    var m = raw.match(itemRe);
    if (m) {
      items.push({ kind: cur, text: m[1].trim() });
      curIdx = items.length - 1;
    } else if (curIdx >= 0) {
      items[curIdx].text += ' ' + raw.trim();                 // wrapped continuation
    } else {
      cur = null; curIdx = -1;                                // non-list content => no items
    }
  }

  items = items.map(function (it) {
    var t = it.text.replace(/\s+/g, ' ').trim();
    if (t.length > 280) t = t.slice(0, 277) + '...';
    return { kind: it.kind, text: t };
  }).filter(function (it) { return it.text.length > 0; });

  var title = (firstTask || '').replace(/\s+/g, ' ').trim().slice(0, 80) || 'Pending items';
  out({ title: title, items: items });
})();
NODEEOF
  local result
  result=$(node "$js" "$transcript" 2>>"$LOG_FILE" || echo '{"title":"","items":[]}')
  rm -f "$js" 2>/dev/null || true
  printf '%s' "$result"
}

# ============================================================================
# Mode: (default) — Stop hook
# ============================================================================
_run_stop() {
  local input; input=$(_read_stdin)

  # transcript path: env first, then stdin JSON.
  local tp="${CLAUDE_TRANSCRIPT_PATH:-}"
  if [[ -z "$tp" ]]; then
    tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
  fi
  [[ -z "$tp" || ! -f "$tp" ]] && { _log "no readable transcript path (tp='${tp:-}')"; exit 0; }

  _have jq   || { _log "jq unavailable"; exit 0; }
  _have node || { _log "node unavailable"; exit 0; }
  local emit; emit=$(_emit_hook)
  [[ -f "$emit" ]] || { _log "sibling emit hook missing at $emit"; exit 0; }

  local extracted; extracted=$(_extract "$tp")
  local n; n=$(printf '%s' "$extracted" | jq '.items | length' 2>/dev/null || echo 0)
  if ! [[ "${n:-0}" =~ ^[0-9]+$ ]]; then n=0; fi
  if [[ "$n" -eq 0 ]]; then _log "no pending-item sections in final assistant message"; exit 0; fi

  local sid; sid=$(_session_id "$input")

  # ---- anchor resolution (ADR-038 D3) ----
  local anchor=""
  local ledger="$LEDGER_DIR/opened-${sid}.jsonl"
  if [[ -s "$ledger" ]]; then
    anchor=$(tail -n1 "$ledger" 2>/dev/null | cut -f1 || echo "")
  fi
  if [[ -z "$anchor" ]]; then
    local rootline; rootline=$(_project_root)
    local root_id="${rootline%%$'\t'*}"
    local root_title="${rootline##*$'\t'}"
    local sess_node; sess_node="sess-$(printf '%s' "$sid" | _sha1 | cut -c1-12)"
    local title; title=$(printf '%s' "$extracted" | jq -r '.title // empty' 2>/dev/null || echo "")
    [[ -z "$title" ]] && title="Pending items"
    # Ensure the project/global root, then the per-session conversation-root.
    # Both --emit-branch calls are idempotent (reducer rejects duplicate node_id).
    jq -cn --arg id "$root_id" --arg t "$root_title" '{node_id:$id,parent_id:null,title:$t}' \
      | "$emit" --emit-branch >/dev/null 2>&1 || true
    jq -cn --arg id "$sess_node" --arg p "$root_id" --arg t "$title" '{node_id:$id,parent_id:$p,title:$t}' \
      | "$emit" --emit-branch >/dev/null 2>&1 || true
    anchor="$sess_node"
  fi

  # ---- emit each extracted item (ADR-038 D2 step 4) ----
  local count=0
  local item kind text norm itemid payload
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    kind=$(printf '%s' "$item" | jq -r '.kind' 2>/dev/null || echo "")
    text=$(printf '%s' "$item" | jq -r '.text' 2>/dev/null || echo "")
    [[ -z "$kind" || -z "$text" ]] && continue
    norm=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
    itemid="it-xp-$(printf '%s|%s|%s' "$sid" "$kind" "$norm" | _sha1 | cut -c1-24)"
    payload=$(jq -cn --arg k "$kind" --arg n "$anchor" --arg i "$itemid" --arg t "$text" \
      '{kind:$k,node_id:$n,item_id:$i,text:$t}')
    printf '%s' "$payload" | "$emit" --emit-item >/dev/null 2>&1 || true
    count=$((count+1))
  done < <(printf '%s' "$extracted" | jq -c '.items[]' 2>/dev/null || true)

  _log "extracted $count item(s) anchor=$anchor session=$sid"
  exit 0
}

# ============================================================================
# Mode: --self-test
# ============================================================================
_self_test() {
  trap - ERR
  local pass=0 fail=0 tmp
  tmp=$(mktemp -d 2>/dev/null || echo "/tmp/cte-xp-st-$$"); mkdir -p "$tmp"
  local LIB; LIB=$(_resolve_state_lib)
  if [[ ! -f "$LIB" ]]; then echo "self-test: cannot locate state library ($LIB)"; echo "self-test: FAIL"; exit 1; fi
  export CONV_TREE_STATE_LIB="$LIB"
  export CONV_TREE_LEDGER_DIR="$tmp/ledger"; mkdir -p "$CONV_TREE_LEDGER_DIR"
  local SELF; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  local EMIT; EMIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/conversation-tree-emit.sh"
  if [[ ! -f "$EMIT" ]]; then echo "self-test: sibling emit hook not found ($EMIT)"; echo "self-test: FAIL"; exit 1; fi

  _ck() { if [[ "$2" == "$3" ]]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (got '$2' want '$3')"; fi; [[ "$2" == "$3" ]] || fail=$((fail+1)); }

  _total_items() { node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var c=0;st.snapshot.nodes.forEach(function(n){c+=(n.items||[]).length});process.stdout.write(String(c))' "$LIB" "$1" 2>/dev/null || echo ERR; }
  _kind_items()  { node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var k=process.argv[3],c=0;st.snapshot.nodes.forEach(function(n){(n.items||[]).forEach(function(it){if(it.kind===k)c++})});process.stdout.write(String(c))' "$LIB" "$1" "$2" 2>/dev/null || echo ERR; }
  _node_items()  { node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.find(function(x){return x.node_id===process.argv[3]});process.stdout.write(String(n?(n.items||[]).length:0))' "$LIB" "$1" "$2" 2>/dev/null || echo 0; }
  _node_item_text() { node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.find(function(x){return x.node_id===process.argv[3]});var all=[];st.snapshot.nodes.forEach(function(x){(x.items||[]).forEach(function(it){all.push(it.text)})});process.stdout.write(all.join("||"))' "$LIB" "$1" "$2" 2>/dev/null || echo ""; }

  # Build a transcript with ONE assistant message (markdown body) + an optional
  # first user task line. Uses jq so embedded newlines are encoded correctly.
  _mk_transcript() {
    local f="$1" md="$2" task="${3:-}"
    : >"$f"
    if [[ -n "$task" ]]; then
      jq -cn --arg t "$task" '{type:"user",message:{role:"user",content:$t}}' >>"$f"
    fi
    jq -cn --arg t "$md" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >>"$f"
  }

  # Run the hook (production-faithful: transcript_path + session_id via stdin JSON).
  _run_hook() {
    local sink="$1" sid="$2" tp="$3"
    printf '{"transcript_path":%s,"session_id":%s}' \
      "$(jq -Rn --arg x "$tp" '$x')" "$(jq -Rn --arg x "$sid" '$x')" \
      | CONV_TREE_STATE_PATH="$sink" bash "$SELF" >/dev/null 2>&1
  }

  # ---- EX1: normal extract — all three markers + items ----
  local md1
  md1=$'Here is my summary.\n\n**Decisions for Misha**\n- Pick approach A or B\n- Approve the budget\n\n**Action items for Misha**\n1. Provision the test org\n2. Share the ntfy topic\n\n**Questions for Misha**\n- Which downstream first?\n'
  local tp1="$tmp/t1.jsonl" sink1="$tmp/s1.json"
  _mk_transcript "$tp1" "$md1" "Close out the conv-tree work"
  _run_hook "$sink1" "sess-ex1" "$tp1"
  _ck "EX1 total items extracted (2 decisions + 2 actions + 1 question = 5)" "$(_total_items "$sink1")" "5"
  _ck "EX1 decisions" "$(_kind_items "$sink1" decision)" "2"
  _ck "EX1 actions"   "$(_kind_items "$sink1" action)" "2"
  _ck "EX1 questions" "$(_kind_items "$sink1" question)" "1"

  # ---- FN1: false-negative guard — a valid heading-style marker must extract ----
  local md2; md2=$'## Questions for Misha\n- Is the schema frozen?\n- Should we ship today?\n'
  local tp2="$tmp/t2.jsonl" sink2="$tmp/s2.json"
  _mk_transcript "$tp2" "$md2"
  _run_hook "$sink2" "sess-fn1" "$tp2"
  _ck "FN1 heading-style marker extracts items" "$(_kind_items "$sink2" question)" "2"

  # ---- FP1: false-positive — bullets but NO marker, plus a mid-sentence mention ----
  local md3; md3=$'I have some questions for Misha to think about later.\n\n- this is a normal bullet\n- another normal bullet\n'
  local tp3="$tmp/t3.jsonl" sink3="$tmp/s3.json"
  _mk_transcript "$tp3" "$md3"
  _run_hook "$sink3" "sess-fp1" "$tp3"
  _ck "FP1 no anchored marker -> zero items" "$(_total_items "$sink3")" "0"

  # ---- FP2: marker header present but followed by prose (no list) -> zero items ----
  local md4; md4=$'**Action items for Misha**\nThere is nothing actionable right now, just FYI.\n'
  local tp4="$tmp/t4.jsonl" sink4="$tmp/s4.json"
  _mk_transcript "$tp4" "$md4"
  _run_hook "$sink4" "sess-fp2" "$tp4"
  _ck "FP2 marker without a list -> zero items" "$(_total_items "$sink4")" "0"

  # ---- ID1: idempotency — running EX1 twice yields the same item count ----
  _run_hook "$sink1" "sess-ex1" "$tp1"
  _ck "ID1 re-run is a per-file no-op" "$(_total_items "$sink1")" "5"

  # ---- FP3: normalization — same item, different case/whitespace, same id ----
  local md5a; md5a=$'**Questions for Misha**\n- Which   Downstream  First?\n'
  local md5b; md5b=$'**Questions for Misha**\n- which downstream first?\n'
  local tp5a="$tmp/t5a.jsonl" tp5b="$tmp/t5b.jsonl" sink5="$tmp/s5.json"
  _mk_transcript "$tp5a" "$md5a"; _mk_transcript "$tp5b" "$md5b"
  _run_hook "$sink5" "sess-fp3" "$tp5a"
  _run_hook "$sink5" "sess-fp3" "$tp5b"
  _ck "FP3 case/whitespace-variant item dedupes to 1" "$(_total_items "$sink5")" "1"

  # ---- ML1: multi-line wrapped item captured whole ----
  local md6; md6=$'**Decisions for Misha**\n- Decide whether to migrate the\n  auth middleware before the freeze\n'
  local tp6="$tmp/t6.jsonl" sink6="$tmp/s6.json"
  _mk_transcript "$tp6" "$md6"
  _run_hook "$sink6" "sess-ml1" "$tp6"
  _ck "ML1 wrapped item -> exactly 1 item" "$(_total_items "$sink6")" "1"
  if [[ "$(_node_item_text "$sink6" any)" == *"auth middleware before the freeze"* ]]; then
    echo "PASS: ML1 wrapped continuation captured whole"; pass=$((pass+1))
  else echo "FAIL: ML1 continuation not captured (got '$(_node_item_text "$sink6" any)')"; fail=$((fail+1)); fi

  # ---- LG1: ledger-anchor path — items attach to the ledger branch ----
  local sink7="$tmp/s7.json"
  printf '{"node_id":"ledgerbranch","parent_id":null,"title":"Ledger Branch"}' \
    | CONV_TREE_STATE_PATH="$sink7" bash "$EMIT" --emit-branch >/dev/null 2>&1
  printf 'ledgerbranch\tLedger Branch\t2026-05-26T00:00:00Z\n' > "$CONV_TREE_LEDGER_DIR/opened-sess-lg1.jsonl"
  local md7; md7=$'**Questions for Misha**\n- anchored to the ledger branch?\n'
  local tp7="$tmp/t7.jsonl"; _mk_transcript "$tp7" "$md7"
  _run_hook "$sink7" "sess-lg1" "$tp7"
  _ck "LG1 items anchor to the ledger branch" "$(_node_items "$sink7" ledgerbranch)" "1"
  rm -f "$CONV_TREE_LEDGER_DIR/opened-sess-lg1.jsonl" 2>/dev/null || true

  # ---- WR1: writer isolation — missing transcript -> exit 0, no crash ----
  local rc
  printf '{"transcript_path":"%s","session_id":"sess-wr1"}' "$tmp/does-not-exist.jsonl" \
    | CONV_TREE_STATE_PATH="$tmp/s8.json" bash "$SELF" >/dev/null 2>&1
  rc=$?
  _ck "WR1 missing transcript -> exit 0" "$rc" "0"

  rm -rf "$tmp" 2>/dev/null || true
  echo "self-test: $pass passed, $fail failed"
  if [[ $fail -eq 0 ]]; then echo "self-test: OK"; exit 0; else echo "self-test: FAIL"; exit 1; fi
}

# ============================================================================
# Dispatch
# ============================================================================
case "$MODE" in
  --self-test) _self_test ;;
  *)           _run_stop ;;
esac
