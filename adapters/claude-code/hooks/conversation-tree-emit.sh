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
# Invocation modes:
#   --on-spawn   PreToolUse on the enumerated spawn surface
#                (mcp__ccd_session__spawn_task | mcp__ccd_session_mgmt__start_code_task
#                 | Task | Agent). Emits `branch-opened` for the spawned child
#                branch (parented under an auto-detected project/global root
#                node) and records it to a per-session correlation ledger.
#   --on-stop    Stop hook. Emits `concluded` for every branch this session
#                opened (read from the ledger), then clears the ledger.
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

MODE="${1:-}"

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/conversation-tree-emit.log"
LEDGER_DIR="$HOME/.claude/state/conversation-tree-emit"

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

# Resolve the state-library entry module (state.js). Mirrors the conv-tree
# gates' _resolve_state_lib resolution order so writer and gate agree.
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

# ADR-032 §5 path resolution — byte-identical logic to the conv-tree gates'
# _resolve_state_path so the §5 sink lands exactly where the gates read.
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

# ============================================================================
# Mode: --on-spawn  (PreToolUse on the enumerated spawn surface)
# ============================================================================
_run_on_spawn() {
  local input; input=$(_read_stdin)
  [[ -z "$input" ]] && exit 0
  _have jq || { _log "jq unavailable — cannot classify spawn"; exit 0; }

  local tool; tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
  case "$tool" in
    mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task|Task|Agent) ;;
    *) exit 0 ;;  # not a covered spawn surface -> no-op
  esac

  local title; title=$(_spawn_title "$input")
  [[ -z "$title" ]] && { _log "spawn ($tool) had no extractable title — skipped"; exit 0; }

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

  # Deterministic, type-scoped event ids -> per-file idempotency on re-fire.
  local ev_root ev_child
  ev_root="cte-bo-$(printf '%s' "$root_id" | _sha1 | cut -c1-32)"
  ev_child="cte-bo-$(printf '%s' "$child_id" | _sha1 | cut -c1-32)"

  local ef; ef=$(mktemp 2>/dev/null || echo "/tmp/cte-spawn-$$.json")
  cat >"$ef" <<JSON
[
  {"event_id":"$ev_root","type":"branch-opened","node_id":"$root_id","parent_id":null,"title":$(jq -Rn --arg t "$root_title" '$t'),"actor":"dispatch"},
  {"event_id":"$ev_child","type":"branch-opened","node_id":"$child_id","parent_id":"$root_id","title":$(jq -Rn --arg t "$title" '$t'),"actor":"dispatch"}
]
JSON
  _emit_dual "$lib" "$ef"
  rm -f "$ef" 2>/dev/null || true

  # Correlation ledger: this session opened child_id (title) — Stop concludes.
  mkdir -p "$LEDGER_DIR" 2>/dev/null || true
  local ledger="$LEDGER_DIR/opened-${sid}.jsonl"
  printf '%s\t%s\t%s\n' "$child_id" "$title" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" >>"$ledger" 2>/dev/null || true
  _log "branch-opened child=$child_id title=\"$title\" root=$root_id session=$sid"
  exit 0
}

# ============================================================================
# Mode: --on-stop  (Stop hook — conclude branches this session opened)
# ============================================================================
_run_on_stop() {
  local input; input=$(_read_stdin)
  local sid; sid=$(_session_id "$input")
  local ledger="$LEDGER_DIR/opened-${sid}.jsonl"
  [[ -f "$ledger" ]] || exit 0   # session opened no branches -> silent no-op

  local lib; lib=$(_resolve_state_lib)
  local ef; ef=$(mktemp 2>/dev/null || echo "/tmp/cte-stop-$$.json")
  : >"$ef"
  printf '[' >"$ef"
  local first=1 nid rest
  while IFS=$'\t' read -r nid rest || [[ -n "$nid" ]]; do
    [[ -z "$nid" ]] && continue
    local ev_cc; ev_cc="cte-cc-$(printf '%s' "$nid" | _sha1 | cut -c1-32)"
    [[ $first -eq 1 ]] || printf ',' >>"$ef"
    printf '{"event_id":"%s","type":"concluded","node_id":"%s","actor":"dispatch"}' "$ev_cc" "$nid" >>"$ef"
    first=0
  done <"$ledger"
  printf ']' >>"$ef"

  if [[ $first -eq 0 ]]; then
    _emit_dual "$lib" "$ef"
    _log "concluded $(wc -l <"$ledger" 2>/dev/null | tr -d ' ') branch(es) for session=$sid"
  fi
  rm -f "$ef" 2>/dev/null || true
  rm -f "$ledger" 2>/dev/null || true   # idempotent: a re-fired Stop is a no-op
  exit 0
}

# ============================================================================
# Mode: --self-test
# ============================================================================
_self_test() {
  trap - ERR
  local pass=0 fail=0 tmp
  tmp=$(mktemp -d 2>/dev/null || echo "/tmp/cte-st-$$"); mkdir -p "$tmp"
  local LIB; LIB=$(CONV_TREE_STATE_LIB="${CONV_TREE_STATE_LIB:-}" _resolve_state_lib)
  if [[ ! -f "$LIB" ]]; then echo "self-test: cannot locate state library ($LIB)"; echo "self-test: FAIL"; exit 1; fi
  export CONV_TREE_STATE_LIB="$LIB"
  local SELF; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  _count() { node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var t=process.argv[3];process.stdout.write(String(st.events.filter(function(e){return e.type===t}).length))}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2" 2>/dev/null; }
  _node_state() { node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});var n=st.snapshot.nodes.filter(function(x){return x.title===process.argv[3]})[0];process.stdout.write(n?n.state:"MISSING")}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2" 2>/dev/null; }
  _has_root() { node -e 'try{var s=require(process.argv[1]);var st=s.readState({statePath:process.argv[2]});process.stdout.write(st.snapshot.nodes.some(function(x){return x.node_id===process.argv[3]&&x.parent_id===null})?"Y":"N")}catch(e){process.stdout.write("ERR")}' "$LIB" "$1" "$2" 2>/dev/null; }
  _ck() { if [[ "$2" == "$3" ]]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (got '$2' want '$3')"; fail=$((fail+1)); fi; }

  # ST1-ST4: each enumerated spawn tool emits a branch-opened titled by the spawn title
  local i=0
  for tn in mcp__ccd_session__spawn_task mcp__ccd_session_mgmt__start_code_task Task Agent; do
    i=$((i+1)); local sp="$tmp/st-$i.json"
    CONV_TREE_STATE_PATH="$sp" CLAUDE_SESSION_ID="sess-st-$i" \
      bash "$SELF" --on-spawn <<<"{\"tool_name\":\"$tn\",\"tool_input\":{\"title\":\"Hello $tn\"},\"session_id\":\"sess-st-$i\"}" >/dev/null 2>&1
    _ck "ST$i spawn($tn) -> branch-opened titled 'Hello $tn'" "$(_node_state "$sp" "Hello $tn")" "open"
  done

  # ST5: non-spawn tool -> no-op (no file written)
  local sp5="$tmp/st-5.json"
  CONV_TREE_STATE_PATH="$sp5" CLAUDE_SESSION_ID="sess-st-5" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"sess-st-5"}' >/dev/null 2>&1
  if [[ -f "$sp5" ]]; then echo "FAIL: ST5 non-spawn must be a no-op"; fail=$((fail+1)); else echo "PASS: ST5 non-spawn no-op"; pass=$((pass+1)); fi

  # ST6: --on-stop concludes the opened branch
  local sp6="$tmp/st-6.json"
  CONV_TREE_STATE_PATH="$sp6" CLAUDE_SESSION_ID="sess-st-6" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"Task","tool_input":{"title":"Branch Six"},"session_id":"sess-st-6"}' >/dev/null 2>&1
  CONV_TREE_STATE_PATH="$sp6" CLAUDE_SESSION_ID="sess-st-6" \
    bash "$SELF" --on-stop <<<'{"session_id":"sess-st-6"}' >/dev/null 2>&1
  _ck "ST6 --on-stop -> branch concluded" "$(_node_state "$sp6" "Branch Six")" "concluded"

  # ST7: idempotent re-fire of the same spawn does NOT double-write
  local sp7="$tmp/st-7.json"
  for _r in 1 2 3; do
    CONV_TREE_STATE_PATH="$sp7" CLAUDE_SESSION_ID="sess-st-7" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"Agent","tool_input":{"title":"Idem"},"session_id":"sess-st-7"}' >/dev/null 2>&1
  done
  _ck "ST7 idempotent: 3 re-fires -> exactly 1 child branch-opened (+1 root = 2)" "$(_count "$sp7" branch-opened)" "2"

  # ST8: project autodetect — cwd under claude-projects/<p>/ -> proj-<p> root
  local sp8="$tmp/st-8.json" pdir="$tmp/claude-projects/demoproj/wt"
  mkdir -p "$pdir"
  ( cd "$pdir" && CONV_TREE_STATE_PATH="$sp8" CLAUDE_SESSION_ID="sess-st-8" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"Task","tool_input":{"title":"PA"},"session_id":"sess-st-8"}' >/dev/null 2>&1 )
  _ck "ST8 autodetect project root proj-demoproj" "$(_has_root "$sp8" "proj-demoproj")" "Y"

  # ST9: no claude-projects in cwd -> global root
  local sp9="$tmp/st-9.json" gdir="$tmp/elsewhere"
  mkdir -p "$gdir"
  ( cd "$gdir" && CONV_TREE_STATE_PATH="$sp9" CLAUDE_SESSION_ID="sess-st-9" \
      bash "$SELF" --on-spawn <<<'{"tool_name":"Task","tool_input":{"title":"GA"},"session_id":"sess-st-9"}' >/dev/null 2>&1 )
  _ck "ST9 autodetect global root" "$(_has_root "$sp9" "global")" "Y"

  # ST10: failure isolation — broken state-lib path -> exit 0, log line written
  local sp10="$tmp/st-10.json" rc
  CONV_TREE_STATE_PATH="$sp10" CONV_TREE_STATE_LIB="$tmp/does-not-exist.js" CLAUDE_SESSION_ID="sess-st-10" \
    bash "$SELF" --on-spawn <<<'{"tool_name":"Task","tool_input":{"title":"Iso"},"session_id":"sess-st-10"}' >/dev/null 2>&1
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

  # ST13/ST14: worktree topology — the operator runs ONE GUI server from the
  # MAIN checkout while Dispatch/Code sessions run in worktrees. The GUI sink
  # MUST resolve to the main checkout's module file (or the GUI never updates
  # — the exact bug the CONV_TREE_STATE_PATH-overridden ST1-12 cannot catch),
  # while the gate sink stays worktree-local (gate parity). Lock both.
  if command -v git >/dev/null 2>&1; then
    local R="$tmp/mainrepo" WT="$tmp/wt"
    mkdir -p "$R/neural-lace/conversation-tree-ui/state"
    : >"$R/neural-lace/conversation-tree-ui/state/state.js"
    ( cd "$R" && git init -q . && git config user.email t@e.test && git config user.name t \
        && git add -A && git commit -qm init && git worktree add -q "$WT" -b st13wt ) >/dev/null 2>&1
    local Rabs gui_from_wt gate_from_wt want_gui
    Rabs=$(cd "$R" && pwd)
    want_gui="$Rabs/neural-lace/conversation-tree-ui/state/tree-state.json"
    gui_from_wt=$( cd "$WT" && CONV_TREE_STATE_PATH="" bash "$SELF" --resolve-gui-sink 2>/dev/null | head -n1 )
    gate_from_wt=$( cd "$WT" && CONV_TREE_STATE_PATH="" bash "$SELF" --resolve-gate-sink 2>/dev/null | head -n1 )
    _ck "ST13 GUI sink from worktree -> MAIN checkout module file" "$gui_from_wt" "$want_gui"
    # Path-format-agnostic (Windows: git emits native C:/... while $WT is MSYS
    # /tmp/...). The invariant that matters: the gate sink is the §5 path
    # (.claude/state/conversation-tree/), NOT the GUI module file
    # (conversation-tree-ui/state/), and the two differ — dual-sink divergence.
    if [[ -n "$gate_from_wt" \
          && "$gate_from_wt" == *"/.claude/state/conversation-tree/tree-state.json" \
          && "$gate_from_wt" != *"conversation-tree-ui/state/"* \
          && "$gate_from_wt" != "$gui_from_wt" ]]; then
      echo "PASS: ST14 gate sink is the §5 path & differs from the GUI sink"; pass=$((pass+1))
    else
      echo "FAIL: ST14 gate sink (got '$gate_from_wt'; want a *.claude/state/conversation-tree/ path != GUI '$gui_from_wt')"; fail=$((fail+1))
    fi
    ( cd "$R" && git worktree remove --force "$WT" ) >/dev/null 2>&1 || true
  else
    echo "PASS: ST13 (skipped: git unavailable)"; pass=$((pass+1))
    echo "PASS: ST14 (skipped: git unavailable)"; pass=$((pass+1))
  fi

  rm -rf "$tmp" 2>/dev/null || true
  echo "self-test: $pass passed, $fail failed"
  if [[ $fail -eq 0 ]]; then echo "self-test: OK"; exit 0; else echo "self-test: FAIL"; exit 1; fi
}

# ============================================================================
# Dispatch
# ============================================================================
case "$MODE" in
  --on-spawn)  _run_on_spawn ;;
  --on-stop)   _run_on_stop ;;
  --self-test) _self_test ;;
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
