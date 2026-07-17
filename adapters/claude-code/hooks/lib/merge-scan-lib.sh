#!/bin/bash
# merge-scan-lib.sh — SHA -> ask attribution + `merged` progress-log
# emission (ask-rooted-workstreams-p1 Task 5: "Master-merge emission").
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# The plan's log-first law needs a `merged` progress-log event whenever a
# commit lands on master, attributed to the ask whose plan it serves. Two
# lanes both call into this ONE implementation (constraint 6: the log
# OBSERVES, never flips anything):
#
#   (a) `adapters/claude-code/git-hooks/post-commit` — best-effort splice
#       for LOCAL commits landing on master (this task also adds that
#       splice). Additive only: it can never see a remote squash-merge,
#       since `gh pr merge` never fires a local git hook.
#   (b) `neural-lace/workstreams-ui/server/auditor.js` (Task 12, NOT built
#       by this task) — the GUARANTEED lane. Task 12's Node auditor shells
#       out to THIS FILE directly (mirrors server/derive-cache.js's
#       existing spawnSync-a-bash-tool convention — Node already shells to
#       bash for oracle reads in this codebase, this is not a new pattern):
#
#         bash adapters/claude-code/hooks/lib/merge-scan-lib.sh scan-repo \
#           <repo-root> [--since <sha-or-ref>] [--limit <n>] \
#           [--emitter auditor]
#
#       once per repo root from `config/projects.js`'s loadProjects() map
#       (constraint: "Multi-repo scan set = the projects.js roots" — Task
#       12 owns enumerating the roots; this lib's unit of work is ONE repo
#       per call, by design, so it composes with any caller's own iteration
#       and its own incremental `--since` bookkeeping).
#
# ============================================================
# SHA -> ASK ATTRIBUTION RULE (review round 1, constraint 10 / Decisions
# Log D8 — the model constraint 10 names for every other derived/backfilled
# event type)
# ============================================================
#
#   sha -> plan-slug -> plan-header `ask-id:` -> per-ask progress log.
#
# Plan-slug resolves, in order:
#   1. TOKEN: a `plan: <slug>` line anywhere in the commit subject/body (the
#      doctrine/git.md one-line convention this task also adds — a trailer
#      line, same shape as `Co-Authored-By:`). Every `plan:` line yields one
#      slug; multiple lines are all kept (deduped) -- BUT ONLY IF at least
#      one of those slugs resolves to a REAL plan file (current tree,
#      archive, or the commit's own tree — finding 7 fix,
#      _ms_plan_file_exists). A stray/typo'd `plan:` line naming no real
#      plan does NOT short-circuit; step 2 still runs.
#   2. FALLBACK (no token found, OR no token slug resolved to a real plan
#      file): the commit's changed-file list touches `docs/plans/<slug>.md`,
#      `docs/plans/archive/<slug>.md` (closed plans move there — see
#      close-plan.sh), or that plan's evidence file/dir
#      (`docs/plans/<slug>-evidence.md` or `docs/plans/<slug>-evidence/...`).
#      EVERY distinct slug matched this way is kept — never guesses a single
#      winner (review round 2's multi-match tie-break).
#
# Commits with NO resolvable plan-slug (neither token nor diff match) are
# SKIPPED entirely — routine, non-plan commits never touch the orphan lane
# (anti-noise). This is deliberately narrower than pl_emit's own empty-
# ask-id orphan-lane behavior, which exists for events that DO name a plan
# but can't yet resolve an ask-id (see ASK-ID RESOLUTION below).
#
# MULTI-MATCH TIE-BREAK (review round 2): when step 2 matches MORE THAN ONE
# plan's files in a single commit, this lib emits one `merged` event PER
# matched slug — never guesses a single winner. Two matched slugs that
# happen to resolve to the SAME ask-id do not produce a duplicate line in
# that ask's log for free: `merged`'s natural key is `repo+sha` (Task 2's
# table) and pl_emit's own per-file dedup collapses the second call to a
# no-op — the tie-break's "each per-ask log keeps exactly one event" promise
# falls out of the existing writer contract; it is not re-implemented here.
#
# ASK-ID RESOLUTION: reads the plan file's `ask-id:` header (extract_ask_id
# awk pattern, duplicated from plan-lifecycle.sh/workstreams-emit.sh per
# this codebase's established "every splice stays independently best-effort,
# never sources another hook" convention), trying in order: (1) the CURRENT
# working tree at `<repo-root>/docs/plans/<slug>.md`, (2) `.../archive/
# <slug>.md`, (3) `git show <sha>:docs/plans/<slug>.md` (the commit's own
# tree, for a plan file that has since moved or vanished entirely). A
# matched plan-slug whose plan file lacks `ask-id:` (every pre-Task-10 plan)
# still emits — with an empty --ask, which pl_emit's own orphan lane
# (pl_path_for("") -> unlinked.jsonl) absorbs, exactly like Task 1/9's
# documented unresolvable-ask-id behavior (Edge Cases: "estate-growth
# safe: old plans never break the surface").
#
# ============================================================
# WRITER SEMANTICS (constraint 5) / SANDBOXING (constraint 4)
# ============================================================
#
# Every function here is READ-ONLY against git/the filesystem except the
# final delegated call to `scripts/progress-log.sh emit`, which is itself
# best-effort/never-blocks (writer semantics inherited, not re-implemented).
# ms_emit_merged_for_commit / ms_scan_repo_for_merges never exit non-zero on
# a recoverable failure; a missing git binary or progress-log.sh CLI is a
# silent no-op for the caller (post-commit / the auditor), never a crash.
#
# This lib writes NO state of its own — every event lands via the delegated
# progress-log.sh emit call, which already resolves its state dir through
# PROGRESS_LOG_STATE_DIR / HARNESS_SELFTEST (progress-log-lib.sh's
# pl_state_dir). The self-test below exports both before calling in, and
# does all git-repo fixture work under its own mktemp dirs, torn down on
# exit.
#
# MERGE-COMMIT COVERAGE (splice-review-panel finding 6 — this paragraph
# corrects an earlier, factually WRONG version of itself): the diff-fallback
# (step 2 above) lists a commit's changed files via `git diff-tree
# --no-commit-id --name-only -r --root -m`. The earlier comment here claimed
# a merge commit "is diffed against its first parent same as any other
# commit" -- that was false. Without `-m`, `git diff-tree` on a true
# multi-parent merge commit emits NOTHING AT ALL (not a first-parent diff,
# an EMPTY diff), so a plan-file touch that exists only on the merged-in
# side (conflict-resolution edits, or any change unique to the non-first
# parent) was silently dropped. With `-m`, diff-tree diffs the merge commit
# against EACH parent independently and this loop sees the union of both
# parents' changed-file lists (the existing `awk '!seen[$0]++'` dedup below
# already collapses any file listed twice); a plan-file touch that differs
# from EITHER parent now surfaces. A `gh pr merge` squash commit is always a
# single-parent ordinary commit and was never affected either way. The
# TOKEN path (step 1) is unaffected regardless, since it only reads the
# commit message. Residual (acceptably narrow) limitation: a file whose
# merge-commit content is byte-identical to BOTH parents cannot surface via
# a diff against either one -- unreachable for a normal two-way clean merge
# that actually changed the file, but theoretically possible via a
# contrived octopus merge or manual tree surgery. Constraint 5's
# "best-effort, never blocks" already accepts that residual gap.
#
# ============================================================
# INCREMENTAL CURSOR (2026-07-16 production fix -- convergence, not re-scan)
# ============================================================
#
# `ms_scan_repo_for_merges` used to re-walk the SAME bounded `git log
# origin/master -n <limit>` window on every single auditor cycle (120s
# cadence), forever. On a repo whose history is deep enough that the
# per-commit subprocess fan-out (git log -1, git diff-tree -m, git
# cat-file/show, a progress-log.sh emit spawn) exceeds
# DEFAULT_CLI_TIMEOUT_MS (60s, auditor.js) across the default 200-commit
# window, `runCli`'s killTree fires every cycle: no leak (the 2026-07-14
# kill-the-tree fix holds), but the backfill NEVER COMPLETES and NEVER MAKES
# PROGRESS -- the exact same window gets killed and re-attempted forever.
#
# The fix: a per-repo last-scanned-SHA CURSOR persisted at
# `~/.claude/state/merge-scan-cursors/<repo-key>` (repo-key derived the same
# way progress-log-lib.sh's `_pl_sanitize_ask_id` / dispatch-provenance.sh's
# `_dp_sanitize` derive theirs -- allowlist-normalize a canonical string,
# every char outside [A-Za-z0-9._-] -> `_`; see _ms_repo_key below).
#
#   1. If a cursor exists AND is still an ancestor of origin/master
#      (`git merge-base --is-ancestor`), scan ONLY `<cursor>..origin/master`
#      -- only commits that landed since the last successful frontier. A
#      corrupt file, a SHA that doesn't resolve to a commit in this repo, or
#      a SHA that is no longer an ancestor (history moved / force-push) all
#      fail OPEN to the original bounded-window full scan -- never an
#      error; the cursor self-heals on the next successful write.
#   2. The commit list (bounded-window OR cursor-narrowed, either way still
#      capped by --limit) is walked OLDEST FIRST (`git log --reverse`), and
#      the cursor is advanced to EACH commit's own SHA as it finishes
#      processing -- NOT only once at the very end. This is the
#      load-bearing property: the process can still be tree-killed mid-run
#      (a large backlog, a slow commit), and oldest-first + per-commit
#      advancement means a killed run leaves the cursor at the last commit
#      ACTUALLY completed -- never skipping the untouched remainder, never
#      falsely claiming more progress than was made. The very next cycle
#      resumes exactly there. (Advancing newest-first would be WRONG: a
#      kill partway through would leave the cursor pointing at a commit
#      newer than some still-unprocessed older ones, permanently orphaning
#      them.)
#   3. An explicit caller-supplied `--since` bypasses the cursor entirely
#      (read AND write) -- a manual/one-off range must never clobber the
#      automatic frontier.
#
# Net effect: the backfill converges across a small, bounded number of
# cycles (each cycle's window is itself bounded by --limit, same as today),
# and once caught up, every further cycle's range is empty
# (cursor==origin/master) and returns immediately -- the cheap steady state
# this fix exists to reach.

set -u

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_MERGE_SCAN_LIB_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_MERGE_SCAN_LIB_SOURCED=1

# ----------------------------------------------------------------------
# _ms_progress_log_cli — resolve scripts/progress-log.sh relative to this
# lib's own hooks/lib/ dir (mirrors workstreams-emit.sh's
# _pl_progress_log_cli override convention -- one directory deeper here
# since this file lives in hooks/lib/, not hooks/).
# ----------------------------------------------------------------------
_ms_progress_log_cli() {
  if [[ -n "${MS_PROGRESS_LOG_CLI_OVERRIDE:-}" ]]; then
    printf '%s' "$MS_PROGRESS_LOG_CLI_OVERRIDE"; return 0
  fi
  printf '%s/../../scripts/progress-log.sh' "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
}

# ----------------------------------------------------------------------
# _ms_plan_token_slugs <text> — every `plan: <slug>` trailer LINE in <text>
# (commit subject+body), slug only, deduped, newline-separated. Empty when
# none found.
# ----------------------------------------------------------------------
_ms_plan_token_slugs() {
  local text="$1"
  printf '%s\n' "$text" \
    | grep -E '^plan:[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*$' \
    | sed -E 's/^plan:[[:space:]]*//; s/[[:space:]]*$//' \
    | awk '!seen[$0]++'
}

# ----------------------------------------------------------------------
# _ms_plan_slugs_from_diff <repo-root> <sha> — every distinct plan slug
# whose plan file / archived plan file / evidence file / evidence dir was
# touched by <sha>, deduped, newline-separated. Empty when none match.
# ----------------------------------------------------------------------
_ms_plan_slugs_from_diff() {
  local repo_root="$1" sha="$2"
  local files
  files="$(git -C "$repo_root" diff-tree --no-commit-id --name-only -r --root -m "$sha" 2>/dev/null)"
  [[ -z "$files" ]] && return 0
  local f base
  printf '%s\n' "$files" | while IFS= read -r f; do
    case "$f" in
      docs/plans/*-evidence/*)
        # MUST be checked BEFORE the `docs/plans/*.md)` arm below (splice-
        # review-panel finding 5): bash `case` globs span `/`, so
        # `docs/plans/foo-evidence/summary.md` also matches `*.md` and,
        # if that arm ran first, would derive the mangled slug
        # `foo-evidence/summary` instead of `foo`.
        base="${f#docs/plans/}"
        base="${base#archive/}"
        base="${base%%/*}"
        printf '%s\n' "${base%-evidence}"
        ;;
      docs/plans/*.md)
        base="${f#docs/plans/}"
        base="${base#archive/}"
        case "$base" in
          *-evidence.md) printf '%s\n' "${base%-evidence.md}" ;;
          *) printf '%s\n' "${base%.md}" ;;
        esac
        ;;
      *) ;;
    esac
  done | awk '!seen[$0]++'
}

# ----------------------------------------------------------------------
# _ms_plan_file_exists <repo-root> <slug> <sha> — true if <slug> resolves to
# a REAL plan file via any of the 3 lookups _ms_resolve_ask_id also uses:
# (1) current working tree docs/plans/<slug>.md, (2) .../archive/<slug>.md,
# (3) the commit's own tree (docs/plans/<slug>.md as of <sha>). Used by
# _ms_commit_plan_slugs (splice-review-panel finding 7) to verify a
# `plan: <token>` trailer names a plan that actually exists before letting
# it short-circuit the more reliable diff fallback.
# ----------------------------------------------------------------------
_ms_plan_file_exists() {
  local repo_root="$1" slug="$2" sha="$3"
  [[ -f "$repo_root/docs/plans/$slug.md" ]] && return 0
  [[ -f "$repo_root/docs/plans/archive/$slug.md" ]] && return 0
  git -C "$repo_root" cat-file -e "$sha:docs/plans/$slug.md" 2>/dev/null && return 0
  return 1
}

# ----------------------------------------------------------------------
# _ms_commit_plan_slugs <repo-root> <sha> — the full step 1 -> step 2
# plan-slug resolution (see SHA -> ASK ATTRIBUTION RULE above). Empty when
# neither step resolves anything (SKIP the commit — anti-noise).
#
# Finding 7 fix: the TOKEN path only short-circuits when at least one
# token slug resolves to a REAL plan file (_ms_plan_file_exists). A stray/
# typo'd `plan: <token>` line that names no real plan now falls through to
# the diff fallback instead of silently orphaning a commit that genuinely
# touches a real plan's files.
# ----------------------------------------------------------------------
_ms_commit_plan_slugs() {
  local repo_root="$1" sha="$2"
  local msg tok
  msg="$(git -C "$repo_root" log -1 --format=%B "$sha" 2>/dev/null)"
  tok="$(_ms_plan_token_slugs "$msg")"
  if [[ -n "$tok" ]]; then
    local slug any_resolved=0
    while IFS= read -r slug; do
      [[ -z "$slug" ]] && continue
      if _ms_plan_file_exists "$repo_root" "$slug" "$sha"; then
        any_resolved=1
        break
      fi
    done <<< "$tok"
    if [[ "$any_resolved" == "1" ]]; then
      printf '%s\n' "$tok"
      return 0
    fi
    # None of the token slugs resolve to a real plan file -- fall through
    # to the diff fallback rather than trusting an unresolvable token.
  fi
  _ms_plan_slugs_from_diff "$repo_root" "$sha"
}

# ----------------------------------------------------------------------
# _ms_resolve_ask_id <repo-root> <slug> <sha> — read the plan file's
# `ask-id:` header per ASK-ID RESOLUTION above. Prints empty (never errors)
# when the plan is matched but carries no ask-id yet -- caller passes that
# straight to pl_emit's own orphan lane.
# ----------------------------------------------------------------------
_ms_resolve_ask_id() {
  local repo_root="$1" slug="$2" sha="$3"
  local f
  for f in "$repo_root/docs/plans/$slug.md" "$repo_root/docs/plans/archive/$slug.md"; do
    if [[ -f "$f" ]]; then
      awk '
        /^ask-id:[[:space:]]*[^[:space:]]+/ {
          sub(/^ask-id:[[:space:]]*/, "", $0)
          sub(/[[:space:]].*$/, "", $0)
          print $0
          exit
        }
      ' "$f" 2>/dev/null
      return 0
    fi
  done
  git -C "$repo_root" show "$sha:docs/plans/$slug.md" 2>/dev/null | awk '
    /^ask-id:[[:space:]]*[^[:space:]]+/ {
      sub(/^ask-id:[[:space:]]*/, "", $0)
      sub(/[[:space:]].*$/, "", $0)
      print $0
      exit
    }
  '
  return 0
}

# ----------------------------------------------------------------------
# ms_emit_merged_for_commit <repo-root> <sha> [--emitter <name>]
#
#   The per-commit primitive both lanes call. Resolves plan-slug(s) (SKIPS,
# no-op, if none resolve — anti-noise), resolves each slug's ask-id, and
# emits one `merged` event per matched slug via the STABLE, UNCHANGED
# scripts/progress-log.sh `emit` CLI (never sourced/reimplemented — same
# convention as every other splice in this plan). Never blocks: exit
# status is always the (ignored) status of the last best-effort emit
# attempt; callers should not branch on it.
# ----------------------------------------------------------------------
ms_emit_merged_for_commit() {
  local repo_root="$1"; shift
  local sha="${1:-}"; shift || true
  local emitter="post-commit"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --emitter) emitter="${2:-post-commit}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -z "$repo_root" || -z "$sha" ]] && return 0

  local pl_cli; pl_cli="$(_ms_progress_log_cli)"
  [[ -f "$pl_cli" ]] || return 0

  local slugs
  slugs="$(_ms_commit_plan_slugs "$repo_root" "$sha")"
  [[ -z "$slugs" ]] && return 0

  local slug ask_id
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    ask_id="$(_ms_resolve_ask_id "$repo_root" "$slug" "$sha")"
    ( cd "$repo_root" 2>/dev/null && bash "$pl_cli" emit --type merged --ask "$ask_id" \
        --plan-slug "$slug" --sha "$sha" --summary "merged to master" \
        --emitter "$emitter" >/dev/null 2>&1 ) || true
  done <<< "$slugs"
  return 0
}

# ----------------------------------------------------------------------
# _ms_cursor_state_dir — resolve the incremental-scan cursor directory.
# Mirrors progress-log-lib.sh's pl_state_dir resolution order exactly
# (explicit override -> HARNESS_SELFTEST sandbox -> real default), but is
# its OWN directory/env-var (MS_CURSOR_STATE_DIR) since cursors are a
# distinct concern from the progress-log event store.
# ----------------------------------------------------------------------
_ms_cursor_state_dir() {
  if [[ -n "${MS_CURSOR_STATE_DIR:-}" ]]; then
    printf '%s' "$MS_CURSOR_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/merge-scan-cursors-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/merge-scan-cursors' "${HOME:-$PWD}"
  return 0
}

# ----------------------------------------------------------------------
# _ms_repo_key <repo-root> — filesystem-safe single-path-component cursor
# filename for <repo-root>, derived from its CANONICAL absolute path (so two
# different relative/symlinked spellings of the same repo share one cursor)
# via the same allowlist technique as progress-log-lib.sh's
# _pl_sanitize_ask_id / dispatch-provenance.sh's _dp_sanitize: every char
# outside [A-Za-z0-9._-] -> `_`. Never fails -- an unresolvable repo-root
# (shouldn't happen; the only caller already checked `git rev-parse
# --is-inside-work-tree`) degrades to a static fallback key rather than an
# empty/degenerate one.
# ----------------------------------------------------------------------
_ms_repo_key() {
  local repo_root="$1"
  local abs
  abs="$(cd "$repo_root" 2>/dev/null && pwd -P)"
  [[ -z "$abs" ]] && abs="$repo_root"
  local s="${abs//[!A-Za-z0-9._-]/_}"
  while [[ "$s" == *..* ]]; do s="${s//../_}"; done
  if [[ -z "$s" || "$s" == "." || "$s" == "_" ]]; then
    s="unknown-repo"
  fi
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# _ms_cursor_path <repo-root> — the resolved cursor file for <repo-root>.
# ----------------------------------------------------------------------
_ms_cursor_path() {
  printf '%s/%s' "$(_ms_cursor_state_dir)" "$(_ms_repo_key "$1")"
}

# ----------------------------------------------------------------------
# _ms_read_cursor <cursor-path> — print the persisted cursor SHA, or empty
# if the file is missing, unreadable, or does not contain exactly a 40-hex-
# char SHA (every SHA this lib ever writes comes straight from `git log
# --format=%H`, always 40 hex chars -- anything else is corruption or a
# foreign write and is treated as absent). FAIL-OPEN: never errors; the
# caller (ms_scan_repo_for_merges) falls back to a full scan on empty.
# ----------------------------------------------------------------------
_ms_read_cursor() {
  local path="$1" raw
  [[ -f "$path" ]] || return 0
  raw="$(cat "$path" 2>/dev/null)" || return 0
  raw="${raw//[$'\t\r\n ']/}"
  if [[ "$raw" =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf '%s' "$raw"
  fi
  return 0
}

# ----------------------------------------------------------------------
# _ms_write_cursor <repo-root> <sha> — atomically persist <sha> as the new
# cursor for <repo-root> (tmp-file + rename, so a concurrent reader never
# observes a half-written file). Best-effort: a failure to mkdir/write/
# rename is swallowed, never propagated -- a cursor write is an
# optimization, not a correctness requirement (worst case, the next run
# just falls back to a full scan again).
# ----------------------------------------------------------------------
_ms_write_cursor() {
  local repo_root="$1" sha="$2"
  local path dir tmp
  path="$(_ms_cursor_path "$repo_root")"
  dir="$(dirname "$path")"
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp="${path}.tmp.$$"
  printf '%s\n' "$sha" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }
  mv -f "$tmp" "$path" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

# ----------------------------------------------------------------------
# ms_scan_repo_for_merges <repo-root> [--since <sha-or-ref>] [--limit <n>]
#                          [--emitter <name>]
#
#   THE GUARANTEED LANE (Task 12 consumes this). Without an explicit
# --since, resumes from the persisted per-repo CURSOR (see INCREMENTAL
# CURSOR above): `<cursor>..origin/master` when the cursor is still a valid
# ancestor, else the original bounded `git log origin/master -n <limit>`
# window (default 200). Either way the commit list is walked OLDEST FIRST
# and the cursor is advanced to each commit as it finishes -- so a
# tree-killed run leaves durable, resumable progress instead of restarting
# from scratch every cycle. An explicit --since bypasses the cursor
# entirely (read and write). Safe to re-run over the same range repeatedly
# regardless: pl_emit's own repo+sha natural-key dedup makes every call
# idempotent independent of the cursor.
# ----------------------------------------------------------------------
ms_scan_repo_for_merges() {
  local repo_root="$1"; shift || true
  [[ -z "${repo_root:-}" ]] && return 0
  local since="" limit="200" emitter="auditor" since_explicit=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) since="${2:-}"; since_explicit=1; shift 2 ;;
      --limit) limit="${2:-200}"; shift 2 ;;
      --emitter) emitter="${2:-auditor}"; shift 2 ;;
      *) shift ;;
    esac
  done
  git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  if [[ "$since_explicit" == "0" ]]; then
    local cursor_sha
    cursor_sha="$(_ms_read_cursor "$(_ms_cursor_path "$repo_root")")"
    if [[ -n "$cursor_sha" ]] \
       && git -C "$repo_root" cat-file -e "${cursor_sha}^{commit}" 2>/dev/null \
       && git -C "$repo_root" merge-base --is-ancestor "$cursor_sha" origin/master 2>/dev/null; then
      since="$cursor_sha"
    fi
    # else: no cursor, corrupt cursor, or a stale (non-ancestor) cursor --
    # fall through to the bounded full scan below; a fresh cursor gets
    # written as commits are processed (self-heals).
  fi

  local range="origin/master"
  [[ -n "$since" ]] && range="${since}..origin/master"

  # NOTE: git's `-n <limit>` always truncates to the NEWEST <limit> commits
  # in the range regardless of --reverse (`-n 2 --reverse` and `--reverse -n
  # 2` both return the two newest, merely printed oldest-first) -- verified
  # empirically, not an assumption. That is exactly what the FALLBACK window
  # wants to preserve (today's "newest <limit> commits on origin/master"),
  # but it is WRONG for the cursor-narrowed catch-up range: truncating a
  # backlog bigger than <limit> to its newest end would silently skip the
  # older, still-unprocessed middle forever once the cursor jumps past it.
  local shas
  if [[ -n "$since" ]]; then
    # Cursor-narrowed: take the OLDEST <=<limit> commits (full --reverse
    # walk + head), so a bounded/killed run always advances the frontier
    # contiguously and a backlog bigger than <limit> converges over
    # successive cycles instead of losing its middle.
    shas="$(git -C "$repo_root" log "$range" --format=%H --reverse 2>/dev/null | head -n "$limit")"
  else
    # Fallback bounded full scan: preserve today's exact WINDOW (the newest
    # <limit> commits on origin/master), but still walk it oldest-first so a
    # mid-window kill -- the file's own historical failure mode, the very
    # first run over a big repo getting tree-killed partway -- leaves
    # resumable progress instead of an arbitrary, unresumable subset.
    shas="$(git -C "$repo_root" log "$range" --format=%H -n "$limit" 2>/dev/null | tac)"
  fi
  [[ -z "$shas" ]] && return 0

  local sha
  while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    ms_emit_merged_for_commit "$repo_root" "$sha" --emitter "$emitter"
    [[ "$since_explicit" == "0" ]] && _ms_write_cursor "$repo_root" "$sha"
  done <<< "$shas"
  return 0
}

# ----------------------------------------------------------------------
# _ms_is_master_branch <repo-root> — true if <repo-root>'s current branch
# is the configured main branch (MS_MASTER_BRANCH override for tests,
# default "master" -- this repo's own main branch, per gitStatus/CLAUDE.md).
# Used by the post-commit splice to scope itself to "commits landing on
# master" (Task 5a's exact wording); the guaranteed lane (Task 5b /
# ms_scan_repo_for_merges) does not need this -- it reads origin/master
# directly regardless of the caller's checked-out branch.
# ----------------------------------------------------------------------
_ms_is_master_branch() {
  local repo_root="$1"
  local want="${MS_MASTER_BRANCH:-master}"
  local cur
  cur="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ "$cur" == "$want" ]]
}

# ============================================================
# --self-test (sandboxed; HARNESS_SELFTEST-style: PROGRESS_LOG_STATE_DIR
# explicit-override is honored by progress-log-lib.sh's pl_state_dir
# regardless of HARNESS_SELFTEST, so exporting it alone is sufficient to
# keep every emit call in this self-test off the real
# ~/.claude/state/progress-logs — HARNESS_SELFTEST=1 is exported too, for
# consistency with the rest of this harness's sandboxing convention.)
# ============================================================
ms_self_test() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local TMP
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'msst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    return 1
  fi

  export HARNESS_SELFTEST=1
  export PROGRESS_LOG_STATE_DIR="$TMP/pl-state"
  mkdir -p "$PROGRESS_LOG_STATE_DIR"
  # Explicit override (same convention as PROGRESS_LOG_STATE_DIR above) so
  # every cursor file this self-test writes lands under $TMP and is swept
  # up by the final `rm -rf "$TMP"` -- never the real per-machine default.
  export MS_CURSOR_STATE_DIR="$TMP/cursor-state"
  mkdir -p "$MS_CURSOR_STATE_DIR"

  local REPO="$TMP/fixture-repo"
  mkdir -p "$REPO"
  (
    cd "$REPO" || exit 1
    git init -q
    git config core.hooksPath ""
    git config user.email "test@example.test"
    git config user.name "Test"
    mkdir -p docs/plans
    cat > docs/plans/plan-a.md <<'EOF'
# Plan: A
Status: ACTIVE
ask-id: ask-fixture-a

## Tasks
- [ ] 1. first task
EOF
    cat > docs/plans/plan-b.md <<'EOF'
# Plan: B
Status: ACTIVE
ask-id: ask-fixture-b

## Tasks
- [ ] 1. first task
EOF
    cat > docs/plans/plan-c.md <<'EOF'
# Plan: C (no ask-id yet -- pre-Task-10 shape)
Status: ACTIVE

## Tasks
- [ ] 1. first task
EOF
    echo "hello" > README.md
    git add . && git commit -q -m "init"
  )
  local FIXTURE_BRANCH
  FIXTURE_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"

  echo "Scenario 1: plan: token in commit body -> resolves plan-a via TOKEN path"
  local sha1
  (
    cd "$REPO" || exit 1
    echo "task 1 done" >> docs/plans/plan-a.md
    git commit -q -am "$(printf 'fix(plan-a): flip task 1\n\nplan: plan-a\n')"
  )
  sha1="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha1" --emitter post-commit
  fa="$PROGRESS_LOG_STATE_DIR/ask-fixture-a.jsonl"
  if [[ -f "$fa" ]] && grep -qF "\"sha\":\"$sha1\"" "$fa" && grep -qF '"plan_slug":"plan-a"' "$fa" && grep -qF '"type":"merged"' "$fa"; then
    pass "TOKEN path: plan-a's merged event landed in ask-fixture-a.jsonl with the right sha"
  else
    fail "expected a merged event for sha1 in $fa"
  fi
  if grep -qF '"provenance":"known"' "$fa" 2>/dev/null; then
    pass "emitter=post-commit is a known mechanism (provenance:known, no de-emphasis)"
  else
    fail "expected provenance:known for the post-commit emitter"
  fi

  echo "Scenario 2: no plan: token, diff touches plan-b.md -> resolves plan-b via DIFF FALLBACK"
  local sha2
  (
    cd "$REPO" || exit 1
    echo "task 1 done" >> docs/plans/plan-b.md
    git commit -q -am "fix(plan-b): typo (no plan token here)"
  )
  sha2="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha2" --emitter post-commit
  fb="$PROGRESS_LOG_STATE_DIR/ask-fixture-b.jsonl"
  if [[ -f "$fb" ]] && grep -qF "\"sha\":\"$sha2\"" "$fb" && grep -qF '"plan_slug":"plan-b"' "$fb"; then
    pass "DIFF FALLBACK: plan-b's merged event landed in ask-fixture-b.jsonl"
  else
    fail "expected a merged event for sha2 in $fb"
  fi

  echo "Scenario 3: MULTI-MATCH -- one commit touches BOTH plan-a.md and plan-b.md -> TWO merged events, one per ask"
  local sha3
  (
    cd "$REPO" || exit 1
    echo "shared cleanup" >> docs/plans/plan-a.md
    echo "shared cleanup" >> docs/plans/plan-b.md
    git commit -q -am "chore: cross-plan cleanup touch (no plan token)"
  )
  sha3="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha3" --emitter post-commit
  if grep -qF "\"sha\":\"$sha3\"" "$fa" && grep -qF "\"sha\":\"$sha3\"" "$fb"; then
    pass "multi-match tie-break: sha3 emitted into BOTH ask-fixture-a.jsonl and ask-fixture-b.jsonl (never guessed one winner)"
  else
    fail "expected sha3 in both $fa and $fb"
  fi
  if [[ "$(grep -cF "\"sha\":\"$sha3\"" "$fa")" == "1" && "$(grep -cF "\"sha\":\"$sha3\"" "$fb")" == "1" ]]; then
    pass "each per-ask log kept exactly one event for sha3 (repo+sha natural key holds even across multi-match)"
  else
    fail "expected exactly one sha3 line per file"
  fi

  echo "Scenario 4: no-slug-resolvable commit (touches only README.md, no plan token) -> SKIPPED, no event anywhere"
  local sha4 unlinked="$PROGRESS_LOG_STATE_DIR/unlinked.jsonl"
  local before_a before_b before_u
  before_a="$(wc -l < "$fa" 2>/dev/null || echo 0)"
  before_b="$(wc -l < "$fb" 2>/dev/null || echo 0)"
  before_u="$(wc -l < "$unlinked" 2>/dev/null || echo 0)"
  (
    cd "$REPO" || exit 1
    echo "readme update" >> README.md
    git commit -q -am "docs: readme touch, not plan-related"
  )
  sha4="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha4" --emitter post-commit
  after_a="$(wc -l < "$fa" 2>/dev/null || echo 0)"
  after_b="$(wc -l < "$fb" 2>/dev/null || echo 0)"
  after_u="$(wc -l < "$unlinked" 2>/dev/null || echo 0)"
  if [[ "$before_a" == "$after_a" && "$before_b" == "$after_b" && "$before_u" == "$after_u" ]] && ! grep -qF "\"sha\":\"$sha4\"" "$unlinked" 2>/dev/null; then
    pass "routine non-plan commit SKIPPED entirely (anti-noise: no orphan-lane flood)"
  else
    fail "expected sha4 to produce NO event anywhere (a=$before_a/$after_a b=$before_b/$after_b u=$before_u/$after_u)"
  fi

  echo "Scenario 5: plan matched but its plan file carries NO ask-id (plan-c, pre-Task-10 shape) -> orphan lane (unlinked.jsonl), never dropped"
  local sha5
  (
    cd "$REPO" || exit 1
    echo "task 1 done" >> docs/plans/plan-c.md
    git commit -q -am "fix(plan-c): flip task 1 (no plan token, no ask-id header)"
  )
  sha5="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha5" --emitter post-commit
  if [[ -f "$unlinked" ]] && grep -qF "\"sha\":\"$sha5\"" "$unlinked" && grep -qF '"plan_slug":"plan-c"' "$unlinked" && grep -qF '"ask_id":""' "$unlinked"; then
    pass "matched-plan-but-no-ask-id lands in the unlinked orphan lane, not dropped (estate-growth safe)"
  else
    fail "expected sha5 in $unlinked with empty ask_id"
  fi

  echo "Scenario 6: idempotency -- re-emitting the SAME commit does not duplicate the line"
  ms_emit_merged_for_commit "$REPO" "$sha1" --emitter post-commit
  local count1
  count1="$(grep -cF "\"sha\":\"$sha1\"" "$fa" 2>/dev/null || echo 0)"
  if [[ "$count1" == "1" ]]; then
    pass "re-running ms_emit_merged_for_commit on an already-emitted sha is a no-op (repo+sha natural key dedup)"
  else
    fail "expected exactly 1 line for sha1 after re-emit, got $count1"
  fi

  echo "Scenario 7: ms_scan_repo_for_merges -- THE GUARANTEED LANE, over a faked origin/master ref"
  local sha6
  (
    cd "$REPO" || exit 1
    echo "another flip" >> docs/plans/plan-a.md
    git commit -q -am "$(printf 'fix(plan-a): flip task 2\n\nplan: plan-a\n')"
  )
  sha6="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" update-ref refs/remotes/origin/master "$sha6"
  # Fresh sandbox for the scan so counts are unambiguous.
  export PROGRESS_LOG_STATE_DIR="$TMP/pl-state-scan"
  mkdir -p "$PROGRESS_LOG_STATE_DIR"
  ms_scan_repo_for_merges "$REPO" --emitter auditor
  local scanned_fa="$PROGRESS_LOG_STATE_DIR/ask-fixture-a.jsonl"
  local scanned_fb="$PROGRESS_LOG_STATE_DIR/ask-fixture-b.jsonl"
  local scanned_unlinked="$PROGRESS_LOG_STATE_DIR/unlinked.jsonl"
  if grep -qF "\"sha\":\"$sha1\"" "$scanned_fa" 2>/dev/null \
     && grep -qF "\"sha\":\"$sha3\"" "$scanned_fa" 2>/dev/null && grep -qF "\"sha\":\"$sha3\"" "$scanned_fb" 2>/dev/null \
     && grep -qF "\"sha\":\"$sha6\"" "$scanned_fa" 2>/dev/null \
     && grep -qF "\"sha\":\"$sha5\"" "$scanned_unlinked" 2>/dev/null \
     && ! grep -qF "\"sha\":\"$sha4\"" "$scanned_unlinked" 2>/dev/null; then
    pass "scan-repo backfilled every commit on origin/master (guaranteed lane) with the same attribution as the per-commit lane"
  else
    fail "expected the full commit set backfilled via ms_scan_repo_for_merges"
  fi

  echo "Scenario 8: ms_scan_repo_for_merges is idempotent (re-scan produces the SAME counts)"
  local before_count after_count
  before_count="$(wc -l < "$scanned_fa" 2>/dev/null || echo 0)"
  ms_scan_repo_for_merges "$REPO" --emitter auditor
  after_count="$(wc -l < "$scanned_fa" 2>/dev/null || echo 0)"
  if [[ "$before_count" == "$after_count" ]]; then
    pass "re-scanning the same origin/master range is idempotent (no duplicate lines)"
  else
    fail "expected $before_count lines after re-scan, got $after_count"
  fi

  echo "Scenario 9: _ms_is_master_branch (used by the post-commit splice to scope itself to master)"
  local cur_branch
  cur_branch="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if _ms_is_master_branch "$REPO"; then
    if [[ "$cur_branch" == "master" ]]; then
      pass "_ms_is_master_branch true on a repo whose current branch is master"
    else
      fail "_ms_is_master_branch true but fixture branch is '$cur_branch', not master (unexpected fixture default branch)"
    fi
  else
    if MS_MASTER_BRANCH="$cur_branch" _ms_is_master_branch "$REPO"; then
      pass "_ms_is_master_branch correctly scopes to MS_MASTER_BRANCH override (fixture default branch is '$cur_branch', not master)"
    else
      fail "_ms_is_master_branch failed even with MS_MASTER_BRANCH override set to the fixture's actual branch"
    fi
  fi

  echo "Scenario 10: sandbox-only writes -- self-test never touched a real .claude/state shape"
  if [[ ! -e "$TMP/.claude" ]]; then
    pass "self-test wrote only under its own sandboxed tempdir"
  else
    fail "self-test unexpectedly created a .claude path under $TMP"
  fi

  echo ""
  echo "---- Regression fixtures for splice-review-panel Findings 5, 6, 7 (fresh log dir; more commits on \$REPO) ----"
  export PROGRESS_LOG_STATE_DIR="$TMP/pl-state-findings"
  mkdir -p "$PROGRESS_LOG_STATE_DIR"
  local f_fa="$PROGRESS_LOG_STATE_DIR/ask-fixture-a.jsonl"
  local f_fd="$PROGRESS_LOG_STATE_DIR/ask-fixture-d.jsonl"

  (
    cd "$REPO" || exit 1
    mkdir -p docs/plans/plan-d-evidence
    cat > docs/plans/plan-d.md <<'EOF'
# Plan: D (finding 5/7 fixture)
Status: ACTIVE
ask-id: ask-fixture-d

## Tasks
- [ ] 1. first task
EOF
    git add docs/plans/plan-d.md
    git commit -q -m "chore: add plan-d fixture (no plan token)"
  )

  echo "Scenario 11a (FINDING 5 regression): a commit touching ONLY docs/plans/plan-d-evidence/summary.md derives PLAN slug 'plan-d', not the mangled 'plan-d-evidence/summary'"
  # DISCRIMINATING BY CONSTRUCTION: the evidence .md is the ONLY file in this
  # commit. An earlier draft of this scenario also touched a .json sibling in
  # the same commit -- but the .json hits the `-evidence/*` arm correctly even
  # in the BUGGY ordering, so it MASKED the .md mis-route and this assertion
  # passed against the pre-fix code (a green test proving nothing). Keep the
  # .md alone here; the .json/plan.md siblings get their own scenarios below.
  local sha11a
  (
    cd "$REPO" || exit 1
    echo "run output" > docs/plans/plan-d-evidence/summary.md
    git add docs/plans/plan-d-evidence/summary.md
    git commit -q -m "chore: plan-d evidence .md ONLY (no plan token, no json sibling)"
  )
  sha11a="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha11a" --emitter post-commit
  if [[ -f "$f_fd" ]] && grep -qF "\"sha\":\"$sha11a\"" "$f_fd" && grep -qF '"plan_slug":"plan-d"' "$f_fd"; then
    pass "FINDING 5: evidence-dir .md ALONE derives plan slug 'plan-d' (landed in ask-fixture-d.jsonl)"
  else
    fail "FINDING 5: expected sha11a attributed to plan-d in $f_fd"
  fi
  if grep -rqF '"plan_slug":"plan-d-evidence/summary"' "$PROGRESS_LOG_STATE_DIR" 2>/dev/null; then
    fail "FINDING 5: the mangled slug 'plan-d-evidence/summary' must never appear"
  else
    pass "FINDING 5: mangled slug 'plan-d-evidence/summary' does not appear anywhere"
  fi

  echo "Scenario 11b (FINDING 5 regression): a .json sibling in the evidence dir still routes to 'plan-d' (the arm reorder did not regress the non-.md case)"
  local sha11b
  (
    cd "$REPO" || exit 1
    echo '{"ok":true}' > docs/plans/plan-d-evidence/summary.json
    git add docs/plans/plan-d-evidence/summary.json
    git commit -q -m "chore: plan-d evidence .json sibling (no plan token)"
  )
  sha11b="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha11b" --emitter post-commit
  if grep -qF "\"sha\":\"$sha11b\"" "$f_fd" 2>/dev/null && grep -qF '"plan_slug":"plan-d"' "$f_fd" 2>/dev/null; then
    pass "FINDING 5: evidence-dir .json sibling still routes to plan-d"
  else
    fail "FINDING 5: expected sha11b attributed to plan-d in $f_fd"
  fi

  echo "Scenario 11c (FINDING 5 regression): a change to plan-d.md ITSELF still routes to 'plan-d' (the plain plan-file arm still works after the reorder)"
  local sha11c
  (
    cd "$REPO" || exit 1
    echo "task 1 done" >> docs/plans/plan-d.md
    git commit -q -am "chore: edit plan-d.md itself (no plan token)"
  )
  sha11c="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha11c" --emitter post-commit
  if grep -qF "\"sha\":\"$sha11c\"" "$f_fd" 2>/dev/null && grep -qF '"plan_slug":"plan-d"' "$f_fd" 2>/dev/null; then
    pass "FINDING 5: a change to plan-d.md itself still routes to plan-d"
  else
    fail "FINDING 5: expected sha11c attributed to plan-d in $f_fd"
  fi

  echo "Scenario 12 (FINDING 6 regression): a true 2-parent merge commit's merge-side plan-file touch surfaces via 'diff-tree -m' (was invisible without -m)"
  local sha_merge
  (
    cd "$REPO" || exit 1
    git checkout -q -b feature-finding6
    echo "feature-branch-only edit" >> docs/plans/plan-a.md
    git commit -q -am "feat: feature-branch edit to plan-a (no plan token)"
    git checkout -q "$FIXTURE_BRANCH"
    echo "unrelated base-branch change" >> README.md
    git commit -q -am "chore: unrelated base-branch change (no plan token)"
    git merge --no-ff -q feature-finding6 -m "Merge feature-finding6 (no plan token)"
  )
  sha_merge="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha_merge" --emitter post-commit
  if grep -qF "\"sha\":\"$sha_merge\"" "$f_fa" 2>/dev/null && grep -qF '"plan_slug":"plan-a"' "$f_fa" 2>/dev/null; then
    pass "FINDING 6: 2-parent merge commit's plan-a.md touch surfaces via diff-tree -m (was invisible before)"
  else
    fail "FINDING 6: expected sha_merge attributed to plan-a in $f_fa"
  fi

  echo "Scenario 13 (FINDING 7 regression): unresolvable 'plan: <typo>' trailer falls through to the diff fallback instead of orphaning a real plan touch"
  local sha13
  (
    cd "$REPO" || exit 1
    echo "another plan-a edit" >> docs/plans/plan-a.md
    git commit -q -am "$(printf 'fix(plan-a): flip task 3\n\nplan: someday-nonexistent-slug\n')"
  )
  sha13="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha13" --emitter post-commit
  if grep -qF "\"sha\":\"$sha13\"" "$f_fa" 2>/dev/null && grep -qF '"plan_slug":"plan-a"' "$f_fa" 2>/dev/null; then
    pass "FINDING 7: unresolvable 'plan: someday-nonexistent-slug' token falls through to the diff fallback -> correctly attributed to plan-a"
  else
    fail "FINDING 7: expected sha13 attributed to plan-a via diff fallback despite unresolvable token"
  fi
  if grep -rqF '"plan_slug":"someday-nonexistent-slug"' "$PROGRESS_LOG_STATE_DIR" 2>/dev/null; then
    fail "FINDING 7: the unresolvable token slug must not be used as an attributed plan_slug"
  else
    pass "FINDING 7: unresolvable token slug never appears as an attributed plan_slug"
  fi

  echo "Scenario 14 (FINDING 7 regression, no false positive): a VALID 'plan: plan-a' trailer still short-circuits correctly even when the diff touches no plan file"
  local sha14
  (
    cd "$REPO" || exit 1
    echo "some unrelated code, no plan file touched" > unrelated-code.txt
    git add unrelated-code.txt
    git commit -q -am "$(printf 'feat: unrelated code change\n\nplan: plan-a\n')"
  )
  sha14="$(git -C "$REPO" rev-parse HEAD)"
  ms_emit_merged_for_commit "$REPO" "$sha14" --emitter post-commit
  if grep -qF "\"sha\":\"$sha14\"" "$f_fa" 2>/dev/null && grep -qF '"plan_slug":"plan-a"' "$f_fa" 2>/dev/null; then
    pass "FINDING 7: a VALID 'plan: plan-a' trailer still short-circuits correctly (no unnecessary fallback to diff)"
  else
    fail "FINDING 7: expected sha14 attributed to plan-a via the valid token path"
  fi

  echo ""
  echo "---- Incremental-cursor regression fixtures (2026-07-16 fix: scan-repo must CONVERGE, not re-scan the same window forever) ----"
  export PROGRESS_LOG_STATE_DIR="$TMP/pl-state-cursor"
  mkdir -p "$PROGRESS_LOG_STATE_DIR"

  local REPO2="$TMP/fixture-repo-cursor"
  mkdir -p "$REPO2"
  (
    cd "$REPO2" || exit 1
    git init -q
    git config core.hooksPath ""
    git config user.email "test@example.test"
    git config user.name "Test"
    mkdir -p docs/plans
    cat > docs/plans/plan-cur.md <<'EOF'
# Plan: Cursor fixture (incremental-scan regression)
Status: ACTIVE
ask-id: ask-fixture-cur

## Tasks
- [ ] 1. first task
EOF
    git add . && git commit -q -m "init"
  )
  local sha15_init sha15_t1 sha15_t2 sha15_t3
  sha15_init="$(git -C "$REPO2" rev-parse HEAD)"
  (
    cd "$REPO2" || exit 1
    echo "task 1 done" >> docs/plans/plan-cur.md
    git commit -q -am "$(printf 'fix(plan-cur): flip task 1\n\nplan: plan-cur\n')"
  )
  sha15_t1="$(git -C "$REPO2" rev-parse HEAD)"
  (
    cd "$REPO2" || exit 1
    echo "task 2 done" >> docs/plans/plan-cur.md
    git commit -q -am "$(printf 'fix(plan-cur): flip task 2\n\nplan: plan-cur\n')"
  )
  sha15_t2="$(git -C "$REPO2" rev-parse HEAD)"
  (
    cd "$REPO2" || exit 1
    echo "task 3 done" >> docs/plans/plan-cur.md
    git commit -q -am "$(printf 'fix(plan-cur): flip task 3\n\nplan: plan-cur\n')"
  )
  sha15_t3="$(git -C "$REPO2" rev-parse HEAD)"
  git -C "$REPO2" update-ref refs/remotes/origin/master "$sha15_t3"
  local cur_repo_key cur_path
  cur_repo_key="$(_ms_repo_key "$REPO2")"
  cur_path="$(_ms_cursor_path "$REPO2")"
  local fcur="$PROGRESS_LOG_STATE_DIR/ask-fixture-cur.jsonl"

  echo "Scenario 15: first scan-repo run (no cursor yet) backfills every commit AND leaves the cursor at HEAD"
  ms_scan_repo_for_merges "$REPO2" --emitter auditor
  if [[ -f "$fcur" ]] \
     && grep -qF "\"sha\":\"$sha15_init\"" "$fcur" \
     && grep -qF "\"sha\":\"$sha15_t1\"" "$fcur" \
     && grep -qF "\"sha\":\"$sha15_t2\"" "$fcur" \
     && grep -qF "\"sha\":\"$sha15_t3\"" "$fcur"; then
    pass "Scenario 15: first run backfilled all 4 commits (init + 3 flips), same as today"
  else
    fail "Scenario 15: expected all 4 shas attributed to plan-cur in $fcur"
  fi
  local cursor_after15; cursor_after15="$(cat "$cur_path" 2>/dev/null)"
  if [[ "$cursor_after15" == "$sha15_t3" ]]; then
    pass "Scenario 15: cursor left at HEAD ($sha15_t3) after the first run"
  else
    fail "Scenario 15: expected cursor==$sha15_t3, got '$cursor_after15'"
  fi

  echo "Scenario 16: second run with no new commits scans ZERO commits, cursor unchanged"
  local before16; before16="$(wc -l < "$fcur" 2>/dev/null || echo 0)"
  ms_scan_repo_for_merges "$REPO2" --emitter auditor
  local after16; after16="$(wc -l < "$fcur" 2>/dev/null || echo 0)"
  local cursor_after16; cursor_after16="$(cat "$cur_path" 2>/dev/null)"
  if [[ "$before16" == "$after16" && "$cursor_after16" == "$sha15_t3" ]]; then
    pass "Scenario 16: no new commits -> no new lines emitted, cursor stays at $sha15_t3"
  else
    fail "Scenario 16: expected a no-op (before=$before16 after=$after16 cursor=$cursor_after16)"
  fi

  echo "Scenario 17: 2 new commits land; scan-repo scans exactly those 2 (via the cursor-narrowed range) and advances the cursor to the new HEAD"
  (
    cd "$REPO2" || exit 1
    echo "task 4 done" >> docs/plans/plan-cur.md
    git commit -q -am "$(printf 'fix(plan-cur): flip task 4\n\nplan: plan-cur\n')"
  )
  local sha17a; sha17a="$(git -C "$REPO2" rev-parse HEAD)"
  (
    cd "$REPO2" || exit 1
    echo "task 5 done" >> docs/plans/plan-cur.md
    git commit -q -am "$(printf 'fix(plan-cur): flip task 5\n\nplan: plan-cur\n')"
  )
  local sha17b; sha17b="$(git -C "$REPO2" rev-parse HEAD)"
  git -C "$REPO2" update-ref refs/remotes/origin/master "$sha17b"
  ms_scan_repo_for_merges "$REPO2" --emitter auditor
  if grep -qF "\"sha\":\"$sha17a\"" "$fcur" && grep -qF "\"sha\":\"$sha17b\"" "$fcur"; then
    pass "Scenario 17: both newly-landed commits were scanned via the cursor-narrowed range"
  else
    fail "Scenario 17: expected both $sha17a and $sha17b in $fcur"
  fi
  local cursor_after17; cursor_after17="$(cat "$cur_path" 2>/dev/null)"
  if [[ "$cursor_after17" == "$sha17b" ]]; then
    pass "Scenario 17: cursor advanced to the new HEAD ($sha17b)"
  else
    fail "Scenario 17: expected cursor==$sha17b, got '$cursor_after17'"
  fi

  echo "Scenario 18 (KILL-RESILIENCE, load-bearing): a run bounded to --limit 1 makes only PARTIAL progress and advances the cursor to exactly the oldest new commit (never straight to HEAD); a follow-up run resumes FROM THE CURSOR and completes the remainder without re-emitting what already landed"
  (
    cd "$REPO2" || exit 1
    echo "task 6 done" >> docs/plans/plan-cur.md
    git commit -q -am "$(printf 'fix(plan-cur): flip task 6\n\nplan: plan-cur\n')"
  )
  local sha18a; sha18a="$(git -C "$REPO2" rev-parse HEAD)"
  (
    cd "$REPO2" || exit 1
    echo "task 7 done" >> docs/plans/plan-cur.md
    git commit -q -am "$(printf 'fix(plan-cur): flip task 7\n\nplan: plan-cur\n')"
  )
  local sha18b; sha18b="$(git -C "$REPO2" rev-parse HEAD)"
  git -C "$REPO2" update-ref refs/remotes/origin/master "$sha18b"

  # Simulate the real-world tree-kill: bound this run to exactly the oldest
  # ONE not-yet-scanned commit -- mirrors what a 60s kill leaves behind:
  # partial progress, never zero progress.
  ms_scan_repo_for_merges "$REPO2" --emitter auditor --limit 1
  local cursor_mid; cursor_mid="$(cat "$cur_path" 2>/dev/null)"
  if [[ "$cursor_mid" == "$sha18a" ]]; then
    pass "Scenario 18: the --limit-1 'killed' run advanced the cursor only to the oldest new commit ($sha18a), not straight to HEAD"
  else
    fail "Scenario 18: expected cursor==$sha18a after the bounded run, got '$cursor_mid'"
  fi
  if grep -qF "\"sha\":\"$sha18a\"" "$fcur" && ! grep -qF "\"sha\":\"$sha18b\"" "$fcur"; then
    pass "Scenario 18: the bounded run emitted sha18a but NOT YET sha18b (genuinely partial progress)"
  else
    fail "Scenario 18: expected sha18a emitted and sha18b absent after the bounded run"
  fi

  ms_scan_repo_for_merges "$REPO2" --emitter auditor
  local cursor_final18; cursor_final18="$(cat "$cur_path" 2>/dev/null)"
  if [[ "$cursor_final18" == "$sha18b" ]]; then
    pass "Scenario 18: the follow-up run resumed from the cursor and advanced the rest of the way to HEAD ($sha18b)"
  else
    fail "Scenario 18: expected cursor==$sha18b after the follow-up run, got '$cursor_final18'"
  fi
  if [[ "$(grep -cF "\"sha\":\"$sha18a\"" "$fcur")" == "1" ]]; then
    pass "Scenario 18: sha18a's event was NOT re-emitted by the follow-up run (the cursor genuinely resumed past it, not merely deduped)"
  else
    fail "Scenario 18: expected exactly one sha18a line even after the follow-up run"
  fi
  if grep -qF "\"sha\":\"$sha18b\"" "$fcur"; then
    pass "Scenario 18: sha18b was emitted by the follow-up run (kill-resilience convergence complete)"
  else
    fail "Scenario 18: expected sha18b emitted by the follow-up run"
  fi

  echo "Scenario 19: a format-corrupt cursor file falls back to a full scan and self-heals (never errors)"
  printf 'not-a-real-sha-xyz\n' > "$cur_path"
  local before19; before19="$(wc -l < "$fcur" 2>/dev/null || echo 0)"
  ms_scan_repo_for_merges "$REPO2" --emitter auditor
  local rc19=$?
  local after19; after19="$(wc -l < "$fcur" 2>/dev/null || echo 0)"
  if [[ "$rc19" == "0" ]]; then
    pass "Scenario 19: scan-repo never errors on a format-corrupt cursor file (exit 0)"
  else
    fail "Scenario 19: expected exit 0 despite a corrupt cursor, got $rc19"
  fi
  local healed19; healed19="$(cat "$cur_path" 2>/dev/null)"
  if [[ "$healed19" == "$sha18b" ]]; then
    pass "Scenario 19: corrupt cursor self-healed to a valid SHA ($sha18b) via the fallback full scan"
  else
    fail "Scenario 19: expected cursor to self-heal to $sha18b, got '$healed19'"
  fi
  if [[ "$after19" == "$before19" ]]; then
    pass "Scenario 19: the fallback full-scan re-processing stayed idempotent (no duplicate lines despite ignoring the corrupt cursor)"
  else
    fail "Scenario 19: expected idempotent line count, before=$before19 after=$after19"
  fi

  echo "Scenario 19b: a well-formed-but-nonexistent SHA in the cursor also falls back safely (git cat-file -e catches it, not just the regex)"
  printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' > "$cur_path"
  ms_scan_repo_for_merges "$REPO2" --emitter auditor
  local rc19b=$?
  if [[ "$rc19b" == "0" ]]; then
    pass "Scenario 19b: a well-formed-but-nonexistent cursor SHA never errors (exit 0)"
  else
    fail "Scenario 19b: expected exit 0, got $rc19b"
  fi
  local healed19b; healed19b="$(cat "$cur_path" 2>/dev/null)"
  if [[ "$healed19b" == "$sha18b" ]]; then
    pass "Scenario 19b: the nonexistent-SHA cursor self-healed to a valid SHA ($sha18b)"
  else
    fail "Scenario 19b: expected cursor to self-heal to $sha18b, got '$healed19b'"
  fi

  echo "Scenario 20: cursor writes are sandbox-only -- self-test never touched the real ~/.claude/state/merge-scan-cursors"
  if [[ ! -e "${HOME:-$PWD}/.claude/state/merge-scan-cursors/$cur_repo_key" ]]; then
    pass "Scenario 20: self-test never wrote a cursor file under the real state dir"
  else
    fail "Scenario 20: unexpected real cursor file under \${HOME}/.claude/state/merge-scan-cursors/$cur_repo_key"
  fi

  rm -rf "$TMP" 2>/dev/null || true

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# CLI dispatch (only when EXECUTED directly, not sourced -- mirrors
# progress-log-lib.sh's own executed-vs-sourced convention, so Task 12's
# Node auditor can shell out to this file without a separate wrapper
# script)
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    scan-repo)
      shift
      ms_scan_repo_for_merges "$@"
      exit 0
      ;;
    scan-commit)
      shift
      _repo="${1:-}"; shift || true
      _sha="${1:-}"; shift || true
      ms_emit_merged_for_commit "$_repo" "$_sha" "$@"
      exit 0
      ;;
    --self-test|--selftest|self-test)
      ms_self_test
      exit $?
      ;;
    -h|--help|"")
      cat <<'USAGE'
merge-scan-lib.sh — SHA -> ask attribution + `merged` progress-log
backfill (ask-rooted-workstreams-p1 Task 5b: "Master-merge emission" --
the GUARANTEED lane).

Verbs:
  scan-repo <repo-root> [--since <sha-or-ref>] [--limit <n>]
                        [--emitter <name>]
                          Walk `git log origin/master` and emit one
                          `merged` event per resolvable-plan-slug commit.
                          Idempotent: safe to re-run over the same range.
                          Without --since, resumes from a persisted
                          per-repo cursor (~/.claude/state/merge-scan-
                          cursors/<repo-key>) so steady-state cycles only
                          scan newly-landed commits.
  scan-commit <repo-root> <sha> [--emitter <name>]
                          Emit `merged` event(s) for exactly one commit.
  --self-test             Run the sandboxed self-test suite.

Sourced usage (post-commit splice / any bash caller):
  source ".../hooks/lib/merge-scan-lib.sh"
  ms_emit_merged_for_commit "$repo_root" "$sha" --emitter post-commit
USAGE
      exit 0
      ;;
    *)
      echo "merge-scan-lib.sh: unknown verb '${1:-}' (see --help)" >&2
      exit 0
      ;;
  esac
fi
