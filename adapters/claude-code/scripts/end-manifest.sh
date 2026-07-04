#!/bin/bash
# end-manifest.sh — session end-manifest writer + validator (NL Overhaul
# Wave E, task E.12, ADR 059 D6 + D3).
#
# ============================================================
# WHAT THIS SCRIPT DOES
# ============================================================
#
# ADR 059 D6: the session ends by writing ONE small structured manifest
# (shipped SHAs, unresolved gaps + where each is durably recorded,
# needs-operator items, the constitution §6 marker as its last-line
# value) instead of every Stop gate forensically re-deriving "what this
# session did" from its own transcript heuristics — which is where the
# misfires breed (NL-FINDING-019's golden counterexample). Schema:
# adapters/claude-code/schemas/end-manifest.schema.json.
#
# Two verbs:
#   end-manifest.sh write [--session-id <id>] [--transcript <path>]
#                          [--shipped-since <ref>] [--torn-down]
#     Generates a manifest from session state (git log for SHAs this
#     session created since --shipped-since, the unresolved-gaps ledger,
#     NEEDS-YOU session entries, the transcript's final marker line) and
#     writes it to ~/.claude/state/end-manifest/<session-id>.json.
#
#   end-manifest.sh validate <session-id-or-path>
#     Re-derives and checks every claim in the manifest MECHANICALLY:
#       - each `shipped[].sha` is reachable from `shipped[].remote`
#       - each `unresolved[].recorded_at` file EXISTS and CONTAINS
#         `unresolved[].item` (substring match)
#       - if `torn_down` is true, the CURRENT worktree is clean (no
#         uncommitted changes, no untracked files outside .claude/state/ —
#         same exclusion work-integrity-gate.sh check (c) already applies,
#         NL-FINDING-026 class 2)
#       - `marker` matches the transcript's actual last non-empty line,
#         VERBATIM
#     Prints PASS/FAIL per check + an overall verdict; exit 0 if every
#     check passes, 1 otherwise. Called by stop-verdict-dispatcher.sh
#     (task E.11) when a manifest exists for the current session — see
#     that file's own docstring for how a passing validation replaces
#     work-integrity-gate's transcript-derived plan-touch scoping with
#     manifest scoping (this file does not itself call into
#     work-integrity-gate.sh; it only validates the manifest's claims).
#
# ============================================================
# SANDBOXING
# ============================================================
# END_MANIFEST_STATE_DIR overrides the manifest directory (default
# ~/.claude/state/end-manifest). HARNESS_SELFTEST=1 (with neither this
# nor HOME overridden) routes to a sandboxed tempdir, same convention as
# lib/signal-ledger.sh / needs-you.sh. Self-tests should ALWAYS set an
# explicit override rather than relying on the fallback, per SELFTEST-
# ORACLE-PIN-01.
#
# ============================================================
# EXIT CODES
# ============================================================
#   write:    0 on success, 1 on a fatal write error (cannot resolve repo
#             root / cannot create state dir).
#   validate: 0 every check passed, 1 any check failed.

set -u

_EM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_EM_HOOKS_DIR="${_EM_DIR%/scripts}/hooks"

# shellcheck disable=SC1091
{ source "${_EM_HOOKS_DIR}/lib/nl-paths.sh" 2>/dev/null; } || true

err() { echo "end-manifest.sh: $*" >&2; }
die() { err "$*"; exit 1; }

# ----------------------------------------------------------------------
# _em_state_dir — resolved manifest directory. Resolution order:
#   1. END_MANIFEST_STATE_DIR env var.
#   2. HARNESS_SELFTEST=1 -> sandboxed tempdir (per-pid, matches
#      needs-you.sh's own convention).
#   3. ${HOME}/.claude/state/end-manifest (default/live).
# ----------------------------------------------------------------------
_em_state_dir() {
  if [[ -n "${END_MANIFEST_STATE_DIR:-}" ]]; then
    printf '%s' "$END_MANIFEST_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/end-manifest-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/end-manifest' "${HOME:-$PWD}"
}

# _em_sanitize_session_id <id> — filesystem-safe filename component.
_em_sanitize_session_id() {
  printf '%s' "$1" | tr -c 'a-zA-Z0-9_-' '_'
}

_em_manifest_path() {
  local sid="$1"
  printf '%s/%s.json' "$(_em_state_dir)" "$(_em_sanitize_session_id "$sid")"
}

_em_now() { date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown'; }

_em_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; :a;N;$!ba; s/\n/\\n/g'
}

# ----------------------------------------------------------------------
# _em_final_marker_line <transcript-path>
#   Echoes the transcript's actual last non-empty line of the final
#   assistant message (same technique as work-integrity-gate.sh's
#   _wig_marker_pass_through / session-honesty-gate.sh's marker_scan_eval
#   — three independent copies of this exact JSONL-tail-parse existed
#   before this task; kept as a fourth here deliberately rather than a
#   NEW shared lib, since unifying all three existing copies is a larger,
#   separately-scoped refactor this task does not own). Returns empty +
#   exit 1 on any parse failure.
# ----------------------------------------------------------------------
_em_final_marker_line() {
  local transcript="$1"
  [[ -n "$transcript" && -f "$transcript" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local final_text
  final_text=$(jq -rs '
    [ .[]
      | select((.type? == "assistant")
               or (.message?.role? == "assistant")
               or (.role? == "assistant")) ] as $a
    | if ($a | length) == 0 then ""
      else
        ($a[-1] | (.message?.content // .content // .text // "")) as $c
        | if ($c | type) == "array" then
            ([ $c[] | if type == "object" then (.text // "")
                      elif type == "string" then .
                      else "" end ] | join("\n"))
          elif ($c | type) == "string" then $c
          else ($c | tostring) end
      end
  ' "$transcript" 2>/dev/null)
  [[ -z "$final_text" ]] && return 1

  printf '%s\n' "$final_text" | awk 'NF{l=$0} END{print l}' | tr -d '\r'
}

# ----------------------------------------------------------------------
# cmd_write [--session-id <id>] [--transcript <path>] [--shipped-since <ref>]
#           [--torn-down]
# ----------------------------------------------------------------------
cmd_write() {
  local session_id="" transcript="" shipped_since="" torn_down="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id) session_id="$2"; shift 2 ;;
      --transcript) transcript="$2"; shift 2 ;;
      --shipped-since) shipped_since="$2"; shift 2 ;;
      --torn-down) torn_down="true"; shift ;;
      *) die "write: unknown flag '$1'" ;;
    esac
  done

  if [[ -z "$session_id" ]]; then
    session_id="${CLAUDE_SESSION_ID:-unknown-$(date +%s)}"
  fi

  local state_dir
  state_dir=$(_em_state_dir)
  mkdir -p "$state_dir" 2>/dev/null || die "cannot create state dir: $state_dir"

  # ---- shipped SHAs: commits this session made (since --shipped-since,
  # or HEAD~N as a best-effort fallback when no explicit base is given)
  # that are ACTUALLY reachable from a remote-tracked ref RIGHT NOW — a
  # commit only made locally (not yet pushed/merged) is NOT "shipped" and
  # is correctly OMITTED here (honesty pin: never claim a state that is
  # not mechanically true — a session mid-flight has nothing shipped yet,
  # which is a legitimate empty shipped[] array, not an error). ----
  local shipped_json="[]"
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local remote_ref=""
    if git rev-parse --verify --quiet '@{upstream}' >/dev/null 2>&1; then
      remote_ref="@{upstream}"
    elif git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
      remote_ref="origin/master"
    fi
    if [[ -n "$remote_ref" ]]; then
      # Fetch the remote ref FRESH so a just-pushed commit is visible
      # (best-effort; a fetch failure just means we validate against
      # whatever ref state is already known locally).
      git fetch --quiet 2>/dev/null || true
      local remote_label
      remote_label=$(git rev-parse --abbrev-ref "$remote_ref" 2>/dev/null || echo "$remote_ref")
      local since_ref="${shipped_since:-HEAD~20}"
      git rev-parse --verify --quiet "$since_ref" >/dev/null 2>&1 || since_ref="$remote_ref"
      local candidate_shas
      candidate_shas=$(git log --pretty=format:'%H' "${since_ref}..HEAD" 2>/dev/null)
      if [[ -n "$candidate_shas" ]]; then
        local entries="" sha
        while IFS= read -r sha; do
          [[ -z "$sha" ]] && continue
          # Only claim SHAs that are ACTUALLY reachable from the remote
          # ref right now (never assume local==pushed).
          if git merge-base --is-ancestor "$sha" "$remote_ref" 2>/dev/null; then
            entries+="{\"sha\":\"${sha}\",\"remote\":\"$(_em_json_escape "${remote_label}")\"},"
          fi
        done <<< "$candidate_shas"
        entries="${entries%,}"
        [[ -n "$entries" ]] && shipped_json="[${entries}]"
      fi
    fi
  fi

  # ---- unresolved gaps: read this session's entries from the
  # unresolved-gaps.jsonl ledger stop-verdict-dispatcher.sh writes
  # (task E.11) — every line already carries session_id/gate/check/message
  # and is durably recorded IN THAT SAME FILE, so recorded_at is simply
  # the ledger path itself. ----
  local unresolved_json="[]"
  local gaps_path="${HOME:-$PWD}/.claude/state/unresolved-gaps.jsonl"
  if [[ -f "$gaps_path" ]] && command -v jq >/dev/null 2>&1; then
    local u
    u=$(jq -cs --arg sid "$session_id" --arg path "$gaps_path" '
      [ .[] | select(.session_id == $sid) | { item: ((.gate // "?") + "/" + (.check // "?") + ": " + (.message // "")), recorded_at: $path } ]
    ' "$gaps_path" 2>/dev/null)
    [[ -n "$u" ]] && unresolved_json="$u"
  fi

  # ---- needs-operator: this session's NEEDS-YOU ledger entries (any
  # section, open state) — tolerate-absent if needs-you.sh's ledger isn't
  # present on this tree/machine. ----
  local needs_operator_json="[]"
  local ny_ledger="${NEEDS_YOU_STATE_DIR:-${HOME:-$PWD}/.claude/state/needs-you}/ledger.json"
  if [[ -f "$ny_ledger" ]] && command -v jq >/dev/null 2>&1; then
    local n
    n=$(jq -c --arg sid "$session_id" '
      [ .items[]? | select(.session == $sid and .state == "open") | .text ]
    ' "$ny_ledger" 2>/dev/null)
    [[ -n "$n" ]] && needs_operator_json="$n"
  fi

  # ---- marker: the transcript's actual last non-empty line. ----
  local marker=""
  if [[ -n "$transcript" ]]; then
    marker=$(_em_final_marker_line "$transcript" || echo "")
  fi
  [[ -z "$marker" ]] && marker="DONE: (marker unresolved by end-manifest.sh write — no transcript provided)"

  local manifest_path
  manifest_path=$(_em_manifest_path "$session_id")

  jq -n \
    --arg session_id "$session_id" \
    --arg created_at "$(_em_now)" \
    --argjson torn_down "$torn_down" \
    --argjson shipped "$shipped_json" \
    --argjson unresolved "$unresolved_json" \
    --argjson needs_operator "$needs_operator_json" \
    --arg marker "$marker" \
    '{
      schema_version: 1,
      session_id: $session_id,
      created_at: $created_at,
      torn_down: $torn_down,
      shipped: $shipped,
      unresolved: $unresolved,
      needs_operator: $needs_operator,
      marker: $marker
    }' > "$manifest_path" 2>/dev/null || die "write failed for $manifest_path"

  echo "$manifest_path"
}

# ----------------------------------------------------------------------
# _em_resolve_manifest_arg <session-id-or-path>
#   If the arg names an existing file, use it directly; otherwise treat
#   it as a session id and resolve via _em_manifest_path.
# ----------------------------------------------------------------------
_em_resolve_manifest_arg() {
  local arg="$1"
  if [[ -f "$arg" ]]; then
    printf '%s' "$arg"
  else
    _em_manifest_path "$arg"
  fi
}

# ----------------------------------------------------------------------
# cmd_validate <session-id-or-path> [--transcript <path>]
#   Prints one PASS/FAIL line per check to stderr; exits 0 iff all pass.
# ----------------------------------------------------------------------
cmd_validate() {
  local arg="${1:-}"
  [[ -n "$arg" ]] || die "validate: session-id-or-path required"
  shift || true
  local transcript=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --transcript) transcript="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local path
  path=$(_em_resolve_manifest_arg "$arg")
  if [[ ! -f "$path" ]]; then
    echo "FAIL: manifest not found at $path" >&2
    return 1
  fi
  command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not available, cannot validate" >&2; return 1; }

  if ! jq -e . "$path" >/dev/null 2>&1; then
    echo "FAIL: manifest is not valid JSON: $path" >&2
    return 1
  fi

  local ok=1

  # ---- check 1: every shipped[].sha reachable from shipped[].remote ----
  local sha remote n_shipped
  n_shipped=$(jq '.shipped | length' "$path" 2>/dev/null || echo 0)
  local i=0
  while [[ "$i" -lt "$n_shipped" ]]; do
    sha=$(jq -r ".shipped[$i].sha" "$path" 2>/dev/null)
    remote=$(jq -r ".shipped[$i].remote" "$path" 2>/dev/null)
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
       && git rev-parse --verify --quiet "$remote" >/dev/null 2>&1 \
       && git merge-base --is-ancestor "$sha" "$remote" 2>/dev/null; then
      echo "PASS: shipped SHA ${sha} is reachable from ${remote}" >&2
    else
      echo "FAIL: shipped SHA ${sha} is NOT reachable from ${remote} (fabricated-SHA / not-yet-merged check)" >&2
      ok=0
    fi
    i=$((i+1))
  done

  # ---- check 2: every unresolved[].recorded_at file exists + contains item ----
  local item recorded_at n_unresolved
  n_unresolved=$(jq '.unresolved | length' "$path" 2>/dev/null || echo 0)
  i=0
  while [[ "$i" -lt "$n_unresolved" ]]; do
    item=$(jq -r ".unresolved[$i].item" "$path" 2>/dev/null)
    recorded_at=$(jq -r ".unresolved[$i].recorded_at" "$path" 2>/dev/null)
    if [[ -f "$recorded_at" ]] && grep -qF -- "$item" "$recorded_at" 2>/dev/null; then
      echo "PASS: unresolved item '${item:0:60}...' found in ${recorded_at}" >&2
    else
      echo "FAIL: unresolved item '${item:0:60}...' NOT found in ${recorded_at} (missing recorded_at / item not actually recorded)" >&2
      ok=0
    fi
    i=$((i+1))
  done

  # ---- check 3: worktree clean if torn_down claimed ----
  local torn_down
  torn_down=$(jq -r '.torn_down // false' "$path" 2>/dev/null)
  if [[ "$torn_down" == "true" ]]; then
    local dirty=0
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then dirty=1; fi
      # Same .claude/state/ exclusion as work-integrity-gate.sh check (c)
      # (NL-FINDING-026 class 2) — a sanctioned remedy artifact must not
      # itself count as "not actually torn down".
      if git ls-files --others --exclude-standard 2>/dev/null | grep -v -E '(^|[/\\])\.claude[/\\]state([/\\]|$)' | grep -q .; then
        dirty=1
      fi
    fi
    if [[ "$dirty" -eq 0 ]]; then
      echo "PASS: worktree is clean, matching the manifest's torn_down: true claim" >&2
    else
      echo "FAIL: manifest claims torn_down: true but the worktree has uncommitted/untracked changes (dirty-tree lie)" >&2
      ok=0
    fi
  else
    echo "PASS: torn_down not claimed (or false) — worktree-clean check not applicable" >&2
  fi

  # ---- check 4: marker matches transcript's actual last line ----
  local manifest_marker
  manifest_marker=$(jq -r '.marker' "$path" 2>/dev/null)
  if [[ -n "$transcript" ]]; then
    local actual_marker
    actual_marker=$(_em_final_marker_line "$transcript" || echo "")
    if [[ -n "$actual_marker" && "$actual_marker" == "$manifest_marker" ]]; then
      echo "PASS: manifest marker matches the transcript's actual last line" >&2
    else
      echo "FAIL: manifest marker ('${manifest_marker}') does NOT match the transcript's actual last line ('${actual_marker}') — marker-mismatch" >&2
      ok=0
    fi
  else
    echo "PASS: no --transcript given — marker cross-check skipped (validator called without transcript context)" >&2
  fi

  if [[ "$ok" -eq 1 ]]; then
    echo "end-manifest validate: ALL CHECKS PASSED ($path)" >&2
    return 0
  else
    echo "end-manifest validate: ONE OR MORE CHECKS FAILED ($path)" >&2
    return 1
  fi
}

# ============================================================
# --self-test: schema-valid write; validator catches fabricated SHA /
# missing recorded_at / dirty-tree lie / marker mismatch; NL-FINDING-019
# golden scenario; incidental-toucher scenario.
# ============================================================
_em_self_test() {
  local script_path="${BASH_SOURCE[0]}"
  case "$script_path" in
    /*) ;;
    [A-Za-z]:[/\\]*) ;;
    *) script_path="$(pwd)/$script_path" ;;
  esac

  export HARNESS_SELFTEST=1
  local tmproot
  tmproot=$(mktemp -d 2>/dev/null || mktemp -d -t emst)
  [[ -n "$tmproot" && -d "$tmproot" ]] || { echo "self-test: cannot create tempdir" >&2; exit 2; }
  trap 'rm -rf "${tmproot:-}"' EXIT

  local passed=0 failed=0
  ok() { passed=$((passed+1)); echo "self-test: PASS: $1" >&2; }
  no() { failed=$((failed+1)); echo "self-test: FAIL: $1" >&2; }

  # Sets the global SCEN_DIR + exports END_MANIFEST_STATE_DIR/HOME for the
  # scenario. MUST be called directly (not via $(...) command
  # substitution) — a subshell's `export` does not propagate to the
  # caller, which would silently leave every subsequent write/validate
  # call pointed at the HARNESS_SELFTEST fallback path instead of this
  # scenario's own sandboxed dir (the exact bug this comment now guards
  # against, caught by this file's own first self-test run).
  SCEN_DIR=""
  _setup_scenario() {
    local name="$1"
    SCEN_DIR="$tmproot/tmpdir-$name"
    mkdir -p "$SCEN_DIR/state"
    export END_MANIFEST_STATE_DIR="$SCEN_DIR/state"
    export HOME="$SCEN_DIR/home"
    mkdir -p "$HOME/.claude/state"
    unset NEEDS_YOU_STATE_DIR
  }

  _build_repo() {
    local d="$1" name="$2"
    local repo="$d/$name"
    mkdir -p "$repo"
    ( cd "$repo" && git init -q -b master 2>/dev/null || (git init -q && git checkout -q -b master 2>/dev/null)
      git config core.hooksPath ""; git config user.email t@example.com; git config user.name T; git config commit.gpgsign false
      echo seed > seed.txt; git add -A; git commit -q -m seed
      git init -q --bare "$d/${name}-origin.git" 2>/dev/null
      git remote add origin "$d/${name}-origin.git"
      git push -q -u origin master 2>/dev/null
    )
    printf '%s' "$repo"
  }

  _write_transcript() {
    local d="$1" text="$2"
    local tfile="$d/t-$$-$RANDOM.jsonl"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"go"}]}}\n' > "$tfile"
    printf '%s\n' "$(jq -cn --arg t "$text" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' 2>/dev/null)" >> "$tfile"
    printf '%s' "$tfile"
  }

  # ================================================================
  # Scenario 1: schema-valid write from a fixture session.
  # ================================================================
  _setup_scenario s1; D="$SCEN_DIR"
  REPO=$(_build_repo "$D" repo)
  T=$(_write_transcript "$D" $'All shipped.\n\nDONE: merged everything')
  ( cd "$REPO" && bash "$script_path" write --session-id sess-s1 --transcript "$T" --shipped-since origin/master >"$D/write-out.txt" 2>"$D/write-err.txt" )
  MPATH=$(cat "$D/write-out.txt" 2>/dev/null)
  if [[ -f "$MPATH" ]] && jq -e . "$MPATH" >/dev/null 2>&1; then
    ok "write produces schema-shaped JSON at $MPATH"
  else
    no "write did not produce valid JSON (see $D/write-err.txt)"
  fi
  if jq -e '.schema_version == 1 and (.shipped | type == "array") and (.unresolved | type == "array") and (.needs_operator | type == "array") and (.marker | type == "string")' "$MPATH" >/dev/null 2>&1; then
    ok "write output matches the end-manifest schema shape"
  else
    no "write output missing required schema fields"
  fi
  RC=0
  ( cd "$REPO" && bash "$script_path" validate "sess-s1" --transcript "$T" >/dev/null 2>"$D/validate-err.txt" ) || RC=$?
  [[ "$RC" == "0" ]] && ok "clean manifest validates PASS (exit 0)" || no "expected clean manifest to validate exit 0, got $RC"

  # ================================================================
  # Scenario 2: validator catches a FABRICATED SHA (never committed).
  # ================================================================
  _setup_scenario s2; D="$SCEN_DIR"
  REPO=$(_build_repo "$D" repo)
  MPATH="$D/state/sess-s2.json"
  jq -n '{schema_version:1,session_id:"sess-s2",created_at:"2026-07-04T00:00:00Z",torn_down:false,shipped:[{sha:"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",remote:"origin/master"}],unresolved:[],needs_operator:[],marker:"DONE: fake"}' > "$MPATH"
  RC=0
  ( cd "$REPO" && bash "$script_path" validate "sess-s2" >/dev/null 2>"$D/validate-err.txt" ) || RC=$?
  [[ "$RC" != "0" ]] && ok "fabricated SHA fails validation (exit != 0)" || no "expected fabricated SHA to fail validation"
  grep -q "NOT reachable" "$D/validate-err.txt" 2>/dev/null && ok "fabricated-SHA failure message present" || no "expected 'NOT reachable' in validator stderr"

  # ================================================================
  # Scenario 3: validator catches a MISSING recorded_at (unresolved item
  # claims a record that doesn't actually contain it).
  # ================================================================
  _setup_scenario s3; D="$SCEN_DIR"
  REPO=$(_build_repo "$D" repo)
  echo "some unrelated backlog content" > "$D/state/backlog-fixture.md"
  MPATH="$D/state/sess-s3.json"
  jq -n --arg rec "$D/state/backlog-fixture.md" '{schema_version:1,session_id:"sess-s3",created_at:"2026-07-04T00:00:00Z",torn_down:false,shipped:[],unresolved:[{item:"this exact gap text was never actually written to the file",recorded_at:$rec}],needs_operator:[],marker:"DONE: fake"}' > "$MPATH"
  RC=0
  ( cd "$REPO" && bash "$script_path" validate "sess-s3" >/dev/null 2>"$D/validate-err.txt" ) || RC=$?
  [[ "$RC" != "0" ]] && ok "missing-recorded_at content fails validation" || no "expected missing recorded_at content to fail validation"

  # ================================================================
  # Scenario 4: validator catches a DIRTY-TREE LIE (torn_down: true but
  # the worktree actually has uncommitted changes).
  # ================================================================
  _setup_scenario s4; D="$SCEN_DIR"
  REPO=$(_build_repo "$D" repo)
  ( cd "$REPO" && echo dirty >> seed.txt )
  MPATH="$D/state/sess-s4.json"
  jq -n '{schema_version:1,session_id:"sess-s4",created_at:"2026-07-04T00:00:00Z",torn_down:true,shipped:[],unresolved:[],needs_operator:[],marker:"DONE: fake"}' > "$MPATH"
  RC=0
  ( cd "$REPO" && bash "$script_path" validate "sess-s4" >/dev/null 2>"$D/validate-err.txt" ) || RC=$?
  [[ "$RC" != "0" ]] && ok "dirty-tree lie (torn_down:true but dirty) fails validation" || no "expected dirty-tree lie to fail validation"

  # ================================================================
  # Scenario 5: validator catches a MARKER MISMATCH (manifest's marker
  # differs from the transcript's actual last line).
  # ================================================================
  _setup_scenario s5; D="$SCEN_DIR"
  REPO=$(_build_repo "$D" repo)
  T=$(_write_transcript "$D" $'Work happened.\n\nPAUSING: need input — reply go or no-go?')
  MPATH="$D/state/sess-s5.json"
  jq -n '{schema_version:1,session_id:"sess-s5",created_at:"2026-07-04T00:00:00Z",torn_down:false,shipped:[],unresolved:[],needs_operator:[],marker:"DONE: this does not match the transcript at all"}' > "$MPATH"
  RC=0
  ( cd "$REPO" && bash "$script_path" validate "sess-s5" --transcript "$T" >/dev/null 2>"$D/validate-err.txt" ) || RC=$?
  [[ "$RC" != "0" ]] && ok "marker-mismatch fails validation" || no "expected marker mismatch to fail validation"
  grep -q "marker-mismatch" "$D/validate-err.txt" 2>/dev/null && ok "marker-mismatch failure message present" || no "expected 'marker-mismatch' in validator stderr"

  # ================================================================
  # Scenario 6 (NL-FINDING-019 golden): scope-line-only touch — a session
  # whose ONLY plan interaction was the in-flight scope-update line the
  # scope-enforcement gate itself mandates. With a manifest present that
  # simply omits this plan from any claim (nothing to validate about it —
  # the manifest's OWN claims are all clean), validation PASSES WITHOUT A
  # WAIVER. This is the manifest-scoping half of the golden scenario;
  # work-integrity-gate.sh's own manifest-scoping branch (see that file)
  # is the OTHER half — this self-test proves the manifest itself carries
  # no false claim requiring a waiver to clear.
  # ================================================================
  _setup_scenario s6; D="$SCEN_DIR"
  REPO=$(_build_repo "$D" repo)
  mkdir -p "$REPO/docs/plans"
  { echo "# Plan: program-plan"; echo "Status: ACTIVE"; echo; echo "## In-flight scope updates"; echo "- added task F.9 (scope-line-only touch)"; echo; echo "## Tasks"; echo "- [ ] F.9 future wave task"; } > "$REPO/docs/plans/program-plan.md"
  ( cd "$REPO" && git add -A && git commit -q -m "scope-line-only touch" )
  T=$(_write_transcript "$D" $'Appended the mandated scope line only.\n\nDONE: scope line appended, nothing else touched')
  ( cd "$REPO" && bash "$script_path" write --session-id sess-s6 --transcript "$T" --shipped-since origin/master >"$D/write-out.txt" 2>"$D/write-err.txt" )
  RC=0
  ( cd "$REPO" && bash "$script_path" validate "sess-s6" --transcript "$T" >/dev/null 2>"$D/validate-err.txt" ) || RC=$?
  [[ "$RC" == "0" ]] && ok "NL-FINDING-019 golden: scope-line-only-touch session's manifest validates PASS without a waiver" || no "expected 019 golden manifest to validate clean, got $RC"
  grep -qi "waiver" "$D/validate-err.txt" 2>/dev/null && no "019 golden validator output mentions 'waiver' — should never need one" || ok "019 golden validation required NO waiver language"

  # ================================================================
  # Scenario 7 (incidental-toucher): a session that only READ (not
  # created/completed) a foreign COMPLETED-but-unchecked plan writes a
  # manifest that makes NO claim about that plan's task-completion state
  # — the manifest only claims what THIS session shipped/left unresolved.
  # Validation passes: the manifest never asserted ownership of the
  # foreign plan's world-state, so there is nothing to inherit a remedy
  # for (the scoping rule: "created the state" vs "touched the file").
  # ================================================================
  _setup_scenario s7; D="$SCEN_DIR"
  REPO=$(_build_repo "$D" repo)
  mkdir -p "$REPO/docs/plans"
  { echo "# Plan: foreign-plan"; echo "Status: COMPLETED"; echo; echo "## Tasks"; echo "- [ ] Z.1 someone else's unfinished task"; } > "$REPO/docs/plans/foreign-plan.md"
  ( cd "$REPO" && git add -A && git commit -q -m "foreign plan (pre-existing, not owned by this session)" )
  T=$(_write_transcript "$D" $'Read the foreign plan for context only; did not touch its tasks.\n\nDONE: unrelated work shipped')
  ( cd "$REPO" && bash "$script_path" write --session-id sess-s7 --transcript "$T" --shipped-since origin/master >"$D/write-out.txt" 2>"$D/write-err.txt" )
  RC=0
  ( cd "$REPO" && bash "$script_path" validate "sess-s7" --transcript "$T" >/dev/null 2>"$D/validate-err.txt" ) || RC=$?
  [[ "$RC" == "0" ]] && ok "incidental-toucher: manifest making no claim about the foreign plan validates PASS (no inherited remedy)" || no "expected incidental-toucher manifest to validate clean, got $RC"

  echo "" >&2
  echo "self-test summary: $passed passed, $failed failed" >&2
  if [[ "$failed" -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# Entry point
# ============================================================
case "${1:-}" in
  --self-test) _em_self_test; exit $? ;;
  write) shift; cmd_write "$@" ;;
  validate) shift; cmd_validate "$@" ;;
  *)
    echo "usage: end-manifest.sh write [--session-id <id>] [--transcript <path>] [--shipped-since <ref>] [--torn-down]" >&2
    echo "       end-manifest.sh validate <session-id-or-path> [--transcript <path>]" >&2
    echo "       end-manifest.sh --self-test" >&2
    exit 1
    ;;
esac
