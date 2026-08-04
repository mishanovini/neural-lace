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
#
# ============================================================
# REGISTER WALK (gated-pipeline-master-2026-08 Task 20; design
# docs/designs/gated-pipeline-master-2026-08-03.md §4, REQ-B11 carriage
# channel 3 — the C-1 merged single-emission form)
# ============================================================
# In addition to the doctrine walk above (manifest jit_triggers.paths), this
# hook ALSO walks config/operator-directives.json via hooks/lib/directives-
# register-lib.sh's dr_register_walk_bash (the pure-bash, subprocess-free
# fast path — see that lib's own header for why: a jq/node parse of the
# register costs ~174ms, and even a naive pure-bash `while read` + `[[ =~ ]]`
# implementation measured slower than that on this platform; the lib's
# actual implementation uses a fast-slurp + case-glob approach instead, kept
# under the <50ms Behavioral Contract budget — measured 10-run average in
# this task's evidence file).
#
# BOTH walks compute independently on every matching event (C-1 form): the
# doctrine walk's per-entry-id marker and the register walk's per-OD-id
# marker are tracked separately ("per-walk markers written independently" —
# design §4, verbatim) so either can fire, both can fire, or neither can
# fire, all landing in exactly ONE `hookSpecificOutput` JSON object (ONE
# `jq -n` call, at the very end of _compute_injection) containing both
# bodies concatenated — never two separate JSON objects, never a body lost
# because the other walk also fired. See _compute_doctrine_body /
# _compute_register_body / _compute_injection below.

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

# Source the directives-register lib (Task 11; THE one parser for the
# register — M-3). Sourcing failure degrades gracefully: dr_register_walk_
# bash simply won't be defined, and _compute_register_body's `command -v`
# guard makes that a silent no-fire, never a crash (same failure-mode
# contract as the manifest/jq guards above).
# shellcheck source=lib/directives-register-lib.sh
if [ -f "$SCRIPT_DIR/lib/directives-register-lib.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/directives-register-lib.sh" 2>/dev/null || true
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

# Resolve the operator-directives register path. UNLIKE manifest.json and
# doctrine/, config/operator-directives.json has no ~/.claude/config/ live
# sync target (install.sh does not sync adapters/claude-code/config/ at
# all — verified during this task's build) — so this resolves ONLY via the
# DOCTRINE_JIT_REGISTER test override or the repo-root fallback, never a
# `$HOME/.claude/...` live path. Echoes empty string if unresolvable (the
# register-walk side then silently no-fires — same failure-mode contract as
# every other resolver in this file).
_resolve_register_path() {
  if [ -n "${DOCTRINE_JIT_REGISTER:-}" ] && [ -f "${DOCTRINE_JIT_REGISTER}" ]; then
    printf '%s' "$DOCTRINE_JIT_REGISTER"
    return 0
  fi
  if command -v nl_repo_root >/dev/null 2>&1; then
    local root
    root="$(nl_repo_root 2>/dev/null || true)"
    if [ -n "$root" ] && [ -f "$root/adapters/claude-code/config/operator-directives.json" ]; then
      printf '%s' "$root/adapters/claude-code/config/operator-directives.json"
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
# Doctrine body (the original C.2 walk, unchanged in substance — only the
# tail changed: it used to `jq -n` its own JSON here; it now sets a global
# instead so _compute_injection (below) can merge it with the register body
# into a SINGLE jq -n emission — Task 20, C-1 form).
#
# Args: $1 = manifest path, $2 = normalized file_path, $3 = session_id,
#       $4 = state_dir
# Sets global _DJ_DOCTRINE_BODY to the body TEXT (header + compact content)
# on a fire, leaves it "" on no-fire — a global, not a stdout echo, so the
# caller does NOT need a `$( )` command-substitution fork around this call
# (see the fork-cost note on _compute_register_body/_compute_injection
# below; this function's own INTERNAL jq calls are pre-existing C.2 cost,
# outside Task 20's <50ms register-walk budget). Writes the marker file as
# a side effect when it fires (unless DOCTRINE_JIT_DRY_RUN=1, used by one
# self-test scenario to inspect would-fire-again behavior without mutating
# state).
# ============================================================
_compute_doctrine_body() {
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

    # Set the global rather than `printf`+return-via-stdout: _compute_
    # injection calls this function DIRECTLY (no `$( )` around the call),
    # so there is only ONE command-substitution fork on the register-walk
    # path (inside _compute_register_body, capturing dr_register_walk_
    # bash's own output) rather than two nested ones — measurably relevant
    # at this platform's fork cost (T20 evidence timing table: doubling the
    # capture layers roughly doubled the observed added latency during this
    # task's build).
    _DJ_DOCTRINE_BODY="$body"

    if [ "${DOCTRINE_JIT_DRY_RUN:-0}" != "1" ]; then
      mkdir -p "$state_dir" 2>/dev/null || true
      : > "$marker" 2>/dev/null || true
    fi
    return 0
  done

  return 0
}

# ============================================================
# Register body (Task 20, REQ-B11 carriage channel 3 — the register walk).
#
# Args: $1 = register path (may be empty — resolver failure is a legitimate
#       silent no-fire, not an error), $2 = normalized file_path,
#       $3 = session_id, $4 = state_dir
# Sets global _DJ_REGISTER_BODY to the body TEXT (header + one block per
# newly-matched OD- entry) when >=1 entry matches AND has not already fired
# this session, leaves it "" otherwise — a global, not a stdout echo, for
# the SAME fork-avoidance reason as _compute_doctrine_body above: the ONE
# unavoidable command-substitution fork on this path is the `raw="$( )"`
# capture just below (dr_register_walk_bash's own text output has to be
# captured somehow to be parsed into per-id blocks); wrapping THIS function
# in a second `$( )` at the _compute_injection call site would double that
# fork cost for no benefit (measured during this task's build — see the T20
# evidence timing table). Writes ONE marker per OD- id that fires
# ($state_dir/<session_id>--od--<id> — a DISTINCT marker namespace from the
# doctrine walk's $state_dir/<session_id>--<entry_id>, so "per-walk markers
# written independently" per the design — an OD- id and a manifest entry id
# can never collide, and either walk's dedup state is fully independent of
# the other's).
# ============================================================
_compute_register_body() {
  local register="$1" norm_path="$2" session_id="$3" state_dir="$4"

  [ -n "$register" ] && [ -f "$register" ] || return 0
  [ -n "$norm_path" ] || return 0
  [ -n "$session_id" ] || return 0
  command -v dr_register_walk_bash >/dev/null 2>&1 || return 0

  # Called DIRECTLY (no `$( )`) — dr_register_walk_bash sets the
  # DR_REGISTER_WALK_OUT global instead of echoing to stdout specifically so
  # this call site needs no capture fork (see that function's own docstring
  # for the measured fork-cost reasoning; this is the SAME pattern as
  # _compute_injection calling _compute_doctrine_body/_compute_register_body
  # directly rather than via `$( )`).
  local raw
  dr_register_walk_bash "$register" "$norm_path"
  raw="$DR_REGISTER_WALK_OUT"
  [ -z "$raw" ] && return 0

  # Parse the ===OD-NNN=== block format (pure bash: fast-slurp-shaped IFS
  # split already happened inside dr_register_walk_bash; this is a much
  # smaller string — only the entries that already matched — so a plain
  # per-line loop here is not on the same measured hot path as the
  # register's own file scan).
  local -a _rlines=()
  local _old_ifs="$IFS"
  IFS=$'\n'
  set -f
  # shellcheck disable=SC2206
  _rlines=($raw)
  set +f
  IFS="$_old_ifs"

  local cur_id="" cur_body="" new_body="" new_count=0 rline marker mkdir_done=0

  # `mkdir -p` is an EXTERNAL binary on this platform (not a bash builtin) —
  # a measurable fork cost (T20 evidence: calling it once per matched entry
  # inside the flush below, instead of at most once here, was most of an
  # earlier ~150ms regression in this function during this task's build).
  # Called at most ONCE per invocation, only if there is at least one new
  # marker to write, and only outside DRY_RUN.
  _dj__ensure_state_dir() {
    [ "$mkdir_done" -eq 1 ] && return 0
    mkdir_done=1
    # `[ -d ]` is a builtin test (no fork) — skip the `mkdir` fork entirely
    # in the overwhelmingly common case where the directory already exists
    # (true for every event after the first in a session).
    [ -d "$state_dir" ] && return 0
    [ "${DOCTRINE_JIT_DRY_RUN:-0}" != "1" ] && mkdir -p "$state_dir" 2>/dev/null
    return 0
  }

  _dj__flush_register_entry() {
    [ -z "$cur_id" ] && return 0
    marker="$state_dir/${session_id}--od--${cur_id}"
    if [ ! -f "$marker" ]; then
      if [ -n "$new_body" ]; then
        new_body="${new_body}

${cur_id} — ${cur_body}"
      else
        new_body="${cur_id} — ${cur_body}"
      fi
      new_count=$((new_count + 1))
      if [ "${DOCTRINE_JIT_DRY_RUN:-0}" != "1" ]; then
        _dj__ensure_state_dir
        : > "$marker" 2>/dev/null || true
      fi
    fi
    cur_id=""; cur_body=""
    return 0
  }

  for rline in "${_rlines[@]}"; do
    case "$rline" in
      ===OD-*===)
        _dj__flush_register_entry
        cur_id="${rline#===}"
        cur_id="${cur_id%===}"
        ;;
      *)
        if [ -n "$cur_id" ]; then
          if [ -n "$cur_body" ]; then
            cur_body="${cur_body}
${rline}"
          else
            cur_body="$rline"
          fi
        fi
        ;;
    esac
  done
  _dj__flush_register_entry

  [ "$new_count" -eq 0 ] && return 0
  # `printf -v` writes straight into the named variable (a bash builtin
  # feature) — no `$( )` fork, unlike a plain `printf` wrapped in command
  # substitution.
  printf -v _DJ_REGISTER_BODY '[doctrine-jit] register — %s operator directive(s) matched (trigger: %s)\n\n%s' \
    "$new_count" "$norm_path" "$new_body"
  return 0
}

# ============================================================
# Core injector logic (used by both the live path and self-test)
#
# Args: $1 = manifest path, $2 = normalized file_path, $3 = session_id,
#       $4 = state_dir, $5 = register path (OPTIONAL — omitted/empty is a
#       legitimate call shape: every pre-Task-20 caller passes only 4 args,
#       and the register walk simply contributes nothing in that case,
#       preserving every existing self-test scenario's behavior unchanged).
# Echoes ONE JSON additionalContext blob (hookSpecificOutput) to stdout when
# EITHER walk fires, containing BOTH bodies concatenated when both fire
# (C-1: single JSON object, never two); echoes nothing when neither fires.
# ============================================================
_compute_injection() {
  local manifest="$1" norm_path="$2" session_id="$3" state_dir="$4" register_path="${5:-}"

  # Called DIRECTLY (no `$( )` around either call) — both sub-computations
  # report through the _DJ_DOCTRINE_BODY / _DJ_REGISTER_BODY globals they
  # set, not stdout. This is the ONE thing that keeps the register walk's
  # measured added latency under the <50ms budget on this platform: an
  # extra command-substitution fork wrapping either call was measured to
  # roughly double the observed cost during this task's build (T20 evidence
  # timing table) — see the fork-avoidance notes on both functions above.
  local doctrine_body register_body merged
  _DJ_DOCTRINE_BODY=""
  _DJ_REGISTER_BODY=""
  _compute_doctrine_body "$manifest" "$norm_path" "$session_id" "$state_dir"
  _compute_register_body "$register_path" "$norm_path" "$session_id" "$state_dir"
  doctrine_body="$_DJ_DOCTRINE_BODY"
  register_body="$_DJ_REGISTER_BODY"

  [ -z "$doctrine_body" ] && [ -z "$register_body" ] && return 0

  if [ -n "$doctrine_body" ] && [ -n "$register_body" ]; then
    merged="${doctrine_body}

---

${register_body}"
  elif [ -n "$doctrine_body" ]; then
    merged="$doctrine_body"
  else
    merged="$register_body"
  fi

  jq -n --arg ctx "$merged" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
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

  local manifest register_path state_dir norm
  manifest="$(_resolve_manifest_path)"
  register_path="$(_resolve_register_path)"
  # Neither walk has anything to read -> nothing this hook can do. A missing
  # MANIFEST alone no longer short-circuits the whole hook (Task 20): the
  # register walk is independent of the doctrine walk's manifest, so an
  # empty manifest with a resolvable register still lets channel 3 fire —
  # _compute_doctrine_body's own `[ -f "$manifest" ]` guard degrades that
  # side to silent no-fire on its own.
  [ -z "$manifest" ] && [ -z "$register_path" ] && exit 0

  state_dir="$(_state_dir)"
  _sweep_stale_markers "$state_dir"

  norm="$(_normalize_path "$file_path")"

  _compute_injection "$manifest" "$norm" "$session_id" "$state_dir" "$register_path"

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

  # Task 20 (REQ-B11 carriage channel 3) fixture register: OD-901's surface
  # ("docs/plans/**") deliberately OVERLAPS the manifest's plan-edit-
  # validator jit_triggers.paths ("docs/plans/") — this is what makes the
  # C-1 both-match-same-event scenario (T11 below) real rather than
  # contrived: a single edited path that trips BOTH walks at once. OD-902's
  # surface ("src/components/**") is disjoint from every manifest trigger —
  # the register-only scenario (T12).
  # NOTE: surfaces MUST be written multi-line (one glob per line, `[` opens
  # its own line, `]` closes its own line), matching the REAL register's
  # convention exactly (config/operator-directives.json is authored this
  # way for every non-empty surfaces array) — dr_register_walk_bash's
  # pure-bash reader targets THIS shape specifically (see its module header:
  # "NOT a general JSON parser"); a single-line `"surfaces": ["x"],` fixture
  # would silently fail to parse and is a real bug this task's own build hit
  # once (documented here so it is never reintroduced).
  local register="$tmp/operator-directives.json"
  cat > "$register" <<'JSON'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "OD-901",
      "status": "BINDING",
      "surfaces": [
        "docs/plans/**"
      ],
      "supersedes": [],
      "instruction": "Rule: FIXTURE DIRECTIVE for doctrine-jit self-test.\nGolden case: T20 both-match-same-event scenario."
    },
    {
      "id": "OD-902",
      "status": "BINDING",
      "surfaces": [
        "src/components/**"
      ],
      "supersedes": [],
      "instruction": "Rule: FIXTURE DIRECTIVE matching a register-only surface.\nGolden case: T20 register-only scenario."
    }
  ]
}
JSON

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

  # ============================================================
  # Task 20 (gated-pipeline-master-2026-08, REQ-B11) — the register walk,
  # C-1 merged single-emission form. Every scenario below passes the 5th
  # arg (register path) explicitly; T1-T10 above never do, so they remain
  # untouched proof that the register walk is fully additive (a caller
  # omitting arg 5 gets EXACTLY the pre-Task-20 doctrine-only behavior).
  # ============================================================

  # T11 — THE LOAD-BEARING SCENARIO (design C-1; this task's Prove-it-works
  # #2): a path matching BOTH a manifest jit_triggers.paths entry AND a
  # register surface -> ONE valid JSON object, additionalContext contains
  # BOTH bodies (the doctrine compact text AND the OD-901 instruction),
  # BOTH markers written (doctrine's own + the register's od-- namespaced
  # one).
  got="$(_compute_injection "$manifest" "docs/plans/both-match.md" "sess-11" "$state_dir" "$register")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -e . >/dev/null 2>&1 \
     && [ "$(printf '%s' "$got" | jq -s 'length')" = "1" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'FUNCTIONALITY OVER COMPONENTS' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '\[doctrine-jit\] plan-edit-validator' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'OD-901' \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'FIXTURE DIRECTIVE for doctrine-jit self-test' \
     && [ -f "$state_dir/sess-11--plan-edit-validator" ] \
     && [ -f "$state_dir/sess-11--od--OD-901" ]; then
    echo "  T11 both-match-same-event -> ONE JSON object, both bodies, both markers: PASS"; pass=$((pass+1))
  else
    echo "  T11 both-match-same-event -> ONE JSON object, both bodies, both markers: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T12 — register-only match (src/components/** hits OD-902 but no
  # manifest jit_triggers.paths entry) -> valid JSON, additionalContext
  # contains ONLY the register body, no doctrine body/marker.
  got="$(_compute_injection "$manifest" "src/components/Foo.ts" "sess-12" "$state_dir" "$register")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -e . >/dev/null 2>&1 \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'OD-902' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'FUNCTIONALITY OVER COMPONENTS' \
     && [ ! -f "$state_dir/sess-12--plan-edit-validator" ] \
     && [ -f "$state_dir/sess-12--od--OD-902" ]; then
    echo "  T12 register-only match -> register body only, no doctrine marker: PASS"; pass=$((pass+1))
  else
    echo "  T12 register-only match -> register body only, no doctrine marker: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T13 — dedup: the SAME session repeats the SAME both-match edit -> no
  # re-injection (both walks already fired for sess-11 in T11 above).
  got="$(_compute_injection "$manifest" "docs/plans/both-match-again.md" "sess-11" "$state_dir" "$register")"
  if [ -z "$got" ]; then
    echo "  T13 dedup same session (both walks already fired) -> silent: PASS"; pass=$((pass+1))
  else
    echo "  T13 dedup same session (both walks already fired) -> silent: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T14 — a NEW session, register-only surface fires again independently
  # (register markers are per-session, matching the doctrine walk's own
  # per-session marker scoping).
  got="$(_compute_injection "$manifest" "src/components/Bar.ts" "sess-14" "$state_dir" "$register")"
  if [ -n "$got" ] && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'OD-902'; then
    echo "  T14 register fires again for a fresh session: PASS"; pass=$((pass+1))
  else
    echo "  T14 register fires again for a fresh session: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T15 — missing/empty register path degrades to doctrine-only behavior,
  # never a crash (the pre-Task-20 call shape, exercised again here with an
  # explicit empty 5th arg rather than an omitted one).
  got="$(_compute_injection "$manifest" "docs/plans/no-register.md" "sess-15" "$state_dir" "")"
  if [ -n "$got" ] \
     && printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'FUNCTIONALITY OVER COMPONENTS' \
     && ! printf '%s' "$got" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'OD-9'; then
    echo "  T15 empty register path -> doctrine-only, no crash: PASS"; pass=$((pass+1))
  else
    echo "  T15 empty register path -> doctrine-only, no crash: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # T16 — a non-existent register FILE path (not just empty string) also
  # degrades silently rather than erroring.
  got="$(_compute_injection "$manifest" "src/components/Baz.ts" "sess-16" "$state_dir" "$tmp/does-not-exist-register.json")"
  if [ -z "$got" ]; then
    echo "  T16 non-existent register path -> silent, no crash: PASS"; pass=$((pass+1))
  else
    echo "  T16 non-existent register path -> silent, no crash: FAIL (got: $got)"; fail=$((fail+1))
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
