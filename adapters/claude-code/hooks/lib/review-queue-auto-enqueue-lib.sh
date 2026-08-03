#!/bin/bash
# review-queue-auto-enqueue-lib.sh — the mechanical "WHETHER a review
# happens" splice (docs/plans/review-independence.md, RI1b).
#
# WHY THIS IS A SEPARATE LIBRARY, NOT INLINED DIRECTLY INTO
# review-record-commit-gate.sh's OWN uncovered-computation loop
#   Built standalone because this worktree's branch base initially did not
#   carry adapters/claude-code/hooks/review-record-commit-gate.sh at all (it
#   had landed on wip/harness-hardening-2026-07-29 while this worktree's
#   history had diverged before that point) -- editing a file this session
#   could not read would have violated Chesterton's Fence. Isolating the
#   auto-enqueue LOGIC here meant it was fully built and self-tested against
#   the REAL review-record-gate-lib.sh before the branches reconciled. THE
#   BRANCHES HAVE SINCE RECONCILED (a `git rebase` onto wip/harness-
#   hardening-2026-07-29's tip, same session) and the splice below IS NOW
#   APPLIED in review-record-commit-gate.sh -- kept as a standalone library
#   rather than inlined, since that gate's own control flow is delicate
#   (61+ pre-existing self-test scenarios) and a bug in THIS file must never
#   be able to affect that gate's exit code:
#
#     source "$_RRCG_SELF_DIR/lib/review-queue-auto-enqueue-lib.sh" 2>/dev/null
#     if command -v rq_auto_enqueue_uncovered >/dev/null 2>&1; then
#       rq_auto_enqueue_uncovered "$repo_root" 2>/dev/null
#     fi
#
#   Inserted right after the rebase/merge exemption check (after the
#   `[[ -d "$gitdir/rebase-merge" ...` block) and BEFORE the
#   REVIEW_RECORD_GATE_OVERRIDE check -- i.e. unconditionally, on every
#   invocation that reaches that point, regardless of whether the commit is
#   ultimately overridden or blocked. This is deliberate: "committing IS
#   enqueueing" (operator-directed 2026-07-29) must not depend on which exit
#   path the gate eventually takes -- an overridden commit still needs
#   independent review just as much as a blocked one. Mutation-proven:
#   review-record-commit-gate.sh's own self-test Scenario 23 stages an
#   uncovered file, commits, and asserts a review-queue.sh item was written;
#   temporarily deleting this splice drives Scenario 23 (and ONLY Scenario
#   23, of 62) to FAIL.
#
# WHAT IT DOES
#   Re-derives the SAME staged/in-surface/uncovered computation
#   review-record-commit-gate.sh's own predicate makes (deliberately
#   redundant rather than threading state through the caller -- isolating
#   this from that gate's delicate, 47-scenario-tested control flow is safer
#   than reaching into it), and for any uncovered file, calls
#   `review-queue.sh enqueue`. Content-key deduping in review-queue.sh
#   itself means retried commit attempts over the same uncovered content
#   never pile up duplicate queue items.
#
# FAIL-OPEN, ALWAYS. This function's return value is NEVER checked by a
# caller that also blocks a commit -- a bug here must never brick `git
# commit`. Every failure path is swallowed. Production mode runs the actual
# enqueue call BACKGROUNDED (fire-and-forget, output discarded) so a slow
# filesystem or a jq hiccup can never add commit-hook latency; RQ_AUTO_
# ENQUEUE_MODE=sync (test-only, mirrors the *_CMD test-override convention
# other cadence scripts in this repo use) runs it synchronously so
# self-test assertions are deterministic instead of racing a background job.
#
# API: source this file, then call:
#   rq_auto_enqueue_uncovered <repo_root> [session_id]
#
# Verification: bash review-queue-auto-enqueue-lib.sh --self-test (same
# direct-invocation-only convention as review-record-gate-lib.sh -- guarded
# so sourcing this file from another script's --self-test never re-triggers
# this one).

set -uo pipefail

_RQAE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rq_auto_enqueue_uncovered() {
  local repo_root="${1:-}" session_id="${2:-}"
  [[ -n "$repo_root" ]] || return 0

  if ! command -v rrg_in_surface >/dev/null 2>&1 || ! command -v rrg_is_covered >/dev/null 2>&1; then
    # shellcheck source=./review-record-gate-lib.sh
    source "$_RQAE_LIB_DIR/review-record-gate-lib.sh" 2>/dev/null || return 0
  fi
  command -v rrg_in_surface >/dev/null 2>&1 || return 0
  command -v rrg_is_covered >/dev/null 2>&1 || return 0
  command -v git >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local queue_sh="$_RQAE_LIB_DIR/../../scripts/review-queue.sh"
  [[ -f "$queue_sh" ]] || return 0

  # NUL-FRAMED, QUOTING DISABLED (harness-reviewer CRITICAL 2, round 4).
  # `--name-only` without `-z` emits C-quoted paths for non-ASCII and
  # backslash, and rrg_in_surface — the very predicate this feeds — answers
  # OUT for the quoted rendering. PROVEN on the push gate against a bare
  # remote with `hooks/pré-push-gate.sh`. Here the consequence is that the
  # review-queue item is silently never filed for such a path, so the
  # sanctioned pathway has nothing to claim and the push gate's own remedy
  # ("if no queue item exists yet ... commit-gate's RI1b splice enqueues one
  # automatically") quietly does not happen. BOTH tokens are required:
  # core.quotePath=false alone still quotes a backslash.
  # ACMRT, not ACMR: a typechange is a change to in-surface content too.
  local _rqae_tmp
  _rqae_tmp="$(mktemp -d "${TMPDIR:-/tmp}/rqae.XXXXXX" 2>/dev/null)" || return 0
  local _staged_z="$_rqae_tmp/staged.z"
  git -C "$repo_root" -c core.quotePath=false diff --cached --name-only -z \
      --diff-filter=ACMRT > "$_staged_z" 2>/dev/null || { rm -rf "$_rqae_tmp"; return 0; }
  [[ -s "$_staged_z" ]] || { rm -rf "$_rqae_tmp"; return 0; }

  local -a upaths=() ushas=()
  local path sha
  while IFS= read -r -d '' path; do
    [[ -n "$path" ]] || continue
    rrg_in_surface "$path" || continue
    sha="$(git -C "$repo_root" rev-parse ":$path" 2>/dev/null)" || sha=""
    [[ -n "$sha" ]] || continue
    rrg_is_covered "$repo_root" "" "$path" "$sha" && continue
    upaths+=("$path")
    ushas+=("$sha")
  done < "$_staged_z"
  rm -rf "$_rqae_tmp"

  [[ "${#upaths[@]}" -eq 0 ]] && return 0

  [[ -z "$session_id" ]] && session_id="${CLAUDE_SESSION_ID:-unknown-session}"
  local branch
  branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch="unknown"

  local -a args=(enqueue --repo-root "$repo_root" --branch "$branch" --enqueuer-session-id "$session_id")
  local i
  for i in "${!upaths[@]}"; do
    args+=(--file "${upaths[$i]}" --blob-sha "${ushas[$i]}")
  done

  if [[ "${RQ_AUTO_ENQUEUE_MODE:-background}" == "sync" ]]; then
    bash "$queue_sh" "${args[@]}" >/dev/null 2>&1
  else
    ( bash "$queue_sh" "${args[@]}" >/dev/null 2>&1 & ) 2>/dev/null
  fi
  return 0
}

# ---------------------------------------------------------------------------
# --self-test (direct invocation only -- guarded so a caller sourcing this
# file, e.g. review-record-commit-gate.sh's own --self-test, never re-fires
# this suite as a side effect of sourcing).
# ---------------------------------------------------------------------------
_rqae_self_test() {
  local PASSED=0 FAILED=0 tmp
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t rqaeself)
  [[ -z "$tmp" || ! -d "$tmp" ]] && { echo "cannot mktemp" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local REPO="$tmp/repo" QDIR="$tmp/queue"
  mkdir -p "$REPO/adapters/claude-code/hooks" "$REPO/adapters/claude-code/doctrine" "$REPO/docs/reviews/records"
  printf '#!/bin/bash\necho v1\n' > "$REPO/adapters/claude-code/hooks/alpha.sh"
  printf 'prose\n' > "$REPO/adapters/claude-code/doctrine/notes.md"
  # An EMPTY-but-PRESENT index.json takes this fixture OUT of rrg_is_covered's
  # bootstrap fail-open (Amendment E: "neither coverage file exists at all" ->
  # everything reads COVERED) -- without this, S1-S3 below would trivially
  # see every staged file as already covered and enqueue nothing, proving
  # nothing.
  printf '{"schema_version":1,"entries":[]}\n' > "$REPO/docs/reviews/records/index.json"
  ( cd "$REPO" && git init -q && git config user.email t@example.com && git config user.name T )

  export REVIEW_QUEUE_STATE_DIR="$QDIR"
  export RQ_AUTO_ENQUEUE_MODE="sync"

  # ---- S1: staging an UNCOVERED in-surface file and calling the function
  # enqueues exactly one item for it ----
  ( cd "$REPO" && git add adapters/claude-code/hooks/alpha.sh )
  rq_auto_enqueue_uncovered "$REPO" "session-test-1"
  local n
  n=$(bash "$_RQAE_LIB_DIR/../../scripts/review-queue.sh" list --status queued --format ids 2>/dev/null | grep -c 'rq-')
  if [[ "$n" -eq 1 ]]; then
    echo "self-test (S1) uncovered-staged-file-enqueues-one-item: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S1) uncovered-staged-file-enqueues-one-item: FAIL (n=$n)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S2: the enqueued item carries the right path/branch/session_id ----
  local item_id item_json
  item_id=$(bash "$_RQAE_LIB_DIR/../../scripts/review-queue.sh" list --status queued --format ids 2>/dev/null | head -1)
  item_json=$(bash "$_RQAE_LIB_DIR/../../scripts/review-queue.sh" get --item-id "$item_id" 2>/dev/null)
  if printf '%s' "$item_json" | jq -e '.covered_files[] | select(.path == "adapters/claude-code/hooks/alpha.sh")' >/dev/null 2>&1 \
     && [[ "$(printf '%s' "$item_json" | jq -r .enqueuer_principal.session_id)" == "session-test-1" ]]; then
    echo "self-test (S2) enqueued-item-carries-correct-fields: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S2) enqueued-item-carries-correct-fields: FAIL (item_json=$item_json)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S3: re-invoking for the SAME staged content is idempotent (no
  # second queue item created for identical uncovered content) ----
  rq_auto_enqueue_uncovered "$REPO" "session-test-1"
  n=$(bash "$_RQAE_LIB_DIR/../../scripts/review-queue.sh" list --status queued --format ids 2>/dev/null | grep -c 'rq-')
  if [[ "$n" -eq 1 ]]; then
    echo "self-test (S3) reinvocation-same-content-idempotent: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S3) reinvocation-same-content-idempotent: FAIL (n=$n)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S4: an OUT-OF-SURFACE staged file (doctrine/*.md) enqueues NOTHING
  # new ----
  rm -rf "$QDIR"
  ( cd "$REPO" && git reset -q && git add adapters/claude-code/doctrine/notes.md )
  rq_auto_enqueue_uncovered "$REPO" "session-test-1"
  n=$(bash "$_RQAE_LIB_DIR/../../scripts/review-queue.sh" list --status all --format ids 2>/dev/null | grep -c 'rq-')
  if [[ "$n" -eq 0 ]]; then
    echo "self-test (S4) out-of-surface-file-enqueues-nothing: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S4) out-of-surface-file-enqueues-nothing: FAIL (n=$n)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S5: a COVERED file (bootstrap-grandfathered) enqueues nothing ----
  rm -rf "$QDIR"
  ( cd "$REPO" && git add -A && git commit -q -m "snapshot for grandfather" )
  bash "$_RQAE_LIB_DIR/../../scripts/write-review-record.sh" bootstrap-grandfather --repo-root "$REPO" --ref HEAD >/dev/null 2>&1
  ( cd "$REPO" && git add adapters/claude-code/hooks/alpha.sh )
  rq_auto_enqueue_uncovered "$REPO" "session-test-1"
  n=$(bash "$_RQAE_LIB_DIR/../../scripts/review-queue.sh" list --status all --format ids 2>/dev/null | grep -c 'rq-')
  if [[ "$n" -eq 0 ]]; then
    echo "self-test (S5) grandfathered-covered-file-enqueues-nothing: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S5) grandfathered-covered-file-enqueues-nothing: FAIL (n=$n)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S6: nothing staged at all -> no-op, no error ----
  rm -rf "$QDIR"
  ( cd "$REPO" && git reset -q )
  rq_auto_enqueue_uncovered "$REPO" "session-test-1"
  local rc=$?
  n=$(bash "$_RQAE_LIB_DIR/../../scripts/review-queue.sh" list --status all --format ids 2>/dev/null | grep -c 'rq-')
  if [[ "$rc" -eq 0 ]] && [[ "$n" -eq 0 ]]; then
    echo "self-test (S6) nothing-staged-is-noop: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S6) nothing-staged-is-noop: FAIL (rc=$rc n=$n)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S7: missing review-queue.sh degrades to a silent no-op (fail-open,
  # never breaks the caller) ----
  local FAKE_LIB_DIR="$tmp/fake-lib-dir"
  mkdir -p "$FAKE_LIB_DIR"
  cp "$_RQAE_LIB_DIR/review-queue-auto-enqueue-lib.sh" "$FAKE_LIB_DIR/"
  cp "$_RQAE_LIB_DIR/review-record-gate-lib.sh" "$FAKE_LIB_DIR/"
  # NOTE: no scripts/ sibling created, so ../../scripts/review-queue.sh
  # cannot resolve for this fake lib dir.
  ( cd "$REPO" && git add adapters/claude-code/hooks/alpha.sh )
  ( unset -f rq_auto_enqueue_uncovered 2>/dev/null
    # shellcheck disable=SC1090
    source "$FAKE_LIB_DIR/review-queue-auto-enqueue-lib.sh"
    rq_auto_enqueue_uncovered "$REPO" "session-test-1" )
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "self-test (S7) missing-review-queue-sh-degrades-silently: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S7) missing-review-queue-sh-degrades-silently: FAIL (rc=$rc)" >&2
    FAILED=$((FAILED+1))
  fi

  unset REVIEW_QUEUE_STATE_DIR RQ_AUTO_ENQUEUE_MODE
  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed (of $((PASSED+FAILED)) scenarios)" >&2
  [[ "$FAILED" -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  _rqae_self_test
  exit $?
fi
