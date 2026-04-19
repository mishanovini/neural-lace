#!/bin/bash
# sync.sh — Push this repo to multiple GitHub remotes in one command
#
# Usage: ./sync.sh [branch]
#   defaults to current branch
#
# This script pushes to both `personal` and `work` remotes if they exist.
# Set CLAUDE_CONFIG_PERSONAL_USER and CLAUDE_CONFIG_WORK_USER env vars to
# force specific credential usernames per remote (useful when your local
# git has a different default user that can't push to both accounts).

set -e

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

PERSONAL_USER="${CLAUDE_CONFIG_PERSONAL_USER:-}"
WORK_USER="${CLAUDE_CONFIG_WORK_USER:-}"

echo ""
echo "Syncing branch: $BRANCH"
echo ""

# Determine which remotes exist
HAS_PERSONAL=$(git remote | grep -c "^personal$" || true)
HAS_WORK=$(git remote | grep -c "^work$" || true)
HAS_PT=$(git remote | grep -c "^pt$" || true)
HAS_ORIGIN=$(git remote | grep -c "^origin$" || true)

# Fallback: if only origin exists, push to it
if [ "$HAS_ORIGIN" -eq 1 ] && [ "$HAS_PERSONAL" -eq 0 ] && [ "$HAS_WORK" -eq 0 ] && [ "$HAS_PT" -eq 0 ]; then
  echo "Only 'origin' remote configured. Pushing to origin..."
  git push origin "$BRANCH"
  echo ""
  echo "TIP: To sync to multiple GitHub accounts, add named remotes:"
  echo "  git remote add personal https://github.com/<your-personal-user>/neural-lace.git"
  echo "  git remote add work     https://github.com/<your-work-org>/neural-lace.git"
  exit 0
fi

# Push to personal remote
if [ "$HAS_PERSONAL" -eq 1 ]; then
  echo "> Pushing to personal remote..."
  if [ -n "$PERSONAL_USER" ]; then
    git -c credential.https://github.com.username="$PERSONAL_USER" push personal "$BRANCH"
  else
    git push personal "$BRANCH"
  fi
  echo ""
fi

# Push to work remote (named 'work' or 'pt' for legacy compatibility)
for WORK_REMOTE in work pt; do
  if [ "$(git remote | grep -c "^${WORK_REMOTE}$" || true)" -eq 1 ]; then
    echo "> Pushing to $WORK_REMOTE remote..."
    if [ -n "$WORK_USER" ]; then
      git -c credential.https://github.com.username="$WORK_USER" push "$WORK_REMOTE" "$BRANCH"
    else
      git push "$WORK_REMOTE" "$BRANCH"
    fi
    echo ""
  fi
done

echo "Sync complete."
echo ""
