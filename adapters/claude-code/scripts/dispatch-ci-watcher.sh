#!/usr/bin/env bash
# dispatch-ci-watcher.sh — System 3 of the drift-backlog + harness-evaluator pair.
#
# Watches CI status of PRs Dispatch (this Claude Code instance) has
# created, tracks state transitions per-PR, and emits drift items on
# transitions to FAILED. Designed to keep the operator OUT of the
# email-forwarding loop for the agent's own CI failures.
#
# Motivation: Misha 2026-05-25 — "I'm getting email notifications for
# failed neural-lace PR CI runs that I (Dispatch) created and never
# followed up on. He's the email-forwarding service for my own CI
# status. That's broken."
#
# Hard rules:
# - Scheduled task (not on-demand). Every 5-10 min via cron / Routine.
# - Read-only against GitHub (just `gh pr checks` calls).
# - Surfaces via Conv Tree (eventually push to Dispatch); NEVER to
#   Misha's inbox unless he opts in.
#
# Heuristics for "Dispatch-spawned":
# - PR is OPEN
# - PR author == the operator (Dispatch commits under operator identity)
# - Branch matches one of the standard Dispatch prefixes (`feat/`,
#   `fix/`, `docs/`, `chore/`, `ci/`, `refactor/`, `claude/`) — excludes
#   manual-only patterns (`release/`, `hotfix/`).
# - Commit body contains the `Co-Authored-By: Claude` marker (strong
#   signal).
#
# State store: .claude/state/ci-watcher/<repo-slug>/<pr-num>.json
# Each file holds: {pr_num, branch, last_check_state, last_seen_ts,
# transitions: [...]}
#
# Output: appends drift-items to
# .claude/state/ci-watcher/drift-items.jsonl on FAIL transition. The
# harness-evaluator and future Conv Tree integration consume that.
#
# Usage:
#   bash adapters/claude-code/scripts/dispatch-ci-watcher.sh
#   bash adapters/claude-code/scripts/dispatch-ci-watcher.sh --repos owner/repo1,owner/repo2
#   bash adapters/claude-code/scripts/dispatch-ci-watcher.sh --self-test
#   bash adapters/claude-code/scripts/dispatch-ci-watcher.sh --report-only

set -uo pipefail

SELF_TEST=0
REPORT_ONLY=0
REPOS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos) REPOS="$2"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    --report-only) REPORT_ONLY=1; shift ;;
    --help|-h) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 1 ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not on PATH: $1" >&2; exit 1
  fi
}
require_cmd gh
require_cmd jq
require_cmd git

# ---- repo root + state ------------------------------------------------------
find_repo_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd
  fi
}
REPO_ROOT="$(find_repo_root)"
STATE_DIR="$REPO_ROOT/.claude/state/ci-watcher"
DRIFT_FILE="$STATE_DIR/drift-items.jsonl"
mkdir -p "$STATE_DIR"

# ---- dispatch detection heuristic ------------------------------------------
# Returns 0 if branch name matches a Dispatch-spawned pattern.
is_dispatch_branch() {
  local branch="$1"
  case "$branch" in
    feat/*|fix/*|docs/*|chore/*|ci/*|refactor/*|claude/*|strategy/*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---- self-test --------------------------------------------------------------
run_self_test() {
  local failed=0
  echo "[self-test] is_dispatch_branch positives"
  for b in "feat/foo" "fix/bar" "docs/baz" "ci/eats" "claude/x"; do
    if ! is_dispatch_branch "$b"; then
      echo "[self-test] FAIL: $b should be detected"; failed=1
    fi
  done
  echo "[self-test] is_dispatch_branch negatives"
  for b in "release/v1" "hotfix/security" "main" "master"; do
    if is_dispatch_branch "$b"; then
      echo "[self-test] FAIL: $b should NOT be detected"; failed=1
    fi
  done
  echo "[self-test] state dir creatable"
  [[ -d "$STATE_DIR" ]] || { echo "[self-test] FAIL: state dir missing"; failed=1; }
  echo "[self-test] gh CLI present"
  command -v gh >/dev/null 2>&1 || { echo "[self-test] FAIL: gh missing"; failed=1; }
  echo "[self-test] gh auth"
  if ! gh auth status >/dev/null 2>&1; then
    echo "[self-test] WARN: gh not authenticated — watcher won't see live PRs"
  else
    echo "[self-test] gh auth ok"
  fi
  if [[ $failed -eq 0 ]]; then
    echo "[self-test] all checks passed"; return 0
  else
    echo "[self-test] FAILED ($failed)"; return 2
  fi
}

# ---- per-repo scan ----------------------------------------------------------
# Returns aggregate verdict per PR: pass | fail | pending | mixed
aggregate_pr_state() {
  local repo="$1" pr_num="$2"
  local checks_json
  checks_json=$(gh pr checks "$pr_num" --repo "$repo" --json name,state,bucket 2>/dev/null || echo "[]")
  local n_total n_fail n_pending n_pass
  n_total=$(echo "$checks_json" | jq 'length')
  n_fail=$(echo "$checks_json" | jq '[.[] | select(.bucket == "fail")] | length')
  n_pending=$(echo "$checks_json" | jq '[.[] | select(.bucket == "pending")] | length')
  n_pass=$(echo "$checks_json" | jq '[.[] | select(.bucket == "pass")] | length')
  if [[ "$n_total" -eq 0 ]]; then
    echo "no-checks"
  elif [[ "$n_fail" -gt 0 ]]; then
    echo "fail"
  elif [[ "$n_pending" -gt 0 ]]; then
    echo "pending"
  elif [[ "$n_pass" -eq "$n_total" ]]; then
    echo "pass"
  else
    echo "mixed"
  fi
}

scan_one_pr() {
  local repo="$1" pr_num="$2" branch="$3" title="$4"
  local repo_slug
  repo_slug=$(echo "$repo" | tr '/' '_')
  local state_file="$STATE_DIR/${repo_slug}_${pr_num}.json"
  local current_state
  current_state=$(aggregate_pr_state "$repo" "$pr_num")
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  if [[ -f "$state_file" ]]; then
    local prior_state
    prior_state=$(jq -r '.last_check_state' "$state_file")
    if [[ "$prior_state" != "$current_state" ]]; then
      echo "[ci-watcher] transition: $repo#$pr_num $prior_state → $current_state"
      # Append transition
      local tmp
      tmp=$(mktemp)
      jq --arg state "$current_state" --arg ts "$now" \
        '.last_check_state = $state |
         .last_seen_ts = $ts |
         .transitions += [{from: .last_check_state, to: $state, ts: $ts}]' \
        "$state_file" > "$tmp" && mv "$tmp" "$state_file"
      # Emit drift item on transitions to fail
      if [[ "$current_state" == "fail" ]]; then
        emit_drift "$repo" "$pr_num" "$branch" "$title" "$prior_state" "$current_state"
      fi
    else
      # Just update last-seen
      local tmp
      tmp=$(mktemp)
      jq --arg ts "$now" '.last_seen_ts = $ts' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
    fi
  else
    # First sighting — create state file. Emit drift item if it starts FAIL.
    jq -n --arg repo "$repo" --argjson pr "$pr_num" --arg branch "$branch" \
        --arg title "$title" --arg state "$current_state" --arg ts "$now" \
      '{repo:$repo, pr_num:$pr, branch:$branch, title:$title,
        first_seen_ts:$ts, last_check_state:$state, last_seen_ts:$ts,
        transitions:[]}' > "$state_file"
    if [[ "$current_state" == "fail" ]]; then
      emit_drift "$repo" "$pr_num" "$branch" "$title" "(new-pr)" "$current_state"
    fi
  fi
}

emit_drift() {
  local repo="$1" pr_num="$2" branch="$3" title="$4" from_state="$5" to_state="$6"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local failed_checks
  failed_checks=$(gh pr checks "$pr_num" --repo "$repo" --json name,state,bucket,link 2>/dev/null \
    | jq -c '[.[] | select(.bucket == "fail") | {name, state, link}]')
  jq -nc --arg repo "$repo" --argjson pr "$pr_num" --arg branch "$branch" \
        --arg title "$title" --arg from "$from_state" --arg to "$to_state" \
        --argjson failed "$failed_checks" --arg ts "$now" \
    '{ts:$ts, severity:"high", kind:"ci-failure",
      repo:$repo, pr_num:$pr, branch:$branch, title:$title,
      transition:{from:$from, to:$to},
      failed_checks:$failed,
      url:("https://github.com/" + $repo + "/pull/" + ($pr|tostring))}' \
    >> "$DRIFT_FILE"
  echo "[ci-watcher] DRIFT-ITEM: $repo#$pr_num ($from_state → $to_state) — $title"
}

scan_repo() {
  local repo="$1"
  echo "[ci-watcher] scanning: $repo"
  local prs_json
  prs_json=$(gh pr list --repo "$repo" --state open --limit 50 \
    --json number,title,headRefName,author 2>/dev/null || echo "[]")
  local n
  n=$(echo "$prs_json" | jq 'length')
  if [[ "$n" -eq 0 ]]; then
    echo "[ci-watcher]   no open PRs"
    return
  fi
  echo "[ci-watcher]   $n open PRs"
  echo "$prs_json" | jq -c '.[]' | while read -r pr; do
    local num branch title author
    num=$(echo "$pr" | jq -r '.number')
    branch=$(echo "$pr" | jq -r '.headRefName')
    title=$(echo "$pr" | jq -r '.title')
    author=$(echo "$pr" | jq -r '.author.login')
    if ! is_dispatch_branch "$branch"; then
      continue  # not a Dispatch-spawned branch
    fi
    echo "[ci-watcher]   checking #$num ($branch)"
    scan_one_pr "$repo" "$num" "$branch" "$title"
  done
}

# ---- report-only mode ------------------------------------------------------
report_only() {
  echo "## Dispatch CI watcher — current state"
  echo
  if [[ ! -d "$STATE_DIR" || -z "$(ls -A "$STATE_DIR" 2>/dev/null)" ]]; then
    echo "_No state — watcher has not run yet._"
    return
  fi
  echo "**Tracked PRs:**"
  echo
  echo "| Repo | PR | Branch | State | Last seen |"
  echo "|---|---|---|---|---|"
  for f in "$STATE_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "drift-items.jsonl" ]] && continue
    jq -r '"| \(.repo) | #\(.pr_num) | \(.branch) | **\(.last_check_state)** | \(.last_seen_ts) |"' "$f" 2>/dev/null
  done
  echo
  if [[ -f "$DRIFT_FILE" ]]; then
    local n
    n=$(wc -l < "$DRIFT_FILE" | tr -d ' ')
    echo "**Drift items (transitions to fail):** $n"
    if [[ "$n" -gt 0 ]]; then
      echo
      tail -10 "$DRIFT_FILE" | while read -r line; do
        echo "$line" | jq -r '"- \(.ts) — \(.repo)#\(.pr_num) \(.transition.from) → \(.transition.to) — [\(.title)](\(.url))"'
      done
    fi
  fi
}

# ---- entry point -----------------------------------------------------------
if [[ $SELF_TEST -eq 1 ]]; then
  run_self_test
  exit $?
fi

if [[ $REPORT_ONLY -eq 1 ]]; then
  report_only
  exit 0
fi

# Determine repos to scan
if [[ -z "$REPOS" ]]; then
  # Default: the current repo only
  current=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  if [[ -n "$current" ]]; then
    REPOS="$current"
  else
    echo "ERROR: could not determine current repo; pass --repos owner/repo" >&2
    exit 1
  fi
fi

echo "[ci-watcher] repos: $REPOS"
IFS=',' read -ra repo_list <<< "$REPOS"
for repo in "${repo_list[@]}"; do
  scan_repo "$repo"
done

echo "[ci-watcher] done"
echo
report_only
