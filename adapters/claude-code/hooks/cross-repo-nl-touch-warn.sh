#!/bin/bash
# cross-repo-nl-touch-warn.sh — cross-repo-incident candidate gate (Wave F,
# task F.5, specs-f §F.5 item 4).
#
# ============================================================
# WHY THIS EXISTS (cross-repo incident, 2026-07-03 — named in specs-f §F.5 as
# a downstream-project incident; the downstream project name is deliberately
# not repeated here per constitution §9)
# ============================================================
#
# A session whose project root is a DIFFERENT repo entirely (not neural-lace,
# not one of its linked worktrees) directly Edit/Write-touched files inside
# the neural-lace repo via an absolute or relative escape path, instead of
# using the cross-project capture point (`nl-issue.sh "<one line>"`,
# constitution §5) or opening a proper NL session. Direct cross-repo edits
# from an unrelated session bypass every NL-repo-local review discipline
# (plan-scoping, spec-freeze, harness-reviewer) and risk exactly the kind of
# silent drift the harness's whole gate-governance apparatus exists to catch
# — except this one instance targets the GOVERNANCE REPO ITSELF from outside
# its own review surface.
#
# ============================================================
# POSTURE: WARN, NEVER BLOCK (PreToolUse, non-blocking by design)
# ============================================================
#
# This is explicitly a WARN-mode candidate, not a blocking gate — see
# specs-f §F.5 item 4 ("Ship ONLY if it passes the §10 evidence bar... FP
# fixture REQUIRED"). A cross-repo touch is sometimes exactly the right
# thing to do (an orchestrator session dispatching builders across several
# repos; a genuinely intended harness fix authored from a non-worktree
# checkout the operator is using deliberately). Blocking a legitimate
# cross-repo edit would be strictly worse than the problem it prevents —
# this hook's entire value is VISIBILITY (name the nl-issue.sh alternative),
# never enforcement. Always exits 0.
#
# ============================================================
# DETECTION (what counts as "session root != NL repo, file targets NL repo")
# ============================================================
#
# 1. Resolve the TARGET file's repo identity: `git -C <dirname(file_path)>
#    rev-parse --git-common-dir`, resolved to an absolute canonical path.
#    (--git-common-dir, not --git-dir, so a LINKED WORKTREE of the NL repo
#    resolves to the SAME identity as the NL main checkout — the identity
#    that survives across every worktree, per NL-FINDING-014's isolation
#    convention.) If this does not resolve, or resolves to a path that is
#    not a neural-lace checkout (no adapters/claude-code/ sibling to the
#    common-dir's parent), this hook no-ops silently — it only ever
#    speaks about NL-repo targets.
# 2. Resolve the SESSION's own root identity the same way, rooted at the
#    hook's own $PWD (the session's cwd at PreToolUse time — the same
#    signal scope-enforcement-gate.sh and plan-edit-validator.sh already
#    rely on for "where is this session, right now").
# 3. WARN iff (1) resolved to an NL identity AND (2) resolved to a DIFFERENT
#    identity (or did not resolve to a git repo at all — a session with no
#    git ancestry editing into a real NL checkout is the MOST suspicious
#    case, not the least). Silent (exit 0, no output) when both resolve to
#    the SAME identity (the ordinary case: an NL session, main or worktree,
#    editing its own repo) — this is the false-positive-avoidance rule the
#    spec's evidence bar requires a fixture for (see FP_FIXTURE below).
#
# ============================================================
# WHY --git-common-dir (not --git-dir or a hardcoded path list)
# ============================================================
#
# `git rev-parse --git-common-dir` returns the SAME absolute path for the
# main checkout and for every one of its linked worktrees (this is the
# mechanism that makes "linked worktree of the NL repo" indistinguishable
# from "the NL repo" for identity purposes, without needing to enumerate
# every worktree path anywhere). This hook never hardcodes a path list —
# unlike a naive "is the path under C:\Users\...\neural-lace" string check,
# it works for ANY worktree, ANY clone location, ANY machine, as long as
# nl-paths.sh's config (or git ancestry) can resolve the canonical root.
#
# ============================================================
# CONTRACT
# ============================================================
#
#   Hook event: PreToolUse, matcher "Edit|Write|MultiEdit".
#   Reads CLAUDE_TOOL_INPUT or stdin JSON (tool_name, tool_input.file_path).
#   Exit codes: ALWAYS 0 (WARN-only; never blocks a tool call). A WARN
#   emits a stderr message (visible to the agent) naming: (a) what was
#   detected, (b) the nl-issue.sh remediation, (c) how to silence it if the
#   cross-repo touch is deliberate (NL_CROSS_REPO_TOUCH_OK=1 env var
#   prefix on the SAME Edit/Write call is not possible for a hook — there
#   is no command to prefix for a tool call, so the silencing mechanism is
#   a state marker file instead, mirroring local-edit-gate.sh's convention:
#   a fresh (<1h) ~/.claude/state/cross-repo-nl-touch-ok-<session-id>.txt
#   silences this WARN for the rest of that session — deliberately NOT a
#   waiver-file (this is advisory, not a block; ADR 059 D4's waiver-parity
#   rule applies to BLOCKING gates, this one is not blocking by design)).
#
#   --self-test : fixture suite (mktemp -d repos) covering:
#     (a) legitimate NL session (cwd IS the NL repo main checkout) editing
#         an NL-repo file -> SILENT (no warning). THE REQUIRED FP FIXTURE.
#     (b) legitimate NL session from a LINKED WORKTREE editing an NL-repo
#         file -> SILENT (same identity via --git-common-dir). ALSO A
#         REQUIRED FP FIXTURE (orchestrator/worktree sessions specifically
#         named in the spec).
#     (c) cross-repo session (cwd is an UNRELATED repo) editing a file
#         inside the NL repo via an absolute/relative path -> WARN.
#     (d) session with no git ancestry at all (cwd not a repo) editing a
#         file inside a real NL repo -> WARN (most suspicious case).
#     (e) session editing a file OUTSIDE any NL repo (ordinary work in an
#         unrelated project, touching only that project's own files) ->
#         SILENT (this hook only ever speaks about NL-repo targets).
#     (f) fresh silence-marker present -> SILENT even though (c)'s
#         condition holds.
#     (g) stale (>1h) silence-marker -> WARN (marker freshness enforced).
#
# ============================================================

set -u

_CRNTW_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ----------------------------------------------------------------------
# _crntw_load_input — CLAUDE_TOOL_INPUT env var, else stdin JSON.
# ----------------------------------------------------------------------
_crntw_load_input() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]]; then
    if [[ ! -t 0 ]]; then
      input="$(cat 2>/dev/null || echo "")"
    fi
  fi
  printf '%s' "$input"
}

_crntw_extract_field() {
  local input="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r ".$field // \"\"" 2>/dev/null
  else
    printf '%s' "$input" | grep -oE "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | sed -E "s/\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/" | head -1
  fi
}

# ----------------------------------------------------------------------
# _crntw_repo_identity <dir> — print the absolute canonical
# --git-common-dir for <dir>, or empty if <dir> is not inside any git repo.
# ----------------------------------------------------------------------
_crntw_repo_identity() {
  local dir="$1"
  [[ -d "$dir" ]] || dir="$(dirname "$dir" 2>/dev/null)"
  [[ -d "$dir" ]] || { printf ''; return 0; }
  local common
  common="$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null)" || { printf ''; return 0; }
  [[ -z "$common" ]] && { printf ''; return 0; }
  # rev-parse commonly prints a path RELATIVE TO <dir> (e.g. ".git",
  # "../../.git" for a subdirectory, or a relative linked-worktree
  # gitdir pointer) rather than an absolute one. Resolve it properly by
  # cd-ing into <dir> and letting the shell's own `cd` + `pwd -P`
  # collapse any ".." segments — naive string concatenation
  # (toplevel + "/" + common) does NOT collapse ".." and silently
  # produces a WRONG path outside the repo when common starts with "../".
  case "$common" in
    /*|[A-Za-z]:*)
      printf '%s' "$common"
      return 0
      ;;
  esac
  local resolved
  resolved="$(cd "$dir" 2>/dev/null && cd "$common" 2>/dev/null && pwd -P 2>/dev/null)"
  if [[ -n "$resolved" ]]; then
    printf '%s' "$resolved"
    return 0
  fi
  # Fallback (cd-into-common-dir failed, e.g. a gitfile pointer rather than
  # a real directory for some git configurations): resolve via toplevel
  # instead, using cd+pwd (not string concatenation) so ".." still
  # collapses correctly.
  local toplevel
  toplevel="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$toplevel" ]]; then
    resolved="$(cd "$toplevel" 2>/dev/null && cd "$common" 2>/dev/null && pwd -P 2>/dev/null)"
    [[ -n "$resolved" ]] && { printf '%s' "$resolved"; return 0; }
  fi
  printf ''
  return 0
}

# ----------------------------------------------------------------------
# _crntw_is_nl_identity <git-common-dir> — 0 if this common-dir belongs to
# a neural-lace checkout (its parent directory contains
# adapters/claude-code/), 1 otherwise. Never hardcodes a path list — this
# is a structural check against whatever repo the common-dir names.
# ----------------------------------------------------------------------
_crntw_is_nl_identity() {
  local common="$1"
  [[ -z "$common" ]] && return 1
  # common-dir is typically <root>/.git ; its parent is the repo root.
  local repo_root
  repo_root="$(dirname "$common" 2>/dev/null)"
  [[ -d "$repo_root/adapters/claude-code" ]] && return 0
  return 1
}

# ----------------------------------------------------------------------
# _crntw_marker_path <session-id>
# ----------------------------------------------------------------------
_crntw_marker_path() {
  local sid="$1"
  local state_dir="${CRNTW_STATE_DIR_OVERRIDE:-${HOME}/.claude/state}"
  printf '%s/cross-repo-nl-touch-ok-%s.txt' "$state_dir" "$sid"
}

# ----------------------------------------------------------------------
# _crntw_marker_fresh <path> — 0 if the marker exists and its mtime is
# within the last hour, 1 otherwise.
# ----------------------------------------------------------------------
_crntw_marker_fresh() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  local mtime now
  mtime="$(stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null || echo 0)"
  now="$(date -u +%s 2>/dev/null || echo 0)"
  [[ $(( now - mtime )) -le 3600 ]]
}

# ----------------------------------------------------------------------
# _crntw_check <file_path> <session_cwd> <session_id> — core decision
# logic, factored out so --self-test can drive it directly without a
# real PreToolUse JSON round-trip. Prints a WARN message to stdout (NOT
# stderr, so --self-test can capture it cleanly) when the cross-repo
# condition holds and no fresh marker silences it; prints nothing
# otherwise. Always "returns" 0 (caller decides exit code; this function
# never fails the hook).
# ----------------------------------------------------------------------
_crntw_check() {
  local file_path="$1" session_cwd="$2" session_id="${3:-unknown}"

  [[ -z "$file_path" ]] && return 0

  local file_dir
  file_dir="$(dirname "$file_path" 2>/dev/null)"
  case "$file_dir" in
    /*|[A-Za-z]:*) : ;;
    *) file_dir="$session_cwd/$file_dir" ;;
  esac

  local file_identity
  file_identity="$(_crntw_repo_identity "$file_dir")"

  # Only ever speaks about NL-repo targets — rule (e).
  if ! _crntw_is_nl_identity "$file_identity"; then
    return 0
  fi

  local session_identity
  session_identity="$(_crntw_repo_identity "$session_cwd")"

  # Same identity (main checkout OR any linked worktree of the SAME repo,
  # since --git-common-dir is shared across all of them) -> silent.
  if [[ -n "$session_identity" && "$session_identity" == "$file_identity" ]]; then
    return 0
  fi

  # Fresh silence marker for this session -> silent.
  local marker
  marker="$(_crntw_marker_path "$session_id")"
  if _crntw_marker_fresh "$marker"; then
    return 0
  fi

  local repo_root
  repo_root="$(dirname "$file_identity" 2>/dev/null)"
  cat <<MSG
WARN [cross-repo-nl-touch]: this session's project root does not match the
neural-lace repo (${repo_root}) that '${file_path}' belongs to.

Direct cross-repo edits to the harness repo from an unrelated session skip
every NL-local review discipline (plan-scoping, spec-freeze, harness-reviewer).
If this is friction/an idea rather than an intended harness change, the
canonical path is:

    nl-issue.sh "<one line describing what you noticed>"

(constitution §5 — cross-project capture; lands in the machine-wide
~/.claude/state/nl-issues.jsonl ledger and the weekly triage, no matter what
repo you run it from.)

If this cross-repo edit IS deliberate (an orchestrator dispatching across
repos, or you are intentionally hand-editing the harness from this checkout),
this is advisory only — nothing is blocked. To silence this warning for the
rest of this session, create a fresh marker:

    mkdir -p ~/.claude/state && date -u +%Y-%m-%dT%H:%M:%SZ > ~/.claude/state/cross-repo-nl-touch-ok-${session_id}.txt

(expires after 1 hour, same freshness convention as /grant-local-edit.)
MSG
  return 0
}

# ----------------------------------------------------------------------
# Main flow (only when executed directly with real hook input, i.e. not
# --self-test and not sourced).
# ----------------------------------------------------------------------
_crntw_main() {
  local input
  input="$(_crntw_load_input)"
  [[ -z "$input" ]] && exit 0

  local tool_name
  tool_name="$(_crntw_extract_field "$input" "tool_name")"
  case "$tool_name" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
  esac

  local file_path
  file_path="$(_crntw_extract_field "$input" "tool_input.file_path")"
  [[ -z "$file_path" ]] && exit 0

  local session_id="${CLAUDE_CODE_SESSION_ID:-unknown}"
  _crntw_check "$file_path" "$PWD" "$session_id" >&2
  exit 0
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" != "--self-test" ]]; then
  _crntw_main
fi

# ============================================================
# --self-test
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'crntwst')"
  if [[ -z "$TMP" || ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  echo "self-test: cross-repo-nl-touch-warn.sh"

  # ------------------------------------------------------------
  # Build a fixture "NL repo" (main checkout) with adapters/claude-code/
  # and a linked worktree of it, plus a wholly unrelated fixture repo.
  # ------------------------------------------------------------
  NL_MAIN="$TMP/nl-main"
  mkdir -p "$NL_MAIN/adapters/claude-code"
  ( cd "$NL_MAIN" && git init -q && git config user.email t@t.com && git config user.name t \
      && git config core.hooksPath "" \
      && echo x > adapters/claude-code/README.md && git add -A && git commit -q -m init )

  NL_WORKTREE="$TMP/nl-worktree"
  ( cd "$NL_MAIN" && git worktree add -q -b nl-wt-branch "$NL_WORKTREE" >/dev/null 2>&1 )

  UNRELATED="$TMP/unrelated-repo"
  mkdir -p "$UNRELATED"
  ( cd "$UNRELATED" && git init -q && git config user.email t@t.com && git config user.name t \
      && git config core.hooksPath "" \
      && echo x > some-file.md && git add -A && git commit -q -m init )

  NOGIT="$TMP/no-git-dir"
  mkdir -p "$NOGIT"

  export CRNTW_STATE_DIR_OVERRIDE="$TMP/state"
  mkdir -p "$CRNTW_STATE_DIR_OVERRIDE"

  SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  # _crntw_check and friends are already defined in THIS process (we are
  # executing inside this same script file's --self-test branch), so they
  # are directly callable below without re-sourcing.

  # ------------------------------------------------------------
  # (a) REQUIRED FP FIXTURE: legitimate NL session, main checkout, editing
  # its own repo -> SILENT.
  # ------------------------------------------------------------
  echo "Scenario (a): NL main-checkout session editing its own repo file -> SILENT (REQUIRED FP fixture)"
  OUT_A="$(_crntw_check "$NL_MAIN/adapters/claude-code/README.md" "$NL_MAIN" "sess-a")"
  if [[ -z "$OUT_A" ]]; then
    pass "main-checkout session editing its own file produces no warning"
  else
    fail "expected silence, got: $OUT_A"
  fi

  # ------------------------------------------------------------
  # (b) REQUIRED FP FIXTURE: legitimate NL session from a LINKED WORKTREE
  # editing an NL-repo file (possibly a file that lives in the main
  # checkout's working tree, e.g. an orchestrator editing shared docs) ->
  # SILENT, because --git-common-dir is shared.
  # ------------------------------------------------------------
  echo "Scenario (b): NL linked-worktree session editing an NL-repo file -> SILENT (REQUIRED FP fixture, orchestrator/worktree case)"
  mkdir -p "$NL_WORKTREE/adapters/claude-code"
  OUT_B="$(_crntw_check "$NL_WORKTREE/adapters/claude-code/README.md" "$NL_WORKTREE" "sess-b")"
  if [[ -z "$OUT_B" ]]; then
    pass "linked-worktree session editing an NL-repo file produces no warning"
  else
    fail "expected silence, got: $OUT_B"
  fi

  # ------------------------------------------------------------
  # (c) Cross-repo session: cwd is an UNRELATED repo, but the file_path
  # targets the NL repo directly -> WARN.
  # ------------------------------------------------------------
  echo "Scenario (c): unrelated-repo session editing an NL-repo file via absolute path -> WARN"
  OUT_C="$(_crntw_check "$NL_MAIN/adapters/claude-code/README.md" "$UNRELATED" "sess-c")"
  if printf '%s' "$OUT_C" | grep -q "WARN \[cross-repo-nl-touch\]"; then
    pass "unrelated-repo session editing an NL-repo file produces the WARN"
  else
    fail "expected a WARN, got: $OUT_C"
  fi
  if printf '%s' "$OUT_C" | grep -q "nl-issue.sh"; then
    pass "WARN names the nl-issue.sh remediation"
  else
    fail "expected nl-issue.sh remediation text in WARN, got: $OUT_C"
  fi

  # ------------------------------------------------------------
  # (d) No-git session editing a real NL-repo file -> WARN (most
  # suspicious case, must not be silently allow-by-default).
  # ------------------------------------------------------------
  echo "Scenario (d): no-git-ancestry session editing an NL-repo file -> WARN"
  OUT_D="$(_crntw_check "$NL_MAIN/adapters/claude-code/README.md" "$NOGIT" "sess-d")"
  if printf '%s' "$OUT_D" | grep -q "WARN \[cross-repo-nl-touch\]"; then
    pass "no-git session editing an NL-repo file produces the WARN"
  else
    fail "expected a WARN, got: $OUT_D"
  fi

  # ------------------------------------------------------------
  # (e) Session editing a file OUTSIDE any NL repo (ordinary unrelated
  # work) -> SILENT, this hook only ever speaks about NL-repo targets.
  # ------------------------------------------------------------
  echo "Scenario (e): session editing a file in an unrelated (non-NL) repo -> SILENT"
  OUT_E="$(_crntw_check "$UNRELATED/some-file.md" "$UNRELATED" "sess-e")"
  if [[ -z "$OUT_E" ]]; then
    pass "unrelated-repo-editing-its-own-file produces no warning"
  else
    fail "expected silence, got: $OUT_E"
  fi

  # ------------------------------------------------------------
  # (f) Fresh silence marker present -> SILENT even though (c)'s
  # condition holds.
  # ------------------------------------------------------------
  echo "Scenario (f): fresh silence marker suppresses the WARN"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$CRNTW_STATE_DIR_OVERRIDE/cross-repo-nl-touch-ok-sess-f.txt"
  OUT_F="$(_crntw_check "$NL_MAIN/adapters/claude-code/README.md" "$UNRELATED" "sess-f")"
  if [[ -z "$OUT_F" ]]; then
    pass "fresh marker silences the WARN"
  else
    fail "expected silence with a fresh marker, got: $OUT_F"
  fi

  # ------------------------------------------------------------
  # (g) Stale (>1h) marker -> WARN (freshness enforced, not a
  # forever-silence).
  # ------------------------------------------------------------
  echo "Scenario (g): stale (>1h) silence marker does NOT suppress the WARN"
  STALE_MARKER="$CRNTW_STATE_DIR_OVERRIDE/cross-repo-nl-touch-ok-sess-g.txt"
  echo "stale" > "$STALE_MARKER"
  OLD_TS=$(( $(date -u +%s 2>/dev/null || echo 0) - 7200 ))
  touch -d "@$OLD_TS" "$STALE_MARKER" 2>/dev/null || touch -t "$(date -u -r "$OLD_TS" '+%Y%m%d%H%M.%S' 2>/dev/null)" "$STALE_MARKER" 2>/dev/null || true
  OUT_G="$(_crntw_check "$NL_MAIN/adapters/claude-code/README.md" "$UNRELATED" "sess-g")"
  if printf '%s' "$OUT_G" | grep -q "WARN \[cross-repo-nl-touch\]"; then
    pass "stale marker does not suppress the WARN"
  else
    fail "expected a WARN despite the stale marker, got: $OUT_G"
  fi

  # ------------------------------------------------------------
  # (h) Full PreToolUse JSON round-trip via CLAUDE_TOOL_INPUT, exercising
  # _crntw_main's real invocation shape (not just _crntw_check directly) —
  # proves the end-to-end hook always exits 0 regardless of WARN/silent.
  # ------------------------------------------------------------
  echo "Scenario (h): real PreToolUse JSON round-trip always exits 0"
  JSON_INPUT="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$NL_MAIN/adapters/claude-code/README.md")"
  ( cd "$UNRELATED" && CLAUDE_TOOL_INPUT="$JSON_INPUT" CLAUDE_CODE_SESSION_ID="sess-h" bash "$SELF_ABS" >/tmp/crntw-h-stdout 2>/tmp/crntw-h-stderr )
  RC_H=$?
  if [[ "$RC_H" -eq 0 ]]; then
    pass "real hook invocation (cross-repo case) exits 0 (WARN, never block)"
  else
    fail "expected exit 0, got rc=$RC_H"
  fi
  if grep -q "WARN \[cross-repo-nl-touch\]" /tmp/crntw-h-stderr 2>/dev/null; then
    pass "real hook invocation emits the WARN to stderr"
  else
    fail "expected WARN text on stderr, got: $(cat /tmp/crntw-h-stderr 2>/dev/null)"
  fi
  rm -f /tmp/crntw-h-stdout /tmp/crntw-h-stderr

  # ------------------------------------------------------------
  # (i) Real PreToolUse JSON round-trip for the FP case (main-checkout
  # session) also exits 0 AND produces no stderr output.
  # ------------------------------------------------------------
  echo "Scenario (i): real PreToolUse JSON round-trip for the FP case is silent"
  JSON_INPUT_I="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$NL_MAIN/adapters/claude-code/README.md")"
  ( cd "$NL_MAIN" && CLAUDE_TOOL_INPUT="$JSON_INPUT_I" CLAUDE_CODE_SESSION_ID="sess-i" bash "$SELF_ABS" >/tmp/crntw-i-stdout 2>/tmp/crntw-i-stderr )
  RC_I=$?
  if [[ "$RC_I" -eq 0 ]] && [[ ! -s /tmp/crntw-i-stderr ]]; then
    pass "real hook invocation (FP case) exits 0 with empty stderr"
  else
    fail "expected exit 0 + empty stderr, got rc=$RC_I stderr=$(cat /tmp/crntw-i-stderr 2>/dev/null)"
  fi
  rm -f /tmp/crntw-i-stdout /tmp/crntw-i-stderr

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
