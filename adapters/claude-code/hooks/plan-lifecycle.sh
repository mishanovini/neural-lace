#!/bin/bash
# plan-lifecycle.sh
#
# PostToolUse hook handling the full lifecycle of plan files under
# `docs/plans/` (top-level — NOT under archive/):
#
#   1. Commit-on-creation warning. When a Write tool creates a new
#      plan file (the file did not exist before this Write), surface a
#      loud reminder that uncommitted plan files can be wiped by
#      concurrent sessions and must be committed immediately.
#
#   2. Auto-archival on terminal status. When an Edit or Write
#      changes the plan's `Status:` field from a non-terminal value
#      (ACTIVE / DEFERRED, etc.) to a terminal value (COMPLETED /
#      ABANDONED / SUPERSEDED), execute `git mv` to move the plan
#      file (and its `<slug>-evidence.md` companion if it exists)
#      into `docs/plans/archive/`. Emit a system message pointing
#      readers at the new path.
#
#      DEFERRED is NOT a terminal status. DEFERRED means "paused,
#      will resume" — auto-archiving would hide the plan from the
#      next session that's supposed to pick it back up. Terminal
#      means "the plan's life is over": COMPLETED / ABANDONED /
#      SUPERSEDED only.
#
# This is a PostToolUse hook. PostToolUse runs AFTER the tool already
# completed; we therefore never block, only annotate. Exit code is
# always 0 unless an unexpected error occurs (and even then we prefer
# to no-op rather than crash, since blocking after-the-fact is
# meaningless).
#
# Activation rules:
#   - Tool must be Edit or Write
#   - file_path must be under docs/plans/ (top-level)
#   - file_path must NOT already be under docs/plans/archive/
#   - file_path must end with .md
#   - file_path must not be a `*-evidence.md` companion (those don't
#     have Status fields and don't trigger lifecycle moves on their
#     own; they ride along with the parent plan when it archives)
#
# Status detection:
#   - Pre-edit content: `git show HEAD:<repo-relative-path>` if the
#     file is tracked, else "" (treated as non-existent / new)
#   - Post-edit content: read from disk
#   - Compare the `Status:` field. Trigger archival on
#     non-terminal -> terminal transition only.
#
# Bash 3.2 portability: avoid `declare -A`, `mapfile`, `${var,,}`,
# `&>>`, `[[ =~ ]]` with `BASH_REMATCH` of unbounded length. Stick to
# POSIX-ish constructs where possible.
#
# Self-test: invoke with `--self-test`. Creates a temp git repo,
# exercises creation warning, status transitions (active to terminal,
# active to active should NOT move, terminal to active should NOT
# move), evidence companion movement, and exits 0/1.

set -u

SCRIPT_NAME="plan-lifecycle.sh"

# ---------- helpers ----------------------------------------------------

# Normalize a path for matching: forward slashes only.
normalize_path() {
  printf '%s' "$1" | tr '\\' '/'
}

# Extract the Status value from a content blob (stdin). Returns
# uppercase token (ACTIVE / COMPLETED / DEFERRED / ABANDONED /
# SUPERSEDED / etc.) or empty if no Status line. Note: DEFERRED is
# a recognized status value but is NOT terminal (see is_terminal_status).
#
# We only look at the first matching line (plan files have one Status
# field at the top).
extract_status() {
  awk '
    /^Status:[[:space:]]*[A-Za-z][A-Za-z0-9_-]*/ {
      sub(/^Status:[[:space:]]*/, "", $0)
      sub(/[[:space:]].*$/, "", $0)
      print toupper($0)
      exit
    }
  '
}

# Returns 0 if the given status string is a terminal status, else 1.
# Terminal statuses trigger archival. DEFERRED is intentionally NOT
# terminal — DEFERRED means "paused, will resume", and auto-archiving
# would hide the plan from the next session that picks it back up.
is_terminal_status() {
  case "$1" in
    COMPLETED|ABANDONED|SUPERSEDED) return 0 ;;
    *) return 1 ;;
  esac
}

# Compute the repo-relative path for a (possibly absolute) file path.
# Echoes the relative path on stdout. If we can't resolve a repo root,
# echoes the input unchanged.
#
# On Git Bash for Windows there are two path namespaces — POSIX-ish
# (`/tmp/foo`) and Windows-mixed (`C:/Users/.../foo`). `git rev-parse`
# always returns the Windows-mixed form, while $PWD and tool input
# may use either. We try both forms when stripping the repo prefix
# AND fall back to using `realpath --relative-to` when possible.
to_repo_relative() {
  local path repo_root_mixed repo_root_posix abs_mixed abs_posix
  path="$1"
  repo_root_mixed=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -z "$repo_root_mixed" ]; then
    printf '%s' "$path"
    return
  fi
  repo_root_mixed=$(normalize_path "$repo_root_mixed")
  abs_mixed=$(normalize_path "$path")

  # If the path is relative (doesn't start with / or X:/), assume
  # it's already repo-relative.
  case "$abs_mixed" in
    /*|[A-Za-z]:/*) ;;
    *)
      printf '%s' "$abs_mixed"
      return
      ;;
  esac

  # Try direct prefix match (mixed form)
  case "$abs_mixed" in
    "$repo_root_mixed"/*)
      printf '%s' "${abs_mixed#"$repo_root_mixed"/}"
      return
      ;;
  esac

  # Try POSIX form on both sides via cygpath if available
  if command -v cygpath >/dev/null 2>&1; then
    repo_root_posix=$(cygpath -u "$repo_root_mixed" 2>/dev/null || echo "")
    abs_posix=$(cygpath -u "$abs_mixed" 2>/dev/null || echo "")
    if [ -n "$repo_root_posix" ] && [ -n "$abs_posix" ]; then
      case "$abs_posix" in
        "$repo_root_posix"/*)
          printf '%s' "${abs_posix#"$repo_root_posix"/}"
          return
          ;;
      esac
    fi
    # Or convert input to mixed form and retry
    abs_posix=$(cygpath -m "$abs_mixed" 2>/dev/null || echo "")
    if [ -n "$abs_posix" ]; then
      case "$abs_posix" in
        "$repo_root_mixed"/*)
          printf '%s' "${abs_posix#"$repo_root_mixed"/}"
          return
          ;;
      esac
    fi
  fi

  # Last-resort: use realpath
  if command -v realpath >/dev/null 2>&1; then
    local rel
    rel=$(realpath --relative-to="$repo_root_mixed" "$abs_mixed" 2>/dev/null || echo "")
    if [ -n "$rel" ] && [ "${rel#../}" = "$rel" ]; then
      printf '%s' "$rel"
      return
    fi
  fi

  # Could not resolve — return input unchanged. Caller will likely
  # fall back to the plain `mv` path.
  printf '%s' "$abs_mixed"
}

# Return the pre-edit content for a tracked file (git HEAD version).
# Echoes empty string if the file is not tracked at HEAD.
pre_edit_content() {
  local rel="$1"
  git show "HEAD:$rel" 2>/dev/null || true
}

# Run the lifecycle logic for one file_path. Used both by the
# real-invocation path and by --self-test.
#
# Args:
#   $1 — file_path (absolute or relative)
#   $2 — tool_name (Edit | Write)
#   $3 — pre-edit content (may be empty if file is new). For Edit,
#        the caller can use git HEAD; for Write, same.
#   $4 — post-edit content (current file contents on disk).
#
# Outputs to stderr (so it appears in tool output stream). Performs
# git mv when archival is triggered.
process_lifecycle_event() {
  local file_path tool_name pre_content post_content
  file_path="$1"
  tool_name="$2"
  pre_content="$3"
  post_content="$4"

  local norm
  norm=$(normalize_path "$file_path")

  # Activation guard: must be a top-level plan markdown file.
  case "$norm" in
    *docs/plans/archive/*) return 0 ;;
    *docs/plans/*.md) ;;
    *) return 0 ;;
  esac

  # Skip evidence companions
  case "$norm" in
    *-evidence.md) return 0 ;;
  esac

  # Compute repo-relative path for git operations
  local rel
  rel=$(to_repo_relative "$norm")

  # ---- (1) Commit-on-creation warning ----
  # Triggered when the file is new (no pre_content from git HEAD AND
  # the post_content exists). For Edit tool calls the file already
  # existed (Edit can't create files), so this is Write-only in
  # practice.
  if [ "$tool_name" = "Write" ] && [ -z "$pre_content" ] && [ -n "$post_content" ]; then
    cat >&2 <<EOF

==================================================================
PLAN LIFECYCLE — uncommitted plan file warning
==================================================================
A new plan file was just written but is NOT yet committed:

  $rel

Uncommitted plan files can be silently wiped by concurrent sessions
or git operations. Commit it now:

  git add "$rel" && git commit -m "plan: $(basename "${rel%.md}")"

(This warning fires once per plan-file creation. It does not block.)

EOF
  fi

  # ---- (2) Status-transition auto-archival ----
  local pre_status post_status
  pre_status=$(printf '%s\n' "$pre_content" | extract_status)
  post_status=$(printf '%s\n' "$post_content" | extract_status)

  # Only act on a non-terminal -> terminal transition. If pre_status
  # is empty (new file), treat it as non-terminal — but only act if
  # post_status is terminal AND the file actually exists on disk.
  if [ -z "$post_status" ]; then return 0; fi
  if ! is_terminal_status "$post_status"; then return 0; fi
  if [ -n "$pre_status" ] && is_terminal_status "$pre_status"; then
    # Already terminal pre-edit — no transition. (e.g. editing a
    # plan that's already COMPLETED — rare; archive will have moved
    # it already, so this branch is mostly defensive.)
    return 0
  fi

  # Preconditions for the move:
  if [ ! -f "$file_path" ]; then return 0; fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then return 0; fi

  # Compute target archive path. Keep the same basename.
  local repo_root archive_dir archive_path base evidence_src evidence_dest
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -z "$repo_root" ]; then return 0; fi
  archive_dir="$repo_root/docs/plans/archive"
  base=$(basename "$rel")
  archive_path="$archive_dir/$base"

  # If a file already exists at the target, don't clobber. Warn instead.
  if [ -e "$archive_path" ]; then
    cat >&2 <<EOF

==================================================================
PLAN LIFECYCLE — archive collision (no move)
==================================================================
Plan transitioned to $post_status but cannot be auto-archived:

  source: docs/plans/$base
  target: docs/plans/archive/$base (already exists)

Resolve manually: rename one of the two and re-flip Status.

EOF
    return 0
  fi

  mkdir -p "$archive_dir"

  # Perform the git mv. If the file is not tracked yet, fall back to
  # a plain `mv` + `git add` — git mv refuses to operate on untracked
  # files.
  local moved="no" mv_err
  if git ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
    if mv_err=$(git mv "$rel" "docs/plans/archive/$base" 2>&1); then
      moved="git"
    fi
  else
    if mv_err=$(mv "$file_path" "$archive_path" 2>&1) && git add "docs/plans/archive/$base" 2>/dev/null; then
      moved="plain"
    fi
  fi

  if [ "$moved" = "no" ]; then
    cat >&2 <<EOF

==================================================================
PLAN LIFECYCLE — archival failed
==================================================================
Plan transitioned to $post_status but git mv failed:

  $mv_err

Resolve manually: git mv "$rel" "docs/plans/archive/$base"

EOF
    return 0
  fi

  # Move evidence companion if present
  local evidence_rel evidence_base
  evidence_rel="${rel%.md}-evidence.md"
  evidence_base="${base%.md}-evidence.md"
  evidence_src="$repo_root/$evidence_rel"
  evidence_dest="$archive_dir/$evidence_base"
  if [ -f "$evidence_src" ] && [ ! -e "$evidence_dest" ]; then
    if git ls-files --error-unmatch "$evidence_rel" >/dev/null 2>&1; then
      git mv "$evidence_rel" "docs/plans/archive/$evidence_base" 2>/dev/null || true
    else
      mv "$evidence_src" "$evidence_dest" 2>/dev/null && git add "docs/plans/archive/$evidence_base" 2>/dev/null || true
    fi
  fi

  cat >&2 <<EOF

==================================================================
PLAN LIFECYCLE — auto-archived
==================================================================
Plan "$base" transitioned to $post_status and was moved to:

  docs/plans/archive/$base

Subsequent references should use the archive path. The git mv is
already staged — your next commit will capture the Status change
AND the rename atomically.

EOF
  return 0
}

# ---------- self-test --------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  set -u
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT

  cd "$TMP" || exit 2
  git init -q .
  git config user.email "selftest@example.test"
  git config user.name "selftest"
  mkdir -p docs/plans

  # ---- Scenario 1: creation warning fires ----
  cat > docs/plans/case1.md <<'EOP'
# Plan: Case 1
Status: ACTIVE
EOP
  OUT1=$(process_lifecycle_event "$TMP/docs/plans/case1.md" "Write" "" "$(cat docs/plans/case1.md)" 2>&1 || true)
  if ! printf '%s' "$OUT1" | grep -q "uncommitted plan file warning"; then
    echo "FAIL scenario 1: expected uncommitted-plan warning. Got:" >&2
    echo "$OUT1" >&2
    exit 1
  fi
  git add docs/plans/case1.md
  git commit -q -m "plan: case1"

  # ---- Scenario 2: ACTIVE -> COMPLETED triggers archival ----
  PRE2=$(git show HEAD:docs/plans/case1.md)
  cat > docs/plans/case1.md <<'EOP'
# Plan: Case 1
Status: COMPLETED
EOP
  POST2=$(cat docs/plans/case1.md)
  OUT2=$(process_lifecycle_event "$TMP/docs/plans/case1.md" "Edit" "$PRE2" "$POST2" 2>&1 || true)
  if ! printf '%s' "$OUT2" | grep -q "auto-archived"; then
    echo "FAIL scenario 2: expected auto-archive message. Got:" >&2
    echo "$OUT2" >&2
    exit 1
  fi
  if [ ! -f docs/plans/archive/case1.md ]; then
    echo "FAIL scenario 2: archive file missing." >&2
    exit 1
  fi
  if [ -f docs/plans/case1.md ]; then
    echo "FAIL scenario 2: source file still present after move." >&2
    exit 1
  fi
  # Verify git knows about the rename. `git status --porcelain` may
  # show "R " (pure rename), "RM" (rename + modified content), or the
  # decomposed "A  archive/foo.md" + "D  foo.md" pair, depending on
  # rename detection. Accept any of those.
  if ! git status --porcelain | grep -qE '(^R[ M] .*docs/plans/archive/case1\.md|^A  docs/plans/archive/case1\.md|^D  docs/plans/case1\.md)'; then
    echo "FAIL scenario 2: git did not stage the move. Status:" >&2
    git status --porcelain >&2
    exit 1
  fi
  git commit -q -m "archive case1"

  # ---- Scenario 3: ACTIVE -> ACTIVE (no Status change) — no move ----
  cat > docs/plans/case3.md <<'EOP'
# Plan: Case 3
Status: ACTIVE
EOP
  git add docs/plans/case3.md
  git commit -q -m "plan: case3"
  PRE3=$(git show HEAD:docs/plans/case3.md)
  cat > docs/plans/case3.md <<'EOP'
# Plan: Case 3
Status: ACTIVE

Some new content added.
EOP
  POST3=$(cat docs/plans/case3.md)
  OUT3=$(process_lifecycle_event "$TMP/docs/plans/case3.md" "Edit" "$PRE3" "$POST3" 2>&1 || true)
  if printf '%s' "$OUT3" | grep -q "auto-archived"; then
    echo "FAIL scenario 3: should NOT archive on ACTIVE->ACTIVE. Got:" >&2
    echo "$OUT3" >&2
    exit 1
  fi
  if [ ! -f docs/plans/case3.md ]; then
    echo "FAIL scenario 3: file should remain at source." >&2
    exit 1
  fi

  # ---- Scenario 4: terminal -> terminal (no transition) — no move ----
  # Build a plan that's already COMPLETED at HEAD, then "edit" it.
  cat > docs/plans/case4.md <<'EOP'
# Plan: Case 4
Status: COMPLETED
EOP
  git add docs/plans/case4.md
  git commit -q -m "plan: case4 already complete (synthetic)"
  PRE4=$(git show HEAD:docs/plans/case4.md)
  cat > docs/plans/case4.md <<'EOP'
# Plan: Case 4
Status: ABANDONED
EOP
  POST4=$(cat docs/plans/case4.md)
  OUT4=$(process_lifecycle_event "$TMP/docs/plans/case4.md" "Edit" "$PRE4" "$POST4" 2>&1 || true)
  if printf '%s' "$OUT4" | grep -q "auto-archived"; then
    echo "FAIL scenario 4: should NOT archive on terminal->terminal. Got:" >&2
    echo "$OUT4" >&2
    exit 1
  fi

  # Reset case4 for next scenarios (don't pollute working tree)
  rm -f docs/plans/case4.md
  git add -A
  git commit -q -m "cleanup case4 working state" 2>/dev/null || true

  # ---- Scenario 5: evidence companion moves with the plan ----
  cat > docs/plans/case5.md <<'EOP'
# Plan: Case 5
Status: ACTIVE
EOP
  cat > docs/plans/case5-evidence.md <<'EOP'
EVIDENCE BLOCK
Task ID: A.1
Runtime verification: bash -lc 'true'
EOP
  git add docs/plans/case5.md docs/plans/case5-evidence.md
  git commit -q -m "plan: case5 + evidence"
  PRE5=$(git show HEAD:docs/plans/case5.md)
  cat > docs/plans/case5.md <<'EOP'
# Plan: Case 5
Status: ABANDONED
EOP
  POST5=$(cat docs/plans/case5.md)
  OUT5=$(process_lifecycle_event "$TMP/docs/plans/case5.md" "Edit" "$PRE5" "$POST5" 2>&1 || true)
  if ! printf '%s' "$OUT5" | grep -q "auto-archived"; then
    echo "FAIL scenario 5: expected archive message. Got:" >&2
    echo "$OUT5" >&2
    exit 1
  fi
  if [ ! -f docs/plans/archive/case5.md ]; then
    echo "FAIL scenario 5: archived plan missing." >&2
    exit 1
  fi
  if [ ! -f docs/plans/archive/case5-evidence.md ]; then
    echo "FAIL scenario 5: evidence companion did not move." >&2
    exit 1
  fi

  # ---- Scenario 6: evidence-only edit does NOT trigger lifecycle ----
  # The filter targets the trailing `-evidence.md` exactly. A path
  # ending in `-evidence.md` should be a no-op regardless of content.
  cat > docs/plans/case6-evidence.md <<'EOP'
EVIDENCE BLOCK
Status: COMPLETED
EOP
  OUT6=$(process_lifecycle_event "$TMP/docs/plans/case6-evidence.md" "Write" "" "$(cat docs/plans/case6-evidence.md)" 2>&1 || true)
  if [ -n "$OUT6" ]; then
    echo "FAIL scenario 6: evidence file should be a no-op. Got:" >&2
    echo "$OUT6" >&2
    exit 1
  fi

  # ---- Scenario 7: archive-collision is detected ----
  cat > docs/plans/case7.md <<'EOP'
# Plan: Case 7
Status: ACTIVE
EOP
  mkdir -p docs/plans/archive
  cat > docs/plans/archive/case7.md <<'EOP'
# Plan: Case 7 (pre-existing archive)
Status: COMPLETED
EOP
  git add docs/plans/case7.md docs/plans/archive/case7.md
  git commit -q -m "plan: case7 (with archive collision)"
  PRE7=$(git show HEAD:docs/plans/case7.md)
  cat > docs/plans/case7.md <<'EOP'
# Plan: Case 7
Status: COMPLETED
EOP
  POST7=$(cat docs/plans/case7.md)
  OUT7=$(process_lifecycle_event "$TMP/docs/plans/case7.md" "Edit" "$PRE7" "$POST7" 2>&1 || true)
  if ! printf '%s' "$OUT7" | grep -q "archive collision"; then
    echo "FAIL scenario 7: expected archive-collision warning. Got:" >&2
    echo "$OUT7" >&2
    exit 1
  fi
  if [ ! -f docs/plans/case7.md ]; then
    echo "FAIL scenario 7: source should remain when collision detected." >&2
    exit 1
  fi

  # ---- Scenario 8: edits OUTSIDE docs/plans/ are ignored ----
  mkdir -p src
  cat > src/example.ts <<'EOP'
// Status: COMPLETED (this is just code; should NOT trigger archival)
export const x = 1
EOP
  OUT8=$(process_lifecycle_event "$TMP/src/example.ts" "Write" "" "$(cat src/example.ts)" 2>&1 || true)
  if [ -n "$OUT8" ]; then
    echo "FAIL scenario 8: non-plan file should be a no-op. Got:" >&2
    echo "$OUT8" >&2
    exit 1
  fi

  # ---- Scenario 9: edits to files already in archive/ are ignored ----
  OUT9=$(process_lifecycle_event "$TMP/docs/plans/archive/case5.md" "Edit" "$(cat docs/plans/archive/case5.md)" "$(cat docs/plans/archive/case5.md)" 2>&1 || true)
  if [ -n "$OUT9" ]; then
    echo "FAIL scenario 9: archive-dir file should be a no-op. Got:" >&2
    echo "$OUT9" >&2
    exit 1
  fi

  # ---- Scenario 10: ACTIVE -> DEFERRED does NOT archive ----
  # DEFERRED means "paused, will resume", not terminal. Auto-archiving
  # would hide the plan from the next session that picks it back up.
  cat > docs/plans/case10.md <<'EOP'
# Plan: Case 10
Status: ACTIVE
EOP
  git add docs/plans/case10.md
  git commit -q -m "plan: case10 active"
  PRE10=$(git show HEAD:docs/plans/case10.md)
  cat > docs/plans/case10.md <<'EOP'
# Plan: Case 10
Status: DEFERRED
EOP
  POST10=$(cat docs/plans/case10.md)
  OUT10=$(process_lifecycle_event "$TMP/docs/plans/case10.md" "Edit" "$PRE10" "$POST10" 2>&1 || true)
  if printf '%s' "$OUT10" | grep -q "auto-archived"; then
    echo "FAIL scenario 10: DEFERRED is not terminal; should NOT archive. Got:" >&2
    echo "$OUT10" >&2
    exit 1
  fi
  if [ ! -f docs/plans/case10.md ] || [ -f docs/plans/archive/case10.md ]; then
    echo "FAIL scenario 10: DEFERRED plan should remain in active dir, not archive." >&2
    exit 1
  fi

  echo "OK ($SCRIPT_NAME --self-test)"
  exit 0
fi

# ---------- main path --------------------------------------------------

# Read the tool invocation JSON. Same dual-source pattern other hooks
# use (CLAUDE_TOOL_INPUT env var OR stdin).
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [ -z "$INPUT" ] && [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL_NAME" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .file_path // ""' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

NORM=$(normalize_path "$FILE_PATH")
case "$NORM" in
  *docs/plans/*.md) ;;
  *) exit 0 ;;
esac
case "$NORM" in
  *docs/plans/archive/*) exit 0 ;;
  *-evidence.md) exit 0 ;;
esac

# Compute pre-edit content from git HEAD (best-effort).
REL=$(to_repo_relative "$NORM")
PRE=$(pre_edit_content "$REL")

# Post-edit content: read from disk (PostToolUse runs after the write
# completed, so disk reflects the new state).
if [ -f "$FILE_PATH" ]; then
  POST=$(cat "$FILE_PATH" 2>/dev/null || echo "")
else
  POST=""
fi

process_lifecycle_event "$FILE_PATH" "$TOOL_NAME" "$PRE" "$POST"

exit 0
