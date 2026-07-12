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
#      slug; multiple lines are all kept (deduped).
#   2. FALLBACK (no token found): the commit's changed-file list touches
#      `docs/plans/<slug>.md`, `docs/plans/archive/<slug>.md` (closed plans
#      move there — see close-plan.sh), or that plan's evidence file/dir
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
# HONEST LIMITATION: the diff-fallback (step 2 above) lists a commit's
# changed files via `git diff-tree --no-commit-id --name-only -r --root`,
# which diffs against the FIRST parent. A true two-parent local merge
# commit (as opposed to a `gh pr merge` squash commit, which is always a
# single-parent ordinary commit) is diffed against its first parent same as
# any other commit here — a file that changed only on the merged-in side
# relative to a common ancestor, but not vs. the first parent, would not
# surface. The TOKEN path (step 1) is unaffected either way, since it only
# reads the commit message. This is the same scope boundary constraint 5's
# "best-effort, never blocks" already accepts for this whole task.

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
  files="$(git -C "$repo_root" diff-tree --no-commit-id --name-only -r --root "$sha" 2>/dev/null)"
  [[ -z "$files" ]] && return 0
  local f base
  printf '%s\n' "$files" | while IFS= read -r f; do
    case "$f" in
      docs/plans/*.md)
        base="${f#docs/plans/}"
        base="${base#archive/}"
        case "$base" in
          *-evidence.md) printf '%s\n' "${base%-evidence.md}" ;;
          *) printf '%s\n' "${base%.md}" ;;
        esac
        ;;
      docs/plans/*-evidence/*)
        base="${f#docs/plans/}"
        base="${base%%/*}"
        printf '%s\n' "${base%-evidence}"
        ;;
      *) ;;
    esac
  done | awk '!seen[$0]++'
}

# ----------------------------------------------------------------------
# _ms_commit_plan_slugs <repo-root> <sha> — the full step 1 -> step 2
# plan-slug resolution (see SHA -> ASK ATTRIBUTION RULE above). Empty when
# neither step resolves anything (SKIP the commit — anti-noise).
# ----------------------------------------------------------------------
_ms_commit_plan_slugs() {
  local repo_root="$1" sha="$2"
  local msg tok
  msg="$(git -C "$repo_root" log -1 --format=%B "$sha" 2>/dev/null)"
  tok="$(_ms_plan_token_slugs "$msg")"
  if [[ -n "$tok" ]]; then
    printf '%s\n' "$tok"
    return 0
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
# ms_scan_repo_for_merges <repo-root> [--since <sha-or-ref>] [--limit <n>]
#                          [--emitter <name>]
#
#   THE GUARANTEED LANE (Task 12 consumes this). Walks `git log
# origin/master` (bounded by --limit, default 200; --since narrows the
# range to `<since>..origin/master` for incremental scanning) and calls
# ms_emit_merged_for_commit for every sha. Safe to re-run over the same
# range repeatedly: pl_emit's own repo+sha natural-key dedup makes every
# call idempotent (Task 12's relaxed-cadence auditor loop relies on this —
# no bookkeeping of "have I scanned this sha before" needs to live here).
# ----------------------------------------------------------------------
ms_scan_repo_for_merges() {
  local repo_root="$1"; shift || true
  [[ -z "${repo_root:-}" ]] && return 0
  local since="" limit="200" emitter="auditor"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) since="${2:-}"; shift 2 ;;
      --limit) limit="${2:-200}"; shift 2 ;;
      --emitter) emitter="${2:-auditor}"; shift 2 ;;
      *) shift ;;
    esac
  done
  git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local range="origin/master"
  [[ -n "$since" ]] && range="${since}..origin/master"

  local shas
  shas="$(git -C "$repo_root" log "$range" --format=%H -n "$limit" 2>/dev/null)"
  [[ -z "$shas" ]] && return 0

  local sha
  while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    ms_emit_merged_for_commit "$repo_root" "$sha" --emitter "$emitter"
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

  local REPO="$TMP/fixture-repo"
  mkdir -p "$REPO"
  (
    cd "$REPO" || exit 1
    git init -q
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
