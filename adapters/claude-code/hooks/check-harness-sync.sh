#!/bin/bash
# check-harness-sync.sh
#
# Called by the PreToolUse hook when a git commit is detected.
# Detects drift between ~/.claude/ and the neural-lace repo.
#
# BEHAVIOR:
# - If ~/.claude/ files have been modified (drift from neural-lace), AUTO-SYNCS
#   the changes back to the neural-lace repo, commits, and pushes to both remotes.
# - If new files exist in ~/.claude/ but not in neural-lace, copies them in.
# - Skips when committing inside neural-lace itself (avoids loops).
# - Skips templates/ (deployed from patterns/templates/, not adapters/).

LIVE="$HOME/.claude"
REPO="$HOME/claude-projects/neural-lace/adapters/claude-code"
NL_ROOT="$HOME/claude-projects/neural-lace"

# Only run if the neural-lace repo exists (-e accepts both .git directory and worktree .git file)
[ -e "$NL_ROOT/.git" ] || exit 0

# Skip if we're committing inside neural-lace itself — avoids infinite loop
CURRENT_REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if echo "$CURRENT_REPO" | grep -q "neural-lace"; then
  exit 0
fi

# ============================================================
# Detect drift
# ============================================================

DRIFT=0
DRIFT_FILES=""
CHANGED_FILES=()

for dir in agents rules hooks scripts; do
  [ -d "$LIVE/$dir" ] && [ -d "$REPO/$dir" ] || continue
  for f in "$LIVE/$dir"/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")

    if [ ! -f "$REPO/$dir/$base" ]; then
      DRIFT=$((DRIFT + 1))
      DRIFT_FILES="$DRIFT_FILES  NEW: $dir/$base\n"
      CHANGED_FILES+=("$dir/$base")
    elif ! diff -q "$f" "$REPO/$dir/$base" > /dev/null 2>&1; then
      DRIFT=$((DRIFT + 1))
      DRIFT_FILES="$DRIFT_FILES  CHANGED: $dir/$base\n"
      CHANGED_FILES+=("$dir/$base")
    fi
  done
done

# Also check CLAUDE.md
if [ -f "$LIVE/CLAUDE.md" ] && [ -f "$REPO/CLAUDE.md" ]; then
  if ! diff -q "$LIVE/CLAUDE.md" "$REPO/CLAUDE.md" > /dev/null 2>&1; then
    DRIFT=$((DRIFT + 1))
    DRIFT_FILES="$DRIFT_FILES  CHANGED: CLAUDE.md\n"
    CHANGED_FILES+=("CLAUDE.md")
  fi
fi

# Also check docs/ (lives at neural-lace/docs/, not adapter/docs/)
if [ -d "$LIVE/docs" ] && [ -d "$NL_ROOT/docs" ]; then
  for f in "$LIVE/docs"/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    if [ -f "$NL_ROOT/docs/$base" ] && ! diff -q "$f" "$NL_ROOT/docs/$base" > /dev/null 2>&1; then
      DRIFT=$((DRIFT + 1))
      DRIFT_FILES="$DRIFT_FILES  CHANGED: docs/$base (neural-lace/docs/)\n"
      # Handle docs separately since they live at root docs/, not adapter
    fi
  done
fi

# ============================================================
# Auto-sync if drift detected
# ============================================================

if [ $DRIFT -eq 0 ]; then
  exit 0
fi

echo "" >&2
echo "🔄 HARNESS DRIFT DETECTED — $DRIFT file(s) changed in ~/.claude/" >&2
echo -e "$DRIFT_FILES" >&2
echo "Auto-syncing changes back to neural-lace..." >&2

# Copy changed files back to neural-lace
for relpath in "${CHANGED_FILES[@]}"; do
  if [ "$relpath" = "CLAUDE.md" ]; then
    cp "$LIVE/CLAUDE.md" "$REPO/CLAUDE.md"
  else
    dir=$(dirname "$relpath")
    base=$(basename "$relpath")
    mkdir -p "$REPO/$dir"
    cp "$LIVE/$dir/$base" "$REPO/$dir/$base"
  fi
done

# Handle docs separately
for f in "$LIVE/docs"/*; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  if [ -f "$NL_ROOT/docs/$base" ] && ! diff -q "$f" "$NL_ROOT/docs/$base" > /dev/null 2>&1; then
    cp "$f" "$NL_ROOT/docs/$base"
  fi
done

# Commit and push in neural-lace
cd "$NL_ROOT"

# Stage changes
git add -A 2>/dev/null

# Only commit if there are staged changes
if ! git diff --cached --quiet 2>/dev/null; then
  # Build a concise commit message listing changed files
  FILE_LIST=$(echo -e "$DRIFT_FILES" | sed 's/^  /  - /' | head -10)

  git commit -m "$(cat <<INNEREOF
chore: auto-sync harness changes from ~/.claude/

Files synced back from live harness:
$FILE_LIST
Source: $(basename "$CURRENT_REPO") session
INNEREOF
)" 2>/dev/null

  echo "  ✓ Changes committed to neural-lace" >&2

  # Push to both remotes (silently, don't block the original commit)
  if [ -f "$NL_ROOT/sync.sh" ]; then
    bash "$NL_ROOT/sync.sh" 2>/dev/null | grep -E "(✓|✗)" >&2
  fi
else
  echo "  (no changes to commit after copy)" >&2
fi

cd "$CURRENT_REPO" 2>/dev/null
echo "" >&2
