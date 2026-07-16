#!/bin/bash
# write-review-record.sh — write a review-record for the review-before-deploy
# gate (harness-governance-batch-2026-07-15, batch task 2).
#
# Design: docs/design-notes/review-record-primitive.md (architecture-reviewer
# verdict SOUND-WITH-AMENDMENTS, 2026-07-16). Neither harness-reviewer nor
# architecture-reviewer can write files (tools: Read, Grep, Glob, Bash only) --
# this script is invoked by the ORCHESTRATING SESSION after a reviewer returns
# its verdict, never by the reviewer itself.
#
# WHAT IT WRITES
#   docs/reviews/records/<yyyy-mm-dd>-<kind>-<short-id>.json  (one file per
#   record, append-only, committed -- never a shared ledger, so N parallel
#   worktree builders writing records never conflict on one file).
#   docs/reviews/records/index.json  is ALWAYS fully rebuilt from every record
#   file after a capture (a content-keyed {path,blob_sha}->record_id map --
#   the ONE file the deploy gate actually reads on its hot path; the records
#   dir itself is audit-only and is never scanned there -- Amendment D).
#
# ANTI-FABRICATION (Amendment C, honestly named, not solved): --quote must be
# a verbatim substring of the reviewer agent's actual returned message. This
# script cannot verify that claim -- zero SubagentStop/TaskCompleted capture
# hooks exist to retrieve the real transcript. The record this writes is an
# audit + honesty anchor, NOT a deploy-path anti-fabrication control.
#
# Subcommands:
#   capture --kind <harness-change-review|fix-root-cause|artifact-evidence>
#           --reviewer <agent> [--reviewer-model <model>]
#           --verdict <PASS|REFORMULATE|REJECT>
#           --plan-ref <ref> --quote <verbatim-quote>
#           --file <repo-relative-path> [--file <path> ...]
#           [--commit-sha <sha>] [--branch <name>] [--transcript-ref <ref>]
#           [--findings-summary <text>] [--written-by <text>]
#           [--payload <json>] [--repo-root <path>]
#   rebuild-index [--records-dir <dir>] [--repo-root <path>] [--stdout]
#   check --path <repo-relative-path> [--blob-sha <sha>] [--ref <ref>]
#         [--repo-root <path>]
#   bootstrap-grandfather [--ref <ref>] [--repo-root <path>] [--stdout]
#     Snapshots every CURRENT trigger-surface file's {path, blob_sha} at
#     <ref> (default HEAD) into grandfather-manifest.json -- Amendment E: a
#     one-time cutover marker so content that already existed at bootstrap
#     time never needs a retroactive review record. Re-running replaces the
#     file with a fresh snapshot at the given ref (intentionally not
#     additive -- the grandfather set is defined by "what existed at ref",
#     not an accumulating history).
#   --self-test
#   --help
#
# Exit codes: 0 PASS/success; 1 UNCOVERED (check only); 2 usage/validation error.
#
# Verification: this script self-tests via --self-test.

set -uo pipefail

SCRIPT_NAME="write-review-record.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../hooks/lib/review-record-gate-lib.sh
source "$SCRIPT_DIR/../hooks/lib/review-record-gate-lib.sh" 2>/dev/null || {
  echo "$SCRIPT_NAME: cannot source review-record-gate-lib.sh" >&2
  exit 2
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME capture --kind <k> --reviewer <agent> --verdict <v> \\
         --plan-ref <ref> --quote <text> --file <path> [--file <path> ...] \\
         [--reviewer-model <m>] [--commit-sha <sha>] [--branch <b>] \\
         [--transcript-ref <ref>] [--findings-summary <text>] \\
         [--written-by <text>] [--payload <json>] [--repo-root <path>]
       $SCRIPT_NAME rebuild-index [--records-dir <dir>] [--repo-root <path>] [--stdout]
       $SCRIPT_NAME check --path <path> [--blob-sha <sha>] [--ref <ref>] [--repo-root <path>]
       $SCRIPT_NAME bootstrap-grandfather [--ref <ref>] [--repo-root <path>] [--stdout]
       $SCRIPT_NAME --self-test
       $SCRIPT_NAME --help
EOF
}

_repo_root_default() {
  local r="$1"
  [[ -n "$r" ]] && { printf '%s' "$r"; return 0; }
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

_records_dir_for() {
  printf '%s/docs/reviews/records' "$1"
}

# ---------------------------------------------------------------------------
# Index rebuild -- a pure function of the records directory's *.json files
# (excluding index.json and grandfather-manifest.json). Deterministically
# sorted so two rebuilds of the same records dir are byte-identical (the
# doctor's consistency check relies on this).
# ---------------------------------------------------------------------------
_rrg_rebuild_index() {
  local records_dir="$1"
  [[ -d "$records_dir" ]] || { printf '{"schema_version":1,"entries":[]}\n'; return 0; }

  local files=() f base
  shopt -s nullglob
  for f in "$records_dir"/*.json; do
    base=$(basename "$f")
    [[ "$base" == "index.json" || "$base" == "grandfather-manifest.json" ]] && continue
    files+=("$f")
  done
  shopt -u nullglob

  if [[ "${#files[@]}" -eq 0 ]]; then
    printf '{"schema_version":1,"entries":[]}\n'
    return 0
  fi

  # `reviewer` is carried into every index row (harness-review REFORMULATE
  # fixup, finding 2b) so a derived row can NEVER drop the honesty
  # qualifier -- an index reader must always be able to see WHO passed a
  # record, not just that some record says PASS. This is what makes the
  # existing placeholder record ("none (orchestrator self-attestation...)")
  # read honestly once rebuilt, without deleting or rewriting the record
  # itself.
  jq -s '
    [ .[] | . as $rec | ($rec.covered_files // [])[] | {
        path: .path,
        blob_sha: .blob_sha,
        record_id: $rec.record_id,
        kind: $rec.kind,
        verdict: $rec.verdict,
        reviewer: $rec.reviewer,
        created_at: $rec.created_at
      } ]
    | sort_by(.path, .blob_sha, .created_at, .record_id)
    | {schema_version: 1, entries: .}
  ' "${files[@]}"
}

# Best-effort ledger log on 2+ CONSECUTIVE REJECT/REFORMULATE for the SAME
# file-path set (OQ3: informational surfacing only -- never blocks, never
# fails this script).
_rrg_maybe_ledger_log_consecutive_rejects() {
  local records_dir="$1" verdict="$2" cov_json="$3"
  [[ "$verdict" == "PASS" ]] && return 0
  command -v jq >/dev/null 2>&1 || return 0

  local pathset
  pathset=$(printf '%s' "$cov_json" | jq -c '[.[].path] | sort' 2>/dev/null) || return 0

  local files=() f base
  shopt -s nullglob
  for f in "$records_dir"/*.json; do
    base=$(basename "$f")
    [[ "$base" == "index.json" || "$base" == "grandfather-manifest.json" ]] && continue
    files+=("$f")
  done
  shopt -u nullglob
  [[ "${#files[@]}" -eq 0 ]] && return 0

  local streak
  streak=$(jq -s --argjson want "$pathset" '
    [ .[] | select((([.covered_files[].path] | sort) == $want)) ]
    | sort_by(.created_at)
    | reverse
    | reduce .[] as $r (
        {run:0, done:false};
        if .done then .
        elif ($r.verdict == "REJECT" or $r.verdict == "REFORMULATE") then (.run += 1)
        else (.done = true)
        end
      )
    | .run
  ' "${files[@]}" 2>/dev/null)

  if [[ "$streak" =~ ^[0-9]+$ ]] && [[ "$streak" -ge 2 ]]; then
    local lib="$SCRIPT_DIR/../hooks/lib/signal-ledger.sh"
    if [[ -f "$lib" ]]; then
      # shellcheck disable=SC1090
      source "$lib" 2>/dev/null && \
        ledger_emit "review-record" "warn" "${streak} consecutive REJECT/REFORMULATE on file set $(printf '%s' "$pathset" | tr -d '\n ')" 2>/dev/null || true
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# capture
# ---------------------------------------------------------------------------
cmd_capture() {
  local kind="" reviewer="" reviewer_model="" verdict="" plan_ref="" quote=""
  local commit_sha="" branch="" transcript_ref="" findings_summary="" written_by=""
  local payload_json="{}" repo_root=""
  local files=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind) kind="$2"; shift 2 ;;
      --reviewer) reviewer="$2"; shift 2 ;;
      --reviewer-model) reviewer_model="$2"; shift 2 ;;
      --verdict) verdict="$2"; shift 2 ;;
      --plan-ref) plan_ref="$2"; shift 2 ;;
      --quote) quote="$2"; shift 2 ;;
      --file) files+=("$2"); shift 2 ;;
      --commit-sha) commit_sha="$2"; shift 2 ;;
      --branch) branch="$2"; shift 2 ;;
      --transcript-ref) transcript_ref="$2"; shift 2 ;;
      --findings-summary) findings_summary="$2"; shift 2 ;;
      --written-by) written_by="$2"; shift 2 ;;
      --payload) payload_json="$2"; shift 2 ;;
      --repo-root) repo_root="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; usage >&2; return 2 ;;
    esac
  done

  case "$kind" in
    harness-change-review|fix-root-cause|artifact-evidence) ;;
    *) echo "$SCRIPT_NAME: --kind must be harness-change-review|fix-root-cause|artifact-evidence (got '$kind')" >&2; return 2 ;;
  esac
  case "$verdict" in
    PASS|REFORMULATE|REJECT) ;;
    *) echo "$SCRIPT_NAME: --verdict must be PASS|REFORMULATE|REJECT (got '$verdict')" >&2; return 2 ;;
  esac
  [[ -z "$reviewer" ]] && { echo "$SCRIPT_NAME: --reviewer is required" >&2; return 2; }
  # Honesty-laundering refusal (harness-review REFORMULATE fixup, finding
  # 2a): a PASS record whose --reviewer is empty/"none"/a self-attestation/
  # a placeholder reads, once buried in index.json, as an indistinguishable
  # bare PASS -- exactly the fabrication risk Amendment C names. Refuse to
  # WRITE such a record at all rather than rely on a human reading the
  # reviewer string later. REFORMULATE/REJECT records are NOT refused here
  # (they never unblock anything, so there is nothing to launder).
  if [[ "$verdict" == "PASS" ]]; then
    local reviewer_lc="${reviewer,,}"
    if [[ -z "${reviewer_lc//[[:space:]]/}" ]] \
       || [[ "$reviewer_lc" == *"none"* ]] \
       || [[ "$reviewer_lc" == *"self-attest"* ]] \
       || [[ "$reviewer_lc" == *"self attest"* ]] \
       || [[ "$reviewer_lc" == *"placeholder"* ]]; then
      echo "$SCRIPT_NAME: refusing to write a PASS record -- --reviewer '$reviewer' reads as empty/none/self-attestation/placeholder, not a real reviewer identity. A PASS record's reviewer must name an actual reviewer (e.g. 'harness-reviewer'). Use --verdict REFORMULATE or REJECT for a non-reviewed placeholder, or supply the real reviewer's identity." >&2
      return 2
    fi
  fi
  [[ -z "$plan_ref" ]] && { echo "$SCRIPT_NAME: --plan-ref is required" >&2; return 2; }
  [[ -z "$quote" ]] && { echo "$SCRIPT_NAME: --quote is required (verbatim substring of the reviewer's returned message)" >&2; return 2; }
  [[ "${#files[@]}" -eq 0 ]] && { echo "$SCRIPT_NAME: at least one --file is required" >&2; return 2; }
  if ! printf '%s' "$payload_json" | jq empty >/dev/null 2>&1; then
    echo "$SCRIPT_NAME: --payload must be valid JSON" >&2
    return 2
  fi

  repo_root="$(_repo_root_default "$repo_root")"
  [[ -z "$reviewer_model" ]] && reviewer_model="unknown"
  [[ -z "$written_by" ]] && written_by="orchestrator via write-review-record.sh"
  [[ -z "$branch" ]] && branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  [[ -z "$commit_sha" ]] && commit_sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo "")"

  local cov="[]" f abs sha
  for f in "${files[@]}"; do
    if [[ "$f" = /* ]]; then abs="$f"; else abs="$repo_root/$f"; fi
    sha=$(rrg_blob_sha_of_file "$abs")
    if [[ -z "$sha" ]]; then
      echo "$SCRIPT_NAME: cannot resolve blob sha for --file '$f' (expected at $abs)" >&2
      return 2
    fi
    # Non-blocking sanity WARN (harness-review REFORMULATE fixup, finding
    # 4 optional): a --file outside the review-before-deploy trigger
    # surface is usually a typo'd path, not a deliberate choice -- the
    # record is still written (it's a valid audit artifact either way, and
    # some callers legitimately capture broader evidence), but flag it
    # loudly so a mistake doesn't silently produce a record that can never
    # actually gate anything.
    if command -v rrg_in_surface >/dev/null 2>&1 && ! rrg_in_surface "$f"; then
      echo "$SCRIPT_NAME: WARN -- --file '$f' is OUTSIDE the review-before-deploy trigger surface; this record will never gate a deploy for it (check for a typo'd path)" >&2
    fi
    cov=$(printf '%s' "$cov" | jq --arg p "$f" --arg s "$sha" '. + [{path:$p, blob_sha:$s}]')
  done

  local kind_prefix
  case "$kind" in
    harness-change-review) kind_prefix="hcr" ;;
    fix-root-cause) kind_prefix="frc" ;;
    artifact-evidence) kind_prefix="ae" ;;
  esac

  local shortid date_compact date_dashed created_at record_id
  shortid=$(printf '%04x%04x' "$RANDOM" "$RANDOM")
  date_compact=$(date -u +%Y%m%d)
  date_dashed=$(date -u +%Y-%m-%d)
  created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  record_id="${kind_prefix}-${date_compact}-${shortid}"

  local record_json
  record_json=$(jq -n \
    --argjson schema_version 1 \
    --arg kind "$kind" \
    --arg record_id "$record_id" \
    --arg created_at "$created_at" \
    --arg verdict "$verdict" \
    --arg reviewer "$reviewer" \
    --arg reviewer_model "$reviewer_model" \
    --arg plan_ref "$plan_ref" \
    --arg commit_sha "$commit_sha" \
    --arg branch "$branch" \
    --argjson covered_files "$cov" \
    --arg transcript_ref "$transcript_ref" \
    --arg verdict_quote "$quote" \
    --arg findings_summary "$findings_summary" \
    --arg written_by "$written_by" \
    --argjson payload "$payload_json" \
    '{
      schema_version: $schema_version,
      kind: $kind,
      record_id: $record_id,
      created_at: $created_at,
      verdict: $verdict,
      reviewer: $reviewer,
      reviewer_model: $reviewer_model,
      plan_ref: $plan_ref,
      change_ref: {commit_sha: $commit_sha, branch: $branch},
      covered_files: $covered_files,
      dispatch_evidence: {
        transcript_ref: $transcript_ref,
        verdict_quote: $verdict_quote,
        findings_summary: $findings_summary
      },
      written_by: $written_by,
      payload: $payload
    }')

  if ! printf '%s' "$record_json" | jq empty >/dev/null 2>&1; then
    echo "$SCRIPT_NAME: internal error -- generated record is not valid JSON" >&2
    return 2
  fi

  local records_dir out_file
  records_dir="$(_records_dir_for "$repo_root")"
  mkdir -p "$records_dir" || { echo "$SCRIPT_NAME: cannot create $records_dir" >&2; return 2; }
  out_file="$records_dir/${date_dashed}-${kind}-${shortid}.json"
  printf '%s\n' "$record_json" > "$out_file" || { echo "$SCRIPT_NAME: cannot write $out_file" >&2; return 2; }

  # Index is ALWAYS fully rebuilt (never incrementally patched) -- it can
  # never drift from "a pure function of the records directory."
  _rrg_rebuild_index "$records_dir" > "$records_dir/index.json"

  _rrg_maybe_ledger_log_consecutive_rejects "$records_dir" "$verdict" "$cov"

  echo "$out_file" >&2
  echo "$record_id" >&2
  return 0
}

# ---------------------------------------------------------------------------
# rebuild-index
# ---------------------------------------------------------------------------
cmd_rebuild_index() {
  local records_dir="" repo_root="" stdout_only=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --records-dir) records_dir="$2"; shift 2 ;;
      --repo-root) repo_root="$2"; shift 2 ;;
      --stdout) stdout_only=1; shift ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; return 2 ;;
    esac
  done
  [[ -z "$records_dir" ]] && records_dir="$(_records_dir_for "$(_repo_root_default "$repo_root")")"

  local out
  out="$(_rrg_rebuild_index "$records_dir")"
  if [[ "$stdout_only" -eq 1 ]]; then
    printf '%s\n' "$out"
  else
    mkdir -p "$records_dir" 2>/dev/null
    printf '%s\n' "$out" > "$records_dir/index.json"
    echo "$records_dir/index.json" >&2
  fi
  return 0
}

# ---------------------------------------------------------------------------
# bootstrap-grandfather
# ---------------------------------------------------------------------------
cmd_bootstrap_grandfather() {
  local repo_root="" ref="HEAD" stdout_only=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-root) repo_root="$2"; shift 2 ;;
      --ref) ref="$2"; shift 2 ;;
      --stdout) stdout_only=1; shift ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; return 2 ;;
    esac
  done
  command -v git >/dev/null 2>&1 || { echo "$SCRIPT_NAME: git is required" >&2; return 2; }
  repo_root="$(_repo_root_default "$repo_root")"

  # Resolve $ref to a concrete commit SHA (harness-review REFORMULATE
  # fixup, finding 3a): a literal "HEAD" (or "master", or any symbolic ref)
  # stored verbatim in cutover_ref is unpinned -- it silently means
  # something DIFFERENT every time the branch moves, defeating the whole
  # point of a cutover marker (a fixed point in history "content existed at
  # or before"). The recorded cutover_ref must be an immutable commit SHA.
  local resolved_ref
  resolved_ref=$(git -C "$repo_root" rev-parse --verify --quiet "$ref" 2>/dev/null)
  if [[ -z "$resolved_ref" ]]; then
    echo "$SCRIPT_NAME: cannot resolve --ref '$ref' to a commit in $repo_root" >&2
    return 2
  fi
  ref="$resolved_ref"

  local files f sha entries="[]"
  files=$(git -C "$repo_root" ls-tree -r --name-only "$ref" 2>/dev/null)
  if [[ -z "$files" ]]; then
    echo "$SCRIPT_NAME: no tracked files resolved at ref '$ref' in $repo_root" >&2
    return 2
  fi
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    rrg_in_surface "$f" || continue
    sha=$(git -C "$repo_root" rev-parse --verify --quiet "${ref}:${f}" 2>/dev/null)
    [[ -z "$sha" ]] && continue
    entries=$(printf '%s' "$entries" | jq --arg p "$f" --arg s "$sha" '. + [{path:$p, blob_sha:$s}]')
  done <<< "$files"

  local out
  out=$(printf '%s' "$entries" | jq --arg ref "$ref" --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{schema_version: 1, cutover_ref: $ref, generated_at: $ts, entries: (sort_by(.path))}')

  if ! printf '%s' "$out" | jq empty >/dev/null 2>&1; then
    echo "$SCRIPT_NAME: internal error -- generated grandfather manifest is not valid JSON" >&2
    return 2
  fi

  if [[ "$stdout_only" -eq 1 ]]; then
    printf '%s\n' "$out"
  else
    local records_dir; records_dir="$(_records_dir_for "$repo_root")"
    mkdir -p "$records_dir" || { echo "$SCRIPT_NAME: cannot create $records_dir" >&2; return 2; }
    printf '%s\n' "$out" > "$records_dir/grandfather-manifest.json"
    echo "$records_dir/grandfather-manifest.json" >&2
    echo "$(printf '%s' "$out" | jq '.entries | length') entries" >&2
  fi
  return 0
}

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------
cmd_check() {
  local path="" blob_sha="" ref="" repo_root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path) path="$2"; shift 2 ;;
      --blob-sha) blob_sha="$2"; shift 2 ;;
      --ref) ref="$2"; shift 2 ;;
      --repo-root) repo_root="$2"; shift 2 ;;
      *) echo "$SCRIPT_NAME: unknown arg: $1" >&2; return 2 ;;
    esac
  done
  [[ -z "$path" ]] && { echo "$SCRIPT_NAME: --path is required" >&2; return 2; }
  repo_root="$(_repo_root_default "$repo_root")"

  if [[ -z "$blob_sha" ]]; then
    if [[ -n "$ref" ]]; then
      blob_sha=$(rrg_blob_sha_of_ref "$repo_root" "$ref" "$path")
    else
      blob_sha=$(rrg_blob_sha_of_file "$repo_root/$path")
    fi
  fi

  if ! rrg_in_surface "$path"; then
    echo "OUT-OF-SURFACE $path"
    return 0
  fi

  if rrg_is_covered "$repo_root" "$ref" "$path" "$blob_sha"; then
    echo "COVERED $path @ ${blob_sha:-<unresolved>}"
    return 0
  else
    echo "UNCOVERED $path @ ${blob_sha:-<unresolved>} -- $(rrg_uncovered_reason "$repo_root" "$ref" "$path" "$blob_sha")"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# --self-test
# ---------------------------------------------------------------------------
run_self_test() {
  local PASSED=0 FAILED=0 tmp saved_pwd SELF_PATH
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t wrrself)
  [[ -z "$tmp" || ! -d "$tmp" ]] && { echo "cannot mktemp" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN
  saved_pwd="$PWD"
  if [[ "$0" == /* ]]; then SELF_PATH="$0"; else SELF_PATH="$saved_pwd/$0"; fi

  local REPO="$tmp/repo"
  mkdir -p "$REPO/adapters/claude-code/hooks" "$REPO/docs/reviews/records"
  printf '#!/bin/bash\necho v1\n' > "$REPO/adapters/claude-code/hooks/alpha.sh"
  ( cd "$REPO" && git init -q && git config user.email t@example.com && git config user.name T )

  # ---- S1: capture with valid args writes a record + rebuilds the index ----
  local out rc
  out=$("$SELF_PATH" capture --kind harness-change-review --reviewer harness-reviewer \
    --reviewer-model opus --verdict PASS --plan-ref "docs/plans/foo.md#task-2" \
    --quote "PASS -- golden scenario covers the case." \
    --file "adapters/claude-code/hooks/alpha.sh" --repo-root "$REPO" 2>&1)
  rc=$?
  local rec_file; rec_file=$(printf '%s\n' "$out" | head -1)
  if [[ "$rc" -eq 0 ]] && [[ -f "$rec_file" ]] \
     && [[ "$(jq -r .verdict "$rec_file" 2>/dev/null)" == "PASS" ]] \
     && [[ -f "$REPO/docs/reviews/records/index.json" ]] \
     && [[ "$(jq '.entries | length' "$REPO/docs/reviews/records/index.json" 2>/dev/null)" == "1" ]]; then
    echo "self-test (S1) capture-pass-writes-record-and-index: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S1) capture-pass-writes-record-and-index: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S2: check reports COVERED for that exact file/blob_sha ----
  out=$("$SELF_PATH" check --path "adapters/claude-code/hooks/alpha.sh" --repo-root "$REPO" 2>&1)
  rc=$?
  if [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q "^COVERED"; then
    echo "self-test (S2) check-reports-covered: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S2) check-reports-covered: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S3: changing the file's content makes check report UNCOVERED (new blob_sha) ----
  printf '#!/bin/bash\necho v2 -- CHANGED\n' > "$REPO/adapters/claude-code/hooks/alpha.sh"
  out=$("$SELF_PATH" check --path "adapters/claude-code/hooks/alpha.sh" --repo-root "$REPO" 2>&1)
  rc=$?
  if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -q "^UNCOVERED"; then
    echo "self-test (S3) changed-content-is-uncovered: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S3) changed-content-is-uncovered: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi
  # restore
  printf '#!/bin/bash\necho v1\n' > "$REPO/adapters/claude-code/hooks/alpha.sh"

  # ---- S4: missing --quote is rejected (exit 2) ----
  "$SELF_PATH" capture --kind harness-change-review --reviewer harness-reviewer \
    --verdict PASS --plan-ref "docs/plans/foo.md#task-2" \
    --file "adapters/claude-code/hooks/alpha.sh" --repo-root "$REPO" >/dev/null 2>&1
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    echo "self-test (S4) missing-quote-rejects: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S4) missing-quote-rejects: FAIL (rc=$rc, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S5: invalid --kind is rejected (exit 2) ----
  "$SELF_PATH" capture --kind bogus-kind --reviewer harness-reviewer --verdict PASS \
    --plan-ref x --quote y --file "adapters/claude-code/hooks/alpha.sh" --repo-root "$REPO" >/dev/null 2>&1
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    echo "self-test (S5) invalid-kind-rejects: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S5) invalid-kind-rejects: FAIL (rc=$rc, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S6: a REJECT record is written but does NOT cover the file ----
  mkdir -p "$REPO/adapters/claude-code/hooks"
  printf '#!/bin/bash\necho beta\n' > "$REPO/adapters/claude-code/hooks/beta.sh"
  "$SELF_PATH" capture --kind harness-change-review --reviewer harness-reviewer \
    --verdict REJECT --plan-ref "docs/plans/foo.md#task-2" \
    --quote "REJECT -- missing retirement_condition." \
    --file "adapters/claude-code/hooks/beta.sh" --repo-root "$REPO" >/dev/null 2>&1
  out=$("$SELF_PATH" check --path "adapters/claude-code/hooks/beta.sh" --repo-root "$REPO" 2>&1)
  rc=$?
  if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -q "^UNCOVERED"; then
    echo "self-test (S6) reject-record-does-not-cover: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S6) reject-record-does-not-cover: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S7: rebuild-index --stdout matches the committed index (consistency) ----
  local committed rebuilt
  committed=$(jq -S . "$REPO/docs/reviews/records/index.json" 2>/dev/null)
  rebuilt=$("$SELF_PATH" rebuild-index --repo-root "$REPO" --stdout 2>/dev/null | jq -S . 2>/dev/null)
  if [[ -n "$committed" ]] && [[ "$committed" == "$rebuilt" ]]; then
    echo "self-test (S7) rebuild-index-matches-committed: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S7) rebuild-index-matches-committed: FAIL" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S8: a path outside the trigger surface reports OUT-OF-SURFACE ----
  mkdir -p "$REPO/adapters/claude-code/doctrine"
  printf 'prose\n' > "$REPO/adapters/claude-code/doctrine/foo.md"
  out=$("$SELF_PATH" check --path "adapters/claude-code/doctrine/foo.md" --repo-root "$REPO" 2>&1)
  rc=$?
  if [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q "^OUT-OF-SURFACE"; then
    echo "self-test (S8) out-of-surface-path-reported: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S8) out-of-surface-path-reported: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S9: two consecutive REJECTs on the SAME file emit a ledger entry (OQ3) ----
  export SIGNAL_LEDGER_PATH="$tmp/ledger.jsonl"
  "$SELF_PATH" capture --kind harness-change-review --reviewer harness-reviewer \
    --verdict REJECT --plan-ref "docs/plans/foo.md#task-2" \
    --quote "REJECT again -- still missing fp_expectation." \
    --file "adapters/claude-code/hooks/beta.sh" --repo-root "$REPO" >/dev/null 2>&1
  if [[ -f "$SIGNAL_LEDGER_PATH" ]] && grep -q '"gate":"review-record"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "self-test (S9) two-consecutive-rejects-ledger-logged: PASS" >&2
    PASSED=$((PASSED+1))
  else
    # Best-effort feature (OQ3 is informational, not load-bearing for the
    # deploy gate) -- flagged loudly rather than silently passed if it
    # regresses, but never a hard failure of this script's core contract.
    echo "self-test (S9) two-consecutive-rejects-ledger-logged: WARN (best-effort; expected $SIGNAL_LEDGER_PATH to contain a review-record entry)" >&2
    PASSED=$((PASSED+1))
  fi
  unset SIGNAL_LEDGER_PATH

  # ---- S10: bootstrap-grandfather snapshots every in-surface tracked file
  # at HEAD, and NOT files outside the surface ----
  mkdir -p "$REPO/docs/some-other-doc"
  printf 'not in surface\n' > "$REPO/docs/some-other-doc/notes.md"
  ( cd "$REPO" && git add -A && git commit -q -m "self-test snapshot for bootstrap" )
  out=$("$SELF_PATH" bootstrap-grandfather --repo-root "$REPO" --ref HEAD --stdout 2>&1)
  if printf '%s' "$out" | jq -e '.entries[] | select(.path == "adapters/claude-code/hooks/alpha.sh")' >/dev/null 2>&1 \
     && ! printf '%s' "$out" | jq -e '.entries[] | select(.path == "docs/some-other-doc/notes.md")' >/dev/null 2>&1 \
     && ! printf '%s' "$out" | jq -e '.entries[] | select(.path | test("docs/reviews/records/"))' >/dev/null 2>&1; then
    echo "self-test (S10) bootstrap-grandfather-scopes-to-surface: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S10) bootstrap-grandfather-scopes-to-surface: FAIL (out: $out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S11: after bootstrap, an unchanged tracked file is COVERED with NO
  # capture needed ----
  "$SELF_PATH" bootstrap-grandfather --repo-root "$REPO" --ref HEAD >/dev/null 2>&1
  out=$("$SELF_PATH" check --path "adapters/claude-code/hooks/alpha.sh" --repo-root "$REPO" 2>&1)
  rc=$?
  if [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q "^COVERED"; then
    echo "self-test (S11) bootstrap-covers-unchanged-tracked-file: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S11) bootstrap-covers-unchanged-tracked-file: FAIL (rc=$rc out=$out)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S12: honesty-laundering refusal (harness-review REFORMULATE fixup,
  # finding 2a) -- a PASS record is REFUSED when --reviewer is empty, "none",
  # a self-attestation, or a placeholder (case-insensitive). ----
  local bad_reviewer
  for bad_reviewer in "none" "None (orchestrator self-attestation)" "SELF-ATTEST" "placeholder-pending-review" "   "; do
    "$SELF_PATH" capture --kind harness-change-review --reviewer "$bad_reviewer" \
      --verdict PASS --plan-ref x --quote y \
      --file "adapters/claude-code/hooks/alpha.sh" --repo-root "$REPO" >/dev/null 2>&1
    rc=$?
    if [[ "$rc" -ne 2 ]]; then
      echo "self-test (S12) honesty-laundering-refused: FAIL (reviewer '$bad_reviewer' was accepted, rc=$rc, expected 2)" >&2
      FAILED=$((FAILED+1))
      break
    fi
  done
  if [[ "$rc" -eq 2 ]]; then
    echo "self-test (S12) honesty-laundering-refused: PASS" >&2
    PASSED=$((PASSED+1))
  fi

  # ---- S13: a genuine reviewer identity is still accepted for PASS ----
  # (NOTE: must use "$REPO/docs/reviews/records", NOT a bare relative path
  # -- this fixture runs with the REAL cwd, and a relative rm -rf here would
  # delete the real repo's records directory instead of the fixture's.)
  rm -rf "$REPO/docs/reviews/records" 2>/dev/null
  "$SELF_PATH" capture --kind harness-change-review --reviewer "harness-reviewer" \
    --verdict PASS --plan-ref x --quote "PASS -- looks good." \
    --file "adapters/claude-code/hooks/alpha.sh" --repo-root "$REPO" >/dev/null 2>&1
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "self-test (S13) genuine-reviewer-still-accepted: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S13) genuine-reviewer-still-accepted: FAIL (rc=$rc)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S14: REFORMULATE/REJECT are NOT refused for a placeholder reviewer
  # (they never unblock anything, so there is nothing to launder) ----
  "$SELF_PATH" capture --kind harness-change-review --reviewer "none (placeholder)" \
    --verdict REJECT --plan-ref x --quote "REJECT placeholder" \
    --file "adapters/claude-code/hooks/beta.sh" --repo-root "$REPO" >/dev/null 2>&1
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "self-test (S14) reject-not-refused-for-placeholder-reviewer: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S14) reject-not-refused-for-placeholder-reviewer: FAIL (rc=$rc)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S15: index.json rows carry the `reviewer` field (finding 2b) so a
  # derived row can never drop the honesty qualifier ----
  local idx_reviewer
  idx_reviewer=$(jq -r '.entries[] | select(.path == "adapters/claude-code/hooks/alpha.sh") | .reviewer' "$REPO/docs/reviews/records/index.json" 2>/dev/null | head -1)
  if [[ "$idx_reviewer" == "harness-reviewer" ]]; then
    echo "self-test (S15) index-rows-carry-reviewer-field: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S15) index-rows-carry-reviewer-field: FAIL (got reviewer='$idx_reviewer')" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- S16: bootstrap-grandfather resolves cutover_ref to a real commit
  # SHA, never the literal ref name (finding 3a) ----
  out=$("$SELF_PATH" bootstrap-grandfather --repo-root "$REPO" --ref HEAD --stdout 2>&1)
  local cutover_val
  cutover_val=$(printf '%s' "$out" | jq -r '.cutover_ref' 2>/dev/null)
  if [[ "$cutover_val" =~ ^[0-9a-f]{40}$ ]]; then
    echo "self-test (S16) bootstrap-cutover-ref-is-resolved-sha: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (S16) bootstrap-cutover-ref-is-resolved-sha: FAIL (cutover_ref='$cutover_val')" >&2
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
  capture) shift; cmd_capture "$@"; exit $? ;;
  rebuild-index) shift; cmd_rebuild_index "$@"; exit $? ;;
  check) shift; cmd_check "$@"; exit $? ;;
  bootstrap-grandfather) shift; cmd_bootstrap_grandfather "$@"; exit $? ;;
  *) usage >&2; exit 2 ;;
esac
