#!/bin/bash
# conversation-tree-state-gate.sh — PreToolUse gate (workstreams-ui v1, Task B1)
#
# Blocks a child-session spawn unless the conversation-tree state file (a)
# exists, (b) is a valid JSON document, (c) carries an *attestation-verified*
# snapshot (DEC-D option (d) / ADR-032 §8 r2.1), (d) is fresh relative to the
# gate's own per-session spawn marker, and (e) names — in `snapshot.nodes` —
# the branch the spawn's tool_input describes (the branch identifier is taken
# INDEPENDENTLY from the spawn input per ADR-031 r7 Pin-1, never derived from
# the state file the writer controls).
#
# This is the mechanical enforcement substrate of ADR-031 r7 "Enforcement
# design" and ADR-032 §8. The branch-presence check is the strongest
# mechanical proxy for "the orchestrator wrote the *true* tree before
# spawning" — raised from "wrote anything" to "wrote a live node naming this
# branch" (ADR-031 r7 Pin-1). Semantic tree-correctness is the B3 rule-class
# layer + the operator's interrupt authority; this gate is the freshness/shape/
# branch-presence floor.
#
# SCOPE (ADR-031 r7 Pin-1, amended r8 / ADR-034 2026-05-19): this gate fires
# ONLY on the Dispatch orchestrator's spawn tools. Sub-agent Task/Agent
# invocations are OUT of scope — they are AI-internal mechanics (peer review,
# verification, internal helpers), NOT branches of the user↔AI conversation
# the tree models. A Code session's reviewer/verifier sub-agents never belong
# in the operator's conversation tree, so the gate must not fire on them.
#
# Matcher (the Dispatch-only enumerated set; B0-verified both carry the full
# tool_name string identically):
#   mcp__ccd_session__spawn_task | mcp__ccd_session_mgmt__start_code_task
#
# Snapshot trust (ADR-032 §8 r2.1 — LOAD-BEARING): the SOLE NORMATIVE
# verifier is the state-library primitive `verifySnapshotAttested`. The gate
# shells out `node -e` requiring the state module and calling that primitive;
# it MUST NOT re-implement canonicalization in shell (`jq -cS | sha256sum` is
# explicitly NON-NORMATIVE and not hash-equivalent — ADR-032 §8 r2.1). The
# library owns the ONE canonicalization used by the writer's attestSnapshot
# AND every verifier.
#
# Pin-2 error partition (ADR-031 r7 Pin-2, cell-for-cell):
#   JSON-parse-fail of the state file        -> CLOSED (BLOCK)
#   missing state file, prior spawn this sess -> CLOSED (BLOCK)
#   missing state file, NO prior spawn        -> OPEN (bootstrap exemption)
#   stale snapshot / attestation fails (torn) -> CLOSED (BLOCK) [waiver valve]
#   unknown schema MAJOR (file > known)       -> CLOSED with distinct
#                                                "schema too new — upgrade"
#   hook-internal error (own node/jq/IO,      -> OPEN (fail-open ONLY on the
#     NOT a state-file shape problem)            gate's own malfunction)
#
# Escape hatch (B1c): a fresh .claude/state/conv-tree-spawn-waiver-*.txt
# (>=1 substantive non-whitespace line, mtime < 1h) ALLOWS the spawn —
# mirrors bug-persistence-gate.sh waiver semantics exactly so a hook bug or
# legitimate edge never bricks all work.
#
# Exit codes:
#   0 — spawn may proceed (ALLOW / no-op / bootstrap / waiver / verified)
#   2 — spawn blocked; stderr explains why; JSON {decision:block} on stdout
#
# Claude Code contract: PreToolUse hooks receive JSON on stdin (tool_name,
# tool_input). We also honor CLAUDE_TOOL_INPUT for the self-test harness.

set -u

# ============================================================
# Resolvable constants / overridable knobs (tests set these)
# ============================================================
# State-file path resolution per ADR-032 §5: per-project tree at
#   <project-root>/.claude/state/conversation-tree/tree-state.json
# global tree at
#   ~/.claude/state/conversation-tree/global/tree-state.json
# CONV_TREE_STATE_PATH overrides both (explicit, used by --self-test).
# CONV_TREE_STATE_LIB overrides the state-library module path (the lib lives
# under the harness source tree, not installed into ~/.claude/).
_resolve_state_path() {
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then
    printf '%s' "$CONV_TREE_STATE_PATH"
    return 0
  fi
  # Prefer a per-project tree if a project root is discoverable.
  local root=""
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    local proj="$root/.claude/state/conversation-tree/tree-state.json"
    if [[ -f "$proj" ]]; then
      printf '%s' "$proj"
      return 0
    fi
  fi
  # Per-project path is the default target even when absent (so a missing
  # per-project file is reported as "missing", not silently bypassed).
  if [[ -n "$root" ]]; then
    printf '%s' "$root/.claude/state/conversation-tree/tree-state.json"
    return 0
  fi
  printf '%s' "$HOME/.claude/state/conversation-tree/global/tree-state.json"
}

# Resolve the state-library entry module (state.js). The library is part of
# the harness source tree (neural-lace/workstreams-ui/state/state.js),
# NOT copied into ~/.claude/. Resolution order: explicit override, then a
# search up from the state file's repo, then the well-known repo subdir.
_resolve_state_lib() {
  if [[ -n "${CONV_TREE_STATE_LIB:-}" ]]; then
    printf '%s' "$CONV_TREE_STATE_LIB"
    return 0
  fi
  local root=""
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    local cand="$root/neural-lace/workstreams-ui/state/state.js"
    if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
    cand="$root/workstreams-ui/state/state.js"
    if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
  fi
  # Fall back to a HOME-relative well-known location if the harness ever
  # vendors the lib there. (Returned even if absent; the require failure is
  # then a hook-internal error -> fail-open per Pin-2.)
  printf '%s' "$HOME/claude-projects/neural-lace/neural-lace/workstreams-ui/state/state.js"
}

WAIVER_GLOB='conv-tree-spawn-waiver-*.txt'

# ============================================================
# --self-test — exercises every Pin-2 partition cell + bootstrap +
# waiver + happy-path + branch-named-but-absent + matcher fire/no-op.
# Uses a REAL attested-snapshot fixture produced via the state library
# so the node -e verifySnapshotAttested path is genuinely exercised
# end-to-end (not stubbed).
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ ! -f "$SELF" ]]; then echo "self-test: cannot resolve own path" >&2; exit 2; fi

  # Locate the real state library for fixture generation.
  ST_ROOT=""
  if ST_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$ST_ROOT" ]]; then :; fi
  ST_LIB=""
  for c in \
    "$ST_ROOT/neural-lace/workstreams-ui/state/state.js" \
    "$ST_ROOT/workstreams-ui/state/state.js"; do
    [[ -f "$c" ]] && { ST_LIB="$c"; break; }
  done
  if [[ -z "$ST_LIB" ]]; then
    echo "self-test: cannot locate state library (state.js) for fixture generation" >&2
    exit 2
  fi

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t conv-tree-gate)
  if [[ -z "$TMP" || ! -d "$TMP" ]]; then echo "self-test: no tmpdir" >&2; exit 2; fi
  trap 'rm -rf "$TMP"' EXIT

  PASSED=0
  FAILED=0

  _mk_attested() {
    # $1 = output file, $2 = node_id, $3 = title, $4 = state(open|archived)
    node -e '
      const s=require(process.argv[1]);
      const fs=require("fs");
      const out=process.argv[2], nid=process.argv[3], title=process.argv[4], state=process.argv[5];
      const st=s.emptyState("global");
      st.events.push({event_id:"e1",type:"branch-opened",node_id:nid,parent_id:null,title:title,ts:new Date().toISOString(),actor:"dispatch"});
      const snap=s.deriveSnapshot(st.events,"global");
      if(state==="archived"){ for(const n of snap.nodes){ if(n.node_id===nid) n.state="archived"; } }
      snap.valid=true;
      const att=s.attestSnapshot(snap);
      st.snapshot=snap;
      st.events.push(att);
      fs.writeFileSync(out, JSON.stringify(st));
    ' "$ST_LIB" "$1" "$2" "$3" "$4" 2>"$TMP/mkerr" || { echo "self-test: fixture gen failed: $(cat "$TMP/mkerr")" >&2; exit 2; }
  }

  _run() {
    # $1 label  $2 expected_exit  $3 state-path(or "")  $4 tool_name
    # $5 tool_input-json  $6 session-id  $7 prior-marker?(1/0)
    # $8 waiver-text(or "")  $9 expect-stderr-substr(or "")
    local label="$1" exp="$2" sp="$3" tn="$4" ti="$5" sid="$6" prior="$7" wv="$8" needle="$9"
    local work="$TMP/$label"
    mkdir -p "$work/.claude/state"
    local marker="$work/.claude/state/conv-tree-spawn-marker-${sid}.txt"
    if [[ "$prior" == "1" ]]; then echo "prior spawn" > "$marker"; fi
    if [[ -n "$wv" ]]; then
      printf '%s\n' "$wv" > "$work/.claude/state/conv-tree-spawn-waiver-test.txt"
    fi
    local input
    input=$(printf '{"tool_name":%s,"tool_input":%s}' "\"$tn\"" "$ti")
    local out err code
    out=$(cd "$work" && CLAUDE_SESSION_ID="$sid" \
          CONV_TREE_STATE_PATH="$sp" CONV_TREE_STATE_LIB="$ST_LIB" \
          CLAUDE_STATE_DIR="$work/.claude/state" \
          CLAUDE_TOOL_INPUT="$input" bash "$SELF" 2>"$TMP/$label.err")
    code=$?
    err=$(cat "$TMP/$label.err" 2>/dev/null || echo "")
    local ok=1
    [[ "$code" -eq "$exp" ]] || ok=0
    if [[ -n "$needle" ]] && ! printf '%s' "$err" | grep -qF "$needle"; then ok=0; fi
    if [[ "$ok" -eq 1 ]]; then
      PASSED=$((PASSED+1)); echo "  PASS  $label (exit $code)"
    else
      FAILED=$((FAILED+1)); echo "  FAIL  $label (exit $code, want $exp; needle='$needle')"
      printf '        decision: %s\n' "$(printf '%s' "$err" | grep -F '[conv-tree-gate]' | tail -1)"
    fi
  }

  echo "conversation-tree-state-gate.sh --self-test"

  # Real attested fixtures
  GOOD="$TMP/good-state.json"            ; _mk_attested "$GOOD" "worker-feat-x" "Feat X" "open"
  ARCHIVED="$TMP/archived-state.json"    ; _mk_attested "$ARCHIVED" "worker-arch" "Archived node" "archived"
  TORN="$TMP/torn-state.json"            ; _mk_attested "$TORN" "worker-feat-x" "Feat X" "open"
  # Byte-tamper the snapshot so the attestation hash no longer matches.
  node -e 'const fs=require("fs");const p=process.argv[1];const o=JSON.parse(fs.readFileSync(p,"utf8"));o.snapshot.nodes[0].title="TAMPERED";fs.writeFileSync(p,JSON.stringify(o));' "$TORN"
  BADJSON="$TMP/bad.json"                ; printf '{not valid json' > "$BADJSON"
  NEWMAJOR="$TMP/newmajor.json"          ; node -e 'const fs=require("fs");const o=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));o.schema_version=999;fs.writeFileSync(process.argv[2],JSON.stringify(o));' "$GOOD" "$NEWMAJOR"
  MISSING="$TMP/does-not-exist.json"

  # Spawn tool_input variants. spawn_task uses {title,prompt,tldr}; the
  # branch identity is in the prompt sentinel (worker-<task-id>) per
  # spawn-task-report-back.md. Task/Agent put the worker branch in the
  # prompt/description.
  TI_GOOD='{"title":"Build feat x","prompt":"Report-back: task-id=feat-x\\nDo the work on branch worker-feat-x","tldr":"x"}'
  TI_TASK='{"description":"build","prompt":"git checkout -b worker-feat-x claude/base"}'
  TI_AGENT='{"subagent_type":"plan-phase-builder","prompt":"work on branch `worker-feat-x`"}'
  TI_ABSENT='{"title":"unrelated","prompt":"Report-back: task-id=nope\\nbranch worker-nope","tldr":"y"}'
  TI_ARCH='{"prompt":"branch worker-arch"}'
  TI_NONMATCH='{"file_path":"/tmp/x"}'

  # --- Matcher: fires for the 2 Dispatch tools; Task/Agent + everything
  # else no-op (ADR-031 r7 Pin-1, amended r8 / ADR-034 — sub-agent Task/
  # Agent are AI-internal mechanics, NOT conversation branches). ---
  _run "m1-spawn_task-fires"        2 "$MISSING" "mcp__ccd_session__spawn_task"        "$TI_GOOD" s-m1 1 "" "BLOCK:"
  _run "m2-start_code_task-fires"   2 "$MISSING" "mcp__ccd_session_mgmt__start_code_task" "$TI_GOOD" s-m2 1 "" "BLOCK:"
  # Task/Agent must NO-OP even with a prior-spawn marker AND a missing state
  # file (the exact friction config that used to force a waiver): exit 0, and
  # the absence of any BLOCK is asserted by the parallel regression below.
  _run "m3-Task-noop"              0 "$MISSING" "Task"                                 "$TI_TASK"  s-m3 1 "" ""
  _run "m4-Agent-noop"             0 "$MISSING" "Agent"                                "$TI_AGENT" s-m4 1 "" ""
  _run "m5-Edit-noop"              0 "$MISSING" "Edit"                                 "$TI_NONMATCH" s-m5 1 "" ""
  _run "m6-Bash-noop"             0 "$MISSING" "Bash"                                 "$TI_NONMATCH" s-m6 1 "" ""

  # --- Pin-2 error partition (cell-for-cell) — exercised via a Dispatch
  # tool (spawn_task), since Task no longer reaches the state logic. ---
  _run "p1-json-parse-fail-CLOSED" 2 "$BADJSON" "mcp__ccd_session__spawn_task" "$TI_GOOD" s-p1 0 "" "not valid JSON"
  _run "p2-missing+prior-CLOSED"   2 "$MISSING" "mcp__ccd_session__spawn_task" "$TI_GOOD" s-p2 1 "" "prior spawn occurred this session"
  _run "p3-missing+noprior-OPEN"   0 "$MISSING" "mcp__ccd_session__spawn_task" "$TI_GOOD" s-p3 0 "" ""
  _run "p4-torn-attest-CLOSED"     2 "$TORN"    "mcp__ccd_session__spawn_task" "$TI_GOOD" s-p4 0 "" "NOT integrity-verified"
  _run "p5-unknown-major-CLOSED"   2 "$NEWMAJOR" "mcp__ccd_session__spawn_task" "$TI_GOOD" s-p5 0 "" "schema too new"

  # --- Happy path: verified snapshot naming the branch -> ALLOW (both
  # Dispatch tools). h3 doubles as proof that Task no-ops even when a fully
  # valid tree exists (matcher exits before the verified-path is reached). ---
  _run "h1-verified-spawn_task-ALLOW"      0 "$GOOD" "mcp__ccd_session__spawn_task"        "$TI_GOOD" s-h1 0 "" ""
  _run "h2-verified-start_code_task-ALLOW" 0 "$GOOD" "mcp__ccd_session_mgmt__start_code_task" "$TI_GOOD" s-h2 0 "" ""
  _run "h3-Task-noop-even-with-good-state"  0 "$GOOD" "Task"                                "$TI_TASK" s-h3 0 "" ""

  # --- Branch named but not in snapshot -> BLOCK (via Dispatch tool) ---
  _run "b1-branch-absent-BLOCK"    2 "$GOOD" "mcp__ccd_session__spawn_task" "$TI_ABSENT" s-b1 0 "" "no live node"
  # --- Branch present but archived -> BLOCK (state!=archived required) ---
  _run "b2-branch-archived-BLOCK"  2 "$ARCHIVED" "mcp__ccd_session__spawn_task" "$TI_ARCH" s-b2 0 "" "no live node"

  # --- Waiver release-valve: torn state + fresh waiver -> ALLOW ---
  _run "w1-waiver-overrides-torn"  0 "$TORN" "mcp__ccd_session__spawn_task" "$TI_GOOD" s-w1 0 "fresh substantive justification line" ""
  # --- Empty/whitespace-only waiver does NOT help: torn still -> CLOSED ---
  _run "w2-empty-waiver-no-help"   2 "$TORN" "mcp__ccd_session__spawn_task" "$TI_GOOD" s-w2 0 "   " "NOT integrity-verified"

  # --- REGRESSION (ADR-034): a Code session doing 4 parallel sub-agent
  # Task dispatches must NOT be gated. Asserts exit 0 AND zero BLOCK output
  # for every one — this is the exact friction Misha identified (3-of-4
  # parallel reviewers blocked, forcing per-session waivers). ---
  par_fail=0
  for n in 1 2 3 4; do
    pin='{"description":"parallel reviewer '"$n"'","prompt":"review the diff for correctness"}'
    pout=$(cd "$TMP" && CLAUDE_SESSION_ID="s-par-$n" \
            CONV_TREE_STATE_PATH="$MISSING" CONV_TREE_STATE_LIB="$ST_LIB" \
            CLAUDE_STATE_DIR="$TMP/par-$n-state" \
            CLAUDE_TOOL_INPUT="$(printf '{"tool_name":"Task","tool_input":%s}' "$pin")" \
            bash "$SELF" 2>"$TMP/par-$n.err")
    pcode=$?
    perr=$(cat "$TMP/par-$n.err" 2>/dev/null || echo "")
    if [[ "$pcode" -ne 0 ]] || printf '%s' "$perr" | grep -qF 'BLOCK:' \
       || printf '%s' "$pout" | grep -qF '"decision": "block"'; then
      par_fail=1
      echo "        par-$n: exit=$pcode err='$(printf '%s' "$perr" | tail -1)'"
    fi
  done
  if [[ "$par_fail" -eq 0 ]]; then
    PASSED=$((PASSED+1)); echo "  PASS  r1-4x-parallel-Task-not-gated (all exit 0, zero BLOCK)"
  else
    FAILED=$((FAILED+1)); echo "  FAIL  r1-4x-parallel-Task-not-gated (a parallel Task dispatch was gated)"
  fi
  # --- REGRESSION: bare Agent with NO branch identifier (the case that
  # previously hit the 'could not extract any branch identifier' BLOCK and
  # forced a waiver) must now silently no-op. ---
  _run "r2-bare-Agent-no-identifier-noop" 0 "$MISSING" "Agent" '{"subagent_type":"code-reviewer","prompt":"review"}' s-r2 1 "" ""

  echo ""
  echo "$PASSED passed, $FAILED failed"
  [[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
fi

# ============================================================
# Runtime path
# ============================================================

# --- Input loading (stdin JSON or CLAUDE_TOOL_INPUT for tests) ---
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  if [[ ! -t 0 ]]; then INPUT=$(cat 2>/dev/null || echo ""); fi
fi
[[ -z "$INPUT" ]] && exit 0   # nothing to inspect -> no-op (cannot be a spawn)

# jq is required for shape inspection; its absence is a hook-internal
# malfunction -> fail OPEN (Pin-2: never fail-closed on our own breakage).
if ! command -v jq >/dev/null 2>&1; then
  echo "[conv-tree-gate] ALLOW (fail-open): jq unavailable — hook-internal, cannot inspect" >&2
  exit 0
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# --- B1a matcher: Dispatch-only enumerated set (ADR-031 r7 Pin-1, amended
# r8 / ADR-034). Sub-agent Task/Agent invocations are AI-internal mechanics,
# not conversation branches — they are deliberately NOT in this set and the
# gate no-ops on them. ---
case "$TOOL_NAME" in
  mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task) ;;
  *) exit 0 ;;   # not a Dispatch spawn surface (incl. Task/Agent) -> no-op
esac

STATE_DIR="${CLAUDE_STATE_DIR:-.claude/state}"
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')
[[ -z "$SESSION_ID" ]] && SESSION_ID="default"
SPAWN_MARKER="$STATE_DIR/conv-tree-spawn-marker-${SESSION_ID}.txt"

STATE_PATH=$(_resolve_state_path)
STATE_LIB=$(_resolve_state_lib)

# --- B1a: extract the spawned branch identifier INDEPENDENTLY from the
# spawn tool_input (ADR-031 r7 Pin-1 — NOT derived from the state file). The
# branch identity differs per spawn tool, but the harness conventions
# (spawn-task-report-back.md sentinel + orchestrator-pattern.md worker-branch
# instruction) place it in the prompt/description/title text. Candidates:
#   (1) `task-id=<id>` sentinel  -> <id> AND worker-<id>
#   (2) any `worker-<token>`     -> worker-<token>
#   (3) backtick-quoted branch after the word "branch"
#   (4) the title field verbatim (spawn_task {title,prompt,tldr})
# The gate ALLOWS only if the attested snapshot's snapshot.nodes contains a
# live (state!=archived) node whose node_id OR title equals ANY candidate.
# Multi-candidate is deliberately permissive on the WHERE-it-came-from while
# strict on the IT-MUST-BE-IN-THE-VERIFIED-TREE property; non-gameable
# because every candidate originates in the spawn input, never the file.
TI_TEXT=$(printf '%s' "$INPUT" | jq -r '
  [ (.tool_input.prompt // ""),
    (.tool_input.description // ""),
    (.tool_input.title // ""),
    (.tool_input.content // "") ] | join("\n")' 2>/dev/null || echo "")
TI_TITLE=$(printf '%s' "$INPUT" | jq -r '.tool_input.title // ""' 2>/dev/null || echo "")

declare -a CANDS=()
# (1) task-id sentinel
while IFS= read -r tid; do
  [[ -z "$tid" ]] && continue
  CANDS+=("$tid" "worker-$tid")
done < <(printf '%s' "$TI_TEXT" | grep -oE 'task-id=[A-Za-z0-9._/-]+' | sed 's/^task-id=//')
# (2) worker-<token>
while IFS= read -r wb; do
  [[ -z "$wb" ]] && continue
  CANDS+=("$wb")
done < <(printf '%s' "$TI_TEXT" | grep -oE 'worker-[A-Za-z0-9._/-]+')
# (3) backtick-quoted token following "branch"
while IFS= read -r bb; do
  [[ -z "$bb" ]] && continue
  CANDS+=("$bb")
done < <(printf '%s' "$TI_TEXT" | grep -oE 'branch[^`]*`[A-Za-z0-9._/-]+`' | grep -oE '`[A-Za-z0-9._/-]+`' | tr -d '`')
# (4) the title verbatim (spawn_task)
[[ -n "$TI_TITLE" ]] && CANDS+=("$TI_TITLE")

# Helper: record that a spawn was attempted/seen this session (so a later
# missing-file spawn fails CLOSED, not bootstrap-OPEN). Defined here (before
# first use) so the waiver release-valve below can call it.
_touch_marker() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)
  printf 'spawn seen at %s tool=%s\n' "$ts" "$TOOL_NAME" >> "$SPAWN_MARKER" 2>/dev/null || true
}

# --- Block helper: structured stderr + JSON {decision:block} + exit 2 ---
_block() {
  local short="$1" body="$2"
  {
    echo "================================================================"
    echo "CONVERSATION-TREE STATE GATE — SPAWN BLOCKED"
    echo "================================================================"
    echo ""
    echo "$body"
    echo ""
    echo "Spawn tool: $TOOL_NAME"
    echo "State file: $STATE_PATH"
    echo ""
    echo "Remediation (diagnose before bypass — ~/.claude/rules/gate-respect.md):"
    echo "  1. Write the true conversation-tree state (a verified snapshot"
    echo "     whose snapshot.nodes contains a live node naming this branch)"
    echo "     via the state library, THEN retry the spawn."
    echo "  2. If this is a legitimate edge or a suspected gate bug, author a"
    echo "     fresh substantive waiver (mirrors bug-persistence-gate.sh):"
    echo "       mkdir -p $STATE_DIR && \\"
    echo "       printf '%s\\n' '<one substantive line: why this spawn is OK>' \\"
    echo "         > $STATE_DIR/conv-tree-spawn-waiver-\$(date +%s).txt"
    echo "     (>=1 non-whitespace line, mtime < 1h). NEVER --no-verify."
    echo "================================================================"
  } >&2
  # The decision line on every fire (ALLOW/BLOCK + reason).
  echo "[conv-tree-gate] BLOCK: $short (tool=$TOOL_NAME)" >&2
  cat <<JSON
{"decision": "block", "reason": "conversation-tree-state-gate: $short. See stderr for the Pin-2 partition cell + remediation (write the true tree, or a fresh substantive conv-tree-spawn-waiver)."}
JSON
  exit 2
}

# --- B1c: fresh substantive waiver release-valve (mirrors
# bug-persistence-gate.sh waiver semantics: >=1 substantive non-whitespace
# line, mtime < 1h). Checked BEFORE the state checks so a hook bug or a
# legitimate edge never bricks all work. ---
_has_fresh_waiver() {
  [[ -d "$STATE_DIR" ]] || return 1
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if grep -q '[^[:space:]]' "$f" 2>/dev/null; then
      return 0
    fi
  done < <(find "$STATE_DIR" -maxdepth 1 -type f -name "$WAIVER_GLOB" -newermt '1 hour ago' 2>/dev/null)
  return 1
}
if _has_fresh_waiver; then
  echo "[conv-tree-gate] ALLOW: fresh substantive conv-tree-spawn-waiver present (release valve)" >&2
  _touch_marker
  exit 0
fi

# --- Pin-2 partition: missing state file ---
if [[ ! -f "$STATE_PATH" ]]; then
  if [[ -f "$SPAWN_MARKER" ]]; then
    # missing-file WITH a prior spawn this session -> CLOSED
    _block "state file missing but a prior spawn occurred this session (prior spawn marker present)" \
      "The conversation-tree state file does not exist, but this session has
already spawned at least once (per-session spawn marker is present). A
missing state file after a prior spawn means the tree was never written —
the spawn is BLOCKED (Pin-2: missing-file + prior-spawn -> CLOSED). This is
NOT the bootstrap case (bootstrap requires NO prior spawn this session)."
  fi
  # missing-file with NO prior spawn -> OPEN (bootstrap: a tree must start)
  echo "[conv-tree-gate] ALLOW: bootstrap exemption — no state file yet AND no prior spawn this session (a tree must be able to start)" >&2
  _touch_marker
  exit 0
fi

# --- State file present: parse it ---
RAW=$(cat "$STATE_PATH" 2>/dev/null || echo "")
if ! printf '%s' "$RAW" | jq -e . >/dev/null 2>&1; then
  # JSON-parse-fail -> CLOSED (corrupt state is exactly the dangerous case)
  _touch_marker
  _block "state file is not valid JSON (parse-fail)" \
    "The conversation-tree state file exists but is not valid JSON. A corrupt
state file is exactly the dangerous case (Pin-2: JSON-parse-fail -> CLOSED) —
a torn/garbled write must never be trusted to satisfy a spawn gate."
fi

# --- Pin-2: unknown schema MAJOR -> CLOSED with the distinct message ---
KNOWN_MAJOR=$(node -e 'try{process.stdout.write(String(require(process.argv[1]).SCHEMA_VERSION))}catch(e){process.stdout.write("")}' "$STATE_LIB" 2>/dev/null || echo "")
[[ -z "$KNOWN_MAJOR" ]] && KNOWN_MAJOR=1
FILE_MAJOR=$(printf '%s' "$RAW" | jq -r '.schema_version // empty' 2>/dev/null || echo "")
if [[ -n "$FILE_MAJOR" ]] && printf '%s' "$FILE_MAJOR" | grep -qE '^[0-9]+$'; then
  if [[ "$FILE_MAJOR" -gt "$KNOWN_MAJOR" ]]; then
    _touch_marker
    _block "schema too new — upgrade the GUI/gate (file schema_version=$FILE_MAJOR > known $KNOWN_MAJOR)" \
      "The state file declares schema_version=$FILE_MAJOR but this gate/state
library only understands major $KNOWN_MAJOR. An unknown FUTURE major is never
silently passed (Pin-2: unknown-schema-major -> CLOSED, distinct message):
upgrade the conversation-tree GUI/gate to a build that understands this
schema major before spawning."
  fi
fi

# --- ADR-032 §8 r2.1 LOAD-BEARING: snapshot trust via the SOLE NORMATIVE
# state-library primitive verifySnapshotAttested. Shell out node -e; the
# library owns the ONE canonicalization. We MUST NOT recompute the hash in
# shell. Distinguish a hook-internal error (node missing / require fails ->
# fail OPEN) from "verified === false" (torn -> fail CLOSED). ---
if ! command -v node >/dev/null 2>&1; then
  echo "[conv-tree-gate] ALLOW (fail-open): node unavailable — hook-internal malfunction, cannot run the §8 r2.1 normative verifier" >&2
  exit 0
fi

VERIFY_OUT=$(node -e '
  try {
    var s = require(process.argv[1]);
    var fs = require("fs");
    var parsed = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    var r = s.verifySnapshotAttested(parsed);
    process.stdout.write(r && r.verified ? "VERIFIED" : ("UNVERIFIED:" + ((r && r.reason) || "unknown")));
    process.exit(0);
  } catch (e) {
    process.stdout.write("LIBERR:" + (e && e.message ? e.message : "require/parse failure"));
    process.exit(0);
  }
' "$STATE_LIB" "$STATE_PATH" 2>/dev/null || echo "LIBERR:node-invocation-failed")

case "$VERIFY_OUT" in
  VERIFIED)
    : # fall through to branch-presence
    ;;
  UNVERIFIED:*)
    # snapshot torn / attestation mismatch -> CLOSED (waiver is the valve,
    # checked above; reaching here means no fresh waiver). The tree enters
    # the existing A2 §7a torn-snapshot-recovery out of band.
    _touch_marker
    _block "snapshot is NOT integrity-verified (${VERIFY_OUT#UNVERIFIED:}) — torn/tampered, §8 r2.1 attestation failed" \
      "The state-library §8 r2.1 verifier (verifySnapshotAttested — the SOLE
NORMATIVE snapshot-trust primitive) reports the snapshot is NOT trustworthy:
reason=${VERIFY_OUT#UNVERIFIED:}. A torn/tampered snapshot is never trusted
to satisfy a spawn gate (Pin-2: stale/torn -> CLOSED). The conversation-tree
enters the A2 §7a torn-snapshot-recovery; re-publish a verified snapshot,
then retry. (Fresh substantive conv-tree-spawn-waiver is the release valve.)"
    ;;
  LIBERR:*)
    # The gate's OWN malfunction (node ran but require/parse threw): the
    # state-FILE shape was already validated as JSON above, so this is a
    # hook-internal error -> fail OPEN (Pin-2: own malfunction only).
    echo "[conv-tree-gate] ALLOW (fail-open): state-library verifier malfunctioned (${VERIFY_OUT#LIBERR:}) — hook-internal, NOT a state-file shape problem" >&2
    exit 0
    ;;
  *)
    echo "[conv-tree-gate] ALLOW (fail-open): unexpected verifier output — hook-internal malfunction" >&2
    exit 0
    ;;
esac

# --- Pin-2: stale snapshot relative to the gate's own per-session spawn
# marker (ADR-031 r7: "mtime newer than the gate's own per-session spawn
# marker"). If a marker exists and the state file is OLDER than it, the
# tree was not (re)written for this spawn -> CLOSED. ---
if [[ -f "$SPAWN_MARKER" ]]; then
  if [[ "$STATE_PATH" -ot "$SPAWN_MARKER" ]]; then
    _touch_marker
    _block "state file is stale (older than this session's prior spawn marker) — the tree was not (re)written for this spawn" \
      "The state file's mtime is older than the gate's per-session spawn
marker: a prior spawn this session already advanced the marker, and the tree
has NOT been re-written since. Spawning again on a stale tree is BLOCKED
(Pin-2: stale -> CLOSED; the fresh conv-tree-spawn-waiver is the release
valve). Re-publish the conversation-tree state for this spawn, then retry."
  fi
fi

# --- B1a: verified snapshot — branch-presence is a pure key-presence read
# of snapshot.nodes (no semantic interpretation; ADR-032 §8 step 2). ALLOW
# iff some candidate matches a live node's node_id OR title. ---
if [[ "${#CANDS[@]}" -eq 0 ]]; then
  _touch_marker
  _block "could not extract any branch identifier from the spawn tool_input" \
    "The spawn's tool_input contained no recognizable branch identifier
(no task-id= sentinel, no worker-<token>, no backtick branch, no title).
ADR-031 r7 Pin-1 requires the branch to come from the spawn input
INDEPENDENTLY; with no identifier the gate cannot prove the tree names this
branch — BLOCKED. Include the worker branch in the spawn prompt (per
spawn-task-report-back.md / orchestrator-pattern.md)."
fi

MATCHED=""
for c in "${CANDS[@]}"; do
  [[ -z "$c" ]] && continue
  if printf '%s' "$RAW" | jq -e --arg b "$c" '
        .snapshot.nodes[]?
        | select(((.node_id==$b) or (.title==$b)) and (.state!="archived"))' \
        >/dev/null 2>&1; then
    MATCHED="$c"
    break
  fi
done

if [[ -z "$MATCHED" ]]; then
  _touch_marker
  _block "verified snapshot has no live node naming this spawn's branch" \
    "The snapshot is integrity-verified, but snapshot.nodes contains no live
(state!=archived) node whose node_id or title matches any branch identifier
extracted from the spawn input (candidates: ${CANDS[*]}). ADR-031 r7 Pin-1:
the orchestrator must write a state entry NAMING this branch before spawning
it — this raises the bar from 'wrote anything' to 'wrote a live node naming
THIS branch'. Write the true tree (a branch-opened for this node), then retry."
fi

# --- ALLOW: verified snapshot + fresh + names a live branch node ---
echo "[conv-tree-gate] ALLOW: verified snapshot names live branch node '$MATCHED' (tool=$TOOL_NAME)" >&2
_touch_marker
exit 0
