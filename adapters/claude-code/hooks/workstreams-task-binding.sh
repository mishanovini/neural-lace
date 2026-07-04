#!/bin/bash
# workstreams-task-binding.sh — bind the Cowork TaskCreate/TaskList task tracker
# to the durable Workstreams (ADR-032) substrate, so the orchestrator is
# structurally nudged to USE the harness-native task list, and every task it
# tracks mirrors into the cross-session event log.
#
# Plan: docs/plans/taskcreate-workstreams-binding.md
#
# THREE reinforcing mechanisms, one file (mirrors conversation-tree-emit.sh's
# multi-mode shape):
#
#   --on-stop            Mechanism 1 (Stop hook) + the BRIDGE.
#                        (a) Mirrors every Task* mutation this session into
#                            Workstreams events (writer — never blocks on this).
#                        (b) If the session made > N tool calls (default 5) but
#                            ZERO task mutations, BLOCKS (default) with an
#                            injection telling the agent to record its work in a
#                            task. Loop-safe via stop-hook-retry-guard; waiver
#                            escape hatch per gate-respect.md.
#   --on-session-start   Mechanism 2 (SessionStart hook). Surfaces this
#                        project's still-active Workstreams items ("active
#                        commitments") so the agent has visibility without
#                        transcript scrolling. The bridge populated these.
#   --on-message         Mechanism 3 (PreToolUse on the Dispatch message
#                        surface). If the outgoing message makes a commitment
#                        ("I'll ...", "next I'll ...", "going to spawn ...")
#                        with no corresponding TaskCreate in the recent
#                        transcript, WARNS (default) the agent to record it.
#   --self-test          Exercises every scenario against temp state +
#                        synthetic transcripts. Prints self-test: OK / FAIL.
#
# Tunables (env, all optional):
#   WS_TASK_MIN_TOOLCALLS   M1 threshold (default 5; block when toolCalls > N)
#   WS_TASK_STOP_MODE       block | warn | off   (M1; default WARN — see retirement note)
#   WS_TASK_MESSAGE_MODE    warn  | block | off   (M3; default warn — calibration-first)
#
# Classification: M1 is a gate (can block if WS_TASK_STOP_MODE=block is set
# explicitly; loop-safe). M2/M3/the bridge are writer/advisory. Every runtime
# path is failure-isolated: a malfunction in the binding must never wedge
# the session.
#
# ============================================================
# M1 Stop-block RETIREMENT (NL Overhaul Wave D, §D.0.5 / D.6, 2026-07-02)
# ============================================================
# The default for WS_TASK_STOP_MODE flipped block -> warn at Wave D.6. Root
# cause (§D.0.5, PROVEN): M1's block demanded "call TaskCreate (and
# TaskUpdate it to completed)" for any session with >5 tool calls and 0 task
# mutations — but complying fired a TaskCompleted event that
# task-completed-evidence-gate.sh then blocked (no plan claims an invented
# compliance task). Mutually unsatisfiable for any session whose work sits
# outside the current ACTIVE plans. Disposition: the Stop-BLOCK retires
# (this default flip is that retirement — old deployments with an explicit
# WS_TASK_STOP_MODE=block override in their environment keep blocking until
# that override is removed; this file's own default no longer forces it).
# The mutation-count SIGNAL survives as a non-blocking ledger warn (this
# hook's normal warn path below, now the default outcome). The
# SessionStart listing (M2, --on-session-start) is unaffected and keeps
# surfacing active commitments. The template wiring removal (deleting the
# Stop-hook registration entirely) lands at D.5 — this file must stay safe
# under STALE LIVE WIRING in the meantime, i.e. even if some deployed
# settings.json still invokes `--on-stop` directly, the new default no
# longer blocks unless the operator opts back in explicitly.

set -uo pipefail

# shellcheck disable=SC1091
{ source "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/waiver-purpose-clause.sh" 2>/dev/null; } || true

MODE="${1:-}"

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/workstreams-task-binding.log"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_JS="$SELF_DIR/lib/workstreams-task-bridge.js"
# shellcheck disable=SC1091
{ source "$SELF_DIR/lib/nl-paths.sh" 2>/dev/null; } || true

# ---- failure isolation -----------------------------------------------------
_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "${MODE:-?}" "$*" >>"$LOG_FILE" 2>/dev/null || true
}
# Runtime modes fail-OPEN (exit 0) on an uncaught error — a binding malfunction
# never blocks the session. --self-test overrides this trap so failures surface.
_die_safe() { _log "isolated error: $*"; exit 0; }
trap '_die_safe "uncaught (line $LINENO)"' ERR

_have() { command -v "$1" >/dev/null 2>&1; }

_read_stdin() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]] && [[ ! -t 0 ]]; then input=$(cat 2>/dev/null || echo ""); fi
  printf '%s' "$input"
}

# ---- resolvers (mirror conversation-tree-emit.sh so writer + gate agree) ----
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

_resolve_state_lib() {
  if [[ -n "${CONV_TREE_STATE_LIB:-}" ]]; then printf '%s' "$CONV_TREE_STATE_LIB"; return 0; fi
  local root=""
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    local cand="$root/neural-lace/workstreams-ui/state/state.js"
    if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
    cand="$root/workstreams-ui/state/state.js"
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

# The GUI state file the operator's single GUI server watches (resolved against
# the MAIN checkout so a worktree session writes the file the GUI reads).
_resolve_gui_state_path() {
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then printf '%s' "$CONV_TREE_STATE_PATH"; return 0; fi
  local mr
  if mr=$(_main_repo_root) && [[ -n "$mr" ]]; then
    local c="$mr/neural-lace/workstreams-ui/state/tree-state.json"
    if [[ -f "$mr/neural-lace/workstreams-ui/state/state.js" ]]; then printf '%s' "$c"; return 0; fi
    c="$mr/workstreams-ui/state/tree-state.json"
    if [[ -f "$mr/workstreams-ui/state/state.js" ]]; then printf '%s' "$c"; return 0; fi
  fi
  _fallback_conv_tree_path "state/tree-state.json"
}

# Project/global root node from a cwd (same mapping as the emit hook).
_project_root_for() {
  local cwd="${1:-${PWD:-$(pwd 2>/dev/null || echo)}}"
  # Mapping is IDENTICAL to conversation-tree-emit.sh's _project_root: only a
  # path under .../claude-projects/<p>/ maps to a per-project root; anything
  # else maps to `global`. Matching it is load-bearing — it keeps bridge items
  # and the emit hook's session branch under the SAME root node.
  local slug=""
  case "$cwd" in
    */claude-projects/*) slug="${cwd#*/claude-projects/}"; slug="${slug%%/*}" ;;
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

# ============================================================================
# Mode: --on-stop  (Mechanism 1 + bridge)
# ============================================================================
_run_on_stop() {
  local input; input=$(_read_stdin)
  local tpath sid cwd
  if _have jq && [[ -n "$input" ]]; then
    tpath=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
    sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || echo "")
    cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || echo "")
  fi
  [[ -z "$sid" ]] && sid="${CLAUDE_SESSION_ID:-unknown}"
  [[ -z "$cwd" ]] && cwd="$(pwd 2>/dev/null || echo)"
  [[ -z "$tpath" ]] && { _log "on-stop: no transcript_path — no-op"; exit 0; }

  # Default flipped block -> warn at NL Overhaul Wave D.6 (§D.0.5 retirement
  # note above). Set WS_TASK_STOP_MODE=block explicitly to restore the old
  # blocking behavior (not recommended — see the collision this fixes).
  local mode="${WS_TASK_STOP_MODE:-warn}"
  [[ "$mode" == "off" ]] && exit 0

  # Resolve sinks + project root, then run the bridge (writer: emit + count).
  local lib gui rootline root_id root_title
  lib=$(_resolve_state_lib)
  gui=$(_resolve_gui_state_path)
  rootline=$(_project_root_for "$cwd")
  root_id="${rootline%%$'\t'*}"; root_title="${rootline##*$'\t'}"

  local summary='{}'
  if _have node && [[ -f "$BRIDGE_JS" ]]; then
    summary=$(node "$BRIDGE_JS" --transcript "$tpath" --session "$sid" \
      --state-lib "$lib" --state-path "$gui" \
      --project-root "$root_id" --project-title "$root_title" --emit 2>>"$LOG_FILE" || echo '{}')
  fi
  _log "on-stop session=$sid summary=$summary"

  # Parse counts. jq if present; cheap fallback grep otherwise.
  local toolcalls mutations
  if _have jq; then
    toolcalls=$(printf '%s' "$summary" | jq -r '.toolCalls // 0' 2>/dev/null || echo 0)
    mutations=$(printf '%s' "$summary" | jq -r '.taskMutations // 0' 2>/dev/null || echo 0)
  else
    toolcalls=$(printf '%s' "$summary" | grep -oE '"toolCalls":[0-9]+' | grep -oE '[0-9]+' | head -1); toolcalls=${toolcalls:-0}
    mutations=$(printf '%s' "$summary" | grep -oE '"taskMutations":[0-9]+' | grep -oE '[0-9]+' | head -1); mutations=${mutations:-0}
  fi

  local threshold="${WS_TASK_MIN_TOOLCALLS:-5}"

  # Pass conditions: trivial session, OR at least one task mutation happened.
  if (( toolcalls <= threshold )) || (( mutations > 0 )); then
    # Clear any prior retry-guard counter for this hook+session (best-effort).
    if [[ -f "$SELF_DIR/lib/stop-hook-retry-guard.sh" ]]; then
      # shellcheck source=/dev/null
      source "$SELF_DIR/lib/stop-hook-retry-guard.sh" 2>/dev/null || true
      _have retry_guard_clear && retry_guard_clear "workstreams-task-binding" "$sid" 2>/dev/null || true
    fi
    exit 0
  fi

  # Waiver escape hatch (gate-respect.md): a fresh substantive waiver file.
  # ADR 058 D5 pin f (specs-e §E.10 item 2): >=1 substantive line alone is
  # no longer sufficient — the purpose-clause pair is required too.
  local state_dir=".claude/state"
  if compgen -G "$state_dir/workstreams-task-waiver-*.txt" >/dev/null 2>&1; then
    local w
    for w in "$state_dir"/workstreams-task-waiver-*.txt; do
      [[ -f "$w" ]] || continue
      # younger than 1h AND >=1 substantive line AND (if the lib loaded)
      # the purpose-clause pair.
      local age_min; age_min=$(( ( $(date +%s 2>/dev/null || echo 0) - $(date -r "$w" +%s 2>/dev/null || echo 0) ) / 60 ))
      if (( age_min < 60 )) && grep -qE '\S' "$w" 2>/dev/null; then
        if declare -F waiver_has_purpose_clauses >/dev/null 2>&1 && ! waiver_has_purpose_clauses "$w"; then
          _log "on-stop: waiver $w present but lacks the purpose-clause pair (pin f) — not honored"
          continue
        fi
        _log "on-stop: honoring waiver $w (age ${age_min}m)"; exit 0
      fi
    done
  fi

  # The injection text (shared by warn + block).
  local nudge="[workstreams-task-binding] This session made $toolcalls tool calls but created/updated ZERO tasks. Record what you did in the task list so it survives to the next session: call TaskCreate (and TaskUpdate it to completed). The harness mirrors your tasks into the durable Workstreams tracker automatically. To intentionally skip (rare): write a waiver naming BOTH why this gate exists and why that does not apply here (ADR 058 D5 pin f) to $state_dir/workstreams-task-waiver-\$(date +%s).txt, e.g. printf 'Purpose: this gate exists to prevent unrecorded session work\\nBecause: <your reason>\\n' > $state_dir/workstreams-task-waiver-\$(date +%s).txt, or set WS_TASK_STOP_MODE=warn."

  if [[ "$mode" == "warn" ]]; then
    printf '%s\n' "$nudge" >&2
    exit 0
  fi

  # Block mode (default) — loop-safe via the shared retry-guard.
  if [[ -f "$SELF_DIR/lib/stop-hook-retry-guard.sh" ]]; then
    # shellcheck source=/dev/null
    source "$SELF_DIR/lib/stop-hook-retry-guard.sh"
    local RG_SID; RG_SID=$(retry_guard_session_id "$input")
    retry_guard_block_or_exit \
      "workstreams-task-binding" \
      "$RG_SID" \
      "ws-task-no-mutation:$toolcalls" \
      "$nudge" \
      "$(printf '{"decision":"block","reason":%s}' "$(printf '%s' "$nudge" | (jq -Rs . 2>/dev/null || printf '"%s"' "$nudge"))")" \
      2
    exit 0
  fi

  # No retry-guard available — block once, plainly.
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$nudge" | (jq -Rs . 2>/dev/null || printf '"%s"' "$nudge"))"
  printf '%s\n' "$nudge" >&2
  exit 2
}

# ============================================================================
# Mode: --on-session-start  (Mechanism 2 — surface active commitments)
# ============================================================================
_run_on_session_start() {
  local input; input=$(_read_stdin)
  local cwd=""
  if _have jq && [[ -n "$input" ]]; then
    cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || echo "")
  fi
  [[ -z "$cwd" ]] && cwd="$(pwd 2>/dev/null || echo)"

  _have node || exit 0
  local lib gui rootline root_id
  lib=$(_resolve_state_lib)
  gui=$(_resolve_gui_state_path)
  [[ -f "$gui" ]] || exit 0
  rootline=$(_project_root_for "$cwd")
  root_id="${rootline%%$'\t'*}"

  # Find active items under this project's subtree (kind=action && !checked &&
  # !deferred). The node helper walks parent_id to scope to the root subtree.
  local listing
  listing=$(node -e '
    var s = require(process.argv[1]);
    var st;
    try { st = s.readState({ statePath: process.argv[2] }); } catch (e) { process.exit(0); }
    var root = process.argv[3];
    var nodes = (st.snapshot && st.snapshot.nodes) || [];
    // Build child->parent map, then the descendant set of root (incl. root).
    var parentOf = {};
    nodes.forEach(function (n) { parentOf[n.node_id] = (n.parent_id == null ? null : n.parent_id); });
    function inSubtree(id) {
      var seen = {}; var cur = id;
      while (cur != null && !seen[cur]) { if (cur === root) return true; seen[cur] = 1; cur = parentOf[cur]; }
      return root === "global"; // global root: everything qualifies
    }
    var active = [];
    nodes.forEach(function (n) {
      if (!inSubtree(n.node_id)) return;
      (n.items || []).forEach(function (it) {
        if (it.kind === "action" && !it.checked && !it.deferred) {
          active.push(String(it.text || "").slice(0, 80));
        }
      });
    });
    if (!active.length) process.exit(0);
    process.stdout.write(String(active.length) + "\n");
    active.slice(0, 10).forEach(function (t) { process.stdout.write("  • " + t + "\n"); });
  ' "$lib" "$gui" "$root_id" 2>/dev/null || echo "")

  [[ -z "$listing" ]] && exit 0
  local count; count=$(printf '%s' "$listing" | head -1)
  local body; body=$(printf '%s' "$listing" | tail -n +2)
  echo "[workstreams-task-binding] $count active commitment(s) tracked for this project (from the durable Workstreams tracker):"
  echo ""
  printf '%s\n' "$body"
  echo ""
  echo "These are open task-list items mirrored from prior sessions. Pick them up,"
  echo "or mark them done with TaskUpdate (status: completed) if already shipped."
  exit 0
}

# ============================================================================
# Mode: --on-message  (Mechanism 3 — commitment-without-task gate; warn default)
# ============================================================================
# Commitment-pattern regex (case-insensitive). Kept deliberately specific to
# first-person FUTURE commitments; questions/observations don't match.
_WS_COMMIT_RE="(\bi('|’)?ll\b|\bi will\b|\bnext,? i('|’)?ll\b|\bnext,? i \b|going to (spawn|build|create|run|fix|implement|add|wire|write|set up|land|ship)|\bwant me to\b|\bi('|’)?m going to\b|\bi plan to\b|\bi'?ll go ahead\b)"

_run_on_message() {
  local input; input=$(_read_stdin)
  _have jq || exit 0
  [[ -z "$input" ]] && exit 0

  local mode="${WS_TASK_MESSAGE_MODE:-warn}"
  [[ "$mode" == "off" ]] && exit 0

  local msg
  msg=$(printf '%s' "$input" | jq -r '
    (.tool_input.message // .tool_input.content // .tool_input.text // .tool_input.body // "")' 2>/dev/null || echo "")
  [[ -z "$msg" ]] && exit 0

  # Commitment present?
  printf '%s' "$msg" | grep -qiE "$_WS_COMMIT_RE" || exit 0

  # Is there a TaskCreate in the recent transcript? (recorded the commitment)
  local tpath
  tpath=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
  if [[ -n "$tpath" && -f "$tpath" ]]; then
    # Tail to "recent" — last 60 transcript lines is plenty for "did I just track it".
    if tail -n 60 "$tpath" 2>/dev/null | grep -qE '"name"[[:space:]]*:[[:space:]]*"TaskCreate"'; then
      exit 0   # commitment is recorded — pass
    fi
  fi

  local nudge="[workstreams-task-binding] You're about to commit to something (\"I'll …\"/\"going to …\") but no TaskCreate appears in the recent transcript. Record the commitment first: TaskCreate it so it's tracked and survives the session. (Set WS_TASK_MESSAGE_MODE=off to silence.)"

  if [[ "$mode" == "block" ]]; then
    printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$nudge" | (jq -Rs . 2>/dev/null || printf '"%s"' "$nudge"))"
    printf '%s\n' "$nudge" >&2
    exit 2
  fi
  # warn (default)
  printf '%s\n' "$nudge" >&2
  exit 0
}

# ============================================================================
# Mode: --self-test
# ============================================================================
_run_self_test() {
  trap - ERR
  local fails=0
  local tmp; tmp=$(mktemp -d 2>/dev/null || echo "/tmp/wstb-$$")
  mkdir -p "$tmp"
  # Sandbox the shared retry-guard: scenarios reuse fixed synthetic session ids
  # (ST-notask etc.), so counters written to the REAL cwd-relative state dir
  # accumulate across suite runs until the guard silently DOWNGRADES the very
  # blocks the scenarios assert (observed 2026-07-03: M1 green all morning,
  # red after the day's repeated doctor sweeps crossed the threshold).
  export RETRY_GUARD_STATE_DIR="$tmp/rg-state"
  mkdir -p "$tmp/rg-state"
  local lib; lib=$(_resolve_state_lib)
  if [[ ! -f "$lib" ]]; then echo "self-test: FAIL (state lib not found at $lib)"; exit 1; fi

  _ck() { # name, condition(0=pass)
    if [[ "$2" -eq 0 ]]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi
  }

  # --- synthetic transcripts ---
  local t_create="$tmp/create.jsonl"
  cat > "$t_create" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"a1","name":"TaskCreate","input":{"subject":"demo task","description":"d"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"a1","content":"Task #1 created successfully: demo task"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"a2","name":"Bash","input":{"command":"ls"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"a3","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
  # Six non-task tool calls, no task mutation.
  local t_notask="$tmp/notask.jsonl"; : > "$t_notask"
  local i
  for i in 1 2 3 4 5 6; do
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"n%s","name":"Bash","input":{"command":"echo %s"}}]}}\n' "$i" "$i" >> "$t_notask"
  done
  # Trivial: one tool call.
  local t_trivial="$tmp/trivial.jsonl"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"z1","name":"Read","input":{"file_path":"x"}}]}}\n' > "$t_trivial"

  echo "self-test: workstreams-task-binding"

  # --- Bridge counts (scenario via bridge directly) ---
  local s
  s=$(node "$BRIDGE_JS" --transcript "$t_create" --session "S1" 2>/dev/null)
  printf '%s' "$s" | grep -q '"taskMutations":2' ; _ck "bridge counts 2 mutations (create+complete)" $?
  printf '%s' "$s" | grep -q '"toolCalls":3' ; _ck "bridge counts 3 tool calls" $?

  # --- Bridge emit + mapping + idempotency ---
  local st="$tmp/state.json"
  node "$BRIDGE_JS" --transcript "$t_create" --session "S1" --state-lib "$lib" --state-path "$st" --project-root "proj-demo" --project-title "demo" --emit >/dev/null 2>&1
  local types
  types=$(node -e 'var s=require(process.argv[1]).readState({statePath:process.argv[2]});process.stdout.write(s.events.map(function(e){return e.type}).join(","))' "$lib" "$st" 2>/dev/null)
  printf '%s' "$types" | grep -q 'action-added' ; _ck "bridge emits action-added (TaskCreate)" $?
  printf '%s' "$types" | grep -q 'action-done' ; _ck "bridge emits action-done (completed)" $?
  local n1; n1=$(node -e 'var s=require(process.argv[1]).readState({statePath:process.argv[2]});process.stdout.write(String(s.events.length))' "$lib" "$st" 2>/dev/null)
  node "$BRIDGE_JS" --transcript "$t_create" --session "S1" --state-lib "$lib" --state-path "$st" --project-root "proj-demo" --project-title "demo" --emit >/dev/null 2>&1
  local n2; n2=$(node -e 'var s=require(process.argv[1]).readState({statePath:process.argv[2]});process.stdout.write(String(s.events.length))' "$lib" "$st" 2>/dev/null)
  [[ "$n1" == "$n2" ]] ; _ck "bridge is idempotent on re-run ($n1==$n2)" $?

  # in_progress -> session-bound ; deleted -> item-backlogged
  local t_ip="$tmp/ip.jsonl"
  cat > "$t_ip" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"b1","name":"TaskCreate","input":{"subject":"x"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","content":"Task #1 created successfully: x"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"b2","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"b3","name":"TaskUpdate","input":{"taskId":"1","status":"deleted"}}]}}
EOF
  local st2="$tmp/state2.json"
  node "$BRIDGE_JS" --transcript "$t_ip" --session "S2" --state-lib "$lib" --state-path "$st2" --project-root "proj-demo" --project-title "demo" --emit >/dev/null 2>&1
  local types2; types2=$(node -e 'var s=require(process.argv[1]).readState({statePath:process.argv[2]});process.stdout.write(s.events.map(function(e){return e.type}).join(","))' "$lib" "$st2" 2>/dev/null)
  printf '%s' "$types2" | grep -q 'session-bound' ; _ck "in_progress -> session-bound" $?
  printf '%s' "$types2" | grep -q 'item-backlogged' ; _ck "deleted -> item-backlogged" $?

  # --- M1 on-stop: block when >threshold tool calls + zero mutations ---
  local out rc
  out=$(printf '{"transcript_path":"%s","session_id":"ST-notask","cwd":"%s"}' "$t_notask" "$tmp" \
    | CONV_TREE_STATE_PATH="$tmp/m1.json" WS_TASK_STOP_MODE=block bash "${BASH_SOURCE[0]}" --on-stop 2>/dev/null); rc=$?
  { [[ $rc -eq 2 ]] || printf '%s' "$out" | grep -q '"decision":"block"'; } ; _ck "M1 blocks: 6 tool calls, zero tasks (rc=$rc)" $?

  # --- M1 on-stop: pass when a task mutation happened ---
  out=$(printf '{"transcript_path":"%s","session_id":"ST-create","cwd":"%s"}' "$t_create" "$tmp" \
    | CONV_TREE_STATE_PATH="$tmp/m1b.json" WS_TASK_STOP_MODE=block bash "${BASH_SOURCE[0]}" --on-stop 2>/dev/null); rc=$?
  [[ $rc -eq 0 ]] ; _ck "M1 passes: task created (rc=$rc)" $?

  # --- M1 on-stop: pass on trivial session (<=threshold) ---
  out=$(printf '{"transcript_path":"%s","session_id":"ST-triv","cwd":"%s"}' "$t_trivial" "$tmp" \
    | CONV_TREE_STATE_PATH="$tmp/m1c.json" WS_TASK_STOP_MODE=block bash "${BASH_SOURCE[0]}" --on-stop 2>/dev/null); rc=$?
  [[ $rc -eq 0 ]] ; _ck "M1 passes: trivial 1-tool session (rc=$rc)" $?

  # --- M1 waiver escape hatch (ADR 058 D5 pin f, specs-e §E.10 item 2):
  # a fresh waiver WITH the purpose-clause pair clears the block; a fresh
  # waiver WITHOUT it does NOT (existence+freshness alone is not enough).
  # Uses SELF_DIR (already-resolved absolute path) rather than the bare
  # ${BASH_SOURCE[0]} since these scenarios `cd` into a fixture dir first.
  local m1w_dir="$tmp/m1w"; mkdir -p "$m1w_dir/.claude/state"
  {
    printf 'Purpose: this gate exists to prevent unrecorded session work\n'
    printf 'Because: this self-test scenario intentionally exercises the waiver valve\n'
  } > "$m1w_dir/.claude/state/workstreams-task-waiver-1.txt"
  rc=$(cd "$m1w_dir" && printf '{"transcript_path":"%s","session_id":"ST-waiver","cwd":"%s"}' "$t_notask" "$m1w_dir" \
    | CONV_TREE_STATE_PATH="$tmp/m1w.json" WS_TASK_STOP_MODE=block RETRY_GUARD_STATE_DIR="$tmp/rg-state-m1w" \
      bash "$SELF_DIR/$(basename "${BASH_SOURCE[0]}")" --on-stop >/dev/null 2>/dev/null; echo $?)
  [[ "$rc" == "0" ]] ; _ck "M1 waiver with purpose clauses clears block (rc=$rc)" $?

  local m1ww_dir="$tmp/m1ww"; mkdir -p "$m1ww_dir/.claude/state"
  printf 'just skip this one\n' > "$m1ww_dir/.claude/state/workstreams-task-waiver-1.txt"
  rc=$(cd "$m1ww_dir" && printf '{"transcript_path":"%s","session_id":"ST-waiver-weak","cwd":"%s"}' "$t_notask" "$m1ww_dir" \
    | CONV_TREE_STATE_PATH="$tmp/m1ww.json" WS_TASK_STOP_MODE=block RETRY_GUARD_STATE_DIR="$tmp/rg-state-m1ww" \
      bash "$SELF_DIR/$(basename "${BASH_SOURCE[0]}")" --on-stop >/dev/null 2>/dev/null; echo $?)
  [[ "$rc" == "2" ]] ; _ck "M1 weak waiver (no purpose clauses) still blocks (rc=$rc)" $?

  # --- M1 warn mode never blocks ---
  out=$(printf '{"transcript_path":"%s","session_id":"ST-warn","cwd":"%s"}' "$t_notask" "$tmp" \
    | CONV_TREE_STATE_PATH="$tmp/m1d.json" WS_TASK_STOP_MODE=warn bash "${BASH_SOURCE[0]}" --on-stop 2>/dev/null); rc=$?
  [[ $rc -eq 0 ]] ; _ck "M1 warn-mode never blocks (rc=$rc)" $?

  # --- M1 DEFAULT (§D.0.5/D.6 retirement): no WS_TASK_STOP_MODE set at all
  # -> must NOT block (default flipped block -> warn at Wave D.6). This is
  # the scenario that would have failed pre-fix: 6 tool calls + zero task
  # mutations, no explicit mode override. ---
  out=$(printf '{"transcript_path":"%s","session_id":"ST-default","cwd":"%s"}' "$t_notask" "$tmp" \
    | CONV_TREE_STATE_PATH="$tmp/m1e.json" bash "${BASH_SOURCE[0]}" --on-stop 2>/dev/null); rc=$?
  [[ $rc -eq 0 ]] ; _ck "M1 default (no env override) no longer blocks — warn is the new default (rc=$rc)" $?

  # --- M2 on-session-start surfaces active items ---
  # Reuse the state from the create scenario (has an unchecked... actually
  # completed). Build a state with an OPEN action item.
  local st3="$tmp/state3.json"
  node -e '
    var s=require(process.argv[1]); var sp=process.argv[2];
    s.appendEvent({type:"branch-opened",node_id:"proj-demo",parent_id:null,title:"demo",actor:"dispatch"},{statePath:sp});
    s.appendEvent({type:"branch-opened",node_id:"ss-x",parent_id:"proj-demo",title:"sess",actor:"dispatch"},{statePath:sp});
    s.appendEvent({type:"action-added",node_id:"ss-x",item_id:"i1",text:"open commitment alpha",actor:"dispatch"},{statePath:sp});
  ' "$lib" "$st3" >/dev/null 2>&1
  out=$(printf '{"cwd":"%s"}' "$tmp/claude-projects/demo" \
    | CONV_TREE_STATE_PATH="$st3" bash "${BASH_SOURCE[0]}" --on-session-start 2>/dev/null); rc=$?
  printf '%s' "$out" | grep -q 'open commitment alpha' ; _ck "M2 surfaces active commitment" $?

  # --- M2 silent when no items ---
  local st4="$tmp/state4.json"
  node -e 's=require(process.argv[1]);s.appendEvent({type:"branch-opened",node_id:"proj-demo",parent_id:null,title:"d",actor:"dispatch"},{statePath:process.argv[2]})' "$lib" "$st4" >/dev/null 2>&1
  out=$(printf '{"cwd":"%s"}' "$tmp/claude-projects/demo" | CONV_TREE_STATE_PATH="$st4" bash "${BASH_SOURCE[0]}" --on-session-start 2>/dev/null)
  [[ -z "$out" ]] ; _ck "M2 silent when no active items" $?

  # --- M3 message gate: commitment + TaskCreate present -> pass ---
  out=$(printf '{"tool_input":{"message":"I'"'"'ll spawn the builder next."},"transcript_path":"%s"}' "$t_create" \
    | WS_TASK_MESSAGE_MODE=warn bash "${BASH_SOURCE[0]}" --on-message 2>/dev/null); rc=$?
  [[ $rc -eq 0 && -z "$out" ]] ; _ck "M3 passes: commitment with TaskCreate in transcript" $?

  # --- M3: commitment + NO TaskCreate -> warn (stderr, rc 0) ---
  local err
  err=$(printf '{"tool_input":{"message":"I'"'"'ll go ahead and fix the bug."},"transcript_path":"%s"}' "$t_notask" \
    | WS_TASK_MESSAGE_MODE=warn bash "${BASH_SOURCE[0]}" --on-message 2>&1 >/dev/null); rc=$?
  { [[ $rc -eq 0 ]] && printf '%s' "$err" | grep -q 'commit to something'; } ; _ck "M3 warns: commitment, no TaskCreate (rc=$rc)" $?

  # --- M3: non-commitment message -> pass, no check ---
  out=$(printf '{"tool_input":{"message":"Here is the status summary of the build."},"transcript_path":"%s"}' "$t_notask" \
    | WS_TASK_MESSAGE_MODE=warn bash "${BASH_SOURCE[0]}" --on-message 2>&1); rc=$?
  [[ $rc -eq 0 && -z "$out" ]] ; _ck "M3 passes: non-commitment message" $?

  # --- M3: block mode on commitment-without-task -> rc 2 ---
  out=$(printf '{"tool_input":{"message":"I will create the file now."},"transcript_path":"%s"}' "$t_notask" \
    | WS_TASK_MESSAGE_MODE=block bash "${BASH_SOURCE[0]}" --on-message 2>/dev/null); rc=$?
  [[ $rc -eq 2 ]] ; _ck "M3 block-mode blocks commitment-without-task (rc=$rc)" $?

  rm -rf "$tmp" 2>/dev/null || true
  echo ""
  if [[ $fails -eq 0 ]]; then echo "self-test: OK"; exit 0; else echo "self-test: FAIL ($fails failing)"; exit 1; fi
}

# ---- dispatch --------------------------------------------------------------
case "$MODE" in
  --on-stop)           _run_on_stop ;;
  --on-session-start)  _run_on_session_start ;;
  --on-message)        _run_on_message ;;
  --self-test)         _run_self_test ;;
  *) echo "usage: $0 --on-stop|--on-session-start|--on-message|--self-test" >&2; exit 0 ;;
esac
