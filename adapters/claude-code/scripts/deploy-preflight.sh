#!/usr/bin/env bash
# deploy-preflight.sh
#
# Fail-CLOSED pre-deploy checker. Run from (or point at) the checkout a
# production deploy will ship from, BEFORE invoking the deploy tool.
#
# Context (docs/discoveries/2026-06-18-engine-deploy-stale-checkout-silent-staleness.md):
# a production deploy shipped STALE engine code because `git fetch` failed
# silently (no credential helper in the non-interactive env), `origin/master`
# resolved to a stale cached ref, and the deploy tool confidently deployed
# the behind-HEAD working tree with a green "Successfully deployed" message.
# The deploy tool deploys the working tree; it has no idea the tree is behind.
# This script makes that deploy impossible FOR ANY DEPLOY THAT RUNS IT —
# invocation is doctrine-mandated (doctrine/git.md), not hook-enforced:
# every check FAILS CLOSED — any doubt aborts the deploy.
#
# Checks (all must pass, in order):
#   1. FETCH    — `git fetch origin` with GIT_TERMINAL_PROMPT=0 (and the
#                 `gh auth git-credential` helper when gh is on PATH). A
#                 nonzero fetch ABORTS: a credential failure must never
#                 degrade into a proceed-on-stale-ref.
#   2. CLEAN    — the working tree has no uncommitted changes (staged,
#                 unstaged, or untracked). The deploy tool ships the tree,
#                 not HEAD, so a dirty tree is an unverifiable deploy.
#   3. AT-TIP   — HEAD == <master-ref> (default origin/master) exactly.
#                 Behind, ahead, or diverged all refuse.
#   4. ANCESTOR — every commit named as an argument is an ancestor of HEAD
#                 (`git merge-base --is-ancestor`): the changes the deploy
#                 exists to ship are provably in what will be deployed.
#
# Usage:
#   deploy-preflight.sh [--repo <path>] [--master-ref <ref>] [<commit>...]
#   deploy-preflight.sh --self-test
#
#   <commit>...   the intended commits/PR heads this deploy must contain
#   --repo        checkout to verify (default: cwd's repo)
#   --master-ref  ref HEAD must equal (default: origin/master)
#
# Exit codes:
#   0 — ALL checks passed; deploying this tree ships true <master-ref>
#   1 — fetch failed (credentials / network / remote) — DO NOT DEPLOY
#   2 — dirty working tree — DO NOT DEPLOY
#   3 — HEAD != <master-ref> (stale/diverged checkout) — DO NOT DEPLOY
#   4 — a named commit is not an ancestor of HEAD — DO NOT DEPLOY
#   5 — usage / not a git repo / unresolvable ref or commit
#   6 — --self-test failure
set -u

SCRIPT_ABS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

REPO=""
MASTER_REF="origin/master"
COMMITS=()
RUN_SELF_TEST=0

die_usage() { echo "deploy-preflight.sh: $1" >&2; echo "see header for usage" >&2; exit 5; }
refuse()    { echo "deploy-preflight: FAIL — $2 — DO NOT DEPLOY" >&2; exit "$1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) shift; [ $# -gt 0 ] || die_usage "--repo needs a path"; REPO="$1" ;;
    --master-ref) shift; [ $# -gt 0 ] || die_usage "--master-ref needs a ref"; MASTER_REF="$1" ;;
    --self-test) RUN_SELF_TEST=1 ;;
    -h|--help) sed -n '2,48p' "$0"; exit 0 ;;
    -*) die_usage "unknown flag: $1" ;;
    *) COMMITS+=("$1") ;;
  esac
  shift
done

run_preflight() {
  local repo="$1" master_ref="$2"; shift 2
  local commits=("$@")

  git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1 \
    || die_usage "not a git repo: $repo"

  # 1. FETCH — fail closed. Never prompt; prefer the gh credential helper
  # (the 2026-06-18 incident was an implicit-HTTPS-prompt silent failure).
  local -a cred=()
  command -v gh >/dev/null 2>&1 && cred=(-c "credential.helper=!gh auth git-credential")
  if ! GIT_TERMINAL_PROMPT=0 git -C "$repo" "${cred[@]}" fetch origin; then
    refuse 1 "git fetch origin failed (credentials/network); origin/* refs may be STALE"
  fi
  echo "deploy-preflight: fetch origin OK"

  # 2. CLEAN — refuse any uncommitted state (the tree is what deploys).
  local dirt
  dirt=$(git -C "$repo" status --porcelain 2>/dev/null)
  if [ -n "$dirt" ]; then
    refuse 2 "working tree is dirty:
$dirt"
  fi
  echo "deploy-preflight: working tree clean"

  # 3. AT-TIP — HEAD must be exactly <master-ref>.
  local head_sha ref_sha
  head_sha=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || die_usage "cannot resolve HEAD in $repo"
  ref_sha=$(git -C "$repo" rev-parse --verify -q "${master_ref}^{commit}") \
    || die_usage "cannot resolve ref: $master_ref"
  if [ "$head_sha" != "$ref_sha" ]; then
    refuse 3 "HEAD ($head_sha) != $master_ref ($ref_sha) — checkout is stale or diverged; reset to $master_ref first"
  fi
  echo "deploy-preflight: HEAD == $master_ref ($head_sha)"

  # 4. ANCESTOR — every intended commit must be contained in HEAD.
  local c c_sha
  for c in ${commits[@]+"${commits[@]}"}; do
    c_sha=$(git -C "$repo" rev-parse --verify -q "${c}^{commit}") \
      || refuse 4 "intended commit does not resolve: $c"
    if ! git -C "$repo" merge-base --is-ancestor "$c_sha" "$head_sha"; then
      refuse 4 "intended commit $c is NOT an ancestor of HEAD — the deploy would not ship it"
    fi
    echo "deploy-preflight: intended commit $c is in HEAD"
  done

  echo "deploy-preflight: PASS — safe to deploy from $repo at $head_sha"
  return 0
}

# ---------------------------------------------------------------------------
# Self-test: sandboxed fixture repos (bare origin + clone). Asserts each
# failure class FAILS CLOSED with its distinct exit code, plus one green pass.
# ---------------------------------------------------------------------------
if [ "$RUN_SELF_TEST" = 1 ]; then
  T=$(mktemp -d)
  cleanup() { rm -rf "$T" 2>/dev/null || true; }
  trap cleanup EXIT
  fail() { echo "SELFTEST FAIL: $1" >&2; exit 6; }
  gitq() { git -c commit.gpgsign=false -c user.email=t@example.com -c user.name=t "$@"; }

  git init -q --bare "$T/origin.git"
  git clone -q "$T/origin.git" "$T/clone" 2>/dev/null
  git -C "$T/clone" config core.autocrlf false
  ( cd "$T/clone"
    echo v1 > f.txt; git add f.txt; gitq commit -qm c1
    echo v2 >> f.txt; git add f.txt; gitq commit -qm c2
    git push -q origin HEAD:master
    git branch -q side HEAD~1
    ( echo side > s.txt; git add s.txt; git checkout -q side; git add s.txt; gitq commit -qm side; git checkout -q - ) >/dev/null 2>&1
  )
  TIP=$(git -C "$T/clone" rev-parse HEAD)
  C1=$(git -C "$T/clone" rev-parse HEAD~1)
  SIDE=$(git -C "$T/clone" rev-parse side)

  # green pass: clean clone at origin/master tip, both real ancestors named
  OUT=$(bash "$SCRIPT_ABS" --repo "$T/clone" "$C1" "$TIP" 2>&1); rc=$?
  [ $rc -eq 0 ] || fail "green case exited $rc: $OUT"
  echo "$OUT" | grep -q "PASS — safe to deploy" || fail "green case missing PASS line: $OUT"

  # missing-ancestor: side-branch commit never merged -> exit 4
  OUT=$(bash "$SCRIPT_ABS" --repo "$T/clone" "$SIDE" 2>&1); rc=$?
  [ $rc -eq 4 ] || fail "missing-ancestor expected exit 4, got $rc: $OUT"

  # stale-HEAD: checkout behind origin/master -> exit 3
  git -C "$T/clone" reset -q --hard HEAD~1
  OUT=$(bash "$SCRIPT_ABS" --repo "$T/clone" 2>&1); rc=$?
  [ $rc -eq 3 ] || fail "stale-HEAD expected exit 3, got $rc: $OUT"
  git -C "$T/clone" reset -q --hard "$TIP"

  # dirty-tree: uncommitted change -> exit 2
  echo dirty >> "$T/clone/f.txt"
  OUT=$(bash "$SCRIPT_ABS" --repo "$T/clone" 2>&1); rc=$?
  [ $rc -eq 2 ] || fail "dirty-tree expected exit 2, got $rc: $OUT"
  git -C "$T/clone" checkout -q -- f.txt

  # fetch-fail: remote points at a nonexistent path -> exit 1 (fail closed,
  # never proceed on the stale cached origin/* refs)
  git -C "$T/clone" remote set-url origin "$T/does-not-exist.git"
  OUT=$(bash "$SCRIPT_ABS" --repo "$T/clone" 2>&1); rc=$?
  [ $rc -eq 1 ] || fail "fetch-fail expected exit 1, got $rc: $OUT"
  git -C "$T/clone" remote set-url origin "$T/origin.git"

  echo "SELFTEST PASS (green deploy passes; stale-HEAD, missing-ancestor, dirty-tree, fetch-fail all FAIL CLOSED with distinct exit codes)"
  exit 0
fi

if [ -z "$REPO" ]; then
  REPO=$(git rev-parse --show-toplevel 2>/dev/null) || die_usage "not in a git repo and no --repo given"
fi
run_preflight "$REPO" "$MASTER_REF" ${COMMITS[@]+"${COMMITS[@]}"}
