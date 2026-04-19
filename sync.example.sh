#!/bin/bash
# sync.example.sh — Reference template for pushing to multiple git remotes
#
# This is an EXAMPLE. It is not invoked by the harness. Copy this to `sync.sh`
# in your local clone and customize for your remotes + accounts config.
#
# Prerequisites:
#   - ~/.claude/local/accounts.config.json exists (see examples/accounts.config.example.json)
#   - Each remote in this repo maps to exactly one account's gh_user
#   - gh CLI is installed and authenticated for every account referenced
#
# Usage:
#   ./sync.sh [branch]    # defaults to current branch
#
# The reference flow:
#   1. For each git remote, decide which gh_user should push it
#   2. Switch gh auth to that user
#   3. Push the branch
#   4. Restore gh auth to the account matching $PWD (per SessionStart convention)

set -e

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

echo ""
echo "Neural Lace — Syncing branch '$BRANCH' to configured remotes"
echo ""

# --- Source the local-config helper ---
REPO_ROOT="$(git rev-parse --show-toplevel)"
HELPER="$REPO_ROOT/adapters/claude-code/scripts/read-local-config.sh"
if [ ! -f "$HELPER" ]; then
  echo "ERROR: helper not found at $HELPER" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$HELPER"

# --- Define your remote→gh_user map ---
# Customize this block. Keys are remote names (from `git remote`), values are
# the gh_user that should be authenticated for pushes to that remote.
declare -A REMOTE_USER_MAP=(
  # ["origin"]="your-personal-gh-user"
  # ["work"]="your-work-gh-user"
)

if [ ${#REMOTE_USER_MAP[@]} -eq 0 ]; then
  echo "No remotes configured in REMOTE_USER_MAP. Edit this script and list"
  echo "each remote → gh_user mapping, then re-run."
  echo ""
  echo "Your current git remotes:"
  git remote -v | awk '{print "  " $1 " → " $2}'
  exit 0
fi

FAILED=0

push_to_remote() {
  local remote="$1"
  local gh_user="$2"

  if ! git remote | grep -q "^${remote}$"; then
    echo "> Skipping $remote (not configured as a git remote)"
    return 0
  fi

  echo "> Pushing to $remote (as $gh_user)..."

  if [ -n "$gh_user" ]; then
    gh auth switch -u "$gh_user" 2>/dev/null || true
    gh auth setup-git 2>/dev/null || true
  fi

  if git push "$remote" "$BRANCH" 2>&1; then
    echo "  OK: $remote synced"
  else
    echo "  FAIL: $remote push failed"
    FAILED=1
  fi
  echo ""
}

for remote in "${!REMOTE_USER_MAP[@]}"; do
  push_to_remote "$remote" "${REMOTE_USER_MAP[$remote]}"
done

# --- Restore gh auth to the account matching $PWD ---
if match=$(nl_accounts_match_dir "$PWD" 2>/dev/null) && [ -n "$match" ]; then
  restore_user=$(echo "$match" | awk '{print $2}')
  if [ -n "$restore_user" ]; then
    gh auth switch -u "$restore_user" 2>/dev/null || true
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  echo "All remotes synced successfully."
else
  echo "WARNING: One or more remotes failed to sync."
  exit 1
fi
echo ""
