#!/bin/bash
# conversation-tree-emit.sh — Claude-side WRITER for the Conversation-Tree UI
# file-mediated state contract (ADR-031 r7 / ADR-032 / PRD FR-11/FR-12).
#
# Classification: WRITER hook, NOT a gate. It NEVER blocks a tool call.
# Every runtime path exits 0. Emission failures are isolated and logged to
# ~/.claude/logs/conversation-tree-emit.log; they must never break the
# orchestrator (gate-respect.md: writer hooks do not block anything).
#
# Today only the GUI (human side) writes events. This hook is the missing
# Claude side: as the Dispatch orchestrator works, it emits the ADR-032 §2
# lifecycle events so the GUI auto-populates live.
#
# Optional rich-details sentinels (v1.1.4 item 41, 2026-05-20):
#   The orchestrator MAY include any/all of these line-prefixed sentinels in
#   the spawn prompt body. The presence/absence is purely advisory; no spawn
#   is ever blocked for missing them.
#       Instructions: <one-line summary of what the spawned session is doing>
#       Recommendation: <one-line guidance for the operator>
#       Links: <doc/path-1.md>, <doc/path-2.md>
#   Since Task 9 of the status-surface plan (2026-06-12) the sentinels DO
#   propagate: when a spawn declares `Work-item: new — <kind>:<text>`, the
#   hook assembles a per-kind context payload from the sentinels through the
#   SOLE-NORMATIVE assembler (decision-context-schema.js assembleItemDetails)
#   and emits a sibling `item-details-set` in the same batch — so the new
#   item is born context-complete. When the payload cannot be assembled (no
#   Instructions: sentinel -> no background), the item is born honestly
#   detail-less and: (a) an observability WARNING lands in the audit log when
#   the prompt is substantive (>200 chars) but carries NO sentinels, and (b)
#   the GUI flags the item context-incomplete (Task 8 render gate). See
#   `_extract_rich_details`, `_assemble_spawn_details`, and the contract in
#   rules/workstreams-state.md "Context-complete item emission".
#
# Invocation modes:
#   --on-spawn   PreToolUse on the Dispatch-only spawn surface
#                (mcp__ccd_session__spawn_task | mcp__ccd_session_mgmt__start_code_task).
#                Emits `branch-opened` for the spawned child branch (parented
#                under an auto-detected project/global root node) and records
#                it to a per-session correlation ledger.
#                SCOPE (ADR-031 r7 Pin-1, amended r8 / ADR-034 2026-05-19):
#                sub-agent Task/Agent invocations are AI-internal mechanics
#                (peer review, verification, internal helpers), NOT branches
#                of the user↔AI conversation the tree models — emitting nodes
#                for them would pollute the operator's tree with workflow
#                noise. The hook deliberately no-ops on Task/Agent so the two
#                Dispatch gates (state-gate, stop-gate) stay consistent with
#                what the tree actually contains.
#   --on-stop    Stop hook. Emits `concluded` for every branch this session
#                opened (read from the ledger), then clears the ledger.
#   --on-builder-dispatch  PreToolUse on Task|Agent|Workflow (ADR-054,
#                2026-06-10). Emits ONE `action-added` WORK-ITEM (kind action,
#                details._category=builder-dispatch, derives 'in-flight') on
#                the session's own ss-* node — NO branch node (ADR-034's
#                branch scoping stands; this is the work-item tier).
#   --on-builder-complete  PostToolUse on Task|Agent|Workflow. Foreground
#                dispatches: tool return == completion -> `action-done`.
#                Background (Workflow / run_in_background:true): launch-ack
#                only -> creation batch, NO done (documented ceiling — see
#                the ADR-054 section below).
#   --self-test  Exercises every classification + idempotency + autodetect +
#                failure-isolation path against temp state files. Prints
#                `self-test: OK` / `self-test: FAIL`. Exit 0 / 1.
#
# Sinks (dual-write, idempotent on a deterministic event_id, per-file dedupe):
#   1. The state-library STATE_FILE (the module tree-state.json the shipped,
#      out-of-scope GUI server watches) — the path that makes the operator's
#      GUI auto-populate. This is the binding sink.
#   2. The ADR-032 §5-resolved path (re-implementing the conv-tree gates'
#      _resolve_state_path identically) so local-Dispatch conv-tree gates see
#      the same truth — best-effort, only when it differs from sink 1.
#   CONV_TREE_STATE_PATH overrides BOTH with a single explicit sink (self-test).
#   CONV_TREE_STATE_LIB overrides the state-library module path.
#
# Writes go ONLY through the frozen A2 facade (state.js appendEvent) — never
# raw JSON. The facade owns idempotency, atomic publish, and attestation.
#
# Out of scope (do not change here): the GUI (server.js/web), the state
# library (A2 frozen — called, never modified), the conv-tree gates, and any
# new event type beyond the ADR-032 §2 enum.

set -uo pipefail

# shellcheck disable=SC1091
{ source "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/nl-paths.sh" 2>/dev/null; } || true
# NL Observability Program Wave O, task O.1 (specs-o §O.1 deliverable 3):
# spawn-dispatched/spawn-concluded ledger events, sourced best-effort so a
# tree missing this lib (should not happen — same repo) never breaks a
# tool call (writer hooks never block, per this file's own header).
# shellcheck disable=SC1091
{ source "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/signal-ledger.sh" 2>/dev/null; } || true

MODE="${1:-}"

# Log + ledger destinations: sandboxed when HARNESS_SELFTEST=1 OR the
# invocation is --self-test itself (self-test isolation — E.2 remediation;
# --self-test always self-sandboxes even if a caller forgot to export
# HARNESS_SELFTEST=1 first) so no self-test run appends to the real
# machine's ~/.claude/logs/conversation-tree-emit.log or writes correlation-
# ledger fixtures into ~/.claude/state/conversation-tree-emit/ regardless of
# HOME. Prefers an explicit HARNESS_SELFTEST_DIR; falls back to a PID-scoped
# tmp sandbox otherwise (signal-ledger.sh's convention) so exporting
# HARNESS_SELFTEST=1 alone (e.g. a bare sweep loop) is enough.
if [[ "${HARNESS_SELFTEST:-0}" == "1" ]] || [[ "$MODE" == "--self-test" ]]; then
  export HARNESS_SELFTEST=1
  _WSE_SANDBOX="${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}/workstreams-emit-selftest/$$}"
  export HARNESS_SELFTEST_DIR="$_WSE_SANDBOX"
  LOG_DIR="$_WSE_SANDBOX/logs"
  LEDGER_DIR="$_WSE_SANDBOX/state/conversation-tree-emit"
else
  LOG_DIR="$HOME/.claude/logs"
  LEDGER_DIR="$HOME/.claude/state/conversation-tree-emit"
fi
LOG_FILE="$LOG_DIR/conversation-tree-emit.log"
# Ensure both dirs exist up front: several call sites redirect directly to
# $LOG_FILE via `2>>` rather than through _log()'s own mkdir -p, so a
# freshly-resolved sandbox dir (self-test) must exist before first use.
mkdir -p "$LOG_DIR" "$LEDGER_DIR" 2>/dev/null || true

# Workstreams consolidation (Phase A, 2026-06-08): the canonical state file
# lives at one operator-configured location (~/.claude/workstreams-state-path.txt),
# resolved by the SHARED resolver so this writer, the sibling hooks, and the GUI
# all read/write the SAME file. Sourced best-effort — if the lib is missing the
# legacy per-path resolvers below still work (graceful degradation; a writer
# hook must never break a tool call).
# shellcheck disable=SC1091
{ source "$(dirname "${BASH_SOURCE[0]}")/lib/workstreams-state-resolver.sh" 2>/dev/null; } || true

# ---- failure isolation -----------------------------------------------------
# Any unexpected error in a runtime mode logs and exits 0. The orchestrator's
# tool call must never be impacted by a writer-hook malfunction.
_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "${MODE:-?}" "$*" >>"$LOG_FILE" 2>/dev/null || true
}
_die_safe() { _log "isolated error: $*"; exit 0; }
trap '_die_safe "uncaught (line $LINENO)"' ERR

# ---- shared helpers --------------------------------------------------------

_have() { command -v "$1" >/dev/null 2>&1; }

# sha1 of stdin -> hex (git-bash provides sha1sum; cksum fallback keeps the
# hook functional even on a stripped environment — determinism is preserved
# per input, which is all idempotency needs).
_sha1() {
  if _have sha1sum; then sha1sum | cut -d' ' -f1
  elif _have shasum; then shasum -a 1 | cut -d' ' -f1
  else cksum | tr -d ' ' ; fi
}

# Config-driven last-resort checkout root for the conv-tree state files. Only
# reached when the git-based resolvers below fail (cwd outside any repo). The
# base is overridable via CONV_TREE_MAIN_CHECKOUT (per-machine config — the
# two-layer-config rule keeps machine-specific absolute paths out of committed
# harness code); the generic default is the historical convention location.
# `<leaf>` is a workstreams-ui-relative path (e.g. state/state.js); both
# the nested (`<root>/neural-lace/workstreams-ui/`) and flat
# (`<root>/workstreams-ui/`) repo layouts are probed, mirroring the
# git-based resolvers, before defaulting to the nested form.
_fallback_conv_tree_path() {
  local leaf="$1"
  local base="${CONV_TREE_MAIN_CHECKOUT:-}"
  if [[ -z "$base" ]] && command -v nl_repo_root >/dev/null 2>&1; then
    base="$(nl_repo_root 2>/dev/null)"
  fi
  [[ -z "$base" ]] && base="$HOME/.claude"
  local nested="$base/neural-lace/workstreams-ui/$leaf"
  local flat="$base/workstreams-ui/$leaf"
  if [[ -e "$nested" ]]; then printf '%s' "$nested"; return 0; fi
  if [[ -e "$flat" ]]; then printf '%s' "$flat"; return 0; fi
  printf '%s' "$nested"
}

# Resolve the state-library entry module (state.js). Mirrors the conv-tree
# gates' _resolve_state_lib resolution order so writer and gate agree.
_resolve_state_lib() {
  if [[ -n "${CONV_TREE_STATE_LIB:-}" ]]; then printf '%s' "$CONV_TREE_STATE_LIB"; return 0; fi
  local _pin="$HOME/.claude/workstreams-lib-path.txt"
  if [[ -f "$_pin" ]]; then
    local _pinned; _pinned=$(head -1 "$_pin" | tr -d '
')
    if [[ -n "$_pinned" && -f "$_pinned" ]]; then printf '%s' "$_pinned"; return 0; fi
  fi
  local root=""
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    local cand="$root/neural-lace/workstreams-ui/state/state.js"
    if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
    cand="$root/workstreams-ui/state/state.js"
    if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
  fi
  _fallback_conv_tree_path "state/state.js"
}

# The MAIN repo checkout (NOT a worktree). `git rev-parse --git-common-dir`
# points a worktree at the parent repo's .git; its dirname is the main
# checkout. In a non-worktree session this equals --show-toplevel. This is
# the same parent-of-git-common-dir pattern git-discipline.md uses for the
# post-merge sync — load-bearing here because the operator runs ONE GUI
# server (from the main checkout) while Dispatch / Code sessions run in
# worktrees: the GUI watches the main checkout's module file, so a
# worktree-rooted writer must target THAT file or the GUI never updates.
_main_repo_root() {
  local gcd
  gcd=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  [[ -z "$gcd" ]] && return 1
  local d
  d=$(cd "$(dirname "$gcd")" 2>/dev/null && pwd) || return 1
  printf '%s' "$d"
}

# GUI sink: the module tree-state.json the shipped, out-of-scope GUI server
# watches (stateLib.STATE_FILE). Resolved against the MAIN checkout so a
# worktree session writes the file the operator's single GUI server is
# actually watching. Falls back to the well-known HOME location.
_resolve_gui_state_path() {
  # Canonical-state-path consolidation: the shared resolver returns the
  # operator-configured canonical file (CONV_TREE_STATE_PATH override > home
  # config > the legacy GUI-sink path computed below as the fallback).
  local legacy mr
  if mr=$(_main_repo_root) && [[ -n "$mr" ]]; then
    if [[ -f "$mr/neural-lace/workstreams-ui/state/state.js" ]]; then
      legacy="$mr/neural-lace/workstreams-ui/state/tree-state.json"
    elif [[ -f "$mr/workstreams-ui/state/state.js" ]]; then
      legacy="$mr/workstreams-ui/state/tree-state.json"
    fi
  fi
  [[ -z "${legacy:-}" ]] && legacy=$(_fallback_conv_tree_path "state/tree-state.json")
  if declare -F resolve_workstreams_state_path >/dev/null 2>&1; then
    resolve_workstreams_state_path "$legacy"
  else
    if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then printf '%s' "$CONV_TREE_STATE_PATH"; else printf '%s' "$legacy"; fi
  fi
}

# ADR-032 §5 path resolution. Pre-consolidation this resolved to the per-project
# .claude/state/conversation-tree/ path — a SECOND, divergent sink. The shared
# resolver now collapses it onto the SAME canonical file as the GUI sink
# (CONV_TREE_STATE_PATH override > home config > the legacy §5 path as fallback),
# so _emit_dual's cheap string-compare dedupes to a single write on the common
# path while the env-override / no-config-file cases keep the old behavior.
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

# Project/global root node from cwd. A directory under .../claude-projects/<p>/
# maps to a per-project root (FR-1: project == a root node); anything else maps
# to the global root (ADR-032 §5 global tree intent, single-file rendering).
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
    # sanitize to a safe node-id token
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
  if [[ -z "$sid" ]] && [[ -n "${1:-}" ]]; then
    sid=$(printf '%s' "$1" | jq -r '.session_id // .session.session_id // empty' 2>/dev/null || echo "")
  fi
  [[ -z "$sid" ]] && sid="ppid-${PPID:-$$}"
  printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

# Append a JSON array of events (argv[3] = file) to one sink via the facade.
# Per-event try/catch: a reducer rejection (e.g. an invariant) is logged, never
# fatal. Always exits 0 — the writer must not fail the hook.
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
    var ok = 0, skipped = 0;
    for (var i = 0; i < evs.length; i++) {
      try { s.appendEvent(evs[i], { statePath: sink }); ok++; }
      catch (e) { skipped++; process.stderr.write("evt-skip[" + (evs[i]&&evs[i].type) + "]:" + (e&&e.message||e) + "\n"); }
    }
    process.stdout.write("OK:" + ok + " skip:" + skipped);
    process.exit(0);
  ' "$lib" "$sink" "$events_file" 2>>"$LOG_FILE") || out="NODEERR"
  _log "sink=$sink result=$out"
}

# Emit a set of events to the configured sink(s), idempotent per file on
# event_id. CONV_TREE_STATE_PATH forces a single explicit sink (no extra node
# subprocesses — used by --self-test and explicit overrides). Otherwise both
# the GUI STATE_FILE and the §5 gate path receive the same events, deduped to
# one write when they resolve identically — computed in ONE node call so a
# cold-start latency cannot interleave multiple resolver subprocesses.
_emit_dual() {
  local lib="$1" events_file="$2"
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then
    _emit_to_sink "$lib" "$CONV_TREE_STATE_PATH" "$events_file"
    return 0
  fi
  # GUI sink = main-checkout module file the operator's GUI server watches.
  # Gate sink = the conv-tree gates' exact §5-resolved path (worktree-aware).
  # Same idempotent event_id makes a double-write to coincidentally-equal
  # paths a harmless per-file no-op, so a cheap string compare is sufficient
  # (no node subprocess — keeps the hot path fast and flake-free).
  local gui gate
  gui=$(_resolve_gui_state_path)
  gate=$(_resolve_gate_state_path)
  if [[ -n "$gui" ]]; then _emit_to_sink "$lib" "$gui" "$events_file"; fi
  if [[ -n "$gate" && "$gate" != "$gui" ]]; then _emit_to_sink "$lib" "$gate" "$events_file"; fi
  if [[ -z "$gui" && -z "$gate" ]]; then _log "no resolvable sink — nothing emitted"; fi
}

_read_stdin() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]] && [[ ! -t 0 ]]; then input=$(cat 2>/dev/null || echo ""); fi
  printf '%s' "$input"
}

# Extract a human branch title from the spawn tool_input. Preference:
# .tool_input.title, else first non-empty trimmed line of prompt/description/
# content, capped at 80 chars. Empty -> caller skips emission.
_spawn_title() {
  local input="$1"
  _have jq || { printf '%s' ""; return 0; }
  local t
  t=$(printf '%s' "$input" | jq -r '.tool_input.title // empty' 2>/dev/null || echo "")
  if [[ -z "$t" ]]; then
    t=$(printf '%s' "$input" | jq -r '
      (.tool_input.prompt // .tool_input.description // .tool_input.content // "")
      | split("\n")[] | select(test("\\S")) ' 2>/dev/null | head -n1 || echo "")
  fi
  t=$(printf '%s' "$t" | sed 's/^[[:space:]]\+//; s/[[:space:]]\+$//' | cut -c1-80)
  printf '%s' "$t"
}

# ---------------------------------------------------------------------------
# Rich-details sentinel extraction (v1.1.4 item 41 — Misha bug 2026-05-20).
#
# Optional sentinels the orchestrator MAY include in a Dispatch spawn prompt
# so the resulting tree branch carries actionable detail (instead of just a
# title). The format is line-prefix-based, mirroring the existing
# `Report-back: task-id=…` and `worker-…` sentinels the gate already parses.
# All sentinels are OPTIONAL — a spawn without them works exactly as today.
#
#   Instructions: <one-line summary of what the spawned session is doing>
#   Recommendation: <one-line guidance for the operator>
#   Links: <doc/path-1.md>, <doc/path-2.md>
#
# What the parsed sentinels power:
#   (a) An observability WARNING in the audit log when a spawn carries a
#       substantive prompt (>200 chars) but NONE of the sentinels — so a
#       human auditing the log can spot branches that shipped without rich
#       detail. NEVER blocks the spawn (writer, not gate).
#   (b) Task 9 (2026-06-12): when the spawn ALSO declares `Work-item: new`,
#       the sentinels feed _assemble_spawn_details -> the sole-normative
#       assembleItemDetails(), and a sibling `item-details-set` joins the
#       same emit batch so the new item is born context-complete
#       (background = Instructions:, recommendation = Recommendation:,
#       links = Links:, per-kind actionable field = the item text).
#
# The functions below are PURE — they extract from input, never write state.
_extract_rich_details() {
  # Echo a single newline-separated triple: instructions\nrecommendation\nlinks
  # (any/all may be empty). Caller splits by line.
  local input="$1"
  _have jq || { printf '\n\n\n'; return 0; }
  local prompt
  prompt=$(printf '%s' "$input" | jq -r '
    (.tool_input.prompt // .tool_input.description // .tool_input.content // "")' 2>/dev/null || echo "")
  local instr rec links
  instr=$(printf '%s' "$prompt" | grep -iE '^[[:space:]]*Instructions:[[:space:]]' | head -n1 \
    | sed -E 's/^[[:space:]]*Instructions:[[:space:]]*//I' | cut -c1-400)
  rec=$(printf '%s' "$prompt" | grep -iE '^[[:space:]]*Recommendation:[[:space:]]' | head -n1 \
    | sed -E 's/^[[:space:]]*Recommendation:[[:space:]]*//I' | cut -c1-400)
  links=$(printf '%s' "$prompt" | grep -iE '^[[:space:]]*Links:[[:space:]]' | head -n1 \
    | sed -E 's/^[[:space:]]*Links:[[:space:]]*//I' | cut -c1-400)
  printf '%s\n%s\n%s\n' "$instr" "$rec" "$links"
}

# Warn (audit log only — NEVER blocks) when a Dispatch spawn carries a
# substantive prompt but no rich-detail sentinels. The audit log is the
# observability surface a human auditor reads to spot branches shipped
# without rich detail. Threshold: 200 chars. Anything shorter is ad-hoc
# and rich-detail sentinels would be overhead.
_warn_no_rich_details() {
  local input="$1" title="$2"
  _have jq || return 0
  local prompt_len
  prompt_len=$(printf '%s' "$input" | jq -r '
    ((.tool_input.prompt // .tool_input.description // .tool_input.content // "") | length)' 2>/dev/null || echo 0)
  [[ "$prompt_len" -lt 200 ]] && return 0
  local triple instr rec links
  triple=$(_extract_rich_details "$input")
  instr=$(printf '%s' "$triple" | sed -n '1p')
  rec=$(printf '%s' "$triple"   | sed -n '2p')
  links=$(printf '%s' "$triple" | sed -n '3p')
  if [[ -z "$instr" && -z "$rec" && -z "$links" ]]; then
    _log "WARN: spawn branch \"$title\" has substantive prompt ($prompt_len chars) but NO rich-details sentinels (Instructions:/Recommendation:/Links:) — branch will render the GUI's 'No detailed instructions recorded' fallback. Future orchestrators should include the sentinels for better operator UX."
  fi
}

# Primary branch identifier the conv-tree-state-gate will look for, derived
# from tool_input with the SAME Pin-1 extraction + priority order the gate
# uses (task-id= sentinel → worker-<tok> → backtick-after-"branch" → the
# .title field verbatim). Returning the gate's first candidate and titling
# the emitted node with it makes a candidate-bearing spawn genuinely satisfy
# the gate (ADR-031 r7: the writer writes the true tree the gate checks for,
# before the gate checks). Empty when tool_input carries none of the four
# patterns (bare Task/Agent prompt) — the gate blocks those regardless of
# what any writer writes; that is a gate-design gap (NL-FINDING-010), not a
# writer bug, and its documented waiver valve is the sanctioned path.
_gate_primary_candidate() {
  local input="$1"
  _have jq || { printf '%s' ""; return 0; }
  local txt ti_title
  txt=$(printf '%s' "$input" | jq -r '[(.tool_input.prompt//""),(.tool_input.description//""),(.tool_input.title//""),(.tool_input.content//"")]|join("\n")' 2>/dev/null || echo "")
  ti_title=$(printf '%s' "$input" | jq -r '.tool_input.title // ""' 2>/dev/null || echo "")
  # (1) task-id=<tok> — the gate adds <tok> first
  local c
  c=$(printf '%s' "$txt" | grep -oE 'task-id=[A-Za-z0-9._/-]+' | head -n1 | sed 's/^task-id=//')
  [[ -n "$c" ]] && { printf '%s' "$c"; return 0; }
  # (2) worker-<token>
  c=$(printf '%s' "$txt" | grep -oE 'worker-[A-Za-z0-9._/-]+' | head -n1)
  [[ -n "$c" ]] && { printf '%s' "$c"; return 0; }
  # (3) backtick-quoted token following the word "branch"
  c=$(printf '%s' "$txt" | grep -oE 'branch[^`]*`[A-Za-z0-9._/-]+`' | head -n1 | grep -oE '`[A-Za-z0-9._/-]+`' | tr -d '`')
  [[ -n "$c" ]] && { printf '%s' "$c"; return 0; }
  # (4) the title field verbatim
  printf '%s' "$ti_title"
}

# ---------------------------------------------------------------------------
# Work-item declaration sentinel (Workstreams Phase 3, 2026-06-01).
#
# A Dispatch spawn MAY declare the WorkItem it serves with a single
# line-prefixed sentinel in the prompt body (same shape family as the
# Instructions:/Recommendation:/Links:/Report-back: sentinels). Two forms:
#
#   Work-item: <existing-item-id>          -> the session serves an item that
#                                             already exists in the tree; the
#                                             child branch records serves_item_id
#                                             and a session-bound link is emitted.
#   Work-item: new — <kind>:<text>         -> the session creates a NEW item; the
#   Work-item: new — <text>                   hook emits the matching kind event
#   Work-item: new: <text>                    (action|decision|question, default
#                                             action) on the child branch, sets
#                                             serves_item_id to a deterministic
#                                             new id, and emits session-bound.
#
# The sentinel is OPTIONAL. A spawn WITHOUT it works exactly as before
# (branch-opened only) — that item-less spawn is the candidate orphan the
# Phase-4 orphan filter surfaces. PURE: extracts from input, never writes.
_extract_work_item() {
  local input="$1"
  _have jq || { printf '%s' ""; return 0; }
  local prompt
  prompt=$(printf '%s' "$input" | jq -r '
    (.tool_input.prompt // .tool_input.description // .tool_input.content // "")' 2>/dev/null || echo "")
  printf '%s' "$prompt" | grep -iE '^[[:space:]]*Work-item:[[:space:]]' | head -n1 \
    | sed -E 's/^[[:space:]]*Work-item:[[:space:]]*//I' | sed -E 's/[[:space:]]+$//' | cut -c1-200
}

# ============================================================================
# Mode: --on-spawn  (PreToolUse on the enumerated spawn surface)
# ============================================================================
_run_on_spawn() {
  local input; input=$(_read_stdin)
  [[ -z "$input" ]] && exit 0
  _have jq || { _log "jq unavailable — cannot classify spawn"; exit 0; }

  local tool; tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
  case "$tool" in
    mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task) ;;
    # Sub-agent Task/Agent are AI-internal mechanics, not conversation
    # branches (ADR-031 r7 Pin-1, amended r8 / ADR-034) -> no node emitted.
    *) exit 0 ;;  # not a Dispatch spawn surface (incl. Task/Agent) -> no-op
  esac

  # Title the emitted branch with the conv-tree-state-gate's PRIMARY Pin-1
  # candidate when tool_input carries one — so the writer genuinely satisfies
  # the gate that runs immediately after (the ADR-031 r7 intended design).
  # For mcp__ccd_session__spawn_task the primary candidate IS the .title
  # field (human-readable). When no candidate exists (a bare Dispatch prompt
  # with no title/sentinel), fall back to a readable first-line title — the
  # gate blocks that spawn regardless (NL-FINDING-010 gate-design gap,
  # waiver-valve territory) but the branch is still recorded for the GUI.
  local title gate_cand
  gate_cand=$(_gate_primary_candidate "$input")
  if [[ -n "$gate_cand" ]]; then
    title="$gate_cand"
  else
    title=$(_spawn_title "$input")
  fi
  [[ -z "$title" ]] && { _log "spawn ($tool) had no extractable title/candidate — skipped"; exit 0; }

  local sid; sid=$(_session_id "$input")
  local rootline; rootline=$(_project_root)
  local root_id="${rootline%%$'\t'*}"
  local root_title="${rootline##*$'\t'}"

  # Deterministic child node id: stable within an hour for the same
  # (session,title) so a hook re-fire dedupes; distinct across spawns.
  local bucket; bucket=$(date -u +%Y%m%d%H 2>/dev/null || echo 0)
  local nhash; nhash=$(printf '%s|%s|%s' "$sid" "$title" "$bucket" | _sha1 | cut -c1-12)
  local child_id="sp-${nhash}"

  local lib; lib=$(_resolve_state_lib)

  # Workstreams Phase 3 — parse the optional Work-item: declaration. Sets
  # serves_item_id (the Session→WorkItem link recorded on the child branch),
  # and for the `new` form, the kind + text of the item to create on the child.
  local wi_raw serves_item_id="" wi_is_new=0 wi_kind="action" wi_text=""
  wi_raw=$(_extract_work_item "$input")
  if [[ -n "$wi_raw" ]]; then
    if printf '%s' "$wi_raw" | grep -qiE '^new([^A-Za-z0-9]|$)'; then
      wi_is_new=1
      # strip leading "new" then any leading non-word separators (space, em-dash,
      # en-dash, hyphen, colon — matched byte-wise so multibyte dashes are safe).
      local rest; rest=$(printf '%s' "$wi_raw" | sed -E 's/^[Nn][Ee][Ww]//' | sed -E 's/^[^A-Za-z0-9]+//')
      local maybe_kind; maybe_kind=$(printf '%s' "$rest" | sed -nE 's/^(action|decision|question):.*$/\1/Ip')
      if [[ -n "$maybe_kind" ]]; then
        wi_kind=$(printf '%s' "$maybe_kind" | tr 'A-Z' 'a-z')
        wi_text=$(printf '%s' "$rest" | sed -E 's/^(action|decision|question):[[:space:]]*//I')
      else
        wi_kind="action"; wi_text="$rest"
      fi
      [[ -z "$wi_text" ]] && wi_text="$title"
      serves_item_id="wi-$(printf '%s|%s' "$child_id" "$wi_text" | _sha1 | cut -c1-12)"
    else
      serves_item_id="$wi_raw"   # reference to an existing WorkItem id
    fi
  fi

  # Deterministic, type-scoped event ids -> per-file idempotency on re-fire.
  local ev_root ev_child
  ev_root="cte-bo-$(printf '%s' "$root_id" | _sha1 | cut -c1-32)"
  ev_child="cte-bo-$(printf '%s' "$child_id" | _sha1 | cut -c1-32)"

  # Build the event batch. Root + child branch-opened always; the child carries
  # serves_item_id when declared. For a `new` work-item, a kind event creates
  # the item on the child branch. A session-bound links this session to the
  # child node whenever a work-item is declared (the provenance link).
  local root_bo child_bo
  root_bo=$(printf '{"event_id":"%s","type":"branch-opened","node_id":"%s","parent_id":null,"title":%s,"actor":"dispatch"}' \
    "$ev_root" "$root_id" "$(jq -Rn --arg t "$root_title" '$t')")
  if [[ -n "$serves_item_id" ]]; then
    child_bo=$(printf '{"event_id":"%s","type":"branch-opened","node_id":"%s","parent_id":"%s","title":%s,"serves_item_id":%s,"actor":"dispatch"}' \
      "$ev_child" "$child_id" "$root_id" "$(jq -Rn --arg t "$title" '$t')" "$(jq -Rn --arg s "$serves_item_id" '$s')")
  else
    child_bo=$(printf '{"event_id":"%s","type":"branch-opened","node_id":"%s","parent_id":"%s","title":%s,"actor":"dispatch"}' \
      "$ev_child" "$child_id" "$root_id" "$(jq -Rn --arg t "$title" '$t')")
  fi
  local events="[$root_bo,$child_bo"
  if [[ "$wi_is_new" -eq 1 && -n "$serves_item_id" ]]; then
    local kind_ev
    case "$wi_kind" in
      decision) kind_ev="decision-raised" ;;
      question) kind_ev="question-raised" ;;
      *)        kind_ev="action-added" ;;
    esac
    local ev_item; ev_item="cte-${kind_ev:0:6}-$(printf '%s|%s' "$child_id" "$serves_item_id" | _sha1 | cut -c1-32)"
    events="$events,$(printf '{"event_id":"%s","type":"%s","node_id":"%s","item_id":"%s","text":%s,"actor":"dispatch"}' \
      "$ev_item" "$kind_ev" "$child_id" "$serves_item_id" "$(jq -Rn --arg t "$wi_text" '$t')")"
    # Task 9 (2026-06-12): a NEW operator-facing work-item is born
    # context-complete when the spawn prompt carries the rich-detail
    # sentinels. The per-kind payload is assembled through the SOLE-NORMATIVE
    # assembler (decision-context-schema.js assembleItemDetails — no shell
    # re-implementation); when it assembles (background present + per-kind
    # actionable field), a sibling item-details-set joins the same batch.
    # When it does not (no Instructions: sentinel -> no background), the item
    # is born honestly detail-less: _warn_no_rich_details observability fires
    # below and the GUI renders it context-incomplete. Never blocks (writer).
    local sp_triple sp_instr sp_rec sp_links spawn_details
    sp_triple=$(_extract_rich_details "$input")
    sp_instr=$(printf '%s' "$sp_triple" | sed -n '1p')
    sp_rec=$(printf '%s' "$sp_triple"   | sed -n '2p')
    sp_links=$(printf '%s' "$sp_triple" | sed -n '3p')
    spawn_details=$(_assemble_spawn_details "$wi_kind" "$wi_text" "$sp_instr" "$sp_rec" "$sp_links")
    if [[ -n "$spawn_details" ]]; then
      # Content-hashed event id: re-firing the same spawn dedupes; a later
      # enrichment via --emit-details (different content) still applies.
      local ev_det; ev_det="cte-detset-$(printf '%s|%s|%s' "$child_id" "$serves_item_id" "$spawn_details" | _sha1 | cut -c1-32)"
      events="$events,$(printf '{"event_id":"%s","type":"item-details-set","node_id":"%s","item_id":"%s","details":%s,"actor":"dispatch"}' \
        "$ev_det" "$child_id" "$serves_item_id" "$spawn_details")"
      _log "work-item new item=$serves_item_id born context-complete (details assembled from spawn sentinels via the sole-normative schema)"
    fi
  fi
  if [[ -n "$serves_item_id" ]]; then
    local ev_sb; ev_sb="cte-sb-$(printf '%s|%s' "$child_id" "$sid" | _sha1 | cut -c1-32)"
    events="$events,$(printf '{"event_id":"%s","type":"session-bound","node_id":"%s","session_id":%s,"actor":"dispatch"}' \
      "$ev_sb" "$child_id" "$(jq -Rn --arg s "$sid" '$s')")"
  fi
  events="$events]"

  local ef; ef=$(mktemp 2>/dev/null || echo "/tmp/cte-spawn-$$.json")
  printf '%s' "$events" >"$ef"
  _emit_dual "$lib" "$ef"
  rm -f "$ef" 2>/dev/null || true

  # Correlation ledger: child_id, title, ts, serves_item_id, base-commit-SHA.
  # The base SHA lets --on-stop detect whether the session shipped a commit
  # (HEAD moved) and emit item-shipped. serves_item_id names the item to ship.
  mkdir -p "$LEDGER_DIR" 2>/dev/null || true
  local ledger="$LEDGER_DIR/opened-${sid}.jsonl"
  local base_sha; base_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
  printf '%s\t%s\t%s\t%s\t%s\n' "$child_id" "$title" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "$serves_item_id" "$base_sha" >>"$ledger" 2>/dev/null || true
  _log "branch-opened child=$child_id title=\"$title\" root=$root_id session=$sid serves=${serves_item_id:-none}"

  # v1.1.4 item 41 — observability for the GUI detail-pane content quality.
  # Non-blocking warning when a substantive Dispatch prompt ships without
  # rich-detail sentinels (Instructions:/Recommendation:/Links:). See the
  # _warn_no_rich_details + _extract_rich_details definitions above for the
  # schema. The warning lives ONLY in the audit log — never blocks. The
  # `Work-item: new` form DOES propagate the sentinels into an
  # item-details-set (Task 9, handled above); this warning remains the
  # observability floor for spawns that carry no sentinels at all.
  _warn_no_rich_details "$input" "$title"

  # ---- WAVE-O O.1 EMIT: spawn-dispatched (contract C2) --------------------
  # ONE marked emit line, per specs-o §O.1 deliverable 3. Never blocks
  # (ledger_emit's own contract); guarded by command -v for a tree missing
  # the lib. child_id/title/serves_item_id are already resolved above.
  if command -v ledger_emit >/dev/null 2>&1; then
    ledger_emit "workstreams-emit" "spawn-dispatched" "child=${child_id} title=\"${title}\" tool=${tool} serves=${serves_item_id:-none}"
  fi
  # ---- END WAVE-O O.1 EMIT --------------------------------------------------

  exit 0
}

# Resolve the node that owns a given item_id in the current snapshot (so an
# item-shipped event targets the item's real owning node — which for a `new`
# work-item is the child branch itself, and for an existing-item reference is
# whatever node already holds it). Empty if not found / node unavailable; the
# caller falls back to the child node (reducer rejects-not-applies a mismatch,
# so a wrong guess is a harmless logged no-op — NFR-2, never a false mutation).
_owner_node_of_item() {
  local item_id="$1"
  _have node || { printf '%s' ""; return 0; }
  local lib sink
  lib=$(_resolve_state_lib)
  sink=$(_resolve_gui_state_path)
  [[ -f "$sink" ]] || { printf '%s' ""; return 0; }
  node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var id=process.argv[3];for(var i=0;i<st.snapshot.nodes.length;i++){var n=st.snapshot.nodes[i];if((n.items||[]).some(function(it){return it.item_id===id})){process.stdout.write(n.node_id);return}}process.stdout.write("")}catch(e){process.stdout.write("")}' "$lib" "$sink" "$item_id" 2>/dev/null || printf '%s' ""
}

# ---------------------------------------------------------------------------
# Context-payload helpers (Task 9 — status-surface plan, 2026-06-12).
#
# THE CONTRACT (rules/workstreams-state.md "Context-complete item emission"):
# every operator-facing decision/question/action raised through this writer
# SHOULD carry the per-kind context payload as an `item-details-set`,
# validated through the SOLE-NORMATIVE module
# (workstreams-ui/state/decision-context-schema.js — assembleItemDetails /
# validateItemDetails / ItemDetailsContentSchema). NO shell re-implementation
# of the schema, ever — these helpers call into the module via node.
# Failure isolation is preserved: a missing module / node / invalid payload
# NEVER blocks the emit; the item lands honestly detail-less (or with the
# raw payload, information-preserving) and the audit log carries a WARN.
# ---------------------------------------------------------------------------

# The sole-normative schema module. Mirrors decision-context-gate.sh's
# _resolve_schema_module (same env override) so writer and gate agree.
_resolve_schema_lib() {
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

# Map an item kind (the --emit-item vocabulary / ADR-032 item kinds) onto the
# detail _category vocabulary of the sole-normative schema.
_kind_to_category() {
  case "$1" in
    decision) printf 'decision' ;;
    question) printf 'question' ;;
    action)   printf 'action_item_for_user' ;;
    *)        printf '' ;;
  esac
}

# _normalize_item_details <category> <details-json>
# stdout (single line): "OK <normalized-json>" | "INVALID <reason>" | "SKIP"
#                       | "NOLIB"
#   OK      — payload validates against the sole-normative schema; the
#             normalized (Zod-parsed, _category-stamped, surfaced_by-stamped)
#             JSON follows. Emit THIS instead of the raw payload.
#   INVALID — payload supplied but fails the cold-read bar (no background /
#             no per-kind actionable field). Caller emits the RAW payload
#             anyway (information-preserving — the GUI flags the item
#             context-incomplete) and logs a WARN with the reason.
#   SKIP    — payload declares a NON-operator _category (e.g.
#             builder-dispatch, the ADR-054 noise-control tier). Passthrough
#             untouched; not an operator-ask payload.
#   NOLIB   — node / schema module unavailable. Passthrough untouched
#             (graceful degradation; a writer must never break a tool call).
_normalize_item_details() {
  local category="$1" details="$2"
  _have node || { printf 'NOLIB'; return 0; }
  local schema; schema=$(_resolve_schema_lib)
  local df; df=$(mktemp 2>/dev/null || echo "/tmp/cte-det-$$.json")
  printf '%s' "$details" >"$df"
  local out
  out=$(node -e '
    var fs = require("fs");
    var cat = process.argv[2];
    var det; try { det = JSON.parse(fs.readFileSync(process.argv[3], "utf8")); } catch (e) { process.stdout.write("INVALID details payload is not parseable JSON"); process.exit(0); }
    // SOLE-NORMATIVE assembler when loadable; else the SAME-CONTRACT inline
    // floor workstreams-turn-emit.sh ships (background + >=1 per-kind
    // actionable field, else null). The fallback exists only so the writer
    // applies the contract in stripped envs (fresh worktree without
    // node_modules); the schema module remains normative when present.
    var assemble = null, validate = null, cats = ["decision", "question", "action_item_for_user", "autonomous_action"];
    try {
      var sch = require(process.argv[1]);
      if (sch && typeof sch.assembleItemDetails === "function") {
        assemble = sch.assembleItemDetails;
        validate = (typeof sch.validateItemDetails === "function") ? sch.validateItemDetails : null;
        if (sch.DETAIL_CATEGORIES) cats = sch.DETAIL_CATEGORIES;
      }
    } catch (e) { /* fall through to the inline floor */ }
    var ACTIONABLE = {
      decision: ["question", "options", "the_ask", "description"],
      question: ["question", "why_asking", "description"],
      action_item_for_user: ["the_ask", "instructions", "description"],
      autonomous_action: ["action_taken", "reasoning", "description"]
    };
    if (!assemble) {
      assemble = function (category, fields) {
        if (cats.indexOf(category) === -1) return null;
        var d = Object.assign({}, fields || {}, { _category: category });
        if (!d.background || String(d.background).trim() === "") return null;
        var need = ACTIONABLE[category] || [];
        var has = need.some(function (f) { return d[f] != null && String(d[f]).trim() !== ""; });
        if (!has) return null;
        return d;
      };
    }
    if (det && typeof det === "object" && !Array.isArray(det) && det._category && cats.indexOf(det._category) === -1) {
      process.stdout.write("SKIP"); process.exit(0);
    }
    var fields = Object.assign({}, det);
    if (!fields.surfaced_by) fields.surfaced_by = "workstreams-emit";
    var ok = assemble(cat, fields);
    if (ok) { process.stdout.write("OK " + JSON.stringify(ok)); process.exit(0); }
    var msg = "missing background and/or the per-kind actionable field (" + (ACTIONABLE[cat] || []).join("|") + ")";
    try {
      if (validate) {
        var v = validate(Object.assign({}, fields, { _category: cat }));
        if (!v.success && v.error && v.error.issues) {
          msg = v.error.issues.map(function (i) { return ((i.path && i.path.join(".")) || "") + ": " + i.message; }).join("; ").replace(/\s+/g, " ").slice(0, 300);
        }
      }
    } catch (e) {}
    process.stdout.write("INVALID " + msg);
  ' "$schema" "$category" "$df" 2>>"$LOG_FILE") || out="NOLIB"
  rm -f "$df" 2>/dev/null || true
  printf '%s' "$out"
}

# _assemble_spawn_details <kind> <item-text> <instructions> <recommendation> <links-csv>
# stdout: normalized details JSON (sole-normative assembleItemDetails), or
# EMPTY when the payload would not be self-contained (no Instructions:
# sentinel -> no background -> the assembler returns null) — caller emits no
# item-details-set and the item is born honestly detail-less.
_assemble_spawn_details() {
  local kind="$1" text="$2" instr="$3" rec="$4" links="$5"
  local category; category=$(_kind_to_category "$kind")
  [[ -z "$category" || -z "$instr" ]] && { printf ''; return 0; }
  _have node || { printf ''; return 0; }
  local schema; schema=$(_resolve_schema_lib)
  node -e '
    var cat = process.argv[2], text = process.argv[3], instr = process.argv[4], rec = process.argv[5], links = process.argv[6];
    // SOLE-NORMATIVE assembler when loadable; same-contract inline floor
    // otherwise (the workstreams-turn-emit.sh precedent — never crash, never
    // emit a payload that fails the cold-read bar).
    var assemble = null;
    try {
      var sch = require(process.argv[1]);
      if (sch && typeof sch.assembleItemDetails === "function") assemble = sch.assembleItemDetails;
    } catch (e) { /* fall through */ }
    if (!assemble) {
      assemble = function (category, fields) {
        var d = Object.assign({}, fields || {}, { _category: category });
        if (!d.background || String(d.background).trim() === "") return null;
        if (!d.question && !d.the_ask) return null;
        return d;
      };
    }
    var fields = { background: instr, surfaced_by: "workstreams-emit" };
    if (cat === "action_item_for_user") { fields.the_ask = text; fields.instructions = instr; }
    else fields.question = text;
    if (rec) fields.recommendation = rec;
    if (links) {
      var ls = links.split(",").map(function (s) { return s.trim(); }).filter(Boolean);
      if (ls.length) fields.links = ls;
    }
    var ok = assemble(cat, fields);
    if (ok) process.stdout.write(JSON.stringify(ok));
  ' "$schema" "$category" "$text" "$instr" "$rec" "$links" 2>>"$LOG_FILE" || printf ''
}

# Resolve an existing item's kind from the sink snapshot (used by
# --emit-details when the payload carries no _category). Empty if not found /
# node unavailable — caller passes the payload through untouched.
_kind_of_item() {
  local item_id="$1"
  _have node || { printf '%s' ""; return 0; }
  local lib sink
  lib=$(_resolve_state_lib)
  sink=$(_resolve_gui_state_path)
  [[ -f "$sink" ]] || { printf '%s' ""; return 0; }
  node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var id=process.argv[3];for(var i=0;i<st.snapshot.nodes.length;i++){var its=st.snapshot.nodes[i].items||[];for(var j=0;j<its.length;j++){if(its[j].item_id===id){process.stdout.write(its[j].kind||"");return}}}process.stdout.write("")}catch(e){process.stdout.write("")}' "$lib" "$sink" "$item_id" 2>/dev/null || printf '%s' ""
}

# ============================================================================
# Mode: --on-stop  (Stop hook — conclude branches this session opened, and
# emit item-shipped for any served work-item whose session shipped a commit)
# ============================================================================
_run_on_stop() {
  local input; input=$(_read_stdin)
  local sid; sid=$(_session_id "$input")
  local ledger="$LEDGER_DIR/opened-${sid}.jsonl"
  [[ -f "$ledger" ]] || exit 0   # session opened no branches -> silent no-op

  local lib; lib=$(_resolve_state_lib)

  # Commit detection: if HEAD moved since the recorded base SHA, the session
  # shipped a commit. Best-effort — git-unavailable / unchanged HEAD / missing
  # base ⇒ no item-shipped (conclude only); never a false ship.
  local head_sha; head_sha=$(git rev-parse HEAD 2>/dev/null || echo "")

  local events="[" first=1 n_cc=0 n_ship=0
  local nid title ts serves base
  while IFS=$'\t' read -r nid title ts serves base || [[ -n "$nid" ]]; do
    [[ -z "$nid" ]] && continue
    # item-shipped FIRST (so FR-7 lets the subsequent concluded apply for a
    # new-item branch — shipped marks the item checked).
    if [[ -n "$serves" && -n "$head_sha" && -n "$base" && "$head_sha" != "$base" ]]; then
      local owner; owner=$(_owner_node_of_item "$serves")
      [[ -z "$owner" ]] && owner="$nid"
      local ev_sh; ev_sh="cte-sh-$(printf '%s|%s' "$owner" "$serves" | _sha1 | cut -c1-32)"
      [[ $first -eq 1 ]] || events="$events,"; first=0
      events="$events$(printf '{"event_id":"%s","type":"item-shipped","node_id":"%s","item_id":"%s","evidence":%s,"actor":"dispatch"}' \
        "$ev_sh" "$owner" "$serves" "$(jq -Rn --arg e "$head_sha" '$e' 2>/dev/null || printf '"%s"' "$head_sha")")"
      n_ship=$((n_ship+1))
    fi
    local ev_cc; ev_cc="cte-cc-$(printf '%s' "$nid" | _sha1 | cut -c1-32)"
    [[ $first -eq 1 ]] || events="$events,"; first=0
    events="$events$(printf '{"event_id":"%s","type":"concluded","node_id":"%s","actor":"dispatch"}' "$ev_cc" "$nid")"
    n_cc=$((n_cc+1))
  done <"$ledger"
  events="$events]"

  if [[ $first -eq 0 ]]; then
    local ef; ef=$(mktemp 2>/dev/null || echo "/tmp/cte-stop-$$.json")
    printf '%s' "$events" >"$ef"
    _emit_dual "$lib" "$ef"
    rm -f "$ef" 2>/dev/null || true
    _log "stop session=$sid concluded=$n_cc shipped=$n_ship"

    # ---- WAVE-O O.1 EMIT: spawn-concluded (contract C2) -------------------
    # ONE marked emit line, per specs-o §O.1 deliverable 3. Only fires when
    # this Stop actually concluded >=1 branch ($first==0, same guard as the
    # _emit_dual call above) — a session that opened nothing has nothing to
    # conclude (mirrors the pre-existing silent-no-op-at-top guard).
    if command -v ledger_emit >/dev/null 2>&1; then
      ledger_emit "workstreams-emit" "spawn-concluded" "session=${sid} concluded=${n_cc} shipped=${n_ship}"
    fi
    # ---- END WAVE-O O.1 EMIT ------------------------------------------------
  fi
  rm -f "$ledger" 2>/dev/null || true   # idempotent: a re-fired Stop is a no-op
  exit 0
}

# ============================================================================
# Mode: --on-session-start  (SessionStart hook — child-side self-registration)
#
# Why this mode exists: the Dispatch orchestrator runs in the cloud (or in a
# remote process that does not have ~/.claude/ loaded), so PreToolUse hooks on
# `mcp__ccd_session_mgmt__start_code_task` NEVER fire for real production
# spawns — only for the self-test against the local stub. The conversation
# tree consequently stays stale: real children spawn, but no branch-opened
# event ever reaches the GUI's state file.
#
# This mode closes the gap from the CHILD's side. When a code session starts
# locally on Misha's machine (SessionStart hook), it emits a branch-opened
# event under the auto-detected project root with the child's own session_id
# as the node_id. The orchestrator never needs to participate — the local
# session writes its own existence into the tree.
#
# Source = SessionStart event JSON (Claude Code provides session_id, cwd,
# source, hook_event_name on stdin). Idempotent on event_id derived from
# session_id, so SessionStart firing multiple times for the same session
# (resume, compact) is a per-file no-op after the first.
# ============================================================================
_run_on_session_start() {
  local input; input=$(_read_stdin)
  _have jq || { _log "session-start: jq unavailable"; exit 0; }

  # Pull session_id from event JSON or env. Source distinguishes startup vs
  # resume vs compact — all of them register the same branch (idempotent).
  local sid="" source="" cwd="" transcript_path=""
  if [[ -n "$input" ]]; then
    sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || echo "")
    source=$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null || echo "")
    cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || echo "")
    transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
  fi
  [[ -z "$sid" ]] && sid="${CLAUDE_SESSION_ID:-}"
  [[ -z "$sid" ]] && { _log "session-start: no session_id available — skipped"; exit 0; }
  [[ -z "$cwd" ]] && cwd="$(pwd 2>/dev/null || echo)"

  # Sanitize session_id for use as a node-id token.
  local sid_safe
  sid_safe=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')

  # Project root resolution (reuse the spawn-side logic for consistency).
  local rootline; rootline=$(cd "$cwd" 2>/dev/null && _project_root || _project_root)
  local root_id="${rootline%%$'\t'*}"
  local root_title="${rootline##*$'\t'}"

  # Derive a branch title. Preference order:
  #   1. CLAUDE_TASK_TITLE env (orchestrator can set this when spawning)
  #   2. Worktree basename (e.g. "vibrant-fermi-acf761")
  #   3. cwd basename
  #   4. fallback: "session <sid-short>"
  local title=""
  if [[ -n "${CLAUDE_TASK_TITLE:-}" ]]; then
    title="$CLAUDE_TASK_TITLE"
  else
    local cwd_base
    cwd_base=$(basename "$cwd" 2>/dev/null || echo "")
    if [[ -n "$cwd_base" && "$cwd_base" != "/" ]]; then
      title="$cwd_base"
    else
      title="session ${sid_safe:0:12}"
    fi
  fi
  title=$(printf '%s' "$title" | cut -c1-80)

  # Deterministic node id = sid-prefixed so the child branch is stable across
  # SessionStart re-fires (resume/compact). Distinct across sessions.
  local nhash; nhash=$(printf '%s' "$sid_safe" | _sha1 | cut -c1-12)
  local child_id="ss-${nhash}"

  local lib; lib=$(_resolve_state_lib)

  # Deterministic event ids → per-file idempotency on SessionStart re-fire.
  local ev_root ev_child
  ev_root="cte-bo-$(printf '%s' "$root_id" | _sha1 | cut -c1-32)"
  ev_child="cte-bo-$(printf '%s' "$child_id" | _sha1 | cut -c1-32)"

  local ef; ef=$(mktemp 2>/dev/null || echo "/tmp/cte-sstart-$$.json")
  cat >"$ef" <<JSON
[
  {"event_id":"$ev_root","type":"branch-opened","node_id":"$root_id","parent_id":null,"title":$(jq -Rn --arg t "$root_title" '$t'),"actor":"dispatch"},
  {"event_id":"$ev_child","type":"branch-opened","node_id":"$child_id","parent_id":"$root_id","title":$(jq -Rn --arg t "$title" '$t'),"actor":"dispatch"}
]
JSON
  _emit_dual "$lib" "$ef"
  rm -f "$ef" 2>/dev/null || true

  # Correlation ledger so --on-stop (Stop hook) can later conclude this
  # branch. Same format as the --on-spawn ledger (one line per opened branch:
  # node_id\ttitle\ttimestamp). Indexed by sid so the Stop hook finds it.
  mkdir -p "$LEDGER_DIR" 2>/dev/null || true
  local ledger="$LEDGER_DIR/opened-${sid_safe}.jsonl"
  # 5-field ledger (Workstreams Phase 3): child_id, title, ts, serves_item_id,
  # base-commit-SHA. serves comes from the CLAUDE_TASK_WORKITEM env the
  # orchestrator MAY set when spawning a worktree session; base SHA lets the
  # child's own --on-stop detect a shipped commit and emit item-shipped.
  local ss_serves; ss_serves="${CLAUDE_TASK_WORKITEM:-}"
  local ss_base; ss_base=$(cd "$cwd" 2>/dev/null && git rev-parse HEAD 2>/dev/null || echo "")
  # Idempotency: only append if this child_id isn't already in the ledger.
  if [[ ! -f "$ledger" ]] || ! grep -q "^${child_id}	" "$ledger" 2>/dev/null; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$child_id" "$title" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "$ss_serves" "$ss_base" >>"$ledger" 2>/dev/null || true
  fi

  # Heartbeat tracker: record this session as live so --heartbeat can detect
  # staleness later. The file's mtime IS the liveness signal.
  mkdir -p "$LEDGER_DIR/live" 2>/dev/null || true
  : > "$LEDGER_DIR/live/${sid_safe}" 2>/dev/null || true

  _log "session-start child=$child_id title=\"$title\" root=$root_id session=$sid_safe source=${source:-?}"
  exit 0
}

# ============================================================================
# Mode: --heartbeat  (scheduled task — refresh liveness, conclude stale)
#
# Scans `~/.claude/projects/*/*.jsonl` (Claude Code's per-session transcript
# directory). For each transcript whose mtime is within the freshness window
# (default 15 min), touches the matching live-marker so the GUI knows the
# session is still active. For each ledger entry whose live-marker is older
# than the staleness threshold (default 60 min) — meaning the session has
# stopped emitting transcript events — emits `concluded` for the branch and
# removes the marker.
#
# This is the upstream-of-the-orchestrator continuous emit that gives the
# tree a live feel even when no event has happened. Designed to be safe to
# run on a 5-min schedule via Windows Task Scheduler / cron.
#
# Tunables (env):
#   CONV_TREE_HEARTBEAT_FRESH_MIN   freshness window (default 15)
#   CONV_TREE_HEARTBEAT_STALE_MIN   conclude threshold (default 60)
# ============================================================================
_run_heartbeat() {
  local fresh_min="${CONV_TREE_HEARTBEAT_FRESH_MIN:-15}"
  local stale_min="${CONV_TREE_HEARTBEAT_STALE_MIN:-60}"

  local projects_dir="$HOME/.claude/projects"
  [[ -d "$projects_dir" ]] || { _log "heartbeat: no projects dir at $projects_dir — skipped"; exit 0; }

  mkdir -p "$LEDGER_DIR/live" 2>/dev/null || true

  # Step 1: refresh live markers for sessions with recent transcript activity.
  local refreshed=0
  while IFS= read -r jsonl; do
    [[ -z "$jsonl" ]] && continue
    # Session id is the filename without .jsonl. Sanitize for marker.
    local sid sid_safe
    sid=$(basename "$jsonl" .jsonl)
    sid_safe=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')
    [[ -z "$sid_safe" ]] && continue
    : > "$LEDGER_DIR/live/${sid_safe}" 2>/dev/null || true
    refreshed=$((refreshed+1))
  done < <(find "$projects_dir" -maxdepth 3 -name "*.jsonl" -type f -mmin "-${fresh_min}" 2>/dev/null)
  _log "heartbeat: refreshed $refreshed live marker(s) (fresh window=${fresh_min}min)"

  # Step 2: conclude branches whose live-marker has gone stale.
  local lib; lib=$(_resolve_state_lib)
  local concluded=0
  local ef; ef=$(mktemp 2>/dev/null || echo "/tmp/cte-hb-$$.json")
  : > "$ef"
  printf '[' >"$ef"
  local first=1

  if [[ -d "$LEDGER_DIR/live" ]]; then
    while IFS= read -r marker; do
      [[ -z "$marker" ]] && continue
      local sid_safe; sid_safe=$(basename "$marker")
      local ledger="$LEDGER_DIR/opened-${sid_safe}.jsonl"
      [[ -f "$ledger" ]] || { rm -f "$marker" 2>/dev/null; continue; }
      # Read all opened branches from this ledger; emit concluded for each.
      while IFS=$'\t' read -r nid rest || [[ -n "$nid" ]]; do
        [[ -z "$nid" ]] && continue
        local ev_cc; ev_cc="cte-cc-$(printf '%s' "$nid" | _sha1 | cut -c1-32)"
        [[ $first -eq 1 ]] || printf ',' >>"$ef"
        printf '{"event_id":"%s","type":"concluded","node_id":"%s","actor":"dispatch"}' "$ev_cc" "$nid" >>"$ef"
        first=0
        concluded=$((concluded+1))
      done <"$ledger"
      rm -f "$marker" 2>/dev/null || true
      rm -f "$ledger" 2>/dev/null || true
    done < <(find "$LEDGER_DIR/live" -maxdepth 1 -type f -mmin "+${stale_min}" 2>/dev/null)
  fi

  printf ']' >>"$ef"
  if [[ $first -eq 0 ]]; then
    _emit_dual "$lib" "$ef"
    _log "heartbeat: concluded $concluded stale branch(es) (stale threshold=${stale_min}min)"
  fi
  rm -f "$ef" 2>/dev/null || true

  # Step 3: write a heartbeat marker file the GUI's /api/health endpoint
  # reads to display "last heartbeat N min ago" so a stuck heartbeat is
  # itself visible to the operator.
  mkdir -p "$HOME/.claude/state/conversation-tree" 2>/dev/null || true
  printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" \
    > "$HOME/.claude/state/conversation-tree/heartbeat.last" 2>/dev/null || true

  exit 0
}

# ============================================================================
# Mode: --self-test
# ============================================================================
_self_test() {
  trap - ERR
  local pass=0 fail=0 tmp
  tmp=$(mktemp -d 2>/dev/null || echo "/tmp/cte-st-$$"); mkdir -p "$tmp"
  # Self-contained sandboxing regardless of caller env (E.2 remediation): every
  # child `bash "$SELF"` this self-test spawns below inherits
  # HARNESS_SELFTEST_DIR="$tmp" and therefore logs/ledgers to $tmp, never the
  # real ~/.claude/logs or ~/.claude/state/conversation-tree-emit/, even if
  # the caller invoked --self-test without first setting HARNESS_SELFTEST=1.
  # Re-point THIS process's own LOG_FILE/LEDGER_DIR (resolved once at
  # top-of-script, before --self-test dispatch reached here) at the SAME
  # "$tmp" so the parent's own log-content assertions (ST38/ST39 etc.) read
  # from the identical file the child subprocesses just wrote to.
  export HARNESS_SELFTEST=1
  export HARNESS_SELFTEST_DIR="$tmp"
  LOG_DIR="$tmp/logs"
  LEDGER_DIR="$tmp/state/conversation-tree-emit"
  LOG_FILE="$LOG_DIR/conversation-tree-emit.log"
  mkdir -p "$LOG_DIR" "$LEDGER_DIR" 2>/dev/null || true
  local LIB; LIB=$(CONV_TREE_STATE_LIB="${CONV_TREE_STATE_LIB:-}" _resolve_state_lib)
  if [[ ! -f "$LIB" ]]; then echo "self-test: cannot locate state library ($LIB)"; echo "self-test: FAIL"; exit 1; fi
  export CONV_TREE_STATE_LIB="$LIB"
  local SELF; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  _count() { node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var t=process.argv[3];process.stdout.write(String(st.events.filter(function(e){return e.type===t}).length))}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2" 2>/dev/null; }
  _node_state() { node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.filter(function(x){return x.title===process.argv[3]})[0];process.stdout.write(n?n.state:"MISSING")}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2" 2>/dev/null; }
  _has_root() { node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.stdout.write(st.snapshot.nodes.some(function(x){return x.node_id===process.argv[3]&&x.parent_id===null})?"Y":"N")}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2" 2>/dev/null; }
  _ck() { if [[ "$2" == "$3" ]]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (got '$2' want '$3')"; fail=$((fail+1)); fi; }

  # ST1-ST2: each Dispatch spawn tool emits a branch-opened titled by the
  # spawn title. ST3-ST4: sub-agent Task/Agent are AI-internal mechanics
  # (ADR-031 r7 Pin-1, amended r8 / ADR-034) -> NO node emitted, NO file
  # written (the exact tree-pollution Misha's Option-A rationale removes).
  local i=0
  for tn in mcp__ccd_session__spawn_task mcp__ccd_session_mgmt__start_code_task; do
    i=$((i+1)); local sp="$tmp/st-$i.json"
    CONV_TREE_STATE_PATH="$sp" CLAUDE_SESSION_ID="sess-st-$i" \
      bash "$SELF" --on-spawn <<<"{\"tool_name\":\"$tn\",\"tool_input\":{\"title\":\"Hello $tn\"},\"session_id\":\"sess-st-$i\"}" >/dev/null 2>&1
    _ck "ST$i spawn($tn) -> branch-opened titled 'Hello $tn'" "$(_node_state "$sp" "Hello $tn")" "open"
  done
  # ST3: sub-agent Task -> no-op, no state file written
  local sp3="$tmp/st-3.json"
  CONV_TREE_STATE_PATH="$sp3" CLAUDE_SESSION_ID="sess-st-3" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"Task","tool_input":{"subagent_type":"code-reviewer","prompt":"review the diff","title":"Reviewer"},"session_id":"sess-st-3"}' >/dev/null 2>&1
  if [[ -f "$sp3" ]]; then echo "FAIL: ST3 sub-agent Task must emit NO node (AI-internal, ADR-034)"; fail=$((fail+1)); else echo "PASS: ST3 sub-agent Task -> no-op (no tree node)"; pass=$((pass+1)); fi
  # ST4: sub-agent Agent -> no-op, no state file written
  local sp4="$tmp/st-4.json"
  CONV_TREE_STATE_PATH="$sp4" CLAUDE_SESSION_ID="sess-st-4" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"Agent","tool_input":{"subagent_type":"task-verifier","prompt":"verify task 3","title":"Verifier"},"session_id":"sess-st-4"}' >/dev/null 2>&1
  if [[ -f "$sp4" ]]; then echo "FAIL: ST4 sub-agent Agent must emit NO node (AI-internal, ADR-034)"; fail=$((fail+1)); else echo "PASS: ST4 sub-agent Agent -> no-op (no tree node)"; pass=$((pass+1)); fi

  # ST5: non-spawn tool -> no-op (no file written)
  local sp5="$tmp/st-5.json"
  CONV_TREE_STATE_PATH="$sp5" CLAUDE_SESSION_ID="sess-st-5" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"sess-st-5"}' >/dev/null 2>&1
  if [[ -f "$sp5" ]]; then echo "FAIL: ST5 non-spawn must be a no-op"; fail=$((fail+1)); else echo "PASS: ST5 non-spawn no-op"; pass=$((pass+1)); fi

  # ST6: --on-stop concludes the opened branch
  local sp6="$tmp/st-6.json"
  CONV_TREE_STATE_PATH="$sp6" CLAUDE_SESSION_ID="sess-st-6" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Branch Six"},"session_id":"sess-st-6"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp6" CLAUDE_SESSION_ID="sess-st-6" \
    bash "$SELF" --on-stop <<<'{"session_id":"sess-st-6"}' >/dev/null 2>&1
  _ck "ST6 --on-stop -> branch concluded" "$(_node_state "$sp6" "Branch Six")" "concluded"

  # ST7: idempotent re-fire of the same spawn does NOT double-write
  local sp7="$tmp/st-7.json"
  for _r in 1 2 3; do
    CONV_TREE_STATE_PATH="$sp7" CLAUDE_SESSION_ID="sess-st-7" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Idem"},"session_id":"sess-st-7"}' >/dev/null 2>&1
  done
  _ck "ST7 idempotent: 3 re-fires -> exactly 1 child branch-opened (+1 root = 2)" "$(_count "$sp7" branch-opened)" "2"

  # ST8: project autodetect — cwd under claude-projects/<p>/ -> proj-<p> root
  local sp8="$tmp/st-8.json" pdir="$tmp/claude-projects/demoproj/wt"
  mkdir -p "$pdir"
  ( cd "$pdir" && CONV_TREE_STATE_PATH="$sp8" CLAUDE_SESSION_ID="sess-st-8" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"PA"},"session_id":"sess-st-8"}' >/dev/null 2>&1 )
  _ck "ST8 autodetect project root proj-demoproj" "$(_has_root "$sp8" "proj-demoproj")" "Y"

  # ST9: no claude-projects in cwd -> global root
  local sp9="$tmp/st-9.json" gdir="$tmp/elsewhere"
  mkdir -p "$gdir"
  ( cd "$gdir" && CONV_TREE_STATE_PATH="$sp9" CLAUDE_SESSION_ID="sess-st-9" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"GA"},"session_id":"sess-st-9"}' >/dev/null 2>&1 )
  _ck "ST9 autodetect global root" "$(_has_root "$sp9" "global")" "Y"

  # ST10: failure isolation — broken state-lib path -> exit 0, log line written
  local sp10="$tmp/st-10.json" rc
  CONV_TREE_STATE_PATH="$sp10" CONV_TREE_STATE_LIB="$tmp/does-not-exist.js" CLAUDE_SESSION_ID="sess-st-10" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Iso"},"session_id":"sess-st-10"}' >/dev/null 2>&1
  rc=$?
  _ck "ST10 failure isolation -> exit 0" "$rc" "0"

  # ST11: title fallback to first non-empty prompt line when .title absent
  local sp11="$tmp/st-11.json"
  CONV_TREE_STATE_PATH="$sp11" CLAUDE_SESSION_ID="sess-st-11" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session_mgmt__start_code_task","tool_input":{"prompt":"\n  First real line here\nsecond\n"},"session_id":"sess-st-11"}' >/dev/null 2>&1
  _ck "ST11 title falls back to first prompt line" "$(_node_state "$sp11" "First real line here")" "open"

  # ST12: --on-stop with no ledger for the session -> silent no-op exit 0
  local sp12="$tmp/st-12.json"
  CONV_TREE_STATE_PATH="$sp12" CLAUDE_SESSION_ID="sess-st-12-never-spawned" \
    bash "$SELF" --on-stop <<<'{"session_id":"sess-st-12-never-spawned"}' >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 0 && ! -f "$sp12" ]]; then echo "PASS: ST12 stop-without-ledger no-op"; pass=$((pass+1)); else echo "FAIL: ST12 stop-without-ledger (rc=$rc)"; fail=$((fail+1)); fi

  # ST15-17: the emitted branch title MUST equal the conv-tree-state-gate's
  # primary Pin-1 candidate so a candidate-bearing spawn genuinely satisfies
  # the gate (writer-satisfies-gate, ADR-031 r7). Mirrors the gate's priority
  # order: task-id= (1) > worker- (2) > backtick-branch (3) > .title (4).
  local sp15="$tmp/st-15.json"
  CONV_TREE_STATE_PATH="$sp15" CLAUDE_SESSION_ID="sess-st-15" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Feat X"},"session_id":"sess-st-15"}' >/dev/null 2>&1
  if node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.exit(st.snapshot.nodes.some(function(n){return n.title==="Feat X"})?0:1)' "$LIB" "$sp15" 2>/dev/null; then echo "PASS: ST15 spawn_task .title -> node title == gate candidate (4)"; pass=$((pass+1)); else echo "FAIL: ST15 spawn_task title not the gate candidate"; fail=$((fail+1)); fi

  local sp16="$tmp/st-16.json"
  CONV_TREE_STATE_PATH="$sp16" CLAUDE_SESSION_ID="sess-st-16" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session_mgmt__start_code_task","tool_input":{"prompt":"do work on branch worker-feat-y now"},"session_id":"sess-st-16"}' >/dev/null 2>&1
  if node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.exit(st.snapshot.nodes.some(function(n){return n.title==="worker-feat-y"})?0:1)' "$LIB" "$sp16" 2>/dev/null; then echo "PASS: ST16 worker-<tok> -> node title == gate candidate (2)"; pass=$((pass+1)); else echo "FAIL: ST16 worker- candidate not matched"; fail=$((fail+1)); fi

  local sp17="$tmp/st-17.json"
  CONV_TREE_STATE_PATH="$sp17" CLAUDE_SESSION_ID="sess-st-17" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"prompt":"Report-back: task-id=abc.123\nbody worker-zzz","title":"ignored-because-taskid-wins"},"session_id":"sess-st-17"}' >/dev/null 2>&1
  if node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.exit(st.snapshot.nodes.some(function(n){return n.title==="abc.123"})?0:1)' "$LIB" "$sp17" 2>/dev/null; then echo "PASS: ST17 task-id= wins over worker-/title (gate priority 1)"; pass=$((pass+1)); else echo "FAIL: ST17 task-id priority not honored"; fail=$((fail+1)); fi

  # ST13/ST14: worktree topology — the operator runs ONE GUI server from the
  # MAIN checkout while Dispatch/Code sessions run in worktrees.
  #
  # Workstreams consolidation (Phase A, 2026-06-08): the canonical state file
  # now lives at one operator-configured location, so by DEFAULT both the GUI
  # sink and the gate sink resolve to the SAME canonical file (ST13b below
  # locks that convergence). ST13/ST14 here pin the LEGACY-FALLBACK topology
  # logic — exercised by disabling the canonical config (WORKSTREAMS_STATE_CONFIG
  # → a non-existent file). That keeps the pre-consolidation invariants tested:
  # GUI sink → MAIN checkout module file; gate sink → worktree-local §5 path;
  # the two differ. Both are the FALLBACK that fires when no config exists.
  if command -v git >/dev/null 2>&1; then
    local R="$tmp/mainrepo" WT="$tmp/wt"
    mkdir -p "$R/neural-lace/workstreams-ui/state"
    : >"$R/neural-lace/workstreams-ui/state/state.js"
    ( cd "$R" && git init -q . && git config core.hooksPath "" && git config user.email t@e.test && git config user.name t \
        && git add -A && git commit -qm init && git worktree add -q "$WT" -b st13wt ) >/dev/null 2>&1
    local Rabs gui_from_wt gate_from_wt want_gui NOCFG="$tmp/no-such-config.txt"
    Rabs=$(cd "$R" && pwd)
    want_gui="$Rabs/neural-lace/workstreams-ui/state/tree-state.json"
    # WORKSTREAMS_STATE_CONFIG → missing file forces the resolver to the legacy
    # fallback, isolating the topology logic from the real machine config.
    gui_from_wt=$( cd "$WT" && CONV_TREE_STATE_PATH="" WORKSTREAMS_STATE_CONFIG="$NOCFG" bash "$SELF" --resolve-gui-sink 2>/dev/null | head -n1 )
    gate_from_wt=$( cd "$WT" && CONV_TREE_STATE_PATH="" WORKSTREAMS_STATE_CONFIG="$NOCFG" bash "$SELF" --resolve-gate-sink 2>/dev/null | head -n1 )
    # Path-format-agnostic (Windows: git emits native C:/… while $WT is MSYS
    # /tmp/…). The invariant that matters: the legacy GUI fallback resolves to
    # the MAIN checkout's workstreams-ui module file, NOT the worktree's.
    if [[ -n "$gui_from_wt" \
          && "$gui_from_wt" == *"/neural-lace/workstreams-ui/state/tree-state.json" \
          && "$gui_from_wt" == *"/mainrepo/"* \
          && "$gui_from_wt" != *"/wt/"* ]]; then
      echo "PASS: ST13 GUI fallback from worktree -> MAIN checkout module file"; pass=$((pass+1))
    else
      echo "FAIL: ST13 GUI fallback (got '$gui_from_wt'; want *mainrepo*/neural-lace/workstreams-ui/state/tree-state.json, not under /wt/)"; fail=$((fail+1))
    fi
    # The legacy gate fallback is the §5 path (.claude/state/conversation-tree/),
    # NOT the GUI module file (workstreams-ui/state/), and the two differ.
    if [[ -n "$gate_from_wt" \
          && "$gate_from_wt" == *"/.claude/state/conversation-tree/tree-state.json" \
          && "$gate_from_wt" != *"workstreams-ui/state/"* \
          && "$gate_from_wt" != "$gui_from_wt" ]]; then
      echo "PASS: ST14 gate fallback is the §5 path & differs from the GUI fallback"; pass=$((pass+1))
    else
      echo "FAIL: ST14 gate fallback (got '$gate_from_wt'; want a *.claude/state/conversation-tree/ path != GUI '$gui_from_wt')"; fail=$((fail+1))
    fi
    # ST13b: WITH a canonical config present, BOTH sinks converge on it — the
    # core consolidation invariant (one file, no divergence). This is what the
    # shared resolver buys: the pre-consolidation GUI/gate split collapses.
    local CFG="$tmp/canon-cfg.txt" CANON="$tmp/canon/tree-state.json"
    printf '%s\n' "$CANON" > "$CFG"
    local gui_canon gate_canon
    gui_canon=$( cd "$WT" && CONV_TREE_STATE_PATH="" WORKSTREAMS_STATE_CONFIG="$CFG" bash "$SELF" --resolve-gui-sink 2>/dev/null | head -n1 )
    gate_canon=$( cd "$WT" && CONV_TREE_STATE_PATH="" WORKSTREAMS_STATE_CONFIG="$CFG" bash "$SELF" --resolve-gate-sink 2>/dev/null | head -n1 )
    if [[ "$gui_canon" == "$CANON" && "$gate_canon" == "$CANON" ]]; then
      echo "PASS: ST13b GUI+gate sinks both converge on canonical config file"; pass=$((pass+1))
    else
      echo "FAIL: ST13b convergence (gui='$gui_canon' gate='$gate_canon'; both want '$CANON')"; fail=$((fail+1))
    fi
    ( cd "$R" && git worktree remove --force "$WT" ) >/dev/null 2>&1 || true
  else
    echo "PASS: ST13 (skipped: git unavailable)"; pass=$((pass+1))
    echo "PASS: ST14 (skipped: git unavailable)"; pass=$((pass+1))
    echo "PASS: ST13b (skipped: git unavailable)"; pass=$((pass+1))
  fi

  # ST18 — v1.1.4 item 41: rich-details sentinel extraction. The hook must
  # parse `Instructions:` / `Recommendation:` / `Links:` lines from a spawn
  # prompt body so future iterations can propagate them. PURE function, no
  # state side effects — assertion is over the function's output triple.
  local triple instr rec links
  triple=$(_extract_rich_details \
'{"tool_input":{"prompt":"do stuff\nInstructions: edit foo.ts and run tests\nRecommendation: ship as a single commit\nLinks: docs/spec.md, docs/api.md\nmore body"}}')
  instr=$(printf '%s' "$triple" | sed -n '1p')
  rec=$(printf '%s' "$triple"   | sed -n '2p')
  links=$(printf '%s' "$triple" | sed -n '3p')
  if [[ "$instr" == "edit foo.ts and run tests" \
        && "$rec" == "ship as a single commit" \
        && "$links" == "docs/spec.md, docs/api.md" ]]; then
    echo "PASS: ST18 _extract_rich_details parses Instructions:/Recommendation:/Links: sentinels"
    pass=$((pass+1))
  else
    echo "FAIL: ST18 (instr='$instr' rec='$rec' links='$links')"
    fail=$((fail+1))
  fi

  # ST19 — no sentinels + short prompt: warning does NOT fire (under threshold).
  local LOG_BEFORE LOG_AFTER
  LOG_BEFORE=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  local sp19="$tmp/st-19.json"
  CONV_TREE_STATE_PATH="$sp19" CLAUDE_SESSION_ID="sess-st-19" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Tiny","prompt":"short"},"session_id":"sess-st-19"}' >/dev/null 2>&1
  LOG_AFTER=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  if ! tail -n $((LOG_AFTER - LOG_BEFORE)) "$LOG_FILE" 2>/dev/null | grep -q 'WARN: spawn branch "Tiny"'; then
    echo "PASS: ST19 short prompt -> no rich-details warning (under 200-char threshold)"
    pass=$((pass+1))
  else
    echo "FAIL: ST19 warning fired on short prompt"
    fail=$((fail+1))
  fi

  # ST20 — substantive prompt + NO sentinels -> warning DOES fire.
  LOG_BEFORE=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  local sp20="$tmp/st-20.json"
  local LONG_PROMPT
  LONG_PROMPT=$(printf 'spawn body without rich-detail sentinels. %.0s' {1..15})
  CONV_TREE_STATE_PATH="$sp20" CLAUDE_SESSION_ID="sess-st-20" \
    bash "$SELF" --on-spawn <<<"{\"tool_name\":\"mcp__ccd_session__spawn_task\",\"tool_input\":{\"title\":\"NoSentinels\",\"prompt\":\"$LONG_PROMPT\"},\"session_id\":\"sess-st-20\"}" >/dev/null 2>&1
  LOG_AFTER=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  if tail -n $((LOG_AFTER - LOG_BEFORE + 1)) "$LOG_FILE" 2>/dev/null | grep -q 'WARN: spawn branch "NoSentinels" has substantive prompt'; then
    echo "PASS: ST20 substantive prompt without sentinels -> WARN logged"
    pass=$((pass+1))
  else
    echo "FAIL: ST20 substantive prompt without sentinels (expected WARN in audit log)"
    fail=$((fail+1))
  fi

  # ST21 — substantive prompt WITH at least one sentinel -> warning does NOT fire.
  LOG_BEFORE=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  local sp21="$tmp/st-21.json"
  local LONG_WITH_SENT="${LONG_PROMPT}\nInstructions: handle the work"
  CONV_TREE_STATE_PATH="$sp21" CLAUDE_SESSION_ID="sess-st-21" \
    bash "$SELF" --on-spawn <<<"{\"tool_name\":\"mcp__ccd_session__spawn_task\",\"tool_input\":{\"title\":\"WithSentinel\",\"prompt\":\"$LONG_WITH_SENT\"},\"session_id\":\"sess-st-21\"}" >/dev/null 2>&1
  LOG_AFTER=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  if ! tail -n $((LOG_AFTER - LOG_BEFORE + 1)) "$LOG_FILE" 2>/dev/null | grep -q 'WARN: spawn branch "WithSentinel"'; then
    echo "PASS: ST21 sentinel present -> NO warning (branch carries rich detail)"
    pass=$((pass+1))
  else
    echo "FAIL: ST21 warning fired despite Instructions: sentinel present"
    fail=$((fail+1))
  fi

  # ST22-ST31: orchestrator-emit modes (v1.1.5 — 2026-05-21).
  # The conversation tree captures conversation-shape data, not just spawns.
  # These tests lock the contract: items raised via --emit-item land in the
  # state file as the matching ADR-032 §2 event with actor='dispatch'.

  # ST22 — --emit-branch creates a logical thread (no Dispatch spawn).
  local sp22="$tmp/st-22.json"
  CONV_TREE_STATE_PATH="$sp22" CLAUDE_SESSION_ID="sess-st-22" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st22-root","parent_id":null,"title":"ST22 Root"}' >/dev/null 2>&1
  _ck "ST22 --emit-branch creates root node" "$(_node_state "$sp22" "ST22 Root")" "open"

  # ST23 — --emit-item raises a decision under an existing branch.
  local sp23="$tmp/st-23.json"
  CONV_TREE_STATE_PATH="$sp23" CLAUDE_SESSION_ID="sess-st-23" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st23-root","parent_id":null,"title":"ST23 Root"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp23" CLAUDE_SESSION_ID="sess-st-23" \
    bash "$SELF" --emit-item <<<'{"kind":"decision","node_id":"st23-root","item_id":"i-st23-a","text":"Pick A or B?"}' >/dev/null 2>&1
  local has_dec
  has_dec=$(node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.find(function(x){return x.node_id==="st23-root"});process.stdout.write(n && n.items && n.items.find(function(i){return i.item_id==="i-st23-a" && i.kind==="decision"})?"Y":"N")' "$LIB" "$sp23" 2>/dev/null)
  _ck "ST23 --emit-item decision lands on branch" "$has_dec" "Y"

  # ST24 — --emit-item with details emits both the item and item-details-set.
  local sp24="$tmp/st-24.json"
  CONV_TREE_STATE_PATH="$sp24" CLAUDE_SESSION_ID="sess-st-24" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st24-root","parent_id":null,"title":"ST24 Root"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp24" CLAUDE_SESSION_ID="sess-st-24" \
    bash "$SELF" --emit-item <<<'{"kind":"action","node_id":"st24-root","item_id":"i-st24-a","text":"Click signup","details":{"instructions":"Sign up at example.com","recommendation":"do it today","links":["docs/example.md"]}}' >/dev/null 2>&1
  local has_det
  has_det=$(node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.find(function(x){return x.node_id==="st24-root"});var it=n&&n.items&&n.items.find(function(i){return i.item_id==="i-st24-a"});process.stdout.write(it&&it.details&&it.details.instructions==="Sign up at example.com"?"Y":"N")' "$LIB" "$sp24" 2>/dev/null)
  _ck "ST24 --emit-item with details populates item.details" "$has_det" "Y"

  # ST25 — --emit-item idempotent: 3 emits of same (kind, node_id, item_id)
  # → exactly ONE item, ONE branch-opened, ONE decision-raised.
  local sp25="$tmp/st-25.json"
  CONV_TREE_STATE_PATH="$sp25" CLAUDE_SESSION_ID="sess-st-25" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st25-root","parent_id":null,"title":"ST25 Root"}' >/dev/null 2>&1
  for _r in 1 2 3; do
    CONV_TREE_STATE_PATH="$sp25" CLAUDE_SESSION_ID="sess-st-25" \
      bash "$SELF" --emit-item <<<'{"kind":"question","node_id":"st25-root","item_id":"i-st25-q","text":"Which way?"}' >/dev/null 2>&1
  done
  _ck "ST25 --emit-item idempotent on (kind,node,item)" "$(_count "$sp25" question-raised)" "1"

  # ST26 — --emit-details populates / replaces existing item.details.
  local sp26="$tmp/st-26.json"
  CONV_TREE_STATE_PATH="$sp26" CLAUDE_SESSION_ID="sess-st-26" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st26-root","parent_id":null,"title":"ST26 Root"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp26" CLAUDE_SESSION_ID="sess-st-26" \
    bash "$SELF" --emit-item <<<'{"kind":"action","node_id":"st26-root","item_id":"i-st26-a","text":"Do thing"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp26" CLAUDE_SESSION_ID="sess-st-26" \
    bash "$SELF" --emit-details <<<'{"node_id":"st26-root","item_id":"i-st26-a","details":{"instructions":"Updated instructions","recommendation":"do A"}}' >/dev/null 2>&1
  local det26
  det26=$(node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.find(function(x){return x.node_id==="st26-root"});var it=n&&n.items&&n.items.find(function(i){return i.item_id==="i-st26-a"});process.stdout.write(it&&it.details&&it.details.recommendation==="do A"?"Y":"N")' "$LIB" "$sp26" 2>/dev/null)
  _ck "ST26 --emit-details applied after item raised" "$det26" "Y"

  # ST27 — --resolve-item with resolution=answered checks a decision/question.
  local sp27="$tmp/st-27.json"
  CONV_TREE_STATE_PATH="$sp27" CLAUDE_SESSION_ID="sess-st-27" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st27-root","parent_id":null,"title":"ST27 Root"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp27" CLAUDE_SESSION_ID="sess-st-27" \
    bash "$SELF" --emit-item <<<'{"kind":"decision","node_id":"st27-root","item_id":"i-st27-d","text":"choose"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp27" CLAUDE_SESSION_ID="sess-st-27" \
    bash "$SELF" --resolve-item <<<'{"node_id":"st27-root","item_id":"i-st27-d","resolution":"answered"}' >/dev/null 2>&1
  local checked27
  checked27=$(node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.find(function(x){return x.node_id==="st27-root"});var it=n&&n.items&&n.items.find(function(i){return i.item_id==="i-st27-d"});process.stdout.write(it&&it.checked?"Y":"N")' "$LIB" "$sp27" 2>/dev/null)
  _ck "ST27 --resolve-item answered -> item.checked" "$checked27" "Y"

  # ST28 — --resolve-item with resolution=done marks an action complete.
  local sp28="$tmp/st-28.json"
  CONV_TREE_STATE_PATH="$sp28" CLAUDE_SESSION_ID="sess-st-28" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st28-root","parent_id":null,"title":"ST28 Root"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp28" CLAUDE_SESSION_ID="sess-st-28" \
    bash "$SELF" --emit-item <<<'{"kind":"action","node_id":"st28-root","item_id":"i-st28-a","text":"act"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp28" CLAUDE_SESSION_ID="sess-st-28" \
    bash "$SELF" --resolve-item <<<'{"node_id":"st28-root","item_id":"i-st28-a","resolution":"done"}' >/dev/null 2>&1
  local checked28
  checked28=$(node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.find(function(x){return x.node_id==="st28-root"});var it=n&&n.items&&n.items.find(function(i){return i.item_id==="i-st28-a"});process.stdout.write(it&&it.checked?"Y":"N")' "$LIB" "$sp28" 2>/dev/null)
  _ck "ST28 --resolve-item done -> action.checked" "$checked28" "Y"

  # ST29 — malformed --emit-item (missing required key) -> no-op, exit 0.
  local sp29="$tmp/st-29.json"
  CONV_TREE_STATE_PATH="$sp29" CLAUDE_SESSION_ID="sess-st-29" \
    bash "$SELF" --emit-item <<<'{"kind":"decision","node_id":"st29-root"}' >/dev/null 2>&1
  local rc29=$?
  if [[ $rc29 -eq 0 && ! -f "$sp29" ]]; then echo "PASS: ST29 malformed --emit-item -> no-op + exit 0"; pass=$((pass+1)); else echo "FAIL: ST29 malformed payload (rc=$rc29, file=$([ -f "$sp29" ] && echo present || echo absent))"; fail=$((fail+1)); fi

  # ST30 — --emit-item with unknown kind -> no-op, exit 0.
  local sp30="$tmp/st-30.json"
  CONV_TREE_STATE_PATH="$sp30" CLAUDE_SESSION_ID="sess-st-30" \
    bash "$SELF" --emit-item <<<'{"kind":"nonsense","node_id":"st30-root","item_id":"i","text":"x"}' >/dev/null 2>&1
  local rc30=$?
  if [[ $rc30 -eq 0 && ! -f "$sp30" ]]; then echo "PASS: ST30 unknown kind -> no-op + exit 0"; pass=$((pass+1)); else echo "FAIL: ST30 unknown kind (rc=$rc30)"; fail=$((fail+1)); fi

  # ST31 — --emit-branch idempotent: 3 re-fires -> exactly 1 branch-opened.
  local sp31="$tmp/st-31.json"
  for _r in 1 2 3; do
    CONV_TREE_STATE_PATH="$sp31" CLAUDE_SESSION_ID="sess-st-31" \
      bash "$SELF" --emit-branch <<<'{"node_id":"st31-root","parent_id":null,"title":"ST31 Root"}' >/dev/null 2>&1
  done
  _ck "ST31 --emit-branch idempotent on node_id" "$(_count "$sp31" branch-opened)" "1"

  # ST32-ST36: Workstreams Phase 3 — work-item declaration + lifecycle emit.
  # ST32: spawn declares an EXISTING work-item -> child branch carries
  # serves_item_id and a session-bound link is emitted.
  local sp32="$tmp/st-32.json"
  CONV_TREE_STATE_PATH="$sp32" CLAUDE_SESSION_ID="sess-st-32" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Serves Existing","prompt":"Work-item: wi-existing-99"},"session_id":"sess-st-32"}' >/dev/null 2>&1
  local serves32
  serves32=$(node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.find(function(x){return x.title==="Serves Existing"});process.stdout.write(n&&n.serves_item_id==="wi-existing-99"?"Y":"N")' "$LIB" "$sp32" 2>/dev/null)
  _ck "ST32 Work-item: <id> -> child branch carries serves_item_id" "$serves32" "Y"
  _ck "ST32b Work-item declared -> session-bound emitted" "$(_count "$sp32" session-bound)" "1"

  # ST33: spawn declares a NEW work-item -> the matching kind event creates the
  # item on the child branch (decision form here).
  local sp33="$tmp/st-33.json"
  CONV_TREE_STATE_PATH="$sp33" CLAUDE_SESSION_ID="sess-st-33" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"New WI","prompt":"Work-item: new — decision:Pick the approach"},"session_id":"sess-st-33"}' >/dev/null 2>&1
  local newitem33
  newitem33=$(node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.find(function(x){return x.title==="New WI"});var ok=n&&(n.items||[]).some(function(it){return it.kind==="decision"&&it.text==="Pick the approach"});process.stdout.write(ok?"Y":"N")' "$LIB" "$sp33" 2>/dev/null)
  _ck "ST33 Work-item: new — decision:... -> decision item on child branch" "$newitem33" "Y"

  # ST34: spawn WITHOUT a Work-item -> backward-compat (no session-bound; still
  # the root+child branch-opened pair).
  local sp34="$tmp/st-34.json"
  CONV_TREE_STATE_PATH="$sp34" CLAUDE_SESSION_ID="sess-st-34" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Plain Spawn","prompt":"just do some work, no declaration"},"session_id":"sess-st-34"}' >/dev/null 2>&1
  _ck "ST34 no Work-item -> NO session-bound (backward-compat)" "$(_count "$sp34" session-bound)" "0"
  _ck "ST34b no Work-item -> still 2 branch-opened (root+child)" "$(_count "$sp34" branch-opened)" "2"

  # ST35: --on-stop after a real commit -> the served (new) item-ships; because
  # item-shipped precedes concluded in the batch, FR-7 lets the node conclude.
  if command -v git >/dev/null 2>&1; then
    local G="$tmp/shiprepo"; mkdir -p "$G"
    ( cd "$G" && git init -q . && git config core.hooksPath "" && git config user.email t@e.test && git config user.name t \
        && echo a > a.txt && git add -A && git commit -qm base ) >/dev/null 2>&1
    local sp35="$tmp/st-35.json"
    ( cd "$G" && CONV_TREE_STATE_PATH="$sp35" CLAUDE_SESSION_ID="sess-st-35" \
        bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Ship Branch","prompt":"Work-item: new — action:Land the thing"},"session_id":"sess-st-35"}' >/dev/null 2>&1 )
    ( cd "$G" && echo b > b.txt && git add -A && git commit -qm work ) >/dev/null 2>&1
    ( cd "$G" && CONV_TREE_STATE_PATH="$sp35" CLAUDE_SESSION_ID="sess-st-35" \
        bash "$SELF" --on-stop <<<'{"session_id":"sess-st-35"}' >/dev/null 2>&1 )
    local shipped35
    shipped35=$(node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var ok=st.snapshot.nodes.some(function(n){return (n.items||[]).some(function(it){return it.state==="shipped"})});process.stdout.write(ok?"Y":"N")' "$LIB" "$sp35" 2>/dev/null)
    _ck "ST35 on-stop after commit -> served item state=shipped" "$shipped35" "Y"
    _ck "ST35b exactly 1 item-shipped event" "$(_count "$sp35" item-shipped)" "1"
  else
    echo "PASS: ST35 (skipped: git unavailable)"; pass=$((pass+1))
    echo "PASS: ST35b (skipped: git unavailable)"; pass=$((pass+1))
  fi

  # ST36: --on-stop with NO commit (HEAD unchanged) -> no item-shipped (no
  # false ship); the unshipped declared item leaves the branch open (orphan
  # candidate) — exactly the Phase-4 surface.
  if command -v git >/dev/null 2>&1; then
    local G2="$tmp/noshiprepo"; mkdir -p "$G2"
    ( cd "$G2" && git init -q . && git config core.hooksPath "" && git config user.email t@e.test && git config user.name t \
        && echo a > a.txt && git add -A && git commit -qm base ) >/dev/null 2>&1
    local sp36="$tmp/st-36.json"
    ( cd "$G2" && CONV_TREE_STATE_PATH="$sp36" CLAUDE_SESSION_ID="sess-st-36" \
        bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"No Ship","prompt":"Work-item: new — action:Maybe later"},"session_id":"sess-st-36"}' >/dev/null 2>&1 )
    ( cd "$G2" && CONV_TREE_STATE_PATH="$sp36" CLAUDE_SESSION_ID="sess-st-36" \
        bash "$SELF" --on-stop <<<'{"session_id":"sess-st-36"}' >/dev/null 2>&1 )
    _ck "ST36 on-stop without commit -> NO item-shipped (no false ship)" "$(_count "$sp36" item-shipped)" "0"
  else
    echo "PASS: ST36 (skipped: git unavailable)"; pass=$((pass+1))
  fi

  # ST37-ST42: Task 9 (2026-06-12) — context-payload discipline on the emit
  # path. Locks the contract in rules/workstreams-state.md "Context-complete
  # item emission": valid payloads normalize through the SOLE-NORMATIVE
  # schema module; invalid payloads land raw + WARN; payload-less raises land
  # + WARN; the Work-item:new spawn path assembles details from the prompt
  # sentinels; --emit-details enrichment applies last-writer-wins.
  _item_det() { # statefile item_id detail-field -> value ("" when absent)
    node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var id=process.argv[3],f=process.argv[4],out="";st.snapshot.nodes.forEach(function(n){(n.items||[]).forEach(function(it){if(it.item_id===id&&it.details)out=it.details[f]===undefined||it.details[f]===null?"":String(it.details[f])})});process.stdout.write(out)}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2" "$3" 2>/dev/null
  }

  # ST37 — --emit-item decision with a VALID per-kind payload -> the sibling
  # item-details-set carries the NORMALIZED payload (_category + surfaced_by
  # stamped by the sole-normative assembler).
  local sp37="$tmp/st-37.json"
  CONV_TREE_STATE_PATH="$sp37" CLAUDE_SESSION_ID="sess-st-37" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st37-root","parent_id":null,"title":"ST37 Root"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp37" CLAUDE_SESSION_ID="sess-st-37" \
    bash "$SELF" --emit-item <<<'{"kind":"decision","node_id":"st37-root","item_id":"i-st37-d","text":"Apply m162 now?","details":{"background":"We are deciding whether to apply migration m162 to prod; it gates the launch.","question":"Apply m162 to production now, or wait?","options":[{"name":"apply now"},{"name":"wait"}],"recommendation":"apply now"}}' >/dev/null 2>&1
  _ck "ST37 valid payload -> item-details-set emitted" "$(_count "$sp37" item-details-set)" "1"
  _ck "ST37b normalized details._category stamped" "$(_item_det "$sp37" "i-st37-d" "_category")" "decision"
  _ck "ST37c normalized details.surfaced_by stamped" "$(_item_det "$sp37" "i-st37-d" "surfaced_by")" "workstreams-emit"

  # ST38 — --emit-item with an INVALID payload (no background -> fails the
  # cold-read bar) -> the RAW payload still lands (information-preserving;
  # the GUI flags context-incomplete) + a schema-FAIL WARN in the audit log.
  LOG_BEFORE=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  local sp38="$tmp/st-38.json"
  CONV_TREE_STATE_PATH="$sp38" CLAUDE_SESSION_ID="sess-st-38" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st38-root","parent_id":null,"title":"ST38 Root"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp38" CLAUDE_SESSION_ID="sess-st-38" \
    bash "$SELF" --emit-item <<<'{"kind":"decision","node_id":"st38-root","item_id":"i-st38-d","text":"Partial","details":{"recommendation":"do A"}}' >/dev/null 2>&1
  LOG_AFTER=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  _ck "ST38 invalid payload still lands raw (info-preserving)" "$(_item_det "$sp38" "i-st38-d" "recommendation")" "do A"
  if tail -n $((LOG_AFTER - LOG_BEFORE + 1)) "$LOG_FILE" 2>/dev/null | grep -q 'WARN: emit-item .* details FAIL the sole-normative context schema'; then
    echo "PASS: ST38b invalid payload -> schema-FAIL WARN logged"; pass=$((pass+1))
  else
    echo "FAIL: ST38b expected schema-FAIL WARN in audit log"; fail=$((fail+1))
  fi

  # ST39 — --emit-item with NO payload -> the item still emits (writer never
  # blocks) but is born context-incomplete: zero item-details-set + WARN.
  LOG_BEFORE=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  local sp39="$tmp/st-39.json"
  CONV_TREE_STATE_PATH="$sp39" CLAUDE_SESSION_ID="sess-st-39" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st39-root","parent_id":null,"title":"ST39 Root"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp39" CLAUDE_SESSION_ID="sess-st-39" \
    bash "$SELF" --emit-item <<<'{"kind":"question","node_id":"st39-root","item_id":"i-st39-q","text":"Which env?"}' >/dev/null 2>&1
  LOG_AFTER=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  _ck "ST39 payload-less raise still emits the item" "$(_count "$sp39" question-raised)" "1"
  _ck "ST39b payload-less raise -> NO item-details-set" "$(_count "$sp39" item-details-set)" "0"
  if tail -n $((LOG_AFTER - LOG_BEFORE + 1)) "$LOG_FILE" 2>/dev/null | grep -q 'WARN: emit-item .* raised WITHOUT a context payload'; then
    echo "PASS: ST39c payload-less raise -> born-context-incomplete WARN logged"; pass=$((pass+1))
  else
    echo "FAIL: ST39c expected born-context-incomplete WARN in audit log"; fail=$((fail+1))
  fi

  # ST40 — Work-item: new + rich-detail sentinels -> the spawn assembles the
  # per-kind payload from Instructions:/Recommendation:/Links: and the new
  # item is BORN context-complete (item-details-set in the same batch).
  local sp40="$tmp/st-40.json"
  CONV_TREE_STATE_PATH="$sp40" CLAUDE_SESSION_ID="sess-st-40" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Born Complete","prompt":"Work-item: new — decision:Pick the rollout strategy\nInstructions: choosing how to roll out the new billing flow to existing orgs\nRecommendation: staged rollout starting with internal orgs\nLinks: docs/plans/billing.md"},"session_id":"sess-st-40"}' >/dev/null 2>&1
  _ck "ST40 Work-item:new + sentinels -> item-details-set in spawn batch" "$(_count "$sp40" item-details-set)" "1"
  local born40
  born40=$(node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var ok=st.snapshot.nodes.some(function(n){return (n.items||[]).some(function(it){return it.kind==="decision"&&it.details&&/billing flow/.test(it.details.background||"")&&it.details._category==="decision"&&it.details.recommendation==="staged rollout starting with internal orgs"})});process.stdout.write(ok?"Y":"N")}catch(e){process.stdout.write("ERR")}' "$LIB" "$sp40" 2>/dev/null)
  _ck "ST40b decision born context-complete (background=Instructions:, recommendation carried)" "$born40" "Y"

  # ST41 — Work-item: new WITHOUT sentinels -> item still created (ST33
  # behavior preserved) but born honestly detail-less: no item-details-set.
  local sp41="$tmp/st-41.json"
  CONV_TREE_STATE_PATH="$sp41" CLAUDE_SESSION_ID="sess-st-41" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Born Bare","prompt":"Work-item: new — question:Which env should the demo use?"},"session_id":"sess-st-41"}' >/dev/null 2>&1
  _ck "ST41 no sentinels -> NO item-details-set (born honestly detail-less)" "$(_count "$sp41" item-details-set)" "0"
  _ck "ST41b the item itself is still created" "$(_count "$sp41" question-raised)" "1"

  # ST42 — --emit-details enrichment applies LAST-WRITER-WINS. The old
  # (node|item)-only event-id derivation made a revision an idempotent no-op
  # (store.js skips duplicate event_ids), silently breaking the enrichment
  # loop the GUI's "needs enrichment" gate depends on. Content-hashed ids fix
  # it: v2 is a NEW event the reducer applies as a replace.
  local sp42="$tmp/st-42.json"
  CONV_TREE_STATE_PATH="$sp42" CLAUDE_SESSION_ID="sess-st-42" \
    bash "$SELF" --emit-branch <<<'{"node_id":"st42-root","parent_id":null,"title":"ST42 Root"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp42" CLAUDE_SESSION_ID="sess-st-42" \
    bash "$SELF" --emit-item <<<'{"kind":"question","node_id":"st42-root","item_id":"i-st42-q","text":"Which env?"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp42" CLAUDE_SESSION_ID="sess-st-42" \
    bash "$SELF" --emit-details <<<'{"node_id":"st42-root","item_id":"i-st42-q","details":{"background":"ctx v1 for the enrichment-loop test","question":"Which env?"}}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp42" CLAUDE_SESSION_ID="sess-st-42" \
    bash "$SELF" --emit-details <<<'{"node_id":"st42-root","item_id":"i-st42-q","details":{"background":"ctx v2 REVISED for the enrichment-loop test","question":"Which env?"}}' >/dev/null 2>&1
  case "$(_item_det "$sp42" "i-st42-q" "background")" in
    *"v2 REVISED"*) echo "PASS: ST42 enrichment revision applies (last-writer-wins restored)"; pass=$((pass+1)) ;;
    *) echo "FAIL: ST42 revision did not apply (got '$(_item_det "$sp42" "i-st42-q" "background")')"; fail=$((fail+1)) ;;
  esac
  _ck "ST42b two distinct item-details-set events (content-hashed ids)" "$(_count "$sp42" item-details-set)" "2"

  # BD1-BD10: builder-dispatch work-item emission (ADR-054, 2026-06-10).
  # Helper: read one field of the builder item from the state file.
  _bd_item() { # statefile item_id jq-expr
    node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var id=process.argv[3];var expr=process.argv[4];var found=null;st.snapshot.nodes.forEach(function(n){(n.items||[]).forEach(function(it){if(it.item_id===id)found=it})});if(!found){process.stdout.write("MISSING")}else{var v=found;expr.split(".").forEach(function(k){v=v&&v[k]});process.stdout.write(v===undefined||v===null?"":String(v))}' "$LIB" "$1" "$2" "$3" 2>/dev/null
  }
  _bd_itemid_of() { # statefile -> first wi-bd-* item id
    node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var out="";st.snapshot.nodes.forEach(function(n){(n.items||[]).forEach(function(it){if(/^wi-bd-/.test(it.item_id))out=it.item_id})});process.stdout.write(out)' "$LIB" "$1" 2>/dev/null
  }

  # BD1: Task dispatch -> action-added work-item on the ss-* session node.
  local spB1="$tmp/bd-1.json"
  CONV_TREE_STATE_PATH="$spB1" CLAUDE_SESSION_ID="sess-bd-1" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build the widget","prompt":"long body"},"session_id":"sess-bd-1"}' >/dev/null 2>&1
  local idB1; idB1=$(_bd_itemid_of "$spB1")
  if [[ -n "$idB1" && "$(_bd_item "$spB1" "$idB1" 'kind')" == "action" && "$(_bd_item "$spB1" "$idB1" 'text')" == "Build the widget" ]]; then
    echo "PASS: BD1 Task dispatch -> action work-item on session node"; pass=$((pass+1))
  else
    echo "FAIL: BD1 (item='$idB1' kind='$(_bd_item "$spB1" "$idB1" 'kind')' text='$(_bd_item "$spB1" "$idB1" 'text')')"; fail=$((fail+1))
  fi
  # BD1b: the item lives on the SAME ss-* node --on-session-start would use.
  local ownerB1
  ownerB1=$(node -e 'var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var out="";st.snapshot.nodes.forEach(function(n){(n.items||[]).some(function(it){return /^wi-bd-/.test(it.item_id)})&&(out=n.node_id)});process.stdout.write(out)' "$LIB" "$spB1" 2>/dev/null)
  case "$ownerB1" in ss-*) echo "PASS: BD1b item owner is the ss-* session node"; pass=$((pass+1)) ;; *) echo "FAIL: BD1b owner='$ownerB1'"; fail=$((fail+1)) ;; esac

  # BD2: details._category=builder-dispatch (never a Misha-ask -> never Awaiting-me).
  _ck "BD2 details._category=builder-dispatch (noise control)" "$(_bd_item "$spB1" "$idB1" 'details._category')" "builder-dispatch"

  # BD3: idempotent — 3 re-fires of the same dispatch -> exactly 1 action-added.
  local spB3="$tmp/bd-3.json"
  for _r in 1 2 3; do
    CONV_TREE_STATE_PATH="$spB3" CLAUDE_SESSION_ID="sess-bd-3" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Agent","tool_input":{"description":"Idem builder"},"session_id":"sess-bd-3"}' >/dev/null 2>&1
  done
  _ck "BD3 builder dispatch idempotent on (session,tool,title)" "$(_count "$spB3" action-added)" "1"

  # BD4: foreground completion — PostToolUse return == completion -> action-done.
  local spB4="$tmp/bd-4.json"
  CONV_TREE_STATE_PATH="$spB4" CLAUDE_SESSION_ID="sess-bd-4" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Finish me"},"session_id":"sess-bd-4"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$spB4" CLAUDE_SESSION_ID="sess-bd-4" \
    bash "$SELF" --on-builder-complete <<<'{"tool_name":"Task","tool_input":{"description":"Finish me"},"tool_response":"done ok","session_id":"sess-bd-4"}' >/dev/null 2>&1
  local idB4; idB4=$(_bd_itemid_of "$spB4")
  _ck "BD4 foreground complete -> item.checked" "$(_bd_item "$spB4" "$idB4" 'checked')" "true"

  # BD5: Workflow launch — PostToolUse is launch-ack, NOT completion -> stays open.
  local spB5="$tmp/bd-5.json"
  local obs_bg_ledger="$tmp/obs-bg-ledger.jsonl"
  SIGNAL_LEDGER_PATH="$obs_bg_ledger" CONV_TREE_STATE_PATH="$spB5" CLAUDE_SESSION_ID="sess-bd-5" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Workflow","tool_input":{"meta":{"name":"Nightly sweep"},"prompt":"body"},"session_id":"sess-bd-5"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$spB5" CLAUDE_SESSION_ID="sess-bd-5" \
    bash "$SELF" --on-builder-complete <<<'{"tool_name":"Workflow","tool_input":{"meta":{"name":"Nightly sweep"},"prompt":"body"},"tool_response":"launched id=wf-1","session_id":"sess-bd-5"}' >/dev/null 2>&1
  local idB5; idB5=$(_bd_itemid_of "$spB5")
  if [[ -n "$idB5" && "$(_bd_item "$spB5" "$idB5" 'checked')" != "true" ]]; then
    echo "PASS: BD5 Workflow launch-return does NOT mark done (honest ceiling)"; pass=$((pass+1))
  else
    echo "FAIL: BD5 (item='$idB5' checked='$(_bd_item "$spB5" "$idB5" 'checked')')"; fail=$((fail+1))
  fi
  _ck "BD5b Workflow title from meta.name" "$(_bd_item "$spB5" "$idB5" 'text')" "Nightly sweep"

  # OBS4 (Wave O task O.1, contract C2): --on-builder-dispatch for a
  # genuinely-background dispatch (Workflow, bg==1 per _builder_is_background)
  # emits bg-task-started. Reuses the SIGNAL_LEDGER_PATH set alongside BD5's
  # own --on-builder-dispatch call immediately above.
  if [[ -f "$obs_bg_ledger" ]] && grep -q '"gate":"workstreams-emit".*"event":"bg-task-started"' "$obs_bg_ledger" 2>/dev/null && grep -q 'Nightly sweep' "$obs_bg_ledger" 2>/dev/null; then
    echo "PASS: OBS4 --on-builder-dispatch (background Workflow) emits bg-task-started"; pass=$((pass+1))
  else
    echo "FAIL: OBS4 --on-builder-dispatch (background Workflow) emits bg-task-started (expected a workstreams-emit/bg-task-started line naming 'Nightly sweep' in $obs_bg_ledger)"; fail=$((fail+1))
  fi

  # OBS5: a FOREGROUND dispatch (bg==0, e.g. BD1's plain Task) must NOT emit
  # bg-task-started (the emit is scoped strictly to bg=="1").
  local obs_fg_ledger="$tmp/obs-fg-ledger.jsonl"
  SIGNAL_LEDGER_PATH="$obs_fg_ledger" CONV_TREE_STATE_PATH="$tmp/obs-fg.json" CLAUDE_SESSION_ID="sess-obs-fg" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Foreground only"},"session_id":"sess-obs-fg"}' >/dev/null 2>&1
  if [[ ! -f "$obs_fg_ledger" ]] || ! grep -q '"event":"bg-task-started"' "$obs_fg_ledger" 2>/dev/null; then
    echo "PASS: OBS5 foreground dispatch (bg==0) emits NO bg-task-started"; pass=$((pass+1))
  else
    echo "FAIL: OBS5 foreground dispatch (bg==0) emits NO bg-task-started"; fail=$((fail+1))
  fi

  # BD6: Agent run_in_background:true -> completion NOT emitted at PostToolUse.
  local spB6="$tmp/bd-6.json"
  CONV_TREE_STATE_PATH="$spB6" CLAUDE_SESSION_ID="sess-bd-6" \
    bash "$SELF" --on-builder-complete <<<'{"tool_name":"Agent","tool_input":{"description":"BG agent","run_in_background":true},"tool_response":"handle-7","session_id":"sess-bd-6"}' >/dev/null 2>&1
  local idB6; idB6=$(_bd_itemid_of "$spB6")
  if [[ -n "$idB6" && "$(_bd_item "$spB6" "$idB6" 'checked')" != "true" ]]; then
    echo "PASS: BD6 run_in_background Agent -> item created, NOT done"; pass=$((pass+1))
  else
    echo "FAIL: BD6 (item='$idB6' checked='$(_bd_item "$spB6" "$idB6" 'checked')')"; fail=$((fail+1))
  fi

  # BD7: non-builder tool -> no-op (no state file written).
  local spB7="$tmp/bd-7.json"
  CONV_TREE_STATE_PATH="$spB7" CLAUDE_SESSION_ID="sess-bd-7" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"sess-bd-7"}' >/dev/null 2>&1
  if [[ -f "$spB7" ]]; then echo "FAIL: BD7 non-builder tool must be a no-op"; fail=$((fail+1)); else echo "PASS: BD7 non-builder tool no-op"; pass=$((pass+1)); fi

  # BD8: Dispatch spawn tools are --on-spawn's surface -> no-op in this mode.
  local spB8="$tmp/bd-8.json"
  CONV_TREE_STATE_PATH="$spB8" CLAUDE_SESSION_ID="sess-bd-8" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Not mine"},"session_id":"sess-bd-8"}' >/dev/null 2>&1
  if [[ -f "$spB8" ]]; then echo "FAIL: BD8 Dispatch spawn must not be handled by --on-builder-dispatch"; fail=$((fail+1)); else echo "PASS: BD8 Dispatch spawn -> no-op in builder mode"; pass=$((pass+1)); fi

  # BD9: failure isolation — broken state-lib -> exit 0, never blocks.
  local spB9="$tmp/bd-9.json" rcB9
  CONV_TREE_STATE_PATH="$spB9" CONV_TREE_STATE_LIB="$tmp/does-not-exist.js" CLAUDE_SESSION_ID="sess-bd-9" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Iso"},"session_id":"sess-bd-9"}' >/dev/null 2>&1
  rcB9=$?
  _ck "BD9 builder emit failure isolation -> exit 0" "$rcB9" "0"

  # BD10: complete-without-prior-dispatch (missed PreToolUse) -> creation batch
  # rides in the complete emission: item exists AND is done in one shot.
  local spB10="$tmp/bd-10.json"
  CONV_TREE_STATE_PATH="$spB10" CLAUDE_SESSION_ID="sess-bd-10" \
    bash "$SELF" --on-builder-complete <<<'{"tool_name":"Task","tool_input":{"description":"Pre was missed"},"tool_response":"ok","session_id":"sess-bd-10"}' >/dev/null 2>&1
  local idB10; idB10=$(_bd_itemid_of "$spB10")
  _ck "BD10 complete-without-pre -> item created + checked" "$(_bd_item "$spB10" "$idB10" 'checked')" "true"

  # ================================================================
  # OBS1/OBS2 (Wave O task O.1, specs-o §O.1 deliverable 3, contract C2):
  # --on-spawn emits spawn-dispatched; --on-stop emits spawn-concluded.
  # SIGNAL_LEDGER_PATH is set explicitly (rather than relying on the
  # HARNESS_SELFTEST=1 PID-scoped default) so both the spawn and the stop
  # calls below — two separate `bash "$SELF"` child processes with two
  # different PIDs — write to the SAME fixture ledger file this scenario
  # asserts against.
  # ================================================================
  local spOBS="$tmp/obs-1.json"
  local obs_ledger="$tmp/obs-ledger.jsonl"
  CONV_TREE_STATE_PATH="$spOBS" SIGNAL_LEDGER_PATH="$obs_ledger" CLAUDE_SESSION_ID="sess-obs-1" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Obs Spawn"},"session_id":"sess-obs-1"}' >/dev/null 2>&1
  if [[ -f "$obs_ledger" ]] && grep -q '"gate":"workstreams-emit".*"event":"spawn-dispatched"' "$obs_ledger" 2>/dev/null && grep -q 'title=\\"Obs Spawn\\"' "$obs_ledger" 2>/dev/null; then
    echo "PASS: OBS1 --on-spawn emits spawn-dispatched (contract C2, title carried in detail)"; pass=$((pass+1))
  else
    echo "FAIL: OBS1 --on-spawn emits spawn-dispatched (expected a workstreams-emit/spawn-dispatched line naming 'Obs Spawn' in $obs_ledger)"; fail=$((fail+1))
    [[ -f "$obs_ledger" ]] && cat "$obs_ledger"
  fi
  CONV_TREE_STATE_PATH="$spOBS" SIGNAL_LEDGER_PATH="$obs_ledger" CLAUDE_SESSION_ID="sess-obs-1" \
    bash "$SELF" --on-stop <<<'{"session_id":"sess-obs-1"}' >/dev/null 2>&1
  if grep -q '"gate":"workstreams-emit".*"event":"spawn-concluded"' "$obs_ledger" 2>/dev/null && grep -q 'session=sess-obs-1 concluded=' "$obs_ledger" 2>/dev/null; then
    echo "PASS: OBS2 --on-stop emits spawn-concluded (contract C2)"; pass=$((pass+1))
  else
    echo "FAIL: OBS2 --on-stop emits spawn-concluded (expected a workstreams-emit/spawn-concluded line in $obs_ledger)"; fail=$((fail+1))
    [[ -f "$obs_ledger" ]] && cat "$obs_ledger"
  fi

  # OBS3: a Stop with NOTHING to conclude (no prior spawn — mirrors ST12's
  # silent-no-op fixture) emits NO spawn-concluded event (the guard only
  # fires when $first==0, i.e. >=1 branch was actually concluded).
  local obs_ledger3="$tmp/obs-ledger-3.json"
  SIGNAL_LEDGER_PATH="$obs_ledger3" CLAUDE_SESSION_ID="sess-obs-3-never-spawned" \
    bash "$SELF" --on-stop <<<'{"session_id":"sess-obs-3-never-spawned"}' >/dev/null 2>&1
  if [[ ! -f "$obs_ledger3" ]] || ! grep -q '"event":"spawn-concluded"' "$obs_ledger3" 2>/dev/null; then
    echo "PASS: OBS3 --on-stop with nothing to conclude emits no spawn-concluded event"; pass=$((pass+1))
  else
    echo "FAIL: OBS3 --on-stop with nothing to conclude emits no spawn-concluded event"; fail=$((fail+1))
  fi

  rm -rf "$tmp" 2>/dev/null || true
  echo "self-test: $pass passed, $fail failed"
  if [[ $fail -eq 0 ]]; then echo "self-test: OK"; exit 0; else echo "self-test: FAIL"; exit 1; fi
}

# ============================================================================
# Orchestrator-emit modes (the Dispatch-orchestrator surface for raising
# user-visible items into the conversation tree).
#
# The conversation tree models what flows BETWEEN Misha and the orchestrator —
# branches (spawns) capture the containers; items capture decisions Misha needs
# to make, questions awaiting his input, and actions only he can take. Without
# these modes, the tree only ever shows containers; items would only ever land
# via the GUI's own "Add" UI, never via the Dispatch orchestrator that surfaces
# them in conversation.
#
# Every emit call shares the SAME write path the spawn hook uses (`_emit_dual`
# → state-library `appendEvent`), so idempotency, atomic publish, attestation,
# and worktree→main-checkout sink resolution are all reused — no parallel
# write path to maintain.
#
# Invocation convention: every mode reads a JSON payload from stdin. The
# orchestrator constructs the JSON inline and pipes it in via a here-doc.
#
#   --emit-branch        (re-opens or creates a logical conversation thread
#                         under a parent — used when the orchestrator wants a
#                         new branch that did NOT come from a Dispatch spawn.
#                         No-ops if node_id already exists.)
#     stdin: {"node_id":"<id>","parent_id":"<parent>|null","title":"<…>"}
#
#   --emit-item          (raises ONE item under an existing branch — the
#                         primary "now-Misha-has-something-to-act-on" hook.)
#     stdin: {"kind":"decision|question|action","node_id":"<branch>",
#             "item_id":"<id>","text":"<one-liner>",
#             "details":{...per-kind context payload...}}
#     `details` SHOULD carry the per-kind context payload (the contract in
#     rules/workstreams-state.md "Context-complete item emission" — minimum:
#     `background` + the per-kind actionable field). When present, it is
#     validated through the SOLE-NORMATIVE module
#     (decision-context-schema.js assembleItemDetails) and emitted as a
#     sibling `item-details-set` in the same batch: valid -> normalized
#     payload; invalid -> raw payload + audit-log WARN (the GUI flags the
#     item context-incomplete). When absent, the item still emits (never
#     blocks) but is born context-incomplete and a WARN lands in the audit
#     log.
#
#   --emit-details       (sets / replaces rich details on an existing item —
#                         the enrichment path for items born detail-less.)
#     stdin: {"node_id":"<branch>","item_id":"<id>","details":{...}}
#     Same sole-normative validation as --emit-item (category from
#     ._category, else looked up from the item's kind). Content-hashed
#     event id: identical re-emits dedupe; revised content applies
#     last-writer-wins.
#
#   --resolve-item       (closes an existing item with answered / action-done /
#                         item-backlogged. The orchestrator uses this when
#                         Misha's reply resolves a previously-raised item.)
#     stdin: {"node_id":"<branch>","item_id":"<id>",
#             "resolution":"answered|done|backlogged"}
#
# All emit modes are idempotent on a deterministic event_id derived from the
# (type, node_id, item_id) tuple — re-firing the same emit is a per-file no-op.
# All emit modes are non-blocking: a malformed payload logs and exits 0 (writer
# hook, never breaks the orchestrator).
# ============================================================================

# Validate that a JSON payload supplied via stdin contains the given top-level
# keys (all required, non-empty). Returns 0 if valid, non-zero on missing keys
# (caller logs and skips emission — non-fatal).
_validate_keys() {
  local input="$1"; shift
  _have jq || { _log "jq unavailable — cannot validate emit payload"; return 1; }
  local k missing=""
  for k in "$@"; do
    local v
    v=$(printf '%s' "$input" | jq -r --arg k "$k" '.[$k] // empty' 2>/dev/null)
    if [[ -z "$v" || "$v" == "null" ]]; then missing="$missing $k"; fi
  done
  if [[ -n "$missing" ]]; then _log "emit-mode missing required keys:$missing"; return 1; fi
  return 0
}

# Emit a one-or-more-event batch (events_file is a JSON array). Wraps
# _emit_dual so callers stay uniform.
_emit_batch_from_payload() {
  local events_json="$1"
  local lib; lib=$(_resolve_state_lib)
  local ef; ef=$(mktemp 2>/dev/null || echo "/tmp/cte-emit-$$.json")
  printf '%s' "$events_json" >"$ef"
  _emit_dual "$lib" "$ef"
  rm -f "$ef" 2>/dev/null || true
}

# ----------------------------------------------------------------------------
# --emit-branch — create a logical conversation thread under a parent.
# Idempotent (event_id derived from node_id; reducer rejects duplicate node_id).
# ----------------------------------------------------------------------------
_run_emit_branch() {
  local input; input=$(_read_stdin)
  [[ -z "$input" ]] && { _log "emit-branch: empty stdin"; exit 0; }
  _validate_keys "$input" node_id title || exit 0

  local node_id parent_id title
  node_id=$(printf '%s' "$input" | jq -r '.node_id' 2>/dev/null)
  parent_id=$(printf '%s' "$input" | jq -r '.parent_id // empty' 2>/dev/null)
  title=$(printf '%s' "$input" | jq -r '.title' 2>/dev/null)

  local ev_id; ev_id="cte-bo-$(printf '%s' "$node_id" | _sha1 | cut -c1-32)"
  local parent_json
  if [[ -z "$parent_id" || "$parent_id" == "null" ]]; then
    parent_json="null"
  else
    parent_json=$(jq -Rn --arg p "$parent_id" '$p')
  fi
  local title_json; title_json=$(jq -Rn --arg t "$title" '$t')

  local events
  events=$(printf '[{"event_id":"%s","type":"branch-opened","node_id":"%s","parent_id":%s,"title":%s,"actor":"dispatch"}]' \
    "$ev_id" "$node_id" "$parent_json" "$title_json")
  _emit_batch_from_payload "$events"
  _log "emit-branch node_id=$node_id parent_id=${parent_id:-null} title=\"$title\""
  exit 0
}

# ----------------------------------------------------------------------------
# --emit-item — raise ONE item (decision|question|action) on a branch.
# Optional .details triggers a follow-up item-details-set in the same batch.
# Idempotent on (kind, node_id, item_id) — reducer rejects duplicate item_id.
# ----------------------------------------------------------------------------
_run_emit_item() {
  local input; input=$(_read_stdin)
  [[ -z "$input" ]] && { _log "emit-item: empty stdin"; exit 0; }
  _validate_keys "$input" kind node_id item_id text || exit 0

  local kind node_id item_id text details
  kind=$(printf '%s' "$input" | jq -r '.kind' 2>/dev/null)
  node_id=$(printf '%s' "$input" | jq -r '.node_id' 2>/dev/null)
  item_id=$(printf '%s' "$input" | jq -r '.item_id' 2>/dev/null)
  text=$(printf '%s' "$input" | jq -r '.text' 2>/dev/null)
  details=$(printf '%s' "$input" | jq -c '.details // empty' 2>/dev/null)

  local ev_type
  case "$kind" in
    decision) ev_type="decision-raised" ;;
    question) ev_type="question-raised" ;;
    action)   ev_type="action-added" ;;
    *) _log "emit-item: unknown kind '$kind'"; exit 0 ;;
  esac

  # Task 9 (2026-06-12) — context-payload discipline. A supplied .details is
  # validated through the SOLE-NORMATIVE schema module (assembleItemDetails):
  #   valid   -> emit the NORMALIZED payload (_category + surfaced_by stamped)
  #   invalid -> emit the RAW payload anyway (information-preserving; the GUI
  #              flags the item context-incomplete) + WARN in the audit log
  #   non-operator _category (e.g. builder-dispatch) -> passthrough untouched
  #   module unavailable -> passthrough untouched (graceful degradation)
  # NO .details on an operator-facing raise -> WARN: born context-incomplete.
  # Never blocks; never drops the item itself (writer, not gate).
  local category; category=$(_kind_to_category "$kind")
  if [[ -n "$details" && "$details" != "null" ]]; then
    local verdict; verdict=$(_normalize_item_details "$category" "$details")
    case "$verdict" in
      OK\ *)
        details="${verdict#OK }"
        _log "emit-item kind=$kind item_id=$item_id details validated against the sole-normative context schema (category=$category)"
        ;;
      INVALID\ *)
        _log "WARN: emit-item kind=$kind node_id=$node_id item_id=$item_id details FAIL the sole-normative context schema (${verdict#INVALID }) — emitted as-is so no information is lost; the GUI flags the item context-incomplete. Contract: rules/workstreams-state.md \"Context-complete item emission\"."
        ;;
      SKIP)
        : ;;  # non-operator noise-control _category — deliberate, untouched
      *)
        _log "emit-item: schema module unavailable — details passed through unvalidated"
        ;;
    esac
  else
    _log "WARN: emit-item kind=$kind node_id=$node_id item_id=$item_id raised WITHOUT a context payload — the item is born context-incomplete (no background/options/recommendation for the operator). Supply .details per rules/workstreams-state.md \"Context-complete item emission\"."
  fi

  local ev_id; ev_id="cte-${ev_type:0:6}-$(printf '%s|%s' "$node_id" "$item_id" | _sha1 | cut -c1-32)"
  local text_json; text_json=$(jq -Rn --arg t "$text" '$t')

  local events
  if [[ -n "$details" && "$details" != "null" ]]; then
    # Content-hashed event id: re-firing the same emit dedupes; a later
    # details revision (different content) is a NEW event the reducer applies
    # last-writer-wins — so enrichment-over-time actually lands.
    local det_ev_id; det_ev_id="cte-detset-$(printf '%s|%s|%s' "$node_id" "$item_id" "$details" | _sha1 | cut -c1-32)"
    events=$(printf '[{"event_id":"%s","type":"%s","node_id":"%s","item_id":"%s","text":%s,"actor":"dispatch"},{"event_id":"%s","type":"item-details-set","node_id":"%s","item_id":"%s","details":%s,"actor":"dispatch"}]' \
      "$ev_id" "$ev_type" "$node_id" "$item_id" "$text_json" \
      "$det_ev_id" "$node_id" "$item_id" "$details")
  else
    events=$(printf '[{"event_id":"%s","type":"%s","node_id":"%s","item_id":"%s","text":%s,"actor":"dispatch"}]' \
      "$ev_id" "$ev_type" "$node_id" "$item_id" "$text_json")
  fi
  _emit_batch_from_payload "$events"
  _log "emit-item kind=$kind node_id=$node_id item_id=$item_id text=\"$text\""
  exit 0
}

# ----------------------------------------------------------------------------
# --emit-details — set rich details on an existing item (last-writer-wins).
# Useful for backfilling content the orchestrator obtained AFTER raising the
# item, or for refining detail content over time.
# ----------------------------------------------------------------------------
_run_emit_details() {
  local input; input=$(_read_stdin)
  [[ -z "$input" ]] && { _log "emit-details: empty stdin"; exit 0; }
  _validate_keys "$input" node_id item_id details || exit 0

  local node_id item_id details
  node_id=$(printf '%s' "$input" | jq -r '.node_id' 2>/dev/null)
  item_id=$(printf '%s' "$input" | jq -r '.item_id' 2>/dev/null)
  details=$(printf '%s' "$input" | jq -c '.details' 2>/dev/null)

  # Task 9 (2026-06-12) — same context-payload discipline as --emit-item.
  # Category resolution: an explicit operator-facing ._category wins; else
  # the existing item's kind is looked up from the sink snapshot. A
  # NON-operator _category (noise-control tier) or an unresolvable category
  # passes through untouched.
  local category="" det_cat
  det_cat=$(printf '%s' "$details" | jq -r '._category // empty' 2>/dev/null)
  case "$det_cat" in
    decision|question|action_item_for_user|autonomous_action) category="$det_cat" ;;
    "")
      local item_kind; item_kind=$(_kind_of_item "$item_id")
      category=$(_kind_to_category "$item_kind")
      ;;
    *) category="" ;;  # non-operator noise-control _category — untouched
  esac
  if [[ -n "$category" ]]; then
    local verdict; verdict=$(_normalize_item_details "$category" "$details")
    case "$verdict" in
      OK\ *)
        details="${verdict#OK }"
        _log "emit-details item_id=$item_id details validated against the sole-normative context schema (category=$category)"
        ;;
      INVALID\ *)
        _log "WARN: emit-details node_id=$node_id item_id=$item_id details FAIL the sole-normative context schema (${verdict#INVALID }) — emitted as-is; the GUI flags the item context-incomplete. Contract: rules/workstreams-state.md \"Context-complete item emission\"."
        ;;
      SKIP|*) : ;;
    esac
  fi

  # Content-hashed event id (Task 9 fix): the previous (node_id, item_id)-only
  # derivation made a SECOND emit-details with NEW content an idempotent
  # no-op (appendEvent skips duplicate event_ids — store.js §2), silently
  # breaking the enrichment loop the GUI's "needs enrichment" gate depends
  # on. Hashing the content restores true last-writer-wins: identical re-emit
  # dedupes; revised content is a new event the reducer applies as a replace.
  local ev_id; ev_id="cte-detset-$(printf '%s|%s|%s' "$node_id" "$item_id" "$details" | _sha1 | cut -c1-32)"
  local events
  events=$(printf '[{"event_id":"%s","type":"item-details-set","node_id":"%s","item_id":"%s","details":%s,"actor":"dispatch"}]' \
    "$ev_id" "$node_id" "$item_id" "$details")
  _emit_batch_from_payload "$events"
  _log "emit-details node_id=$node_id item_id=$item_id"
  exit 0
}

# ----------------------------------------------------------------------------
# --resolve-item — close an existing item.
#   resolution=answered    -> answered (decision/question)
#   resolution=done        -> action-done (action)
#   resolution=backlogged  -> item-backlogged (moves out of "Waiting on you")
# ----------------------------------------------------------------------------
_run_resolve_item() {
  local input; input=$(_read_stdin)
  [[ -z "$input" ]] && { _log "resolve-item: empty stdin"; exit 0; }
  _validate_keys "$input" node_id item_id resolution || exit 0

  local node_id item_id resolution
  node_id=$(printf '%s' "$input" | jq -r '.node_id' 2>/dev/null)
  item_id=$(printf '%s' "$input" | jq -r '.item_id' 2>/dev/null)
  resolution=$(printf '%s' "$input" | jq -r '.resolution' 2>/dev/null)

  local ev_type
  case "$resolution" in
    answered)   ev_type="answered" ;;
    done)       ev_type="action-done" ;;
    backlogged) ev_type="item-backlogged" ;;
    *) _log "resolve-item: unknown resolution '$resolution'"; exit 0 ;;
  esac
  local ev_id; ev_id="cte-${ev_type:0:8}-$(printf '%s|%s' "$node_id" "$item_id" | _sha1 | cut -c1-32)"
  local events
  events=$(printf '[{"event_id":"%s","type":"%s","node_id":"%s","item_id":"%s","actor":"dispatch"}]' \
    "$ev_id" "$ev_type" "$node_id" "$item_id")
  _emit_batch_from_payload "$events"
  _log "resolve-item resolution=$resolution node_id=$node_id item_id=$item_id"
  exit 0
}

# ============================================================================
# Builder-dispatch work-item emission (ADR-054, 2026-06-10).
#
# ADR-034 scoped sub-agent Task/Agent OUT of the conversation-BRANCH surface
# (they are AI-internal mechanics, not user↔AI conversation branches). That
# scoping STANDS — these modes emit NO branch node for a builder dispatch.
# What ADR-054 adds is the WORK-ITEM tier: every orchestrator builder dispatch
# (Task | Agent | Workflow) auto-emits ONE `action-added` work-item on the
# SESSION's own node (the same `ss-<hash>` node --on-session-start registers),
# so work-in-motion is visible in the Workstreams UI without the orchestrator
# doing anything. Noise control:
#   - kind=action + details._category="builder-dispatch" (NOT in the GUI's
#     MISHA_ASK_CATEGORIES set) -> the item can NEVER land in Awaiting-me;
#   - unchecked + no explicit state -> derives 'in-flight' (the In-flight
#     chip), exactly the work-in-motion tier;
#   - completion (--on-builder-complete) emits `action-done` -> checked ->
#     leaves the In-flight set.
#
# COMPLETION-SIGNAL CEILING (honest — investigated 2026-06-10):
#   - Foreground Task/Agent dispatches: PostToolUse fires at tool RETURN,
#     which IS sub-agent completion -> action-done is mechanical and solid.
#   - `Workflow` launches and Agent dispatches with run_in_background:true:
#     PostToolUse fires at LAUNCH-return, NOT completion. Emitting done there
#     would be a false completion claim, so these emit the creation batch only
#     and the item honestly stays in-flight. There is NO stable local hook
#     event or documented transcript contract for background-dispatch
#     completion (no per-workflow completion hook; wake-message shape is
#     undocumented). Named gap per Rule 7 — resolution paths: a future turn's
#     orchestrator `--resolve-item`, the operator in the GUI, or an upstream
#     hook surface if Anthropic ships one. FR-7 keeps the owning session node
#     un-concludable while such an item is open — intentionally visible.
#   - Missed PreToolUse/PostToolUse fires: workstreams-emit-reconciler.sh
#     re-derives the same deterministic ids from the transcript at Stop and
#     catch-up-emits (idempotent event_ids make double-emission a no-op).
# ============================================================================

# Builder work-item title from tool_input. Preference: .description (Task/
# Agent 3-5-word summary) > .meta.name > .name > .title > first non-empty
# prompt/content line. Cap 120 chars. Empty -> caller skips emission.
_builder_title() {
  local input="$1"
  _have jq || { printf '%s' ""; return 0; }
  local t
  t=$(printf '%s' "$input" | jq -r '
    (.tool_input.description // (.tool_input.meta.name? // empty) //
     .tool_input.name // .tool_input.title // empty)' 2>/dev/null || echo "")
  if [[ -z "$t" || "$t" == "null" ]]; then
    t=$(printf '%s' "$input" | jq -r '
      (.tool_input.prompt // .tool_input.content // "")
      | split("\n")[] | select(test("\\S"))' 2>/dev/null | head -n1 || echo "")
  fi
  t=$(printf '%s' "$t" | sed 's/^[[:space:]]\+//; s/[[:space:]]\+$//' | cut -c1-120)
  printf '%s' "$t"
}

# Background-dispatch predicate: Workflow launches return immediately; Agent
# dispatches with run_in_background:true return a handle, not a result.
_builder_is_background() {
  local input="$1" tool="$2"
  [[ "$tool" == "Workflow" ]] && { printf '1'; return 0; }
  local bg
  bg=$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false' 2>/dev/null || echo "false")
  [[ "$bg" == "true" ]] && printf '1' || printf '0'
}

# Compose the idempotent creation batch for one builder work-item:
#   [root bo, session-node bo, action-added, item-details-set]
# Every event_id is deterministic, so re-emission (PostToolUse after
# PreToolUse, reconciler after both) is a per-file no-op. Echoes the JSON
# array WITHOUT the closing bracket so the caller may append more events.
_builder_creation_events() {
  local sid="$1" tool="$2" title="$3" child_id="$4" item_id="$5" bg="$6"
  local rootline; rootline=$(_project_root)
  local root_id="${rootline%%$'\t'*}"
  local root_title="${rootline##*$'\t'}"
  local ev_root ev_child ev_item ev_det
  ev_root="cte-bo-$(printf '%s' "$root_id" | _sha1 | cut -c1-32)"
  ev_child="cte-bo-$(printf '%s' "$child_id" | _sha1 | cut -c1-32)"
  # ev_item: SAME derivation as _run_emit_item so a manual --emit-item for the
  # same (node,item) dedupes with the automatic one. ev_det: deliberately the
  # FIXED (node|item)-only derivation — NOT --emit-details' content-hashed one
  # (Task 9). The builder details ({_category:builder-dispatch,tool,bg}) are
  # constant per dispatch, so Pre/Post/reconciler re-fires dedupe on the fixed
  # id; and because that fixed id is already in the log, a reconciler re-fire
  # can never clobber a LATER content-hashed enrichment via --emit-details.
  ev_item="cte-action-$(printf '%s|%s' "$child_id" "$item_id" | _sha1 | cut -c1-32)"
  ev_det="cte-detset-$(printf '%s|%s' "$child_id" "$item_id" | _sha1 | cut -c1-32)"
  local sess_title; sess_title=$(basename "${PWD:-.}" 2>/dev/null || echo "")
  [[ -z "$sess_title" || "$sess_title" == "/" ]] && sess_title="session ${sid:0:12}"
  local subagent
  subagent=$(printf '%s' "${BUILDER_INPUT_JSON:-}" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
  local bg_json="false"; [[ "$bg" == "1" ]] && bg_json="true"
  local details
  details=$(jq -cn --arg tool "$tool" --arg st "$subagent" --argjson bg "$bg_json" \
    '{_category:"builder-dispatch", tool:$tool, background:$bg} + (if $st != "" then {subagent_type:$st} else {} end)' 2>/dev/null) \
    || details='{"_category":"builder-dispatch"}'
  printf '[{"event_id":"%s","type":"branch-opened","node_id":"%s","parent_id":null,"title":%s,"actor":"dispatch"},{"event_id":"%s","type":"branch-opened","node_id":"%s","parent_id":"%s","title":%s,"actor":"dispatch"},{"event_id":"%s","type":"action-added","node_id":"%s","item_id":"%s","text":%s,"actor":"dispatch"},{"event_id":"%s","type":"item-details-set","node_id":"%s","item_id":"%s","details":%s,"actor":"dispatch"}' \
    "$ev_root" "$root_id" "$(jq -Rn --arg t "$root_title" '$t')" \
    "$ev_child" "$child_id" "$root_id" "$(jq -Rn --arg t "$sess_title" '$t')" \
    "$ev_item" "$child_id" "$item_id" "$(jq -Rn --arg t "$title" '$t')" \
    "$ev_det" "$child_id" "$item_id" "$details"
}

# Shared classification for both builder modes. Echoes
#   tool \t sid \t child_id \t item_id \t title \t bg
# or nothing when the input is not a builder dispatch.
_builder_classify() {
  local input="$1"
  _have jq || return 0
  local tool; tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
  case "$tool" in
    Task|Agent|Workflow) ;;
    # Dispatch spawn tools are --on-spawn's surface (conversation branches);
    # everything else is not a builder dispatch.
    *) return 0 ;;
  esac
  local title; title=$(_builder_title "$input")
  [[ -z "$title" ]] && { _log "builder dispatch ($tool) had no extractable title — skipped"; return 0; }
  local sid; sid=$(_session_id "$input")
  local child_id="ss-$(printf '%s' "$sid" | _sha1 | cut -c1-12)"
  # NO time bucket: PostToolUse + the Stop-time reconciler must recompute the
  # SAME id from the same fields, possibly hours later.
  local item_id="wi-bd-$(printf '%s|%s|%s' "$sid" "$tool" "$title" | _sha1 | cut -c1-12)"
  local bg; bg=$(_builder_is_background "$input" "$tool")
  printf '%s\t%s\t%s\t%s\t%s\t%s' "$tool" "$sid" "$child_id" "$item_id" "$title" "$bg"
}

# ----------------------------------------------------------------------------
# --on-builder-dispatch  (PreToolUse on Task|Agent|Workflow)
# ----------------------------------------------------------------------------
_run_on_builder_dispatch() {
  local input; input=$(_read_stdin)
  [[ -z "$input" ]] && exit 0
  local line; line=$(_builder_classify "$input")
  [[ -z "$line" ]] && exit 0
  local tool sid child_id item_id title bg
  IFS=$'\t' read -r tool sid child_id item_id title bg <<<"$line"

  local lib; lib=$(_resolve_state_lib)
  local events
  events="$(BUILDER_INPUT_JSON="$input" _builder_creation_events "$sid" "$tool" "$title" "$child_id" "$item_id" "$bg")]"
  local ef; ef=$(mktemp 2>/dev/null || echo "/tmp/cte-bd-$$.json")
  printf '%s' "$events" >"$ef"
  _emit_dual "$lib" "$ef"
  rm -f "$ef" 2>/dev/null || true

  # Builder correlation ledger (observability + reconciler hint):
  # item_id \t child_id \t tool \t bg \t title \t ts — append once per item.
  mkdir -p "$LEDGER_DIR" 2>/dev/null || true
  local ledger="$LEDGER_DIR/builder-${sid}.jsonl"
  if [[ ! -f "$ledger" ]] || ! grep -q "^${item_id}	" "$ledger" 2>/dev/null; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$item_id" "$child_id" "$tool" "$bg" "$title" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" >>"$ledger" 2>/dev/null || true
  fi
  _log "builder-dispatch item=$item_id node=$child_id tool=$tool bg=$bg title=\"$title\" session=$sid"

  # ---- WAVE-O O.1 EMIT: bg-task-started (contract C2) --------------------
  # ONE marked emit line, per specs-o §O.1 deliverable 3. Scoped HONESTLY:
  # this is the closest existing mechanical tap for "a background task
  # started" (PreToolUse on Task|Agent|Workflow, bg=="1" derived from
  # _builder_is_background — run_in_background:true or a Workflow launch)
  # but it does NOT cover EVERY background-task shape in this harness — a
  # `Bash` tool call with run_in_background:true (or the `Monitor` tool)
  # has no PreToolUse/PostToolUse hook wired anywhere that would fire this
  # event. See this task's report-back for the documented gap; no
  # cooperative-discipline convention was invented to paper over it.
  if [[ "$bg" == "1" ]] && command -v ledger_emit >/dev/null 2>&1; then
    ledger_emit "workstreams-emit" "bg-task-started" "item=${item_id} node=${child_id} tool=${tool} title=\"${title}\" session=${sid}"
  fi
  # ---- END WAVE-O O.1 EMIT --------------------------------------------------

  exit 0
}

# ----------------------------------------------------------------------------
# --on-builder-complete  (PostToolUse on Task|Agent|Workflow)
# Foreground: tool return == completion -> creation batch (covers a missed
# PreToolUse) + action-done. Background: creation batch only (launch-ack is
# NOT completion — the documented ceiling above).
# ----------------------------------------------------------------------------
_run_on_builder_complete() {
  local input; input=$(_read_stdin)
  [[ -z "$input" ]] && exit 0
  local line; line=$(_builder_classify "$input")
  [[ -z "$line" ]] && exit 0
  local tool sid child_id item_id title bg
  IFS=$'\t' read -r tool sid child_id item_id title bg <<<"$line"

  local lib; lib=$(_resolve_state_lib)
  local events
  events="$(BUILDER_INPUT_JSON="$input" _builder_creation_events "$sid" "$tool" "$title" "$child_id" "$item_id" "$bg")"
  if [[ "$bg" == "1" ]]; then
    events="$events]"
    _log "builder-complete DEFERRED (background $tool) item=$item_id — launch-ack is not completion (ADR-054 ceiling)"
    # NL Observability Program Wave O, task O.1 (specs-o §O.1 deliverable 3):
    # deliberately NO bg-task-finished emit here. This branch fires at
    # LAUNCH-RETURN for a background dispatch, not at its actual
    # completion (the COMPLETION-SIGNAL CEILING documented above this
    # function: "NO stable local hook event ... for background-dispatch
    # completion"). Emitting bg-task-finished here would be a false
    # completion claim, exactly the failure mode this file's own ADR-054
    # ceiling was written to avoid. Per specs-o §O.1 deliverable 3's own
    # instruction ("if none exists, document the gap ... do NOT invent a
    # cooperative-discipline convention"), this gap is left unfilled and
    # named in this task's report-back rather than papered over.
  else
    # SAME derivation as _run_resolve_item resolution=done, so a manual
    # resolve and this automatic one dedupe to one event.
    local ev_type="action-done"
    local ev_done; ev_done="cte-${ev_type:0:8}-$(printf '%s|%s' "$child_id" "$item_id" | _sha1 | cut -c1-32)"
    events="$events,$(printf '{"event_id":"%s","type":"action-done","node_id":"%s","item_id":"%s","actor":"dispatch"}' \
      "$ev_done" "$child_id" "$item_id")]"
    _log "builder-complete item=$item_id node=$child_id tool=$tool session=$sid"
  fi
  local ef; ef=$(mktemp 2>/dev/null || echo "/tmp/cte-bdc-$$.json")
  printf '%s' "$events" >"$ef"
  _emit_dual "$lib" "$ef"
  rm -f "$ef" 2>/dev/null || true
  exit 0
}

# ============================================================================
# Dispatch
# ============================================================================
case "$MODE" in
  --on-spawn)      _run_on_spawn ;;
  --on-stop)       _run_on_stop ;;
  --on-session-start) _run_on_session_start ;;
  --heartbeat)     _run_heartbeat ;;
  --self-test)     _self_test ;;
  # Builder-dispatch work-item surface (ADR-054 — 2026-06-10):
  --on-builder-dispatch) _run_on_builder_dispatch ;;
  --on-builder-complete) _run_on_builder_complete ;;
  # Orchestrator-emit surface (v1.1.5 — 2026-05-21):
  --emit-branch)   _run_emit_branch ;;
  --emit-item)     _run_emit_item ;;
  --emit-details)  _run_emit_details ;;
  --resolve-item)  _run_resolve_item ;;
  # Read-only introspection (no side effects) — used by --self-test to assert
  # worktree→main-checkout sink resolution without a live GUI server.
  --resolve-gui-sink)  trap - ERR; _resolve_gui_state_path; printf '\n'; exit 0 ;;
  --resolve-gate-sink) trap - ERR; _resolve_gate_state_path; printf '\n'; exit 0 ;;
  *)
    # Unknown / no mode: never block. (A misconfigured wiring must not break
    # the orchestrator — writer, not gate.)
    _log "invoked with no/unknown mode '${MODE:-}' — no-op"
    exit 0
    ;;
esac
