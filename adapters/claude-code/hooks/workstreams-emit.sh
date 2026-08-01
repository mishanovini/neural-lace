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
# shellcheck disable=SC1091
{ source "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/hook-reentry-guard.sh" 2>/dev/null; } || true

MODE="${1:-}"

# NL-FINDING-040 keystone guard: several MODE branches below spawn further
# subprocesses (bash "$SELF" --on-stop from within builder-dispatch flows,
# workstreams-task-bridge.js, etc.). Under NL_HOOK_REENTRY=1 (automation-
# spawned/re-entrant child), no-op for every LIVE mode. --self-test is
# deliberately EXEMPT (it internally re-invokes this
# same script with HARNESS_SELFTEST=1 to exercise --on-stop etc. as a
# controlled, bounded, sandboxed fixture — that is not the reentrancy
# scenario this guard targets, and suppressing it would break the self-test
# suite itself rather than protect anything).
if [[ "$MODE" != "--self-test" ]] && command -v hook_reentry_should_suppress >/dev/null 2>&1 && hook_reentry_should_suppress; then
  hook_reentry_note "workstreams-emit" 2>/dev/null || true
  exit 0
fi

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
  #
  # REPLAY DETECTION (ROADMAP-FALSE-ETERNAL-RUNNING-01, 2026-07-30): the
  # spawn surface is replayed by PreToolUse exactly like the builder surface
  # (see the long note at _run_on_builder_dispatch's ledger append for the
  # measured evidence). (child_id, title) is this surface's dispatch
  # identity -- child_id alone is sha1(sid) and therefore constant, so the
  # title field must participate. Read BEFORE the append below, and with
  # awk field equality rather than a substring grep so a title that happens
  # to appear inside another row's text can never produce a false "already
  # seen" (which would silently suppress a real spawn). That field-equality
  # claim is PINNED BY SCENARIO RPL8 -- it was load-bearing and untested
  # until 2026-07-30, when a refuter swapped in `grep -qF` and the whole
  # suite stayed green.
  #
  # THE IDENTITY LEDGER IS A SEPARATE FILE FROM THE CONCLUDE LEDGER, and the
  # separation is the whole point (F1, adversarial refuter 2026-07-30). The
  # gate first keyed on `opened-<sid>.jsonl` -- but that file is CONSUMED
  # STATE with a per-turn lifetime: `--on-stop` deletes it after concluding
  # (correctly -- concluding twice would be wrong) and `--heartbeat` deletes
  # it when a session goes stale. A Stop hook fires at EVERY turn boundary
  # (48 real invocations logged by 2026-07-30), so the gate was erased within
  # one turn of being set and every later transcript replay counted as a
  # start again -- i.e. the eternal-green defect was still fully live on this
  # surface while the code comment, the commit message, the doctrine, the
  # manifest and the backlog all claimed it was fixed. Executed proof and the
  # regression pin: scenarios RPL6/RPL6b/RPL6c.
  #
  # A DISPATCH IDENTITY SET AND A CONCLUDE QUEUE ARE DIFFERENT THINGS with
  # different lifetimes, so they get different files. The identity set must
  # live as long as the SESSION whose replays it must suppress; the conclude
  # queue must be cleared the moment it is drained. `spawn-<sid>.jsonl` is
  # therefore append-only and deleted by nothing -- the same shape, and the
  # same durability, the builder surface's `builder-<sid>.jsonl` already has
  # (which is exactly why the builder surface never had this hole). Growth is
  # bounded by dispatches-per-session at ~1 short line each, matching the
  # builder ledger's already-accepted footprint.
  mkdir -p "$LEDGER_DIR" 2>/dev/null || true
  local ledger="$LEDGER_DIR/opened-${sid}.jsonl"
  local id_ledger="$LEDGER_DIR/spawn-${sid}.jsonl"
  local spawn_is_new=1
  if [[ -f "$id_ledger" ]] && awk -F'\t' -v c="$child_id" -v t="$title" \
       '$1==c && $2==t { found=1; exit } END { exit !found }' "$id_ledger" 2>/dev/null; then
    spawn_is_new=0
  else
    printf '%s\t%s\t%s\n' "$child_id" "$title" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" >>"$id_ledger" 2>/dev/null || true
  fi
  local base_sha; base_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
  printf '%s\t%s\t%s\t%s\t%s\n' "$child_id" "$title" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "$serves_item_id" "$base_sha" >>"$ledger" 2>/dev/null || true
  _log "branch-opened child=$child_id title=\"$title\" root=$root_id session=$sid serves=${serves_item_id:-none} replay=$((1 - spawn_is_new))"

  # v1.1.4 item 41 — observability for the GUI detail-pane content quality.
  # Non-blocking warning when a substantive Dispatch prompt ships without
  # rich-detail sentinels (Instructions:/Recommendation:/Links:). See the
  # _warn_no_rich_details + _extract_rich_details definitions above for the
  # schema. The warning lives ONLY in the audit log — never blocks. The
  # `Work-item: new` form DOES propagate the sentinels into an
  # item-details-set (Task 9, handled above); this warning remains the
  # observability floor for spawns that carry no sentinels at all.
  _warn_no_rich_details "$input" "$title"

  # ask-rooted-workstreams-p1 Task 3: best-effort task_started progress-log
  # emission + dispatch-provenance marker (see the TWO SINKS block above
  # _emit_dispatch_provenance for the full contract). sid/child_id here are
  # the SAME values just used for the branch-opened/session-bound events
  # above -- "the same provenance the SESSIONS lineage rendering consumes"
  # per the plan's Task 3 spec.
  #
  # The NL-ATTRIBUTION parse is done HERE too (2026-07-30). It was
  # previously only done on the builder surface, so a spawn's task_started
  # could only ever come from the free-text scrape. Now that scraping is no
  # longer a source of task_started, omitting this parse would silently kill
  # attribution for headered spawns instead of fixing them -- so the spawn
  # surface gets the same authoritative path the builder surface has.
  local sp_plan sp_task sp_role sp_attributed
  IFS='|' read -r sp_plan sp_task sp_role sp_attributed <<<"$(_extract_nl_attribution "$(_dispatch_text "$input")")"
  _emit_dispatch_provenance "$input" "$sid" "$child_id" \
    "$sp_plan" "$sp_task" "$sp_role" "$sp_attributed" "$spawn_is_new" || true

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
  # Stop hooks receive transcript_path on stdin alongside session_id (same
  # field bug-persistence-gate.sh / work-integrity-gate.sh / the reconciler
  # already read) — used below by the NL-ATTRIBUTION END trigger.
  local transcript_path; transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
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
    #
    # NL-ATTRIBUTION END trigger (attribution-pipeline task, 2026-07-29): a
    # dispatched CHILD session's PreToolUse dispatch text was never visible
    # to IT (that lived in the PARENT's hook invocation) but its OWN
    # transcript's first user turn IS the prompt it was launched with -- the
    # same text the header convention asks orchestrators to put the
    # NL-ATTRIBUTION line into. _stop_extract_nl_attribution reads it here,
    # at the guaranteed-complete end of the session, so start (governor
    # ledger, parent-side) and end (this signal-ledger row, child-side)
    # carry the SAME plan/task/role vocabulary even though they are
    # necessarily two different session_ids (HONEST GAP, not silently
    # papered over: see docs/plans/fragments/attribution-server-fragment.md
    # for how a consumer should treat "concluded with no matching start" as
    # its own class rather than a join failure).
    if command -v ledger_emit >/dev/null 2>&1; then
      local a_plan a_task a_role a_attributed
      IFS='|' read -r a_plan a_task a_role a_attributed <<<"$(_stop_extract_nl_attribution "$transcript_path")"
      ledger_emit "workstreams-emit" "spawn-concluded" "session=${sid} concluded=${n_cc} shipped=${n_ship} plan=${a_plan} task=${a_task} role=${a_role} attributed=${a_attributed}"
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
  # Count task_started events across a per-ask progress-log DIRECTORY that
  # may not exist at all (the honest-silence cases assert exactly that).
  # `grep -c` exits 1 on zero matches, so the naive `|| echo 0` idiom yields
  # the two-line string "0\n0" and fails a numeric compare against "0" --
  # normalize to a single integer here instead of repeating the trap.
  _ts_count_dir() {
    local n; n=$(cat "$1"/*.jsonl 2>/dev/null | grep -c '"type":"task_started"' 2>/dev/null | tr -d ' \n')
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    printf '%s' "$n"
  }
  # _ts_grep_dir <dir> <extended-regex> -> count of matching lines, whole dir.
  #
  # THE VACUOUS-ABSENCE CLASS (harness-reviewer, 2026-07-30 — the class behind
  # F7, swept here rather than fixed one instance at a time). An assertion of
  # the form `! grep -q <pattern> "$one_named_file"` passes for TWO different
  # reasons: the event genuinely was not emitted (what the test means), or the
  # event WAS emitted and landed in a different file (what the test cannot
  # tell apart). The second is not hypothetical in this codebase — PL4d exists
  # precisely because a placeholder ask-id once routed real events to
  # `_id.jsonl`, and pl_path_for's orphan lane (`unlinked.jsonl`) is a
  # standing second destination for anything whose ask-id does not resolve.
  # So an absence assertion, and equally a "no FURTHER emission" count
  # assertion, is only meaningful over the WHOLE progress-log directory.
  #
  # SCOPE OF THIS SWEEP, stated narrowly (an earlier draft of this comment
  # claimed "every such assertion in this suite", which was over-broad):
  # every absence / no-further-emission assertion in the PROGRESS-LOG lane
  # (PL*, RPL*) is directory-scoped. NOT swept, and deliberately named so the
  # gap is visible rather than implied: NLA2 and NLA4 assert over a single
  # `ls ... | head -n1`-picked file in the GOVERNOR-LEDGER lane, which is a
  # different store with a different layout -- same vacuity class, different
  # sweep, not done here. Presence assertions may stay file-scoped anywhere,
  # since naming the exact destination is a STRONGER claim, not a vacuous one.
  _ts_grep_dir() {
    local n; n=$(cat "$1"/*.jsonl 2>/dev/null | grep -cE "$2" 2>/dev/null | tr -d ' \n')
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    printf '%s' "$n"
  }

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
  # PL1-PL6 (ask-rooted-workstreams-p1 Task 3 -- dispatch emission splice):
  # task_started progress-log emission + dispatch-provenance marker, spliced
  # into --on-builder-dispatch / --on-spawn alongside the conv-tree emission
  # above. A fixture plan file with an `ask-id:` header proves the SAME
  # ask-id resolution Task 1's plan-lifecycle.sh splice established.
  # ================================================================
  local plfix="$tmp/planfix"
  mkdir -p "$plfix/docs/plans"
  cat >"$plfix/docs/plans/pl-fixture-plan.md" <<'PLANEOF'
# Plan: PL fixture
Status: ACTIVE
ask-id: ask-pl-fixture-1
PLANEOF
  if command -v git >/dev/null 2>&1; then
    ( cd "$plfix" && git init -q . && git config core.hooksPath "" \
        && git config user.email t@e.test && git config user.name t \
        && git add -A && git commit -qm init ) >/dev/null 2>&1
  fi

  # PL1 (REFORMULATED 2026-07-30, ROADMAP-FALSE-ETERNAL-RUNNING-01 -- this
  # scenario previously asserted THE DEFECT). It used to require that a
  # free-text "Task 3 of ... docs/plans/<slug>.md" prompt EMIT a
  # task_started. That is precisely how a dispatch that merely MENTIONS a
  # plan/task turned the operator's chip green with nothing running, so the
  # assertion is inverted deliberately, not weakened: prose is no longer a
  # source of task_started. The marker (sink 2) is unaffected and PL2 below
  # still proves it is written from exactly this prompt.
  local plog1="$tmp/pl-progresslog-1" dpdir1="$tmp/dispatch-provenance-1"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog1" DISPATCH_PROVENANCE_STATE_DIR="$dpdir1" \
      CONV_TREE_STATE_PATH="$tmp/pl-1.json" CLAUDE_SESSION_ID="sess-pl-1" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 3 of the FROZEN plan docs/plans/pl-fixture-plan.md","prompt":"Build Task 3 of the FROZEN plan docs/plans/pl-fixture-plan.md in your worktree."},"session_id":"sess-pl-1"}' >/dev/null 2>&1 )
  local plfile1="$plog1/ask-pl-fixture-1.jsonl"
  # Counted across the WHOLE progress-log DIRECTORY, not just the one file
  # this dispatch is expected to resolve to (F7, adversarial refuter
  # 2026-07-30). Asserting absence in ONE named file passes VACUOUSLY whenever
  # a regression makes the event land somewhere else -- the orphan/unlinked
  # lane, or a differently-resolved ask-id -- which is a real and already-
  # observed failure shape here (PL4d exists because a placeholder ask-id once
  # routed events to `_id.jsonl`). _ts_count_dir is what RPL3/RPL4 already use
  # for exactly this reason; PL1 is now consistent with them.
  local pl1_n; pl1_n=$(_ts_count_dir "$plog1")
  if [[ "$pl1_n" == "0" ]]; then
    echo "PASS: PL1 a header-less, prose-only dispatch emits NO task_started ANYWHERE under the progress-log dir -- a MENTION of a plan/task is not a dispatch of it (the green-chip lie under repair)"; pass=$((pass+1))
  else
    echo "FAIL: PL1 expected NO task_started from a prose-only dispatch, found $pl1_n under $plog1"; fail=$((fail+1))
    cat "$plog1"/*.jsonl 2>/dev/null
  fi

  # PL1a: the SAME prompt WITH an NL-ATTRIBUTION header emits exactly one
  # task_started carrying the HEADER's plan/task, resolved to the fixture
  # plan's ask-id, via the UNCHANGED progress-log.sh emit CLI (Task 2). The
  # header says task=3 and the prose says "Task 3" too, so this is the
  # like-for-like replacement of what PL1 used to assert -- the emission
  # lane still works, it just requires the authoritative source now.
  local plog1a="$tmp/pl-progresslog-1a" dpdir1a="$tmp/dispatch-provenance-1a"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog1a" DISPATCH_PROVENANCE_STATE_DIR="$dpdir1a" \
      CONV_TREE_STATE_PATH="$tmp/pl-1a.json" CLAUDE_SESSION_ID="sess-pl-1a" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 3 of the FROZEN plan docs/plans/pl-fixture-plan.md","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=3 role=builder\nBuild Task 3 of the FROZEN plan docs/plans/pl-fixture-plan.md in your worktree."},"session_id":"sess-pl-1a"}' >/dev/null 2>&1 )
  local plfile1a="$plog1a/ask-pl-fixture-1.jsonl"
  if [[ -f "$plfile1a" ]] && grep -q '"type":"task_started"' "$plfile1a" && grep -q '"plan_slug":"pl-fixture-plan"' "$plfile1a" && grep -q '"task_id":"3"' "$plfile1a" && grep -q '"emitter":"workstreams-emit"' "$plfile1a"; then
    echo "PASS: PL1a a header-attributed dispatch emits task_started (plan_slug/task_id/ask_id resolved, emitter=workstreams-emit) via the unchanged progress-log.sh CLI"; pass=$((pass+1))
  else
    echo "FAIL: PL1a expected a task_started event with plan_slug=pl-fixture-plan task_id=3 in $plfile1a"; fail=$((fail+1))
    [[ -f "$plfile1a" ]] && cat "$plfile1a"
  fi

  # PL1b (FINDING 2 REGRESSION, half 1 -- A RE-FIRE MUST NEVER DOUBLE-EMIT):
  # re-fire the SAME dispatch identity IMMEDIATELY (same session_id, same
  # tool, same title, back-to-back) -> still exactly ONE task_started. Two
  # independent mechanisms now enforce this: the ledger replay gate (this
  # identity is already recorded) and, for the truly-concurrent case where
  # two processes could both win the append race, _dispatch_replay_token's
  # debounce window feeding pl_emit's natural key. Run at PRODUCTION
  # DEFAULTS (no debounce override).
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog1a" DISPATCH_PROVENANCE_STATE_DIR="$dpdir1a" \
      CONV_TREE_STATE_PATH="$tmp/pl-1a.json" CLAUDE_SESSION_ID="sess-pl-1a" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 3 of the FROZEN plan docs/plans/pl-fixture-plan.md","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=3 role=builder\nBuild Task 3 of the FROZEN plan docs/plans/pl-fixture-plan.md in your worktree."},"session_id":"sess-pl-1a"}' >/dev/null 2>&1 )
  local ts_count_pl1; ts_count_pl1=$(_ts_count_dir "$plog1a")
  _ck "PL1b true double-fire (same session_id, same dispatch identity, back-to-back) emits exactly 1 task_started" "$ts_count_pl1" "1"

  # PL1c (FINDING 2 REGRESSION, half 2 -- THE LOAD-BEARING TEST, REFORMULATED
  # 2026-07-30). FINDING 2's real intent was: a GENUINE re-dispatch must not
  # be silently swallowed just because the orchestrator's CLAUDE_SESSION_ID
  # is invariant across its own dispatches. That intent is preserved here,
  # against the real-world re-dispatch shape -- a distinct title ("(retry)",
  # "Re-verify", "Round 2"), which is what every one of the 105 dispatch
  # identities in the operator's real 43h ledger looks like.
  #
  # What changed and why: the OLD form of this test re-fired a BYTE-IDENTICAL
  # dispatch and demanded a 2nd event, with wall-clock time as the only
  # discriminator. That contract is now impossible to honor honestly --
  # PreToolUse replays the whole transcript, so "same identity, later clock"
  # is exactly what a REPLAY looks like, and a rule that emits for it is the
  # bug (see PL1d, which pins the accepted cost explicitly).
  #
  # DISPATCH_REPLAY_DEBOUNCE_SECONDS=1 compresses the clock rather than
  # sleeping past the real 120s production window (a 121s sleep in a
  # self-test is not worth it). This is the SAME mechanism and the SAME
  # boundary the shipped default crosses -- only the window's width is
  # parameterized, via the documented knob. The COMPLEMENTARY assertion
  # (PL1b, immediately above) runs at the PRODUCTION DEFAULT, so between them
  # both sides of the window are covered: replay-inside dedups,
  # re-dispatch-outside does not.
  sleep 3
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog1a" DISPATCH_PROVENANCE_STATE_DIR="$dpdir1a" \
      CONV_TREE_STATE_PATH="$tmp/pl-1a.json" CLAUDE_SESSION_ID="sess-pl-1a" \
      DISPATCH_REPLAY_DEBOUNCE_SECONDS=1 \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 3 of the FROZEN plan docs/plans/pl-fixture-plan.md (retry)","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=3 role=builder\nBuild Task 3 of the FROZEN plan docs/plans/pl-fixture-plan.md in your worktree."},"session_id":"sess-pl-1a"}' >/dev/null 2>&1 )
  local ts_count_pl1c; ts_count_pl1c=$(_ts_count_dir "$plog1a")
  _ck "PL1c a GENUINE re-dispatch of the same task from the same dispatching session_id (distinct dispatch identity, past the debounce window) is NOT dropped (2 task_started events total)" "$ts_count_pl1c" "2"

  # PL1d (THE ACCEPTED COST, pinned so it can never regress silently): a
  # re-fire that reuses the IDENTICAL (session, tool, title) identity stays
  # at 2 -- it is indistinguishable from a transcript replay at PreToolUse,
  # so it is treated as the same dispatch. Documented in full at
  # _run_on_builder_dispatch's ledger-append note; asserted here so the
  # trade is visible in the suite output rather than buried in a comment.
  sleep 2
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog1a" DISPATCH_PROVENANCE_STATE_DIR="$dpdir1a" \
      CONV_TREE_STATE_PATH="$tmp/pl-1a.json" CLAUDE_SESSION_ID="sess-pl-1a" \
      DISPATCH_REPLAY_DEBOUNCE_SECONDS=1 \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 3 of the FROZEN plan docs/plans/pl-fixture-plan.md (retry)","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=3 role=builder\nBuild Task 3 of the FROZEN plan docs/plans/pl-fixture-plan.md in your worktree."},"session_id":"sess-pl-1a"}' >/dev/null 2>&1 )
  local ts_count_pl1d; ts_count_pl1d=$(_ts_count_dir "$plog1a")
  _ck "PL1d an identical-identity re-fire past the debounce window is treated as a replay and emits nothing further (still 2, never 3) -- the deliberate miss-a-green-before-faking-one trade" "$ts_count_pl1d" "2"

  # PL2: the SAME dispatch also writes a dispatch-provenance marker file
  # (Task 9's future guard input) with the resolved fields.
  local dpfile1; dpfile1=$(ls "$dpdir1"/*.json 2>/dev/null | head -n1)
  if [[ -n "$dpfile1" && -f "$dpfile1" ]] && grep -q '"ask_id":"ask-pl-fixture-1"' "$dpfile1" && grep -q '"plan_slug":"pl-fixture-plan"' "$dpfile1" && grep -q '"task_id":"3"' "$dpfile1" && grep -q '"session_id":"sess-pl-1"' "$dpfile1"; then
    echo "PASS: PL2 dispatch-provenance marker written with resolved ask_id/plan_slug/task_id/session_id"; pass=$((pass+1))
  else
    echo "FAIL: PL2 expected a populated dispatch-provenance marker under $dpdir1 (got '$dpfile1')"; fail=$((fail+1))
    [[ -n "$dpfile1" ]] && cat "$dpfile1"
  fi
  case "$(basename "${dpfile1:-}" 2>/dev/null || echo)" in
    UNRESOLVED__*) echo "PASS: PL2b marker filename honestly says UNRESOLVED (no worktree hint on the Task/Agent surface)"; pass=$((pass+1)) ;;
    *) echo "FAIL: PL2b expected an UNRESOLVED-prefixed marker filename (Task/Agent carries no cwd), got '$(basename "${dpfile1:-}" 2>/dev/null)'"; fail=$((fail+1)) ;;
  esac

  # PL3: anti-noise guard — a dispatch with NO plan reference emits nothing
  # (no task_started event, no marker file): not every builder dispatch
  # serves a plan task.
  local plog3="$tmp/pl-progresslog-3" dpdir3="$tmp/dispatch-provenance-3"
  CONV_TREE_STATE_PATH="$tmp/pl-3.json" PROGRESS_LOG_STATE_DIR="$plog3" DISPATCH_PROVENANCE_STATE_DIR="$dpdir3" CLAUDE_SESSION_ID="sess-pl-3" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Investigate a flaky test","prompt":"look into why the CI job is flaky"},"session_id":"sess-pl-3"}' >/dev/null 2>&1
  if [[ ! -d "$plog3" || -z "$(ls -A "$plog3" 2>/dev/null)" ]] && [[ ! -d "$dpdir3" || -z "$(ls -A "$dpdir3" 2>/dev/null)" ]]; then
    echo "PASS: PL3 anti-noise: a plan-less dispatch emits NO task_started event and writes NO marker"; pass=$((pass+1))
  else
    echo "FAIL: PL3 expected no progress-log/marker output for a plan-less dispatch (plog3=$(ls -A "$plog3" 2>/dev/null) dpdir3=$(ls -A "$dpdir3" 2>/dev/null))"; fail=$((fail+1))
  fi

  # PL4: --on-spawn (mcp__ccd_session__spawn_task) with an explicit
  # tool_input.cwd hint that IS a real worktrees-pool path -> the marker's
  # worktree_path is populated (the one surface that CAN carry a
  # pre-dispatch location hint; see this splice's header comment on the
  # Task/Agent surface's honest gap).
  local plog4="$tmp/pl-progresslog-4" dpdir4="$tmp/dispatch-provenance-4"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog4" DISPATCH_PROVENANCE_STATE_DIR="$dpdir4" \
      CONV_TREE_STATE_PATH="$tmp/pl-4.json" CLAUDE_SESSION_ID="sess-pl-4" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Spawn PL","prompt":"Build Task 5 of the FROZEN plan docs/plans/pl-fixture-plan.md","cwd":"/tmp/some/project/root/.claude/worktrees/agent-pl4"},"session_id":"sess-pl-4"}' >/dev/null 2>&1 )
  local dpfile4; dpfile4=$(ls "$dpdir4"/*.json 2>/dev/null | head -n1)
  if [[ -n "$dpfile4" ]] && grep -q '"worktree_path":"/tmp/some/project/root/.claude/worktrees/agent-pl4"' "$dpfile4" && grep -q '"task_id":"5"' "$dpfile4"; then
    echo "PASS: PL4 --on-spawn with a pool-shaped tool_input.cwd hint populates the marker's worktree_path"; pass=$((pass+1))
  else
    echo "FAIL: PL4 expected worktree_path=/tmp/some/project/root/.claude/worktrees/agent-pl4 task_id=5 in $dpfile4"; fail=$((fail+1))
    [[ -n "$dpfile4" ]] && cat "$dpfile4"
  fi

  # PL4b (FINDING 3 REGRESSION, 2026-07-14 review panel): --on-spawn with a
  # tool_input.cwd hint that is a BARE PROJECT ROOT (the documented
  # cross-repo spawn_task workflow's actual shape, NOT a
  # `.claude/worktrees/` child) must NOT be recorded as the marker's
  # worktree_path -- recording it verbatim previously let a later,
  # unrelated operator session at that same root get misclassified
  # spawned by pl_classify_session. The marker must land honestly
  # UNRESOLVED, exactly like the generic Task/Agent surface's gap.
  local plog4b="$tmp/pl-progresslog-4b" dpdir4b="$tmp/dispatch-provenance-4b"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog4b" DISPATCH_PROVENANCE_STATE_DIR="$dpdir4b" \
      CONV_TREE_STATE_PATH="$tmp/pl-4b.json" CLAUDE_SESSION_ID="sess-pl-4b" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Cross-repo Spawn","prompt":"Build Task 6 of the FROZEN plan docs/plans/pl-fixture-plan.md","cwd":"/tmp/some/other-project-root"},"session_id":"sess-pl-4b"}' >/dev/null 2>&1 )
  local dpfile4b; dpfile4b=$(ls "$dpdir4b"/*.json 2>/dev/null | head -n1)
  if [[ -n "$dpfile4b" ]] && grep -q '"worktree_path":""' "$dpfile4b" && grep -q '"task_id":"6"' "$dpfile4b"; then
    echo "PASS: PL4b a bare-project-root tool_input.cwd is NOT recorded as worktree_path (honest UNRESOLVED, not a misleading non-pool value)"; pass=$((pass+1))
  else
    echo "FAIL: PL4b expected worktree_path=\"\" task_id=6 (bare project root must never populate worktree_path) in $dpfile4b"; fail=$((fail+1))
    [[ -n "$dpfile4b" ]] && cat "$dpfile4b"
  fi
  case "$(basename "${dpfile4b:-}" 2>/dev/null || echo)" in
    UNRESOLVED__*) echo "PASS: PL4c marker filename honestly says UNRESOLVED for a bare-project-root cwd hint"; pass=$((pass+1)) ;;
    *) echo "FAIL: PL4c expected an UNRESOLVED-prefixed marker filename for a bare-project-root cwd hint, got '$(basename "${dpfile4b:-}" 2>/dev/null)'"; fail=$((fail+1)) ;;
  esac

  # ================================================================
  # RPL1-RPL5 (ROADMAP-FALSE-ETERNAL-RUNNING-01, 2026-07-30): the operator's
  # longest-running visible defect, stated verbatim -- "The green items are
  # supposed to indicate something is actively running. I see several green
  # plans that aren't running."
  #
  # Every scenario below EXECUTES the real hook and asserts the real emitted
  # events; none of them reads this file's source text. The two production
  # mechanisms they pin, both measured on the operator's machine 2026-07-30:
  #   MENTION != DISPATCH  -- prompt-text scraping marked any plan/task a
  #     prompt merely named as started.
  #   REPLAY  != START     -- PreToolUse re-fires for every historical
  #     dispatch in the transcript (100 fires in 67s, walking 43h of
  #     history), re-greening everything the session ever dispatched.
  # ================================================================

  # RPL1 (THE MANDATED SCENARIO): a prompt that MENTIONS THREE tasks but
  # carries an NL-ATTRIBUTION header for ONE must emit EXACTLY ONE
  # task_started -- for the header's task, not for the prose's. The prose
  # here is deliberately the most seductive shape for the old heuristic: it
  # names a plan file and three "Task N" tokens, and the FIRST one it would
  # have scraped (Task 5) is NOT the task actually being dispatched (task
  # 11), so a scraping regression cannot pass this by accident.
  local plog_rpl1="$tmp/pl-rpl1" dpdir_rpl1="$tmp/dp-rpl1"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl1" DISPATCH_PROVENANCE_STATE_DIR="$dpdir_rpl1" \
      CONV_TREE_STATE_PATH="$tmp/rpl-1.json" CLAUDE_SESSION_ID="sess-rpl-1" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Round 3 orchestration","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=11 role=builder\nContext for you: Task 5 of docs/plans/pl-fixture-plan.md already landed, Task 6 of docs/plans/pl-fixture-plan.md is with the verifier, and Task 9 of docs/plans/pl-fixture-plan.md is blocked on the operator walkthrough. Do not touch any of them."},"session_id":"sess-rpl-1"}' >/dev/null 2>&1 )
  local plfile_rpl1="$plog_rpl1/ask-pl-fixture-1.jsonl"
  local rpl1_n; rpl1_n=$(_ts_count_dir "$plog_rpl1")
  _ck "RPL1 a prompt mentioning THREE tasks with a header naming ONE emits exactly 1 task_started (mention != dispatch)" "$rpl1_n" "1"
  if [[ -f "$plfile_rpl1" ]] && grep -q '"task_id":"11"' "$plfile_rpl1" 2>/dev/null; then
    echo "PASS: RPL1b the single event names the HEADER's task (11), not the first task the prose mentions (5)"; pass=$((pass+1))
  else
    echo "FAIL: RPL1b expected task_id=11 (the header's task) in $plfile_rpl1"; fail=$((fail+1))
    [[ -f "$plfile_rpl1" ]] && cat "$plfile_rpl1"
  fi
  # Directory-scoped (vacuous-absence class, see _ts_grep_dir): the old form
  # asserted absence in ONE named file, so a 5/6/9 event routed to the orphan
  # lane would have passed it while the defect was live.
  _ck "RPL1c none of the three merely-MENTIONED tasks (5, 6, 9) was marked started ANYWHERE under the progress-log dir" \
    "$(_ts_grep_dir "$plog_rpl1" '"task_id":"(5|6|9)"')" "0"

  # RPL2 (REPLAY SUPPRESSION, the production shape): fire three DISTINCT
  # header-attributed dispatches, then replay ALL THREE identities the way
  # PreToolUse actually does. Result must stay at 3 -- one per real
  # dispatch, none per replay. Before this fix the second pass re-emitted
  # every one of them, which is literally what kept the operator's chips
  # green with nothing running.
  local plog_rpl2="$tmp/pl-rpl2" dpdir_rpl2="$tmp/dp-rpl2"
  local rpl2_task
  for rpl2_task in 21 22 23; do
    ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl2" DISPATCH_PROVENANCE_STATE_DIR="$dpdir_rpl2" \
        CONV_TREE_STATE_PATH="$tmp/rpl-2.json" CLAUDE_SESSION_ID="sess-rpl-2" \
        bash "$SELF" --on-builder-dispatch <<<"{\"tool_name\":\"Task\",\"tool_input\":{\"description\":\"Build item $rpl2_task\",\"prompt\":\"NL-ATTRIBUTION: plan=pl-fixture-plan task=$rpl2_task role=builder\\nbody\"},\"session_id\":\"sess-rpl-2\"}" >/dev/null 2>&1 )
  done
  local plfile_rpl2="$plog_rpl2/ask-pl-fixture-1.jsonl"
  local rpl2_first; rpl2_first=$(_ts_count_dir "$plog_rpl2")
  _ck "RPL2 three distinct header-attributed dispatches emit 3 task_started (one each)" "$rpl2_first" "3"
  local rpl2_markers_before; rpl2_markers_before=$(ls "$dpdir_rpl2"/*.json 2>/dev/null | wc -l | tr -d ' ')
  # The replay: same session, same identities, past the debounce window so
  # the token cannot be what suppresses them -- only the replay gate can.
  sleep 3
  for rpl2_task in 21 22 23; do
    ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl2" DISPATCH_PROVENANCE_STATE_DIR="$dpdir_rpl2" \
        CONV_TREE_STATE_PATH="$tmp/rpl-2.json" CLAUDE_SESSION_ID="sess-rpl-2" \
        DISPATCH_REPLAY_DEBOUNCE_SECONDS=1 \
        bash "$SELF" --on-builder-dispatch <<<"{\"tool_name\":\"Task\",\"tool_input\":{\"description\":\"Build item $rpl2_task\",\"prompt\":\"NL-ATTRIBUTION: plan=pl-fixture-plan task=$rpl2_task role=builder\\nbody\"},\"session_id\":\"sess-rpl-2\"}" >/dev/null 2>&1 )
  done
  local rpl2_after; rpl2_after=$(_ts_count_dir "$plog_rpl2")
  _ck "RPL2b replaying all three dispatch identities past the debounce window emits NOTHING further (still 3, not 6) -- a replay is not a start" "$rpl2_after" "3"
  # And the marker sink is replay-gated too: the replay pass must add ZERO
  # new marker files (a replayed marker is byte-identical in every field its
  # consumer joins on, and only ever evicted genuine older markers from
  # dispatch-provenance.sh's 200-marker cap).
  #
  # Asserted as "the count did not GROW" rather than "== 3" on purpose:
  # marker filenames are UNRESOLVED__<YYYYMMDDHHMMSS>.json, one-second
  # granularity, so same-second dispatches overwrite each other and 3 real
  # dispatches can legitimately leave 2 files. That collision is a REAL
  # pre-existing defect in scripts/dispatch-provenance.sh (filed as
  # DISPATCH-PROVENANCE-MARKER-SECOND-COLLISION-01) and is NOT what this
  # scenario is here to measure -- pinning an exact count would couple this
  # assertion to that unrelated bug and mask the thing it does measure.
  local rpl2_markers_after; rpl2_markers_after=$(ls "$dpdir_rpl2"/*.json 2>/dev/null | wc -l | tr -d ' ')
  _ck "RPL2c the dispatch-provenance sink is replay-gated as well (the replay pass adds no new markers)" "$rpl2_markers_after" "$rpl2_markers_before"

  # RPL3: honest silence for a header-less dispatch -- NO task_started at
  # all, while the WARN observability that already counts these stays. This
  # is the no-header policy justified in _emit_dispatch_provenance's header:
  # an unattributed event names no task, so it can turn no chip green; it
  # could only pollute the orphan lane.
  local plog_rpl3="$tmp/pl-rpl3"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl3" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl3" \
      CONV_TREE_STATE_PATH="$tmp/rpl-3.json" CLAUDE_SESSION_ID="sess-rpl-3" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Sweep the estate","prompt":"Please look at docs/plans/pl-fixture-plan.md and tell me about Task 4."},"session_id":"sess-rpl-3"}' >/dev/null 2>&1 )
  local rpl3_n; rpl3_n=$(_ts_count_dir "$plog_rpl3")
  _ck "RPL3 a header-less dispatch that names a plan AND a task in prose emits 0 task_started (honest silence, never a scrape)" "$rpl3_n" "0"
  if grep -qE 'WARN unattributed builder dispatch.*session=sess-rpl-3' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: RPL3b honest silence keeps its observability -- the unattributed dispatch is still WARN-logged with a running count"; pass=$((pass+1))
  else
    echo "FAIL: RPL3b expected a WARN line naming session=sess-rpl-3 in $LOG_FILE"; fail=$((fail+1))
  fi

  # RPL4: an ACCEPTANCE task the operator alone can perform -- the exact
  # cockpit-roadmap-redesign/9 shape that was rendering green all day. Three
  # different historical dispatches MENTIONED it (with role=builder,
  # role=advocate, and no role); none of them dispatched it. Zero events.
  local plog_rpl4="$tmp/pl-rpl4"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl4" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl4" \
      CONV_TREE_STATE_PATH="$tmp/rpl-4.json" CLAUDE_SESSION_ID="sess-rpl-4" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Status roundup","prompt":"Task 9 of docs/plans/pl-fixture-plan.md is an Acceptance task and needs the OPERATOR to walk through it -- no agent can run it. Report on it only."},"session_id":"sess-rpl-4"}' >/dev/null 2>&1 )
  local rpl4_n; rpl4_n=$(_ts_count_dir "$plog_rpl4")
  _ck "RPL4 an operator-only Acceptance task discussed in a prompt is never marked started (the cockpit-roadmap-redesign/9 shape)" "$rpl4_n" "0"

  # RPL5: the spawn surface keeps a working attribution lane. --on-spawn
  # previously had NO header parse at all, so making task_started
  # header-only would have silently killed spawn attribution instead of
  # fixing it. A headered spawn still emits; a replayed one does not.
  local plog_rpl5="$tmp/pl-rpl5"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl5" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl5" \
      CONV_TREE_STATE_PATH="$tmp/rpl-5.json" CLAUDE_SESSION_ID="sess-rpl-5" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Spawn RPL5","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=31 role=builder\nbody"},"session_id":"sess-rpl-5"}' >/dev/null 2>&1 )
  local plfile_rpl5="$plog_rpl5/ask-pl-fixture-1.jsonl"
  if [[ -f "$plfile_rpl5" ]] && grep -q '"task_id":"31"' "$plfile_rpl5" 2>/dev/null; then
    echo "PASS: RPL5 --on-spawn now parses NL-ATTRIBUTION too, so a headered spawn still emits task_started (lane preserved, not collateral damage)"; pass=$((pass+1))
  else
    echo "FAIL: RPL5 expected task_id=31 from a headered spawn in $plfile_rpl5"; fail=$((fail+1))
    [[ -f "$plfile_rpl5" ]] && cat "$plfile_rpl5"
  fi
  sleep 3
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl5" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl5" \
      CONV_TREE_STATE_PATH="$tmp/rpl-5.json" CLAUDE_SESSION_ID="sess-rpl-5" \
      DISPATCH_REPLAY_DEBOUNCE_SECONDS=1 \
      bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Spawn RPL5","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=31 role=builder\nbody"},"session_id":"sess-rpl-5"}' >/dev/null 2>&1 )
  local rpl5_after; rpl5_after=$(_ts_count_dir "$plog_rpl5")
  _ck "RPL5b a replayed spawn identity emits nothing further (still 1, not 2)" "$rpl5_after" "1"

  # ------------------------------------------------------------------------
  # RPL6 (F1, adversarial refuter 2026-07-30 -- THE REPLAY GATE MUST SURVIVE A
  # TURN BOUNDARY). RPL5b above proves the spawn gate holds WITHIN one turn.
  # It did NOT prove it holds ACROSS one, and it did not: the spawn gate used
  # to key on `opened-<sid>.jsonl`, the SAME file `--on-stop` deletes at the
  # end of every turn (and `--heartbeat` deletes when a session goes stale).
  # A Stop hook is not a rare event -- it is wired at ~/.claude/settings.json
  # and had 48 real invocations logged by 2026-07-30. So on the spawn surface
  # the "first fire of a dispatch identity" guarantee evaporated at the first
  # turn boundary and every subsequent transcript replay counted as a start
  # again -- the exact eternal-green defect this whole change exists to kill,
  # still live on one of the two surfaces.
  #
  # The BUILDER surface never had this hole (`builder-<sid>.jsonl` is written
  # by no deleter), which is why RPL2b passes and this scenario is needed:
  # the two surfaces had different lifetimes for the same claimed guarantee.
  local plog_rpl6="$tmp/pl-rpl6"
  local rpl6_dispatch='{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Spawn RPL6","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=61 role=builder\nbody"},"session_id":"sess-rpl-6"}'
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl6" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl6" \
      CONV_TREE_STATE_PATH="$tmp/rpl-6.json" CLAUDE_SESSION_ID="sess-rpl-6" \
      bash "$SELF" --on-spawn <<<"$rpl6_dispatch" >/dev/null 2>&1 )
  local rpl6_first; rpl6_first=$(_ts_count_dir "$plog_rpl6")
  _ck "RPL6 a real headered spawn emits 1 task_started (the lane this scenario then replays across a turn boundary)" "$rpl6_first" "1"
  # THE TURN BOUNDARY. --on-stop concludes the branch and clears the conclude
  # ledger, exactly as it does after every real turn.
  ( cd "$plfix" && CONV_TREE_STATE_PATH="$tmp/rpl-6.json" CLAUDE_SESSION_ID="sess-rpl-6" \
      bash "$SELF" --on-stop <<<'{"session_id":"sess-rpl-6"}' >/dev/null 2>&1 )
  sleep 3
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl6" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl6" \
      CONV_TREE_STATE_PATH="$tmp/rpl-6.json" CLAUDE_SESSION_ID="sess-rpl-6" \
      DISPATCH_REPLAY_DEBOUNCE_SECONDS=1 \
      bash "$SELF" --on-spawn <<<"$rpl6_dispatch" >/dev/null 2>&1 )
  local rpl6_after; rpl6_after=$(_ts_count_dir "$plog_rpl6")
  _ck "RPL6b a replay AFTER --on-stop emits nothing further (still 1, not 2) -- the spawn replay gate survives the turn boundary that clears the conclude ledger" "$rpl6_after" "1"
  # RPL6c: the same across the OTHER deleter of that file, --heartbeat's
  # stale-session sweep. Same erasure, same class, different trigger.
  ( cd "$plfix" && CONV_TREE_STATE_PATH="$tmp/rpl-6.json" CLAUDE_SESSION_ID="sess-rpl-6" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Spawn RPL6 second"},"session_id":"sess-rpl-6"}' >/dev/null 2>&1 )
  rm -f "$LEDGER_DIR/opened-sess-rpl-6.jsonl" 2>/dev/null || true
  sleep 3
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl6" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl6" \
      CONV_TREE_STATE_PATH="$tmp/rpl-6.json" CLAUDE_SESSION_ID="sess-rpl-6" \
      DISPATCH_REPLAY_DEBOUNCE_SECONDS=1 \
      bash "$SELF" --on-spawn <<<"$rpl6_dispatch" >/dev/null 2>&1 )
  local rpl6_hb; rpl6_hb=$(_ts_count_dir "$plog_rpl6")
  _ck "RPL6c a replay after the conclude ledger is removed by ANY path (--heartbeat's stale sweep) still emits nothing (still 1)" "$rpl6_hb" "1"

  # ------------------------------------------------------------------------
  # RPL7 (F2, adversarial refuter 2026-07-30 -- A QUOTED HEADER IS NOT A
  # DISPATCH). The header parse grepped `NL-ATTRIBUTION:.*` ANYWHERE in the
  # joined prompt+description+content, so a prompt that merely DISCUSSED a
  # prior dispatch -- pasting or quoting its header -- emitted a real
  # task_started for the quoted task. This is a LIVE vector, not a theoretical
  # one: handoff, review and post-mortem prompts routinely paste the builder
  # prompt they are talking about. It is the SAME defect class as the free-text
  # scrape this change removed (a MENTION is not a DISPATCH), surviving in the
  # one source the fix declared authoritative.
  #
  # RPL7 is the refuter's own probe, verbatim.
  local plog_rpl7="$tmp/pl-rpl7"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl7" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl7" \
      CONV_TREE_STATE_PATH="$tmp/rpl-7.json" CLAUDE_SESSION_ID="sess-rpl-7" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Handoff","prompt":"The prior builder was dispatched with the line NL-ATTRIBUTION: plan=pl-fixture-plan task=9 role=builder and it failed. Just read the diff."},"session_id":"sess-rpl-7"}' >/dev/null 2>&1 )
  local rpl7_n; rpl7_n=$(_ts_count_dir "$plog_rpl7")
  _ck "RPL7 a prompt that QUOTES a header mid-sentence while discussing a prior dispatch emits 0 task_started (a quoted header is not a dispatch)" "$rpl7_n" "0"

  # RPL7b: the same vector in its other real shape -- a VERBATIM PASTE, so the
  # header sits at line start but deep inside a handoff prompt, after the
  # explanatory prose that necessarily precedes a paste.
  local plog_rpl7b="$tmp/pl-rpl7b"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl7b" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl7b" \
      CONV_TREE_STATE_PATH="$tmp/rpl-7b.json" CLAUDE_SESSION_ID="sess-rpl-7b" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Review","prompt":"Review the failed run from the prior session.\n\nContext: the orchestrator dispatched a builder and it returned PARTIAL.\n\nHere is the prompt it was given, verbatim:\n\nNL-ATTRIBUTION: plan=pl-fixture-plan task=9 role=builder\nBuild the thing.\n\nDo not build anything. Only report what went wrong."},"session_id":"sess-rpl-7b"}' >/dev/null 2>&1 )
  local rpl7b_n; rpl7b_n=$(_ts_count_dir "$plog_rpl7b")
  _ck "RPL7b a pasted header on line 8 (well past the window) emits 0 task_started" "$rpl7b_n" "0"

  # ------------------------------------------------------------------------
  # RPL7d/RPL7e/RPL7f — THE BOUNDARY TRIPLE (harness-reviewer REFORMULATE,
  # 2026-07-30). RPL7b above is a TRUE assertion that was certifying a FALSE
  # generalization, and the mechanism of that error is worth naming because it
  # is reusable: its preamble happens to run eight lines, so it clears the
  # 5-line window by a wide margin and passes for a reason its own name does
  # not state ("buried below the handoff prose"). Prose written from it then
  # claimed quoted headers are inert generally -- which is FALSE for every
  # preamble shorter than the window, i.e. for the shape a real handoff prompt
  # actually has. A positional guard tested only COMFORTABLY BEYOND its
  # threshold certifies nothing about the threshold.
  #
  # GENERALIZATION (carry this to every threshold/positional guard in this
  # harness): pin n-1, n AND n+1. The n-1 and n cases document what the guard
  # does NOT catch as precisely as n+1 documents what it does, so the prose
  # residual can be written from the EXECUTED boundary instead of from the
  # motivating anecdote.
  #
  # These three pin the ACCEPTED, DOCUMENTED residual -- RPL7d/RPL7f assert
  # EMISSION deliberately. They are not aspirational: if a future change
  # tightens the anchor they must be updated in the same commit, which is the
  # point (the residual cannot drift silently in either direction).
  #
  # RPL7f: n-1. Header on line 4, INDENTED (4 spaces, as a fenced or quoted
  # paste indents it) -- proves the leading-whitespace tolerance is part of the
  # residual, not just line position.
  local plog_rpl7f="$tmp/pl-rpl7f"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl7f" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl7f" \
      CONV_TREE_STATE_PATH="$tmp/rpl-7f.json" CLAUDE_SESSION_ID="sess-rpl-7f" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Handoff","prompt":"Handoff from the prior run.\n\nThe prompt it was given:\n    NL-ATTRIBUTION: plan=pl-fixture-plan task=9 role=builder\n    Build it.\nJust report what went wrong."},"session_id":"sess-rpl-7f"}' >/dev/null 2>&1 )
  _ck "RPL7f (n-1, RESIDUAL) an INDENTED quoted header on line 4 still EMITS -- leading whitespace does not defeat the anchor" "$(_ts_count_dir "$plog_rpl7f")" "1"

  # RPL7d: n. Header on line 5 -- the LAST position the window admits. A
  # three-line preamble plus a fence lands exactly here, which is why a real
  # handoff prompt trips this and RPL7b's eight-line one does not.
  local plog_rpl7d="$tmp/pl-rpl7d"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl7d" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl7d" \
      CONV_TREE_STATE_PATH="$tmp/rpl-7d.json" CLAUDE_SESSION_ID="sess-rpl-7d" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Review","prompt":"Review the failed run.\n\nThe prompt it got:\n```\nNL-ATTRIBUTION: plan=pl-fixture-plan task=9 role=builder\nBuild it.\n```"},"session_id":"sess-rpl-7d"}' >/dev/null 2>&1 )
  _ck "RPL7d (n, RESIDUAL) a fenced paste landing the header on line 5 -- the last admitted line -- still EMITS" "$(_ts_count_dir "$plog_rpl7d")" "1"

  # RPL7e: n+1. Header on line 6 -- the FIRST position the window excludes.
  # This is the tight negative RPL7b should have been.
  local plog_rpl7e="$tmp/pl-rpl7e"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl7e" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl7e" \
      CONV_TREE_STATE_PATH="$tmp/rpl-7e.json" CLAUDE_SESSION_ID="sess-rpl-7e" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Review","prompt":"Review the failed run.\n\nContext line.\n\nThe prompt it got:\nNL-ATTRIBUTION: plan=pl-fixture-plan task=9 role=builder\nBuild it."},"session_id":"sess-rpl-7e"}' >/dev/null 2>&1 )
  _ck "RPL7e (n+1) a quoted header on line 6 -- one line past the window -- emits 0 (the tight negative that actually pins the threshold)" "$(_ts_count_dir "$plog_rpl7e")" "0"

  # RPL7g/RPL7h: THE DOCUMENTED ESCAPE HATCHES MUST ACTUALLY WORK. The
  # doctrine now instructs authors quoting a header to prefix it with `> ` or
  # `- `. That instruction is a load-bearing claim, and an untested one would
  # repeat F4 exactly (a claim in prose with no detector). Both are pinned.
  local plog_rpl7g="$tmp/pl-rpl7g"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl7g" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl7g" \
      CONV_TREE_STATE_PATH="$tmp/rpl-7g.json" CLAUDE_SESSION_ID="sess-rpl-7g" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Handoff","prompt":"Here is what was dispatched:\n> NL-ATTRIBUTION: plan=pl-fixture-plan task=9 role=builder\nJust report."},"session_id":"sess-rpl-7g"}' >/dev/null 2>&1 )
  _ck "RPL7g the doctrine's blockquote escape works: a '> '-prefixed header on line 2 emits 0" "$(_ts_count_dir "$plog_rpl7g")" "0"
  local plog_rpl7h="$tmp/pl-rpl7h"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl7h" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl7h" \
      CONV_TREE_STATE_PATH="$tmp/rpl-7h.json" CLAUDE_SESSION_ID="sess-rpl-7h" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Handoff","prompt":"Here is what was dispatched:\n- NL-ATTRIBUTION: plan=pl-fixture-plan task=9 role=builder\nJust report."},"session_id":"sess-rpl-7h"}' >/dev/null 2>&1 )
  _ck "RPL7h the doctrine's list-prefix escape works: a '- '-prefixed header on line 2 emits 0" "$(_ts_count_dir "$plog_rpl7h")" "0"

  # ------------------------------------------------------------------------
  # RPL7i/RPL7j — THE WINDOW IS OVER THE JOINED TEXT, NOT OVER THE PROMPT
  # (harness-reviewer round 3, 2026-07-30). _dispatch_text joins
  # [prompt, description, content] with newlines and the window is applied to
  # THAT, so the header's admitted region spans a SECOND INPUT FIELD: a short
  # prompt leaves description-borne lines inside the first N. Every artifact
  # said "the first N lines of your prompt", which is wrong in a way an author
  # cannot act on -- the same field-scope error class as F2 itself, one level
  # up. An untested claim about a second input field is also the exact F4
  # shape RPL7g/RPL7h exist to prevent, so both directions are pinned here.
  #
  # RPL7i: 3-line prompt + header alone in `description` -> joined line 4 ->
  # EMITS (residual, asserted deliberately).
  local plog_rpl7i="$tmp/pl-rpl7i"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl7i" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl7i" \
      CONV_TREE_STATE_PATH="$tmp/rpl-7i.json" CLAUDE_SESSION_ID="sess-rpl-7i" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"prompt":"Review the failed run.\nDo not build.\nJust report.","description":"NL-ATTRIBUTION: plan=pl-fixture-plan task=9 role=builder"},"session_id":"sess-rpl-7i"}' >/dev/null 2>&1 )
  _ck "RPL7i (RESIDUAL, second input field) a header carried in the DESCRIPTION field after a 3-line prompt lands on JOINED line 4 and EMITS -- the window spans prompt+description+content, not the prompt" "$(_ts_count_dir "$plog_rpl7i")" "1"

  # RPL7j: the same description, behind a 10-line prompt -> joined line 11 ->
  # silent. Proves RPL7i is genuinely about JOINED position and not about the
  # description field being read unconditionally.
  local plog_rpl7j="$tmp/pl-rpl7j"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl7j" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl7j" \
      CONV_TREE_STATE_PATH="$tmp/rpl-7j.json" CLAUDE_SESSION_ID="sess-rpl-7j" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"prompt":"L1\nL2\nL3\nL4\nL5\nL6\nL7\nL8\nL9\nL10","description":"NL-ATTRIBUTION: plan=pl-fixture-plan task=9 role=builder"},"session_id":"sess-rpl-7j"}' >/dev/null 2>&1 )
  _ck "RPL7j the SAME description behind a 10-line prompt lands on joined line 11 and emits 0 -- confirming JOINED position is the rule, not field identity" "$(_ts_count_dir "$plog_rpl7j")" "0"

  # RPL7c: THE LANE IS NOT COLLATERAL DAMAGE. A real dispatch -- whose prompt
  # OPENS with the header, which is what doctrine/orchestrator-pattern.md
  # already mandates in those words -- still emits exactly one event. Without
  # this assertion RPL7/RPL7b would be satisfiable by breaking attribution
  # outright, which is the failure mode the narrowing must not have.
  local plog_rpl7c="$tmp/pl-rpl7c"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl7c" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl7c" \
      CONV_TREE_STATE_PATH="$tmp/rpl-7c.json" CLAUDE_SESSION_ID="sess-rpl-7c" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Build","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=71 role=builder\n\nBuild the thing. The prior attempt was dispatched with NL-ATTRIBUTION: plan=pl-fixture-plan task=9 role=builder and failed."},"session_id":"sess-rpl-7c"}' >/dev/null 2>&1 )
  local plfile_rpl7c="$plog_rpl7c/ask-pl-fixture-1.jsonl"
  if [[ -f "$plfile_rpl7c" ]] && grep -q '"task_id":"71"' "$plfile_rpl7c" 2>/dev/null && [[ "$(_ts_grep_dir "$plog_rpl7c" '"task_id":"9"')" == "0" ]]; then
    echo "PASS: RPL7c a real dispatch OPENING with its header still emits exactly one event naming ITS task (71), not the task quoted later in the same prompt (9)"; pass=$((pass+1))
  else
    echo "FAIL: RPL7c expected exactly task_id=71 (never 9) in $plfile_rpl7c"; fail=$((fail+1))
    [[ -f "$plfile_rpl7c" ]] && cat "$plfile_rpl7c"
  fi

  # ------------------------------------------------------------------------
  # RPL8 (F4, adversarial refuter 2026-07-30 -- PIN THE FIELD-EQUALITY CLAIM).
  # The spawn gate's comment claims awk FIELD equality is used "rather than a
  # substring grep so a title that happens to appear inside another row's text
  # can never produce a false 'already seen'". That claim was load-bearing and
  # UNTESTED: the refuter swapped the awk for `grep -qF "$title"` and the whole
  # suite stayed green, so nothing in the harness detected the regression the
  # comment exists to prevent. A false "already seen" SUPPRESSES a real
  # dispatch's green chip -- silent under-reporting, the hardest kind to
  # notice, since the operator sees nothing rather than something wrong.
  #
  # Two spawns in ONE session where title B ("Alpha") is a SUBSTRING of title
  # A's ledger row ("Spawn RPL8 Alpha Beta"). child_id is sha1(session_id) and
  # therefore IDENTICAL for both, so the title field is the only discriminator
  # -- which is precisely why it must be compared as a FIELD.
  local plog_rpl8="$tmp/pl-rpl8"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl8" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl8" \
      CONV_TREE_STATE_PATH="$tmp/rpl-8.json" CLAUDE_SESSION_ID="sess-rpl-8" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Spawn RPL8 Alpha Beta","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=81 role=builder\nbody"},"session_id":"sess-rpl-8"}' >/dev/null 2>&1 )
  sleep 3
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_rpl8" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dp-rpl8" \
      CONV_TREE_STATE_PATH="$tmp/rpl-8.json" CLAUDE_SESSION_ID="sess-rpl-8" \
      DISPATCH_REPLAY_DEBOUNCE_SECONDS=1 \
      bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"Alpha","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=82 role=builder\nbody"},"session_id":"sess-rpl-8"}' >/dev/null 2>&1 )
  local plfile_rpl8="$plog_rpl8/ask-pl-fixture-1.jsonl"
  if [[ -f "$plfile_rpl8" ]] && grep -q '"task_id":"81"' "$plfile_rpl8" 2>/dev/null && grep -q '"task_id":"82"' "$plfile_rpl8" 2>/dev/null; then
    echo "PASS: RPL8 a second spawn whose title is a SUBSTRING of an earlier row still emits (field equality, not substring match) -- both 81 and 82 present"; pass=$((pass+1))
  else
    echo "FAIL: RPL8 expected BOTH task_id=81 and task_id=82 in $plfile_rpl8 (a substring match would have suppressed 82)"; fail=$((fail+1))
    [[ -f "$plfile_rpl8" ]] && cat "$plfile_rpl8"
  fi
  _ck "RPL8b exactly 2 task_started across the substring-title pair (no suppression, no duplication)" "$(_ts_count_dir "$plog_rpl8")" "2"

  # PL4d (REGRESSION, proven 2026-07-27 bug): a fixture plan whose header
  # still carries the LITERAL un-substituted template placeholder
  # (`ask-id: <id | none — no linked ask>` — real example still on disk:
  # docs/plans/cockpit-roadmap-redesign.md:7) must resolve the dispatch's
  # task_started event into the SAME "unlinked" per-ask log a plan with NO
  # ask-id header at all would use — NEVER a separate `_id.jsonl` (the
  # plausible-but-wrong file _resolve_ask_id_for_plan_slug produced
  # pre-fix; 1090 real events found filed there on this machine).
  local plfixph="$tmp/planfix-placeholder"
  mkdir -p "$plfixph/docs/plans"
  cat >"$plfixph/docs/plans/pl-fixture-placeholder.md" <<'PLANEOF'
# Plan: PL fixture (unsubstituted placeholder)
Status: ACTIVE
ask-id: <id | none — no linked ask>
PLANEOF
  if command -v git >/dev/null 2>&1; then
    ( cd "$plfixph" && git init -q . && git config core.hooksPath "" \
        && git config user.email t@e.test && git config user.name t \
        && git add -A && git commit -qm init ) >/dev/null 2>&1
  fi
  local plog4d="$tmp/pl-progresslog-4d"
  ( cd "$plfixph" && PROGRESS_LOG_STATE_DIR="$plog4d" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dispatch-provenance-4d" \
      CONV_TREE_STATE_PATH="$tmp/pl-4d.json" CLAUDE_SESSION_ID="sess-pl-4d" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 2 of the FROZEN plan docs/plans/pl-fixture-placeholder.md","prompt":"NL-ATTRIBUTION: plan=pl-fixture-placeholder task=2 role=builder\nBuild Task 2 of the FROZEN plan docs/plans/pl-fixture-placeholder.md in your worktree."},"session_id":"sess-pl-4d"}' >/dev/null 2>&1 )
  if [[ -f "$plog4d/unlinked.jsonl" ]] && grep -q '"plan_slug":"pl-fixture-placeholder"' "$plog4d/unlinked.jsonl"; then
    echo "PASS: PL4d a plan header carrying the literal un-substituted placeholder resolves to the unlinked log, same as no ask-id header at all"; pass=$((pass+1))
  else
    echo "FAIL: PL4d expected the placeholder-plan's task_started event in $plog4d/unlinked.jsonl"; fail=$((fail+1))
    ls -la "$plog4d" 2>/dev/null
  fi
  if [[ -f "$plog4d/_id.jsonl" ]]; then
    echo "FAIL: PL4d _id.jsonl was created — _resolve_ask_id_for_plan_slug is still handing the literal placeholder token to pl_emit"; fail=$((fail+1))
  else
    echo "PASS: PL4d no _id.jsonl (the historical garbage filename) was created"; pass=$((pass+1))
  fi

  # PL4e (ASK-SENTINEL-PER-SITE-REGRESSION-TESTS-01, site-local none-sentinel
  # regression): a fixture plan whose header carries the SPELLED-OUT no-ask
  # value (`ask-id: none — no linked ask`, the template's documented
  # substitution) must ALSO resolve the dispatch's task_started event into
  # the "unlinked" per-ask log -- the OTHER sentinel branch
  # _resolve_ask_id_for_plan_slug guards ('<'* | none), never exercised by
  # PL4d above (that fixture's header starts with `<`, hitting only the
  # first arm). Real-id preservation through this SAME extractor is already
  # covered by PL1 (`ask-id: ask-pl-fixture-1` resolves to its own per-ask
  # log, not unlinked) -- no separate fixture needed for that half. The
  # dispatch prompt MUST carry the NL-ATTRIBUTION header even though the
  # prose names the plan: headerless dispatches emit nothing (PL1/NLA2),
  # so without it this scenario silently tests the no-op path, not the
  # extractor arm.
  local plfixnone="$tmp/planfix-none"
  mkdir -p "$plfixnone/docs/plans"
  cat >"$plfixnone/docs/plans/pl-fixture-none.md" <<'PLANEOF'
# Plan: PL fixture (spelled-out none-sentinel)
Status: ACTIVE
ask-id: none — no linked ask
PLANEOF
  if command -v git >/dev/null 2>&1; then
    ( cd "$plfixnone" && git init -q . && git config core.hooksPath "" \
        && git config user.email t@e.test && git config user.name t \
        && git add -A && git commit -qm init ) >/dev/null 2>&1
  fi
  local plog4e="$tmp/pl-progresslog-4e"
  ( cd "$plfixnone" && PROGRESS_LOG_STATE_DIR="$plog4e" DISPATCH_PROVENANCE_STATE_DIR="$tmp/dispatch-provenance-4e" \
      CONV_TREE_STATE_PATH="$tmp/pl-4e.json" CLAUDE_SESSION_ID="sess-pl-4e" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 2 of the FROZEN plan docs/plans/pl-fixture-none.md","prompt":"NL-ATTRIBUTION: plan=pl-fixture-none task=2 role=builder\nBuild Task 2 of the FROZEN plan docs/plans/pl-fixture-none.md in your worktree."},"session_id":"sess-pl-4e"}' >/dev/null 2>&1 )
  if [[ -f "$plog4e/unlinked.jsonl" ]] && grep -q '"plan_slug":"pl-fixture-none"' "$plog4e/unlinked.jsonl"; then
    echo "PASS: PL4e a plan header carrying the spelled-out none-sentinel resolves to the unlinked log, same as no ask-id header at all"; pass=$((pass+1))
  else
    echo "FAIL: PL4e expected the none-sentinel plan's task_started event in $plog4e/unlinked.jsonl"; fail=$((fail+1))
    ls -la "$plog4e" 2>/dev/null
  fi
  if [[ -f "$plog4e/none.jsonl" ]]; then
    echo "FAIL: PL4e none.jsonl was created — _resolve_ask_id_for_plan_slug is still handing the literal 'none' sentinel to pl_emit unresolved"; fail=$((fail+1))
  else
    echo "PASS: PL4e no none.jsonl (the historical misfiled-events shape) was created"; pass=$((pass+1))
  fi

  # PL5: failure isolation — missing progress-log.sh/dispatch-provenance.sh
  # CLIs (simulated via the override env vars) never blocks the caller.
  local rcPL5
  PL_PROGRESS_LOG_CLI_OVERRIDE="$tmp/does-not-exist-pl.sh" DISPATCH_PROVENANCE_CLI_OVERRIDE="$tmp/does-not-exist-dp.sh" \
    CONV_TREE_STATE_PATH="$tmp/pl-5.json" CLAUDE_SESSION_ID="sess-pl-5" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"description":"Task 1 of the FROZEN plan docs/plans/pl-fixture-plan.md"},"session_id":"sess-pl-5"}' >/dev/null 2>&1
  rcPL5=$?
  _ck "PL5 missing progress-log.sh/dispatch-provenance.sh CLIs -> exit 0 (never blocks)" "$rcPL5" "0"

  # ================================================================
  # NLA1-NLA4, NLA-STOP1/2 (attribution-pipeline task, 2026-07-29): the
  # NL-ATTRIBUTION header convention (doctrine/orchestrator-pattern.md) — a
  # machine-readable `plan=<slug> task=<id> role=<...>` line any dispatch
  # prompt may carry, parsed once by _extract_nl_attribution and threaded
  # into every sink --on-builder-dispatch already writes (governor ledger
  # via adm_admit, task_started progress-log, dispatch-provenance marker)
  # PLUS the --on-stop END trigger (spawn-concluded), so a future consumer
  # can join "started, not concluded" dispatches to a <plan>/<task> id --
  # see docs/plans/fragments/attribution-server-fragment.md.
  # ================================================================

  # NLA1: a dispatch prompt with ONLY the header — NO "docs/plans/X.md"
  # text, NO "Task N of" phrasing (the exact shape the pre-existing
  # free-text heuristic silently no-ops on, PL3-style, and the exact shape
  # THIS task's own dispatch prompt had) — still gets a task_started event
  # resolved against the REAL fixture plan's ask-id, via the header alone.
  local plog_nla1="$tmp/pl-nla1" dpdir_nla1="$tmp/dp-nla1" adm_nla1="$tmp/adm-nla1"
  ( cd "$plfix" && PROGRESS_LOG_STATE_DIR="$plog_nla1" DISPATCH_PROVENANCE_STATE_DIR="$dpdir_nla1" \
      ADM_STATE_DIR="$adm_nla1" CONV_TREE_STATE_PATH="$tmp/nla-1.json" CLAUDE_SESSION_ID="sess-nla-1" \
      bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build the thing","prompt":"NL-ATTRIBUTION: plan=pl-fixture-plan task=7 role=builder\nGo build the thing -- no plan-file phrasing anywhere in this prompt at all."},"session_id":"sess-nla-1"}' >/dev/null 2>&1 )
  local plfile_nla1="$plog_nla1/ask-pl-fixture-1.jsonl"
  if [[ -f "$plfile_nla1" ]] && grep -q '"plan_slug":"pl-fixture-plan"' "$plfile_nla1" && grep -q '"task_id":"7"' "$plfile_nla1"; then
    echo "PASS: NLA1 header-only prompt (no free-text plan/task phrasing) still emits task_started via the NL-ATTRIBUTION header alone -- fixes the exact silent-no-op class PL3 documents for prose-less dispatches"; pass=$((pass+1))
  else
    echo "FAIL: NLA1 expected task_started plan_slug=pl-fixture-plan task_id=7 in $plfile_nla1 (header-only dispatch)"; fail=$((fail+1))
    [[ -f "$plfile_nla1" ]] && cat "$plfile_nla1"
  fi
  local dpfile_nla1; dpfile_nla1=$(ls "$dpdir_nla1"/*.json 2>/dev/null | head -n1)
  if [[ -n "$dpfile_nla1" ]] && grep -q '"role":"builder"' "$dpfile_nla1" 2>/dev/null; then
    echo "PASS: NLA1b dispatch-provenance marker carries role=builder from the header"; pass=$((pass+1))
  else
    echo "FAIL: NLA1b expected role=builder in dispatch-provenance marker ($dpfile_nla1)"; fail=$((fail+1))
  fi
  local ledger_nla1; ledger_nla1=$(ls "$adm_nla1"/ledger/*.jsonl 2>/dev/null | head -n1)
  if [[ -n "$ledger_nla1" ]] && grep -q '"plan":"pl-fixture-plan"' "$ledger_nla1" 2>/dev/null \
      && grep -q '"task":"7"' "$ledger_nla1" 2>/dev/null && grep -q '"role":"builder"' "$ledger_nla1" 2>/dev/null \
      && grep -q '"attributed":"1"' "$ledger_nla1" 2>/dev/null; then
    echo "PASS: NLA1c governor ledger row (adm_admit, the same 1000+/day emit-feed row) carries plan/task/role/attributed=1 -- the START trigger's consumer-ready row"; pass=$((pass+1))
  else
    echo "FAIL: NLA1c expected plan/task/role/attributed=1 in governor ledger $ledger_nla1"; fail=$((fail+1))
    [[ -n "$ledger_nla1" ]] && cat "$ledger_nla1"
  fi

  # NLA2: NO header (an ORDINARY pre-existing dispatch, e.g. BD1's own
  # prompt shape) -> attributed=0 in the governor ledger row, a WARN line
  # logged, and the pre-existing free-text-heuristic behavior is completely
  # unaffected (no plan/task label written at all -- honest absence, never
  # a guess).
  local adm_nla2="$tmp/adm-nla2"
  ADM_STATE_DIR="$adm_nla2" CONV_TREE_STATE_PATH="$tmp/nla-2.json" CLAUDE_SESSION_ID="sess-nla-2" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build the widget","prompt":"long body, no header, no plan reference"},"session_id":"sess-nla-2"}' >/dev/null 2>&1
  local ledger_nla2; ledger_nla2=$(ls "$adm_nla2"/ledger/*.jsonl 2>/dev/null | head -n1)
  if [[ -n "$ledger_nla2" ]] && grep -q '"attributed":"0"' "$ledger_nla2" 2>/dev/null && ! grep -q '"plan":"' "$ledger_nla2" 2>/dev/null; then
    echo "PASS: NLA2 no header -> attributed=0, and plan/task/role labels are absent (empty values dropped by adm_admit itself, never a guessed value)"; pass=$((pass+1))
  else
    echo "FAIL: NLA2 expected attributed=0 with no plan/task/role labels in $ledger_nla2"; fail=$((fail+1))
    [[ -n "$ledger_nla2" ]] && cat "$ledger_nla2"
  fi
  if grep -qE 'WARN unattributed builder dispatch.*session=sess-nla-2' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: NLA2b unattributed dispatch logs a WARN line naming this session (constitution §10 adoption-lag signal, never a block)"; pass=$((pass+1))
  else
    echo "FAIL: NLA2b expected a WARN line naming session=sess-nla-2 in $LOG_FILE"; fail=$((fail+1))
  fi

  # NLA3: PARTIAL header (plan= present, task= missing) -> attributed=0
  # (both fields are required to name a real <slug>/<task_id> node) even
  # though plan WAS parsed and is still recorded (diagnostic visibility,
  # never silently dropped) -- and _emit_dispatch_provenance falls all the
  # way back to the free-text heuristic rather than trusting a
  # half-populated header (this prompt's free text also names no plan, so
  # the net effect mirrors PL3: no task_started emitted).
  local plog_nla3="$tmp/pl-nla3" adm_nla3="$tmp/adm-nla3"
  PROGRESS_LOG_STATE_DIR="$plog_nla3" ADM_STATE_DIR="$adm_nla3" \
    CONV_TREE_STATE_PATH="$tmp/nla-3.json" CLAUDE_SESSION_ID="sess-nla-3" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"prompt":"NL-ATTRIBUTION: plan=orphan-plan role=builder\nno task= token in this header"},"session_id":"sess-nla-3"}' >/dev/null 2>&1
  local ledger_nla3; ledger_nla3=$(ls "$adm_nla3"/ledger/*.jsonl 2>/dev/null | head -n1)
  if [[ -n "$ledger_nla3" ]] && grep -q '"attributed":"0"' "$ledger_nla3" 2>/dev/null && grep -q '"plan":"orphan-plan"' "$ledger_nla3" 2>/dev/null; then
    echo "PASS: NLA3 partial header (plan without task) -> attributed=0 but the parsed plan value is still recorded"; pass=$((pass+1))
  else
    echo "FAIL: NLA3 expected attributed=0 with plan=orphan-plan in $ledger_nla3"; fail=$((fail+1))
    [[ -n "$ledger_nla3" ]] && cat "$ledger_nla3"
  fi
  if [[ ! -d "$plog_nla3" || -z "$(ls -A "$plog_nla3" 2>/dev/null)" ]]; then
    echo "PASS: NLA3b a partial header falls back to the free-text heuristic in full (no task_started emitted, matching PL3's plan-less anti-noise since the free text also names no plan)"; pass=$((pass+1))
  else
    echo "FAIL: NLA3b expected no task_started output for a partial-header, plan-less-by-heuristic dispatch (plog3=$(ls -A "$plog_nla3" 2>/dev/null))"; fail=$((fail+1))
  fi

  # NLA4: role=hacker (out-of-enum) -> role dropped (empty), plan/task
  # still honored, attributed still 1 (role never gates attribution).
  local adm_nla4="$tmp/adm-nla4"
  ADM_STATE_DIR="$adm_nla4" CONV_TREE_STATE_PATH="$tmp/nla-4.json" CLAUDE_SESSION_ID="sess-nla-4" \
    bash "$SELF" --on-builder-dispatch <<<'{"tool_name":"Task","tool_input":{"prompt":"NL-ATTRIBUTION: plan=some-plan task=2 role=hacker\nbody"},"session_id":"sess-nla-4"}' >/dev/null 2>&1
  local ledger_nla4; ledger_nla4=$(ls "$adm_nla4"/ledger/*.jsonl 2>/dev/null | head -n1)
  if [[ -n "$ledger_nla4" ]] && grep -q '"attributed":"1"' "$ledger_nla4" 2>/dev/null && ! grep -q '"role":"' "$ledger_nla4" 2>/dev/null; then
    echo "PASS: NLA4 an out-of-enum role= value is dropped (never guessed/passed-through) while plan/task attribution still succeeds"; pass=$((pass+1))
  else
    echo "FAIL: NLA4 expected attributed=1 with NO role label for role=hacker in $ledger_nla4"; fail=$((fail+1))
    [[ -n "$ledger_nla4" ]] && cat "$ledger_nla4"
  fi

  # NLA-STOP1: the END trigger. --on-stop reads the STOPPING session's OWN
  # transcript (not tool_input -- that lived in the DISPATCHING parent's
  # hook) for the SAME NL-ATTRIBUTION line, since the transcript's first
  # user turn IS the prompt the session was launched with. --on-spawn opens
  # the branch first (OBS1/OBS2's own precedent) so --on-stop's early
  # "nothing opened" guard does not short-circuit.
  local tp_nla1="$tmp/transcript-nla1.jsonl"
  cat >"$tp_nla1" <<'TRJSON'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"NL-ATTRIBUTION: plan=attribution-pipeline task=2 role=builder\nBuild the thing."}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}
TRJSON
  local obs_ledger_nla1="$tmp/obs-ledger-nla1.jsonl"
  CONV_TREE_STATE_PATH="$tmp/nla-stop-1.json" SIGNAL_LEDGER_PATH="$obs_ledger_nla1" CLAUDE_SESSION_ID="sess-nla-stop-1" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"NLA Stop Branch"},"session_id":"sess-nla-stop-1"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$tmp/nla-stop-1.json" SIGNAL_LEDGER_PATH="$obs_ledger_nla1" CLAUDE_SESSION_ID="sess-nla-stop-1" \
    bash "$SELF" --on-stop <<<"$(printf '{"session_id":"sess-nla-stop-1","transcript_path":"%s"}' "$tp_nla1")" >/dev/null 2>&1
  if grep -q '"event":"spawn-concluded"' "$obs_ledger_nla1" 2>/dev/null && grep -q 'plan=attribution-pipeline task=2 role=builder attributed=1' "$obs_ledger_nla1" 2>/dev/null; then
    echo "PASS: NLA-STOP1 --on-stop's spawn-concluded carries the SAME plan/task/role parsed from the stopping session's own transcript (END trigger, same ids as START)"; pass=$((pass+1))
  else
    echo "FAIL: NLA-STOP1 expected spawn-concluded detail with plan=attribution-pipeline task=2 role=builder attributed=1 in $obs_ledger_nla1"; fail=$((fail+1))
    [[ -f "$obs_ledger_nla1" ]] && cat "$obs_ledger_nla1"
  fi

  # NLA-STOP2: a transcript with NO NL-ATTRIBUTION line -> spawn-concluded
  # still carries attributed=0 explicitly (never omits the field, never
  # crashes on a header-less transcript) -- "a concluded event without a
  # matching start is its own honest class" starts here: a consumer sees
  # attributed=0 rather than a guessed or silently-missing field.
  local tp_nla2="$tmp/transcript-nla2.jsonl"
  cat >"$tp_nla2" <<'TRJSON2'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"just build the thing, no header here"}]}}
TRJSON2
  local obs_ledger_nla2="$tmp/obs-ledger-nla2.jsonl"
  CONV_TREE_STATE_PATH="$tmp/nla-stop-2.json" SIGNAL_LEDGER_PATH="$obs_ledger_nla2" CLAUDE_SESSION_ID="sess-nla-stop-2" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"NLA Stop Branch 2"},"session_id":"sess-nla-stop-2"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$tmp/nla-stop-2.json" SIGNAL_LEDGER_PATH="$obs_ledger_nla2" CLAUDE_SESSION_ID="sess-nla-stop-2" \
    bash "$SELF" --on-stop <<<"$(printf '{"session_id":"sess-nla-stop-2","transcript_path":"%s"}' "$tp_nla2")" >/dev/null 2>&1
  if grep -q 'plan= task= role= attributed=0' "$obs_ledger_nla2" 2>/dev/null; then
    echo "PASS: NLA-STOP2 a header-less transcript still emits attributed=0 explicitly (honest absence, never omitted or guessed)"; pass=$((pass+1))
  else
    echo "FAIL: NLA-STOP2 expected 'plan= task= role= attributed=0' in $obs_ledger_nla2"; fail=$((fail+1))
    [[ -f "$obs_ledger_nla2" ]] && cat "$obs_ledger_nla2"
  fi

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

# ============================================================================
# Progress-log `task_started` emission + DISPATCH-PROVENANCE MARKER
# (ask-rooted-workstreams-p1, Task 3 — "Dispatch emission splice").
#
# WHY: the plan's log-first law (constraint 6, verifier monopoly preserved —
# this NEVER flips a checkbox, only OBSERVES a dispatch) requires every
# dispatch to be recorded by a MECHANISM. This best-effort addition runs
# inside the ALREADY-WIRED --on-builder-dispatch (PreToolUse Task|Agent|
# Workflow) and --on-spawn (PreToolUse mcp__ccd_session__spawn_task |
# mcp__ccd_session_mgmt__start_code_task) hooks, alongside their existing
# conv-tree emission (untouched). It:
#   (a) emits ONE `task_started` progress-log event via the STABLE, UNCHANGED
#       scripts/progress-log.sh `emit` CLI (Task 2) when the dispatch text
#       names a plan (`docs/plans/<slug>.md`) + a task number — the same
#       shape Task 1's plan-lifecycle.sh splice already established;
#   (b) writes the DISPATCH-PROVENANCE MARKER Task 9's spawned-session
#       classification guard consumes, via scripts/dispatch-provenance.sh.
#
# ANTI-NOISE GUARD: a dispatch whose text names no plan is a SILENT no-op —
# not every builder/spawn dispatch serves a plan task (Explore, ad-hoc
# research, etc.), and emitting an empty-plan_slug event for every one of
# them would violate the anti-noise law and flood the orphan lane.
#
# HONEST LIMITATION (documented, not papered over — mirrors this file's own
# ADR-054 background-completion-ceiling discipline above): the true CHILD
# worktree path is not visible to a PreToolUse hook on the generic
# Task/Agent/Workflow dispatch surface. Harness/SDK `isolation: worktree`
# creates the worktree as part of EXECUTING the tool call and returns the
# path only in the PostToolUse result (this hook's --on-builder-complete
# mode) — not before. This splice therefore records `--worktree` best-effort:
# populated only from `.tool_input.cwd` when the dispatching tool_input
# happens to carry one (the mcp__ccd_session__spawn_task surface accepts an
# optional `cwd` project-root override) AND that hint itself already looks
# like a real `.claude/worktrees/` pool path (`_looks_like_worktree_pool`,
# FINDING 3 fix, 2026-07-14 review panel); left UNRESOLVED otherwise — a
# cross-repo spawn's `cwd` override is frequently a bare PROJECT ROOT, and
# recording that verbatim previously let a later, unrelated operator
# session at the same root get misclassified spawned by
# pl_classify_session's ancestor predicate. Task 9 (out of this task's
# scope) is expected to correlate primarily via its own
# cwd-under-`.claude/worktrees/` predicate and treat this marker as an
# ADDITIONAL, not sole, signal — see dispatch-provenance.sh's own header for
# the full marker schema.
#
# Never blocks: every external call is best-effort (`|| true`); missing CLIs
# are silently skipped via `[[ -f ]]` guards.
# ============================================================================

# Resolve scripts/progress-log.sh next to this hook's own hooks/ dir. Override
# for tests (mirrors CONV_TREE_STATE_LIB's env-override convention).
_pl_progress_log_cli() {
  if [[ -n "${PL_PROGRESS_LOG_CLI_OVERRIDE:-}" ]]; then
    printf '%s' "$PL_PROGRESS_LOG_CLI_OVERRIDE"; return 0
  fi
  printf '%s/../scripts/progress-log.sh' "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
}

# Resolve scripts/dispatch-provenance.sh. Override for tests.
_dispatch_provenance_cli() {
  if [[ -n "${DISPATCH_PROVENANCE_CLI_OVERRIDE:-}" ]]; then
    printf '%s' "$DISPATCH_PROVENANCE_CLI_OVERRIDE"; return 0
  fi
  printf '%s/../scripts/dispatch-provenance.sh' "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
}

# The combined prompt/description/content text a dispatch tool_input may
# carry, in ONE string (the same field set _builder_title / _spawn_title /
# _extract_rich_details already read from tool_input).
_dispatch_text() {
  local input="$1"
  _have jq || { printf ''; return 0; }
  printf '%s' "$input" | jq -r '
    [(.tool_input.prompt // ""),(.tool_input.description // ""),(.tool_input.content // "")] | join("\n")' 2>/dev/null || echo ""
}

# First `docs/plans/<slug>.md` reference in the dispatch text, or empty.
_extract_plan_slug() {
  local text="$1" ref
  ref=$(printf '%s' "$text" | grep -oE 'docs/plans/[A-Za-z0-9_.-]+\.md' | head -n1)
  [[ -z "$ref" ]] && { printf ''; return 0; }
  local slug="${ref#docs/plans/}"
  slug="${slug%.md}"
  printf '%s' "$slug"
}

# Best-effort task number: prefers the "Task N of" convention this harness's
# orchestrator dispatch prompts use (matches this exact plan's own dispatch
# prompt shape); falls back to the first bare "Task N" mention. N may be
# dotted (e.g. 3.2). Empty when no task number is found.
_extract_task_id() {
  local text="$1" m
  m=$(printf '%s' "$text" | grep -oE '[Tt]ask[[:space:]]+[0-9]+(\.[0-9]+)?[[:space:]]+of\b' | head -n1)
  if [[ -z "$m" ]]; then
    m=$(printf '%s' "$text" | grep -oE '[Tt]ask[[:space:]]+[0-9]+(\.[0-9]+)?' | head -n1)
  fi
  [[ -z "$m" ]] && { printf ''; return 0; }
  printf '%s' "$m" | grep -oE '[0-9]+(\.[0-9]+)?' | head -n1
}

# ============================================================================
# NL-ATTRIBUTION header (attribution-pipeline task, 2026-07-29 — operator
# directive: "how do we ensure we don't keep running into this same damn
# issue of you reporting something that's complete false" -- the START
# trigger (this hook's --on-builder-dispatch) already fires reliably, but
# nothing a dispatch carries is MACHINE-READABLE, so deriveLiveAgentLeaves
# (workstreams-ui/server/roadmap-routes.js) can bind nothing and the cockpit
# reads "N running, unattributed to a task" all day. This is the convention
# (doctrine: doctrine/orchestrator-pattern.md) + parser closing that gap.
#
# CONVENTION: a dispatch prompt MUST OPEN WITH this line -- it must START A
# LINE (leading whitespace only) and sit within the first
# NL_ATTRIBUTION_MAX_LINE (default 5) lines of the JOINED
# prompt+description+content that _dispatch_text produces:
#   NL-ATTRIBUTION: plan=<slug> task=<id> role=<builder|verifier|reviewer|advocate>
# (CORRECTED 2026-07-30. This header previously read "MAY include a line
# ANYWHERE in its text" -- the retracted charter of the quoted-header defect,
# still sitting 40 lines above the corrected comment that says the opposite.
# It survived two sweeps because it is a PARAPHRASE: greps for `inert` and for
# "anywhere in the prompt text" both missed "anywhere in its text". A
# retraction sweep is scoped by the CLAIM, not by one lexical form of it --
# re-run it with every wording the claim has ever had.)
# Same key=value vocabulary as admission-lib.sh's adm_admit labels and
# estate-registration-lib.sh's reg_register labels (plan=/task= already
# closed-enum keys in both) -- one vocabulary across all three attribution
# surfaces, not a fourth invented shape.
#
# _extract_nl_attribution <text> -> plan|task|role|attributed ('|'-joined —
#   see the printf at the end of this function for why NOT tab-joined)
#   attributed=1 iff BOTH plan AND task are present -- the id scheme
#   (roadmap-routes.js: `<slug>/<task_id>`) needs both to name a real node;
#   role is supplementary metadata and never gates attribution. role is a
#   CLOSED enum (builder|verifier|reviewer|advocate) -- an unrecognized
#   value is dropped, not guessed, mirroring _adm_key_allowed's closed-enum
#   discipline. Tolerant of a missing/malformed header: never guesses,
#   always returns the 4-field row (empty fields, attributed=0) so a caller
#   can unconditionally destructure it.
# ============================================================================
_extract_nl_attribution() {
  local text="$1"
  # POSITIONAL ANCHOR (F1/F2 pass, adversarial refuter 2026-07-30): the
  # header must OPEN the dispatch -- it must start a line (leading whitespace
  # only) AND sit within the first NL_ATTRIBUTION_MAX_LINE lines of the text.
  #
  # WHY. This grep used to match `NL-ATTRIBUTION:.*` ANYWHERE in the joined
  # prompt+description+content, which made a QUOTED header indistinguishable
  # from a real one: a prompt merely DISCUSSING a prior dispatch ("...it was
  # dispatched with the line NL-ATTRIBUTION: plan=X task=9 role=builder and it
  # failed") emitted a real task_started for task 9 and turned that chip
  # green. That is the SAME defect class as the free-text scrape this change
  # removed -- a MENTION is not a DISPATCH -- surviving inside the one source
  # the fix had just declared authoritative, and it is a live vector rather
  # than a theoretical one: handoff, review and post-mortem prompts routinely
  # paste the builder prompt they are about. Pinned by RPL7/RPL7b; RPL7c pins
  # that a real dispatch is NOT collateral damage.
  #
  # WHY THIS ANCHOR IS THE RIGHT ONE. Line-start alone does not close it (a
  # verbatim paste keeps the header at line start); a first-lines window alone
  # does not either (prose can quote a header inline in its opening sentence).
  # Both together match what doctrine/orchestrator-pattern.md ALREADY states
  # in those words -- a dispatch prompt "MUST open with" the header -- so this
  # narrows the parser to the documented convention rather than inventing a
  # stricter one. (orchestrator-pattern-full.md said "anywhere in the prompt
  # text"; that looser wording was the bug's charter and is corrected in the
  # same commit.)
  #
  # RESIDUAL, STATED FROM THE EXECUTED BOUNDARY (restated 2026-07-30 after a
  # harness-reviewer REFORMULATE; the previous wording here was UNDERSTATED and
  # its doctrine counterpart was outright FALSE).
  #
  # THE RESIDUAL IS: any quoted header that STARTS A LINE -- with arbitrary
  # leading whitespace, including the indentation a fenced or indented paste
  # adds -- within the first NL_ATTRIBUTION_MAX_LINE lines of the JOINED
  # `prompt + description + content` text still emits. It is NOT limited to
  # "a prompt that literally begins with a quoted header".
  #
  # THE WINDOW IS OVER THE JOINED TEXT, NOT OVER THE PROMPT (corrected in
  # round 3). _dispatch_text (see its definition above) joins the three
  # tool_input fields with newlines BEFORE this function applies the window,
  # so the admitted region spans a SECOND INPUT FIELD whenever the prompt is
  # short: a 3-line prompt with the header alone in `description` puts it on
  # JOINED line 4 and EMITS (RPL7i), while the same description behind a
  # 10-line prompt is silent (RPL7j). Saying "the first N lines of your
  # prompt" is therefore advice an author cannot act on.
  #
  # Measured against this exact code -- EMITS: a 2-line preamble + fenced
  # paste; a 4-space-indented paste; a TAB-indented header on line 2; a
  # 3-line preamble + fence (header on line 5, the last admitted line); a
  # header in `description` behind a short prompt. SILENT: header on joined
  # line 6+, any `> ` or `- ` prefix, and a mid-sentence quote.
  # Pinned by RPL7d/RPL7e/RPL7f (the n-1 / n / n+1 boundary triple),
  # RPL7g/RPL7h (the documented escapes) and RPL7i/RPL7j (the joined-input
  # scope).
  #
  # WHY THE EARLIER WORDING WAS WRONG, because the mechanism generalizes:
  # RPL7b passes with a preamble that happens to run EIGHT lines, clearing the
  # 5-line window by a wide margin. Prose written from that single test
  # generalized to "a quoted header below the prose that introduces it is
  # inert" -- false for every preamble shorter than the window, which is the
  # shape a real handoff prompt has. A positional guard exercised only
  # comfortably beyond its threshold certifies nothing about the threshold.
  # RULE: every threshold guard ships n-1, n AND n+1, and the prose residual
  # is written from the executed boundary, never from the motivating anecdote.
  #
  # Closing the residual entirely needs an out-of-band channel (a dispatch
  # field the prose cannot forge), which this hook cannot reach from
  # PreToolUse tool_input alone -- filed in docs/backlog.md, not papered over.
  #
  # The window is overridable so a caller can compress or widen it without
  # editing the parser; 5 lines allows a blank line or a short preamble ahead
  # of the header while excluding a paste, which necessarily follows the
  # explanatory prose that introduces it.
  local maxln="${NL_ATTRIBUTION_MAX_LINE:-5}"
  case "$maxln" in ''|*[!0-9]*) maxln=5 ;; esac
  [[ "$maxln" -lt 1 ]] && maxln=5
  local line
  line=$(printf '%s' "$text" | head -n "$maxln" 2>/dev/null \
         | grep -oE '^[[:space:]]*NL-ATTRIBUTION:.*' | head -n1)
  local plan="" task="" role=""
  if [[ -n "$line" ]]; then
    plan=$(printf '%s' "$line" | grep -oE 'plan=[A-Za-z0-9_.-]+' | head -n1)
    plan="${plan#plan=}"
    task=$(printf '%s' "$line" | grep -oE 'task=[A-Za-z0-9_.-]+' | head -n1)
    task="${task#task=}"
    role=$(printf '%s' "$line" | grep -oE 'role=(builder|verifier|reviewer|advocate)' | head -n1)
    role="${role#role=}"
  fi
  local attributed="0"
  [[ -n "$plan" && -n "$task" ]] && attributed="1"
  # Field separator is '|', NOT a tab: bash treats tab as "IFS whitespace"
  # (like space/newline) regardless of being the SOLE IFS character, so
  # `IFS=$'\t' read -r a b c d` silently COLLAPSES leading empty fields —
  # proven live: `printf '\t\t\t0'` read back with IFS=$'\t' assigns "0" to
  # the FIRST variable, not the fourth (every caller destructures via `read`
  # and must see a true absent-plan/absent-task row correctly, so this bug
  # would have silently mis-attributed the common no-header case). '|' is
  # not IFS whitespace, so leading/embedded empty fields round-trip exactly
  # — and '|' can never appear in plan/task (charset [A-Za-z0-9_.-]) or role
  # (closed enum), so no value collision is possible.
  printf '%s|%s|%s|%s' "$plan" "$task" "$role" "$attributed"
}

# _stop_extract_nl_attribution <transcript_path>
#   END-side counterpart: a dispatched CHILD session cannot see its own
#   dispatch tool_input (that lived in the PARENT's PreToolUse hook) but its
#   OWN transcript's first user-role turn IS the prompt it was launched
#   with -- the same text the header convention asks orchestrators to put
#   the NL-ATTRIBUTION line into. Reading it at --on-stop (not
#   --on-session-start) is deliberate: the transcript is GUARANTEED
#   complete by the time a session stops, whereas SessionStart timing
#   relative to first-turn ingestion is not something this hook can safely
#   assume. jq idiom mirrors work-integrity-gate.sh's _wig_touched_plan_paths
#   and workstreams-emit-reconciler.sh's user/tool_result extraction (both
#   already read this same transcript JSONL shape) -- not a new technique.
#   Only the FIRST matching user-role turn is read (head -n1): later turns
#   are ordinary conversation, not the dispatch prompt.
#
#   POSITIONAL-ANCHOR CONSEQUENCE (2026-07-30, F2): this function flattens the
#   turn to ONE line (gsub of newlines) before handing it to
#   _extract_nl_attribution, so the anchor there resolves, on this path, to
#   "the first user turn BEGINS with the header". That is a deliberate
#   tightening and the SAME rule the START side applies: a child session whose
#   opening turn merely QUOTES a header (a handoff or review prompt) must not
#   attribute its spawn-concluded row to the quoted task.
_stop_extract_nl_attribution() {
  local tp="$1"
  [[ -n "$tp" && -f "$tp" ]] || { _extract_nl_attribution ""; return 0; }
  _have jq || { _extract_nl_attribution ""; return 0; }
  local text
  text=$(jq -r '
    select(.type == "user" or .role == "user" or .message.role == "user")
    | (.message.content // .content // empty)
    | if type == "array" then
        ([ .[] | select(type=="object" and .type=="text") | .text ] | join(" "))
      elif type == "string" then .
      else empty end
    | gsub("\n"; " ")
  ' "$tp" 2>/dev/null | head -n1)
  _extract_nl_attribution "$text"
}

# Read the plan header's `ask-id:` value from docs/plans/<slug>.md, resolved
# against the CURRENT repo's toplevel (ephemeral-ok READ, constraint 11 --
# this is not a durable in-repo WRITE). Deliberately duplicates
# plan-lifecycle.sh's extract_ask_id awk pattern rather than sourcing that
# hook: this hook does not depend on plan-lifecycle.sh, keeping the two
# splices independently best-effort per this file's own failure-isolation
# contract. Empty when the plan/header/repo is unresolvable -- pl_emit's own
# orphan lane (pl_path_for("") -> unlinked.jsonl) absorbs it, same as Task 1.
#
# PLACEHOLDER GUARD (fix, 2026-07-27 -- SAME proven bug and SAME fix as
# plan-lifecycle.sh's extract_ask_id; kept in sync deliberately since this
# is a KNOWN duplication, not a shared function): a plan header still
# carrying the LITERAL un-substituted template default (`ask-id: <id | none
# — no linked ask>`, adapters/claude-code/templates/plan-template.md's own
# text; real example still on disk: docs/plans/cockpit-roadmap-redesign.md:7)
# matches the awk pattern below and used to hand back the truncated literal
# token `<id` as if it were a real ask-id -- pl_emit then filed the event
# under the plausible-but-wrong `_id.jsonl` (1090 real events proven on this
# machine, most from THIS splice's own --on-builder-dispatch task_started
# emission). A token starting with `<` is never a legitimate ask-id, so it
# means the same thing an absent header means and now resolves to the same
# empty/"unlinked" case. (progress-log-lib.sh's pl_path_for independently
# quarantines any placeholder-shaped ask_id reaching it by any other path --
# a writer-side backstop, not relied on here.)
_resolve_ask_id_for_plan_slug() {
  local slug="$1"
  [[ -z "$slug" ]] && { printf ''; return 0; }
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { printf ''; return 0; }
  local planfile="$root/docs/plans/$slug.md"
  [[ -f "$planfile" ]] || { printf ''; return 0; }
  local raw
  raw="$(awk '
    /^ask-id:[[:space:]]*[^[:space:]]+/ {
      sub(/^ask-id:[[:space:]]*/, "", $0)
      sub(/[[:space:]].*$/, "", $0)
      print $0
      exit
    }
  ' "$planfile" 2>/dev/null)"
  case "$raw" in
    # '<'* = template placeholder; none = the documented no-ask spelling —
    # both sentinels resolve to empty (re-review Critical, 2026-07-28).
    '<'* | none) printf ''; return 0 ;;
  esac
  printf '%s' "$raw"
}

# _dispatch_state_dir -- resolve the dispatch-provenance state dir with the
# SAME order scripts/dispatch-provenance.sh's `_dp_state_dir` and
# progress-log-lib.sh's `_pl_dispatch_provenance_dir` use, so a caller that
# sandboxes one sandboxes all three. Used only to park the replay-debounce
# files below (named WITHOUT a .json suffix so they never collide with the
# `*.json` marker glob that pl_classify_session / _dp_prune walk).
_dispatch_state_dir() {
  if [[ -n "${DISPATCH_PROVENANCE_STATE_DIR:-}" ]]; then
    printf '%s' "$DISPATCH_PROVENANCE_STATE_DIR"; return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/state/dispatch-provenance' "${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}/dispatch-provenance-selftest/$$}"
    return 0
  fi
  printf '%s/.claude/state/dispatch-provenance' "${HOME:-$PWD}"
}

# _dispatch_replay_token <sid> <slug> <task_id>
#   The per-dispatch DISCRIMINATOR for the task_started dedup key (FINDING 2,
#   2026-07-14 ask-splice review panel).
#
# THE PROBLEM. The natural key's session_id is the DISPATCHING orchestrator's
# CLAUDE_SESSION_ID -- INVARIANT across every dispatch it makes (and child_id
# is a pure function of that same sid, so it is no help either). A
# within-session RE-DISPATCH of a failed task therefore produced an identical
# plan_slug+task_id+session_id key and was silently DROPPED. But the key must
# STILL absorb a genuine hook double-fire (the same PreToolUse firing twice
# for ONE tool call) -- so the discriminator has to tell "the same dispatch,
# fired twice" apart from "the same task, dispatched twice", and the ONLY
# thing that distinguishes those two is WHEN they happened.
#
# WHY NOT A WALL-CLOCK TIME BUCKET (floor(now/N), the obvious first answer --
# and the one this function replaces): a bucket has BOUNDARIES, and two fires
# milliseconds apart can straddle one. That makes a double-fire produce a
# DUPLICATE event whenever it happens to land on a boundary -- a real,
# silently-wrong outcome, not just a flaky test. (It is what made this file's
# own PL1b regression scenario fail.)
#
# WHAT THIS DOES INSTEAD -- a debounce anchored at the FIRST fire, so there is
# no boundary to straddle: the first fire of a given (sid, slug, task_id)
# records `<epoch> <token>` in a small state file and returns that token. Any
# re-fire within DISPATCH_REPLAY_DEBOUNCE_SECONDS (default 120) reads the file
# and returns the SAME token -> identical natural key -> deduped (a replay).
# A fire after the window mints a NEW token -> new key -> a distinct event (a
# genuine re-dispatch).
#
# SIZING THE WINDOW (120s). It must exceed the wall-clock gap between two
# fires of ONE dispatch, and stay well under the gap between two GENUINE
# dispatches of the same task. The lower bound is NOT "sub-second" -- and, as
# of 2026-07-29, NOT "tens of seconds" either: this hook forks a whole bash
# process (plus git + sha1sum) per fire, and on this machine's Windows/Git-
# Bash fork-taxed target that measurably costs multiple tens of seconds under
# load. The PREVIOUS 30s default was PROVEN too tight, not just theorized:
# the full self-test suite failed PL1b (got 2 want 1) and PL1c (got 3 want 2)
# twice in a row on this machine, and the T3 verifier independently measured
# a 32-wall-second gap between two back-to-back stamp writes the same day.
# The upper bound is still generous: a genuine orchestrator re-dispatch cycle
# is dispatch -> let the builder run -> verify -- minutes, not seconds -- so
# 120s keeps large real margin on both sides even after the correction.
# Override via the env var for tests that need to compress the clock rather
# than sleep past a real window.
#
# Best-effort and NEVER BLOCKS: if the state dir is unwritable or `date` is
# missing, it falls back to a value that is merely conservative (never a
# crash). Two truly-concurrent first-fires could both mint a token and produce
# one duplicate line -- exactly the pre-existing worst case, never a lost or
# blocked write.
_dispatch_replay_token() {
  local sid="${1:-}" slug="${2:-}" task_id="${3:-}"
  local now; now=$(date -u +%s 2>/dev/null)
  # No usable clock -> return a constant so a replay still dedups (the
  # conservative direction: never manufacture a spurious second event).
  [[ -n "$now" ]] || { printf 'noclock'; return 0; }

  local debounce="${DISPATCH_REPLAY_DEBOUNCE_SECONDS:-120}"
  local dir; dir="$(_dispatch_state_dir)"
  mkdir -p "$dir" 2>/dev/null || { printf '%s' "$now"; return 0; }

  local key; key=$(printf '%s|%s|%s' "$sid" "$slug" "$task_id" | _sha1 | cut -c1-16)
  local f="$dir/.replay-$key"

  local prev_ts="" prev_token=""
  if [[ -f "$f" ]]; then
    read -r prev_ts prev_token <"$f" 2>/dev/null || true
    if [[ "$prev_ts" =~ ^[0-9]+$ ]] && [[ -n "$prev_token" ]] \
       && [[ $(( now - prev_ts )) -le "$debounce" ]] && [[ $(( now - prev_ts )) -ge 0 ]]; then
      # Within the debounce window -> this is a REPLAY of the dispatch the
      # stored token already represents. Deliberately do NOT refresh the
      # stored ts: the window stays anchored at the FIRST fire, so a long
      # chain of replays can never keep extending it.
      printf '%s' "$prev_token"
      return 0
    fi
  fi

  # First fire (or past the window) -> mint a new token and anchor the window.
  printf '%s %s\n' "$now" "$now" >"$f" 2>/dev/null || true
  printf '%s' "$now"
  return 0
}

# _looks_like_worktree_pool <path> -- true iff <path> (after normalizing
# backslashes) sits inside a `.claude/worktrees/` pool. Mirrors
# progress-log-lib.sh's pl_classify_session pool predicate exactly (same
# case pattern) so the writer side and the reader side agree on what
# "looks like a real child worktree" means (FINDING 3, 2026-07-14 review
# panel -- see below).
_looks_like_worktree_pool() {
  local p="${1:-}"
  [[ -z "$p" ]] && return 1
  local norm="${p//\\//}"
  case "$norm" in
    */.claude/worktrees/*) return 0 ;;
    *) return 1 ;;
  esac
}

# _emit_dispatch_provenance <input> <sid> <child_id> [h_plan h_task h_role h_attributed first_dispatch]
#   Best-effort task_started progress-log emission + dispatch-provenance
#   marker write. sid/child_id are the SAME dispatching-session-derived
#   values the caller already computed for the conv-tree SESSIONS lineage
#   rendering -- this is "the same provenance the SESSIONS lineage rendering
#   consumes" per the plan's Task 3 spec, not a newly-invented session
#   concept.
#
# ===========================================================================
# THE TWO SINKS ARE NOT THE SAME SIGNAL (ROADMAP-FALSE-ETERNAL-RUNNING-01,
# 2026-07-30). They used to share one attribution path; that is the defect.
#
#   SINK 1 `task_started` -> the cockpit's GREEN "running NOW" chip. It is a
#   CLAIM ABOUT THE PRESENT and the operator reads it as one, verbatim: "The
#   green items are supposed to indicate something is actively running."
#   A wrong one is a lie on the operator's screen.
#
#   SINK 2 the dispatch-provenance marker -> pl_classify_session's
#   spawned-session guard. It is a CORRELATION HINT consumed by a
#   best-effort classifier; a loose one costs a misclassification at worst.
#
# So they get DIFFERENT admission rules, and sink 1 gets the strict one.
#
# SINK 1 RULE (both conditions, no fallback):
#   (a) HEADER-AUTHORITATIVE ONLY. Only an `NL-ATTRIBUTION: plan=<slug>
#       task=<id>` header may name the task that started. The free-text
#       heuristic (_extract_plan_slug / _extract_task_id) is NEVER a source
#       of task_started. It scrapes the PROMPT TEXT, so a dispatch that
#       merely MENTIONS `docs/plans/<slug>.md` or the words "Task 9" marked
#       that task started -- MEASURED 2026-07-30: one orchestration prompt
#       mentioning a plan re-greened it with no task id at all, and
#       cockpit-roadmap-redesign/9 (an ACCEPTANCE task only the operator can
#       perform, which no agent can ever be running) was marked started
#       from prose. A mention is not a dispatch.
#   (b) FIRST FIRE OF THIS DISPATCH IDENTITY ONLY (first_dispatch==1). See
#       the caller's replay note: PreToolUse re-fires for EVERY historical
#       Task/Agent tool call in the transcript, so without this a single
#       replay re-greens every task the session ever dispatched, forever.
#
# NO-HEADER POLICY = HONEST SILENCE, and here is the justification (the
# alternative considered was "emit an explicitly-unattributed event"):
# an unattributed task_started names no task, so it CANNOT turn any chip
# green -- it can only land in the orphan lane as a row a future consumer
# might mis-join, which is exactly the pollution class
# PROGRESS-LOG-ID-JSONL-UNACCOUNTED-01 already tracks. The observability it
# would provide already exists and is strictly better: the caller logs a
# WARN line per unattributed dispatch WITH a running count (4090 and rising
# on this machine on 2026-07-30). Silence here loses no information and
# fabricates no green. Falling back to scraping is not an option at all --
# scraping IS the bug.
#
# SINK 2 keeps its pre-existing header-then-free-text resolution UNCHANGED
# (a looser hint is the right trade for a correlation guard, and narrowing
# it would shrink pl_classify_session's evidence for a defect it does not
# have). It IS also replay-gated, which strictly HELPS it: a replayed marker
# is byte-identical to the one the first fire already wrote in every field
# the consumer joins on, and its only real effect was evicting genuine older
# markers out of dispatch-provenance.sh's 200-marker cap (auditor.js already
# recorded the dir pinned at exactly 200 markers spanning ~2.3h).
# ===========================================================================
_emit_dispatch_provenance() {
  local input="$1" sid="$2" child_id="$3"
  local h_plan="${4:-}" h_task="${5:-}" h_role="${6:-}" h_attributed="${7:-0}"
  local first_dispatch="${8:-1}"

  # (b) REPLAY GATE -- applies to BOTH sinks. A PreToolUse fire for a
  # dispatch identity this session already recorded is a transcript replay,
  # not a start. Nothing about it is news; emitting is pure fabrication.
  if [[ "$first_dispatch" != "1" ]]; then
    _log "dispatch-provenance: replayed dispatch identity (session=$sid) -> no task_started, no marker"
    return 0
  fi

  local text; text=$(_dispatch_text "$input")

  # ---- SINK 1: task_started -- HEADER ONLY, never the free-text scrape ----
  if [[ "$h_attributed" == "1" ]]; then
    local pl_cli; pl_cli=$(_pl_progress_log_cli)
    if [[ -f "$pl_cli" ]]; then
      local h_ask_id; h_ask_id=$(_resolve_ask_id_for_plan_slug "$h_plan")
      # FINDING 2 fix: --dedup-extra carries a per-dispatch replay-debounce
      # token (see _dispatch_replay_token above) so this dispatch's
      # task_started event is NOT collapsed with a LATER re-dispatch of the
      # same task from the same (invariant) dispatching session_id, while a
      # hook double-fire of THIS dispatch still dedups to one event.
      local dispatch_token; dispatch_token=$(_dispatch_replay_token "$sid" "$h_plan" "$h_task")
      bash "$pl_cli" emit --type task_started --ask "$h_ask_id" --plan-slug "$h_plan" \
        --task-id "$h_task" --session-id "$sid" --dedup-extra "$dispatch_token" \
        --summary "task ${h_task} dispatched" --emitter workstreams-emit \
        >/dev/null 2>&1 || true
    fi
  fi

  # ---- SINK 2: dispatch-provenance marker (resolution UNCHANGED) ---------
  local slug task_id
  if [[ "$h_attributed" == "1" ]]; then
    slug="$h_plan"
    task_id="$h_task"
  else
    slug=$(_extract_plan_slug "$text")
    [[ -z "$slug" ]] && return 0
    task_id=$(_extract_task_id "$text")
  fi
  local ask_id; ask_id=$(_resolve_ask_id_for_plan_slug "$slug")

  # Best-effort worktree hint: only the spawn_task surface's optional `cwd`
  # override is ever visible pre-dispatch (see the section header above) --
  # empty on the generic Task|Agent|Workflow surface, which is an honest
  # gap, not a guessed value (dispatch-provenance.sh records it as such).
  #
  # FINDING 3 fix (2026-07-14 review panel): a cross-repo spawn_task's cwd
  # override is frequently a PROJECT ROOT (the documented estate workflow
  # for spawning into a different project entirely), not the
  # `.claude/worktrees/<slug>` child the harness's own per-task isolation
  # actually creates. Recording that bare project-root as worktree_path
  # made a LATER, wholly unrelated operator session at that same root (or a
  # subdirectory of it) match pl_classify_session's ancestor predicate and
  # get misclassified spawned -- silently dropping its opening ask. Only
  # ever record --worktree when the hint itself already looks like a real
  # worktrees-pool path; otherwise this is the SAME honest UNRESOLVED gap
  # the generic Task/Agent/Workflow surface already produces (never a
  # guess) -- predicate (a) in pl_classify_session catches the real child
  # unconditionally when the harness's own isolation actually creates one.
  local wt_hint
  wt_hint=$(printf '%s' "$input" | jq -r '.tool_input.cwd // empty' 2>/dev/null || echo "")

  local dp_cli; dp_cli=$(_dispatch_provenance_cli)
  if [[ -f "$dp_cli" ]]; then
    if [[ -n "$wt_hint" ]] && _looks_like_worktree_pool "$wt_hint"; then
      bash "$dp_cli" write --ask "$ask_id" --plan-slug "$slug" --task-id "$task_id" \
        --session-id "$sid" --child-id "$child_id" --worktree "$wt_hint" --role "$h_role" \
        >/dev/null 2>&1 || true
    else
      bash "$dp_cli" write --ask "$ask_id" --plan-slug "$slug" --task-id "$task_id" \
        --session-id "$sid" --child-id "$child_id" --role "$h_role" \
        >/dev/null 2>&1 || true
    fi
  fi
  return 0
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

  # NL-ATTRIBUTION header parse (attribution-pipeline task, 2026-07-29) —
  # ONE parse of the dispatch text, reused by every downstream sink below
  # (governor ledger, dispatch-provenance marker, WARN counter) so they can
  # never disagree with each other about what this dispatch claims.
  local h_plan h_task h_role h_attributed
  IFS='|' read -r h_plan h_task h_role h_attributed <<<"$(_extract_nl_attribution "$(_dispatch_text "$input")")"

  local lib; lib=$(_resolve_state_lib)
  local events
  events="$(BUILDER_INPUT_JSON="$input" _builder_creation_events "$sid" "$tool" "$title" "$child_id" "$item_id" "$bg")]"
  local ef; ef=$(mktemp 2>/dev/null || echo "/tmp/cte-bd-$$.json")
  printf '%s' "$events" >"$ef"
  _emit_dual "$lib" "$ef"
  rm -f "$ef" 2>/dev/null || true

  # ---- ADMISSION OBSERVATION SPLICE (accountable-estate T3) -----------------
  # OBSERVE MODE ONLY: records what estate admission WOULD have decided for this
  # dispatch; never blocks, never changes this hook's exit code. This is the
  # emit-feed registration callsite named by the T3 task text — it sits on the
  # PreToolUse Task|Agent|Workflow matcher, so it is also the "dispatch gate"
  # surface. Per review F2 the lib, not this gate, is the guarantee: the same
  # lib is called by session-resumer.sh (hookless scheduled dispatcher) and
  # spawn-worktree.sh. Best-effort by construction — a missing or broken lib
  # leaves this hook's behavior byte-identical. See hooks/lib/admission-lib.sh.
  #
  # plan=/task=/role=/attributed= (attribution-pipeline task, 2026-07-29):
  # the SAME NL-ATTRIBUTION parse above, carried into the governor ledger row
  # this splice already writes 1000+ times/day — the START trigger the
  # cockpit's future consumer joins against (see
  # docs/plans/fragments/attribution-server-fragment.md). adm_admit's own
  # _adm_key_allowed enum gates role/attributed same as plan/task; empty
  # values are dropped by adm_admit itself, so an absent header contributes
  # only attributed=0 (honest, never guessed).
  (
    # SUBSHELL, not brace group (round-3 review M1: 4th sibling of the same
    # containment sweep — a set -u abort inside the lib escapes
    # `{...} || true` and would kill this hook before the correlation-ledger
    # write below).
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/admission-lib.sh" 2>/dev/null \
      && declare -F adm_admit >/dev/null 2>&1 \
      && adm_admit emit-feed kind="$([[ "${bg:-0}" == "1" ]] && printf bg || printf fg)" \
           plan="$h_plan" task="$h_task" role="$h_role" attributed="$h_attributed" >/dev/null 2>&1
  ) || true

  # Builder correlation ledger (observability + reconciler hint):
  # item_id \t child_id \t tool \t bg \t title \t ts — append once per item.
  #
  # REPLAY DETECTION (ROADMAP-FALSE-ETERNAL-RUNNING-01, 2026-07-30). This
  # ledger's first-seen semantics are now LOAD-BEARING, not just
  # observability: `dispatch_is_new` is the ONLY honest signal available at
  # PreToolUse for "is this tool call happening now, or is the transcript
  # being replayed?".
  #
  # WHY IT IS NEEDED (measured, not theorized). PreToolUse on Task|Agent|
  # Workflow re-fires for EVERY historical dispatch in the session's
  # transcript. On 2026-07-30 the operator's session logged 100 fires in 67
  # seconds (22:16:59Z-22:18:06Z) walking this very ledger's rows in order
  # from index 0 -- a dispatch whose real tool call happened 43 hours
  # earlier -- with exactly 2 genuinely-new dispatches spliced in. Five such
  # replays happened between 21:11Z and 22:29Z. Every one re-emitted
  # task_started for every plan/task any prompt in that history named, which
  # is precisely why plans stayed green with nothing running. No downstream
  # idle-window can separate these: the replayed events and the genuine ones
  # arrive in the same second.
  #
  # WHY THIS ORACLE AND NOT A TIME WINDOW: item_id is sha1(sid|tool|title)
  # with NO time bucket -- deliberately, so PostToolUse and the Stop-time
  # reconciler recompute it hours later (see _builder_classify). A row here
  # therefore means "this session already dispatched this identity", which
  # is exactly the question. It is also correct from the FIRST fire after
  # install: the ledger already holds the session's history, so a replay
  # finds every id present rather than needing a warm-up period.
  #
  # ACCEPTED COST, stated plainly: a GENUINE re-dispatch that reuses the
  # identical (session, tool, title) is now treated as the same dispatch and
  # emits no second task_started. That is a deliberate trade -- the harness
  # ALREADY treats that triple as one work item everywhere else (this
  # ledger dedups it, _emit_dual dedups the conv-tree row), so this makes
  # task_started agree with the identity model rather than inventing a new
  # one, and it errs toward a MISSING green rather than a FALSE one, which
  # is the operator's stated bar. A re-dispatch with any distinct title
  # (the real-world shape: "(retry)", "Re-verify", "Round 2") is unaffected
  # -- see scenario RPL3. Empirical support: all 105 dispatch identities in
  # the operator's real 43-hour ledger are distinct titles.
  mkdir -p "$LEDGER_DIR" 2>/dev/null || true
  local ledger="$LEDGER_DIR/builder-${sid}.jsonl"
  local dispatch_is_new=1
  if [[ -f "$ledger" ]] && grep -q "^${item_id}	" "$ledger" 2>/dev/null; then
    dispatch_is_new=0
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$item_id" "$child_id" "$tool" "$bg" "$title" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" >>"$ledger" 2>/dev/null || true
  fi

  # WARN counter (constitution §10 requires the golden scenario/FP-rate/
  # retirement condition named at the callsite, not just here — see
  # doctrine/orchestrator-pattern-full.md's NL-ATTRIBUTION section). NEVER
  # blocks: this is the adoption-lag signal, not a gate. Counts prior
  # attributed=0 lines already appended to the append-only LOG_FILE (no
  # separate racy read-modify-write counter file needed) so the value is
  # exact under sequential dispatches and merely best-effort (never wrong in
  # a blocking sense) under true concurrency.
  local warn_count=""
  if [[ "$h_attributed" == "0" ]]; then
    local prior_warns; prior_warns=$(grep -c 'WARN unattributed builder dispatch' "$LOG_FILE" 2>/dev/null | tr -d ' \n')
    [[ -n "$prior_warns" ]] || prior_warns=0
    warn_count=$((prior_warns + 1))
    _log "WARN unattributed builder dispatch (no NL-ATTRIBUTION header) item=$item_id title=\"$title\" session=$sid — unattributed dispatch #$warn_count logged this session (doctrine/orchestrator-pattern.md names the header MANDATORY; this WARN never blocks the dispatch)"
  fi
  _log "builder-dispatch item=$item_id node=$child_id tool=$tool bg=$bg title=\"$title\" session=$sid plan=$h_plan task=$h_task role=$h_role attributed=$h_attributed replay=$((1 - dispatch_is_new))${warn_count:+ warn_count=$warn_count}"

  # ask-rooted-workstreams-p1 Task 3: best-effort task_started progress-log
  # emission + dispatch-provenance marker (see the TWO SINKS block above
  # that function for the full contract). Header fields AND the replay
  # signal are passed through: task_started is emitted ONLY for a
  # header-attributed dispatch on its first fire.
  _emit_dispatch_provenance "$input" "$sid" "$child_id" "$h_plan" "$h_task" "$h_role" "$h_attributed" "$dispatch_is_new" || true

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
