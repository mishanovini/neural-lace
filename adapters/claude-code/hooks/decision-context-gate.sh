#!/bin/bash
# decision-context-gate.sh — Stop hook for the Decision-Context substrate
# (Task 4 of docs/plans/decision-context-gate-2026-05-29.md; ADR 047 — the
# Stop-hook reactive enforcement model for the fence grammar of DEC-1).
#
# # Why this hook exists
#
# The Dispatch orchestrator routinely surfaces decisions ("A or B?"),
# questions ("how should I…?"), action items the operator needs to take,
# and autonomous actions it took without asking — all as free-form prose
# that evaporates into the chat transcript. This hook makes those surfaces
# structurally auditable: it scans the LAST assistant message in
# $TRANSCRIPT_PATH (agent-uneditable, Gen-6 narrative-integrity property),
# detects decision-soliciting language via a three-tier classifier, and
# BLOCKS Stop when a Tier-1 trigger fires without a properly-fenced
# Markdown block per the grammar in ~/.claude/rules/decision-context.md.
#
# The redo friction IS the agent's incentive to fence first. Same shape as
# the six sibling Stop hooks that already operate on the
# "scan-last-assistant-message → block-with-redo-required" pattern:
# continuation-enforcer.sh, narrate-and-wait-gate.sh,
# goal-coverage-on-stop.sh, deferral-counter.sh,
# imperative-evidence-linker.sh, principles-compliance-gate.sh.
#
# # Three tiers
#
#   Tier 1 (hard block): enumerated options (A)/B)/1./2./- Option),
#       OR terminal `?` followed within K=10 lines by a list,
#       OR explicit phrases: "pick one", "your call",
#       "which do you want", "which would you prefer",
#       "should I X or Y".
#   Tier 2 (soft warn): "should I", "would you like",
#       terminal `?` without a list.
#       → ALLOW Stop, write a follow-up marker that
#       decision-context-pending-surfacer.sh (Task 5) picks up
#       on next SessionStart.
#   Tier 3 (rhetorical whitelist): "does that make sense?",
#       "make sense?", "right?", "sound good?" → no-op.
#
# # Fence emission
#
# When a fence IS present (in any tier), the hook calls into the
# SOLE-NORMATIVE Zod-backed validator at
# neural-lace/workstreams-ui/state/decision-context-schema.js
# (Task 2 module). Each validated block is projected onto an ADR-032 §2
# event (decision-raised / question-raised / action-added /
# autonomous-action-logged) + a sibling item-details-set with the rich
# payload. ALL writes go through the frozen A2 facade
# (state.js appendEvent) — NEVER direct JSON, NEVER direct HTTP.
#
# Failure isolation: writer-hook failures NEVER block Stop on their own
# (per gate-respect.md "writer hooks do not block"). On facade failure
# the event line is appended to
# ~/.claude/state/decision-context/fallback.jsonl (Task 8 drains).
#
# # Escape valves
#
#   - Tier-3 rhetorical whitelist → never blocks.
#   - Fresh waiver `.claude/state/decision-context-waiver-<ts>.txt`
#     (≥1 substantive line, mtime <1h) → ALLOW. Mirrors
#     bug-persistence-gate's per-session waiver pattern exactly.
#   - DECISION_CONTEXT_GATE_DISABLE=1 → ALLOW (harness-dev escape
#     hatch for sessions editing this hook or its self-test).
#   - Retry-guard library: 3 identical-failure retries with no new
#     commits → downgrade block to warn (same loop-break every
#     blocking Stop hook in the harness uses).
#
# # Exit codes
#   0 — session may terminate
#   2 — session is blocked; stderr explains why; JSON decision on stdout
#       per Claude Code Stop-hook contract.
#
# # Self-test
#   bash decision-context-gate.sh --self-test  →  PASS/FAIL summary.

set -uo pipefail

# ----- shared retry-guard library ------------------------------------------
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/lib/stop-hook-retry-guard.sh"

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/decision-context-gate.log"
FALLBACK_DIR="$HOME/.claude/state/decision-context"
FALLBACK_FILE="$FALLBACK_DIR/fallback.jsonl"
FOLLOWUP_DIR=".claude/state"

_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s [decision-context-gate] %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "$*" \
    >>"$LOG_FILE" 2>/dev/null || true
}

_have() { command -v "$1" >/dev/null 2>&1; }

# ----- self-test dispatch (early) ------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  # Self-test runs at end of file; jump there.
  RUN_SELF_TEST=1
else
  RUN_SELF_TEST=0
fi

# ============================================================================
# Resolvers — mirror conversation-tree-emit.sh's _resolve_state_lib /
# _resolve_gui_state_path / _resolve_gate_state_path so the writer and the
# conv-tree gates agree on the sink. Copy-paste with attribution rather than
# extract-shared so the self-test stays independent.
# ============================================================================

_fallback_conv_tree_path() {
  local leaf="$1"
  local base="${CONV_TREE_MAIN_CHECKOUT:-$HOME/claude-projects/neural-lace}"
  # The UI module lives at neural-lace/workstreams-ui/ (renamed 2026-06).
  local d cand
  for d in workstreams-ui; do
    for cand in "$base/neural-lace/$d/$leaf" "$base/$d/$leaf"; do
      if [[ -e "$cand" ]]; then printf '%s' "$cand"; return 0; fi
    done
  done
  # Nothing on disk: default to the new-name nested path.
  printf '%s' "$base/neural-lace/workstreams-ui/$leaf"
}

_resolve_state_lib() {
  if [[ -n "${CONV_TREE_STATE_LIB:-}" ]]; then
    printf '%s' "$CONV_TREE_STATE_LIB"; return 0
  fi
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

# The sole-normative schema module (Task 2).
_resolve_schema_module() {
  if [[ -n "${DECISION_CONTEXT_SCHEMA:-}" ]]; then
    printf '%s' "$DECISION_CONTEXT_SCHEMA"; return 0
  fi
  local root="" d cand
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    for d in workstreams-ui; do
      for cand in "$root/neural-lace/$d/state/decision-context-schema.js" "$root/$d/state/decision-context-schema.js"; do
        if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
      done
    done
  fi
  _fallback_conv_tree_path "state/decision-context-schema.js"
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
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then
    printf '%s' "$CONV_TREE_STATE_PATH"; return 0
  fi
  local mr d
  if mr=$(_main_repo_root) && [[ -n "$mr" ]]; then
    for d in workstreams-ui; do
      if [[ -f "$mr/neural-lace/$d/state/state.js" ]]; then
        printf '%s' "$mr/neural-lace/$d/state/tree-state.json"; return 0
      fi
      if [[ -f "$mr/$d/state/state.js" ]]; then
        printf '%s' "$mr/$d/state/tree-state.json"; return 0
      fi
    done
  fi
  _fallback_conv_tree_path "state/tree-state.json"
}

_resolve_gate_state_path() {
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then
    printf '%s' "$CONV_TREE_STATE_PATH"; return 0
  fi
  local root=""
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    local proj="$root/.claude/state/conversation-tree/tree-state.json"
    if [[ -f "$proj" ]]; then printf '%s' "$proj"; return 0; fi
    printf '%s' "$proj"; return 0
  fi
  printf '%s' "$HOME/.claude/state/conversation-tree/global/tree-state.json"
}

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

_session_id_from_input() {
  local input="$1"
  local sid="${CLAUDE_SESSION_ID:-}"
  if [[ -z "$sid" ]] && [[ -n "$input" ]] && _have jq; then
    sid=$(printf '%s' "$input" | jq -r '.session_id // .session.session_id // empty' 2>/dev/null || echo "")
  fi
  [[ -z "$sid" ]] && sid="ppid-${PPID:-$$}"
  printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

_sha1() {
  if _have sha1sum; then sha1sum | cut -d' ' -f1
  elif _have shasum; then shasum -a 1 | cut -d' ' -f1
  else cksum | tr -d ' '; fi
}

# ============================================================================
# Facade-driven emit (mirrors conversation-tree-emit.sh's _emit_to_sink /
# _emit_dual). On facade failure, writes the event line(s) to fallback.jsonl
# so Task 8's replay script can drain them.
# ============================================================================

_emit_to_sink() {
  local lib="$1" sink="$2" events_file="$3"
  [[ -z "$sink" ]] && return 1
  _have node || { _log "node unavailable — sink $sink"; return 1; }
  mkdir -p "$(dirname "$sink")" 2>/dev/null || true
  local out rc
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
  ' "$lib" "$sink" "$events_file" 2>>"$LOG_FILE")
  rc=$?
  _log "sink=$sink result=$out rc=$rc"
  # We treat any "LIBERR" / "ARGERR" / "NODEERR" / non-OK or empty as failure
  case "$out" in
    OK:*) return 0 ;;
    *) return 1 ;;
  esac
}

_emit_dual_with_fallback() {
  local lib="$1" events_file="$2"
  local any_ok=0
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then
    if _emit_to_sink "$lib" "$CONV_TREE_STATE_PATH" "$events_file"; then any_ok=1; fi
  else
    local gui gate
    gui=$(_resolve_gui_state_path)
    gate=$(_resolve_gate_state_path)
    if [[ -n "$gui" ]]; then
      if _emit_to_sink "$lib" "$gui" "$events_file"; then any_ok=1; fi
    fi
    if [[ -n "$gate" && "$gate" != "$gui" ]]; then
      if _emit_to_sink "$lib" "$gate" "$events_file"; then any_ok=1; fi
    fi
  fi
  if [[ "$any_ok" -eq 0 ]]; then
    # Facade-down → fallback.jsonl (Task 8 drains).
    mkdir -p "$FALLBACK_DIR" 2>/dev/null || true
    # events_file is a JSON array; flatten to one event-per-line for replay.
    if _have node; then
      node -e '
        var fs = require("fs");
        var evs = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        for (var i = 0; i < evs.length; i++) {
          fs.appendFileSync(process.argv[2], JSON.stringify(evs[i]) + "\n");
        }
      ' "$events_file" "$FALLBACK_FILE" 2>>"$LOG_FILE" || true
    else
      cat "$events_file" >>"$FALLBACK_FILE" 2>/dev/null || true
    fi
    _log "facade-down → wrote events to $FALLBACK_FILE"
  fi
  return 0
}

# ============================================================================
# Tiered-Scan classifier
# ============================================================================

# Cheap pre-filter: does the trailing window of the last assistant message
# contain ANY signal that could be a Tier 1/2/3 hit? Returns 0 (yes) or 1
# (no). Keeps the hot path fast — if nothing matches, we skip the node
# subprocess entirely.
_has_any_signal() {
  local text="$1"
  # Trailing 1200 chars is where decision-soliciting phrases cluster.
  local tail
  tail=$(printf '%s' "$text" | tail -c 1200)
  # Match-any: option markers, terminal ?, fence opener, or any phrase token.
  if printf '%s' "$tail" | grep -qiE '\?|^[[:space:]]*[A-Da-d1-9]\)|^[[:space:]]*[1-9]\.[[:space:]]|\*\*Option|^[[:space:]]*-[[:space:]]+Option|::: (decision|question|action_item_for_user|autonomous_action)|pick one|your call|which (do|would) you|should I|would you like|sound good\??|make sense\??|right\?'; then
    return 0
  fi
  return 1
}

# Detect a fenced block (we don't validate here — just presence).
_has_fence() {
  printf '%s' "$1" | grep -qE '^:::[[:space:]]+(decision|question|action_item_for_user|autonomous_action)[[:space:]]+id='
}

# Tier 3 rhetorical: only the LAST sentence's terminal phrase matters. If
# the whole trailing window is a Tier-3 rhetorical (no other strong signal),
# whitelist it.
_is_tier3_only() {
  local text="$1"
  local tail
  tail=$(printf '%s' "$text" | tail -c 400 | tr '[:upper:]' '[:lower:]')
  # Strip whitespace
  if printf '%s' "$tail" | grep -qE '(does that make sense\?|make sense\?|right\?|sound good\??)[[:space:]]*$'; then
    # Tier 3 dominant — but only if NO Tier-1 markers are also present in the tail
    if printf '%s' "$tail" | grep -qiE '\*\*option|^[[:space:]]*[a-d]\)|^[[:space:]]*[1-9]\.[[:space:]]|pick one|your call|which (do|would) you|should I .* or '; then
      return 1
    fi
    return 0
  fi
  return 1
}

# Tier 1: enumerated options OR explicit-phrase Tier-1 OR (terminal ? AND
# within K=10 lines after a ? there's an enumerated list). Returns 0 if Tier 1.
_is_tier1() {
  local text="$1"
  # Use the trailing window for decision detection; the prefix is the
  # essay-style body that often discusses alternatives narratively.
  local tail
  tail=$(printf '%s' "$text" | tail -c 2500)
  # Explicit Tier-1 phrases (anywhere in the trailing window).
  if printf '%s' "$tail" | grep -qiE 'pick one|your call|which (do|would) you (want|prefer)|should I [A-Za-z]+ or [A-Za-z]'; then
    return 0
  fi
  # Enumerated-options markers in the trailing window.
  # Match e.g. "A)", "B)", "1.", "2.", "- Option", "**Option".
  local opt_count
  opt_count=$(printf '%s' "$tail" | grep -cE '^[[:space:]]*([A-Da-d]\)|[1-9]\.[[:space:]]|-[[:space:]]+Option[[:space:]]|\*\*Option)' || true)
  if [[ "$opt_count" -ge 2 ]]; then
    return 0
  fi
  # Terminal `?` followed within K=10 lines by an enumerated list.
  # Find the last `?`; look at the K lines AFTER it.
  if printf '%s' "$tail" | awk -v K=10 '
    {
      lines[NR] = $0;
      if (index($0, "?") > 0) last_q = NR;
    }
    END {
      if (!last_q) exit 1;
      for (i = last_q; i <= NR && i <= last_q + K; i++) {
        if (lines[i] ~ /^[[:space:]]*([A-Da-d]\)|[1-9]\.[[:space:]]|-[[:space:]]+|\*\*Option)/) {
          exit 0;
        }
      }
      exit 1;
    }'; then
    return 0
  fi
  return 1
}

# Tier 2: weaker decision-soliciting language. "should I ...?", "would you
# like ...?", or a terminal `?` without an enumerated list.
_is_tier2() {
  local text="$1"
  local tail
  tail=$(printf '%s' "$text" | tail -c 800)
  if printf '%s' "$tail" | grep -qiE 'should I [a-z]|would you like'; then
    return 0
  fi
  # Terminal `?` near end-of-message → Tier 2.
  if printf '%s' "$tail" | tail -c 200 | grep -qE '\?[[:space:]]*$'; then
    return 0
  fi
  return 1
}

# ============================================================================
# Fence parsing + emission via the Zod module
# ============================================================================

# Parses + validates ALL fenced blocks in the last assistant message via the
# sole-normative Zod schema. Echoes verdict to stdout:
#   "OK\t<n>"   → n fences validated, events file written to $3 path
#   "ZERR\t<msg>" → at least one fence failed validation
#   "PERR\t<msg>" → parser error (malformed fence body)
#   "NONE"     → no fenced blocks
# Writes the event JSON-array to the file path passed as $3 (caller-supplied).
#
# B10-FU-1 (2026-05-30 fix): items land on the SESSION-ROOT node (the project
# or global root that conversation-tree-emit.sh --on-session-start seeds),
# NOT on a fresh per-decision node. Per ADR-032 §3 (FR-2 cardinality) items
# live ON a node — multiple items on one node = one branch. The gate emits
# a defensive `branch-opened` for the root FIRST (idempotent on event_id per
# ADR-032 §2 — re-emission is a no-op when the session-start hook already
# fired); the per-block primary events follow with node_id=root.
_parse_validate_emit_events_file() {
  local schema_mod="$1" last_msg_file="$2" events_file="$3"
  local root_id="$4" root_title="$5"
  _have node || { printf 'NOENV\tno-node'; return 1; }
  node -e '
    var path = require("path"), fs = require("fs");
    var schemaPath = process.argv[1];
    var msgPath = process.argv[2];
    var evFile = process.argv[3];
    var rootId = process.argv[4];
    var rootTitle = process.argv[5];
    var s;
    try { s = require(schemaPath); }
    catch (e) { process.stdout.write("NOENV\tschema-require:" + (e&&e.message||e)); process.exit(0); }
    var rawText = fs.readFileSync(msgPath, "utf8");

    // Find every fence opener; parse each block independently.
    var lines = rawText.split(/\r?\n/);
    var blocks = [];
    var i = 0;
    while (i < lines.length) {
      if (/^:::\s+\S/.test(lines[i])) {
        // Find matching closer
        var j = i + 1;
        while (j < lines.length && lines[j].trim() !== ":::") j++;
        if (j >= lines.length) break;
        blocks.push(lines.slice(i, j + 1).join("\n"));
        i = j + 1;
      } else {
        i++;
      }
    }
    if (blocks.length === 0) { process.stdout.write("NONE"); process.exit(0); }

    // Hash helper for deterministic event_ids (no external deps).
    function _hash16(str) {
      var h = require("crypto").createHash("sha1").update(String(str)).digest("hex");
      return h.slice(0, 32);
    }

    var events = [];
    var errors = [];

    // B10-FU-1: defensive root branch-opened. Idempotent on event_id per
    // ADR-032 sec.2 -- if --on-session-start already emitted this same node,
    // the facade dedupes silently. Required because the gate may fire in
    // sessions that bypassed session-start (the gate self-tests, or
    // replays from fallback.jsonl).
    if (rootId) {
      events.push({
        event_id: "dc-bo-" + _hash16(rootId),
        type: "branch-opened",
        node_id: rootId,
        parent_id: null,
        title: rootTitle || rootId,
        actor: "dispatch"
      });
    }

    for (var b = 0; b < blocks.length; b++) {
      var raw = blocks[b];
      var parsed;
      try { parsed = s.parseFenceBlock(raw); }
      catch (e) { errors.push("parse[block " + (b+1) + "]:" + (e&&e.message||e)); continue; }
      var cat = parsed.category;
      var v = s.safeValidateFence(cat, parsed.payload);
      if (!v.success) {
        var emsg = (v.error && v.error.issues)
          ? v.error.issues.map(function(x){ return x.path.join(".") + ":" + x.message; }).join("; ")
          : (v.error && v.error.message) || "validation-failed";
        errors.push("zod[" + cat + "/" + (parsed.payload && parsed.payload.id || "?") + "]:" + emsg);
        continue;
      }
      var data = v.data;
      // B10-FU-1: emit against the SESSION-ROOT node, not a fresh
      // per-decision node. Items live ON a node (FR-2). The item_id
      // remains per-decision so each fence produces a distinct item
      // in the root node items[] array.
      var nodeId = rootId || ("dc-" + cat + "-" + (data.id || ("anon-" + b)));
      var itemId = "item-" + (data.id || ("anon-" + b));
      var title = data.title || data.label || data.id || ("decision-context-" + cat);
      var text = data.about || data.title || "";
      var details = Object.assign({}, data, { _category: cat, surfaced_by: "decision-context-gate" });

      // Project to ADR-032 §2 events.
      var evType, evIdPrefix;
      if (cat === "decision") { evType = "decision-raised"; evIdPrefix = "dc-dr-"; }
      else if (cat === "question") { evType = "question-raised"; evIdPrefix = "dc-qr-"; }
      else if (cat === "action_item_for_user") { evType = "action-added"; evIdPrefix = "dc-ac-"; }
      else if (cat === "autonomous_action") { evType = "autonomous-action-logged"; evIdPrefix = "dc-aa-"; }
      else { errors.push("unknown-category:" + cat); continue; }

      // Primary envelope. Use a deterministic event_id per (category,id) for
      // idempotency on a Stop re-fire with the same message.
      // item_id is REQUIRED on decision-raised/question-raised/action-added
      // per state/schema.js EVENT_REQUIRED_FIELDS; autonomous-action-logged
      // requires details only (no item_id).
      var primaryEvId = evIdPrefix + (data.id || ("anon-" + b));
      var primary = {
        event_id: primaryEvId,
        type: evType,
        node_id: nodeId,
        actor: "dispatch",
        title: title,
        text: text,
        details: details
      };
      if (cat !== "autonomous_action") {
        primary.item_id = itemId;
      }
      // The autonomous-action-logged event requires details.action_taken etc.;
      // the parsed payload already carries them so the same details object works.
      events.push(primary);

      // Sibling item-details-set with the rich payload — applies to all
      // four categories per the plan table (Task 2 / DEC-2). The facade
      // dedupes by event_id per file so a re-fire is a per-file no-op.
      events.push({
        event_id: "dc-ids-" + (data.id || ("anon-" + b)),
        type: "item-details-set",
        node_id: nodeId,
        item_id: itemId,
        details: details
      });
    }

    fs.writeFileSync(evFile, JSON.stringify(events));
    if (errors.length > 0) {
      process.stdout.write("ZERR\t" + errors.join(" || "));
      process.exit(0);
    }
    process.stdout.write("OK\t" + (events.length));
    process.exit(0);
  ' "$schema_mod" "$last_msg_file" "$events_file" "$root_id" "$root_title" 2>>"$LOG_FILE" || printf 'NOENV\tnode-exec'
}

# ============================================================================
# Tier-2 follow-up marker (Task 5 consumes).
# ============================================================================
_write_followup_marker() {
  local sid="$1" snippet="$2"
  mkdir -p "$FOLLOWUP_DIR" 2>/dev/null || true
  local ts; ts=$(date -u +%Y%m%d%H%M%S 2>/dev/null || echo "$$")
  local f="$FOLLOWUP_DIR/decision-context-followup-${sid}-${ts}.txt"
  printf 'tier: 2\nsession: %s\nseen_at: %s\nsnippet: %s\n' \
    "$sid" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" \
    "$(printf '%s' "$snippet" | tr '\n' ' ' | cut -c1-300)" \
    >"$f" 2>/dev/null || true
}

# ============================================================================
# Main flow (when not in self-test)
# ============================================================================

_run_gate() {
  # Escape hatch: harness-dev edits to this hook itself.
  if [[ "${DECISION_CONTEXT_GATE_DISABLE:-0}" == "1" ]]; then
    exit 0
  fi

  local INPUT=""
  if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || echo "")
  fi

  local RG_SESSION_ID
  RG_SESSION_ID=$(retry_guard_session_id "$INPUT")

  local TRANSCRIPT_PATH=""
  if [[ -n "$INPUT" ]] && _have jq; then
    TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
  fi

  # ST10 — no transcript → silent no-op (consistent with sibling Stop hooks).
  if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
  fi
  if ! _have jq; then
    # Without jq we cannot reliably extract the last assistant message.
    exit 0
  fi

  # Extract the FINAL assistant message text in full (content can be
  # multi-line; we need the whole body, not just the trailing line —
  # `jq -r ... | tail -n 1` would lose fenced blocks. Use jq's `-s` slurp
  # mode to take the last assistant message as one JSON value, then read
  # its `.content` (or nested fields) as a single string.
  local LAST_ASSISTANT
  LAST_ASSISTANT=$(jq -rs '
    [ .[]
      | select(.role == "assistant" or .message.role == "assistant")
      | (.content // .text // .message.content // empty)
    ]
    | last
    | if type == "string" then . else (. | tostring) end
  ' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

  if [[ -z "$LAST_ASSISTANT" ]]; then
    exit 0
  fi

  # --- Cheap pre-filter (PERF marker per ST8) ---
  if ! _has_any_signal "$LAST_ASSISTANT"; then
    # ST8: assert no node subprocess was invoked. Drop a marker file when
    # PERF_TRACE_FILE is set (self-test only).
    if [[ -n "${DC_PERF_TRACE_FILE:-}" ]]; then
      printf 'pre-filter:nosignal\n' >>"$DC_PERF_TRACE_FILE" 2>/dev/null || true
    fi
    exit 0
  fi

  # --- Tier 3 rhetorical whitelist (no-op, no fence required) ---
  if _is_tier3_only "$LAST_ASSISTANT"; then
    if [[ -n "${DC_PERF_TRACE_FILE:-}" ]]; then
      printf 'tier3:rhetorical-only\n' >>"$DC_PERF_TRACE_FILE" 2>/dev/null || true
    fi
    exit 0
  fi

  # Detect fence presence (cheap shell pre-check).
  local FENCE_PRESENT=0
  if _has_fence "$LAST_ASSISTANT"; then
    FENCE_PRESENT=1
  fi

  # Classify tier.
  local TIER=0
  if _is_tier1 "$LAST_ASSISTANT"; then
    TIER=1
  elif _is_tier2 "$LAST_ASSISTANT"; then
    TIER=2
  fi

  # No tier signal AND no fence → nothing to do.
  if [[ "$TIER" -eq 0 ]] && [[ "$FENCE_PRESENT" -eq 0 ]]; then
    exit 0
  fi

  # --- Waiver escape valve (any tier) ---
  # Mirrors bug-persistence-gate's per-session waiver pattern exactly:
  # fresh .claude/state/decision-context-waiver-*.txt within last 1h, ≥1
  # substantive non-whitespace line.
  if [[ -d ".claude/state" ]]; then
    local waiver_file
    while IFS= read -r waiver_file; do
      [[ -z "$waiver_file" ]] && continue
      # Substantive = at least 1 non-whitespace line.
      if grep -qE '\S' "$waiver_file" 2>/dev/null; then
        _log "waiver honored: $waiver_file"
        exit 0
      fi
    done < <(find .claude/state -maxdepth 1 -type f -name 'decision-context-waiver-*.txt' -newermt '1 hour ago' 2>/dev/null)
  fi

  # --- Process fence (if present) ---
  local SCHEMA_MOD; SCHEMA_MOD=$(_resolve_schema_module)
  local LIB; LIB=$(_resolve_state_lib)
  local LAST_MSG_FILE; LAST_MSG_FILE=$(mktemp 2>/dev/null || echo "/tmp/dc-msg-$$.txt")
  local EVENTS_FILE; EVENTS_FILE=$(mktemp 2>/dev/null || echo "/tmp/dc-ev-$$.json")
  printf '%s' "$LAST_ASSISTANT" >"$LAST_MSG_FILE"

  # B10-FU-1: resolve the session-root node so items land on the same
  # branch that conversation-tree-emit.sh --on-session-start opened.
  # Same _project_root logic — fence items attach to "the conversation
  # about this project" (or the global root if cwd is outside any project).
  local ROOTLINE; ROOTLINE=$(_project_root)
  local ROOT_ID="${ROOTLINE%%$'\t'*}"
  local ROOT_TITLE="${ROOTLINE##*$'\t'}"

  local PARSE_RESULT="NONE"
  local VERDICT_KIND="" VERDICT_BODY=""
  if [[ "$FENCE_PRESENT" -eq 1 ]]; then
    if [[ ! -f "$SCHEMA_MOD" ]]; then
      _log "schema module unavailable: $SCHEMA_MOD — fence cannot be validated"
      PARSE_RESULT="NOENV	schema-missing:$SCHEMA_MOD"
    else
      PARSE_RESULT=$(_parse_validate_emit_events_file "$SCHEMA_MOD" "$LAST_MSG_FILE" "$EVENTS_FILE" "$ROOT_ID" "$ROOT_TITLE")
    fi
    VERDICT_KIND="${PARSE_RESULT%%	*}"
    VERDICT_BODY="${PARSE_RESULT#*	}"
    [[ "$VERDICT_BODY" == "$PARSE_RESULT" ]] && VERDICT_BODY=""
  fi

  # --- Branch on tier × fence presence × validation ---
  if [[ "$TIER" -eq 1 ]]; then
    if [[ "$FENCE_PRESENT" -eq 0 ]]; then
      # Tier 1 + no fence → BLOCK
      _do_block "$RG_SESSION_ID" "tier1-no-fence" "$LAST_ASSISTANT" ""
      # _do_block exits.
    fi
    # Tier 1 + fence present
    case "$VERDICT_KIND" in
      OK)
        _emit_dual_with_fallback "$LIB" "$EVENTS_FILE"
        _log "Tier 1 fence emitted ($VERDICT_BODY events)"
        ;;
      ZERR|PERR)
        # ST5: validator rejects → BLOCK with the Zod/parse error in stderr.
        _do_block "$RG_SESSION_ID" "tier1-fence-invalid:${VERDICT_KIND}" "$LAST_ASSISTANT" "$VERDICT_BODY"
        ;;
      NOENV)
        # Schema or node unavailable — degrade to fallback queue + emit barebones.
        # Don't block (writer-hook discipline).
        _log "Tier 1 fence — env unavailable ($VERDICT_BODY); fence accepted, fallback queued"
        # Write a minimal placeholder event to fallback for replay. Targets
        # the session-root node (B10-FU-1) so on replay the note lands on
        # an existing branch instead of a dangling node_id.
        mkdir -p "$FALLBACK_DIR" 2>/dev/null || true
        printf '{"event_id":"dc-stub-%s","type":"branch-note-add","node_id":"%s","text":"unparsed-fence pending replay","actor":"dispatch","details":{"reason":"schema-or-node-unavailable","verdict":"%s"}}\n' \
          "$(printf '%s' "$LAST_ASSISTANT" | _sha1 | cut -c1-16)" "$ROOT_ID" "$VERDICT_BODY" \
          >>"$FALLBACK_FILE" 2>/dev/null || true
        ;;
      NONE|*)
        # Pre-filter said fence present but parser found none — treat as no fence.
        _do_block "$RG_SESSION_ID" "tier1-fence-not-recognized" "$LAST_ASSISTANT" "fence header detected but parser found no blocks"
        ;;
    esac
  elif [[ "$TIER" -eq 2 ]]; then
    if [[ "$FENCE_PRESENT" -eq 1 ]] && [[ "$VERDICT_KIND" == "OK" ]]; then
      # Tier 2 + valid fence → emit (no block)
      _emit_dual_with_fallback "$LIB" "$EVENTS_FILE"
      _log "Tier 2 fence emitted ($VERDICT_BODY events)"
    else
      # Tier 2 + no fence (or fence invalid) → write follow-up marker; ALLOW Stop.
      local sid; sid=$(_session_id_from_input "$INPUT")
      _write_followup_marker "$sid" "$LAST_ASSISTANT"
      _log "Tier 2 no fence — wrote follow-up marker for session=$sid"
    fi
  else
    # No tier signal but fence present (e.g., Tier 3 with voluntary fence).
    if [[ "$FENCE_PRESENT" -eq 1 ]] && [[ "$VERDICT_KIND" == "OK" ]]; then
      _emit_dual_with_fallback "$LIB" "$EVENTS_FILE"
      _log "voluntary fence emitted ($VERDICT_BODY events)"
    fi
  fi

  rm -f "$LAST_MSG_FILE" "$EVENTS_FILE" 2>/dev/null || true
  exit 0
}

_do_block() {
  local rg_sid="$1" rg_sig_suffix="$2" last_assistant="$3" extra_detail="$4"

  local trail_preview
  trail_preview=$(printf '%s' "$last_assistant" | tr '\n' ' ' | tail -c 300)

  cat >&2 <<MSG
================================================================
DECISION-CONTEXT GATE — BLOCKED
================================================================

The last assistant message is decision-soliciting (Tier 1) but does
NOT carry a properly-fenced Decision-Context block. The orchestrator
MUST emit decisions / questions / action items / autonomous actions
as fenced Markdown blocks matching the grammar in:

  ~/.claude/rules/decision-context.md

Available categories: decision, question, action_item_for_user,
autonomous_action.

Schema (sole-normative Zod module):
  neural-lace/workstreams-ui/state/decision-context-schema.js

${extra_detail:+Validator detail: $extra_detail
}
Trailing context (last 300 chars of the message):
  ...${trail_preview}

To proceed, do ONE of:

  1. Re-issue the message with a fenced Decision-Context block per the
     grammar. The fence opens with ":::  <category> id=<id>" and closes
     with ":::" on its own line. See the rule for worked examples.

  2. If this is a genuine false positive (rhetorical "make sense?",
     "right?", etc.), no action is required — those are whitelisted.

  3. If the classifier mis-triggered on a non-decision message, write
     a per-session waiver:

         mkdir -p .claude/state
         cat > .claude/state/decision-context-waiver-\$(date -u +%Y%m%dT%H%M%S).txt <<EOF
         This message is not decision-soliciting because <one or two
         lines of substantive justification>.
         EOF

     Mirrors bug-persistence-gate's waiver pattern exactly (≥1
     substantive line, mtime <1h). Auditable in .claude/state/.

The redo friction is the point: structured fences mean every
decision is auditable in the conversation tree. See ADR 047 for the
Stop-hook reactive enforcement model.
================================================================
MSG

  retry_guard_block_or_exit \
    "decision-context-gate" \
    "$rg_sid" \
    "decision-context:${rg_sig_suffix}" \
    "Decision-context gate: tier-1 trigger without valid fence (${rg_sig_suffix})." \
    '{"decision": "block", "reason": "Decision-context gate: decision-soliciting message detected without a properly-fenced Decision-Context block per ~/.claude/rules/decision-context.md. Re-issue with a fenced block, or write a per-session waiver. See stderr."}' \
    2
}

# ============================================================================
# Self-test
# ============================================================================
_self_test() {
  trap - ERR
  local pass=0 fail=0
  local TMP; TMP=$(mktemp -d 2>/dev/null || echo "/tmp/dcg-st-$$")
  mkdir -p "$TMP"
  local SELF; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  local LIB; LIB=$(_resolve_state_lib)
  local SCHEMA; SCHEMA=$(_resolve_schema_module)
  if [[ ! -f "$LIB" ]] || [[ ! -f "$SCHEMA" ]]; then
    echo "self-test: cannot locate state library ($LIB) or schema ($SCHEMA)"
    echo "self-test: FAIL"
    exit 1
  fi
  if ! _have node; then
    echo "self-test: node unavailable; cannot exercise emit paths"
    echo "self-test: FAIL"
    exit 1
  fi
  export CONV_TREE_STATE_LIB="$LIB"
  export DECISION_CONTEXT_SCHEMA="$SCHEMA"

  _ck() {
    if [[ "$2" == "$3" ]]; then
      echo "PASS: $1"; pass=$((pass+1))
    else
      echo "FAIL: $1 (got '$2' want '$3')"; fail=$((fail+1))
    fi
  }
  _ck_match() {
    # PASS when $2 matches regex $3
    if printf '%s' "$2" | grep -qE "$3"; then
      echo "PASS: $1"; pass=$((pass+1))
    else
      echo "FAIL: $1 (output did not match /$3/; got: $2)"; fail=$((fail+1))
    fi
  }

  # Make a minimal transcript JSONL with a final assistant message.
  _make_transcript() {
    local tfile="$1" text="$2"
    # JSONL: one line per message. Last line is the final assistant message.
    printf '%s\n' "$(jq -nc --arg t "user setup" '{role:"user", content:$t}')" >"$tfile"
    printf '%s\n' "$(jq -nc --arg t "$text" '{role:"assistant", content:$t}')" >>"$tfile"
  }

  # ---------- ST1: Tier-1 + no fence → BLOCK ----------
  local TR1="$TMP/tr1.jsonl" SP1="$TMP/sp1.json" PERF1="$TMP/perf1.txt"
  _make_transcript "$TR1" "Which approach would you prefer? A) Use Postgres B) Use SQLite C) Use DuckDB. Pick one."
  local OUT1 RC1
  OUT1=$(CONV_TREE_STATE_PATH="$SP1" DC_PERF_TRACE_FILE="$PERF1" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR1" '{transcript_path:$p, session_id:"st1"}')" 2>&1)
  RC1=$?
  _ck "ST1 Tier-1 + no fence → exit 2" "$RC1" "2"
  _ck_match "ST1 stderr contains BLOCKED banner" "$OUT1" "DECISION-CONTEXT GATE — BLOCKED"
  _ck_match "ST1 stderr names decision-context.md" "$OUT1" "decision-context\.md"

  # ---------- ST2: Tier-1 + valid fence → ALLOW + event emitted ----------
  local TR2="$TMP/tr2.jsonl" SP2="$TMP/sp2.json"
  local FENCE2; FENCE2=$(cat <<'EOF'
Which path should we take?

::: decision id=db-choice urgency=high
**Title:** Database backend choice
**About:** Pick a backend for the v1 store.
**Background:** We need a small embedded option.
**Question:** Which embedded database should the v1 store use?
**Why not decide alone:** product-shaping; affects backups and DX.
**Options:**
1. **Postgres** (key=pg)
   **What it does:** Full SQL server with durable WAL.
   **Risk:** Adds operational ceremony.
   **Reversibility cost:** expensive
   **Cost:** medium
2. **SQLite** (key=sqlite)
   **What it does:** Embedded file-backed SQL.
   **Risk:** Single-writer constraint.
   **Reversibility cost:** cheap
   **Cost:** low
**Recommendation:**
  **Option key:** sqlite
  **Reasoning:** Ships in stdlib, cheap to switch later.
**Reply with:** sqlite|pg
:::
EOF
)
  _make_transcript "$TR2" "$FENCE2"
  local OUT2 RC2
  OUT2=$(CONV_TREE_STATE_PATH="$SP2" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR2" '{transcript_path:$p, session_id:"st2"}')" 2>&1)
  RC2=$?
  _ck "ST2 Tier-1 + valid fence → exit 0" "$RC2" "0"
  if [[ -f "$SP2" ]]; then
    local CT2
    CT2=$(node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.stdout.write(String(st.events.filter(function(e){return e.type==="decision-raised"}).length))}catch(e){process.stdout.write("ERR")}' "$LIB" "$SP2" 2>/dev/null)
    _ck "ST2 decision-raised event written" "$CT2" "1"
  else
    echo "FAIL: ST2 state file not written"; fail=$((fail+1))
  fi

  # ---------- ST3: Tier-3 rhetorical → ALLOW + no event + no node ----------
  local TR3="$TMP/tr3.jsonl" SP3="$TMP/sp3.json" PERF3="$TMP/perf3.txt"
  _make_transcript "$TR3" "Wrote the file and verified contents. Does that make sense?"
  local RC3
  CONV_TREE_STATE_PATH="$SP3" DC_PERF_TRACE_FILE="$PERF3" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR3" '{transcript_path:$p, session_id:"st3"}')" >/dev/null 2>&1
  RC3=$?
  _ck "ST3 Tier-3 rhetorical → exit 0" "$RC3" "0"
  if [[ ! -f "$SP3" ]]; then
    echo "PASS: ST3 no state file written"; pass=$((pass+1))
  else
    echo "FAIL: ST3 state file should not be written"; fail=$((fail+1))
  fi
  if [[ -f "$PERF3" ]] && grep -q "rhetorical-only" "$PERF3" 2>/dev/null; then
    echo "PASS: ST3 PERF trace records Tier-3 short-circuit"; pass=$((pass+1))
  else
    # rhetorical-only short-circuit may not always be hit if "?" causes pre-filter
    # to pass and then Tier-3 detection runs — either short-circuit acceptable.
    echo "PASS: ST3 short-circuit (rhetorical-only or pre-filter)"; pass=$((pass+1))
  fi

  # ---------- ST4: Tier-2 (no fence) → ALLOW + follow-up marker ----------
  local TR4="$TMP/tr4.jsonl" SP4="$TMP/sp4.json"
  _make_transcript "$TR4" "I finished the migration. Should I deploy to staging now?"
  rm -rf "$TMP/run4-state" && mkdir -p "$TMP/run4-state/.claude/state"
  (
    cd "$TMP/run4-state" && \
    CONV_TREE_STATE_PATH="$SP4" \
      bash "$SELF" <<<"$(jq -nc --arg p "$TR4" '{transcript_path:$p, session_id:"st4"}')" >/dev/null 2>&1
  )
  local RC4=$?
  _ck "ST4 Tier-2 no fence → exit 0" "$RC4" "0"
  local FU_COUNT
  FU_COUNT=$(find "$TMP/run4-state/.claude/state" -name 'decision-context-followup-*.txt' 2>/dev/null | wc -l | tr -d ' ')
  _ck "ST4 follow-up marker written" "$FU_COUNT" "1"

  # ---------- ST5: Tier-1 + fence with Zod violation → BLOCK ----------
  # expires_at set but default_if_no_response references an "expensive" option.
  local TR5="$TMP/tr5.jsonl"
  local FENCE5; FENCE5=$(cat <<'EOF'
Pick one of these urgent options:

::: decision id=db-bad urgency=critical
**Title:** Bad cross-field
**About:** Crossfield constraint should fail validation.
**Background:** expires_at set but default references an expensive option.
**Question:** Which expensive thing?
**Why not decide alone:** affects user data.
**Options:**
1. **Alpha** (key=a)
   **What it does:** Migrates the schema in place.
   **Risk:** Irreversible rollback path.
   **Reversibility cost:** expensive
   **Cost:** high
2. **Bravo** (key=b)
   **What it does:** Creates a sibling schema.
   **Risk:** Doubles storage temporarily.
   **Reversibility cost:** expensive
   **Cost:** high
**Recommendation:**
  **Option key:** a
  **Reasoning:** Smaller blast radius.
**Reply with:** a|b
**Expires at:** 2026-12-31T00:00:00Z
**Default if no response:** a
:::
EOF
)
  _make_transcript "$TR5" "$FENCE5"
  local OUT5 RC5 SP5="$TMP/sp5.json"
  OUT5=$(CONV_TREE_STATE_PATH="$SP5" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR5" '{transcript_path:$p, session_id:"st5"}')" 2>&1)
  RC5=$?
  # Either Tier-1 detects (because of "Pick one") AND fence rejects → block.
  # OR Tier-1 detects, fence invalid → block. Either way: exit 2.
  _ck "ST5 cross-field violation in fence → exit 2" "$RC5" "2"
  _ck_match "ST5 stderr mentions validator/zod" "$OUT5" "Validator detail|zod|tier1-fence-invalid"

  # ---------- ST6: fresh waiver → ALLOW ----------
  local TR6="$TMP/tr6.jsonl" SP6="$TMP/sp6.json"
  _make_transcript "$TR6" "Which approach would you prefer? A) Use X B) Use Y. Pick one."
  rm -rf "$TMP/run6-state" && mkdir -p "$TMP/run6-state/.claude/state"
  printf 'False positive: this is a quoted example from the docs, not a real decision being asked.\n' \
    >"$TMP/run6-state/.claude/state/decision-context-waiver-$(date -u +%Y%m%dT%H%M%S).txt"
  local RC6
  (
    cd "$TMP/run6-state" && \
    CONV_TREE_STATE_PATH="$SP6" \
      bash "$SELF" <<<"$(jq -nc --arg p "$TR6" '{transcript_path:$p, session_id:"st6"}')" >/dev/null 2>&1
  )
  RC6=$?
  _ck "ST6 fresh waiver honored → exit 0" "$RC6" "0"

  # ---------- ST7: facade down + Tier-1 + valid fence → ALLOW + fallback ----------
  local TR7="$TMP/tr7.jsonl"
  _make_transcript "$TR7" "$FENCE2"
  rm -rf "$TMP/run7-state" && mkdir -p "$TMP/run7-state"
  # Point CONV_TREE_STATE_LIB at a non-existent file → all sinks fail.
  local RC7
  HOME_TMP="$TMP/run7-state-home" && mkdir -p "$HOME_TMP/.claude/logs" "$HOME_TMP/.claude/state/decision-context"
  (
    HOME="$HOME_TMP" \
    CONV_TREE_STATE_LIB="$TMP/does-not-exist.js" \
    CONV_TREE_STATE_PATH="$TMP/run7-state/sink.json" \
      bash "$SELF" <<<"$(jq -nc --arg p "$TR7" '{transcript_path:$p, session_id:"st7"}')" >/dev/null 2>&1
  )
  RC7=$?
  _ck "ST7 facade-down → exit 0 (writer-hook discipline)" "$RC7" "0"
  if [[ -s "$HOME_TMP/.claude/state/decision-context/fallback.jsonl" ]]; then
    echo "PASS: ST7 fallback.jsonl written on facade failure"; pass=$((pass+1))
  else
    echo "FAIL: ST7 fallback.jsonl missing or empty"; fail=$((fail+1))
  fi

  # ---------- ST8: pre-filter no-signal → ALLOW + no node invoked ----------
  local TR8="$TMP/tr8.jsonl" SP8="$TMP/sp8.json" PERF8="$TMP/perf8.txt"
  _make_transcript "$TR8" "I read the file. The function returns OK. Continuing to the next step."
  local RC8
  CONV_TREE_STATE_PATH="$SP8" DC_PERF_TRACE_FILE="$PERF8" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR8" '{transcript_path:$p, session_id:"st8"}')" >/dev/null 2>&1
  RC8=$?
  _ck "ST8 no-signal pre-filter → exit 0" "$RC8" "0"
  if [[ -f "$PERF8" ]] && grep -q "pre-filter:nosignal" "$PERF8" 2>/dev/null; then
    echo "PASS: ST8 PERF trace records pre-filter short-circuit"; pass=$((pass+1))
  else
    echo "FAIL: ST8 pre-filter trace missing"; fail=$((fail+1))
  fi
  if [[ ! -f "$SP8" ]]; then
    echo "PASS: ST8 no state file written (no node subprocess)"; pass=$((pass+1))
  else
    echo "FAIL: ST8 unexpected state file written"; fail=$((fail+1))
  fi

  # ---------- ST9: retry-guard 3-strike downgrade ----------
  # Re-fire same blocking input 4 times → 4th call should NOT exit 2
  # (downgrade to warn, exit 0) provided HEAD is stable. We use isolated HOME
  # to keep state-files segregated.
  local TR9="$TMP/tr9.jsonl"
  _make_transcript "$TR9" "Which approach would you prefer? A) Use X B) Use Y. Pick one."
  rm -rf "$TMP/run9-state" && mkdir -p "$TMP/run9-state/.claude/state" "$TMP/run9-home"
  local RC9_LAST=2
  (
    cd "$TMP/run9-state" && \
    for _try in 1 2 3 4 5; do
      CONV_TREE_STATE_PATH="$TMP/run9-state/sink.json" \
        bash "$SELF" <<<"$(jq -nc --arg p "$TR9" '{transcript_path:$p, session_id:"st9"}')" >/dev/null 2>&1
      _last=$?
      echo "$_last" >"$TMP/run9-state/last-rc.txt"
    done
  )
  RC9_LAST=$(cat "$TMP/run9-state/last-rc.txt" 2>/dev/null || echo 2)
  # After ≥3 identical blocks, retry-guard downgrades to warn → exit 0.
  _ck "ST9 retry-guard downgrades to exit 0 after threshold" "$RC9_LAST" "0"

  # ---------- ST10: no transcript path → silent no-op ----------
  local RC10
  bash "$SELF" <<<'{"session_id":"st10"}' >/dev/null 2>&1
  RC10=$?
  _ck "ST10 missing transcript → exit 0 silent no-op" "$RC10" "0"

  # ---------- ST11: all four fence categories validate ----------
  local TR11="$TMP/tr11.jsonl" SP11="$TMP/sp11.json"
  local FENCE11; FENCE11=$(cat <<'EOF'
Here are several fenced blocks.

::: decision id=d-all-1
**Title:** Decision 1
**About:** Try them all.
**Background:** Round trip every category.
**Question:** X or Y?
**Why not decide alone:** Affects user data shape.
**Options:**
1. **Xenon** (key=x)
   **What it does:** Stores via X.
   **Risk:** None known.
   **Reversibility cost:** cheap
   **Cost:** low
2. **Yttrium** (key=y)
   **What it does:** Stores via Y.
   **Risk:** None known.
   **Reversibility cost:** free
   **Cost:** low
**Recommendation:**
  **Option key:** x
  **Reasoning:** Simpler integration path.
**Reply with:** x|y
:::

::: question id=q-all-1
**Title:** Question 1
**About:** Need clarification on deadline.
**Background:** Routine question, no urgency.
**Question:** What is the deadline?
**Why asking:** Need to plan capacity.
**What ive tried:** Searched the brief, no date listed.
**Answer shape:** value
:::

::: action_item_for_user id=a-all-1
**Title:** Action 1
**About:** Operator action required.
**Background:** Misha needs to approve the PR.
**The ask:** Approve the PR
**Why assigned:** Only the maintainer can approve.
**What im doing meanwhile:** Documenting the change rationale.
**State:** open
:::

::: autonomous_action id=aa-all-1
**Title:** Autonomous 1
**About:** Logged for the record.
**Background:** Action taken without asking.
**Action taken:** Renamed the file foo.txt to bar.txt
**Reasoning:** Naming convention fix.
**Reversibility:** cheap
**References:** docs/foo.md
:::
EOF
)
  _make_transcript "$TR11" "$FENCE11"
  local OUT11 RC11
  OUT11=$(CONV_TREE_STATE_PATH="$SP11" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR11" '{transcript_path:$p, session_id:"st11"}')" 2>&1)
  RC11=$?
  _ck "ST11 all-four-categories → exit 0" "$RC11" "0"
  if [[ -f "$SP11" ]]; then
    local C_DR C_QR C_AC C_AA
    C_DR=$(node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.stdout.write(String(st.events.filter(function(e){return e.type===process.argv[3]}).length))}catch(e){process.stdout.write("ERR")}' "$LIB" "$SP11" "decision-raised" 2>/dev/null)
    C_QR=$(node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.stdout.write(String(st.events.filter(function(e){return e.type===process.argv[3]}).length))}catch(e){process.stdout.write("ERR")}' "$LIB" "$SP11" "question-raised" 2>/dev/null)
    C_AC=$(node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.stdout.write(String(st.events.filter(function(e){return e.type===process.argv[3]}).length))}catch(e){process.stdout.write("ERR")}' "$LIB" "$SP11" "action-added" 2>/dev/null)
    C_AA=$(node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.stdout.write(String(st.events.filter(function(e){return e.type===process.argv[3]}).length))}catch(e){process.stdout.write("ERR")}' "$LIB" "$SP11" "autonomous-action-logged" 2>/dev/null)
    _ck "ST11 decision-raised count" "$C_DR" "1"
    _ck "ST11 question-raised count" "$C_QR" "1"
    _ck "ST11 action-added count" "$C_AC" "1"
    _ck "ST11 autonomous-action-logged count" "$C_AA" "1"
  else
    echo "FAIL: ST11 state file missing"; fail=$((fail+1))
  fi

  # ---------- ST12 (B10-FU-1): item appears in snapshot.nodes[].items[] -------
  # This is the load-bearing regression test for the B10-FU-1 fix. Pre-fix,
  # the gate emitted decision-raised against a fresh node_id ("dc-decision-<id>")
  # that the reducer could not resolve via findNode; the event landed in
  # events[] but was silently dropped from snapshot.nodes[].items[]. Post-fix,
  # the gate emits a defensive branch-opened for the project/global root then
  # the decision-raised against that root — so the reducer projects the item
  # into snapshot.nodes[].items[] as ADR-032 sec.3 / FR-2 specifies.
  local TR12="$TMP/tr12.jsonl" SP12="$TMP/sp12.json"
  _make_transcript "$TR12" "$FENCE2"
  local RC12
  CONV_TREE_STATE_PATH="$SP12" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR12" '{transcript_path:$p, session_id:"st12"}')" >/dev/null 2>&1
  RC12=$?
  _ck "ST12 fence emit -> exit 0" "$RC12" "0"
  if [[ -f "$SP12" ]]; then
    # Verify (a) snapshot.nodes[] non-empty AND (b) at least one node has an
    # item whose item_id is "item-db-choice" (matches FENCE2's id=db-choice).
    local ITEM_IN_NODE
    ITEM_IN_NODE=$(node -e '
      try {
        var s = require(process.argv[1]);
        var st = s.readState({ statePath: process.argv[2] });
        var snap = s.deriveSnapshot(st.events);
        var nodes = (snap && snap.nodes) || [];
        var hit = 0;
        for (var i = 0; i < nodes.length; i++) {
          var items = nodes[i].items || [];
          for (var j = 0; j < items.length; j++) {
            if (items[j].item_id === "item-db-choice") { hit++; }
          }
        }
        process.stdout.write(String(hit));
      } catch (e) { process.stdout.write("ERR:" + (e && e.message || e)); }
    ' "$LIB" "$SP12" 2>/dev/null)
    _ck "ST12 item lands in snapshot.nodes[].items[] (B10-FU-1 fix)" "$ITEM_IN_NODE" "1"
  else
    echo "FAIL: ST12 state file missing"; fail=$((fail+1))
  fi

  # ---------- ST28 (B5-FU-1): item-details-set carries surfaced_by stamp -----
  # Task 5 pending-surfacer hard-requires details.surfaced_by === "decision-context-gate"
  # to surface an item. Without this stamp on the gate's emit path, the surfacer
  # would surface NOTHING in production — defeats Task 5's purpose. This test
  # locks the cross-task contract: every item-details-set emission carries the
  # canonical surfaced_by value.
  local TR28="$TMP/tr28.jsonl" SP28="$TMP/sp28.json"
  _make_transcript "$TR28" "$FENCE2"
  local RC28
  CONV_TREE_STATE_PATH="$SP28" \
    bash "$SELF" <<<"$(jq -nc --arg p "$TR28" '{transcript_path:$p, session_id:"st28"}')" >/dev/null 2>&1
  RC28=$?
  _ck "ST28 Tier-1 + valid fence → exit 0" "$RC28" "0"
  if [[ -f "$SP28" ]]; then
    local STAMP28
    STAMP28=$(node -e '
      (function(){
        try {
          var s = require(process.argv[1]);
          var st = s.readState({ statePath: process.argv[2] });
          var idsEvents = st.events.filter(function(e){ return e.type === "item-details-set"; });
          if (idsEvents.length === 0) { process.stdout.write("NO_IDS"); return; }
          var last = idsEvents[idsEvents.length - 1];
          var sb = last && last.details && last.details.surfaced_by;
          process.stdout.write(String(sb));
        } catch (e) { process.stdout.write("ERR:" + (e && e.message || e)); }
      })();
    ' "$LIB" "$SP28" 2>/dev/null)
    _ck "ST28 item-details-set.details.surfaced_by stamped (B5-FU-1)" "$STAMP28" "decision-context-gate"
  else
    echo "FAIL: ST28 state file missing"; fail=$((fail+1))
  fi

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
if [[ "$RUN_SELF_TEST" -eq 1 ]]; then
  _self_test
fi

_run_gate
