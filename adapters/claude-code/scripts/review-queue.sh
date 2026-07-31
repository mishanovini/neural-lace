#!/bin/bash
# review-queue.sh — the review queue (docs/plans/review-independence.md, RI1).
#
# WHY THIS EXISTS
#   review-record-commit-gate.sh already BLOCKS a commit that touches an
#   uncovered in-surface file (docs/reviews/records/*, harness-governance-
#   batch-2026-07-15 task 2 + the 2026-07-29 commit-time-carrier landing).
#   What it could not do is guarantee the review that eventually covers that
#   content came from a DIFFERENT principal than the one who wrote it —
#   nothing stopped the authoring session from dispatching harness-reviewer
#   itself and writing its own PASS record (self-approval). This queue is the
#   structural fix's FIRST deterministic point: WHETHER a review happens.
#   RI1b (the splice in review-record-commit-gate.sh) makes `enqueue` the
#   MECHANICAL side effect of a blocked commit — the authoring session never
#   decides to enqueue; attempting to commit uncovered content IS enqueueing.
#
#   Design pivot (docs/decisions/067-review-independence-same-session-
#   pathway.md, operator-directed 2026-07-29): independence is about the
#   PATHWAY (a genuinely fresh session/process reviews, never the authoring
#   session), not about physical machine locality. The default storage below
#   is a plain per-machine state dir — zero configuration required — and
#   remains pointable at a coord-repo clone for an operator who wants
#   cross-machine visibility for free via the pre-existing coord-sync.sh
#   cadence (which already `git add -A`s its clone directory); that is
#   optional hardening, not something this script builds or depends on.
#
# THE AUTHORING SESSION'S ONLY LEGAL INTERACTION IS `enqueue` (mechanically,
# via the RI1b splice, never called directly by an authoring session) AND
# `list` (read-only). `claim`/`complete`/`mark-stale` are the REVIEWING
# principal's verbs — review-runner.sh (RI2) is their only caller.
#
# STORAGE
#   One JSON file per item (never a shared ledger — the exact reasoning
#   write-review-record.sh's header already gives for records: N parallel
#   writers must never conflict on one file), under
#   $REVIEW_QUEUE_STATE_DIR/<item-id>.json (default
#   $HOME/.claude/state/review-queue, overridable per-call via --state-dir
#   for tests and for pointing at a synced coord-repo clone directory).
#   Items are mutated in place (status transitions), always via the shared
#   state-json-init.sh validity guard + atomic tmp-then-mv write — there is
#   no separate index; `list` globs the directory directly (small N, no hot
#   deploy-time read path the way docs/reviews/records/index.json is).
#
# QUEUE ITEM SCHEMA (schema_version 1)
#   {
#     schema_version, item_id, status: queued|claimed|completed|stale,
#     branch, covered_files: [{path, blob_sha}], content_key,
#     enqueuer_principal: {hostname, account, session_id}, created_at,
#     claimant_principal: {hostname, account, session_id} | null, claimed_at,
#     result: {record_id, record_commit_sha} | null, completed_at,
#     stale_reason
#   }
#   `content_key` (sha256 of the sorted covered_files array) is the DEDUPE
#   key, mirroring the review-record primitive's own content-addressed
#   identity model (docs/design-notes/review-record-primitive.md) rather
#   than a commit SHA or a plan-task id — the same file set enqueued twice
#   while still OPEN (queued/claimed) is one item, not two.
#
# Subcommands:
#   enqueue --branch <b> --file <path> --blob-sha <sha> [--file <path>
#           --blob-sha <sha> ...] [--enqueuer-session-id <id>]
#           [--enqueuer-hostname <h>] [--enqueuer-account <a>]
#           [--state-dir <dir>] [--repo-root <path>]
#     -> idempotent while an OPEN (queued|claimed) item with the same
#        content_key exists. Prints "<item-file-path>\n<item_id>" to stderr;
#        rc 0.
#   list [--status queued|claimed|completed|stale|all] [--state-dir <dir>]
#        [--format json|ids]
#     -> prints matching items (JSON array, default) or one item_id per
#        line (--format ids) to stdout. rc 0.
#   get --item-id <id> [--state-dir <dir>]
#     -> prints the item's JSON to stdout; rc 1 if not found.
#   claim --item-id <id> [--claimant-session-id <id>] [--claimant-hostname <h>]
#         [--claimant-account <a>] [--state-dir <dir>]
#     -> rc 2 if the item is not `queued`. rc 2 (SELF-CLAIM REFUSED) if the
#        claimant's session_id matches the item's enqueuer session_id — the
#        mechanical guarantee that the authoring session can never become
#        its own reviewer. Else sets status=claimed + claimant_principal +
#        claimed_at. rc 0.
#   complete --item-id <id> --record-id <rid> --record-commit-sha <sha>
#            [--state-dir <dir>]
#     -> rc 2 if the item is not `claimed`. Else sets status=completed +
#        result + completed_at. rc 0.
#   mark-stale --item-id <id> --reason <text> [--state-dir <dir>]
#     -> rc 2 if the item is `completed`. Else sets status=stale +
#        stale_reason. rc 0. (review-runner.sh calls this when the branch
#        moved past the recorded blob_sha before/while claiming.)
#   --self-test
#   --help
#
# Exit codes: 0 success; 1 not-found (get); 2 usage/validation/refusal error.

set -uo pipefail

SCRIPT_NAME="review-queue.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/state-json-init.sh
source "$SCRIPT_DIR/lib/state-json-init.sh" 2>/dev/null || {
  echo "$SCRIPT_NAME: cannot source lib/state-json-init.sh" >&2
  exit 2
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME enqueue --branch <b> --file <path> --blob-sha <sha> \\
         [--file <path> --blob-sha <sha> ...] [--enqueuer-session-id <id>] \\
         [--enqueuer-hostname <h>] [--enqueuer-account <a>] \\
         [--state-dir <dir>] [--repo-root <path>]
       $SCRIPT_NAME list [--status queued|claimed|completed|stale|all] \\
         [--state-dir <dir>] [--format json|ids]
       $SCRIPT_NAME get --item-id <id> [--state-dir <dir>]
       $SCRIPT_NAME claim --item-id <id> [--claimant-session-id <id>] \\
         [--claimant-hostname <h>] [--claimant-account <a>] [--state-dir <dir>]
       $SCRIPT_NAME complete --item-id <id> --record-id <rid> \\
         --record-commit-sha <sha> [--state-dir <dir>]
       $SCRIPT_NAME mark-stale --item-id <id> --reason <text> [--state-dir <dir>]
       $SCRIPT_NAME --self-test
       $SCRIPT_NAME --help
EOF
}

_rq_state_dir_default() {
  if [[ -n "${REVIEW_QUEUE_STATE_DIR:-}" ]]; then
    printf '%s' "$REVIEW_QUEUE_STATE_DIR"
    return 0
  fi
  # Sandbox-by-default under HARNESS_SELFTEST (same convention as
  # hooks/lib/signal-ledger.sh's _signal_ledger_path): a CALLER that forgets
  # to override REVIEW_QUEUE_STATE_DIR during a self-test run (e.g.
  # review-record-commit-gate.sh's own suite, which exercises the real
  # review-queue-auto-enqueue-lib.sh splice against fixture repos) must
  # never write fixture garbage into the operator's real
  # ~/.claude/state/review-queue/ -- this defaulting is the backstop, not
  # the primary control (every self-test in THIS repo's own suite still
  # passes --state-dir explicitly).
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/review-queue-selftest-%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/review-queue' "${HOME:-$PWD}"
}

_rq_hostname() {
  local h; h=$(hostname 2>/dev/null || echo "")
  [ -n "$h" ] || h="${COMPUTERNAME:-${HOSTNAME:-unknown-host}}"
  printf '%s' "$h"
}

_rq_account_default() {
  git config user.email 2>/dev/null || echo "unknown"
}

_rq_iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Portable sha256 -- prefers shasum (macOS/BSD default) then sha256sum (Linux).
_rq_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    # No hashing tool at all -- degrade to a fixed placeholder rather than
    # crash; dedupe simply never matches (fail toward "enqueue duplicates",
    # never toward "silently drop a real review need").
    printf 'no-sha256-tool-available'
  fi
}

_rq_content_key() {
  # $1 = covered_files JSON array
  printf '%s' "$1" | jq -c 'sort_by(.path, .blob_sha)' 2>/dev/null | _rq_sha256
}

# ---------------------------------------------------------------------------
# enqueue
# ---------------------------------------------------------------------------
cmd_enqueue() {
  local branch="" state_dir="" repo_root=""
  local e_session="" e_host="" e_account=""
  local -a paths=() shas=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) branch="$2"; shift 2 ;;
      --file) paths+=("$2"); shift 2 ;;
      --blob-sha) shas+=("$2"); shift 2 ;;
      --enqueuer-session-id) e_session="$2"; shift 2 ;;
      --enqueuer-hostname) e_host="$2"; shift 2 ;;
      --enqueuer-account) e_account="$2"; shift 2 ;;
      --state-dir) state_dir="$2"; shift 2 ;;
      --repo-root) repo_root="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; usage >&2; return 2 ;;
    esac
  done

  [[ -z "$branch" ]] && { echo "$SCRIPT_NAME: --branch is required" >&2; return 2; }
  [[ "${#paths[@]}" -eq 0 ]] && { echo "$SCRIPT_NAME: at least one --file/--blob-sha pair is required" >&2; return 2; }
  [[ "${#paths[@]}" -ne "${#shas[@]}" ]] && { echo "$SCRIPT_NAME: --file and --blob-sha counts must match (${#paths[@]} vs ${#shas[@]})" >&2; return 2; }

  [[ -z "$state_dir" ]] && state_dir="$(_rq_state_dir_default)"
  [[ -z "$e_session" ]] && e_session="${CLAUDE_SESSION_ID:-unknown-session}"
  [[ -z "$e_host" ]] && e_host="$(_rq_hostname)"
  [[ -z "$e_account" ]] && e_account="$(_rq_account_default)"

  mkdir -p "$state_dir" || { echo "$SCRIPT_NAME: cannot create $state_dir" >&2; return 2; }

  local cov="[]" i
  for i in "${!paths[@]}"; do
    cov=$(printf '%s' "$cov" | jq --arg p "${paths[$i]}" --arg s "${shas[$i]}" '. + [{path:$p, blob_sha:$s}]')
  done
  cov=$(printf '%s' "$cov" | jq -c 'sort_by(.path, .blob_sha)')

  local content_key; content_key="$(_rq_content_key "$cov")"

  # Idempotent while an OPEN item (queued|claimed) already carries this exact
  # content_key -- "committing IS enqueueing" must never pile up N identical
  # items for the same uncovered content across N retried commit attempts.
  local existing f st ck
  shopt -s nullglob
  for f in "$state_dir"/*.json; do
    [[ -f "$f" ]] || continue
    st=$(jq -r '.status // empty' "$f" 2>/dev/null)
    case "$st" in queued|claimed) ;; *) continue ;; esac
    ck=$(jq -r '.content_key // empty' "$f" 2>/dev/null)
    if [[ "$ck" == "$content_key" ]]; then
      existing=$(jq -r '.item_id // empty' "$f" 2>/dev/null)
      break
    fi
  done
  shopt -u nullglob
  if [[ -n "${existing:-}" ]]; then
    echo "$f" >&2
    echo "$existing" >&2
    return 0
  fi

  local shortid item_id created_at
  shortid=$(printf '%04x%04x' "$RANDOM" "$RANDOM")
  item_id="rq-$(date -u +%Y%m%d)-${shortid}"
  created_at="$(_rq_iso_now)"

  local item_json
  item_json=$(jq -n \
    --argjson schema_version 1 \
    --arg item_id "$item_id" \
    --arg branch "$branch" \
    --argjson covered_files "$cov" \
    --arg content_key "$content_key" \
    --arg e_host "$e_host" --arg e_account "$e_account" --arg e_session "$e_session" \
    --arg created_at "$created_at" \
    '{
      schema_version: $schema_version,
      item_id: $item_id,
      status: "queued",
      branch: $branch,
      covered_files: $covered_files,
      content_key: $content_key,
      enqueuer_principal: {hostname: $e_host, account: $e_account, session_id: $e_session},
      created_at: $created_at,
      claimant_principal: null,
      claimed_at: null,
      result: null,
      completed_at: null,
      stale_reason: null
    }')

  local out_file="$state_dir/${item_id}.json"
  local tmp; tmp=$(mktemp "${out_file}.XXXXXX" 2>/dev/null) || { echo "$SCRIPT_NAME: mktemp failed" >&2; return 2; }
  printf '%s\n' "$item_json" > "$tmp" && mv "$tmp" "$out_file" || { rm -f "$tmp"; echo "$SCRIPT_NAME: cannot write $out_file" >&2; return 2; }

  echo "$out_file" >&2
  echo "$item_id" >&2
  return 0
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------
cmd_list() {
  local status_filter="all" state_dir="" fmt="json"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) status_filter="$2"; shift 2 ;;
      --state-dir) state_dir="$2"; shift 2 ;;
      --format) fmt="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; return 2 ;;
    esac
  done
  [[ -z "$state_dir" ]] && state_dir="$(_rq_state_dir_default)"
  [[ -d "$state_dir" ]] || { [[ "$fmt" == "ids" ]] && return 0; echo "[]"; return 0; }

  local -a items=()
  local f st
  shopt -s nullglob
  for f in "$state_dir"/*.json; do
    [[ -f "$f" ]] || continue
    if [[ "$status_filter" != "all" ]]; then
      st=$(jq -r '.status // empty' "$f" 2>/dev/null)
      [[ "$st" == "$status_filter" ]] || continue
    fi
    items+=("$f")
  done
  shopt -u nullglob

  if [[ "$fmt" == "ids" ]]; then
    local it
    for it in "${items[@]:-}"; do
      [[ -n "$it" ]] || continue
      jq -r '.item_id' "$it" 2>/dev/null
    done
    return 0
  fi

  if [[ "${#items[@]}" -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  jq -s 'sort_by(.created_at, .item_id)' "${items[@]}" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# get
# ---------------------------------------------------------------------------
cmd_get() {
  local item_id="" state_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --item-id) item_id="$2"; shift 2 ;;
      --state-dir) state_dir="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; return 2 ;;
    esac
  done
  [[ -z "$item_id" ]] && { echo "$SCRIPT_NAME: --item-id is required" >&2; return 2; }
  [[ -z "$state_dir" ]] && state_dir="$(_rq_state_dir_default)"
  local f="$state_dir/${item_id}.json"
  [[ -f "$f" ]] || { echo "$SCRIPT_NAME: no such item: $item_id" >&2; return 1; }
  cat "$f"
  return 0
}

# ---------------------------------------------------------------------------
# claim
# ---------------------------------------------------------------------------
cmd_claim() {
  local item_id="" state_dir="" c_session="" c_host="" c_account=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --item-id) item_id="$2"; shift 2 ;;
      --claimant-session-id) c_session="$2"; shift 2 ;;
      --claimant-hostname) c_host="$2"; shift 2 ;;
      --claimant-account) c_account="$2"; shift 2 ;;
      --state-dir) state_dir="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; return 2 ;;
    esac
  done
  [[ -z "$item_id" ]] && { echo "$SCRIPT_NAME: --item-id is required" >&2; return 2; }
  [[ -z "$state_dir" ]] && state_dir="$(_rq_state_dir_default)"
  [[ -z "$c_session" ]] && c_session="${CLAUDE_SESSION_ID:-unknown-session}"
  [[ -z "$c_host" ]] && c_host="$(_rq_hostname)"
  [[ -z "$c_account" ]] && c_account="$(_rq_account_default)"

  local f="$state_dir/${item_id}.json"
  [[ -f "$f" ]] || { echo "$SCRIPT_NAME: no such item: $item_id" >&2; return 2; }

  local st; st=$(jq -r '.status // empty' "$f" 2>/dev/null)
  if [[ "$st" != "queued" ]]; then
    echo "$SCRIPT_NAME: item $item_id is not queued (status=$st) -- refusing claim" >&2
    return 2
  fi

  # THE self-approval guard (review-independence plan RI1/RI2, operator-
  # directed 2026-07-29): the claimant's session_id must NOT match the
  # enqueuer's. This is the mechanical guarantee that the authoring session
  # can never become its own reviewer -- "same machine, same account" is
  # fine and expected (docs/decisions/067-review-independence-same-session-
  # pathway.md); "same SESSION" is exactly the self-approval this plan
  # exists to eliminate, and it is refused unconditionally -- no override
  # flag, by design (a fudgeable guard here defeats the entire point).
  local e_session; e_session=$(jq -r '.enqueuer_principal.session_id // empty' "$f" 2>/dev/null)
  if [[ -n "$e_session" ]] && [[ "$e_session" == "$c_session" ]]; then
    echo "$SCRIPT_NAME: SELF-CLAIM REFUSED -- item $item_id was enqueued by session '$e_session'; the claiming session is the SAME session. A reviewer must be a genuinely different session/process than the one that authored the work (docs/decisions/067-review-independence-same-session-pathway.md). Dispatch a fresh session (or a subagent invocation with its own CLAUDE_SESSION_ID) to review this." >&2
    return 2
  fi

  local claimed_at; claimed_at="$(_rq_iso_now)"
  local updated
  updated=$(jq --arg host "$c_host" --arg account "$c_account" --arg session "$c_session" --arg ts "$claimed_at" \
    '.status = "claimed" | .claimant_principal = {hostname:$host, account:$account, session_id:$session} | .claimed_at = $ts' "$f" 2>/dev/null)
  [[ -z "$updated" ]] && { echo "$SCRIPT_NAME: internal error updating $f" >&2; return 2; }
  local tmp; tmp=$(mktemp "${f}.XXXXXX" 2>/dev/null) || return 2
  printf '%s\n' "$updated" > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; return 2; }
  echo "CLAIMED $item_id" >&2
  return 0
}

# ---------------------------------------------------------------------------
# complete
# ---------------------------------------------------------------------------
cmd_complete() {
  local item_id="" state_dir="" record_id="" record_commit_sha=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --item-id) item_id="$2"; shift 2 ;;
      --record-id) record_id="$2"; shift 2 ;;
      --record-commit-sha) record_commit_sha="$2"; shift 2 ;;
      --state-dir) state_dir="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; return 2 ;;
    esac
  done
  [[ -z "$item_id" ]] && { echo "$SCRIPT_NAME: --item-id is required" >&2; return 2; }
  [[ -z "$record_id" ]] && { echo "$SCRIPT_NAME: --record-id is required" >&2; return 2; }
  [[ -z "$record_commit_sha" ]] && { echo "$SCRIPT_NAME: --record-commit-sha is required" >&2; return 2; }
  [[ -z "$state_dir" ]] && state_dir="$(_rq_state_dir_default)"

  local f="$state_dir/${item_id}.json"
  [[ -f "$f" ]] || { echo "$SCRIPT_NAME: no such item: $item_id" >&2; return 2; }
  local st; st=$(jq -r '.status // empty' "$f" 2>/dev/null)
  if [[ "$st" != "claimed" ]]; then
    echo "$SCRIPT_NAME: item $item_id is not claimed (status=$st) -- refusing complete" >&2
    return 2
  fi

  local completed_at; completed_at="$(_rq_iso_now)"
  local updated
  updated=$(jq --arg rid "$record_id" --arg rsha "$record_commit_sha" --arg ts "$completed_at" \
    '.status = "completed" | .result = {record_id:$rid, record_commit_sha:$rsha} | .completed_at = $ts' "$f" 2>/dev/null)
  [[ -z "$updated" ]] && { echo "$SCRIPT_NAME: internal error updating $f" >&2; return 2; }
  local tmp; tmp=$(mktemp "${f}.XXXXXX" 2>/dev/null) || return 2
  printf '%s\n' "$updated" > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; return 2; }
  echo "COMPLETED $item_id" >&2
  return 0
}

# ---------------------------------------------------------------------------
# mark-stale
# ---------------------------------------------------------------------------
cmd_mark_stale() {
  local item_id="" state_dir="" reason=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --item-id) item_id="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
      --state-dir) state_dir="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; return 2 ;;
    esac
  done
  [[ -z "$item_id" ]] && { echo "$SCRIPT_NAME: --item-id is required" >&2; return 2; }
  [[ -z "$reason" ]] && { echo "$SCRIPT_NAME: --reason is required" >&2; return 2; }
  [[ -z "$state_dir" ]] && state_dir="$(_rq_state_dir_default)"

  local f="$state_dir/${item_id}.json"
  [[ -f "$f" ]] || { echo "$SCRIPT_NAME: no such item: $item_id" >&2; return 2; }
  local st; st=$(jq -r '.status // empty' "$f" 2>/dev/null)
  if [[ "$st" == "completed" ]]; then
    echo "$SCRIPT_NAME: item $item_id is already completed -- refusing to mark stale" >&2
    return 2
  fi

  local updated
  updated=$(jq --arg reason "$reason" '.status = "stale" | .stale_reason = $reason' "$f" 2>/dev/null)
  [[ -z "$updated" ]] && { echo "$SCRIPT_NAME: internal error updating $f" >&2; return 2; }
  local tmp; tmp=$(mktemp "${f}.XXXXXX" 2>/dev/null) || return 2
  printf '%s\n' "$updated" > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; return 2; }
  echo "STALE $item_id" >&2
  return 0
}

# ---------------------------------------------------------------------------
# --self-test
# ---------------------------------------------------------------------------
run_self_test() {
  local PASSED=0 FAILED=0 tmp SELF_PATH saved_pwd
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t rqself)
  [[ -z "$tmp" || ! -d "$tmp" ]] && { echo "cannot mktemp" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN
  saved_pwd="$PWD"
  if [[ "$0" == /* ]]; then SELF_PATH="$0"; else SELF_PATH="$saved_pwd/$0"; fi

  local SD="$tmp/queue"

  # ---- S1: enqueue creates a queued item with the right fields ----
  local out item_id
  out=$("$SELF_PATH" enqueue --branch "wip/feature" --file "adapters/claude-code/scripts/foo.sh" \
    --blob-sha "aaaa1111" --enqueuer-session-id "session-author" \
    --enqueuer-hostname "host-a" --enqueuer-account "acct-a" --state-dir "$SD" 2>&1)
  item_id=$(printf '%s\n' "$out" | tail -1)
  if [[ -f "$SD/${item_id}.json" ]] \
     && [[ "$(jq -r .status "$SD/${item_id}.json")" == "queued" ]] \
     && [[ "$(jq -r .branch "$SD/${item_id}.json")" == "wip/feature" ]] \
     && [[ "$(jq -r .enqueuer_principal.session_id "$SD/${item_id}.json")" == "session-author" ]]; then
    echo "self-test (S1) enqueue-creates-queued-item: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S1) enqueue-creates-queued-item: FAIL (out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S2: re-enqueueing the SAME content while OPEN is idempotent (no
  # duplicate item file) ----
  local before_count after_count
  before_count=$(ls "$SD"/*.json 2>/dev/null | wc -l | tr -d ' ')
  out2=$("$SELF_PATH" enqueue --branch "wip/feature" --file "adapters/claude-code/scripts/foo.sh" \
    --blob-sha "aaaa1111" --enqueuer-session-id "session-author" --state-dir "$SD" 2>&1)
  after_count=$(ls "$SD"/*.json 2>/dev/null | wc -l | tr -d ' ')
  item_id2=$(printf '%s\n' "$out2" | tail -1)
  if [[ "$before_count" == "$after_count" ]] && [[ "$item_id2" == "$item_id" ]]; then
    echo "self-test (S2) enqueue-idempotent-while-open: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S2) enqueue-idempotent-while-open: FAIL (before=$before_count after=$after_count id=$item_id id2=$item_id2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S3: list --status queued shows the item; --format ids works ----
  out=$("$SELF_PATH" list --status queued --state-dir "$SD" 2>&1)
  if printf '%s' "$out" | jq -e --arg id "$item_id" '.[] | select(.item_id == $id)' >/dev/null 2>&1; then
    echo "self-test (S3a) list-shows-queued-item: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S3a) list-shows-queued-item: FAIL (out=$out)" >&2
    FAILED=$((FAILED+1))
  fi
  out=$("$SELF_PATH" list --status queued --state-dir "$SD" --format ids 2>&1)
  if printf '%s\n' "$out" | grep -qx "$item_id"; then
    echo "self-test (S3b) list-format-ids: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S3b) list-format-ids: FAIL (out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S4: claim by a DIFFERENT session succeeds ----
  out=$("$SELF_PATH" claim --item-id "$item_id" --claimant-session-id "session-reviewer" \
    --claimant-hostname "host-a" --claimant-account "acct-a" --state-dir "$SD" 2>&1)
  rc=$?
  if [[ "$rc" -eq 0 ]] \
     && [[ "$(jq -r .status "$SD/${item_id}.json")" == "claimed" ]] \
     && [[ "$(jq -r .claimant_principal.session_id "$SD/${item_id}.json")" == "session-reviewer" ]]; then
    echo "self-test (S4) claim-by-different-session-succeeds: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S4) claim-by-different-session-succeeds: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S5: SELF-CLAIM (same session_id as enqueuer) on a FRESH item is
  # REFUSED rc=2 -- the core self-approval guard ----
  out=$("$SELF_PATH" enqueue --branch "wip/feature2" --file "adapters/claude-code/scripts/bar.sh" \
    --blob-sha "bbbb2222" --enqueuer-session-id "session-author" --state-dir "$SD" 2>&1)
  local item_id3; item_id3=$(printf '%s\n' "$out" | tail -1)
  out=$("$SELF_PATH" claim --item-id "$item_id3" --claimant-session-id "session-author" --state-dir "$SD" 2>&1)
  rc=$?
  if [[ "$rc" -eq 2 ]] && [[ "$(jq -r .status "$SD/${item_id3}.json")" == "queued" ]]; then
    echo "self-test (S5) self-claim-refused: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S5) self-claim-refused: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S6: claim on an already-claimed item is refused ----
  out=$("$SELF_PATH" claim --item-id "$item_id" --claimant-session-id "session-reviewer-2" --state-dir "$SD" 2>&1)
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    echo "self-test (S6) claim-already-claimed-refused: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S6) claim-already-claimed-refused: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S7: complete after claim sets status + links the record ----
  out=$("$SELF_PATH" complete --item-id "$item_id" --record-id "hcr-fixture-1" \
    --record-commit-sha "deadbeef" --state-dir "$SD" 2>&1)
  rc=$?
  if [[ "$rc" -eq 0 ]] \
     && [[ "$(jq -r .status "$SD/${item_id}.json")" == "completed" ]] \
     && [[ "$(jq -r .result.record_id "$SD/${item_id}.json")" == "hcr-fixture-1" ]]; then
    echo "self-test (S7) complete-links-record: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S7) complete-links-record: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S8: complete without a prior claim is refused ----
  out=$("$SELF_PATH" complete --item-id "$item_id3" --record-id "x" --record-commit-sha "y" --state-dir "$SD" 2>&1)
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    echo "self-test (S8) complete-without-claim-refused: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S8) complete-without-claim-refused: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S9: mark-stale removes the item from `list --status queued` ----
  "$SELF_PATH" mark-stale --item-id "$item_id3" --reason "branch moved past recorded blob_sha" --state-dir "$SD" >/dev/null 2>&1
  out=$("$SELF_PATH" list --status queued --state-dir "$SD" --format ids 2>&1)
  if ! printf '%s\n' "$out" | grep -qx "$item_id3"; then
    echo "self-test (S9) mark-stale-removes-from-queued-list: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S9) mark-stale-removes-from-queued-list: FAIL (out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S10: re-enqueueing the SAME content_key after the prior item
  # COMPLETED creates a FRESH item (re-review is allowed, not blocked) ----
  before_count=$(ls "$SD"/*.json 2>/dev/null | wc -l | tr -d ' ')
  out=$("$SELF_PATH" enqueue --branch "wip/feature" --file "adapters/claude-code/scripts/foo.sh" \
    --blob-sha "aaaa1111" --enqueuer-session-id "session-author" --state-dir "$SD" 2>&1)
  after_count=$(ls "$SD"/*.json 2>/dev/null | wc -l | tr -d ' ')
  local item_id4; item_id4=$(printf '%s\n' "$out" | tail -1)
  if [[ "$after_count" -gt "$before_count" ]] && [[ "$item_id4" != "$item_id" ]]; then
    echo "self-test (S10) reenqueue-after-completed-creates-fresh-item: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S10) reenqueue-after-completed-creates-fresh-item: FAIL (before=$before_count after=$after_count id4=$item_id4 id=$item_id)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S11: --state-dir is fully overridable, and a directory shared
  # between two "logically separate" invocations sees the same items --
  # this is the mechanism a synced coord-repo clone would use for cross-
  # machine visibility (docs/decisions/067-review-independence-same-
  # session-pathway.md): pointing REVIEW_QUEUE_STATE_DIR at a shared/
  # synced directory is the whole mechanism, proven generically here ----
  local SHARED="$tmp/shared-queue"
  ( unset REVIEW_QUEUE_STATE_DIR; REVIEW_QUEUE_STATE_DIR="$SHARED" "$SELF_PATH" enqueue \
      --branch "wip/shared" --file "adapters/claude-code/scripts/shared.sh" --blob-sha "cccc3333" \
      --enqueuer-session-id "session-machine-a" >/dev/null 2>&1 )
  out=$( REVIEW_QUEUE_STATE_DIR="$SHARED" "$SELF_PATH" list --status queued --format ids 2>&1 )
  if [[ "$(printf '%s\n' "$out" | grep -c 'rq-')" -ge 1 ]]; then
    echo "self-test (S11) shared-state-dir-visible-across-invocations: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S11) shared-state-dir-visible-across-invocations: FAIL (out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S12: get on a nonexistent item returns rc=1 ----
  "$SELF_PATH" get --item-id "rq-nonexistent" --state-dir "$SD" >/dev/null 2>&1
  rc=$?
  if [[ "$rc" -eq 1 ]]; then
    echo "self-test (S12) get-nonexistent-item-rc1: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S12) get-nonexistent-item-rc1: FAIL (rc=$rc)" >&2
    FAILED=$((FAILED+1))
  fi

  cd "$saved_pwd" 2>/dev/null || true
  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed (of $((PASSED+FAILED)) scenarios)" >&2
  [[ "$FAILED" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  --self-test) run_self_test; exit $? ;;
  --help|-h) usage; exit 0 ;;
  enqueue) shift; cmd_enqueue "$@"; exit $? ;;
  list) shift; cmd_list "$@"; exit $? ;;
  get) shift; cmd_get "$@"; exit $? ;;
  claim) shift; cmd_claim "$@"; exit $? ;;
  complete) shift; cmd_complete "$@"; exit $? ;;
  mark-stale) shift; cmd_mark_stale "$@"; exit $? ;;
  *) usage >&2; exit 2 ;;
esac
