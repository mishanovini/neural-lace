#!/bin/bash
# doctrine-jit.sh
#
# PostToolUse writer hook (Edit|Write|MultiEdit) implementing the just-in-time
# doctrine injector for NL Overhaul Program Wave C, task C.2 (ADR 058 D2).
#
# WHY THIS EXISTS: Wave C moves the bulk of the harness's rule prose out of
# the always-loaded CLAUDE.md/rules/ auto-load surface into doctrine/ compacts
# (constitution.md stays the only thing loaded on every turn). A compact that
# is never loaded is invisible; a session editing docs/plans/foo.md gets no
# automatic reminder that doctrine/planning.md governs plan-file edits. This
# hook closes that gap: the FIRST time a session's Edit/Write/MultiEdit touches
# a path matching a manifest entry's jit_triggers.paths, the entry's doctrine
# compact is injected into model context via the sanctioned PostToolUse
# additionalContext channel (precedent: gh-account-blindness-hint.sh) — once
# per doctrine file per session.
#
# THIS IS A WRITER HOOK (manifest kind: writer). Per gate-respect.md and the
# gh-account-blindness-hint.sh precedent this file follows: EVERY code path
# exits 0. A writer/informational hook must never break the triggering tool
# call — PostToolUse fires after the edit already landed; blocking here would
# be meaningless and the injected context would never be seen if the hook
# aborted the response.
#
# Behavior:
#   1. Read PostToolUse JSON (stdin, with the CLAUDE_TOOL_INPUT env fallback
#      the sibling plan-auto-closure.sh / plan-lifecycle.sh use). Extract
#      session_id + tool_input.file_path. Missing/malformed input -> exit 0
#      silently (no context emitted).
#   2. Resolve the manifest: ~/.claude/manifest.json first, then
#      <repo>/adapters/claude-code/manifest.json via lib/nl-paths.sh. Absent
#      manifest (pre-C.1 machine, or a checkout this resolver can't locate)
#      -> exit 0 silently.
#   3. Normalize file_path (backslash -> forward slash, Windows worktrees).
#      Walk manifest .entries in file order; for each entry with a non-empty
#      jit_triggers.paths array, test each pattern as a substring/glob against
#      the normalized path (bash `case` glob semantics — a trigger like
#      "docs/plans/" matches any path CONTAINING that segment, not just a
#      prefix, matching the spec's "substring/glob" contract).
#   4. Take the FIRST matching entry whose per-session marker
#      ($STATE_DIR/<session_id>--<entry-id>) does not yet exist. Resolve its
#      doctrine compact: ~/.claude/doctrine/<basename> first, then
#      <repo>/adapters/claude-code/doctrine/<basename> (basename is the last
#      path segment of the entry's doctrine_file field, which for hook-only
#      entries with doctrine_file:null cannot match — skip such entries).
#      Compact >6000 bytes is truncated at 6000 bytes with a
#      "[truncated — read <path>]" tail (defensive; the C.4 authoring cap is
#      3000 bytes so this should rarely if ever fire in practice).
#   5. Emit ONE hookSpecificOutput.additionalContext JSON blob (the sanctioned
#      channel — plain stdout does NOT reach model context per plan finding 7)
#      with a one-line header identifying the injected doctrine unit, then the
#      compact body. Write the per-session marker so this doctrine file does
#      not re-inject for the rest of the session.
#   6. Marker hygiene: on every invocation, before anything else, delete
#      marker files older than 48h (mtime) from STATE_DIR so the directory
#      does not grow unbounded across the life of a long-lived machine.
#   7. ALWAYS exit 0. No code path in this file returns non-zero except
#      --self-test's own summary exit code.
#
# STATE_DIR: $HOME/.claude/state/doctrine-jit in production. Under
# HARNESS_SELFTEST=1 the self-test suite sandboxes STATE_DIR (and every other
# resolvable path) into a mktemp -d so no self-test run ever touches
# production marker state (self-test scenario 7 asserts this directly).
#
# Self-test: invoke with --self-test. >= 7 scenarios per the plan's
# Done-when list (match+valid-JSON, dedup-same-session, non-matching-silent,
# missing-manifest-exit-0, malformed-stdin-exit-0, two-files-two-events,
# markers-sandboxed).
#
# NOTE ON THE LIVE PROBE: this file's --self-test exercises the injector's
# LOGIC against synthetic fixtures. The REAL live-session probe (does
# additionalContext actually reach a running Claude Code session's model
# context end-to-end) is the ORCHESTRATOR's step, run after this hook is
# wired into settings.json.template and a compact is copied to the live
# ~/.claude/doctrine/ path — see specs-c §C.2 "Live-probe protocol" and the
# "## C.2 live-probe result" addendum in that file. This hook cannot self-verify
# that; it can only verify it emits the correct JSON shape.

set -u

SCRIPT_NAME="doctrine-jit.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared repo-root resolver (task B.2's canonical answer to
# "where is neural-lace checked out"). Sourcing failure degrades gracefully:
# nl_repo_root/nl_workstreams_ui simply won't be defined and every call site
# below already guards with `command -v` / direct fallback logic.
# shellcheck source=lib/nl-paths.sh
if [ -f "$SCRIPT_DIR/lib/nl-paths.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/nl-paths.sh" 2>/dev/null || true
fi

# ============================================================
# Path helpers
# ============================================================

# Normalize a path for matching: forward slashes only (Windows worktrees).
_normalize_path() {
  printf '%s' "$1" | tr '\\' '/'
}

# Resolve the manifest.json path: ~/.claude/manifest.json first, then
# <repo-root>/adapters/claude-code/manifest.json. Echoes the resolved path,
# or empty string if neither exists.
_resolve_manifest_path() {
  if [ -n "${DOCTRINE_JIT_MANIFEST:-}" ] && [ -f "${DOCTRINE_JIT_MANIFEST}" ]; then
    printf '%s' "$DOCTRINE_JIT_MANIFEST"
    return 0
  fi
  local live="$HOME/.claude/manifest.json"
  if [ -f "$live" ]; then
    printf '%s' "$live"
    return 0
  fi
  if command -v nl_repo_root >/dev/null 2>&1; then
    local root
    root="$(nl_repo_root 2>/dev/null || true)"
    if [ -n "$root" ] && [ -f "$root/adapters/claude-code/manifest.json" ]; then
      printf '%s' "$root/adapters/claude-code/manifest.json"
      return 0
    fi
  fi
  printf ''
}

# Resolve the doctrine compact file for a given doctrine_file value
# (e.g. "doctrine/planning.md"). Tries ~/.claude/doctrine/<basename> first,
# then <repo-root>/adapters/claude-code/doctrine/<basename>. Echoes the
# resolved absolute path, or empty string if not found anywhere.
_resolve_doctrine_file() {
  local doctrine_file="$1" basename
  [ -z "$doctrine_file" ] && { printf ''; return 0; }
  basename="${doctrine_file##*/}"
  [ -z "$basename" ] && { printf ''; return 0; }

  if [ -n "${DOCTRINE_JIT_DOCTRINE_DIR:-}" ] && [ -f "${DOCTRINE_JIT_DOCTRINE_DIR}/${basename}" ]; then
    printf '%s' "${DOCTRINE_JIT_DOCTRINE_DIR}/${basename}"
    return 0
  fi
  local live="$HOME/.claude/doctrine/${basename}"
  if [ -f "$live" ]; then
    printf '%s' "$live"
    return 0
  fi
  if command -v nl_repo_root >/dev/null 2>&1; then
    local root
    root="$(nl_repo_root 2>/dev/null || true)"
    if [ -n "$root" ] && [ -f "$root/adapters/claude-code/doctrine/${basename}" ]; then
      printf '%s' "$root/adapters/claude-code/doctrine/${basename}"
      return 0
    fi
  fi
  printf ''
}

# Resolve STATE_DIR. Self-test sandboxes this via HARNESS_SELFTEST_DIR so no
# self-test run ever touches production marker state.
_state_dir() {
  if [ "${HARNESS_SELFTEST:-0}" = "1" ] && [ -n "${HARNESS_SELFTEST_DIR:-}" ]; then
    printf '%s/state/doctrine-jit' "$HARNESS_SELFTEST_DIR"
    return 0
  fi
  printf '%s/.claude/state/doctrine-jit' "$HOME"
}

# Marker-hygiene sweep: delete markers older than 48h (mtime). Silent,
# best-effort, never fatal.
_sweep_stale_markers() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -type f -mmin +2880 -exec rm -f {} + 2>/dev/null || true
}

# ============================================================
# Matching
# ============================================================

# Test whether normalized path $1 matches ANY of the jit_triggers.paths
# patterns given as remaining args. Patterns are matched as a SUBSTRING
# (bash case glob with leading/trailing '*' wrapped around the pattern),
# per the spec: "a trigger docs/plans/ matches any path containing it".
_path_matches_any() {
  local path="$1"; shift
  local pat
  for pat in "$@"; do
    [ -z "$pat" ] && continue
    case "$path" in
      *"$pat"*) return 0 ;;
    esac
  done
  return 1
}

# ============================================================
# Core injector logic (used by both the live path and self-test)
#
# Args: $1 = manifest path, $2 = normalized file_path, $3 = session_id,
#       $4 = state_dir
# Echoes the JSON additionalContext blob to stdout on a fire; echoes nothing
# on no-fire. Writes the marker file as a side effect when it fires (unless
# DOCTRINE_JIT_DRY_RUN=1, used by one self-test scenario to inspect
# would-fire-again behavior without mutating state).
# ============================================================
_compute_injection() {
  local manifest="$1" norm_path="$2" session_id="$3" state_dir="$4"

  [ -f "$manifest" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [ -n "$norm_path" ] || return 0
  [ -n "$session_id" ] || return 0

  jq -e . "$manifest" >/dev/null 2>&1 || return 0

  local n_entries idx
  n_entries="$(jq -r '.entries | length' "$manifest" 2>/dev/null || echo 0)"
  [ "$n_entries" -gt 0 ] 2>/dev/null || return 0

  idx=0
  while [ "$idx" -lt "$n_entries" ]; do
    local entry_id doctrine_file paths_json
    entry_id="$(jq -r ".entries[$idx].id // \"\"" "$manifest" 2>/dev/null)"
    doctrine_file="$(jq -r ".entries[$idx].doctrine_file // \"\"" "$manifest" 2>/dev/null)"
    paths_json="$(jq -c ".entries[$idx].jit_triggers.paths // []" "$manifest" 2>/dev/null)"
    idx=$((idx + 1))

    [ -z "$entry_id" ] && continue
    [ -z "$doctrine_file" ] && continue
    [ "$paths_json" = "[]" ] && continue
    [ "$paths_json" = "null" ] && continue

    # Expand the JSON array of patterns into bash args. Strip any trailing
    # CR: manifest.json is committed with LF endings, but a manifest read
    # from a heredoc-fixture (self-test) or a CRLF-checked-out working tree
    # (Windows core.autocrlf) can carry a stray \r into the jq -r output,
    # which would silently defeat the substring match below.
    local -a patterns=()
    while IFS= read -r p; do
      p="${p%$'\r'}"
      [ -n "$p" ] && patterns+=("$p")
    done < <(printf '%s' "$paths_json" | jq -r '.[]' 2>/dev/null)
    [ "${#patterns[@]}" -eq 0 ] && continue

    _path_matches_any "$norm_path" "${patterns[@]}" || continue

    # Matched. Check per-session marker (cap: ≤1 injection per doctrine file
    # per session, keyed by entry id).
    local marker="$state_dir/${session_id}--${entry_id}"
    [ -f "$marker" ] && continue

    local compact_path
    compact_path="$(_resolve_doctrine_file "$doctrine_file")"
    [ -z "$compact_path" ] && continue
    [ -f "$compact_path" ] || continue

    local matched_pattern content size
    matched_pattern=""
    for p in "${patterns[@]}"; do
      case "$norm_path" in
        *"$p"*) matched_pattern="$p"; break ;;
      esac
    done

    content="$(cat "$compact_path" 2>/dev/null || echo "")"
    size="${#content}"
    if [ "$size" -gt 6000 ]; then
      content="${content:0:6000}"
      content="${content}
[truncated — read ${compact_path}]"
    fi

    local header body
    header="[doctrine-jit] ${entry_id} — injected once for this session (trigger: ${matched_pattern})"
    body="${header}

${content}"

    jq -n --arg ctx "$body" \
      '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'

    if [ "${DOCTRINE_JIT_DRY_RUN:-0}" != "1" ]; then
      mkdir -p "$state_dir" 2>/dev/null || true
      : > "$marker" 2>/dev/null || true
    fi
    return 0
  done

  return 0
}

# ============================================================
# Live entry path
# ============================================================

_run_live() {
  local input
  input="${CLAUDE_TOOL_INPUT:-}"
  if [ -z "$input" ] && [ ! -t 0 ]; then
    input="$(cat 2>/dev/null || echo "")"
  fi
  [ -z "$input" ] && exit 0

  command -v jq >/dev/null 2>&1 || exit 0

  jq -e . >/dev/null 2>&1 <<<"$input" || exit 0

  local tool_name
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)"
  case "$tool_name" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
  esac

  local file_path session_id
  file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .file_path // ""' 2>/dev/null)"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // .session.id // ""' 2>/dev/null)"

  [ -z "$file_path" ] && exit 0
  [ -z "$session_id" ] && exit 0

  local manifest state_dir norm
  manifest="$(_resolve_manifest_path)"
  [ -z "$manifest" ] && exit 0

  state_dir="$(_state_dir)"
  _sweep_stale_markers "$state_dir"

  norm="$(_normalize_path "$file_path")"

  _compute_injection "$manifest" "$norm" "$session_id" "$state_dir"

  exit 0
}

# ============================================================
# Self-test
# ============================================================

_self_test() {
  local pass=0 fail=0
  local tmp
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t doctrinejit)"

  export HARNESS_SELFTEST=1
  export HARNESS_SELFTEST_DIR="$tmp/sandbox"
  mkdir -p "$HARNESS_SELFTEST_DIR"

  local manifest="$tmp/manifest.json"
  local doctrine_dir="$tmp/doctrine"
  mkdir -p "$doctrine_dir"

  cat > "$manifest" <<'JSON'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "plan-edit-validator",
      "kind": "gate",
      "doctrine_file": "doctrine/planning.md",
      "hooks": ["plan-edit-validator.sh"],
      "events": ["PreToolUse"],
      "wired_template": true,
      "selftest": true,
      "jit_triggers": { "paths": ["docs/plans/"], "keywords": [] },
      "blocking": true,
      "budget_class": "pretool"
    },
    {
      "id": "discovery-protocol",
      "kind": "surfacer",
      "doctrine_file": "doctrine/discovery-protocol.md",
      "hooks": ["discovery-surfacer.sh"],
      "events": ["SessionStart"],
      "wired_template": true,
      "selftest": true,
      "jit_triggers": { "paths": ["docs/discoveries/"], "keywords": [] },
      "blocking": false,
      "budget_class": "session-start"
    },
    {
      "id": "automation-modes",
      "kind": "pattern",
      "doctrine_file": "doctrine/automation-modes.md",
      "hooks": [],
      "events": [],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": false,
      "budget_class": "none"
    }
  ]
}
JSON

  printf '# Planning compact\nFUNCTIONALITY OVER COMPONENTS. Task-verifier is the sole checkbox-flipper.\n' > "$doctrine_dir/planning.md"
  printf '# Discovery protocol compact\nCapture mid-process learnings; auto-apply reversible decisions.\n' > "$doctrine_dir/discovery-protocol.md"

  export DOCTRINE_JIT_MANIFEST="$manifest"
  export DOCTRINE_JIT_DOCTRINE_DIR="$doctrine_dir"
  local state_dir
  state_dir="$(_state_dir)"

  # T1 — match on docs/plans/ path -> valid additionalContext JSON containing
  # the compact text, header names the entry + trigger, marker written.
  local got
  got="$(_compute_injection "$manifest" "docs/plans/foo.md" "sess-1" "$state_dir")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -e . >/dev/null 2>&1 \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'FUNCTIONALITY OVER COMPONENTS' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '\[doctrine-jit\] plan-edit-validator' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.hookEventName' | grep -q '^PostToolUse$' \
     && [ -f "$state_dir/sess-1--plan-edit-validator" ]; then
    echo "  T1 match -> valid additionalContext + marker written: PASS"; pass=$((pass+1))
  else
    echo "  T1 match -> valid additionalContext + marker written: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T2 — same session + same file again -> silent (dedup via marker).
  got="$(_compute_injection "$manifest" "docs/plans/bar.md" "sess-1" "$state_dir")"
  if [ -z "$got" ]; then
    echo "  T2 dedup same session -> silent: PASS"; pass=$((pass+1))
  else
    echo "  T2 dedup same session -> silent: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T3 — non-matching path -> silent.
  got="$(_compute_injection "$manifest" "src/components/Foo.ts" "sess-2" "$state_dir")"
  if [ -z "$got" ]; then
    echo "  T3 non-matching path -> silent: PASS"; pass=$((pass+1))
  else
    echo "  T3 non-matching path -> silent: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T4 — missing manifest -> silent (no crash).
  got="$(_compute_injection "$tmp/does-not-exist.json" "docs/plans/foo.md" "sess-3" "$state_dir")"
  if [ -z "$got" ]; then
    echo "  T4 missing manifest -> silent: PASS"; pass=$((pass+1))
  else
    echo "  T4 missing manifest -> silent: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T5 — malformed stdin at the live-entry layer -> exit 0, no output.
  # Exercise _run_live via subshell with malformed JSON on stdin.
  local rc out
  out="$(printf 'not json at all' | DOCTRINE_JIT_MANIFEST="$manifest" DOCTRINE_JIT_DOCTRINE_DIR="$doctrine_dir" \
         HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR="$HARNESS_SELFTEST_DIR" bash "$0" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    echo "  T5 malformed stdin -> exit 0 silent: PASS"; pass=$((pass+1))
  else
    echo "  T5 malformed stdin -> exit 0 silent: FAIL (rc=$rc out='$out')"; fail=$((fail+1))
  fi

  # T5b — missing session_id -> exit 0, no output (defensive; distinct from T5).
  local payload_no_sid='{"tool_name":"Edit","tool_input":{"file_path":"docs/plans/foo.md"}}'
  out="$(printf '%s' "$payload_no_sid" | DOCTRINE_JIT_MANIFEST="$manifest" DOCTRINE_JIT_DOCTRINE_DIR="$doctrine_dir" \
         HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR="$HARNESS_SELFTEST_DIR" bash "$0" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    echo "  T5b missing session_id -> exit 0 silent: PASS"; pass=$((pass+1))
  else
    echo "  T5b missing session_id -> exit 0 silent: FAIL (rc=$rc out='$out')"; fail=$((fail+1))
  fi

  # T6 — two different doctrine files inject on separate events (same
  # session, two different triggering paths -> two separate fires).
  local got_a got_b
  got_a="$(_compute_injection "$manifest" "docs/plans/x.md" "sess-6" "$state_dir")"
  got_b="$(_compute_injection "$manifest" "docs/discoveries/y.md" "sess-6" "$state_dir")"
  if [ -n "$got_a" ] && [ -n "$got_b" ] \
     && printf '%s' "$got_a" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'plan-edit-validator' \
     && printf '%s' "$got_b" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'discovery-protocol' \
     && [ -f "$state_dir/sess-6--plan-edit-validator" ] \
     && [ -f "$state_dir/sess-6--discovery-protocol" ]; then
    echo "  T6 two doctrine files, separate events, both fire: PASS"; pass=$((pass+1))
  else
    echo "  T6 two doctrine files, separate events, both fire: FAIL (a: $got_a | b: $got_b)"; fail=$((fail+1))
  fi

  # T7 — markers land in the HARNESS_SELFTEST sandbox, not production state.
  local prod_dir="$HOME/.claude/state/doctrine-jit"
  if [ ! -d "$prod_dir" ] || ! find "$prod_dir" -maxdepth 1 -name 'sess-*' -newer "$manifest" 2>/dev/null | grep -q .; then
    if [[ "$state_dir" == "$HARNESS_SELFTEST_DIR"* ]]; then
      echo "  T7 markers sandboxed (state_dir under HARNESS_SELFTEST_DIR): PASS"; pass=$((pass+1))
    else
      echo "  T7 markers sandboxed (state_dir under HARNESS_SELFTEST_DIR): FAIL (state_dir=$state_dir)"; fail=$((fail+1))
    fi
  else
    echo "  T7 markers sandboxed (state_dir under HARNESS_SELFTEST_DIR): FAIL (found new files in prod state dir)"; fail=$((fail+1))
  fi

  # T8 — pattern-kind entry (empty jit_triggers.paths, e.g. automation-modes)
  # never fires regardless of path, and doesn't error the loop.
  got="$(_compute_injection "$manifest" "anything/at/all.md" "sess-8" "$state_dir")"
  if [ -z "$got" ]; then
    echo "  T8 pattern-kind (empty jit_triggers) never fires: PASS"; pass=$((pass+1))
  else
    echo "  T8 pattern-kind (empty jit_triggers) never fires: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T9 — oversized compact (>6000 bytes) is truncated with the tail marker.
  local big_dir="$tmp/doctrine-big"
  mkdir -p "$big_dir"
  # shellcheck disable=SC2183
  printf '%*s' 7000 '' | tr ' ' 'x' > "$big_dir/planning.md"
  got="$(DOCTRINE_JIT_DOCTRINE_DIR="$big_dir" _compute_injection "$manifest" "docs/plans/big.md" "sess-9" "$state_dir")"
  local ctx_len
  ctx_len="$(printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | wc -c)"
  if printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '\[truncated' \
     && [ "$ctx_len" -lt 7000 ]; then
    echo "  T9 oversized compact truncated with tail marker: PASS"; pass=$((pass+1))
  else
    echo "  T9 oversized compact truncated with tail marker: FAIL (ctx_len=$ctx_len got: $(printf '%s' "$got" | head -c 200))"; fail=$((fail+1))
  fi

  # T10 — file_path with backslashes (Windows) still matches after
  # normalization is applied by the caller (_run_live normalizes before
  # calling _compute_injection; here we simulate directly).
  got="$(_compute_injection "$manifest" "$(_normalize_path 'docs\plans\win.md')" "sess-10" "$state_dir")"
  if [ -n "$got" ] && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'plan-edit-validator'; then
    echo "  T10 backslash path normalized and matches: PASS"; pass=$((pass+1))
  else
    echo "  T10 backslash path normalized and matches: FAIL (got: $got)"; fail=$((fail+1))
  fi

  rm -rf "$tmp" 2>/dev/null
  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return "$fail"
}

# ============================================================
# Entry point
# ============================================================

case "${1:-}" in
  --self-test) _self_test; exit $? ;;
  -h|--help)
    cat <<'DOCTRINEJIT_USAGE' >&2
doctrine-jit.sh — just-in-time doctrine compact injection on matching Edit/Write/MultiEdit.

  doctrine-jit.sh                # PostToolUse: reads JSON on stdin, emits
                                  # additionalContext when a manifest
                                  # jit_triggers.paths entry matches the
                                  # edited file (once per doctrine file per
                                  # session).
  doctrine-jit.sh --self-test    # run self-test suite

Reads ~/.claude/manifest.json (fallback <repo>/adapters/claude-code/manifest.json).
Reads doctrine compacts from ~/.claude/doctrine/<name> (fallback
<repo>/adapters/claude-code/doctrine/<name>). Markers under
~/.claude/state/doctrine-jit/. Always exits 0 (writer hook; never blocks).
DOCTRINEJIT_USAGE
    exit 2
    ;;
  "") _run_live ;;
  *)
    echo "doctrine-jit.sh: unknown argument '$1'" >&2
    exit 2
    ;;
esac
