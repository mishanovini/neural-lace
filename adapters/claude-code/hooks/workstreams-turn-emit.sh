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

# shellcheck disable=SC1091
{ source "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/nl-paths.sh" 2>/dev/null; } || true

MODE="${1:-}"

# Log destination: sandboxed when HARNESS_SELFTEST=1 or MODE is --self-test
# itself (self-test isolation — E.2 remediation) so no self-test run appends
# to the real machine's ~/.claude/logs/workstreams-turn-emit.log regardless
# of HOME. Prefers an explicit HARNESS_SELFTEST_DIR; falls back to a
# PID-scoped tmp sandbox otherwise (signal-ledger.sh's convention).
if [[ "${HARNESS_SELFTEST:-0}" == "1" ]] || [[ "$MODE" == "--self-test" ]]; then
  export HARNESS_SELFTEST=1
  _WTE_SANDBOX="${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}/workstreams-turn-emit-selftest/$$}"
  export HARNESS_SELFTEST_DIR="$_WTE_SANDBOX"
  LOG_DIR="$_WTE_SANDBOX/logs"
else
  LOG_DIR="$HOME/.claude/logs"
fi
LOG_FILE="$LOG_DIR/workstreams-turn-emit.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

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
  local base="${CONV_TREE_MAIN_CHECKOUT:-}"
  if [[ -z "$base" ]] && command -v nl_repo_root >/dev/null 2>&1; then
    base="$(nl_repo_root 2>/dev/null)"
  fi
  [[ -z "$base" ]] && base="$HOME/.claude"
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

# Resolve the SOLE-NORMATIVE decision-context schema module
# (decision-context-schema.js — sibling of state.js). Carries
# assembleItemDetails(): the single normative assembler both emit paths use to
# produce self-contained item `details` (Phase C, 2026-06-09). Override via
# CONV_TREE_SCHEMA_LIB (self-test). Falls back to the state-lib's sibling.
_resolve_schema_lib() {
  if [[ -n "${CONV_TREE_SCHEMA_LIB:-}" ]]; then printf '%s' "$CONV_TREE_SCHEMA_LIB"; return 0; fi
  local statelib; statelib=$(_resolve_state_lib)
  local dir; dir=$(dirname "$statelib")
  printf '%s' "$dir/decision-context-schema.js"
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
#
# Phase C rewrite (2026-06-09) — Misha: "items show INCOMPLETE METADATA /
# fragments like 'Turn 2229' or a garbled \" decisions… — useless. Assume I
# will not look at this until I've COMPLETELY FORGOTTEN what we're doing. I
# need background to trigger my memory and the info to make a decision."
#
# The fix has three parts:
#   1. NO per-turn "Turn N" node. Items attach DIRECTLY to the project/global
#      ROOT node (the same shape decision-context-gate.sh uses — items live ON
#      a node, FR-2). No more "Turn 2229" noise cards.
#   2. FRAGMENT REJECTION. _isCleanItem() rejects mid-sentence fragments,
#      escaped-quote/leading-punctuation noise, lowercase continuations, and
#      too-short scraps. Only a clean, complete, self-contained solicitation is
#      a candidate.
#   3. SELF-CONTAINED details. Each item carries a BACKGROUND memory-trigger
#      paragraph + the actionable field, assembled + validated via the SOLE
#      NORMATIVE assembleItemDetails() (decision-context-schema.js). If the
#      assembler returns null (no background / no actionable field) the item is
#      NOT emitted — emit NOTHING rather than an "INCOMPLETE METADATA" card.
#
# Implemented in ONE node call so the regex/extraction logic is portable and
# the JSON is well-formed by construction. The node program receives the
# final-assistant-message text on a file + session_id + turn_index + root node
# id/title + the schema-lib path, and prints the events JSON.
# ============================================================================
_build_events_file() {
  local msg_file="$1" sid="$2" turn_index="$3" root_id="$4" root_title="$5" out_file="$6" schema_lib="$7"
  _have node || return 1
  node -e '
    var fs = require("fs");
    var msgPath = process.argv[1];
    var sid = process.argv[2];
    var turnIndex = process.argv[3];
    var rootId = process.argv[4];
    var rootTitle = process.argv[5];
    var outFile = process.argv[6];
    var schemaLib = process.argv[7];
    var crypto = require("crypto");

    // ---- SOLE NORMATIVE details assembler -------------------------------
    // Load assembleItemDetails from the schema module. If it cannot be loaded
    // (stripped env / missing dep) fall back to an INLINE assembler that
    // applies the SAME contract (background + >=1 actionable field, else
    // null). The fallback exists only so the writer never crashes; the schema
    // module remains the normative source when present.
    var assembleItemDetails = null;
    try {
      var sch = require(schemaLib);
      if (sch && typeof sch.assembleItemDetails === "function") assembleItemDetails = sch.assembleItemDetails;
    } catch (e) { /* fall through to inline */ }
    if (!assembleItemDetails) {
      var CATS = ["decision", "question", "action_item_for_user", "autonomous_action"];
      var ACTIONABLE = {
        decision: ["question", "options", "the_ask", "description"],
        question: ["question", "why_asking", "description"],
        action_item_for_user: ["the_ask", "instructions", "description"],
        autonomous_action: ["action_taken", "reasoning", "description"]
      };
      assembleItemDetails = function (category, fields) {
        if (CATS.indexOf(category) === -1) return null;
        var d = Object.assign({}, fields || {}, { _category: category });
        if (!d.background || String(d.background).trim() === "") return null;
        var need = ACTIONABLE[category] || [];
        var has = need.some(function (f) { return d[f] != null && String(d[f]).trim() !== ""; });
        if (!has) return null;
        return d;
      };
    }

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
    function eid(kind, salt) {
      return "wte-" + kind + "-" + h16(sid + "|" + turnIndex + "|" + contentHash + "|" + salt);
    }

    var lines = text.split(/\r?\n/);

    // ---- FRAGMENT GUARD (escaping-agnostic) -------------------------------
    // A candidate item must be a clean, complete, self-contained statement.
    // The garbage Misha saw was JSONL escape-corruption + list-fragment
    // leftovers — all detectable by their LEADING character, which is robust
    // across shell-escaping (no fragile unescape pass needed). Reject when the
    // first char is a fragment-leader (backslash, quote, closing-punct,
    // list-leftover, open-paren parenthetical, code-fence/table/blockquote
    // marker, smart-quote), a bare path/identifier with no spaces, or too
    // short to be a real ask. The clean asks ("need your call ...", "Approve
    // the ...", "which do you prefer?") begin with a letter + contain a space.
    //
    // FRAGMENT_LEADERS is built from char codes because the node program is
    // embedded inside a single-quoted bash string — a literal single-quote or
    // backtick in the JS source would terminate it. Codes:
    //   92 \   34 "   39 (apostrophe)   96 (backtick)   41 )   93 ]   125 }
    //   44 ,   59 ;   58 :   46 .   45 -   124 |   62 >   42 *   95 _   126 ~
    //   40 (   8220/8221 smart-doublequotes   8216/8217 smart-singlequotes
    function cleanText(s) {
      // Trim + collapse internal whitespace. Deliberately does NOT unescape —
      // escape artifacts are a garbage signal the leading-char guard catches.
      return String(s == null ? "" : s).replace(/\s+/g, " ").trim();
    }
    var FRAGMENT_LEADER_CODES = [
      92, 34, 39, 96, 41, 93, 125, 44, 59, 58, 46, 45, 124, 62, 42, 95, 126, 40,
      8220, 8221, 8216, 8217
    ];
    function isFragmentLeader(ch) {
      var code = ch.charCodeAt(0);
      for (var i = 0; i < FRAGMENT_LEADER_CODES.length; i++) {
        if (FRAGMENT_LEADER_CODES[i] === code) return true;
      }
      return false;
    }
    function isCleanItem(s) {
      s = cleanText(s);
      if (s.length < 12) return false;
      if (isFragmentLeader(s.charAt(0))) return false;
      if (/^[A-Za-z0-9._\/-]+$/.test(s)) return false; // bare path/identifier
      if (!/\s/.test(s)) return false;                  // single token, no ask
      return true;
    }

    // ---- 1. session-end marker (DONE / PAUSING / BLOCKED) -----------------
    var marker = null, markerSummary = "";
    for (var li = lines.length - 1; li >= 0; li--) {
      var L = lines[li].replace(/^\s*[*_`>#-]+\s*/, "").trim();
      var m = L.match(/^(DONE|PAUSING|BLOCKED)\s*:\s*(.*)$/);
      if (m) { marker = m[1]; markerSummary = cleanText(m[2]); break; }
    }

    // ---- section-header detection -----------------------------------------
    function headerKind(line) {
      var s = line.replace(/^\s*#+\s*/, "").replace(/^\s*\*\*\s*/, "").replace(/\s*\*\*\s*$/, "").trim();
      s = s.replace(/:\s*$/, "");
      var low = s.toLowerCase();
      if (/^decisions?\b/.test(low) && /\b(for|awaiting|need|from)\b/.test(low)) return "decision";
      if (/^questions?\b/.test(low) && /\b(for|awaiting|need|from)\b/.test(low)) return "question";
      if (/^(action items?|actions?)\b/.test(low) && /\b(for|awaiting|need|from)\b/.test(low)) return "action";
      if (/^waiting on (you|misha)\b/.test(low)) return "action";
      return null;
    }
    function isListItem(line) { return /^\s*(?:[-*+]\s+|\d+[.)]\s+)/.test(line); }
    function stripBullet(line) { return line.replace(/^\s*(?:[-*+]\s+|\d+[.)]\s+)/, "").trim(); }
    function isHr(line) { return /^\s*([-*_])\1{2,}\s*$/.test(line); }

    // ---- a memory-trigger BACKGROUND paragraph ----------------------------
    // Misha forgot all context. Background must answer: what is this, what were
    // we doing, why does it matter. We assemble it from what we can ground in
    // the message deterministically — never fabricate. Sources, in order:
    //   - the project/root this turn belongs to (orientation),
    //   - the section the item came from (the kind + header phrasing),
    //   - the lead context paragraph of the message (the "what were we doing"),
    //   - the marker summary when present (the "why now / what is at stake").
    // The result is prose the operator can read cold.
    var leadContext = "";
    (function () {
      // first 1-3 non-empty, non-header, non-list prose lines = the gist of
      // what this turn was about.
      var picked = [];
      for (var i = 0; i < lines.length && picked.length < 3; i++) {
        var ln = lines[i].trim();
        if (!ln) continue;
        if (headerKind(lines[i])) continue;
        if (isListItem(lines[i])) continue;
        if (isHr(lines[i])) continue;
        if (/^(DONE|PAUSING|BLOCKED)\s*:/.test(ln)) continue;
        if (/^[#>*`|]/.test(ln)) continue;
        picked.push(cleanText(ln));
      }
      leadContext = picked.join(" ").slice(0, 400);
    })();

    var projectLabel = (rootTitle && rootTitle !== rootId) ? rootTitle : "this workstream";

    function buildBackground(kind, headerPhrase) {
      var parts = [];
      // orientation
      parts.push("From " + projectLabel + (marker ? " (turn ended " + marker + ")" : "") + ".");
      // what were we doing
      if (leadContext && leadContext.length > 8) parts.push("Context: " + leadContext);
      // why it matters / what is at stake — the marker summary when distinct
      if (markerSummary && markerSummary.length > 8) parts.push("At stake: " + markerSummary);
      // the kind framing
      var kindWord = kind === "decision" ? "A decision is awaiting you"
        : kind === "question" ? "A question is awaiting your answer"
        : "An action is assigned to you";
      parts.push(kindWord + (headerPhrase ? " (" + headerPhrase + ")" : "") + ".");
      var bg = parts.join(" ").replace(/\s+/g, " ").trim();
      return bg.length > 700 ? bg.slice(0, 697) + "..." : bg;
    }

    // ---- collect candidate items (kind + text + header phrase) ------------
    var candidates = [];
    var seenText = {};
    function pushCandidate(kind, txt, headerPhrase) {
      txt = cleanText(txt);
      if (!isCleanItem(txt)) return;            // FRAGMENT GUARD
      if (txt.length > 220) txt = txt.slice(0, 217) + "...";
      var key = kind + "::" + txt.toLowerCase();
      if (seenText[key]) return;
      seenText[key] = 1;
      candidates.push({ kind: kind, text: txt, headerPhrase: headerPhrase || "" });
    }

    // 2a. section-header lists
    for (var i = 0; i < lines.length; i++) {
      var k = headerKind(lines[i]);
      if (!k) continue;
      var headerPhrase = lines[i].replace(/^\s*[#*\s]+/, "").replace(/[:*\s]+$/, "").trim();
      var j = i + 1;
      while (j < lines.length) {
        var ln = lines[j];
        if (isHr(ln)) break;
        if (headerKind(ln)) break;
        if (isListItem(ln)) {
          var itemText = stripBullet(ln);
          j++;
          // fold wrapped continuation lines INTO this item (they belong to it)
          while (j < lines.length && lines[j].trim() !== "" && !isListItem(lines[j]) && !headerKind(lines[j]) && !isHr(lines[j])) {
            itemText = (itemText + " " + lines[j].trim());
            j++;
          }
          pushCandidate(k, itemText, headerPhrase);
          continue;
        }
        if (ln.trim() === "") break;
        break;
      }
      i = j - 1;
    }

    // 2b. PAUSING/BLOCKED marker summary as a decision/action (the plain-prose
    // failure mode: a PAUSING with no fence/section). Only if it is a clean,
    // self-contained sentence.
    if (marker === "PAUSING" && markerSummary) {
      pushCandidate("decision", markerSummary, "PAUSING marker");
    } else if (marker === "BLOCKED" && markerSummary) {
      pushCandidate("action", markerSummary, "BLOCKED marker");
    }

    // 2c. enumerated-option decision (no header, no marker): "pick one" /
    // "your call" / "which do you prefer" + >=2 enumerated options.
    if (candidates.filter(function (x) { return x.kind === "decision"; }).length === 0) {
      var tail = lines.slice(Math.max(0, lines.length - 30)).join("\n");
      var solicit = /pick one|your call|which (?:do|would) you (?:want|prefer)|should I [A-Za-z]+ or [A-Za-z]/i.test(tail);
      var optCount = (tail.match(/^\s*(?:[A-Da-d]\)|[1-9][.)]\s|\*\*Option|-\s+Option)/gmi) || []).length;
      if (solicit && optCount >= 2) {
        var solLine = "";
        for (var s2 = lines.length - 1; s2 >= 0; s2--) {
          if (/pick one|your call|which (?:do|would) you|should I .* or /i.test(lines[s2])) { solLine = cleanText(lines[s2]); break; }
        }
        if (solLine) pushCandidate("decision", solLine, "enumerated options");
      }
    }

    // 2d. inline "waiting on you: <x>"
    if (candidates.filter(function (x) { return x.kind === "action"; }).length === 0) {
      for (var w = 0; w < lines.length; w++) {
        var wm = lines[w].match(/waiting on (?:you|misha)\s*(?:to|:)?\s*(.+)$/i);
        if (wm && wm[1] && cleanText(wm[1]).length > 3) { pushCandidate("action", wm[1], "waiting on you"); break; }
      }
    }

    // ---- build the event array --------------------------------------------
    // Items attach to the ROOT node (no per-turn node). Each item carries a
    // self-contained `details` via assembleItemDetails; if that returns null
    // the item is DROPPED (emit nothing rather than incomplete metadata).
    var kindToEvent = {
      decision: "decision-raised",
      question: "question-raised",
      action: "action-added"
    };
    var detailCat = {
      decision: "decision",
      question: "question",
      action: "action_item_for_user"
    };

    var events = [];
    var emitted = 0;

    for (var ci = 0; ci < candidates.length; ci++) {
      var c = candidates[ci];
      var cat = detailCat[c.kind] || "action_item_for_user";
      // actionable field per category
      var fields = {
        background: buildBackground(c.kind, c.headerPhrase),
        surfaced_by: "workstreams-turn-emit",
        source: "workstreams-turn-emit",
        turn_index: Number(turnIndex) || turnIndex,
        links: [ "(see branch: " + (rootTitle || rootId) + ")" ]
      };
      if (cat === "decision") { fields.question = c.text; }
      else if (cat === "question") { fields.question = c.text; }
      else { fields.the_ask = c.text; }

      var details = assembleItemDetails(cat, fields);
      if (!details) continue;   // not self-contained → DROP (no garbage card)

      // first self-contained item triggers the defensive root branch-opened
      if (emitted === 0) {
        events.push({
          event_id: "wte-root-" + h16(rootId),
          type: "branch-opened",
          node_id: rootId,
          parent_id: null,
          title: rootTitle || rootId,
          actor: "dispatch"
        });
      }

      var evType = kindToEvent[c.kind] || "action-added";
      var salt = c.kind + "|" + c.text;
      var itemId = "item-" + h16(salt);
      events.push({
        event_id: eid(c.kind.slice(0, 3), salt),
        type: evType,
        node_id: rootId,
        item_id: itemId,
        text: c.text,
        actor: "dispatch"
      });
      events.push({
        event_id: eid("ids", salt),
        type: "item-details-set",
        node_id: rootId,
        item_id: itemId,
        details: details,
        actor: "dispatch"
      });
      emitted++;
    }

    // Nothing self-contained surfaced this turn → emit nothing. NO "Turn N"
    // node, NO status annotations. Silence beats noise.
    fs.writeFileSync(outFile, JSON.stringify(events));
    process.exit(0);
  ' "$msg_file" "$sid" "$turn_index" "$root_id" "$root_title" "$out_file" "$schema_lib" 2>>"$LOG_FILE"
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
  local SCHEMA; SCHEMA=$(_resolve_schema_lib)
  local MSG_FILE; MSG_FILE=$(mktemp 2>/dev/null || echo "/tmp/wte-msg-$$.txt")
  local EV_FILE; EV_FILE=$(mktemp 2>/dev/null || echo "/tmp/wte-ev-$$.json")
  printf '%s' "$LAST" >"$MSG_FILE"

  if _build_events_file "$MSG_FILE" "$SID" "$TURN" "$ROOT_ID" "$ROOT_TITLE" "$EV_FILE" "$SCHEMA"; then
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
  local SCHEMA; SCHEMA=$(_resolve_schema_lib)
  if [[ ! -f "$LIB" ]]; then
    echo "self-test: cannot locate state library ($LIB)"; echo "self-test: FAIL"; exit 1
  fi
  if ! _have node || ! _have jq; then
    echo "self-test: node/jq unavailable"; echo "self-test: FAIL"; exit 1
  fi
  export CONV_TREE_STATE_LIB="$LIB"
  export CONV_TREE_SCHEMA_LIB="$SCHEMA"

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
  # number of nodes whose node_id starts with "turn-" (post-fix: MUST be 0 —
  # the rewrite emits items on the ROOT node, never a per-turn node).
  _count_turn_nodes() {
    node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.stdout.write(String(st.snapshot.nodes.filter(function(n){return /^turn-/.test(n.node_id)}).length))}catch(e){process.stdout.write("ERR")}' "$LIB" "$1"
  }
  # does any node have a node whose title matches a regex?
  _node_title_match() {
    node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var re=process.argv[3];process.stdout.write(st.snapshot.nodes.some(function(n){return new RegExp(re).test(n.title||"")})?"Y":"N")}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2"
  }
  # Does the FIRST item of kind $3 carry a details object with a non-empty
  # field named $4 (dotted-path-free top-level key)?  Prints Y/N.
  _item_detail_has() {
    node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var kind=process.argv[3],field=process.argv[4];var hit="N";st.snapshot.nodes.forEach(function(n){(n.items||[]).forEach(function(it){if(hit==="Y")return;if(it.kind!==kind)return;var d=it.details;if(d&&d[field]!=null&&((Array.isArray(d[field])&&d[field].length)||String(d[field]).trim()!==""))hit="Y"})});process.stdout.write(hit)}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2" "$3"
  }
  # Print the text of the first item whose text matches regex $3 (or "" / NONE).
  _item_text_present() {
    node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var re=new RegExp(process.argv[3]);var hit="N";st.snapshot.nodes.forEach(function(n){(n.items||[]).forEach(function(it){if(re.test(String(it.text||"")))hit="Y"})});process.stdout.write(hit)}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2"
  }
  _run_hook() {
    local transcript="$1" sink="$2" sid="$3"
    CONV_TREE_STATE_PATH="$sink" CLAUDE_SESSION_ID="$sid" \
      bash "$SELF" <<<"$(jq -nc --arg p "$transcript" --arg s "$sid" '{transcript_path:$p, session_id:$s}')" >/dev/null 2>&1
    echo $?
  }

  # ---------- ST1: PAUSING marker → SELF-CONTAINED decision on ROOT --------
  local TR1="$TMP/tr1.jsonl" SP1="$TMP/sp1.json"
  _make_transcript "$TR1" "$(printf 'I reviewed the 24 proposals for the R23 launch.\n\nPAUSING: need your call on whether to apply migration m162 to production before the deploy — it drops a legacy column irreversibly.')"
  local RC1; RC1=$(_run_hook "$TR1" "$SP1" "sess-st1")
  _ck "ST1 PAUSING marker → exit 0" "$RC1" "0"
  _ck "ST1 decision-raised emitted" "$(_count_type "$SP1" decision-raised)" "1"
  _ck "ST1 NO 'turn-' noise node (item on root)" "$(_count_turn_nodes "$SP1")" "0"
  _ck "ST1 NO node titled 'Turn N'" "$(_node_title_match "$SP1" '^Turn [0-9]')" "N"
  _ck "ST1 decision item lands in snapshot.nodes[].items[]" "$(_count_items "$SP1" decision)" "1"
  _ck "ST1 item details carry background (memory-trigger)" "$(_item_detail_has "$SP1" decision background)" "Y"
  _ck "ST1 item details carry _category" "$(_item_detail_has "$SP1" decision _category)" "Y"
  _ck "ST1 item details carry the actionable question" "$(_item_detail_has "$SP1" decision question)" "Y"

  # ---------- ST2: idempotency — re-fire same message → no duplication -----
  local RC2; RC2=$(_run_hook "$TR1" "$SP1" "sess-st1")
  _ck "ST2 re-fire same message → exit 0" "$RC2" "0"
  _ck "ST2 decision-raised still 1 (idempotent)" "$(_count_type "$SP1" decision-raised)" "1"
  _ck "ST2 decision items still 1 (idempotent)" "$(_count_items "$SP1" decision)" "1"

  # ---------- ST3: section headers → mixed cards, all self-contained -------
  local TR3="$TMP/tr3.jsonl" SP3="$TMP/sp3.json"
  _make_transcript "$TR3" "$(printf 'Progress update on the demo-org launch prep.\n\nDecisions for Misha:\n- Approve the production DB password rotation before launch\n- Choose squash vs merge for PR #476\n\nQuestions for Misha:\n- Which Twilio number should the demo campaign use?\n\nAction items for Misha:\n- Rotate the production API key in Vercel settings\n\nDONE: shipped the turn-emit hook (commit abc1234)')"
  local RC3; RC3=$(_run_hook "$TR3" "$SP3" "sess-st3")
  _ck "ST3 section headers → exit 0" "$RC3" "0"
  _ck "ST3 two decisions" "$(_count_items "$SP3" decision)" "2"
  _ck "ST3 one question" "$(_count_items "$SP3" question)" "1"
  _ck "ST3 one action" "$(_count_items "$SP3" action)" "1"
  _ck "ST3 NO turn-noise node" "$(_count_turn_nodes "$SP3")" "0"
  _ck "ST3 question item carries background" "$(_item_detail_has "$SP3" question background)" "Y"
  _ck "ST3 action item carries the_ask" "$(_item_detail_has "$SP3" action the_ask)" "Y"

  # ---------- ST4: enumerated options, no header, no marker → decision -----
  local TR4="$TMP/tr4.jsonl" SP4="$TMP/sp4.json"
  _make_transcript "$TR4" "$(printf 'For the cherry-pick conflict on the rule file, which do you prefer?\n\nA) Take ours\nB) Take theirs\nC) Hand-resolve to union')"
  local RC4; RC4=$(_run_hook "$TR4" "$SP4" "sess-st4")
  _ck "ST4 enumerated options → exit 0" "$RC4" "0"
  _ck "ST4 decision card from enumerated options" "$(_count_items "$SP4" decision)" "1"
  _ck "ST4 decision carries background" "$(_item_detail_has "$SP4" decision background)" "Y"

  # ---------- ST5: plain prose, nothing actionable → NO cards -------------
  local TR5="$TMP/tr5.jsonl" SP5="$TMP/sp5.json"
  _make_transcript "$TR5" "I read the file and confirmed the handler signature is unchanged. Continuing to the next step."
  local RC5; RC5=$(_run_hook "$TR5" "$SP5" "sess-st5")
  _ck "ST5 plain prose → exit 0" "$RC5" "0"
  if [[ ! -f "$SP5" ]]; then
    echo "PASS: ST5 no state file written (nothing to surface)"; pass=$((pass+1))
  else
    _ck "ST5 zero decision-raised" "$(_count_type "$SP5" decision-raised)" "0"
  fi

  # ---------- ST6: BLOCKED marker → self-contained action card ------------
  local TR6="$TMP/tr6.jsonl" SP6="$TMP/sp6.json"
  _make_transcript "$TR6" "$(printf 'Investigated the deploy failure on the demo org.\n\nBLOCKED: e2e suite needs the DB password in .env.local which is unset here — provide it or a sandbox with it set.')"
  local RC6; RC6=$(_run_hook "$TR6" "$SP6" "sess-st6")
  _ck "ST6 BLOCKED marker → exit 0" "$RC6" "0"
  _ck "ST6 action-added from BLOCKED" "$(_count_items "$SP6" action)" "1"
  _ck "ST6 action carries background" "$(_item_detail_has "$SP6" action background)" "Y"

  # ---------- ST7: new turn (different message) → fresh distinct card ------
  local TR7="$TMP/tr7.jsonl"
  cp "$TR1" "$TR7"
  printf '%s\n' "$(jq -nc '{role:"user", content:"and the next?"}')" >>"$TR7"
  printf '%s\n' "$(jq -nc '{role:"assistant", content:"Looked at the R23 reframe.\n\nPAUSING: also need your decision on the R23 reframe vs leaving the open/close times feature as-is."}')" >>"$TR7"
  local RC7; RC7=$(_run_hook "$TR7" "$SP1" "sess-st1")
  _ck "ST7 new turn → exit 0" "$RC7" "0"
  _ck "ST7 second turn adds a distinct decision (total 2)" "$(_count_type "$SP1" decision-raised)" "2"
  _ck "ST7 still NO turn-noise nodes" "$(_count_turn_nodes "$SP1")" "0"

  # ---------- ST8: no transcript → silent no-op ----------------------------
  local RC8
  RC8=$(WORKSTREAMS_TURN_EMIT_DISABLE=0 bash "$SELF" <<<'{"session_id":"st8"}' >/dev/null 2>&1; echo $?)
  _ck "ST8 missing transcript → exit 0" "$RC8" "0"

  # ---------- ST9: DISABLE escape hatch → no emit --------------------------
  local TR9="$TMP/tr9.jsonl" SP9="$TMP/sp9.json"
  _make_transcript "$TR9" "PAUSING: should we ship feature X or feature Y first?"
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
  _make_transcript "$TR10" "PAUSING: decide on whether to ship the thing now or wait."
  local RC10
  RC10=$(CONV_TREE_STATE_LIB="$TMP/does-not-exist.js" CONV_TREE_STATE_PATH="$TMP/sp10.json" CLAUDE_SESSION_ID="st10" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR10" '{transcript_path:$p, session_id:"st10"}')" >/dev/null 2>&1; echo $?)
  _ck "ST10 facade-down → exit 0 (never blocks)" "$RC10" "0"

  # ---------- ST11 (REQUIRED a): FRAGMENT / turn-noise → NOT emitted -------
  # The exact garbage shapes Misha saw: a "Turn N" header + a mid-sentence
  # fragment beginning with an escaped quote + a leading-paren continuation.
  # None of these is a clean, self-contained item → ZERO cards, NO state file.
  local TR11="$TMP/tr11.jsonl" SP11="$TMP/sp11.json"
  _make_transcript "$TR11" "$(printf 'Turn 2229\n\n\\\" decisions (the class it missed) and **hard-blocks** if no card got emitted. Self-test passes.\n\n)\\\", \\\"TWLO-006 launch-blocker\\\", \\\"Phase 6 plan')"
  local RC11; RC11=$(_run_hook "$TR11" "$SP11" "sess-st11")
  _ck "ST11 fragment/turn-noise → exit 0" "$RC11" "0"
  if [[ ! -f "$SP11" ]]; then
    echo "PASS: ST11 fragment/turn-noise → NO state file (nothing emitted)"; pass=$((pass+1))
    echo "PASS: ST11 fragment/turn-noise → zero items (NO state file)"; pass=$((pass+1))
  else
    _ck "ST11 fragment/turn-noise → zero decision-raised" "$(_count_type "$SP11" decision-raised)" "0"
    _ck "ST11 fragment/turn-noise → zero action items" "$(_count_items "$SP11" action)" "0"
  fi
  _ck "ST11 fragment/turn-noise → NO 'turn-' node" "$(_count_turn_nodes "$SP11")" "0"

  # ---------- ST12 (REQUIRED b): real decision → FULL self-contained card --
  # A genuine decision with background + the question. Verify the emitted item
  # carries the memory-trigger background AND the actionable question (the
  # full-content contract). Options/recommendation come from the FENCE path
  # (decision-context-gate); the turn-emit path guarantees background + the
  # actionable field, which is what makes a turn-extracted card self-contained.
  local TR12="$TMP/tr12.jsonl" SP12="$TMP/sp12.json"
  _make_transcript "$TR12" "$(printf 'I finished the migration audit for the R23 launch on the demo org.\n\nPAUSING: I need your decision on whether to apply migration m162 to production now, or wait for the nightly backup window first — m162 drops the legacy open_hours column irreversibly, so there is no rollback once it runs.')"
  local RC12; RC12=$(_run_hook "$TR12" "$SP12" "sess-st12")
  _ck "ST12 real decision → exit 0" "$RC12" "0"
  _ck "ST12 one decision emitted" "$(_count_items "$SP12" decision)" "1"
  _ck "ST12 decision text is the full ask (not a fragment)" "$(_item_text_present "$SP12" 'migration m162')" "Y"
  _ck "ST12 decision carries background (memory-trigger)" "$(_item_detail_has "$SP12" decision background)" "Y"
  _ck "ST12 decision carries the actionable question" "$(_item_detail_has "$SP12" decision question)" "Y"
  _ck "ST12 decision carries _category" "$(_item_detail_has "$SP12" decision _category)" "Y"
  _ck "ST12 decision carries links pointer" "$(_item_detail_has "$SP12" decision links)" "Y"
  _ck "ST12 NO turn-noise node" "$(_count_turn_nodes "$SP12")" "0"

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
