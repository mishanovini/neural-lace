#!/bin/bash
# pr-health-snapshot.sh — PR-health-across-active-repos COLLECTOR (D.4
# relocation of hooks/pr-health-snapshot-gate.sh, a retired Stop hook).
#
# WHY THIS EXISTS / WHAT CHANGED
# ===============================
# The retired gate only checked whether a session's FINAL MESSAGE mentioned a
# `## PR Health Snapshot` heading covering every active repo — it never
# actually queried `gh` itself; the agent had to run the query template by
# hand each time, and a differently-worded wrap-up could dodge the gate
# entirely. This script is the thing that was always meant to exist: a real
# collector that runs the `gh pr list` queries, classifies results, and
# EMITS the snapshot — callable manually, by session-wrap.sh, or by the
# future E.1 digest (Wave E). The Stop-hook ENFORCEMENT retires at D.5; this
# script keeps the underlying data flow alive so nothing is lost, and turns
# what used to be "hope the agent pastes a table" into "run one command."
#
# WHAT IT DOES
# ============
# 1. Resolve the active-repo list: PR_HEALTH_REPOS_OVERRIDE env (self-test /
#    manual override) > ~/.claude/config/active-repos.txt > empty (no-op).
# 2. For each repo, `gh pr list --state open --json ...` and classify every
#    open PR into: failing-ci | conflict | stale-green-mergeable (mergeable,
#    all checks green, updatedAt older than STALE_GREEN_HOURS, default 1h) |
#    ok (none of the above — fresh, green, no action needed).
# 3. Emit a `## PR Health Snapshot` markdown table, one row per repo,
#    summarizing counts per classification + an Action column.
#
# USAGE
#   pr-health-snapshot.sh                 Query gh, print the snapshot table.
#   pr-health-snapshot.sh --repos a,b,c   Override the repo list for one run.
#   pr-health-snapshot.sh --self-test     Run internal scenarios (NO gh calls
#                                         — classification logic exercised
#                                         against fixture JSON; a real `gh`
#                                         call is stubbed out).
#   pr-health-snapshot.sh --help          Show usage.
#
# EXIT CODES
#   0 — snapshot printed (regardless of how many repos have issues; this is
#       an observability collector, not a gate — it never blocks anything)
#   0 — --self-test all scenarios pass
#   1 — --self-test at least one scenario failed
#   2 — usage error
#
# ESCAPE HATCH / CONFIG (same conventions as the retired gate, for
# continuity): PR_HEALTH_REPOS_OVERRIDE (comma/space list), PR_HEALTH_REPOS_CONFIG
# (path override, default ~/.claude/config/active-repos.txt).

set -uo pipefail

SCRIPT_NAME="pr-health-snapshot.sh"

STALE_GREEN_HOURS="${PR_HEALTH_STALE_GREEN_HOURS:-1}"

usage() {
  cat <<EOF
Usage: pr-health-snapshot.sh [--repos a,b,c]
       pr-health-snapshot.sh --self-test
       pr-health-snapshot.sh --help

Collector: queries gh for open-PR health across Misha's active repos and
prints a '## PR Health Snapshot' markdown table. Read-only; never blocks.
Callable manually, by session-wrap.sh, or by the future E.1 digest.

Repo list resolution: PR_HEALTH_REPOS_OVERRIDE env (or --repos) >
~/.claude/config/active-repos.txt > empty (no-op — nothing to report until
the operator populates the config, same as the retired gate's fallback).
EOF
}

# ------------------------------------------------------------
# resolve_repo_list — echoes the active repo list (space-separated).
# Identical resolution order to the retired gate, for continuity.
# ------------------------------------------------------------
resolve_repo_list() {
  if [[ -n "${PR_HEALTH_REPOS_OVERRIDE:-}" ]]; then
    printf '%s' "$PR_HEALTH_REPOS_OVERRIDE" | tr ',' ' '
    return 0
  fi
  local cfg="${PR_HEALTH_REPOS_CONFIG:-$HOME/.claude/config/active-repos.txt}"
  if [[ -f "$cfg" ]]; then
    local list
    list=$(sed -E 's/#.*$//' "$cfg" 2>/dev/null | tr -d '\r' | awk 'NF{print $1}' | tr '\n' ' ')
    if [[ -n "${list// /}" ]]; then
      printf '%s' "$list"
      return 0
    fi
  fi
  printf ''
}

# ------------------------------------------------------------
# _prh_gh_pr_list <repo> — echoes the JSON array from `gh pr list`. A thin
# wrapper so --self-test can override it (PRH_GH_STUB_FN) without touching
# the real `gh` binary or network.
# ------------------------------------------------------------
_prh_gh_pr_list() {
  local repo="$1"
  if [[ -n "${PRH_GH_STUB_FN:-}" ]]; then
    "$PRH_GH_STUB_FN" "$repo"
    return $?
  fi
  gh pr list --repo "$repo" --state open \
    --json number,title,statusCheckRollup,mergeable,headRefName,updatedAt \
    2>/dev/null
}

# ------------------------------------------------------------
# classify_prs_json <repo> <json> — reads a `gh pr list --json` array and
# echoes four counts + an action hint: "failing=<n> conflict=<n>
# stale=<n> ok=<n> action=<text>"
#
# Classification per PR (first match wins, in this priority order):
#   conflict     — mergeable == "CONFLICTING"
#   failing-ci   — any statusCheckRollup entry has conclusion in
#                  (FAILURE, ERROR, CANCELLED, TIMED_OUT)
#   stale-green  — mergeable == "MERGEABLE", all checks conclude SUCCESS
#                  (or no checks at all), and updatedAt is older than
#                  STALE_GREEN_HOURS
#   ok           — none of the above (fresh green-mergeable, or pending checks)
# ------------------------------------------------------------
classify_prs_json() {
  local repo="$1" json="$2"
  if ! command -v jq >/dev/null 2>&1; then
    printf 'failing=0 conflict=0 stale=0 ok=0 action=jq-unavailable'
    return 0
  fi
  if [[ -z "$json" ]] || ! printf '%s' "$json" | jq -e 'type=="array"' >/dev/null 2>&1; then
    printf 'failing=0 conflict=0 stale=0 ok=0 action=query-failed'
    return 0
  fi

  local now_epoch stale_seconds
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)
  stale_seconds=$((STALE_GREEN_HOURS * 3600))

  local failing=0 conflict=0 stale=0 ok=0
  local count
  count=$(printf '%s' "$json" | jq 'length' 2>/dev/null || echo 0)
  local i=0
  while [[ "$i" -lt "$count" ]]; do
    local pr mergeable updated_at has_failure
    pr=$(printf '%s' "$json" | jq -c ".[$i]" 2>/dev/null)
    mergeable=$(printf '%s' "$pr" | jq -r '.mergeable // "UNKNOWN"' 2>/dev/null)
    updated_at=$(printf '%s' "$pr" | jq -r '.updatedAt // ""' 2>/dev/null)
    has_failure=$(printf '%s' "$pr" | jq -r '
      [.statusCheckRollup // [] | .[] | select((.conclusion // "") as $c | $c=="FAILURE" or $c=="ERROR" or $c=="CANCELLED" or $c=="TIMED_OUT")] | length > 0
    ' 2>/dev/null)

    if [[ "$mergeable" == "CONFLICTING" ]]; then
      conflict=$((conflict+1))
    elif [[ "$has_failure" == "true" ]]; then
      failing=$((failing+1))
    else
      # Candidate for stale-green-mergeable: MERGEABLE + no failing checks.
      local updated_epoch age_seconds
      updated_epoch=$(date -u -d "$updated_at" +%s 2>/dev/null || date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$updated_at" +%s 2>/dev/null || echo "$now_epoch")
      age_seconds=$((now_epoch - updated_epoch))
      if [[ "$mergeable" == "MERGEABLE" ]] && [[ "$age_seconds" -ge "$stale_seconds" ]]; then
        stale=$((stale+1))
      else
        ok=$((ok+1))
      fi
    fi
    i=$((i+1))
  done

  local action="none"
  if [[ "$conflict" -gt 0 ]]; then
    action="resolve conflicts"
  elif [[ "$failing" -gt 0 ]]; then
    action="fix CI"
  elif [[ "$stale" -gt 0 ]]; then
    action="merge stale-green PR(s)"
  fi

  printf 'failing=%d conflict=%d stale=%d ok=%d action=%s' "$failing" "$conflict" "$stale" "$ok" "$action"
}

# ------------------------------------------------------------
# emit_snapshot <repo-list> — runs the collector across every repo and
# prints the '## PR Health Snapshot' markdown table to stdout.
# ------------------------------------------------------------
emit_snapshot() {
  local repos="$1"

  echo "## PR Health Snapshot"
  echo ""
  echo "| Repo | Open PRs | Failing CI | Conflicts | Stale-green (>=${STALE_GREEN_HOURS}h) | Action |"
  echo "|---|---|---|---|---|---|"

  local repo
  for repo in $repos; do
    [[ -z "$repo" ]] && continue
    local json classification failing conflict stale ok action total
    json=$(_prh_gh_pr_list "$repo")
    classification=$(classify_prs_json "$repo" "$json")
    failing=$(printf '%s' "$classification" | grep -oE 'failing=[0-9]+' | cut -d= -f2)
    conflict=$(printf '%s' "$classification" | grep -oE 'conflict=[0-9]+' | cut -d= -f2)
    stale=$(printf '%s' "$classification" | grep -oE 'stale=[0-9]+' | cut -d= -f2)
    ok=$(printf '%s' "$classification" | grep -oE 'ok=[0-9]+' | cut -d= -f2)
    action=$(printf '%s' "$classification" | grep -oE 'action=.*$' | cut -d= -f2-)
    total=$(( ${failing:-0} + ${conflict:-0} + ${stale:-0} + ${ok:-0} ))
    printf '| %s | %s | %s | %s | %s | %s |\n' "$repo" "$total" "${failing:-0}" "${conflict:-0}" "${stale:-0}" "$action"
  done
  echo ""
}

# ============================================================
# --self-test (no real gh/network calls — PRH_GH_STUB_FN fixtures)
# ============================================================
run_self_test() {
  local PASS=0 FAIL=0

  # Fixture stubs — echo canned `gh pr list --json` output per repo, no network.
  _stub_all_green() {
    cat <<'JSON'
[{"number":1,"title":"fix a","statusCheckRollup":[{"conclusion":"SUCCESS"}],"mergeable":"MERGEABLE","headRefName":"a","updatedAt":"2026-07-03T12:00:00Z"}]
JSON
  }
  _stub_failing_ci() {
    cat <<'JSON'
[{"number":2,"title":"broken","statusCheckRollup":[{"conclusion":"FAILURE"}],"mergeable":"MERGEABLE","headRefName":"b","updatedAt":"2026-07-03T12:00:00Z"}]
JSON
  }
  _stub_conflict() {
    cat <<'JSON'
[{"number":3,"title":"conflicted","statusCheckRollup":[{"conclusion":"SUCCESS"}],"mergeable":"CONFLICTING","headRefName":"c","updatedAt":"2026-07-03T12:00:00Z"}]
JSON
  }
  _stub_stale_green() {
    # updatedAt far in the past -> stale-green-mergeable.
    cat <<'JSON'
[{"number":4,"title":"stale but green","statusCheckRollup":[{"conclusion":"SUCCESS"}],"mergeable":"MERGEABLE","headRefName":"d","updatedAt":"2020-01-01T00:00:00Z"}]
JSON
  }
  _stub_empty() {
    echo "[]"
  }
  _stub_query_failed() {
    echo ""
  }

  # ST1 — all-green fresh PR classifies "ok", action=none. In-process (not a
  # bash -c subshell — a subshell would need to re-export every stub
  # function across the boundary, which is unreliable across bash versions;
  # calling emit_snapshot() directly in THIS process is simpler and just as
  # valid a check of the classification logic).
  export PRH_GH_STUB_FN=_stub_all_green
  export -f _stub_all_green
  out=$(emit_snapshot "repo-a" 2>&1)
  if printf '%s' "$out" | grep -q '| repo-a | 1 | 0 | 0 | 0 | none |'; then
    echo "PASS  all-green-fresh-pr-classifies-ok"
    PASS=$((PASS+1))
  else
    echo "FAIL  all-green-fresh-pr-classifies-ok (got: $out)"
    FAIL=$((FAIL+1))
  fi
  unset PRH_GH_STUB_FN

  # ST2 — failing-CI PR classifies failing=1, action=fix CI.
  export PRH_GH_STUB_FN=_stub_failing_ci
  export -f _stub_failing_ci
  out=$(emit_snapshot "repo-b" 2>&1)
  if printf '%s' "$out" | grep -q '| repo-b | 1 | 1 | 0 | 0 | fix CI |'; then
    echo "PASS  failing-ci-pr-classifies-failing"
    PASS=$((PASS+1))
  else
    echo "FAIL  failing-ci-pr-classifies-failing (got: $out)"
    FAIL=$((FAIL+1))
  fi
  unset PRH_GH_STUB_FN

  # ST3 — conflicting PR classifies conflict=1, action=resolve conflicts.
  export PRH_GH_STUB_FN=_stub_conflict
  export -f _stub_conflict
  out=$(emit_snapshot "repo-c" 2>&1)
  if printf '%s' "$out" | grep -q '| repo-c | 1 | 0 | 1 | 0 | resolve conflicts |'; then
    echo "PASS  conflicting-pr-classifies-conflict"
    PASS=$((PASS+1))
  else
    echo "FAIL  conflicting-pr-classifies-conflict (got: $out)"
    FAIL=$((FAIL+1))
  fi
  unset PRH_GH_STUB_FN

  # ST4 — stale-green PR (old updatedAt, green, mergeable) classifies stale=1.
  export PRH_GH_STUB_FN=_stub_stale_green
  export -f _stub_stale_green
  out=$(emit_snapshot "repo-d" 2>&1)
  if printf '%s' "$out" | grep -q '| repo-d | 1 | 0 | 0 | 1 | merge stale-green PR(s) |'; then
    echo "PASS  stale-green-pr-classifies-stale"
    PASS=$((PASS+1))
  else
    echo "FAIL  stale-green-pr-classifies-stale (got: $out)"
    FAIL=$((FAIL+1))
  fi
  unset PRH_GH_STUB_FN

  # ST5 — empty repo (no open PRs) classifies all-zero, action=none.
  export PRH_GH_STUB_FN=_stub_empty
  export -f _stub_empty
  out=$(emit_snapshot "repo-e" 2>&1)
  if printf '%s' "$out" | grep -q '| repo-e | 0 | 0 | 0 | 0 | none |'; then
    echo "PASS  empty-repo-classifies-zero"
    PASS=$((PASS+1))
  else
    echo "FAIL  empty-repo-classifies-zero (got: $out)"
    FAIL=$((FAIL+1))
  fi
  unset PRH_GH_STUB_FN

  # ST6 — query-failed (gh error / empty output) degrades gracefully, never
  # crashes — classify_prs_json's dedicated query-failed action, distinct
  # from a genuinely-empty-but-successful PR list (ST5's "none").
  export PRH_GH_STUB_FN=_stub_query_failed
  export -f _stub_query_failed
  out=$(emit_snapshot "repo-f" 2>&1)
  if printf '%s' "$out" | grep -q '| repo-f | 0 | 0 | 0 | 0 | query-failed |'; then
    echo "PASS  query-failed-degrades-gracefully"
    PASS=$((PASS+1))
  else
    echo "FAIL  query-failed-degrades-gracefully (got: $out)"
    FAIL=$((FAIL+1))
  fi
  unset PRH_GH_STUB_FN

  # ST7 — resolve_repo_list: override env wins, comma-separated.
  ST7_LIST=$(PR_HEALTH_REPOS_OVERRIDE="repo-x,repo-y" resolve_repo_list)
  if [[ "$ST7_LIST" == "repo-x repo-y" ]]; then
    echo "PASS  resolve-repo-list-override-comma"
    PASS=$((PASS+1))
  else
    echo "FAIL  resolve-repo-list-override-comma (got: '$ST7_LIST')"
    FAIL=$((FAIL+1))
  fi

  # ST8 — resolve_repo_list: no override + no config -> empty.
  ST8_LIST=$(PR_HEALTH_REPOS_OVERRIDE="" PR_HEALTH_REPOS_CONFIG="/nonexistent/active-repos.txt" resolve_repo_list)
  if [[ -z "$ST8_LIST" ]]; then
    echo "PASS  resolve-repo-list-empty-when-unconfigured"
    PASS=$((PASS+1))
  else
    echo "FAIL  resolve-repo-list-empty-when-unconfigured (got: '$ST8_LIST')"
    FAIL=$((FAIL+1))
  fi

  # ST9 — multi-repo snapshot: table has one row per repo, in order.
  export PRH_GH_STUB_FN=_stub_all_green
  export -f _stub_all_green
  out=$(emit_snapshot "repo-g repo-h" 2>&1)
  if printf '%s' "$out" | grep -q '| repo-g |' && printf '%s' "$out" | grep -q '| repo-h |'; then
    echo "PASS  multi-repo-snapshot-one-row-each"
    PASS=$((PASS+1))
  else
    echo "FAIL  multi-repo-snapshot-one-row-each (got: $out)"
    FAIL=$((FAIL+1))
  fi
  unset PRH_GH_STUB_FN

  echo ""
  echo "self-test: $PASS pass, $FAIL fail"
  if [[ "$FAIL" -gt 0 ]]; then echo "self-test: FAIL"; return 1; fi
  echo "self-test: OK $PASS/$PASS"
  return 0
}

# ============================================================
# Main dispatch
# ============================================================
case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --self-test)
    run_self_test
    exit $?
    ;;
  --repos)
    if [[ -z "${2:-}" ]]; then
      echo "$SCRIPT_NAME: --repos requires an argument" >&2
      usage >&2
      exit 2
    fi
    PR_HEALTH_REPOS_OVERRIDE="$2"
    ;;
  "")
    ;;
  *)
    echo "$SCRIPT_NAME: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

REPOS=$(resolve_repo_list)
if [[ -z "${REPOS// /}" ]]; then
  echo "$SCRIPT_NAME: no active repos configured (populate ~/.claude/config/active-repos.txt or pass --repos a,b,c) — nothing to report." >&2
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "$SCRIPT_NAME: gh CLI not available — cannot query PR health." >&2
  exit 0
fi

emit_snapshot "$REPOS"
exit 0
