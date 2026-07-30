#!/bin/bash
# review-runner.sh — the reviewing principal's CLI (docs/plans/
# review-independence.md, RI2).
#
# WHO RUNS THIS
#   Any Claude Code session that did NOT author the reviewed content — a
#   fresh interactive session, a subagent dispatch, a scheduled headless
#   `claude -p` invocation, or a different machine entirely. Design pivot
#   (docs/decisions/067-review-independence-same-session-pathway.md,
#   operator-directed 2026-07-29): "It's all the same claude, agents,
#   harness ... why can't [the existing adversarial review agents] be your
#   principal?" — independence is about the PATHWAY (a genuinely different
#   session/process reviews, using the EXISTING adversarial reviewer agents
#   such as harness-reviewer as its workforce), never about physical
#   machine locality. `independence: pathway` is therefore the default
#   tier; `independence: cross-machine` is optional additional hardening
#   recorded truthfully when the claimant's hostname genuinely differs, but
#   nothing in this script or the doctor blocks on its absence.
#
#   THE AUTHORING SESSION MUST NEVER RUN `finalize` (or `claim`) FOR ITS OWN
#   WORK. review-queue.sh's `claim` verb refuses (rc=2) the moment the
#   claimant's session_id matches the item's enqueuer session_id — that is
#   the mechanical guarantee, not a convention this script re-checks.
#
# THE THREE DETERMINISTIC POINTS THIS SCRIPT OWNS (2 AND 3 OF 3; RI1/RI1b
# own point 1, WHETHER a review happens):
#   2. WHAT THE REVIEWER SEES: `prepare` emits ONLY the git diff the runner
#      computes itself (base_ref...branch, per path) plus a pointer to the
#      FIXED, versioned instruction template (config/review-instructions.md,
#      hashed) — never any enqueuer-supplied free text. The queue item this
#      reads carries only {branch, paths, blob_shas, enqueuer principal,
#      timestamp} (review-queue.sh's schema) — there is no context field to
#      leak through in the first place.
#   3. WHAT THE VERDICT BECOMES: `finalize` writes the review record AND
#      commits it, in THIS process, under THIS process's own git identity —
#      the authoring session never touches a record file after RI1b lands.
#      The claimant identity used in the record is the one review-queue.sh
#      recorded at `claim` time (re-read from the item, never re-trusted
#      from fresh CLI flags at finalize time), so a session cannot claim
#      honestly and then finalize under a different, unverified identity.
#
# STALENESS (the false-green class): `claim` AND `finalize` both re-verify
# every covered_files {path, blob_sha} against the CURRENT tip of the
# item's recorded branch. Any mismatch marks the item `stale`
# (review-queue.sh mark-stale) and refuses (rc=3) rather than reviewing
# content that already moved on.
#
# Subcommands:
#   claim --item-id <id> --repo-root <path> [--base-ref <ref>]
#         [--claimant-session-id <id>] [--claimant-hostname <h>]
#         [--claimant-account <a>] [--state-dir <dir>]
#     -> rc 2 self-claim/already-claimed refusal (from review-queue.sh);
#        rc 3 STALE (branch moved past a recorded blob_sha -- item marked
#        stale, re-enqueue needed); rc 0 CLAIMED.
#   prepare --item-id <id> --repo-root <path> [--base-ref <ref>]
#           [--state-dir <dir>]
#     -> rc 2 if the item is not `claimed`. Else prints, to stdout: a
#        banner naming config/review-instructions.md + its sha256, then
#        `git diff <base_ref>...<branch> -- <path>` for every covered file.
#        rc 0.
#   finalize --item-id <id> --repo-root <path> --verdict <PASS|REFORMULATE|
#            REJECT> --quote <text> --plan-ref <ref>
#            [--findings-summary <text>] [--reviewer <agent>]
#            [--reviewer-model <model>] [--base-ref <ref>] [--state-dir <dir>]
#     -> rc 2 if the item is not `claimed`. rc 3 if content went stale since
#        claim. Else: writes + commits the review record under THIS
#        process's git identity, marks the queue item completed
#        (record_id + record commit sha), rc 0. --reviewer defaults to
#        "harness-reviewer".
#   --self-test
#   --help
#
# Exit codes: 0 success; 2 usage/refusal/not-claimed; 3 stale content.

set -uo pipefail

SCRIPT_NAME="review-runner.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE_SH="$SCRIPT_DIR/review-queue.sh"
WRITER_SH="$SCRIPT_DIR/write-review-record.sh"
INSTRUCTIONS_MD="$SCRIPT_DIR/../config/review-instructions.md"

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME claim --item-id <id> --repo-root <path> [--base-ref <ref>] \\
         [--claimant-session-id <id>] [--claimant-hostname <h>] \\
         [--claimant-account <a>] [--state-dir <dir>]
       $SCRIPT_NAME prepare --item-id <id> --repo-root <path> [--base-ref <ref>] \\
         [--state-dir <dir>]
       $SCRIPT_NAME finalize --item-id <id> --repo-root <path> \\
         --verdict <PASS|REFORMULATE|REJECT> --quote <text> --plan-ref <ref> \\
         [--findings-summary <text>] [--reviewer <agent>] \\
         [--reviewer-model <model>] [--base-ref <ref>] [--state-dir <dir>]
       $SCRIPT_NAME --self-test
       $SCRIPT_NAME --help
EOF
}

_rr_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else printf 'no-sha256-tool-available'; fi
}

# _rr_stale_check <repo_root> <item_json> -> rc 0 if every covered_files
# entry's recorded blob_sha still matches the CURRENT tip of the item's
# branch; rc 1 (with a reason on stdout) otherwise.
_rr_stale_check() {
  local repo_root="$1" item_json="$2"
  local branch; branch=$(printf '%s' "$item_json" | jq -r '.branch')
  local n; n=$(printf '%s' "$item_json" | jq '.covered_files | length')
  local i path recorded_sha current_sha
  i=0
  while [[ "$i" -lt "$n" ]]; do
    path=$(printf '%s' "$item_json" | jq -r ".covered_files[$i].path")
    recorded_sha=$(printf '%s' "$item_json" | jq -r ".covered_files[$i].blob_sha")
    current_sha=$(git -C "$repo_root" rev-parse --verify --quiet "${branch}:${path}" 2>/dev/null) || current_sha=""
    if [[ "$current_sha" != "$recorded_sha" ]]; then
      printf 'branch %s moved: %s is now %s, item recorded %s' "$branch" "$path" "${current_sha:-<absent>}" "$recorded_sha"
      return 1
    fi
    i=$((i+1))
  done
  return 0
}

cmd_claim() {
  local item_id="" repo_root="" base_ref="origin/master" state_dir=""
  local c_session="" c_host="" c_account=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --item-id) item_id="$2"; shift 2 ;;
      --repo-root) repo_root="$2"; shift 2 ;;
      --base-ref) base_ref="$2"; shift 2 ;;
      --claimant-session-id) c_session="$2"; shift 2 ;;
      --claimant-hostname) c_host="$2"; shift 2 ;;
      --claimant-account) c_account="$2"; shift 2 ;;
      --state-dir) state_dir="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; usage >&2; return 2 ;;
    esac
  done
  [[ -z "$item_id" ]] && { echo "$SCRIPT_NAME: --item-id is required" >&2; return 2; }
  [[ -z "$repo_root" ]] && { echo "$SCRIPT_NAME: --repo-root is required" >&2; return 2; }

  local -a qargs=(claim --item-id "$item_id")
  [[ -n "$c_session" ]] && qargs+=(--claimant-session-id "$c_session")
  [[ -n "$c_host" ]] && qargs+=(--claimant-hostname "$c_host")
  [[ -n "$c_account" ]] && qargs+=(--claimant-account "$c_account")
  [[ -n "$state_dir" ]] && qargs+=(--state-dir "$state_dir")

  bash "$QUEUE_SH" "${qargs[@]}" >/dev/null
  local rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "$SCRIPT_NAME: claim refused by review-queue.sh (rc=$rc)" >&2
    return 2
  fi

  local -a gargs=(get --item-id "$item_id")
  [[ -n "$state_dir" ]] && gargs+=(--state-dir "$state_dir")
  local item_json; item_json=$(bash "$QUEUE_SH" "${gargs[@]}" 2>/dev/null)

  local reason
  if ! reason=$(_rr_stale_check "$repo_root" "$item_json"); then
    local -a sargs=(mark-stale --item-id "$item_id" --reason "$reason")
    [[ -n "$state_dir" ]] && sargs+=(--state-dir "$state_dir")
    bash "$QUEUE_SH" "${sargs[@]}" >/dev/null 2>&1
    echo "$SCRIPT_NAME: STALE -- $reason" >&2
    return 3
  fi

  echo "CLAIMED $item_id" >&2
  return 0
}

cmd_prepare() {
  local item_id="" repo_root="" base_ref="origin/master" state_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --item-id) item_id="$2"; shift 2 ;;
      --repo-root) repo_root="$2"; shift 2 ;;
      --base-ref) base_ref="$2"; shift 2 ;;
      --state-dir) state_dir="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; usage >&2; return 2 ;;
    esac
  done
  [[ -z "$item_id" ]] && { echo "$SCRIPT_NAME: --item-id is required" >&2; return 2; }
  [[ -z "$repo_root" ]] && { echo "$SCRIPT_NAME: --repo-root is required" >&2; return 2; }

  local -a gargs=(get --item-id "$item_id")
  [[ -n "$state_dir" ]] && gargs+=(--state-dir "$state_dir")
  local item_json; item_json=$(bash "$QUEUE_SH" "${gargs[@]}" 2>/dev/null)
  [[ -z "$item_json" ]] && { echo "$SCRIPT_NAME: no such item: $item_id" >&2; return 2; }
  local st; st=$(printf '%s' "$item_json" | jq -r .status)
  [[ "$st" == "claimed" ]] || { echo "$SCRIPT_NAME: item $item_id is not claimed (status=$st) -- claim it first" >&2; return 2; }

  local instr_sha="unavailable"
  [[ -f "$INSTRUCTIONS_MD" ]] && instr_sha=$(_rr_sha256 < "$INSTRUCTIONS_MD")

  echo "================================================================"
  echo "REVIEW-RUNNER PREPARE -- item $item_id"
  echo "Reviewer instructions: config/review-instructions.md (sha256 ${instr_sha})"
  echo "Read that file for the fixed review rubric before judging the diff below."
  echo "Everything below this line is derived by this script directly from git"
  echo "-- no enqueuer-supplied free text is ever included."
  echo "================================================================"

  local branch; branch=$(printf '%s' "$item_json" | jq -r .branch)
  local n; n=$(printf '%s' "$item_json" | jq '.covered_files | length')
  local i path
  i=0
  while [[ "$i" -lt "$n" ]]; do
    path=$(printf '%s' "$item_json" | jq -r ".covered_files[$i].path")
    echo ""
    echo "---- $path (branch $branch vs $base_ref) ----"
    git -C "$repo_root" diff "${base_ref}...${branch}" -- "$path" 2>/dev/null \
      || git -C "$repo_root" show "${branch}:${path}" 2>/dev/null \
      || echo "(unable to compute a diff or show content for $path)"
    i=$((i+1))
  done
  return 0
}

cmd_finalize() {
  local item_id="" repo_root="" base_ref="origin/master" state_dir=""
  local verdict="" quote="" plan_ref="" findings_summary="" reviewer="harness-reviewer" reviewer_model=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --item-id) item_id="$2"; shift 2 ;;
      --repo-root) repo_root="$2"; shift 2 ;;
      --base-ref) base_ref="$2"; shift 2 ;;
      --state-dir) state_dir="$2"; shift 2 ;;
      --verdict) verdict="$2"; shift 2 ;;
      --quote) quote="$2"; shift 2 ;;
      --plan-ref) plan_ref="$2"; shift 2 ;;
      --findings-summary) findings_summary="$2"; shift 2 ;;
      --reviewer) reviewer="$2"; shift 2 ;;
      --reviewer-model) reviewer_model="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; usage >&2; return 2 ;;
    esac
  done
  [[ -z "$item_id" ]] && { echo "$SCRIPT_NAME: --item-id is required" >&2; return 2; }
  [[ -z "$repo_root" ]] && { echo "$SCRIPT_NAME: --repo-root is required" >&2; return 2; }
  case "$verdict" in
    PASS|REFORMULATE|REJECT) ;;
    *) echo "$SCRIPT_NAME: --verdict must be PASS|REFORMULATE|REJECT" >&2; return 2 ;;
  esac
  [[ -z "$quote" ]] && { echo "$SCRIPT_NAME: --quote is required" >&2; return 2; }
  [[ -z "$plan_ref" ]] && { echo "$SCRIPT_NAME: --plan-ref is required" >&2; return 2; }

  local -a gargs=(get --item-id "$item_id")
  [[ -n "$state_dir" ]] && gargs+=(--state-dir "$state_dir")
  local item_json; item_json=$(bash "$QUEUE_SH" "${gargs[@]}" 2>/dev/null)
  [[ -z "$item_json" ]] && { echo "$SCRIPT_NAME: no such item: $item_id" >&2; return 2; }
  local st; st=$(printf '%s' "$item_json" | jq -r .status)
  [[ "$st" == "claimed" ]] || { echo "$SCRIPT_NAME: item $item_id is not claimed (status=$st) -- refusing finalize" >&2; return 2; }

  # Defensive re-check: time may have passed between claim/prepare and
  # finalize; content the reviewer looked at must still be what is
  # actually about to be recorded as reviewed.
  local reason
  if ! reason=$(_rr_stale_check "$repo_root" "$item_json"); then
    local -a sargs=(mark-stale --item-id "$item_id" --reason "$reason")
    [[ -n "$state_dir" ]] && sargs+=(--state-dir "$state_dir")
    bash "$QUEUE_SH" "${sargs[@]}" >/dev/null 2>&1
    echo "$SCRIPT_NAME: STALE at finalize time -- $reason" >&2
    return 3
  fi

  # THE claimant identity used here is the one review-queue.sh recorded at
  # `claim` time -- re-read from the item, never re-trusted from fresh CLI
  # flags. A session cannot claim honestly (passing the self-claim guard)
  # and then finalize under a different, unverified identity.
  local claimant_json
  claimant_json=$(printf '%s' "$item_json" | jq -c '.claimant_principal // null')
  if [[ "$claimant_json" == "null" ]]; then
    echo "$SCRIPT_NAME: item $item_id has no recorded claimant_principal -- refusing finalize" >&2
    return 2
  fi

  # independence tier: docs/decisions/067-review-independence-same-session-
  # pathway.md -- "pathway" is the default/expected tier for every review
  # that went through this deterministic pipe, regardless of machine.
  # "cross-machine" is recorded truthfully as OPTIONAL additional hardening
  # only when the claimant's hostname genuinely differs from the
  # enqueuer's -- never required, never blocked on.
  local e_host c_host independence
  e_host=$(printf '%s' "$item_json" | jq -r '.enqueuer_principal.hostname // empty')
  c_host=$(printf '%s' "$claimant_json" | jq -r '.hostname // empty')
  if [[ -n "$e_host" ]] && [[ -n "$c_host" ]] && [[ "$e_host" != "$c_host" ]]; then
    independence="cross-machine"
  else
    independence="pathway"
  fi

  local -a files_args=()
  local n path
  n=$(printf '%s' "$item_json" | jq '.covered_files | length')
  local i=0
  while [[ "$i" -lt "$n" ]]; do
    path=$(printf '%s' "$item_json" | jq -r ".covered_files[$i].path")
    files_args+=(--file "$path")
    i=$((i+1))
  done

  local -a wargs=(capture --kind harness-change-review --reviewer "$reviewer" \
    --verdict "$verdict" --plan-ref "$plan_ref" --quote "$quote" \
    --repo-root "$repo_root" --reviewer-principal "$claimant_json" --independence "$independence")
  [[ -n "$reviewer_model" ]] && wargs+=(--reviewer-model "$reviewer_model")
  [[ -n "$findings_summary" ]] && wargs+=(--findings-summary "$findings_summary")
  wargs+=(${files_args[@]+"${files_args[@]}"})

  local wout wrc
  wout=$(bash "$WRITER_SH" "${wargs[@]}" 2>&1)
  wrc=$?
  if [[ "$wrc" -ne 0 ]]; then
    echo "$SCRIPT_NAME: write-review-record.sh capture failed: $wout" >&2
    return 2
  fi
  local record_file record_id
  record_file=$(printf '%s\n' "$wout" | sed -n '1p')
  record_id=$(printf '%s\n' "$wout" | sed -n '2p')

  # THE runner commits the record itself, under ITS OWN git identity --
  # never handed back to the authoring session to commit on the reviewer's
  # behalf. Whatever git user.name/user.email this process's environment
  # resolves to IS the reviewing principal's committer identity; this
  # script does not override it.
  local index_file="$repo_root/docs/reviews/records/index.json"
  git -C "$repo_root" add "$record_file" "$index_file" >/dev/null 2>&1
  # ONLY-THE-RECORD GUARANTEE (delta-sweep reviewer 2026-07-30, PROVEN by
  # fixture): an UNSCOPED commit here swept any pre-staged content into the
  # record commit under the REVIEWER identity — invisible to the commit gate
  # (a PreToolUse hook sees only this script invocation, never the inner git
  # call). Two layers: refuse when anything outside docs/reviews/records/ is
  # staged, and scope the commit to exactly the record artifacts regardless.
  local _stray
  _stray=$(git -C "$repo_root" diff --cached --name-only 2>/dev/null | grep -v '^docs/reviews/records/' || true)
  if [[ -n "$_stray" ]]; then
    echo "$SCRIPT_NAME: REFUSING finalize — the index holds staged content outside docs/reviews/records/ (a record commit must contain ONLY the record):" >&2
    printf '%s\n' "$_stray" | head -5 >&2
    return 2
  fi
  local commit_msg="review-record(${item_id}): ${verdict} on ${n} file(s) by ${reviewer} (independence: ${independence})"
  if ! git -C "$repo_root" commit -q -m "$commit_msg" -- "$record_file" "$index_file" >/dev/null 2>&1; then
    echo "$SCRIPT_NAME: git commit of the review record failed (nothing to commit, or no git identity configured)" >&2
    return 2
  fi
  local record_commit_sha; record_commit_sha=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null)

  local -a cargs=(complete --item-id "$item_id" --record-id "$record_id" --record-commit-sha "$record_commit_sha")
  [[ -n "$state_dir" ]] && cargs+=(--state-dir "$state_dir")
  bash "$QUEUE_SH" "${cargs[@]}" >/dev/null 2>&1

  echo "FINALIZED $item_id -> record $record_id @ $record_commit_sha (independence: $independence)" >&2
  return 0
}

# ---------------------------------------------------------------------------
# --self-test
# ---------------------------------------------------------------------------
run_self_test() {
  local PASSED=0 FAILED=0 tmp SELF_PATH saved_pwd
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t rrself)
  [[ -z "$tmp" || ! -d "$tmp" ]] && { echo "cannot mktemp" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN
  saved_pwd="$PWD"
  if [[ "$0" == /* ]]; then SELF_PATH="$0"; else SELF_PATH="$saved_pwd/$0"; fi

  local REPO="$tmp/repo" QD="$tmp/queue"
  mkdir -p "$REPO/adapters/claude-code/hooks" "$REPO/docs/reviews/records"
  ( cd "$REPO" && git init -q -b main )
  ( cd "$REPO" && git config user.email "author@example.com" && git config user.name "Author Session" )
  printf '{"schema_version":1,"entries":[]}\n' > "$REPO/docs/reviews/records/index.json"
  printf '#!/bin/bash\necho v1\n' > "$REPO/adapters/claude-code/hooks/alpha.sh"
  # A SECOND, content-distinct file (beta.sh) -- scenarios that must NOT
  # collide with the alpha.sh item's content_key (review-queue.sh dedupes
  # enqueue by {path, blob_sha} while an item is OPEN) use this one instead.
  printf '#!/bin/bash\necho beta-v1\n' > "$REPO/adapters/claude-code/hooks/beta.sh"
  ( cd "$REPO" && git add -A && git commit -q -m "author: add alpha.sh + beta.sh" )
  # origin/master stand-in: a bare clone one commit behind, used as --base-ref.
  local BARE="$tmp/origin.git"
  git clone -q --bare "$REPO" "$BARE" >/dev/null 2>&1
  ( cd "$REPO" && git remote add origin "$BARE" && git fetch -q origin >/dev/null 2>&1 )

  local branch_sha; branch_sha=$(git -C "$REPO" rev-parse --verify --quiet "main:adapters/claude-code/hooks/alpha.sh")
  local beta_sha; beta_sha=$(git -C "$REPO" rev-parse --verify --quiet "main:adapters/claude-code/hooks/beta.sh")

  local out item_id
  out=$(bash "$SCRIPT_DIR/review-queue.sh" enqueue --branch main --file "adapters/claude-code/hooks/alpha.sh" \
    --blob-sha "$branch_sha" --enqueuer-session-id "session-author" --state-dir "$QD" 2>&1)
  item_id=$(printf '%s\n' "$out" | tail -1)

  # ---- S1: claim by a DIFFERENT session succeeds and does not mark stale ----
  ( cd "$REPO" && git config user.email "runner@example.com" && git config user.name "Runner Process" )
  out=$("$SELF_PATH" claim --item-id "$item_id" --repo-root "$REPO" --claimant-session-id "session-reviewer" --state-dir "$QD" 2>&1)
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "self-test (S1) claim-different-session-succeeds: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S1) claim-different-session-succeeds: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S2: self-claim is refused via the delegated review-queue.sh guard ----
  # Uses beta.sh (a content_key distinct from item_id/alpha.sh, already
  # claimed by S1) so this enqueue creates a genuinely NEW, still-queued
  # item rather than colliding with S1's item via review-queue.sh's
  # content-key dedup.
  local out2
  out2=$(bash "$SCRIPT_DIR/review-queue.sh" enqueue --branch main --file "adapters/claude-code/hooks/beta.sh" \
    --blob-sha "$beta_sha" --enqueuer-session-id "session-author-2" --state-dir "$QD" 2>&1)
  local item_id2; item_id2=$(printf '%s\n' "$out2" | tail -1)
  out2=$("$SELF_PATH" claim --item-id "$item_id2" --repo-root "$REPO" --claimant-session-id "session-author-2" --state-dir "$QD" 2>&1)
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    echo "self-test (S2) self-claim-refused: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S2) self-claim-refused: FAIL (rc=$rc out=$out2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S3: prepare on the claimed item emits the instructions banner + a
  # real git diff, with no enqueuer free text (there is none to leak) ----
  out=$("$SELF_PATH" prepare --item-id "$item_id" --repo-root "$REPO" --base-ref origin/main --state-dir "$QD" 2>&1)
  if printf '%s' "$out" | grep -q "config/review-instructions.md" \
     && printf '%s' "$out" | grep -q "adapters/claude-code/hooks/alpha.sh"; then
    echo "self-test (S3) prepare-emits-banner-and-diff: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S3) prepare-emits-banner-and-diff: FAIL (out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S4: prepare on a QUEUED (not claimed) item is refused ----
  out=$("$SELF_PATH" prepare --item-id "$item_id2" --repo-root "$REPO" --state-dir "$QD" 2>&1)
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    echo "self-test (S4) prepare-not-claimed-refused: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S4) prepare-not-claimed-refused: FAIL (rc=$rc)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S5: finalize writes + COMMITS the record under the RUNNER's own
  # git identity (currently configured as "Runner Process"), links it to
  # the queue item, and defaults independence to "pathway" (same hostname,
  # same-session-pathway design) ----
  out=$("$SELF_PATH" finalize --item-id "$item_id" --repo-root "$REPO" --verdict PASS \
    --quote "PASS -- looks correct." --plan-ref "docs/plans/review-independence.md#RI2" \
    --state-dir "$QD" 2>&1)
  rc=$?
  local record_commit_author
  record_commit_author=$(git -C "$REPO" log -1 --format=%an 2>/dev/null)
  if [[ "$rc" -eq 0 ]] \
     && [[ "$record_commit_author" == "Runner Process" ]] \
     && [[ "$(bash "$SCRIPT_DIR/review-queue.sh" get --item-id "$item_id" --state-dir "$QD" 2>/dev/null | jq -r .status)" == "completed" ]]; then
    echo "self-test (S5) finalize-commits-under-runner-identity-and-completes: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S5) finalize-commits-under-runner-identity-and-completes: FAIL (rc=$rc author=$record_commit_author out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S6: the written record's reviewer_principal.session_id matches the
  # CLAIMANT recorded at claim time (session-reviewer), independence=pathway ----
  local rec_commit_sha rec_json
  rec_commit_sha=$(git -C "$REPO" rev-parse HEAD)
  rec_json=$(git -C "$REPO" show HEAD --format="" --name-only 2>/dev/null | grep '^docs/reviews/records/.*\.json$' | grep -v index.json | head -1)
  if [[ -n "$rec_json" ]]; then
    local principal_sid independence_val
    principal_sid=$(git -C "$REPO" show "HEAD:$rec_json" 2>/dev/null | jq -r .reviewer_principal.session_id)
    independence_val=$(git -C "$REPO" show "HEAD:$rec_json" 2>/dev/null | jq -r .independence)
    if [[ "$principal_sid" == "session-reviewer" ]] && [[ "$independence_val" == "pathway" ]]; then
      echo "self-test (S6) record-carries-claimant-principal-and-pathway-independence: PASS" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test (S6) record-carries-claimant-principal-and-pathway-independence: FAIL (sid=$principal_sid independence=$independence_val)" >&2
      FAILED=$((FAILED+1))
    fi
  else
    echo "self-test (S6) record-carries-claimant-principal-and-pathway-independence: FAIL (no record file found in HEAD)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S7: finalize on an already-completed item is refused ----
  out=$("$SELF_PATH" finalize --item-id "$item_id" --repo-root "$REPO" --verdict PASS \
    --quote "PASS again" --plan-ref x --state-dir "$QD" 2>&1)
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    echo "self-test (S7) finalize-already-completed-refused: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S7) finalize-already-completed-refused: FAIL (rc=$rc)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S8: STALE detection -- content changes after claim; finalize
  # refuses rc=3 and marks the item stale ----
  local out3 item_id3
  out3=$(bash "$SCRIPT_DIR/review-queue.sh" enqueue --branch main --file "adapters/claude-code/hooks/alpha.sh" \
    --blob-sha "$branch_sha" --enqueuer-session-id "session-author-3" --state-dir "$QD" 2>&1)
  item_id3=$(printf '%s\n' "$out3" | tail -1)
  "$SELF_PATH" claim --item-id "$item_id3" --repo-root "$REPO" --claimant-session-id "session-reviewer-3" --state-dir "$QD" >/dev/null 2>&1
  # Content moves on: a NEW commit changes alpha.sh after the claim.
  ( cd "$REPO" && git config user.email "author@example.com" && git config user.name "Author Session" )
  printf '#!/bin/bash\necho v2 -- CHANGED AFTER CLAIM\n' > "$REPO/adapters/claude-code/hooks/alpha.sh"
  ( cd "$REPO" && git add -A && git commit -q -m "author: change alpha.sh after claim" )
  out3=$("$SELF_PATH" finalize --item-id "$item_id3" --repo-root "$REPO" --verdict PASS \
    --quote "PASS -- stale?" --plan-ref x --state-dir "$QD" 2>&1)
  rc=$?
  local st3; st3=$(bash "$SCRIPT_DIR/review-queue.sh" get --item-id "$item_id3" --state-dir "$QD" 2>/dev/null | jq -r .status)
  if [[ "$rc" -eq 3 ]] && [[ "$st3" == "stale" ]]; then
    echo "self-test (S8) stale-content-refused-and-marked: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S8) stale-content-refused-and-marked: FAIL (rc=$rc status=$st3 out=$out3)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S9: ONLY-THE-RECORD guarantee (delta-sweep reviewer 2026-07-30) --
  # PROVEN pre-fix: an unscoped commit swept pre-staged content into the
  # record commit under the reviewer identity. Two assertions: finalize
  # REFUSES with a stray staged file; and after a clean finalize the record
  # commit's file list contains ONLY docs/reviews/records/ paths.
  local out4 item_id4
  out4=$(bash "$SCRIPT_DIR/review-queue.sh" enqueue --branch main --file "adapters/claude-code/hooks/beta.sh" \
    --blob-sha "$(git -C "$REPO" rev-parse HEAD:adapters/claude-code/hooks/beta.sh)" \
    --enqueuer-session-id "session-author-4" --state-dir "$QD" 2>&1)
  item_id4=$(printf '%s\n' "$out4" | tail -1)
  "$SELF_PATH" claim --item-id "$item_id4" --repo-root "$REPO" --claimant-session-id "session-reviewer-4" --state-dir "$QD" >/dev/null 2>&1
  printf '#!/bin/bash\necho leftover\n' > "$REPO/adapters/claude-code/hooks/leftover.sh"
  ( cd "$REPO" && git add adapters/claude-code/hooks/leftover.sh )
  out4=$("$SELF_PATH" finalize --item-id "$item_id4" --repo-root "$REPO" --verdict PASS \
    --quote "PASS -- only-the-record probe" --plan-ref x --state-dir "$QD" 2>&1)
  rc=$?
  if [[ "$rc" -eq 2 ]] && printf '%s' "$out4" | grep -q "REFUSING finalize"; then
    echo "self-test (S9a) stray-staged-content-refused: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S9a) stray-staged-content-refused: FAIL (rc=$rc out=$out4)" >&2
    FAILED=$((FAILED+1))
  fi
  ( cd "$REPO" && git reset -q HEAD adapters/claude-code/hooks/leftover.sh && rm -f adapters/claude-code/hooks/leftover.sh )
  out4=$("$SELF_PATH" finalize --item-id "$item_id4" --repo-root "$REPO" --verdict PASS \
    --quote "PASS -- only-the-record probe clean" --plan-ref x --state-dir "$QD" 2>&1)
  rc=$?
  local rec_files
  rec_files=$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | grep -cv '^docs/reviews/records/' || true)
  if [[ "$rc" -eq 0 ]] && [[ "${rec_files:-1}" -eq 0 ]]; then
    echo "self-test (S9b) record-commit-contains-only-record-paths: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S9b) record-commit-contains-only-record-paths: FAIL (rc=$rc non-record-files=$rec_files)" >&2
    FAILED=$((FAILED+1))
  fi

  cd "$saved_pwd" 2>/dev/null || true
  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed (of $((PASSED+FAILED)) scenarios)" >&2
  [[ "$FAILED" -eq 0 ]]
}

case "${1:-}" in
  --self-test) run_self_test; exit $? ;;
  --help|-h) usage; exit 0 ;;
  claim) shift; cmd_claim "$@"; exit $? ;;
  prepare) shift; cmd_prepare "$@"; exit $? ;;
  finalize) shift; cmd_finalize "$@"; exit $? ;;
  *) usage >&2; exit 2 ;;
esac
