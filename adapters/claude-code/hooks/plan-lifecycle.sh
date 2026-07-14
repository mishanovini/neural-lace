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
#      DEFERRED / ABANDONED / SUPERSEDED), execute `git mv` to move
#      the plan file (and its `<slug>-evidence.md` companion if it
#      exists) into `docs/plans/archive/`. Emit a system message
#      pointing readers at the new path.
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
# Target-repo resolution (2026-06-12; incident observed 2026-06-11 —
# same class as scope-enforcement-gate's HARNESS-GAP-47 fix):
#   ALL git operations (repo-root resolution, HEAD content reads,
#   git ls-files / mv / add) run against the repo CONTAINING the edited
#   plan file — derived from tool_input.file_path via
#   `git -C "$(dirname <file>)" rev-parse --show-toplevel` — NEVER
#   against the hook process's cwd (the session root). Pre-fix, a
#   session rooted in repo A that flipped Status on a plan inside repo B
#   (e.g. a sibling project's worktree) archived the plan into REPO A:
#   the cross-repo path fell through to_repo_relative() unchanged,
#   `git ls-files` (in A) reported it "untracked", and the plain-mv
#   fallback physically moved B's plan into A's docs/plans/archive/ and
#   staged it there — deleting it from the repo that owned it. See the
#   "Target-repo resolution" header section in scope-enforcement-gate.sh
#   for the sibling fix on command-subject hooks, and FM-032 in
#   docs/failure-modes.md for the class. Self-test scenario 10 covers
#   the cross-repo case.
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

# Resolved ONCE at load time, before anything else runs a `cd` (the
# --self-test path below `cd`s into a synthetic fixture repo for its
# scenarios) — BASH_SOURCE[0] may be a path RELATIVE to the invocation
# cwd, and resolving it lazily inside a function called AFTER a `cd`
# elsewhere in this same process silently breaks (dirname/cd against the
# wrong base). emit_task_done_progress_log_events uses this pre-resolved
# absolute path to locate scripts/progress-log.sh instead of re-deriving
# BASH_SOURCE[0] at call time.
_PL_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ---------- helpers ----------------------------------------------------

# Normalize a path for matching: forward slashes only.
normalize_path() {
  printf '%s' "$1" | tr '\\' '/'
}

# Extract the Status value from a content blob (stdin). Returns
# uppercase token (ACTIVE / COMPLETED / DEFERRED / ABANDONED /
# SUPERSEDED / etc.) or empty if no Status line.
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
# Terminal statuses trigger archival.
is_terminal_status() {
  case "$1" in
    COMPLETED|DEFERRED|ABANDONED|SUPERSEDED) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve the toplevel of the git repo CONTAINING the given file path —
# NOT the hook process's cwd. PostToolUse hooks run with the SESSION's
# cwd, which may be a different repo than the one the edited plan file
# lives in (e.g. a session rooted in one repo editing a plan inside a
# sibling project's worktree). Deriving the archival target from cwd
# moved a plan into the WRONG repo — see the header "Target-repo
# resolution" section. Echoes the repo root (git's mixed form on
# Windows), or "" when the file is not inside a git work tree.
resolve_file_repo_root() {
  local dir
  dir=$(dirname "$1")
  [ -d "$dir" ] || { printf '%s' ""; return; }
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true
}

# Compute the repo-relative path for a (possibly absolute) file path,
# relative to the CALLER-SUPPLIED repo root ($2) — the root of the repo
# containing the file, from resolve_file_repo_root(). Echoes the
# relative path on stdout. If the supplied root is empty, echoes the
# input unchanged.
#
# On Git Bash for Windows there are two path namespaces — POSIX-ish
# (`/tmp/foo`) and Windows-mixed (`C:/Users/.../foo`). `git rev-parse`
# always returns the Windows-mixed form, while $PWD and tool input
# may use either. We try both forms when stripping the repo prefix
# AND fall back to using `realpath --relative-to` when possible.
to_repo_relative() {
  local path repo_root_mixed repo_root_posix abs_mixed abs_posix
  path="$1"
  repo_root_mixed="${2:-}"
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

# Return the pre-edit content for a tracked file (git HEAD version),
# evaluated in the repo that contains the file ($1 = that repo's root,
# from resolve_file_repo_root(); $2 = repo-relative path). Echoes empty
# string if the root is empty or the file is not tracked at HEAD.
pre_edit_content() {
  local root="$1" rel="$2"
  [ -z "$root" ] && return 0
  git -C "$root" show "HEAD:$rel" 2>/dev/null || true
}

# ---------- progress-log emission (ask-rooted-workstreams-p1 Task 1) --------
#
# Walking-skeleton splice: observe a genuine "- [ ] N." -> "- [x] N."
# transition between pre-edit and post-edit plan content and emit ONE
# task_done progress-log event per newly-checked task, via
# scripts/progress-log.sh (hooks/lib/progress-log-lib.sh's pl_emit). This
# NEVER flips a checkbox itself and never adds a second done-bit — it only
# OBSERVES a flip the task-verifier already made (constraint 6: verifier
# monopoly preserved). Best-effort, never blocks (constraint 5): every
# failure path is swallowed with `|| true`.

# extract_checked_task_ids — print one task number per line for every
# "- [x] N." / "- [X] N." line in a plan-file content blob (stdin).
extract_checked_task_ids() {
  awk '
    /^- \[[xX]\][ \t]*[0-9]+\./ {
      line = $0
      sub(/^- \[[xX]\][ \t]*/, "", line)
      sub(/\..*$/, "", line)
      print line
    }
  '
}

# extract_ask_id — print the plan header's `ask-id: <token>` value (first
# match) from a plan-file content blob (stdin), or empty if absent. Every
# pre-existing plan lacks this field (Task 10 adds it going forward) —
# absence is a first-class, non-fatal case: the event still lands (see
# emit_task_done_progress_log_events), just in the "unlinked" per-ask log
# file (hooks/lib/progress-log-lib.sh's pl_path_for fallback) rather than
# being dropped. A full orphan-lane reattachment (matching an unlinked
# event back to an ask once linkage appears) is Task 2/12's job.
extract_ask_id() {
  awk '
    /^ask-id:[[:space:]]*[^[:space:]]+/ {
      sub(/^ask-id:[[:space:]]*/, "", $0)
      sub(/[[:space:]].*$/, "", $0)
      print $0
      exit
    }
  '
}

# emit_task_done_progress_log_events <repo_root> <rel-path> <pre> <post>
#   Diffs the checked-task-id sets between pre and post content; for every
# NEWLY checked task number (present in post, absent in pre — a re-save
# with no new flips naturally produces an empty diff and emits nothing,
# satisfying the "distinguish a fresh flip from a re-save" integration
# point), emits one task_done event. Resolves ask-id from the plan header
# in the POST content (the just-written version). PROGRESS_LOG_CLI is
# resolved once, relative to this hook's own location (mirrors the
# resolution style other splices in this repo use for sibling scripts).
emit_task_done_progress_log_events() {
  local repo_root="$1" rel="$2" pre="$3" post="$4"

  local ask_id
  ask_id="$(printf '%s\n' "$post" | extract_ask_id)"

  local post_ids
  post_ids="$(printf '%s\n' "$post" | extract_checked_task_ids)"
  [ -n "$post_ids" ] || return 0

  local pre_ids
  pre_ids="$(printf '%s\n' "$pre" | extract_checked_task_ids)"

  local slug
  slug="$(basename "$rel")"
  slug="${slug%.md}"

  local progress_log_cli
  progress_log_cli="$_PL_HOOK_DIR/../scripts/progress-log.sh"
  [ -f "$progress_log_cli" ] || return 0

  local evidence_link="$repo_root/$rel"

  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    if printf '%s\n' "$pre_ids" | grep -qxF "$n"; then
      continue  # already checked pre-edit -- not a fresh flip, no-op
    fi
    bash "$progress_log_cli" emit \
      --type task_done \
      --ask "$ask_id" \
      --plan-slug "$slug" \
      --task-id "$n" \
      --summary "task $n verified done" \
      --evidence-link "$evidence_link" \
      --emitter plan-lifecycle \
      >/dev/null 2>&1 || true
  done <<TASK_IDS_EOF
$post_ids
TASK_IDS_EOF

  return 0
}

# ---------- progress-log emission (ask-rooted-workstreams-p1 Task 6a) ------
#
# Plan-amendment splice: detect a genuine AMENDMENT to an ACTIVE plan --
# either a newly-introduced task line or an edited `## Scope` section -- and
# emit ONE plan_amended event per distinct delta found in a single edit.
#
# REUSE NOTE: this is the same "new task line" principle
# adapters/claude-code/hooks/plan-edit-validator.sh's check_docs_impact_warn
# already established for its Docs-impact WARN (a task line is "new" when
# its task-id token has no counterpart in the prior content). That function
# only ever sees an EDIT's old_string/new_string fragment, so it falls back
# to a substring search (`grep -qF "$tid" <<< "$old_content"`) across the
# whole prior file. This hook always has the FULL pre/post plan content (see
# emit_task_done_progress_log_events above), so it diffs task-id SETS
# instead -- the same technique this file already uses for task_done -- which
# is strictly more precise than a substring search for the plain-numeric ids
# ("1.", "6.") this technique would otherwise risk false-negating against
# (a bare "6" substring-matches inside "2026-07-10" all over a plan file;
# check_docs_impact_warn's own ids are letter-prefixed ("A.1"/"F.2b"), which
# happens to make that collision rarer for ITS callers but not for ours).
# Task-id token grammar below accepts BOTH conventions live in docs/plans/
# today (verified 2026-07-12): plain-numeric ("1", "6") and lettered
# ("A.1", "B.0", "D.2", "F.2b" -- optional letter-prefix + mandatory dot,
# then digits, then an optional trailing letter, repeatable).

# extract_all_task_line_ids -- print one task-id token per line for EVERY
# checkbox task line ("- [ ] " or "- [x]"/"- [X]"), regardless of check
# state (unlike extract_checked_task_ids above, which only looks at checked
# boxes -- amendment cares about a task line EXISTING, not its check state).
extract_all_task_line_ids() {
  awk '
    /^- \[[ xX]\][ \t]+/ {
      line = $0
      sub(/^- \[[ xX]\][ \t]+/, "", line)
      if (match(line, /^([A-Za-z]+\.)?[0-9]+[A-Za-z]?(\.[0-9]+[A-Za-z]?)*/)) {
        print substr(line, RSTART, RLENGTH)
      }
    }
  '
}

# extract_scope_section -- print the body of the plan's `## Scope` section
# (between the `## Scope` heading and the next `## ` heading), or empty if
# absent. Mirrors plan-edit-validator.sh's check_backlog_absorption_warn
# section-extraction awk idiom.
extract_scope_section() {
  awk '
    /^##[[:space:]]*Scope[[:space:]]*$/ { insec=1; next }
    /^##[[:space:]]/ { insec=0 }
    insec { print }
  '
}

# compute_content_hash <string> -- portable best-effort content hash for
# --dedup-extra values (mirrors progress-log-lib.sh's private _pl_hash;
# duplicated here rather than sourced because this hook shells out to
# scripts/progress-log.sh as its own CLI process for every emission --
# same one-process-per-emission convention emit_task_done_progress_log_events
# above already follows -- rather than sourcing the writer lib in-process).
compute_content_hash() {
  local s="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$s" | sha1sum 2>/dev/null | awk '{print $1}' && return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$s" | openssl dgst -sha1 2>/dev/null | awk '{print $NF}' && return 0
  fi
  printf '%s' "$s" | cksum 2>/dev/null | awk '{print $1"-"$2}'
}

# _amendment_state_dir -- resolve the progress-log state dir with the SAME
# order progress-log-lib.sh's pl_state_dir uses, so a caller that sandboxes
# the progress log (this file's own --self-test exports
# PROGRESS_LOG_STATE_DIR) automatically sandboxes the debounce files below.
_amendment_state_dir() {
  if [ -n "${PROGRESS_LOG_STATE_DIR:-}" ]; then
    printf '%s' "$PROGRESS_LOG_STATE_DIR"; return 0
  fi
  if [ "${HARNESS_SELFTEST:-0}" = "1" ]; then
    printf '%s/progress-log-selftest/%s' "${TMPDIR:-/tmp}" "$$"; return 0
  fi
  printf '%s/.claude/state/progress-logs' "${HOME:-$PWD}"
}

# _amendment_replay_token <slug> <delta_hash> -- the recurrence
# discriminator for the plan_amended dedup key (FINDING 4, 2026-07-14
# ask-splice review panel).
#
# THE PROBLEM. The key hashed the FULL RESULTING SCOPE, so editing the scope
# back to a PREVIOUSLY-SEEN exact state dropped a genuine amendment: in the
# sequence A->A,B / A,B->A / A->A,B, the 3rd edit's post-scope equals the
# 1st's and collided with it. Hashing the pre->post DELTA instead is
# necessary but NOT sufficient -- in that same sequence the 1st and 3rd
# transitions are textually IDENTICAL in BOTH pre and post, so a pure
# content hash still collides. Some time-varying component is required.
#
# WHY NOT A WALL-CLOCK BUCKET (floor(now/N)): a bucket has BOUNDARIES, and a
# hook re-firing for ONE edit milliseconds later can straddle one -- which
# would emit a spurious DUPLICATE plan_amended. Same trap, same fix as
# workstreams-emit.sh's `_dispatch_replay_token` (Finding 2): debounce
# anchored at the FIRST fire, so there is no boundary to straddle.
#
# The first fire for a given (slug, delta_hash) records `<epoch> <token>`
# and returns that token; any re-fire within
# AMENDMENT_REPLAY_DEBOUNCE_SECONDS (default 30) returns the SAME token (a
# replay of one edit -> deduped). A later edit that happens to reproduce the
# same delta mints a NEW token -> a genuinely distinct amendment. Never
# blocks: an unwritable state dir or missing `date` degrades to a
# conservative constant, never a crash.
#
# SIZING THE WINDOW (30s): it must exceed the wall-clock gap between two
# fires of ONE edit -- and that gap is NOT sub-second, because each fire
# forks progress-log.sh (bash + git + sha1sum), which costs SECONDS on the
# Windows/Git-Bash target (a 5s window was measurably too tight and let a
# replay mint a fresh token). Two genuinely-distinct scope edits that revert
# and reproduce the exact same state inside 30s are implausible, so the
# window stays far from the other bound.
# NOTE: every variable below is `local`. Bash uses DYNAMIC scoping, so a
# bare assignment here would reach up and clobber the CALLER's same-named
# local -- and this function is called from
# emit_plan_amended_progress_log_events, which has its own `slug` and `dir`.
_amendment_replay_token() {
  local slug="$1" delta_hash="$2"
  local now; now=$(date -u +%s 2>/dev/null)
  [ -n "$now" ] || { printf 'noclock'; return 0; }

  local debounce="${AMENDMENT_REPLAY_DEBOUNCE_SECONDS:-30}"
  local adir; adir="$(_amendment_state_dir)"
  mkdir -p "$adir" 2>/dev/null || { printf '%s' "$now"; return 0; }

  local key; key="$(compute_content_hash "${slug}|${delta_hash}" | cut -c1-16)"
  local f="$adir/.amend-replay-$key"

  local prev_ts="" prev_token=""
  if [ -f "$f" ]; then
    read -r prev_ts prev_token <"$f" 2>/dev/null || true
    case "$prev_ts" in
      ''|*[!0-9]*) : ;;
      *)
        if [ -n "$prev_token" ] && [ $(( now - prev_ts )) -le "$debounce" ] \
           && [ $(( now - prev_ts )) -ge 0 ]; then
          # Replay of the SAME edit -> reuse the token. Window stays
          # anchored at the first fire (never refreshed).
          printf '%s' "$prev_token"
          return 0
        fi
        ;;
    esac
  fi

  printf '%s %s\n' "$now" "$now" >"$f" 2>/dev/null || true
  printf '%s' "$now"
  return 0
}

# emit_plan_amended_progress_log_events <repo_root> <rel-path> <pre> <post>
#   Emits up to two plan_amended events for one edit: one for newly-
# introduced task lines (summary "+task <ids>"), one for an edited `## Scope`
# section (summary "scope delta"). Each is deduped by
# plan_slug + content-hash-of-its-own-delta (Task 2 table's --dedup-extra
# convention), so a SECOND, DIFFERENT amendment in a later edit is a
# genuinely distinct event (new delta -> new hash) while re-saving the
# IDENTICAL delta (e.g. a hook replay) is a no-op.
emit_plan_amended_progress_log_events() {
  local repo_root="$1" rel="$2" pre="$3" post="$4"

  # A brand-new plan file (no pre-edit content at all) is a CREATION, not an
  # amendment -- every one of its initial task lines would otherwise look
  # "new" against an empty pre and spuriously burst plan_amended events on
  # the plan's very first commit. Amendment tracking applies only to an
  # EXISTING plan gaining tasks/scope after the fact.
  [ -n "$pre" ] || return 0

  # Scope of this splice (Task 6a spec): ACTIVE plans only.
  local post_status
  post_status="$(printf '%s\n' "$post" | extract_status)"
  [ "$post_status" = "ACTIVE" ] || return 0

  local ask_id
  ask_id="$(printf '%s\n' "$post" | extract_ask_id)"

  local slug
  slug="$(basename "$rel")"
  slug="${slug%.md}"

  local progress_log_cli
  progress_log_cli="$_PL_HOOK_DIR/../scripts/progress-log.sh"
  [ -f "$progress_log_cli" ] || return 0

  local evidence_link="$repo_root/$rel"

  # ---- (a) newly-introduced task lines ----
  local post_ids pre_ids new_ids n
  post_ids="$(printf '%s\n' "$post" | extract_all_task_line_ids)"
  pre_ids="$(printf '%s\n' "$pre" | extract_all_task_line_ids)"
  new_ids=""
  if [ -n "$post_ids" ]; then
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      if ! printf '%s\n' "$pre_ids" | grep -qxF "$n"; then
        new_ids="$new_ids$n,"
      fi
    done <<TASK_AMEND_IDS_EOF
$post_ids
TASK_AMEND_IDS_EOF
  fi
  new_ids="${new_ids%,}"

  if [ -n "$new_ids" ]; then
    local task_hash
    task_hash="$(compute_content_hash "newtasks:$new_ids")"
    bash "$progress_log_cli" emit \
      --type plan_amended \
      --ask "$ask_id" \
      --plan-slug "$slug" \
      --summary "+task $new_ids" \
      --evidence-link "$evidence_link" \
      --emitter plan-lifecycle \
      --dedup-extra "$task_hash" \
      >/dev/null 2>&1 || true
  fi

  # ---- (b) ## Scope section delta ----
  local pre_scope post_scope
  pre_scope="$(printf '%s\n' "$pre" | extract_scope_section)"
  post_scope="$(printf '%s\n' "$post" | extract_scope_section)"
  if [ -n "$post_scope" ] && [ "$pre_scope" != "$post_scope" ]; then
    # FINDING 4 fix (2026-07-14 ask-splice review panel): hash the pre->post
    # DELTA, not just post_scope (the original bug: returning the scope to a
    # previously-seen exact post-state collided with the earlier amendment's
    # key), PLUS a replay-debounce token (see _amendment_replay_token above)
    # so even a repeat of the IDENTICAL delta (same pre AND post -- e.g.
    # amendment 1 and amendment 3 in an A->A,B / A,B->A / A->A,B sequence)
    # still gets a genuinely distinct key, while a hook re-fire for ONE edit
    # still dedups.
    local scope_hash scope_delta scope_token
    scope_delta="$(compute_content_hash "scope-delta:${pre_scope}$(printf '\036')${post_scope}")"
    scope_token="$(_amendment_replay_token "$slug" "$scope_delta")"
    scope_hash="$(compute_content_hash "scope-delta:${scope_delta}:${scope_token}")"
    bash "$progress_log_cli" emit \
      --type plan_amended \
      --ask "$ask_id" \
      --plan-slug "$slug" \
      --summary "scope delta" \
      --evidence-link "$evidence_link" \
      --emitter plan-lifecycle \
      --dedup-extra "$scope_hash" \
      >/dev/null 2>&1 || true
  fi

  return 0
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
  # archive/ AND deferred/ are resting places — never re-act on files there.
  case "$norm" in
    *docs/plans/archive/*) return 0 ;;
    *docs/plans/deferred/*) return 0 ;;
    *docs/plans/*.md) ;;
    *) return 0 ;;
  esac

  # Skip evidence companions
  case "$norm" in
    *-evidence.md) return 0 ;;
  esac

  # Resolve the repo CONTAINING the edited file (never the process cwd —
  # see the header "Target-repo resolution" section), then compute the
  # repo-relative path for git operations against THAT root.
  local file_repo_root rel
  file_repo_root=$(resolve_file_repo_root "$norm")
  rel=$(to_repo_relative "$norm" "$file_repo_root")

  # ---- (0) Progress-log emission: task-verifier flip -> task_done event ----
  # (ask-rooted-workstreams-p1 Task 1 walking skeleton.) Fires on every
  # Edit/Write reaching this point regardless of Status transition — a task
  # can be flipped independently of any archival move.
  emit_task_done_progress_log_events "$file_repo_root" "$rel" "$pre_content" "$post_content"

  # ---- (0b) Progress-log emission: plan amendment -> plan_amended event ----
  # (ask-rooted-workstreams-p1 Task 6a.) Added ALONGSIDE the task_done splice
  # above -- it does not replace or alter it. Fires on every Edit/Write
  # reaching this point; the function itself gates on ACTIVE status and on
  # this not being a fresh plan creation.
  emit_plan_amended_progress_log_events "$file_repo_root" "$rel" "$pre_content" "$post_content"

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
or git operations. Commit it now (rooted in the plan's own repo —
\`git -C ""\` degrades to cwd when the file is outside any repo):

  git -C "$file_repo_root" add "$rel" && git -C "$file_repo_root" commit -m "plan: $(basename "${rel%.md}")"

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

  # Preconditions for the move: the file must exist and must live inside
  # a git work tree (the FILE's work tree — the process cwd is
  # deliberately irrelevant here).
  if [ ! -f "$file_path" ]; then return 0; fi
  if [ -z "$file_repo_root" ]; then return 0; fi

  # Compute target path. Keep the same basename.
  # DESTINATION SPLIT (ADR 051 / Misha 2026-06-04): DEFERRED is terminal for
  # EDITING (no more edits expected → the plan rests) but NOT done for BUILDING
  # (the work is still intended). So DEFERRED routes to docs/plans/deferred/ —
  # the "intended but not currently active" category, a plan-level backlog —
  # NOT to archive/. COMPLETED / ABANDONED / SUPERSEDED are genuinely done-with
  # → archive/.
  local repo_root archive_dir archive_path base evidence_src evidence_dest dest_subdir
  repo_root="$file_repo_root"
  if [ "$post_status" = "DEFERRED" ]; then dest_subdir="deferred"; else dest_subdir="archive"; fi
  archive_dir="$repo_root/docs/plans/$dest_subdir"
  base=$(basename "$rel")
  archive_path="$archive_dir/$base"

  # If a file already exists at the target, don't clobber. Warn instead.
  if [ -e "$archive_path" ]; then
    cat >&2 <<EOF

==================================================================
PLAN LIFECYCLE — $dest_subdir collision (no move)
==================================================================
Plan transitioned to $post_status but cannot be auto-moved:

  source: docs/plans/$base
  target: docs/plans/$dest_subdir/$base (already exists)

Resolve manually: rename one of the two and re-flip Status.

EOF
    return 0
  fi

  mkdir -p "$archive_dir"

  # Perform the git mv. If the file is not tracked yet, fall back to
  # a plain `mv` + `git add` — git mv refuses to operate on untracked
  # files.
  local moved="no" mv_err
  if git -C "$repo_root" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
    if mv_err=$(git -C "$repo_root" mv "$rel" "docs/plans/$dest_subdir/$base" 2>&1); then
      moved="git"
    fi
  else
    if mv_err=$(mv "$file_path" "$archive_path" 2>&1) && git -C "$repo_root" add "docs/plans/$dest_subdir/$base" 2>/dev/null; then
      moved="plain"
    fi
  fi

  if [ "$moved" = "no" ]; then
    cat >&2 <<EOF

==================================================================
PLAN LIFECYCLE — move failed
==================================================================
Plan transitioned to $post_status but git mv failed:

  $mv_err

Resolve manually: git -C "$repo_root" mv "$rel" "docs/plans/$dest_subdir/$base"

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
    if git -C "$repo_root" ls-files --error-unmatch "$evidence_rel" >/dev/null 2>&1; then
      git -C "$repo_root" mv "$evidence_rel" "docs/plans/$dest_subdir/$evidence_base" 2>/dev/null || true
    else
      mv "$evidence_src" "$evidence_dest" 2>/dev/null && git -C "$repo_root" add "docs/plans/$dest_subdir/$evidence_base" 2>/dev/null || true
    fi
  fi

  local dest_label
  if [ "$dest_subdir" = "deferred" ]; then
    dest_label="moved to the DEFERRED (intended-but-not-active) area"
  else
    dest_label="auto-archived"
  fi
  cat >&2 <<EOF

==================================================================
PLAN LIFECYCLE — $dest_label
==================================================================
Plan "$base" transitioned to $post_status and was moved to:

  docs/plans/$dest_subdir/$base

Subsequent references should use that path. The git mv is already
staged — your next commit will capture the Status change AND the
rename atomically.

EOF
  return 0
}

# ---------- self-test --------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  set -u
  TMP=$(mktemp -d)
  OTHER=$(mktemp -d)
  trap 'rm -rf "$TMP" "$OTHER"' EXIT

  # Sandbox EVERY progress-log emission this self-test triggers (constraint
  # 4): the splice shells out to scripts/progress-log.sh, which resolves its
  # state dir via PROGRESS_LOG_STATE_DIR/HARNESS_SELFTEST — without this
  # export, running `plan-lifecycle.sh --self-test` on a real machine would
  # write task_done fixtures into the OPERATOR's real
  # ~/.claude/state/progress-logs.
  export HARNESS_SELFTEST=1
  export PROGRESS_LOG_STATE_DIR="$TMP/progress-logs"
  mkdir -p "$PROGRESS_LOG_STATE_DIR"

  cd "$TMP" || exit 2
  git init -q .
  git config core.hooksPath ""  # don't fire machine-global harness git hooks in fixtures
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
Status: COMPLETED
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

  # ---- Scenario 5b: DEFERRED routes to deferred/ (NOT archive/) ----
  # DEFERRED is terminal-for-editing but NOT done-for-building, so it
  # belongs in the intended-but-not-active area, not archive/.
  cat > docs/plans/case5b.md <<'EOP'
# Plan: Case 5b
Status: ACTIVE
EOP
  cat > docs/plans/case5b-evidence.md <<'EOP'
EVIDENCE BLOCK
Task ID: B.1
Runtime verification: bash -lc 'true'
EOP
  git add docs/plans/case5b.md docs/plans/case5b-evidence.md
  git commit -q -m "plan: case5b + evidence"
  PRE5B=$(git show HEAD:docs/plans/case5b.md)
  cat > docs/plans/case5b.md <<'EOP'
# Plan: Case 5b
Status: DEFERRED
EOP
  POST5B=$(cat docs/plans/case5b.md)
  OUT5B=$(process_lifecycle_event "$TMP/docs/plans/case5b.md" "Edit" "$PRE5B" "$POST5B" 2>&1 || true)
  if ! printf '%s' "$OUT5B" | grep -q "DEFERRED (intended-but-not-active)"; then
    echo "FAIL scenario 5b: expected deferred-area message. Got:" >&2
    echo "$OUT5B" >&2
    exit 1
  fi
  if [ ! -f docs/plans/deferred/case5b.md ]; then
    echo "FAIL scenario 5b: deferred plan not in docs/plans/deferred/." >&2
    exit 1
  fi
  if [ -f docs/plans/archive/case5b.md ]; then
    echo "FAIL scenario 5b: DEFERRED plan wrongly went to archive/." >&2
    exit 1
  fi
  if [ ! -f docs/plans/deferred/case5b-evidence.md ]; then
    echo "FAIL scenario 5b: evidence companion did not move to deferred/." >&2
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

  # ---- Scenario 10: plan file in a DIFFERENT repo than the cwd ----
  # The hook's process cwd stays in $TMP (the "session repo") while the
  # edited plan lives in $OTHER (a sibling repo, e.g. another project's
  # worktree). Regression test for the cross-repo mis-archival (header
  # "Target-repo resolution" section / FM-032): the archival must land
  # in $OTHER/docs/plans/archive/, stage in $OTHER, and leave the
  # session repo ($TMP) completely untouched.
  git -C "$OTHER" init -q
  git -C "$OTHER" config user.email "selftest@example.test"
  git -C "$OTHER" config user.name "selftest"
  mkdir -p "$OTHER/docs/plans"
  cat > "$OTHER/docs/plans/case10.md" <<'EOP'
# Plan: Case 10
Status: ACTIVE
EOP
  git -C "$OTHER" add docs/plans/case10.md
  git -C "$OTHER" commit -q -m "plan: case10"
  PRE10=$(git -C "$OTHER" show HEAD:docs/plans/case10.md)
  cat > "$OTHER/docs/plans/case10.md" <<'EOP'
# Plan: Case 10
Status: COMPLETED
EOP
  POST10=$(cat "$OTHER/docs/plans/case10.md")
  # NOTE: cwd is still $TMP — that is the point of this scenario.
  OUT10=$(process_lifecycle_event "$OTHER/docs/plans/case10.md" "Edit" "$PRE10" "$POST10" 2>&1 || true)
  if ! printf '%s' "$OUT10" | grep -q "auto-archived"; then
    echo "FAIL scenario 10: expected auto-archive message. Got:" >&2
    echo "$OUT10" >&2
    exit 1
  fi
  if [ ! -f "$OTHER/docs/plans/archive/case10.md" ]; then
    echo "FAIL scenario 10: plan not archived in ITS OWN repo." >&2
    exit 1
  fi
  if [ -e "$TMP/docs/plans/archive/case10.md" ]; then
    echo "FAIL scenario 10: plan wrongly archived into the SESSION repo (cwd)." >&2
    exit 1
  fi
  if [ -f "$OTHER/docs/plans/case10.md" ]; then
    echo "FAIL scenario 10: source file still present in target repo." >&2
    exit 1
  fi
  if ! git -C "$OTHER" status --porcelain | grep -qE '(^R[ M] .*docs/plans/archive/case10\.md|^A  docs/plans/archive/case10\.md|^D  docs/plans/case10\.md)'; then
    echo "FAIL scenario 10: move not staged in the plan's own repo. Status:" >&2
    git -C "$OTHER" status --porcelain >&2
    exit 1
  fi
  if git status --porcelain | grep -q "case10"; then
    echo "FAIL scenario 10: session repo (cwd) has staged/dirty case10 state." >&2
    git status --porcelain >&2
    exit 1
  fi

  # ---- Scenario 11: a fresh "- [ ] N." -> "- [x] N." flip emits ONE
  # task_done progress-log event (ask-rooted-workstreams-p1 Task 1 walking
  # skeleton) carrying plan slug + task id + an ISO ts, resolved to the
  # plan header's ask-id ----
  cat > docs/plans/case11.md <<'EOP'
# Plan: Case 11
Status: ACTIVE
ask-id: ask-selftest-case11

## Tasks
- [ ] 1. first task
- [ ] 2. second task
EOP
  git add docs/plans/case11.md
  git commit -q -m "plan: case11"
  PRE11=$(git show HEAD:docs/plans/case11.md)
  cat > docs/plans/case11.md <<'EOP'
# Plan: Case 11
Status: ACTIVE
ask-id: ask-selftest-case11

## Tasks
- [x] 1. first task
- [ ] 2. second task
EOP
  POST11=$(cat docs/plans/case11.md)
  process_lifecycle_event "$TMP/docs/plans/case11.md" "Edit" "$PRE11" "$POST11" >/dev/null 2>&1 || true
  F11="$PROGRESS_LOG_STATE_DIR/ask-selftest-case11.jsonl"
  if [ ! -f "$F11" ]; then
    echo "FAIL scenario 11: expected a task_done event log at $F11" >&2
    exit 1
  fi
  if ! grep -q '"type":"task_done"' "$F11"; then
    echo "FAIL scenario 11: log file exists but has no task_done event. Contents:" >&2
    cat "$F11" >&2
    exit 1
  fi
  if ! grep -q '"plan_slug":"case11"' "$F11" || ! grep -q '"task_id":"1"' "$F11"; then
    echo "FAIL scenario 11: task_done event missing plan_slug=case11/task_id=1. Contents:" >&2
    cat "$F11" >&2
    exit 1
  fi
  if command -v jq >/dev/null 2>&1; then
    TS11=$(jq -r '.ts' "$F11" 2>/dev/null | tr -d '\r')
    case "$TS11" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z) : ;;
      *) echo "FAIL scenario 11: ts '$TS11' is not ISO-8601 UTC" >&2; exit 1 ;;
    esac
  fi

  # ---- Scenario 12: re-saving the SAME plan with NO new flip emits no
  # additional task_done event (distinguishes a fresh flip from a re-save,
  # per Task 1's Integration point) ----
  LINES12_BEFORE=$(wc -l < "$F11" | tr -d ' ')
  PRE12="$POST11"
  cat > docs/plans/case11.md <<'EOP'
# Plan: Case 11
Status: ACTIVE
ask-id: ask-selftest-case11

## Tasks
- [x] 1. first task
- [ ] 2. second task

Some unrelated prose edit.
EOP
  POST12=$(cat docs/plans/case11.md)
  process_lifecycle_event "$TMP/docs/plans/case11.md" "Edit" "$PRE12" "$POST12" >/dev/null 2>&1 || true
  LINES12_AFTER=$(wc -l < "$F11" | tr -d ' ')
  if [ "$LINES12_BEFORE" != "$LINES12_AFTER" ]; then
    echo "FAIL scenario 12: a re-save with no new flip should not append another event (before=$LINES12_BEFORE after=$LINES12_AFTER)" >&2
    exit 1
  fi

  # ---- Scenario 13: a plan flip with NO ask-id header still emits (lands
  # in the "unlinked" per-ask log, never silently dropped — Edge Cases:
  # "estate-growth safe: old plans never break the surface") ----
  cat > docs/plans/case13.md <<'EOP'
# Plan: Case 13 (no ask-id — pre-existing-plan shape)
Status: ACTIVE

## Tasks
- [ ] 1. only task
EOP
  git add docs/plans/case13.md
  git commit -q -m "plan: case13"
  PRE13=$(git show HEAD:docs/plans/case13.md)
  cat > docs/plans/case13.md <<'EOP'
# Plan: Case 13 (no ask-id — pre-existing-plan shape)
Status: ACTIVE

## Tasks
- [x] 1. only task
EOP
  POST13=$(cat docs/plans/case13.md)
  process_lifecycle_event "$TMP/docs/plans/case13.md" "Edit" "$PRE13" "$POST13" >/dev/null 2>&1 || true
  F13="$PROGRESS_LOG_STATE_DIR/unlinked.jsonl"
  if [ ! -f "$F13" ] || ! grep -q '"plan_slug":"case13"' "$F13"; then
    echo "FAIL scenario 13: expected a task_done event for the ask-id-less plan in the unlinked log" >&2
    exit 1
  fi

  # ---- Scenario 14: a newly-introduced task line on an ACTIVE plan emits a
  # plan_amended event summarizing "+task <id>" (Task 6a) ----
  cat > docs/plans/case14.md <<'EOP'
# Plan: Case 14 (plan amendment)
Status: ACTIVE
ask-id: ask-selftest-case14

## Scope
- IN: original scope

## Tasks
- [ ] 1. first task
EOP
  git add docs/plans/case14.md
  git commit -q -m "plan: case14"
  PRE14=$(git show HEAD:docs/plans/case14.md)
  cat > docs/plans/case14.md <<'EOP'
# Plan: Case 14 (plan amendment)
Status: ACTIVE
ask-id: ask-selftest-case14

## Scope
- IN: original scope

## Tasks
- [ ] 1. first task
- [ ] 2. second task (newly added)
EOP
  POST14=$(cat docs/plans/case14.md)
  process_lifecycle_event "$TMP/docs/plans/case14.md" "Edit" "$PRE14" "$POST14" >/dev/null 2>&1 || true
  F14="$PROGRESS_LOG_STATE_DIR/ask-selftest-case14.jsonl"
  if [ ! -f "$F14" ] || ! grep -q '"type":"plan_amended"' "$F14" || ! grep -q '"summary":"+task 2"' "$F14"; then
    echo "FAIL scenario 14: expected a plan_amended event with summary '+task 2' at $F14. Contents:" >&2
    cat "$F14" 2>/dev/null >&2
    exit 1
  fi

  # ---- Scenario 15: re-saving with NO new task and NO scope change emits
  # no additional plan_amended event (idempotent; mirrors Scenario 12's
  # re-save-is-a-no-op discipline for task_done) ----
  PRE15="$POST14"
  cat > docs/plans/case14.md <<'EOP'
# Plan: Case 14 (plan amendment)
Status: ACTIVE
ask-id: ask-selftest-case14

## Scope
- IN: original scope

## Tasks
- [ ] 1. first task
- [ ] 2. second task (newly added)

Some unrelated prose edit -- no new tasks, no scope change.
EOP
  POST15=$(cat docs/plans/case14.md)
  process_lifecycle_event "$TMP/docs/plans/case14.md" "Edit" "$PRE15" "$POST15" >/dev/null 2>&1 || true
  LINES15=$(grep -c '"type":"plan_amended"' "$F14" 2>/dev/null || echo 0)
  if [ "$LINES15" != "1" ]; then
    echo "FAIL scenario 15: expected still 1 plan_amended event after a delta-free re-save, got $LINES15" >&2
    exit 1
  fi

  # ---- Scenario 16: an edited `## Scope` section (no new task line) emits
  # a SECOND, DISTINCT plan_amended event summarizing "scope delta" ----
  PRE16="$POST15"
  cat > docs/plans/case14.md <<'EOP'
# Plan: Case 14 (plan amendment)
Status: ACTIVE
ask-id: ask-selftest-case14

## Scope
- IN: original scope
- IN: an added scope line

## Tasks
- [ ] 1. first task
- [ ] 2. second task (newly added)

Some unrelated prose edit -- no new tasks, no scope change.
EOP
  POST16=$(cat docs/plans/case14.md)
  process_lifecycle_event "$TMP/docs/plans/case14.md" "Edit" "$PRE16" "$POST16" >/dev/null 2>&1 || true
  if ! grep -q '"summary":"scope delta"' "$F14"; then
    echo "FAIL scenario 16: expected a plan_amended event with summary 'scope delta'. Contents:" >&2
    cat "$F14" >&2
    exit 1
  fi
  LINES16=$(grep -c '"type":"plan_amended"' "$F14" 2>/dev/null || echo 0)
  if [ "$LINES16" != "2" ]; then
    echo "FAIL scenario 16: expected 2 total plan_amended events (task-add + scope-delta), got $LINES16" >&2
    exit 1
  fi

  # ---- Scenario 17: a SECOND, DIFFERENT new-task amendment emits a THIRD,
  # DISTINCT event -- "second amendment = new delta hash" (Task 2 table),
  # never suppressed by the first amendment's dedup key ----
  PRE17="$POST16"
  cat > docs/plans/case14.md <<'EOP'
# Plan: Case 14 (plan amendment)
Status: ACTIVE
ask-id: ask-selftest-case14

## Scope
- IN: original scope
- IN: an added scope line

## Tasks
- [ ] 1. first task
- [ ] 2. second task (newly added)
- [ ] 3. third task (second amendment)

Some unrelated prose edit -- no new tasks, no scope change.
EOP
  POST17=$(cat docs/plans/case14.md)
  process_lifecycle_event "$TMP/docs/plans/case14.md" "Edit" "$PRE17" "$POST17" >/dev/null 2>&1 || true
  if ! grep -q '"summary":"+task 3"' "$F14"; then
    echo "FAIL scenario 17: expected a second, distinct plan_amended event for the new task 3. Contents:" >&2
    cat "$F14" >&2
    exit 1
  fi
  LINES17=$(grep -c '"type":"plan_amended"' "$F14" 2>/dev/null || echo 0)
  if [ "$LINES17" != "3" ]; then
    echo "FAIL scenario 17: expected 3 total plan_amended events, got $LINES17" >&2
    exit 1
  fi

  # ---- Scenario 18: a non-ACTIVE (DEFERRED) plan gaining a new task line
  # emits NO plan_amended event -- amendment tracking is scoped to ACTIVE
  # plans only (Task 6a spec) ----
  cat > docs/plans/case18.md <<'EOP'
# Plan: Case 18 (non-active -- no amendment tracking)
Status: DEFERRED
ask-id: ask-selftest-case18

## Tasks
- [ ] 1. only task
EOP
  git add docs/plans/case18.md
  git commit -q -m "plan: case18"
  PRE18=$(git show HEAD:docs/plans/case18.md)
  cat > docs/plans/case18.md <<'EOP'
# Plan: Case 18 (non-active -- no amendment tracking)
Status: DEFERRED
ask-id: ask-selftest-case18

## Tasks
- [ ] 1. only task
- [ ] 2. a new task added while deferred
EOP
  POST18=$(cat docs/plans/case18.md)
  process_lifecycle_event "$TMP/docs/plans/case18.md" "Edit" "$PRE18" "$POST18" >/dev/null 2>&1 || true
  F18="$PROGRESS_LOG_STATE_DIR/ask-selftest-case18.jsonl"
  if [ -f "$F18" ] && grep -q '"type":"plan_amended"' "$F18"; then
    echo "FAIL scenario 18: a DEFERRED (non-ACTIVE) plan should NOT get amendment tracking. Contents:" >&2
    cat "$F18" >&2
    exit 1
  fi

  # ---- Scenario 19: a brand-new plan (no pre-edit content at all) does NOT
  # burst-emit plan_amended for its initial task lines -- creation is not
  # amendment ----
  cat > docs/plans/case19.md <<'EOP'
# Plan: Case 19 (fresh creation should not burst-amend)
Status: ACTIVE
ask-id: ask-selftest-case19

## Tasks
- [ ] 1. first
- [ ] 2. second
EOP
  process_lifecycle_event "$TMP/docs/plans/case19.md" "Write" "" "$(cat docs/plans/case19.md)" >/dev/null 2>&1 || true
  F19="$PROGRESS_LOG_STATE_DIR/ask-selftest-case19.jsonl"
  if [ -f "$F19" ] && grep -q '"type":"plan_amended"' "$F19"; then
    echo "FAIL scenario 19: a brand-new plan (no pre-edit content) should not emit plan_amended for its initial tasks. Contents:" >&2
    cat "$F19" >&2
    exit 1
  fi
  git add docs/plans/case19.md
  git commit -q -m "plan: case19" 2>/dev/null || true

  # ---- Scenario 20 (FINDING 4 REGRESSION, 2026-07-14 ask-splice review
  # panel): a scope amendment that returns to a PREVIOUSLY-SEEN exact state
  # (A->A,B / A,B->A / A->A,B) must emit a THIRD, DISTINCT plan_amended
  # event. The 1st and 3rd transitions below have the IDENTICAL pre_scope
  # AND post_scope -- hashing content alone (even the pre->post delta, not
  # just post_scope) collides between them without a time-bucket
  # discriminator (_amendment_time_bucket). ----
  cat > docs/plans/case20.md <<'EOP'
# Plan: Case 20 (repeat-scope-state amendment)
Status: ACTIVE
ask-id: ask-selftest-case20

## Scope
- IN: state A

## Tasks
- [ ] 1. only task
EOP
  git add docs/plans/case20.md
  git commit -q -m "plan: case20"
  PRE20A=$(git show HEAD:docs/plans/case20.md)
  cat > docs/plans/case20.md <<'EOP'
# Plan: Case 20 (repeat-scope-state amendment)
Status: ACTIVE
ask-id: ask-selftest-case20

## Scope
- IN: state A
- IN: state B

## Tasks
- [ ] 1. only task
EOP
  POST20A=$(cat docs/plans/case20.md)
  process_lifecycle_event "$TMP/docs/plans/case20.md" "Edit" "$PRE20A" "$POST20A" >/dev/null 2>&1 || true
  F20="$PROGRESS_LOG_STATE_DIR/ask-selftest-case20.jsonl"
  LINES20A=$(grep -c '"type":"plan_amended"' "$F20" 2>/dev/null || echo 0)
  if [ "$LINES20A" != "1" ]; then
    echo "FAIL scenario 20a: expected 1 plan_amended event after A->A,B (1st amendment), got $LINES20A" >&2
    cat "$F20" 2>/dev/null >&2
    exit 1
  fi

  # A,B -> A (revert -- a genuinely different delta from 20a).
  PRE20B="$POST20A"
  cat > docs/plans/case20.md <<'EOP'
# Plan: Case 20 (repeat-scope-state amendment)
Status: ACTIVE
ask-id: ask-selftest-case20

## Scope
- IN: state A

## Tasks
- [ ] 1. only task
EOP
  POST20B=$(cat docs/plans/case20.md)
  process_lifecycle_event "$TMP/docs/plans/case20.md" "Edit" "$PRE20B" "$POST20B" >/dev/null 2>&1 || true
  LINES20B=$(grep -c '"type":"plan_amended"' "$F20" 2>/dev/null || echo 0)
  if [ "$LINES20B" != "2" ]; then
    echo "FAIL scenario 20b: expected 2 plan_amended events after A,B->A (2nd amendment), got $LINES20B" >&2
    cat "$F20" 2>/dev/null >&2
    exit 1
  fi

  # Cross _amendment_replay_token's debounce window so the 3rd transition
  # counts as a NEW amendment rather than a hook re-fire of 20a's edit.
  # AMENDMENT_REPLAY_DEBOUNCE_SECONDS=1 compresses the clock instead of
  # sleeping past the real 30s production window (a 31s sleep in a self-test
  # is not worth it) -- same mechanism, same boundary, only the width is
  # parameterized via the documented knob. Scenario 20d below then runs at
  # the PRODUCTION DEFAULT to assert the other side of the window (a replay
  # still dedups), so both sides are covered.
  sleep 3
  AMENDMENT_REPLAY_DEBOUNCE_SECONDS=1
  export AMENDMENT_REPLAY_DEBOUNCE_SECONDS

  # A -> A,B AGAIN: pre_scope/post_scope here are byte-identical to 20a's
  # (PRE20A == POST20B, POST20A == the heredoc below) -- the load-bearing
  # assertion.
  PRE20C="$POST20B"
  cat > docs/plans/case20.md <<'EOP'
# Plan: Case 20 (repeat-scope-state amendment)
Status: ACTIVE
ask-id: ask-selftest-case20

## Scope
- IN: state A
- IN: state B

## Tasks
- [ ] 1. only task
EOP
  POST20C=$(cat docs/plans/case20.md)
  process_lifecycle_event "$TMP/docs/plans/case20.md" "Edit" "$PRE20C" "$POST20C" >/dev/null 2>&1 || true
  LINES20C=$(grep -c '"type":"plan_amended"' "$F20" 2>/dev/null || echo 0)
  if [ "$LINES20C" != "3" ]; then
    echo "FAIL scenario 20c: expected 3 plan_amended events once A->A,B repeats a previously-seen exact state (3rd amendment), got $LINES20C. This is the Finding 4 regression: a content-only hash (even of the pre->post delta) collides here because the 1st and 3rd transitions are textually identical." >&2
    cat "$F20" 2>/dev/null >&2
    exit 1
  fi

  # ---- Scenario 20d (FINDING 4, the OTHER half): a hook RE-FIRE for the
  # SAME single edit -- identical pre AND post, immediately, inside
  # _amendment_replay_token's debounce window -- must STILL dedup to no new
  # event. Without this, the time-varying component added for 20c would just
  # have traded a dropped amendment for a duplicated one.
  #
  # Runs at the PRODUCTION DEFAULT window (the 20c override is dropped here),
  # so this asserts the shipped behavior, not a test-only setting. ----
  unset AMENDMENT_REPLAY_DEBOUNCE_SECONDS
  process_lifecycle_event "$TMP/docs/plans/case20.md" "Edit" "$PRE20C" "$POST20C" >/dev/null 2>&1 || true
  LINES20D=$(grep -c '"type":"plan_amended"' "$F20" 2>/dev/null || echo 0)
  if [ "$LINES20D" != "3" ]; then
    echo "FAIL scenario 20d: an immediate hook re-fire of the SAME edit must NOT emit a 4th plan_amended event (replay must still dedup), got $LINES20D" >&2
    cat "$F20" 2>/dev/null >&2
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

# Resolve the repo containing the edited file (NOT the process cwd) and
# compute pre-edit content from THAT repo's HEAD (best-effort).
FILE_REPO_ROOT=$(resolve_file_repo_root "$NORM")
REL=$(to_repo_relative "$NORM" "$FILE_REPO_ROOT")
PRE=$(pre_edit_content "$FILE_REPO_ROOT" "$REL")

# Post-edit content: read from disk (PostToolUse runs after the write
# completed, so disk reflects the new state).
if [ -f "$FILE_PATH" ]; then
  POST=$(cat "$FILE_PATH" 2>/dev/null || echo "")
else
  POST=""
fi

process_lifecycle_event "$FILE_PATH" "$TOOL_NAME" "$PRE" "$POST"

exit 0
