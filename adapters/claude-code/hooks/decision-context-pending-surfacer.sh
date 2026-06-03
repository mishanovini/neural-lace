#!/bin/bash
# decision-context-pending-surfacer.sh
#
# SessionStart hook that scans the attestation-verified conversation-tree
# state for unresolved decision-context items (items emitted by the
# decision-context-gate as `decision`/`question`/`action` carrying
# `details.surfaced_by == "decision-context-gate"`) and surfaces each as
# a system-reminder block. Also drains Tier-2 follow-up markers written
# at `~/.claude/state/decision-context-followup-*.txt`.
#
# Classification: WRITER hook (system-reminder surface). NEVER blocks
# session start. Every runtime path exits 0. Failures are isolated and
# logged to `~/.claude/logs/decision-context-pending-surfacer.log`.
#
# Sibling patterns:
#   - discovery-surfacer.sh — SessionStart silent-when-empty surface scan
#   - conversation-tree-emit.sh — state.js facade reading via node -e + the
#     _resolve_state_lib / _resolve_gui_state_path resolvers
#
# State trust: per ADR-032 §8 r2.1, snapshot trust comes ONLY through the
# state-library `verifySnapshotAttested` primitive — never via raw JSON
# read of tree-state.json. We `require(state.js)` and call `readState`.
#
# Per-session "seen" tracking: marker file at
#   `~/.claude/state/decision-context/seen-<session_id>.json`
# maps item_id -> latest event_id seen. We only re-surface an item when
# its current revision (latest matching event_id in events[]) differs
# from the seen revision. Missing seen-file or corrupted JSON is treated
# as empty (safe rebuild).
#
# Follow-up markers: Task 4's gate writes `decision-context-followup-*.txt`
# files into `~/.claude/state/` on Tier-2 detection. Fresh markers (<24h)
# emit ONE reminder "previous-turn weak signal — consider whether to
# fence", then the marker is deleted.
#
# Self-test: --self-test exercises 9 scenarios.

set -uo pipefail

MODE="${1:-}"

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/decision-context-pending-surfacer.log"
SEEN_DIR="${DCPS_SEEN_DIR:-$HOME/.claude/state/decision-context}"
# Glob is overridable via DCPS_FOLLOWUP_GLOB (test scaffolding); production
# default points at the canonical ~/.claude/state location.
FOLLOWUP_GLOB="${DCPS_FOLLOWUP_GLOB:-$HOME/.claude/state/decision-context-followup-*.txt}"
FOLLOWUP_MAX_AGE_HOURS="${DCPS_FOLLOWUP_MAX_AGE_HOURS:-24}"

# Tree base URL for the "Tree view" link in reminders.
TREE_VIEW_BASE="${DCPS_TREE_VIEW_BASE:-http://127.0.0.1:7733/#node=}"

# ---- failure isolation -----------------------------------------------------
_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "${MODE:-?}" "$*" >>"$LOG_FILE" 2>/dev/null || true
}
_die_safe() { _log "isolated error: $*"; exit 0; }
trap '_die_safe "uncaught (line $LINENO)"' ERR

_have() { command -v "$1" >/dev/null 2>&1; }

# ---- conv-tree path resolvers (copied from conversation-tree-emit.sh) ------
_fallback_conv_tree_path() {
  local leaf="$1"
  local base="${CONV_TREE_MAIN_CHECKOUT:-$HOME/claude-projects/neural-lace}"
  # UI module lives at neural-lace/workstreams-ui/ (renamed 2026-06).
  local d cand
  for d in workstreams-ui; do
    for cand in "$base/neural-lace/$d/$leaf" "$base/$d/$leaf"; do
      if [[ -e "$cand" ]]; then printf '%s' "$cand"; return 0; fi
    done
  done
  printf '%s' "$base/neural-lace/workstreams-ui/$leaf"
}

_resolve_state_lib() {
  if [[ -n "${CONV_TREE_STATE_LIB:-}" ]]; then printf '%s' "$CONV_TREE_STATE_LIB"; return 0; fi
  local root="" d cand
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    for d in workstreams-ui; do
      for cand in "$root/neural-lace/$d/state/state.js" "$root/$d/state/state.js"; do
        if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
      done
    done
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
  local mr d
  if mr=$(_main_repo_root) && [[ -n "$mr" ]]; then
    for d in workstreams-ui; do
      if [[ -f "$mr/neural-lace/$d/state/state.js" ]]; then printf '%s' "$mr/neural-lace/$d/state/tree-state.json"; return 0; fi
      if [[ -f "$mr/$d/state/state.js" ]]; then printf '%s' "$mr/$d/state/tree-state.json"; return 0; fi
    done
  fi
  _fallback_conv_tree_path "state/tree-state.json"
}

# ---- session id ------------------------------------------------------------
_read_stdin() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]] && [[ ! -t 0 ]]; then input=$(cat 2>/dev/null || echo ""); fi
  printf '%s' "$input"
}

_session_id_from_input() {
  local input="$1"
  local sid=""
  if [[ -n "$input" ]] && _have jq; then
    sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || echo "")
  fi
  [[ -z "$sid" ]] && sid="${CLAUDE_SESSION_ID:-}"
  [[ -z "$sid" ]] && sid="ppid-${PPID:-$$}"
  printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

# ---- core: list pending items from tree state ------------------------------
# Uses node -e to read state via the facade (verifySnapshotAttested under the
# hood), then emits one tab-separated record per unresolved decision-context
# item:
#   <item_id>\t<node_id>\t<kind>\t<text>\t<latest_event_id>\t<node_state>\t<details_json>
# Empty stdout = no items.
_list_pending_items() {
  local lib="$1" sink="$2"
  _have node || { _log "node unavailable"; return 0; }
  [[ -f "$sink" ]] || return 0
  node -e '
    "use strict";
    var libPath = process.argv[1], sink = process.argv[2];
    var s;
    try { s = require(libPath); } catch (e) { process.stderr.write("LIBERR:" + (e&&e.message||e) + "\n"); process.exit(0); }
    var st;
    try { st = s.readState({ statePath: sink }); }
    catch (e) { process.stderr.write("READERR:" + (e&&e.message||e) + "\n"); process.exit(0); }
    if (!st || !st.snapshot || !Array.isArray(st.snapshot.nodes)) process.exit(0);
    // Per ADR-032 §8 r2.1, snapshot trust is verified via the facade primitive.
    // The conv-tree gates (state-gate, stop-gate) REFUSE on verified===false.
    // The surfacer is an informational hook, NOT a gate; production state today
    // does not emit snapshot-committed attestations (reason: no-attestation is
    // the normal v1 case). We therefore only refuse on explicit torn/tampered
    // reasons; no-attestation passes through so the surfacer stays useful
    // pre-attestation-rollout. Once attestation events land in production
    // state, this surfacer auto-upgrades to the stricter trust posture.
    try {
      var v = s.verifySnapshotAttested(st);
      if (v && v.verified === false) {
        var reason = String((v && v.reason) || "");
        if (reason === "torn" || reason === "tampered" || reason.indexOf("hash-mismatch") >= 0) {
          process.exit(0);
        }
        // no-attestation / unknown -> proceed (informational hook posture)
      }
    } catch (e) { /* primitive may throw on torn -> refuse silently */ process.exit(0); }

    // Index latest event_id per item_id from events[] (item-affecting events).
    // Tracks ALL events with an item_id field so any update bumps the revision.
    var latest = {};   // item_id -> latest event_id
    var events = Array.isArray(st.events) ? st.events : [];
    for (var i = 0; i < events.length; i++) {
      var ev = events[i];
      if (!ev || !ev.item_id) continue;
      latest[ev.item_id] = ev.event_id || ("idx-" + i);
    }

    var out = [];
    var nodes = st.snapshot.nodes;
    for (var n = 0; n < nodes.length; n++) {
      var node = nodes[n];
      if (!node || node.state === "archived") continue;
      var items = Array.isArray(node.items) ? node.items : [];
      for (var k = 0; k < items.length; k++) {
        var it = items[k];
        if (!it || it.checked) continue;
        // Decision-context filter: surfaced_by stamp inside details.
        var details = it.details && typeof it.details === "object" ? it.details : null;
        var surfaced_by = details && typeof details.surfaced_by === "string" ? details.surfaced_by : "";
        if (surfaced_by !== "decision-context-gate") continue;
        var rev = latest[it.item_id] || "no-event";
        var nodeState = node.state || "open";
        var detailsJson = details ? JSON.stringify(details) : "{}";
        // Sanitize tabs/newlines in text so the tab-separated transport is safe.
        var text = String(it.text || "").replace(/\t/g, " ").replace(/\n/g, " ");
        out.push([it.item_id, node.node_id, it.kind, text, rev, nodeState, detailsJson].join("\t"));
      }
    }
    process.stdout.write(out.join("\n"));
    process.exit(0);
  ' "$lib" "$sink" 2>>"$LOG_FILE"
}

# ---- seen-file management --------------------------------------------------
# Read seen-file and emit lines: <item_id>\t<event_id>
# Empty if file missing or corrupted (corruption == safe rebuild).
_read_seen_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  _have node || return 0
  node -e '
    "use strict";
    var fs = require("fs");
    try {
      var obj = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      if (!obj || typeof obj !== "object") process.exit(0);
      var keys = Object.keys(obj);
      for (var i = 0; i < keys.length; i++) {
        var k = keys[i], v = obj[k];
        if (typeof v === "string") process.stdout.write(k + "\t" + v + "\n");
      }
    } catch (e) { /* corrupted -> treat as empty (safe rebuild) */ }
  ' "$path" 2>>"$LOG_FILE"
}

# Write seen-file from a tsv of <item_id>\t<event_id> lines on stdin.
_write_seen_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  _have node || return 0
  node -e '
    "use strict";
    var fs = require("fs");
    var lines = require("fs").readFileSync(0, "utf8").split("\n");
    var obj = {};
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (!line) continue;
      var idx = line.indexOf("\t");
      if (idx < 0) continue;
      obj[line.slice(0, idx)] = line.slice(idx + 1);
    }
    fs.writeFileSync(process.argv[1], JSON.stringify(obj, null, 2) + "\n");
  ' "$path" 2>>"$LOG_FILE"
}

# ---- reminder formatting ---------------------------------------------------
# Emit one reminder block for an item. Args:
#   $1=item_id $2=node_id $3=kind $4=text $5=node_state $6=details_json
_emit_reminder() {
  local item_id="$1" node_id="$2" kind="$3" text="$4" node_state="$5" details_json="$6"
  local reply_with=""
  if _have node; then
    reply_with=$(printf '%s' "$details_json" | node -e '
      "use strict";
      try {
        var d = JSON.parse(require("fs").readFileSync(0, "utf8"));
        if (d && typeof d.reply_with === "string") process.stdout.write(d.reply_with);
      } catch (e) {}
    ' 2>/dev/null || echo "")
  fi
  echo "[decision-context pending] ${kind}: ${text} (id=${item_id}, node=${node_id})"
  echo "  Status: open (node.state=${node_state})"
  if [[ -n "$reply_with" ]]; then
    echo "  Reply with: \"${reply_with}\""
  fi
  echo "  Tree view: ${TREE_VIEW_BASE}${node_id}"
  echo ""
}

# ---- follow-up marker draining ---------------------------------------------
_drain_followup_markers() {
  local now_s; now_s=$(date -u +%s 2>/dev/null || echo 0)
  local max_age_s=$(( FOLLOWUP_MAX_AGE_HOURS * 3600 ))
  local emitted_header=0
  local marker mtime age
  # NB: shopt nullglob would be cleaner but isn't universally enabled — guard the glob.
  for marker in $FOLLOWUP_GLOB; do
    [[ -f "$marker" ]] || continue
    mtime=$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null || echo 0)
    age=$(( now_s - mtime ))
    if (( age > max_age_s )); then
      rm -f "$marker" 2>/dev/null || true
      _log "stale follow-up marker dropped: $(basename "$marker") (age ${age}s)"
      continue
    fi
    if [[ $emitted_header -eq 0 ]]; then
      echo "[decision-context follow-up] previous-turn weak signal detected — consider whether to fence:"
      emitted_header=1
    fi
    echo "  • marker: $(basename "$marker") (age $(( age / 60 ))min)"
    # Best-effort: include first non-empty line of the marker as context.
    local first_line
    first_line=$(grep -m1 -v '^[[:space:]]*$' "$marker" 2>/dev/null | head -c 200 || echo "")
    [[ -n "$first_line" ]] && echo "    context: ${first_line}"
    rm -f "$marker" 2>/dev/null || true
  done
  [[ $emitted_header -eq 1 ]] && echo ""
}

# ---- main run --------------------------------------------------------------
# Args (for testability):
#   $1 = optional override of seen-dir (defaults to SEEN_DIR)
_run_surface() {
  local seen_dir_override="${1:-}"
  local seen_dir="${seen_dir_override:-$SEEN_DIR}"
  mkdir -p "$seen_dir" 2>/dev/null || true

  local input; input=$(_read_stdin)
  local sid; sid=$(_session_id_from_input "$input")
  local seen_file="$seen_dir/seen-${sid}.json"

  local lib; lib=$(_resolve_state_lib)
  local sink; sink=$(_resolve_gui_state_path)

  # If neither lib nor sink resolve to existing files, silent no-op.
  if [[ ! -f "$lib" ]] || [[ ! -f "$sink" ]]; then
    _log "no resolvable state lib ($lib) or sink ($sink) — silent no-op"
    # Still drain follow-up markers (orthogonal to tree state).
    _drain_followup_markers
    exit 0
  fi

  # Pull unresolved decision-context items from the verified snapshot.
  local items_tsv; items_tsv=$(_list_pending_items "$lib" "$sink")

  # Read seen-file into an associative array.
  declare -A SEEN
  while IFS=$'\t' read -r sid_key sid_val; do
    [[ -z "$sid_key" ]] && continue
    SEEN["$sid_key"]="$sid_val"
  done < <(_read_seen_file "$seen_file")

  # Collect reminders to emit; track new seen-state to write at the end.
  local emitted_header=0
  local new_seen_tsv=""
  local item_id node_id kind text rev node_state details_json
  if [[ -n "$items_tsv" ]]; then
    while IFS=$'\t' read -r item_id node_id kind text rev node_state details_json; do
      [[ -z "$item_id" ]] && continue
      local prior="${SEEN[$item_id]:-}"
      new_seen_tsv+="${item_id}	${rev}"$'\n'
      if [[ "$prior" == "$rev" ]]; then
        # Already seen at this revision — silent.
        continue
      fi
      if [[ $emitted_header -eq 0 ]]; then
        echo ""
        emitted_header=1
      fi
      _emit_reminder "$item_id" "$node_id" "$kind" "$text" "$node_state" "$details_json"
    done <<< "$items_tsv"
  fi

  # Drain follow-up markers (orthogonal to items).
  _drain_followup_markers

  # Persist updated seen-file ONLY when there were items in the snapshot. If
  # the snapshot had zero pending items we leave the existing seen-file alone
  # so a transient empty read doesn't clobber prior state.
  if [[ -n "$new_seen_tsv" ]]; then
    printf '%s' "$new_seen_tsv" | _write_seen_file "$seen_file"
  fi
  exit 0
}

# ============================================================================
# Self-test
# ============================================================================
_self_test() {
  trap - ERR
  local pass=0 fail=0 tmp
  tmp=$(mktemp -d 2>/dev/null || echo "/tmp/dcps-st-$$"); mkdir -p "$tmp"
  local LIB; LIB=$(_resolve_state_lib)
  if [[ ! -f "$LIB" ]]; then
    echo "self-test: cannot locate state library ($LIB)"
    echo "self-test: FAIL"
    exit 1
  fi
  if ! _have node; then
    echo "self-test: node unavailable — cannot run scenarios"
    echo "self-test: FAIL"
    exit 1
  fi
  local SELF; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  _ck() { if [[ "$2" == "$3" ]]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (got '$2' want '$3')"; fail=$((fail+1)); fi; }
  _ck_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
      echo "PASS: $label"
      pass=$((pass+1))
    else
      echo "FAIL: $label (haystack did not contain '$needle')"
      fail=$((fail+1))
    fi
  }

  # Helper: seed a fresh state file with given events using the facade.
  # $1=path, $2=newline-separated JSON event objects
  _seed_state() {
    local sink="$1"
    rm -f "$sink"
    mkdir -p "$(dirname "$sink")" 2>/dev/null || true
    node -e '
      "use strict";
      var libPath = process.argv[1], sink = process.argv[2];
      var fs = require("fs");
      var s = require(libPath);
      var lines = fs.readFileSync(0, "utf8").split("\n");
      for (var i = 0; i < lines.length; i++) {
        var L = lines[i].trim();
        if (!L) continue;
        try { s.appendEvent(JSON.parse(L), { statePath: sink }); }
        catch (e) { process.stderr.write("seed-err: " + e.message + "\n"); }
      }
    ' "$LIB" "$sink"
  }

  # Common envelopes -- decision item details carrying surfaced_by stamp.
  local DC_DETAILS='{"surfaced_by":"decision-context-gate","reply_with":"yes/no"}'

  # ---- ST1: no state file -> silent no-op exit 0
  local seen1="$tmp/st1-seen"
  local out rc
  out=$(CONV_TREE_STATE_PATH="$tmp/no-such-file.json" CLAUDE_SESSION_ID="st1" \
        bash "$SELF" <<<'{"session_id":"st1","source":"startup"}' 2>/dev/null || echo "")
  rc=$?
  if [[ $rc -eq 0 && -z "$out" ]]; then
    echo "PASS: ST1 no-state-file -> silent exit 0"
    pass=$((pass+1))
  else
    echo "FAIL: ST1 no-state-file (rc=$rc, out=[$out])"
    fail=$((fail+1))
  fi

  # ---- ST2: state file with 0 unresolved items + no markers -> silent no-op
  local sink2="$tmp/st2.json" seen2="$tmp/st2-seen"
  _seed_state "$sink2" <<'EOF'
{"type":"branch-opened","node_id":"root","parent_id":null,"title":"Root"}
EOF
  out=$(DCPS_FOLLOWUP_GLOB="$tmp/none-*.txt" CONV_TREE_STATE_PATH="$sink2" CLAUDE_SESSION_ID="st2" \
        bash "$SELF" "$seen2" <<<'{"session_id":"st2"}' 2>/dev/null || echo "")
  rc=$?
  if [[ $rc -eq 0 && -z "$out" ]]; then
    echo "PASS: ST2 zero-pending + no-markers -> silent"
    pass=$((pass+1))
  else
    echo "FAIL: ST2 (rc=$rc, out=[$out])"
    fail=$((fail+1))
  fi

  # ---- ST3: 1 unresolved decision item + no seen-file -> reminder emitted, seen-file written
  local sink3="$tmp/st3.json" seen3_dir="$tmp/st3-seen"
  _seed_state "$sink3" <<EOF
{"type":"branch-opened","node_id":"root","parent_id":null,"title":"Root"}
{"type":"decision-raised","node_id":"root","item_id":"itm-1","text":"Pick option A or B"}
{"type":"item-details-set","node_id":"root","item_id":"itm-1","details":$DC_DETAILS}
EOF
  out=$(CONV_TREE_STATE_PATH="$sink3" CLAUDE_SESSION_ID="st3" \
        bash "$SELF" "$seen3_dir" <<<'{"session_id":"st3"}' 2>/dev/null || echo "")
  _ck_contains "ST3 reminder mentions item id" "$out" "id=itm-1"
  _ck_contains "ST3 reminder names item text" "$out" "Pick option A or B"
  _ck_contains "ST3 reminder includes Reply-with" "$out" "yes/no"
  if [[ -f "$seen3_dir/seen-st3.json" ]]; then
    echo "PASS: ST3 seen-file written"
    pass=$((pass+1))
  else
    echo "FAIL: ST3 seen-file NOT written ($seen3_dir/seen-st3.json)"
    fail=$((fail+1))
  fi

  # ---- ST4: same state, second invocation, seen-file unchanged -> silent
  out=$(CONV_TREE_STATE_PATH="$sink3" CLAUDE_SESSION_ID="st3" \
        bash "$SELF" "$seen3_dir" <<<'{"session_id":"st3"}' 2>/dev/null || echo "")
  if [[ -z "$out" ]]; then
    echo "PASS: ST4 re-invocation with unchanged rev -> silent"
    pass=$((pass+1))
  else
    echo "FAIL: ST4 re-invocation NOT silent (out=[$out])"
    fail=$((fail+1))
  fi

  # ---- ST5: same state but receives item-details-set update -> reminder re-emitted
  node -e '
    var s = require(process.argv[1]);
    s.appendEvent({type:"item-details-set", node_id:"root", item_id:"itm-1",
                   details:{surfaced_by:"decision-context-gate", reply_with:"updated"}},
                  { statePath: process.argv[2] });
  ' "$LIB" "$sink3" 2>/dev/null
  out=$(CONV_TREE_STATE_PATH="$sink3" CLAUDE_SESSION_ID="st3" \
        bash "$SELF" "$seen3_dir" <<<'{"session_id":"st3"}' 2>/dev/null || echo "")
  _ck_contains "ST5 reminder re-emitted after rev change" "$out" "id=itm-1"

  # ---- ST6: Tier-2 follow-up marker present -> reminder emitted, marker deleted
  local marker_dir="$tmp/markers-st6"
  mkdir -p "$marker_dir"
  local marker="$marker_dir/decision-context-followup-fixture.txt"
  echo "fixture: ambiguous signal in last turn" > "$marker"
  out=$(CONV_TREE_STATE_PATH="$tmp/no-such-file.json" CLAUDE_SESSION_ID="st6" \
        DCPS_FOLLOWUP_GLOB="$marker_dir/decision-context-followup-*.txt" \
        bash "$SELF" "$tmp/st6-seen" <<<'{"session_id":"st6"}' 2>/dev/null || echo "")
  _ck_contains "ST6 follow-up reminder emitted" "$out" "previous-turn weak signal"
  if [[ -f "$marker" ]]; then
    echo "FAIL: ST6 marker NOT deleted"
    fail=$((fail+1))
  else
    echo "PASS: ST6 marker deleted after surfacing"
    pass=$((pass+1))
  fi

  # ---- ST7: archived node -> item NOT surfaced
  local sink7="$tmp/st7.json" seen7_dir="$tmp/st7-seen"
  _seed_state "$sink7" <<EOF
{"type":"branch-opened","node_id":"root","parent_id":null,"title":"Root"}
{"type":"decision-raised","node_id":"root","item_id":"itm-1","text":"Should not surface"}
{"type":"item-details-set","node_id":"root","item_id":"itm-1","details":$DC_DETAILS}
{"type":"archived","node_id":"root"}
EOF
  out=$(CONV_TREE_STATE_PATH="$sink7" CLAUDE_SESSION_ID="st7" \
        bash "$SELF" "$seen7_dir" <<<'{"session_id":"st7"}' 2>/dev/null || echo "")
  if [[ -z "$out" ]]; then
    echo "PASS: ST7 archived node items not surfaced"
    pass=$((pass+1))
  else
    echo "FAIL: ST7 archived-node leak (out=[$out])"
    fail=$((fail+1))
  fi

  # ---- ST8: multiple unresolved items in one snapshot -> multiple reminders
  local sink8="$tmp/st8.json" seen8_dir="$tmp/st8-seen"
  _seed_state "$sink8" <<EOF
{"type":"branch-opened","node_id":"root","parent_id":null,"title":"Root"}
{"type":"decision-raised","node_id":"root","item_id":"itm-a","text":"Decision A"}
{"type":"item-details-set","node_id":"root","item_id":"itm-a","details":$DC_DETAILS}
{"type":"question-raised","node_id":"root","item_id":"itm-b","text":"Question B"}
{"type":"item-details-set","node_id":"root","item_id":"itm-b","details":$DC_DETAILS}
{"type":"action-added","node_id":"root","item_id":"itm-c","text":"Action C"}
{"type":"item-details-set","node_id":"root","item_id":"itm-c","details":$DC_DETAILS}
EOF
  out=$(CONV_TREE_STATE_PATH="$sink8" CLAUDE_SESSION_ID="st8" \
        bash "$SELF" "$seen8_dir" <<<'{"session_id":"st8"}' 2>/dev/null || echo "")
  _ck_contains "ST8 emits itm-a" "$out" "id=itm-a"
  _ck_contains "ST8 emits itm-b" "$out" "id=itm-b"
  _ck_contains "ST8 emits itm-c" "$out" "id=itm-c"

  # ---- ST9: facade-down (broken CONV_TREE_STATE_LIB) -> silent exit 0
  local sink9="$tmp/st9.json" seen9_dir="$tmp/st9-seen"
  # Seed via the real lib first so a sink exists.
  _seed_state "$sink9" <<EOF
{"type":"branch-opened","node_id":"root","parent_id":null,"title":"Root"}
{"type":"decision-raised","node_id":"root","item_id":"itm-1","text":"Pick something"}
{"type":"item-details-set","node_id":"root","item_id":"itm-1","details":$DC_DETAILS}
EOF
  out=$(CONV_TREE_STATE_LIB="$tmp/does-not-exist.js" CONV_TREE_STATE_PATH="$sink9" CLAUDE_SESSION_ID="st9" \
        bash "$SELF" "$seen9_dir" <<<'{"session_id":"st9"}' 2>/dev/null || echo "")
  rc=$?
  if [[ $rc -eq 0 && -z "$out" ]]; then
    echo "PASS: ST9 facade-down -> silent exit 0"
    pass=$((pass+1))
  else
    echo "FAIL: ST9 facade-down (rc=$rc, out=[$out])"
    fail=$((fail+1))
  fi

  echo ""
  echo "self-test: ${pass} passed, ${fail} failed"
  if (( fail == 0 )); then
    echo "self-test: OK ${pass}/${pass}"
    exit 0
  else
    echo "self-test: FAIL"
    exit 1
  fi
}

# ============================================================================
# Entry point
# ============================================================================
if [[ "$MODE" == "--self-test" ]]; then
  _self_test
fi

# Production entry: arg $1 (when present and not --self-test) is treated as a
# seen-dir override (used by the self-test harness invoking the script as a
# subprocess; production invocations pass no arguments and use the default
# $SEEN_DIR / DCPS_SEEN_DIR resolution).
_run_surface "$MODE"
exit 0
