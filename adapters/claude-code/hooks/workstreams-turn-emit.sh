#!/bin/bash
# workstreams-turn-emit.sh — DETERMINISTIC every-turn WRITER for the
# Workstreams UI file-mediated state contract (ADR-031 r7 / ADR-032).
#
# Originating context: docs/discoveries/2026-06-08-deterministic-workstreams-turn-emit.md.
# Misha's directive: "how do we enforce this DETERMINISTICALLY?" The fence-emit
# Pattern (conv-tree-orchestrator-emit.md Layer D) relied on the orchestrator
# AUTHORING `::: decision` fences. That discipline is proven unreliable — the
# orchestrator wrote plain-prose `PAUSING:` markers and the decision-context-gate
# Tier-1 trigger did not catch them, so ZERO decision cards were emitted for the
# real items. This hook removes the dependency on the agent's behavior entirely.
#
# # What it does (Stop hook, runs EVERY turn)
#   1. Reads the FINAL assistant message from $TRANSCRIPT_PATH (agent-uneditable
#      JSONL — the Gen-6 narrative-integrity property; the agent cannot dodge it).
#   2. Deterministically extracts from that message:
#        - the session-end marker: DONE: / PAUSING: / BLOCKED: + its summary;
#        - decision-soliciting items (PAUSING-with-options, "Decisions for Misha",
#          enumerated A)/B)/1./2. choices, "pick one" / "your call");
#        - questions ("Questions for Misha", "?"-terminated solicitations);
#        - "waiting on you" / action items ("Action items for Misha", "waiting on you");
#        - in-flight statements ("in flight", "in progress", "still building");
#        - shipped / merged lines ("shipped", "merged to master", "DONE: <x>").
#   3. Emits them to the conv-tree state as cards via the SOLE-NORMATIVE state.js
#      facade (ADR-032 §8 — appendEvent + attestation; NEVER a parallel JSON
#      writer, NEVER direct HTTP):
#        - one per-turn root branch node `turn-<sid>-<turn_index>` parented under
#          the project/global root (reuses _project_root);
#        - decision/question/waiting items as decision-raised / question-raised /
#          action-added items ON that node (FR-2 — items live on a node);
#        - the marker summary + in-flight + shipped lines as `annotated` notes.
#   4. IDEMPOTENT by (session_id, turn_index, content-hash): every event carries a
#      deterministic event_id derived from those three + the item text, so a
#      Stop re-fire on the same message is a per-file no-op (the facade dedupes
#      on event_id). A NEW turn (different turn_index/content-hash) produces fresh
#      cards; it never duplicates a prior turn's cards.
#
# # Classification
#   WRITER hook, NOT a gate. It NEVER blocks Stop. Every runtime path exits 0.
#   Emission failures are isolated and logged to
#   ~/.claude/logs/workstreams-turn-emit.log (gate-respect.md: writer hooks do
#   not block anything). The hard-block backstop for prose-decisions that slip
#   through lives in decision-context-gate.sh (Piece 3), NOT here.
#
# # Sinks (dual-write, idempotent on a deterministic event_id, per-file dedupe)
#   1. The GUI STATE_FILE the running server watches (stateLib.STATE_FILE =
#      neural-lace/workstreams-ui/state/tree-state.json in the MAIN checkout) —
#      the binding sink that makes the operator's GUI auto-populate. The path is
#      resolved IDENTICALLY to workstreams-emit.sh / decision-context-gate.sh so
#      the writer, the conv-tree gates and the GUI server all agree (no mismatch).
#   2. The ADR-032 §5-resolved gate path (worktree-aware) — best-effort, only
#      when it differs from sink 1.
#   CONV_TREE_STATE_PATH overrides BOTH with a single explicit sink (self-test).
#   CONV_TREE_STATE_LIB overrides the state-library module path.
#
# # Escape hatch
#   WORKSTREAMS_TURN_EMIT_DISABLE=1 → exit 0 silently (harness-dev sessions
#   editing this hook or its self-test, so it does not self-emit during testing).
#
# # Self-test
#   bash workstreams-turn-emit.sh --self-test  →  PASS/FAIL summary, exit 0/1.

set -uo pipefail

MODE="${1:-}"

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/workstreams-turn-emit.log"

# Workstreams consolidation (Phase A, 2026-06-08): SHARED canonical-state-path
# resolver — collapses the GUI sink and §5 gate sink onto the one
# operator-configured canonical file (~/.claude/workstreams-state-path.txt), so
# this writer, the sibling hooks, and the GUI all read/write the SAME file.
# Sourced best-effort; legacy resolvers below still work if the lib is absent.
# shellcheck disable=SC1091
{ source "$(dirname "${BASH_SOURCE[0]}")/lib/workstreams-state-resolver.sh" 2>/dev/null; } || true

# ---- failure isolation -----------------------------------------------------
# Any unexpected error in a runtime path logs and exits 0. The orchestrator's
# Stop must never be impacted by a writer-hook malfunction.
_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "${MODE:-turn}" "$*" \
    >>"$LOG_FILE" 2>/dev/null || true
}
_die_safe() { _log "isolated error: $*"; exit 0; }
# Only arm the trap for the runtime path; the self-test disarms it.
if [[ "$MODE" != "--self-test" ]]; then
  trap '_die_safe "uncaught (line $LINENO)"' ERR
fi

# ---- shared helpers --------------------------------------------------------

_have() { command -v "$1" >/dev/null 2>&1; }

# sha1 of stdin -> hex. git-bash provides sha1sum; shasum/cksum fallbacks keep
# the hook functional on a stripped environment — determinism per input is all
# the idempotency contract needs.
_sha1() {
  if _have sha1sum; then sha1sum | cut -d' ' -f1
  elif _have shasum; then shasum -a 1 | cut -d' ' -f1
  else cksum | tr -d ' '; fi
}

# Config-driven last-resort checkout root. Only reached when the git-based
# resolvers fail (cwd outside any repo). Overridable via CONV_TREE_MAIN_CHECKOUT
# (per-machine config — keeps machine-specific absolute paths out of the kit).
_fallback_conv_tree_path() {
  local leaf="$1"
  local base="${CONV_TREE_MAIN_CHECKOUT:-$HOME/claude-projects/neural-lace}"
  local d cand
  for d in workstreams-ui; do
    for cand in "$base/neural-lace/$d/$leaf" "$base/$d/$leaf"; do
      if [[ -e "$cand" ]]; then printf '%s' "$cand"; return 0; fi
    done
  done
  printf '%s' "$base/neural-lace/workstreams-ui/$leaf"
}

# Resolve the state-library entry module (state.js). Mirrors
# workstreams-emit.sh / decision-context-gate.sh resolution exactly.
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

# Parent of the repo's git-common-dir = the MAIN checkout (worktree-aware). A
# worktree session resolves to the main checkout so it writes the file the
# operator's single GUI server is actually watching.
_main_repo_root() {
  local gcd
  gcd=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  [[ -z "$gcd" ]] && return 1
  local d
  d=$(cd "$(dirname "$gcd")" 2>/dev/null && pwd) || return 1
  printf '%s' "$d"
}

# GUI sink: the module tree-state.json the shipped GUI server watches
# (stateLib.STATE_FILE). Resolved against the MAIN checkout. Byte-identical
# logic to workstreams-emit.sh _resolve_gui_state_path + decision-context-gate.
_resolve_gui_state_path() {
  # Canonical-state-path consolidation: shared resolver returns the configured
  # canonical file (CONV_TREE_STATE_PATH override > home config > legacy GUI
  # sink computed below as fallback).
  local legacy mr d
  if mr=$(_main_repo_root) && [[ -n "$mr" ]]; then
    for d in workstreams-ui; do
      if [[ -f "$mr/neural-lace/$d/state/state.js" ]]; then
        legacy="$mr/neural-lace/$d/state/tree-state.json"; break
      fi
      if [[ -f "$mr/$d/state/state.js" ]]; then
        legacy="$mr/$d/state/tree-state.json"; break
      fi
    done
  fi
  [[ -z "${legacy:-}" ]] && legacy=$(_fallback_conv_tree_path "state/tree-state.json")
  if declare -F resolve_workstreams_state_path >/dev/null 2>&1; then
    resolve_workstreams_state_path "$legacy"
  else
    if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then printf '%s' "$CONV_TREE_STATE_PATH"; else printf '%s' "$legacy"; fi
  fi
}

# ADR-032 §5 path resolution. Pre-consolidation this was a SECOND divergent
# sink; the shared resolver now collapses it onto the SAME canonical file as
# the GUI sink (override > home config > legacy §5 path as fallback).
_resolve_gate_state_path() {
  local legacy root=""
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    legacy="$root/.claude/state/conversation-tree/tree-state.json"
  else
    legacy="$HOME/.claude/state/conversation-tree/global/tree-state.json"
  fi
  if declare -F resolve_workstreams_state_path >/dev/null 2>&1; then
    resolve_workstreams_state_path "$legacy"
  else
    if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then printf '%s' "$CONV_TREE_STATE_PATH"; else printf '%s' "$legacy"; fi
  fi
}

# Project/global root node from cwd (FR-1: project == a root node). Mirrors
# workstreams-emit.sh _project_root exactly so turn cards attach to the SAME
# root branch that --on-session-start / the fence gate use (no orphan roots).
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

_session_id() {
  local sid="${CLAUDE_SESSION_ID:-}"
  if [[ -z "$sid" ]] && [[ -n "${1:-}" ]] && _have jq; then
    sid=$(printf '%s' "$1" | jq -r '.session_id // .session.session_id // empty' 2>/dev/null || echo "")
  fi
  [[ -z "$sid" ]] && sid="ppid-${PPID:-$$}"
  printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

_read_stdin() {
  if [[ ! -t 0 ]]; then cat 2>/dev/null || echo ""; else echo ""; fi
}

# ============================================================================
# Facade-driven emit (mirrors workstreams-emit.sh _emit_to_sink / _emit_dual).
# ALL writes go through state.js appendEvent — never raw JSON, never HTTP.
# ============================================================================
_emit_to_sink() {
  local lib="$1" sink="$2" events_file="$3"
  [[ -z "$sink" ]] && return 0
  _have node || { _log "node unavailable — skipping sink $sink"; return 0; }
  mkdir -p "$(dirname "$sink")" 2>/dev/null || true
  local out
  out=$(node -e '
    var libPath = process.argv[1], sink = process.argv[2], evFile = process.argv[3];
    var fs = require("fs");
    var s, evs;
    try { s = require(libPath); } catch (e) { process.stdout.write("LIBERR:" + (e&&e.message||e)); process.exit(0); }
    try { evs = JSON.parse(fs.readFileSync(evFile, "utf8")); } catch (e) { process.stdout.write("ARGERR:" + (e&&e.message||e)); process.exit(0); }
    var ok = 0, skipped = 0, errs = [];
    for (var i = 0; i < evs.length; i++) {
      try { s.appendEvent(evs[i], { statePath: sink }); ok++; }
      catch (e) { skipped++; errs.push((evs[i]&&evs[i].type)+":"+(e&&e.message||e)); }
    }
    process.stdout.write("OK:" + ok + " skip:" + skipped + (errs.length?" errs:"+errs.join("|"):""));
    process.exit(0);
  ' "$lib" "$sink" "$events_file" 2>>"$LOG_FILE") || out="NODEERR"
  _log "sink=$sink result=$out"
}

# Emit a JSON array of events to the configured sink(s). CONV_TREE_STATE_PATH
# forces a single explicit sink. Otherwise both the GUI STATE_FILE and the §5
# gate path receive the same events, deduped to one write when they coincide.
_emit_dual() {
  local lib="$1" events_file="$2"
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then
    _emit_to_sink "$lib" "$CONV_TREE_STATE_PATH" "$events_file"
    return 0
  fi
  local gui gate
  gui=$(_resolve_gui_state_path)
  gate=$(_resolve_gate_state_path)
  if [[ -n "$gui" ]]; then _emit_to_sink "$lib" "$gui" "$events_file"; fi
  if [[ -n "$gate" && "$gate" != "$gui" ]]; then _emit_to_sink "$lib" "$gate" "$events_file"; fi
  if [[ -z "$gui" && -z "$gate" ]]; then _log "no resolvable sink — nothing emitted"; fi
}

# ============================================================================
# Deterministic extraction + event-array build (the heart of the hook).
# Implemented in ONE node call so the regex/extraction logic is portable and
# the JSON is well-formed by construction (no shell-quoting hazards). The node
# program receives the final-assistant-message text on a file + the
# session_id + turn_index + root node id/title, and prints the events JSON.
# ============================================================================
_build_events_file() {
  local msg_file="$1" sid="$2" turn_index="$3" root_id="$4" root_title="$5" out_file="$6"
  _have node || return 1
  node -e '
    var fs = require("fs");
    var msgPath = process.argv[1];
    var sid = process.argv[2];
    var turnIndex = process.argv[3];
    var rootId = process.argv[4];
    var rootTitle = process.argv[5];
    var outFile = process.argv[6];
    var crypto = require("crypto");

    var text = "";
    try { text = fs.readFileSync(msgPath, "utf8"); } catch (e) { text = ""; }
    if (!text) { fs.writeFileSync(outFile, "[]"); process.exit(0); }

    // content-hash component of the idempotency key (session_id, turn_index,
    // content-hash). A re-fire on the SAME message reproduces the SAME ids;
    // a new turn (different text) produces fresh ids.
    var contentHash = crypto.createHash("sha1").update(text).digest("hex").slice(0, 12);

    function h16(s) {
      return crypto.createHash("sha1").update(String(s)).digest("hex").slice(0, 16);
    }
    // Deterministic per-(sid,turn,content,kind,salt) event id.
    function eid(kind, salt) {
      return "wte-" + kind + "-" + h16(sid + "|" + turnIndex + "|" + contentHash + "|" + salt);
    }

    var lines = text.split(/\r?\n/);

    // ---- 1. The session-end marker (DONE / PAUSING / BLOCKED) --------------
    // Markers live on (typically) the last non-empty line per
    // session-end-protocol.md. Scan from the end for the first line whose
    // trimmed form begins with the marker keyword (leading markdown emphasis
    // tolerated, mirroring continuation-enforcer.sh).
    var marker = null, markerSummary = "";
    for (var li = lines.length - 1; li >= 0; li--) {
      var L = lines[li].replace(/^\s*[*_`>#-]+\s*/, "").trim();
      var m = L.match(/^(DONE|PAUSING|BLOCKED)\s*:\s*(.*)$/);
      if (m) { marker = m[1]; markerSummary = m[2].trim(); break; }
    }

    // ---- 2. Section-header items (Decisions/Questions/Action items) -------
    // Mirrors the workstreams-extract-pending.sh marker convention: a header
    // line alone, optionally bold/## wrapped, naming a kind; the bullet list
    // that immediately follows is the items.
    function headerKind(line) {
      var s = line.replace(/^\s*#+\s*/, "").replace(/^\s*\*\*\s*/, "").replace(/\s*\*\*\s*$/, "").trim();
      s = s.replace(/:\s*$/, "");
      var low = s.toLowerCase();
      if (/^decisions?\b/.test(low) && /\b(for|awaiting|need|from)\b/.test(low)) return "decision";
      if (/^questions?\b/.test(low) && /\b(for|awaiting|need|from)\b/.test(low)) return "question";
      if (/^(action items?|actions?)\b/.test(low) && /\b(for|awaiting|need|from)\b/.test(low)) return "action";
      // also accept the canonical "Waiting on you" header
      if (/^waiting on (you|misha)\b/.test(low)) return "action";
      return null;
    }
    function isListItem(line) {
      return /^\s*(?:[-*+]\s+|\d+[.)]\s+)/.test(line);
    }
    function stripBullet(line) {
      return line.replace(/^\s*(?:[-*+]\s+|\d+[.)]\s+)/, "").trim();
    }
    function isHr(line) { return /^\s*([-*_])\1{2,}\s*$/.test(line); }

    // collected items: { kind, text }
    var items = [];
    var seenText = {};
    function pushItem(kind, txt) {
      txt = String(txt || "").trim();
      if (!txt) return;
      // cap to a sane card length; keep first 280 chars
      if (txt.length > 280) txt = txt.slice(0, 277) + "...";
      var key = kind + "::" + txt.toLowerCase();
      if (seenText[key]) return;
      seenText[key] = 1;
      items.push({ kind: kind, text: txt });
    }

    for (var i = 0; i < lines.length; i++) {
      var k = headerKind(lines[i]);
      if (!k) continue;
      // consume the following list
      var j = i + 1;
      while (j < lines.length) {
        var ln = lines[j];
        if (isHr(ln)) break;
        if (headerKind(ln)) break;
        if (isListItem(ln)) {
          pushItem(k, stripBullet(ln));
          j++;
          // capture wrapped continuation lines (non-list, non-blank)
          while (j < lines.length && lines[j].trim() !== "" && !isListItem(lines[j]) && !headerKind(lines[j]) && !isHr(lines[j])) {
            // append continuation to the last item of this kind
            var last = items[items.length - 1];
            if (last) last.text = (last.text + " " + lines[j].trim()).slice(0, 280);
            j++;
          }
          continue;
        }
        if (ln.trim() === "") { // blank line ends the section
          break;
        }
        // a non-list, non-blank line before any list item ends the section
        break;
      }
      i = j - 1;
    }

    // ---- 3. PAUSING-marker decision: the marker summary itself ------------
    // When the marker is PAUSING/BLOCKED, the summary IS a decision/blocker the
    // operator must act on. Surface it as a decision (PAUSING) or action
    // (BLOCKED) item even if no section header was present (the failure mode
    // the discovery names: plain-prose PAUSING with no fence/section).
    if (marker === "PAUSING" && markerSummary) {
      pushItem("decision", markerSummary);
    } else if (marker === "BLOCKED" && markerSummary) {
      pushItem("action", markerSummary);
    }

    // ---- 4. Enumerated-option decision (no header, no marker) -------------
    // "pick one" / "your call" / "which do you prefer" + 2+ enumerated options
    // in the trailing window → a decision the operator must make. We capture
    // the solicitation sentence as the decision text (the options render as the
    // card body via the message itself; here we just need ONE card per turn).
    if (items.filter(function (x) { return x.kind === "decision"; }).length === 0) {
      var tail = lines.slice(Math.max(0, lines.length - 30)).join("\n");
      var solicit = /pick one|your call|which (?:do|would) you (?:want|prefer)|should I [A-Za-z]+ or [A-Za-z]/i.test(tail);
      var optCount = (tail.match(/^\s*(?:[A-Da-d]\)|[1-9][.)]\s|\*\*Option|-\s+Option)/gmi) || []).length;
      if (solicit && optCount >= 2) {
        // Use the solicitation sentence (the line containing the phrase) as text.
        var solLine = "";
        for (var s2 = lines.length - 1; s2 >= 0; s2--) {
          if (/pick one|your call|which (?:do|would) you|should I .* or /i.test(lines[s2])) { solLine = lines[s2].trim(); break; }
        }
        pushItem("decision", solLine || "Decision requested (enumerated options) — see message");
      }
    }

    // ---- 5. "waiting on you" inline (no header) ---------------------------
    // A line like "Waiting on you: <x>" or "waiting on you to <x>".
    if (items.filter(function (x) { return x.kind === "action"; }).length === 0) {
      for (var w = 0; w < lines.length; w++) {
        var wm = lines[w].match(/waiting on (?:you|misha)\s*(?:to|:)?\s*(.+)$/i);
        if (wm && wm[1] && wm[1].trim().length > 3) { pushItem("action", wm[1].trim()); break; }
      }
    }

    // ---- 6. in-flight + shipped annotation lines --------------------------
    var notes = [];
    function pushNote(tag, txt) {
      txt = String(txt || "").trim();
      if (!txt) return;
      if (txt.length > 280) txt = txt.slice(0, 277) + "...";
      notes.push({ tag: tag, text: txt });
    }
    // in-flight statements
    for (var f = 0; f < lines.length; f++) {
      if (/\b(in[- ]flight|in progress|still (?:building|working|running)|currently (?:building|working))\b/i.test(lines[f])) {
        pushNote("in-flight", lines[f].trim());
        break; // one in-flight note per turn is enough
      }
    }
    // shipped / merged
    for (var g = 0; g < lines.length; g++) {
      if (/\b(shipped|merged to (?:master|main)|deployed to (?:master|production|prod)|landed on (?:master|main))\b/i.test(lines[g])) {
        pushNote("shipped", lines[g].trim());
        break;
      }
    }
    if (marker === "DONE" && markerSummary) {
      pushNote("done", "DONE: " + markerSummary);
    }

    // ---- 7. Build the event array -----------------------------------------
    // Nothing to surface? Emit nothing (no empty turn cards).
    var hasContent = (marker !== null) || items.length > 0 || notes.length > 0;
    if (!hasContent) { fs.writeFileSync(outFile, "[]"); process.exit(0); }

    var events = [];

    // 7a. Defensive root branch-opened (idempotent on event_id — the
    // session-start hook or fence gate may already have opened it).
    events.push({
      event_id: "wte-root-" + h16(rootId),
      type: "branch-opened",
      node_id: rootId,
      parent_id: null,
      title: rootTitle || rootId,
      actor: "dispatch"
    });

    // 7b. The per-turn branch node, parented under the project/global root.
    // Title = the marker summary (or a generic turn label). The turn node is
    // the card the operator sees for "what happened this turn".
    var turnNodeId = "turn-" + sid + "-" + turnIndex;
    var turnTitle = marker
      ? (marker + ": " + (markerSummary || "(no summary)")).slice(0, 120)
      : ("Turn " + turnIndex);
    events.push({
      event_id: "wte-tbo-" + h16(turnNodeId),
      type: "branch-opened",
      node_id: turnNodeId,
      parent_id: rootId,
      title: turnTitle,
      actor: "dispatch"
    });

    // 7c. Items (decision/question/action) as cards ON the turn node.
    var kindToEvent = {
      decision: "decision-raised",
      question: "question-raised",
      action: "action-added"
    };
    for (var ii = 0; ii < items.length; ii++) {
      var it = items[ii];
      var evType = kindToEvent[it.kind] || "action-added";
      var salt = it.kind + "|" + it.text;
      var itemId = "item-" + h16(salt);
      events.push({
        event_id: eid(it.kind.slice(0, 3), salt),
        type: evType,
        node_id: turnNodeId,
        item_id: itemId,
        text: it.text,
        actor: "dispatch"
      });
      // rich details so the GUI detail-pane renders source + kind.
      events.push({
        event_id: eid("ids", salt),
        type: "item-details-set",
        node_id: turnNodeId,
        item_id: itemId,
        details: {
          kind: it.kind,
          source: "workstreams-turn-emit",
          surfaced_by: "workstreams-turn-emit",
          turn_index: Number(turnIndex) || turnIndex,
          marker: marker || null
        },
        actor: "dispatch"
      });
    }

    // 7d. Notes (marker summary / in-flight / shipped) as annotations on the
    // turn node. Annotations do not require the node to be unchecked-free, so
    // they coexist with open items (FR-7 only constrains `concluded`).
    for (var nn = 0; nn < notes.length; nn++) {
      var note = notes[nn];
      events.push({
        event_id: eid("note", note.tag + "|" + note.text),
        type: "annotated",
        node_id: turnNodeId,
        text: "[" + note.tag + "] " + note.text,
        actor: "dispatch"
      });
    }

    fs.writeFileSync(outFile, JSON.stringify(events));
    process.exit(0);
  ' "$msg_file" "$sid" "$turn_index" "$root_id" "$root_title" "$out_file" 2>>"$LOG_FILE"
}

# Count assistant messages in the transcript → a stable per-turn index. Uses jq
# slurp; falls back to 0 if jq is unavailable (the content-hash still keys the
# idempotency, turn_index just disambiguates identical messages across turns).
_turn_index() {
  local transcript="$1"
  if _have jq && [[ -f "$transcript" ]]; then
    jq -rs '[ .[] | select(.role=="assistant" or .message.role=="assistant") ] | length' \
      "$transcript" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Extract the FINAL assistant message body in full (multi-line preserved).
_extract_last_assistant() {
  local transcript="$1"
  jq -rs '
    [ .[]
      | select(.role == "assistant" or .message.role == "assistant")
      | (.content // .text // .message.content // empty)
    ]
    | last
    | if type == "string" then . else (. | tostring) end
  ' "$transcript" 2>/dev/null || echo ""
}

# ============================================================================
# Main runtime flow
# ============================================================================
_run() {
  if [[ "${WORKSTREAMS_TURN_EMIT_DISABLE:-0}" == "1" ]]; then
    exit 0
  fi

  local INPUT; INPUT=$(_read_stdin)

  local TRANSCRIPT_PATH=""
  if [[ -n "$INPUT" ]] && _have jq; then
    TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
  fi
  if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    _log "no transcript — silent no-op"
    exit 0
  fi
  if ! _have jq; then _log "jq unavailable — silent no-op"; exit 0; fi
  if ! _have node; then _log "node unavailable — silent no-op"; exit 0; fi

  local SID; SID=$(_session_id "$INPUT")
  local TURN; TURN=$(_turn_index "$TRANSCRIPT_PATH")
  local LAST; LAST=$(_extract_last_assistant "$TRANSCRIPT_PATH")
  if [[ -z "$LAST" ]]; then _log "empty last-assistant — no-op"; exit 0; fi

  local ROOTLINE; ROOTLINE=$(_project_root)
  local ROOT_ID="${ROOTLINE%%$'\t'*}"
  local ROOT_TITLE="${ROOTLINE##*$'\t'}"

  local LIB; LIB=$(_resolve_state_lib)
  local MSG_FILE; MSG_FILE=$(mktemp 2>/dev/null || echo "/tmp/wte-msg-$$.txt")
  local EV_FILE; EV_FILE=$(mktemp 2>/dev/null || echo "/tmp/wte-ev-$$.json")
  printf '%s' "$LAST" >"$MSG_FILE"

  if _build_events_file "$MSG_FILE" "$SID" "$TURN" "$ROOT_ID" "$ROOT_TITLE" "$EV_FILE"; then
    # Skip the emit when the event array is empty (nothing surfaced this turn).
    local n
    n=$(node -e 'try{var a=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(a.length))}catch(e){process.stdout.write("0")}' "$EV_FILE" 2>/dev/null || echo 0)
    if [[ "${n:-0}" -gt 0 ]]; then
      _emit_dual "$LIB" "$EV_FILE"
      _log "turn=$TURN session=$SID emitted $n event(s) (root=$ROOT_ID)"
    else
      _log "turn=$TURN session=$SID nothing to surface"
    fi
  else
    _log "event build failed — no-op"
  fi

  rm -f "$MSG_FILE" "$EV_FILE" 2>/dev/null || true
  exit 0
}

# ============================================================================
# Self-test
# ============================================================================
_self_test() {
  trap - ERR
  local pass=0 fail=0
  local TMP; TMP=$(mktemp -d 2>/dev/null || echo "/tmp/wte-st-$$")
  mkdir -p "$TMP"
  local SELF; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  local LIB; LIB=$(_resolve_state_lib)
  if [[ ! -f "$LIB" ]]; then
    echo "self-test: cannot locate state library ($LIB)"; echo "self-test: FAIL"; exit 1
  fi
  if ! _have node || ! _have jq; then
    echo "self-test: node/jq unavailable"; echo "self-test: FAIL"; exit 1
  fi
  export CONV_TREE_STATE_LIB="$LIB"

  _ck() {
    if [[ "$2" == "$3" ]]; then echo "PASS: $1"; pass=$((pass+1));
    else echo "FAIL: $1 (got '$2' want '$3')"; fail=$((fail+1)); fi
  }
  _ck_ge() {
    if [[ "$2" -ge "$3" ]] 2>/dev/null; then echo "PASS: $1"; pass=$((pass+1));
    else echo "FAIL: $1 (got '$2' want >= '$3')"; fail=$((fail+1)); fi
  }

  # build a transcript JSONL whose final assistant message is $2
  _make_transcript() {
    local tfile="$1" text="$2"
    printf '%s\n' "$(jq -nc --arg t "user setup" '{role:"user", content:$t}')" >"$tfile"
    printf '%s\n' "$(jq -nc --arg t "$text" '{role:"assistant", content:$t}')" >>"$tfile"
  }
  # count events of a type in a sink file
  _count_type() {
    node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.stdout.write(String(st.events.filter(function(e){return e.type===process.argv[3]}).length))}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2" 2>/dev/null
  }
  # count items across snapshot.nodes by kind
  _count_items() {
    node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var k=process.argv[3];var c=0;st.snapshot.nodes.forEach(function(n){(n.items||[]).forEach(function(it){if(it.kind===k)c++})});process.stdout.write(String(c))}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2"
  }
  # does a node with the given title prefix exist?
  _node_title_match() {
    node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var re=process.argv[3];process.stdout.write(st.snapshot.nodes.some(function(n){return new RegExp(re).test(n.title||"")})?"Y":"N")}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2"
  }
  # total annotations across nodes
  _count_annotations() {
    node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var c=0;st.snapshot.nodes.forEach(function(n){(n.annotations||[]).forEach(function(){c++})});process.stdout.write(String(c))}catch(e){process.stdout.write("ERR")}' "$LIB" "$1"
  }
  _run_hook() {
    local transcript="$1" sink="$2" sid="$3"
    CONV_TREE_STATE_PATH="$sink" CLAUDE_SESSION_ID="$sid" \
      bash "$SELF" <<<"$(jq -nc --arg p "$transcript" --arg s "$sid" '{transcript_path:$p, session_id:$s}')" >/dev/null 2>&1
    echo $?
  }

  # ---------- ST1: PAUSING marker with options → decision card -------------
  local TR1="$TMP/tr1.jsonl" SP1="$TMP/sp1.json"
  _make_transcript "$TR1" "$(printf 'I reviewed the 24 proposals.\n\nPAUSING: need your call on whether to apply migration m162 to production before the deploy — it drops a legacy column irreversibly.')"
  local RC1; RC1=$(_run_hook "$TR1" "$SP1" "sess-st1")
  _ck "ST1 PAUSING marker → exit 0" "$RC1" "0"
  _ck "ST1 decision-raised emitted" "$(_count_type "$SP1" decision-raised)" "1"
  _ck "ST1 turn node titled with PAUSING" "$(_node_title_match "$SP1" '^PAUSING:')" "Y"
  _ck "ST1 decision item lands in snapshot.nodes[].items[]" "$(_count_items "$SP1" decision)" "1"

  # ---------- ST2: idempotency — re-fire same message → no duplication -----
  local RC2; RC2=$(_run_hook "$TR1" "$SP1" "sess-st1")
  _ck "ST2 re-fire same message → exit 0" "$RC2" "0"
  _ck "ST2 decision-raised still 1 (idempotent)" "$(_count_type "$SP1" decision-raised)" "1"
  _ck "ST2 decision items still 1 (idempotent)" "$(_count_items "$SP1" decision)" "1"

  # ---------- ST3: section headers → mixed cards ---------------------------
  local TR3="$TMP/tr3.jsonl" SP3="$TMP/sp3.json"
  _make_transcript "$TR3" "$(printf 'Progress update.\n\nDecisions for Misha:\n- Approve the DB password rotation\n- Choose squash vs merge for #476\n\nQuestions for Misha:\n- Which Twilio number should the campaign use?\n\nAction items for Misha:\n- Rotate the production API key in Vercel\n\nDONE: shipped the turn-emit hook (commit abc1234)')"
  local RC3; RC3=$(_run_hook "$TR3" "$SP3" "sess-st3")
  _ck "ST3 section headers → exit 0" "$RC3" "0"
  _ck "ST3 two decisions" "$(_count_items "$SP3" decision)" "2"
  _ck "ST3 one question" "$(_count_items "$SP3" question)" "1"
  _ck "ST3 one action" "$(_count_items "$SP3" action)" "1"
  # DONE marker → annotation note
  _ck_ge "ST3 at least one annotation (DONE note)" "$(_count_annotations "$SP3")" "1"

  # ---------- ST4: enumerated options, no header, no marker → decision -----
  local TR4="$TMP/tr4.jsonl" SP4="$TMP/sp4.json"
  _make_transcript "$TR4" "$(printf 'For the cherry-pick conflict, which do you prefer?\n\nA) Take ours\nB) Take theirs\nC) Hand-resolve to union')"
  local RC4; RC4=$(_run_hook "$TR4" "$SP4" "sess-st4")
  _ck "ST4 enumerated options → exit 0" "$RC4" "0"
  _ck "ST4 decision card from enumerated options" "$(_count_items "$SP4" decision)" "1"

  # ---------- ST5: no marker, no items, plain prose → no cards -------------
  local TR5="$TMP/tr5.jsonl" SP5="$TMP/sp5.json"
  _make_transcript "$TR5" "I read the file and confirmed the handler signature is unchanged. Continuing to the next step."
  local RC5; RC5=$(_run_hook "$TR5" "$SP5" "sess-st5")
  _ck "ST5 plain prose → exit 0" "$RC5" "0"
  if [[ ! -f "$SP5" ]]; then
    echo "PASS: ST5 no state file written (nothing to surface)"; pass=$((pass+1))
  else
    # if written, must contain zero turn nodes / items
    _ck "ST5 zero decision-raised" "$(_count_type "$SP5" decision-raised)" "0"
  fi

  # ---------- ST6: BLOCKED marker → action card ----------------------------
  local TR6="$TMP/tr6.jsonl" SP6="$TMP/sp6.json"
  _make_transcript "$TR6" "$(printf 'Investigated the deploy.\n\nBLOCKED: e2e suite needs the DB password in .env.local which is unset here — provide it or a sandbox with it set.')"
  local RC6; RC6=$(_run_hook "$TR6" "$SP6" "sess-st6")
  _ck "ST6 BLOCKED marker → exit 0" "$RC6" "0"
  _ck "ST6 action-added from BLOCKED" "$(_count_items "$SP6" action)" "1"

  # ---------- ST7: new turn (different message) → fresh cards, not dup -----
  # Same session + sink, a DIFFERENT final message → distinct turn node + card.
  local TR7="$TMP/tr7.jsonl"
  # Append two more assistant turns so turn_index advances and content differs.
  cp "$TR1" "$TR7"
  printf '%s\n' "$(jq -nc '{role:"user", content:"and the next?"}')" >>"$TR7"
  printf '%s\n' "$(jq -nc '{role:"assistant", content:"PAUSING: also need your decision on the R23 reframe vs leaving it as-is."}')" >>"$TR7"
  local RC7; RC7=$(_run_hook "$TR7" "$SP1" "sess-st1")
  _ck "ST7 new turn → exit 0" "$RC7" "0"
  # Now SP1 should have 2 decision-raised total (the m162 one + the R23 one)
  _ck "ST7 second turn adds a distinct decision (total 2)" "$(_count_type "$SP1" decision-raised)" "2"

  # ---------- ST8: no transcript → silent no-op ----------------------------
  local RC8
  RC8=$(WORKSTREAMS_TURN_EMIT_DISABLE=0 bash "$SELF" <<<'{"session_id":"st8"}' >/dev/null 2>&1; echo $?)
  _ck "ST8 missing transcript → exit 0" "$RC8" "0"

  # ---------- ST9: DISABLE escape hatch → no emit --------------------------
  local TR9="$TMP/tr9.jsonl" SP9="$TMP/sp9.json"
  _make_transcript "$TR9" "PAUSING: should we ship X or Y?"
  local RC9
  RC9=$(WORKSTREAMS_TURN_EMIT_DISABLE=1 CONV_TREE_STATE_PATH="$SP9" CLAUDE_SESSION_ID="st9" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR9" '{transcript_path:$p, session_id:"st9"}')" >/dev/null 2>&1; echo $?)
  _ck "ST9 DISABLE → exit 0" "$RC9" "0"
  if [[ ! -f "$SP9" ]]; then
    echo "PASS: ST9 DISABLE → no state file written"; pass=$((pass+1))
  else
    echo "FAIL: ST9 DISABLE should not write state"; fail=$((fail+1))
  fi

  # ---------- ST10: facade unavailable → exit 0 (writer-hook discipline) ---
  local TR10="$TMP/tr10.jsonl"
  _make_transcript "$TR10" "PAUSING: decide on the thing."
  local RC10
  RC10=$(CONV_TREE_STATE_LIB="$TMP/does-not-exist.js" CONV_TREE_STATE_PATH="$TMP/sp10.json" CLAUDE_SESSION_ID="st10" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR10" '{transcript_path:$p, session_id:"st10"}')" >/dev/null 2>&1; echo $?)
  _ck "ST10 facade-down → exit 0 (never blocks)" "$RC10" "0"

  # ---------- ST11: in-flight statement → annotation -----------------------
  local TR11="$TMP/tr11.jsonl" SP11="$TMP/sp11.json"
  _make_transcript "$TR11" "$(printf 'The migration is still building in the background.\n\nDONE: kicked off the build')"
  local RC11; RC11=$(_run_hook "$TR11" "$SP11" "sess-st11")
  _ck "ST11 in-flight → exit 0" "$RC11" "0"
  _ck_ge "ST11 annotations present (in-flight + done)" "$(_count_annotations "$SP11")" "1"

  # ---------- ST12: shipped/merged line → annotation -----------------------
  local TR12="$TMP/tr12.jsonl" SP12="$TMP/sp12.json"
  _make_transcript "$TR12" "$(printf 'Merged to master at deadbeef.\n\nDONE: feature shipped to production')"
  local RC12; RC12=$(_run_hook "$TR12" "$SP12" "sess-st12")
  _ck "ST12 shipped line → exit 0" "$RC12" "0"
  _ck_ge "ST12 annotation present (shipped)" "$(_count_annotations "$SP12")" "1"

  echo
  echo "self-test: $pass pass, $fail fail"
  if [[ "$fail" -eq 0 ]]; then
    echo "self-test: OK $pass/$((pass+fail))"
    rm -rf "$TMP" 2>/dev/null || true
    exit 0
  else
    echo "self-test: FAIL"
    echo "(temp dir kept for inspection: $TMP)"
    exit 1
  fi
}

# ----- main dispatch -------------------------------------------------------
case "$MODE" in
  --self-test) _self_test ;;
  *) _run ;;
esac
