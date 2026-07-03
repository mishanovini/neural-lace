#!/bin/bash
# conversation-tree-stop-gate.sh — Stop hook (workstreams-ui v1, Task B2)
#
# The SECOND enforcement leg of ADR-031 r7 "Enforcement design". B1's
# PreToolUse gate (conversation-tree-state-gate.sh) blocks an *individual*
# spawn that lacks a true-tree write; this Stop gate closes the loop at
# session boundary: it scans the agent-uneditable session transcript and
# BLOCKS session end if a spawn/dispatch occurred THIS session without a
# corresponding *verified* conversation-tree state-file write naming the
# spawned branch(es). Mechanically forces:
#   "spawned in transcript  =>  must have written the true tree before Stop".
#
# Mirrors bug-persistence-gate.sh EXACTLY for the cross-cutting Stop-hook
# machinery so a future maintainer reads one pattern, not two:
#   - $TRANSCRIPT_PATH JSONL scan (agent cannot edit the transcript)
#   - Stop-hook decision/exit shape: exit 2 + {"decision":"block",...} stdout
#   - fresh-substantive-waiver escape hatch (>=1 non-whitespace line, mtime<1h)
#   - the shared lib/stop-hook-retry-guard.sh integration (block_or_exit)
#
# Snapshot trust (ADR-032 §8 r2.1 — LOAD-BEARING, SOLE NORMATIVE): the only
# sanctioned snapshot-trust verifier is the state-library primitive
# `verifySnapshotAttested`. This gate shells `node -e` requiring the state
# module and calling that primitive on the on-disk file. It MUST NOT
# re-implement canonicalization in shell (`jq -cS | sha256sum` is explicitly
# NON-NORMATIVE and not hash-equivalent — ADR-032 §8 r2.1). The state-file
# path resolution and the node -e invocation shape are kept byte-consistent
# with B1's conversation-tree-state-gate.sh (same trust primitive; do not
# diverge).
#
# SCOPE (ADR-031 r7 Pin-1, amended r8 / ADR-034 2026-05-19): this gate
# detects ONLY the Dispatch orchestrator's spawn tools in the transcript.
# Sub-agent Task/Agent invocations are AI-internal mechanics (peer review,
# verification, internal helpers) — NOT branches of the user↔AI conversation
# the tree models — so a session whose only spawns were Task/Agent does NOT
# trip this Stop gate.
#
# Spawn enumeration (the Dispatch-only set; B0-verified literal tool_name
# values, same set as B1's PreToolUse gate):
#   mcp__ccd_session__spawn_task | mcp__ccd_session_mgmt__start_code_task
#
# Decision matrix:
#   no matched spawn this session              -> ALLOW (silent)
#   spawn(s) + state verified + names branch(es)-> ALLOW
#   spawn(s) + (no state | unverified | branch  -> BLOCK (waiver = release valve)
#     not in verified snapshot.nodes)
#   fresh substantive conv-tree-stop-waiver-*   -> ALLOW (release valve)
#   gate-internal malfunction (own node/jq/IO,  -> ALLOW (fail-open ONLY on
#     missing $TRANSCRIPT_PATH)                    the gate's own breakage)
# A torn / missing state file WITH a real spawn is NOT a gate malfunction —
# it BLOCKs (consistent with B1's Pin-2 fail-closed-on-state-shape discipline).
#
# Escape hatch: a fresh .claude/state/conv-tree-stop-waiver-*.txt (>=1
# substantive non-whitespace line, mtime < 1h) ALLOWs session end — mirrors
# bug-persistence-gate.sh waiver semantics EXACTLY so a hook bug or a
# legitimate edge never bricks all work.
#
# Exit codes:
#   0 — session may terminate (ALLOW / silent / verified / waiver / fail-open)
#   2 — session is blocked; stderr explains why; {"decision":"block"} on stdout
#
# Claude Code contract: Stop hooks receive JSON on stdin; we read
# transcript_path from it. If the transcript is unavailable we no-op (cannot
# verify; do not block — that is a gate-internal limitation, not a state
# violation).

set -u

# shellcheck disable=SC1091
{ source "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/nl-paths.sh" 2>/dev/null; } || true

# ============================================================
# State-file + state-library path resolution — kept byte-consistent with
# conversation-tree-state-gate.sh (B1) per ADR-032 §5. Same trust primitive;
# do not diverge.
# ============================================================
_resolve_state_path() {
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then
    printf '%s' "$CONV_TREE_STATE_PATH"
    return 0
  fi
  local root=""
  if root=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
    local proj="$root/.claude/state/conversation-tree/tree-state.json"
    if [[ -f "$proj" ]]; then
      printf '%s' "$proj"
      return 0
    fi
  fi
  if [[ -n "$root" ]]; then
    printf '%s' "$root/.claude/state/conversation-tree/tree-state.json"
    return 0
  fi
  printf '%s' "$HOME/.claude/state/conversation-tree/global/tree-state.json"
}

_resolve_state_lib() {
  if [[ -n "${CONV_TREE_STATE_LIB:-}" ]]; then
    printf '%s' "$CONV_TREE_STATE_LIB"
    return 0
  fi
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
  if command -v nl_workstreams_ui >/dev/null 2>&1; then
    local _ui; _ui="$(nl_workstreams_ui 2>/dev/null)"
    [[ -n "$_ui" ]] && { printf '%s' "$_ui/state/state.js"; return 0; }
  fi
  printf '%s' "$HOME/.claude/state/state.js"
}

WAIVER_GLOB='conv-tree-stop-waiver-*.txt'

# ============================================================
# --self-test — exercises: spawn-without-verified-write -> BLOCK;
# spawn-with-verified-write-naming-the-branch -> ALLOW; no-spawn -> ALLOW
# (silent); fresh-substantive-waiver -> ALLOW; whitespace-only-waiver ->
# still BLOCK; stale(>1h)-waiver -> still BLOCK; transcript-missing
# (gate-internal) -> fail-open ALLOW.
#
# Uses a REAL state-library-produced attested fixture + a synthetic JSONL
# transcript so the transcript-scan AND the node -e verifySnapshotAttested
# path are genuinely exercised end-to-end (not stubbed).
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ ! -f "$SELF" ]]; then echo "self-test: cannot resolve own path" >&2; exit 2; fi

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

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t conv-tree-stop-gate)
  if [[ -z "$TMP" || ! -d "$TMP" ]]; then echo "self-test: no tmpdir" >&2; exit 2; fi
  trap 'rm -rf "$TMP"' EXIT

  PASSED=0
  FAILED=0

  # Build a REAL attested snapshot fixture via the state library — exactly
  # B1's _mk_attested shape so the node -e verifySnapshotAttested path the
  # runtime uses is exercised end-to-end here.
  _mk_attested() {
    # $1=out  $2=node_id  $3=title  $4=state(open|archived)
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

  # Synthesize a minimal JSONL transcript. $1=out  $2=spawn?(1/0)
  # When spawn=1 the transcript contains a real tool-call line whose
  # tool_name is one of the enumerated spawn surfaces and whose prompt
  # names branch worker-feat-x (so the verified-fixture happy path matches).
  # $2: 1 = a Dispatch spawn (trips the gate); 0 = no spawn; "taskonly" =
  # ONLY sub-agent Task/Agent tool_use lines (must NOT trip the gate — they
  # are AI-internal mechanics, ADR-031 r7 Pin-1 amended r8 / ADR-034).
  _mk_transcript() {
    local out="$1" spawn="$2"
    if [[ "$spawn" == "1" ]]; then
      cat > "$out" <<'JSONL'
{"role":"user","content":"please build feat x"}
{"role":"assistant","content":[{"type":"tool_use","name":"mcp__ccd_session__spawn_task","input":{"title":"Build feat x","prompt":"do work on branch worker-feat-x"}}]}
JSONL
    elif [[ "$spawn" == "taskonly" ]]; then
      cat > "$out" <<'JSONL'
{"role":"user","content":"build the feature and review it"}
{"role":"assistant","content":[{"type":"tool_use","name":"Task","input":{"subagent_type":"code-reviewer","prompt":"review the diff for correctness"}}]}
{"role":"assistant","content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"task-verifier","prompt":"verify task 3 on branch worker-x"}}]}
{"role":"assistant","content":[{"type":"tool_use","name":"Task","input":{"subagent_type":"ux-designer","prompt":"review the UI plan"}}]}
JSONL
    else
      cat > "$out" <<'JSONL'
{"role":"user","content":"just a question, no spawn"}
{"role":"assistant","content":[{"type":"text","text":"Here is the answer; no dispatch performed."}]}
JSONL
    fi
  }

  # $1 label  $2 expected_exit  $3 state-path(or "")  $4 transcript-path
  # $5 waiver-text(or "")  $6 waiver-age(fresh|stale|"")  $7 stderr-needle(or "")
  _run() {
    local label="$1" exp="$2" sp="$3" tp="$4" wv="$5" wage="$6" needle="$7"
    local work="$TMP/$label"
    mkdir -p "$work/.claude/state"
    if [[ -n "$wv" ]]; then
      local wf="$work/.claude/state/conv-tree-stop-waiver-test.txt"
      printf '%s\n' "$wv" > "$wf"
      if [[ "$wage" == "stale" ]]; then
        touch -d '2 hours ago' "$wf" 2>/dev/null || touch -t "$(date -d '2 hours ago' +%Y%m%d%H%M 2>/dev/null || echo 197001010000)" "$wf" 2>/dev/null || true
      fi
    fi
    local input
    input=$(printf '{"transcript_path":"%s","session_id":"%s"}' "$tp" "$label")
    local out code err
    out=$(cd "$work" && printf '%s' "$input" | CLAUDE_SESSION_ID="$label" \
          CONV_TREE_STATE_PATH="$sp" CONV_TREE_STATE_LIB="$ST_LIB" \
          CLAUDE_STATE_DIR="$work/.claude/state" \
          RETRY_GUARD_STATE_DIR="$work/.claude/state" \
          bash "$SELF" 2>"$TMP/$label.err")
    code=$?
    err=$(cat "$TMP/$label.err" 2>/dev/null || echo "")
    local ok=1
    [[ "$code" -eq "$exp" ]] || ok=0
    if [[ -n "$needle" ]] && ! printf '%s' "$err" | grep -qF "$needle"; then ok=0; fi
    if [[ "$ok" -eq 1 ]]; then
      PASSED=$((PASSED+1)); echo "  PASS  $label (exit $code)"
    else
      FAILED=$((FAILED+1)); echo "  FAIL  $label (exit $code, want $exp; needle='$needle')"
      printf '        decision: %s\n' "$(printf '%s' "$err" | grep -F '[conv-tree-stop-gate]' | tail -1)"
    fi
  }

  echo "conversation-tree-stop-gate.sh --self-test"

  GOOD="$TMP/good-state.json"   ; _mk_attested "$GOOD" "worker-feat-x" "Feat X" "open"
  TORN="$TMP/torn-state.json"   ; _mk_attested "$TORN" "worker-feat-x" "Feat X" "open"
  node -e 'const fs=require("fs");const p=process.argv[1];const o=JSON.parse(fs.readFileSync(p,"utf8"));o.snapshot.nodes[0].title="TAMPERED";fs.writeFileSync(p,JSON.stringify(o));' "$TORN"
  MISSING="$TMP/does-not-exist.json"

  TR_SPAWN="$TMP/tr-spawn.jsonl"       ; _mk_transcript "$TR_SPAWN" 1
  TR_NOSPAWN="$TMP/tr-nospawn.jsonl"   ; _mk_transcript "$TR_NOSPAWN" 0
  TR_TASKONLY="$TMP/tr-taskonly.jsonl" ; _mk_transcript "$TR_TASKONLY" taskonly
  TR_MISSING="$TMP/tr-missing.jsonl"   # deliberately not created

  # 1. spawn this session, NO state file -> BLOCK
  _run "s1-spawn-no-state-BLOCK"        2 "$MISSING"  "$TR_SPAWN"   ""  ""      "conversation-tree state"
  # 2. spawn this session, verified state naming the branch -> ALLOW
  _run "s2-spawn-verified-named-ALLOW"  0 "$GOOD"     "$TR_SPAWN"   ""  ""      ""
  # 3. spawn this session, torn (unverified) state -> BLOCK
  _run "s3-spawn-torn-state-BLOCK"      2 "$TORN"     "$TR_SPAWN"   ""  ""      "NOT integrity-verified"
  # 4. NO spawn this session -> ALLOW (silent)
  _run "s4-no-spawn-ALLOW-silent"       0 "$MISSING"  "$TR_NOSPAWN" ""  ""      ""
  # 5. spawn + no state BUT fresh substantive waiver -> ALLOW
  _run "s5-fresh-waiver-ALLOW"          0 "$MISSING"  "$TR_SPAWN"   "legitimate edge: spawn dispatched a read-only research agent that touches no tree" fresh ""
  # 6. spawn + no state + whitespace-only waiver -> still BLOCK
  _run "s6-whitespace-waiver-BLOCK"     2 "$MISSING"  "$TR_SPAWN"   "    " fresh "conversation-tree state"
  # 7. spawn + no state + stale(>1h) waiver -> still BLOCK
  _run "s7-stale-waiver-BLOCK"          2 "$MISSING"  "$TR_SPAWN"   "this justification is substantive but stale" stale "conversation-tree state"
  # 8. transcript missing (gate-internal limitation) -> fail-open ALLOW
  _run "s8-transcript-missing-failopen" 0 "$GOOD"     "$TR_MISSING" ""  ""      ""
  # 9. REGRESSION (ADR-034): a session whose ONLY spawns were sub-agent
  # Task/Agent must ALLOW session-end SILENTLY even with NO state file —
  # sub-agent dispatch is AI-internal, not a conversation branch. This is
  # the Stop-side of the friction Misha identified (a Code session that ran
  # parallel reviewers must not be Stop-blocked or forced to write a waiver).
  _run "s9-taskonly-no-spawn-ALLOW"     0 "$MISSING"  "$TR_TASKONLY" ""  ""      ""

  echo ""
  echo "$PASSED passed, $FAILED failed"
  [[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
fi

# ============================================================
# Runtime path
# ============================================================

# Shared retry-guard library — mirror bug-persistence-gate.sh exactly.
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/lib/stop-hook-retry-guard.sh" 2>/dev/null || true

# Read stdin JSON (Claude Code provides it for Stop hooks).
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi

# Locate the transcript. Field name varies across Claude Code versions; try
# the same selectors bug-persistence-gate.sh uses.
TRANSCRIPT_PATH=""
if [[ -n "$INPUT" ]] && command -v jq >/dev/null 2>&1; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
fi

# No transcript => cannot verify => no-op. This is a gate-internal
# limitation (we cannot read what spawned), NOT a state violation —
# fail-open per ADR-031 r7 (own malfunction only).
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "[conv-tree-stop-gate] ALLOW (fail-open): no readable \$TRANSCRIPT_PATH — gate-internal, cannot verify" >&2
  exit 0
fi

# jq is required to inspect the JSONL transcript shape; its absence is a
# gate-internal malfunction -> fail OPEN (never fail-closed on our breakage).
if ! command -v jq >/dev/null 2>&1; then
  echo "[conv-tree-stop-gate] ALLOW (fail-open): jq unavailable — gate-internal, cannot scan transcript" >&2
  exit 0
fi

# --- Scan the transcript for a spawn/dispatch THIS session. ---
# Claude Code transcripts are JSONL: one JSON object per line. A tool
# invocation appears as a content block of type "tool_use" with a "name"
# (assistant turn). Across versions the tool name can also surface as a
# top-level .tool_name or .message.content[].name. We extract every plausible
# tool-name token and test it against the enumerated spawn set.
SPAWN_NAMES=$(jq -r '
  [ .tool_name? ,
    ( .message?.tool_name? ) ,
    ( (.content? // empty) | if type=="array" then .[] else . end | .name? ) ,
    ( (.message?.content? // empty) | if type=="array" then .[] else . end | .name? )
  ]
  | map(select(. != null and . != ""))
  | .[]
' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

SPAWN_SEEN=0
SPAWN_LIST=""
while IFS= read -r nm; do
  [[ -z "$nm" ]] && continue
  case "$nm" in
    mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task)
      SPAWN_SEEN=1
      case "  $SPAWN_LIST  " in *"  $nm  "*) ;; *) SPAWN_LIST="${SPAWN_LIST:+$SPAWN_LIST, }$nm" ;; esac
      ;;
  esac
done <<< "$SPAWN_NAMES"

# No matched spawn this session -> ALLOW silently (mirrors
# bug-persistence-gate.sh: no trigger => nothing to enforce, no output).
if [[ "$SPAWN_SEEN" -eq 0 ]]; then
  exit 0
fi

STATE_DIR="${CLAUDE_STATE_DIR:-.claude/state}"
STATE_PATH=$(_resolve_state_path)
STATE_LIB=$(_resolve_state_lib)

# --- Extract the spawned branch identifier(s) INDEPENDENTLY from the
# transcript's spawn tool_input (ADR-031 r7 Pin-1 — never from the state
# file the writer controls). Same candidate-extraction logic as B1's gate
# applied to every spawn tool_use input found in the transcript. ---
TI_TEXT=$(jq -r '
  [ ( (.content? // empty)         | if type=="array" then .[] else . end | (.input?.prompt?, .input?.description?, .input?.title?, .input?.content?) ),
    ( (.message?.content? // empty) | if type=="array" then .[] else . end | (.input?.prompt?, .input?.description?, .input?.title?, .input?.content?) ),
    .tool_input?.prompt?, .tool_input?.description?, .tool_input?.title?, .tool_input?.content?
  ] | map(select(. != null and . != "")) | join("\n")
' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")
TI_TITLES=$(jq -r '
  [ ( (.content? // empty)         | if type=="array" then .[] else . end | .input?.title? ),
    ( (.message?.content? // empty) | if type=="array" then .[] else . end | .input?.title? ),
    .tool_input?.title?
  ] | map(select(. != null and . != "")) | .[]
' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

declare -a CANDS=()
while IFS= read -r tid; do
  [[ -z "$tid" ]] && continue
  CANDS+=("$tid" "worker-$tid")
done < <(printf '%s' "$TI_TEXT" | grep -oE 'task-id=[A-Za-z0-9._/-]+' | sed 's/^task-id=//')
while IFS= read -r wb; do
  [[ -z "$wb" ]] && continue
  CANDS+=("$wb")
done < <(printf '%s' "$TI_TEXT" | grep -oE 'worker-[A-Za-z0-9._/-]+')
while IFS= read -r bb; do
  [[ -z "$bb" ]] && continue
  CANDS+=("$bb")
done < <(printf '%s' "$TI_TEXT" | grep -oE 'branch[^`]*`[A-Za-z0-9._/-]+`' | grep -oE '`[A-Za-z0-9._/-]+`' | tr -d '`')
while IFS= read -r tt; do
  [[ -z "$tt" ]] && continue
  CANDS+=("$tt")
done <<< "$TI_TITLES"

# --- Fresh substantive waiver release-valve (mirrors bug-persistence-gate.sh
# waiver semantics EXACTLY: >=1 substantive non-whitespace line, mtime < 1h).
# Checked BEFORE the state checks so a hook bug or a legitimate edge never
# bricks all work. ---
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
  echo "[conv-tree-stop-gate] ALLOW: fresh substantive conv-tree-stop-waiver present (release valve)" >&2
  exit 0
fi

# --- Determine whether the spawn(s) have a corresponding VERIFIED state
# write naming the branch(es). A spawn occurred; for ALLOW we require:
#   (1) the state file exists,
#   (2) it is valid JSON,
#   (3) it passes the §8 r2.1 verifySnapshotAttested check (SOLE NORMATIVE),
#   (4) its verified snapshot.nodes contains a live (state!=archived) node
#       naming at least one extracted branch candidate.
# Any of (1)-(4) failing while a real spawn occurred is a STATE-SHAPE
# violation -> BLOCK (NOT fail-open: a torn/missing state file with a real
# spawn must block, consistent with B1's Pin-2 discipline). ---
STATE_VERDICT="OK"   # OK | NOSTATE | BADJSON | UNVERIFIED:<reason> | NOBRANCH | LIBERR:<msg>

if [[ ! -f "$STATE_PATH" ]]; then
  STATE_VERDICT="NOSTATE"
else
  RAW=$(cat "$STATE_PATH" 2>/dev/null || echo "")
  if ! printf '%s' "$RAW" | jq -e . >/dev/null 2>&1; then
    STATE_VERDICT="BADJSON"
  elif ! command -v node >/dev/null 2>&1; then
    # node is the SOLE NORMATIVE §8 r2.1 verifier; its absence is a
    # gate-internal malfunction -> fail OPEN (never fail-closed on our
    # own breakage, even when a spawn occurred).
    echo "[conv-tree-stop-gate] ALLOW (fail-open): node unavailable — gate-internal, cannot run the §8 r2.1 normative verifier" >&2
    exit 0
  else
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
        # Verified — now require a live node naming an extracted candidate.
        MATCHED=""
        if [[ "${#CANDS[@]}" -gt 0 ]]; then
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
        fi
        if [[ -n "$MATCHED" ]]; then
          STATE_VERDICT="OK"
        else
          STATE_VERDICT="NOBRANCH"
        fi
        ;;
      UNVERIFIED:*)
        STATE_VERDICT="$VERIFY_OUT"
        ;;
      LIBERR:*)
        # The gate's OWN malfunction (node ran but require/parse threw);
        # the state-FILE shape was already validated as JSON above, so
        # this is gate-internal -> fail OPEN (Pin-2: own malfunction only).
        echo "[conv-tree-stop-gate] ALLOW (fail-open): state-library verifier malfunctioned (${VERIFY_OUT#LIBERR:}) — gate-internal, NOT a state-file shape problem" >&2
        exit 0
        ;;
      *)
        echo "[conv-tree-stop-gate] ALLOW (fail-open): unexpected verifier output — gate-internal malfunction" >&2
        exit 0
        ;;
    esac
  fi
fi

if [[ "$STATE_VERDICT" == "OK" ]]; then
  echo "[conv-tree-stop-gate] ALLOW: spawn(s) [$SPAWN_LIST] have a verified conversation-tree state naming the branch" >&2
  exit 0
fi

# --- BLOCK: a spawn occurred this session without a verified true-tree
# write. Structured stderr + {"decision":"block"} + retry-guard, mirroring
# bug-persistence-gate.sh exactly. ---
case "$STATE_VERDICT" in
  NOSTATE)       WHY="the conversation-tree state file does not exist ($STATE_PATH)";;
  BADJSON)       WHY="the conversation-tree state file is not valid JSON (torn/garbled write — never trusted)";;
  UNVERIFIED:*)  WHY="the snapshot is NOT integrity-verified (${STATE_VERDICT#UNVERIFIED:}) — §8 r2.1 attestation failed (torn/tampered)";;
  NOBRANCH)      WHY="the verified snapshot.nodes has no live node naming any spawned branch (candidates: ${CANDS[*]:-<none extracted>})";;
  *)             WHY="the conversation-tree state could not be verified for the spawn(s) this session";;
esac

cat >&2 <<MSG
================================================================
CONVERSATION-TREE STOP GATE — SESSION END BLOCKED
================================================================

This session dispatched at least one Dispatch orchestrator spawn
($SPAWN_LIST), but $WHY.

ADR-031 r7 enforcement: a session that spawned a child MUST have
written the *true* conversation tree (a verified snapshot whose
snapshot.nodes contains a live node naming the spawned branch)
BEFORE the session ends. The PreToolUse B1 gate enforces this per
spawn; this Stop gate is the session-boundary backstop.

Before the session can end, do ONE of:

  1. Write the true conversation-tree state via the state library
     (a verified snapshot whose snapshot.nodes contains a live
     node naming the spawned branch(es)), THEN end the session.
     State file: $STATE_PATH

  2. If this spawn legitimately touches no tree (e.g. a read-only
     research dispatch) or you suspect a gate bug, author a fresh
     substantive waiver (mirrors bug-persistence-gate.sh):
       mkdir -p $STATE_DIR && \\
       printf '%s\\n' '<one substantive line: why session-end is OK>' \\
         > $STATE_DIR/conv-tree-stop-waiver-\$(date +%s).txt
     (>=1 non-whitespace line, mtime < 1h). NEVER --no-verify.

See ~/.claude/doctrine/gate-respect.md — diagnose before bypass.
================================================================
MSG

echo "[conv-tree-stop-gate] BLOCK: spawn(s) [$SPAWN_LIST] without a verified true-tree write ($STATE_VERDICT)" >&2

RG_SESSION_ID=$(command -v retry_guard_session_id >/dev/null 2>&1 && retry_guard_session_id "$INPUT" || echo "ppid_${PPID:-$$}")
RG_FAILURE_SIG="conv-tree-stop:${STATE_VERDICT}:${SPAWN_LIST}"
RG_ERROR_ONELINE="Conversation-tree stop gate: spawn(s) [$SPAWN_LIST] occurred this session without a verified true-tree state write ($STATE_VERDICT)."
RG_BLOCK_JSON='{"decision": "block", "reason": "conversation-tree-stop-gate: a spawn/Task/Agent occurred this session without a verified conversation-tree state write naming the branch. See stderr for remediation (write the true tree, or a fresh substantive conv-tree-stop-waiver). NEVER --no-verify."}'

if command -v retry_guard_block_or_exit >/dev/null 2>&1; then
  retry_guard_block_or_exit \
    "conversation-tree-stop-gate" \
    "$RG_SESSION_ID" \
    "$RG_FAILURE_SIG" \
    "$RG_ERROR_ONELINE" \
    "$RG_BLOCK_JSON" \
    2
else
  # Retry-guard library unavailable (gate-internal degradation): still
  # block, but without the loop-cap. Mirrors bug-persistence-gate.sh's
  # block shape.
  printf '%s\n' "$RG_BLOCK_JSON"
  exit 2
fi
